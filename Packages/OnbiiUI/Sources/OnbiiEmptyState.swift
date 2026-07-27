import SwiftUI

/// The shared "nothing here yet" screen: the mark, a line in the display face,
/// a sentence of plain guidance, and optionally the action that resolves it.
///
/// This replaces `ContentUnavailableView` in the two places where the emptiness
/// is the person's first impression of Onbii rather than an edge case.
public struct OnbiiEmptyState<Actions: View>: View {
    private let title: String
    private let message: String
    private let actions: Actions

    public init(
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: OnbiiTheme.Spacing.m) {
            OnbiiBrandMark(size: 76)
                .padding(.bottom, OnbiiTheme.Spacing.xs)

            Text(title)
                .font(.onbiiSectionTitle)
                .foregroundStyle(.onbiiPrimaryText)
                .multilineTextAlignment(.center)

            Text(message)
                .foregroundStyle(.onbiiSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            actions
                .padding(.top, OnbiiTheme.Spacing.xs)
        }
        .padding(OnbiiTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public extension OnbiiEmptyState where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

#Preview("Empty state") {
    OnbiiEmptyState(
        title: "Your knowledge, preserved.",
        message: "Record or import audio and it becomes an object you own."
    ) {
        Button("Import Audio") {}
            .buttonStyle(.borderedProminent)
    }
    .background(Color.onbiiBackground)
}
