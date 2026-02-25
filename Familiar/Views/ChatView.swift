import SwiftUI
import UniformTypeIdentifiers
import AppKit
import UserNotifications

struct AttachedFile: Identifiable {
    let id = UUID()
    let path: String
    var filename: String { (path as NSString).lastPathComponent }
    var isImage: Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp", "svg", "ico"].contains(ext)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private extension String {
    var abbreviatingWithTilde: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - Message Grouping

private enum MessageSegment: Identifiable {
    case single(ChatMessage)
    case toolGroup([ChatMessage])

    var id: String {
        switch self {
        case .single(let msg): return msg.id.uuidString
        case .toolGroup(let msgs): return "tg-" + (msgs.first?.id.uuidString ?? UUID().uuidString)
        }
    }
}

private func groupMessages(_ messages: [ChatMessage]) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    var toolBuffer: [ChatMessage] = []

    func flushTools() {
        if !toolBuffer.isEmpty {
            segments.append(.toolGroup(toolBuffer))
            toolBuffer = []
        }
    }

    for msg in messages {
        switch msg.role {
        case .toolUse, .toolResult, .toolError:
            toolBuffer.append(msg)
        default:
            flushTools()
            segments.append(.single(msg))
        }
    }
    flushTools()
    return segments
}

struct BlueprintGridBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let minorSpacing: CGFloat = 24

                var minor = Path()
                stride(from: CGFloat(0), through: size.width, by: minorSpacing).forEach { x in
                    minor.move(to: CGPoint(x: x, y: 0))
                    minor.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: minorSpacing).forEach { y in
                    minor.move(to: CGPoint(x: 0, y: y))
                    minor.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(minor, with: .color(Color.black.opacity(0.05)), lineWidth: 0.5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var agentTeamWatcher: AgentTeamWatcher?
    @State private var messageText = ""
    @State private var cachedSegments: [MessageSegment] = []
    @State private var cachedMessageCount = 0
    @FocusState private var isInputFocused: Bool
    @State private var showSlashMenu = false
    @State private var slashFilter = ""
    @State private var slashSelectedIndex = 0
    @State private var allSlashCommands: [SlashCommand] = SlashCommand.allCommands()
    @State private var showFileMention = false
    @State private var fileMentionFilter = ""
    @State private var fileMentionSelectedIndex = 0
    @State private var fileMentionResults: [String] = []
    @State private var showSearchBar = false
    @State private var showAgentTeamSheet = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isDragOver = false
    @State private var scrollWork: DispatchWorkItem?
    @State private var terminalSnippets: [TerminalSnippet] = []
    @State private var attachedFiles: [AttachedFile] = []
    @AppStorage("accentR") private var accentR = 0.2
    @AppStorage("accentG") private var accentG = 0.62
    @AppStorage("accentB") private var accentB = 0.58

    private var searchMatchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        return viewModel.messages.filter { $0.content.localizedCaseInsensitiveContains(searchText) }.count
    }

    private var filteredSlashCommands: [SlashCommand] {
        if slashFilter.isEmpty { return allSlashCommands }
        return allSlashCommands.filter { $0.name.localizedCaseInsensitiveContains(slashFilter) }
    }

    private var projectName: String {
        (viewModel.workingDirectory as NSString).lastPathComponent
    }

    private var selectedModelLabel: String {
        ChatViewModel.availableModels.first(where: { $0.0 == viewModel.selectedModel })?.1 ?? "Sonnet 4.6"
    }

    private var selectedPermissionLabel: String {
        ChatViewModel.availablePermissionModes.first(where: { $0.0 == viewModel.selectedPermissionMode })?.1 ?? "Default"
    }

    private var selectedPermissionIcon: String {
        ChatViewModel.availablePermissionModes.first(where: { $0.0 == viewModel.selectedPermissionMode })?.2 ?? "shield.checkered"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            if showSearchBar {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Find in conversation…", text: $searchText)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onExitCommand {
                            showSearchBar = false
                            searchText = ""
                            isInputFocused = true
                        }
                    if !searchText.isEmpty {
                        Text("\(searchMatchCount) match\(searchMatchCount == 1 ? "" : "es")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button(action: {
                        showSearchBar = false
                        searchText = ""
                        isInputFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(TinkerApp.canvasBackground.opacity(0.92))
                Divider()
            }

            // Messages or empty state
            if viewModel.messages.isEmpty {
                EmptyStateView(viewModel: viewModel) {
                    HStack(alignment: .bottom, spacing: 8) {
                        composerOverflowMenu
                            .padding(.bottom, 30)
                        emptyStateInputCard
                    }
                    .frame(maxWidth: 760)
                }
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {

                        ForEach(cachedSegments) { segment in
                            switch segment {
                            case .single(let message):
                                let isMatch = !searchText.isEmpty && message.content.localizedCaseInsensitiveContains(searchText)
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(TinkerApp.accent, lineWidth: isMatch ? 1.5 : 0)
                                            .opacity(isMatch ? 1 : 0)
                                    )
                                    .opacity(!searchText.isEmpty && !isMatch ? 0.4 : 1)
                            case .toolGroup(let tools):
                                let hasMatch = !searchText.isEmpty && tools.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
                                let agentTools: Set = ["Task", "TeamCreate", "SendMessage", "TeamDelete"]
                                let hasAgents = tools.contains { agentTools.contains($0.toolName ?? "") }
                                Group {
                                    if hasAgents {
                                        AgentTeamView(tools: tools)
                                            .frame(maxWidth: 500, alignment: .leading)
                                    } else {
                                        ToolGroupView(tools: tools)
                                            .frame(maxWidth: 500, alignment: .leading)
                                    }
                                }
                                    .id(tools.first?.id)
                                    .transition(.opacity.combined(with: .offset(y: 8)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(TinkerApp.accent, lineWidth: hasMatch ? 1.5 : 0)
                                            .opacity(hasMatch ? 1 : 0)
                                    )
                                    .opacity(!searchText.isEmpty && !hasMatch ? 0.4 : 1)
                            }
                        }
                    }
                    .padding(.leading, 48)
                    .padding(.trailing, 28)
                    .padding(.vertical, 16)
                    .padding(.top, 8)

                    // Invisible spacer so scrolling to "bottom-anchor" clears the fade + input area
                    Color.clear
                        .frame(height: 60)
                        .id("bottom-anchor")
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    cachedSegments = groupMessages(viewModel.messages)
                    cachedMessageCount = viewModel.messages.count
                    if viewModel.messages.last != nil {
                        debouncedScroll(proxy: proxy, delay: 0.1, animated: false)
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    cachedSegments = groupMessages(viewModel.messages)
                    cachedMessageCount = viewModel.messages.count
                    debouncedScroll(proxy: proxy, delay: 0.05, animated: true)
                }
                .onChange(of: viewModel.messages.last?.content) {
                    cachedSegments = groupMessages(viewModel.messages)
                    cachedMessageCount = viewModel.messages.count
                    // Streaming content can update rapidly; coalesce scroll work.
                    debouncedScroll(proxy: proxy, delay: 0.03, animated: false)
                }
                .onChange(of: viewModel.messages.last?.isComplete) {
                    cachedSegments = groupMessages(viewModel.messages)
                    cachedMessageCount = viewModel.messages.count
                    // After completion, reflow may change layout — one delayed scroll
                    debouncedScroll(proxy: proxy, delay: 0.15, animated: false)
                }
                .onChange(of: viewModel.currentSession?.id) {
                    cachedSegments = groupMessages(viewModel.messages)
                    cachedMessageCount = viewModel.messages.count
                    // Session switch — single delayed scroll for layout
                    debouncedScroll(proxy: proxy, delay: 0.1, animated: false)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .top) {
                // Feather the harsh toolbar divider line
                LinearGradient(
                    colors: [TinkerApp.canvasBackground, TinkerApp.canvasBackground.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                // Soft gradient fade at bottom of conversation
                LinearGradient(
                    colors: [TinkerApp.canvasBackground.opacity(0), TinkerApp.canvasBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)
            }
            } // end else (has messages)

            // Error banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error.localizedDescription)
                        .font(.callout)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") { viewModel.error = nil }
                        .font(.callout)
                        .buttonStyle(.borderless)
                }
                .padding(10)
                .background(.red.opacity(0.1))
            }

            if !viewModel.messages.isEmpty {
            // Status bar
            StatusBar(viewModel: viewModel)
                .padding(.top, 12)
                .padding(.bottom, 10)

            // Input area
            ZStack(alignment: .bottomLeading) {
                if showSlashMenu && !filteredSlashCommands.isEmpty {
                    SlashCommandMenu(
                        commands: filteredSlashCommands,
                        selectedIndex: slashSelectedIndex,
                        onSelect: { insertSlashCommand($0) }
                    )
                    .offset(x: 12, y: -4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
                }

                if showFileMention && !fileMentionResults.isEmpty {
                    FileMentionMenu(
                        files: fileMentionResults,
                        selectedIndex: fileMentionSelectedIndex,
                        onSelect: { insertFileMention($0) }
                    )
                    .offset(x: 12, y: -4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    composerOverflowMenu
                        .padding(.bottom, 34)
                    inputCard
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }

            // Message queue (visible when messages are queued)
            if !viewModel.messageQueue.isEmpty {
                MessageQueueView(viewModel: viewModel)
                    .padding(.horizontal, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            } // end if has messages (bottom input)
        }
        .background(TinkerApp.canvasBackground)
        .sheet(isPresented: $showAgentTeamSheet) {
            if let watcher = agentTeamWatcher {
                AgentTeamSheetView(watcher: watcher)
                    .frame(width: 600, height: 500)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TinkerApp.accent, lineWidth: 2)
                .opacity(isDragOver ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isDragOver)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleFileDrop(providers)
        }
        .onAppear { isInputFocused = true }
        .onDisappear {
            scrollWork?.cancel()
            scrollWork = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInConversation)) { _ in
            showSearchBar = true
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInputField)) { _ in
            isInputFocused = true
        }
    }


    private var sessionHasAgentTeam: Bool {
        guard let watcher = agentTeamWatcher, watcher.hasActiveTeam else { return false }
        return viewModel.messages.contains { $0.toolName == "TeamCreate" }
    }

    private var inputCard: some View {
        inputCardView(style: .inline)
    }

    private var emptyStateInputCard: some View {
        inputCardView(style: .emptyState)
    }

    private enum InputCardStyle {
        case inline, emptyState

        var snippetPaddingH: CGFloat { self == .inline ? 10 : 14 }
        var snippetPaddingTop: CGFloat { self == .inline ? 10 : 14 }
        var textPaddingH: CGFloat { self == .inline ? 28 : 18 }
        var textPaddingTop: CGFloat { self == .inline ? 24 : 16 }
        var textPaddingBottom: CGFloat { self == .inline ? 18 : 12 }
        var bottomHSpacing: CGFloat { self == .inline ? 8 : 10 }
        var bottomPaddingH: CGFloat { self == .inline ? 26 : 16 }
        var bottomPaddingBottom: CGFloat { self == .inline ? 18 : 14 }
        var buttonSize: CGFloat { self == .inline ? 22 : 24 }
        var cornerRadius: CGFloat { self == .inline ? 18 : 24 }
        var shadowOpacity: Double { self == .inline ? 0.08 : 0.14 }
        var shadowRadius: CGFloat { self == .inline ? 10 : 20 }
        var shadowY: CGFloat { self == .inline ? 4 : 10 }
    }

    private func debouncedScroll(proxy: ScrollViewProxy, delay: Double, animated: Bool) {
        scrollWork?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
        scrollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func inputCardView(style: InputCardStyle) -> some View {
        VStack(spacing: 0) {
            // Terminal snippets
            if !terminalSnippets.isEmpty {
                VStack(spacing: 6) {
                    ForEach($terminalSnippets) { $snippet in
                        TerminalSnippetView(snippet: $snippet) {
                            removeTerminalSnippet(snippet)
                        }
                    }
                }
                .padding(.horizontal, style.snippetPaddingH)
                .padding(.top, style.snippetPaddingTop)
            }

            // Attached file chips
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedFiles) { file in
                            AttachedFileChip(file: file) {
                                attachedFiles.removeAll { $0.id == file.id }
                            }
                        }
                    }
                    .padding(.horizontal, style.textPaddingH)
                    .padding(.top, 8)
                }
            }

            TextField("Ask anything, @ to add files, / for commands", text: $messageText, axis: .vertical)
                .font(.body)
                .textFieldStyle(.plain)
                .lineLimit(1...12)
                .focused($isInputFocused)
                .onKeyPress(.return) {
                    if NSEvent.modifierFlags.contains(.shift) {
                        messageText += "\n"
                        return .handled
                    }
                    if showSlashMenu && !filteredSlashCommands.isEmpty {
                        let cmd = filteredSlashCommands[min(slashSelectedIndex, filteredSlashCommands.count - 1)]
                        insertSlashCommand(cmd)
                    } else if showFileMention && !fileMentionResults.isEmpty {
                        insertFileMention(fileMentionResults[min(fileMentionSelectedIndex, fileMentionResults.count - 1)])
                    } else {
                        sendMessage()
                    }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if showSlashMenu && !filteredSlashCommands.isEmpty {
                        slashSelectedIndex = max(0, slashSelectedIndex - 1)
                        return .handled
                    }
                    if showFileMention && !fileMentionResults.isEmpty {
                        fileMentionSelectedIndex = max(0, fileMentionSelectedIndex - 1)
                        return .handled
                    }
                    if messageText.isEmpty && !viewModel.lastSentMessage.isEmpty {
                        messageText = viewModel.lastSentMessage
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if showSlashMenu && !filteredSlashCommands.isEmpty {
                        slashSelectedIndex = min(filteredSlashCommands.count - 1, slashSelectedIndex + 1)
                        return .handled
                    }
                    if showFileMention && !fileMentionResults.isEmpty {
                        fileMentionSelectedIndex = min(fileMentionResults.count - 1, fileMentionSelectedIndex + 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if showSlashMenu {
                        showSlashMenu = false
                        return .handled
                    }
                    if showFileMention {
                        showFileMention = false
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.tab) {
                    if showFileMention && !fileMentionResults.isEmpty {
                        insertFileMention(fileMentionResults[min(fileMentionSelectedIndex, fileMentionResults.count - 1)])
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: messageText) {
                    updateSlashMenu()
                    updateFileMention()
                }
                .padding(.horizontal, style.textPaddingH)
                .padding(.top, style.textPaddingTop)
                .padding(.bottom, style.textPaddingBottom)

            HStack(spacing: style.bottomHSpacing) {
                Menu {
                    ForEach(ChatViewModel.availableModels, id: \.0) { modelId, label in
                        Button {
                            viewModel.selectedModel = modelId
                        } label: {
                            HStack {
                                Text(label)
                                if viewModel.selectedModel == modelId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(selectedModelLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                permissionModeMenu

                directorySelector

                Spacer()

                if sessionHasAgentTeam {
                    Button { showAgentTeamSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 8))
                            Text("Agent Team")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TinkerApp.agentPurple)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading {
                    Button(action: { viewModel.cancelRequest() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: style.buttonSize))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel request")
                    .help("Cancel request (Esc)")
                } else {
                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: style.buttonSize))
                            .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFiles.isEmpty ? .gray : TinkerApp.accent)
                            .animation(.easeOut(duration: 0.15), value: messageText.isEmpty)
                    }
                    .buttonStyle(.borderless)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedFiles.isEmpty)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.horizontal, style.bottomPaddingH)
            .padding(.bottom, style.bottomPaddingBottom)
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = true }
        .background {
            liquidGlassFill(cornerRadius: style.cornerRadius)
        }
        .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, y: style.shadowY)
    }

    private var permissionModeMenu: some View {
        Menu {
            ForEach(ChatViewModel.availablePermissionModes, id: \.0) { modeId, label, icon in
                Button {
                    viewModel.selectedPermissionMode = modeId
                } label: {
                    HStack {
                        Image(systemName: icon)
                        Text(label)
                        if viewModel.selectedPermissionMode == modeId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: selectedPermissionIcon)
                    .font(.caption)
                Text(selectedPermissionLabel)
                    .font(.callout)
            }
            .foregroundStyle(viewModel.selectedPermissionMode == "bypassPermissions" ? .orange : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var directorySelector: some View {
        HStack(spacing: 6) {
            Button(action: { viewModel.pickWorkingDirectory() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(projectName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(TinkerApp.accent)
            .help("Click to change working directory")
            .accessibilityLabel("Change working directory")
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var composerOverflowMenu: some View {
        Menu {
            Button("Add Photos & Files", systemImage: "photo.on.rectangle") {
                presentAttachmentPicker(canChooseFiles: true, canChooseDirectories: false)
            }
            Button("Add Folder", systemImage: "folder.badge.plus") {
                presentAttachmentPicker(canChooseFiles: false, canChooseDirectories: true)
            }
            Button("Add Terminal Command", systemImage: "terminal") {
                addTerminalSnippet()
            }
            Divider()
            Button("Open in Terminal", systemImage: "terminal") {
                NSWorkspace.shared.open(
                    [URL(fileURLWithPath: viewModel.workingDirectory)],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            Button("Change Working Directory", systemImage: "folder") {
                viewModel.pickWorkingDirectory()
            }
            Button("Clear Draft", systemImage: "xmark.circle") {
                messageText = ""
            }
        } label: {
            Image(systemName: "plus")
                .resizable()
                .frame(width: 24, height: 24)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 40, height: 40)
        .accessibilityLabel("Composer actions")
    }

    @ViewBuilder
    private func liquidGlassFill(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func circularGlassFill() -> some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
        }
    }

    private func updateSlashMenu() {
        if messageText.hasPrefix("/") && !messageText.contains(" ") {
            slashFilter = messageText
            slashSelectedIndex = 0
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showSlashMenu = true
            }
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showSlashMenu = false
            }
        }
    }

    private func insertSlashCommand(_ command: SlashCommand) {
        showSlashMenu = false
        // Handle built-in commands directly
        switch command.id {
        case "clear":
            viewModel.clearConversation()
            messageText = ""
        case "compact":
            messageText = ""
            // Add a system message so the user knows what happened
            viewModel.messages.append(ChatMessage(role: .system, content: "Compacting conversation context…"))
            viewModel.sendMessage("/compact")
        case "help":
            messageText = ""
            viewModel.sendMessage("/help")
        default:
            // Agent commands — insert and let user add a prompt
            messageText = command.name + " "
        }
    }

    private func updateFileMention() {
        // Look for @ trigger — find the last @ in the text
        guard let atRange = messageText.range(of: "@", options: .backwards) else {
            showFileMention = false
            return
        }

        let afterAt = String(messageText[atRange.upperBound...])

        // Don't trigger if there's a space before content (completed mention)
        // or if @ is followed by nothing useful
        if afterAt.contains("\n") {
            showFileMention = false
            return
        }

        let query = afterAt.trimmingCharacters(in: .whitespaces)
        if query.isEmpty && messageText.hasSuffix("@") {
            // Just typed @, show recent/common files
            fileMentionFilter = ""
            fileMentionSelectedIndex = 0
            loadFileSuggestions("")
            showFileMention = true
        } else if !query.isEmpty && !afterAt.hasPrefix(" ") {
            fileMentionFilter = query
            fileMentionSelectedIndex = 0
            loadFileSuggestions(query)
            showFileMention = !fileMentionResults.isEmpty
        } else {
            showFileMention = false
        }
    }

    private func loadFileSuggestions(_ query: String) {
        let dir = viewModel.workingDirectory
        Task.detached {
            let found = Self.searchFiles(in: dir, query: query)
            await MainActor.run {
                self.fileMentionResults = found
            }
        }
    }

    private static func searchFiles(in dir: String, query: String) -> [String] {
        let fm = FileManager.default
        if query.isEmpty {
            if let contents = try? fm.contentsOfDirectory(atPath: dir) {
                return Array(contents.filter { !$0.hasPrefix(".") }.sorted().prefix(10))
            }
            return []
        }

        var results: [String] = []
        guard let enumerator = fm.enumerator(atPath: dir) else { return [] }
        while let file = enumerator.nextObject() as? String {
            if file.contains("/.") || file.hasPrefix(".") {
                if file.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            let skipDirs = ["node_modules", ".git", ".build", "DerivedData", "__pycache__"]
            if skipDirs.contains(where: { file.hasPrefix($0 + "/") || file == $0 }) {
                enumerator.skipDescendants()
                continue
            }
            let filename = (file as NSString).lastPathComponent
            if filename.localizedCaseInsensitiveContains(query) || file.localizedCaseInsensitiveContains(query) {
                results.append(file)
                if results.count >= 10 { break }
            }
        }
        return results
    }

    private func insertFileMention(_ file: String) {
        // Replace @query with the full path
        if let atRange = messageText.range(of: "@", options: .backwards) {
            let fullPath = (viewModel.workingDirectory as NSString).appendingPathComponent(file)
            messageText = String(messageText[..<atRange.lowerBound]) + fullPath + " "
        }
        showFileMention = false
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        var paths: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                lock.lock()
                paths.append(url.path)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            appendPathsToComposer(paths)
        }
        return true
    }

    private func presentAttachmentPicker(canChooseFiles: Bool, canChooseDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.begin { response in
            guard response == .OK else { return }
            let paths = panel.urls.map(\.path)
            appendPathsToComposer(paths)
        }
    }

    private func appendPathsToComposer(_ paths: [String]) {
        guard !paths.isEmpty else { return }

        var parts: [String] = []
        if !messageText.isEmpty {
            parts.append(messageText)
        }

        for path in paths {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            let textExtensions: Set<String> = [
                "txt", "md", "markdown", "json", "yaml", "yml", "toml", "xml", "csv", "tsv",
                "swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "rb", "java", "kt",
                "c", "h", "cpp", "hpp", "cs", "m", "mm", "sh", "bash", "zsh", "fish",
                "html", "css", "scss", "less", "sql", "graphql", "proto",
                "env", "ini", "cfg", "conf", "log", "diff", "patch",
                "r", "R", "lua", "zig", "nim", "dart", "scala", "clj", "ex", "exs",
                "vue", "svelte", "astro", "mdx", "rst", "tex", "bib"
            ]
            let isText = textExtensions.contains(ext) || ext.isEmpty

            if isText, let contents = try? String(contentsOfFile: path, encoding: .utf8),
               contents.count < 200_000 {
                let filename = url.lastPathComponent
                parts.append("File: \(filename)\n```\n\(contents)\n```")
            } else {
                // Binary or too large — show as attached file chip
                attachedFiles.append(AttachedFile(path: path))
            }
        }

        messageText = parts.joined(separator: "\n\n")
        isInputFocused = true
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSnippets = !terminalSnippets.isEmpty
        let hasAttachments = !attachedFiles.isEmpty
        guard !text.isEmpty || hasSnippets || hasAttachments else { return }

        // Build final message with snippets appended as code blocks
        var finalMessage = text
        for snippet in terminalSnippets {
            let trimmed = snippet.command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !finalMessage.isEmpty { finalMessage += "\n\n" }
            finalMessage += "```bash\n\(trimmed)\n```"
        }

        // Append attached file paths
        for file in attachedFiles {
            if !finalMessage.isEmpty { finalMessage += "\n\n" }
            finalMessage += file.path
        }

        guard !finalMessage.isEmpty else { return }
        viewModel.sendMessage(finalMessage)
        messageText = ""
        terminalSnippets = []
        attachedFiles = []
    }

    private func addTerminalSnippet() {
        terminalSnippets.append(TerminalSnippet())
    }

    private func removeTerminalSnippet(_ snippet: TerminalSnippet) {
        terminalSnippets.removeAll { $0.id == snippet.id }
    }
}

// MARK: - Terminal Snippet

struct TerminalSnippet: Identifiable {
    let id = UUID()
    var command: String = ""
}

struct TerminalSnippetView: View {
    @Binding var snippet: TerminalSnippet
    let onRemove: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("$")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.4, green: 0.82, blue: 0.35))
                .padding(.leading, 10)
                .padding(.top, 8)

            TextField("command", text: $snippet.command, axis: .vertical)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isFocused)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { isFocused = true }
    }
}

// MARK: - Message Queue View

struct MessageQueueView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "tray.full")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Queued (\(viewModel.messageQueue.count))")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { viewModel.messageQueue.removeAll() }) {
                    Text("Clear")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ForEach(Array(viewModel.messageQueue.enumerated()), id: \.element.id) { index, message in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)

                    Text(message.text)
                        .font(.callout)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Move up
                    if index > 0 {
                        Button(action: { viewModel.moveQueuedMessage(from: index, to: index - 1) }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Remove
                    Button(action: { viewModel.removeFromQueue(message) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Chat Toolbar (Native Title Bar)

struct ChatToolbarTerminal: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .frame(width: 26, height: 26, alignment: .center)
                .foregroundStyle(isOpen ? TinkerApp.accent : .secondary)
        }
        .help(isOpen ? "Hide terminal pane" : "Show terminal pane")
        .accessibilityLabel(isOpen ? "Hide terminal pane" : "Show terminal pane")
    }
}

struct ChatToolbarLeading: View {
    @Bindable var viewModel: ChatViewModel

    private var projectName: String {
        (viewModel.workingDirectory as NSString).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { viewModel.pickWorkingDirectory() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(projectName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)

            Button(action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: viewModel.workingDirectory))
            }) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10))
                    .frame(width: 26, height: 26, alignment: .center)
            }
            .help("Open in Finder")
            .accessibilityLabel("Open in Finder")

            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.workingDirectory, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .frame(width: 26, height: 26, alignment: .center)
            }
            .help("Copy Path")
            .accessibilityLabel("Copy path")

            // Worktree badge
            if viewModel.currentSession?.isWorktree == true {
                Text("·")
                    .foregroundStyle(.quaternary)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                        .foregroundStyle(TinkerApp.agentPurple)
                    Text("Worktree")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TinkerApp.agentPurple)
                }
            }
        }
    }
}

// MARK: - Git Toolbar (Codex-style)

struct GitToolbarView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showCommitSheet = false

    var body: some View {
        HStack(spacing: 6) {
            // Commit dropdown
            Menu {
                Button(action: { showCommitSheet = true }) {
                    Label("Commit", systemImage: "checkmark.circle")
                }
                Button(action: {
                    Task { await viewModel.gitService.push(in: viewModel.workingDirectory) }
                }) {
                    Label("Push", systemImage: "icloud.and.arrow.up")
                }
                Button(action: {
                    Task { await viewModel.gitService.pull(in: viewModel.workingDirectory) }
                }) {
                    Label("Pull", systemImage: "icloud.and.arrow.down")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text("Commit")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Diff stats
            let stats = viewModel.gitService.diffStats
            if stats.added > 0 || stats.removed > 0 {
                HStack(spacing: 2) {
                    if stats.added > 0 {
                        Text("+\(formatDiffCount(stats.added))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if stats.removed > 0 {
                        Text("-\(formatDiffCount(stats.removed))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheetView(viewModel: viewModel, isPresented: $showCommitSheet)
        }
    }

    private func formatDiffCount(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }
}

// MARK: - Commit Sheet

struct CommitSheetView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var commitMessage = ""
    @State private var includeUnstaged = true
    @State private var nextStep: CommitNextStep = .commit
    @State private var isCommitting = false

    enum CommitNextStep: String, CaseIterable {
        case commit = "Commit"
        case commitAndPush = "Commit and push"
        case commitAndPR = "Commit and create PR"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Commit your changes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Branch + stats
            HStack {
                Text("Branch")
                    .foregroundStyle(.secondary)
                Spacer()
                if let branch = viewModel.gitBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                        Text(branch)
                            .font(.system(.body, design: .monospaced))
                    }
                    .foregroundStyle(.primary)
                }
            }

            HStack {
                Text("Changes")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Text("\(viewModel.gitService.changedFiles.count) files")
                    let stats = viewModel.gitService.diffStats
                    if stats.added > 0 {
                        Text("+\(stats.added)")
                            .foregroundStyle(.green)
                    }
                    if stats.removed > 0 {
                        Text("-\(stats.removed)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.system(.body, design: .monospaced))
            }

            // Include unstaged toggle
            Toggle("Include unstaged", isOn: $includeUnstaged)
                .tint(.blue)

            // Commit message
            VStack(alignment: .leading, spacing: 4) {
                Text("Commit message")
                    .foregroundStyle(.secondary)
                TextField("Leave blank to autogenerate a commit message", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)
            }

            // Next steps
            VStack(alignment: .leading, spacing: 8) {
                Text("Next steps")
                    .foregroundStyle(.secondary)
                ForEach(CommitNextStep.allCases, id: \.self) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step == .commit ? "checkmark.circle" :
                                step == .commitAndPush ? "icloud.and.arrow.up" : "arrow.triangle.pull")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text(step.rawValue)
                        Spacer()
                        if step == nextStep {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { nextStep = step }
                }
            }

            // Continue button
            Button(action: performCommit) {
                HStack {
                    Spacer()
                    if isCommitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Continue")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isCommitting)
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            Task { await viewModel.gitService.refresh(in: viewModel.workingDirectory) }
        }
    }

    private func performCommit() {
        isCommitting = true
        let message = commitMessage.isEmpty ? "Update from Tinker" : commitMessage

        Task {
            let success = await viewModel.gitService.commit(
                message: message,
                includeUnstaged: includeUnstaged,
                in: viewModel.workingDirectory
            )

            if success {
                switch nextStep {
                case .commit:
                    break
                case .commitAndPush:
                    let _ = await viewModel.gitService.push(in: viewModel.workingDirectory)
                case .commitAndPR:
                    let _ = await viewModel.gitService.push(in: viewModel.workingDirectory)
                    // Open GitHub create PR page
                    let remote = await getRemoteURL()
                    if let url = remote {
                        await MainActor.run { NSWorkspace.shared.open(url) }
                    }
                }
            }

            await MainActor.run {
                isCommitting = false
                isPresented = false
            }
        }
    }

    private func getRemoteURL() async -> URL? {
        let result = await viewModel.gitService.getRemoteURL(in: viewModel.workingDirectory)
        guard var urlStr = result else { return nil }
        // Convert git@github.com:user/repo.git → https://github.com/user/repo/compare
        if urlStr.hasPrefix("git@github.com:") {
            urlStr = urlStr.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        }
        if urlStr.hasSuffix(".git") { urlStr = String(urlStr.dropLast(4)) }
        return URL(string: urlStr + "/compare")
    }
}

struct AttachedFileChip: View {
    let file: AttachedFile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if file.isImage, let nsImage = NSImage(contentsOfFile: file.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(file.filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(file.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
struct ChatToolbarNotifications: View {
    var body: some View {
        Button(action: {
            let content = UNMutableNotificationContent()
            content.title = "Tinker"
            content.body = "Notifications are enabled."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }) {
            Image(systemName: "bell")
                .font(.system(size: 10))
                .frame(width: 26, height: 26, alignment: .center)
        }
        .help("Send test notification")
        .accessibilityLabel("Send test notification")
    }
}

struct StatusBar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @AppStorage("accentR") private var accentR = 0.2

    private var statusDotColor: Color {
        switch viewModel.runState {
        case .idle, .completed: return Color(TinkerApp.accent)
        case .running, .stopping: return Color(TinkerApp.earthSand)
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Connection indicator
            HStack(spacing: 24) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                    .overlay {
                        if viewModel.runState.isActive {
                            Circle()
                                .fill(TinkerApp.earthSand.opacity(0.4))
                                .frame(width: 10, height: 10)
                                .phaseAnimator([false, true]) { content, phase in
                                    content.opacity(phase ? 0.0 : 1.0)
                                } animation: { _ in .easeInOut(duration: 0.8) }
                        }
                    }
                    .accessibilityLabel("Status: \(viewModel.runState.displayLabel)")
                if viewModel.runState.isActive {
                    SpinnerVerbView()
                } else {
                    Text(viewModel.runState.displayLabel)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Token usage & cost (shown after a response completes)
            if !viewModel.isLoading && viewModel.lastInputTokens > 0 {
                HStack(spacing: 6) {
                    Text(formatTokens(viewModel.lastInputTokens) + " in / " + formatTokens(viewModel.lastOutputTokens) + " out")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text(formatCost(viewModel.totalSessionCost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Elapsed time during request
            if viewModel.isLoading {
                Text(formatElapsed(elapsed))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Branch name (bottom right, like Codex)
            if let branch = viewModel.gitBranch {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branch)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(TinkerApp.canvasBackground.opacity(0.6))
        .onChange(of: viewModel.isLoading) { _, loading in
            if loading {
                elapsed = 0
                let startTime = viewModel.requestStartTime
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                    Task { @MainActor in
                        if let start = startTime {
                            self.elapsed = Date().timeIntervalSince(start)
                        }
                    }
                }
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.3f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let seconds = Int(t)
        if seconds < 60 {
            return String(format: "%d.%ds", seconds, Int((t - Double(seconds)) * 10))
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
