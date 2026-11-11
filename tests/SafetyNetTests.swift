import Foundation

@main
enum SafetyNetTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() {
        let dir = CommandLine.arguments[1]
        let fm = FileManager.default
        func write(_ name: String, _ text: String) { try! text.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8) }
        func read(_ name: String) -> String? { try? String(contentsOfFile: dir + "/" + name, encoding: .utf8) }

        // Not a repository yet.
        if case .failure(let f) = SafetyNet.save(cwd: dir) { check(f == .notARepository, "not a repository") } else { check(false, "should fail outside a repository") }

        SafetyNet.git(["init", "-q"], cwd: dir)
        write("a.txt", "one")
        write(".gitignore", "secret.log\n")
        SafetyNet.git(["add", "."], cwd: dir)
        SafetyNet.git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"], cwd: dir)
        write("a.txt", "two")                 // tracked change, not staged
        write("new.txt", "fresh")             // untracked
        write("secret.log", "ignored")        // ignored
        SafetyNet.git(["add", "a.txt"], cwd: dir)   // the user's own staging must survive
        let statusBefore = SafetyNet.git(["status", "--porcelain"], cwd: dir).out

        guard case .success(let net) = SafetyNet.save(cwd: dir, now: Date(timeIntervalSince1970: 1_800_000_000)) else {
            check(false, "save failed"); exit(1)
        }
        check(net.ref == "refs/rafiq/nets/1800000000", "ref name \(net.ref)")
        check(SafetyNet.git(["status", "--porcelain"], cwd: dir).out == statusBefore, "index and files untouched")
        check(SafetyNet.git(["stash", "list"], cwd: dir).out.isEmpty, "no stash entry")
        check(SafetyNet.git(["branch", "--list"], cwd: dir).out == "* main" || SafetyNet.git(["branch", "--list"], cwd: dir).out == "* master", "no new branch")
        let files = SafetyNet.git(["ls-tree", "-r", "--name-only", net.sha], cwd: dir).out
        check(files.contains("new.txt") && files.contains("a.txt") && !files.contains("secret.log"), "tree holds tracked + untracked, not ignored: \(files)")
        check(SafetyNet.git(["show", "\(net.sha):a.txt"], cwd: dir).out == "two", "saved the working copy")

        // The agent breaks things; the net brings them back.
        write("a.txt", "broken")
        try? fm.removeItem(atPath: dir + "/new.txt")
        if case .failure(let f) = SafetyNet.restore(net, cwd: dir) { check(false, "restore failed \(f)") }
        check(read("a.txt") == "two" && read("new.txt") == "fresh", "restored")
        check(SafetyNet.nets(cwd: dir).first?.sha == net.sha, "listed")

        // Pruning keeps the newest.
        for i in 1...3 { _ = SafetyNet.save(cwd: dir, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i))) }
        SafetyNet.prune(cwd: dir, keep: 2)
        check(SafetyNet.nets(cwd: dir).count == 2, "pruned to 2")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("SafetyNet: all tests passed")
    }
}
