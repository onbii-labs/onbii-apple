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

/// One run that produced a derived result, and what it was produced with.
///
/// An object may hold several generations of the same derived artifact
/// (`0032`), and each keeps the configuration it was made with (`0033`). This
/// reads them straight out of provenance, which is where both decisions put
/// them — so it works on an object produced by any implementation, including
/// one that laid its retained generations out differently.
public struct OnbiiDerivationGeneration: Equatable, Sendable {
    public var occurredAt: Date
    public var agent: OnbiiProvenanceEvent.Agent
    public var configuration: OnbiiDerivationConfiguration?
    /// The newest generation is the current one — what `content.md`, previews
    /// and applications present.
    public var isCurrent: Bool
}

public extension OnbiiManifest {
    /// Every run of `action`, oldest first, with the newest marked current.
    func generations(of action: String) -> [OnbiiDerivationGeneration] {
        let events = provenance
            .filter { $0.action == action }
            .sorted { $0.occurredAt < $1.occurredAt }
        return events.enumerated().map { index, event in
            OnbiiDerivationGeneration(
                occurredAt: event.occurredAt,
                agent: event.agent,
                configuration: event.configuration,
                isCurrent: index == events.count - 1
            )
        }
    }

    /// Every transcription this object has been through.
    var transcriptGenerations: [OnbiiDerivationGeneration] {
        generations(of: "transcribed")
    }
}

public extension OnbiiDerivationConfiguration {
    /// How to say what this transcript assumed, in a sentence a person can act
    /// on. `0033` exists so that "this transcript is wrong" can be told apart
    /// from "this transcript was made under the wrong assumption".
    var spokenDescription: String? {
        guard let languages, !languages.isEmpty else { return nil }
        let names = languages.map { tag in
            Locale.current.localizedString(forIdentifier: tag) ?? tag
        }
        let joined = names.count == 1
            ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return switch languageSelection {
        case .chosen: "Transcribed as \(joined), chosen."
        case .detected: "Transcribed as \(joined), detected automatically."
        case nil: "Transcribed as \(joined)."
        }
    }
}
