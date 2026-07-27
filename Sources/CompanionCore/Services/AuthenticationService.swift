import Foundation

/// The signed-in account, such as it exists in the MVP.
public struct Account: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var displayName: String?
    public var email: String?
    /// How the account was established. Surfaced in Settings so the owner is
    /// never misled about whether they have a real, recoverable account.
    public var provider: AuthenticationProvider

    public init(
        id: UUID = UUID(),
        displayName: String? = nil,
        email: String? = nil,
        provider: AuthenticationProvider
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.provider = provider
    }
}

public enum AuthenticationProvider: String, Codable, Sendable {
    case apple
    case email
    /// A local-only account. Data lives on this device and nowhere else.
    case localDevice

    public var displayName: String {
        switch self {
        case .apple: "Sign in with Apple"
        case .email: "Email"
        case .localDevice: "On this device"
        }
    }

    /// Whether the account can be recovered on another device.
    public var isRecoverable: Bool {
        self != .localDevice
    }
}

public enum AuthenticationState: Sendable, Hashable {
    case unknown
    case signedOut
    case signedIn(Account)

    public var account: Account? {
        if case .signedIn(let account) = self { return account }
        return nil
    }
}

public enum AuthenticationError: Error, Sendable, Equatable {
    case cancelled
    case notConfigured(String)
    case failed(String)

    public var userMessage: String {
        switch self {
        case .cancelled:
            "Sign-in was cancelled. Nothing has changed."
        case .notConfigured(let detail):
            "This sign-in method is not available in this build: \(detail)"
        case .failed(let detail):
            "Sign-in could not be completed: \(detail)"
        }
    }
}

public protocol AuthenticationService: Sendable {
    func currentState() async -> AuthenticationState
    func signInWithApple() async throws -> Account
    func signInWithEmail(_ email: String) async throws -> Account
    /// Creates a device-local account so the app is fully usable before any
    /// backend exists.
    func continueOnDevice() async throws -> Account
    func signOut() async throws
}

/// The authentication used by the MVP.
///
/// It creates a real, persisted, device-local account — it does not pretend to
/// talk to a server. `signInWithApple` and `signInWithEmail` therefore throw
/// `.notConfigured`: presenting a fake success for them would tell the owner
/// their data was backed up to an account when it is only on this device.
///
// TODO: Replace with the chosen production identity provider once the backend
// architecture (Phase 2) and the account-deletion requirements for App Store
// review have been settled. The protocol boundary is the only thing the rest of
// the app depends on, so the swap is contained to this file and its registration
// in AppEnvironment.
public actor LocalAuthenticationService: AuthenticationService {
    private let profileRepository: any UserProfileRepository
    private var state: AuthenticationState = .unknown

    public init(profileRepository: any UserProfileRepository) {
        self.profileRepository = profileRepository
    }

    public func currentState() async -> AuthenticationState {
        if case .signedIn = state { return state }
        // A saved profile is what "signed in" means without a backend.
        if let profile = try? await profileRepository.load() {
            let account = Account(
                id: profile.id,
                displayName: profile.firstName.isEmpty ? nil : profile.firstName,
                provider: .localDevice
            )
            state = .signedIn(account)
            return state
        }
        state = .signedOut
        return state
    }

    public func signInWithApple() async throws -> Account {
        throw AuthenticationError.notConfigured(
            "Sign in with Apple needs an App Store team and the Sign In with Apple capability, "
            + "which this build does not have yet."
        )
    }

    public func signInWithEmail(_ email: String) async throws -> Account {
        throw AuthenticationError.notConfigured(
            "Email accounts need the Companion backend, which is not built yet."
        )
    }

    public func continueOnDevice() async throws -> Account {
        let account = Account(provider: .localDevice)
        state = .signedIn(account)
        return account
    }

    public func signOut() async throws {
        state = .signedOut
    }
}

/// Returns a fixed state. For previews and tests.
public struct StubAuthenticationService: AuthenticationService {
    public let state: AuthenticationState

    public init(state: AuthenticationState = .signedIn(Account(provider: .localDevice))) {
        self.state = state
    }

    public func currentState() async -> AuthenticationState { state }
    public func signInWithApple() async throws -> Account {
        state.account ?? Account(provider: .apple)
    }
    public func signInWithEmail(_ email: String) async throws -> Account {
        state.account ?? Account(email: email, provider: .email)
    }
    public func continueOnDevice() async throws -> Account {
        state.account ?? Account(provider: .localDevice)
    }
    public func signOut() async throws {}
}
