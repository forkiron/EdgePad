// BrightnessController.swift
//
// Reads/writes built-in display brightness via the private
// DisplayServices.framework — the same entry point macOS System Settings
// uses. Loaded via dlopen/dlsym so there's no link-time dependency on a
// private framework.
//
// Fallback for future macOS breakage: post F1/F2 media keys, which
// works everywhere but loses absolute-set capability.

import Foundation
import Darwin
import CoreGraphics

@MainActor
public final class BrightnessController {

    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var setFn: SetFn?
    private var getFn: GetFn?

    public var sensitivity: Float = 1.2
    private var startBrightness: Float = 0.5

    public init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let h = dlopen(path, RTLD_LAZY) {
            handle = h
            if let s = dlsym(h, "DisplayServicesSetBrightness") {
                setFn = unsafeBitCast(s, to: SetFn.self)
            }
            if let g = dlsym(h, "DisplayServicesGetBrightness") {
                getFn = unsafeBitCast(g, to: GetFn.self)
            }
        }
    }

    public func captureStartValue() {
        startBrightness = currentBrightness()
    }

    @discardableResult
    public func applyDelta(_ delta: Float) -> Float {
        let target = max(0, min(1, startBrightness + delta * sensitivity))
        setBrightness(target)
        return target
    }

    public func currentBrightness() -> Float {
        guard let getFn, let display = mainDisplay() else { return 0.5 }
        var value: Float = 0
        _ = getFn(display, &value)
        return max(0, min(1, value))
    }

    @discardableResult
    public func setBrightness(_ value: Float) -> Bool {
        let clamped = max(0, min(1, value))
        guard let setFn, let display = mainDisplay() else { return false }
        return setFn(display, clamped) == 0
    }

    private func mainDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.first
    }
}
