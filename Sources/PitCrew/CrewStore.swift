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

/// A subagent (Claude's Task/Agent tool) running inside a session. Its hook
/// events carry the parent's session_id plus its own agent_id / agent_type.
struct SubAgent: Identifiable {
    let id: String          // agent_id
    var type: String        // agent_type, e.g. "Explore"
    var activity = "Starting…"
    var finished = false
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
    let questions: [CrewQuestion]    // non-empty for AskUserQuestion
    let agentID: String?             // which subagent asked (nil = the main agent)
    let expires: Date                // just before the hook's own timeout
    let reply: (Data) -> Void
}

enum PermissionChoice { case allow, deny, terminal }

struct Agent: Identifiable {
    let id: String                // Claude Code session_id
    var colorIndex: Int
    var order: Int                // arrival order, for stable sorting
    var cwd = ""
    var title = ""
    var hasPrompt = false
    var activity = "Starting…"
    var tasks: [TaskItem] = []
    var attention: String?        // Notification text (e.g. waiting for input)
    /// Prompts waiting on you, oldest first. Parallel subagents can each ask.
    var permissions: [PendingPermission] = []
    var subagents: [SubAgent] = []
    var finished = false
    var dismissed = false

    // Detail view
    var recent: [ActivityItem] = []   // last few tool calls, oldest first
    var lastCommand: String?          // last Bash command
    var lastOutput = ""               // tail of its output
    var commandRunning = false

    /// The prompt currently shown; the rest wait their turn.
    var permission: PendingPermission? { permissions.first }

    var folder: String { (cwd as NSString).lastPathComponent }
    var done: Int { tasks.filter { $0.status == "completed" }.count }
    var fraction: Double { tasks.isEmpty ? 0 : Double(done) / Double(tasks.count) }
    var current: TaskItem? { tasks.first { $0.status == "in_progress" } }
    var runningSubagents: Int { subagents.filter { !$0.finished }.count }

    /// Lime text shown instead of the status line when the agent needs you.
    var highlight: String? {
        if let p = permission {
            let more = permissions.count > 1 ? " (+\(permissions.count - 1) more)" : ""
            return (p.questions.isEmpty ? "needs permission" : "asks a question") + more
        }
        return attention
    }

    /// Grey line under the title, e.g. "Rendering animations".
    var statusLine: String {
        if finished { return "Done, waiting for you" }
        if let c = current?.activeForm { return c }
        if runningSubagents > 0 {
            return "Waiting on \(runningSubagents) subagent\(runningSubagents == 1 ? "" : "s")"
        }
        return activity
    }

    /// Label after "5/7", e.g. "Render 01-hook.mp4".
    var progressLabel: String {
        if let c = current { return c.content }
        if done == tasks.count { return "All tasks done" }
        return tasks.first { $0.status == "pending" }?.content ?? ""
    }

    /// Sort key: prompts first, then other alerts, then working, then finished.
    var urgency: Int {
        if permission != nil { return 0 }
        if attention != nil { return 1 }
        if !finished { return 2 }
        return 3
    }
}

final class CrewStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published var collapsed = false
    @Published var soundOn = true
    /// Which agent's detail view is open (nil = the list).
    @Published var selectedID: String?
    /// Header filter: show only agents that need you.
    @Published var onlyNeedsYou = false
    /// Tallest the panel may get (set from the screen size by the app delegate).
    @Published var maxPanelHeight: CGFloat = 800

    /// Above this many agents, quiet agents shrink to one-line rows grouped by project.
    static let compactThreshold = 8
    /// How many finished subagents a card keeps showing.
    static let keepFinishedSubagents = 3

    /// A Theme id or Theme.autoID. Remembered between launches.
    @Published var themeID: String = UserDefaults.standard.string(forKey: "theme") ?? Theme.pitLane.id {
        didSet { UserDefaults.standard.set(themeID, forKey: "theme") }
    }

    /// 🎨 button: steps through every theme, then Auto, then back to the first.
    func cycleTheme() {
        let order = Theme.all.map(\.id) + [Theme.autoID]
        let i = order.firstIndex(of: themeID) ?? -1
        themeID = order[(i + 1) % order.count]
    }

    var selectedAgent: Agent? {
        guard let id = selectedID else { return nil }
        return visibleAgents.first { $0.id == id }
    }

    /// Set by the app delegate. If the panel is hidden, permission prompts
    /// fall straight through to the terminal.
    var isPanelVisible: () -> Bool = { true }

    /// Hook timeout is 600s in settings.json and curl gives up at 590s.
    static let permissionWindow: TimeInterval = 585

    private var nextOrder = 0
    private var lastDing = Date.distantPast
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
    var needsYouCount: Int { visibleAgents.filter { $0.highlight != nil }.count }
    var needsAttention: Bool { needsYouCount > 0 }

    /// Every visible agent, the ones that need you first, otherwise arrival order.
    var rankedAgents: [Agent] {
        visibleAgents.sorted { ($0.urgency, $0.order) < ($1.urgency, $1.order) }
    }

    /// What the list shows: `rankedAgents`, minus the rest when the filter is on.
    var sortedAgents: [Agent] {
        rankedAgents.filter { !onlyNeedsYou || $0.highlight != nil }
    }

    var isCrowded: Bool { visibleAgents.count > Self.compactThreshold }

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
            agents.first { $0.id == sid }?.permissions.forEach { $0.reply(Data()) }
            agents.removeAll { $0.id == sid }
            return
        }

        let idx = agentIndex(sid, cwd: e["cwd"] as? String)
        var a = agents[idx]
        let tool = e["tool_name"] as? String ?? ""
        let input = e["tool_input"] as? [String: Any] ?? [:]
        // Set when the event comes from a subagent inside this session.
        let agentID = (e["agent_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let agentType = (e["agent_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // Whoever sent this moved on (answered in the terminal, or the hook timed
        // out), so a prompt from that same agent still showing here is stale.
        // Prompts from other subagents in this session are left alone.
        if ["PreToolUse", "PostToolUse"].contains(event) {
            Self.dropPermissions(&a) { $0.agentID == agentID }
        } else if ["UserPromptSubmit", "Stop"].contains(event) {
            Self.dropPermissions(&a) { _ in true }
        }

        // Subagent events update that subagent's row, not the parent's own state.
        if let agentID, event != "SubagentStart", event != "SubagentStop" {
            let sub = Self.subagentIndex(&a, agentID, type: agentType)
            switch event {
            case "PreToolUse":
                a.subagents[sub].activity = Self.describe(tool: tool, input: input)
                a.subagents[sub].finished = false
            case "Notification":
                if a.permission == nil && a.attention == nil {
                    a.attention = e["message"] as? String ?? "Needs your input"
                    a.dismissed = false
                    ding()
                }
            default:
                break
            }
            agents[idx] = a
            return
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
            a.subagents.removeAll { $0.finished }

        case "SubagentStart":
            guard let agentID else { break }
            let i = Self.subagentIndex(&a, agentID, type: agentType)
            a.subagents[i].finished = false
            a.finished = false

        case "SubagentStop":
            // Claude Code sometimes sends a stop with no matching start; ignore those.
            guard let agentID, let i = a.subagents.firstIndex(where: { $0.id == agentID }) else { break }
            a.subagents[i].finished = true
            a.subagents[i].activity = "Done"
            Self.dropPermissions(&a) { $0.agentID == agentID }
            Self.trimFinishedSubagents(&a)

        case "PreToolUse":
            a.attention = nil
            a.finished = false
            a.activity = Self.describe(tool: tool, input: input)
            if !Self.taskTools.contains(tool) {
                // The main agent runs tools one after another, so anything older
                // is finished (or was denied and will never get a PostToolUse).
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
            for i in a.subagents.indices { a.subagents[i].finished = true }
            Self.trimFinishedSubagents(&a)
            ding()

        default:
            break
        }
        agents[idx] = a
    }

    /// Finds or creates the row for a subagent (some never send SubagentStart).
    private static func subagentIndex(_ a: inout Agent, _ agentID: String, type: String?) -> Int {
        if let i = a.subagents.firstIndex(where: { $0.id == agentID }) {
            if let type, a.subagents[i].type == "Subagent" { a.subagents[i].type = type }
            return i
        }
        a.subagents.append(SubAgent(id: agentID, type: type ?? "Subagent"))
        return a.subagents.count - 1
    }

    private static func trimFinishedSubagents(_ a: inout Agent) {
        let finished = a.subagents.filter { $0.finished }
        guard finished.count > Self.keepFinishedSubagents else { return }
        let drop = Set(finished.prefix(finished.count - Self.keepFinishedSubagents).map(\.id))
        a.subagents.removeAll { drop.contains($0.id) }
    }

    /// Answers matching prompts with "no decision" (the terminal takes over) and removes them.
    private static func dropPermissions(_ a: inout Agent, where match: (PendingPermission) -> Bool) {
        for p in a.permissions where match(p) { p.reply(Data()) }
        a.permissions.removeAll(where: match)
    }

    // MARK: Permissions

    private func handlePermission(_ req: IncomingRequest) {
        let e = req.json
        let tool = e["tool_name"] as? String ?? ""
        let input = e["tool_input"] as? [String: Any] ?? [:]
        guard let sid = e["session_id"] as? String else { req.reply(Data()); return }
        let agentID = (e["agent_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let agentType = (e["agent_type"] as? String).flatMap { $0.isEmpty ? nil : $0 }

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

        // A newer prompt from the same (sub)agent replaces its older one.
        Self.dropPermissions(&agents[idx]) { $0.agentID == agentID }

        var summary = Self.permissionSummary(tool: tool, input: input)
        if agentID != nil { summary = "\(agentType ?? "Subagent") · " + summary }

        agents[idx].permissions.append(PendingPermission(
            tool: tool,
            summary: summary,
            input: input,
            questions: questions,
            agentID: agentID,
            expires: Date().addingTimeInterval(Self.permissionWindow),
            reply: req.reply
        ))
        agents[idx].attention = nil
        agents[idx].dismissed = false
        agents[idx].finished = false
        collapsed = false   // make sure the buttons are visible
        ding()
    }

    /// Pops the prompt currently shown on this agent's card.
    private func takeShownPermission(_ agent: Agent) -> (Int, PendingPermission)? {
        guard let i = agents.firstIndex(where: { $0.id == agent.id }),
              let p = agents[i].permissions.first else { return nil }
        agents[i].permissions.removeFirst()
        return (i, p)
    }

    func decide(_ agent: Agent, _ choice: PermissionChoice) {
        guard let taken = takeShownPermission(agent) else { return }
        let (i, p) = taken
        switch choice {
        case .allow:
            p.reply(Self.decisionJSON(allow: true))
            if p.agentID == nil { agents[i].activity = "Approved \(p.tool)" }
        case .deny:
            p.reply(Self.decisionJSON(allow: false))
            if p.agentID == nil { agents[i].activity = "Denied \(p.tool)" }
        case .terminal:
            p.reply(Data())   // no decision → Claude Code shows its own prompt
            focus(agent)
        }
    }

    /// Answers an AskUserQuestion: `answers` maps question text → chosen label(s).
    func answer(_ agent: Agent, _ answers: [String: String]) {
        guard let taken = takeShownPermission(agent) else { return }
        let (i, p) = taken
        var updated = p.input
        updated["answers"] = answers
        p.reply(Self.decisionJSON(allow: true, updatedInput: updated))
        if p.agentID == nil { agents[i].activity = "Got your answer" }
    }

    private func clearExpiredPermissions() {
        let now = Date()
        for i in agents.indices where agents[i].permissions.contains(where: { $0.expires < now }) {
            agents[i].permissions.removeAll { $0.expires < now }
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

    /// At most one chime every 1.5s, so a crowd of agents doesn't turn into a drumroll.
    private func ding() {
        guard soundOn, Date().timeIntervalSince(lastDing) > 1.5 else { return }
        lastDing = Date()
        NSSound(named: "Glass")?.play()
    }

    // MARK: Helpers

    private func agentIndex(_ sid: String, cwd: String?) -> Int {
        let idx: Int
        if let i = agents.firstIndex(where: { $0.id == sid }) {
            idx = i
        } else {
            agents.append(Agent(id: sid, colorIndex: nextOrder, order: nextOrder))
            nextOrder += 1
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
