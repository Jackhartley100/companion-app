import SwiftUI
import CompanionCore

/// Every photo across every walk, newest first, in one scrollable grid.
///
/// A single walk's photos live on that walk's own screens; this is the other
/// direction — the whole album of a dog's life outdoors, browsable without
/// having to remember which walk a given photo was taken on.
struct WalkPhotosGalleryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var viewingPhoto: PhotoViewerTarget?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: Theme.Space.xs)]

    /// Every (activity, photo) pair, newest walk first, in the order photos
    /// were added within each walk — the same order `WalkPhotoViewerScreen`
    /// will page through.
    private var entries: [(activity: WalkActivity, reference: String)] {
        model.activities
            .sorted { $0.startDate > $1.startDate }
            .flatMap { activity in activity.imageReferences.map { (activity, $0) } }
    }

    private var allReferences: [String] { entries.map(\.reference) }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyStateView(
                    symbolName: "photo.on.rectangle.angled",
                    title: "No photos yet",
                    message: "Take a photo during or after a walk and it will "
                        + "show up here, alongside every other one you've taken."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                        ForEach(entries, id: \.reference) { entry in
                            WalkPhotoThumbnail(
                                reference: entry.reference,
                                imageStore: model.environment.imageStore,
                                cornerRadius: Theme.Radius.small
                            )
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture { viewingPhoto = PhotoViewerTarget(entry.reference) }
                            .accessibilityLabel(
                                "Photo from \(entry.activity.title), "
                                + formatters.dateTime(entry.activity.startDate)
                            )
                        }
                    }
                    .padding(Theme.Space.l)
                }
            }
        }
        .navigationTitle("Walk Photos")
        .compactNavigationTitle()
        .sheet(item: $viewingPhoto) { target in
            WalkPhotoViewerScreen(
                references: allReferences,
                startingAt: target.id,
                imageStore: model.environment.imageStore,
                caption: captionForReference
            )
        }
    }

    private func captionForReference(_ reference: String) -> String? {
        guard let entry = entries.first(where: { $0.reference == reference }) else { return nil }
        return "\(entry.activity.title) — \(formatters.dateTime(entry.activity.startDate))"
    }
}

struct WalkPhotosGalleryScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { WalkPhotosGalleryScreen() }
        }
        .previewDisplayName("Gallery")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { WalkPhotosGalleryScreen() }
        }
        .previewDisplayName("Empty")
    }
}
