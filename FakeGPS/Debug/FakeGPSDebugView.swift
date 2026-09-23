#if DEBUG
import CoreLocation
import SwiftUI

/// Layar kontrol fake GPS. Hanya ada di build DEBUG.
struct FakeGPSDebugView: View {
    @StateObject private var viewModel: FakeGPSDebugViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field { case latitude, longitude }

    init(provider: SwitchableLocationProvider) {
        _viewModel = StateObject(wrappedValue: FakeGPSDebugViewModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                manualInputSection
                mapSection
                presetSection
                routeSection
                gpxSection
            }
            .navigationTitle("Fake GPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tutup") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Selesai") { focusedField = nil }
                }
            }
        }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            Picker("Sumber lokasi", selection: Binding(
                get: { viewModel.provider.source },
                set: { viewModel.setSource($0) }
            )) {
                ForEach(SwitchableLocationProvider.Source.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fakeGPS.sourcePicker")

            if let location = viewModel.mock.currentLocation {
                LabeledContent("Posisi palsu", value: format(location.coordinate))
                    .font(.footnote.monospacedDigit())
            }
        } header: {
            Text("Sumber")
        } footer: {
            Text(viewModel.isMockActive
                 ? "App menerima koordinat palsu dari layar ini."
                 : "App memakai GPS asli (termasuk lokasi simulasi dari Xcode/GPX).")
        }
    }

    private var mapSection: some View {
        Section {
            Picker("Mode tap", selection: $viewModel.tapMode) {
                ForEach(FakeGPSDebugViewModel.MapTapMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            MapPickerView(
                pickedCoordinate: viewModel.pickedCoordinate,
                mockCoordinate: viewModel.mock.currentLocation?.coordinate,
                waypoints: viewModel.waypoints.map(\.coordinate),
                recenterRequest: viewModel.recenterRequest,
                onTap: { viewModel.handleMapTap($0) }
            )
            .frame(height: 300)
            .listRowInsets(EdgeInsets())

            if viewModel.tapMode == .pickPoint {
                Button("Pakai titik yang dipilih") { viewModel.applyPickedLocation() }
                    .disabled(viewModel.pickedCoordinate == nil)
            }
        } header: {
            Text("Peta")
        } footer: {
            Text("Pin biru = titik dipilih, merah = lokasi palsu aktif, oranye = waypoint rute.")
        }
    }

    private var manualInputSection: some View {
        Section("Input manual") {
            TextField("Latitude (mis. -6.1754)", text: $viewModel.latitudeText)
                .keyboardType(.numbersAndPunctuation)
                .focused($focusedField, equals: .latitude)
                .accessibilityIdentifier("fakeGPS.latitudeField")
            TextField("Longitude (mis. 106.8272)", text: $viewModel.longitudeText)
                .keyboardType(.numbersAndPunctuation)
                .focused($focusedField, equals: .longitude)
                .accessibilityIdentifier("fakeGPS.longitudeField")

            Button("Set lokasi") {
                focusedField = nil
                viewModel.applyManualInput()
            }
            .accessibilityIdentifier("fakeGPS.applyManualButton")

            if let error = viewModel.inputError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var presetSection: some View {
        Section {
            ForEach(LocationPreset.all) { preset in
                Button {
                    viewModel.apply(preset)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text(format(preset.coordinate))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: preset.systemImage)
                    }
                }
                .swipeActions {
                    Button("+ Waypoint") { viewModel.addPresetAsWaypoint(preset) }
                        .tint(.orange)
                }
            }
        } header: {
            Text("Preset")
        } footer: {
            Text("Tap untuk langsung pindah. Geser ke kiri untuk menambahkan sebagai waypoint.")
        }
    }

    private var routeSection: some View {
        Section {
            if viewModel.waypoints.isEmpty {
                Text("Belum ada waypoint. Pilih mode \"Tambah waypoint\" lalu tap peta.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(viewModel.waypoints.enumerated()), id: \.element.id) { index, waypoint in
                LabeledContent("WP \(index + 1)", value: format(waypoint.coordinate))
                    .font(.footnote.monospacedDigit())
            }
            .onDelete { viewModel.removeWaypoints(at: $0) }
            .onMove { viewModel.moveWaypoints(from: $0, to: $1) }

            HStack {
                Button("Tambah titik dipilih") { viewModel.addPickedAsWaypoint() }
                    .disabled(viewModel.pickedCoordinate == nil)
                Spacer()
                Button("Hapus semua", role: .destructive) { viewModel.clearWaypoints() }
                    .disabled(viewModel.waypoints.isEmpty)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading) {
                Text("Kecepatan: \(Int(viewModel.speedKmh)) km/j")
                Slider(value: $viewModel.speedKmh, in: 1...150, step: 1)
                HStack {
                    speedPreset("Jalan", 5)
                    speedPreset("Sepeda", 15)
                    speedPreset("Motor", 40)
                    speedPreset("Tol", 90)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Stepper(value: $viewModel.updateInterval, in: 0.5...10, step: 0.5) {
                Text("Interval update: \(viewModel.updateInterval, specifier: "%.1f") dtk")
            }

            Toggle("Ulangi (loop)", isOn: $viewModel.loopRoute)

            if viewModel.canStartRoute {
                LabeledContent("Jarak", value: String(format: "%.2f km", viewModel.routeDistance / 1000))
                LabeledContent("Estimasi waktu", value: durationText(viewModel.estimatedDuration))
            }

            if viewModel.mock.isSimulatingRoute {
                ProgressView(value: viewModel.mock.routeProgress)
                Button("Stop simulasi", role: .destructive) { viewModel.stopRoute() }
                    .accessibilityIdentifier("fakeGPS.stopRouteButton")
            } else {
                Button("Mulai simulasi") { viewModel.startRoute() }
                    .disabled(!viewModel.canStartRoute)
                    .accessibilityIdentifier("fakeGPS.startRouteButton")
            }
        } header: {
            HStack {
                Text("Simulasi rute")
                Spacer()
                EditButton().font(.caption)
            }
        }
    }

    private var gpxSection: some View {
        Section {
            Button("Buat file GPX") { viewModel.exportGPX() }

            if let url = viewModel.exportedGPXURL {
                ShareLink(item: url) {
                    Label("Bagikan \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
            if let error = viewModel.exportError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("GPX")
        } footer: {
            Text("AirDrop file ke Mac, lalu tambahkan ke folder GPX/ di project untuk dipakai di Debug > Simulate Location.")
        }
    }

    // MARK: - Helpers

    private func speedPreset(_ title: String, _ kmh: Double) -> some View {
        Button(title) { viewModel.speedKmh = kmh }
    }

    private func format(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "-"
    }
}

// MARK: - Entry point

private struct FakeGPSDebugMenuModifier: ViewModifier {
    let provider: SwitchableLocationProvider
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresented = true
                    } label: {
                        Image(systemName: "location.magnifyingglass")
                    }
                    .accessibilityLabel("Fake GPS")
                    .accessibilityIdentifier("fakeGPS.openButton")
                }
            }
            .sheet(isPresented: $isPresented) {
                FakeGPSDebugView(provider: provider)
            }
    }
}

extension View {
    /// Tambahkan tombol toolbar yang membuka layar Fake GPS. Hanya tersedia di DEBUG.
    func fakeGPSDebugMenu(provider: SwitchableLocationProvider) -> some View {
        modifier(FakeGPSDebugMenuModifier(provider: provider))
    }
}
#endif
