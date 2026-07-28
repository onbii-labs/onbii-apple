import OnbiiArchive
import OnbiiUI
import SwiftUI

/// One object in the list: what it is, when it happened, and what state it is
/// in — without having to open it.
struct MobileObjectRow: View {
    let bundle: OnbiiBundle
    let indicator: OnbiiStatusIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: OnbiiTheme.Spacing.xs) {
            Text(bundle.manifest.title)
                .lineLimit(1)

            HStack(spacing: OnbiiTheme.Spacing.s) {
                Text(
                    bundle.manifest.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.onbiiSecondaryText)

                if let place = bundle.manifest.location?.name {
                    Text("· \(place)")
                        .font(.caption)
                        .foregroundStyle(.onbiiSecondaryText)
                        .lineLimit(1)
                }
            }

            OnbiiStatusBadge(indicator)
                .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}
