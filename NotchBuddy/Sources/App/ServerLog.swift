import Foundation

// MARK: - ServerLog: what the home server's logs and sockets say
// Parses sshd's lines (journalctl or /var/log/auth.log) and `ss -tlnH` (the TCP ports
// listening), for the server watch (ServerLink). An address is "home" when it is private
// (LAN, WireGuard, Tailscale's 100.64/10) or one the user said was theirs.
// Pure Foundation: tested by scripts/test-server-log.sh.

struct SSHLogin: Equatable, Sendable {
    var user: String
    var ip: String
    var method: String      // publickey, password, keyboard-interactive…
    var key: String         // "ED25519 SHA256:…" for a key, "" otherwise
}

enum ServerLog {
    private static let accepted = try! NSRegularExpression(
        pattern: #"Accepted (\S+) for (\S+) from (\S+) port \d+(?: ssh2)?(?::\s*(.+))?$"#)
    private static let failed = try! NSRegularExpression(
        pattern: #"Failed (?:password|publickey|none) for (?:invalid user )?(\S+) from (\S+) port"#)

    static func login(_ line: String) -> SSHLogin? {
        let ns = line as NSString
        guard let m = accepted.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        return SSHLogin(user: g(2), ip: g(3), method: g(1), key: g(4).trimmingCharacters(in: .whitespaces))
    }

    /// A failed attempt: (user, ip).
    static func failure(_ line: String) -> (user: String, ip: String)? {
        let ns = line as NSString
        guard let m = failed.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)))
    }

    /// LAN, WireGuard and Tailscale addresses, loopback, IPv6 local ranges.
    static func isPrivate(_ ip: String) -> Bool {
        let v = ip.lowercased()
        if v == "::1" || v.hasPrefix("fe80:") || v.hasPrefix("fc") || v.hasPrefix("fd") { return true }
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true     // Tailscale (CGNAT range)
        case (169, 254): return true
        default: return false
        }
    }

    /// `ss -tlnH`: the listening TCP endpoints, as "address:port" (IPv6 in brackets kept).
    static func listening(_ output: String) -> Set<String> {
        var out = Set<String>()
        for line in output.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            // State Recv-Q Send-Q Local Peer [Process]
            guard cols.count >= 4, cols[0] == "LISTEN" else { continue }
            out.insert(cols[3].replacingOccurrences(of: "%lo", with: ""))
        }
        return out
    }

    /// Ports reachable from other machines (not bound to loopback only).
    static func exposed(_ endpoints: Set<String>) -> Set<String> {
        endpoints.filter { !$0.hasPrefix("127.") && !$0.hasPrefix("[::1]") && !$0.hasPrefix("::1") }
    }
}
