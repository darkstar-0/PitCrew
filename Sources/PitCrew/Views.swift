import SwiftUI
import AppKit

extension Color {
    static let lime = Color(red: 0.84, green: 0.97, blue: 0.36)
    static let crewCard = Color(white: 0.16)
    static let crewBG = Color(white: 0.10)
    static let crewMuted = Color(white: 0.62)
}

let robotPalette: [Color] = [
    Color(red: 0.33, green: 0.52, blue: 0.96),  // blue
    Color(red: 0.93, green: 0.42, blue: 0.66),  // pink
    Color(red: 0.94, green: 0.64, blue: 0.33),  // orange
    Color(red: 0.58, green: 0.45, blue: 0.95),  // purple
    Color(red: 0.30, green: 0.75, blue: 0.70),  // teal
    Color(red: 0.55, green: 0.80, blue: 0.35),  // green
]

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

    var body: some View {
        Group {
            if store.collapsed { pill } else { panel }
        }
        .frame(width: AppDelegate.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear.preference(key: HeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(HeightKey.self, perform: onHeight)
    }

    private var countText: String {
        let n = store.visibleAgents.count
        return "\(n) agent\(n == 1 ? "" : "s") running"
    }

    var pill: some View {
        HStack {
            Spacer()
            Button { store.collapsed = false } label: {
                HStack(spacing: 8) {
                    Circle().fill(Color.black).frame(width: 7, height: 7)
                    Text(store.needsAttention ? "Agent needs you" : countText)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.lime))
            }
            .buttonStyle(.plain)
        }
    }

    var panel: some View {
        VStack(spacing: 8) {
            header
            if store.visibleAgents.isEmpty {
                Text("No agents running")
                    .font(.system(size: 12))
                    .foregroundColor(Color.pitcrewMuted)
                    .padding(.vertical, 14)
            }
            ForEach(store.visibleAgents) { agent in
                AgentCard(agent: agent, store: store)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.pitcrewBG.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.lime).frame(width: 7, height: 7)
            Text("Pit Crew").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            Text("\(store.visibleAgents.count)").font(.system(size: 14, weight: .bold)).foregroundColor(Color.pitcrewMuted)
            Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.pitcrewCard))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.lime, lineWidth: agent.highlight == nil ? 0 : 2))
    }

    private func permissionBox(_ p: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(p.summary)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                PillButton(title: "Allow", primary: true) { store.decide(agent, .allow) }
                PillButton(title: "Deny") { store.decide(agent, .deny) }
                PillButton(title: "In VS Code") { store.decide(agent, .terminal) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Robot(color: robotPalette[agent.colorIndex % robotPalette.count],
                  working: !agent.finished && agent.highlight == nil)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(agent.highlight ?? agent.statusLine)
                    .font(.system(size: 11.5, weight: agent.highlight == nil ? .regular : .semibold))
                    .foregroundColor(agent.highlight == nil ? Color.pitcrewMuted : Color.lime)
                    .lineLimit(1)

                if !agent.tasks.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(agent.done)/\(agent.tasks.count)").foregroundColor(Color.lime)
                        Text(agent.progressLabel).foregroundColor(Color(white: 0.8)).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 2)

                    ProgressBar(fraction: agent.fraction)
                }

                Text(agent.folder)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(white: 0.4))
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

// MARK: Questions (AskUserQuestion)

struct QuestionBox: View {
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private func questionView(_ i: Int) -> some View {
        let q = questions[i]
        return VStack(alignment: .leading, spacing: 6) {
            if !q.header.isEmpty {
                Text(q.header.uppercased())
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.lime))
            }
            Text(q.text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
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
                    .foregroundColor(selected ? Color.lime : Color.pitcrewMuted)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.pitcrewMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.lime.opacity(0.12) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.lime.opacity(0.7) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(primary ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(primary ? Color.lime : Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color.lime)
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
            ZStack {
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

// MARK: Small pieces

struct IconButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.85))
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
