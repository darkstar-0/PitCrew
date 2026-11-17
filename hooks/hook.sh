#!/bin/sh
# Pit Crew hook: forwards every Claude Code hook event (JSON on stdin)
# to the overlay app. Never slows or breaks Claude Code: 1s timeout,
# output discarded, always exits 0. If the app isn't running, curl fails
# instantly and nothing happens.
#
# -H 'Expect:' stops curl from pausing ~1s on large payloads.
curl -s --max-time 1 \
  -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary @- http://127.0.0.1:7777/event >/dev/null 2>&1
exit 0
