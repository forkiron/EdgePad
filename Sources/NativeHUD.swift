// NativeHUD.swift
//
// Triggers the real macOS volume/brightness HUD by calling
// `[OSDManager sharedManager] showImage:onDisplayID:priority:msecUntilFade:
//   filledChiclets:totalChiclets:locked:]` from the private OSD.framework.
//
// This is the exact API the system itself uses when you press F1/F2 or
// F11/F12, so the overlay we render is — by definition — pixel-identical
// to Apple's native HUD on whatever macOS version the user is running.
// No bespoke window, no glyph approximation, no "looks-like" overlay.

import AppKit
import CoreGraphics
import ObjectiveC

@MainActor
public enum NativeHUD {

    // OSDManager image identifiers (private). These are stable across at
    // least macOS 11–15. Higher values exist for eject, kbd-brightness, etc.
    public static let graphicBrightness: Int64 = 1
    public static let graphicSound:      Int64 = 3
    public static let graphicSoundMute:  Int64 = 4

    // The native HUD draws 16 chiclets for both volume and brightness.
    private static let totalChiclets: UInt32 = 16
    private static let priority:      UInt32 = 0x1F4
    private static let fadeMsec:      UInt32 = 1000

    private typealias SharedManagerIMP = @convention(c) (AnyClass, Selector) -> AnyObject
    private typealias ShowImageIMP = @convention(c) (
        AnyObject, Selector,
        Int64,   // graphic
        UInt32,  // displayID
        UInt32,  // priority
        UInt32,  // msecUntilFade
        UInt32,  // filledChiclets
        UInt32,  // totalChiclets
        Bool     // locked
    ) -> Void

    private static var manager: AnyObject?
    private static var showSelector: Selector?
    private static var showIMP: ShowImageIMP?
    private static var loadAttempted = false
    private static var loadSucceeded = false

    public static func showVolume(_ value: Float) {
        post(graphic: graphicSound, value: value)
    }

    public static func showBrightness(_ value: Float) {
        post(graphic: graphicBrightness, value: value)
    }

    private static func post(graphic: Int64, value: Float) {
        guard ensureLoaded(),
              let manager,
              let showSelector,
              let showIMP else { return }

        let clamped = max(0, min(1, value))
        let filled = UInt32((Double(clamped) * Double(totalChiclets)).rounded())
        let displayID = UInt32(CGMainDisplayID())

        showIMP(manager, showSelector,
                graphic, displayID, priority, fadeMsec,
                filled, totalChiclets, false)
    }

    @discardableResult
    public static func ensureLoaded() -> Bool {
        if loadAttempted { return loadSucceeded }
        loadAttempted = true

        let path = "/System/Library/PrivateFrameworks/OSD.framework"
        guard let bundle = Bundle(path: path) else {
            NSLog("[HUD] ✗ OSD.framework not found at \(path) — HUD disabled")
            return false
        }
        if !bundle.load() {
            NSLog("[HUD] ✗ Bundle.load() failed for OSD.framework — HUD disabled")
            return false
        }
        guard let cls = NSClassFromString("OSDManager") else {
            NSLog("[HUD] ✗ OSDManager class not present in OSD.framework — Apple may have renamed it; HUD disabled")
            return false
        }

        let sharedSel = NSSelectorFromString("sharedManager")
        guard let sharedMethod = class_getClassMethod(cls, sharedSel) else {
            NSLog("[HUD] ✗ +[OSDManager sharedManager] not found — HUD disabled")
            return false
        }
        let sharedIMP = unsafeBitCast(method_getImplementation(sharedMethod), to: SharedManagerIMP.self)
        let mgr = sharedIMP(cls, sharedSel)

        let showSel = NSSelectorFromString(
            "showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
        )
        guard let showMethod = class_getInstanceMethod(cls, showSel) else {
            NSLog("[HUD] ✗ -[OSDManager \(showSel)] not found — Apple may have changed the signature; HUD disabled")
            return false
        }
        let imp = unsafeBitCast(method_getImplementation(showMethod), to: ShowImageIMP.self)

        manager = mgr
        showSelector = showSel
        showIMP = imp
        loadSucceeded = true
        NSLog("[HUD] ✓ OSDManager loaded — using native macOS HUD")
        return true
    }

    /// True if the native HUD is wired up and calls will succeed.
    public static var isAvailable: Bool {
        ensureLoaded()
        return loadSucceeded
    }
}
