import CoreLocation

extension CLLocationCoordinate2D {
    /// Parse `"lat,lon"` (mis. `"-6.1754,106.8272"`). Mengembalikan `nil` jika tidak valid.
    init?(parsing text: String) {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        self.init(latitudeText: parts[0], longitudeText: parts[1])
    }

    /// Parse latitude & longitude terpisah. Menerima koma sebagai pemisah desimal (`-6,1754`).
    init?(latitudeText: String, longitudeText: String) {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        guard let latitude = number(latitudeText),
              let longitude = number(longitudeText),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }
}
