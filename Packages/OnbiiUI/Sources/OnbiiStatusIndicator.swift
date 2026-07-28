import OnbiiArchive
import SwiftUI

/// What the application is currently doing to one object.
///
/// This is transient and lives only in a view model's memory for the length of
/// a session. It is never encoded, never written to a manifest, and never
/// consulted by anything that reads or writes a bundle — an object does not
/// become different because an app is busy with it.
public enum OnbiiObjectActivity: Equatable, Sendable {
    /// Work is under way; the string is the message already shown elsewhere.
    case working(String)
    /// The last attempt in this session failed. The object itself is intact.
    case failed(String)
}

/// What a person should see about an object at a glance.
///
/// Combines what the manifest says (``OnbiiObjectStatus``) with what the app is
/// doing right now (``OnbiiObjectActivity``), with activity taking precedence
/// because it is the more urgent and more recent truth.
public enum OnbiiStatusIndicator: Equatable, Sendable {
    case transcribed
    case awaitingTranscription
    case sourceOnly
    case working(String)
    case needsAttention(String)

    public init(_ status: OnbiiObjectStatus, activity: OnbiiObjectActivity? = nil) {
        switch activity {
        case let .working(message):
            self = .working(message)
        case let .failed(message):
            self = .needsAttention(message)
        case nil:
            switch status {
            case .transcribed: self = .transcribed
            case .awaitingTranscription: self = .awaitingTranscription
            case .sourceOnly: self = .sourceOnly
            }
        }
    }

    public var title: String {
        switch self {
        case .transcribed: "Transcribed"
        case .awaitingTranscription: "Not transcribed"
        case .sourceOnly: "Preserved"
        case let .working(message): message
        case let .needsAttention(message): message
        }
    }

    /// The reason, where the short form has one and cannot carry it.
    ///
    /// A badge reading "Needs attention" and nothing else tells a person that
    /// something is wrong and gives them no way to find out what — which is
    /// what field test 2 ran into. Anywhere there is room, show this beside it.
    public var detail: String? {
        switch self {
        case .working, .needsAttention: title
        default: nil
        }
    }

    /// The short form for a dense row, where the message would not fit.
    public var shortTitle: String {
        switch self {
        case .working: "Working"
        case .needsAttention: "Needs attention"
        default: title
        }
    }

    public var systemImage: String {
        switch self {
        case .transcribed: "text.badge.checkmark"
        case .awaitingTranscription: "waveform"
        case .sourceOnly: "doc"
        case .working: "ellipsis"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .transcribed: .onbiiSuccess
        case .awaitingTranscription, .sourceOnly: .onbiiSecondaryText
        case .working: .onbiiAccent
        case .needsAttention: .onbiiError
        }
    }

    var showsProgress: Bool {
        if case .working = self { true } else { false }
    }
}

/// The one rendering of object status, shared by every list and detail view.
///
/// Status is never carried by colour alone: the badge style always pairs the
/// tint with a symbol and a word, the icon style always carries an
/// accessibility label, and both are legible with colour vision differences or
/// in a monochrome screenshot.
public struct OnbiiStatusBadge: View {
    public enum Style {
        /// Capsule with symbol and text. For a detail header or a list row.
        case badge
        /// Symbol only. For a dense sidebar row.
        case icon
    }

    private let indicator: OnbiiStatusIndicator
    private let style: Style

    public init(_ indicator: OnbiiStatusIndicator, style: Style = .badge) {
        self.indicator = indicator
        self.style = style
    }

    public var body: some View {
        switch style {
        case .badge:
            HStack(spacing: OnbiiTheme.Spacing.xs) {
                symbol
                Text(indicator.shortTitle)
                    .font(.onbiiSubheader)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .foregroundStyle(indicator.tint)
            .padding(.horizontal, OnbiiTheme.Spacing.s)
            .padding(.vertical, OnbiiTheme.Spacing.xs)
            .background(indicator.tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(indicator.title)

        case .icon:
            symbol
                .foregroundStyle(indicator.tint)
                .accessibilityLabel(indicator.title)
                .help(indicator.title)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        if indicator.showsProgress {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: indicator.systemImage)
                .imageScale(.small)
        }
    }
}

#Preview("Status badges") {
    VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.m) {
        OnbiiStatusBadge(.transcribed)
        OnbiiStatusBadge(.awaitingTranscription)
        OnbiiStatusBadge(.sourceOnly)
        OnbiiStatusBadge(.working("Transcribing on device…"))
        OnbiiStatusBadge(.needsAttention("Transcription failed."))
        HStack(spacing: OnbiiTheme.Spacing.m) {
            OnbiiStatusBadge(.transcribed, style: .icon)
            OnbiiStatusBadge(.awaitingTranscription, style: .icon)
            OnbiiStatusBadge(.needsAttention("Failed"), style: .icon)
        }
    }
    .padding(OnbiiTheme.Spacing.xl)
    .background(Color.onbiiBackground)
}
