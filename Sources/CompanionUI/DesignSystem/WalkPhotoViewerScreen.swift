import SwiftUI
import CompanionCore

/// `String` has no stable identity of its own to hang a `.sheet(item:)` on, so
/// every screen that opens `WalkPhotoViewerScreen` from a tapped reference
/// shares this one wrapper rather than each declaring its own.
public struct PhotoViewerTarget: Identifiable {
    public let id: String
    public init(_ reference: String) { self.id = reference }
}

/// A full-screen, swipeable viewer for a walk's photos, opened from a
/// thumbnail tap anywhere in the app — the summary, activity detail, or the
/// all-photos gallery.
public struct WalkPhotoViewerScreen: View {
    private let references: [String]
    private let imageStore: any ImageStore
    /// Given the reference on screen, the caption to show for it — a closure
    /// rather than a fixed string, so the caption follows a swipe between
    /// photos from different walks (as in the all-photos gallery) instead of
    /// staying pinned to whichever photo was originally tapped.
    private let caption: ((String) -> String?)?

    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    public init(
        references: [String],
        startingAt startReference: String,
        imageStore: any ImageStore,
        caption: ((String) -> String?)? = nil
    ) {
        self.references = references
        self.imageStore = imageStore
        self.caption = caption
        _index = State(initialValue: references.firstIndex(of: startReference) ?? 0)
    }

    /// Convenience for the common case: every photo in the viewer shares one
    /// caption (a single walk's title, for instance).
    public init(
        references: [String],
        startingAt startReference: String,
        imageStore: any ImageStore,
        fixedCaption: String?
    ) {
        self.init(
            references: references,
            startingAt: startReference,
            imageStore: imageStore,
            caption: fixedCaption.map { text in { _ in text } }
        )
    }

    public var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(references.enumerated()), id: \.offset) { offset, reference in
                    WalkPhotoThumbnail(
                        reference: reference,
                        imageStore: imageStore,
                        cornerRadius: 0,
                        contentMode: .fit
                    )
                    .tag(offset)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: references.count > 1 ? .automatic : .never))
            #endif
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let text = caption.flatMap({ references.indices.contains(index) ? $0(references[index]) : nil }) {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.4))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
