#!/usr/bin/env bash
# Installs Rafiq (iPhone app, its widgets and the Apple Watch app) on your own iPhone with a
# free Apple Account: no paid developer program, no TestFlight.
#
#   ./scripts/install-iphone-free.sh            the first iPhone connected
#   ./scripts/install-iphone-free.sh <udid>     a given iPhone
#   TEAM=ABCDE12345 ./scripts/install-iphone-free.sh
#
# Before: Xcode → Settings → Accounts → + → your Apple Account (it creates your "Personal
# Team"); plug the iPhone in with a cable, unlock it, tap Trust; on the iPhone, Settings →
# Privacy & Security → Developer Mode → on (it restarts).
#
# What a free account cannot do: iCloud and push. This build has no link with the Mac
# (PERSONAL_TEAM in PhoneLink.swift), and the app stops opening after 7 days: run this again.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$REPO_ROOT/NotchBuddy/build/DDPersonalDevice"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

die() { echo "error: $*" >&2; exit 1; }

# ── The Personal Team ─────────────────────────────────────────────────────────
if [ -z "${TEAM:-}" ]; then
  TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | grep -E 'teamID = ' | head -1 | sed -E 's/.*teamID = "?([A-Z0-9]+)"?;.*/\1/' || true)
fi
[ -n "${TEAM:-}" ] || die "no Apple Account in Xcode. Xcode → Settings → Accounts → + → Apple Account, then run this again (or TEAM=<team id> $0)."
echo "Team: $TEAM"

# ── The iPhone ────────────────────────────────────────────────────────────────
DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/iPhone/ && !/simulated/ && /(available|connected)/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }')
fi
[ -n "$DEVICE" ] || die "no iPhone found. Plug it in with a cable, unlock it, tap Trust, turn on Developer Mode; xcrun devicectl list devices shows it."
echo "iPhone: $DEVICE"

# ── Build, signed by Xcode for this team ──────────────────────────────────────
cd "$REPO_ROOT/NotchBuddy"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
# OTHER_SWIFT_FLAGS keeps each target's own compile conditions (WIDGET_EXTENSION…).
# An empty entitlements file: iCloud, push and App Groups are not for free accounts.
xcodebuild \
  -project NotchBuddy.xcodeproj \
  -scheme CoucouPhone \
  -configuration Release \
  -destination "id=$DEVICE" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGN_ENTITLEMENTS=Resources/PersonalTeam.entitlements \
  OTHER_SWIFT_FLAGS="-strict-concurrency=complete -DPERSONAL_TEAM" \
  build | grep -E "error:|warning: .*provision|BUILD (SUCCEEDED|FAILED)" || true

APP="$DD/Build/Products/Release-iphoneos/Rafiq.app"
[ -d "$APP" ] && codesign -v "$APP" 2>/dev/null || die "the build failed, see the errors above"

# ── Install ───────────────────────────────────────────────────────────────────
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo
echo "✓ Rafiq is on your iPhone."
echo "  First launch: Settings → General → VPN & Device Management → your Apple Account → Trust."
echo "  Apple Watch: Watch app on the iPhone → Rafiq → Install."
echo "  It stops opening after 7 days: run this script again."
