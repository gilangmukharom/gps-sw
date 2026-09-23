import CoreLocation
import Foundation

/// Contoh consumer lokasi: tracking jarak tempuh + deteksi masuk/keluar geofence.
/// Hanya bergantung pada `LocationProviding`, jadi bisa di-test dengan `MockLocationManager`.
@MainActor
final class TrackingViewModel: ObservableObject {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var totalDistance: CLLocationDistance = 0
    @Published private(set) var isTracking = false
    @Published private(set) var isInsideGeofence = false
    @Published private(set) var geofenceEvents: [GeofenceEvent] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    let geofence: Geofence
    /// Lokasi dengan akurasi lebih buruk dari ini (meter) diabaikan.
    let maximumAcceptedAccuracy: CLLocationAccuracy

    private let locationProvider: any LocationProviding
    private var startWhenAuthorized = false

    init(
        locationProvider: any LocationProviding,
        geofence: Geofence = .office,
        maximumAcceptedAccuracy: CLLocationAccuracy = 50
    ) {
        self.locationProvider = locationProvider
        self.geofence = geofence
        self.maximumAcceptedAccuracy = maximumAcceptedAccuracy
        self.authorizationStatus = locationProvider.authorizationStatus
        locationProvider.delegate = self
    }

    func startTracking() {
        errorMessage = nil
        switch locationProvider.authorizationStatus {
        case .notDetermined:
            startWhenAuthorized = true
            locationProvider.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Izin lokasi ditolak. Aktifkan di Settings."
        default:
            beginUpdates()
        }
    }

    func stopTracking() {
        startWhenAuthorized = false
        isTracking = false
        locationProvider.stopUpdatingLocation()
    }

    func resetTrip() {
        totalDistance = 0
        geofenceEvents = []
    }

    private func beginUpdates() {
        isTracking = true
        locationProvider.startUpdatingLocation()
    }

    private func handle(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumAcceptedAccuracy
        else { return }

        if let previous = currentLocation {
            totalDistance += location.distance(from: previous)
        }
        currentLocation = location

        let inside = geofence.contains(location)
        if inside != isInsideGeofence {
            isInsideGeofence = inside
            geofenceEvents.append(inside ? .entered : .exited)
        }
    }
}

extension TrackingViewModel: LocationProvidingDelegate {
    func locationProvider(_ provider: any LocationProviding, didUpdateLocations locations: [CLLocation]) {
        locations.forEach(handle)
    }

    func locationProvider(_ provider: any LocationProviding, didFailWithError error: Error) {
        // locationUnknown bersifat sementara; CoreLocation akan terus mencoba.
        if (error as? CLError)?.code == .locationUnknown { return }
        errorMessage = error.localizedDescription
    }

    func locationProvider(_ provider: any LocationProviding, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status.isAuthorized, startWhenAuthorized {
            startWhenAuthorized = false
            beginUpdates()
        } else if status == .denied || status == .restricted {
            startWhenAuthorized = false
            if isTracking { stopTracking() }
            errorMessage = "Izin lokasi ditolak. Aktifkan di Settings."
        }
    }
}
