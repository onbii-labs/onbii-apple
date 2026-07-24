#if os(macOS) || os(iOS)
import Foundation

/// A transcription language the user can choose, with its on-device install
/// state. Shared by the macOS and iOS language pickers.
public struct OnbiiTranscriptionLanguage: Identifiable, Hashable, Sendable {
    public let locale: Locale
    public let isInstalled: Bool

    public init(locale: Locale, isInstalled: Bool) {
        self.locale = locale
        self.isInstalled = isInstalled
    }

    public var id: String { locale.identifier(.bcp47) }

    /// Localized display name, e.g. "Dutch" / "English (United States)".
    public var displayName: String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }
}

public extension AppleOnDeviceTranscriber {
    /// The supported on-device languages with their install state, sorted by
    /// display name.
    static func availableLanguages() async -> [OnbiiTranscriptionLanguage] {
        let supported = await supportedLocales()
        let installed = Set(
            (await installedLocales()).map { $0.identifier(.bcp47) }
        )
        return supported
            .map {
                OnbiiTranscriptionLanguage(
                    locale: $0,
                    isInstalled: installed.contains($0.identifier(.bcp47))
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                    == .orderedAscending
            }
    }

    /// The default choice: the system language if supported, otherwise English,
    /// otherwise the first supported language.
    static func preferredLanguage(
        among languages: [OnbiiTranscriptionLanguage]
    ) -> OnbiiTranscriptionLanguage? {
        let systemCode = Locale.current.language.languageCode?.identifier
        if let match = languages.first(where: {
            $0.locale.language.languageCode?.identifier == systemCode
        }) {
            return match
        }
        if let english = languages.first(where: {
            $0.locale.language.languageCode?.identifier == "en"
        }) {
            return english
        }
        return languages.first
    }
}
#endif
