import Foundation
import UserNotifications

/// Tells a person something they need to know when they are not looking at the
/// Watch.
///
/// A haptic says *something* happened; a notification says *what*. On a walk
/// with the app in the background, that difference is whether someone turns
/// around and starts again or carries on believing they are recording.
///
/// Duplicated deliberately rather than shared with `OnbiiNotifier` in `OnbiiUI`.
/// The Watch takes no dependency on that package — it would drag `OnbiiArchive`
/// onto a device that has no business reading or writing bundles — which is the
/// same reason `WatchPrimaryButtonStyle` exists separately. Keep the two in step
/// by hand; both are small.
enum WatchNotifier {
    /// Asked when a recording starts, not at launch. Never blocks.
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }

    /// A recording ended without being asked to.
    static func captureStopped(_ reason: String) async {
        await post(title: "Recording stopped", body: reason)
    }

    /// The audio is safe on the Watch but has not reached the iPhone.
    ///
    /// Worth saying out loud, because the person's mental model is that a
    /// recording they finished is already in their archive. Until it transfers,
    /// it is not — and nothing else tells them.
    static func transferOutstanding() async {
        await post(
            title: "Recording still on this Watch",
            body: "It has not reached your iPhone yet. Nothing is lost — open "
                + "Onbii here to send it again."
        )
    }
}
