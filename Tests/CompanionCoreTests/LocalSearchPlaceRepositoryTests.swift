import Testing
import Foundation
@testable import CompanionCore

/// The live repository, tested entirely through its injectable search — no test
/// here ever touches MapKit or the network.
@Suite("Local search place repository")
struct LocalSearchPlaceRepositoryTests {
    private let london = Coordinate(latitude: 51.5074, longitude: -0.1278)

    private func place(
        name: String,
        category: PlaceCategory = .park,
        latitude: Double,
        longitude: Double
    ) -> Place {
        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        return Place(
            id: LocalSearchPlaceRepository.stableID(name: name, coordinate: coordinate),
            name: name,
            category: category,
            coordinate: coordinate,
            summary: "Test",
            source: .remoteProvider
        )
    }

    @Test("No location falls back to the bundled samples")
    func noLocationUsesSamples() async throws {
        let repository = LocalSearchPlaceRepository(search: { _, _, _ in
            Issue.record("Search must not run without a location")
            return []
        })
        let places = try await repository.places(near: nil)
        #expect(places == SamplePlaceRepository.samples)
    }

    @Test("Live results are deduplicated and sorted by distance")
    func liveResultsDedupedAndSorted() async throws {
        let near = place(name: "Near Park", latitude: 51.51, longitude: -0.13)
        let far = place(name: "Far Park", latitude: 51.60, longitude: -0.20)
        let repository = LocalSearchPlaceRepository(search: { _, category, _ in
            // Every category's query returns the same two places, as
            // overlapping MapKit queries do in practice.
            category == .park ? [far, near] : [near]
        })

        let places = try await repository.places(near: london)
        #expect(places.count == 2)
        #expect(places.first?.name == "Near Park")
    }

    @Test("Empty live results fall back to samples sorted by distance")
    func emptyLiveResultsFallBackToSamples() async throws {
        let repository = LocalSearchPlaceRepository(search: { _, _, _ in [] })
        let places = try await repository.places(near: london)
        #expect(!places.isEmpty)
        #expect(places.allSatisfy { $0.source == .sample })
    }

    @Test("A failing search behaves like an empty one rather than throwing")
    func failingSearchFallsBack() async throws {
        struct SearchFailed: Error {}
        let repository = LocalSearchPlaceRepository(search: { _, _, _ in throw SearchFailed() })
        let places = try await repository.places(near: london)
        #expect(places.allSatisfy { $0.source == .sample })
    }

    @Test("Stable IDs are deterministic and insensitive to name casing")
    func stableIDDeterminism() {
        let coordinate = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let first = LocalSearchPlaceRepository.stableID(name: "Hyde Park", coordinate: coordinate)
        let second = LocalSearchPlaceRepository.stableID(name: "hyde park", coordinate: coordinate)
        let elsewhere = LocalSearchPlaceRepository.stableID(
            name: "Hyde Park",
            coordinate: Coordinate(latitude: 53.4, longitude: -2.9)
        )
        #expect(first == second)
        #expect(first != elsewhere)
    }

    @Test("Stable IDs tolerate provider jitter below ~10 m")
    func stableIDToleratesJitter() {
        let first = LocalSearchPlaceRepository.stableID(
            name: "Hyde Park",
            coordinate: Coordinate(latitude: 51.50740, longitude: -0.12780)
        )
        let second = LocalSearchPlaceRepository.stableID(
            name: "Hyde Park",
            coordinate: Coordinate(latitude: 51.507404, longitude: -0.127796)
        )
        #expect(first == second)
    }

    @Test("Saving a live place persists across repository instances")
    func savedPlacePersists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let park = place(name: "Near Park", latitude: 51.51, longitude: -0.13)

        let first = LocalSearchPlaceRepository(store: FileStore(root: root), search: { _, _, _ in [park] })
        try await first.setSaved(true, placeID: park.id)

        let second = LocalSearchPlaceRepository(store: FileStore(root: root), search: { _, _, _ in [park] })
        let saved = try await second.savedPlaceIDs()
        #expect(saved.contains(park.id))
    }
}
