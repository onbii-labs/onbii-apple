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

    /// Whether notifications can actually be delivered.
    ///
    /// A feature built on notifications has to be able to say when they are
    /// switched off. Everything here is best-effort and silent about its own
    /// failure, which is right for a message that is a courtesy — and wrong when
    /// the notification *is* the feature, as it is for a capture suggestion. An
    /// app that offers something and then does nothing is the failure Milestone
    /// 1.6 exists to remove.
    public static var isAllowed: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current()
                .notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
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

    /// Identifies the "an app you chose became active" suggestion and the one
    /// action on it. An app that offers to record must never be able to start
    /// recording by itself, so the action is the only route from here to a
    /// capture (`0023`).
    public static let captureSuggestionCategory = "onbii.capture-suggestion"
    public static let startCaptureAction = "onbii.start-capture"

    /// Registers the suggestion's *Record* button. Call once at launch.
    public static func registerCaptureSuggestion() {
        let record = UNNotificationAction(
            identifier: startCaptureAction,
            title: "Record",
            options: [.foreground]
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: captureSuggestionCategory,
                actions: [record],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    /// Offers to record because an application the person chose became active.
    ///
    /// An offer, and only an offer. Spec decision
    /// `0023` allows contextual detection to *suggest* capture and requires the
    /// capture itself to be explicit — so nothing starts until the button is
    /// pressed, and ignoring this does nothing at all.
    public static func suggestCapture(for applicationName: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(applicationName) is open"
        content.body = "Record this conversation? Onbii only records when you say so."
        content.categoryIdentifier = captureSuggestionCategory
        try? await center.add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
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
