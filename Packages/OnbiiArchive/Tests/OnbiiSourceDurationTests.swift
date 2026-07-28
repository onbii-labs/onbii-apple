import AVFoundation
import Foundation
@testable import OnbiiArchive
import OnbiiCore
import Testing

/// Field test 1, finding 1: a twenty-minute Watch recording was filed as
/// `durationSeconds: 0` because the app had been suspended and the capture
/// timer reported `0`. The writer took its word for it.
@Suite
struct SourceDurationTests {
    @Test
    func writerPrefersTheMeasuredDurationOverAWrongReportedOne() throws {
        let scratch = try Scratch()
        let source = try scratch.writeTone(seconds: 2.0, named: "capture.m4a")

        let result = try OnbiiBundleWriter().preserve(
            OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-recording",
                        sourceURL: source,
                        storedFilename: "recording.m4a",
                        mediaType: "audio/mp4",
                        captureStartedAt: Date(timeIntervalSince1970: 0),
                        // What a suspended AVAudioRecorder reports.
                        durationSeconds: 0
                    ),
                ],
                destinationBundleURL: scratch.bundleURL,
                title: "Interrupted",
                sourceAction: "captured",
                sourceAgentName: "test"
            )
        )

        let measured = try #require(
            result.manifest.resources.first { $0.id == "source-recording" }?
                .durationSeconds
        )
        #expect(abs(measured - 2.0) < 0.1)

        let mismatch = try #require(result.durationMismatches.first)
        #expect(mismatch.resourceID == "source-recording")
        #expect(mismatch.reportedSeconds == 0)
        #expect(abs(mismatch.measuredSeconds - 2.0) < 0.1)
    }

    /// A duration that agrees with the file is not an anomaly, and neither is a
    /// file import that never had a capture timer to report from.
    @Test
    func anAgreeingOrAbsentDurationIsNotReportedAsAMismatch() throws {
        for reported in [2.0, nil] as [Double?] {
            let scratch = try Scratch()
            let source = try scratch.writeTone(seconds: 2.0, named: "capture.m4a")

            let result = try OnbiiBundleWriter().preserve(
                OnbiiImportRequest(
                    sources: [
                        OnbiiSourceFile(
                            resourceID: "source-recording",
                            sourceURL: source,
                            storedFilename: "recording.m4a",
                            mediaType: "audio/mp4",
                            durationSeconds: reported
                        ),
                    ],
                    destinationBundleURL: scratch.bundleURL,
                    title: "Fine",
                    sourceAction: "imported",
                    sourceAgentName: "test"
                )
            )

            #expect(result.durationMismatches.isEmpty)
            // Absent or not, the manifest ends up carrying the measured value.
            let stored = try #require(
                result.manifest.resources.first { $0.id == "source-recording" }?
                    .durationSeconds
            )
            #expect(abs(stored - 2.0) < 0.1)
        }
    }

    /// Preserving the source outranks describing it: a file whose duration
    /// cannot be measured still reaches the archive.
    @Test
    func anUnmeasurableSourceIsStillPreserved() throws {
        let scratch = try Scratch()
        let source = scratch.directory.appendingPathComponent("notes.pdf")
        try Data("not audio".utf8).write(to: source)

        let result = try OnbiiBundleWriter().preserve(
            OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-document",
                        sourceURL: source,
                        storedFilename: "notes.pdf",
                        mediaType: "application/pdf"
                    ),
                ],
                destinationBundleURL: scratch.bundleURL,
                title: "A document",
                sourceAction: "imported",
                sourceAgentName: "test"
            )
        )

        #expect(result.durationMismatches.isEmpty)
        #expect(
            result.manifest.resources
                .first { $0.id == "source-document" }?.durationSeconds == nil
        )
        #expect(FileManager.default.fileExists(atPath: scratch.bundleURL.path))
    }

    /// Audio the measurer cannot open keeps whatever the caller reported rather
    /// than losing it.
    @Test
    func unreadableAudioKeepsTheReportedDuration() throws {
        let scratch = try Scratch()
        let source = scratch.directory.appendingPathComponent("broken.m4a")
        try Data("not really an m4a".utf8).write(to: source)

        let result = try OnbiiBundleWriter().preserve(
            OnbiiImportRequest(
                sources: [
                    OnbiiSourceFile(
                        resourceID: "source-recording",
                        sourceURL: source,
                        storedFilename: "recording.m4a",
                        mediaType: "audio/mp4",
                        durationSeconds: 12.5
                    ),
                ],
                destinationBundleURL: scratch.bundleURL,
                title: "Unreadable",
                sourceAction: "captured",
                sourceAgentName: "test"
            )
        )

        #expect(result.durationMismatches.isEmpty)
        #expect(
            result.manifest.resources
                .first { $0.id == "source-recording" }?.durationSeconds == 12.5
        )
    }

    @Test
    func encoderFramingIsNotAMismatchButALostRecordingIs() {
        #expect(!OnbiiSourceDuration.disagrees(reported: 143.35, measured: 143.4))
        #expect(!OnbiiSourceDuration.disagrees(reported: nil, measured: 143.4))
        #expect(OnbiiSourceDuration.disagrees(reported: 0, measured: 1_200.1))
    }

    @Test
    func onlyTimeBasedMediaHasAMeasurableDuration() {
        #expect(OnbiiSourceDuration.isMeasurable(mediaType: "audio/mp4"))
        #expect(!OnbiiSourceDuration.isMeasurable(mediaType: "application/pdf"))
        #expect(!OnbiiSourceDuration.isMeasurable(mediaType: "text/markdown"))
    }
}

// MARK: - Helpers

private struct Scratch {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnbiiDurationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    var bundleURL: URL {
        directory.appendingPathComponent("Object.onbii")
    }

    /// Writes a real AAC file of a known length, so the measurement under test
    /// is exercised against the same format capture produces.
    func writeTone(seconds: Double, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let sampleRate = 44_100.0
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
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
        return url
    }
}
