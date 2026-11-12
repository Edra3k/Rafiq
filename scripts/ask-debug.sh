#!/usr/bin/env bash
# Debug builds of Rafiq only: hands a task to "Ask…" as if typed in the notch card.
# Usage: scripts/ask-debug.sh "check the disk" [auto|hermes|claude|answer]
set -euo pipefail
ASK_TEXT="${1:?task}" ASK_TARGET="${2:-auto}" osascript -l JavaScript -e '
ObjC.import("Foundation");
var env = $.NSProcessInfo.processInfo.environment;
$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
  "com.edra3k.rafiq.debug.ask", env.objectForKey("ASK_TEXT"), $({target: ObjC.unwrap(env.objectForKey("ASK_TARGET"))}), true);
'
