import SwiftUI

@main
struct OnbiiIOSApp: App {
    init() {
        WatchRecordingReceiver.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            MobileContentView()
        }
    }
}

