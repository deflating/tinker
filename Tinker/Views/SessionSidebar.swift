import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sort Mode

enum SessionSortMode: String, CaseIterable {
    case threads = "Threads"
    case date = "Date"
}

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
    @State private var showThreadManager = false
    @State private var collapsedThreads: Set<String> = []
    @State private var showAddTagAlert = false
    @State private var newTagText = ""
    @State private var tagTargetSession: Session?
    @AppStorage("sessionSortMode") private var sortMode: String = SessionSortMode.threads.rawValue
    @FocusState private var isSearchFocused: Bool

    private var currentSortMode: SessionSortMode {
        SessionSortMode(rawValue: sortMode) ?? .threads
    }

    private var filteredSessions: [Session] {
        var result = viewModel.sessions
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.lastMessage.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return result
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

            // Sort mode
            sortModePicker
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            ZStack(alignment: .bottom) {
                ScrollView {
                    chatSection
                        .padding(.bottom, 180)
                }

                // MARK: Menu items (floating over scroll with blur)
                VStack(alignment: .leading, spacing: 2) {
                    SidebarMenuButton(icon: "clock.arrow.circlepath", label: "Timeline") {
                        showTimeline = true
                    }
                    SidebarMenuButton(icon: "magnifyingglass", label: "Search") {
                        showSearch = true
                    }
                    SidebarMenuButton(icon: "text.line.first.and.arrowtriangle.forward", label: "Threads") {
                        showThreadManager = true
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
        .alert("Add Tag", isPresented: $showAddTagAlert) {
            TextField("Tag name", text: $newTagText)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                if let session = tagTargetSession {
                    viewModel.addTag(newTagText, to: session)
                }
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
        .sheet(isPresented: $showThreadManager) {
            ThreadManagerView(viewModel: viewModel)
                .frame(width: 500, height: 400)
        }
    }

    // MARK: - Sort Mode Picker

    private var sortModePicker: some View {
        HStack(spacing: 2) {
            ForEach(SessionSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode.rawValue
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(currentSortMode == mode ? signatureColor.opacity(0.2) : Color.primary.opacity(0.06))
                        .foregroundStyle(currentSortMode == mode ? signatureColor : .secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chat Section

    private var pinnedSessions: [Session] {
        filteredSessions.filter(\.isPinned)
    }

    private var unpinnedSessions: [Session] {
        filteredSessions.filter { !$0.isPinned }
    }

    /// Sessions assigned to threads
    private var threadedSessions: [(SessionThread, [Session])] {
        let unthreaded = unpinnedSessions
        return viewModel.threads.compactMap { thread in
            let sessions = unthreaded.filter { $0.threadId == thread.id }
            guard !sessions.isEmpty else { return nil }
            return (thread, sessions)
        }
    }

    /// Sessions not pinned and not in any thread, grouped by date
    private var ungroupedSessions: [Session] {
        unpinnedSessions.filter { $0.threadId == nil }
    }

    private var groupedUngrouped: [(SessionGroup, [Session])] {
        let dict = Dictionary(grouping: ungroupedSessions) { groupForDate($0.updatedAt) }
        return SessionGroup.allCases.compactMap { group in
            guard let sessions = dict[group], !sessions.isEmpty else { return nil }
            return (group, sessions)
        }
    }

    /// All sessions grouped by date (for flat date mode)
    private var allByDate: [(SessionGroup, [Session])] {
        let unpinned = filteredSessions.filter { !$0.isPinned }
        let dict = Dictionary(grouping: unpinned) { groupForDate($0.updatedAt) }
        return SessionGroup.allCases.compactMap { group in
            guard let sessions = dict[group], !sessions.isEmpty else { return nil }
            return (group, sessions)
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned always at top
            if !pinnedSessions.isEmpty {
                sectionHeader("Pinned", icon: "pin.fill")
                ForEach(pinnedSessions) { session in
                    sessionRow(session)
                }
            }

            if currentSortMode == .threads {
                // Threaded groups
                ForEach(threadedSessions, id: \.0.id) { thread, sessions in
                    threadSection(thread: thread, sessions: sessions)
                }

                // Ungrouped by date
                ForEach(groupedUngrouped, id: \.0) { group, sessions in
                    Text(group.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            } else {
                // Flat date view — all unpinned sessions by date, ignoring threads
                ForEach(allByDate, id: \.0) { group, sessions in
                    Text(group.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func threadSection(thread: SessionThread, sessions: [Session]) -> some View {
        let isCollapsed = collapsedThreads.contains(thread.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedThreads.remove(thread.id)
                    } else {
                        collapsedThreads.insert(thread.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                    Circle()
                        .fill(threadColor(thread.color))
                        .frame(width: 6, height: 6)
                    Text(thread.name)
                        .font(.caption.weight(.medium))
                    Text("\(sessions.count)")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if !isCollapsed {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        SessionRowCompact(
            session: session,
            thread: viewModel.thread(for: session),
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
            // Pin/unpin
            Button(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin") {
                viewModel.togglePin(session)
            }

            Divider()

            // Thread assignment
            Menu("Thread") {
                Button("None") {
                    viewModel.assignThread(nil, to: session)
                }
                Divider()
                ForEach(viewModel.threads) { thread in
                    Button {
                        viewModel.assignThread(thread, to: session)
                    } label: {
                        HStack {
                            Circle()
                                .fill(threadColor(thread.color))
                                .frame(width: 8, height: 8)
                            Text(thread.name)
                            if session.threadId == thread.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("New Thread…", systemImage: "plus") {
                    showThreadManager = true
                }
            }

            // Tags
            Menu("Tags") {
                ForEach(viewModel.allTags, id: \.self) { tag in
                    Button {
                        if session.tags.contains(tag) {
                            viewModel.removeTag(tag, from: session)
                        } else {
                            viewModel.addTag(tag, to: session)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                            if session.tags.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if !viewModel.allTags.isEmpty { Divider() }
                Button("Add Tag…", systemImage: "plus") {
                    newTagText = ""
                    tagTargetSession = session
                    showAddTagAlert = true
                }
            }

            Divider()

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

// MARK: - Thread Color Helper

func threadColor(_ name: String) -> Color {
    switch name {
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "teal": return .teal
    case "cyan": return .cyan
    case "indigo": return .indigo
    default: return .blue
    }
}

// MARK: - Compact Session Row

private struct SessionRowCompact: View {
    let session: Session
    var thread: SessionThread?
    let isSelected: Bool
    var isEditing: Bool = false
    @Binding var editingName: String
    var onSelect: () -> Void = {}
    var onCommitRename: () -> Void = {}
    var onCancelRename: () -> Void = {}
    @State private var isHovered = false
    @State private var showTagInput = false
    @State private var newTag = ""

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
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
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

                // Tags
                if !session.tags.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(session.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(.secondary)
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
