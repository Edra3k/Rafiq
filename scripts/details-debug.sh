#!/usr/bin/env bash
# Debug builds only: opens the island on Details for a pill, as a click on the session card would,
# or makes Rafiq say something with the voice chosen in Settings.
#   scripts/details-debug.sh                       the Claude app's pill (agent_claude-desktop)
#   scripts/details-debug.sh integration_claude    VS Code and terminal sessions
#   scripts/details-debug.sh "say:Bonjour Ahmed"   Rafiq says it
#   scripts/details-debug.sh "ask:Où en est Claude ?"   the same path as Siri, answer said and logged
#   scripts/details-debug.sh "page:mac"; scripts/details-debug.sh "view:tools"   the Tools tab on a page
#   scripts/details-debug.sh "pills:7:6"   7 test pills, the 7th working ("pills:0" removes them); "demo" toggles demo mode
set -euo pipefail
PILL="${1:-agent_claude-desktop}" /usr/bin/osascript -l JavaScript -e '
ObjC.import("Foundation");
const pill = $.NSProcessInfo.processInfo.environment.objectForKey("PILL").js;
$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("com.edra3k.rafiq.debug.details", pill, $(), true);
' >/dev/null
