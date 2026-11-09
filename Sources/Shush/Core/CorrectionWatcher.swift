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
    private var settleTask: Task<Void, Never>?
    /// The timeout fired while an edit was still settling; that settle is the last read.
    private var expired = false

    /// Long enough to cover "noticed the mis-transcription a few words later and fixed it,"
    /// short enough not to leave a stale observer attached once the user has clearly moved
    /// on within the same app (e.g. scrolled elsewhere without changing focused element).
    private static let timeout: Duration = .seconds(25)

    /// Quiet time after the last keystroke before the field is read. The first change
    /// notification arrives after a single letter, when the word is only half-corrected
    /// ("Shush" → "Shus"); reading then reports a bogus partial rule, or finds nothing to
    /// report, and either way the watch used to end for good before the real edit landed.
    private static let settle: Duration = .milliseconds(1500)

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
            self?.expire()
        }
    }

    private func expire() {
        timeoutTask = nil
        if settleTask == nil {
            teardown()
        } else {
            expired = true
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
            scheduleSettle()
            return
        }

        // Focus moved or the element went away. An edit still settling gets its one last
        // read — fixing a word and hitting Return or clicking away must not lose it.
        if settleTask != nil { evaluateEdit() }
        teardown()
    }

    /// Restarts the quiet-period clock on every change. After the timeout an already-pending
    /// read is not pushed out any further, so a field that never stops changing can't keep
    /// the watch alive.
    private func scheduleSettle() {
        if expired, settleTask != nil { return }

        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.settled()
        }
    }

    /// Ends the watch once a correction has been offered — never a second one, that's how a
    /// normal typing session would spam toasts. With nothing to offer yet (an append, a
    /// half-finished edit) it keeps watching until the timeout.
    private func settled() {
        settleTask = nil
        if evaluateEdit() || expired { teardown() }
    }

    @discardableResult
    private func evaluateEdit() -> Bool {
        guard let original, let watchedElement else { return false }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(watchedElement, kAXValueAttribute as CFString, &value) == .success,
              let current = value as? String
        else { return false }

        guard let correction = CorrectionDiff.detect(original: original, current: current) else { return false }

        Log.correction.info(
            "detected correction: \(correction.hear, privacy: .private) -> \(correction.write, privacy: .private)"
        )
        onCorrectionDetected?(correction, watchedElement)
        return true
    }

    func cancel() {
        teardown()
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        expired = false

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
