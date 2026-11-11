#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-prayer-times.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/PrayerTimesEngine.swift \
    tests/PrayerTimesTests.swift -o "$TEST_DIR/prayer-times-tests"
"$TEST_DIR/prayer-times-tests"
