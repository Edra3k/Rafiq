import Foundation

@main
enum SecretScannerTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func kinds(_ text: String) -> [SecretHit.Kind] { SecretScanner.scan(text).map(\.kind) }

    static func main() {
        // Fake values built at run time so the repository holds no secret-shaped literal.
        let aws = "AKIA" + "Z7Q2" + "K9LMNP3R" + "T5VW"
        let gh = "ghp_" + String(repeating: "aB3dE5", count: 6)
        let stripe = "sk_" + "live_" + String(repeating: "Xy9", count: 9)
        let anth = "sk-" + "ant-" + "api03-" + String(repeating: "Qw8_", count: 8)
        let google = "AIza" + String(repeating: "Sy0bC", count: 7)

        check(kinds("const key = \"\(aws)\"") == [.awsKey], "AWS key")
        check(kinds("token: \(gh)") == [.githubToken], "GitHub token")
        check(kinds("STRIPE=\(stripe)") == [.stripeKey], "Stripe live key")
        check(kinds("ANTHROPIC_API_KEY=\(anth)") == [.anthropicKey], "Anthropic key, once (not also OpenAI)")
        check(kinds("maps(\"\(google)\")") == [.googleKey], "Google key")
        check(kinds("-----BEGIN OPENSSH PRIVATE KEY-----\nabc") == [.privateKey], "private key")
        check(kinds("password = \"hunter2-Tr0ub4dor\"") == [.assignedSecret], "assigned password")
        check(kinds("client_secret: 'q8Zr!mN2pL'") == [.assignedSecret], "assigned client secret")

        // Not secrets.
        check(kinds("password = \"changeme123\"").isEmpty, "placeholder password")
        check(kinds("api_key = \"YOUR_API_KEY_HERE\"").isEmpty, "placeholder key")
        check(kinds("api_key = process.env.API_KEY").isEmpty, "read from the environment")
        check(kinds("secret = \"aaaaaaaaaaaa\"").isEmpty, "one repeated character")
        check(kinds("let skipped = items.filter { $0.isDone }").isEmpty, "ordinary code")
        check(kinds("").isEmpty, "empty text")

        // Masking and lines.
        let hit = SecretScanner.scan("a\nb\nlet k = \"\(aws)\"").first
        check(hit?.line == 3, "line number")
        check(hit?.masked == "AKIA••••••••VW", "masked value \(hit?.masked ?? "nil")")
        check(!(hit?.masked.contains("K9LMNP3R") ?? true), "the middle is never shown")

        // What each tool writes.
        check(SecretScanner.writtenText(tool: "Write", input: ["content": "x"]) == "x", "Write content")
        check(SecretScanner.writtenText(tool: "Edit", input: ["new_string": "y"]) == "y", "Edit new_string")
        check(SecretScanner.writtenText(tool: "MultiEdit", input: ["edits": [["new_string": "a"], ["new_string": "b"]]]) == "a\nb", "MultiEdit")
        check(SecretScanner.writtenText(tool: "Bash", input: ["command": "ls"]) == nil, "Bash writes nothing here")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("SecretScanner: all tests passed")
    }
}
