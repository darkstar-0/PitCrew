#!/bin/sh
# Installs Pit Crew's hook scripts and registers them with Claude Code.
# Safe to re-run after pulling updates.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$HOME/.pitcrew"
for f in hook.sh permission.sh; do
  cp "$ROOT/hooks/$f" "$HOME/.pitcrew/$f"
  chmod +x "$HOME/.pitcrew/$f"
done
echo "✓ Installed hook scripts to ~/.pitcrew/"

if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/hooks/merge_settings.py"
else
  echo "python3 not found. Paste hooks/settings-snippet.json into ~/.claude/settings.json by hand."
fi

echo "✓ Done. New Claude Code sessions will report to Pit Crew."
