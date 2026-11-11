import Foundation

// MARK: - SafetyNet: "Allow with a net"
// Before a risky action is allowed, Rafiq saves the project's working tree (tracked and
// untracked files, ignored ones left out) as a commit kept under refs/rafiq/nets/<time>.
// It never touches the user's index, branch, stash or files: a separate index file is used,
// and the ref is not a branch. Restoring writes the saved files back over the working tree
// (after a confirmation in the app); files created since are left in place.
// Pure Foundation (Process + git): tested by scripts/test-safety-net.sh.

enum SafetyNet {
    struct Net: Equatable, Sendable {
        var ref: String
        var sha: String
        var date: Date
    }

    enum Failure: Error, Equatable {
        case notARepository
        case git(String)
    }

    @discardableResult
    static func git(_ args: [String], cwd: String, env: [String: String] = [:]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd] + args
        var environment = ["GIT_TERMINAL_PROMPT": "0", "PATH": "/usr/bin:/bin",
                           "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: o, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                String(data: e, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    /// Saves the working tree of the repository holding `cwd`. Slow on huge trees: call it
    /// off the main thread.
    static func save(cwd: String, now: Date = Date()) -> Result<Net, Failure> {
        let top = git(["rev-parse", "--show-toplevel"], cwd: cwd)
        guard top.status == 0, !top.out.isEmpty else { return .failure(.notARepository) }
        let root = top.out
        let tmpIndex = FileManager.default.temporaryDirectory
            .appendingPathComponent("rafiq-net-\(UUID().uuidString).index").path
        defer { try? FileManager.default.removeItem(atPath: tmpIndex) }
        let env = ["GIT_INDEX_FILE": tmpIndex]
        // Start from HEAD's tree when there is one, then add everything not ignored.
        let head = git(["rev-parse", "--verify", "-q", "HEAD"], cwd: root)
        if head.status == 0 { _ = git(["read-tree", "HEAD"], cwd: root, env: env) }
        let add = git(["add", "-A", "--", "."], cwd: root, env: env)
        guard add.status == 0 else { return .failure(.git(add.err)) }
        let tree = git(["write-tree"], cwd: root, env: env)
        guard tree.status == 0 else { return .failure(.git(tree.err)) }
        var commitArgs = ["commit-tree", tree.out, "-m", "Rafiq safety net"]
        if head.status == 0 { commitArgs += ["-p", head.out] }
        let commit = git(commitArgs, cwd: root, env: [
            "GIT_AUTHOR_NAME": "Rafiq", "GIT_AUTHOR_EMAIL": "rafiq@localhost",
            "GIT_COMMITTER_NAME": "Rafiq", "GIT_COMMITTER_EMAIL": "rafiq@localhost",
        ])
        guard commit.status == 0 else { return .failure(.git(commit.err)) }
        let stamp = Int(now.timeIntervalSince1970)
        let ref = "refs/rafiq/nets/\(stamp)"
        let update = git(["update-ref", ref, commit.out], cwd: root)
        guard update.status == 0 else { return .failure(.git(update.err)) }
        return .success(Net(ref: ref, sha: commit.out, date: now))
    }

    /// The nets kept for the repository holding `cwd`, newest first.
    static func nets(cwd: String) -> [Net] {
        let r = git(["for-each-ref", "--sort=-refname", "--format=%(refname) %(objectname)", "refs/rafiq/nets"], cwd: cwd)
        guard r.status == 0 else { return [] }
        return r.out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2, let stamp = Double(parts[0].split(separator: "/").last ?? "") else { return nil }
            return Net(ref: String(parts[0]), sha: String(parts[1]), date: Date(timeIntervalSince1970: stamp))
        }
    }

    /// Writes the net's files back over the working tree (the index is left as it is).
    static func restore(_ net: Net, cwd: String) -> Result<Void, Failure> {
        let top = git(["rev-parse", "--show-toplevel"], cwd: cwd)
        guard top.status == 0 else { return .failure(.notARepository) }
        let r = git(["restore", "--source", net.sha, "--worktree", "--", "."], cwd: top.out)
        return r.status == 0 ? .success(()) : .failure(.git(r.err))
    }

    /// Keeps the 20 newest nets of a repository.
    static func prune(cwd: String, keep: Int = 20) {
        for net in nets(cwd: cwd).dropFirst(keep) { git(["update-ref", "-d", net.ref], cwd: cwd) }
    }
}
