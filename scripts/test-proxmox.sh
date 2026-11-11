#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-pve.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ProxmoxAPI.swift tests/ProxmoxTests.swift -o "$TEST_DIR/pve-tests"
"$TEST_DIR/pve-tests"
