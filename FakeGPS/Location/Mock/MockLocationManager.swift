#if DEBUG
import Combine
import CoreLocation
import Foundation

/// `LocationProviding` palsu. Hanya dikompilasi di build DEBUG.
///
/// Dua mode:
/// - **Statis**: `setLocation(_:)` mengirim satu koordinat.
/// - **Rute**: `startRoute(waypoints:speed:updateInterval:loop:)` mengirim
///   lokasi berjalan antar waypoint setiap `updateInterval` detik.
///
/// Untuk unit test, gunakan `autoAdvance: false` lalu panggil `advanceRoute()`
/// secara manual supaya test deterministik (tanpa Timer).
@MainActor
final class MockLocationManager: ObservableObject, LocationProviding {
    weak var delegate: (any LocationProvidingDelegate)?

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isUpdatingLocation = false
    @Published private(set) var currentLocation: CLLocation?

    @Published private(set) var isSimulatingRoute = false
    @Published private(set) var routeSamples: [CLLocation] = []
    @Published private(set) var routeProgress: Double = 0

    private var routeIndex = 0
    private var loopsRoute = false
    private var timer: Timer?
    private var pendingRouteStart: (() -> Void)?
    private let now: () -> Date

    init(
        initialCoordinate: CLLocationCoordinate2D? = nil,
        authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse,
        now: @escaping () -> Date = Date.init
    ) {
        self.authorizationStatus = authorizationStatus
        self.now = now
        if let initialCoordinate {
            currentLocation = Self.makeLocation(initialCoordinate, timestamp: now())
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - LocationProviding

    func requestWhenInUseAuthorization() {
        if authorizationStatus == .notDetermined {
            authorizationStatus = .authorizedWhenInUse
        }
        delegate?.locationProvider(self, didChangeAuthorization: authorizationStatus)
    }

    func startUpdatingLocation() {
        isUpdatingLocation = true
        if let pendingRouteStart {
            self.pendingRouteStart = nil
            pendingRouteStart()
        } else if let currentLocation {
            delegate?.locationProvider(self, didUpdateLocations: [restamped(currentLocation)])
        }
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
    }

    // MARK: - Lokasi statis

    /// Set koordinat palsu. Menghentikan simulasi rute yang sedang berjalan.
    func setLocation(_ coordinate: CLLocationCoordinate2D, horizontalAccuracy: CLLocationAccuracy = 5) {
        stopRoute()
        publish(Self.makeLocation(coordinate, horizontalAccuracy: horizontalAccuracy, timestamp: now()))
    }

    func setLocation(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        setLocation(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    /// Kirim `CLLocation` apa adanya, misalnya untuk menguji lokasi dengan akurasi buruk.
    func send(_ location: CLLocation) {
        publish(location)
    }

    // MARK: - Simulasi error / izin

    func simulateAuthorizationChange(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        delegate?.locationProvider(self, didChangeAuthorization: status)
    }

    func simulateError(_ error: Error = CLError(.locationUnknown)) {
        delegate?.locationProvider(self, didFailWithError: error)
    }

    // MARK: - Simulasi rute

    /// Mulai simulasi rute.
    /// - Parameters:
    ///   - speed: kecepatan dalam meter/detik (km/j ÷ 3.6).
    ///   - updateInterval: jeda antar update lokasi, dalam detik.
    ///   - loop: ulangi dari awal setelah sampai di waypoint terakhir.
    ///   - autoAdvance: `false` untuk test, lalu panggil `advanceRoute()` manual.
    /// - Returns: `false` kalau waypoint kurang dari 2.
    @discardableResult
    func startRoute(
        waypoints: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        updateInterval: TimeInterval = 1,
        loop: Bool = false,
        autoAdvance: Bool = true
    ) -> Bool {
        guard waypoints.count >= 2 else { return false }
        let samples = RouteInterpolator.samples(along: waypoints, speed: speed, interval: updateInterval, startDate: now())
        startRoute(samples: samples, updateInterval: updateInterval, loop: loop, autoAdvance: autoAdvance)
        return true
    }

    /// Seperti `startRoute`, tapi baru dijalankan saat `startUpdatingLocation()` dipanggil.
    /// Dipakai launch argument `-MockLocation_Route` supaya UI test melihat rute dari titik awal.
    func startRouteWhenUpdating(
        waypoints: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        updateInterval: TimeInterval = 1,
        loop: Bool = false
    ) {
        guard waypoints.count >= 2 else { return }
        if isUpdatingLocation {
            startRoute(waypoints: waypoints, speed: speed, updateInterval: updateInterval, loop: loop)
            return
        }
        pendingRouteStart = { [weak self] in
            self?.startRoute(waypoints: waypoints, speed: speed, updateInterval: updateInterval, loop: loop)
        }
    }

    /// Replay daftar lokasi yang sudah jadi (misalnya hasil rekaman).
    func startRoute(
        samples: [CLLocation],
        updateInterval: TimeInterval = 1,
        loop: Bool = false,
        autoAdvance: Bool = true
    ) {
        stopRoute()
        guard !samples.isEmpty else { return }

        routeSamples = samples
        routeIndex = 0
        routeProgress = 0
        loopsRoute = loop
        isSimulatingRoute = true

        advanceRoute()

        guard autoAdvance, isSimulatingRoute else { return }
        let timer = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceRoute() }
        }
        // .common supaya tetap jalan saat user scroll / geser peta.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Kirim titik rute berikutnya. Mengembalikan lokasi yang dikirim, atau `nil` jika rute selesai.
    @discardableResult
    func advanceRoute() -> CLLocation? {
        guard isSimulatingRoute, !routeSamples.isEmpty else { return nil }

        if routeIndex >= routeSamples.count {
            guard loopsRoute else {
                finishRoute()
                return nil
            }
            routeIndex = 0
        }

        let location = restamped(routeSamples[routeIndex])
        routeIndex += 1
        routeProgress = Double(routeIndex) / Double(routeSamples.count)
        publish(location)

        if routeIndex >= routeSamples.count, !loopsRoute {
            finishRoute()
        }
        return location
    }

    /// Hentikan simulasi rute. Lokasi terakhir tetap dipertahankan.
    func stopRoute() {
        pendingRouteStart = nil
        timer?.invalidate()
        timer = nil
        isSimulatingRoute = false
    }

    // MARK: - Private

    private func finishRoute() {
        timer?.invalidate()
        timer = nil
        isSimulatingRoute = false
        routeProgress = 1
    }

    private func publish(_ location: CLLocation) {
        currentLocation = location
        guard isUpdatingLocation else { return }
        delegate?.locationProvider(self, didUpdateLocations: [location])
    }

    /// Beri timestamp "sekarang" supaya logic yang membuang lokasi basi tidak salah paham.
    private func restamped(_ location: CLLocation) -> CLLocation {
        CLLocation(
            coordinate: location.coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            course: location.course,
            courseAccuracy: location.courseAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            timestamp: now()
        )
    }

    private static func makeLocation(
        _ coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy = 5,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }
}
#endif
