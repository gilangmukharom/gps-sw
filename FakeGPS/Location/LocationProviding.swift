import CoreLocation

/// Callback dari sebuah `LocationProviding`. Semua callback dikirim di main actor.
@MainActor
protocol LocationProvidingDelegate: AnyObject {
    func locationProvider(_ provider: any LocationProviding, didUpdateLocations locations: [CLLocation])
    func locationProvider(_ provider: any LocationProviding, didFailWithError error: Error)
    func locationProvider(_ provider: any LocationProviding, didChangeAuthorization status: CLAuthorizationStatus)
}

extension LocationProvidingDelegate {
    func locationProvider(_ provider: any LocationProviding, didFailWithError error: Error) {}
    func locationProvider(_ provider: any LocationProviding, didChangeAuthorization status: CLAuthorizationStatus) {}
}

/// Abstraksi di atas `CLLocationManager`.
///
/// Kode app (ViewModel/Service) hanya bergantung pada protocol ini, sehingga
/// implementasinya bisa ditukar: `RealLocationManager` (GPS asli) atau
/// `MockLocationManager` (koordinat palsu, hanya ada di build DEBUG).
@MainActor
protocol LocationProviding: AnyObject {
    var delegate: (any LocationProvidingDelegate)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var isUpdatingLocation: Bool { get }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLAuthorizationStatus {
    var isAuthorized: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}
