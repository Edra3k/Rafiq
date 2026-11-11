#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-net.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir "$TEST_DIR/repo"
swiftc NotchBuddy/Sources/App/SafetyNet.swift tests/SafetyNetTests.swift -o "$TEST_DIR/net-tests"
"$TEST_DIR/net-tests" "$TEST_DIR/repo"
