import Testing
import Foundation
@testable import CompanionCore

@Suite("Sample place repository")
struct SamplePlaceRepositoryTests {
    @Test("With no location, places come back in their bundled order")
    func noLocationReturnsBundledOrder() async throws {
        let repository = SamplePlaceRepository()
        let places = try await repository.places(near: nil)
        #expect(places.map(\.id) == SamplePlaceRepository.samples.map(\.id))
    }

    /// The behaviour Explore actually depends on: passing the owner's real
    /// location reorders the list nearest-first.
    @Test("With a location, places are sorted nearest first")
    func locationSortsByProximity() async throws {
        let repository = SamplePlaceRepository()
        // Directly on top of Richmond Park, which should therefore lead the list.
        let richmondPark = Coordinate(latitude: 51.4425, longitude: -0.2735)

        let places = try await repository.places(near: richmondPark)

        #expect(places.first?.name == "Richmond Park")
        let distances = places.map { richmondPark.distance(to: $0.coordinate) }
        #expect(distances == distances.sorted())
    }

    @Test("Saving and unsaving a place round-trips")
    func savedPlacesRoundTrip() async throws {
        let repository = SamplePlaceRepository()
        let placeID = SamplePlaceRepository.samples[0].id

        #expect(try await repository.savedPlaceIDs().isEmpty)

        try await repository.setSaved(true, placeID: placeID)
        #expect(try await repository.savedPlaceIDs() == [placeID])

        try await repository.setSaved(false, placeID: placeID)
        #expect(try await repository.savedPlaceIDs().isEmpty)
    }
}
