import AppKit

/// Launching the Claude desktop app, so the popover can hand off to the real
/// Usage pane. Falls back to the web app when Claude isn't installed.
enum ClaudeApp {
    private static let bundleID = "com.anthropic.claudefordesktop"
    private static let webURL = URL(string: "https://claude.ai")!

    static var isInstalled: Bool { installedURL != nil }

    private static var installedURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func open() {
        guard let appURL = installedURL else {
            NSWorkspace.shared.open(webURL)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            // If the bundle is there but won't launch (moved, damaged), the web
            // app still gets the user where they were going.
            if error != nil {
                DispatchQueue.main.async { NSWorkspace.shared.open(webURL) }
            }
        }
    }
}
