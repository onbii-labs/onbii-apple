import OnbiiUI
import SwiftUI

/// Where knowledge is kept, which language is recognised, and what this build
/// is made of.
struct MobileSettingsView: View {
    @Bindable var model: MobileViewModel
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Location") {
                        Text(model.archiveDescription)
                            .foregroundStyle(.onbiiSecondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Where your knowledge lives")
                        .onbiiSubheaderStyle()
                } footer: {
                    Text(
                        "Onbii writes ordinary folders you own — no vendor "
                            + "backend. Objects in iCloud Drive appear on your "
                            + "Mac too."
                    )
                }

                Section {
                    if model.availableLanguages.isEmpty {
                        Text("No speech languages are available on this iPhone yet.")
                            .foregroundStyle(.onbiiSecondaryText)
                    } else {
                        Picker(
                            "Language",
                            selection: $model.selectedLanguageID
                        ) {
                            ForEach(model.availableLanguages) { language in
                                Text(
                                    language.isInstalled
                                        ? language.displayName
                                        : "\(language.displayName) — download"
                                )
                                .tag(language.id)
                            }
                        }
                        // Remembered from now on. Left unremembered, every
                        // launch reset this to the system language — which is
                        // how a Dutch conversation came to be transcribed as
                        // Australian English.
                        .onChange(of: model.selectedLanguageID) { _, _ in
                            model.rememberTranscriptionLanguage()
                        }
                    }
                } header: {
                    Text("Speech recognition")
                        .onbiiSubheaderStyle()
                } footer: {
                    Text(
                        "Transcription always runs on this iPhone. If the "
                            + "on-device recognizer is unavailable, "
                            + "transcription stops rather than sending your "
                            + "recording to a server. The language is recorded "
                            + "with each transcript, and a transcript made in "
                            + "the wrong language can always be made again."
                    )
                }

                Section {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .foregroundStyle(.onbiiSecondaryText)
                    }
                    LabeledContent("Display type") {
                        Text("Prata (SIL Open Font License 1.1)")
                            .foregroundStyle(.onbiiSecondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("About")
                        .onbiiSubheaderStyle()
                }
            }
            .listStyle(.insetGrouped)
            .listRowBackground(Color.onbiiSurface)
            .scrollContentBackground(.hidden)
            .background(Color.onbiiBackground)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.onbiiAccent)
    }
}

#Preview("Light") {
    MobileSettingsView(model: MobileViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MobileSettingsView(model: MobileViewModel())
        .preferredColorScheme(.dark)
}
