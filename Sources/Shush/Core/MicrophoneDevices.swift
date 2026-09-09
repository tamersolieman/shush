import AVFoundation
import CoreAudio
import Foundation

/// A microphone the user can pick, alongside the CoreAudio device it maps to.
struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    /// `AVCaptureDevice.uniqueID` — also CoreAudio's device UID, which is what's persisted
    /// in Settings (stable across reboots, unlike `AudioDeviceID` which is reassigned).
    var id: String
    let name: String
    let audioDeviceID: AudioDeviceID
}

enum MicrophoneDevices {
    static func available() -> [MicrophoneDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
        )
        return session.devices.compactMap { device in
            guard let audioDeviceID = coreAudioDeviceID(forUID: device.uniqueID) else { return nil }
            return MicrophoneDevice(id: device.uniqueID, name: device.localizedName, audioDeviceID: audioDeviceID)
        }
    }

    static func resolve(uid: String) -> MicrophoneDevice? {
        available().first { $0.id == uid }
    }

    /// `AVCaptureDevice.uniqueID` and CoreAudio's `AudioDeviceID` are different address
    /// spaces — this walks every hardware device and matches on `kAudioDevicePropertyDeviceUID`,
    /// which is the string both APIs agree on.
    private static func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr
        else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr
        else { return nil }

        for deviceID in deviceIDs where deviceUID(deviceID) == uid {
            return deviceID
        }
        return nil
    }

    private static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { return nil }
        return uid as String?
    }
}
