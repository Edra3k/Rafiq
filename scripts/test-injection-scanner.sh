#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-injection.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/InjectionScanner.swift tests/InjectionScannerTests.swift -o "$TEST_DIR/injection-tests"
"$TEST_DIR/injection-tests"
