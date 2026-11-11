#if !APPSTORE
import AppKit
import Foundation

// MARK: - ServerLink: the Mac's link to the home server, over SSH
// Everything goes through the user's own SSH setup (~/.ssh/config, keys, the WireGuard or
// Tailscale address): BatchMode, so ssh never asks anything, and nothing listens on a port.
// - The tunnel: `ssh -R` forwards a socket on the server to Rafiq's nb.sock on the Mac
//   (docs/REMOTE.md), kept up with a backoff. Hermes (CLI or gateway) and Claude Code on
//   the server reach the notch through it: sessions, steps, approvals.
// - The watch: sshd's log, followed live, and the listening ports, every 10 minutes. An
//   SSH login from an address that is not private or known, or a port newly open to the
//   network, brings a red card.
// - The install: copies the relay and the Hermes plugin to the server (after a click and
//   a confirmation), with a dated backup of Hermes's config.yaml before enabling it.

@MainActor
final class ServerLink: ObservableObject {
    static let shared = ServerLink()

    static let hostKey = "serverSSHHost"
    static let tunnelKey = "serverTunnel"
    static let watchKey = "serverWatch"
    private static let knownIPsKey = "serverKnownIPs"

    enum LinkState: Equatable {
        case off, connecting, up, failed(String)
    }

    @Published private(set) var tunnel: LinkState = .off
    @Published private(set) var watch: LinkState = .off
    @Published private(set) var installLog: [String] = []
    @Published private(set) var installing = false

    static var host: String { UserDefaults.standard.string(forKey: hostKey)?.trimmingCharacters(in: .whitespaces) ?? "" }
    static var tunnelEnabled: Bool { UserDefaults.standard.bool(forKey: tunnelKey) }
    static var watchEnabled: Bool { UserDefaults.standard.object(forKey: watchKey) as? Bool ?? true }

    private var tunnelProcess: Process?
    private var watchProcess: Process?
    private var portsTimer: Timer?
    private var tunnelRetry = 0
    private var watchRetry = 0
    private var lineBuffer = ""
    private var failedCount: [String: Int] = [:]

    // MARK: Settings

    func applySettings() {
        let host = Self.host
        if Self.tunnelEnabled, !host.isEmpty { if tunnelProcess == nil { startTunnel() } } else { stopTunnel() }
        if Self.watchEnabled, Self.tunnelEnabled, !host.isEmpty {
            if watchProcess == nil { startWatch() }
            if portsTimer == nil { startPorts() }
        } else {
            stopWatch()
        }
    }

    // MARK: SSH helpers

    nonisolated static func sshArgs(_ host: String, _ extra: [String] = []) -> [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
         "-o", "ServerAliveCountMax=3"] + extra + [host]
    }

    /// Runs one command on the server; returns its status and output.
    nonisolated static func run(_ host: String, _ command: String, input: Data? = nil) async -> (Int32, String) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = sshArgs(host) + [command]
            let out = Pipe(), err = Pipe(), inp = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = inp
            p.terminationHandler = { proc in
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: o.isEmpty ? e : o, encoding: .utf8) ?? ""
                cont.resume(returning: (proc.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try p.run()
                if let input { inp.fileHandleForWriting.write(input) }
                try? inp.fileHandleForWriting.close()
            } catch {
                cont.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    // MARK: Tunnel

    private func startTunnel() {
        let host = Self.host
        tunnel = .connecting
        Task {
            // Make the folder, remove a socket left by an earlier connection, print the path.
            let (status, path) = await Self.run(host, #"d="$HOME/Library/Application Support/NotchBuddy"; mkdir -p "$d" && chmod 700 "$d" && rm -f "$d/nb.sock" && printf %s "$d/nb.sock""#)
            guard Self.tunnelEnabled, Self.host == host else { return }
            guard status == 0, !path.isEmpty else {
                tunnel = .failed(path.isEmpty ? "ssh \(status)" : String(path.prefix(120)))
                scheduleTunnelRetry()
                return
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = Self.sshArgs(host, ["-N", "-o", "ExitOnForwardFailure=yes",
                                              "-R", "\(path):\(HookServer.socketPath)"])
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            p.terminationHandler = { proc in
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    let link = ServerLink.shared
                    link.tunnelProcess = nil
                    guard ServerLink.tunnelEnabled else { link.tunnel = .off; return }
                    link.tunnel = .failed(msg.isEmpty ? "ssh \(proc.terminationStatus)" : String(msg.prefix(120)))
                    link.scheduleTunnelRetry()
                }
            }
            do {
                try p.run()
                tunnelProcess = p
                // ExitOnForwardFailure ends ssh within a few seconds if the forward fails.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if tunnelProcess === p, p.isRunning { tunnel = .up; tunnelRetry = 0 }
            } catch {
                tunnel = .failed(error.localizedDescription)
                scheduleTunnelRetry()
            }
        }
    }

    private func scheduleTunnelRetry() {
        tunnelRetry += 1
        let delay = [5.0, 15, 30, 60, 120][min(tunnelRetry - 1, 4)]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let link = ServerLink.shared
                if ServerLink.tunnelEnabled, link.tunnelProcess == nil, !ServerLink.host.isEmpty { link.startTunnel() }
            }
        }
    }

    private func stopTunnel() {
        tunnelProcess?.terminate()
        tunnelProcess = nil
        tunnel = .off
    }

    // MARK: Watch

    private func startWatch() {
        let host = Self.host
        watch = .connecting
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = Self.sshArgs(host) + ["journalctl -f -n 0 -o cat _COMM=sshd 2>/dev/null || sudo -n tail -F -n 0 /var/log/auth.log 2>/dev/null || tail -F -n 0 /var/log/auth.log"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in ServerLink.shared.receive(text) }
        }
        p.terminationHandler = { _ in
            Task { @MainActor in
                let link = ServerLink.shared
                link.watchProcess = nil
                guard ServerLink.watchEnabled, ServerLink.tunnelEnabled else { link.watch = .off; return }
                link.watch = .failed("ssh")
                link.watchRetry += 1
                let delay = [10.0, 30, 60, 300][min(link.watchRetry - 1, 3)]
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated {
                        if ServerLink.shared.watchProcess == nil, ServerLink.watchEnabled { ServerLink.shared.startWatch() }
                    }
                }
            }
        }
        do {
            try p.run()
            watchProcess = p
            watch = .up
            watchRetry = 0
        } catch {
            watch = .failed(error.localizedDescription)
        }
    }

    private func stopWatch() {
        watchProcess?.terminate()
        watchProcess = nil
        portsTimer?.invalidate()
        portsTimer = nil
        watch = .off
    }

    private func receive(_ chunk: String) {
        lineBuffer += chunk
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
            handle(line)
        }
        if lineBuffer.count > 8000 { lineBuffer = "" }
    }

    var knownIPs: Set<String> { Set(UserDefaults.standard.stringArray(forKey: Self.knownIPsKey) ?? []) }

    func trust(_ ip: String) {
        var s = knownIPs
        s.insert(ip)
        UserDefaults.standard.set(Array(s), forKey: Self.knownIPsKey)
    }

    private func handle(_ line: String) {
        if let login = ServerLog.login(line) {
            guard !ServerLog.isPrivate(login.ip), !knownIPs.contains(login.ip) else { return }
            DigestCenter.shared.show(Digest(
                kind: .server,
                title: String(format: String(localized: "server.ssh.title %@", defaultValue: "Unusual SSH login · %@"), Self.host),
                subtitle: String(format: String(localized: "server.ssh.from %@ %@ %@", defaultValue: "%@ from %@ (%@)"),
                                 login.user, login.ip, login.method),
                lines: [login.key.isEmpty ? String(localized: "server.ssh.check", defaultValue: "If it is not you, cut the session and change the keys.") : login.key],
                code: "\(login.user)@\(login.ip)",
                primary: (String(localized: "server.ssh.mine", defaultValue: "It's me"), .trustIP(login.ip))
            ))
            SoundEngine.shared.play("error")
        } else if let fail = ServerLog.failure(line), !ServerLog.isPrivate(fail.ip) {
            failedCount[fail.ip, default: 0] += 1
            // Twenty failures from one address: someone is guessing.
            if failedCount[fail.ip] == 20 {
                DigestCenter.shared.show(Digest(
                    kind: .server,
                    title: String(format: String(localized: "server.brute.title %@", defaultValue: "Someone is guessing passwords on %@"), Self.host),
                    subtitle: String(format: String(localized: "server.brute.from %@", defaultValue: "20 failed SSH logins from %@"), fail.ip),
                    lines: [String(localized: "server.brute.advice", defaultValue: "Keys only (PasswordAuthentication no), and fail2ban or CrowdSec, stop this.")]
                ))
            }
        }
    }

    // MARK: Ports

    private func startPorts() {
        checkPorts()
        let t = Timer(timeInterval: 600, repeats: true) { _ in
            MainActor.assumeIsolated { ServerLink.shared.checkPorts() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        portsTimer = t
    }

    private func checkPorts() {
        let host = Self.host
        guard !host.isEmpty else { return }
        Task {
            let (status, out) = await Self.run(host, "ss -tlnH")
            guard status == 0 else { return }
            let exposed = ServerLog.exposed(ServerLog.listening(out))
            let key = "serverPorts-\(host)"
            let before = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            UserDefaults.standard.set(Array(exposed), forKey: key)
            // The first look is the baseline: nothing to compare yet.
            guard UserDefaults.standard.object(forKey: key + "-seen") != nil else {
                UserDefaults.standard.set(true, forKey: key + "-seen")
                return
            }
            let new = exposed.subtracting(before).sorted()
            guard !new.isEmpty else { return }
            DigestCenter.shared.show(Digest(
                kind: .server,
                title: String(format: String(localized: "server.ports.title %@", defaultValue: "New port open on %@"), host),
                subtitle: String(localized: "server.ports.subtitle", defaultValue: "Reachable from other machines, not only from the server itself."),
                lines: new,
                code: new.joined(separator: "  ")
            ))
        }
    }

    // MARK: Install on the server

    /// Copies the relay and the Hermes plugin, enables the plugin in Hermes's config.yaml
    /// (dated backup first). Asked from Settings, after a confirmation.
    func installOnServer() {
        let host = Self.host
        guard !host.isEmpty, !installing else { return }
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "server.install.title %@", defaultValue: "Install Rafiq's relay on %@?"), host)
        alert.informativeText = String(localized: "server.install.body", defaultValue: "Rafiq copies its relay to ~/.coucou and its Hermes plugin to ~/.hermes/plugins/coucou on the server, then adds coucou to the plugins Hermes enables, after saving a dated copy of ~/.hermes/config.yaml. Nothing else changes.")
        alert.addButton(withTitle: String(localized: "server.install.confirm", defaultValue: "Install"))
        alert.addButton(withTitle: String(localized: "net.restore.cancel", defaultValue: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installing = true
        installLog = []
        Task {
            defer { installing = false }
            @MainActor func step(_ s: String) { ServerLink.shared.installLog.append(s) }
            let support = HookServer.supportDir
            guard let hook = try? Data(contentsOf: support.appendingPathComponent("nb-hook")),
                  let hookPy = try? Data(contentsOf: support.appendingPathComponent("nb-hook.py")) else {
                step("✗ " + String(localized: "server.install.no-relay", defaultValue: "The relay is not on this Mac yet: install the Claude Code hooks once."))
                return
            }
            var (s, o) = await Self.run(host, "mkdir -p ~/.coucou && chmod 700 ~/.coucou && cat > ~/.coucou/nb-hook && chmod 755 ~/.coucou/nb-hook", input: hook)
            guard s == 0 else { step("✗ nb-hook: \(o)"); return }
            (s, o) = await Self.run(host, "cat > ~/.coucou/nb-hook.py && chmod 755 ~/.coucou/nb-hook.py", input: hookPy)
            guard s == 0 else { step("✗ nb-hook.py: \(o)"); return }
            step("✓ ~/.coucou/nb-hook")
            let plugin = HookServer.hermesPluginSource(hookExpression: "Path(os.path.expanduser('~/.coucou/nb-hook'))")
            (s, o) = await Self.run(host, "mkdir -p ~/.hermes/plugins/coucou && cat > ~/.hermes/plugins/coucou/__init__.py", input: Data(plugin.utf8))
            guard s == 0 else { step("✗ plugin: \(o)"); return }
            (s, o) = await Self.run(host, "cat > ~/.hermes/plugins/coucou/plugin.yaml", input: Data(HookServer.hermesPluginYaml.utf8))
            guard s == 0 else { step("✗ plugin.yaml: \(o)"); return }
            step("✓ ~/.hermes/plugins/coucou")
            let (cs, config) = await Self.run(host, "cat ~/.hermes/config.yaml 2>/dev/null || true")
            guard cs == 0 else { step("✗ config.yaml"); return }
            guard let merged = HookServer.mergedHermesConfig(config, enableApprovals: true) else {
                step("✗ " + String(localized: "server.install.config-manual", defaultValue: "config.yaml has a layout Rafiq does not edit: add coucou under plugins → enabled yourself."))
                return
            }
            if merged != config {
                let stamp = Int(Date().timeIntervalSince1970)
                (s, o) = await Self.run(host, "[ -f ~/.hermes/config.yaml ] && cp ~/.hermes/config.yaml ~/.hermes/config.yaml.rafiq-\(stamp).bak; cat > ~/.hermes/config.yaml", input: Data(merged.utf8))
                guard s == 0 else { step("✗ config.yaml: \(o)"); return }
                step("✓ ~/.hermes/config.yaml (" + String(localized: "server.install.backup", defaultValue: "copy kept") + ")")
            } else {
                step("✓ ~/.hermes/config.yaml")
            }
            step(String(localized: "server.install.done", defaultValue: "Done. Restart Hermes on the server, and keep the tunnel on."))
        }
    }
}

#endif
