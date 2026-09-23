#if DEBUG
import CoreLocation

/// Preset lokasi untuk layar debug. Silakan ganti dengan koordinat milikmu.
struct LocationPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let office = LocationPreset(
        id: "office", name: "Kantor (GSO)", systemImage: "airplane",
        latitude: Geofence.office.latitude, longitude: Geofence.office.longitude
    )
    static let home = LocationPreset(
        id: "home", name: "Rumah", systemImage: "house",
        latitude: -6.2615, longitude: 106.7810
    )
    static let monas = LocationPreset(
        id: "monas", name: "Uji: Monas", systemImage: "mappin.and.ellipse",
        latitude: -6.1754, longitude: 106.8272
    )
    static let gbk = LocationPreset(
        id: "gbk", name: "Uji: GBK", systemImage: "sportscourt",
        latitude: -6.2183, longitude: 106.8022
    )
    static let outsideCountry = LocationPreset(
        id: "singapore", name: "Uji: Luar negeri (Singapura)", systemImage: "globe.asia.australia",
        latitude: 1.2834, longitude: 103.8607
    )

    static let all: [LocationPreset] = [office, home, monas, gbk, outsideCountry]
}
#endif
