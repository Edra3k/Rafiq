#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-serverlog.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ServerLog.swift tests/ServerLogTests.swift -o "$TEST_DIR/serverlog-tests"
"$TEST_DIR/serverlog-tests"
