import Foundation

/// Explore content for the MVP.
///
/// The places are hand-written examples bundled with the app, all marked
/// `source: .sample` and `isVerified: false`. The Explore screen labels them as
/// examples. They exist so the screen's structure, saving and detail flow can be
/// built and tested before a places provider is chosen — presenting them as live
/// listings would be a straightforward lie about data the app does not have.
///
// TODO: Replace with a real provider once one is selected. The candidates are
// MapKit's MKLocalSearch (free, no dog-specific metadata), a licensed places
// API, or Companion's own community-contributed data with moderation (Phase 4).
// The choice affects cost and moderation obligations, so it is a decision to
// make deliberately rather than by picking whatever is easiest to integrate.
public actor SamplePlaceRepository: PlaceRepository {
    private let store: FileStore?
    private var saved: Set<UUID>

    public init(store: FileStore? = nil, initiallySaved: Set<UUID> = []) {
        self.store = store
        self.saved = initiallySaved
    }

    public func places(near coordinate: Coordinate?) async throws -> [Place] {
        await loadSavedIfNeeded()
        guard let coordinate else { return Self.samples }
        return Self.samples.sorted {
            coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate)
        }
    }

    public func savedPlaceIDs() async throws -> Set<UUID> {
        await loadSavedIfNeeded()
        return saved
    }

    public func setSaved(_ isSaved: Bool, placeID: UUID) async throws {
        await loadSavedIfNeeded()
        if isSaved { saved.insert(placeID) } else { saved.remove(placeID) }
        try await store?.write(Array(saved), to: StorePath.savedPlaces)
    }

    private var hasLoaded = false

    private func loadSavedIfNeeded() async {
        guard !hasLoaded, let store else { hasLoaded = true; return }
        hasLoaded = true
        if let ids = try? await store.read([UUID].self, from: StorePath.savedPlaces) {
            saved.formUnion(ids)
        }
    }

    /// Example destinations around London, chosen because they make the Explore
    /// screen's categories and detail fields visible during development.
    public static let samples: [Place] = [
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000001")!,
            name: "Hampstead Heath",
            category: .park,
            coordinate: Coordinate(latitude: 51.5608, longitude: -0.1629),
            summary: "Large open heath with woodland paths and long sightlines.",
            accessNotes: "Off-lead in most areas. Lead required near the bathing ponds.",
            leadRequired: false,
            facilities: ["Water", "Café", "Parking", "Bins"]
        ),
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000002")!,
            name: "Richmond Park",
            category: .park,
            coordinate: Coordinate(latitude: 51.4425, longitude: -0.2735),
            summary: "Royal park with wide grassland and ancient trees.",
            accessNotes: "Dogs must be on a lead during deer birthing and rutting seasons.",
            leadRequired: true,
            facilities: ["Parking", "Café", "Toilets"]
        ),
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000003")!,
            name: "Epping Forest",
            category: .woodland,
            coordinate: Coordinate(latitude: 51.6620, longitude: 0.0350),
            summary: "Ancient woodland with a network of shaded trails.",
            accessNotes: "Off-lead throughout. Keep dogs close to paths near roads.",
            leadRequired: false,
            facilities: ["Parking", "Trails"]
        ),
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000004")!,
            name: "Camber Sands",
            category: .beach,
            coordinate: Coordinate(latitude: 50.9333, longitude: 0.7900),
            summary: "Wide sandy beach with dunes behind.",
            accessNotes: "Seasonal restrictions apply on the main beach between May and September.",
            leadRequired: false,
            facilities: ["Parking", "Toilets", "Water"]
        ),
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000005")!,
            name: "The Secure Field",
            category: .securedField,
            coordinate: Coordinate(latitude: 51.4100, longitude: -0.3000),
            summary: "Fully fenced private field, booked by the hour.",
            accessNotes: "One dog group at a time. Booking required.",
            leadRequired: false,
            facilities: ["Fenced", "Parking", "Water", "Agility equipment"]
        ),
        Place(
            id: UUID(uuidString: "11111111-0000-0000-0000-000000000006")!,
            name: "The Waterside Inn",
            category: .pub,
            coordinate: Coordinate(latitude: 51.5010, longitude: -0.1200),
            summary: "Riverside pub with a dog-friendly bar and garden.",
            accessNotes: "Dogs welcome in the bar and garden, not in the dining room.",
            leadRequired: true,
            facilities: ["Water bowls", "Garden", "Treats"]
        )
    ]
}
