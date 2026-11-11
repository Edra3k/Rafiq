#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-git.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# Only the pure parser: the store needs the app.
sed -n '1,/^@MainActor/p' NotchBuddy/Sources/App/GitStatusStore.swift | sed '$d' > "$TEST_DIR/GitParse.swift"
swiftc "$TEST_DIR/GitParse.swift" tests/GitStatusTests.swift -o "$TEST_DIR/git-tests"
"$TEST_DIR/git-tests"
