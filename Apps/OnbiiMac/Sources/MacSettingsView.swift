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

            Form { suggestionsSection }
                .formStyle(.grouped)
                .tabItem { Label("Suggestions", systemImage: "bell.badge") }
        }
        .frame(width: 520, height: 340)
    }

    /// Onbii offers; it never starts.
    ///
    /// Spec decision `0023` allows contextual detection to *suggest* capture and
    /// requires the capture itself to be explicit. The wording here is part of
    /// the feature rather than decoration: someone reading this screen must come
    /// away certain that naming an application does not mean Onbii will be
    /// listening while it is open.
    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            if model.watchedApplications.isEmpty {
                Text("No applications chosen.")
                    .foregroundStyle(.onbiiSecondaryText)
            } else {
                ForEach(model.watchedApplications) { application in
                    HStack {
                        Text(application.name)
                        Spacer()
                        Button("Remove") { model.stopWatching(application) }
                            .buttonStyle(.link)
                    }
                }
            }

            Button("Add Application…") { model.chooseApplicationToWatch() }
        } header: {
            Text("Offer to record when these open")
                .onbiiSubheaderStyle()
        } footer: {
            Text(
                "When one of these becomes the active application, Onbii asks "
                    + "whether to record. It never starts on its own, and it "
                    + "keeps no audio from before you say yes — there is nothing "
                    + "to record retrospectively from. Declining, or ignoring "
                    + "the question, records nothing."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }
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
                // Remembered from now on. Left unremembered, every launch reset
                // this to the system language — which is how a Dutch
                // conversation came to be transcribed as Australian English.
                .onChange(of: model.selectedLanguageID) { _, _ in
                    model.rememberTranscriptionLanguage()
                }
            }
        } header: {
            Text("Speech recognition")
                .onbiiSubheaderStyle()
        } footer: {
            Text(
                "Transcription always runs on this Mac. If the on-device "
                    + "recognizer is unavailable, transcription stops rather "
                    + "than sending your recording to a server. The language is "
                    + "recorded with each transcript, and a transcript made in "
                    + "the wrong language can always be made again."
            )
            .font(.caption)
            .foregroundStyle(.onbiiSecondaryText)
        }

        Section {
            Toggle(
                "Transcribe new objects automatically",
                isOn: $model.transcribesNewObjectsAutomatically
            )
        } footer: {
            // Says exactly what it will and will not do. "Automatic" is a word
            // that has to earn trust here: this app's whole argument is that it
            // does not do things to a person's knowledge quietly.
            Text(
                "Applies to objects that arrive while Onbii is running — a "
                    + "recording from iPhone or Apple Watch, or a file dropped "
                    + "into the archive. Onbii never re-transcribes something "
                    + "that already has a transcript, and never touches what "
                    + "was already in the archive when it opened. It uses the "
                    + "language above, and records that choice with the result."
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
