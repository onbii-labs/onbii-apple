import AppKit
import Foundation
import Observation
import OnbiiArchive
import OnbiiCapture
import OnbiiTranscription
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportViewModel {
    private static let archiveBookmarkKey = "selectedArchiveBookmark"

    enum CaptureKind: Equatable {
        case microphone
        case call
    }

    enum State: Equatable {
        case idle
        case importing(filename: String)
        case preparingCapture
        case capturing
        case transcribing(message: String)
        case completed(bundleURL: URL)
        case transcribed(bundleURL: URL)
        case opened(bundleURL: URL)
        case failed(message: String)
    }

    private let microphoneRecorder = OnbiiMicrophoneRecorder()
    private let dualCaptureSession = OnbiiDualAudioCaptureSession()
    private var durationTask: Task<Void, Never>?
    private var dualCaptureDirectory: URL?
    private var recordingStartedAt: Date?

    var archiveURL: URL?
    private(set) var selectedBundle: OnbiiBundle?
    private(set) var state: State = .idle
    private(set) var isCapturing = false
    private(set) var captureDuration: TimeInterval = 0
    private(set) var captureKind: CaptureKind?

    var isImporting: Bool {
        if case .importing = state {
            true
        } else {
            false
        }
    }

    var isPreparingCapture: Bool {
        if case .preparingCapture = state {
            true
        } else {
            false
        }
    }

    var isTranscribing: Bool {
        if case .transcribing = state {
            true
        } else {
            false
        }
    }

    var canTranscribeSelectedBundle: Bool {
        guard let selectedBundle else {
            return false
        }
        let hasAudioSource = selectedBundle.manifest.resources.contains {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        let alreadyHasTranscript = selectedBundle.manifest.resources.contains {
            $0.id == "derived-transcript" || $0.id == "transcript-markdown"
        }
        return hasAudioSource && !alreadyHasTranscript
    }

    var archiveDisplayName: String {
        archiveURL?.path(percentEncoded: false) ?? "No archive selected"
    }

    var captureDurationText: String {
        let seconds = Int(captureDuration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    init() {
        restoreArchive()
    }

    func chooseArchive() {
        Task {
            let panel = NSOpenPanel()
            panel.title = "Choose Your Onbii Archive"
            panel.prompt = "Choose Archive"
            panel.message = "Onbii objects will be created in this folder."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false

            guard await present(panel) == .OK, let selectedURL = panel.url else {
                return
            }

            do {
                try persistArchive(selectedURL)
                archiveURL = selectedURL
                state = .idle
            } catch {
                archiveURL = selectedURL
                state = .failed(
                    message: "The archive was selected but could not be remembered: "
                        + error.localizedDescription
                )
            }
        }
    }

    func importAudio() {
        guard archiveURL != nil else {
            state = .failed(message: "Choose an archive folder before importing.")
            return
        }

        Task {
            let panel = NSOpenPanel()
            panel.title = "Import Audio Into Onbii"
            panel.prompt = "Import"
            panel.message = "The original recording will be copied into a new Onbii object."
            panel.allowedContentTypes = [.audio]
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false

            guard await present(panel) == .OK, let sourceURL = panel.url else {
                return
            }

            await performImport(of: sourceURL)
        }
    }

    func startCapture() {
        guard archiveURL != nil else {
            state = .failed(message: "Choose an archive folder before recording.")
            return
        }
        guard !isPreparingCapture, !isCapturing else {
            return
        }

        state = .preparingCapture
        Task {
            guard await microphoneRecorder.requestPermission() else {
                state = .failed(
                    message: "Microphone access is required for explicit capture."
                )
                return
            }

            do {
                let captureURL = try makeCaptureURL()
                let startedAt = Date()
                try microphoneRecorder.startRecording(to: captureURL)
                recordingStartedAt = startedAt
                captureDuration = 0
                captureKind = .microphone
                isCapturing = true
                state = .capturing
                beginDurationUpdates()
            } catch {
                recordingStartedAt = nil
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func startCallCapture() {
        guard archiveURL != nil else {
            state = .failed(message: "Choose an archive folder before recording.")
            return
        }
        guard !isPreparingCapture, !isCapturing else {
            return
        }

        state = .preparingCapture
        Task {
            guard await dualCaptureSession.requestMicrophonePermission() else {
                state = .failed(
                    message: "Microphone access is required to capture your side of the call."
                )
                return
            }

            do {
                let locations = try makeDualCaptureLocations()
                dualCaptureDirectory = locations.directory
                try dualCaptureSession.start(
                    systemAudioURL: locations.systemAudio,
                    microphoneAudioURL: locations.microphoneAudio
                )
                captureDuration = 0
                captureKind = .call
                isCapturing = true
                state = .capturing
                beginDurationUpdates()
            } catch {
                let recoveryMessage = dualCaptureDirectory.map {
                    " Any partial capture files remain at \($0.path)."
                } ?? ""
                state = .failed(message: error.localizedDescription + recoveryMessage)
            }
        }
    }

    func stopCapture() {
        if case .call = captureKind {
            stopCallCapture()
            return
        }

        let finalDuration = microphoneRecorder.duration

        guard let captureURL = microphoneRecorder.stopRecording() else {
            return
        }

        captureDuration = finalDuration
        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil
        isCapturing = false
        captureKind = nil
        durationTask?.cancel()
        durationTask = nil

        let title = OnbiiRecordingName(startedAt: startedAt).title
        Task {
            await performImport(
                of: captureURL,
                title: title,
                mediaType: "audio/mp4",
                sourceAction: "captured",
                sourceAgentName: "macOS microphone capture",
                removeSourceAfterImport: true
            )
        }
    }

    func openBundle(_ bundleURL: URL) {
        Task {
            await performOpen(of: bundleURL)
        }
    }

    func revealSelectedBundle() {
        guard let bundleURL = selectedBundle?.url else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    func transcribeSelectedBundle() {
        guard let bundle = selectedBundle else {
            state = .failed(message: "Open an Onbii bundle before transcribing.")
            return
        }
        guard canTranscribeSelectedBundle else {
            state = .failed(
                message: "This object has no untranscribed source audio."
            )
            return
        }
        guard !isCapturing, !isImporting, !isPreparingCapture, !isTranscribing else {
            return
        }

        state = .transcribing(message: "Requesting speech recognition access…")
        Task {
            let authorization: OnbiiSpeechAuthorization
            if AppleOnDeviceTranscriber.authorization == .notDetermined {
                guard await confirmGenericSpeechPermissionWording() else {
                    state = .idle
                    return
                }
                authorization = await AppleOnDeviceTranscriber.requestAuthorization()
            } else {
                authorization = AppleOnDeviceTranscriber.authorization
            }
            guard authorization == .authorized else {
                state = .failed(
                    message: "Speech recognition permission is required to transcribe."
                )
                return
            }

            await performTranscription(of: bundle)
        }
    }

    private func performImport(
        of sourceURL: URL,
        title explicitTitle: String? = nil,
        mediaType explicitMediaType: String? = nil,
        sourceAction: String = "imported",
        sourceAgentName: String = "macOS file import",
        removeSourceAfterImport: Bool = false
    ) async {
        guard let archiveURL else {
            state = .failed(message: "The selected archive is no longer available.")
            return
        }

        let title = explicitTitle
            ?? sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = uniqueDestination(for: title, in: archiveURL)
        let mediaType = explicitMediaType
            ?? UTType(filenameExtension: sourceURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let request = OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: destinationURL,
            title: title,
            mediaType: mediaType,
            sourceAction: sourceAction,
            sourceAgentName: sourceAgentName
        )

        state = .importing(filename: sourceURL.lastPathComponent)

        let hasSourceAccess = sourceURL.startAccessingSecurityScopedResource()
        let hasArchiveAccess = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if hasSourceAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            if hasArchiveAccess {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bundle = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleWriter().write(request)
                return try OnbiiBundleReader().read(at: destinationURL)
            }.value
            selectedBundle = bundle
            state = .completed(bundleURL: destinationURL)

            if removeSourceAfterImport {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        } catch {
            let recoveryMessage = removeSourceAfterImport
                ? " The captured audio remains at \(sourceURL.path)."
                : ""
            state = .failed(
                message: error.localizedDescription + recoveryMessage
            )
        }
    }

    private func performTranscription(of bundle: OnbiiBundle) async {
        let sourceResources = bundle.manifest.resources.filter {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        guard !sourceResources.isEmpty else {
            state = .failed(message: "This object contains no source audio.")
            return
        }

        let hasBundleAccess = bundle.url.startAccessingSecurityScopedResource()
        let hasArchiveAccess = archiveURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if hasBundleAccess {
                bundle.url.stopAccessingSecurityScopedResource()
            }
            if hasArchiveAccess {
                archiveURL?.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let transcriber = AppleOnDeviceTranscriber()
            let firstStart = sourceResources.compactMap(\.captureStartedAt).min()
            var tracks = [OnbiiTrackTranscript]()
            var timelineInputs = [
                (transcript: OnbiiTrackTranscript, offset: TimeInterval)
            ]()

            for (index, resource) in sourceResources.enumerated() {
                state = .transcribing(
                    message: "Transcribing track \(index + 1) of "
                        + "\(sourceResources.count) on this Mac…"
                )
                let role = transcriptRole(for: resource.id)
                let transcript = try await transcriber.transcribe(
                    audioURL: bundle.url(for: resource),
                    sourceResourceID: resource.id,
                    sourceRole: role
                )
                let offset = if let firstStart, let resourceStart = resource.captureStartedAt {
                    max(0.0, resourceStart.timeIntervalSince(firstStart))
                } else {
                    0.0
                }
                tracks.append(transcript)
                timelineInputs.append((transcript, offset: offset))
            }
            guard tracks.contains(where: { !$0.segments.isEmpty }) else {
                throw AppleOnDeviceTranscriberError.noSpeechDetected
            }

            let generatedAt = Date()
            let document = OnbiiTranscriptDocument(
                generatedAt: generatedAt,
                tracks: tracks,
                timeline: OnbiiTranscriptTimeline.merge(timelineInputs)
            )
            state = .transcribing(message: "Attaching transcript to the object…")
            let processingDirectory = try makeProcessingDirectory()
            defer {
                try? FileManager.default.removeItem(at: processingDirectory)
            }

            let jsonURL = processingDirectory.appendingPathComponent("transcript.json")
            let markdownURL = processingDirectory.appendingPathComponent("transcript.md")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes,
            ]
            try encoder.encode(document).write(to: jsonURL, options: .atomic)
            try Data(
                OnbiiTranscriptMarkdown.render(
                    document,
                    title: bundle.manifest.title
                ).utf8
            ).write(to: markdownURL, options: .atomic)

            let request = OnbiiBundleEnrichmentRequest(
                bundleURL: bundle.url,
                artifacts: [
                    OnbiiBundleArtifact(
                        sourceURL: jsonURL,
                        resourceID: "derived-transcript",
                        role: .derived,
                        path: "derived/transcript.json",
                        mediaType: "application/json"
                    ),
                    OnbiiBundleArtifact(
                        sourceURL: markdownURL,
                        resourceID: "transcript-markdown",
                        role: .humanReadable,
                        path: "transcript.md",
                        mediaType: "text/markdown; charset=utf-8"
                    ),
                ],
                action: "transcribed",
                occurredAt: generatedAt,
                agent: .init(kind: "software", name: "Apple Speech on-device"),
                inputResourceIDs: sourceResources.map(\.id)
            )
            let enriched = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleEnricher().enrich(request)
            }.value
            selectedBundle = enriched
            state = .transcribed(bundleURL: bundle.url)
        } catch {
            state = .failed(
                message: error.localizedDescription
                    + " The source recordings were not changed."
            )
        }
    }

    private func stopCallCapture() {
        let recoveryDirectory = dualCaptureDirectory

        do {
            let result = try dualCaptureSession.stop()
            captureDuration = result.systemAudio.duration
            isCapturing = false
            captureKind = nil
            durationTask?.cancel()
            durationTask = nil
            dualCaptureDirectory = nil

            let startedAt = min(
                result.systemAudio.startedAt,
                result.microphoneAudio.startedAt
            )
            let title = OnbiiRecordingName(startedAt: startedAt).title
            Task {
                await performCallCaptureImport(
                    result,
                    title: title,
                    cleanupDirectory: recoveryDirectory
                )
            }
        } catch {
            isCapturing = false
            captureKind = nil
            durationTask?.cancel()
            durationTask = nil
            dualCaptureDirectory = nil
            let recoveryMessage = recoveryDirectory.map {
                " Partial capture files remain at \($0.path)."
            } ?? ""
            state = .failed(message: error.localizedDescription + recoveryMessage)
        }
    }

    private func performCallCaptureImport(
        _ result: OnbiiDualAudioCaptureResult,
        title: String,
        cleanupDirectory: URL?
    ) async {
        guard let archiveURL else {
            state = .failed(message: "The selected archive is no longer available.")
            return
        }

        let destinationURL = uniqueDestination(for: title, in: archiveURL)
        let request = OnbiiImportRequest(
            sources: [
                OnbiiSourceFile(
                    resourceID: "source-system-audio",
                    sourceURL: result.systemAudio.url,
                    storedFilename: "system-audio.caf",
                    mediaType: "audio/x-caf",
                    captureStartedAt: result.systemAudio.startedAt,
                    durationSeconds: result.systemAudio.duration
                ),
                OnbiiSourceFile(
                    resourceID: "source-microphone-audio",
                    sourceURL: result.microphoneAudio.url,
                    storedFilename: "microphone-audio.m4a",
                    mediaType: "audio/mp4",
                    captureStartedAt: result.microphoneAudio.startedAt,
                    durationSeconds: result.microphoneAudio.duration
                ),
            ],
            destinationBundleURL: destinationURL,
            title: title,
            createdAt: min(
                result.systemAudio.startedAt,
                result.microphoneAudio.startedAt
            ),
            sourceAction: "captured",
            sourceAgentName: "macOS dual-source call capture"
        )

        state = .importing(filename: "system audio and microphone")
        let hasArchiveAccess = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if hasArchiveAccess {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bundle = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleWriter().write(request)
                return try OnbiiBundleReader().read(at: destinationURL)
            }.value
            selectedBundle = bundle
            state = .completed(bundleURL: destinationURL)

            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
        } catch {
            let recoveryMessage = cleanupDirectory.map {
                " The captured source tracks remain at \($0.path)."
            } ?? ""
            state = .failed(message: error.localizedDescription + recoveryMessage)
        }
    }

    private func performOpen(of bundleURL: URL) async {
        let hasAccess = bundleURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                bundleURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let bundle = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleReader().read(at: bundleURL)
            }.value
            selectedBundle = bundle
            state = .opened(bundleURL: bundleURL)
        } catch {
            selectedBundle = nil
            state = .failed(message: error.localizedDescription)
        }
    }

    private func present(_ panel: NSOpenPanel) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await panel.beginSheetModal(for: window)
        }

        NSApp.activate()
        return await panel.begin()
    }

    private func confirmGenericSpeechPermissionWording() async -> Bool {
        let alert = NSAlert()
        alert.messageText = "About macOS Speech Permission"
        alert.informativeText =
            "macOS uses a generic permission message that may say audio is sent "
            + "to Apple. Onbii requires the on-device recognizer for every request. "
            + "If it is unavailable, transcription stops instead of using a server."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
            }
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func restoreArchive() {
        guard let bookmarkData = UserDefaults.standard.data(
            forKey: Self.archiveBookmarkKey
        ) else {
            return
        }

        var isStale = false
        do {
            let restoredURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            archiveURL = restoredURL

            if isStale {
                try persistArchive(restoredURL)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.archiveBookmarkKey)
            archiveURL = nil
            state = .failed(
                message: "The previous archive is no longer available. Choose it again."
            )
        }
    }

    private func persistArchive(_ archiveURL: URL) throws {
        let hasAccess = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                archiveURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try archiveURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: Self.archiveBookmarkKey)
    }

    private func makeCaptureURL() throws -> URL {
        let captureDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true
        )
        return captureDirectory.appendingPathComponent(
            "capture-\(UUID().uuidString.lowercased()).m4a"
        )
    }

    private func makeDualCaptureLocations() throws -> (
        directory: URL,
        systemAudio: URL,
        microphoneAudio: URL
    ) {
        let captureDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Captures", isDirectory: true)
        .appendingPathComponent(
            "call-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true
        )
        return (
            captureDirectory,
            captureDirectory.appendingPathComponent("system-audio.caf"),
            captureDirectory.appendingPathComponent("microphone-audio.m4a")
        )
    }

    private func makeProcessingDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Processing", isDirectory: true)
        .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func transcriptRole(for resourceID: String) -> String {
        switch resourceID {
        case "source-system-audio":
            "system-audio"
        case "source-microphone-audio":
            "microphone"
        default:
            "recording"
        }
    }

    private func beginDurationUpdates() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else {
                    return
                }
                captureDuration = if case .call = captureKind {
                    dualCaptureSession.duration
                } else {
                    microphoneRecorder.duration
                }
            }
        }
    }

    private func uniqueDestination(for title: String, in archiveURL: URL) -> URL {
        let baseName = safeFilename(from: title)
        var candidate = archiveURL.appendingPathComponent("\(baseName).onbii")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = archiveURL.appendingPathComponent("\(baseName) \(suffix).onbii")
            suffix += 1
        }

        return candidate
    }

    private func safeFilename(from title: String) -> String {
        let replacementCharacters = CharacterSet(charactersIn: "/:")
        let cleaned = title.unicodeScalars
            .map { replacementCharacters.contains($0) ? "-" : String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Recording" : cleaned
    }
}
