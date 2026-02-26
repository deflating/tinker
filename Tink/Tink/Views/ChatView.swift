import SwiftUI

// MARK: - Display Item

/// Flattened display model: text bubbles, tool group summaries, typing indicator.
private enum DisplayItem: Identifiable {
    case message(ChatMessage)
    case toolGroup(id: String, summary: String)
    case typing

    var id: String {
        switch self {
        case .message(let m): return m.id.uuidString
        case .toolGroup(let id, _): return id
        case .typing: return "typing-indicator"
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    var connection: TinkerConnection
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var showTyping = false
    @State private var showPlusMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .background(Color(.systemBackground))

            // iMessage-style plus menu overlay
            if showPlusMenu {
                PlusMenuOverlay(isPresented: $showPlusMenu, onAction: handlePlusAction)
            }
        }
        .navigationTitle(connection.currentSession?.name ?? "Tinker")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: connection.isLoading) { _, loading in
            if !loading { showTyping = false }
        }
    }

    private func handlePlusAction(_ action: PlusMenuAction) {
        switch action {
        case .camera: showCamera = true
        case .photos: showPhotoPicker = true
        case .files: showFilePicker = true
        case .model, .workingDirectory, .permissions: break // TODO
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(displayItems) { item in
                        switch item {
                        case .message(let msg):
                            MessageBubble(message: msg)
                        case .toolGroup(_, let summary):
                            ToolGroupPill(summary: summary)
                        case .typing:
                            TypingIndicator()
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: displayItems.count) {
                scrollToBottom(proxy, animated: true)
            }
        }
    }

    private var displayItems: [DisplayItem] {
        var items: [DisplayItem] = []
        var toolBuffer: [ChatMessage] = []
        var toolGroupIndex = 0

        func flushTools() {
            guard !toolBuffer.isEmpty else { return }
            let summary = toolSummary(toolBuffer)
            items.append(.toolGroup(id: "toolgroup-\(toolGroupIndex)", summary: summary))
            toolGroupIndex += 1
            toolBuffer = []
        }

        for msg in connection.messages {
            switch msg.messageType {
            case .text:
                flushTools()
                items.append(.message(msg))
            case .toolUse, .toolResult, .toolError, .thinking, .webSearch:
                toolBuffer.append(msg)
            }
        }
        flushTools()

        // Show typing indicator only when loading AND we have messages (not on initial load)
        if showTyping && !connection.messages.isEmpty {
            items.append(.typing)
        }

        return items
    }

    private func toolSummary(_ tools: [ChatMessage]) -> String {
        var counts: [String: Int] = [:]
        var hasThinking = false
        var hasWebSearch = false

        for tool in tools {
            if tool.messageType == .thinking { hasThinking = true; continue }
            if tool.messageType == .webSearch { hasWebSearch = true; continue }
            guard tool.messageType == .toolUse else { continue }

            let name = tool.toolName ?? "Tool"
            let category: String
            switch name {
            case "Read": category = "Read"
            case "Bash": category = "Bash"
            case "Edit", "Write": category = "Edit"
            case "Grep", "Glob": category = "Search"
            case "Task": category = "Agent"
            case "WebSearch", "WebFetch": category = "Web"
            default:
                if name.hasPrefix("mcp__") { category = "MCP" }
                else { category = "Other" }
            }
            counts[category, default: 0] += 1
        }

        var parts: [String] = []
        if hasThinking { parts.append("Thought") }
        if let n = counts["Read"] { parts.append("Read \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["Bash"] { parts.append("Ran \(n) command\(n == 1 ? "" : "s")") }
        if let n = counts["Edit"] { parts.append("Edited \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["Search"] { parts.append("Searched \(n) time\(n == 1 ? "" : "s")") }
        if let n = counts["Agent"] { parts.append("Spawned \(n) agent\(n == 1 ? "" : "s")") }
        if hasWebSearch || counts["Web"] != nil { parts.append("Web search") }
        if let n = counts["MCP"] { parts.append("Used \(n) extension\(n == 1 ? "" : "s")") }
        if let n = counts["Other"] { parts.append("Used \(n) tool\(n == 1 ? "" : "s")") }

        return parts.isEmpty ? "Used tools" : parts.joined(separator: ", ")
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showPlusMenu = true
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }

            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { send() }
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        connection.sendMessage(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if connection.isLoading { showTyping = true }
        }
    }
}

// MARK: - Tool Group Pill

private let toolBlue = Color(red: 0.35, green: 0.55, blue: 0.85)

struct ToolGroupPill: View {
    let summary: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.fill")
                .font(.system(size: 11))
                .foregroundStyle(toolBlue)
            Text(summary)
                .font(.caption)
                .foregroundStyle(toolBlue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(toolBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dot0 = false
    @State private var dot1 = false
    @State private var dot2 = false

    var body: some View {
        HStack(spacing: 5) {
            TypingDot(animating: dot0)
            TypingDot(animating: dot1)
            TypingDot(animating: dot2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            let anim = Animation.easeInOut(duration: 0.45).repeatForever(autoreverses: true)
            withAnimation(anim) { dot0 = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(anim) { dot1 = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(anim) { dot2 = true }
            }
        }
    }
}

private struct TypingDot: View {
    var animating: Bool

    var body: some View {
        Circle()
            .fill(Color(.systemGray))
            .frame(width: 8, height: 8)
            .offset(y: animating ? -4 : 2)
            .opacity(animating ? 1.0 : 0.4)
    }
}

// MARK: - Plus Menu

enum PlusMenuAction {
    case camera, photos, files, model, workingDirectory, permissions
}

struct PlusMenuOverlay: View {
    @Binding var isPresented: Bool
    var onAction: (PlusMenuAction) -> Void
    @State private var appeared = false

    private let items: [(icon: String, label: String, color: Color, action: PlusMenuAction)] = [
        ("camera.fill", "Camera", .yellow, .camera),
        ("photo.fill", "Photos", .pink, .photos),
        ("folder.fill", "Files", .blue, .files),
        ("cpu", "Model", .purple, .model),
        ("folder.badge.gearshape", "Working Directory", .orange, .workingDirectory),
        ("lock.shield", "Permissions", .green, .permissions),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed background
            Color.black.opacity(appeared ? 0.5 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Menu card
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        dismiss()
                        onAction(item.action)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(item.color, in: Circle())
                            Text(item.label)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    if index < items.count - 1 {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
            .scaleEffect(appeared ? 1.0 : 0.5, anchor: .bottomLeading)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content.trimmingCharacters(in: .whitespacesAndNewlines))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.role == .user ? .white : .primary)

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var bubbleColor: Color {
        message.role == .user
            ? Color(red: 0.25, green: 0.25, blue: 0.25)
            : Color(.secondarySystemBackground)
    }
}

