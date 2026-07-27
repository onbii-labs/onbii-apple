import Foundation
import OnbiiCore

/// What an object's own manifest already says about it.
///
/// This reads the manifest and nothing else. It is not a cache, not a database,
/// and not a second source of truth: delete every line of it and the user's
/// objects are unchanged. It exists so that a view can say "transcribed" or
/// "not transcribed yet" at a glance without three surfaces inventing three
/// different answers.
///
/// Transient app activity — "transcribing right now", "the last attempt
/// failed" — is deliberately absent. That is a property of the application
/// looking at the object, not of the object, and it belongs in a view model.
public enum OnbiiObjectStatus: String, Equatable, Sendable, CaseIterable {
    /// An audio source is preserved; no transcript has been derived from it yet.
    case awaitingTranscription
    /// A derived transcript is declared in the manifest.
    case transcribed
    /// Preserved, but there is no audio source for transcription to work from.
    case sourceOnly
}

public extension OnbiiManifest {
    /// Resource identifiers the Milestone 1 transcription paths declare for a
    /// transcript. Both the macOS and iPhone enrichment calls add the JSON and
    /// the Markdown artefact together, so either one present means transcribed.
    ///
    /// This is the single definition on purpose: three call sites previously
    /// disagreed about whether `transcript-markdown` on its own counted.
    static let transcriptResourceIDs: Set<String> = [
        "derived-transcript",
        "transcript-markdown",
    ]

    /// Whether a derived transcript is declared.
    var hasTranscript: Bool {
        resources.contains { Self.transcriptResourceIDs.contains($0.id) }
    }

    /// Whether there is a preserved audio source that transcription could read.
    var hasTranscribableAudio: Bool {
        resources.contains { $0.role == .source && $0.mediaType.hasPrefix("audio/") }
    }

    var status: OnbiiObjectStatus {
        if hasTranscript {
            .transcribed
        } else if hasTranscribableAudio {
            .awaitingTranscription
        } else {
            .sourceOnly
        }
    }
}

public extension OnbiiBundle {
    var status: OnbiiObjectStatus { manifest.status }
}
