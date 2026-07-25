import Foundation
import OnbiiArchive
import OnbiiCapture
import OnbiiCore
@preconcurrency import WatchConnectivity

extension Notification.Name {
    static let onbiiWatchRecordingReceived = Notification.Name(
        "onbiiWatchRecordingReceived"
    )
}

final class WatchRecordingReceiver: NSObject, @unchecked Sendable {
    static let shared = WatchRecordingReceiver()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func stage(_ file: WCSessionFile) throws -> URL {
        let fileManager = FileManager.default
        let inboxURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Watch Inbox", isDirectory: true)
        try fileManager.createDirectory(
            at: inboxURL,
            withIntermediateDirectories: true
        )
        let destinationURL = inboxURL.appendingPathComponent(
            "watch-\(UUID().uuidString.lowercased()).m4a"
        )
        try fileManager.moveItem(at: file.fileURL, to: destinationURL)
        return destinationURL
    }

    private func preserve(
        stagedURL: URL,
        metadata: OnbiiWatchRecordingMetadata
    ) async throws -> URL {
        let archiveURL: URL
        do {
            archiveURL = try OnbiiCloudArchive().directoryURL()
        } catch {
            archiveURL = try localArchiveDirectory()
        }

        let title = OnbiiRecordingName(
            startedAt: metadata.captureStartedAt
        ).title
        let destinationURL = uniqueDestination(
            for: title,
            in: archiveURL
        )

        var location: OnbiiLocation?
        if let latitude = metadata.latitude, let longitude = metadata.longitude {
            location = OnbiiLocation(
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracyMeters: metadata.horizontalAccuracyMeters,
                name: await OnbiiLocationProvider.placeName(
                    latitude: latitude, longitude: longitude
                ),
                capturedAt: metadata.captureStartedAt
            )
        }

        let request = OnbiiImportRequest(
            sources: [
                OnbiiSourceFile(
                    resourceID: "source-recording",
                    sourceURL: stagedURL,
                    storedFilename: "recording.m4a",
                    mediaType: "audio/mp4",
                    captureStartedAt: metadata.captureStartedAt,
                    durationSeconds: metadata.durationSeconds
                ),
            ],
            destinationBundleURL: destinationURL,
            title: title,
            createdAt: metadata.captureStartedAt,
            sourceAction: "captured",
            sourceAgentName: "Apple Watch microphone capture",
            location: location
        )
        try OnbiiBundleWriter().write(request)
        try FileManager.default.removeItem(at: stagedURL)
        return destinationURL
    }

    private func localArchiveDirectory() throws -> URL {
        let documentsURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let archiveURL = documentsURL.appendingPathComponent(
            OnbiiCloudArchive.archiveDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: archiveURL,
            withIntermediateDirectories: true
        )
        return archiveURL
    }

    private func uniqueDestination(
        for title: String,
        in archiveURL: URL
    ) -> URL {
        var destinationURL = archiveURL.appendingPathComponent(
            "\(title).onbii"
        )
        var suffix = 2
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = archiveURL.appendingPathComponent(
                "\(title) \(suffix).onbii"
            )
            suffix += 1
        }
        return destinationURL
    }

    private func notify(bundleURL: URL? = nil, error: (any Error)? = nil) {
        Task { @MainActor in
            var userInfo = [String: Any]()
            userInfo["bundleURL"] = bundleURL
            userInfo["errorMessage"] = error?.localizedDescription
            NotificationCenter.default.post(
                name: .onbiiWatchRecordingReceived,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}

extension WatchRecordingReceiver: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let stagedURL: URL
        do {
            stagedURL = try stage(file)
        } catch {
            notify(error: error)
            return
        }

        guard let propertyList = file.metadata,
              let metadata = OnbiiWatchRecordingMetadata(
                  propertyList: propertyList
              )
        else {
            notify(
                error: WatchRecordingReceiverError.invalidMetadata(
                    preservedPath: stagedURL.path
                )
            )
            return
        }

        Task.detached(priority: .utility) { [self] in
            do {
                let bundleURL = try await preserve(
                    stagedURL: stagedURL,
                    metadata: metadata
                )
                notify(bundleURL: bundleURL)
            } catch {
                notify(error: error)
            }
        }
    }
}

private enum WatchRecordingReceiverError: LocalizedError {
    case invalidMetadata(preservedPath: String)

    var errorDescription: String? {
        switch self {
        case .invalidMetadata(let preservedPath):
            "A Watch recording arrived without valid metadata. "
                + "The audio remains at \(preservedPath)."
        }
    }
}
