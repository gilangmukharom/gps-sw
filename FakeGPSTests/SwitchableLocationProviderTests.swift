import CoreLocation
import XCTest
@testable import FakeGPS

@MainActor
final class SwitchableLocationProviderTests: XCTestCase {
    private var real: StubLocationProvider!
    private var mock: MockLocationManager!
    private var spy: SpyLocationDelegate!

    override func setUp() async throws {
        real = StubLocationProvider()
        mock = MockLocationManager()
        spy = SpyLocationDelegate()
    }

    private func makeSUT(source: SwitchableLocationProvider.Source) -> SwitchableLocationProvider {
        let sut = SwitchableLocationProvider(real: real, mock: mock, source: source, defaults: nil)
        sut.delegate = spy
        return sut
    }

    func test_forwardsOnlyActiveSource() {
        let sut = makeSUT(source: .real)
        sut.startUpdatingLocation()

        mock.setLocation(TestCoordinates.monas)   // diabaikan
        real.emit(TestCoordinates.office)          // diteruskan

        XCTAssertEqual(spy.receivedLocations.count, 1)
        XCTAssertEqual(spy.receivedLocations[0].coordinate.latitude, TestCoordinates.office.latitude, accuracy: 1e-9)
    }

    func test_switchingWhileUpdating_movesUpdatesToNewSource() {
        let sut = makeSUT(source: .real)
        sut.startUpdatingLocation()

        sut.setSource(.mock)
        mock.setLocation(TestCoordinates.monas)

        XCTAssertEqual(real.stopCount, 1)
        XCTAssertTrue(mock.isUpdatingLocation)
        XCTAssertEqual(spy.receivedLocations.last?.coordinate.latitude ?? 0, TestCoordinates.monas.latitude, accuracy: 1e-9)
    }

    func test_setSource_persistsChoice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        let sut = SwitchableLocationProvider(real: real, mock: mock, source: .real, defaults: defaults)

        sut.setSource(.mock)

        XCTAssertEqual(defaults.string(forKey: SwitchableLocationProvider.sourceDefaultsKey), "mock")
    }

    func test_launchConfiguration_parsesArguments() {
        let config = LaunchConfiguration(arguments: [
            "FakeGPS",
            "-UITest_MockLocation",
            "-MockLocation_Route", "-6.131336,106.644936;-6.121336,106.644936",
            "-MockLocation_SpeedKmh", "120",
            "-MockLocation_Interval", "0.5",
        ])

        XCTAssertEqual(config.forcedSource, .mock)
        XCTAssertEqual(config.mockRoute.count, 2)
        XCTAssertEqual(config.mockRouteSpeedKmh, 120)
        XCTAssertEqual(config.mockRouteInterval, 0.5)
        XCTAssertEqual(config.mockCoordinate?.latitude ?? 0, -6.131336, accuracy: 1e-9)
    }

    func test_coordinateParsing() {
        XCTAssertNotNil(CLLocationCoordinate2D(parsing: "-6.1754, 106.8272"))
        XCTAssertNotNil(CLLocationCoordinate2D(latitudeText: "-6,1754", longitudeText: "106,8272"))
        XCTAssertNil(CLLocationCoordinate2D(parsing: "91,0"))
        XCTAssertNil(CLLocationCoordinate2D(parsing: "abc"))
    }
}
