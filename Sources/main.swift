import AppKit
import SwiftUI
import ServiceManagement

private let showPercentKey = "showPercentInMenuBar"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = UsageModel()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [showPercentKey: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(
            rootView: UsageView(model: model,
                                onQuit: { NSApp.terminate(nil) },
                                onOpenSettings: { [weak self] in self?.showMenu() })
        )
        hosting.sizingOptions = .preferredContentSize

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hosting

        model.onUpdate = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        model.start()

        // Handy for testing the popover without clicking the menu bar.
        if CommandLine.arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        // Only fall back to a warning glyph when there's nothing at all to show;
        // a transient error over good data keeps the Claude mark.
        if model.errorMessage != nil && model.snapshot == nil {
            let warning = NSImage(systemSymbolName: "exclamationmark.triangle",
                                  accessibilityDescription: "Claude Code usage unavailable")
            warning?.isTemplate = true
            button.image = warning
        } else {
            button.image = ClaudeGlyph.statusBarImage()
        }
        button.imagePosition = .imageLeading

        guard UserDefaults.standard.bool(forKey: showPercentKey),
              let percent = model.snapshot?.sessionPercent else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Claude Code usage"
            return
        }

        let text = " \(Int(percent.rounded()))%"
        let peak = model.snapshot?.peakPercent ?? percent
        let color: NSColor = peak >= 90 ? .systemRed : (peak >= 75 ? .systemOrange : .labelColor)
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: color,
            ]
        )
        button.toolTip = "Claude Code — session \(Int(percent.rounded()))% used"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }

        model.refreshIfStale()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // .transient alone doesn't always dismiss for an accessory app.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Menu

    private func showMenu() {
        popover.performClose(nil)

        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let percent = NSMenuItem(title: "Show Percentage in Menu Bar",
                                 action: #selector(togglePercent), keyEquivalent: "")
        percent.target = self
        percent.state = UserDefaults.standard.bool(forKey: showPercentKey) ? .on : .off
        menu.addItem(percent)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // restore click-to-popover behaviour
    }

    @objc private func refreshNow() { model.refresh(force: true) }

    @objc private func togglePercent() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: showPercentKey), forKey: showPercentKey)
        updateStatusItem()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the Launch at Login setting"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// Top-level code isn't main-actor isolated under -swift-version 5, but it does
// run on the main thread, so asserting that is safe here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)

    // NSApplication doesn't retain its delegate.
    objc_setAssociatedObject(app, "ClaudeUsageDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)

    app.run()
}
