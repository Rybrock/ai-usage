import Foundation

/// Shape of `GET https://api.anthropic.com/api/oauth/usage`.
/// Only the fields we render are modelled; the endpoint returns several
/// additional per-model windows that are null on non-Max plans.
struct UsageResponse: Decodable {
    let limits: [LimitEntry]
    let spend: Spend?
}

struct LimitEntry: Decodable, Identifiable {
    let kind: String
    let group: String
    let percent: Double
    let severity: String
    let resetsAt: Date?
    let isActive: Bool

    var id: String { kind }

    /// The endpoint returns machine kinds; these are the labels the
    /// Claude settings pane shows for them.
    var title: String {
        switch kind {
        case "session":       return "Current session"
        case "weekly_all":    return "All models"
        case "weekly_opus":   return "Opus"
        case "weekly_sonnet": return "Sonnet"
        case "weekly_cowork": return "Cowork"
        default:
            let cleaned = kind.replacingOccurrences(of: "weekly_", with: "")
                              .replacingOccurrences(of: "_", with: " ")
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
    }
}

struct Spend: Decodable {
    let used: Money
    let limit: Money?
    let percent: Double
    let severity: String
    let enabled: Bool
    let disabledReason: String?
}

struct Money: Decodable {
    let amountMinor: Int
    let currency: String
    let exponent: Int

    var amount: Double { Double(amountMinor) / pow(10, Double(exponent)) }

    var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = exponent
        f.minimumFractionDigits = exponent
        return f.string(from: amount as NSNumber) ?? String(format: "%.2f", amount)
    }
}

/// Shape of `GET /api/oauth/profile` — used only for the plan badge.
struct ProfileResponse: Decodable {
    struct Organization: Decodable { let organizationType: String? }
    struct Account: Decodable {
        let hasClaudeMax: Bool?
        let hasClaudePro: Bool?
    }
    let account: Account?
    let organization: Organization?

    var planName: String {
        if account?.hasClaudeMax == true { return "Max" }
        if account?.hasClaudePro == true { return "Pro" }
        switch organization?.organizationType {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        default:           return ""
        }
    }
}

/// Everything the popover needs for one render.
struct UsageSnapshot {
    var limits: [LimitEntry]
    var spend: Spend?
    var plan: String
    var fetchedAt: Date

    var sessionPercent: Double? {
        limits.first(where: { $0.kind == "session" })?.percent
    }

    /// Worst-case percentage across every window, for menu-bar colouring.
    var peakPercent: Double {
        limits.map(\.percent).max() ?? 0
    }
}
