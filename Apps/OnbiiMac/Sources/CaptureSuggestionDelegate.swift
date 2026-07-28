import OnbiiUI
import UserNotifications

/// Turns the *Record* button on a capture suggestion into an actual capture.
///
/// This is the only route from "an application you chose became active" to a
/// recording, and it exists so that route requires a press. Spec decision
/// `0023` permits contextual detection to suggest capture and requires the
/// capture itself to be explicit; a delegate that started recording on delivery
/// rather than on the action would quietly turn a suggestion into surveillance.
///
/// Ignoring the notification does nothing. There is no buffer to record
/// retrospectively from, by design.
/// Holds an action rather than the view model, because the delegate method is
/// called from outside any actor with parameters that cannot cross one. The
/// closure is what carries the isolation.
final class CaptureSuggestionDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let startCapture: @MainActor @Sendable () -> Void

    init(startCapture: @escaping @MainActor @Sendable () -> Void) {
        self.startCapture = startCapture
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Read the one thing that matters before leaving this context: the
        // response itself cannot cross to the main actor.
        let action = response.actionIdentifier
        guard action == OnbiiNotifier.startCaptureAction else { return }
        await startCapture()
    }
}
