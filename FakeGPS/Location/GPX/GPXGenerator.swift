#if DEBUG
import CoreLocation
import Foundation

struct GPXPoint: Equatable {
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var elevation: CLLocationDistance?
    var time: Date?
    var name: String?

    init(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        elevation: CLLocationDistance? = nil,
        time: Date? = nil,
        name: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
        self.name = name
    }

    init(coordinate: CLLocationCoordinate2D, elevation: CLLocationDistance? = nil, time: Date? = nil, name: String? = nil) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: elevation, time: time, name: name)
    }

    init(location: CLLocation, name: String? = nil) {
        self.init(
            coordinate: location.coordinate,
            elevation: location.verticalAccuracy >= 0 ? location.altitude : nil,
            time: location.timestamp,
            name: name
        )
    }
}

struct GPXTrack: Equatable {
    var name: String?
    var segments: [[GPXPoint]]
}

struct GPXDocument: Equatable {
    var name: String?
    var creator: String = "FakeGPS"
    var time: Date?
    var waypoints: [GPXPoint] = []
    var tracks: [GPXTrack] = []
}

/// Generator file GPX 1.1 (http://www.topografix.com/GPX/1/1).
///
/// Catatan untuk Xcode "Simulate Location": Xcode membaca elemen `<wpt>`.
/// Kalau `<wpt>` punya `<time>`, Xcode menggerakkan lokasi antar waypoint sesuai
/// selisih waktunya. `<trk>` diabaikan Xcode, tapi berguna untuk tool lain
/// (Google Earth, Strava, dsb). `routeDocument` mengisi keduanya.
enum GPXGenerator {

    // MARK: - Builder

    /// GPX satu titik statis (seperti `GarudaSentraOperasi.gpx`).
    static func singleLocation(_ coordinate: CLLocationCoordinate2D, name: String) -> GPXDocument {
        GPXDocument(name: name, waypoints: [GPXPoint(coordinate: coordinate, name: name)])
    }

    /// GPX rute yang kompatibel dengan Xcode:
    /// - `<wpt>` per waypoint dengan `<time>` dihitung dari jarak ÷ kecepatan (untuk Xcode)
    /// - `<trk>` berisi titik-titik rapat hasil interpolasi (untuk tool lain)
    static func routeDocument(
        name: String,
        waypoints: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        trackInterval: TimeInterval = 1,
        startDate: Date = Date()
    ) -> GPXDocument {
        var elapsed: TimeInterval = 0
        var timedWaypoints: [GPXPoint] = []
        for (index, coordinate) in waypoints.enumerated() {
            if index > 0, speed > 0 {
                elapsed += RouteInterpolator.distance(from: waypoints[index - 1], to: coordinate) / speed
            }
            timedWaypoints.append(
                GPXPoint(coordinate: coordinate, time: startDate.addingTimeInterval(elapsed), name: "WP\(index + 1)")
            )
        }

        let samples = RouteInterpolator.samples(along: waypoints, speed: speed, interval: trackInterval, startDate: startDate)
        let track = GPXTrack(name: name, segments: [samples.map { GPXPoint(location: $0) }])

        return GPXDocument(
            name: name,
            time: startDate,
            waypoints: timedWaypoints,
            tracks: samples.isEmpty ? [] : [track]
        )
    }

    // MARK: - Serialisasi

    static func xml(for document: GPXDocument) -> String {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="\#(escape(document.creator))""#
                + #" xmlns="http://www.topografix.com/GPX/1/1""#
                + #" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance""#
                + #" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">"#,
        ]

        if document.name != nil || document.time != nil {
            lines.append("  <metadata>")
            if let name = document.name { lines.append("    <name>\(escape(name))</name>") }
            if let time = document.time { lines.append("    <time>\(format(time))</time>") }
            lines.append("  </metadata>")
        }

        for waypoint in document.waypoints {
            lines.append(contentsOf: pointXML(waypoint, tag: "wpt", indent: "  "))
        }

        for track in document.tracks {
            lines.append("  <trk>")
            if let name = track.name { lines.append("    <name>\(escape(name))</name>") }
            for segment in track.segments {
                lines.append("    <trkseg>")
                for point in segment {
                    lines.append(contentsOf: pointXML(point, tag: "trkpt", indent: "      "))
                }
                lines.append("    </trkseg>")
            }
            lines.append("  </trk>")
        }

        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func data(for document: GPXDocument) -> Data {
        Data(xml(for: document).utf8)
    }

    /// Tulis ke folder temporary dan kembalikan URL-nya (untuk ShareLink / AirDrop ke Mac).
    @discardableResult
    static func write(
        _ document: GPXDocument,
        fileName: String,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let safeName = fileName.hasSuffix(".gpx") ? fileName : fileName + ".gpx"
        let url = directory.appendingPathComponent(safeName)
        try data(for: document).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private

    // GPX 1.1 wptType: urutan child wajib ele -> time -> ... -> name.
    private static func pointXML(_ point: GPXPoint, tag: String, indent: String) -> [String] {
        let open = "\(indent)<\(tag) lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\""
        var children: [String] = []
        if let elevation = point.elevation { children.append("<ele>\(String(format: "%.2f", elevation))</ele>") }
        if let time = point.time { children.append("<time>\(format(time))</time>") }
        if let name = point.name { children.append("<name>\(escape(name))</name>") }

        guard !children.isEmpty else { return [open + "/>"] }
        return [open + ">"] + children.map { "\(indent)  \($0)" } + ["\(indent)</\(tag)>"]
    }

    private static func coordinate(_ value: Double) -> String {
        // String(format:) tidak terpengaruh locale device (selalu pakai titik desimal).
        String(format: "%.7f", value)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
#endif
