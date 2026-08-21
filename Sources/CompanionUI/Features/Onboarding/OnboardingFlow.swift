import SwiftUI
import PhotosUI
import CompanionCore

/// The path from opening the app for the first time to being ready to walk.
///
/// Four steps, none of which asks for anything the first walk does not need.
/// Location and notification permissions are deliberately absent — they are
/// requested later, in the moment they make sense.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var draftProfile = UserProfile()
    @State private var authenticationError: String?

    enum Step: Hashable {
        case welcome
        case account
        case owner
        case addDog
        case ready(dogName: String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome:
                    WelcomeScreen(
                        getStarted: {
                            model.environment.analytics.track(.onboardingStarted)
                            advance(to: .account)
                        },
                        signIn: {
                            model.environment.analytics.track(.onboardingStarted)
                            advance(to: .account)
                        }
                    )
                case .account:
                    AccountScreen(
                        errorMessage: $authenticationError,
                        onContinue: { await continueOnDevice() }
                    )
                case .owner:
                    OwnerDetailsScreen(profile: $draftProfile) {
                        Task {
                            await model.saveProfile(draftProfile)
                            advance(to: .addDog)
                        }
                    }
                case .addDog:
                    DogEditorScreen(mode: .create) { dog in
                        await model.saveDog(dog)
                        model.environment.analytics.track(
                            .dogCreated(
                                hasPhoto: dog.imageReference != nil,
                                hasBreed: dog.breedName?.isEmpty == false
                            )
                        )
                        await createSuggestedGoal(for: dog)
                        advance(to: .ready(dogName: dog.name))
                    }
                case .ready(let dogName):
                    ReadyScreen(dogName: dogName) {
                        Task { await model.completeOnboarding() }
                    }
                }
            }
            // Step changes are animated at the mutation sites (`advance(to:)`)
            // rather than with a blanket `.animation(value:)` over the whole
            // switch, so the animation applies to the step transition itself
            // and not to every layout change inside whichever screen is shown.
            .transition(.opacity)
        }
    }

    /// Moves to the next step, animated unless the owner has asked for reduced
    /// motion.
    private func advance(to next: Step) {
        if reduceMotion {
            step = next
        } else {
            withAnimation(.companionStandard) { step = next }
        }
    }

    private func continueOnDevice() async {
        do {
            let account = try await model.environment.authentication.continueOnDevice()
            draftProfile = UserProfile(
                id: account.id,
                firstName: account.displayName ?? "",
                preferredDistanceUnit: .default(),
                preferredWeightUnit: .default()
            )
            authenticationError = nil
            advance(to: .owner)
        } catch let error as AuthenticationError {
            authenticationError = error.userMessage
        } catch {
            authenticationError = error.localizedDescription
        }
    }

    /// Gives a new dog one starting goal so Today has something to show, rather
    /// than an empty ring on day one.
    private func createSuggestedGoal(for dog: Dog) async {
        let target = Goal.suggestedTarget(
            for: .distance,
            activityLevel: dog.activityLevel,
            period: .weekly
        )
        await model.saveGoal(
            Goal(dogID: dog.id, goalType: .distance, targetValue: target, period: .weekly)
        )
    }
}

// MARK: - Welcome

struct WelcomeScreen: View {
    let getStarted: () -> Void
    let signIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WelcomeHero()
                .frame(height: 420)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: Theme.Space.xl) {
                VStack(spacing: Theme.Space.s) {
                    Text(Theme.Brand.tagline)
                        .font(Theme.Typeface.heroTitle(.largeTitle))
                        .foregroundStyle(Theme.Colour.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Theme.Brand.supportingLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.xxs)
                }

                Spacer(minLength: 0)

                VStack(spacing: Theme.Space.m) {
                    PrimaryButton("Start Walking", trailingSymbolName: "arrow.right", action: getStarted)
                    Button("I already have an account", action: signIn)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(Theme.Colour.secondaryText)
                        .frame(minHeight: Theme.minimumTapTarget)
                }
            }
            .padding(Theme.Space.xl)
            .padding(.top, Theme.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colour.background)
    }
}

/// The looping video (falling back to a photograph, then an abstract
/// composition) at the top of Welcome, dissolving into the page background.
///
/// Both the video and the photograph live in the `Companion` app target, not
/// this package, so neither is visible to `swift build`, `swift test`, or
/// previews run from this package — hence the two-step fallback, which keeps
/// the package self-contained rather than depending on the app target to
/// compile at all.
struct WelcomeHero: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                #if canImport(UIKit)
                if let videoURL = Bundle.main.url(forResource: "WelcomeVideo", withExtension: "mp4") {
                    LoopingVideoPlayer(url: videoURL)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                } else if let photograph = Image.namedIfAvailable("WelcomeArtwork") {
                    photograph
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    WelcomeArtwork()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                #else
                if let photograph = Image.namedIfAvailable("WelcomeArtwork") {
                    photograph
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    WelcomeArtwork()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                #endif

                // Dissolves the photo into the page background rather than
                // hard-cropping it, so the join is invisible in both
                // appearances. Three stops rather than a straight two-colour
                // gradient: a flat fade from clear to opaque reads as a visible
                // band where it crosses the photo's own midtones, but easing
                // through a half-opacity stop blends with whatever the photo is
                // doing underneath first.
                LinearGradient(
                    stops: [
                        .init(color: Theme.Colour.background.opacity(0), location: 0),
                        .init(color: Theme.Colour.background.opacity(0.5), location: 0.6),
                        .init(color: Theme.Colour.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * 0.5)
                .allowsHitTesting(false)
            }
        }
    }
}

/// An abstract composition standing in for photography.
///
/// Used only as a fallback for contexts that cannot see the app's asset
/// catalogue — see `WelcomeHero`. Adapts to light and dark with no separate
/// export, which the real photograph cannot do.
struct WelcomeArtwork: View {
    var body: some View {
        ZStack {
            Theme.Colour.background

            // A soft glow rather than a thin outline — closer to the moody,
            // backlit look of the reference photography this stands in for.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Colour.accent.opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .blur(radius: 10)

            Circle()
                .strokeBorder(Theme.Colour.accent.opacity(0.3), lineWidth: 1)
                .frame(width: 280, height: 280)

            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 88, weight: .semibold))
                Image(systemName: "dog")
                    .font(.system(size: 62, weight: .semibold))
            }
            .foregroundStyle(Theme.Colour.accent)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Account

struct AccountScreen: View {
    @Binding var errorMessage: String?
    let onContinue: () async -> Void

    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                AccountVisualPlaceholder()

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Set up Companion")
                        .font(Theme.Typeface.heroTitle(.title))
                        .foregroundStyle(Theme.Colour.primaryText)
                    Text("Your dogs, walks and history are stored on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }

                PrimaryButton(
                    "Continue on this iPhone",
                    trailingSymbolName: "arrow.right",
                    isLoading: isWorking
                ) {
                    Task {
                        isWorking = true
                        await onContinue()
                        isWorking = false
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colour.warning)
                }

                Label(
                    "Your dogs, walks and history stay on this iPhone and are removed if you delete the app.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colour.background)
    }
}

/// The screen's own artwork — a wide landscape photograph, falling back to a
/// blank placeholder card so the layout already reads correctly on builds
/// where the asset catalogue isn't visible (see `WelcomeHero`'s equivalent
/// two-step fallback for why).
private struct AccountVisualPlaceholder: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            if let photograph = Image.namedIfAvailable("AccountArtwork") {
                photograph
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.Colour.surface
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(Theme.Colour.secondaryText.opacity(0.4))
                    )
            }

            // Dissolves the photo's lower edge into the page background —
            // the same treatment as the Welcome hero — rather than letting
            // the card sit on top of the photo as a hard-edged rectangle.
            LinearGradient(
                stops: [
                    .init(color: Theme.Colour.background.opacity(0), location: 0),
                    .init(color: Theme.Colour.background.opacity(0.55), location: 0.7),
                    .init(color: Theme.Colour.background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .allowsHitTesting(false)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Owner details

struct OwnerDetailsScreen: View {
    @Binding var profile: UserProfile
    let onContinue: () -> Void

    @Environment(AppModel.self) private var model
    @FocusState private var isNameFocused: Bool
    @State private var avatarData: Data?
    @State private var didLoadAvatar = false
    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showsLibraryPicker = false
    @State private var showsAvatarPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("About you")
                        .font(Theme.Typeface.heroTitle(.title))
                        .foregroundStyle(Theme.Colour.primaryText)
                    Text("Just enough to say hello and get your units right.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }

                ownerPhotoPicker

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader("What should we call you?")
                    TextField("First name", text: $profile.firstName)
                        .textContentType(.givenName)
                        .focused($isNameFocused)
                        .foregroundStyle(Theme.Colour.primaryText)
                        .padding(Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colour.surface)
                        .clipShape(Capsule())
                    Text("Used to greet you on the Today screen. Nothing more.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader("When's your birthday?")
                    HStack {
                        Text("Date of birth")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Colour.primaryText)
                        Spacer(minLength: 0)
                        DatePicker(
                            "",
                            selection: dateOfBirthBinding,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .tint(Theme.Colour.accent)
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colour.surface)
                    .clipShape(Capsule())
                    Text("Optional — helps us celebrate the milestones.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader("Units")
                    VStack(spacing: Theme.Space.s) {
                        PillPickerRow(
                            title: "Distance",
                            selection: $profile.preferredDistanceUnit,
                            displayName: \.displayName
                        )
                        PillPickerRow(
                            title: "Weight",
                            selection: $profile.preferredWeightUnit,
                            displayName: \.displayName
                        )
                        PillPickerRow(
                            title: "Week starts on",
                            selection: $profile.weekStart,
                            displayName: \.displayName
                        )
                    }
                }

                PrimaryButton(
                    "Continue",
                    trailingSymbolName: "arrow.right",
                    isEnabled: !trimmedName.isEmpty,
                    action: onContinue
                )
            }
            .padding(Theme.Space.xl)
            // Belt-and-suspenders: `TextField` and `Menu` labels don't
            // reliably pick up `.fontDesign` from the environment the way
            // plain `Text` does, so this screen (unlike Welcome and Account,
            // which are pure `Text`) restates it explicitly.
            .fontDesign(.rounded)
        }
        .background(Theme.Colour.background)
        .compactNavigationTitle()
        .task {
            guard !didLoadAvatar else { return }
            didLoadAvatar = true
            guard let reference = profile.imageReference else { return }
            avatarData = try? await model.environment.imageStore.data(for: reference)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureView(
                onCapture: { data in
                    showsCamera = false
                    Task { await storeAvatar(data) }
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        #endif
        .photosPicker(isPresented: $showsLibraryPicker, selection: $libraryItem, matching: .images)
        .task(id: libraryItem) {
            guard let libraryItem else { return }
            defer { self.libraryItem = nil }
            guard let data = try? await libraryItem.loadTransferable(type: Data.self) else { return }
            await storeAvatar(data)
        }
        .sheet(isPresented: $showsAvatarPicker) {
            AvatarPickerSheet { avatar in
                showsAvatarPicker = false
                Task { await storeAvatar(avatar.renderedData()) }
            }
        }
    }

    private var ownerPhotoPicker: some View {
        HStack(spacing: Theme.Space.l) {
            ZStack {
                if let avatarData, let image = Image(data: avatarData) {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(Theme.Colour.surface)
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(avatarData == nil ? "Add a photo" : "Change photo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.primaryText)
                Text("Optional — or pick an avatar instead.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(Theme.Colour.surface)
        .clipShape(Capsule())
        .overlay(
            Menu {
                #if os(iOS)
                if CameraAvailability.isAvailable {
                    Button("Take Photo", systemImage: "camera") { showsCamera = true }
                }
                #endif
                Button("Choose from Library", systemImage: "photo.on.rectangle") {
                    showsLibraryPicker = true
                }
                Button("Choose an Avatar", systemImage: "person.crop.circle") {
                    showsAvatarPicker = true
                }
                if avatarData != nil {
                    Button("Remove Photo", systemImage: "trash", role: .destructive) {
                        Task { await removeAvatar() }
                    }
                }
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .menuStyle(.button)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(avatarData == nil ? "Add a photo" : "Change photo")
        .accessibilityHint("Opens options to take a photo, choose one, or pick an avatar")
    }

    private func storeAvatar(_ data: Data) async {
        guard let reference = try? await model.environment.imageStore.store(data) else { return }
        if let previous = profile.imageReference {
            try? await model.environment.imageStore.delete(reference: previous)
        }
        profile.imageReference = reference
        avatarData = data
    }

    private func removeAvatar() async {
        if let previous = profile.imageReference {
            try? await model.environment.imageStore.delete(reference: previous)
        }
        profile.imageReference = nil
        avatarData = nil
    }

    private var trimmedName: String {
        profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `DatePicker` needs a non-optional `Date` to bind to; this supplies a
    /// reasonable starting point (30 years back) the first time the picker
    /// opens on a profile with no birthday set yet, without writing anything
    /// to `profile.dateOfBirth` until the owner actually changes it.
    private var dateOfBirthBinding: Binding<Date> {
        Binding(
            get: {
                profile.dateOfBirth
                    ?? Calendar.current.date(byAdding: .year, value: -30, to: Date())
                    ?? Date()
            },
            set: { profile.dateOfBirth = $0 }
        )
    }
}

/// A stand-in for a real photo, offered to owners who would rather not
/// upload one. Each case renders to raster data on selection — see
/// `renderedData()` — so it flows through the same `ImageStore` pipeline as
/// a real photo, and nothing downstream needs to know the difference.
///
/// Cases with no illustration yet fall back to a symbol-on-a-tint swatch;
/// `imageAssetName` is how a case graduates from placeholder to real
/// artwork, without touching the picker or the storage path.
enum PresetAvatar: String, CaseIterable, Identifiable {
    case fern, clay, denim, brass

    var id: String { rawValue }

    var imageAssetName: String? {
        switch self {
        case .fern: "Avatar1"
        case .clay: "Avatar2"
        case .denim: "Avatar3"
        case .brass: "Avatar4"
        }
    }

    var tint: Color {
        switch self {
        case .fern: Theme.Colour.accent
        case .clay: Theme.Colour.Tier.bronze
        case .denim: Theme.Colour.route
        case .brass: Theme.Colour.secondaryAccent
        }
    }

    @ViewBuilder
    func swatch(size: CGFloat) -> some View {
        ZStack {
            if let imageAssetName, let photograph = Image.namedIfAvailable(imageAssetName) {
                photograph.resizable().scaledToFill()
            } else {
                Circle().fill(tint.opacity(0.22))
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @MainActor
    func renderedData() -> Data {
        let renderer = ImageRenderer(content: swatch(size: 240))
        renderer.scale = 3
        #if canImport(UIKit)
        return renderer.uiImage?.pngData() ?? Data()
        #else
        return Data()
        #endif
    }
}

/// A grid of preset avatars, offered from the owner photo picker as an
/// alternative to a real photo.
private struct AvatarPickerSheet: View {
    let onPick: (PresetAvatar) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: Theme.Space.l)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Space.l) {
                    ForEach(PresetAvatar.allCases) { avatar in
                        Button { onPick(avatar) } label: {
                            avatar.swatch(size: 84)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(avatar.rawValue.capitalized) avatar")
                    }
                }
                .padding(Theme.Space.xl)
            }
            .background(Theme.Colour.background)
            .navigationTitle("Choose an Avatar")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }
}

// MARK: - Ready

struct ReadyScreen: View {
    let dogName: String
    let onFinish: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ReadyBackground()
                .ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Theme.Colour.accent.opacity(0.16))
                        .frame(width: 132, height: 132)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Theme.Colour.accent)
                }
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.7)
                .accessibilityHidden(true)

                VStack(spacing: Theme.Space.m) {
                    Text("\(dogName) is ready to walk.")
                        .font(Theme.Typeface.heroTitle(.title))
                        .foregroundStyle(Theme.Colour.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Tap Start Walk whenever you head out. "
                        + "Companion will draw your route and keep a record of every adventure."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryButton("Start Exploring", trailingSymbolName: "arrow.right", action: onFinish)

                Spacer(minLength: 0)
            }
            .padding(Theme.Space.xl)
        }
        .fontDesign(.rounded)
        .background(Theme.Colour.background)
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.companionStandard) { hasAppeared = true }
        }
    }
}

/// The aerial route photograph behind the whole screen, dimmed so the
/// celebration text and CTA stay readable over it end to end — not just
/// dissolving into the page background at the bottom, since here the photo
/// fills the entire screen rather than a hero band at the top.
private struct ReadyBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let photograph = Image.namedIfAvailable("ReadyArtwork") {
                    photograph
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true)
                } else {
                    Theme.Colour.background
                }

                Theme.Colour.background.opacity(0.72)
            }
        }
        .allowsHitTesting(false)
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(getStarted: {}, signIn: {})
            .previewDisplayName("Welcome")

        WelcomeScreen(getStarted: {}, signIn: {})
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Welcome — large text")

        NavigationStack { AccountScreen(errorMessage: .constant(nil), onContinue: {}) }
            .previewDisplayName("Account")

        NavigationStack {
            AccountScreen(
                errorMessage: .constant(
                    AuthenticationError.notConfigured("the backend is not built yet").userMessage
                ),
                onContinue: {}
            )
        }
        .previewDisplayName("Account — error")

        NavigationStack {
            OwnerDetailsScreen(profile: .constant(UserProfile(firstName: "Jack"))) {}
        }
        .previewDisplayName("Owner details")

        ReadyScreen(dogName: "Roxy") {}
            .previewDisplayName("Ready")

        ReadyScreen(dogName: "Roxy") {}
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Ready — large text")

        PreviewHost(store: InMemoryStore()) { OnboardingFlow() }
            .previewDisplayName("Full flow")
    }
}
