import SwiftUI

@main
struct OnbiiMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, minHeight: 380)
        }
        .defaultSize(width: 640, height: 440)
    }
}
