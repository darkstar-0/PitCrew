"""Adds the Pit Crew hooks to ~/.claude/settings.json (backs it up first).

Safe to run more than once: skips hooks that are already registered.
"""
import json
import os
import shutil
import time

PATH = os.path.expanduser("~/.claude/settings.json")
EVENT_CMD = "$HOME/.pitcrew/hook.sh"
PERMISSION_CMD = "$HOME/.pitcrew/permission.sh"

# event -> (matcher, command, timeout seconds)
HOOKS = {
    "SessionStart": (None, EVENT_CMD, None),
    "UserPromptSubmit": (None, EVENT_CMD, None),
    "PreToolUse": ("*", EVENT_CMD, None),
    "PostToolUse": ("*", EVENT_CMD, None),
    "Notification": (None, EVENT_CMD, None),
    "Stop": (None, EVENT_CMD, None),
    "SessionEnd": (None, EVENT_CMD, None),
    # Waits for you to click Allow/Deny, so it needs a long timeout.
    "PermissionRequest": ("*", PERMISSION_CMD, 600),
}

settings = {}
if os.path.exists(PATH):
    backup = PATH + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy(PATH, backup)
    print("Backed up existing settings to", backup)
    with open(PATH) as f:
        settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Remove hooks left over from the project's old name (Agent Huddle, ~/.huddle/),
# otherwise every event would be sent twice.
OLD_DIR = "/." + "huddle/"
removed = 0
for event in list(hooks):
    groups = hooks[event]
    for g in groups:
        before = len(g.get("hooks", []))
        g["hooks"] = [h for h in g.get("hooks", []) if OLD_DIR not in h.get("command", "")]
        removed += before - len(g["hooks"])
    hooks[event] = [g for g in groups if g.get("hooks")]
    if not hooks[event]:
        del hooks[event]
if removed:
    print(f"Removed {removed} old Agent Huddle hook(s)")

added = []
for event, (matcher, cmd, timeout) in HOOKS.items():
    groups = hooks.setdefault(event, [])
    if any(h.get("command") == cmd for g in groups for h in g.get("hooks", [])):
        continue
    hook = {"type": "command", "command": cmd}
    if timeout:
        hook["timeout"] = timeout
    group = {"hooks": [hook]}
    if matcher:
        group["matcher"] = matcher
    groups.append(group)
    added.append(event)

os.makedirs(os.path.dirname(PATH), exist_ok=True)
with open(PATH, "w") as f:
    json.dump(settings, f, indent=2)
print("Added hooks for:", ", ".join(added) if added else "nothing new (already installed)")
