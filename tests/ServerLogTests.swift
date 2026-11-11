import Foundation

@main
enum ServerLogTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() {
        let a = ServerLog.login("Accepted publickey for root from 185.220.101.42 port 51234 ssh2: ED25519 SHA256:AbCd")
        check(a == SSHLogin(user: "root", ip: "185.220.101.42", method: "publickey", key: "ED25519 SHA256:AbCd"), "publickey: \(String(describing: a))")
        let b = ServerLog.login("sshd[812]: Accepted password for ahmed from 10.8.0.3 port 40022 ssh2")
        check(b?.user == "ahmed" && b?.ip == "10.8.0.3" && b?.method == "password" && b?.key == "", "password")
        check(ServerLog.login("Connection closed by 1.2.3.4 port 22") == nil, "not a login")
        let f = ServerLog.failure("Failed password for invalid user admin from 45.9.8.7 port 3322 ssh2")
        check(f?.user == "admin" && f?.ip == "45.9.8.7", "failure")

        for ip in ["10.0.0.5", "192.168.1.20", "172.20.1.1", "100.101.102.103", "127.0.0.1", "fd7a:115c::1", "::1"] {
            check(ServerLog.isPrivate(ip), "private \(ip)")
        }
        for ip in ["185.220.101.42", "172.32.0.1", "100.128.0.1", "8.8.8.8", "2a01:e0a::1"] {
            check(!ServerLog.isPrivate(ip), "public \(ip)")
        }

        let ss = """
        LISTEN 0      4096         0.0.0.0:22        0.0.0.0:*
        LISTEN 0      4096       127.0.0.1:11434     0.0.0.0:*
        LISTEN 0      4096         0.0.0.0:11434     0.0.0.0:*
        LISTEN 0      4096            [::]:8006         [::]:*
        LISTEN 0      128            [::1]:25            [::]:*
        """
        let l = ServerLog.listening(ss)
        check(l.count == 5, "listening \(l)")
        check(ServerLog.exposed(l) == ["0.0.0.0:22", "0.0.0.0:11434", "[::]:8006"], "exposed \(ServerLog.exposed(l))")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("ServerLog: all tests passed")
    }
}
