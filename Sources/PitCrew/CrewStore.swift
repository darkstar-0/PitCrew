import AppKit
import Combine

struct TaskItem: Identifiable {
    var id: String
    var content: String
    var activeForm: String?
    var status: String   // pending | in_progress | completed
}

/// One tool call in the detail view's activity list.
struct ActivityItem: Identifiable {
    let id = UUID()
    let symbol: String   // SF Symbol for the tool kind
    let text: String
    var done = false
}

struct CrewOption {
    let label: String
    let detail: String
}

struct CrewQuestion {
    let text: String
    let header: String
    let options: [CrewOption]
    let multiSelect: Bool
}

/// A permission prompt (or AskUserQuestion) that Claude Code is blocked on.
struct PendingPermission {
    let id = UUID()
    let tool: String
    let summary: String              // e.g. "Bash: npx hyperframes render . -o out.mp4"
    let input: [String: Any]         // original tool_input (echoed back for questions)
    let questions: [CrewQuestion]  // non-empty for AskUserQuestion
    let expires: Date                // just before the hook's own timeout
    let reply: (Data) -> Void
}

enum PermissionChoice { case allow, deny, terminal }

struct Agent: Identifiable {
    let id: String                // Claude Code session_id
    var colorIndex: Int
    var cwd = ""
    var title = ""
    var hasPrompt = false
    var activity = "Starting…"
    var tasks: [TaskItem] = []
    var attention: String?        // Notification text (e.g. waiting for input)
    var permission: PendingPermission?
    var finished = false
    var dismissed = false

    // Detail view
    var recent: [ActivityItem] = []   // last few tool calls, oldest first
    var lastCommand: String?          // last Bash command
    var lastOutput = ""               // tail of its output
    var commandRunning = false

    var folder: String { (cwd as NSString).lastPathComponent }
    var done: Int { tasks.filter { $0.status == "completed" }.count }
    var fraction: Double { tasks.isEmpty ? 0 : Double(done) / Double(tasks.count) }
    var current: TaskItem? { tasks.first { $0.status == "in_progress" } }

    /// Lime text shown instead of the status line when the agent needs you.
    var highlight: String? {
        if let p = permission { return p.questions.isEmpty ? "needs permission" : "asks a question" }
        return attention
    }

    /// Grey line under the title, e.g. "Rendering animations".
    var statusLine: String {
        if finished { return "Done, waiting for you" }
        return current?.activeForm ?? activity
    }

    /// Label after "5/7", e.g. "Render 01-hook.mp4".
    var progressLabel: String {
        if let c = current { return c.content }
        if done == tasks.count { return "All tasks done" }
        return tasks.first { $0.status == "pending" }?.content ?? ""
    }
}

final class CrewStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published var collapsed = false
    @Published var soundOn = true
    /// Which agent's detail view is open (nil = the list).
    @Published var selectedID: String?

    var selectedAgent: Agent? {
        guard let id = selectedID else { return nil }
        return visibleAgents.first { $0.id == id }
    }

    /// Set by the app delegate. If the panel is hidden, permission prompts
    /// fall straight through to the terminal.
    var isPanelVisible: () -> Bool = { true }

    /// Hook timeout is 600s in settings.json and curl gives up at 590s.
    static let permissionWindow: TimeInterval = 585

    private var nextColor = 0
    private let logURL: URL
    private var sweepTimer: Timer?

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pitcrew")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("events.log")
        try? Data().write(to: logURL)   // fresh log each launch

        sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.clearExpiredPermissions()
        }
    }

    var visibleAgents: [Agent] { agents.filter { !$0.dismissed } }
    var needsAttention: Bool { visibleAgents.contains { $0.highlight != nil } }

    // MARK: Requests

    func handle(_ req: IncomingRequest) {
        appendLog(req.raw)
        if req.path == "/permission" {
            handlePermission(req)
        } else {
            handleEvent(req.json)
        }
    }

    private func handleEvent(_ e: [String: Any]) {
        guard let sid = e["session_id"] as? String,
              let event = e["hook_event_name"] as? String else { return }

        if event == "SessionEnd" {
            agents.first { $0.id == sid }?.permission?.reply(Data())
            agents.removeAll { $0.id == sid }
            return
        }

        let idx = agentIndex(sid, cwd: e["cwd"] as? String)
        var a = agents[idx]
        let tool = e["tool_name"] as? String ?? ""
        let input = e["tool_input"] as? [String: Any] ?? [:]

        // The agent moved on (you answered in the terminal, or the hook timed
        // out), so any prompt still showing in Pit Crew is stale.
        if ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop"].contains(event) {
            a.permission?.reply(Data())
            a.permission = nil
        }

        switch event {
        case "SessionStart":
            a.activity = "Ready"

        case "UserPromptSubmit":
            let prompt = (e["prompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.hasPrompt && !prompt.isEmpty {
                a.title = Self.shorten(prompt, 40)
                a.hasPrompt = true
            }
            a.activity = "Thinking…"
            a.attention = nil
            a.finished = false
            a.dismissed = false

        case "PreToolUse":
            a.attention = nil
            a.finished = false
            a.activity = Self.describe(tool: tool, input: input)
            if !Self.taskTools.contains(tool) {
                // Tools run one after another, so anything older is finished
                // (or was denied and will never get a PostToolUse).
                for i in a.recent.indices { a.recent[i].done = true }
                a.recent.append(ActivityItem(symbol: Self.symbol(for: tool), text: a.activity))
                if a.recent.count > 8 { a.recent.removeFirst(a.recent.count - 8) }
            }
            if tool == "Bash" {
                a.lastCommand = input["command"] as? String ?? ""
                a.lastOutput = ""
                a.commandRunning = true
            }

        case "PostToolUse":
            a.attention = nil
            applyTasks(&a, tool: tool, input: input, response: e["tool_response"])
            if let i = a.recent.lastIndex(where: { !$0.done }) { a.recent[i].done = true }
            if tool == "Bash" {
                a.commandRunning = false
                a.lastOutput = Self.tail(Self.bashOutput(e["tool_response"]), lines: 6)
            }

        case "Notification":
            // Fires when the terminal is showing a prompt, or Claude is idle waiting.
            // Don't let its generic text overwrite a more specific label we already set.
            if a.permission == nil && a.attention == nil {
                a.attention = e["message"] as? String ?? "Needs your input"
                a.dismissed = false
                ding()
            }

        case "Stop":
            a.finished = true
            a.attention = nil
            a.commandRunning = false
            for i in a.recent.indices { a.recent[i].done = true }
            ding()

        default:
            break
        }
        agents[idx] = a
    }

    // MARK: Permissions

    private func handlePermission(_ req: IncomingRequest) {
        let e = req.json
        let tool = e["tool_name"] as? String ?? ""
        let input = e["tool_input"] as? [String: Any] ?? [:]
        guard let sid = e["session_id"] as? String else { req.reply(Data()); return }

        let idx = agentIndex(sid, cwd: e["cwd"] as? String)

        let questions = tool == "AskUserQuestion" ? Self.parseQuestions(input) : []

        // Plan approval (and any question we can't parse) stays in the terminal;
        // just flag the card.
        if tool == "ExitPlanMode" || (tool == "AskUserQuestion" && questions.isEmpty) {
            req.reply(Data())
            agents[idx].attention = tool == "ExitPlanMode" ? "wants plan approval" : "asks a question"
            agents[idx].dismissed = false
            ding()
            return
        }

        // Panel hidden: answer "no decision" so the normal terminal prompt shows.
        guard isPanelVisible() else {
            req.reply(Data())
            if !questions.isEmpty { agents[idx].attention = "asks a question" }
            return
        }

        agents[idx].permission?.reply(Data())   // supersede anything older
        agents[idx].permission = PendingPermission(
            tool: tool,
            summary: Self.permissionSummary(tool: tool, input: input),
            input: input,
            questions: questions,
            expires: Date().addingTimeInterval(Self.permissionWindow),
            reply: req.reply
        )
        agents[idx].attention = nil
        agents[idx].dismissed = false
        agents[idx].finished = false
        collapsed = false   // make sure the buttons are visible
        ding()
    }

    func decide(_ agent: Agent, _ choice: PermissionChoice) {
        guard let i = agents.firstIndex(where: { $0.id == agent.id }),
              let p = agents[i].permission else { return }
        agents[i].permission = nil

        switch choice {
        case .allow:
            p.reply(Self.decisionJSON(allow: true))
            agents[i].activity = "Approved \(p.tool)"
        case .deny:
            p.reply(Self.decisionJSON(allow: false))
            agents[i].activity = "Denied \(p.tool)"
        case .terminal:
            p.reply(Data())   // no decision → Claude Code shows its own prompt
            focus(agent)
        }
    }

    /// Answers an AskUserQuestion: `answers` maps question text → chosen label(s).
    func answer(_ agent: Agent, _ answers: [String: String]) {
        guard let i = agents.firstIndex(where: { $0.id == agent.id }),
              let p = agents[i].permission else { return }
        agents[i].permission = nil
        var updated = p.input
        updated["answers"] = answers
        p.reply(Self.decisionJSON(allow: true, updatedInput: updated))
        agents[i].activity = "Got your answer"
    }

    private func clearExpiredPermissions() {
        let now = Date()
        for i in agents.indices where (agents[i].permission?.expires ?? .distantFuture) < now {
            agents[i].permission = nil
        }
    }

    static func parseQuestions(_ input: [String: Any]) -> [CrewQuestion] {
        guard let qs = input["questions"] as? [[String: Any]] else { return [] }
        return qs.compactMap { q -> CrewQuestion? in
            guard let text = q["question"] as? String else { return nil }
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> CrewOption? in
                guard let label = o["label"] as? String else { return nil }
                return CrewOption(label: label, detail: o["description"] as? String ?? "")
            }
            return CrewQuestion(text: text,
                                  header: q["header"] as? String ?? "",
                                  options: options,
                                  multiSelect: q["multiSelect"] as? Bool ?? false)
        }
    }

    static func decisionJSON(allow: Bool, updatedInput: [String: Any]? = nil) -> Data {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "The user denied this from Pit Crew." }
        if let updatedInput { decision["updatedInput"] = updatedInput }
        let obj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ] as [String: Any]
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    static func permissionSummary(tool: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Bash":
            return "Bash: " + shorten(input["command"] as? String ?? "", 140)
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            return "\(tool): \(file ?? "a file")"
        case "WebFetch":
            return "WebFetch: " + shorten(input["url"] as? String ?? "", 120)
        default:
            let args = stringify(input)
            return args == "{}" ? tool : "\(tool): " + shorten(args, 120)
        }
    }

    // MARK: Tasks

    /// Supports both the older TodoWrite tool and the newer TaskCreate/TaskUpdate tools.
    private func applyTasks(_ a: inout Agent, tool: String, input: [String: Any], response: Any?) {
        switch tool {
        case "TodoWrite":
            guard let todos = input["todos"] as? [[String: Any]] else { return }
            a.tasks = todos.enumerated().map { i, t in
                TaskItem(id: String(i),
                         content: t["content"] as? String ?? "",
                         activeForm: t["activeForm"] as? String,
                         status: t["status"] as? String ?? "pending")
            }

        case "TaskCreate":
            // Response text looks like "Task #3 created…"; fall back to a running count.
            let text = Self.stringify(response)
            var id = String(a.tasks.count + 1)
            if let r = text.range(of: #"#(\d+)"#, options: .regularExpression) {
                id = String(text[r].dropFirst())
            }
            a.tasks.append(TaskItem(id: id,
                                    content: input["subject"] as? String ?? "Task",
                                    activeForm: input["activeForm"] as? String,
                                    status: "pending"))

        case "TaskUpdate":
            guard let tid = Self.idString(input["taskId"]),
                  let i = a.tasks.firstIndex(where: { $0.id == tid }) else { return }
            if let s = input["status"] as? String {
                if s == "deleted" { a.tasks.remove(at: i); return }
                a.tasks[i].status = s
            }
            if let s = input["subject"] as? String { a.tasks[i].content = s }
            if let s = input["activeForm"] as? String { a.tasks[i].activeForm = s }

        default:
            break
        }
    }

    // MARK: Actions

    func focus(_ agent: Agent) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = agent.cwd.isEmpty
            ? ["-a", "Visual Studio Code"]
            : ["-a", "Visual Studio Code", agent.cwd]
        try? p.run()
    }

    func dismiss(_ agent: Agent) {
        if let i = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[i].dismissed = true
        }
    }

    private func ding() {
        if soundOn { NSSound(named: "Glass")?.play() }
    }

    // MARK: Helpers

    private func agentIndex(_ sid: String, cwd: String?) -> Int {
        let idx: Int
        if let i = agents.firstIndex(where: { $0.id == sid }) {
            idx = i
        } else {
            agents.append(Agent(id: sid, colorIndex: nextColor))
            nextColor += 1
            idx = agents.count - 1
        }
        if let cwd { agents[idx].cwd = cwd }
        if agents[idx].title.isEmpty {
            agents[idx].title = agents[idx].folder.isEmpty ? "Claude Code" : agents[idx].folder
        }
        return idx
    }

    static func describe(tool: String, input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Bash":
            if let d = input["description"] as? String { return shorten(d, 44) }
            return "$ " + shorten(input["command"] as? String ?? "command", 40)
        case "Read": return "Reading \(file ?? "a file")"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing \(file ?? "a file")"
        case "Grep", "Glob": return "Searching the code"
        case "WebSearch", "WebFetch": return "Researching the web"
        case "Task", "Agent": return "Delegating to a subagent"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": return "Planning"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__")
                return "Using \(parts.count > 1 ? parts[1] : "a tool")"
            }
            return "Using \(tool)"
        }
    }

    static let taskTools: Set<String> = ["TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet"]

    static func symbol(for tool: String) -> String {
        switch tool {
        case "Bash": return "apple.terminal"
        case "Read": return "doc.text"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebSearch", "WebFetch": return "globe"
        case "Task", "Agent": return "person.2"
        default: return "wrench.and.screwdriver"
        }
    }

    /// Bash tool_response is usually {"stdout": …, "stderr": …}; fall back to text.
    static func bashOutput(_ response: Any?) -> String {
        if let d = response as? [String: Any] {
            let out = d["stdout"] as? String ?? ""
            let err = d["stderr"] as? String ?? ""
            return [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return stringify(response)
    }

    static func tail(_ s: String, lines n: Int) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.count > 90 ? String($0.prefix(89)) + "…" : String($0) }
        return lines.suffix(n).joined(separator: "\n")
    }

    static func shorten(_ s: String, _ n: Int) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count <= n ? oneLine : String(oneLine.prefix(n - 1)) + "…"
    }

    static func stringify(_ v: Any?) -> String {
        guard let v else { return "" }
        if let s = v as? String { return s }
        if JSONSerialization.isValidJSONObject(v),
           let d = try? JSONSerialization.data(withJSONObject: v) {
            return String(decoding: d, as: UTF8.self)
        }
        return "\(v)"
    }

    static func idString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private func appendLog(_ raw: Data) {
        guard let h = try? FileHandle(forWritingTo: logURL) else { return }
        h.seekToEndOfFile()
        h.write(raw)
        h.write(Data("\n".utf8))
        h.closeFile()
    }
}
