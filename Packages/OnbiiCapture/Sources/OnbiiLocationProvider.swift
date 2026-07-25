#if canImport(CoreLocation)
import CoreLocation
import Foundation
import MapKit

/// A captured location in the capture domain. The app maps this to the archive
/// model, keeping `OnbiiCapture` free of a dependency on the logical model.
public struct OnbiiCapturedLocation: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracyMeters: Double?
    public var name: String?
    public var capturedAt: Date?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        name: String? = nil,
        capturedAt: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.name = name
        self.capturedAt = capturedAt
    }
}

/// A one-shot location fetch for stamping a recording's capture location.
/// Permission-aware: returns nil when location is unavailable or not granted, so
/// it never blocks a recording. Reverse geocoding to a place name is best-effort.
@MainActor
public final class OnbiiLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Returns the current location, or nil if unavailable/denied. Prompts for
    /// permission on first use. `reverseGeocode` adds a best-effort place name.
    public func currentLocation(
        reverseGeocode: Bool = true
    ) async -> OnbiiCapturedLocation? {
        guard Self.isAuthorized(await ensureAuthorization()) else { return nil }
        guard let location = await requestOneShot() else { return nil }
        let name = reverseGeocode ? await Self.placeName(for: location) : nil
        return OnbiiCapturedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0
                ? location.horizontalAccuracy : nil,
            name: name,
            capturedAt: location.timestamp
        )
    }

    private func ensureAuthorization() async -> CLAuthorizationStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestOneShot() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                finishLocation(nil)  // never leave a recording waiting
            }
        }
    }

    private func finishLocation(_ location: CLLocation?) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: location)
    }

    private static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(macOS)
        return status == .authorizedAlways
        #else
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    /// Best-effort reverse geocode of coordinates to a place name. Lets the
    /// iPhone name a location captured elsewhere (e.g. on the Watch).
    public static func placeName(
        latitude: Double,
        longitude: Double
    ) async -> String? {
        await placeName(
            for: CLLocation(latitude: latitude, longitude: longitude)
        )
    }

    private static func placeName(for location: CLLocation) async -> String? {
        #if os(watchOS)
        return nil  // reverse geocoding happens on the iPhone
        #else
        // MapKit; CLGeocoder is deprecated as of the 26 SDKs.
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else {
            return nil
        }
        return item.addressRepresentations?.cityWithContext
            ?? item.addressRepresentations?.cityName
            ?? item.address?.shortAddress
            ?? item.name
        #endif
    }

    // MARK: CLLocationManagerDelegate

    public nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil
            continuation.resume(returning: status)
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let location = locations.last
        Task { @MainActor in finishLocation(location) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in finishLocation(nil) }
    }
}
#endif
