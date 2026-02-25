import SwiftUI

// MARK: - Agent Team Group View

struct AgentTeamView: View {
    let tools: [ChatMessage]
    @State private var isExpanded = true

    private var entries: [AgentActivityEntry] {
        var result: [AgentActivityEntry] = []
        var i = 0
        while i < tools.count {
            let msg = tools[i]
            guard msg.role == .toolUse else { i += 1; continue }

            // Look ahead for result
            var toolResult: ChatMessage?
            if i + 1 < tools.count {
                let next = tools[i + 1]
                if next.role == .toolResult || next.role == .toolError {
                    toolResult = next
                    i += 1
                }
            }

            switch msg.toolName {
            case "TeamCreate":
                let parsed = Self.parseTeamCreate(msg.content)
                result.append(AgentActivityEntry(
                    id: msg.id,
                    kind: .teamCreate,
                    title: parsed.teamName ?? "Agent team",
                    detail: parsed.members.isEmpty ? nil : parsed.members.joined(separator: ", "),
                    agentType: nil,
                    result: toolResult
                ))

            case "Task":
                let parsed = Self.parseTaskInput(msg.content)
                result.append(AgentActivityEntry(
                    id: msg.id,
                    kind: .task,
                    title: parsed.name ?? parsed.description,
                    detail: parsed.promptSummary,
                    agentType: parsed.agentType,
                    result: toolResult
                ))

            case "SendMessage":
                let parsed = Self.parseSendMessage(msg.content)
                result.append(AgentActivityEntry(
                    id: msg.id,
                    kind: .message,
                    title: parsed.target.map { "Message to \($0)" } ?? "Team message",
                    detail: parsed.preview,
                    agentType: nil,
                    result: toolResult
                ))

            default:
                break
            }
            i += 1
        }
        return result
    }

    private var taskEntries: [AgentActivityEntry] { entries.filter { $0.kind == .task } }
    private var agentCount: Int { taskEntries.count }
    private var doneCount: Int { taskEntries.filter { $0.status == .complete }.count }
    private var errorCount: Int { taskEntries.filter { $0.status == .error }.count }
    private var runningCount: Int { taskEntries.filter { $0.status == .running }.count }
    private var allDone: Bool { runningCount == 0 && !taskEntries.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries) { entry in
                        AgentActivityRowView(entry: entry)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(FamiliarApp.agentPurple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var headerButton: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FamiliarApp.agentPurple)
                    .frame(width: 12)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(FamiliarApp.agentPurple)

                if agentCount > 0 {
                    Text("\(agentCount) agent\(agentCount == 1 ? "" : "s")")
                        .font(.callout.bold())
                        .foregroundStyle(FamiliarApp.agentPurple)
                } else {
                    Text("Agent team")
                        .font(.callout.bold())
                        .foregroundStyle(FamiliarApp.agentPurple)
                }

                Spacer()

                // Status badges
                if allDone {
                    if doneCount > 0 {
                        statusBadge("checkmark", count: doneCount, color: FamiliarApp.agentGreen)
                    }
                    if errorCount > 0 {
                        statusBadge("xmark", count: errorCount, color: FamiliarApp.agentRed)
                    }
                } else if !taskEntries.isEmpty {
                    HStack(spacing: 4) {
                        if doneCount > 0 {
                            statusBadge("checkmark", count: doneCount, color: FamiliarApp.agentGreen)
                        }
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 11))
                            .foregroundStyle(FamiliarApp.agentPurple)
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                        Text("\(runningCount) running")
                            .font(.caption2)
                            .foregroundStyle(FamiliarApp.agentPurple.opacity(0.8))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(8)
    }

    private func statusBadge(_ icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.caption2.bold())
        }
        .foregroundStyle(color)
    }

    // MARK: - Parsers

    struct ParsedTask {
        let description: String
        let agentType: String
        let name: String?
        let promptSummary: String?
    }

    static func parseTaskInput(_ content: String) -> ParsedTask {
        let description = extractJsonValue(content, key: "description") ?? "Agent task"
        let agentType = extractJsonValue(content, key: "subagent_type") ?? "agent"
        let name = extractJsonValue(content, key: "name")
        let prompt = extractJsonValue(content, key: "prompt")
        // Take first sentence or first 120 chars of prompt as summary
        let summary: String? = prompt.map { p in
            let clean = p.replacingOccurrences(of: "\\n", with: " ")
            if let dot = clean.firstIndex(of: "."), clean.distance(from: clean.startIndex, to: dot) < 150 {
                return String(clean[...dot])
            }
            return String(clean.prefix(120)) + (clean.count > 120 ? "..." : "")
        }
        return ParsedTask(description: description, agentType: agentType, name: name, promptSummary: summary)
    }

    struct ParsedTeamCreate {
        let teamName: String?
        let members: [String]
    }

    static func parseTeamCreate(_ content: String) -> ParsedTeamCreate {
        let name = extractJsonValue(content, key: "name") ?? extractJsonValue(content, key: "team_name")
        // Try to extract member names from the JSON array
        var members: [String] = []
        let memberPattern = "\"name\"\\s*:\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: memberPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    members.append(String(content[range]))
                }
            }
        }
        return ParsedTeamCreate(teamName: name, members: members)
    }

    struct ParsedSendMessage {
        let target: String?
        let preview: String?
    }

    static func parseSendMessage(_ content: String) -> ParsedSendMessage {
        let target = extractJsonValue(content, key: "recipient") ?? extractJsonValue(content, key: "to")
        let message = extractJsonValue(content, key: "message") ?? extractJsonValue(content, key: "content")
        let preview = message.map { String($0.prefix(100)) + ($0.count > 100 ? "..." : "") }
        return ParsedSendMessage(target: target, preview: preview)
    }

    private static func extractJsonValue(_ text: String, key: String) -> String? {
        // Match both JSON-style ("key": "value") and formattedDescription-style (key: "value")
        let pattern = "\"?\(key)\"?\\s*:\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

// MARK: - Entry Model

private struct AgentActivityEntry: Identifiable {
    let id: UUID
    let kind: Kind
    let title: String
    let detail: String?
    let agentType: String?
    let result: ChatMessage?

    enum Kind { case teamCreate, task, message }
    enum Status { case running, complete, error }

    var status: Status {
        guard let result else { return .running }
        return result.role == .toolError ? .error : .complete
    }
}

// MARK: - Row View

private struct AgentActivityRowView: View {
    let entry: AgentActivityEntry
    @State private var isExpanded = false

    private var icon: String {
        switch entry.kind {
        case .teamCreate: return "diamond.fill"
        case .message: return "paperplane.fill"
        case .task:
            switch (entry.agentType ?? "").lowercased() {
            case "explore": return "magnifyingglass"
            case "bash": return "terminal"
            case "plan": return "map"
            case "code-reviewer": return "eye"
            case "bug-analyzer": return "ladybug"
            case "ui-sketcher": return "pencil.and.ruler"
            case "margot": return "paintbrush"
            case "raze": return "scissors"
            case "benji": return "questionmark.bubble"
            case "general-purpose": return "cpu"
            default: return "diamond"
            }
        }
    }

    private var kindLabel: String {
        switch entry.kind {
        case .teamCreate: return "team"
        case .message: return "message"
        case .task: return entry.agentType ?? "agent"
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .running: return "circle.dotted"
        case .complete: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .running: return FamiliarApp.agentPurple
        case .complete: return FamiliarApp.agentGreen
        case .error: return FamiliarApp.agentRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if entry.result != nil {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                }
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Type badge
                        HStack(spacing: 3) {
                            Image(systemName: icon)
                                .font(.system(size: 9))
                            Text(kindLabel)
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(FamiliarApp.agentPurple.opacity(0.6))
                        .clipShape(Capsule())

                        Text(entry.title)
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Image(systemName: statusIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(statusColor)
                            .symbolEffect(.pulse, options: .repeating, isActive: entry.status == .running)
                    }

                    // Detail line — shows what the agent is actually doing
                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable result
            if isExpanded, let result = entry.result {
                ScrollView {
                    Text(LocalizedStringKey(result.content))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 400)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .background(FamiliarApp.agentPurple.opacity(entry.status == .running ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
