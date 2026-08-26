import Foundation

enum UsageError: LocalizedError {
    case noCredentials(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials(let detail):
            return "Couldn't read your Claude Code login from the Keychain.\n\(detail)"
        case .unauthorized:
            return "Your Claude Code session has expired. Run `claude` in a terminal to sign in again."
        case .rateLimited(let retryAfter):
            let minutes = max(1, Int((retryAfter / 60).rounded(.up)))
            return "Rate limited by Anthropic — showing the last known figures. Retrying in about \(minutes) min."
        case .http(let code):
            return "Anthropic API returned HTTP \(code)."
        case .decoding(let detail):
            return "Unexpected response from the usage API.\n\(detail)"
        }
    }

    /// How long the caller must wait before trying again.
    var retryDelay: TimeInterval? {
        if case .rateLimited(let after) = self { return after }
        return nil
    }
}

enum UsageService {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let oauthBeta = "oauth-2025-04-20"

    /// Claude Code stores its OAuth tokens in the login Keychain and refreshes
    /// them itself, so we re-read the item on every poll rather than caching.
    /// Shelling out to `/usr/bin/security` reuses the access path the user has
    /// already authorised, instead of prompting separately for this app.
    private static func accessToken() throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        do { try proc.run() } catch {
            throw UsageError.noCredentials(error.localizedDescription)
        }

        // Read before waiting so a full pipe buffer can't deadlock us.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let detail = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "security exited \(proc.terminationStatus)"
            throw UsageError.noCredentials(detail.isEmpty ? "Is Claude Code signed in?" : detail)
        }

        struct Credentials: Decodable {
            struct OAuth: Decodable { let accessToken: String }
            let claudeAiOauth: OAuth
        }

        do {
            return try JSONDecoder().decode(Credentials.self, from: outData).claudeAiOauth.accessToken
        } catch {
            throw UsageError.noCredentials("Keychain item wasn't in the expected format.")
        }
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(),
                                                   debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }

    private static func request(_ url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(oauthBeta, forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeUsageBar/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        return req
    }

    private static func get<T: Decodable>(_ url: URL, token: String, as: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request(url, token: token))

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401, 403:
                throw UsageError.unauthorized
            case 429:
                let header = http.value(forHTTPHeaderField: "retry-after")
                throw UsageError.rateLimited(retryAfter: Double(header ?? "") ?? 300)
            default:
                throw UsageError.http(http.statusCode)
            }
        }

        do {
            return try decoder().decode(T.self, from: data)
        } catch {
            throw UsageError.decoding(String(describing: error).prefix(200).description)
        }
    }

    /// The plan never changes mid-session, and these endpoints are rate limited
    /// hard (HTTP 429 with retry-after ~250s), so fetch it once and reuse it.
    private static var cachedPlan: String?

    static func fetch() async throws -> UsageSnapshot {
        let token = try accessToken()
        let usage = try await get(usageURL, token: token, as: UsageResponse.self)

        if cachedPlan == nil {
            // The plan badge is cosmetic — never fail the whole refresh over it.
            cachedPlan = (try? await get(profileURL, token: token, as: ProfileResponse.self))?.planName
        }

        return UsageSnapshot(limits: usage.limits,
                             spend: usage.spend,
                             extraUsage: usage.extraUsage,
                             plan: cachedPlan ?? "",
                             fetchedAt: Date())
    }
}
