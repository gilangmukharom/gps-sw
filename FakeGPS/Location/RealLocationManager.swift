import CoreLocation

/// Implementasi `LocationProviding` yang memakai `CLLocationManager` asli.
///
/// Ini satu-satunya provider yang ikut ke build Release. Lokasi yang disimulasikan
/// oleh Xcode (GPX / Debug > Simulate Location) dan `XCUIDevice.shared.location`
/// juga masuk lewat class ini, karena keduanya bekerja di level sistem.
@MainActor
final class RealLocationManager: NSObject, LocationProviding {
    weak var delegate: (any LocationProvidingDelegate)?
    private(set) var isUpdatingLocation = false

    private let manager: CLLocationManager

    init(
        desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest,
        distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    ) {
        manager = CLLocationManager()
        super.init()
        manager.desiredAccuracy = desiredAccuracy
        manager.distanceFilter = distanceFilter
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        isUpdatingLocation = true
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
        manager.stopUpdatingLocation()
    }
}

extension RealLocationManager: CLLocationManagerDelegate {
    // CLLocationManager memanggil delegate di thread tempat ia dibuat (main),
    // tapi protocol-nya nonisolated, jadi kita hop eksplisit ke MainActor.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.locationProvider(self, didUpdateLocations: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.locationProvider(self, didFailWithError: error)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.locationProvider(self, didChangeAuthorization: status)
        }
    }
}
