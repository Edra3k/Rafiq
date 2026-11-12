import Foundation

@main
enum AgentAskTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ raw: String, _ target: AskTarget, _ text: String? = nil, explicit: Bool? = nil,
                       chosen: AskTarget = .auto, hasHermes: Bool = true, line: Int = #line) {
        let r = AskRouter.route(raw, chosen: chosen, hasHermes: hasHermes)
        if r.target != target || (text != nil && r.text != text) || (explicit != nil && r.explicit != explicit) {
            failures += 1
            print("FAIL line \(line): \(raw.debugDescription) → \(r.target) \(r.text.debugDescription) explicit=\(r.explicit)")
        }
    }

    static func main() {
        // An agent named at the start wins, and is taken off the task.
        expect("demande à Hermes de vérifier l'espace disque", .hermes, "vérifier l'espace disque", explicit: true)
        expect("Hey Rafiq, demande à Hermes de redémarrer jellyfin", .hermes, "redémarrer jellyfin")
        expect("dis à Claude de corriger le build de Rafiq", .claude, "corriger le build de Rafiq", explicit: true)
        expect("Ask Hermes to check the disk", .hermes, "check the disk")
        expect("tell claude code to fix the tests", .claude, "fix the tests")
        expect("Claude, fix the tests", .claude, "fix the tests")
        expect("hermes: uptime du serveur", .hermes, "uptime du serveur")
        // A word that only starts like an agent is not one.
        expect("hermesien est un mot ?", .answer)

        // Auto.
        expect("vérifie l'espace disque du serveur", .hermes, explicit: false)
        expect("redémarre la VM jellyfin", .hermes)
        expect("rappelle-moi de sortir les poubelles à 20h", .hermes)
        expect("corrige le bug du build", .claude)
        expect("fix the failing tests in the api", .claude)
        expect("c'est quoi un reverse proxy", .answer)
        expect("why is the sky blue?", .answer)
        expect("range mon bureau", .hermes)
        // No Hermes here: Claude takes what Hermes would have.
        expect("vérifie le disque du serveur", .claude, hasHermes: false)
        expect("demande à Hermes de vérifier le disque", .claude, hasHermes: false)

        // A chip picked wins over the words.
        expect("corrige le bug", .hermes, "corrige le bug", explicit: true, chosen: .hermes)
        expect("demande à Hermes de corriger le bug", .claude, "corriger le bug", chosen: .claude)
        expect("vérifie le serveur", .answer, chosen: .answer)

        // The project named in the task.
        let folders = ["/Users/a/Rafiq", "/Users/a/code/rafiq-site", "/Users/a/api", "/Users/a/x"]
        func project(_ text: String, _ expected: String?, line: Int = #line) {
            let p = AskRouter.project(in: text, among: folders)
            if p != expected { failures += 1; print("FAIL line \(line): \(text) → \(p ?? "nil")") }
        }
        project("corrige le build de Rafiq", "/Users/a/Rafiq")
        project("update the rafiq site footer", "/Users/a/code/rafiq-site")
        project("fix the API tests", "/Users/a/api")
        project("fix the tests", nil)
        project("x marks the spot", nil)

        // A task in its own words.
        if !AskRouter.hasTaskWords("vérifie le disque du serveur") { failures += 1; print("FAIL task words server") }
        if AskRouter.hasTaskWords("quelle heure est-il") { failures += 1; print("FAIL task words time") }

        // Said aloud.
        func speech(_ answer: String, _ expected: [String], line: Int = #line) {
            let got = AskSpeech.sentences(answer)
            if got != expected { failures += 1; print("FAIL line \(line): \(got)") }
        }
        speech("Il reste **53 Go** sur `/dev/disk4s1s1`. Utilisé : 26 %.", ["Il reste 53 Go sur /dev/disk4s1s1.", "Utilisé : 26 %."])
        speech("## Résumé\n- Disque OK\n- Voir [le rapport](https://x.y/z)", ["Résumé Disque OK Voir le rapport"])
        speech("Voici :\n```\ndf -h\n```\nTout va bien !", ["Voici : Tout va bien !"])
        speech("Un. Deux. Trois. Quatre. Cinq.", ["Un.", "Deux.", "Trois.", "Quatre."])
        speech("", [])

        if failures == 0 { print("AgentAsk: all tests passed") } else { print("AgentAsk: \(failures) failure(s)"); exit(1) }
    }
}
