import SwiftUI
import CompanionCore

/// The image shared to a story (Instagram, WhatsApp, Messages, and so on).
///
/// Designed at 360×640 points and rendered at 3x through `ImageRenderer`,
/// which gives exactly 1080×1920 — the standard story canvas — without the
/// view ever needing to know about pixels.
///
/// Two things this view is deliberately never given: the raw route, and the
/// system colour scheme. The route is trimmed by the caller with
/// `RoutePrivacy` before it ever reaches here, so this view cannot leak a
/// home address even if a future edit forgets to trim first — there is
/// simply nothing un-trimmed to draw. And the card always renders as one
/// fixed dark design regardless of the device's light/dark setting, because
/// a shared image is seen out of context by other people; it should not
/// change appearance depending on whose phone took the screenshot.
public struct WalkStoryCardView: View {
    let activity: WalkActivity
    let dogNames: [String]
    /// Already passed through `RoutePrivacy.trimmingEndpoints` by the caller.
    let trimmedRoute: [Coordinate]
    let photoData: Data?
    let formatters: Formatters

    public static let size = CGSize(width: 360, height: 640)

    public init(
        activity: WalkActivity,
        dogNames: [String],
        trimmedRoute: [Coordinate],
        photoData: Data?,
        formatters: Formatters
    ) {
        self.activity = activity
        self.dogNames = dogNames
        self.trimmedRoute = trimmedRoute
        self.photoData = photoData
        self.formatters = formatters
    }

    /// Fixed palette, independent of `Theme` — see the type's own note on why.
    private enum Card {
        static let deepGreen = Color(red: 0.086, green: 0.188, blue: 0.125)
        static let green = Color(red: 0.18, green: 0.42, blue: 0.31)
        static let sand = Color(red: 0.91, green: 0.73, blue: 0.40)
        static let cream = Color(red: 0.95, green: 0.93, blue: 0.86)
    }

    public var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                brandMark
                    .padding(.top, 40)

                Spacer(minLength: 12)

                if trimmedRoute.count > 1 {
                    RouteShape(coordinates: trimmedRoute)
                        .stroke(Card.cream, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }

                Spacer(minLength: 12)

                headline

                statRow
                    .padding(.top, 28)

                Spacer(minLength: 0)

                dateLine
                    .padding(.bottom, 36)
            }
            .padding(.horizontal, 28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    @ViewBuilder
    private var background: some View {
        if let photoData, let image = Image(data: photoData) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
                .overlay {
                    // Darkens the photo evenly so white text stays legible
                    // wherever the route or stats happen to land on it.
                    LinearGradient(
                        colors: [Card.deepGreen.opacity(0.35), Card.deepGreen.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            LinearGradient(
                colors: [Card.green, Card.deepGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var brandMark: some View {
        HStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 13))
            Text(Theme.Brand.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Card.sand)
    }

    private var headline: some View {
        Text(headlineText)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }

    private var headlineText: String {
        let distance = formatters.distance(activity.distance)
        guard !dogNames.isEmpty else { return "\(distance) walked" }
        let names = dogNames.joined(separator: " & ")
        return "\(distance) with \(names)"
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            storyStat(value: formatters.duration(activity.movingDuration), label: "Time")
            divider
            storyStat(
                value: formatters.rate(metresPerSecond: activity.averageSpeed, activityType: activity.activityType) ?? "—",
                label: "Pace"
            )
            if let gain = activity.elevationGain, gain > 5 {
                divider
                storyStat(value: formatters.distance(gain), label: "Climb")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Card.cream.opacity(0.25))
            .frame(width: 1, height: 34)
    }

    private func storyStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Card.cream.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private var dateLine: some View {
        Text(formatters.dateTime(activity.startDate))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Card.cream.opacity(0.6))
    }
}

struct WalkStoryCardView_Previews: PreviewProvider {
    static var previews: some View {
        let activity = DemoDataProvider.sampleActivity()
        WalkStoryCardView(
            activity: activity,
            dogNames: ["Roxy"],
            trimmedRoute: RoutePrivacy.trimmingEndpoints(SyntheticRoute.loop(radiusMetres: 420, pointCount: 90)).map(\.coordinate),
            photoData: nil,
            formatters: Formatters(distanceUnit: .kilometres, weightUnit: .kilograms)
        )
        .previewLayout(.fixed(width: 360, height: 640))
        .previewDisplayName("No photo")

        WalkStoryCardView(
            activity: activity,
            dogNames: ["Roxy", "Bailey"],
            trimmedRoute: [],
            photoData: nil,
            formatters: Formatters(distanceUnit: .kilometres, weightUnit: .kilograms)
        )
        .previewLayout(.fixed(width: 360, height: 640))
        .previewDisplayName("Short walk, no route")
    }
}
