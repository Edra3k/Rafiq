import Foundation

@main
enum GitStatusTests {
    nonisolated(unsafe) static var failures = 0
    static func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    static func main() {
        let a = GitSummary.parse("## main...origin/main [ahead 3]\n M a.swift\n?? b.swift\n")
        check(a == GitSummary(branch: "main", ahead: 3, behind: 0, changed: 2), "ahead + changes: \(String(describing: a))")
        let b = GitSummary.parse("## feature/x...origin/feature/x [ahead 1, behind 2]\n")
        check(b == GitSummary(branch: "feature/x", ahead: 1, behind: 2, changed: 0), "ahead and behind")
        let c = GitSummary.parse("## main\n")
        check(c == GitSummary(branch: "main", ahead: 0, behind: 0, changed: 0), "no upstream")
        let d = GitSummary.parse("## No commits yet on main\n?? x\n")
        check(d?.branch == "main" && d?.changed == 1, "fresh repository")
        let e = GitSummary.parse("## HEAD (no branch)\n")
        check(e?.branch == "HEAD", "detached")
        check(GitSummary.parse("") == nil, "not a repository")
        check(GitSummary.parse("fatal: not a git repository") == nil, "git error")
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("GitSummary: all tests passed")
    }
}
