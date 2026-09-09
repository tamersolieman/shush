import CoreAudio
import Foundation

/// Mutes and restores the default output device — used to keep a recording from picking up
/// whatever's currently playing.
enum SystemAudio {
    @discardableResult
    static func setOutputMuted(_ muted: Bool) -> Bool {
        guard let deviceID = defaultOutputDevice() else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            Log.audio.info("default output device has no mute control — skipping")
            return false
        }

        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
        return status == noErr
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID
        )
        return status == noErr ? deviceID : nil
    }
}
