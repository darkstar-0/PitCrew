<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Pit Crew icon">
</p>

<h1 align="center">Pit Crew</h1>

<p align="center">
  A floating macOS panel for your Claude Code agents.<br>
  See what every session is doing, and approve or answer them without switching windows.
</p>

---

Running several Claude Code agents in VS Code tabs means constantly checking which one is
stuck waiting on you. Pit Crew sits in the top-right corner of your screen, across every
desktop, and shows:

- **Every session as a card**: its first prompt as the title, what it's doing right now,
  and a progress bar from its task list
- **When an agent needs you**: the card lights up and plays a sound
- **Allow / Deny** for permission prompts, right on the card
- **Answers to Claude's questions**: pick an option and hit Send
- **A detail view**: click a card for the full checklist and the last terminal command
  with its output
- **↗** to jump straight to that agent's VS Code window

Everything runs locally. Pit Crew only listens on `127.0.0.1`.

## Quick start

Requires macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/darkstar-0/PitCrew.git
cd PitCrew
make install   # builds PitCrew.app, installs + launches it, and hooks up Claude Code
make demo      # guided tour with fake agents: try every feature in ~3 minutes
```

Then start a **new** Claude Code session (hooks load when a session starts) and
it shows up in Pit Crew.

To keep Pit Crew around, click its menu bar icon → **Launch at Login**.

### All commands

| Command | What it does |
|---|---|
| `make install` | Build `PitCrew.app`, copy it to Applications, launch it, register the hooks |
| `make demo` | Guided tour with four fake agents (Pit Crew must be running) |
| `make app` | Just build `build/PitCrew.app` |
| `make hooks` | Just register the hooks in `~/.claude/settings.json` (safe to re-run) |
| `make run` | Run from source with `swift run` (for development) |
| `make uninstall` | Remove the app, the hooks and `~/.pitcrew` |

The demo also takes `--fast` (shorter pauses) and `--no-wait` (answers prompts
itself): `./scripts/demo.py --fast`.

## Controls

- **Click a card** to open its detail view. The mini robots at the top switch agents; **‹** goes back.
- **⌃** collapses the panel to an "N agents running" pill. Click the pill to expand.
- **↗** brings that project's VS Code window to the front.
- **✕** on a card hides it until the agent needs you again. **✕** in the header hides the panel.
- **🔊** mutes the sounds.
- **Drag the header** to move the panel. It stays pinned by its top-right corner.
- **Menu bar icon**: Show Pit Crew, Reset Position, Launch at Login, Quit.

## How it works

```
Claude Code ──hooks──► ~/.pitcrew/hook.sh ──────► Pit Crew (127.0.0.1:7777)
                       ~/.pitcrew/permission.sh ─┘   SwiftUI floating panel
```

`make hooks` adds these [Claude Code hooks](https://code.claude.com/docs/en/hooks)
to `~/.claude/settings.json`, after backing it up. Your other settings are left alone.

| Hook | What Pit Crew does with it |
|---|---|
| `SessionStart` / `SessionEnd` | Adds / removes the card |
| `UserPromptSubmit` | First prompt becomes the card title |
| `PreToolUse` | Status line ("Editing Views.swift"), activity list, terminal command |
| `PostToolUse` | Progress from TodoWrite / TaskCreate / TaskUpdate, command output |
| `Notification` | Lime highlight + sound when Claude is waiting |
| `Stop` | "Done, waiting for you" + sound |
| `PermissionRequest` | Allow / Deny buttons, or the question with its options |

**Permissions and questions.** `permission.sh` posts the request to Pit Crew,
which holds it open until you click. Pit Crew then replies with Claude Code's
decision JSON, `{"decision": {"behavior": "allow"}}` or `"deny"`. To answer a
question, it sends `"allow"` plus `updatedInput.answers` (the question text mapped
to the label you picked).

**It never blocks you.** Pit Crew replies with *no decision*, so Claude Code shows
its normal prompt in the terminal, when:
- the app isn't running
- the panel is hidden
- you click **In VS Code** / **Type in VS Code**
- nobody answers within about 10 minutes

The terminal prompt also stays visible while Pit Crew is waiting, so you can
answer in either place.

## Troubleshooting

- **A session doesn't show up.** Hooks load when a session starts, so start a new
  one after `make hooks`. Check that `~/.claude/settings.json` has `~/.pitcrew/` entries.
- **See what Claude Code is sending.** Every hook payload is logged to
  `~/.pitcrew/events.log`, which is cleared each time the app launches.
- **Port 7777 is taken.** Only one copy of Pit Crew can run at a time. Quit any
  `swift run` copy before opening the app.
- **The output in the detail view lags.** Hooks only report a command's output
  once it finishes, so long-running commands show "running…" until they're done.

## Project layout

```
Sources/PitCrew/     the app (SwiftUI + AppKit, no dependencies)
  AppDelegate.swift    panel window, menu bar, Launch at Login
  EventServer.swift    tiny HTTP server for the hooks
  CrewStore.swift      turns hook events into agent state
  Views.swift          cards, detail view, buttons, robots
hooks/               scripts Claude Code runs + settings installer
scripts/             build-app.sh, install-hooks.sh, demo.py, uninstall.sh
Resources/           Info.plist and the app icon
```

## Roadmap

- "Always allow" button (via the hook's `updatedPermissions`)
- VS Code extension so ↗ focuses the exact terminal tab, not just the window
- Answering plan approvals (ExitPlanMode) from the panel
