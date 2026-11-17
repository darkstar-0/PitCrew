"""Registers Pit Crew's hooks in ~/.claude/settings.json (backs it up first).

    python3 merge_settings.py           add the hooks (safe to run repeatedly)
    python3 merge_settings.py --remove  take them out again

Your other settings and hooks are left untouched.
"""
import json
import os
import shutil
import sys
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


def load():
    if not os.path.exists(PATH):
        return {}
    backup = PATH + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy(PATH, backup)
    print("Backed up existing settings to", backup)
    with open(PATH) as f:
        return json.load(f)


def save(settings):
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    with open(PATH, "w") as f:
        json.dump(settings, f, indent=2)


def remove_matching(hooks, needle):
    """Drops every hook whose command contains `needle`; returns how many."""
    removed = 0
    for event in list(hooks):
        groups = hooks[event]
        for g in groups:
            before = len(g.get("hooks", []))
            g["hooks"] = [h for h in g.get("hooks", []) if needle not in h.get("command", "")]
            removed += before - len(g["hooks"])
        hooks[event] = [g for g in groups if g.get("hooks")]
        if not hooks[event]:
            del hooks[event]
    return removed


def main():
    settings = load()
    hooks = settings.setdefault("hooks", {})

    if "--remove" in sys.argv:
        n = remove_matching(hooks, "/.pitcrew/")
        if not hooks:
            del settings["hooks"]
        save(settings)
        print(f"Removed {n} Pit Crew hook(s) from {PATH}")
        return

    # Hooks from the project's original name (Agent Huddle) would double-send events.
    old = remove_matching(hooks, "/." + "huddle/")
    if old:
        print(f"Removed {old} hook(s) left over from Agent Huddle")

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

    save(settings)
    print("Added hooks for:", ", ".join(added) if added else "nothing new (already installed)")


if __name__ == "__main__":
    main()
