import SwiftUI

@main
struct IwaApp: App {
    init() {
        Signposts.appStarted()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear(perform: Signposts.firstFrameShown)
        }
    }
}
