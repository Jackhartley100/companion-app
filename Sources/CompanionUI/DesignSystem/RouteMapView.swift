import SwiftUI
import MapKit
import CompanionCore

/// Draws a recorded route on an Apple Maps view.
///
/// Used in three places with different needs — the live walk, the summary and
/// the list thumbnail — so the interactivity and the camera behaviour are
/// parameters rather than three near-identical views.
public struct RouteMapView: View {
    public enum Mode {
        /// Live recording: follows the walker and shows the blue location dot.
        case following
        /// Live recording, but the owner has panned away and is in control.
        case free
        /// A finished route, framed to fit, not interactive.
        case staticPreview
    }

    private let segments: [[Coordinate]]
    private let mode: Mode
    private let showsUserLocation: Bool
    @Binding private var cameraPosition: MapCameraPosition

    public init(
        segments: [[Coordinate]],
        mode: Mode,
        showsUserLocation: Bool = false,
        cameraPosition: Binding<MapCameraPosition>
    ) {
        self.segments = segments
        self.mode = mode
        self.showsUserLocation = showsUserLocation
        self._cameraPosition = cameraPosition
    }

    /// Convenience for a single unbroken route.
    public init(
        coordinates: [Coordinate],
        mode: Mode,
        showsUserLocation: Bool = false,
        cameraPosition: Binding<MapCameraPosition>
    ) {
        self.init(
            segments: coordinates.isEmpty ? [] : [coordinates],
            mode: mode,
            showsUserLocation: showsUserLocation,
            cameraPosition: cameraPosition
        )
    }

    public var body: some View {
        Map(position: $cameraPosition, interactionModes: interactionModes) {
            // A pause is drawn as a break in the line. Joining the two ends would
            // show a straight segment over ground the owner never walked.
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment.map(\.clCoordinate))
                        .stroke(
                            Theme.Colour.route,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                }
            }

            if let start = segments.first?.first, mode == .staticPreview {
                Annotation("Start", coordinate: start.clCoordinate) {
                    RouteEndpointMarker(symbolName: "flag.fill", tint: Theme.Colour.success)
                }
            }
            if let end = segments.last?.last, mode == .staticPreview, segments.flatMap(\.self).count > 1 {
                Annotation("Finish", coordinate: end.clCoordinate) {
                    RouteEndpointMarker(symbolName: "flag.checkered", tint: Theme.Colour.primaryText)
                }
            }

            if showsUserLocation {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // The map is decorative for VoiceOver — the metrics beside it carry the
        // information, and an unlabelled map is a dead end for a screen reader.
        .accessibilityHidden(true)
    }

    private var interactionModes: MapInteractionModes {
        mode == .staticPreview ? [] : [.pan, .zoom, .rotate]
    }
}

private struct RouteEndpointMarker: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }
}

public extension MapCameraPosition {
    /// A camera framing the whole route with a little breathing room.
    static func fitting(_ coordinates: [Coordinate], padding: Double = 1.4) -> MapCameraPosition {
        guard let first = coordinates.first else {
            return .automatic
        }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        let centre = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        // A floor on the span stops a very short walk zooming to street level,
        // where the route fills the screen and gives away the exact address.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.003, (maxLatitude - minLatitude) * padding),
            longitudeDelta: max(0.003, (maxLongitude - minLongitude) * padding)
        )
        return .region(MKCoordinateRegion(center: centre, span: span))
    }
}

/// Splits a route wherever consecutive points are implausibly far apart, which
/// is where a pause happened.
public func routeSegments(from coordinates: [Coordinate], breakDistance: Double = 60) -> [[Coordinate]] {
    guard !coordinates.isEmpty else { return [] }
    var result: [[Coordinate]] = []
    var current: [Coordinate] = [coordinates[0]]
    for index in 1..<coordinates.count {
        if coordinates[index - 1].distance(to: coordinates[index]) > breakDistance {
            result.append(current)
            current = [coordinates[index]]
        } else {
            current.append(coordinates[index])
        }
    }
    result.append(current)
    return result
}

/// A route shown as a card, with the metrics that make it identifiable.
public struct RoutePreviewCard: View {
    private let coordinates: [Coordinate]
    private let height: CGFloat
    private let placeholderSymbol: String
    private let placeholderMessage: String

    @State private var camera: MapCameraPosition

    public init(
        coordinates: [Coordinate],
        height: CGFloat = 180,
        placeholderSymbol: String = "map",
        placeholderMessage: String = "No route was recorded for this walk"
    ) {
        self.coordinates = coordinates
        self.height = height
        self.placeholderSymbol = placeholderSymbol
        self.placeholderMessage = placeholderMessage
        self._camera = State(initialValue: .fitting(coordinates))
    }

    public var body: some View {
        Group {
            if coordinates.count > 1 {
                RouteMapView(
                    segments: routeSegments(from: coordinates),
                    mode: .staticPreview,
                    cameraPosition: $camera
                )
            } else {
                ZStack {
                    Theme.Colour.fill
                    VStack(spacing: Theme.Space.s) {
                        Image(systemName: placeholderSymbol)
                            .font(.title2)
                            .foregroundStyle(Theme.Colour.secondaryText)
                        Text(placeholderMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colour.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(placeholderMessage)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

struct RouteMapView_Previews: PreviewProvider {
    static var previews: some View {
        RoutePreviewCard(coordinates: DemoDataProvider.sampleRoute().map(\.coordinate))
            .padding()
            .previewDisplayName("Route")

        RoutePreviewCard(coordinates: [])
            .padding()
            .previewDisplayName("No route recorded")

        RoutePreviewCard(coordinates: DemoDataProvider.sampleRoute().map(\.coordinate), height: 260)
            .padding()
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")
    }
}
