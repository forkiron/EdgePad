// AudioActivity.swift
//
// "Is something on this Mac making sound right now?" via CoreAudio.
// Used by ContextDetector to flip top-edge to mediaScrub when the user
// is in a browser with audio playing — covers sites like X, LinkedIn,
// embedded video players, etc. that don't publish meaningful AX video
// semantics for our click-based detection.
//
// CoreAudio is a coarse signal: it tells us "the default output device
// is being driven by some process" without identifying the process or
// telling us if there's a controllable timeline. Combined with the
// frontmost-is-browser gate, that's good enough for the common case
// (user clicks video → audio starts → top edge scrubs via arrow keys
// because the video now has keyboard focus).

import CoreAudio
import Foundation

public enum AudioActivity {

    /// True if the default output device reports any process actively
    /// pushing audio through it. Returns false if CoreAudio cannot
    /// answer — never throws or hangs.
    public static func isPlaying() -> Bool {
        guard let deviceID = defaultOutputDevice() else { return false }
        return deviceIsRunningSomewhere(deviceID)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &device
        )
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    private static func deviceIsRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        return status == noErr && running != 0
    }
}
