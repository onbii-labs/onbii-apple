import OnbiiUI
import SwiftUI

/// Settings holds the two choices that are about the whole app rather than
/// about one object: where knowledge is kept, and which language is recognised.
struct MacSettingsView: View {
    @Bindable var model: ImportViewModel

    var body: some View {
        TabView {
            Form { archiveSection }
                .formStyle(.grouped)
                .tabItem { Label("Archive", systemImage: "archivebox") }

            Form { transcriptionSection }
                .formStyle(.grouped)
                .tabItem { Label("Transcription", systemImage: "text.viewfinder") }
        }
        .frame(width: 520, height: 300)
    }

    @ViewBuilder
    private var archiveSection: some View {
        Section {
            LabeledContent("Location") {
                Text(model.archiveDisplayName)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(.onbiiSecondaryText)
            }

            HStack {
                Button(model.archiveURL == nil ? "Choose…" : "Change…") {
                    model.chooseArchive()
                }
                .disabled(model.isBusy)

                Button("Reveal in Finder") {
                    model.revealArchive()
                }
                .disabled(model.archiveURL == nil)
            }
        } header: {
            Text("Where your knowledge lives")
                .onbiiSubheaderStyle()
        } footer: {
            Text(
                "Onbii writes ordinary folders you own — no vendor backend. "
                    + "To share objects with iPhone, choose "
                    + "iCloud Drive → Onbii → Onbii Archive."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }
    }

    @ViewBuilder
    private var transcriptionSection: some View {
        Section {
            if model.availableLanguages.isEmpty {
                Text("No speech languages are available on this Mac yet.")
                    .foregroundStyle(.onbiiSecondaryText)
            } else {
                Picker("Language", selection: $model.selectedLanguageID) {
                    ForEach(model.availableLanguages) { language in
                        Text(
                            language.isInstalled
                                ? language.displayName
                                : "\(language.displayName) — download"
                        )
                        .tag(language.id)
                    }
                }
            }
        } header: {
            Text("Speech recognition")
                .onbiiSubheaderStyle()
        } footer: {
            Text(
                "Transcription always runs on this Mac. If the on-device "
                    + "recognizer is unavailable, transcription stops rather "
                    + "than sending your recording to a server."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }
    }
}

#Preview("Light") {
    MacSettingsView(model: ImportViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MacSettingsView(model: ImportViewModel())
        .preferredColorScheme(.dark)
}
