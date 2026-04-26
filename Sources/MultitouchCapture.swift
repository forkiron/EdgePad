// MultitouchCapture.swift
//
// Direct bindings to Apple's private MultitouchSupport.framework via
// dlopen/dlsym. We enumerate all devices with MTDeviceCreateList and
// start only the ones with real trackpad-sized sensor grids. We do
// NOT use MTDeviceCreateDefault() — on Apple Silicon MacBooks it
// returns a 60×2 auxiliary sensor instead of the real 26×18 trackpad
// and every coordinate it yields is unusable.

import Foundation
import Darwin
import CoreFoundation
import QuartzCore

// MARK: - C struct layouts (must match MT framework binary layout)

public struct MTPoint: Sendable {
    public var x: Float
    public var y: Float
}

public struct MTVector: Sendable {
    public var position: MTPoint
    public var velocity: MTPoint
}

public struct MTData: Sendable {
    public var frame: Int32
    public var timestamp: Double
    public var identifier: Int32
    public var state: Int32
    public var unknown1: Int32
    public var unknown2: Int32
    public var normalized: MTVector
    public var size: Float
    public var unknown3: Int32
    public var angle: Float
    public var majorAxis: Float
    public var minorAxis: Float
    public var unknown4: MTVector
    public var unknown5_1: Int32
    public var unknown5_2: Int32
    public var unknown6: Float
}

// MARK: - Public sample type + delegate

public enum TouchLifecycle: Sendable {
    case beginning
    case touching
    case ending
}

public struct TouchSample: Sendable {
    public let id: Int32
    public let x: Float          // 0…1, 0 = left edge
    public let y: Float          // 0…1, 0 = bottom edge
    public let pressure: Float   // size field, approximates pressure
    public let state: TouchLifecycle
    public let timestamp: Double

    public init(id: Int32, x: Float, y: Float, pressure: Float, state: TouchLifecycle, timestamp: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.pressure = pressure
        self.state = state
        self.timestamp = timestamp
    }
}

// MARK: - Function pointer types

private typealias MTDeviceRef = UnsafeMutableRawPointer

// Note: UnsafeMutableRawPointer? (not UnsafePointer<MTData>?) because
// @convention(c) closures require ObjC-representable parameter types,
// and MTData isn't ObjC-compatible. We cast inside the trampoline.
private typealias MTContactCallback = @convention(c) (
    Int32,                          // device
    UnsafeMutableRawPointer?,       // data (cast to MTData* inside)
    Int32,                          // nFingers
    Double,                         // timestamp
    Int32                           // frame
) -> Int32

private typealias MTDeviceCreateListFn        = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterCallbackFn        = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTUnregisterCallbackFn      = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias MTDeviceStartFn             = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias MTDeviceStopFn              = @convention(c) (MTDeviceRef) -> Void
private typealias MTDeviceGetSensorDimsFn     = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
private typealias MTDeviceGetFamilyIDFn       = @convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>) -> Int32
private typealias MTDeviceIsBuiltInFn         = @convention(c) (MTDeviceRef) -> Bool

// MARK: - C trampoline state

// Stored outside the class because @convention(c) closures can't capture
// Swift instance state. We only expect a single MultitouchCapture at a
// time (menu bar app), so a weak static ref is enough.
private final class WeakCaptureRef: @unchecked Sendable {
    weak var value: MultitouchCapture?
}
private let activeCapture = WeakCaptureRef()

// MARK: - MultitouchCapture

@MainActor
public final class MultitouchCapture {

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    private var running = false
    private weak var detector: EdgeDetector?

    // Cached function pointers
    private var unregisterFn: MTUnregisterCallbackFn?
    private var stopFn: MTDeviceStopFn?

    public init() {}

    // No deinit cleanup — the menu-bar app shuts down via explicit
    // stop() in applicationWillTerminate, and StrictConcurrency forbids
    // touching @MainActor state from a nonisolated deinit.

    public func start(routingTo detector: EdgeDetector) {
        guard !running else { return }
        self.detector = detector

        let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        NSLog("[MT] dlopen(\(frameworkPath))")
        guard let h = dlopen(frameworkPath, RTLD_LAZY) else {
            NSLog("[MT] ✗ dlopen failed: \(String(cString: dlerror() ?? UnsafeMutablePointer(mutating: ("unknown" as NSString).utf8String!)))")
            return
        }
        handle = h

        // Resolve symbols.
        guard let createListSym = dlsym(h, "MTDeviceCreateList") else {
            NSLog("[MT] ✗ missing MTDeviceCreateList"); return
        }
        guard let registerSym = dlsym(h, "MTRegisterContactFrameCallback") else {
            NSLog("[MT] ✗ missing MTRegisterContactFrameCallback"); return
        }
        guard let startSym = dlsym(h, "MTDeviceStart") else {
            NSLog("[MT] ✗ missing MTDeviceStart"); return
        }
        let dimsSym    = dlsym(h, "MTDeviceGetSensorDimensions")
        let familySym  = dlsym(h, "MTDeviceGetFamilyID")
        let builtInSym = dlsym(h, "MTDeviceIsBuiltIn")

        let createList = unsafeBitCast(createListSym, to: MTDeviceCreateListFn.self)
        let register   = unsafeBitCast(registerSym,   to: MTRegisterCallbackFn.self)
        let startFn    = unsafeBitCast(startSym,      to: MTDeviceStartFn.self)

        if let sym = dlsym(h, "MTUnregisterContactFrameCallback") {
            unregisterFn = unsafeBitCast(sym, to: MTUnregisterCallbackFn.self)
        }
        if let sym = dlsym(h, "MTDeviceStop") {
            stopFn = unsafeBitCast(sym, to: MTDeviceStopFn.self)
        }

        guard let arrayUnmanaged = createList() else {
            NSLog("[MT] ✗ MTDeviceCreateList returned nil")
            return
        }
        let deviceArray = arrayUnmanaged.takeRetainedValue()
        let count = CFArrayGetCount(deviceArray)
        NSLog("[MT] Found \(count) multitouch device(s)")

        activeCapture.value = self

        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(deviceArray, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)

            // Query dimensions to filter out auxiliary sensors.
            var rows: Int32 = 0
            var cols: Int32 = 0
            if let dimsSym = dimsSym {
                let getDims = unsafeBitCast(dimsSym, to: MTDeviceGetSensorDimsFn.self)
                _ = getDims(device, &rows, &cols)
            }

            var family: Int32 = 0
            if let familySym = familySym {
                let getFamily = unsafeBitCast(familySym, to: MTDeviceGetFamilyIDFn.self)
                _ = getFamily(device, &family)
            }

            var builtIn = false
            if let builtInSym = builtInSym {
                let isBuiltIn = unsafeBitCast(builtInSym, to: MTDeviceIsBuiltInFn.self)
                builtIn = isBuiltIn(device)
            }

            NSLog("[MT] Device #\(i): family=0x\(String(family, radix: 16, uppercase: false)) (\(family)) sensor=\(rows)x\(cols) builtIn=\(builtIn)")

            // Skip auxiliary sensors (e.g. the 60×2 sensor on some
            // MacBooks — possibly the haptic ring or hinge sensor).
            // The real trackpad always has at least ~18 rows.
            if rows < 10 {
                NSLog("[MT]   → SKIPPING (fewer than 10 rows — not the main trackpad)")
                continue
            }

            NSLog("[MT]   → starting")
            register(device, multitouchCallback)
            startFn(device, 0)
            devices.append(device)
        }

        NSLog("[MT] Started \(devices.count) / \(count) device(s)")
        if devices.isEmpty {
            NSLog("[MT] ✗ No suitable trackpad found — edge gestures will do nothing")
        }
        running = true
    }

    public func stop() {
        guard running else { return }
        running = false
        if let unregisterFn, let stopFn {
            for device in devices {
                unregisterFn(device, multitouchCallback)
                stopFn(device)
            }
        }
        devices.removeAll()
        activeCapture.value = nil
    }

    // MARK: - Frame processing (called from C callback, dispatched to main)

    fileprivate func processRawFrame(
        data: UnsafePointer<MTData>?,
        nFingers: Int,
        timestamp: Double,
        frameID: Int
    ) {
        // Verbose log for the first few frames + periodic heartbeat.
        if frameID <= 3 || frameID % 240 == 0 {
            NSLog("[MT] frame #\(frameID) fingers=\(nFingers)")
            if let data, nFingers >= 1 {
                for i in 0..<min(nFingers, 3) {
                    let t = data[i]
                    NSLog("[MT]   [\(i)] id=\(t.identifier) pos=(\(String(format: "%.3f", t.normalized.position.x)), \(String(format: "%.3f", t.normalized.position.y))) state=\(t.state) size=\(String(format: "%.2f", t.size))")
                }
            }
        }

        if nFingers == 1, let data {
            let t = data[0]
            let lifecycle = mapLifecycle(state: t.state)

            // Log every finger-landing for debug.
            if lifecycle == .beginning {
                NSLog("[MT] finger DOWN id=\(t.identifier) pos=(\(String(format: "%.3f", t.normalized.position.x)), \(String(format: "%.3f", t.normalized.position.y))) state=\(t.state)")
            }
            if lifecycle == .ending {
                NSLog("[MT] finger UP id=\(t.identifier) pos=(\(String(format: "%.3f", t.normalized.position.x)), \(String(format: "%.3f", t.normalized.position.y))) state=\(t.state)")
            }

            let sample = TouchSample(
                id: t.identifier,
                x: t.normalized.position.x,
                y: t.normalized.position.y,
                pressure: t.size,
                state: lifecycle,
                timestamp: timestamp
            )
            detector?.handle(sample: sample)
            if lifecycle == .ending {
                detector?.handleTouchEnd(id: t.identifier)
            }
        } else if nFingers == 0 {
            detector?.handleAllTouchesEnded()
        } else {
            detector?.handleMultiFinger()
        }
    }

    /// Map MT framework integer states to our three lifecycle values.
    ///   1 = starting
    ///   2 = hovering (finger close but not touching)
    ///   3 = making
    ///   4 = touching
    ///   5 = breaking
    ///   6 = lingering
    ///   7 = leaving
    private func mapLifecycle(state: Int32) -> TouchLifecycle {
        switch state {
        case 1, 3:       return .beginning
        case 4, 6:       return .touching
        case 5, 7:       return .ending
        default:         return .touching
        }
    }
}

// MARK: - C trampoline

private func multitouchCallback(
    device: Int32,
    data: UnsafeMutableRawPointer?,
    nFingers: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    // Snapshot MTData by value since we can't hold the raw pointer
    // across an async hop (MT framework may reuse its buffer).
    let n = Int(nFingers)
    let f = Int(frame)
    var copied: [MTData] = []
    if let data, n > 0 {
        let typed = data.assumingMemoryBound(to: MTData.self)
        copied = Array(UnsafeBufferPointer(start: typed, count: n))
    }

    let snapshot = copied
    DispatchQueue.main.async {
        guard let instance = activeCapture.value else { return }
        snapshot.withUnsafeBufferPointer { buf in
            instance.processRawFrame(
                data: buf.baseAddress,
                nFingers: n,
                timestamp: timestamp,
                frameID: f
            )
        }
    }
    return 0
}
