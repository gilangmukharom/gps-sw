import CoreLocation
import XCTest
@testable import FakeGPS

@MainActor
final class MockLocationManagerTests: XCTestCase {
    private var mock: MockLocationManager!
    private var spy: SpyLocationDelegate!

    override func setUp() async throws {
        mock = MockLocationManager()
        spy = SpyLocationDelegate()
        mock.delegate = spy
    }

    func test_setLocation_whileUpdating_notifiesDelegate() {
        mock.startUpdatingLocation()

        mock.setLocation(TestCoordinates.monas)

        XCTAssertEqual(spy.receivedLocations.count, 1)
        XCTAssertEqual(spy.receivedLocations[0].coordinate.latitude, -6.1754, accuracy: 1e-9)
        XCTAssertEqual(spy.receivedLocations[0].coordinate.longitude, 106.8272, accuracy: 1e-9)
    }

    func test_setLocation_whileStopped_isDeliveredOnStart() {
        mock.setLocation(TestCoordinates.monas)
        XCTAssertTrue(spy.receivedLocations.isEmpty)

        mock.startUpdatingLocation()

        XCTAssertEqual(spy.receivedLocations.count, 1)
    }

    func test_stopUpdating_stopsDelivery() {
        mock.startUpdatingLocation()
        mock.stopUpdatingLocation()

        mock.setLocation(TestCoordinates.monas)

        XCTAssertTrue(spy.receivedLocations.isEmpty)
        XCTAssertNotNil(mock.currentLocation, "Lokasi tetap disimpan walau tidak dikirim")
    }

    func test_route_manualAdvance_emitsInterpolatedSamplesAndFinishes() throws {
        mock.startUpdatingLocation()

        // ±1.1 km pada 36 km/j (10 m/s), interval 10 dtk -> titik tiap 100 m.
        let started = mock.startRoute(
            waypoints: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 10,
            updateInterval: 10,
            autoAdvance: false
        )
        XCTAssertTrue(started)
        XCTAssertEqual(spy.receivedLocations.count, 1, "Titik pertama langsung dikirim")

        while mock.advanceRoute() != nil {}

        XCTAssertFalse(mock.isSimulatingRoute)
        XCTAssertEqual(mock.routeProgress, 1)
        XCTAssertEqual(spy.receivedLocations.count, mock.routeSamples.count)
        XCTAssertGreaterThanOrEqual(spy.receivedLocations.count, 11)

        let last = try XCTUnwrap(spy.receivedLocations.last)
        XCTAssertEqual(last.coordinate.latitude, TestCoordinates.north1km.latitude, accuracy: 1e-6)

        // Bergerak ke utara -> course ±0°.
        XCTAssertEqual(spy.receivedLocations[1].course, 0, accuracy: 1)
        XCTAssertEqual(spy.receivedLocations[1].speed, 10, accuracy: 0.01)
    }

    func test_route_loop_restartsFromBeginning() {
        mock.startUpdatingLocation()
        mock.startRoute(
            waypoints: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 100,
            updateInterval: 10,
            loop: true,
            autoAdvance: false
        )
        let sampleCount = mock.routeSamples.count

        for _ in 0..<(sampleCount * 2) { mock.advanceRoute() }

        XCTAssertTrue(mock.isSimulatingRoute)
        XCTAssertEqual(spy.receivedLocations[sampleCount].coordinate.latitude,
                       TestCoordinates.office.latitude, accuracy: 1e-9)
    }

    func test_startRouteWhenUpdating_waitsForStartUpdating() {
        mock.startRouteWhenUpdating(waypoints: [TestCoordinates.office, TestCoordinates.north1km], speed: 10)
        XCTAssertFalse(mock.isSimulatingRoute)

        mock.startUpdatingLocation()

        XCTAssertTrue(mock.isSimulatingRoute)
        XCTAssertEqual(spy.receivedLocations.first?.coordinate.latitude ?? 0, TestCoordinates.office.latitude, accuracy: 1e-9)
        mock.stopRoute()
    }

    func test_route_withSingleWaypoint_isRejected() {
        XCTAssertFalse(mock.startRoute(waypoints: [TestCoordinates.office], speed: 10))
        XCTAssertFalse(mock.isSimulatingRoute)
    }

    func test_setLocation_stopsRunningRoute() {
        mock.startRoute(waypoints: [TestCoordinates.office, TestCoordinates.north1km], speed: 10, autoAdvance: false)

        mock.setLocation(TestCoordinates.monas)

        XCTAssertFalse(mock.isSimulatingRoute)
        XCTAssertNil(mock.advanceRoute())
    }

    func test_route_withTimer_emitsUpdatesAutomatically() async {
        mock.startUpdatingLocation()
        let expectation = expectation(description: "3 update dari timer")
        expectation.expectedFulfillmentCount = 3
        expectation.assertForOverFulfill = false
        spy.onUpdate = { _ in expectation.fulfill() }

        mock.startRoute(
            waypoints: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 50,
            updateInterval: 0.05
        )

        await fulfillment(of: [expectation], timeout: 2)
        mock.stopRoute()
    }

    func test_requestAuthorization_grantsWhenNotDetermined() {
        let mock = MockLocationManager(authorizationStatus: .notDetermined)
        mock.delegate = spy

        mock.requestWhenInUseAuthorization()

        XCTAssertEqual(mock.authorizationStatus, .authorizedWhenInUse)
        XCTAssertEqual(spy.receivedStatuses, [.authorizedWhenInUse])
    }

    func test_simulateError_forwardsToDelegate() {
        mock.simulateError(CLError(.denied))

        XCTAssertEqual((spy.receivedErrors.first as? CLError)?.code, .denied)
    }
}
