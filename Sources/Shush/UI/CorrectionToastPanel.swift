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
    private static let gap: CGFloat = 8
    /// Above this height a field is a pane (an editor, a long compose box), and "above the
    /// field" would be nowhere near where the text landed — anchor on the caret line instead.
    private static let tallField: CGFloat = 200

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

    /// Places the toast just above the edited element, on whichever display that element is
    /// on, using its AX-reported screen rect. When the rect is unreadable it falls back to
    /// the display under the mouse, so the toast still lands on the screen being worked on
    /// rather than at the origin or on another monitor.
    func present(near element: AXUIElement) {
        setFrameOrigin(origin(near: element) ?? fallbackOrigin())

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

    private func origin(near element: AXUIElement) -> NSPoint? {
        guard var anchor = appKitRect(of: element) else { return nil }
        if anchor.height > Self.tallField, let caret = caretRect(of: element) { anchor = caret }

        // The display is whichever one holds the field's centre, not the primary one.
        let centre = NSPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) else { return nil }
        let visible = screen.visibleFrame

        // Above the field; below it only when there's no room (a field at the top of the screen).
        var y = anchor.maxY + Self.gap
        if y + Self.size.height > visible.maxY { y = anchor.minY - Self.gap - Self.size.height }

        let x = min(max(anchor.minX, visible.minX + Self.gap), visible.maxX - Self.size.width - Self.gap)
        return NSPoint(x: x, y: min(max(y, visible.minY), visible.maxY - Self.size.height))
    }

    /// AX frames are top-left-origin, y-down, in one global space anchored at the primary
    /// display's top-left; AppKit's are bottom-left-origin, y-up, anchored at its bottom-left.
    /// Flipping against the primary display's height is exact for every display in the layout.
    private static func appKitRect(fromAX rect: CGRect) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func appKitRect(of element: AXUIElement) -> NSRect? {
        guard let position = axValue(element, kAXPositionAttribute, .cgPoint, CGPoint.self),
              let size = axValue(element, kAXSizeAttribute, .cgSize, CGSize.self)
        else { return nil }
        return Self.appKitRect(fromAX: CGRect(origin: position, size: size))
    }

    /// The caret's line, for apps that can report it. Many can't, hence the optional.
    private func caretRect(of element: AXUIElement) -> NSRect? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range
        else { return nil }

        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds
        ) == .success, let bounds else { return nil }

        let value = unsafeDowncast(bounds as AnyObject, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              rect.height > 0, rect.origin != .zero
        else { return nil }
        return Self.appKitRect(fromAX: rect)
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

    /// Same spot `HUDPanel.reposition()` uses, but on the display under the mouse: with
    /// several screens `NSScreen.main` can be a different one from where the user is typing.
    private func fallbackOrigin() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens.first
        else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 96)
    }
}
