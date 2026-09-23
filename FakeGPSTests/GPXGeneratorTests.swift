import CoreLocation
import XCTest
@testable import FakeGPS

final class GPXGeneratorTests: XCTestCase {

    func test_singleLocation_producesValidGPX11() throws {
        let xml = GPXGenerator.xml(for: GPXGenerator.singleLocation(TestCoordinates.monas, name: "Monas"))

        XCTAssertTrue(xml.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(xml.contains(#"version="1.1""#))
        XCTAssertTrue(xml.contains(#"xmlns="http://www.topografix.com/GPX/1/1""#))
        XCTAssertTrue(xml.contains(#"<wpt lat="-6.1754000" lon="106.8272000">"#))

        let parsed = try GPXElementCounter.parse(xml)
        XCTAssertEqual(parsed["wpt"], 1)
        XCTAssertEqual(parsed["trk"], nil)
    }

    func test_routeDocument_hasTimedWaypointsAndTrack() throws {
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        let document = GPXGenerator.routeDocument(
            name: "Test",
            waypoints: [TestCoordinates.office, TestCoordinates.north1km],
            speed: 10,
            trackInterval: 10,
            startDate: start
        )

        XCTAssertEqual(document.waypoints.count, 2)
        XCTAssertEqual(document.waypoints[0].time, start)
        // ±1106 m / 10 m/s = ±110.6 dtk
        let duration = try XCTUnwrap(document.waypoints[1].time).timeIntervalSince(start)
        XCTAssertEqual(duration, 110.6, accuracy: 2)

        let xml = GPXGenerator.xml(for: document)
        XCTAssertTrue(xml.contains("<time>2026-01-01T00:00:00Z</time>"))

        let parsed = try GPXElementCounter.parse(xml)
        XCTAssertEqual(parsed["wpt"], 2)
        XCTAssertEqual(parsed["trk"], 1)
        XCTAssertGreaterThanOrEqual(parsed["trkpt"] ?? 0, 11)
    }

    func test_specialCharactersAreEscaped() throws {
        let xml = GPXGenerator.xml(for: GPXGenerator.singleLocation(TestCoordinates.office, name: #"R&D <"Lt 3">"#))

        XCTAssertTrue(xml.contains("<name>R&amp;D &lt;&quot;Lt 3&quot;&gt;</name>"))
        XCTAssertNoThrow(try GPXElementCounter.parse(xml))
    }

    func test_write_createsFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try GPXGenerator.write(
            GPXGenerator.singleLocation(TestCoordinates.office, name: "Kantor"),
            fileName: "Office",
            directory: directory
        )

        XCTAssertEqual(url.lastPathComponent, "Office.gpx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

/// Parse XML dan hitung jumlah tiap elemen; gagal kalau XML tidak well-formed.
private final class GPXElementCounter: NSObject, XMLParserDelegate {
    private var counts: [String: Int] = [:]

    static func parse(_ xml: String) throws -> [String: Int] {
        let counter = GPXElementCounter()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = counter
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "GPXElementCounter", code: 1)
        }
        return counter.counts
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        counts[elementName, default: 0] += 1
    }
}
