#if !APPSTORE
import AppIntents
import Foundation

// MARK: - Rafiq for Siri and Shortcuts (App Intents)
//
// "Hey Siri, ask Rafiq where Claude is", "… ask Rafiq to tell Hermes to check the disk": the
// same brain as "OK Rafiq" (Apple Intelligence on the Mac, JarvisTools), the same actions, the
// answer spoken by Siri. Also in the Shortcuts app, so Apple Intelligence and Siri can use them.
// No intent here allows or denies an agent's request.

@MainActor
enum JarvisAsk {
    /// Runs one request through Rafiq's brain: its actions, then a sentence to say.
    static func answer(_ text: String) async -> String {
        let pills = PillCatalog.available
        // The parser first (fast and exact), then the on-device model.
        let parsed = IntentParser.parse(text, pills: pills)
        if case .unknown = parsed {} else {
            let r = await VoiceActionRunner.shared.run(parsed, availablePills: pills, rawTranscript: text)
            if !r.message.isEmpty { return r.message }
        }
        guard VoiceBrain._checkStatus() == .available else {
            return String(localized: "intent.no-brain", defaultValue: "Rafiq's brain needs Apple Intelligence turned on.")
        }
        guard let brain = await VoiceBrain.shared.resolve(text, pills: pills) else {
            return String(localized: "intent.brain-failed", defaultValue: "I couldn't answer that one. Try again?")
        }
        var said: [String] = []
        for intent in brain.intents {
            let r = await VoiceActionRunner.shared.run(intent, availablePills: pills, rawTranscript: text)
            if !r.message.isEmpty { said.append(r.message) }
        }
        let reply = said.isEmpty ? brain.text : said.joined(separator: " ")
        return reply.isEmpty ? String(localized: "intent.done", defaultValue: "Done.") : reply
    }
}

struct AskRafiqIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("intent.ask.title", defaultValue: "Ask Rafiq")
    static let description = IntentDescription(LocalizedStringResource("intent.ask.description",
        defaultValue: "Ask Rafiq anything: where your agents are, a task for Hermes or Claude, the next prayer, your day."))

    @Parameter(title: LocalizedStringResource("intent.ask.request", defaultValue: "Request"))
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let reply = await JarvisAsk.answer(request)
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

struct AgentsStatusIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("intent.agents.title", defaultValue: "Where are my agents")
    static let description = IntentDescription(LocalizedStringResource("intent.agents.description",
        defaultValue: "What Claude, Hermes and your other agents are doing, and what waits for your OK."))

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let reply = await JarvisAsk.answer(String(localized: "intent.agents.question", defaultValue: "Where are my agents, and does anything wait for me?"))
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

struct NextPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("intent.prayer.title", defaultValue: "Next prayer")
    static let description = IntentDescription(LocalizedStringResource("intent.prayer.description",
        defaultValue: "The next prayer and how long until it, as Rafiq computes it on your Mac."))

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let reply = await JarvisAsk.answer(String(localized: "intent.prayer.question", defaultValue: "When is the next prayer?"))
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

struct AgentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("intent.task.title", defaultValue: "Give a task to an agent")
    static let description = IntentDescription(LocalizedStringResource("intent.task.description",
        defaultValue: "Hermes for the server and the home, Claude for code. It runs in the background; a risky command still waits for your click."))

    enum Agent: String, AppEnum {
        case auto, hermes, claude
        static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("intent.task.agent", defaultValue: "Agent"))
        static let caseDisplayRepresentations: [Agent: DisplayRepresentation] = [
            .auto: DisplayRepresentation(title: LocalizedStringResource("ask.auto", defaultValue: "Auto")),
            .hermes: DisplayRepresentation(title: "Hermes"),
            .claude: DisplayRepresentation(title: "Claude"),
        ]
    }

    @Parameter(title: LocalizedStringResource("intent.task.agent", defaultValue: "Agent"), default: .auto)
    var agent: Agent

    @Parameter(title: LocalizedStringResource("intent.task.task", defaultValue: "Task"))
    var task: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target: AskTarget = agent == .hermes ? .hermes : agent == .claude ? .claude : .auto
        let r = await VoiceActionRunner.shared.run(.askAgent(target: target, text: task), availablePills: PillCatalog.available, rawTranscript: task)
        return .result(dialog: IntentDialog(stringLiteral: r.message.isEmpty
            ? String(localized: "intent.done", defaultValue: "Done.") : r.message))
    }
}

struct RafiqShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskRafiqIntent(), phrases: [
            "Ask \(.applicationName)",
            "Talk to \(.applicationName)",
            "Demande à \(.applicationName)",
            "Parle à \(.applicationName)",
        ], shortTitle: LocalizedStringResource("intent.ask.title", defaultValue: "Ask Rafiq"), systemImageName: "sparkles")
        AppShortcut(intent: AgentsStatusIntent(), phrases: [
            "Where are my agents in \(.applicationName)",
            "Ask \(.applicationName) where my agents are",
            "Où en sont mes agents dans \(.applicationName)",
            "Demande à \(.applicationName) où en sont mes agents",
        ], shortTitle: LocalizedStringResource("intent.agents.title", defaultValue: "Where are my agents"), systemImageName: "person.2.wave.2")
        AppShortcut(intent: NextPrayerIntent(), phrases: [
            "Next prayer with \(.applicationName)",
            "Ask \(.applicationName) for the next prayer",
            "Prochaine prière avec \(.applicationName)",
            "Demande à \(.applicationName) la prochaine prière",
        ], shortTitle: LocalizedStringResource("intent.prayer.title", defaultValue: "Next prayer"), systemImageName: "moon.fill")
        AppShortcut(intent: AgentTaskIntent(), phrases: [
            "Give a task to an agent with \(.applicationName)",
            "Donne une tâche à un agent avec \(.applicationName)",
        ], shortTitle: LocalizedStringResource("intent.task.title", defaultValue: "Give a task to an agent"), systemImageName: "hammer")
    }
}
#endif
