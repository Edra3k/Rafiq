import Foundation

@main
enum OSVWatchTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() {
        // package-lock v3
        let v3 = """
        {"lockfileVersion": 3, "packages": {
          "": {"name": "app"},
          "node_modules/next": {"version": "14.2.3"},
          "node_modules/@scope/pkg": {"version": "1.0.0"},
          "node_modules/a/node_modules/b": {"version": "2.0.0"},
          "node_modules/local": {"link": true, "version": "0.0.1"}
        }}
        """.data(using: .utf8)!
        let npm = Set(LockfileParser.npm(v3).map { "\($0.name)@\($0.version)" })
        check(npm == ["next@14.2.3", "@scope/pkg@1.0.0", "b@2.0.0"], "npm v3: \(npm)")

        // package-lock v1
        let v1 = """
        {"lockfileVersion": 1, "dependencies": {
          "lodash": {"version": "4.17.15", "dependencies": {"inner": {"version": "1.2.3"}}},
          "gitdep": {"version": "github:user/repo#abc"}
        }}
        """.data(using: .utf8)!
        let npm1 = Set(LockfileParser.npm(v1).map { "\($0.name)@\($0.version)" })
        check(npm1 == ["lodash@4.17.15", "inner@1.2.3"], "npm v1: \(npm1)")

        // Cargo.lock: registry packages only
        let cargo = """
        [[package]]
        name = "serde"
        version = "1.0.190"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "my-app"
        version = "0.1.0"
        """
        let c = LockfileParser.cargo(cargo)
        check(c == [LockedPackage(ecosystem: "crates.io", name: "serde", version: "1.0.190")], "cargo: \(c)")

        // requirements.txt
        let req = """
        # comment
        Django==4.2.1
        requests[security]==2.31.0  # pinned
        flask>=2.0
        numpy==1.26.0 ; python_version >= "3.9"
        -r other.txt
        """
        let p = Set(LockfileParser.pip(req).map { "\($0.name)@\($0.version)" })
        check(p == ["django@4.2.1", "requests@2.31.0", "numpy@1.26.0"], "pip: \(p)")

        // OSV responses
        let batch = #"{"results":[{"vulns":[{"id":"GHSA-aaaa"},{"id":"GHSA-bbbb"}]},{}]}"#.data(using: .utf8)!
        check(OSVResponse.batchIds(batch, count: 2) == [["GHSA-aaaa", "GHSA-bbbb"], []], "batch ids")
        check(OSVResponse.batchIds(Data(), count: 2) == [[], []], "bad batch")

        let vuln = """
        {"id":"GHSA-aaaa","aliases":["CVE-2026-1234"],"summary":"Auth bypass","database_specific":{"severity":"CRITICAL"},
         "affected":[{"package":{"ecosystem":"npm","name":"next"},"ranges":[{"type":"SEMVER","events":[{"introduced":"0"},{"fixed":"14.2.7"}]}]}]}
        """.data(using: .utf8)!
        let pkg = LockedPackage(ecosystem: "npm", name: "next", version: "14.2.3")
        let f = OSVResponse.finding(vuln, package: pkg)
        check(f?.id == "CVE-2026-1234", "CVE alias first")
        check(f?.severity == "CRITICAL" && f?.rank == 4, "severity")
        check(f?.fixed == "14.2.7", "fixed version")
        check(f?.summary == "Auth bypass", "summary")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("OSVWatch: all tests passed")
    }
}
