#if !APPSTORE
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - JarvisRouter: what the user asked, as a command Rafiq runs itself
//
// The on-device model is small: left to pick among many tools it sometimes answers without
// calling any, and then says "done" for something that never happened. So for the Mac's own
// powers (calendar, reminders, the screen, apps, files, volume, timers, the web, Shortcuts) it
// only fills a typed command (guided generation); Rafiq runs it and the model then says the
// real outcome in one sentence. Anything else goes on to the conversational brain.

@MainActor
enum JarvisRouter {
    /// Words that make it worth asking the router first (a quick, local test).
    static let cue: Set<String> = [
        "minuteur", "minuteurs", "timer", "alarme", "rappel", "rappels", "rappelle", "agenda", "calendrier",
        "rendez", "reunion", "evenement", "demain", "aujourd", "ecran", "screen", "raccourci", "raccourcis",
        "shortcut", "shortcuts", "fichier", "fichiers", "dossier", "ouvre", "open", "cherche", "trouve",
        "find", "volume", "son", "muet", "mute", "google", "recherche", "search", "web", "internet",
        "lumiere", "lumieres", "lampe", "salon", "chambre", "maison", "traduis", "translate", "resume",
        "explique", "page", "reminder", "calendar", "event", "agenda", "schedule", "today", "tomorrow",
    ]

    static func mightHandle(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: cue.contains)
    }

    /// The reply to say, or nil when this isn't one of the Mac's powers (or no model).
    static func handle(_ transcript: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard mightHandle(transcript), SystemLanguageModel.default.availability == .available else { return nil }
            let fr = VoiceSettings.language == "fr"
            let classifier = LanguageModelSession(instructions: Self.classifierInstructions())
            guard let command = try? await classifier.respond(to: transcript, generating: JarvisCommand.self).content,
                  command.domain != "none", command.action != "none" else { return nil }
            #if DEBUG
            appendAppLog("nb.log", "[Jarvis route] \(command.domain)/\(command.action) text=\(command.text) when=\(command.when) n=\(command.number)")
            #endif
            let outcome = await run(command)
            #if DEBUG
            appendAppLog("nb.log", "[Jarvis route] outcome: \(outcome.prefix(160))")
            #endif
            if outcome.hasPrefix(JarvisMac.finalMark) { return String(outcome.dropFirst(JarvisMac.finalMark.count)) }
            // Everything but the screen is said as it happened: the model never rephrases a result
            // (it invented files and reminders when it did).
            guard command.action == "read_screen" else { return outcome }
            // The model says what really happened, in the user's language, in a sentence or two.
            let speaker = LanguageModelSession(instructions: fr
                ? "Tu es Rafiq, un assistant vocal. Tu tutoies l'utilisateur. Réponds en français, en une ou deux phrases courtes, sans rien inventer : dis seulement ce que les faits disent. Pour une liste longue (fichiers, raccourcis), cite les deux ou trois plus utiles et dis combien il y en a."
                : "You are Rafiq, a voice assistant. Answer in English in one or two short sentences, inventing nothing: say only what the facts say. For a long list (files, shortcuts), name the two or three most useful and say how many there are.")
            let prompt = command.domain == "screen"
                ? (fr ? "Question de l'utilisateur : \(transcript)\nCe qu'il y a à l'écran :\n\(outcome)\nRéponds à sa question à partir de l'écran."
                      : "The user's question: \(transcript)\nWhat is on screen:\n\(outcome)\nAnswer the question from the screen.")
                : (fr ? "L'utilisateur a dit : \(transcript)\nRésultat réel : \(outcome)\nDis-lui le résultat."
                      : "The user said: \(transcript)\nActual result: \(outcome)\nTell them the result.")
            return (try? await speaker.respond(to: prompt).content) ?? outcome
        }
        #endif
        return nil
    }

    static func classifierInstructions() -> String {
        """
        Turn the user's request (French or English) into one command for a Mac assistant. It is \(VoiceBrain.nowText(fr: false)).
        Actions:
        - agenda: what is in the calendar (when = today, tomorrow or yyyy-MM-dd).
        - add_event: a calendar event (text = title, when = yyyy-MM-dd HH:mm, number = minutes, 60 if not said).
        - add_reminder: only when the user says "rappelle-moi", "rappel" or "remind me" (text = what, when = yyyy-MM-dd HH:mm or empty).
        - list_reminders: the reminders.
        - read_screen: about what is on the screen, a page, an error shown, to translate or sum up what they see.
        - open_app (text = app name), find_file or open_file (text = the file name only).
        - volume (number 0-100), mute, unmute.
        - timer: "minuteur", "timer", "dans 5 minutes préviens-moi" (number = minutes, text = what for). A timer is never a reminder.
        - web_search (text = what to search).
        - list_shortcuts, run_shortcut (text = the shortcut's name; for lights or the home, the device words).
        - none: anything else (questions, chat, agents, prayers, music, pills, email).
        Set domain to calendar, reminder, screen, mac or shortcut to match, or none.
        Examples: "mets un minuteur de 5 minutes pour les pâtes" → timer, number 5, text pâtes. "qu'est-ce que j'ai demain" → agenda, when tomorrow. "rappelle-moi d'appeler Karim demain à 9h" → add_reminder, text appeler Karim, when <tomorrow's date> 09:00. "c'est quoi cette erreur à l'écran" → read_screen. "cherche le fichier CHANGELOG" → find_file, text CHANGELOG. "éteins la lumière du salon" → run_shortcut, text lumière salon. "où en est Claude" → none.
        """
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    static func run(_ c: JarvisCommand) async -> String {
        switch c.action {
        case "agenda": return await JarvisMac.agenda(day: c.when)
        case "add_event": return await JarvisMac.addEvent(title: c.text, start: c.when, minutes: c.number > 0 ? c.number : 60)
        case "add_reminder": return await JarvisMac.addReminder(title: c.text, due: c.when)
        case "list_reminders": return await JarvisMac.reminders()
        case "read_screen": return await JarvisMac.screenText()
        case "open_app": return JarvisMac.openApp(c.text)
        case "find_file": return JarvisMac.findFiles(c.text, open: false)
        case "open_file": return JarvisMac.findFiles(c.text, open: true)
        case "volume": return JarvisMac.volume(c.number, mute: nil)
        case "mute": return JarvisMac.volume(nil, mute: true)
        case "unmute": return JarvisMac.volume(nil, mute: false)
        case "timer": return JarvisMac.timer(minutes: Double(max(c.number, 1)), label: c.text)
        case "web_search": return JarvisMac.webSearch(c.text)
        case "list_shortcuts":
            let names = await Task.detached { JarvisMac.shortcutNames() }.value
            return names.isEmpty ? String(localized: "jarvis.shortcuts.none", defaultValue: "You have no Shortcuts.")
                : String(format: String(localized: "jarvis.shortcuts.list %@", defaultValue: "Your shortcuts: %@."), names.joined(separator: ", "))
        case "run_shortcut":
            let name = c.text
            return await Task.detached { JarvisMac.runShortcut(name, input: "") }.value
        default: return String(localized: "jarvis.nothing", defaultValue: "I didn't do anything.")
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct JarvisCommand {
    @Guide(description: "What kind of request", .anyOf(["calendar", "reminder", "screen", "mac", "shortcut", "none"]))
    var domain: String
    @Guide(description: "The action, as listed in the instructions",
           .anyOf(["agenda", "add_event", "add_reminder", "list_reminders", "read_screen", "open_app", "find_file",
                   "open_file", "volume", "mute", "unmute", "timer", "web_search", "list_shortcuts", "run_shortcut", "none"]))
    var action: String
    @Guide(description: "Title, app or file name, search words, timer label or shortcut name; empty if none")
    var text: String
    @Guide(description: "A day (today, tomorrow, yyyy-MM-dd) or a date and time (yyyy-MM-dd HH:mm); empty if none")
    var when: String
    @Guide(description: "Minutes for a timer or an event, volume 0-100; 0 if none")
    var number: Int
}
#endif
#endif
