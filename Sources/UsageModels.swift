import Foundation

/// Shape of `GET https://api.anthropic.com/api/oauth/usage`.
/// Only the fields we render are modelled; the endpoint returns several
/// additional per-model windows that are null on non-Max plans.
struct UsageResponse: Decodable {
    let limits: [LimitEntry]
    let spend: Spend?
    let extraUsage: ExtraUsage?
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
    /// Effective spendability, *not* the user's setting — this goes false when
    /// the monthly cap is reached even though credits are still switched on.
    /// Read `UsageSnapshot.credits` instead of branching on this directly.
    let enabled: Bool
    let disabledReason: String?
    /// Markdown blurb with one inline link, e.g. "Usage credits cover you when
    /// you hit your plan limits. [Learn more](https://…)".
    let disclaimer: String?
    let canPurchaseCredits: Bool?

    /// The endpoint doesn't expose a credits *settings* URL, and the claude.ai
    /// settings paths aren't stable enough to hardcode — so the one credits
    /// destination we can trust is the link the API puts in `disclaimer`.
    var disclaimerLink: SpendLink? {
        guard let disclaimer,
              let open = disclaimer.range(of: "]("),
              let close = disclaimer.range(of: ")", range: open.upperBound..<disclaimer.endIndex),
              let label = disclaimer.range(of: "[", options: .backwards,
                                           range: disclaimer.startIndex..<open.lowerBound)
        else { return nil }

        // Only ever hand AppKit an https URL — this string comes off the wire.
        guard let url = URL(string: String(disclaimer[open.upperBound..<close.lowerBound])),
              url.scheme == "https"
        else { return nil }

        // An empty label would render as an invisible, unclickable link.
        let text = disclaimer[label.upperBound..<open.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return SpendLink(label: text, url: url)
    }
}

/// A markdown link lifted out of an API-provided blurb.
struct SpendLink {
    let label: String
    let url: URL
}

/// The same credits figures in the endpoint's older shape. Modelled only for
/// `user_disabled`, which is the actual on/off toggle from the Claude settings
/// pane and has no equivalent in `spend`.
struct ExtraUsage: Decodable {
    let userDisabled: Bool?
    let spendLimitReached: Bool?
}

/// What the popover should say about usage credits.
enum CreditsState {
    /// On and spendable — no explanatory line needed.
    case on
    /// Still switched on, but the monthly cap is used up.
    case capReached
    /// The user has switched credits off.
    case off
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
    var extraUsage: ExtraUsage?
    var plan: String
    var fetchedAt: Date

    /// Hitting the monthly cap clears `spend.enabled` while the toggle stays
    /// on, so "off" has to come from `user_disabled` to match what the Claude
    /// settings pane shows.
    var credits: CreditsState {
        if extraUsage?.userDisabled == true { return .off }
        if spend?.enabled == true { return .on }
        if spend?.disabledReason == "out_of_credits" || extraUsage?.spendLimitReached == true {
            return .capReached
        }
        return .off
    }

    var sessionPercent: Double? {
        limits.first(where: { $0.kind == "session" })?.percent
    }

    /// Worst-case percentage across every window, for menu-bar colouring.
    var peakPercent: Double {
        limits.map(\.percent).max() ?? 0
    }
}
