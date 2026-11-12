#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rafiq-ask.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/AgentAsk.swift tests/AgentAskTests.swift -o "$TEST_DIR/ask-tests"
"$TEST_DIR/ask-tests"
