import Foundation
import Observation
import OnbiiArchive
import OnbiiCapture
import OnbiiCore
import OnbiiProcessing
import OnbiiTranscription
import OnbiiUI
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
        /// Preserved. The second value carries anything the archive noticed
        /// while preserving it — a capture that reported a duration the file
        /// does not bear out, for instance. The object is safe either way; an
        /// app that stayed quiet about this is how a twenty-minute recording
        /// came to be filed as zero seconds.
        case completed(String, warning: String? = nil)
        case failed(String)
    }

    private let recorder = OnbiiMicrophoneRecorder()
    private var durationTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var archiveURL: URL?
    /// Set when a recording ended without being asked to, and carried through to
    /// the message shown once what was captured has been preserved.
    private var pendingInterruption: String?

    private(set) var state: State = .preparingArchive
    private(set) var duration: TimeInterval = 0
    private(set) var objects = [OnbiiBundle]()
    private(set) var archiveDescription = "Connecting to iCloud Drive…"
    /// What this app is doing to an object right now. Session-only: never
    /// encoded, never written to a manifest.
    private(set) var activity = [OnbiiObjectID: OnbiiObjectActivity]()
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

    /// Re-checks a recording the app believes is running.
    ///
    /// Called every time the app becomes active. A suspended app cannot notice
    /// its own suspension, so returning to the foreground is the first honest
    /// chance — this is what was missing when an auto-locking phone cut a 44 s
    /// recording short without a word.
    func verifyRecordingIsStillRunning() {
        guard state == .recording,
              let interruption = recorder.verifyStillRecording() else {
            return
        }
        handle(interruption)
    }

    func startRecording() {
        guard !isBusy else {
            return
        }
        pendingInterruption = nil
        state = .preparing
        // Asked here rather than at launch: a permission prompt makes sense next
        // to the thing it is for. Never blocks the recording.
        Task { await OnbiiNotifier.requestAuthorizationIfNeeded() }
        Task {
            guard await recorder.requestPermission() else {
                state = .failed("Microphone permission is required to record.")
                return
            }
            do {
                let url = try makeCaptureURL()
                recordingStartedAt = Date()
                let recorder = self.recorder
                // Activate the audio session off the main actor; setActive is
                // synchronous and warns about UI unresponsiveness on the main
                // thread.
                try await Task.detached(priority: .userInitiated) {
                    try recorder.startRecording(to: url)
                }.value
                beginCaptureLocation()
                duration = 0
                state = .recording
                beginDurationUpdates()
                observeInterruptions()
            } catch {
                recordingStartedAt = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Listens for the recording dying while the app is running. The other half
    /// of the problem — the app not running at all — is
    /// ``verifyRecordingIsStillRunning()``.
    private func observeInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            guard let interruptions = self?.recorder.interruptions else { return }
            for await interruption in interruptions {
                guard let self, state == .recording else { return }
                handle(interruption)
                return
            }
        }
    }

    /// Preserves what reached the file and says what happened. An interruption
    /// is not a reason to discard audio.
    private func handle(_ interruption: OnbiiCaptureInterruption) {
        pendingInterruption = interruption.message
        // A pocketed phone is exactly the case this matters in, and exactly the
        // case where nobody sees the status line.
        Task { await OnbiiNotifier.captureStopped(interruption.message) }
        stopRecording()
    }

    func stopRecording() {
        interruptionTask?.cancel()
        interruptionTask = nil
        let finalDuration = recorder.duration
        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil
        duration = finalDuration
        durationTask?.cancel()
        durationTask = nil

        Task {
            let recorder = self.recorder
            // Stop + deactivate the audio session off the main actor.
            let sourceURL = await Task.detached(priority: .userInitiated) {
                recorder.stopRecording()
            }.value
            guard let sourceURL else {
                return
            }
            await preserve(
                sourceURL,
                title: OnbiiRecordingName(startedAt: startedAt).title,
                mediaType: "audio/mp4",
                action: "captured",
                agent: "iPhone microphone capture",
                captureStartedAt: startedAt,
                durationSeconds: finalDuration,
                location: pendingCaptureLocation,
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
            // A Watch recording that fails to land is as silent as one that was
            // never made, and the person believes it is already in the archive.
            Task { await OnbiiNotifier.captureStopped(errorMessage) }
            return
        }
        reloadObjects()
        if let bundleURL = notification.userInfo?["bundleURL"] as? URL {
            state = .completed(
                bundleURL.lastPathComponent,
                warning: notification.userInfo?["warning"] as? String
            )
        }
    }

    // MARK: Repairing recorded facts

    /// What each object would gain from being repaired. Session-only; filled in
    /// as objects are looked at, cleared once one is repaired.
    private(set) var repairFindings = [OnbiiObjectID: OnbiiObjectRepair.Findings]()

    /// Checks quietly, so the object can offer the repair rather than the person
    /// having to suspect it. Reads only; writes nothing.
    func checkForRepairs(_ bundle: OnbiiBundle) {
        let objectID = bundle.manifest.objectID
        guard repairFindings[objectID] == nil else { return }
        Task { [weak self] in
            let findings = await OnbiiObjectRepair().findings(
                for: bundle,
                resolvingPlaceName: { latitude, longitude in
                    await OnbiiLocationProvider.placeName(
                        latitude: latitude, longitude: longitude
                    )
                }
            )
            self?.repairFindings[objectID] = findings
        }
    }

    /// Corrects what the object records about itself, and regenerates its
    /// readable facet so it stops repeating what was wrong.
    ///
    /// Deliberate, never automatic: an object is not rewritten because someone
    /// looked at it.
    func repair(_ bundle: OnbiiBundle) {
        guard !isBusy else { return }
        let objectID = bundle.manifest.objectID
        activity[objectID] = .working("Correcting what this object records…")
        Task {
            do {
                let hasAccess = bundle.url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { bundle.url.stopAccessingSecurityScopedResource() }
                }
                let (repaired, _) = try await OnbiiObjectRepair().repair(
                    bundle,
                    resolvingPlaceName: { latitude, longitude in
                        await OnbiiLocationProvider.placeName(
                            latitude: latitude, longitude: longitude
                        )
                    }
                )
                activity[objectID] = nil
                repairFindings[objectID] = OnbiiObjectRepair.Findings()
                if let index = objects.firstIndex(where: {
                    $0.manifest.objectID == objectID
                }) {
                    objects[index] = repaired
                }
            } catch {
                activity[objectID] = .failed(error.localizedDescription)
                state = .failed(
                    error.localizedDescription + " The object was not changed."
                )
            }
        }
    }

    // MARK: Place names

    /// Names resolved for objects whose manifest has coordinates but no label.
    /// Session-only: never encoded, never written to a manifest.
    private var resolvedPlaceNames = [OnbiiObjectID: String]()

    /// What to show for an object's location.
    ///
    /// The manifest's own label wins. Failing that, the coordinates are resolved
    /// for display — the objects from the first field test all carry good
    /// coordinates and an empty name, because the geocoder happened to have no
    /// label for a spot in a park that morning, and a name it can produce today
    /// is worth showing.
    ///
    /// This resolves for **display only**; nothing is written back. Coordinates
    /// are what the object recorded and a name has always been best-effort, so a
    /// view is the right place to resolve one. It does mean `content.md` still
    /// shows coordinates to anything reading the object outside this app —
    /// putting the name in the object itself is a repair, with its own
    /// provenance, and is not this.
    func locationDescription(for bundle: OnbiiBundle) -> String? {
        guard let location = bundle.manifest.location else { return nil }
        if let name = location.resolvedName {
            return name
        }
        if let resolved = resolvedPlaceNames[bundle.manifest.objectID] {
            return resolved
        }
        return String(
            format: "%.4f, %.4f", location.latitude, location.longitude
        )
    }

    /// Best-effort, and quiet about failing: an unresolvable spot simply keeps
    /// showing its coordinates, which were never wrong.
    func resolvePlaceNameIfNeeded(for bundle: OnbiiBundle) {
        let objectID = bundle.manifest.objectID
        guard let location = bundle.manifest.location,
              location.resolvedName == nil,
              resolvedPlaceNames[objectID] == nil else {
            return
        }
        Task { [weak self] in
            guard let name = await OnbiiLocationProvider.placeName(
                latitude: location.latitude,
                longitude: location.longitude
            ) else {
                return
            }
            self?.resolvedPlaceNames[objectID] = name
        }
    }

    var selectedTranscriptionLocale: Locale {
        availableLanguages.first { $0.id == selectedLanguageID }?.locale ?? .current
    }

    /// What a person should see about this object at a glance.
    func indicator(for bundle: OnbiiBundle) -> OnbiiStatusIndicator {
        OnbiiStatusIndicator(bundle.status, activity: activity[bundle.manifest.objectID])
    }

    /// Having a transcript is not a terminal state.
    ///
    /// It used to be — `hasTranscribableAudio && !hasTranscript` — and one
    /// silent wrong language guess then degraded an object permanently, with a
    /// perfectly good source sitting inside it. Under spec decision `0032`
    /// offering to reprocess is a normal capability, not a recovery path; a
    /// second transcript supersedes the first rather than replacing it.
    func canTranscribe(_ bundle: OnbiiBundle) -> Bool {
        bundle.manifest.hasTranscribableAudio
    }

    /// Whether transcribing this object again would supersede something.
    func wouldSupersedeTranscript(_ bundle: OnbiiBundle) -> Bool {
        bundle.manifest.hasTranscript
    }

    /// - Parameter locale: the language to transcribe *this* object in. The
    ///   Settings choice is only a default: which language a recording is in is
    ///   a property of the recording, not of the app, and someone who keeps
    ///   notes in two languages should not have to visit Settings between them.
    func transcribe(_ bundle: OnbiiBundle, in locale: Locale? = nil) {
        let locale = locale ?? selectedTranscriptionLocale
        guard !isBusy else {
            return
        }
        guard bundle.manifest.hasTranscribableAudio else {
            failTranscribing("This object has no source audio to transcribe.", for: bundle)
            return
        }
        beginTranscribing("Requesting speech recognition access…", for: bundle)
        Task {
            let authorization: OnbiiSpeechAuthorization =
                AppleOnDeviceTranscriber.authorization == .notDetermined
                    ? await AppleOnDeviceTranscriber.requestAuthorization()
                    : AppleOnDeviceTranscriber.authorization
            guard authorization == .authorized else {
                failTranscribing(
                    "Speech recognition permission is required to transcribe.",
                    for: bundle
                )
                return
            }
            await performTranscription(of: bundle, in: locale)
        }
    }

    /// Transcription progress is both app state and per-object activity: the
    /// status section says what the app is doing, the object's row says which
    /// object it is doing it to.
    private func beginTranscribing(_ message: String, for bundle: OnbiiBundle) {
        state = .transcribing(message)
        activity[bundle.manifest.objectID] = .working(message)
    }

    /// The object is untouched by a failure — only this session's attempt failed.
    private func failTranscribing(_ message: String, for bundle: OnbiiBundle) {
        state = .failed(message)
        activity[bundle.manifest.objectID] = .failed(message)
    }

    /// The language a transcribe action will use unless another is picked.
    var selectedLanguageDisplayName: String {
        availableLanguages.first { $0.id == selectedLanguageID }?.displayName
            ?? languageDisplayName(for: selectedTranscriptionLocale)
    }

    private func languageDisplayName(for locale: Locale) -> String {
        availableLanguages.first { $0.id == locale.identifier(.bcp47) }?.displayName
            ?? Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    private let locationProvider = OnbiiLocationProvider()
    private var pendingCaptureLocation: OnbiiLocation?

    /// Fetches the capture location asynchronously at record start so it never
    /// blocks recording; best-effort and may be absent. Consumed on preserve.
    private func beginCaptureLocation() {
        pendingCaptureLocation = nil
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

    static let speakerModelName = "3D-Speaker CAM++ (VoxCeleb) on-device"

    /// Best-effort rough speaker turns for one track. On any failure the
    /// segments are returned unchanged, so transcription still succeeds and the
    /// transcript falls back to track labels. Diarization is derived data and
    /// never blocks preserving a source.
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

    /// Restores a remembered choice, or falls back to the system language for a
    /// person who has never chosen.
    ///
    /// The language used to be ordinary view state, so every launch silently
    /// reset it to whatever the phone was set to. That is how a Dutch
    /// conversation came to be transcribed as Australian English: nobody chose
    /// it, and nothing said it had been chosen for them.
    private func loadLanguages() async {
        let languages = await AppleOnDeviceTranscriber.availableLanguages()
        availableLanguages = languages
        let remembered = UserDefaults.standard.string(
            forKey: Self.transcriptionLanguageKey
        )
        if let remembered, languages.contains(where: { $0.id == remembered }) {
            selectedLanguageID = remembered
            return
        }
        if selectedLanguageID.isEmpty
            || !languages.contains(where: { $0.id == selectedLanguageID }) {
            selectedLanguageID = AppleOnDeviceTranscriber
                .preferredLanguage(among: languages)?.id ?? ""
        }
    }

    /// Remembers what the person picked. Called by the settings picker.
    func rememberTranscriptionLanguage() {
        guard !selectedLanguageID.isEmpty else { return }
        UserDefaults.standard.set(
            selectedLanguageID,
            forKey: Self.transcriptionLanguageKey
        )
    }

    private static let transcriptionLanguageKey = "selectedTranscriptionLanguage"

    /// Runs the shared transcription pipeline and reports what it is doing.
    ///
    /// Everything this used to do by hand — recognise, diarize, render, attach —
    /// now lives in `OnbiiProcessing`, alongside the identical copy the Mac had.
    /// What is left is what genuinely belongs to an iPhone app.
    private func performTranscription(of bundle: OnbiiBundle, in locale: Locale) async {
        let hasAccess = bundle.url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                bundle.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let enriched = try await OnbiiTranscriptionRun().run(
                on: bundle,
                language: .init(locale: locale)
            ) { progress in
                Task { @MainActor [weak self] in
                    self?.beginTranscribing(Self.describe(progress), for: bundle)
                }
            }
            await loadLanguages()
            activity[bundle.manifest.objectID] = nil
            if let index = objects.firstIndex(where: {
                $0.manifest.objectID == bundle.manifest.objectID
            }) {
                objects[index] = enriched
            }
            state = .completed(bundle.url.lastPathComponent)
        } catch {
            failTranscribing(
                error.localizedDescription
                    + " The source recording was not changed.",
                for: bundle
            )
        }
    }

    private static func describe(_ progress: OnbiiTranscriptionRun.Progress) -> String {
        switch progress {
        case let .downloadingModel(language, fraction):
            "Downloading the \(language) language model… \(Int(fraction * 100))%"
        case let .transcribing(track, total):
            total > 1
                ? "Transcribing on this iPhone… (\(track)/\(total))"
                : "Transcribing on this iPhone…"
        case let .identifyingSpeakers(track, total):
            total > 1
                ? "Identifying speakers… (\(track)/\(total))"
                : "Identifying speakers…"
        case .attaching:
            "Attaching transcript to the object…"
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
        location: OnbiiLocation? = nil,
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
                sourceAgentName: agent,
                location: location
            )
            let preserved = try await Task.detached(priority: .userInitiated) {
                let result = try OnbiiBundleWriter().preserve(request)
                return (
                    bundle: try OnbiiBundleReader().read(at: destinationURL),
                    mismatches: result.durationMismatches
                )
            }.value
            if removeSourceAfterSuccess {
                try? FileManager.default.removeItem(at: sourceURL)
            }
            objects.insert(preserved.bundle, at: 0)
            // Two independent witnesses: what the app saw happen, and what the
            // archive found in the file. Either alone is worth saying.
            let noticed = [
                pendingInterruption,
                preserved.mismatches.first?.recordedDescription,
            ].compactMap(\.self)
            pendingInterruption = nil
            state = .completed(
                preserved.bundle.url.lastPathComponent,
                warning: noticed.isEmpty ? nil : noticed.joined(separator: " ")
            )
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

    /// Re-reads the archive folders. Both are listed even when iCloud is the
    /// chosen home, so objects preserved locally during an outage stay visible.
    func reloadObjects() {
        guard let archiveURL else {
            return
        }

        var directories = [archiveURL]
        if let localURL = try? localArchiveDirectory(),
           localURL.standardizedFileURL != archiveURL.standardizedFileURL {
            directories.append(localURL)
        }

        objects = OnbiiArchiveIndex().objects(in: directories)
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
