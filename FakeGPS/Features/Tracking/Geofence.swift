import CoreLocation

struct Geofence: Equatable {
    var name: String
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var radius: CLLocationDistance

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func contains(_ location: CLLocation) -> Bool {
        location.distance(from: CLLocation(latitude: latitude, longitude: longitude)) <= radius
    }

    /// Garuda Sentra Operasi (GSO), Bandara Soekarno-Hatta — titik dari OpenStreetMap
    /// ("Garuda Operation & Crew Center"). Samakan dengan `GPX/Office.gpx`.
    static let office = Geofence(name: "Kantor (GSO)", latitude: -6.131336, longitude: 106.644936, radius: 150)
}

enum GeofenceEvent: Equatable {
    case entered
    case exited
}
