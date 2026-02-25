import SwiftUI

/// Full sheet view for interacting with an active agent team.
/// Shows agent list on the left, selected agent's messages on the right with input.
struct AgentTeamSheetView: View {
    let watcher: AgentTeamWatcher
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgent: String? // nil = all messages
    @State private var inputText = ""

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                agentList
                    .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)
                agentDetail
            }
        }
        .background(FamiliarApp.canvasBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 14))
                .foregroundStyle(FamiliarApp.agentPurple)

            if let team = watcher.activeTeam {
                Text(team.name)
                    .font(.headline)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(nonLeadMembers(team).count) agents")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Agent Team")
                    .font(.headline)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Agent List (left sidebar)

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "All" option
            agentListRow(
                name: "All",
                color: "purple",
                icon: "diamond.fill",
                isSelected: selectedAgent == nil,
                isIdle: false,
                messageCount: watcher.messages.filter { !$0.isIdleNotification }.count
            ) {
                selectedAgent = nil
            }

            Divider().padding(.horizontal, 8)

            // Individual agents
            if let team = watcher.activeTeam {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(nonLeadMembers(team)) { member in
                            let isIdle = watcher.idleAgents.contains(member.name)
                            let msgCount = watcher.messages.filter { $0.from == member.name && !$0.isIdleNotification }.count
                            agentListRow(
                                name: member.name,
                                color: member.color,
                                icon: iconFor(member.name),
                                isSelected: selectedAgent == member.name,
                                isIdle: isIdle,
                                messageCount: msgCount
                            ) {
                                selectedAgent = member.name
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .background(FamiliarApp.surfaceBackground)
    }

    private func agentListRow(
        name: String,
        color: String,
        icon: String,
        isSelected: Bool,
        isIdle: Bool,
        messageCount: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(agentColor(color))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if !isIdle && name != "All" {
                            Circle()
                                .fill(agentColor(color).opacity(0.4))
                                .frame(width: 14, height: 14)
                                .phaseAnimator([false, true]) { content, phase in
                                    content.opacity(phase ? 0 : 0.6)
                                } animation: { _ in .easeInOut(duration: 1.0) }
                        }
                    }

                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer()

                if messageCount > 0 {
                    Text("\(messageCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? FamiliarApp.agentPurple.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agent Detail (right side)

    private var agentDetail: some View {
        VStack(spacing: 0) {
            // Messages
            let filtered = filteredMessages
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    if selectedAgent != nil {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                        Text("\(selectedAgent ?? "") is working...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                        Text("Agents are working...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(filtered) { msg in
                                agentMessageRow(msg)
                            }
                            Color.clear.frame(height: 1).id("detail-bottom")
                        }
                        .padding(14)
                    }
                    .onChange(of: watcher.messages.count) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo("detail-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input for messaging this agent
            HStack(spacing: 8) {
                TextField(
                    selectedAgent.map { "Message \($0)..." } ?? "Message all agents...",
                    text: $inputText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { sendMessage() }

                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(FamiliarApp.agentPurple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var filteredMessages: [InboxMessage] {
        let nonIdle = watcher.messages.filter { !$0.isIdleNotification }
        if let agent = selectedAgent {
            return nonIdle.filter { $0.from == agent }
        }
        return nonIdle
    }

    private func agentMessageRow(_ msg: InboxMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(agentColor(msg.color))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(msg.from)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(Self.timeFormatter.string(from: msg.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Text(msg.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(10)
        .background(agentColor(msg.color).opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let team = watcher.activeTeam else { return }

        let content = inputText
        inputText = ""

        let inboxDir = "\(team.directoryPath)/inboxes"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: inboxDir, withIntermediateDirectories: true)

        let message: [String: Any] = [
            "from": "user",
            "text": content,
            "target": selectedAgent ?? "broadcast",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "color": "gray",
        ]

        let filePath = "\(inboxDir)/user-input.json"
        var existing: [[String: Any]] = []
        if let data = fm.contents(atPath: filePath),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            existing = arr
        }
        existing.append(message)
        if let data = try? JSONSerialization.data(withJSONObject: existing) {
            try? data.write(to: URL(fileURLWithPath: filePath))
        }
    }

    // MARK: - Helpers

    private func nonLeadMembers(_ team: TeamConfig) -> [TeamMember] {
        team.members.filter { $0.agentType != "team-lead" }
    }

    private func iconFor(_ name: String) -> String {
        switch name.lowercased() {
        case "margot": return "paintbrush"
        case "raze": return "scissors"
        case "benji": return "questionmark.bubble"
        default: return "diamond"
        }
    }

    private func agentColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "purple": return FamiliarApp.agentPurple
        case "yellow": return .yellow
        case "pink": return .pink
        case "cyan", "teal": return .teal
        default: return .secondary
        }
    }
}
