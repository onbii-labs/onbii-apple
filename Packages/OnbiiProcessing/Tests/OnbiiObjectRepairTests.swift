#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import OnbiiArchive
import OnbiiCore
@testable import OnbiiProcessing
import Testing

/// Field test 1 left two objects whose manifests say something the objects
/// themselves contradict: a twenty-minute recording filed as zero seconds, and
/// good coordinates with an empty place name.
@Suite
struct ObjectRepairTests {
    @Test
    func aDurationTheAudioContradictsIsCorrected() async throws {
        let object = try Object(reportedDuration: 0, placeName: nil)

        let found = await OnbiiObjectRepair().findings(for: object.bundle)
        #expect(found.durations.count == 1)
        #expect(abs((found.durations["source-recording"] ?? 0) - 2.0) < 0.1)

        let (repaired, corrected) = try await OnbiiObjectRepair().repair(
            object.bundle
        )
        #expect(corrected.durations.count == 1)
        let duration = try #require(
            repaired.manifest.resources
                .first { $0.id == "source-recording" }?.durationSeconds
        )
        #expect(abs(duration - 2.0) < 0.1)
    }

    @Test
    func anEmptyPlaceNameIsFilledIn() async throws {
        let object = try Object(reportedDuration: 2.0, placeName: "")

        let (repaired, corrected) = try await OnbiiObjectRepair().repair(
            object.bundle,
            resolvingPlaceName: { _, _ in "Breda, Netherlands" }
        )
        #expect(corrected.placeName == "Breda, Netherlands")
        #expect(repaired.manifest.location?.resolvedName == "Breda, Netherlands")
    }

    /// A name already there may have been typed by a person, and reprocessing
    /// must never displace a human edit (spec decision 0010).
    @Test
    func aPlaceNameAlreadyRecordedIsNeverReplaced() async throws {
        let object = try Object(reportedDuration: 2.0, placeName: "The kitchen table")

        let found = await OnbiiObjectRepair().findings(
            for: object.bundle,
            resolvingPlaceName: { _, _ in "Somewhere Else" }
        )
        #expect(found.placeName == nil)
        #expect(found.isEmpty)
    }

    /// A repair that finds nothing writes nothing — no provenance event, no new
    /// generation of anything.
    @Test
    func anObjectWithNothingWrongIsLeftAlone() async throws {
        let object = try Object(reportedDuration: 2.0, placeName: "Breda")
        let before = object.bundle.manifest

        let (repaired, corrected) = try await OnbiiObjectRepair().repair(
            object.bundle,
            resolvingPlaceName: { _, _ in "Elsewhere" }
        )
        #expect(corrected.isEmpty)
        #expect(repaired.manifest == before)
    }

    /// The readable facet has to stop repeating the wrong fact, and what it used
    /// to say is kept — `content.md` is a resource, so it supersedes.
    @Test
    func contentMarkdownIsRegeneratedAndTheOldOneKept() async throws {
        let object = try Object(reportedDuration: 0, placeName: "")

        let (repaired, _) = try await OnbiiObjectRepair().repair(
            object.bundle,
            resolvingPlaceName: { _, _ in "Breda, Netherlands" },
            occurredAt: Date(timeIntervalSince1970: 2_000_000)
        )

        let content = try #require(
            repaired.manifest.resources.first { $0.id == "content-markdown" }
        )
        let text = try String(
            contentsOf: repaired.url(for: content), encoding: .utf8
        )
        #expect(text.contains("Breda, Netherlands"))

        let retiredID = OnbiiSupersededGeneration.resourceID(
            for: "content-markdown",
            at: Date(timeIntervalSince1970: 2_000_000)
        )
        let retired = try #require(
            repaired.manifest.resources.first { $0.id == retiredID }
        )
        let old = try String(
            contentsOf: repaired.url(for: retired), encoding: .utf8
        )
        #expect(!old.contains("Breda, Netherlands"))
    }

    /// A correction is a change to what the object says about itself, so the
    /// object says that it happened and what made it.
    @Test
    func theCorrectionIsRecordedInProvenance() async throws {
        let object = try Object(reportedDuration: 0, placeName: nil)

        let (repaired, _) = try await OnbiiObjectRepair().repair(object.bundle)

        let event = try #require(
            repaired.manifest.provenance.first {
                $0.action == OnbiiProvenanceEvent.correctedAction
            }
        )
        #expect(event.agent.name == OnbiiObjectRepair.agentName)
        #expect(event.inputResourceIDs.contains("source-recording"))
        // Still a valid Onbii bundle afterwards.
        #expect(throws: Never.self) {
            try OnbiiBundleReader().read(at: object.bundle.url)
        }
    }

    /// The source is the irreplaceable thing. A repair reads its length and
    /// nothing else.
    @Test
    func theSourceBytesAreUntouched() async throws {
        let object = try Object(reportedDuration: 0, placeName: "")
        let source = try #require(
            object.bundle.manifest.resources.first { $0.role == .source }
        )
        let before = try Data(contentsOf: object.bundle.url(for: source))

        let (repaired, _) = try await OnbiiObjectRepair().repair(
            object.bundle,
            resolvingPlaceName: { _, _ in "Breda" }
        )

        let after = try Data(
            contentsOf: repaired.url(
                for: repaired.manifest.resources.first { $0.role == .source }!
            )
        )
        #expect(before == after)
    }
}

// MARK: - Helpers

private struct Object {
    let bundle: OnbiiBundle
    let directory: URL

    init(reportedDuration: Double?, placeName: String?) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnbiiRepairTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sourceURL = directory.appendingPathComponent("tone.m4a")
        try Self.writeTone(seconds: 2.0, to: sourceURL)
        let bundleURL = directory.appendingPathComponent("Object.onbii")

        try OnbiiBundleWriter().write(
            OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-recording",
                        sourceURL: sourceURL,
                        storedFilename: "recording.m4a",
                        mediaType: "audio/mp4"
                    ),
                ],
                destinationBundleURL: bundleURL,
                title: "Object",
                createdAt: Date(timeIntervalSince1970: 0),
                sourceAction: "captured",
                sourceAgentName: "test",
                location: OnbiiLocation(
                    latitude: 51.5818, longitude: 4.7770, name: placeName
                )
            )
        )

        // The writer measures correctly, so reproduce the broken state the field
        // test produced by rewriting the manifest directly.
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(
            OnbiiManifest.self, from: Data(contentsOf: manifestURL)
        )
        if let index = manifest.resources.firstIndex(
            where: { $0.id == "source-recording" }
        ) {
            manifest.resources[index].durationSeconds = reportedDuration
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        bundle = try OnbiiBundleReader().read(at: bundleURL)
    }

    private static func writeTone(seconds: Double, to url: URL) throws {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        )!
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = 0.2 * sinf(
                2 * .pi * 440 * Float(index) / Float(sampleRate)
            )
        }
        try file.write(from: buffer)
    }
}
#endif
