#!/bin/sh
# Simulates a PermissionRequest the way Claude Code sends it, and prints
# what the crew answers. Run with Pit Crew open.

echo "Sent a fake permission request. Click Allow, Deny or In VS Code in Pit Crew…"
RESULT=$(curl -s --max-time 120 -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary '{"session_id":"demo-perm","hook_event_name":"PermissionRequest","cwd":"/Users/jack/code/idea-scout","tool_name":"Bash","tool_input":{"command":"npx hyperframes render . -o out.mp4","description":"Render the video"}}' \
  http://127.0.0.1:7777/permission) || { echo "Pit Crew isn't running (start it with: swift run)"; exit 1; }

if [ -z "$RESULT" ]; then
  echo "Pit Crew answered: (no decision) → Claude Code would show its normal terminal prompt"
else
  echo "Pit Crew answered: $RESULT"
fi

# Clean up the fake card.
curl -s -H 'Expect:' --data-binary '{"session_id":"demo-perm","hook_event_name":"SessionEnd"}' \
  http://127.0.0.1:7777/event >/dev/null
