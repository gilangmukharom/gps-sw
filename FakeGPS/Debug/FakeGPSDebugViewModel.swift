#if DEBUG
import Combine
import CoreLocation
import Foundation

struct RouteWaypoint: Identifiable, Equatable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: RouteWaypoint, rhs: RouteWaypoint) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

@MainActor
final class FakeGPSDebugViewModel: ObservableObject {
    enum MapTapMode: String, CaseIterable, Identifiable {
        case pickPoint = "Pilih titik"
        case addWaypoint = "Tambah waypoint"

        var id: String { rawValue }
    }

    let provider: SwitchableLocationProvider
    var mock: MockLocationManager { provider.mock }

    @Published var tapMode: MapTapMode = .pickPoint
    @Published private(set) var pickedCoordinate: CLLocationCoordinate2D?
    @Published var latitudeText = ""
    @Published var longitudeText = ""
    @Published private(set) var inputError: String?

    @Published var waypoints: [RouteWaypoint] = []
    @Published var speedKmh: Double = 40
    @Published var updateInterval: Double = 1
    @Published var loopRoute = false

    @Published private(set) var recenterRequest: MapRecenterRequest?
    @Published private(set) var exportedGPXURL: URL?
    @Published private(set) var exportError: String?

    private var cancellables: Set<AnyCancellable> = []

    init(provider: SwitchableLocationProvider) {
        self.provider = provider
        // Teruskan perubahan provider & mock supaya view ikut ter-refresh.
        provider.objectWillChange
            .merge(with: provider.mock.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if let current = provider.mock.currentLocation?.coordinate {
            fillInputs(with: current)
        }
    }

    // MARK: - Source

    var isMockActive: Bool { provider.source == .mock }

    func setSource(_ source: SwitchableLocationProvider.Source) {
        provider.setSource(source)
    }

    // MARK: - Peta & input manual

    func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        switch tapMode {
        case .pickPoint:
            pick(coordinate)
        case .addWaypoint:
            waypoints.append(RouteWaypoint(coordinate: coordinate))
            exportedGPXURL = nil
        }
    }

    func pick(_ coordinate: CLLocationCoordinate2D) {
        pickedCoordinate = coordinate
        fillInputs(with: coordinate)
        inputError = nil
    }

    func applyManualInput() {
        guard let coordinate = CLLocationCoordinate2D(latitudeText: latitudeText, longitudeText: longitudeText) else {
            inputError = "Format salah. Latitude -90…90, longitude -180…180 (contoh: -6.1754 / 106.8272)."
            return
        }
        pick(coordinate)
        recenterRequest = MapRecenterRequest(coordinate: coordinate)
        applyPickedLocation()
    }

    func applyPickedLocation() {
        guard let pickedCoordinate else { return }
        activateMock()
        mock.setLocation(pickedCoordinate)
    }

    func apply(_ preset: LocationPreset) {
        pick(preset.coordinate)
        recenterRequest = MapRecenterRequest(coordinate: preset.coordinate)
        applyPickedLocation()
    }

    // MARK: - Rute

    func addPickedAsWaypoint() {
        guard let pickedCoordinate else { return }
        waypoints.append(RouteWaypoint(coordinate: pickedCoordinate))
        exportedGPXURL = nil
    }

    func addPresetAsWaypoint(_ preset: LocationPreset) {
        waypoints.append(RouteWaypoint(coordinate: preset.coordinate))
        exportedGPXURL = nil
    }

    func removeWaypoints(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        exportedGPXURL = nil
    }

    func moveWaypoints(from source: IndexSet, to destination: Int) {
        waypoints.move(fromOffsets: source, toOffset: destination)
        exportedGPXURL = nil
    }

    func clearWaypoints() {
        waypoints.removeAll()
        exportedGPXURL = nil
    }

    var canStartRoute: Bool { waypoints.count >= 2 }

    func startRoute() {
        guard canStartRoute else { return }
        activateMock()
        mock.startRoute(
            waypoints: waypoints.map(\.coordinate),
            speed: speedKmh / 3.6,
            updateInterval: updateInterval,
            loop: loopRoute
        )
    }

    func stopRoute() {
        mock.stopRoute()
    }

    var routeDistance: CLLocationDistance {
        RouteInterpolator.totalDistance(of: waypoints.map(\.coordinate))
    }

    var estimatedDuration: TimeInterval {
        speedKmh > 0 ? routeDistance / (speedKmh / 3.6) : 0
    }

    // MARK: - GPX

    func exportGPX() {
        exportError = nil
        let coordinates: [CLLocationCoordinate2D]
        if waypoints.count >= 2 {
            coordinates = waypoints.map(\.coordinate)
        } else if let single = pickedCoordinate ?? mock.currentLocation?.coordinate {
            coordinates = [single]
        } else {
            exportError = "Pilih lokasi atau buat minimal 2 waypoint dulu."
            return
        }

        let stamp = Self.fileStamp.string(from: Date())
        let document = coordinates.count == 1
            ? GPXGenerator.singleLocation(coordinates[0], name: "FakeGPS \(stamp)")
            : GPXGenerator.routeDocument(name: "FakeGPS Route \(stamp)", waypoints: coordinates, speed: speedKmh / 3.6)

        do {
            exportedGPXURL = try GPXGenerator.write(document, fileName: "FakeGPS-\(stamp)")
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func activateMock() {
        if provider.source != .mock { provider.setSource(.mock) }
    }

    private func fillInputs(with coordinate: CLLocationCoordinate2D) {
        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
#endif
