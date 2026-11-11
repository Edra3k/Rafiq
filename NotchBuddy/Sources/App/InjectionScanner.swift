import Foundation

// MARK: - InjectionScanner: traps hidden in what an agent reads
// Looks at what a tool brought back to the agent (a web page, a file, a command's output,
// PostToolUse tool_response) for text written to steer an AI: "ignore previous instructions",
// orders to hide things from the user or send secrets away, text hidden in invisible
// Unicode (tag characters, long runs of zero-width marks). A hit shows a card; nothing is
// blocked (the agent already has the text), but the user knows before approving what follows.
// Pure Foundation: tested by scripts/test-injection-scanner.sh.

struct InjectionHit: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case overrideInstructions, hideFromUser, exfiltrate, roleHijack, hiddenUnicode
    }
    var kind: Kind
    /// A short, one-line excerpt around the match (hidden characters made visible).
    var excerpt: String
}

enum InjectionScanner {
    private struct Rule {
        let kind: InjectionHit.Kind
        let regex: NSRegularExpression
    }

    private static func rx(_ p: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static let rules: [Rule] = [
        Rule(kind: .overrideInstructions, regex: rx(#"\b(ignore|disregard|forget|override)\b[^.\n]{0,30}\b(all|any|the|your)?\s*(previous|prior|above|earlier|system|original)\s+(instructions?|prompts?|rules?|directives?)"#)),
        Rule(kind: .overrideInstructions, regex: rx(#"\b(ignore|oublie|ignorez|oubliez)\b[^.\n]{0,30}\b(instructions?|consignes?)\s+(pr[ée]c[ée]dentes?|ant[ée]rieures?)"#)),
        Rule(kind: .overrideInstructions, regex: rx(#"\bnew\s+(system\s+)?instructions?\s*:"#)),
        Rule(kind: .hideFromUser, regex: rx(#"\b(do\s+not|don'?t|never)\s+(tell|inform|mention|reveal|show)\b[^.\n]{0,20}\b(the\s+)?(user|human|operator)\b"#)),
        Rule(kind: .hideFromUser, regex: rx(#"\bne\s+(dis|dites|mentionne|r[ée]v[èe]le)\s+(rien|pas)\b[^.\n]{0,20}\b(utilisateur|l'humain)\b"#)),
        Rule(kind: .exfiltrate, regex: rx(#"\b(send|post|upload|exfiltrate|forward|transmit|leak)\b[^.\n]{0,40}\b(api[\s_-]?keys?|credentials?|secrets?|tokens?|passwords?|\.env|ssh\s+keys?|id_rsa|cookies?)\b"#)),
        Rule(kind: .exfiltrate, regex: rx(#"\b(envoie|envoyer|transf[èe]re)\b[^.\n]{0,40}\b(cl[ée]s?\s+api|identifiants|secrets?|mots?\s+de\s+passe|jetons?)\b"#)),
        Rule(kind: .roleHijack, regex: rx(#"\b(you\s+are\s+now|from\s+now\s+on\s+you\s+are|act\s+as)\b[^.\n]{0,30}\b(unrestricted|jailbroken|dan|developer\s+mode|without\s+(any\s+)?restrictions)\b"#)),
        Rule(kind: .roleHijack, regex: rx(#"(<\|im_start\|>|\[INST\]|<<SYS>>|<system>|</system>|\bIMPORTANT:\s*(AI|LLM|assistant|agent)s?\b)"#)),
    ]

    /// Unicode tag characters (U+E0000–E007F) never belong in normal text; a run of zero-width
    /// characters (U+200B–200F, U+2060–2064, U+FEFF) longer than 8 hides text.
    static func hiddenUnicode(in text: String) -> String? {
        var tags = ""
        var zeroWidthRun = 0, maxRun = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0xE0000...0xE007F).contains(v) {
                if (0xE0020...0xE007E).contains(v), let s = Unicode.Scalar(v - 0xE0000) { tags.unicodeScalars.append(s) }
                continue
            }
            if (0x200B...0x200F).contains(v) || (0x2060...0x2064).contains(v) || v == 0xFEFF {
                zeroWidthRun += 1; maxRun = max(maxRun, zeroWidthRun)
            } else {
                zeroWidthRun = 0
            }
        }
        if !tags.isEmpty { return "⟨tags⟩ " + String(tags.prefix(80)) }
        if maxRun > 8 { return "⟨\(maxRun) zero-width characters⟩" }
        return nil
    }

    static func scan(_ text: String) -> [InjectionHit] {
        guard !text.isEmpty else { return [] }
        // Very large outputs: the start and the end are where injected text usually sits.
        let sample: String = text.count > 400_000 ? String(text.prefix(200_000)) + "\n" + String(text.suffix(200_000)) : text
        var hits: [InjectionHit] = []
        if let hidden = hiddenUnicode(in: sample) { hits.append(InjectionHit(kind: .hiddenUnicode, excerpt: hidden)) }
        let ns = sample as NSString
        var seen = Set<InjectionHit.Kind>()
        for rule in rules where !seen.contains(rule.kind) {
            guard let m = rule.regex.firstMatch(in: sample, range: NSRange(location: 0, length: ns.length)) else { continue }
            seen.insert(rule.kind)
            let start = max(0, m.range.location - 20)
            let length = min(ns.length - start, m.range.length + 40)
            let excerpt = ns.substring(with: NSRange(location: start, length: length))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            hits.append(InjectionHit(kind: rule.kind, excerpt: String(excerpt.prefix(120))))
        }
        return hits
    }

    /// A tool's response as text, whatever its shape (string, object, array).
    static func responseText(_ response: Any?) -> String? {
        switch response {
        case let s as String: return s
        case nil: return nil
        case let other?:
            guard JSONSerialization.isValidJSONObject(other),
                  let data = try? JSONSerialization.data(withJSONObject: other),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }
    }

    /// Tools whose response comes from outside the user's own instructions.
    static func readsOutside(_ tool: String) -> Bool {
        ["WebFetch", "WebSearch", "Read", "Bash", "Grep", "mcp"].contains { tool == $0 || tool.hasPrefix("mcp__") }
    }
}
