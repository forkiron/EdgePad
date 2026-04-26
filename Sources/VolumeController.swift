// VolumeController.swift
//
// Reads and writes the system default output device's volume via
// CoreAudio. Public API, App Store safe, works everywhere.

import Foundation
import CoreAudio

@MainActor
public final class VolumeController {

    private var startVolume: Float = 0
    public var sensitivity: Float = 1.2

    public init() {}

    public func captureStartValue() {
        startVolume = currentVolume()
    }

    /// Apply a drag-delta from the EdgeDetector to the captured start.
    public func applyDelta(_ delta: Float) -> Float {
        let target = max(0, min(1, startVolume + delta * sensitivity))
        setVolume(target)
        return target
    }

    public func currentVolume() -> Float {
        guard let device = defaultOutputDevice() else { return 0 }

        // Some output devices (notably Bluetooth/USB) return noErr on the
        // main element with value=0 even though channels 1+2 carry the real
        // volume. Read from all three and take the max — safest with the
        // various ways CoreAudio splits volume across elements.
        var best: Float = 0
        var anyFound = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
            if status == noErr {
                best = max(best, Float(volume))
                anyFound = true
            }
        }
        if !anyFound {
            NSLog("[VOL] ✗ no volume property exposed on any element")
        }
        return max(0, min(1, best))
    }

    @discardableResult
    public func setVolume(_ value: Float) -> Bool {
        let clamped = max(0, min(1, value))
        guard let device = defaultOutputDevice() else { return false }

        var master = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(device, &master) {
            if AudioObjectSetPropertyData(device, &master, 0, nil, size, &vol) == noErr {
                return true
            }
        }

        var ok = false
        for channel: AudioObjectPropertyElement in [1, 2] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            if AudioObjectHasProperty(device, &addr) {
                if AudioObjectSetPropertyData(device, &addr, 0, nil, size, &vol) == noErr {
                    ok = true
                }
            }
        }
        return ok
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &id
        )
        return status == noErr ? id : nil
    }
}
