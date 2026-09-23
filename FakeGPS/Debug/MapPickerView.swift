#if DEBUG
import MapKit
import SwiftUI

struct MapRecenterRequest: Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapRecenterRequest, rhs: MapRecenterRequest) -> Bool { lhs.id == rhs.id }
}

/// Peta yang bisa di-tap untuk memilih koordinat.
///
/// Memakai `MKMapView` karena SwiftUI `Map` di iOS 16 belum bisa mengubah titik tap
/// menjadi koordinat (`MapReader` baru ada di iOS 17).
struct MapPickerView: UIViewRepresentable {
    var pickedCoordinate: CLLocationCoordinate2D?
    var mockCoordinate: CLLocationCoordinate2D?
    var waypoints: [CLLocationCoordinate2D]
    var recenterRequest: MapRecenterRequest?
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .excludingAll

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)

        let center = mockCoordinate ?? pickedCoordinate ?? LocationPreset.office.coordinate
        mapView.setRegion(
            MKCoordinateRegion(center: center, latitudinalMeters: 3_000, longitudinalMeters: 3_000),
            animated: false
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        coordinator.sync(coordinator.pickedAnnotation, to: pickedCoordinate, on: mapView)
        coordinator.sync(coordinator.mockAnnotation, to: mockCoordinate, on: mapView)
        coordinator.syncWaypoints(waypoints, on: mapView)

        if let request = recenterRequest, request.id != coordinator.lastRecenterID {
            coordinator.lastRecenterID = request.id
            mapView.setCenter(request.coordinate, animated: true)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapPickerView
        var lastRecenterID: UUID?

        let pickedAnnotation = KindAnnotation(kind: .picked, title: "Dipilih")
        let mockAnnotation = KindAnnotation(kind: .mock, title: "Lokasi palsu")
        private var waypointAnnotations: [KindAnnotation] = []
        private var routeOverlay: MKPolyline?
        private var lastWaypointKey: [Double] = []

        init(parent: MapPickerView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            parent.onTap(mapView.convert(point, toCoordinateFrom: mapView))
        }

        func sync(_ annotation: KindAnnotation, to coordinate: CLLocationCoordinate2D?, on mapView: MKMapView) {
            let isOnMap = mapView.annotations.contains { $0 === annotation }
            guard let coordinate else {
                if isOnMap { mapView.removeAnnotation(annotation) }
                return
            }
            // MKPointAnnotation.coordinate KVO-compliant: pin bergerak tanpa di-remove/add ulang.
            annotation.coordinate = coordinate
            if !isOnMap { mapView.addAnnotation(annotation) }
        }

        func syncWaypoints(_ waypoints: [CLLocationCoordinate2D], on mapView: MKMapView) {
            let key = waypoints.flatMap { [$0.latitude, $0.longitude] }
            guard key != lastWaypointKey else { return }
            lastWaypointKey = key

            mapView.removeAnnotations(waypointAnnotations)
            waypointAnnotations = waypoints.enumerated().map { index, coordinate in
                let annotation = KindAnnotation(kind: .waypoint, title: "WP \(index + 1)")
                annotation.coordinate = coordinate
                return annotation
            }
            mapView.addAnnotations(waypointAnnotations)

            if let routeOverlay { mapView.removeOverlay(routeOverlay) }
            routeOverlay = nil
            if waypoints.count >= 2 {
                let polyline = MKPolyline(coordinates: waypoints, count: waypoints.count)
                mapView.addOverlay(polyline)
                routeOverlay = polyline
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? KindAnnotation else { return nil }
            let identifier = annotation.kind.rawValue
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = true
            switch annotation.kind {
            case .picked:
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "hand.tap")
            case .mock:
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "location.fill")
                view.displayPriority = .required
            case .waypoint:
                view.markerTintColor = .systemOrange
                view.glyphText = annotation.title?.replacingOccurrences(of: "WP ", with: "")
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemOrange
            renderer.lineWidth = 4
            renderer.lineDashPattern = [6, 4]
            return renderer
        }
    }

    final class KindAnnotation: MKPointAnnotation {
        enum Kind: String {
            case picked, mock, waypoint
        }

        let kind: Kind

        init(kind: Kind, title: String) {
            self.kind = kind
            super.init()
            self.title = title
        }
    }
}
#endif
