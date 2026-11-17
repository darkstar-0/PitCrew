#!/bin/sh
# Removes Pit Crew: its Claude Code hooks, ~/.pitcrew, and the installed app.
# Your other Claude Code settings are left alone (a backup is made first).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "› Removing hooks from ~/.claude/settings.json"
python3 "$ROOT/hooks/merge_settings.py" --remove

echo "› Quitting Pit Crew"
osascript -e 'quit app "PitCrew"' >/dev/null 2>&1 || true
pkill -x PitCrew >/dev/null 2>&1 || true

for app in "/Applications/PitCrew.app" "$HOME/Applications/PitCrew.app"; do
  if [ -d "$app" ]; then
    rm -rf "$app" && echo "✓ Deleted $app"
  fi
done

rm -rf "$HOME/.pitcrew" && echo "✓ Deleted ~/.pitcrew"
echo "✓ Pit Crew is uninstalled. (If you turned on Launch at Login, macOS drops it once the app is gone.)"
