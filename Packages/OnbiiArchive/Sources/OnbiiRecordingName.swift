import Foundation

/// The default sortable name for a directly captured recording.
public struct OnbiiRecordingName: Equatable, Sendable {
    public let title: String

    public var bundleFilename: String {
        "\(title).onbii"
    }

    public init(
        startedAt: Date,
        timeZone: TimeZone = .current
    ) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm 'Recording'"
        title = formatter.string(from: startedAt)
    }
}
