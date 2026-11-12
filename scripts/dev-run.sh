#!/usr/bin/env bash
# Builds the Debug Rafiq, signs it with your Apple Development certificate when you have one
# (a free Apple Account in Xcode is enough), and relaunches it. Signed this way, macOS knows
# it is the same app from one build to the next and keeps its permissions (microphone,
# Calendars, Screen Recording…). dev-install.sh does the same for the iCloud build, which
# needs a paid team.
#
#   ./scripts/dev-run.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${REPO_ROOT}/NotchBuddy/build/DD/Build/Products/Debug/Rafiq.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "${REPO_ROOT}/NotchBuddy"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build/DD build CODE_SIGNING_ALLOWED=NO -quiet

IDENTITY=$(security find-identity -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
if [ -n "${IDENTITY}" ]; then
  codesign --force --deep --options runtime --timestamp=none \
    --entitlements Resources/Rafiq.entitlements --sign "${IDENTITY}" "${APP}"
  echo "Signed with ${IDENTITY%% (*}"
else
  echo "No Apple Development certificate: ad-hoc build (macOS will ask for permissions again after each build)."
fi

pkill -f "${APP}/Contents/MacOS/Rafiq" 2>/dev/null || true
sleep 1
open "${APP}"
echo "Rafiq relaunched."
