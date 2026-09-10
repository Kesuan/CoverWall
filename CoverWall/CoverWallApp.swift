import SwiftUI

@main
struct CoverWallApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
