import OnbiiArchive
import OnbiiUI
import SwiftUI

/// The archive, browsable. One row per object, newest first, each showing what
/// state it is in without being opened.
struct ObjectListView: View {
    @Bindable var model: ImportViewModel
    @State private var searchText = ""

    private var visibleObjects: [OnbiiBundle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.objects
        }
        return model.objects.filter {
            $0.manifest.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(selection: $model.selectedObjectID) {
            Section {
                if visibleObjects.isEmpty {
                    emptyRow
                } else {
                    ForEach(visibleObjects, id: \.manifest.objectID) { bundle in
                        ObjectRow(bundle: bundle, indicator: model.indicator(for: bundle))
                            .tag(bundle.manifest.objectID)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    model.reveal(bundle)
                                }
                            }
                    }
                }
            } header: {
                Text("Objects")
                    .onbiiSubheaderStyle()
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search titles")
        .safeAreaInset(edge: .bottom) {
            archiveFooter
        }
    }

    @ViewBuilder
    private var emptyRow: some View {
        if model.archiveURL == nil {
            Text("No archive chosen yet.")
                .foregroundStyle(.onbiiSecondaryText)
        } else if searchText.isEmpty {
            Text("No objects in this archive.")
                .foregroundStyle(.onbiiSecondaryText)
        } else {
            Text("No object matches “\(searchText)”.")
                .foregroundStyle(.onbiiSecondaryText)
        }
    }

    /// Where the objects actually are, always visible. "Where is my knowledge?"
    /// should never require opening a settings window to answer.
    private var archiveFooter: some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
            Divider()
            HStack(spacing: OnbiiTheme.Spacing.s) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.onbiiAccent)
                Text(model.archiveDisplayName)
                    .font(.caption)
                    .foregroundStyle(.onbiiSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.archiveDisplayName)
                Spacer()
            }
            .padding(.horizontal, OnbiiTheme.Spacing.m)
            .padding(.bottom, OnbiiTheme.Spacing.s)
        }
        .background(.bar)
    }
}

private struct ObjectRow: View {
    let bundle: OnbiiBundle
    let indicator: OnbiiStatusIndicator

    var body: some View {
        HStack(spacing: OnbiiTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.manifest.title)
                    .lineLimit(1)
                Text(
                    bundle.manifest.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.onbiiSecondaryText)
            }

            Spacer(minLength: OnbiiTheme.Spacing.s)

            OnbiiStatusBadge(indicator, style: .icon)
        }
        .padding(.vertical, 2)
    }
}
