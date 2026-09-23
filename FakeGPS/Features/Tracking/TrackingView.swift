import CoreLocation
import SwiftUI

struct TrackingView: View {
    @ObservedObject var viewModel: TrackingViewModel

    var body: some View {
        List {
            Section("Lokasi saat ini") {
                row("Latitude", value: viewModel.currentLocation.map { format($0.coordinate.latitude) } ?? "-",
                    id: "latitudeValue")
                row("Longitude", value: viewModel.currentLocation.map { format($0.coordinate.longitude) } ?? "-",
                    id: "longitudeValue")
                row("Kecepatan", value: speedText, id: "speedValue")
                row("Arah", value: courseText, id: "courseValue")
            }

            Section("Perjalanan") {
                row("Jarak tempuh", value: distanceText, id: "distanceValue")
            }

            Section("Geofence: \(viewModel.geofence.name)") {
                row("Status",
                    value: viewModel.isInsideGeofence ? "Di dalam area" : "Di luar area",
                    id: "geofenceStatus")
                row("Event", value: eventsText, id: "geofenceEvents")
            }

            Section {
                Button(viewModel.isTracking ? "Stop tracking" : "Mulai tracking") {
                    viewModel.isTracking ? viewModel.stopTracking() : viewModel.startTracking()
                }
                .accessibilityIdentifier("trackingToggleButton")

                Button("Reset perjalanan", role: .destructive) { viewModel.resetTrip() }
            } footer: {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Location Demo")
    }

    private func row(_ title: String, value: String, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(id)
        }
    }

    private func format(_ degrees: CLLocationDegrees) -> String {
        String(format: "%.6f", degrees)
    }

    private var speedText: String {
        guard let speed = viewModel.currentLocation?.speed, speed >= 0 else { return "-" }
        return String(format: "%.1f km/j", speed * 3.6)
    }

    private var courseText: String {
        guard let course = viewModel.currentLocation?.course, course >= 0 else { return "-" }
        return String(format: "%.0f°", course)
    }

    private var distanceText: String {
        Measurement(value: viewModel.totalDistance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var eventsText: String {
        viewModel.geofenceEvents.isEmpty
            ? "-"
            : viewModel.geofenceEvents.map { $0 == .entered ? "masuk" : "keluar" }.joined(separator: " → ")
    }
}
