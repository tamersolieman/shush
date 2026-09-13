import ApplicationServices
import AppKit
import ShushDictionary
import SwiftUI

/// The "save this as a correction?" toast — same non-activating-panel contract as `HUDPanel`
/// and for the same reason: it appears while the user is still working in another app, and
/// must never steal focus from it.
@MainActor
final class CorrectionToastPanel: NSPanel {
    private var dismissTask: Task<Void, Never>?

    private static let size = NSSize(width: 360, height: 118)
    private static let autoDismiss: Duration = .seconds(8)

    init(correction: CorrectionDiff.Correction, onSave: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        contentView = NSHostingView(rootView: CorrectionToastView(
            correction: correction,
            onSave: { [weak self] in
                onSave()
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                onDismiss()
                self?.dismiss()
            }
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the toast just below the edited element, using its AX-reported screen rect
    /// when readable; falls back to `HUDPanel`'s above-the-Dock spot otherwise, so an
    /// unpositionable toast still lands somewhere predictable rather than at the origin.
    func present(near element: AXUIElement) {
        setFrameOrigin(originNear(element) ?? aboveDockOrigin())

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoDismiss)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }

    private func originNear(_ element: AXUIElement) -> NSPoint? {
        guard let axPosition = axValue(element, kAXPositionAttribute, .cgPoint, CGPoint.self),
              let axSize = axValue(element, kAXSizeAttribute, .cgSize, CGSize.self),
              let screen = NSScreen.screens.first
        else { return nil }

        // AX position is top-left-origin, y-down, in the primary display's coordinate space;
        // AppKit screen coordinates are bottom-left-origin, y-up. This conversion is only
        // exact on the primary display — an acceptable approximation for "roughly under the
        // field," not pixel-perfect placement on a secondary monitor.
        let primaryHeight = screen.frame.height
        let flippedY = primaryHeight - axPosition.y - axSize.height

        let point = NSPoint(x: axPosition.x, y: flippedY - Self.size.height - 8)
        let candidate = NSRect(origin: point, size: Self.size)
        guard screen.frame.intersects(candidate) else { return nil }
        return point
    }

    private func axValue<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType, _: T.Type) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success, let raw else { return nil }
        let axValue = unsafeDowncast(raw as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == type else { return nil }
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AXValueGetValue(axValue, type, value) else { return nil }
        return value.pointee
    }

    /// Same spot `HUDPanel.reposition()` uses — reused so an unpositioned toast is still
    /// consistent with the rest of the app's floating UI.
    private func aboveDockOrigin() -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 96)
    }
}
