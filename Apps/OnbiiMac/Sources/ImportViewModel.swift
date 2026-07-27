import AppKit
import Foundation
import Observation
import OnbiiArchive
import OnbiiCapture
import OnbiiCore
import OnbiiTranscription
import OnbiiUI
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

    /// The objects in the chosen archive, newest first, plus anything the
    /// person opened from outside it.
    private(set) var objects: [OnbiiBundle] = []
    var selectedObjectID: OnbiiObjectID?

    /// Read from the archive directory on every reload.
    private var archivedObjects: [OnbiiBundle] = []
    /// Opened from outside the archive — a bundle double-clicked in Finder, say.
    /// Applications are views: something the person opened should be visible
    /// even when it does not live in the folder they chose.
    private var externalObjects: [OnbiiBundle] = []

    /// What this app is doing to an object right now. Session-only: never
    /// encoded, never written to a manifest, gone when the app quits.
    private(set) var activity: [OnbiiObjectID: OnbiiObjectActivity] = [:]

    private(set) var state: State = .idle
    private(set) var isCapturing = false
    private(set) var captureDuration: TimeInterval = 0
    private(set) var captureKind: CaptureKind?

    private(set) var availableLanguages: [OnbiiTranscriptionLanguage] = []
    var selectedLanguageID: String = ""

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

    /// Any operation that must finish before another one starts. Every action
    /// in the app was already gated on exactly this combination; naming it once
    /// keeps the toolbar, the menu and the detail pane from drifting apart.
    var isBusy: Bool {
        isImporting || isPreparingCapture || isCapturing || isTranscribing
    }

    /// Derived from the selection rather than stored, so a sidebar selection and
    /// the detail pane cannot drift apart.
    var selectedBundle: OnbiiBundle? {
        guard let selectedObjectID else {
            return nil
        }
        return objects.first { $0.manifest.objectID == selectedObjectID }
    }

    var canTranscribeSelectedBundle: Bool {
        guard let selectedBundle else {
            return false
        }
        return selectedBundle.manifest.hasTranscribableAudio
            && !selectedBundle.manifest.hasTranscript
    }

    /// What a person should see about this object at a glance.
    func indicator(for bundle: OnbiiBundle) -> OnbiiStatusIndicator {
        OnbiiStatusIndicator(bundle.status, activity: activity[bundle.manifest.objectID])
    }

    /// The full path, for the place that has room to show it.
    var archiveDisplayName: String {
        archiveURL?.path(percentEncoded: false) ?? "No archive selected"
    }

    /// Just the folder, for the window subtitle — the full path lives in the
    /// sidebar footer and in Settings, and repeating it in the title bar only
    /// crowds it.
    var archiveShortName: String {
        archiveURL?.lastPathComponent ?? "No archive selected"
    }

    var captureDurationText: String {
        let seconds = Int(captureDuration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    init() {
        restoreArchive()
        reloadObjects()
        Task { await loadLanguages() }
    }

    /// Re-reads the archive folder. The filesystem is the truth every time:
    /// an object that arrived by any route — sync, Finder, another app — is
    /// simply there on the next read.
    func reloadObjects() {
        guard let archiveURL else {
            archivedObjects = []
            rebuildObjects()
            return
        }

        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                let hasAccess = archiveURL.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        archiveURL.stopAccessingSecurityScopedResource()
                    }
                }
                return OnbiiArchiveIndex().objects(in: [archiveURL])
            }.value

            archivedObjects = loaded
            rebuildObjects()
        }
    }

    /// Records a bundle this session just wrote or read, without waiting for a
    /// full reload.
    private func upsert(_ bundle: OnbiiBundle) {
        let objectID = bundle.manifest.objectID

        if let index = archivedObjects.firstIndex(
            where: { $0.manifest.objectID == objectID }
        ) {
            archivedObjects[index] = bundle
        } else if let index = externalObjects.firstIndex(
            where: { $0.manifest.objectID == objectID }
        ) {
            externalObjects[index] = bundle
        } else if isInsideArchive(bundle.url) {
            archivedObjects.append(bundle)
        } else {
            externalObjects.append(bundle)
        }

        rebuildObjects()
    }

    private func rebuildObjects() {
        let archived = Set(archivedObjects.map(\.manifest.objectID))
        objects = (
            archivedObjects
                + externalObjects.filter { !archived.contains($0.manifest.objectID) }
        )
        .sorted { $0.manifest.createdAt > $1.manifest.createdAt }

        if let selectedObjectID,
           !objects.contains(where: { $0.manifest.objectID == selectedObjectID }) {
            self.selectedObjectID = nil
        }
    }

    private func isInsideArchive(_ bundleURL: URL) -> Bool {
        guard let archiveURL else {
            return false
        }
        return bundleURL.standardizedFileURL.deletingLastPathComponent().path
            == archiveURL.standardizedFileURL.path
    }

    var selectedTranscriptionLocale: Locale {
        availableLanguages.first { $0.id == selectedLanguageID }?.locale ?? .current
    }

    private func languageDisplayName(for locale: Locale) -> String {
        availableLanguages.first { $0.id == locale.identifier(.bcp47) }?.displayName
            ?? Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    private func loadLanguages() async {
        let languages = await AppleOnDeviceTranscriber.availableLanguages()
        availableLanguages = languages
        if selectedLanguageID.isEmpty
            || !languages.contains(where: { $0.id == selectedLanguageID }) {
            selectedLanguageID = AppleOnDeviceTranscriber
                .preferredLanguage(among: languages)?.id ?? ""
        }
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

            reloadObjects()
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
                beginCaptureContext(includeApplications: false)
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
                beginCaptureContext(includeApplications: true)
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
                location: pendingCaptureLocation,
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
        guard let bundle = selectedBundle else {
            return
        }
        reveal(bundle)
    }

    /// An object is an ordinary folder. Showing it in Finder is not an escape
    /// hatch from the app; it is the point.
    func reveal(_ bundle: OnbiiBundle) {
        NSWorkspace.shared.activateFileViewerSelecting([bundle.url])
    }

    /// Reveals the archive folder itself, even when it holds nothing yet.
    func revealArchive() {
        guard let archiveURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([archiveURL])
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

        beginTranscribing("Requesting speech recognition access…", for: bundle)
        Task {
            let authorization: OnbiiSpeechAuthorization
            if AppleOnDeviceTranscriber.authorization == .notDetermined {
                guard await confirmGenericSpeechPermissionWording() else {
                    activity[bundle.manifest.objectID] = nil
                    state = .idle
                    return
                }
                authorization = await AppleOnDeviceTranscriber.requestAuthorization()
            } else {
                authorization = AppleOnDeviceTranscriber.authorization
            }
            guard authorization == .authorized else {
                failTranscribing(
                    "Speech recognition permission is required to transcribe.",
                    for: bundle
                )
                return
            }

            await performTranscription(of: bundle)
        }
    }

    private let locationProvider = OnbiiLocationProvider()
    private var pendingCaptureLocation: OnbiiLocation?
    private var pendingCaptureApplications: [OnbiiSourceApplication] = []

    /// Gathers capture context when a recording starts: the audio-producing
    /// apps (for system-audio captures) synchronously, and the location
    /// asynchronously so it never blocks recording. Consumed when the bundle is
    /// written; both are best-effort and may be absent.
    private func beginCaptureContext(includeApplications: Bool) {
        pendingCaptureLocation = nil
        pendingCaptureApplications = includeApplications
            ? OnbiiAudioProcessProbe.outputProducingApplications().map {
                OnbiiSourceApplication(bundleIdentifier: $0.bundleIdentifier, name: $0.name)
            }
            : []
        Task { [weak self] in
            guard let captured = await self?.locationProvider.currentLocation() else {
                return
            }
            self?.pendingCaptureLocation = OnbiiLocation(
                latitude: captured.latitude,
                longitude: captured.longitude,
                horizontalAccuracyMeters: captured.horizontalAccuracyMeters,
                name: captured.name,
                capturedAt: captured.capturedAt
            )
        }
    }

    private func performImport(
        of sourceURL: URL,
        title explicitTitle: String? = nil,
        mediaType explicitMediaType: String? = nil,
        location: OnbiiLocation? = nil,
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
            sourceAgentName: sourceAgentName,
            location: location
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
            upsert(bundle)
            selectedObjectID = bundle.manifest.objectID
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

    /// Transcription progress is both app state and per-object activity: the
    /// status pill says what the app is doing, the object's row says which
    /// object it is doing it to.
    private func beginTranscribing(_ message: String, for bundle: OnbiiBundle) {
        state = .transcribing(message: message)
        activity[bundle.manifest.objectID] = .working(message)
    }

    /// The object is untouched by a failure — only this session's attempt failed.
    private func failTranscribing(_ message: String, for bundle: OnbiiBundle) {
        state = .failed(message: message)
        activity[bundle.manifest.objectID] = .failed(message)
    }

    private func performTranscription(of bundle: OnbiiBundle) async {
        let sourceResources = bundle.manifest.resources.filter {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        guard !sourceResources.isEmpty else {
            failTranscribing("This object contains no source audio.", for: bundle)
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
            let locale = selectedTranscriptionLocale
            if !(await AppleOnDeviceTranscriber.isModelInstalled(for: locale)) {
                let name = languageDisplayName(for: locale)
                beginTranscribing(
                    "Downloading the \(name) language model…",
                    for: bundle
                )
                try await AppleOnDeviceTranscriber.prepareModel(for: locale) { fraction in
                    Task { @MainActor [weak self] in
                        self?.beginTranscribing(
                            "Downloading the \(name) language model… "
                                + "\(Int(fraction * 100))%",
                            for: bundle
                        )
                    }
                }
                await loadLanguages()
            }
            let firstStart = sourceResources.compactMap(\.captureStartedAt).min()
            var tracks = [OnbiiTrackTranscript]()
            var timelineInputs = [
                (transcript: OnbiiTrackTranscript, offset: TimeInterval)
            ]()

            for (index, resource) in sourceResources.enumerated() {
                beginTranscribing(
                    "Transcribing track \(index + 1) of "
                        + "\(sourceResources.count) on this Mac…",
                    for: bundle
                )
                let role = transcriptRole(for: resource.id)
                var transcript = try await transcriber.transcribe(
                    audioURL: bundle.url(for: resource),
                    sourceResourceID: resource.id,
                    sourceRole: role,
                    locale: locale
                )
                beginTranscribing(
                    "Identifying speakers on track \(index + 1)…",
                    for: bundle
                )
                transcript.segments = await Self.diarize(
                    transcript.segments,
                    audioURL: bundle.url(for: resource),
                    labelPrefix: "t\(index)s"
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
                failTranscribing(
                    "No speech was recognized in this recording.",
                    for: bundle
                )
                return
            }

            let generatedAt = Date()
            let anyDiarized = tracks.contains { track in
                track.segments.contains { $0.speakerID != nil }
            }
            let document = OnbiiTranscriptDocument(
                generatedAt: generatedAt,
                tracks: tracks,
                timeline: OnbiiTranscriptTimeline.merge(timelineInputs),
                speakerModel: anyDiarized ? Self.speakerModelName : nil
            )
            beginTranscribing("Attaching transcript to the object…", for: bundle)
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

            let contentURL = processingDirectory.appendingPathComponent("content.md")
            let speakerCount = Set(document.timeline.compactMap(\.speakerID)).count
            try Data(
                OnbiiContentMarkdown.render(
                    title: bundle.manifest.title,
                    createdAt: bundle.manifest.createdAt,
                    sources: bundle.manifest.resources
                        .filter { $0.role == .source }
                        .map {
                            OnbiiContentMarkdown.Source(
                                storedPath: $0.path,
                                originalFilename: $0.originalFilename
                            )
                        },
                    location: bundle.manifest.location,
                    sourceApplications: bundle.manifest.sourceApplications,
                    transcript: OnbiiTranscriptMarkdown.body(document),
                    speakerCount: speakerCount > 0 ? speakerCount : nil
                ).utf8
            ).write(to: contentURL, options: .atomic)

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
                replacements: [
                    OnbiiBundleArtifact(
                        sourceURL: contentURL,
                        resourceID: "content-markdown",
                        role: .humanReadable,
                        path: "content.md",
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
            activity[bundle.manifest.objectID] = nil
            upsert(enriched)
            state = .transcribed(bundleURL: bundle.url)
        } catch {
            failTranscribing(
                error.localizedDescription
                    + " The source recordings were not changed.",
                for: bundle
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
            sourceAgentName: "macOS dual-source call capture",
            location: pendingCaptureLocation,
            sourceApplications: pendingCaptureApplications.isEmpty
                ? nil : pendingCaptureApplications
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
            upsert(bundle)
            selectedObjectID = bundle.manifest.objectID
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
            upsert(bundle)
            selectedObjectID = bundle.manifest.objectID
            state = .opened(bundleURL: bundleURL)
        } catch {
            selectedObjectID = nil
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

    static let speakerModelName = "3D-Speaker CAM++ (VoxCeleb) on-device"

    /// Best-effort rough speaker turns for one track. On any failure (model
    /// missing, unreadable audio) the segments are returned unchanged, so
    /// transcription still succeeds and the transcript falls back to track
    /// labels. Diarization is derived data and never blocks preserving a source.
    static func diarize(
        _ segments: [OnbiiTranscriptSegment],
        audioURL: URL,
        labelPrefix: String
    ) async -> [OnbiiTranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        do {
            let embedder = try OnbiiCoreMLSpeakerEmbedder(audioURL: audioURL)
            return try await OnbiiSpeakerDiarizer().diarize(
                track: segments,
                using: embedder,
                labelPrefix: labelPrefix
            )
        } catch {
            return segments
        }
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
