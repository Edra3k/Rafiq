import Foundation

@main
enum ProxmoxTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() {
        let resources = """
        {"data":[
          {"type":"node","node":"pve","status":"online","cpu":0.38,"mem":11811160064,"maxmem":16642998272,"uptime":1036800},
          {"type":"qemu","vmid":104,"name":"hermes-agent","node":"pve","status":"running","mem":"4294967296","maxmem":8589934592,"cpu":0.12,"tags":"agent"},
          {"type":"qemu","vmid":101,"name":"kali-2026","node":"pve","status":"running","mem":2147483648,"maxmem":4294967296,"cpu":0.02,"tags":"lab;pentest"},
          {"type":"lxc","vmid":200,"name":"jellyfin","node":"pve","status":"stopped","mem":0,"maxmem":1073741824,"cpu":0},
          {"type":"qemu","vmid":9000,"name":"tpl-debian","node":"pve","status":"stopped","template":1},
          {"type":"storage","storage":"local-zfs","node":"pve","disk":920000000000,"maxdisk":1000000000000}
        ]}
        """.data(using: .utf8)!
        let r = PVEParse.resources(resources)
        check(r.nodes.count == 1 && r.nodes[0].online && abs(r.nodes[0].cpu - 0.38) < 0.001, "node")
        check(r.guests.map(\.vmid) == [101, 104, 200], "guests sorted, template left out: \(r.guests.map(\.vmid))")
        check(r.guests[0].isLab && !r.guests[1].isLab, "lab tag")
        check(r.guests[1].mem == 4294967296, "memory given as a string")
        check(r.guests[2].kind == .lxc && !r.guests[2].running, "container stopped")
        check(abs(r.storages[0].share - 0.92) < 0.001, "storage share")
        check(PVEParse.resources(Data("{}".utf8)).guests.isEmpty, "empty answer")

        let snaps = """
        {"data":[{"name":"current","running":1},
                 {"name":"before-ad","snaptime":1800000000,"description":"by hand"},
                 {"name":"rafiq-20271115-140200","snaptime":1800003600}]}
        """.data(using: .utf8)!
        let s = PVEParse.snapshots(snaps)
        check(s.map(\.name) == ["rafiq-20271115-140200", "before-ad"], "snapshots newest first, current left out")
        check(s[0].byRafiq && !s[1].byRafiq, "made by Rafiq")

        let name = PVEParse.snapshotName(at: Date(timeIntervalSince1970: 0))
        check(name.hasPrefix("rafiq-") && name.count == "rafiq-19700101-000000".count, "snapshot name \(name)")
        check(name.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) != nil, "Proxmox-safe name")

        check(PVEParse.authorization(tokenId: " root@pam!rafiq ", secret: "abc") == "PVEAPIToken=root@pam!rafiq=abc", "auth header")
        check(PVEParse.baseURL("pve.home")?.absoluteString == "https://pve.home:8006", "host only")
        check(PVEParse.baseURL("10.8.0.2:8443")?.absoluteString == "https://10.8.0.2:8443", "host and port")
        check(PVEParse.baseURL("http://pve.home:8006/api2/json")?.absoluteString == "https://pve.home:8006", "full URL forced to https")
        check(PVEParse.baseURL("  ") == nil, "empty")
        check(PVEParse.fingerprint(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("Proxmox: all tests passed")
    }
}
