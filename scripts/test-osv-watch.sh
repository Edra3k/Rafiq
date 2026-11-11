#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-osv.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# Only the pure part: the watch itself needs the app (DigestCenter).
sed -n '1,/^\/\/ MARK: - Watch/p' NotchBuddy/Sources/App/OSVWatch.swift > "$TEST_DIR/OSVParse.swift"
swiftc "$TEST_DIR/OSVParse.swift" tests/OSVWatchTests.swift -o "$TEST_DIR/osv-tests"
"$TEST_DIR/osv-tests"
