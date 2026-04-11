// EdgeDetectorTests.swift
//
// Unit tests for the pure-logic edge detection state machine.
// Uses synthetic TouchSamples — no system APIs, no multitouch framework.

import XCTest
@testable import EdgePad

@MainActor
final class EdgeDetectorTests: XCTestCase {

    private var detector: EdgeDetector!
    private var delegate: MockDelegate!

    override func setUp() async throws {
        detector = EdgeDetector()
        delegate = MockDelegate()
        detector.delegate = delegate
    }

    // MARK: - Helpers

    private func sample(x: Float, y: Float, id: Int32 = 1, state: TouchLifecycle = .touching) -> TouchSample {
        TouchSample(id: id, x: x, y: y, pressure: 0.5, state: state, timestamp: 0)
    }

    // MARK: - Tests

    func testTouchInCenterDoesNotTriggerDrag() {
        detector.handle(sample: sample(x: 0.5, y: 0.5))
        detector.handle(sample: sample(x: 0.55, y: 0.55))
        XCTAssertEqual(delegate.beginCalls.count, 0)
        XCTAssertEqual(delegate.updateCalls.count, 0)
    }

    func testLeftEdgeTouchDoesNotEmitUntilDeadZoneCleared() {
        detector.handle(sample: sample(x: 0.05, y: 0.50))
        XCTAssertEqual(delegate.beginCalls.count, 0, "No begin until we pass the dead zone")
        detector.handle(sample: sample(x: 0.05, y: 0.505))
        XCTAssertEqual(delegate.beginCalls.count, 0, "0.5% travel is still below dead zone")
        detector.handle(sample: sample(x: 0.05, y: 0.52))
        XCTAssertEqual(delegate.beginCalls.count, 1, "Crossed the dead zone")
        XCTAssertEqual(delegate.beginCalls.first?.0, .left)
    }

    func testLeftEdgeDragEmitsUpdates() {
        detector.handle(sample: sample(x: 0.05, y: 0.50))
        detector.handle(sample: sample(x: 0.05, y: 0.55))
        detector.handle(sample: sample(x: 0.05, y: 0.60))
        XCTAssertEqual(delegate.beginCalls.count, 1)
        XCTAssertGreaterThanOrEqual(delegate.updateCalls.count, 1)
        XCTAssertEqual(delegate.updateCalls.last?.edge, .left)
    }

    func testDragContinuesWhenFingerLeavesEdgeZone() {
        detector.handle(sample: sample(x: 0.05, y: 0.50))
        detector.handle(sample: sample(x: 0.05, y: 0.55))     // starts real drag
        detector.handle(sample: sample(x: 0.30, y: 0.60))     // left the edge strip
        XCTAssertEqual(delegate.beginCalls.count, 1)
        XCTAssertGreaterThanOrEqual(delegate.updateCalls.count, 2)
    }

    func testMultiFingerCancelsActiveDrag() {
        detector.handle(sample: sample(x: 0.05, y: 0.50))
        detector.handle(sample: sample(x: 0.05, y: 0.55))
        detector.handleMultiFinger()
        XCTAssertEqual(delegate.endCalls.count, 1)
    }

    func testTouchEndEmitsEndForActiveDrag() {
        detector.handle(sample: sample(x: 0.05, y: 0.50))
        detector.handle(sample: sample(x: 0.05, y: 0.55))
        detector.handleTouchEnd(id: 1)
        XCTAssertEqual(delegate.endCalls.count, 1)
    }

    func testTouchEndOnIdleDoesNothing() {
        detector.handleTouchEnd(id: 1)
        XCTAssertEqual(delegate.endCalls.count, 0)
    }

    func testTopEdgeUsesHorizontalAxis() {
        detector.handle(sample: sample(x: 0.50, y: 0.95))
        detector.handle(sample: sample(x: 0.60, y: 0.95))   // horizontal motion → top edge axis
        XCTAssertEqual(delegate.beginCalls.first?.0, .top)
    }
}

@MainActor
final class MockDelegate: EdgeDetectorDelegate {
    var beginCalls: [(TrackpadEdge, Float)] = []
    var updateCalls: [EdgeDragEvent] = []
    var endCalls: [TrackpadEdge] = []

    func edgeDetector(_ d: EdgeDetector, didBeginDragOn edge: TrackpadEdge, at position: Float) {
        beginCalls.append((edge, position))
    }
    func edgeDetector(_ d: EdgeDetector, didUpdate event: EdgeDragEvent) {
        updateCalls.append(event)
    }
    func edgeDetector(_ d: EdgeDetector, didEndDragOn edge: TrackpadEdge) {
        endCalls.append(edge)
    }
}
