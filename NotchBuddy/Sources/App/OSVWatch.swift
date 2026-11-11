import Foundation

// MARK: - OSVWatch: known vulnerabilities in the projects your agents work in
// Opt-in (Settings → General → Rafiq watches → Vulnerability watch, off by default): when a
// session starts in a project, Rafiq reads its lockfiles (package-lock.json, Cargo.lock,
// requirements.txt pinned with ==) and asks OSV.dev (Google's open vulnerability database,
// no account, no key) which of those exact versions have known advisories. Only package
// names and versions are sent; never a path, a file or anything else. Each project is checked
// at most once a day. A finding shows a Digest card with the worst packages and their fix.
// Parsing is pure Foundation: tested by scripts/test-osv-watch.sh.

struct LockedPackage: Hashable, Sendable {
    /// OSV ecosystem: "npm", "crates.io", "PyPI".
    var ecosystem: String
    var name: String
    var version: String
}

enum LockfileParser {
    /// The packages pinned by the lockfiles found at the root of `projectDir`.
    static func packages(in projectDir: URL) -> [LockedPackage] {
        var all: [LockedPackage] = []
        let fm = FileManager.default
        func read(_ name: String) -> Data? {
            let url = projectDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path),
                  let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
                  size < 20_000_000 else { return nil }
            return try? Data(contentsOf: url)
        }
        if let d = read("package-lock.json") { all += npm(d) }
        if let d = read("Cargo.lock"), let s = String(data: d, encoding: .utf8) { all += cargo(s) }
        if let d = read("requirements.txt"), let s = String(data: d, encoding: .utf8) { all += pip(s) }
        return Array(Set(all)).sorted { ($0.ecosystem, $0.name) < ($1.ecosystem, $1.name) }
    }

    /// package-lock.json v2/v3 ("packages": {"node_modules/x": {"version": …}}) or v1
    /// ("dependencies": {"x": {"version": …}}).
    static func npm(_ data: Data) -> [LockedPackage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [LockedPackage] = []
        if let packages = json["packages"] as? [String: Any] {
            for (path, value) in packages where path.contains("node_modules/") {
                guard let entry = value as? [String: Any], let version = entry["version"] as? String,
                      entry["link"] as? Bool != true else { continue }
                let name = String(path[path.range(of: "node_modules/", options: .backwards)!.upperBound...])
                guard !name.isEmpty else { continue }
                out.append(LockedPackage(ecosystem: "npm", name: name, version: version))
            }
        } else if let deps = json["dependencies"] as? [String: Any] {
            func walk(_ deps: [String: Any]) {
                for (name, value) in deps {
                    guard let entry = value as? [String: Any] else { continue }
                    if let version = entry["version"] as? String, !version.contains(":") {
                        out.append(LockedPackage(ecosystem: "npm", name: name, version: version))
                    }
                    if let nested = entry["dependencies"] as? [String: Any] { walk(nested) }
                }
            }
            walk(deps)
        }
        return out
    }

    /// Cargo.lock: [[package]] blocks with name = "…" and version = "…" (registry ones only).
    static func cargo(_ text: String) -> [LockedPackage] {
        var out: [LockedPackage] = []
        var name: String?, version: String?, source: String?
        func flush() {
            if let name, let version, source?.hasPrefix("registry+") == true {
                out.append(LockedPackage(ecosystem: "crates.io", name: name, version: version))
            }
            name = nil; version = nil; source = nil
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "[[package]]" { flush(); continue }
            func value(_ key: String) -> String? {
                guard line.hasPrefix(key + " = \"") , line.hasSuffix("\"") else { return nil }
                return String(line.dropFirst(key.count + 4).dropLast())
            }
            if let v = value("name") { name = v }
            if let v = value("version") { version = v }
            if let v = value("source") { source = v }
        }
        flush()
        return out
    }

    /// requirements.txt: only exact pins (name==1.2.3), extras and markers dropped.
    static func pip(_ text: String) -> [LockedPackage] {
        var out: [LockedPackage] = []
        for raw in text.split(separator: "\n") {
            var line = String(raw)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            if let semi = line.firstIndex(of: ";") { line = String(line[..<semi]) }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("-"), let range = line.range(of: "==") else { continue }
            var name = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let bracket = name.firstIndex(of: "[") { name = String(name[..<bracket]) }
            let version = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !version.isEmpty, !version.contains("*") else { continue }
            out.append(LockedPackage(ecosystem: "PyPI", name: name.lowercased(), version: version))
        }
        return out
    }
}

/// One advisory that touches one locked package.
struct OSVFinding: Equatable, Sendable {
    var package: LockedPackage
    var id: String
    var summary: String
    /// "CRITICAL", "HIGH", "MODERATE", "LOW", or "" when OSV gives none.
    var severity: String
    /// The first version that fixes it, if OSV knows one.
    var fixed: String?

    var rank: Int {
        switch severity.uppercased() {
        case "CRITICAL": return 4
        case "HIGH": return 3
        case "MODERATE", "MEDIUM": return 2
        case "LOW": return 1
        default: return 0
        }
    }
}

enum OSVResponse {
    /// /v1/querybatch: results[i].vulns[].id, in the order of the queries.
    static func batchIds(_ data: Data, count: Int) -> [[String]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return Array(repeating: [], count: count) }
        var out = results.map { ($0["vulns"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }
        if out.count < count { out += Array(repeating: [], count: count - out.count) }
        return Array(out.prefix(count))
    }

    /// /v1/vulns/{id}: the summary, the severity (database_specific.severity, as GitHub
    /// advisories give it) and the first fixed version for `package`.
    static func finding(_ data: Data, package: LockedPackage) -> OSVFinding? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else { return nil }
        let aliases = json["aliases"] as? [String] ?? []
        let shownId = aliases.first(where: { $0.hasPrefix("CVE-") }) ?? id
        let summary = (json["summary"] as? String) ?? (json["details"] as? String).map { String($0.prefix(120)) } ?? ""
        let severity = ((json["database_specific"] as? [String: Any])?["severity"] as? String) ?? ""
        var fixed: String?
        for affected in json["affected"] as? [[String: Any]] ?? [] {
            guard let pkg = affected["package"] as? [String: Any],
                  (pkg["name"] as? String)?.lowercased() == package.name.lowercased() else { continue }
            for range in affected["ranges"] as? [[String: Any]] ?? [] {
                for event in range["events"] as? [[String: Any]] ?? [] {
                    if let f = event["fixed"] as? String { fixed = fixed ?? f }
                }
            }
        }
        return OSVFinding(package: package, id: shownId, summary: summary, severity: severity, fixed: fixed)
    }
}

// MARK: - Watch

@MainActor
final class OSVWatch {
    static let shared = OSVWatch()
    static let enabledKey = "osvWatchEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var checking = Set<String>()
    private let lastCheckKey = "osvWatchLastCheck"

    /// A session started in `cwd`: check its project once a day, in the background.
    func sessionStarted(cwd: String) {
        guard Self.isEnabled, !cwd.isEmpty else { return }
        let dir = URL(fileURLWithPath: cwd)
        let key = dir.standardizedFileURL.path
        var last = UserDefaults.standard.dictionary(forKey: lastCheckKey) as? [String: Double] ?? [:]
        if let t = last[key], Date().timeIntervalSince1970 - t < 86_400 { return }
        guard !checking.contains(key) else { return }
        checking.insert(key)
        last[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(last, forKey: lastCheckKey)
        let project = dir.lastPathComponent
        Task.detached(priority: .utility) {
            let packages = LockfileParser.packages(in: dir)
            let findings = packages.isEmpty ? [] : await Self.query(packages)
            await MainActor.run {
                OSVWatch.shared.checking.remove(key)
                OSVWatch.shared.report(findings, project: project, path: key)
            }
        }
    }

    private static func query(_ packages: [LockedPackage]) async -> [OSVFinding] {
        let batch = Array(packages.prefix(1000))
        let body: [String: Any] = ["queries": batch.map {
            ["package": ["ecosystem": $0.ecosystem, "name": $0.name], "version": $0.version]
        }]
        guard let url = URL(string: "https://api.osv.dev/v1/querybatch"),
              let payload = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        let ids = OSVResponse.batchIds(data, count: batch.count)
        var pairs: [(LockedPackage, String)] = []
        for (i, list) in ids.enumerated() { for id in list { pairs.append((batch[i], id)) } }
        // Details for the first few only: the card shows three.
        var findings: [OSVFinding] = []
        for (pkg, id) in pairs.prefix(12) {
            guard let u = URL(string: "https://api.osv.dev/v1/vulns/\(id)"),
                  let (d, _) = try? await URLSession.shared.data(from: u),
                  let f = OSVResponse.finding(d, package: pkg) else { continue }
            findings.append(f)
        }
        // Advisories past the first 12 still count, without details.
        for (pkg, id) in pairs.dropFirst(12) {
            findings.append(OSVFinding(package: pkg, id: id, summary: "", severity: "", fixed: nil))
        }
        return findings
    }

    private func report(_ findings: [OSVFinding], project: String, path: String) {
        guard !findings.isEmpty else { return }
        let sorted = findings.sorted { $0.rank > $1.rank }
        let worst = sorted[0]
        let packages = Set(findings.map(\.package)).count
        let title = String(format: String(localized: "osv.title %lld %@", defaultValue: "%lld known vulnerabilities in %@"),
                           findings.count, project)
        let critical = findings.filter { $0.rank >= 3 }.count
        let fixes = sorted.prefix(3).map { f in
            "\(f.package.name) \(f.package.version)" + (f.fixed.map { " → \($0)" } ?? "") + " · \(f.id)"
        }
        let prompt = String(format: String(localized: "osv.prompt %@", defaultValue: "Update these dependencies to versions that fix their known vulnerabilities, then run the tests:\n%@"),
                            sorted.prefix(10).map { f in
                                "- \(f.package.name) \(f.package.version)" + (f.fixed.map { " → \($0)" } ?? "") + " (\(f.id))"
                            }.joined(separator: "\n"))
        DigestCenter.shared.show(Digest(
            kind: .cve,
            title: title,
            subtitle: worst.summary.isEmpty ? String(localized: "osv.subtitle", defaultValue: "From OSV.dev, for the exact versions in your lockfiles")
                                            : worst.summary,
            tiles: [
                .init(value: "\(findings.count)", label: String(localized: "osv.tile.advisories", defaultValue: "advisories"), tone: .bad),
                .init(value: "\(critical)", label: String(localized: "osv.tile.serious", defaultValue: "high or critical"), tone: critical > 0 ? .bad : .plain),
                .init(value: "\(packages)", label: String(localized: "osv.tile.packages", defaultValue: "packages"), tone: .plain),
            ],
            lines: fixes,
            code: fixes.first,
            primary: (String(localized: "osv.copy", defaultValue: "Copy a prompt for Claude"), .copy(prompt))
        ))
        _ = path
    }
}
