// MediaRemote.swift
//
// Slim Swift binding to the private MediaRemote.framework — write side
// only. The read side (`MRMediaRemoteGetNowPlayingInfo`) is TCC-gated
// for non-Apple-signed processes on macOS 15.4+ and returns nil dicts;
// we don't bother with it. The write side (`MRMediaRemoteSendCommand`)
// still works on macOS 26 and is the same channel that powers media
// keys, AirPods controls, and Control Center transport buttons.
//
// Used by MediaController to scrub timelines on any site / app that
// publishes a Now Playing source — YouTube, X, LinkedIn, Twitch, Apple
// Music, Podcasts, Apple TV, Spotify, embedded HTML5 video, etc. Each
// edge-travel "step" fires a discrete SkipForward15 / GoBack15.
//
// Loaded via dlopen at first use, like BrightnessController.

import Darwin
import Foundation

/// Subset of MediaRemote command codes that we actually use. These are
/// stable across macOS 13–26 (sourced from MediaRemote.framework
/// reverse-engineering — see Cykey/ios-reversed-headers).
public enum MediaRemoteCommand: Int32 {
    case play              = 0
    case pause             = 1
    case togglePlayPause   = 2
    case stop              = 3
    case nextTrack         = 4
    case previousTrack     = 5
    case goBack15Seconds   = 12
    case skip15Seconds     = 13
}

public enum MediaRemote {

    private typealias SendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool

    private static let lock = NSLock()
    nonisolated(unsafe) private static var loadAttempted = false
    nonisolated(unsafe) private static var sendFn: SendCommandFn?

    /// Send a transport command to the active Now Playing source.
    /// Returns true if the call was dispatched into MediaRemote — note
    /// that the framework will report success even if the source app
    /// silently ignores the command (Spotify is known to do this for
    /// certain seek requests).
    @discardableResult
    public static func send(_ command: MediaRemoteCommand) -> Bool {
        ensureLoaded()
        return sendFn?(command.rawValue, nil) ?? false
    }

    /// True if MediaRemote loaded and the SendCommand symbol bound.
    public static var isAvailable: Bool {
        ensureLoaded()
        return sendFn != nil
    }

    private static func ensureLoaded() {
        lock.lock(); defer { lock.unlock() }
        if loadAttempted { return }
        loadAttempted = true

        // Bundle.load triggers the framework's ObjC +load and constructor
        // initializers. Loading the inner Mach-O directly via dlopen
        // skips that step on some macOS versions and the SendCommand
        // function pointer ends up un-wired. This matches NativeHUD.swift.
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = Bundle(path: path) else {
            NSLog("[MR] ✗ MediaRemote.framework not found — transport commands disabled")
            return
        }
        if !bundle.load() {
            NSLog("[MR] ✗ Bundle.load() failed for MediaRemote.framework")
            return
        }
        // After Bundle.load, the framework's symbols are linked into
        // the process; dlsym(RTLD_DEFAULT) resolves them by name.
        if let sym = dlsym(dlopen(nil, RTLD_LAZY), "MRMediaRemoteSendCommand") {
            sendFn = unsafeBitCast(sym, to: SendCommandFn.self)
            NSLog("[MR] ✓ MRMediaRemoteSendCommand bound")
        } else {
            NSLog("[MR] ✗ MRMediaRemoteSendCommand symbol missing")
        }
    }
}
