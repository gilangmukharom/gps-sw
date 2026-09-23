#if DEBUG
import CoreLocation

/// Memecah polyline waypoint menjadi titik-titik lokasi berjarak `speed * interval`,
/// lengkap dengan `course` (arah) dan `speed`, untuk disimulasikan satu per satu.
enum RouteInterpolator {

    static func samples(
        along waypoints: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        interval: TimeInterval,
        startDate: Date = Date()
    ) -> [CLLocation] {
        guard let first = waypoints.first else { return [] }
        guard waypoints.count >= 2, speed > 0, interval > 0 else {
            return [makeLocation(first, course: -1, speed: 0, timestamp: startDate)]
        }

        let step = speed * interval
        var coordinates: [(CLLocationCoordinate2D, CLLocationDirection)] = [
            (first, bearing(from: waypoints[0], to: waypoints[1]))
        ]
        var distanceUntilNextSample = step

        for index in 0..<(waypoints.count - 1) {
            let start = waypoints[index]
            let end = waypoints[index + 1]
            let segmentLength = distance(from: start, to: end)
            guard segmentLength > 0 else { continue }

            let course = bearing(from: start, to: end)
            var traveled: CLLocationDistance = 0

            while segmentLength - traveled >= distanceUntilNextSample {
                traveled += distanceUntilNextSample
                coordinates.append((interpolate(from: start, to: end, fraction: traveled / segmentLength), course))
                distanceUntilNextSample = step
            }
            distanceUntilNextSample -= segmentLength - traveled
        }

        // Pastikan titik terakhir persis di waypoint tujuan.
        let last = waypoints[waypoints.count - 1]
        if let lastEntry = coordinates.last {
            if distance(from: lastEntry.0, to: last) > 0.5 {
                coordinates.append((last, lastEntry.1))
            } else {
                coordinates[coordinates.count - 1].0 = last
            }
        }

        return coordinates.enumerated().map { offset, element in
            let isLast = offset == coordinates.count - 1
            return makeLocation(
                element.0,
                course: element.1,
                speed: isLast ? 0 : speed,
                timestamp: startDate.addingTimeInterval(Double(offset) * interval)
            )
        }
    }

    /// Total panjang rute dalam meter.
    static func totalDistance(of waypoints: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard waypoints.count >= 2 else { return 0 }
        return zip(waypoints, waypoints.dropFirst()).reduce(0) { $0 + distance(from: $1.0, to: $1.1) }
    }

    // MARK: - Geometry helpers

    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Bearing awal (derajat, 0 = utara, searah jarum jam).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Interpolasi linear lat/lon. Cukup akurat untuk segmen pendek (< beberapa km).
    static func interpolate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
    }

    private static func makeLocation(
        _ coordinate: CLLocationCoordinate2D,
        course: CLLocationDirection,
        speed: CLLocationSpeed,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            courseAccuracy: course >= 0 ? 5 : -1,
            speed: speed,
            speedAccuracy: 0.5,
            timestamp: timestamp
        )
    }
}
#endif
