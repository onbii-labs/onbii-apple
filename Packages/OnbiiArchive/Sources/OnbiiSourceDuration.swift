@preconcurrency import AVFoundation
import Foundation

/// A capture-reported duration that disagrees with the file the writer
/// preserved.
///
/// This is not a formatting nicety. The first field test produced a twenty-minute
/// Watch recording filed as `durationSeconds: 0`, because the app was suspended
/// mid-capture and `AVAudioRecorder.currentTime` reports `0` once the recorder
/// stops. Nothing noticed. A mismatch here is the archive noticing.
public struct OnbiiSourceDurationMismatch: Equatable, Sendable {
    public var resourceID: String
    /// What the capture side claimed.
    public var reportedSeconds: Double
    /// What the preserved file actually contains, and what the manifest records.
    public var measuredSeconds: Double

    public init(
        resourceID: String,
        reportedSeconds: Double,
        measuredSeconds: Double
    ) {
        self.resourceID = resourceID
        self.reportedSeconds = reportedSeconds
        self.measuredSeconds = measuredSeconds
    }

    /// What to tell a person. Says what was preserved, what the app believed,
    /// and — without pretending to know why — that the two do not match.
    ///
    /// The source is intact either way; this is about not letting a wrong
    /// number pass unremarked.
    public var recordedDescription: String {
        "Preserved \(Self.clock(measuredSeconds)) of audio, but capture "
            + "reported \(Self.clock(reportedSeconds)). The recording was "
            + "interrupted; everything that reached the file is preserved."
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Measures the duration of media the archive has preserved.
///
/// The writer records what it can *verify*. A capture-side timer is a claim
/// about a live process; the preserved file is a fact about bytes on disk, and a
/// manifest is supposed to describe the preserved source truthfully. Where the
/// two disagree, the file wins and the disagreement is reported.
///
/// This is the one place `OnbiiArchive` reads media, and it reads only what it
/// has just written. It does not decode, transform, or interpret audio — that
/// stays behind the capture and processing boundaries.
public enum OnbiiSourceDuration {
    /// Below this, a difference is encoder framing rather than a lost recording.
    /// AAC carries a little encoder delay and padding, so a faithfully preserved
    /// file measures a few milliseconds off its capture timer. A capture that
    /// died measures off by minutes.
    public static let toleranceSeconds: Double = 1.0

    /// Whether a duration is meaningful for this media type. Only time-based
    /// media has one; an imported PDF does not.
    public static func isMeasurable(mediaType: String) -> Bool {
        mediaType.hasPrefix("audio/")
    }

    /// The duration of the media at `url`, or `nil` when it cannot be read.
    ///
    /// Best-effort by design. A file Onbii cannot measure is still a file worth
    /// preserving, so a failure here must never stop a source reaching the
    /// archive — preserving the source outranks describing it.
    public static func seconds(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else {
            return nil
        }
        return Double(file.length) / sampleRate
    }

    /// Whether a reported duration disagrees with the measured one.
    ///
    /// An *absent* report is not a disagreement. A file import has no capture
    /// timer to report from, so filling the duration in is an improvement rather
    /// than an anomaly. Only a claim that turns out to be wrong is worth telling
    /// someone about.
    static func disagrees(reported: Double?, measured: Double) -> Bool {
        guard let reported else {
            return false
        }
        return abs(reported - measured) > toleranceSeconds
    }
}
