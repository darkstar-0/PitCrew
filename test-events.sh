#!/bin/sh
# Fakes two Claude Code sessions so you can see the UI without running agents.
# Usage: ./test-events.sh   (with Pit Crew running)

post() {
  curl -s -H 'Content-Type: application/json' -H 'Expect:' \
    --data-binary "$1" http://127.0.0.1:7777/event >/dev/null || {
      echo "Pit Crew isn't running (start it with: swift run)"; exit 1; }
}

todos() {  # $1 = session, $2..$6 = statuses for 5 tasks
  post "{\"session_id\":\"$1\",\"hook_event_name\":\"PostToolUse\",\"cwd\":\"/Users/jack/code/demo\",\"tool_name\":\"TodoWrite\",\"tool_input\":{\"todos\":[
    {\"content\":\"Read transcript\",\"activeForm\":\"Reading the transcript\",\"status\":\"$2\"},
    {\"content\":\"Write style sheet\",\"activeForm\":\"Writing the style sheet\",\"status\":\"$3\"},
    {\"content\":\"Render 01-hook.mp4\",\"activeForm\":\"Rendering animations\",\"status\":\"$4\"},
    {\"content\":\"Render 02-problem.mp4\",\"activeForm\":\"Rendering animations\",\"status\":\"$5\"},
    {\"content\":\"Build CapCut project\",\"activeForm\":\"Building the project\",\"status\":\"$6\"}]}}"
}

post '{"session_id":"demo-a","hook_event_name":"SessionStart","cwd":"/Users/jack/code/watch-videos"}'
post '{"session_id":"demo-a","hook_event_name":"UserPromptSubmit","cwd":"/Users/jack/code/watch-videos","prompt":"Polish the Watch Videos video"}'
post '{"session_id":"demo-b","hook_event_name":"UserPromptSubmit","cwd":"/Users/jack/code/idea-scout","prompt":"Idea Scout: score 140 videos"}'
post '{"session_id":"demo-b","hook_event_name":"PreToolUse","cwd":"/Users/jack/code/idea-scout","tool_name":"Read","tool_input":{"file_path":"/Users/jack/code/idea-scout/videos.csv"}}'

todos demo-a in_progress pending pending pending pending; sleep 1.5
todos demo-a completed in_progress pending pending pending; sleep 1.5
todos demo-a completed completed in_progress pending pending; sleep 1.5

echo "Permission request on Idea Scout…"
post '{"session_id":"demo-b","hook_event_name":"Notification","cwd":"/Users/jack/code/idea-scout","message":"Claude needs your permission to use Bash"}'
sleep 3
post '{"session_id":"demo-b","hook_event_name":"PostToolUse","cwd":"/Users/jack/code/idea-scout","tool_name":"Bash","tool_input":{"command":"ls"}}'

todos demo-a completed completed completed in_progress pending; sleep 1.5
todos demo-a completed completed completed completed completed
post '{"session_id":"demo-a","hook_event_name":"Stop","cwd":"/Users/jack/code/watch-videos"}'

echo "Done. Close the fake sessions with:"
echo "  curl -s -d '{\"session_id\":\"demo-a\",\"hook_event_name\":\"SessionEnd\"}' localhost:7777/event"
