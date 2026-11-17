#!/bin/sh
# Simulates Claude asking a question (AskUserQuestion) and prints what the
# crew sends back. Run with Pit Crew open.

echo "Sent a fake question. Pick an option and click Send in Pit Crew…"
RESULT=$(curl -s --max-time 120 -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary '{"session_id":"demo-q","hook_event_name":"PermissionRequest","cwd":"/Users/jack/code/breakdown-reel","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which hook should I use?","header":"Hook","multiSelect":false,"options":[{"label":"The pain one","description":"Open on the frustration"},{"label":"The number one","description":"Lead with a stat"},{"label":"The question one","description":"Ask the viewer something"}]}]}}' \
  http://127.0.0.1:7777/permission) || { echo "Pit Crew isn't running (start it with: swift run)"; exit 1; }

if [ -z "$RESULT" ]; then
  echo "Pit Crew answered: (no decision) → Claude Code would show its normal terminal prompt"
else
  echo "Pit Crew answered: $RESULT"
fi

curl -s -H 'Expect:' --data-binary '{"session_id":"demo-q","hook_event_name":"SessionEnd"}' \
  http://127.0.0.1:7777/event >/dev/null
