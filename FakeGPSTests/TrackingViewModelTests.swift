import CoreLocation
import XCTest
@testable import FakeGPS

/// Contoh unit test logic yang bergantung pada lokasi, memakai `MockLocationManager`.
@MainActor
final class TrackingViewModelTests: XCTestCase {

    func test_startTracking_whenAuthorized_startsUpdates() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)

        sut.startTracking()

        XCTAssertTrue(sut.isTracking)
        XCTAssertTrue(mock.isUpdatingLocation)
    }

    func test_startTracking_whenNotDetermined_requestsPermissionThenStarts() {
        let mock = MockLocationManager(authorizationStatus: .notDetermined)
        let sut = TrackingViewModel(locationProvider: mock)

        sut.startTracking()

        // MockLocationManager otomatis "mengizinkan" saat diminta.
        XCTAssertEqual(sut.authorizationStatus, .authorizedWhenInUse)
        XCTAssertTrue(sut.isTracking)
        XCTAssertTrue(mock.isUpdatingLocation)
    }

    func test_startTracking_whenDenied_showsError() {
        let mock = MockLocationManager(authorizationStatus: .denied)
        let sut = TrackingViewModel(locationProvider: mock)

        sut.startTracking()

        XCTAssertFalse(sut.isTracking)
        XCTAssertNotNil(sut.errorMessage)
    }

    func test_permissionRevokedWhileTracking_stopsTracking() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)
        sut.startTracking()

        mock.simulateAuthorizationChange(to: .denied)

        XCTAssertFalse(sut.isTracking)
        XCTAssertFalse(mock.isUpdatingLocation)
    }

    func test_locationInsideOffice_isInsideGeofence() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)
        sut.startTracking()

        mock.setLocation(TestCoordinates.office)

        XCTAssertTrue(sut.isInsideGeofence)
        XCTAssertEqual(sut.geofenceEvents, [.entered])
    }

    func test_routeLeavingOffice_emitsEnterThenExit() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)
        sut.startTracking()

        mock.startRoute(
            waypoints: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 20,
            updateInterval: 5,
            autoAdvance: false
        )
        while mock.advanceRoute() != nil {}

        XCTAssertFalse(sut.isInsideGeofence)
        XCTAssertEqual(sut.geofenceEvents, [.entered, .exited])
        XCTAssertEqual(sut.totalDistance, 1_106, accuracy: 15)
    }

    func test_inaccurateLocations_areIgnored() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock, maximumAcceptedAccuracy: 50)
        sut.startTracking()

        mock.setLocation(TestCoordinates.monas, horizontalAccuracy: 500)
        mock.send(CLLocation(
            coordinate: TestCoordinates.monas, altitude: 0,
            horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date()
        ))

        XCTAssertNil(sut.currentLocation)
        XCTAssertEqual(sut.totalDistance, 0)
    }

    func test_distanceAccumulatesBetweenUpdates() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)
        sut.startTracking()

        mock.setLocation(TestCoordinates.office)
        mock.setLocation(TestCoordinates.north1km)
        mock.setLocation(TestCoordinates.office)

        XCTAssertEqual(sut.totalDistance, 2 * 1_106, accuracy: 20)
    }

    func test_stopTracking_ignoresFurtherUpdates() {
        let mock = MockLocationManager()
        let sut = TrackingViewModel(locationProvider: mock)
        sut.startTracking()
        mock.setLocation(TestCoordinates.office)

        sut.stopTracking()
        mock.setLocation(TestCoordinates.north1km)

        XCTAssertEqual(sut.currentLocation?.coordinate.latitude ?? 0, TestCoordinates.office.latitude, accuracy: 1e-9)
    }
}
