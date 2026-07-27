#if os(macOS) || os(iOS)
import Foundation
import UserNotifications

/// Tells a person something they need to know when they are not looking at the
/// app.
///
/// The first field test's worst failure was silent: a recording stopped and
/// nothing said so for twenty-five minutes. Milestone 1.6 made the app honest
/// when someone is looking at it — but a phone in a pocket during a walk is
/// exactly the case where nobody is, and an honest status line reaches no one.
///
/// Local notifications only. No entitlement, no Info.plist key, no usage
/// description — just the person's permission, asked for in context rather than
/// at launch.
///
/// Nothing here is required for an object to be correct. A notification that
/// fails to send loses no knowledge; it only costs someone finding out sooner.
/// So every call is best-effort and silent about its own failures.
public enum OnbiiNotifier: Sendable {
    /// Asks once, the first time there is a plausible reason to.
    ///
    /// Call this when a capture starts, not at launch: a permission prompt makes
    /// sense next to the thing it is for. Never blocks — a refused or ignored
    /// prompt must not stop a recording.
    public static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Posts immediately, if allowed.
    ///
    /// Deliberately no banner while the app is frontmost: that is the default
    /// behaviour without a presentation delegate, and it is the right one here
    /// because the app already says this on screen. The notification exists for
    /// the person who is not looking.
    public static func post(title: String, body: String) async {
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

    /// A capture ended without being asked to.
    public static func captureStopped(_ reason: String) async {
        await post(title: "Recording stopped", body: reason)
    }

    /// A Watch recording has not reached the iPhone.
    ///
    /// A recording sitting on a Watch is not lost — but the person believes it
    /// is in their archive, and that belief is wrong until it arrives.
    public static func transferOutstanding() async {
        await post(
            title: "Recording still on your Watch",
            body: "It has not reached your iPhone yet. Open Onbii on your Watch "
                + "to send it again. Nothing is lost in the meantime."
        )
    }
}
#endif
