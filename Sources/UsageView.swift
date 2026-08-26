import SwiftUI

// MARK: - Formatting helpers

enum Format {
    static func resets(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "Resetting now" }

        if interval < 86_400 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "Resets in \(hours) hr \(minutes) min" : "Resets in \(minutes) min"
        }

        let f = DateFormatter()
        f.dateFormat = interval < 7 * 86_400 ? "EEE h:mm a" : "MMM d"
        return "Resets \(f.string(from: date))"
    }

    /// The usage endpoint doesn't carry a reset date for credits — they roll
    /// over on the 1st of the month, which is what the Claude settings pane shows.
    static func creditsReset() -> String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        guard let next = cal.date(byAdding: .month, value: 1, to: start) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Resets \(f.string(from: next))"
    }

    static func lastUpdated(_ date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(elapsed)s ago" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        return "\(elapsed / 3600)h ago"
    }
}

func severityColor(_ severity: String, percent: Double) -> Color {
    switch severity {
    case "critical": return .red
    case "warning":  return .orange
    default:         return percent >= 90 ? .red : (percent >= 75 ? .orange : .accentColor)
    }
}

// MARK: - Pieces

struct MeterBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, percent / 100)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

struct UsageRow: View {
    let title: String
    let subtitle: String
    let percent: Double
    let color: Color
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, alignment: .leading)

            MeterBar(percent: percent, color: color)

            Text(trailing ?? "\(Int(percent.rounded()))% used")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .padding(.top, 6)
    }
}

// MARK: - Popover

struct UsageView: View {
    @ObservedObject var model: UsageModel
    var onQuit: () -> Void
    var onOpenSettings: () -> Void
    var onOpenClaude: () -> Void

    private var sessionLimits: [LimitEntry] {
        model.snapshot?.limits.filter { $0.group == "session" } ?? []
    }
    private var weeklyLimits: [LimitEntry] {
        model.snapshot?.limits.filter { $0.group != "session" } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let error = model.errorMessage {
                errorBanner(error)
            }

            if model.snapshot == nil && model.errorMessage == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading usage…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            }

            if let snapshot = model.snapshot {
                ForEach(sessionLimits) { limit in
                    UsageRow(title: limit.title,
                             subtitle: Format.resets(limit.resetsAt),
                             percent: limit.percent,
                             color: severityColor(limit.severity, percent: limit.percent))
                }

                if !weeklyLimits.isEmpty {
                    Divider().padding(.vertical, 2)
                    SectionLabel(text: "Weekly limits")
                    ForEach(weeklyLimits) { limit in
                        UsageRow(title: limit.title,
                                 subtitle: Format.resets(limit.resetsAt),
                                 percent: limit.percent,
                                 color: severityColor(limit.severity, percent: limit.percent))
                    }
                }

                if let spend = snapshot.spend {
                    Divider().padding(.vertical, 2)
                    SectionLabel(text: "Usage credits")
                    UsageRow(title: spend.used.formatted + " spent",
                             subtitle: Format.creditsReset(),
                             percent: spend.percent,
                             color: severityColor(spend.severity, percent: spend.percent))
                    if !spend.enabled {
                        Text(spend.disabledReason == "out_of_credits"
                             ? "Credits are off — you've used your monthly cap."
                             : "Usage credits are turned off.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                footer(snapshot)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Plan usage limits")
                .font(.system(size: 13, weight: .semibold))
            if let plan = model.snapshot?.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { model.refresh(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .help("Refresh now")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func footer(_ snapshot: UsageSnapshot) -> some View {
        HStack {
            Text("Last updated: \(Format.lastUpdated(snapshot.fetchedAt))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(ClaudeApp.isInstalled ? "Open Claude" : "claude.ai", action: onOpenClaude)
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .help(ClaudeApp.isInstalled
                      ? "Open the Claude desktop app"
                      : "Claude isn't installed — opens claude.ai")
            Button("Settings", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
