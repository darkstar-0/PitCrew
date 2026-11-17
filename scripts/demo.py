#!/usr/bin/env python3
"""
Pit Crew demo: a guided tour of every feature, no Claude Code needed.

It plays four fake Claude Code agents by sending Pit Crew the same hook
events real sessions send. Some scenes wait for you to click in the panel.

    1. Start Pit Crew       (open PitCrew.app, or `swift run`)
    2. ./scripts/demo.py    (or `make demo`)

Options:
    --fast        shorter pauses (good for a second run)
    --no-wait     don't wait for clicks; answer prompts automatically
    --crowd [N]   stress test: N agents (default 50) across six projects,
                  with subagents and permission prompts popping up
    --seconds S   with --crowd --no-wait: how long to run (default 20)
"""
import json
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.request

URL = os.environ.get("PITCREW_URL", "http://127.0.0.1:7777")
FAST = "--fast" in sys.argv
AUTO = "--no-wait" in sys.argv
SPEED = float(os.environ.get("PITCREW_DEMO_SPEED", "0.5" if FAST else "1.0"))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _arg_value(flag, default):
    """Value after `flag` on the command line, or `default` (None if the flag is absent)."""
    if flag not in sys.argv:
        return None
    i = sys.argv.index(flag)
    if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--"):
        return sys.argv[i + 1]
    return default


CROWD = _arg_value("--crowd", "50")
SECONDS = float(_arg_value("--seconds", "20") or 20)

# ── terminal styling ──────────────────────────────────────────────────────────
TTY = sys.stdout.isatty()
def c(code, s): return f"\033[{code}m{s}\033[0m" if TTY else s
LIME = lambda s: c("38;5;191", s)
DIM = lambda s: c("2", s)
BOLD = lambda s: c("1", s)

_print_lock = threading.Lock()
def say(s=""):
    with _print_lock:
        print(s, flush=True)

def scene(n, title, blurb):
    say()
    say(LIME(f"━━ {n}. {title} ") + LIME("━" * max(0, 50 - len(title))))
    say(DIM(blurb))

def you(s):
    say(BOLD(LIME("👉 ")) + BOLD(s))

def pause(seconds):
    time.sleep(seconds * SPEED)


# ── talking to Pit Crew ───────────────────────────────────────────────────────
def post(path, payload, timeout=3.0):
    req = urllib.request.Request(
        URL + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode()


class FakeAgent:
    """Sends the hook events a real Claude Code session would."""

    def __init__(self, sid, prompt, tasks, cwd=ROOT):
        self.sid = f"pitcrew-demo-{sid}"
        self.prompt = prompt
        self.tasks = tasks           # list of (content, activeForm)
        self.status = ["pending"] * len(tasks)
        self.cwd = cwd               # the card shows this folder's name

    def event(self, name, **fields):
        payload = {"session_id": self.sid, "hook_event_name": name, "cwd": self.cwd}
        payload.update(fields)
        post("/event", payload)

    # lifecycle
    def start(self):
        self.event("SessionStart", source="startup")
        self.event("UserPromptSubmit", prompt=self.prompt)

    def stop(self):
        self.event("Stop", stop_hook_active=False)

    def end(self):
        try:
            self.event("SessionEnd", reason="other")
        except Exception:
            pass

    # task list (what drives the progress bar and checklist)
    def _write_todos(self):
        todos = [{"content": t, "activeForm": a, "status": s}
                 for (t, a), s in zip(self.tasks, self.status)]
        self.event("PreToolUse", tool_name="TodoWrite", tool_input={"todos": todos})
        self.event("PostToolUse", tool_name="TodoWrite", tool_input={"todos": todos},
                   tool_response={"oldTodos": [], "newTodos": todos})

    def plan(self):
        self._write_todos()

    def begin(self, i):
        self.status[i] = "in_progress"
        self._write_todos()

    def complete(self, i):
        self.status[i] = "completed"
        self._write_todos()

    @property
    def next_task(self):
        return next((i for i, s in enumerate(self.status) if s != "completed"), None)

    # tool calls (what drives the status line, activity list and terminal box)
    def tool(self, name, tool_input, response=None, seconds=1.0):
        self.event("PreToolUse", tool_name=name, tool_input=tool_input)
        pause(seconds)
        self.event("PostToolUse", tool_name=name, tool_input=tool_input,
                   tool_response=response if response is not None else {})

    def bash(self, command, description, output, seconds=2.0):
        self.tool("Bash", {"command": command, "description": description},
                  {"stdout": output, "stderr": "", "interrupted": False}, seconds)

    # subagents: same session_id as the parent, plus agent_id / agent_type
    def sub_event(self, name, sub, **fields):
        agent_id, agent_type = sub
        self.event(name, agent_id=agent_id, agent_type=agent_type, **fields)

    def sub_start(self, sub):
        self.sub_event("SubagentStart", sub)

    def sub_stop(self, sub):
        self.sub_event("SubagentStop", sub, stop_hook_active=False)

    def sub_tool(self, sub, name, tool_input, response=None, seconds=1.0):
        self.sub_event("PreToolUse", sub, tool_name=name, tool_input=tool_input)
        pause(seconds)
        self.sub_event("PostToolUse", sub, tool_name=name, tool_input=tool_input,
                       tool_response=response if response is not None else {})

    # things that wait for you
    def ask_permission(self, tool_name, tool_input, sub=None):
        """Blocks until you click. Returns 'allow', 'deny' or None (handed to VS Code)."""
        payload = {"session_id": self.sid, "hook_event_name": "PermissionRequest",
                   "cwd": self.cwd, "tool_name": tool_name, "tool_input": tool_input,
                   "permission_mode": "default"}
        if sub:
            payload["agent_id"], payload["agent_type"] = sub
        body = post("/permission", payload, timeout=600)
        if not body.strip():
            return None
        return json.loads(body)["hookSpecificOutput"]["decision"]["behavior"]

    def ask_question(self, questions):
        """Blocks until you answer. Returns {question: label} or None."""
        payload = {"session_id": self.sid, "hook_event_name": "PermissionRequest",
                   "cwd": self.cwd, "tool_name": "AskUserQuestion",
                   "tool_input": {"questions": questions}, "permission_mode": "default"}
        body = post("/permission", payload, timeout=600)
        if not body.strip():
            return None
        decision = json.loads(body)["hookSpecificOutput"]["decision"]
        return decision.get("updatedInput", {}).get("answers")


def wait_for_click(fn, auto_result, label):
    """Runs a blocking prompt; with --no-wait, answers it after a moment instead."""
    if AUTO:
        result = {}
        t = threading.Thread(target=lambda: result.update(v=fn()), daemon=True)
        t.start()
        pause(2.5)
        say(DIM(f"   (--no-wait: answering “{label}” automatically)"))
        return auto_result
    return fn()


# ── background workers: agents that keep busy while you click around ─────────
class Worker(threading.Thread):
    def __init__(self, agent, steps):
        super().__init__(daemon=True)
        self.agent = agent
        self.steps = steps        # per task: list of (kind, args) tool calls
        self.stop_flag = threading.Event()

    def run(self):
        a = self.agent
        for i, calls in enumerate(self.steps):
            if self.stop_flag.is_set():
                return
            a.begin(i)
            for kind, args in calls:
                if self.stop_flag.is_set():
                    return
                if kind == "bash":
                    a.bash(*args, seconds=random.uniform(2.0, 3.5))
                else:
                    a.tool(kind, args, seconds=random.uniform(1.2, 2.5))
            a.complete(i)
            pause(random.uniform(0.8, 1.6))
        a.stop()


# ── the agents ───────────────────────────────────────────────────────────────
polish = FakeAgent("polish", "Polish · Watch Videos", [
    ("Read final-cut-transcript.md", "Reading the transcript"),
    ("Write style-sheet.md", "Writing the style sheet"),
    ("Render 01-hook.mp4", "Rendering animations"),
    ("Render 02-problem.mp4", "Rendering animations"),
    ("Render 03-crew.mp4", "Rendering animations"),
    ("Render 04-outro.mp4", "Rendering animations"),
    ("Build CapCut project", "Building the CapCut project"),
])
reel = FakeAgent("reel", "Breakdown reel", [
    ("Read the transcript", "Reading the transcript"),
    ("Pick a hook", "Picking a hook"),
    ("Write the script", "Writing the script"),
    ("Cut the b-roll list", "Cutting the b-roll list"),
    ("Export captions", "Exporting captions"),
])
scout = FakeAgent("scout", "Idea Scout", [
    ("Load videos.csv", "Loading 140 videos"),
    ("Score 140 videos", "Scoring 140 videos"),
    ("Cluster the winners", "Clustering the winners"),
    ("Render the top pick", "Rendering the top pick"),
    ("Write report.md", "Writing the report"),
    ("Post summary", "Posting the summary"),
])
sheet = FakeAgent("sheet", "Cheat sheet · Tokens", [
    ("Collect token prices", "Collecting token prices"),
    ("Outline the sheet", "Outlining the sheet"),
    ("Write the draft", "Writing the draft"),
    ("Proofread", "Proofreading"),
    ("Export PDF", "Exporting the PDF"),
])
AGENTS = [polish, reel, scout, sheet]


def render_step(n):
    return [("bash", (f"npx hyperframes render . -o 0{n}.mp4", f"Render 0{n}.mp4",
                      f"rendering frame 139/139\n✓ wrote 0{n}.mp4 (2.{n} MB, 4.6s)"))]


POLISH_STEPS = [
    [("Read", {"file_path": f"{ROOT}/final-cut-transcript.md"})],
    [("Write", {"file_path": f"{ROOT}/style-sheet.md", "content": "…"})],
    render_step(1), render_step(2), render_step(3), render_step(4),
    [("bash", ("python build_capcut.py --out project.capcut", "Build CapCut project",
               "Added 4 clips, 1 audio track\n✓ project.capcut ready"))],
]
SHEET_STEPS = [
    [("WebSearch", {"query": "LLM token pricing per million"}),
     ("WebFetch", {"url": "https://example.com/pricing", "prompt": "prices"})],
    [("Write", {"file_path": f"{ROOT}/outline.md", "content": "…"})],
    [("Edit", {"file_path": f"{ROOT}/cheat-sheet.md"}), ("Edit", {"file_path": f"{ROOT}/cheat-sheet.md"})],
    [("Read", {"file_path": f"{ROOT}/cheat-sheet.md"})],
    [("bash", ("pandoc cheat-sheet.md -o cheat-sheet.pdf", "Export PDF", "✓ cheat-sheet.pdf (1 page)"))],
]


# ── the tour ─────────────────────────────────────────────────────────────────
def preflight():
    try:
        post("/event", {"session_id": "pitcrew-demo-ping", "hook_event_name": "SessionEnd"})
    except (urllib.error.URLError, ConnectionError, OSError):
        say("Pit Crew isn't running. Start it first, then run this again:")
        say("   open /Applications/PitCrew.app     # if you installed the app")
        say("   swift run                          # or run it from the repo")
        sys.exit(1)


def main():
    preflight()
    say(BOLD("Pit Crew demo") + DIM("  ·  four fake agents, real Pit Crew. Ctrl-C to quit any time."))

    # 1 ─ agents appear
    scene(1, "Your crew shows up",
          "Each Claude Code session gets a card: a robot, its first prompt as the title,\n"
          "what it's doing right now, and a progress bar from its task list.")
    for a in AGENTS:
        a.start()
        pause(0.6)
        a.plan()
    pause(1.5)

    # 2 ─ background work
    scene(2, "They get to work",
          "Polish and Cheat sheet will keep working in the background for the rest of the demo.\n"
          "Watch the status lines and bars move; finished agents close their eyes.")
    workers = [Worker(polish, POLISH_STEPS), Worker(sheet, SHEET_STEPS)]
    for w in workers:
        w.start()

    scout.begin(0)
    scout.tool("Read", {"file_path": f"{ROOT}/videos.csv"}, seconds=1.5)
    scout.complete(0)
    scout.begin(1)
    scout.bash("python score.py videos.csv --top 3", "Scoring 140 videos",
               "Scored 140 videos\n1. hook-pain.mp4      9.2\n2. stats-open.mp4     8.7\n3. why-agents.mp4     8.1",
               seconds=3)
    scout.complete(1)

    reel.begin(0)
    reel.tool("Read", {"file_path": f"{ROOT}/breakdown-transcript.md"}, seconds=1.5)
    reel.complete(0)
    pause(1)

    # 3 ─ detail view
    scene(3, "Look inside an agent",
          "Click the Idea Scout card (anywhere but its buttons). You'll see its checklist\n"
          "and the last terminal command with its output. The mini robots switch agents; ‹ goes back.")
    if not AUTO:
        you("Click Idea Scout, look around, then come back here and press Enter.")
        input()
    else:
        pause(3)

    # 4 ─ permission
    scene(4, "An agent needs permission",
          "Claude Code asks before running risky commands. Pit Crew holds the request and\n"
          "shows Allow / Deny right on the card, so you never have to switch windows.")
    scout.begin(2)
    scout.tool("Grep", {"pattern": "score"}, seconds=1)
    scout.complete(2)
    scout.begin(3)
    you("Idea Scout wants to run a command. Click Allow or Deny in Pit Crew.")
    decision = wait_for_click(
        lambda: scout.ask_permission("Bash", {"command": "npx hyperframes render . -o top-pick.mp4",
                                              "description": "Render the top pick"}),
        "allow", "Allow")
    if decision == "allow":
        say(LIME("✓ You allowed it.") + " Claude Code receives "
            + DIM('{"behavior": "allow"}') + " and runs the command:")
        scout.bash("npx hyperframes render . -o top-pick.mp4", "Render the top pick",
                   "rendering frame 139/139\n✓ wrote top-pick.mp4 (3.1 MB)", seconds=3)
    elif decision == "deny":
        say(LIME("✓ You denied it.") + " Claude gets your “no” and picks another approach:")
        scout.tool("Write", {"file_path": f"{ROOT}/render-later.md", "content": "…"}, seconds=1.5)
    else:
        say(LIME("✓ Handed to VS Code.") + " In a real session, Claude Code's own prompt shows in the terminal.")
    scout.complete(3)

    # 5 ─ question
    scene(5, "An agent asks a question",
          "When Claude asks a multiple-choice question, you can answer it from the card.\n"
          "“Type in VS Code” sends it back to the terminal if you want to write your own answer.")
    reel.begin(1)
    you("Breakdown reel has a question. Pick a hook and click Send.")
    question = "Which hook should I use?"
    answers = wait_for_click(
        lambda: reel.ask_question([{
            "question": question, "header": "Hook", "multiSelect": False,
            "options": [
                {"label": "The pain one", "description": "Open on the frustration"},
                {"label": "The number one", "description": "Lead with a stat"},
                {"label": "The question one", "description": "Ask the viewer something"},
            ],
        }]),
        {question: "The pain one"}, "The pain one")
    if answers:
        pick = answers.get(question, "?")
        say(LIME("✓ You picked “" + pick + "”.") + " Claude Code receives " + DIM(json.dumps({"answers": answers})))
    else:
        pick = "the pain one"
        say(LIME("✓ Handed to VS Code.") + " In a real session you'd answer in the terminal.")
    reel.complete(1)
    reel.begin(2)
    reel.tool("Write", {"file_path": f"{ROOT}/script.md", "content": f"Hook: {pick}"}, seconds=2)
    reel.complete(2)

    # 6 ─ subagents
    scene(6, "An agent brings in helpers",
          "When Claude hands work to subagents, they show up under their parent's card,\n"
          "each with what it's doing, and each can ask for permission on its own.")
    reel.begin(3)
    reel.event("PreToolUse", tool_name="Task",
               tool_input={"description": "Find b-roll", "subagent_type": "Explore"})
    clips, stock, reviewer = ("demo-sub-clips", "Explore"), ("demo-sub-stock", "Explore"), \
        ("demo-sub-review", "script-reviewer")
    plans = {
        clips: [("Grep", {"pattern": "b-roll"}), ("Read", {"file_path": f"{ROOT}/clips/index.md"}),
                ("Glob", {"pattern": "**/*.mp4"}), ("Read", {"file_path": f"{ROOT}/clips/notes.md"})],
        stock: [("WebSearch", {"query": "stock footage terminal typing"}),
                ("WebFetch", {"url": "https://example.com/stock", "prompt": "list clips"}),
                ("WebSearch", {"query": "stock footage race car pit stop"})],
    }

    def run_sub(sub):
        reel.sub_start(sub)
        for name, args in plans[sub]:
            reel.sub_tool(sub, name, args, seconds=random.uniform(2.0, 3.5))
        reel.sub_stop(sub)

    helpers = [threading.Thread(target=run_sub, args=(sub,), daemon=True) for sub in (clips, stock)]
    for t in helpers:
        t.start()
        pause(0.5)
    reel.sub_start(reviewer)
    reel.sub_tool(reviewer, "Read", {"file_path": f"{ROOT}/script.md"}, seconds=1.5)
    you("Breakdown reel's script-reviewer subagent wants to run a spell check. Allow or Deny it.\n"
        "   (Its siblings keep working meanwhile: click the card to watch them.)")
    decision = wait_for_click(
        lambda: reel.ask_permission("Bash", {"command": "npx cspell script.md",
                                             "description": "Spell-check the script"}, sub=reviewer),
        "allow", "Allow")
    if decision == "allow":
        say(LIME("✓ Allowed.") + " Only the reviewer was waiting; the other two never stopped.")
        reel.sub_tool(reviewer, "Bash", {"command": "npx cspell script.md"},
                      {"stdout": "CSpell: 1 file checked, 0 issues", "stderr": ""}, seconds=1.5)
    elif decision == "deny":
        say(LIME("✓ Denied.") + " The reviewer skips the spell check and carries on.")
    else:
        say(LIME("✓ Handed to VS Code."))
    reel.sub_tool(reviewer, "Edit", {"file_path": f"{ROOT}/script.md"}, seconds=1.5)
    reel.sub_stop(reviewer)
    for t in helpers:
        t.join(timeout=30)
    reel.event("PostToolUse", tool_name="Task",
               tool_input={"description": "Find b-roll", "subagent_type": "Explore"},
               tool_response={"content": "Found 6 clips"})
    reel.complete(3)

    # 7 ─ finishing up
    scene(7, "Agents finish and wait for you",
          "When an agent stops, its card says “Done, waiting for you” and plays a sound\n"
          "(the speaker icon mutes it). If it sits idle, it pings you again.")
    for i in (4,):
        reel.begin(i)
        reel.tool("Edit", {"file_path": f"{ROOT}/script.md"}, seconds=1.2)
        reel.complete(i)
    reel.stop()
    for i in (4, 5):
        scout.begin(i)
        scout.tool("Write", {"file_path": f"{ROOT}/report.md", "content": "…"}, seconds=1.2)
        scout.complete(i)
    scout.stop()
    pause(2)
    reel.event("Notification", message="Claude is waiting for your input",
               notification_type="idle_prompt")

    for w in workers:
        w.join(timeout=60 * SPEED + 5)

    # 8 ─ wrap
    scene(8, "Try the controls",
          "  🎨  cycle through the color themes (also in the menu bar → Theme)\n"
          "  ≡   show only agents that need you\n"
          "  ⌃   collapse to the “N agents running” pill (click it to expand)\n"
          "  ↗   jump to that agent's VS Code window\n"
          "  ✕   on a card hides it; ✕ in the header hides the panel (menu bar icon brings it back)\n"
          "  Drag the header to move the panel.\n"
          "  Want to see a crowd? Run: make crowd  (50 agents)")
    if not AUTO:
        you("Press Enter to clear the demo agents.")
        input()


# ── crowd mode: lots of agents at once ───────────────────────────────────────
CROWD_PROJECTS = ["web-app", "api", "mobile", "infra", "docs", "data-pipeline"]
CROWD_JOBS = [
    ("Fix the login redirect", ["Reproduce the bug", "Find the redirect logic", "Write the fix", "Add a test"]),
    ("Upgrade dependencies", ["Check outdated packages", "Bump versions", "Run the test suite", "Fix breakages"]),
    ("Add dark mode", ["Audit the colors", "Add theme tokens", "Update components", "Screenshot test"]),
    ("Speed up the build", ["Profile the build", "Cache dependencies", "Split the bundle"]),
    ("Write API docs", ["List the endpoints", "Draft examples", "Generate reference", "Proofread"]),
    ("Flaky test hunt", ["Rerun CI 20 times", "Find the race", "Fix the test"]),
    ("Migrate to Postgres 17", ["Back up the data", "Run migrations", "Verify row counts", "Update configs"]),
    ("Refactor auth module", ["Map call sites", "Extract the service", "Move tests", "Clean up"]),
    ("Triage open issues", ["Read new issues", "Label them", "Close duplicates"]),
    ("Add rate limiting", ["Pick a strategy", "Write middleware", "Load test"]),
]
CROWD_FILES = ["index.ts", "auth.py", "README.md", "schema.sql", "App.swift", "main.go", "config.yaml"]
CROWD_HELPERS = ["Explore", "Plan", "code-reviewer", "test-runner"]


def crowd_tool():
    name = random.choice(["Read", "Read", "Edit", "Grep", "Bash", "Write", "WebSearch"])
    f = random.choice(CROWD_FILES)
    if name == "Bash":
        cmd = random.choice(["npm test", "pytest -q", "make build", "git status", "go vet ./..."])
        return name, {"command": cmd}, {"stdout": f"$ {cmd}\nok ({random.randint(3, 90)} passed)", "stderr": ""}
    if name == "Grep":
        return name, {"pattern": random.choice(["TODO", "redirect", "token", "retry"])}, {}
    if name == "WebSearch":
        return name, {"query": "how to " + random.choice(["cache npm in CI", "fix flaky tests", "rate limit"])}, {}
    return name, {"file_path": f"/src/{f}"}, {}


def crowd_mode(n):
    global AGENTS
    preflight()
    rng_jobs = [random.choice(CROWD_JOBS) for _ in range(n)]
    AGENTS = [
        FakeAgent(f"crowd-{i}", title, [(t, t) for t in tasks],
                  cwd=f"/tmp/pitcrew-crowd/{CROWD_PROJECTS[i % len(CROWD_PROJECTS)]}")
        for i, (title, tasks) in enumerate(rng_jobs)
    ]
    say(BOLD(f"Pit Crew crowd test: {n} agents") + DIM("  ·  Ctrl-C to stop"))
    say(DIM("Past 8 agents, quiet ones shrink to one-line rows grouped by project, and anything that\n"
            "needs you jumps to the top as a full card. Try: scroll, the ≡ filter, clicking a row,\n"
            "the mini robots in a detail view, and the counts on the collapsed ⌃ pill."))
    for a in AGENTS:
        a.start()
        a.plan()
        time.sleep(0.02)

    lock = threading.Lock()
    waiting = set()          # agents blocked on a permission prompt
    helpers = {}             # agent sid -> [sub, steps left]
    done = set()
    stop = threading.Event()
    asked = 0

    def ask(a):
        verdict = a.ask_permission("Bash", {"command": f"rm -rf ./build && {random.choice(['make', 'npm run build'])}",
                                            "description": "Clean rebuild"})
        say(LIME("✓ ") + f"{a.prompt} ({os.path.basename(a.cwd)}): "
            + {"allow": "allowed", "deny": "denied"}.get(verdict, "handed to VS Code"))
        with lock:
            waiting.discard(a.sid)

    def step(a):
        i = a.next_task
        if i is None:
            a.stop()
            done.add(a.sid)
            return
        if a.status[i] == "pending":
            a.begin(i)
            return
        h = helpers.get(a.sid)
        if h:                                   # a subagent is working
            sub, left = h
            if left == 0:
                a.sub_stop(sub)
                del helpers[a.sid]
            else:
                name, args, resp = crowd_tool()
                a.sub_tool(sub, name, args, resp, seconds=0)
                h[1] -= 1
            return
        r = random.random()
        if r < 0.10:
            sub = (f"{a.sid}-helper-{random.randint(100, 999)}", random.choice(CROWD_HELPERS))
            a.sub_start(sub)
            helpers[a.sid] = [sub, random.randint(2, 5)]
        elif r < 0.75:
            name, args, resp = crowd_tool()
            a.tool(name, args, resp, seconds=0)
        else:
            a.complete(i)

    if not AUTO:
        threading.Thread(target=lambda: (input(), stop.set()), daemon=True).start()
        say(BOLD("Press Enter to stop."))
    started = time.time()
    last_ask = started
    while not stop.is_set() and len(done) < len(AGENTS):
        if AUTO and time.time() - started > SECONDS:
            break
        with lock:
            busy = waiting | done
        free = [a for a in AGENTS if a.sid not in busy]
        if free:
            step(random.choice(free))
        # Every few seconds someone needs permission (at most 3 waiting at once).
        if time.time() - last_ask > 5 * SPEED and len(waiting) < 3 and free:
            last_ask = time.time()
            a = random.choice(free)
            with lock:
                waiting.add(a.sid)
            asked += 1
            threading.Thread(target=ask, args=(a,), daemon=True).start()
        time.sleep(0.08 * SPEED)
    say(LIME(f"\n✓ Crowd test over: {len(done)}/{len(AGENTS)} agents finished, {asked} permission prompts."))


def cleanup():
    for a in AGENTS:
        a.end()


if __name__ == "__main__":
    try:
        if CROWD:
            crowd_mode(max(1, int(CROWD)))
        else:
            main()
            say(LIME("\n✓ Demo done.") + " To use Pit Crew with real agents: " + BOLD("make hooks")
                + DIM("  (then start a new Claude Code session)"))
    except KeyboardInterrupt:
        say("\nStopping the demo…")
    finally:
        try:
            cleanup()
        except Exception:
            pass
