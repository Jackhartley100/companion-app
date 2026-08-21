import SwiftUI
import CompanionCore

/// One walk in a list.
///
/// Reads as a diary entry rather than a database row: the title and the dogs
/// come first, the numbers support them.
public struct ActivityRow: View {
    private let activity: WalkActivity
    private let dogs: [Dog]
    private let imageStore: (any ImageStore)?
    private let hasAchievement: Bool

    @Environment(\.formatters) private var formatters
    @Environment(\.companionCalendar) private var calendar

    public init(
        activity: WalkActivity,
        dogs: [Dog],
        imageStore: (any ImageStore)? = nil,
        hasAchievement: Bool = false
    ) {
        self.activity = activity
        self.dogs = dogs
        self.imageStore = imageStore
        self.hasAchievement = hasAchievement
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            RouteThumbnail(coordinates: activity.routePreview, activityType: activity.activityType)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xs) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)
                    if hasAchievement {
                        Image(systemName: "rosette")
                            .font(.caption)
                            .foregroundStyle(Theme.Colour.accent)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .lineLimit(1)

                HStack(spacing: Theme.Space.m) {
                    Label(
                        formatters.distance(activity.distance),
                        systemImage: activity.activityType.symbolName
                    )
                    Label(formatters.duration(activity.movingDuration), systemImage: "clock")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Colour.secondaryText)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            if !dogs.isEmpty {
                DogAvatarRow(dogs: dogs, size: 28, imageStore: imageStore)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var subtitle: String {
        let day = formatters.relativeDay(activity.startDate, calendar: calendar)
        return "\(day) at \(formatters.time(activity.startDate))"
    }

    /// One sentence carrying everything the visual row shows, so VoiceOver users
    /// are not left navigating five separate fragments per row.
    private var accessibilityDescription: String {
        var parts = [
            activity.title,
            subtitle,
            formatters.accessibleDistance(activity.distance),
            formatters.spelledDuration(activity.movingDuration)
        ]
        if !dogs.isEmpty {
            parts.append("with \(dogs.map(\.name).formatted(.list(type: .and)))")
        }
        if hasAchievement {
            parts.append("achievement earned")
        }
        return parts.joined(separator: ", ")
    }
}

/// A small route sketch drawn without MapKit.
///
/// A list of fifty walks would otherwise mean fifty live map views, which is
/// slow and pointless at this size. The shape is enough to tell one walk from
/// another at a glance.
public struct RouteThumbnail: View {
    private let coordinates: [Coordinate]
    private let activityType: ActivityType
    private let size: CGFloat

    public init(coordinates: [Coordinate], activityType: ActivityType, size: CGFloat = 56) {
        self.coordinates = coordinates
        self.activityType = activityType
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.Colour.accent.opacity(0.10))

            if coordinates.count > 1 {
                RouteShape(coordinates: coordinates)
                    .stroke(
                        Theme.Colour.route,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .padding(Theme.Space.s)
            } else {
                Image(systemName: activityType.symbolName)
                    .font(.title3)
                    .foregroundStyle(Theme.Colour.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Normalises a route into the unit square and draws it.
struct RouteShape: Shape {
    let coordinates: [Coordinate]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard coordinates.count > 1 else { return path }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else {
            return path
        }

        // Guard against a degenerate span: a route that never moved in one axis
        // would otherwise divide by zero.
        let latitudeSpan = max(maxLatitude - minLatitude, 0.000_001)
        let longitudeSpan = max(maxLongitude - minLongitude, 0.000_001)
        // Keep the aspect ratio so a long thin walk does not render as a blob.
        let scale = min(rect.width / longitudeSpan, rect.height / latitudeSpan)
        let offsetX = (rect.width - longitudeSpan * scale) / 2
        let offsetY = (rect.height - latitudeSpan * scale) / 2

        let points = coordinates.map { coordinate in
            CGPoint(
                x: rect.minX + offsetX + (coordinate.longitude - minLongitude) * scale,
                // Latitude increases northwards; screen y increases downwards.
                y: rect.minY + offsetY + (maxLatitude - coordinate.latitude) * scale
            )
        }

        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }
}

struct ActivityRow_Previews: PreviewProvider {
    static let activity = DemoDataProvider.sampleActivity()

    static var previews: some View {
        List {
            ActivityRow(activity: activity, dogs: [DemoDataProvider.roxy()], hasAchievement: true)
            ActivityRow(activity: activity, dogs: DemoDataProvider.dogs)
            ActivityRow(
                activity: {
                    var withoutRoute = activity
                    withoutRoute.routePreview = []
                    withoutRoute.routePointCount = 0
                    withoutRoute.title = "Manual entry"
                    return withoutRoute
                }(),
                dogs: [DemoDataProvider.bailey()]
            )
        }
        .previewDisplayName("Rows")

        List {
            ActivityRow(activity: activity, dogs: DemoDataProvider.dogs, hasAchievement: true)
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")

        List {
            ActivityRow(activity: activity, dogs: [DemoDataProvider.roxy()])
        }
        .environment(\.sizeCategory, .accessibilityLarge)
        .previewDisplayName("Large text")
    }
}
