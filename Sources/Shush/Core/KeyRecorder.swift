import AppKit
import Carbon.HIToolbox

/// Captures the next key or modifier the user presses and turns it into a `PushToTalkKey`.
///
/// A *local* monitor is enough here — recording only ever happens while the Settings window
/// has focus, unlike the always-on global tap in `HotkeyMonitor`. Watches both `.keyDown`
/// (regular keys) and `.flagsChanged` (modifiers, which never send `keyDown`) and resolves
/// whichever fires first.
@MainActor
final class KeyRecorder {
    private var monitor: Any?

    var isRecording: Bool { monitor != nil }

    func start(onCapture: @escaping (PushToTalkKey) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let key = Self.resolve(event) else { return event }
            self.stop()
            onCapture(key)
            return nil // swallow the event that defined the shortcut itself
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func resolve(_ event: NSEvent) -> PushToTalkKey? {
        let keyCode = Int64(event.keyCode)

        if event.type == .flagsChanged {
            // A release event on the *same* key that's already being captured isn't a
            // capture — it's just the recorder's own key coming back up.
            return PushToTalkKey.captured(keyCode: keyCode, displayName: modifierName(keyCode))
        }

        guard event.type == .keyDown else { return nil }
        return PushToTalkKey.captured(keyCode: keyCode, displayName: regularKeyName(event))
    }

    private static func modifierName(_ keyCode: Int64) -> String {
        switch Int(keyCode) {
        case kVK_Function: "fn"
        case kVK_Control: "⌃ (Left)"
        case kVK_RightControl: "⌃ (Right)"
        case kVK_Shift: "⇧ (Left)"
        case kVK_RightShift: "⇧ (Right)"
        case kVK_Command: "⌘ (Left)"
        case kVK_RightCommand: "Right ⌘"
        case kVK_Option: "⌥ (Left)"
        case kVK_RightOption: "Right ⌥"
        case kVK_CapsLock: "Caps Lock"
        default: "Key \(keyCode)"
        }
    }

    /// Named keys first (arrows, function row, whitespace/editing keys — none of these
    /// produce useful `characters`), then falls back to the typed character itself.
    private static func regularKeyName(_ event: NSEvent) -> String {
        let named: [Int: String] = [
            kVK_Escape: "Escape", kVK_Tab: "Tab", kVK_Space: "Space", kVK_Return: "Return",
            kVK_Delete: "Delete", kVK_ForwardDelete: "Fwd Delete",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = named[Int(event.keyCode)] { return name }

        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
           chars.rangeOfCharacter(from: .controlCharacters) == nil {
            return chars.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}
