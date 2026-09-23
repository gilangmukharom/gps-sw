import CoreLocation
import XCTest
@testable import FakeGPS

final class RouteInterpolatorTests: XCTestCase {

    func test_samplesAreSpacedBySpeedTimesInterval() {
        let samples = RouteInterpolator.samples(
            along: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 10,
            interval: 5
        )

        // Jarak antar titik (kecuali titik terakhir) = 10 m/s * 5 dtk = 50 m.
        for (a, b) in zip(samples, samples.dropFirst()).dropLast() {
            XCTAssertEqual(b.distance(from: a), 50, accuracy: 0.5)
        }
    }

    func test_firstAndLastSampleMatchWaypoints() throws {
        let waypoints = [TestCoordinates.office, TestCoordinates.monas, TestCoordinates.north1km]
        let samples = RouteInterpolator.samples(along: waypoints, speed: 15, interval: 1)

        let first = try XCTUnwrap(samples.first)
        let last = try XCTUnwrap(samples.last)
        XCTAssertLessThan(first.distance(from: CLLocation(latitude: waypoints[0].latitude, longitude: waypoints[0].longitude)), 0.01)
        XCTAssertLessThan(last.distance(from: CLLocation(latitude: waypoints[2].latitude, longitude: waypoints[2].longitude)), 0.01)
        XCTAssertEqual(last.speed, 0)
    }

    func test_timestampsIncreaseByInterval() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = RouteInterpolator.samples(
            along: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 10, interval: 2, startDate: start
        )

        XCTAssertEqual(samples[0].timestamp, start)
        XCTAssertEqual(samples[3].timestamp, start.addingTimeInterval(6))
    }

    func test_bearing() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(RouteInterpolator.bearing(from: origin, to: .init(latitude: 1, longitude: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(RouteInterpolator.bearing(from: origin, to: .init(latitude: 0, longitude: 1)), 90, accuracy: 0.01)
        XCTAssertEqual(RouteInterpolator.bearing(from: origin, to: .init(latitude: -1, longitude: 0)), 180, accuracy: 0.01)
        XCTAssertEqual(RouteInterpolator.bearing(from: origin, to: .init(latitude: 0, longitude: -1)), 270, accuracy: 0.01)
    }

    func test_invalidInput() {
        XCTAssertTrue(RouteInterpolator.samples(along: [], speed: 10, interval: 1).isEmpty)
        XCTAssertEqual(RouteInterpolator.samples(along: [TestCoordinates.office], speed: 10, interval: 1).count, 1)
        XCTAssertEqual(RouteInterpolator.samples(along: [TestCoordinates.office, TestCoordinates.monas], speed: 0, interval: 1).count, 1)
    }
}
