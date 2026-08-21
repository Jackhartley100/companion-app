import SwiftUI
import CompanionCore
#if canImport(UIKit)
import UIKit
#endif

/// Renders a `WalkStoryCardView` to an image and lets the owner share or save
/// it.
///
/// Rendering happens once, when this screen appears, rather than inside the
/// menu action that presents it — `ImageRenderer` needs the view to actually
/// be laid out, which a plain function call cannot guarantee, and doing it
/// here keeps the loading state (route privacy trimming, the walk's first
/// photo) visible to the owner instead of a menu item that silently pauses.
public struct StorySharePreviewScreen: View {
    private let activity: WalkActivity
    private let dogNames: [String]
    private let route: [RoutePoint]
    private let imageStore: any ImageStore
    private let formatters: Formatters

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: Image?
    #if canImport(UIKit)
    @State private var sharedUIImage: UIImage?
    #endif

    public init(
        activity: WalkActivity,
        dogNames: [String],
        route: [RoutePoint],
        imageStore: any ImageStore,
        formatters: Formatters
    ) {
        self.activity = activity
        self.dogNames = dogNames
        self.route = route
        self.imageStore = imageStore
        self.formatters = formatters
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let renderedImage {
                    ScrollView {
                        VStack(spacing: Theme.Space.xl) {
                            renderedImage
                                .resizable()
                                .aspectRatio(WalkStoryCardView.size.width / WalkStoryCardView.size.height, contentMode: .fit)
                                .frame(maxWidth: 340)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                                .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                                .padding(.top, Theme.Space.l)

                            #if canImport(UIKit)
                            if let sharedUIImage {
                                ShareLink(
                                    item: Image(uiImage: sharedUIImage),
                                    preview: SharePreview(shareTitle, image: Image(uiImage: sharedUIImage))
                                ) {
                                    Label("Share to Story", systemImage: "square.and.arrow.up")
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.Colour.accent)
                                .padding(.horizontal, Theme.Space.l)
                            }
                            #endif

                            Text(privacyNote)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colour.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Space.xl)
                        }
                        .padding(.bottom, Theme.Space.xl)
                    }
                } else {
                    LoadingStateView(message: "Preparing your story card")
                }
            }
            .background(Theme.Colour.groupedBackground)
            .navigationTitle("Share as Story")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await render() }
        }
    }

    private var shareTitle: String {
        "\(activity.title) — \(Theme.Brand.name)"
    }

    private var privacyNote: String {
        RoutePrivacy.canShareMap(route)
            ? "The start and end of your route are trimmed so this never shows where the walk began — usually home."
            : "This walk was too short to show a route without giving away where it started, so only your stats are shown."
    }

    @MainActor
    private func render() async {
        let trimmedRoute = RoutePrivacy.trimmingEndpoints(route).map(\.coordinate)
        let photoData: Data? = if let reference = activity.imageReferences.first {
            try? await imageStore.data(for: reference)
        } else {
            nil
        }

        let card = WalkStoryCardView(
            activity: activity,
            dogNames: dogNames,
            trimmedRoute: trimmedRoute,
            photoData: photoData,
            formatters: formatters
        )

        let renderer = ImageRenderer(content: card)
        // 3x matches the @3x assets the rest of the app ships and lands
        // squarely on 1080×1920 — the standard story canvas — from a
        // 360×640-point view.
        renderer.scale = 3

        #if canImport(UIKit)
        if let uiImage = renderer.uiImage {
            sharedUIImage = uiImage
            renderedImage = Image(uiImage: uiImage)
        } else {
            renderedImage = Image(systemName: "photo")
        }
        #else
        if let nsImage = renderer.nsImage {
            renderedImage = Image(nsImage: nsImage)
        } else {
            renderedImage = Image(systemName: "photo")
        }
        #endif
    }
}
