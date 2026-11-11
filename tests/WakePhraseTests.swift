import Foundation

// MARK: - WakePhrase tests (pure functions, no concurrency)

@main
enum WakePhraseTests {

    static var failures = 0

    static func main() {
        // MARK: split — should match

        // Basic wake phrases (no command)
        checkMatch("ok rafiq",              WakePhrase.split("ok rafiq"),              cmd: "")
        checkMatch("OK RAFIQ",              WakePhrase.split("OK RAFIQ"),              cmd: "")
        checkMatch("okay rafiq",            WakePhrase.split("okay rafiq"),            cmd: "")
        checkMatch("ok rafik",                WakePhrase.split("ok rafik"),                cmd: "")
        checkMatch("ok ra fiq",             WakePhrase.split("ok ra fiq"),             cmd: "")
        checkMatch("hey rafiq",             WakePhrase.split("hey rafiq"),             cmd: "")
        checkMatch("Hey Rafiq",             WakePhrase.split("Hey Rafiq"),             cmd: "")

        // Command extracted from original text (casing/punctuation preserved)
        checkMatch("Okay, Rafiq, ajoute GitHub",
                   WakePhrase.split("Okay, Rafiq, ajoute GitHub"),             cmd: "ajoute GitHub")
        checkMatch("ok rafique add github",
                   WakePhrase.split("ok rafique add github"),                    cmd: "add github")
        checkMatch("ok rafiq ouvre figma",
                   WakePhrase.split("ok rafiq ouvre figma"),                   cmd: "ouvre figma")

        // Apostrophes, hyphens and accents preserved in command
        checkMatch("OK Rafiq, mets l'album de Daft Punk",
                   WakePhrase.split("OK Rafiq, mets l'album de Daft Punk"),   cmd: "mets l'album de Daft Punk")
        checkMatch("ok rafiq qu'est-ce que fait Claude ?",
                   WakePhrase.split("ok rafiq qu'est-ce que fait Claude ?"),  cmd: "qu'est-ce que fait Claude ?")

        // Wake anywhere in transcript (word-boundary search)
        checkMatch("euh ok rafiq mets de la musique",
                   WakePhrase.split("euh ok rafiq mets de la musique"),        cmd: "mets de la musique")
        checkMatch("la chanson dit ok rafiq",
                   WakePhrase.split("la chanson dit ok rafiq"),                cmd: "") // accepted false positive

        // LAST occurrence wins
        checkMatch("ok rafiq search ok rafiq play music",
                   WakePhrase.split("ok rafiq search ok rafiq play music"),   cmd: "play music")

        // Partial word-by-word delivery
        checkNoMatch("ok alone",             WakePhrase.split("ok"))
        checkMatch("ok rafiq partial",      WakePhrase.split("ok rafiq"),              cmd: "")
        checkMatch("ok rafiq with more",    WakePhrase.split("ok rafiq mets"),         cmd: "mets")

        // MARK: split — should NOT match
        checkNoMatch("standalone rafiq",    WakePhrase.split("rafiq"))
        checkNoMatch("standalone RAFIQ",    WakePhrase.split("RAFIQ"))
        checkNoMatch("partial rafiq ça va", WakePhrase.split("rafiq ça va"))
        checkMatch("ok rafeeq (accent)",     WakePhrase.split("ok Rafeeq quelle heure"),  cmd: "quelle heure")
        checkMatch("hey ra fik",             WakePhrase.split("hey ra fik"),             cmd: "")
        checkNoMatch("ok rafale",            WakePhrase.split("ok rafale"))
        checkNoMatch("rafiq comment",       WakePhrase.split("rafiq comment tu vas"))
        checkNoMatch("ok google",            WakePhrase.split("ok google"))
        checkNoMatch("hey siri",             WakePhrase.split("hey siri"))
        checkNoMatch("okkkk rafiq",         WakePhrase.split("okkkk rafiq"))
        checkNoMatch("empty",                WakePhrase.split(""))

        // Summary
        if failures == 0 { print("\n\(total)/\(total) tests passed.") }
        else { print("\n\(failures) test(s) FAILED."); exit(1) }
    }

    static var total = 0

    static func checkMatch(_ label: String, _ r: WakePhrase.SplitResult, cmd: String) {
        total += 1
        if !r.matched {
            print("✗  \(label) — expected match, got no match"); failures += 1; return
        }
        if r.command != cmd {
            print("✗  \(label) — matched ✓ but command \"\(r.command)\" ≠ \"\(cmd)\""); failures += 1; return
        }
        print("✓  \(label)")
    }

    static func checkNoMatch(_ label: String, _ r: WakePhrase.SplitResult) {
        total += 1
        if r.matched { print("✗  \(label) — expected no match, got matched (cmd: \"\(r.command)\")"); failures += 1 }
        else         { print("✓  \(label)") }
    }
}
