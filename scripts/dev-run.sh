#!/usr/bin/env bash
# Builds the Debug Rafiq, signs it with your Apple Development certificate when you have one
# (a free Apple Account in Xcode is enough), installs it as the only Rafiq in /Applications and
# launches it. Signed this way and at one place, macOS knows it is the same app from one build
# to the next and keeps its permissions (microphone, Calendars, Screen Recording…).
# dev-install.sh does the same for the iCloud build, which needs a paid team.
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

# One Rafiq only: quit every copy, put this one in /Applications (never over the App Store
# Rafiq, which has another bundle identifier), launch it from there.
TARGET="/Applications/Rafiq.app"
if [ -d "${TARGET}" ]; then
  EXISTING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${TARGET}/Contents/Info.plist" 2>/dev/null || echo "")
  if [ "${EXISTING}" != "com.edra3k.rafiq" ]; then TARGET="${HOME}/Applications/Rafiq.app"; mkdir -p "${HOME}/Applications"; fi
fi
osascript -e 'tell application id "com.edra3k.rafiq" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -f "Rafiq.app/Contents/MacOS/Rafiq" 2>/dev/null || true
sleep 1
rm -rf "${TARGET}"
ditto "${APP}" "${TARGET}"
open "${TARGET}"
echo "Rafiq installed in ${TARGET} and launched."
