import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ChatViewModel
    @State private var searchText = ""
    @State private var selectedRoles: Set<SearchRoleFilter> = Set(SearchRoleFilter.allCases)
    @State private var selectedSession: SearchSessionScope = .current
    @State private var dateFilter: SearchDateFilter = .anytime
    @State private var filterTag: String?
    @State private var filterThreadId: String?
    @FocusState private var isSearchFocused: Bool

    enum SearchRoleFilter: String, CaseIterable, Identifiable {
        case user = "You"
        case assistant = "Assistant"
        case system = "System"
        case tool = "Tools"

        var id: String { rawValue }

        func matches(_ role: MessageRole) -> Bool {
            switch self {
            case .user: return role == .user
            case .assistant: return role == .assistant
            case .system: return role == .system
            case .tool: return role == .toolUse || role == .toolResult || role == .toolError
            }
        }
    }

    enum SearchSessionScope: String, CaseIterable {
        case current = "Current Session"
        case all = "All Sessions"
    }

    enum SearchDateFilter: String, CaseIterable {
        case anytime = "Anytime"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    private var sessionsInScope: [Session] {
        var sessions = viewModel.sessions
        if let tag = filterTag {
            sessions = sessions.filter { $0.tags.contains(tag) }
        }
        if let threadId = filterThreadId {
            sessions = sessions.filter { $0.threadId == threadId }
        }
        return sessions
    }

    private var searchableMessages: [SearchResult] {
        guard !searchText.isEmpty else { return [] }

        switch selectedSession {
        case .current:
            if let current = viewModel.currentSession, passesSessionFilter(current) {
                return filterMessages(
                    viewModel.messages,
                    sessionId: current.id,
                    sessionName: current.name
                )
            }
            return []
        case .all:
            var results: [SearchResult] = []
            for session in sessionsInScope {
                let messages = viewModel.loadMessagesForSplit(sessionId: session.id)
                results.append(contentsOf: filterMessages(messages, sessionId: session.id, sessionName: session.name))
            }
            return results
        }
    }

    /// Sessions whose name or last message match the search text
    private var matchingSessions: [Session] {
        guard !searchText.isEmpty, selectedSession == .all else { return [] }
        return sessionsInScope.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.lastMessage.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func passesSessionFilter(_ session: Session) -> Bool {
        if let tag = filterTag, !session.tags.contains(tag) { return false }
        if let threadId = filterThreadId, session.threadId != threadId { return false }
        return true
    }

    private func filterMessages(_ messages: [ChatMessage], sessionId: String, sessionName: String) -> [SearchResult] {
        messages.compactMap { msg in
            // Role filter
            guard selectedRoles.contains(where: { $0.matches(msg.role) }) else { return nil }

            // Date filter
            if !passesDateFilter(msg.timestamp) { return nil }

            // Text match
            guard msg.content.localizedCaseInsensitiveContains(searchText) else { return nil }

            return SearchResult(message: msg, sessionId: sessionId, sessionName: sessionName)
        }
    }

    private func passesDateFilter(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch dateFilter {
        case .anytime: return true
        case .today: return cal.isDateInToday(date)
        case .thisWeek:
            let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return date >= weekAgo
        case .thisMonth:
            let monthAgo = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return date >= monthAgo
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Search")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                TextField("Search conversations…", text: $searchText)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Filters
            HStack(spacing: 12) {
                // Session scope
                Picker("", selection: $selectedSession) {
                    ForEach(SearchSessionScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                // Date filter
                Picker("", selection: $dateFilter) {
                    ForEach(SearchDateFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 120)

                Spacer()

                // Role filters
                HStack(spacing: 4) {
                    ForEach(SearchRoleFilter.allCases) { role in
                        Toggle(role.rawValue, isOn: Binding(
                            get: { selectedRoles.contains(role) },
                            set: { isOn in
                                if isOn { selectedRoles.insert(role) }
                                else { selectedRoles.remove(role) }
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 4)

            // Tag and thread filters
            if !viewModel.allTags.isEmpty || !viewModel.threads.isEmpty {
                HStack(spacing: 6) {
                    if !viewModel.threads.isEmpty {
                        Menu {
                            Button("All Threads") { filterThreadId = nil }
                            Divider()
                            ForEach(viewModel.threads) { thread in
                                Button {
                                    filterThreadId = thread.id
                                } label: {
                                    HStack {
                                        Text(thread.name)
                                        if filterThreadId == thread.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 9))
                                Text(filterThreadId.flatMap { id in viewModel.threads.first { $0.id == id }?.name } ?? "All Threads")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(filterThreadId != nil ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if !viewModel.allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(viewModel.allTags, id: \.self) { tag in
                                    Button {
                                        filterTag = filterTag == tag ? nil : tag
                                    } label: {
                                        Text(tag)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(filterTag == tag ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                                            .foregroundStyle(filterTag == tag ? .primary : .secondary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            Divider()

            // Results
            if searchText.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Search your conversations")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Filter by session, date, tag, thread, and message type")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if searchableMessages.isEmpty && matchingSessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No results for \"\(searchText)\"")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                let totalCount = searchableMessages.count + matchingSessions.count
                HStack {
                    Text("\(totalCount) result\(totalCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Session matches (when searching all)
                        if !matchingSessions.isEmpty {
                            Text("Sessions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.top, 4)
                                .padding(.bottom, 2)

                            ForEach(matchingSessions) { session in
                                SessionSearchRow(session: session) {
                                    viewModel.selectSession(session)
                                    dismiss()
                                }
                            }
                        }

                        // Message matches
                        if !searchableMessages.isEmpty {
                            if !matchingSessions.isEmpty {
                                Text("Messages")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 12)
                                    .padding(.bottom, 2)
                            }

                            ForEach(searchableMessages) { result in
                                SearchResultRow(
                                    result: result,
                                    searchText: searchText,
                                    onNavigate: {
                                        if let session = viewModel.sessions.first(where: { $0.id == result.sessionId }) {
                                            viewModel.selectSession(session)
                                        }
                                        dismiss()
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(TinkerApp.canvasBackground)
        .onAppear { isSearchFocused = true }
    }
}

// MARK: - Session Search Row

private struct SessionSearchRow: View {
    let session: Session
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !session.lastMessage.isEmpty {
                        Text(session.lastMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(session.updatedAt.shortSearchDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(isHovered ? Color.primary.opacity(0.04) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 30)
        }
    }
}

// MARK: - Search Result Model

struct SearchResult: Identifiable {
    let id = UUID()
    let message: ChatMessage
    let sessionId: String
    let sessionName: String
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let searchText: String
    let onNavigate: () -> Void
    @State private var isHovered = false

    private var roleIcon: String {
        switch result.message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkle"
        case .system: return "gearshape"
        case .toolUse, .toolResult, .toolError: return "wrench"
        case .thinking: return "brain"
        }
    }

    private var roleLabel: String {
        switch result.message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .toolUse: return "Tool Use"
        case .toolResult: return "Tool Result"
        case .toolError: return "Tool Error"
        case .thinking: return "Thinking"
        }
    }

    var body: some View {
        Button(action: onNavigate) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: roleIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(roleLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(result.sessionName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Text(result.message.timestamp.shortSearchDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Show matching content with highlight
                Text(highlightedSnippet)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isHovered ? Color.primary.opacity(0.04) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 26)
        }
    }

    private var highlightedSnippet: AttributedString {
        let content = result.message.content
        // Find the match location and show surrounding context
        guard let range = content.range(of: searchText, options: .caseInsensitive) else {
            let prefix = String(content.prefix(200))
            return AttributedString(prefix)
        }

        let matchStart = content.distance(from: content.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - 60)
        let startIdx = content.index(content.startIndex, offsetBy: snippetStart)
        let endIdx = content.index(startIdx, offsetBy: min(250, content.distance(from: startIdx, to: content.endIndex)))
        var snippet = String(content[startIdx..<endIdx])
        if snippetStart > 0 { snippet = "…" + snippet }
        if endIdx < content.endIndex { snippet += "…" }

        var attributed = AttributedString(snippet)
        // Bold the search term matches
        if let attrRange = attributed.range(of: searchText, options: .caseInsensitive) {
            attributed[attrRange].font = .callout.bold()
            attributed[attrRange].foregroundColor = TinkerApp.accent
        }
        return attributed
    }
}

// MARK: - Date Extension

private extension Date {
    var shortSearchDescription: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, " + formatter.string(from: self)
        }
        if cal.isDateInYesterday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday, " + formatter.string(from: self)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }
}
