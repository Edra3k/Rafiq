import SwiftUI
import WatchKit

@main
struct RafiqWatchApp: App {
    init() { WatchStore.shared.start() }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(store: WatchStore.shared)
        }
    }
}
