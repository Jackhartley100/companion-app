import SwiftUI
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
        VStack(spacing: Theme.Space.xl) {
            Spacer(minLength: Theme.Space.xl)

            WelcomeArtwork()
                .frame(maxHeight: 240)

            VStack(spacing: Theme.Space.m) {
                Text(Theme.Brand.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Colour.accent)
                Text(Theme.Brand.tagline)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Theme.Brand.supportingLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.s) {
                PrimaryButton("Get Started", action: getStarted)
                Button("I already have an account", action: signIn)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .frame(minHeight: Theme.minimumTapTarget)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.background)
    }
}

/// An abstract composition standing in for photography.
///
/// Drawn in code rather than shipped as an image so the package has no binary
/// assets to compile, and so it adapts to light and dark without two exports.
// TODO: Replace with commissioned or licensed photography of a dog and owner
// before submission. The layout reserves the same space, so this is a swap of
// this view only.
struct WelcomeArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colour.accent.opacity(0.10))
                .frame(width: 220, height: 220)
            Circle()
                .strokeBorder(Theme.Colour.accent.opacity(0.22), lineWidth: 1)
                .frame(width: 260, height: 260)

            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 78, weight: .light))
                Image(systemName: "dog")
                    .font(.system(size: 54, weight: .light))
            }
            .foregroundStyle(Theme.Colour.accent)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Account

struct AccountScreen: View {
    @Binding var errorMessage: String?
    let onContinue: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Set up Companion")
                    .font(.largeTitle.weight(.bold))
                Text("Your dogs, walks and history are stored on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }

            VStack(spacing: Theme.Space.m) {
                PrimaryButton("Continue on this iPhone", symbolName: "iphone", isLoading: isWorking) {
                    Task {
                        isWorking = true
                        await onContinue()
                        isWorking = false
                    }
                }

                // Stated plainly rather than shown as tappable buttons that fail.
                // An owner should not discover that "Sign in with Apple" does
                // nothing by tapping it.
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                    Label("Email account", systemImage: "envelope")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Colour.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m)
                .background(Theme.Colour.fill.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Text("Coming soon")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, Theme.Space.xxs)
                        .background(Theme.Colour.fill, in: Capsule())
                        .padding(Theme.Space.s)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Sign in with Apple and email accounts are coming in a future update"
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colour.warning)
            }

            Label(
                "Accounts that sync between devices are coming later. "
                + "Until then, deleting the app removes your walks.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(Theme.Colour.secondaryText)

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Owner details

struct OwnerDetailsScreen: View {
    @Binding var profile: UserProfile
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $profile.firstName)
                    .textContentType(.givenName)
            } header: {
                Text("What should we call you?")
            } footer: {
                Text("Used to greet you on the Today screen. Nothing more.")
            }

            Section("Units") {
                Picker("Distance", selection: $profile.preferredDistanceUnit) {
                    ForEach(DistanceUnit.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Weight", selection: $profile.preferredWeightUnit) {
                    ForEach(WeightUnit.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Week starts on", selection: $profile.weekStart) {
                    ForEach(WeekStart.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section {
                PrimaryButton("Continue", isEnabled: !trimmedName.isEmpty, action: onContinue)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About you")
        .compactNavigationTitle()
    }

    private var trimmedName: String {
        profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Ready

struct ReadyScreen: View {
    let dogName: String
    let onFinish: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.Colour.success)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.7)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.m) {
                Text("\(dogName) is ready for her first walk.")
                    .font(.title.weight(.bold))
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

            Spacer()

            PrimaryButton("Start Using Companion", action: onFinish)
        }
        .padding(Theme.Space.xl)
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.companionStandard) { hasAppeared = true }
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeScreen(getStarted: {}, signIn: {})
            .previewDisplayName("Welcome")

        WelcomeScreen(getStarted: {}, signIn: {})
            .preferredColorScheme(.dark)
            .previewDisplayName("Welcome — dark")

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
