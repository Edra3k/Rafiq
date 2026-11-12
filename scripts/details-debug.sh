#!/usr/bin/env bash
# Debug builds only: opens the island on Details for a pill, as a click on the session card would.
#   scripts/details-debug.sh                       the Claude app's pill (agent_claude-desktop)
#   scripts/details-debug.sh integration_claude    VS Code and terminal sessions
set -euo pipefail
PILL="${1:-agent_claude-desktop}" /usr/bin/osascript -l JavaScript -e '
ObjC.import("Foundation");
const pill = $.NSProcessInfo.processInfo.environment.objectForKey("PILL").js;
$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("com.edra3k.rafiq.debug.details", pill, $(), true);
' >/dev/null
