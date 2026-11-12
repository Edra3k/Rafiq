#if !APPSTORE
import SwiftUI

// MARK: - Settings → Agents → "Ask…"
// Answer aloud (on by default) and where Hermes works (Auto: the server for the server,
// else this Mac).

struct AskSettings: View {
    @AppStorage(AskRunner.speakKey) private var speaks = true
    @AppStorage(AskRunner.whereKey) private var place = "auto"

    var body: some View {
        GroupBox(String(localized: "ask.settings.title", defaultValue: "Ask Hermes or Claude")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ask.settings.body")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(String(localized: "ask.settings.aloud", defaultValue: "Say the answer aloud"), isOn: $speaks)
                Picker(String(localized: "ask.settings.where", defaultValue: "Hermes works"), selection: $place) {
                    Text("ask.settings.where.auto").tag("auto")
                    Text("ask.settings.where.mac").tag("mac")
                    Text("ask.settings.where.server").tag("server")
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsAnchor("agents.ask")
    }
}
#endif
