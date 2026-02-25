import SwiftUI
import UniformTypeIdentifiers

// MARK: - Date Grouping

private enum SessionGroup: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case older = "Older"
}

private func groupForDate(_ date: Date) -> SessionGroup {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return .today }
    if cal.isDateInYesterday(date) { return .yesterday }
    let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    if date >= weekAgo { return .thisWeek }
    return .older
}

struct SessionSidebar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showSearch = false
    @State private var searchExpanded = false
    @State private var searchText = ""
    @State private var editingSessionId: String?
    @State private var editingName = ""
    @State private var sessionToDelete: Session?
    @State private var showExtensions = false
    @State private var showTimeline = false
    @State private var showKnowledge = false
    @FocusState private var isSearchFocused: Bool

    private var filteredSessions: [Session] {
        if searchText.isEmpty {
            return viewModel.sessions
        }
        return viewModel.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.lastMessage.localizedCaseInsensitiveContains(searchText)
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("accentR") private var accentR = 0.2
    @AppStorage("accentG") private var accentG = 0.62
    @AppStorage("accentB") private var accentB = 0.58
    private var signatureColor: Color { Color(red: accentR, green: accentG, blue: accentB) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // New session button at top
            HStack(spacing: 4) {
                Button(action: { viewModel.newSession() }) {
                    Label("New Session", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(signatureColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Menu {
                    Button("New Session", systemImage: "plus") {
                        viewModel.newSession()
                    }
                    Button("New Worktree Session", systemImage: "arrow.triangle.branch") {
                        viewModel.newWorktreeSession()
                    }
                    .help("Work in an isolated copy of your repo")
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 32)
                        .background(signatureColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ZStack(alignment: .bottom) {
                ScrollView {
                    chatSection
                        .padding(.bottom, 180) // space for menu to float over
                }

                // MARK: Menu items (floating over scroll with blur)
                VStack(alignment: .leading, spacing: 2) {
                    SidebarMenuButton(icon: "clock.arrow.circlepath", label: "Timeline") {
                        showTimeline = true
                    }
                    SidebarMenuButton(icon: "magnifyingglass", label: "Search") {
                        showSearch = true
                    }
                    Button { showExtensions = true } label: {
                        HStack(spacing: 7) {
                            Image("MCPIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .opacity(0.6)
                                .frame(width: 18, alignment: .center)
                            Text("Extensions")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    SidebarMenuButton(icon: "book.closed", label: "Knowledge") {
                        showKnowledge = true
                    }
                    SidebarMenuButton(icon: "gearshape", label: "Settings") {
                        viewModel.showSettings = true
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : TinkerApp.canvasBackground)
                .overlay(alignment: .top) {
                    Divider()
                }
            }

        }
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : TinkerApp.canvasBackground)
        .tint(Color(nsColor: .systemGray))
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    viewModel.deleteSession(session)
                    sessionToDelete = nil
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("\"\(session.name)\" will be permanently deleted.")
            }
        }
        .sheet(isPresented: $showExtensions) {
            ExtensionsView()
                .frame(width: 920, height: 640)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(viewModel: viewModel)
                .frame(width: 920, height: 640)
        }
        .sheet(isPresented: $showTimeline) {
            SessionTimelineView(sessions: viewModel.sessions) { session in
                viewModel.selectSession(session)
            }
            .frame(width: 920, height: 640)
        }
        .sheet(isPresented: $showKnowledge) {
            KnowledgeView(ragService: viewModel.ragService)
                .frame(width: 920, height: 640)
        }
    }

    // MARK: - Chat Section

    private var groupedSessions: [(SessionGroup, [Session])] {
        let dict = Dictionary(grouping: filteredSessions) { groupForDate($0.updatedAt) }
        return SessionGroup.allCases.compactMap { group in
            guard let sessions = dict[group], !sessions.isEmpty else { return nil }
            return (group, sessions)
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session list grouped by date
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groupedSessions, id: \.0) { group, sessions in
                    Text(group.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, group == groupedSessions.first?.0 ? 4 : 12)
                        .padding(.bottom, 4)

                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }

            }
        }
        .padding(.horizontal, 8)
    }

    private func sessionRow(_ session: Session) -> some View {
        SessionRowCompact(
            session: session,
            isSelected: viewModel.currentSession?.id == session.id,
            isEditing: editingSessionId == session.id,
            editingName: $editingName,
            onSelect: { viewModel.selectSession(session) },
            onCommitRename: {
                let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    viewModel.renameSession(session, to: trimmed)
                }
                editingSessionId = nil
            },
            onCancelRename: { editingSessionId = nil }
        )
        .contextMenu {
            Button("Open in Split View") {
                NotificationCenter.default.post(name: .openSplitSession, object: session)
            }
            Divider()
            Button("Rename") {
                editingName = session.name
                editingSessionId = session.id
            }
            Button("Duplicate") {
                viewModel.duplicateSession(session)
            }
            Button("Export as Markdown…") {
                viewModel.exportSessionAsMarkdown(session)
            }
            Divider()
            Button("Delete", role: .destructive) {
                sessionToDelete = session
            }
        }
    }

    // MARK: - Search Section

}

// MARK: - Compact Session Row (for collapsible list)

private struct SessionRowCompact: View {
    let session: Session
    let isSelected: Bool
    var isEditing: Bool = false
    @Binding var editingName: String
    var onSelect: () -> Void = {}
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}
    @State private var isHovered = false

    private var directoryName: String {
        if let dir = session.workingDirectory {
            return (dir as NSString).lastPathComponent
        }
        return ""
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    if isEditing {
                        TextField("Session name", text: $editingName)
                            .font(.body.weight(.medium))
                            .textFieldStyle(.plain)
                            .onSubmit { onCommitRename() }
                            .onExitCommand { onCancelRename() }
                    } else {
                        Text(session.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(session.updatedAt.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    if session.isWorktree {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("Worktree")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(TinkerApp.agentPurple)
                    }
                    if !directoryName.isEmpty {
                        Text(directoryName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.primary.opacity(0.08) :
                isHovered ? Color.primary.opacity(0.04) : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}

// MARK: - Sidebar Menu Button

private struct SidebarMenuButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                Text(label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(isHovered ? Color.primary.opacity(0.06) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}


private extension Date {
    var shortDescription: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: self)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    var sidebarDateTimeDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: self)
    }
}

