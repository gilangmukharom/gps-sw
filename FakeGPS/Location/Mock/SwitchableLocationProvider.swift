#if DEBUG
import Combine
import CoreLocation
import Foundation

/// Provider yang bisa berpindah antara GPS asli dan GPS palsu saat runtime.
/// Dipakai di build DEBUG supaya layar debug bisa menyalakan/mematikan fake GPS
/// tanpa restart app. Di build Release, app langsung memakai `RealLocationManager`.
@MainActor
final class SwitchableLocationProvider: ObservableObject, LocationProviding {
    enum Source: String, CaseIterable, Identifiable {
        case real
        case mock

        var id: String { rawValue }

        var title: String {
            switch self {
            case .real: return "GPS asli"
            case .mock: return "Fake GPS"
            }
        }
    }

    static let sourceDefaultsKey = "FakeGPS.locationSource"

    weak var delegate: (any LocationProvidingDelegate)?

    let real: any LocationProviding
    let mock: MockLocationManager

    @Published private(set) var source: Source
    private(set) var isUpdatingLocation = false

    /// `nil` = jangan simpan pilihan (misalnya saat source dipaksa oleh launch argument).
    private let defaults: UserDefaults?

    init(real: any LocationProviding, mock: MockLocationManager, source: Source, defaults: UserDefaults? = .standard) {
        self.real = real
        self.mock = mock
        self.source = source
        self.defaults = defaults
        real.delegate = self
        mock.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        active.authorizationStatus
    }

    func setSource(_ newSource: Source) {
        guard newSource != source else { return }

        if isUpdatingLocation { active.stopUpdatingLocation() }
        source = newSource
        defaults?.set(newSource.rawValue, forKey: Self.sourceDefaultsKey)
        if isUpdatingLocation { active.startUpdatingLocation() }

        delegate?.locationProvider(self, didChangeAuthorization: authorizationStatus)
    }

    func requestWhenInUseAuthorization() {
        active.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        isUpdatingLocation = true
        active.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
        active.stopUpdatingLocation()
    }

    private var active: any LocationProviding {
        switch source {
        case .real: return real
        case .mock: return mock
        }
    }
}

extension SwitchableLocationProvider: LocationProvidingDelegate {
    // Hanya teruskan event dari source yang sedang aktif.

    func locationProvider(_ provider: any LocationProviding, didUpdateLocations locations: [CLLocation]) {
        guard provider === active else { return }
        delegate?.locationProvider(self, didUpdateLocations: locations)
    }

    func locationProvider(_ provider: any LocationProviding, didFailWithError error: Error) {
        guard provider === active else { return }
        delegate?.locationProvider(self, didFailWithError: error)
    }

    func locationProvider(_ provider: any LocationProviding, didChangeAuthorization status: CLAuthorizationStatus) {
        guard provider === active else { return }
        delegate?.locationProvider(self, didChangeAuthorization: status)
    }
}
#endif
