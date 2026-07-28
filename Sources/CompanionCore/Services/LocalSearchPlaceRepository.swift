import Foundation
import MapKit
import CryptoKit

/// Live Explore content: real places near the owner, found through MapKit.
///
/// This replaces `SamplePlaceRepository` as the production repository. Given a
/// location it asks `MKLocalSearch` for parks, beaches, woodland, cafés and
/// pubs around that point, so Explore always reflects where the owner actually
/// is. The bundled samples remain only as a fallback for when there is no
/// location (permission not granted) or the search returns nothing (offline),
/// and the UI labels that fallback as example content.
///
/// What MapKit cannot provide — dog access rules, lead requirements,
/// facilities — is left empty rather than invented, and results are marked
/// `source: .remoteProvider`, `isVerified: false` so the UI can say plainly
/// that dog-friendliness has not been checked.
public actor LocalSearchPlaceRepository: PlaceRepository {
    /// One category's worth of searching. Injectable so tests can supply fake
    /// results instead of hitting MapKit's servers.
    public typealias Search = @Sendable (_ query: String, _ category: PlaceCategory, _ near: Coordinate) async throws -> [Place]

    private let store: FileStore?
    private var saved: Set<UUID>
    private let search: Search

    /// Results are cached per ~1 km grid cell for the session. Explore's
    /// `.task` re-runs every time the tab appears, and re-issuing five
    /// `MKLocalSearch` requests on every tab switch would run into MapKit's
    /// throttling; within a cell the answers would be identical anyway.
    private var cache: [CacheKey: [Place]] = [:]

    public init(
        store: FileStore? = nil,
        initiallySaved: Set<UUID> = [],
        search: @escaping Search = LocalSearchPlaceRepository.mapKitSearch
    ) {
        self.store = store
        self.saved = initiallySaved
        self.search = search
    }

    /// The natural-language queries issued per load. `securedField` and
    /// `waterPoint` have no workable MapKit query, so those categories only
    /// ever contain sample or (later) community content.
    static let liveQueries: [(query: String, category: PlaceCategory)] = [
        ("park", .park),
        ("beach", .beach),
        ("forest woodland", .woodland),
        ("dog friendly cafe", .cafe),
        ("dog friendly pub", .pub)
    ]

    /// How far around the owner a "nearby" search reaches, in metres.
    static let searchSpan: Double = 10_000

    public func places(near coordinate: Coordinate?) async throws -> [Place] {
        await loadSavedIfNeeded()
        guard let coordinate else { return SamplePlaceRepository.samples }

        let key = CacheKey(coordinate)
        if let cached = cache[key] { return cached }

        let results = await liveResults(near: coordinate)
        guard !results.isEmpty else {
            // Offline, throttled, or genuinely nothing around: the labelled
            // samples are more useful than an empty screen, and are not cached
            // so a transient failure recovers on the next visit.
            return SamplePlaceRepository.samples.sorted {
                coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate)
            }
        }
        cache[key] = results
        return results
    }

    private func liveResults(near coordinate: Coordinate) async -> [Place] {
        let search = self.search
        let found = await withTaskGroup(of: [Place].self) { group in
            for (query, category) in Self.liveQueries {
                group.addTask {
                    (try? await search(query, category, coordinate)) ?? []
                }
            }
            var all: [Place] = []
            for await places in group { all.append(contentsOf: places) }
            return all
        }

        // A place can match more than one query ("dog friendly cafe" and
        // "dog friendly pub" overlap); the stable ID makes duplicates collapse.
        var seen = Set<UUID>()
        return found
            .filter { seen.insert($0.id).inserted }
            .sorted { coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate) }
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

    /// A ~1 km grid cell: two decimal places of latitude/longitude. Two loads
    /// from within the same cell share cached results.
    private struct CacheKey: Hashable {
        let latitudeCell: Int
        let longitudeCell: Int

        init(_ coordinate: Coordinate) {
            latitudeCell = Int((coordinate.latitude * 100).rounded())
            longitudeCell = Int((coordinate.longitude * 100).rounded())
        }
    }

    // MARK: - Identity

    /// A deterministic ID from the place's name and position, so that saving a
    /// place survives across sessions even though `MKLocalSearch` results carry
    /// no stable identifier of their own. Coordinates are rounded to ~10 m so a
    /// provider-side jitter in the last decimal places does not orphan a saved
    /// bookmark.
    public static func stableID(name: String, coordinate: Coordinate) -> UUID {
        let key = String(
            format: "%@|%.4f|%.4f",
            name.lowercased(), coordinate.latitude, coordinate.longitude
        )
        let digest = SHA256.hash(data: Data(key.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - MapKit

    /// The production search. Kept static and self-contained: the
    /// `MKLocalSearch` machinery is created, used and discarded inside this one
    /// function, so none of MapKit's non-Sendable types cross an isolation
    /// boundary.
    @Sendable
    public static func mapKitSearch(
        query: String,
        category: PlaceCategory,
        near coordinate: Coordinate
    ) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        // Without this, the text query alone is too loose: "park" happily
        // returns car parks and sports venues. The filter pins results to the
        // kinds of point of interest the category actually means.
        request.pointOfInterestFilter = pointOfInterestFilter(for: category)
        request.region = MKCoordinateRegion(
            center: coordinate.clCoordinate,
            latitudinalMeters: searchSpan,
            longitudinalMeters: searchSpan
        )

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let placeCoordinate = Coordinate(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            return Place(
                id: stableID(name: name, coordinate: placeCoordinate),
                name: name,
                category: category,
                coordinate: placeCoordinate,
                summary: summary(category: category, locality: item.placemark.locality),
                isVerified: false,
                source: .remoteProvider
            )
        }
    }

    /// MapKit has no "woodland" or "pub" point-of-interest category, so those
    /// use the nearest umbrella (parks; restaurants and breweries) and rely on
    /// the query text to narrow within it.
    private static func pointOfInterestFilter(for category: PlaceCategory) -> MKPointOfInterestFilter? {
        switch category {
        case .park: MKPointOfInterestFilter(including: [.park, .nationalPark])
        case .beach: MKPointOfInterestFilter(including: [.beach])
        case .woodland: MKPointOfInterestFilter(including: [.park, .nationalPark])
        case .cafe: MKPointOfInterestFilter(including: [.cafe])
        case .pub: MKPointOfInterestFilter(including: [.restaurant, .brewery])
        case .securedField, .waterPoint: nil
        }
    }

    /// Factual and modest: names the category and town, credits the source,
    /// and does not pretend to knowledge (opening times, dog rules) the app
    /// does not have.
    static func summary(category: PlaceCategory, locality: String?) -> String {
        let what = locality.map { "\(category.displayName) in \($0)" } ?? category.displayName
        return "\(what). Found via Apple Maps — dog access has not been verified."
    }
}
