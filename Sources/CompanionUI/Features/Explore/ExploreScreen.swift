import SwiftUI
import MapKit
import CompanionCore

/// Dog-friendly places.
///
/// The MVP ships bundled example places rather than live listings, and says so
/// on the screen. Building the structure now — categories, saving, detail,
/// directions — means the swap to a real provider changes `PlaceRepository` and
/// nothing else.
struct ExploreScreen: View {
    let startWalk: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var places: [Place] = []
    @State private var savedIDs: Set<UUID> = []
    @State private var categoryFilter: PlaceCategory?
    @State private var isMapMode = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading = true
    /// Set only when permission was already granted from a previous walk —
    /// Explore never triggers the system prompt itself.
    @State private var userLocation: Coordinate?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingStateView(message: "Finding places")
                } else if filtered.isEmpty {
                    EmptyStateView(
                        symbolName: "map",
                        title: "Nothing in this category",
                        message: "Try another category to see more places.",
                        actionTitle: "Show all",
                        action: { categoryFilter = nil }
                    )
                } else if isMapMode {
                    mapView
                } else {
                    listView
                }
            }
            .navigationTitle("Explore")
            .largeNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isMapMode.toggle()
                    } label: {
                        Label(
                            isMapMode ? "Show list" : "Show map",
                            systemImage: isMapMode ? "list.bullet" : "map"
                        )
                    }
                }
            }
            .navigationDestination(for: Place.self) { place in
                PlaceDetailScreen(
                    place: place,
                    isSaved: savedIDs.contains(place.id),
                    toggleSaved: { await toggleSaved(place) },
                    startWalk: startWalk
                )
            }
            .task { await load() }
        }
    }

    private var listView: some View {
        List {
            Section {
                sampleDataNotice
                if userLocation != nil {
                    Label("Sorted by distance from your current location", systemImage: "location.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }

            Section {
                categoryPicker
            }

            ForEach(filtered) { place in
                NavigationLink(value: place) {
                    PlaceRow(
                        place: place,
                        isSaved: savedIDs.contains(place.id),
                        distanceText: distanceText(to: place)
                    )
                }
            }
        }
        .groupedListStyle()
    }

    private var mapView: some View {
        Map(position: $camera) {
            ForEach(filtered) { place in
                Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate.clCoordinate)
                    .tint(Theme.Colour.accent)
            }
            if userLocation != nil {
                UserAnnotation()
            }
        }
        .overlay(alignment: .top) {
            sampleDataNotice
                .padding(Theme.Space.m)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .padding(Theme.Space.l)
        }
    }

    private func distanceText(to place: Place) -> String? {
        guard let userLocation else { return nil }
        return formatters.distance(userLocation.distance(to: place.coordinate)) + " away"
    }

    /// Says plainly that these are examples. Showing unverified sample content as
    /// though it were checked, live data would be the kind of quiet dishonesty
    /// this product avoids — someone could drive to a beach on the strength of it.
    private var sampleDataNotice: some View {
        Label(
            "These are example places included with the app. They have not been checked "
            + "and opening times, access and rules may be out of date.",
            systemImage: "info.circle"
        )
        .font(.footnote)
        .foregroundStyle(Theme.Colour.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                CategoryChip(title: "All", symbolName: "square.grid.2x2", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(PlaceCategory.allCases) { category in
                    CategoryChip(
                        title: category.displayName,
                        symbolName: category.symbolName,
                        isSelected: categoryFilter == category
                    ) {
                        categoryFilter = categoryFilter == category ? nil : category
                    }
                }
            }
            .padding(.vertical, Theme.Space.xxs)
        }
    }

    private var filtered: [Place] {
        guard let categoryFilter else { return places }
        return places.filter { $0.category == categoryFilter }
    }

    private func load() async {
        isLoading = true
        userLocation = await model.environment.locationPermissions.currentLocation()
        places = (try? await model.environment.placeRepository.places(near: userLocation)) ?? []
        savedIDs = (try? await model.environment.placeRepository.savedPlaceIDs()) ?? []
        camera = .fitting(places.map(\.coordinate))
        isLoading = false
    }

    private func toggleSaved(_ place: Place) async {
        let willSave = !savedIDs.contains(place.id)
        try? await model.environment.placeRepository.setSaved(willSave, placeID: place.id)
        savedIDs = (try? await model.environment.placeRepository.savedPlaceIDs()) ?? savedIDs
        if willSave { model.environment.analytics.track(.placeSaved) }
    }
}

struct CategoryChip: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .frame(minHeight: Theme.minimumTapTarget)
                .background(isSelected ? Theme.Colour.accent : Theme.Colour.fill)
                .foregroundStyle(isSelected ? .white : Theme.Colour.primaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct PlaceRow: View {
    let place: Place
    let isSaved: Bool
    var distanceText: String?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: place.category.symbolName)
                .font(.body)
                .foregroundStyle(Theme.Colour.accent)
                .frame(width: 40, height: 40)
                .background(Theme.Colour.accent.opacity(0.12), in: RoundedRectangle(
                    cornerRadius: Theme.Radius.small, style: .continuous
                ))

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.headline)
                Text(
                    [place.category.displayName, distanceText]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
            }

            Spacer()

            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryAccent)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [place.name, place.category.displayName, distanceText, isSaved ? "saved" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

struct PlaceDetailScreen: View {
    let place: Place
    let isSaved: Bool
    let toggleSaved: () async -> Void
    let startWalk: () -> Void

    @State private var camera: MapCameraPosition

    init(
        place: Place,
        isSaved: Bool,
        toggleSaved: @escaping () async -> Void,
        startWalk: @escaping () -> Void
    ) {
        self.place = place
        self.isSaved = isSaved
        self.toggleSaved = toggleSaved
        self.startWalk = startWalk
        _camera = State(initialValue: .fitting([place.coordinate], padding: 4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Map(position: $camera, interactionModes: []) {
                    Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate.clCoordinate)
                        .tint(Theme.Colour.accent)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label(place.category.displayName, systemImage: place.category.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.accent)
                    Text(place.summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notes = place.accessNotes {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text("Dog access").font(.headline)
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colour.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            if let leadRequired = place.leadRequired {
                                Label(
                                    leadRequired ? "Lead required" : "Off-lead areas",
                                    systemImage: leadRequired ? "lock" : "lock.open"
                                )
                                .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }

                if !place.facilities.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader("Facilities")
                        WrappingChips(items: place.facilities)
                    }
                }

                VStack(spacing: Theme.Space.s) {
                    PrimaryButton("Start a Walk Here", symbolName: "figure.walk", action: startWalk)
                    SecondaryButton(
                        isSaved ? "Saved" : "Save this place",
                        symbolName: isSaved ? "bookmark.fill" : "bookmark"
                    ) {
                        Task { await toggleSaved() }
                    }
                    SecondaryButton("Open in Maps", symbolName: "arrow.triangle.turn.up.right.circle") {
                        openInMaps()
                    }
                }

                if place.source.isDemonstrationContent {
                    Label(
                        "This is an example place bundled with the app. "
                        + "It has not been verified — check before you travel.",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.Colour.warning)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle(place.name)
        .compactNavigationTitle()
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate.clCoordinate))
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

struct WrappingChips: View {
    let items: [String]

    var body: some View {
        // A simple adaptive grid rather than a hand-rolled flow layout: it wraps
        // correctly at every Dynamic Type size without custom measurement.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colour.fill)
                    .clipShape(Capsule())
            }
        }
    }
}

struct ExploreScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { ExploreScreen(startWalk: {}) }
            .previewDisplayName("List")

        PreviewHost { ExploreScreen(startWalk: {}) }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        PreviewHost {
            NavigationStack {
                PlaceDetailScreen(
                    place: SamplePlaceRepository.samples[0],
                    isSaved: false,
                    toggleSaved: {},
                    startWalk: {}
                )
            }
        }
        .previewDisplayName("Place detail")
    }
}
