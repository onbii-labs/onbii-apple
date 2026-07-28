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

    /// Runs that completed and produced nothing, oldest first.
    ///
    /// An object with none of these has never been processed. An object with
    /// some has, and the configuration each was made under is the useful part —
    /// it is the difference between "nobody has tried" and "Dutch was tried and
    /// there was no speech to find".
    var emptyDerivations: [OnbiiDerivationGeneration] {
        generations(of: OnbiiProvenanceEvent.foundNothingAction)
    }

    /// Whether unattended processing has anything to do with this object.
    ///
    /// Deliberately narrower than "could be transcribed". Three conditions, each
    /// of which is a rule rather than an optimisation:
    ///
    /// - **There is audio to work from.** Otherwise there is nothing to do.
    /// - **There is no transcript.** `0032` makes a second transcript safe — it
    ///   supersedes and retains rather than overwriting — but it also says
    ///   reprocessing is *deliberate*. A generation nobody asked for is what
    ///   that rules out, and safety is not the same as permission.
    /// - **It has not already been transcribed and found empty.** An object that
    ///   holds a `found-nothing` event has been through this and there was no
    ///   speech in it. Without this condition every re-read would queue the same
    ///   silent recording again, forever.
    ///
    /// Whether to act on it is still the application's call — this only says
    /// there is work outstanding.
    var awaitsFirstTranscript: Bool {
        hasTranscribableAudio && !hasTranscript && emptyDerivations.isEmpty
    }

    /// One sentence for everything this object has been through that produced
    /// nothing, or `nil` if it has been through none.
    ///
    /// The languages are the point. "Nothing was found" invites trying again
    /// with the same setting; "nothing was found in Dutch" is something a person
    /// can act on. The single definition lives here because both apps show it
    /// and they must not word it differently.
    var emptyDerivationSummary: String? {
        let runs = emptyDerivations
        guard let latest = runs.last else { return nil }

        var languages = [String]()
        for run in runs {
            for tag in run.configuration?.languages ?? [] {
                let name = OnbiiDerivationConfiguration.languageName(for: tag)
                if !languages.contains(name) {
                    languages.append(name)
                }
            }
        }
        let formatted = DateFormatter()
        formatted.dateStyle = .medium
        formatted.timeStyle = .none
        let when = formatted.string(from: latest.occurredAt)

        guard !languages.isEmpty else {
            return "Transcribing this recording on \(when) found no speech."
        }
        let joined = languages.count == 1
            ? languages[0]
            : languages.dropLast().joined(separator: ", ")
                + " and " + languages[languages.count - 1]
        let occasion = runs.count == 1 ? "on \(when)" : "most recently on \(when)"
        return "Transcribing in \(joined) found no speech, \(occasion). "
            + "The recording is unchanged."
    }
}

public extension OnbiiDerivationConfiguration {
    /// A language tag as a person would say it: "Dutch", not "Dutch
    /// (Netherlands)" and not `nl-NL`.
    ///
    /// The region belongs in the manifest, where it is a fact, and not in a
    /// sentence about which language was tried. A recogniser resolves a request
    /// to whichever regional model it has, so the region often says more about
    /// Apple's model catalogue than about the recording.
    static func languageName(for tag: String) -> String {
        let code = Locale(identifier: tag).language.languageCode?.identifier
        if let code, let name = Locale.current.localizedString(forLanguageCode: code) {
            return name
        }
        return Locale.current.localizedString(forIdentifier: tag) ?? tag
    }

    /// How to say what this transcript assumed, in a sentence a person can act
    /// on. `0033` exists so that "this transcript is wrong" can be told apart
    /// from "this transcript was made under the wrong assumption".
    var spokenDescription: String? {
        guard let languages, !languages.isEmpty else { return nil }
        let names = languages.map { Self.languageName(for: $0) }
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
