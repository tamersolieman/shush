import AppKit
import ApplicationServices
import Foundation
import ShushDictionary

/// Watches the one field Shush just injected text into for a short window afterward. If the
/// user hand-corrects a word there, offers to save it as a dictionary rule.
///
/// Entirely best-effort, layered on top of dictation rather than part of it:
/// `DictationController` has already returned to `.idle` before `observe(injected:target:)`
/// is ever called, so nothing here can block or fail a dictation. `AXObserverCreate`/
/// `AXObserverAddNotification` failing (sandboxed target, an app with the same "half-hearted
/// AX implementation" `TextInjector` already routes around) is a silent no-op — logged, not
/// surfaced.
///
/// Only ever observes the single `AXUIElement` re-acquired immediately after injection —
/// never enumerates the target app's other windows or elements, never walks
/// `kAXChildrenAttribute`. That, plus the timeout below and "starting a new watch always
/// cancels the previous one," bounds how much and how long this ever reads from another app.
@MainActor
final class CorrectionWatcher {
    static let shared = CorrectionWatcher()

    var onCorrectionDetected: ((CorrectionDiff.Correction, AXUIElement) -> Void)?

    private var observer: AXObserver?
    private var watchedElement: AXUIElement?
    private var appElement: AXUIElement?
    private var original: String?
    private var timeoutTask: Task<Void, Never>?

    /// Long enough to cover "noticed the mis-transcription a few words later and fixed it,"
    /// short enough not to leave a stale observer attached once the user has clearly moved
    /// on within the same app (e.g. scrolled elsewhere without changing focused element).
    private static let timeout: Duration = .seconds(25)

    private init() {}

    /// Starts watching the currently focused element for an edit to `injected`. Always
    /// cancels any prior watch first — exactly one watch is ever live, corresponding to the
    /// most recent dictation.
    func observe(injected: String, target: NSRunningApplication?) {
        teardown()

        guard let pid = target?.processIdentifier else { return }

        // Re-acquire fresh, exactly as `TextInjector` does — safe because the HUD is
        // non-activating, so focus never left this element during/after injection.
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else { return }
        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        let app = AXUIElementCreateApplication(pid)

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &newObserver) == .success, let newObserver else {
            Log.correction.info("AXObserverCreate failed for pid \(pid)")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let attachResults = [
            AXObserverAddNotification(newObserver, element, kAXValueChangedNotification as CFString, refcon),
            AXObserverAddNotification(newObserver, element, kAXUIElementDestroyedNotification as CFString, refcon),
            AXObserverAddNotification(newObserver, app, kAXFocusedUIElementChangedNotification as CFString, refcon),
        ]
        guard attachResults.allSatisfy({ $0 == .success }) else {
            Log.correction.info("AXObserverAddNotification failed — target likely doesn't support AX observation")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        observer = newObserver
        watchedElement = element
        appElement = app
        original = injected

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    /// The C callback `AXObserverCreate` requires — no captures allowed, so it recovers
    /// `self` from `refcon` and hops back onto the main actor to do anything with it.
    private static let axCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let watcher = Unmanaged<CorrectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        Task { @MainActor in
            watcher.handle(notification: name)
        }
    }

    private func handle(notification: String) {
        // A prior teardown (e.g. the timeout task won a race) already cleared state.
        guard observer != nil else { return }

        if notification == kAXValueChangedNotification as String {
            evaluateEdit()
        }
        // Either path — evaluated or abandoned (focus moved, element destroyed) — this
        // watch is done. Don't keep watching for a second edit; that's how a normal typing
        // session would spam toasts.
        teardown()
    }

    private func evaluateEdit() {
        guard let original, let watchedElement else { return }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(watchedElement, kAXValueAttribute as CFString, &value) == .success,
              let current = value as? String
        else { return }

        guard let correction = CorrectionDiff.detect(original: original, current: current) else { return }

        Log.correction.info(
            "detected correction: \(correction.hear, privacy: .private) -> \(correction.write, privacy: .private)"
        )
        onCorrectionDetected?(correction, watchedElement)
    }

    func cancel() {
        teardown()
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil

        if let observer, let watchedElement {
            AXObserverRemoveNotification(observer, watchedElement, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, watchedElement, kAXUIElementDestroyedNotification as CFString)
        }
        if let observer, let appElement {
            AXObserverRemoveNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString)
        }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observer = nil
        watchedElement = nil
        appElement = nil
        original = nil
    }
}
