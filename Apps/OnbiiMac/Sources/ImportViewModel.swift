import AppKit
import Foundation
import Observation
import OnbiiArchive
import OnbiiCapture
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportViewModel {
    private static let archiveBookmarkKey = "selectedArchiveBookmark"

    enum State: Equatable {
        case idle
        case importing(filename: String)
        case preparingCapture
        case capturing
        case completed(bundleURL: URL)
        case opened(bundleURL: URL)
        case failed(message: String)
    }

    private let microphoneRecorder = OnbiiMicrophoneRecorder()
    private let systemAudioProbe = OnbiiSystemAudioProbe()
    private var durationTask: Task<Void, Never>?

    var archiveURL: URL?
    private(set) var selectedBundle: OnbiiBundle?
    private(set) var state: State = .idle
    private(set) var isCapturing = false
    private(set) var captureDuration: TimeInterval = 0
    private(set) var systemAudioProbeEvent: OnbiiSystemAudioProbeEvent = .idle

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

    var isSystemAudioProbeActive: Bool {
        switch systemAudioProbeEvent {
        case .starting, .listening, .audioDetected:
            true
        case .idle, .stopped, .failed:
            false
        }
    }

    var systemAudioProbeStatus: String {
        switch systemAudioProbeEvent {
        case .idle:
            "Not running."
        case .starting:
            "Starting the Core Audio application-output tap…"
        case .listening:
            "Listening for remote/application audio. Play audio in another app."
        case .audioDetected:
            "Audible application output is reaching the Core Audio tap."
        case .stopped:
            "Probe stopped."
        case .failed(let message):
            "Probe failed: \(message)"
        }
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
                try microphoneRecorder.startRecording(to: captureURL)
                captureDuration = 0
                isCapturing = true
                state = .capturing
                beginDurationUpdates()
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func startSystemAudioProbe() {
        guard !isImporting, !isPreparingCapture, !isCapturing else {
            return
        }

        systemAudioProbe.begin { [weak self] event in
            self?.systemAudioProbeEvent = event
        }
    }

    func stopSystemAudioProbe() {
        systemAudioProbe.stop()
    }

    func stopCapture() {
        let finalDuration = microphoneRecorder.duration

        guard let captureURL = microphoneRecorder.stopRecording() else {
            return
        }

        captureDuration = finalDuration
        isCapturing = false
        durationTask?.cancel()
        durationTask = nil

        let title = "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        Task {
            await performImport(
                of: captureURL,
                title: title,
                mediaType: "audio/mp4",
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

    private func performImport(
        of sourceURL: URL,
        title explicitTitle: String? = nil,
        mediaType explicitMediaType: String? = nil,
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

    private func beginDurationUpdates() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else {
                    return
                }
                captureDuration = microphoneRecorder.duration
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
