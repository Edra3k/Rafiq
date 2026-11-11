#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-secrets.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/SecretScanner.swift tests/SecretScannerTests.swift -o "$TEST_DIR/secret-tests"
"$TEST_DIR/secret-tests"
