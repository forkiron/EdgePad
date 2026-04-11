// EdgeProfile.swift
//
// Types that describe what each of the 4 trackpad edges does, and two
// shipped defaults: Media and Reading.
//
// Each edge is mapped to an EdgeAction. The active profile is stored in
// AppSettings and routed by AppDelegate on each EdgeDragEvent.

import Foundation

public enum TrackpadEdge: String, Sendable, CaseIterable {
    case top
    case bottom
    case left
    case right
}

public enum EdgeAction: String, Sendable, CaseIterable {
    case volume            // left edge in both profiles
    case brightness        // right edge in Media
    case mediaScrub        // top edge in both profiles
    case scrollVertical    // right edge in Reading (replaces brightness)
    case scrollHorizontal  // bottom edge in both profiles
    case disabled
}

public struct EdgeProfile: Sendable, Equatable {
    public var top: EdgeAction
    public var bottom: EdgeAction
    public var left: EdgeAction
    public var right: EdgeAction

    public init(top: EdgeAction, bottom: EdgeAction, left: EdgeAction, right: EdgeAction) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public func action(for edge: TrackpadEdge) -> EdgeAction {
        switch edge {
        case .top:    return top
        case .bottom: return bottom
        case .left:   return left
        case .right:  return right
        }
    }

    /// Default media-consumption profile. The app ships with this as the
    /// active profile on first launch.
    ///
    /// - Top:    media scrub (arrow keys to focused app)
    /// - Left:   volume
    /// - Right:  brightness
    /// - Bottom: horizontal scroll
    public static let media = EdgeProfile(
        top: .mediaScrub,
        bottom: .scrollHorizontal,
        left: .volume,
        right: .brightness
    )

    /// Accessibility-focused profile for reading zoomed content. The
    /// right edge swaps from brightness to vertical scroll — bottom
    /// stays as horizontal scroll — giving zoomed PDFs / Safari /
    /// macOS Accessibility Zoom a dedicated pan input.
    public static let reading = EdgeProfile(
        top: .mediaScrub,
        bottom: .scrollHorizontal,
        left: .volume,
        right: .scrollVertical
    )
}

public enum EdgeProfilePreset: String, CaseIterable, Sendable {
    case media
    case reading

    public var profile: EdgeProfile {
        switch self {
        case .media:   return .media
        case .reading: return .reading
        }
    }

    public var displayName: String {
        switch self {
        case .media:   return "Media"
        case .reading: return "Reading"
        }
    }
}
