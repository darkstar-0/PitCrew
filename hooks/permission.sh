#!/bin/sh
# Pit Crew PermissionRequest hook.
# Holds the permission prompt open until you click Allow / Deny in Pit Crew,
# then prints Claude Code's decision JSON.
#
# Prints nothing (so Claude Code shows its normal terminal prompt) when:
#   - the app isn't running (curl fails instantly)
#   - the Pit Crew panel is hidden
#   - you click "In VS Code"
#   - nobody answers within ~10 minutes
curl -s --max-time 590 \
  -H 'Content-Type: application/json' -H 'Expect:' \
  --data-binary @- http://127.0.0.1:7777/permission 2>/dev/null
exit 0
