import SwiftUI

// MARK: - PushGuard: what a `git push` from an agent would send, checked first
//
// When an agent is about to run `git push` (PreToolUse, PermissionRequest), Rafiq lists the
// files of the commits no remote has yet and looks for what should not leave the Mac: a key or
// a password in their text (SecretScanner), an .env, a private key, a file over 10 MB. Found
// something: the approval card shows it (Deny stays your click), and if the push needs no
// approval, a red card says what left with it. Read only: Rafiq never changes the repository.

struct PushFinding: Equatable, Identifiable {
    enum Reason: Equatable { case secret(String), envFile, keyFile, large(Int64) }
    var id: String { path }
    var path: String
    var reason: Reason

    var isSecret: Bool {
        switch reason { case .secret, .envFile, .keyFile: return true; case .large: return false }
    }

    var label: String {
        switch reason {
        case .secret(let what): return what
        case .envFile: return String(localized: "push.env", defaultValue: "environment file")
        case .keyFile: return String(localized: "push.key", defaultValue: "private key or certificate")
        case .large(let bytes): return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }
}

struct PushReport: Equatable {
    var cwd: String
    var commits: Int
    var findings: [PushFinding]
    var at: Date
    var hasSecret: Bool { findings.contains(where: \.isSecret) }
}

@MainActor
final class PushGuard: ObservableObject {
    static let shared = PushGuard()
    static let enabledKey = "pushGuardEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// The latest report of each folder, while it is fresh (10 minutes).
    @Published private(set) var reports: [String: PushReport] = [:]
    private var checking: Set<String> = []

    nonisolated static let largeBytes: Int64 = 10 * 1_048_576
    nonisolated static let scanBytes: Int64 = 1_048_576

    /// `git push`, `git -C dir push`, after `&&` or `;`.
    nonisolated static func isPush(_ command: String) -> Bool {
        command.range(of: #"(^|[\s;&|(])git(\s+-C\s+\S+)?(\s+-c\s+\S+)*\s+push\b"#, options: .regularExpression) != nil
    }

    func report(for cwd: String) -> PushReport? {
        guard let r = reports[cwd], Date().timeIntervalSince(r.at) < 600 else { return nil }
        return r
    }

    /// An agent is about to push from `cwd`: check, then warn if a push may already go.
    func check(command: String, cwd: String, pill: String) {
        guard Self.isEnabled, Self.isPush(command), !cwd.isEmpty, !checking.contains(cwd) else { return }
        checking.insert(cwd)
        Task.detached(priority: .userInitiated) {
            let report = Self.scan(cwd: cwd)
            await MainActor.run {
                let guardian = PushGuard.shared
                guardian.checking.remove(cwd)
                appendAppLog("nb.log", "[PushGuard] \(URL(fileURLWithPath: cwd).lastPathComponent): "
                              + (report.map { "\($0.commits) commits, \($0.findings.count) findings" } ?? "not a repository"))
                guard let report else { guardian.reports[cwd] = nil; return }
                guardian.reports[cwd] = report
                guard !report.findings.isEmpty else { return }
                // With a request on the card, the card shows it; without one the push goes on.
                if AppState.shared.pendingApproval.map({ $0.cwd == cwd && PushGuard.isPush($0.command) }) != true {
                    guardian.warn(report, pill: pill)
                }
            }
        }
    }

    private func warn(_ report: PushReport, pill: String) {
        SoundEngine.shared.play("error")
        let project = URL(fileURLWithPath: report.cwd).lastPathComponent
        let names = report.findings.prefix(4).map { "\($0.path) — \($0.label)" }
        let prompt = String(format: String(localized: "push.prompt %@", defaultValue:
            "Take these files out of the commits that aren't pushed yet, add them to .gitignore, and don't push them: %@"),
            report.findings.map(\.path).joined(separator: ", "))
        DigestCenter.shared.show(Digest(
            kind: .push,
            title: report.hasSecret
                ? String(localized: "push.title.secret", defaultValue: "This push carries a secret")
                : String(localized: "push.title.large", defaultValue: "This push carries large files"),
            subtitle: report.commits == 1
                ? String(format: String(localized: "push.subtitle.one %@", defaultValue: "%@ · 1 commit not on the remote yet"), project)
                : String(format: String(localized: "push.subtitle %@ %lld", defaultValue: "%@ · %lld commits not on the remote yet"),
                         project, Int64(report.commits)),
            lines: names + [String(localized: "push.no-approval", defaultValue: "The push didn't ask for your OK: check the remote, and rotate a key that left.")],
            primary: (String(localized: "secret.copy", defaultValue: "Copy a prompt for Claude"), .copy(prompt))
        ))
    }

    // MARK: Scan (off the main actor)

    nonisolated static func scan(cwd: String) -> PushReport? {
        guard let count = git(["rev-list", "HEAD", "--not", "--remotes", "--count"], cwd: cwd).flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        else { return nil }
        guard count > 0 else { return PushReport(cwd: cwd, commits: 0, findings: [], at: Date()) }
        let names = git(["log", "HEAD", "--not", "--remotes", "--name-only", "--format="], cwd: cwd) ?? ""
        var paths: [String] = []
        for line in names.split(separator: "\n") where !line.isEmpty {
            let p = String(line)
            if !paths.contains(p) { paths.append(p) }
            if paths.count >= 300 { break }
        }
        var findings: [PushFinding] = []
        for path in paths {
            // Only what HEAD still has (a file added then removed doesn't leave in this state).
            guard let sizeText = git(["cat-file", "-s", "HEAD:\(path)"], cwd: cwd),
                  let size = Int64(sizeText.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            if name == ".env" || (name.hasPrefix(".env.") && !name.hasSuffix(".example") && !name.hasSuffix(".sample") && !name.hasSuffix(".template")) {
                findings.append(PushFinding(path: path, reason: .envFile)); continue
            }
            if ["id_rsa", "id_ed25519", "id_ecdsa"].contains(name) || [".pem", ".p12", ".pfx", ".key", ".keystore"].contains(where: { name.hasSuffix($0) }) {
                findings.append(PushFinding(path: path, reason: .keyFile)); continue
            }
            if size > largeBytes { findings.append(PushFinding(path: path, reason: .large(size))); continue }
            if size <= scanBytes, let text = git(["show", "HEAD:\(path)"], cwd: cwd),
               let hit = SecretScanner.scan(text).first {
                findings.append(PushFinding(path: path, reason: .secret("\(SecretAlert.label(hit.kind)) \(hit.masked)")))
            }
        }
        return PushReport(cwd: cwd, commits: count, findings: findings, at: Date())
    }

    /// `git -C cwd …`'s output, nil when it fails (not a repository, no HEAD…).
    nonisolated private static func git(_ args: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// On a request to `git push`: what it would send that shouldn't leave (nothing when clean).
struct PushGuardBanner: View {
    let cwd: String
    let command: String
    @ObservedObject private var guardian = PushGuard.shared

    var body: some View {
        if PushGuard.isPush(command), let report = guardian.report(for: cwd), !report.findings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.shield.fill").font(.system(size: 10))
                    Text(verbatim: report.hasSecret
                         ? String(localized: "push.title.secret", defaultValue: "This push carries a secret")
                         : String(localized: "push.title.large", defaultValue: "This push carries large files"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#F4505E"))
                ForEach(report.findings.prefix(3)) { f in
                    HStack(spacing: 6) {
                        Text(verbatim: f.path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.head)
                        Spacer(minLength: 4)
                        Text(verbatim: f.label).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundColor(Color(hex: f.isSecret ? "#F7C1C1" : "#F5C27A"))
                }
                if report.findings.count > 3 {
                    Text(verbatim: String(format: String(localized: "details.more %lld", defaultValue: "+ %lld more"), Int64(report.findings.count - 3)))
                        .font(.system(size: 10)).foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#F4505E").opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: "#F4505E").opacity(0.4), lineWidth: 1))
        }
    }
}
