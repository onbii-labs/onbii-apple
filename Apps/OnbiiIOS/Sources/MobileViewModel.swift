import Foundation
import Observation
import OnbiiArchive
import OnbiiCapture
import OnbiiTranscription
import UniformTypeIdentifiers

@MainActor
@Observable
final class MobileViewModel {
    enum State: Equatable {
        case preparingArchive
        case idle
        case preparing
        case recording
        case preserving
        case transcribing(String)
        case completed(String)
        case failed(String)
    }

    private let recorder = OnbiiMicrophoneRecorder()
    private var durationTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var archiveURL: URL?

    private(set) var state: State = .preparingArchive
    private(set) var duration: TimeInterval = 0
    private(set) var objects = [OnbiiBundle]()
    private(set) var archiveDescription = "Connecting to iCloud Drive…"
    var showsImporter = false
    private(set) var availableLanguages = [OnbiiTranscriptionLanguage]()
    var selectedLanguageID = ""

    var isRecording: Bool {
        state == .recording
    }

    var isBusy: Bool {
        switch state {
        case .preparingArchive, .preparing, .recording, .preserving, .transcribing:
            true
        default:
            false
        }
    }

    var durationText: String {
        let seconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    init() {
        Task {
            await prepareArchive()
        }
        Task {
            await loadLanguages()
        }
    }

    func startRecording() {
        guard !isBusy else {
            return
        }
        state = .preparing
        Task {
            guard await recorder.requestPermission() else {
                state = .failed("Microphone permission is required to record.")
                return
            }
            do {
                let url = try makeCaptureURL()
                recordingStartedAt = Date()
                try recorder.startRecording(to: url)
                duration = 0
                state = .recording
                beginDurationUpdates()
            } catch {
                recordingStartedAt = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        let finalDuration = recorder.duration
        guard let sourceURL = recorder.stopRecording() else {
            return
        }
        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil
        duration = finalDuration
        durationTask?.cancel()
        durationTask = nil

        Task {
            await preserve(
                sourceURL,
                title: OnbiiRecordingName(startedAt: startedAt).title,
                mediaType: "audio/mp4",
                action: "captured",
                agent: "iPhone microphone capture",
                captureStartedAt: startedAt,
                durationSeconds: finalDuration,
                removeSourceAfterSuccess: true
            )
        }
    }

    func importAudio(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            Task {
                let mediaType =
                    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                await preserve(
                    url,
                    title: url.deletingPathExtension().lastPathComponent,
                    mediaType: mediaType,
                    action: "imported",
                    agent: "iPhone Files import"
                )
            }
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    func watchRecordingReceived(_ notification: Notification) {
        if let errorMessage = notification.userInfo?["errorMessage"] as? String {
            state = .failed(errorMessage)
            return
        }
        reloadObjects()
        if let bundleURL = notification.userInfo?["bundleURL"] as? URL {
            state = .completed(bundleURL.lastPathComponent)
        }
    }

    var selectedTranscriptionLocale: Locale {
        availableLanguages.first { $0.id == selectedLanguageID }?.locale ?? .current
    }

    func hasTranscript(_ bundle: OnbiiBundle) -> Bool {
        bundle.manifest.resources.contains { $0.id == "derived-transcript" }
    }

    func transcribe(_ bundle: OnbiiBundle) {
        guard !isBusy else {
            return
        }
        let sources = bundle.manifest.resources.filter {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        guard !sources.isEmpty else {
            state = .failed("This object has no source audio to transcribe.")
            return
        }
        state = .transcribing("Requesting speech recognition access…")
        Task {
            let authorization: OnbiiSpeechAuthorization =
                AppleOnDeviceTranscriber.authorization == .notDetermined
                    ? await AppleOnDeviceTranscriber.requestAuthorization()
                    : AppleOnDeviceTranscriber.authorization
            guard authorization == .authorized else {
                state = .failed(
                    "Speech recognition permission is required to transcribe."
                )
                return
            }
            await performTranscription(of: bundle)
        }
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

    private func performTranscription(of bundle: OnbiiBundle) async {
        let sources = bundle.manifest.resources.filter {
            $0.role == .source && $0.mediaType.hasPrefix("audio/")
        }
        let hasAccess = bundle.url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                bundle.url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let locale = selectedTranscriptionLocale
            if !(await AppleOnDeviceTranscriber.isModelInstalled(for: locale)) {
                let name = languageDisplayName(for: locale)
                state = .transcribing("Downloading the \(name) language model…")
                try await AppleOnDeviceTranscriber.prepareModel(for: locale) { fraction in
                    Task { @MainActor [weak self] in
                        self?.state = .transcribing(
                            "Downloading the \(name) language model… "
                                + "\(Int(fraction * 100))%"
                        )
                    }
                }
                await loadLanguages()
            }

            let transcriber = AppleOnDeviceTranscriber()
            let firstStart = sources.compactMap(\.captureStartedAt).min()
            var tracks = [OnbiiTrackTranscript]()
            var timelineInputs = [
                (transcript: OnbiiTrackTranscript, offset: TimeInterval)
            ]()
            for (index, resource) in sources.enumerated() {
                state = .transcribing(
                    "Transcribing on this iPhone… (\(index + 1)/\(sources.count))"
                )
                let transcript = try await transcriber.transcribe(
                    audioURL: bundle.url(for: resource),
                    sourceResourceID: resource.id,
                    sourceRole: "recording",
                    locale: locale
                )
                let offset: TimeInterval = if let firstStart,
                    let started = resource.captureStartedAt {
                    max(0, started.timeIntervalSince(firstStart))
                } else {
                    0
                }
                tracks.append(transcript)
                timelineInputs.append((transcript, offset: offset))
            }
            guard tracks.contains(where: { !$0.segments.isEmpty }) else {
                state = .failed("No speech was recognized in this recording.")
                return
            }

            let generatedAt = Date()
            let document = OnbiiTranscriptDocument(
                generatedAt: generatedAt,
                tracks: tracks,
                timeline: OnbiiTranscriptTimeline.merge(timelineInputs)
            )
            state = .transcribing("Attaching transcript to the object…")
            let processingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "Transcribing-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: processingDirectory,
                withIntermediateDirectories: true
            )
            defer {
                try? FileManager.default.removeItem(at: processingDirectory)
            }
            let jsonURL = processingDirectory.appendingPathComponent("transcript.json")
            let markdownURL = processingDirectory
                .appendingPathComponent("transcript.md")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
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
                inputResourceIDs: sources.map(\.id)
            )
            let enriched = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleEnricher().enrich(request)
            }.value
            if let index = objects.firstIndex(where: {
                $0.manifest.objectID == bundle.manifest.objectID
            }) {
                objects[index] = enriched
            }
            state = .completed(bundle.url.lastPathComponent)
        } catch {
            state = .failed(
                error.localizedDescription
                    + " The source recording was not changed."
            )
        }
    }

    private func preserve(
        _ sourceURL: URL,
        title: String,
        mediaType: String,
        action: String,
        agent: String,
        captureStartedAt: Date? = nil,
        durationSeconds: TimeInterval? = nil,
        removeSourceAfterSuccess: Bool = false
    ) async {
        state = .preserving
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            guard let archiveURL else {
                throw OnbiiCloudArchiveError.iCloudUnavailable
            }
            let destinationURL = uniqueDestination(for: title, in: archiveURL)
            let sourceExtension = sourceURL.pathExtension
            let storedFilename = sourceExtension.isEmpty
                ? "recording"
                : "recording.\(sourceExtension.lowercased())"
            let request = OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-recording",
                        sourceURL: sourceURL,
                        storedFilename: storedFilename,
                        mediaType: mediaType,
                        captureStartedAt: captureStartedAt,
                        durationSeconds: durationSeconds
                    ),
                ],
                destinationBundleURL: destinationURL,
                title: title,
                createdAt: captureStartedAt ?? Date(),
                sourceAction: action,
                sourceAgentName: agent
            )
            let bundle = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleWriter().write(request)
                return try OnbiiBundleReader().read(at: destinationURL)
            }.value
            if removeSourceAfterSuccess {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            objects.insert(bundle, at: 0)
            state = .completed(bundle.url.lastPathComponent)
        } catch {
            let recovery = removeSourceAfterSuccess
                ? " The temporary recording remains at \(sourceURL.path)."
                : ""
            state = .failed(error.localizedDescription + recovery)
        }
    }

    private func prepareArchive() async {
        do {
            archiveURL = try await Task.detached(priority: .userInitiated) {
                try OnbiiCloudArchive().directoryURL()
            }.value
            archiveDescription = "iCloud Drive → Onbii → Onbii Archive"
        } catch {
            do {
                archiveURL = try localArchiveDirectory()
                archiveDescription =
                    "On My iPhone → Onbii → Onbii Archive (iCloud unavailable)"
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }

        reloadObjects()
        state = .idle
    }

    private func reloadObjects() {
        guard let archiveURL else {
            return
        }

        do {
            var archiveURLs = [archiveURL]
            let localURL = try localArchiveDirectory()
            if localURL.standardizedFileURL != archiveURL.standardizedFileURL {
                archiveURLs.append(localURL)
            }

            objects = archiveURLs
                .flatMap { directory in
                    (try? FileManager.default.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                }
                .filter { $0.pathExtension.lowercased() == "onbii" }
                .compactMap { try? OnbiiBundleReader().read(at: $0) }
                .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func localArchiveDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let archive = documents.appendingPathComponent(
            "Onbii Archive",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: archive,
            withIntermediateDirectories: true
        )
        return archive
    }

    private func makeCaptureURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(
            "capture-\(UUID().uuidString.lowercased()).m4a"
        )
    }

    private func beginDurationUpdates() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else {
                    return
                }
                duration = recorder.duration
            }
        }
    }

    private func uniqueDestination(for title: String, in archiveURL: URL) -> URL {
        let base = safeFilename(title)
        var destination = archiveURL.appendingPathComponent("\(base).onbii")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = archiveURL.appendingPathComponent(
                "\(base) \(suffix).onbii"
            )
            suffix += 1
        }
        return destination
    }

    private func safeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = title.unicodeScalars.map {
            invalid.contains($0) ? "-" : String($0)
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Recording" : cleaned
    }
}
