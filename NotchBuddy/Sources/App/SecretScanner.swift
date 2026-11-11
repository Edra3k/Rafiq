import Foundation

// MARK: - SecretScanner
// Looks for credentials in the text an agent is about to write into a file (Write content,
// Edit new_string, MultiEdit edits): cloud keys, tokens, private keys, and a password or key
// assigned in plain text. A hit only shows a card (DigestCenter): the write still happens,
// nothing is denied for the user. Reported values are masked, never shown or logged whole.
// Pure Foundation: tested by scripts/test-secret-scanner.sh.

struct SecretHit: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case awsKey, githubToken, slackToken, stripeKey, googleKey, openAIKey, anthropicKey,
             privateKey, jwt, assignedSecret
    }
    var kind: Kind
    /// The first and last characters only: "AKIA••••••••Q7".
    var masked: String
    /// 1-based line in the scanned text.
    var line: Int
}

enum SecretScanner {
    private struct Rule {
        let kind: SecretHit.Kind
        let regex: NSRegularExpression
        /// Capture group holding the secret itself (0 = whole match).
        let group: Int
    }

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let rules: [Rule] = [
        Rule(kind: .awsKey, regex: rx(#"\b((?:AKIA|ASIA)[0-9A-Z]{16})\b"#), group: 1),
        Rule(kind: .githubToken, regex: rx(#"\b((?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b"#), group: 1),
        Rule(kind: .slackToken, regex: rx(#"\b(xox[abposr]-[A-Za-z0-9-]{10,})\b"#), group: 1),
        Rule(kind: .stripeKey, regex: rx(#"\b((?:sk|rk)_live_[A-Za-z0-9]{20,})\b"#), group: 1),
        Rule(kind: .googleKey, regex: rx(#"\b(AIza[0-9A-Za-z_\-]{35})\b"#), group: 1),
        Rule(kind: .anthropicKey, regex: rx(#"\b(sk-ant-[A-Za-z0-9_\-]{20,})"#), group: 1),
        Rule(kind: .openAIKey, regex: rx(#"\b(sk-(?:proj-)?[A-Za-z0-9_\-]{32,})"#), group: 1),
        Rule(kind: .privateKey, regex: rx(#"(-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----)"#), group: 1),
        Rule(kind: .jwt, regex: rx(#"\b(eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,})\b"#), group: 1),
        // password = "…", api_key: '…', SECRET_TOKEN="…" — a literal of 8+ characters.
        Rule(kind: .assignedSecret,
             regex: rx(#"(?:pass(?:word|wd)?|secret|api[_-]?key|access[_-]?token|auth[_-]?token|private[_-]?key|client[_-]?secret)[A-Za-z0-9_]*\s*[:=]\s*["']([^"'\s]{8,})["']"#,
                       [.caseInsensitive]),
             group: 1),
    ]

    /// Values that look like a secret but are placeholders.
    private static func isPlaceholder(_ value: String) -> Bool {
        let v = value.lowercased()
        let words = ["example", "changeme", "change-me", "your", "xxxx", "placeholder", "dummy", "test",
                     "fake", "sample", "<", "${", "{{", "process.env", "os.environ", "env(", "redacted", "****", "••"]
        if words.contains(where: { v.contains($0) }) { return true }
        // aaaaaaaa, 12345678: no real secret is one repeated character or a short run.
        return Set(v).count <= 3
    }

    static func scan(_ text: String) -> [SecretHit] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var hits: [SecretHit] = []
        var seen = Set<String>()
        for rule in rules {
            for m in rule.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let r = m.range(at: rule.group)
                guard r.location != NSNotFound else { continue }
                let value = ns.substring(with: r)
                if rule.kind == .assignedSecret || rule.kind == .openAIKey, isPlaceholder(value) { continue }
                // One secret, one hit (sk-ant- also matches the OpenAI shape).
                if seen.contains(where: { $0.contains(value) || value.contains($0) }) { continue }
                seen.insert(value)
                let line = ns.substring(to: r.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                hits.append(SecretHit(kind: rule.kind, masked: mask(value), line: line))
            }
        }
        return hits.sorted { $0.line < $1.line }
    }

    /// The text a tool is about to write: Write's content, Edit's new_string, MultiEdit's edits.
    static func writtenText(tool: String, input: [String: Any]) -> String? {
        switch tool {
        case "Write":
            return input["content"] as? String
        case "Edit":
            return input["new_string"] as? String
        case "MultiEdit":
            let edits = input["edits"] as? [[String: Any]] ?? []
            let joined = edits.compactMap { $0["new_string"] as? String }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        default:
            return nil
        }
    }

    /// "AKIAIOSFODNN7EXAMPLE" → "AKIA••••••••LE": enough to recognise it, not to use it.
    static func mask(_ value: String) -> String {
        if value.hasPrefix("-----BEGIN") { return value }
        let chars = Array(value)
        guard chars.count > 8 else { return String(repeating: "•", count: chars.count) }
        let head = chars.count >= 16 ? 4 : 2
        return String(chars.prefix(head)) + String(repeating: "•", count: 8) + String(chars.suffix(2))
    }
}
