import AppKit
import Foundation
import Observation
import OnbiiArchive
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportViewModel {
    private static let archiveBookmarkKey = "selectedArchiveBookmark"

    enum State: Equatable {
        case idle
        case importing(filename: String)
        case completed(bundleURL: URL)
        case failed(message: String)
    }

    var archiveURL: URL?
    private(set) var state: State = .idle

    var isImporting: Bool {
        if case .importing = state {
            true
        } else {
            false
        }
    }

    var archiveDisplayName: String {
        archiveURL?.path(percentEncoded: false) ?? "No archive selected"
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

    func revealLastBundle() {
        guard case .completed(let bundleURL) = state else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    private func performImport(of sourceURL: URL) async {
        guard let archiveURL else {
            state = .failed(message: "The selected archive is no longer available.")
            return
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = uniqueDestination(for: title, in: archiveURL)
        let mediaType = UTType(filenameExtension: sourceURL.pathExtension)?
            .preferredMIMEType ?? "application/octet-stream"
        let request = OnbiiImportRequest(
            sourceAudioURL: sourceURL,
            destinationBundleURL: destinationURL,
            title: title,
            mediaType: mediaType
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
            _ = try await Task.detached(priority: .userInitiated) {
                try OnbiiBundleWriter().write(request)
            }.value
            state = .completed(bundleURL: destinationURL)
        } catch {
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
