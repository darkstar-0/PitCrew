import SwiftUI
import AppKit

let robotPalette: [Color] = [
    Color(red: 0.33, green: 0.52, blue: 0.96),  // blue
    Color(red: 0.93, green: 0.42, blue: 0.66),  // pink
    Color(red: 0.94, green: 0.64, blue: 0.33),  // orange
    Color(red: 0.58, green: 0.45, blue: 0.95),  // purple
    Color(red: 0.30, green: 0.75, blue: 0.70),  // teal
    Color(red: 0.55, green: 0.80, blue: 0.35),  // green
    Color(red: 0.95, green: 0.36, blue: 0.36),  // red
    Color(red: 0.95, green: 0.82, blue: 0.30),  // yellow
    Color(red: 0.40, green: 0.72, blue: 0.98),  // sky
    Color(red: 0.80, green: 0.50, blue: 0.95),  // violet
    Color(red: 0.98, green: 0.58, blue: 0.47),  // coral
    Color(red: 0.62, green: 0.64, blue: 0.70),  // slate
]

/// Each agent's robot: 12 colors × 3 head shapes before anything repeats.
func robotColor(_ index: Int) -> Color { robotPalette[index % robotPalette.count] }
func robotVariant(_ index: Int) -> Int { (index / robotPalette.count) % 3 }

/// A group of quiet agents in the same project folder (crowded mode).
struct AgentGroup: Identifiable {
    let id: String       // folder name
    let agents: [Agent]
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Grows with its content up to `maxHeight`, then scrolls.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: contentHeight > maxHeight) {
            content
                .background(GeometryReader { g in
                    Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                })
        }
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: Root

struct CrewView: View {
    @ObservedObject var store: CrewStore
    var onHeight: (CGFloat) -> Void
    var onHide: () -> Void
    @Environment(\.colorScheme) var colorScheme

    /// The active theme ("Auto" follows macOS light/dark mode).
    private var theme: Theme { Theme.resolve(store.themeID, colorScheme: colorScheme) }

    var body: some View {
        Group {
            if store.collapsed {
                pill
            } else if let agent = store.selectedAgent {
                DetailView(agent: agent, store: store, onHide: onHide)
            } else {
                panel
            }
        }
        .frame(width: AppDelegate.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear.preference(key: HeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(HeightKey.self, perform: onHeight)
        .environment(\.theme, theme)
    }

    private var countText: String {
        let n = store.visibleAgents.count
        let k = store.needsYouCount
        if k > 0 { return "\(n) agent\(n == 1 ? "" : "s") · \(k) need\(k == 1 ? "s" : "") you" }
        return "\(n) agent\(n == 1 ? "" : "s") running"
    }

    var pill: some View {
        HStack {
            Spacer()
            Button { store.collapsed = false } label: {
                HStack(spacing: 8) {
                    Circle().fill(theme.onAccent).frame(width: 7, height: 7)
                    Text(countText)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(theme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.accent))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    var panel: some View {
        VStack(spacing: 8) {
            header
            CappedScroll(maxHeight: max(160, store.maxPanelHeight - 56)) {
                VStack(spacing: 8) { list }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.text.opacity(0.08), lineWidth: 1))
    }

    /// Few agents: a full card each. A crowd: agents that need you keep full
    /// cards at the top; everyone else shrinks to a one-line row, grouped by project.
    @ViewBuilder var list: some View {
        let agents = store.sortedAgents
        if store.visibleAgents.isEmpty {
            emptyText("No agents running")
        } else if agents.isEmpty {
            emptyText("Nobody needs you right now")
        } else if !store.isCrowded {
            ForEach(agents) { agent in
                AgentCard(agent: agent, store: store)
            }
        } else {
            ForEach(agents.filter { $0.highlight != nil }) { agent in
                AgentCard(agent: agent, store: store)
            }
            ForEach(Self.groups(agents.filter { $0.highlight == nil })) { group in
                VStack(spacing: 4) {
                    SectionHeader(title: group.id, count: group.agents.count)
                    ForEach(group.agents) { agent in
                        CompactRow(agent: agent, store: store)
                    }
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(theme.secondary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
    }

    /// Groups agents by project folder, keeping the order folders first appeared in.
    static func groups(_ agents: [Agent]) -> [AgentGroup] {
        var order: [String] = []
        var byFolder: [String: [Agent]] = [:]
        for a in agents {
            let key = a.folder.isEmpty ? "Other" : a.folder
            if byFolder[key] == nil { order.append(key) }
            byFolder[key, default: []].append(a)
        }
        return order.map { AgentGroup(id: $0, agents: byFolder[$0] ?? []) }
    }

    var header: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.accentInk).frame(width: 7, height: 7)
            Text("Pit Crew").font(.system(size: 14, weight: .bold)).foregroundColor(theme.text)
                .fixedSize()
            Text("\(store.visibleAgents.count)").font(.system(size: 14, weight: .bold)).foregroundColor(theme.secondary)
            if store.needsYouCount > 0 {
                Text("· \(store.needsYouCount) need\(store.needsYouCount == 1 ? "s" : "") you")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.accentInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton(symbol: store.onlyNeedsYou ? "line.3.horizontal.decrease.circle.fill"
                                                  : "line.3.horizontal.decrease.circle") {
                store.onlyNeedsYou.toggle()
            }
            .help(store.onlyNeedsYou ? "Showing only agents that need you" : "Show only agents that need you")
            IconButton(symbol: "paintpalette") { store.cycleTheme() }
                .help("Theme: \(theme.name). Click for the next one.")
            IconButton(symbol: store.soundOn ? "speaker.wave.2" : "speaker.slash") { store.soundOn.toggle() }
            IconButton(symbol: "chevron.up") { store.collapsed = true }
            IconButton(symbol: "xmark") { onHide() }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .background(WindowDragArea())
    }
}

// MARK: Card

struct AgentCard: View {
    let agent: Agent
    @ObservedObject var store: CrewStore
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow
                .contentShape(Rectangle())
                .onTapGesture { store.selectedID = agent.id }   // open detail view
            ActionBox(agent: agent, store: store)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(theme.accentInk, lineWidth: agent.highlight == nil ? 0 : 2))
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Robot(color: robotColor(agent.colorIndex),
                  working: !agent.finished && agent.highlight == nil,
                  variant: robotVariant(agent.colorIndex))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)

                Text(agent.highlight ?? agent.statusLine)
                    .font(.system(size: 11.5, weight: agent.highlight == nil ? .regular : .semibold))
                    .foregroundColor(agent.highlight == nil ? theme.secondary : theme.accentInk)
                    .lineLimit(1)

                if !agent.tasks.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(agent.done)/\(agent.tasks.count)").foregroundColor(theme.accentInk)
                        Text(agent.progressLabel).foregroundColor(theme.text.opacity(0.8)).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 2)

                    ProgressBar(fraction: agent.fraction)
                }

                if !agent.subagents.isEmpty {
                    SubagentList(subagents: agent.subagents, limit: 3)
                        .padding(.top, 3)
                }

                Text(agent.folder)
                    .font(.system(size: 9.5))
                    .foregroundColor(theme.tertiary)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                IconButton(symbol: "arrow.up.forward.square") { store.focus(agent) }
                IconButton(symbol: "xmark") { store.dismiss(agent) }
            }
        }
    }
}

// MARK: Pending permission / question (shared by card and detail view)

struct ActionBox: View {
    let agent: Agent
    @ObservedObject var store: CrewStore
    @Environment(\.theme) private var theme

    var body: some View {
        if let p = agent.permission {
            if p.questions.isEmpty {
                permissionBox(p)
            } else {
                QuestionBox(
                    questions: p.questions,
                    onSend: { store.answer(agent, $0) },
                    onTerminal: { store.decide(agent, .terminal) }
                )
                .id(p.id)   // fresh selections for each new question
            }
        }
    }

    private func permissionBox(_ p: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.summary)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(theme.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                PillButton(title: "Allow", primary: true) { store.decide(agent, .allow) }
                PillButton(title: "Deny") { store.decide(agent, .deny) }
                PillButton(title: "In VS Code") { store.decide(agent, .terminal) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.text.opacity(0.06)))
    }
}

// MARK: Detail view

struct DetailView: View {
    let agent: Agent
    @ObservedObject var store: CrewStore
    @Environment(\.theme) private var theme
    var onHide: () -> Void

    private var color: Color { robotColor(agent.colorIndex) }

    var body: some View {
        VStack(spacing: 8) {
            header
            CappedScroll(maxHeight: max(160, store.maxPanelHeight - 56)) {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    Rectangle().fill(theme.text.opacity(0.08)).frame(height: 1)
                    if !agent.subagents.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SUBAGENTS")
                                .font(.system(size: 9.5, weight: .heavy))
                                .foregroundColor(theme.secondary)
                            SubagentList(subagents: agent.subagents, limit: 12, large: true)
                        }
                    }
                    checklist
                    ActionBox(agent: agent, store: store)
                    if let cmd = agent.lastCommand {
                        TerminalBox(command: cmd, output: agent.lastOutput, running: agent.commandRunning)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.accentInk, lineWidth: agent.highlight == nil ? 0 : 2))
                .padding(1)   // keep the highlight outline inside the scroll area
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.text.opacity(0.08), lineWidth: 1))
    }

    /// Back button, a mini robot per agent to hop between them, window controls.
    private var header: some View {
        HStack(spacing: 6) {
            IconButton(symbol: "chevron.left") { store.selectedID = nil }
            // One mini robot per agent (needs-you first); scrolls sideways in a crowd.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.rankedAgents) { a in
                        Button { store.selectedID = a.id } label: {
                            MiniBot(color: robotColor(a.colorIndex),
                                    selected: a.id == agent.id,
                                    alert: a.highlight != nil)
                        }
                        .buttonStyle(.plain)
                        .help(a.title)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 28)   // a horizontal scroll view has no natural height of its own
            IconButton(symbol: "arrow.up.forward.square") { store.focus(agent) }
            IconButton(symbol: store.soundOn ? "speaker.wave.2" : "speaker.slash") { store.soundOn.toggle() }
            IconButton(symbol: "chevron.up") { store.collapsed = true }
            IconButton(symbol: "xmark") { onHide() }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .background(WindowDragArea())
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 14) {
            Robot(color: color, working: !agent.finished && agent.highlight == nil,
                  variant: robotVariant(agent.colorIndex))
                .scaleEffect(1.25)
                .padding(.horizontal, 4)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(agent.highlight ?? agent.statusLine)
                    .font(.system(size: 12, weight: agent.highlight == nil ? .regular : .semibold))
                    .foregroundColor(agent.highlight == nil ? theme.secondary : theme.accentInk)
                    .lineLimit(1)
                if !agent.tasks.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(agent.done)/\(agent.tasks.count)").foregroundColor(theme.accentInk)
                        Text(agent.progressLabel).foregroundColor(theme.text.opacity(0.8)).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.top, 2)
                    ProgressBar(fraction: agent.fraction)
                }
                Text(agent.folder)
                    .font(.system(size: 10))
                    .foregroundColor(theme.tertiary)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The agent's task list if it made one, otherwise its recent tool calls.
    @ViewBuilder private var checklist: some View {
        if !agent.tasks.isEmpty {
            let shown = Array(agent.tasks.prefix(10))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown) { t in
                    ChecklistRow(state: t.status == "completed" ? .done
                                      : t.status == "in_progress" ? .active : .pending,
                                 symbol: nil,
                                 text: t.content)
                }
                if agent.tasks.count > shown.count {
                    Text("+\(agent.tasks.count - shown.count) more")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondary)
                        .padding(.leading, 26)
                }
            }
        } else if !agent.recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(theme.secondary)
                ForEach(agent.recent) { item in
                    ChecklistRow(state: item.done ? .done : .active,
                                 symbol: item.symbol,
                                 text: item.text)
                }
            }
        } else {
            Text("Nothing to show yet")
                .font(.system(size: 12))
                .foregroundColor(theme.secondary)
        }
    }
}

struct ChecklistRow: View {
    @Environment(\.theme) private var theme
    enum RowState { case done, active, pending }
    let state: RowState
    let symbol: String?
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(theme.secondary)
                case .active:
                    Spinner()
                case .pending:
                    Image(systemName: "circle")
                        .foregroundColor(theme.tertiary)
                }
            }
            .font(.system(size: 14))
            .frame(width: 16, height: 16)

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondary)
                    .frame(width: 14)
            }

            Text(text)
                .font(.system(size: 12.5, weight: state == .active ? .semibold : .regular))
                .foregroundColor(state == .active ? theme.text
                                 : state == .done ? theme.secondary : theme.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// Clock-driven spinner (no repeatForever, so nothing leaks into layout).
struct Spinner: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 13
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(theme.text, style: StrokeStyle(lineWidth: size > 10 ? 2 : 1.5, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
        }
    }
}

struct TerminalBox: View {
    @Environment(\.theme) private var theme
    let command: String
    let output: String
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "apple.terminal").font(.system(size: 10))
                Text("Terminal").font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(theme.terminalText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))

            Text("$ " + CrewStore.shorten(command, 160))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(theme.terminalInk)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if running {
                Text("running…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.terminalText.opacity(0.6))
            } else if !output.isEmpty {
                Text(output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(theme.terminalText)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.terminal))
    }
}

/// Tiny robot head for switching agents in the detail header.
struct MiniBot: View {
    @Environment(\.theme) private var theme
    let color: Color
    let selected: Bool
    let alert: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 26, height: 18)
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.8)).frame(width: 3, height: 5)
                RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.8)).frame(width: 3, height: 5)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(alert ? theme.accentInk : theme.text.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
        .opacity(selected || alert ? 1 : 0.55)
    }
}

// MARK: Questions (AskUserQuestion)

struct QuestionBox: View {
    @Environment(\.theme) private var theme
    let questions: [CrewQuestion]
    let onSend: ([String: String]) -> Void
    let onTerminal: () -> Void

    /// Selected labels per question index.
    @State private var picks: [Int: Set<String>] = [:]

    private var allAnswered: Bool {
        questions.indices.allSatisfy { !(picks[$0] ?? []).isEmpty }
    }

    /// question text → chosen label(s), multi-select joined with ", "
    private var answers: [String: String] {
        var out: [String: String] = [:]
        for i in questions.indices {
            let chosen = picks[i] ?? []
            out[questions[i].text] = questions[i].options
                .map(\.label)
                .filter { chosen.contains($0) }
                .joined(separator: ", ")
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(questions.indices, id: \.self) { i in
                questionView(i)
            }
            HStack(spacing: 6) {
                PillButton(title: "Send", primary: allAnswered) {
                    if allAnswered { onSend(answers) }
                }
                .opacity(allAnswered ? 1 : 0.5)
                PillButton(title: "Type in VS Code") { onTerminal() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.text.opacity(0.06)))
    }

    private func questionView(_ i: Int) -> some View {
        let q = questions[i]
        return VStack(alignment: .leading, spacing: 6) {
            if !q.header.isEmpty {
                Text(q.header.uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(theme.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent))
            }
            Text(q.text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(q.options.indices, id: \.self) { j in
                let option = q.options[j]
                OptionRow(label: option.label,
                          detail: option.detail,
                          selected: (picks[i] ?? []).contains(option.label),
                          multi: q.multiSelect) {
                    toggle(question: i, label: option.label, multi: q.multiSelect)
                }
            }
        }
    }

    private func toggle(question i: Int, label: String, multi: Bool) {
        var set = picks[i] ?? []
        if multi {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
        }
        picks[i] = set
    }
}

struct OptionRow: View {
    @Environment(\.theme) private var theme
    let label: String
    let detail: String
    let selected: Bool
    let multi: Bool
    let action: () -> Void

    private var symbol: String {
        if multi { return selected ? "checkmark.square.fill" : "square" }
        return selected ? "largecircle.fill.circle" : "circle"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundColor(selected ? theme.accentInk : theme.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(theme.text)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(theme.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? theme.accent.opacity(theme.isLight ? 0.22 : 0.12) : theme.text.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? theme.accentInk.opacity(0.7) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(primary ? theme.onAccent : theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(primary ? theme.accent : theme.text.opacity(0.10)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    @Environment(\.theme) private var theme
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.12))
                Capsule().fill(theme.accent)
                    .frame(width: max(4, g.size.width * fraction))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 4)
    }
}

// MARK: Robot

struct Robot: View {
    let color: Color
    let working: Bool
    /// 0 = plain, 1 = antenna, 2 = ears. Lets 36 agents each look different.
    var variant: Int = 0

    // Driven by a clock instead of withAnimation(.repeatForever): that version
    // leaked the repeating animation into the whole layout, so every card's
    // text and the window height bounced forever.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !working)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            figure.offset(y: working ? CGFloat(sin(t * .pi / 0.6)) * 2 : 0)
        }
    }

    private var figure: some View {
        VStack(spacing: 0) {
            // Antenna slot is always there (empty for most) so every robot is the same height.
            VStack(spacing: 0) {
                Circle().fill(color).frame(width: 5, height: 5)
                Rectangle().fill(color).frame(width: 2, height: 3)
            }
            .opacity(variant == 1 ? 1 : 0)
            ZStack {
                if variant == 2 {
                    HStack(spacing: 34) {
                        RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 4, height: 12)
                        RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 4, height: 12)
                    }
                }
                RoundedRectangle(cornerRadius: 7).fill(color).frame(width: 34, height: 40)
                VStack(spacing: 7) {
                    HStack(spacing: 9) { eye; eye }
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 11, height: 2.5)
                }
                .offset(y: -2)
            }
            HStack(spacing: 12) { leg; leg }
        }
    }

    // Eyes close to a line when the agent is idle/done.
    var eye: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.black.opacity(0.8))
            .frame(width: 5, height: working ? 7 : 2)
    }

    var leg: some View {
        Rectangle().fill(color).frame(width: 5, height: 7)
    }
}

// MARK: Subagents

/// "↳ Explore  Reading Views.swift" rows under a card (or in the detail view).
struct SubagentList: View {
    @Environment(\.theme) private var theme
    let subagents: [SubAgent]
    let limit: Int
    var large = false

    /// Running ones first, then the most recently finished.
    private var ordered: [SubAgent] {
        subagents.filter { !$0.finished } + Array(subagents.filter { $0.finished }.reversed())
    }

    var body: some View {
        let shown = Array(ordered.prefix(limit))
        VStack(alignment: .leading, spacing: large ? 7 : 3) {
            ForEach(shown) { sub in
                HStack(spacing: 5) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: large ? 10 : 8.5, weight: .semibold))
                        .foregroundColor(theme.tertiary)
                    Group {
                        if sub.finished {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: large ? 12 : 9.5))
                                .foregroundColor(theme.secondary)
                        } else {
                            Spinner(size: large ? 11 : 8.5)
                        }
                    }
                    .frame(width: large ? 13 : 10)
                    Text(sub.type)
                        .font(.system(size: large ? 12 : 10.5, weight: .semibold))
                        .foregroundColor(theme.text.opacity(sub.finished ? 0.55 : 0.9))
                        .lineLimit(1)
                        .fixedSize()
                    Text(sub.activity)
                        .font(.system(size: large ? 12 : 10.5))
                        .foregroundColor(sub.finished ? theme.tertiary : theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            if subagents.count > shown.count {
                Text("+\(subagents.count - shown.count) more")
                    .font(.system(size: large ? 11 : 10))
                    .foregroundColor(theme.tertiary)
                    .padding(.leading, large ? 18 : 15)
            }
        }
    }
}

// MARK: Crowded mode

/// One-line row used when there are more than CrewStore.compactThreshold agents.
struct CompactRow: View {
    let agent: Agent
    @ObservedObject var store: CrewStore
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            MiniBot(color: robotColor(agent.colorIndex), selected: true, alert: false)
                .scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                Text(agent.statusLine)
                    .font(.system(size: 10.5))
                    .foregroundColor(theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if agent.runningSubagents > 0 {
                Text("↳\(agent.runningSubagents)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.secondary)
                    .help("\(agent.runningSubagents) subagents running")
            }
            if agent.finished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondary)
            } else if !agent.tasks.isEmpty {
                Text("\(agent.done)/\(agent.tasks.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(theme.accentInk)
                ProgressBar(fraction: agent.fraction)
                    .frame(width: 40)
            } else {
                Spinner(size: 9)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.card))
        .opacity(agent.finished ? 0.65 : 1)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedID = agent.id }   // open detail view
        .help(agent.title)
    }
}

/// Project folder label above a group of compact rows.
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundColor(theme.secondary)
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(theme.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

// MARK: Small pieces

struct IconButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.text.opacity(0.8))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Lets you drag the borderless panel by its header.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
