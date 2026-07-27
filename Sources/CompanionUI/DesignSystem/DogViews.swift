import SwiftUI
import CompanionCore

/// Loads an image from the app's image store by reference.
///
/// References are filenames, not absolute paths, because the app container moves
/// between launches and an absolute path saved yesterday may not resolve today.
public struct StoredImage<Placeholder: View>: View {
    private let reference: String?
    private let imageStore: any ImageStore
    private let placeholder: Placeholder

    @State private var loaded: Image?
    @State private var didAttempt = false

    public init(
        reference: String?,
        imageStore: any ImageStore,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.reference = reference
        self.imageStore = imageStore
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let loaded {
                loaded.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: reference) {
            guard let reference, !didAttempt || loaded == nil else { return }
            didAttempt = true
            guard let data = try? await imageStore.data(for: reference) else { return }
            loaded = Image(data: data)
        }
    }
}

extension Image {
    /// Cross-platform construction from raw image data.
    init?(data: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A dog's photo, or their initial when there is no photo.
///
/// The initial matters: a dog must never be identifiable only by a photograph,
/// because that leaves VoiceOver users and anyone who has not added photos with
/// no way to tell two dogs apart.
public struct DogAvatar: View {
    private let dog: Dog
    private let size: CGFloat
    private let imageStore: (any ImageStore)?
    private let isSelected: Bool

    public init(
        dog: Dog,
        size: CGFloat = 44,
        imageStore: (any ImageStore)? = nil,
        isSelected: Bool = false
    ) {
        self.dog = dog
        self.size = size
        self.imageStore = imageStore
        self.isSelected = isSelected
    }

    private var initialView: some View {
        ZStack {
            Circle().fill(Theme.Colour.accent.opacity(0.16))
            Text(dog.initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colour.accent)
        }
    }

    public var body: some View {
        Group {
            if let imageStore, dog.imageReference != nil {
                StoredImage(reference: dog.imageReference, imageStore: imageStore) {
                    initialView
                }
            } else {
                initialView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(
                isSelected ? Theme.Colour.accent : Color.clear,
                lineWidth: 2.5
            )
        }
        .accessibilityHidden(true)
    }
}

/// Picks which dog the screen is about.
///
/// Shown only when the owner has more than one dog — a single-dog owner should
/// never have to interact with a chooser that has one option.
public struct DogSelector: View {
    private let dogs: [Dog]
    @Binding private var selection: UUID?
    private let imageStore: (any ImageStore)?

    public init(dogs: [Dog], selection: Binding<UUID?>, imageStore: (any ImageStore)? = nil) {
        self.dogs = dogs
        self._selection = selection
        self.imageStore = imageStore
    }

    public var body: some View {
        if dogs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.m) {
                    ForEach(dogs) { dog in
                        Button {
                            selection = dog.id
                            Haptics.play(.selectionChanged)
                        } label: {
                            VStack(spacing: Theme.Space.xs) {
                                DogAvatar(
                                    dog: dog,
                                    size: 56,
                                    imageStore: imageStore,
                                    isSelected: dog.id == selection
                                )
                                Text(dog.name)
                                    .font(.caption)
                                    .fontWeight(dog.id == selection ? .semibold : .regular)
                                    .foregroundStyle(
                                        dog.id == selection
                                            ? Theme.Colour.primaryText
                                            : Theme.Colour.secondaryText
                                    )
                            }
                            .frame(minWidth: Theme.minimumTapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dog.name)
                        .accessibilityAddTraits(
                            dog.id == selection ? [.isButton, .isSelected] : .isButton
                        )
                    }
                }
                .padding(.horizontal, Theme.Space.xxs)
            }
            .accessibilityLabel("Choose a dog")
        }
    }
}

/// A row of dog avatars, for showing who came on a walk.
public struct DogAvatarRow: View {
    private let dogs: [Dog]
    private let size: CGFloat
    private let imageStore: (any ImageStore)?

    public init(dogs: [Dog], size: CGFloat = 26, imageStore: (any ImageStore)? = nil) {
        self.dogs = dogs
        self.size = size
        self.imageStore = imageStore
    }

    public var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(dogs) { dog in
                DogAvatar(dog: dog, size: size, imageStore: imageStore)
                    .overlay(Circle().strokeBorder(Theme.Colour.surface, lineWidth: 1.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            dogs.isEmpty ? "No dogs" : "With \(dogs.map(\.name).formatted(.list(type: .and)))"
        )
    }
}

struct DogViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.l) {
                DogAvatar(dog: DemoDataProvider.roxy(), size: 64)
                DogAvatar(dog: DemoDataProvider.bailey(), size: 64, isSelected: true)
            }
            DogSelector(dogs: DemoDataProvider.dogs, selection: .constant(DemoDataProvider.roxyID))
            DogAvatarRow(dogs: DemoDataProvider.dogs, size: 32)
        }
        .padding()
        .previewDisplayName("Light")

        VStack(spacing: Theme.Space.xl) {
            DogSelector(dogs: DemoDataProvider.dogs, selection: .constant(DemoDataProvider.baileyID))
            DogAvatarRow(dogs: DemoDataProvider.dogs, size: 32)
        }
        .padding()
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")

        // A single-dog owner never sees a chooser.
        DogSelector(dogs: [DemoDataProvider.roxy()], selection: .constant(DemoDataProvider.roxyID))
            .padding()
            .previewDisplayName("Single dog — no selector")
    }
}
