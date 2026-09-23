import CoreLocation
import XCTest

/// Dua pendekatan UI test lokasi:
///
/// 1. **Launch argument + MockLocationManager** (`-UITest_MockLocation`)
///    Deterministik, tanpa dialog izin, jalan di Simulator & device. Hanya build DEBUG.
///
/// 2. **`XCUIDevice.shared.location`** (iOS 16.4+ / Xcode 14.3+)
///    Mengubah lokasi di level sistem, jadi app memakai `RealLocationManager`
///    (`-UITest_RealLocation`). Menguji jalur CoreLocation yang asli.
final class LocationUITests: XCTestCase {
    private let office = "-6.131336,106.644936"         // GSO
    private let farFromOffice = "-6.121336,106.644936"  // ±1.1 km ke utara

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Via launch argument (MockLocationManager)

    func test_mockLocation_atOffice_showsInsideGeofence() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest_MockLocation", "-MockLocation_Coordinate", office]
        app.launch()

        app.buttons["trackingToggleButton"].tap()

        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di dalam area")
        XCTAssertEqual(app.staticTexts["latitudeValue"].label, "-6.131336")
    }

    func test_mockRoute_leavingOffice_showsEnterThenExit() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITest_MockLocation",
            "-MockLocation_Route", "\(office);\(farFromOffice)",
            "-MockLocation_SpeedKmh", "360",   // 100 m/s -> ±11 detik
            "-MockLocation_Interval", "0.5",
        ]
        app.launch()

        app.buttons["trackingToggleButton"].tap()

        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di luar area", timeout: 30)
        XCTAssertEqual(app.staticTexts["geofenceEvents"].label, "masuk → keluar")
    }

    // MARK: - 2. Via XCUIDevice.shared.location (lokasi sistem)

    @available(iOS 16.4, *)
    func test_systemLocation_viaXCUIDevice_updatesGeofence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest_RealLocation"]
        app.resetAuthorizationStatus(for: .location)

        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.131336, longitude: 106.644936))
        app.launch()

        app.buttons["trackingToggleButton"].tap()
        allowLocationPermissionIfNeeded()

        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di dalam area", timeout: 15)

        // Pindahkan lokasi saat app berjalan.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: -6.121336, longitude: 106.644936))

        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di luar area", timeout: 15)
    }

    // MARK: - 3. Mengendalikan layar debug Fake GPS

    func test_debugScreen_manualInput_movesMockLocation() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest_MockLocation", "-MockLocation_Coordinate", farFromOffice]
        app.launch()
        app.buttons["trackingToggleButton"].tap()
        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di luar area")

        app.buttons["fakeGPS.openButton"].tap()
        replaceText(in: app.textFields["fakeGPS.latitudeField"], with: "-6.131336")
        replaceText(in: app.textFields["fakeGPS.longitudeField"], with: "106.644936")
        app.buttons["fakeGPS.applyManualButton"].tap()
        app.buttons["Tutup"].tap()

        assertLabel(of: app.staticTexts["geofenceStatus"], becomes: "Di dalam area")
    }

    // MARK: - Helpers

    private func assertLabel(
        of element: XCUIElement,
        becomes expected: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed,
                       "Label '\(element.label)' tidak menjadi '\(expected)' dalam \(timeout) dtk",
                       file: file, line: line)
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    /// Tap tombol "Allow While Using App" di alert izin lokasi (dialog milik SpringBoard).
    private func allowLocationPermissionIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }

        let englishButton = alert.buttons["Allow While Using App"]
        if englishButton.exists {
            englishButton.tap()
        } else {
            // Urutan tombol: Allow Once / Allow While Using App / Don't Allow (bahasa apa pun).
            alert.buttons.element(boundBy: 1).tap()
        }
    }
}
