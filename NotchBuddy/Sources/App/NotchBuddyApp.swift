import SwiftUI
import AppKit

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        #if !APPSTORE
        .commands {
            // ⌘, and Rafiq → Settings… open the notch's pages of the Rafiq window.
            CommandGroup(replacing: .appSettings) {
                Button(NSLocalizedString("Settings…", comment: "")) {
                    delegate.openSettings()
                }
                .keyboardShortcut(",")
            }
        }
        #endif
    }
}
