import AppKit
import CoreGraphics
import SwiftUI

private let kBlockerWindowLevel = NSWindow.Level(
    rawValue: Int(CGWindowLevelForKey(.maximumWindow))
)

@MainActor
final class BlockerCoordinator: BreakBlocking {
    private weak var controller: SessionController?
    private var windows: [NSWindow] = []

    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var screenSaverStopObserver: NSObjectProtocol?
    private var screenSaverStartObserver: NSObjectProtocol?

    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var watchdogTimer: Timer?
    private var isShown = false

    private static let requiredPresentationOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableAppleMenu,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication,
        .disableMenuBarTransparency
    ]

    init(controller: SessionController) {
        self.controller = controller
    }

    func show() {
        guard !isShown else { return }
        isShown = true

        NSApp.activate(ignoringOtherApps: true)

        savedPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = Self.requiredPresentationOptions

        rebuildWindows()
        installObservers()
        startWatchdog()
    }

    func hide() {
        guard isShown else { return }
        isShown = false

        stopWatchdog()
        removeObservers()

        if let opts = savedPresentationOptions {
            NSApp.presentationOptions = opts
        }
        savedPresentationOptions = nil

        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        screenObserver = nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildWindows() }
        }
        resignObserver = nc.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforce() }
        }

        let wsNC = NSWorkspace.shared.notificationCenter
        deactivateObserver = wsNC.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforce() }
        }
        spaceObserver = wsNC.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforce() }
        }
        wakeObserver = wsNC.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildWindows(); self?.enforce() }
        }
        screensWakeObserver = wsNC.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildWindows(); self?.enforce() }
        }

        let dnc = DistributedNotificationCenter.default()
        screenSaverStopObserver = dnc.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildWindows(); self?.enforce() }
        }
        screenSaverStartObserver = dnc.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforce() }
        }
    }

    private func removeObservers() {
        let nc = NotificationCenter.default
        if let o = screenObserver { nc.removeObserver(o); screenObserver = nil }
        if let o = resignObserver { nc.removeObserver(o); resignObserver = nil }

        let wsNC = NSWorkspace.shared.notificationCenter
        if let o = deactivateObserver { wsNC.removeObserver(o); deactivateObserver = nil }
        if let o = spaceObserver { wsNC.removeObserver(o); spaceObserver = nil }
        if let o = wakeObserver { wsNC.removeObserver(o); wakeObserver = nil }
        if let o = screensWakeObserver { wsNC.removeObserver(o); screensWakeObserver = nil }

        let dnc = DistributedNotificationCenter.default()
        if let o = screenSaverStopObserver { dnc.removeObserver(o); screenSaverStopObserver = nil }
        if let o = screenSaverStartObserver { dnc.removeObserver(o); screenSaverStartObserver = nil }
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enforce() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdogTimer = t
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func enforce() {
        guard isShown else { return }

        if NSApp.presentationOptions != Self.requiredPresentationOptions {
            NSApp.presentationOptions = Self.requiredPresentationOptions
        }

        if windows.count != NSScreen.screens.count {
            rebuildWindows()
            return
        }

        for w in windows {
            if w.level != kBlockerWindowLevel {
                w.level = kBlockerWindowLevel
            }
            if !w.isVisible {
                w.orderFrontRegardless()
            }
            w.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle
            ]
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func rebuildWindows() {
        guard let controller else { return }

        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = BlockerWindow(screen: screen)
            let host = NSHostingView(
                rootView: BreakBlockerView().environmentObject(controller)
            )
            host.frame = screen.frame
            host.autoresizingMask = [.width, .height]
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }
}

final class BlockerWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.setFrame(screen.frame, display: false)
        self.isOpaque = true
        self.backgroundColor = .black
        self.level = kBlockerWindowLevel
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.canHide = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Swallow keys.
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        // Swallow Escape.
    }
}
