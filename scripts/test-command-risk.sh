#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-risk.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/AgyPermissionRules.swift NotchBuddy/Sources/CoucouKit/CommandRisk.swift \
  tests/CommandRiskTests.swift -o "$TEST_DIR/risk-tests"
"$TEST_DIR/risk-tests"
