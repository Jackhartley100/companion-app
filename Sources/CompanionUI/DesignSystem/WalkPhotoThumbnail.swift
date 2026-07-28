import SwiftUI
import CompanionCore

/// A single walk photo, loaded lazily from `ImageStore` and cached for the
/// life of the view. Every photo grid and strip in the app is built from this,
/// so a walk's photos look identical whether seen live, in the summary, on
/// activity detail, or in the all-photos gallery.
public struct WalkPhotoThumbnail: View {
    private let reference: String
    private let imageStore: any ImageStore
    private let cornerRadius: CGFloat
    private let contentMode: ContentMode

    @State private var data: Data?
    @State private var failed = false

    public init(
        reference: String,
        imageStore: any ImageStore,
        cornerRadius: CGFloat = Theme.Radius.medium,
        contentMode: ContentMode = .fill
    ) {
        self.reference = reference
        self.imageStore = imageStore
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let data, let image = Image(data: data) {
                image.resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Theme.Colour.fill
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(Theme.Colour.secondaryText)
                    }
            } else {
                Theme.Colour.fill
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: reference) {
            data = nil
            failed = false
            guard let loaded = try? await imageStore.data(for: reference) else {
                failed = true
                return
            }
            data = loaded
        }
    }
}

/// A horizontally scrolling row of photo thumbnails with a leading "add"
/// tile, used while a walk is recording and on its summary. Read-only display
/// (no delete) is `WalkPhotoStrip(canRemove: false)`; the summary screen
/// passes `true` so a mis-tap can be undone.
public struct WalkPhotoStrip: View {
    private let references: [String]
    private let imageStore: any ImageStore
    private let canRemove: Bool
    private let onAdd: (Data) async -> Void
    private let onRemove: ((String) -> Void)?
    private let onTap: ((String) -> Void)?

    public init(
        references: [String],
        imageStore: any ImageStore,
        canRemove: Bool = false,
        onAdd: @escaping (Data) async -> Void,
        onRemove: ((String) -> Void)? = nil,
        onTap: ((String) -> Void)? = nil
    ) {
        self.references = references
        self.imageStore = imageStore
        self.canRemove = canRemove
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onTap = onTap
    }

    private let tileSize: CGFloat = 84

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) {
                AddWalkPhotoButton(label: "Add", symbolName: "camera.fill", onCapture: onAdd)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.Colour.accent)
                    .frame(width: tileSize, height: tileSize)
                    .background(Theme.Colour.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .accessibilityLabel("Add a photo to this walk")

                ForEach(references, id: \.self) { reference in
                    WalkPhotoThumbnail(reference: reference, imageStore: imageStore)
                        .frame(width: tileSize, height: tileSize)
                        .onTapGesture { onTap?(reference) }
                        .overlay(alignment: .topTrailing) {
                            if canRemove {
                                Button {
                                    onRemove?(reference)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                        .font(.system(size: 18))
                                }
                                .padding(4)
                                .accessibilityLabel("Remove this photo")
                            }
                        }
                }
            }
            .padding(.vertical, Theme.Space.xxs)
        }
    }
}
