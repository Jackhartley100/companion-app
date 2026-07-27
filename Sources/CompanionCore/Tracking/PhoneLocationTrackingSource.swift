import Foundation
import CoreLocation

/// Records the owner's route using the iPhone's location hardware.
///
/// This is the only real tracking source in the MVP. It records where the
/// *owner's phone* went — which the rest of the app is careful to describe
/// honestly, because it is not a measurement of the dog's own movement.
///
/// Isolated to the main actor: `CLLocationManager` must be created and
/// configured on a thread with an active run loop, and its delegate callbacks
/// arrive there. Keeping the whole type main-actor-isolated is simpler and
/// safer than scattering `@unchecked Sendable` boxes, and the work it does per
/// callback is a few arithmetic operations.
@MainActor
public final class PhoneLocationTrackingSource: NSObject, ActivityTrackingSource {
    public nonisolated let sourceID = "phone"
    public nonisolated let displayName = "iPhone"
    public nonisolated let capabilities: TrackingCapabilities = [
        .ownerLocation, .speed, .elevation
    ]
    public nonisolated let recordingSource: RecordingSource = .iPhone

    private let manager: CLLocationManager
    private var continuation: AsyncStream<TrackingUpdate>.Continuation?
    private var authorisationContinuations: [CheckedContinuation<LocationAuthorizationStatus, Never>] = []
    private var collected: [RoutePoint] = []
    private var sessionStart: Date?
    private var isSessionActive = false
    private var lastReportedAccuracy: AccuracyLevel = .unusable
    private var hasSignalledInterruption = false
    private var currentLocationContinuation: CheckedContinuation<Coordinate?, Never>?

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Deliver every metre of movement: the route filter downstream decides
        // what counts, and a coarse distance filter here would quantise the
        // route before it can be judged.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        // Lets iOS suspend GPS when the owner is clearly stationary. It resumes
        // automatically, and it materially reduces battery use on a long walk.
        manager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - ActivityTrackingSource

    public func sessionUpdates() -> AsyncStream<TrackingUpdate> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in }
        }
    }

    public func startSession(configuration: TrackingConfiguration) async throws {
        guard !isSessionActive else { throw TrackingError.alreadyRecording }

        let status = LocationAuthorizationStatus(manager.authorizationStatus)
        switch status {
        case .denied: throw TrackingError.authorisationDenied
        case .restricted: throw TrackingError.authorisationRestricted
        case .notDetermined:
            let granted = await requestWhenInUseAuthorization()
            guard granted.isUsable else { throw TrackingError.authorisationDenied }
        case .whenInUse, .always:
            break
        }

        collected = []
        sessionStart = Date()
        isSessionActive = true
        hasSignalledInterruption = false

        #if os(iOS)
        // Requires the "location" background mode in the app's Info.plist. With
        // "when in use" authorisation iOS permits this only while a session is
        // running, which is exactly the guarantee we want to give the owner.
        if configuration.allowsBackgroundUpdates {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        #endif

        manager.startUpdatingLocation()
    }

    public func pauseSession() async throws {
        guard isSessionActive else { throw TrackingError.notRecording }
        // Updates keep flowing so the map still shows where the owner is; the
        // recorder discards them. Stopping the manager outright would mean a
        // cold GPS re-acquisition on resume, which loses the first minute.
    }

    public func resumeSession() async throws {
        guard isSessionActive else { throw TrackingError.notRecording }
    }

    public func stopSession() async throws -> TrackingSessionResult {
        guard isSessionActive, let start = sessionStart else { throw TrackingError.notRecording }
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.allowsBackgroundLocationUpdates = false
        #endif
        isSessionActive = false
        continuation?.finish()
        continuation = nil
        let result = TrackingSessionResult(points: collected, startDate: start, endDate: Date())
        collected = []
        sessionStart = nil
        return result
    }
}

// MARK: - Permission

extension PhoneLocationTrackingSource: LocationPermissionProviding {
    public func currentStatus() async -> LocationAuthorizationStatus {
        LocationAuthorizationStatus(manager.authorizationStatus)
    }

    public func servicesEnabled() async -> Bool {
        // `CLLocationManager.locationServicesEnabled()` blocks; the authorisation
        // status plus a failed-update callback tells us what we need without it.
        manager.authorizationStatus != .restricted
    }

    public func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        let current = LocationAuthorizationStatus(manager.authorizationStatus)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            authorisationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation() async -> Coordinate? {
        guard LocationAuthorizationStatus(manager.authorizationStatus).isUsable else { return nil }
        // `requestLocation()` and `startUpdatingLocation()` are not meant to run
        // together on one manager. A walk recording blocks the rest of the app
        // behind a full-screen cover, so this should not be reachable mid-session
        // in practice, but it costs nothing to make it impossible.
        guard !isSessionActive else { return nil }
        guard currentLocationContinuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            currentLocationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Resolves a pending `currentLocation()` call, if there is one. Safe to
    /// call unconditionally — a no-op when nothing is waiting.
    private func resolveCurrentLocationRequest(with coordinate: Coordinate?) {
        guard let continuation = currentLocationContinuation else { return }
        currentLocationContinuation = nil
        continuation.resume(returning: coordinate)
    }

    private func resolveAuthorisationRequests(with status: LocationAuthorizationStatus) {
        let pending = authorisationContinuations
        authorisationContinuations = []
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PhoneLocationTrackingSource: CLLocationManagerDelegate {
    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        let mapped = LocationAuthorizationStatus(status)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resolveAuthorisationRequests(with: mapped)
            if self.isSessionActive, !mapped.isUsable {
                self.continuation?.yield(.interrupted(.authorisationLost))
            }
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let points = locations.map(RoutePoint.init)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resolveCurrentLocationRequest(with: points.first?.coordinate)
            self.handle(points)
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A one-shot `requestLocation()` call fails through this same
            // delegate method (typically `.locationUnknown` on timeout). Without
            // resolving it here, a failed request would leave its caller
            // suspended forever rather than falling back gracefully.
            self.resolveCurrentLocationRequest(with: nil)
            guard self.isSessionActive else { return }
            switch code {
            case .denied:
                self.continuation?.yield(.interrupted(.authorisationLost))
            case .locationUnknown:
                // Transient: iOS could not get a fix right now but is still
                // trying. Reporting it as a failure would flash an error at the
                // owner mid-walk for something that usually resolves itself.
                self.reportAccuracy(.unusable)
            default:
                self.continuation?.yield(.interrupted(.signalLost))
            }
        }
    }

    private func handle(_ points: [RoutePoint]) {
        guard isSessionActive else { return }
        for point in points {
            reportAccuracy(AccuracyLevel(horizontalAccuracy: point.horizontalAccuracy))
            if hasSignalledInterruption, point.horizontalAccuracy != nil {
                hasSignalledInterruption = false
                continuation?.yield(.resumedAfterInterruption)
            }
            collected.append(point)
            continuation?.yield(.location(point))
        }
    }

    private func reportAccuracy(_ level: AccuracyLevel) {
        guard level != lastReportedAccuracy else { return }
        lastReportedAccuracy = level
        continuation?.yield(.accuracyChanged(level))
        if level == .unusable, !hasSignalledInterruption {
            hasSignalledInterruption = true
            continuation?.yield(.interrupted(.signalLost))
        }
    }
}
