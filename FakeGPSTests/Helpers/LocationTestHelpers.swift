import CoreLocation
@testable import FakeGPS

/// Delegate perekam untuk memeriksa apa yang dikirim provider.
@MainActor
final class SpyLocationDelegate: LocationProvidingDelegate {
    private(set) var receivedLocations: [CLLocation] = []
    private(set) var receivedErrors: [Error] = []
    private(set) var receivedStatuses: [CLAuthorizationStatus] = []
    var onUpdate: ((CLLocation) -> Void)?

    func locationProvider(_ provider: any LocationProviding, didUpdateLocations locations: [CLLocation]) {
        receivedLocations.append(contentsOf: locations)
        locations.forEach { onUpdate?($0) }
    }

    func locationProvider(_ provider: any LocationProviding, didFailWithError error: Error) {
        receivedErrors.append(error)
    }

    func locationProvider(_ provider: any LocationProviding, didChangeAuthorization status: CLAuthorizationStatus) {
        receivedStatuses.append(status)
    }
}

/// Stub sederhana untuk menggantikan `RealLocationManager` di test.
@MainActor
final class StubLocationProvider: LocationProviding {
    weak var delegate: (any LocationProvidingDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private(set) var isUpdatingLocation = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        isUpdatingLocation = true
        startCount += 1
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
        stopCount += 1
    }

    func emit(_ coordinate: CLLocationCoordinate2D) {
        delegate?.locationProvider(self, didUpdateLocations: [
            CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        ])
    }
}

enum TestCoordinates {
    static let office = CLLocationCoordinate2D(latitude: Geofence.office.latitude, longitude: Geofence.office.longitude)
    /// ±1.1 km di utara kantor (di luar geofence 150 m).
    static let north1km = CLLocationCoordinate2D(latitude: Geofence.office.latitude + 0.01, longitude: Geofence.office.longitude)
    static let monas = CLLocationCoordinate2D(latitude: -6.1754, longitude: 106.8272)
}
