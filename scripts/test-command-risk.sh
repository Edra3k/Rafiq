#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-risk.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AgyPermissionRules.swift NotchBuddy/Sources/App/CommandRisk.swift \
  tests/CommandRiskTests.swift -o "$TEST_DIR/risk-tests"
"$TEST_DIR/risk-tests"
