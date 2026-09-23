import CoreLocation
import Foundation

/// Composition root: satu-satunya tempat yang memutuskan provider lokasi mana yang dipakai.
///
/// - Release: selalu `RealLocationManager`. Kode mock tidak ikut terkompilasi (`#if DEBUG`).
/// - Debug: `SwitchableLocationProvider` (GPS asli <-> fake GPS), dikontrol oleh
///   launch argument atau pilihan terakhir di layar debug.
@MainActor
final class AppEnvironment {
    let locationProvider: any LocationProviding

    #if DEBUG
    let switchableLocation: SwitchableLocationProvider
    #endif

    init(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) {
        #if DEBUG
        let launch = LaunchConfiguration(arguments: arguments)
        let mock = MockLocationManager(initialCoordinate: launch.mockCoordinate)

        let storedSource = defaults.string(forKey: SwitchableLocationProvider.sourceDefaultsKey)
            .flatMap(SwitchableLocationProvider.Source.init(rawValue:))
        let switchable = SwitchableLocationProvider(
            real: RealLocationManager(),
            mock: mock,
            source: launch.forcedSource ?? storedSource ?? .real,
            // Kalau source dipaksa launch argument (UI test), jangan timpa pilihan manual developer.
            defaults: launch.forcedSource == nil ? defaults : nil
        )

        if launch.mockRoute.count >= 2 {
            mock.startRouteWhenUpdating(
                waypoints: launch.mockRoute,
                speed: launch.mockRouteSpeedKmh / 3.6,
                updateInterval: launch.mockRouteInterval
            )
        }

        switchableLocation = switchable
        locationProvider = switchable
        #else
        locationProvider = RealLocationManager()
        #endif
    }
}

#if DEBUG
/// Launch argument yang dikenali di build DEBUG.
///
/// | Argument                                   | Efek                                         |
/// |--------------------------------------------|----------------------------------------------|
/// | `-UITest_MockLocation`                     | Paksa pakai fake GPS                         |
/// | `-UITest_RealLocation`                     | Paksa pakai GPS asli (untuk XCUIDevice/GPX)  |
/// | `-MockLocation_Coordinate <lat,lon>`       | Koordinat awal fake GPS                      |
/// | `-MockLocation_Route <lat,lon;lat,lon;...>`| Langsung jalankan simulasi rute              |
/// | `-MockLocation_SpeedKmh <angka>`           | Kecepatan rute (default 40)                  |
/// | `-MockLocation_Interval <detik>`           | Interval update rute (default 1)             |
struct LaunchConfiguration {
    static let mockLocation = "-UITest_MockLocation"
    static let realLocation = "-UITest_RealLocation"
    static let coordinate = "-MockLocation_Coordinate"
    static let route = "-MockLocation_Route"
    static let speedKmh = "-MockLocation_SpeedKmh"
    static let interval = "-MockLocation_Interval"

    var forcedSource: SwitchableLocationProvider.Source?
    var mockCoordinate: CLLocationCoordinate2D?
    var mockRoute: [CLLocationCoordinate2D] = []
    var mockRouteSpeedKmh: Double = 40
    var mockRouteInterval: TimeInterval = 1

    init(arguments: [String]) {
        if arguments.contains(Self.mockLocation) {
            forcedSource = .mock
        } else if arguments.contains(Self.realLocation) {
            forcedSource = .real
        }

        func value(after key: String) -> String? {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }

        mockCoordinate = value(after: Self.coordinate).flatMap(CLLocationCoordinate2D.init(parsing:))
        mockRoute = value(after: Self.route)?
            .split(separator: ";")
            .compactMap { CLLocationCoordinate2D(parsing: String($0)) } ?? []
        if let speed = value(after: Self.speedKmh).flatMap(Double.init), speed > 0 {
            mockRouteSpeedKmh = speed
        }
        if let interval = value(after: Self.interval).flatMap(Double.init), interval > 0 {
            mockRouteInterval = interval
        }

        // Rute tanpa koordinat awal -> mulai dari waypoint pertama.
        if mockCoordinate == nil { mockCoordinate = mockRoute.first }
    }
}
#endif
