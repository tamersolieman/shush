import AppKit
import Carbon.HIToolbox
import Foundation

/// Which key holds the mic open — any key, not just the three built-in presets.
///
/// Two shapes, because macOS reports them through entirely different event types:
/// - **A modifier** (⌥⌘⌃⇧fn) never generates `keyDown`/`keyUp` — only `flagsChanged`, with
///   the same `keyCode` for press and release. `flagMask` is the device-*specific* bit
///   (`NX_DEVICE*`) that tells press from release for that exact physical key — the public
///   `CGEventFlags` constants only expose the union of left+right, which makes a release
///   invisible whenever the other side is also down.
/// - **Any other key** (letters, F-keys, Space, arrows…) has ordinary `keyDown`/`keyUp`,
///   so `flagMask` is nil and `HotkeyMonitor` watches those instead.
struct PushToTalkKey: Codable, Equatable, Sendable {
    var keyCode: Int64
    var flagMask: UInt64?
    var displayName: String

    var isModifier: Bool { flagMask != nil }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so it's let
    /// through. Every other key is dedicated to this app while held, so it's safe to consume.
    var shouldConsumeEvent: Bool { keyCode != Int64(kVK_Function) }

    static let rightOption = PushToTalkKey(keyCode: Int64(kVK_RightOption), flagMask: 0x40, displayName: "Right ⌥")
    static let fn = PushToTalkKey(
        keyCode: Int64(kVK_Function), flagMask: CGEventFlags.maskSecondaryFn.rawValue, displayName: "fn"
    )
    static let rightCommand = PushToTalkKey(keyCode: Int64(kVK_RightCommand), flagMask: 0x10, displayName: "Right ⌘")
    static let `default` = rightOption

    /// The `NX_DEVICE*` bits for every modifier key macOS can report individually. A
    /// modifier not in this table (there isn't one, but belt and braces) falls back to
    /// treating it as a regular key, which just means a held-but-not-yet-released state
    /// could misbehave — acceptable, since every real modifier is listed here.
    private static let deviceFlags: [Int64: UInt64] = [
        Int64(kVK_Control): 0x0001, Int64(kVK_RightControl): 0x2000,
        Int64(kVK_Shift): 0x0002, Int64(kVK_RightShift): 0x0004,
        Int64(kVK_Command): 0x0008, Int64(kVK_RightCommand): 0x0010,
        Int64(kVK_Option): 0x0020, Int64(kVK_RightOption): 0x0040,
        Int64(kVK_Function): CGEventFlags.maskSecondaryFn.rawValue,
    ]

    /// Builds a key from whatever the recorder just captured.
    static func captured(keyCode: Int64, displayName: String) -> PushToTalkKey {
        PushToTalkKey(keyCode: keyCode, flagMask: deviceFlags[keyCode], displayName: displayName)
    }
}

/// Watches for a held key — modifier or otherwise — using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs. This needs
/// Accessibility permission; without it `CGEvent.tapCreate` returns nil.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    var key: PushToTalkKey = .default
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.key.displayName)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isPressed = false
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard keyCode == key.keyCode else { return false }

        if let flagMask = key.flagMask {
            guard type == .flagsChanged else { return false }
            let nowPressed = (flags.rawValue & flagMask) != 0
            guard nowPressed != isPressed else { return false }
            isPressed = nowPressed
            if nowPressed { onPress?() } else { onRelease?() }
            return key.shouldConsumeEvent
        }

        // A regular key: ordinary keyDown/keyUp, no flag bit involved.
        switch type {
        case .keyDown:
            // Key-repeat resends keyDown every ~30ms while held — consumed so it doesn't
            // leak into whatever's focused, but ignored so it doesn't restart the hold.
            guard !isRepeat, !isPressed else { return true }
            isPressed = true
            onPress?()
            return true
        case .keyUp:
            guard isPressed else { return false }
            isPressed = false
            onRelease?()
            return true
        default:
            return false
        }
    }
}
