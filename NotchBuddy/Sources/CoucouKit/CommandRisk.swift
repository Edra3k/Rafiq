import Foundation

// MARK: - CommandRisk
// The agent guard: how risky the action an agent asks to run is, shown as a badge on the
// approval card (and in the island's header). A rating only informs: it never allows or
// denies anything by itself. Every decision stays an explicit click (CLAUDE.md).
//
// Shell commands are read with the same POSIX word splitter as the Antigravity rules
// (AgyPermissionRules.parse); the whole line takes the worst rating of its parts.
// Pure Foundation, no AppKit: tested by scripts/test-command-risk.sh.

struct CommandRisk: Equatable, Sendable {
    enum Level: Int, Comparable, Sendable {
        /// Reads only: nothing on disk or on the network changes.
        case safe
        /// Changes files, uses the network, installs or runs code: worth a look.
        case caution
        /// Can destroy work, leak secrets or take over the machine.
        case high

        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    enum Reason: String, Equatable, Sendable {
        case readOnly, writesFiles, network, installs, runsCode, publishes, unknown
        case deletes, forcePush, rewritesHistory, pipeToShell, privilege, secrets, systemConfig
    }

    var level: Level
    var reason: Reason

    static let safe = CommandRisk(level: .safe, reason: .readOnly)

    // MARK: Assessing

    /// The rating of what `tool` asks to do. `command` is the shell line for shell tools,
    /// or the tool's name when there is none (Claude Code's Write, Edit…).
    static func assess(tool: String, command: String) -> CommandRisk {
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line == tool { return assessTool(tool) }
        return assessShell(line)
    }

    /// Tools that are not a shell line.
    static func assessTool(_ tool: String) -> CommandRisk {
        switch tool {
        case "Read", "Glob", "Grep", "LS", "NotebookRead", "WebSearch", "TodoWrite", "TodoRead":
            return .safe
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            return CommandRisk(level: .caution, reason: .writesFiles)
        case "WebFetch":
            return CommandRisk(level: .caution, reason: .network)
        default:
            return CommandRisk(level: .caution, reason: .unknown)
        }
    }

    /// A shell line: the worst of its parts.
    static func assessShell(_ line: String) -> CommandRisk {
        // A line that cannot be read reliably (an open quote) is not trusted.
        guard let parsed = AgyPermissionRules.parse(line), !parsed.segments.isEmpty else {
            return CommandRisk(level: .caution, reason: .unknown)
        }
        var worst = CommandRisk.safe
        func take(_ r: CommandRisk) { if r.level > worst.level { worst = r } }

        // Sensitive places anywhere on the line, read or written: keys, keychains, shell setup.
        if sensitivePath(in: line) { take(CommandRisk(level: .high, reason: .secrets)) }
        // Writing through a redirection (> file, >> file), not to /dev/null.
        if writesThroughRedirection(parsed) { take(CommandRisk(level: .caution, reason: .writesFiles)) }
        // Something downloaded then handed to a shell or an interpreter: curl … | sh.
        if pipesDownloadToShell(parsed) { take(CommandRisk(level: .high, reason: .pipeToShell)) }
        // A command hidden inside $(…) or backticks: at least worth a look.
        if parsed.hasSubstitution { take(CommandRisk(level: .caution, reason: .runsCode)) }

        for segment in parsed.segments { take(assessWords(segment)) }
        return worst
    }

    // MARK: One command

    static func assessWords(_ raw: [String]) -> CommandRisk {
        var words = raw
        // FOO=bar cmd …: the assignments only set the environment.
        while let first = words.first, isAssignment(first) { words.removeFirst() }
        guard var name = words.first else { return .safe }
        if ["sudo", "doas", "su", "pkexec"].contains(name) {
            return CommandRisk(level: .high, reason: .privilege)
        }
        // Wrappers that only change how the command runs.
        while ["env", "nohup", "time", "nice", "command", "exec", "xargs"].contains(name), words.count > 1 {
            words.removeFirst()
            while let first = words.first, first.hasPrefix("-") || isAssignment(first) { words.removeFirst() }
            guard let next = words.first else { return .safe }
            name = next
        }
        name = (name as NSString).lastPathComponent
        let args = Array(words.dropFirst())
        let flags = args.filter { $0.hasPrefix("-") }

        switch name {
        // Reads only.
        case "ls", "cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "ag",
             "wc", "pwd", "echo", "printf", "which", "whereis", "type", "file", "stat", "du", "df",
             "tree", "sort", "uniq", "cut", "tr", "diff", "cmp", "jq", "yq", "date", "cal",
             "basename", "dirname", "realpath", "readlink", "true", "false", "test", "[",
             "whoami", "id", "uname", "sw_vers", "hostname", "uptime", "ps", "top", "lsof",
             "md5", "shasum", "sha256sum", "md5sum", "xxd", "hexdump", "strings", "otool", "nm",
             "column", "nl", "fold", "rev", "seq", "sleep", "cd", "pushd", "popd", "plutil", "defaults":
            if name == "defaults", args.first.map({ ["write", "delete", "import"].contains($0) }) == true {
                return CommandRisk(level: .caution, reason: .systemConfig)
            }
            if name == "plutil", flags.contains(where: { ["-replace", "-insert", "-remove", "-convert"].contains($0) }) {
                return CommandRisk(level: .caution, reason: .writesFiles)
            }
            return .safe
        case "sed", "awk", "gawk", "perl":
            if flags.contains(where: { $0 == "-i" || $0.hasPrefix("-i") }) {
                return CommandRisk(level: .caution, reason: .writesFiles)
            }
            return name == "perl" ? CommandRisk(level: .caution, reason: .runsCode) : .safe
        case "find", "fd":
            if args.contains(where: { ["-delete", "-exec", "-execdir", "-ok", "--exec", "-x", "-X"].contains($0) }) {
                return CommandRisk(level: .caution, reason: .runsCode)
            }
            return .safe
        case "env", "printenv", "set", "export":
            // Prints (or sets) the environment, where tokens often live.
            return args.isEmpty ? CommandRisk(level: .caution, reason: .secrets) : .safe

        // Destroys.
        case "rm", "rmdir", "unlink", "srm", "trash":
            let recursive = flags.contains { $0 == "--recursive" || (!$0.hasPrefix("--") && ($0.contains("r") || $0.contains("R"))) }
            let force = flags.contains { $0 == "--force" || (!$0.hasPrefix("--") && $0.contains("f")) }
            let wide = args.contains { ["/", "~", "~/", "$HOME", "*", ".", "..", "/*", "~/*"].contains($0) }
            if recursive || force || wide { return CommandRisk(level: .high, reason: .deletes) }
            return CommandRisk(level: .caution, reason: .deletes)
        case "dd", "mkfs", "shred", "wipefs", "fdisk", "newfs_apfs", "newfs_hfs":
            return CommandRisk(level: .high, reason: .deletes)
        case "diskutil":
            if args.contains(where: { $0.lowercased().hasPrefix("erase") || $0 == "partitionDisk" || $0 == "zeroDisk" || $0 == "secureErase" }) {
                return CommandRisk(level: .high, reason: .deletes)
            }
            return args.first == "list" || args.first == "info" ? .safe : CommandRisk(level: .caution, reason: .systemConfig)
        case "tmutil":
            return args.first.map { ["deletelocalsnapshots", "delete", "thinlocalsnapshots", "disable"].contains($0) } == true
                ? CommandRisk(level: .high, reason: .deletes) : .safe
        case "mv", "cp", "ln", "rsync", "ditto", "install", "touch", "mkdir", "tee", "truncate":
            if name == "rsync", flags.contains(where: { $0.hasPrefix("--delete") }) {
                return CommandRisk(level: .high, reason: .deletes)
            }
            if name == "rsync" { return CommandRisk(level: .caution, reason: .network) }
            return CommandRisk(level: .caution, reason: .writesFiles)

        // Git.
        case "git":
            return assessGit(args)
        case "gh":
            let sub = args.prefix(2).joined(separator: " ")
            if ["repo delete", "release delete", "secret set", "secret delete", "auth token"].contains(sub) {
                return CommandRisk(level: .high, reason: sub.hasPrefix("secret") || sub == "auth token" ? .secrets : .deletes)
            }
            if ["pr merge", "release create", "pr create", "issue create", "pr comment", "issue comment", "repo create"].contains(sub) {
                return CommandRisk(level: .caution, reason: .publishes)
            }
            if args.first == "api" {
                // gh api reads unless it is told another method.
                return args.contains("-X") || args.contains("--method") || args.contains("-f") || args.contains("-F")
                    ? CommandRisk(level: .caution, reason: .network) : .safe
            }
            let reads: Set<String> = ["pr view", "pr list", "pr diff", "pr checks", "pr status", "issue view",
                                      "issue list", "run list", "run view", "repo view", "auth status"]
            return reads.contains(sub) ? .safe : CommandRisk(level: .caution, reason: .network)

        // Network.
        case "curl", "wget", "http", "https", "ssh", "nc", "ncat", "netcat", "telnet", "ftp", "sftp", "scp":
            return CommandRisk(level: .caution, reason: .network)

        // Installs and package managers.
        case "npm", "pnpm", "yarn", "bun", "pip", "pip3", "pipx", "uv", "gem", "cargo", "brew", "apt",
             "apt-get", "port", "go", "swift", "composer", "poetry", "conda", "mamba":
            return assessPackageManager(name, args)
        case "npx", "bunx", "pnpx", "uvx":
            return CommandRisk(level: .caution, reason: .installs)

        // Runs code.
        case "sh", "bash", "zsh", "fish", "python", "python3", "node", "deno", "ruby", "php", "osascript",
             "make", "cmake", "xcodebuild", "xcodegen", "swiftc", "clang", "gcc", "tsc", "pytest", "jest",
             "vitest", "eval", "source", ".", "open", "docker", "podman", "kubectl", "terraform":
            if name == "eval" { return CommandRisk(level: .high, reason: .pipeToShell) }
            if name == "terraform", args.first.map({ ["apply", "destroy"].contains($0) }) == true {
                return CommandRisk(level: .high, reason: .deletes)
            }
            if name == "kubectl", args.first == "delete" { return CommandRisk(level: .high, reason: .deletes) }
            return CommandRisk(level: .caution, reason: .runsCode)

        // The machine itself.
        case "chmod", "chown", "chgrp", "xattr", "chflags":
            if args.contains("777") || args.contains("a+rwx") { return CommandRisk(level: .high, reason: .systemConfig) }
            return CommandRisk(level: .caution, reason: .writesFiles)
        case "launchctl", "crontab", "systemctl", "csrutil", "spctl", "pfctl", "networksetup", "scutil",
             "pmset", "nvram", "dscl", "kextload", "systemsetup", "profiles":
            return CommandRisk(level: .high, reason: .systemConfig)
        case "security":
            if args.first.map({ $0.hasPrefix("find-") || $0.hasPrefix("dump-") || $0 == "export" || $0.hasPrefix("delete-") }) == true {
                return CommandRisk(level: .high, reason: .secrets)
            }
            return CommandRisk(level: .caution, reason: .secrets)
        case "kill", "killall", "pkill":
            return CommandRisk(level: .caution, reason: .systemConfig)
        case "base64":
            return .safe
        default:
            return CommandRisk(level: .caution, reason: .unknown)
        }
    }

    static func assessGit(_ args: [String]) -> CommandRisk {
        // git -C dir …, git -c key=value …: skip to the subcommand.
        var rest = args[...]
        while let first = rest.first, first.hasPrefix("-") {
            rest = rest.dropFirst()
            if ["-C", "-c", "--git-dir", "--work-tree"].contains(first) { rest = rest.dropFirst() }
        }
        guard let sub = rest.first else { return .safe }
        let more = Array(rest.dropFirst())
        let flags = more.filter { $0.hasPrefix("-") }
        switch sub {
        case "status", "log", "diff", "show", "blame", "rev-parse", "describe", "shortlog", "grep",
             "ls-files", "ls-tree", "ls-remote", "reflog", "cat-file", "merge-base", "name-rev", "whatchanged":
            return .safe
        case "branch":
            if flags.contains(where: { $0 == "-D" || $0 == "--delete" && more.contains("--force") }) {
                return CommandRisk(level: .high, reason: .deletes)
            }
            return flags.contains(where: { ["-d", "-m", "-M", "--delete", "--move"].contains($0) }) || more.contains(where: { !$0.hasPrefix("-") })
                ? CommandRisk(level: .caution, reason: .writesFiles) : .safe
        case "remote", "tag", "stash", "config":
            if sub == "config", more.contains(where: { $0.contains("credential") || $0.contains("hooksPath") }) {
                return CommandRisk(level: .high, reason: .secrets)
            }
            return more.isEmpty || flags == ["-v"] || flags == ["--list"] || flags == ["-l"]
                || (sub == "stash" && more.first == "list") || (sub == "config" && flags.contains("--get"))
                ? .safe : CommandRisk(level: .caution, reason: .writesFiles)
        case "push":
            if flags.contains(where: { $0 == "-f" || $0 == "--force" || $0.hasPrefix("--force-with-lease") || $0 == "--mirror" || $0 == "--delete" || $0 == "-d" })
                || more.contains(where: { $0.hasPrefix("+") || $0.hasPrefix(":") }) {
                return CommandRisk(level: .high, reason: .forcePush)
            }
            return CommandRisk(level: .caution, reason: .publishes)
        case "reset":
            return flags.contains("--hard") ? CommandRisk(level: .high, reason: .deletes) : CommandRisk(level: .caution, reason: .writesFiles)
        case "clean":
            return flags.contains(where: { $0.hasPrefix("-") && $0.contains("f") && !$0.contains("n") })
                ? CommandRisk(level: .high, reason: .deletes) : .safe
        case "checkout", "restore", "switch":
            if more.contains("--") || more.contains(".") || flags.contains("-f") || flags.contains("--force") {
                return CommandRisk(level: .high, reason: .deletes)
            }
            return CommandRisk(level: .caution, reason: .writesFiles)
        case "rebase", "filter-branch", "filter-repo", "replace":
            return CommandRisk(level: .high, reason: .rewritesHistory)
        case "commit":
            return flags.contains("--amend") ? CommandRisk(level: .caution, reason: .rewritesHistory) : CommandRisk(level: .caution, reason: .writesFiles)
        case "fetch", "pull", "clone", "submodule":
            return CommandRisk(level: .caution, reason: .network)
        default:
            return CommandRisk(level: .caution, reason: .writesFiles)
        }
    }

    static func assessPackageManager(_ name: String, _ args: [String]) -> CommandRisk {
        let sub = args.first(where: { !$0.hasPrefix("-") }) ?? ""
        let installs: Set<String> = ["install", "i", "add", "ci", "update", "upgrade", "up", "get", "reinstall", "sync", "tap"]
        let publishes: Set<String> = ["publish", "push", "release", "deploy", "unpublish", "yank"]
        let reads: Set<String> = ["list", "ls", "outdated", "view", "info", "show", "search", "why", "audit", "doctor",
                                  "--version", "version", "config", "env", "help", "freeze", "tree", "deps"]
        if publishes.contains(sub) { return CommandRisk(level: .high, reason: .publishes) }
        if ["uninstall", "remove", "rm", "un", "purge", "autoremove", "cleanup", "prune"].contains(sub) {
            return CommandRisk(level: .caution, reason: .deletes)
        }
        if installs.contains(sub) { return CommandRisk(level: .caution, reason: .installs) }
        if reads.contains(sub) || args.isEmpty { return .safe }
        // npm run, cargo build, swift test, go run…
        return CommandRisk(level: .caution, reason: .runsCode)
    }

    // MARK: Line-wide checks

    private static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return false }
        return word[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Keys, tokens, keychains, shell and launch setup.
    static func sensitivePath(in line: String) -> Bool {
        let l = line.lowercased()
        let needles = ["/.ssh", "~/.ssh", "id_rsa", "id_ed25519", "id_ecdsa", ".aws/credentials", "/.gnupg",
                       "library/keychains", ".netrc", ".npmrc", ".pypirc", ".docker/config.json", ".kube/config",
                       ".git-credentials", "/etc/sudoers", "/etc/hosts", "/etc/passwd", "/etc/shadow",
                       "launchagents", "launchdaemons", ".zshrc", ".bashrc", ".bash_profile", ".zprofile",
                       ".profile", ".claude/settings.json", ".env"]
        for needle in needles where l.contains(needle) {
            // ".env" alone also matches ".envrc", "environment", ".env.example": only a file named .env*
            // that is not an example.
            if needle == ".env" {
                let words = l.split(whereSeparator: { " \t'\"/=<>|;&".contains($0) })
                if words.contains(where: { $0 == ".env" || ($0.hasPrefix(".env.") && !$0.hasSuffix("example") && !$0.hasSuffix("sample")) }) {
                    return true
                }
                continue
            }
            return true
        }
        return false
    }

    private static func writesThroughRedirection(_ parsed: AgyPermissionRules.Parsed) -> Bool {
        for segment in parsed.segments {
            for (i, word) in segment.enumerated() {
                guard word.hasPrefix(">") || word.hasPrefix("1>") || word.hasPrefix(">>") || word.hasPrefix("&>") else { continue }
                // 2>&1, >&2: another stream, not a file.
                if word.hasSuffix("&1") || word.hasSuffix("&2") { continue }
                let target = word.trimmingCharacters(in: CharacterSet(charactersIn: "1&>"))
                let file = target.isEmpty ? (i + 1 < segment.count ? segment[i + 1] : "") : target
                if file == "/dev/null" || file == "/dev/stderr" || file == "/dev/stdout" { continue }
                return true
            }
        }
        return false
    }

    private static func pipesDownloadToShell(_ parsed: AgyPermissionRules.Parsed) -> Bool {
        let fetchers: Set<String> = ["curl", "wget", "http", "fetch"]
        let shells: Set<String> = ["sh", "bash", "zsh", "fish", "python", "python3", "perl", "ruby", "node", "osascript", "sudo", "eval", "source"]
        var fetched = false
        for segment in parsed.segments {
            let name = (segment.first.map { ($0 as NSString).lastPathComponent }) ?? ""
            if fetchers.contains(name) { fetched = true; continue }
            if fetched && shells.contains(name) { return true }
            if name == "base64" && segment.contains(where: { $0 == "-d" || $0 == "--decode" || $0 == "-D" }) { fetched = true }
        }
        return false
    }
}
