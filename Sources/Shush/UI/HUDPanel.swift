import AppKit
import ApplicationServices
import SwiftUI

/// The floating capsule that appears while you hold the key.
///
/// The single most important property here is that this panel **never becomes key**.
/// If it did, the user's text field would lose focus and `TextInjector` would have
/// nothing to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false`.
@MainActor
final class HUDPanel: NSPanel {
    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        // The HUD carries a close/cancel button now, so it can't be fully click-through
        // anymore — AppKit has no per-pixel passthrough for a single window. It's small and
        // only on screen while actively dictating, so this briefly blocking clicks to
        // whatever's underneath is an acceptable trade for the button working at all.
        ignoresMouseEvents = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: HUDView(controller: controller))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Parks the panel just above the Dock, horizontally centered on the screen holding the
    /// frontmost app's focused window.
    ///
    /// `NSScreen.main` is the screen with the *key window* — and an accessory app with a
    /// non-activating panel never has one, so it's useless here. The HUD needs to track
    /// wherever the user is actually dictating into, which on a multi-monitor setup is
    /// whatever screen the target app's window sits on, not the display holding the menu
    /// bar. Falls back to the menu-bar screen, then `screens.first`, if AX lookup fails.
    func reposition() {
        guard let screen = HUDPanel.frontmostWindowScreen() ?? NSScreen.main ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 96
            )
        )
    }

    /// The screen holding the frontmost app's focused window, via the Accessibility API
    /// (already granted — `TextInjector` depends on the same permission).
    private static func frontmostWindowScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        let window = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }

        // AX coordinates are top-left-origin, screen-down; NSScreen frames are
        // bottom-left-origin, screen-up. Flip against the primary screen's height.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let center = NSPoint(
            x: position.x + size.width / 2,
            y: primaryHeight - (position.y + size.height / 2)
        )

        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    func present() {
        // Every active state change (starting → listening → finishing) calls this. Without
        // the early exit the panel would reset to alpha 0 and re-fade on each one, which
        // reads as a flicker mid-utterance.
        guard !isVisible || alphaValue < 1 else { return }

        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit always calls this on the main thread.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
