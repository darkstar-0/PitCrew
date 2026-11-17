import AppKit
import SwiftUI
import ServiceManagement

/// Borderless panels can't become key by default, which makes SwiftUI buttons flaky.
/// With .nonactivatingPanel it can take clicks without stealing focus from VS Code.
final class CrewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let width: CGFloat = 360
    static let port: UInt16 = 7777

    let store = CrewStore()
    var panel: CrewPanel!
    var statusItem: NSStatusItem!
    var server: EventServer?
    var loginItem: NSMenuItem!

    /// Top-right corner the panel stays pinned to as it grows/shrinks.
    var anchor: NSPoint?

    /// True when running from PitCrew.app (vs. `swift run`). Launch at Login
    /// only works for a real app bundle.
    var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy can own the port; if PitCrew.app is already running, bow out.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        setupPanel()
        setupStatusItem()
        store.isPanelVisible = { [weak self] in self?.panel.isVisible ?? false }
        do {
            let server = try EventServer(port: Self.port) { [weak self] request in
                self?.store.handle(request)
            }
            server.start()
            self.server = server
        } catch {
            NSLog("Pit Crew: could not start event server on port \(Self.port): \(error)")
        }
    }

    // MARK: Panel

    func setupPanel() {
        panel = CrewPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let root = CrewView(
            store: store,
            onHeight: { [weak self] h in self?.resize(height: h) },
            onHide: { [weak self] in self?.panel.orderOut(nil) }
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []   // we size the window ourselves
        panel.contentView = host

        resetPosition()
        panel.orderFrontRegardless()

        // When the user drags the panel, remember the new top-right corner.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.anchor = NSPoint(x: self.panel.frame.maxX, y: self.panel.frame.maxY)
        }
    }

    func resize(height: CGFloat) {
        guard height > 0, let anchor else { return }
        panel.setFrame(
            NSRect(x: anchor.x - Self.width, y: anchor.y - height, width: Self.width, height: height),
            display: true
        )
    }

    @objc func resetPosition() {
        if let screen = NSScreen.main?.visibleFrame {
            anchor = NSPoint(x: screen.maxX - 16, y: screen.maxY - 16)
        }
        resize(height: max(panel.frame.height, 60))
    }

    @objc func showPanel() {
        panel.orderFrontRegardless()
    }

    // MARK: Launch at Login

    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Pit Crew: Launch at Login failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also add Pit Crew in System Settings → General → Login Items."
            alert.runModal()
        }
        refreshLoginItem()
    }

    func refreshLoginItem() {
        guard let loginItem else { return }
        if isAppBundle {
            loginItem.isEnabled = true
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            loginItem.title = "Launch at Login"
        } else {
            loginItem.isEnabled = false
            loginItem.state = .off
            loginItem.title = "Launch at Login (needs PitCrew.app)"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLoginItem()
    }

    // MARK: Menu bar

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "person.3.fill",
                                           accessibilityDescription: "Pit Crew")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Show Pit Crew", action: #selector(showPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "").target = self
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pit Crew", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        refreshLoginItem()
    }
}
