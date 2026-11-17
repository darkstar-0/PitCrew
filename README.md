# Pit Crew (v0)

A floating macOS panel that shows every running Claude Code session:
what it's doing, task progress, and when it needs you.

## How it works

```
Claude Code hooks ──► ~/.pitcrew/hook.sh ──curl──► Pit Crew app (127.0.0.1:7777)
                                                     │
                                       SwiftUI NSPanel, top-right, all Spaces
```

| Hook | What Pit Crew does with it |
|---|---|
| `SessionStart` | Adds a card |
| `UserPromptSubmit` | First prompt becomes the card title |
| `PreToolUse` | Subtitle, e.g. "Editing Views.swift" |
| `PostToolUse` (TodoWrite / TaskCreate / TaskUpdate) | Progress "3/5" + bar |
| `Notification` | Lime border + "needs permission" text + sound |
| `Stop` | Robot closes its eyes, "Done, waiting for you" + sound |
| `SessionEnd` | Removes the card |
| `PermissionRequest` | Shows the command with **Allow / Deny / In VS Code** buttons and holds Claude Code until you click |

### How Allow/Deny works

`permission.sh` POSTs to `/permission` and the app **holds the request open**
until you click. Then it replies with Claude Code's decision JSON:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

It replies with *nothing* (so Claude Code shows its normal terminal prompt) when:
the app isn't running, the panel is hidden, you click **In VS Code**, or nobody
answers within ~10 minutes. Plan approval always goes to the terminal for now;
the card just lights up.

### Questions (AskUserQuestion)

Claude's clarifying questions also arrive through `PermissionRequest`. The card
shows each question with its options. **Send** replies "allow" with
`updatedInput` = the original `questions` plus an `answers` map
(question text → chosen label, multi-select joined with ", "). **Type in VS Code**
falls back to the terminal, e.g. to write a custom answer.

## Run it

Requires macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```sh
cd PitCrew
swift run                 # panel appears top-right, icon in the menu bar
./test-events.sh          # in another terminal: fake agents to check the UI
./test-permission.sh      # fake permission prompt: click a button, see the reply
./test-question.sh        # fake AskUserQuestion: pick an option, see the reply
./install.sh              # register the hooks with Claude Code (safe to re-run)
```

Then start **new** Claude Code sessions (hooks load at session start).

## Debugging

- Every raw hook payload is logged to `~/.pitcrew/events.log` (reset on each launch).
  Handy for seeing exactly what Claude Code sends.
- `install.sh` backs up `~/.claude/settings.json` before editing it.
  To uninstall, remove the `$HOME/.pitcrew/hook.sh` entries from that file.

## Controls

- Drag the header to move the panel. It stays pinned by its top-right corner.
- Click a card to open its **detail view**: the full checklist (or recent tool
  calls if the agent made no task list) and the last terminal command with its
  output. The mini robots at the top switch agents; `‹` goes back.
- `⌃` collapses to the "N agents running" pill. Click the pill to expand.
- `↗` brings that project's VS Code window to the front.
- `✕` on a card hides it until that agent's next prompt or notification.
- Menu bar icon: Show Pit Crew, Reset Position, Quit.

## Roadmap

- ~~**v1:** Allow/Deny from the panel via the `PermissionRequest` hook.~~ Done.
- **Next:** launch at login; "Always allow" (via `updatedPermissions`).
- ~~Detail view; answering `AskUserQuestion` from the panel.~~ Done.
- **Later:** a VS Code extension for exact terminal-tab focus.
