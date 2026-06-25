import AppKit
import SwiftUI

/// A borderless window that is allowed to become key, so the parent-PIN field inside the
/// lock overlay can receive keyboard input. (Plain borderless windows refuse key status.)
private final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Presents the v2 lock overlay: one shielding window per display, at the screen-saver
/// window level, covering everything. The overlay is re-asserted if it loses key status
/// or the display layout changes, so the child can't click/Cmd-Tab their way out. While
/// it's up, the dock, menu bar, app switching, and force-quit are suppressed via
/// `presentationOptions`.
///
/// Honest scope note: this resists casual evasion from within the child's session. It is
/// not a substitute for the privileged watchdog (see `scripts/`), and a child with admin
/// rights or recovery-mode access can still bypass it.
///
/// All methods run on the main thread: callers drive it from the 1 Hz tick / UI actions,
/// and the notification observers below are delivered on the main queue.
final class LockController {
    private weak var model: AppModel?
    private var windows: [LockWindow] = []
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var observers: [NSObjectProtocol] = []

    private var isLocked: Bool { !windows.isEmpty }

    init(model: AppModel) {
        self.model = model
    }

    /// Idempotently bring the overlay in line with whether it should be shown.
    func update(shouldLock: Bool) {
        if shouldLock { present() } else { dismiss() }
    }

    // MARK: Present / dismiss

    private func present() {
        guard !isLocked, model != nil else { return }

        savedPresentationOptions = NSApp.presentationOptions

        // Place the shield windows on the *currently active* Space first — including
        // another app's native full-screen Space — via `.canJoinAllSpaces` at the
        // shielding level. We deliberately stay an accessory (LSUIElement) app and do
        // NOT flip to `.regular`: doing so makes the window server reassign our windows
        // to the app's own Space (the desktop behind the full-screen app), which is why
        // the overlay used to appear only after the child left full-screen mode.
        buildWindows()

        // Become the active app so the PIN field can receive keystrokes, and clamp the
        // environment (no dock/menu bar, no app-switch/force-quit). Accessory apps can
        // activate and own a key window without switching to `.regular`.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit]

        installObservers()
    }

    /// Create one shielding window per screen and bring them on screen. Does not touch
    /// presentation options or observers, so it's safe to call again on `rebuild`.
    private func buildWindows() {
        guard let model else { return }
        let primary = NSScreen.main
        for screen in NSScreen.screens {
            let isPrimary = (screen == primary)
            let window = LockWindow(contentRect: screen.frame,
                                    styleMask: .borderless,
                                    backing: .buffered,
                                    defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: LockOverlayView(model: model, showsControls: isPrimary))
            window.setFrame(screen.frame, display: true)
            // `orderFrontRegardless` (not `makeKeyAndOrderFront`) so the window lands on
            // the active Space without forcing app activation — that activation is what
            // pulled the overlay out of another app's full-screen Space. The primary
            // window is made key once we activate in `present()`/`reassert()`.
            window.orderFrontRegardless()
            if isPrimary {
                window.makeKey()
            }
            windows.append(window)
        }
    }

    private func dismiss() {
        guard isLocked else { return }
        removeObservers()
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        if let saved = savedPresentationOptions {
            NSApp.presentationOptions = saved
            savedPresentationOptions = nil
        }
        // The app stayed an accessory (LSUIElement) throughout, so there's no activation
        // policy to restore here.
    }

    // MARK: Re-assertion

    private func installObservers() {
        let nc = NotificationCenter.default

        // If our key window loses focus (e.g. the child tries to switch away), pull it back.
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self, self.isLocked,
                  let w = note.object as? NSWindow, self.windows.contains(where: { $0 === w }) else { return }
            self.reassert()
        })

        // Display added/removed/resized → rebuild to keep covering every screen.
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isLocked else { return }
            self.rebuild()
        })
    }

    private func removeObservers() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func reassert() {
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        for window in windows where window != windows.first { window.orderFrontRegardless() }
    }

    private func rebuild() {
        // Replace the windows to match the new display layout; the lock stays active and
        // the saved presentation options are preserved.
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        buildWindows()
    }
}
