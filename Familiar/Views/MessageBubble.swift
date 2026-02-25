import SwiftUI
import AppKit

// MARK: - Spinner Verbs

struct SpinnerVerbView: View {
    private static let verbs = [
        "Thinking…", "Pondering…", "Musing…", "Noodling…", "Percolating…",
        "Marinating…", "Stewing…", "Brewing…", "Churning…", "Cogitating…",
        "Deliberating…", "Contemplating…", "Mulling…", "Ruminating…",
        "Considering…", "Processing…", "Working…", "Baking…", "Beaming…",
        "Befuddling…", "Billowing…", "Blanching…", "Bloviating…",
        "Boogieing…", "Boondoggling…", "Booping…", "Bunning…", "Burrowing…",
        "Discombobulating…", "Doodling…", "Flibbertigibbeting…",
        "Flummoxing…", "Gallivanting…", "Hullaballooing…", "Lollygagging…",
        "Mustering…", "Shenaniganing…", "Skedaddling…",
    ]

    @State private var verbIndex = Int.random(in: 0..<Self.verbs.count)
    @State private var displayedText = ""
    @State private var charIndex = 0
    @State private var typeTimer: Timer?
    @State private var pauseTimer: Timer?
    @State private var isDeleting = false

    private var currentVerb: String {
        Self.verbs[verbIndex % Self.verbs.count]
    }

    var body: some View {
        Text(displayedText)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .onAppear {
                startTyping()
            }
            .onDisappear {
                typeTimer?.invalidate()
                pauseTimer?.invalidate()
            }
    }

    private func startTyping() {
        displayedText = ""
        charIndex = 0
        isDeleting = false
        typeTimer?.invalidate()
        pauseTimer?.invalidate()
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { _ in
            let verb = currentVerb
            if !isDeleting {
                if charIndex < verb.count {
                    displayedText = String(verb.prefix(charIndex + 1))
                    charIndex += 1
                } else {
                    typeTimer?.invalidate()
                    pauseTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                        isDeleting = true
                        startDeleting()
                    }
                }
            }
        }
    }

    private func startDeleting() {
        typeTimer?.invalidate()
        pauseTimer?.invalidate()
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { _ in
            if charIndex > 0 {
                charIndex -= 1
                displayedText = String(currentVerb.prefix(charIndex))
            } else {
                typeTimer?.invalidate()
                verbIndex = Int.random(in: 0..<Self.verbs.count)
                pauseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                    startTyping()
                }
            }
        }
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let text: String
    let size: CGFloat

    @State private var showCopied = false

    init(_ text: String, size: CGFloat = 11) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showCopied = false }
        }) {
            if showCopied {
                Text("Copied!")
                    .font(.system(size: size - 1))
                    .foregroundStyle(FamiliarApp.accent)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: size))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

// MARK: - Markdown Rendering

private struct MarkdownSegment: Identifiable {
    let id: Int  // positional index, stable within a parse
    let kind: Kind

    enum Kind {
        case text(String)
        case codeBlock(language: String?, code: String)
    }
}

private func parseMarkdownSegments(_ input: String) -> [MarkdownSegment] {
    var segments: [MarkdownSegment] = []
    let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var i = 0
    var textBuffer: [String] = []

    func flushText() {
        if !textBuffer.isEmpty {
            segments.append(MarkdownSegment(id: segments.count, kind: .text(textBuffer.joined(separator: "\n"))))
            textBuffer = []
        }
    }

    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("```") {
            flushText()
            let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeLines: [String] = []
            i += 1
            while i < lines.count && !lines[i].hasPrefix("```") {
                codeLines.append(lines[i])
                i += 1
            }
            segments.append(MarkdownSegment(
                id: segments.count,
                kind: .codeBlock(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n"))
            ))
            i += 1 // skip closing ```
        } else {
            textBuffer.append(line)
            i += 1
        }
    }
    flushText()
    return segments
}

private struct MarkdownContentView: View {
    let content: String

    @State private var segments: [MarkdownSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(makeAttributedString(text))
                            .font(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    }
                case .codeBlock(let language, let code):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let language = language, !language.isEmpty {
                                Text(language)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            CopyButton(code, size: 10)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 6)

                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.init(top: 2, leading: 10, bottom: 8, trailing: 10))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
        .onChange(of: content) {
            segments = parseMarkdownSegments(content)
        }
        .onAppear {
            segments = parseMarkdownSegments(content)
        }
    }

    private func makeAttributedString(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }
}

// MARK: - Diff Content View

private func isDiffContent(_ text: String) -> Bool {
    let lines = text.prefix(2000).split(separator: "\n", maxSplits: 20, omittingEmptySubsequences: false)
    var diffMarkers = 0
    for line in lines {
        if line.hasPrefix("@@") || line.hasPrefix("---") || line.hasPrefix("+++") ||
           line.hasPrefix("diff --git") {
            diffMarkers += 1
        }
    }
    return diffMarkers >= 2
}

private struct DiffLine: Identifiable {
    let id: Int
    let text: String
    let kind: Kind
    enum Kind { case context, addition, removal, header }
}

private func parseDiffLines(_ text: String) -> [DiffLine] {
    text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { i, line in
        let s = String(line)
        let kind: DiffLine.Kind
        if s.hasPrefix("@@") || s.hasPrefix("diff --git") || s.hasPrefix("---") || s.hasPrefix("+++") {
            kind = .header
        } else if s.hasPrefix("+") {
            kind = .addition
        } else if s.hasPrefix("-") {
            kind = .removal
        } else {
            kind = .context
        }
        return DiffLine(id: i, text: s, kind: kind)
    }
}

private struct DiffContentView: View {
    let content: String

    private static let addColor = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.2, green: 0.55, blue: 0.3, alpha: 1)
            : NSColor(red: 0.15, green: 0.5, blue: 0.25, alpha: 1)
    })
    private static let removeColor = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.7, green: 0.25, blue: 0.25, alpha: 1)
            : NSColor(red: 0.65, green: 0.2, blue: 0.2, alpha: 1)
    })
    private static let headerColor = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1)
            : NSColor(red: 0.3, green: 0.4, blue: 0.65, alpha: 1)
    })
    private static let addBg = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.15, green: 0.35, blue: 0.2, alpha: 0.3)
            : NSColor(red: 0.15, green: 0.5, blue: 0.2, alpha: 0.12)
    })
    private static let removeBg = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.4, green: 0.15, blue: 0.15, alpha: 0.3)
            : NSColor(red: 0.6, green: 0.15, blue: 0.15, alpha: 0.12)
    })

    var body: some View {
        let lines = parseDiffLines(content)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(color(for: line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(bg(for: line.kind))
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxHeight: 400)
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Self.addColor
        case .removal: return Self.removeColor
        case .header: return Self.headerColor
        case .context: return .secondary
        }
    }

    private func bg(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Self.addBg
        case .removal: return Self.removeBg
        default: return .clear
        }
    }
}

// MARK: - Tool Disclosure

private struct ToolDisclosureView: View {
    let icon: String
    let label: String
    let content: String
    let color: Color
    let defaultExpanded: Bool

    @State private var isExpanded: Bool

    init(icon: String, label: String, content: String, color: Color, defaultExpanded: Bool) {
        self.icon = icon
        self.label = label
        self.content = content
        self.color = color
        self.defaultExpanded = defaultExpanded
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 12)
                    Image(systemName: icon)
                        .font(.callout)
                        .foregroundStyle(color)
                    Text(label)
                        .font(.callout.bold())
                        .foregroundStyle(color)
                    Spacer()
                    if !isExpanded && !content.isEmpty {
                        Text(content.prefix(40) + (content.count > 40 ? "…" : ""))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(8)

            if isExpanded {
                if isDiffContent(content) {
                    DiffContentView(content: content)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                } else {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .frame(maxHeight: 300)
                }
            }
        }
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Tool Group View

struct ToolGroupView: View {
    let tools: [ChatMessage]
    @State private var isExpanded = false

    /// Whether the last tool in the group has a result yet
    private var isComplete: Bool {
        guard let last = tools.last else { return true }
        return last.role == .toolResult || last.role == .toolError
    }

    private var summaryText: String {
        var counts: [String: Int] = [:]
        for tool in tools {
            guard tool.role == .toolUse else { continue }
            let name = tool.toolName ?? "Tool"
            let category: String
            switch name {
            case "Read": category = "Read"
            case "Bash": category = "Bash"
            case "Edit", "Write": category = "Edit"
            case "Grep", "Glob": category = "Search"
            case "ToolSearch": category = "ToolSearch"
            default:
                if name.hasPrefix("mcp__") {
                    category = Self.mcpCategory(name)
                } else {
                    category = "Other"
                }
            }
            counts[category, default: 0] += 1
        }

        var parts: [String] = []
        if let n = counts["Read"] { parts.append("Read \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["Bash"] { parts.append("ran \(n) command\(n == 1 ? "" : "s")") }
        if let n = counts["Edit"] { parts.append("edited \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["Search"] { parts.append("searched \(n) time\(n == 1 ? "" : "s")") }
        if let n = counts["ToolSearch"] { parts.append("loaded \(n) tool\(n == 1 ? "" : "s")") }
        if let n = counts["WebSearch"] { parts.append("web search\(n == 1 ? "" : " ×\(n)")") }
        if let n = counts["Memory"] { parts.append("memory \(n == 1 ? "lookup" : "×\(n)")") }
        if let n = counts["MCP"] { parts.append("used \(n) extension\(n == 1 ? "" : "s")") }
        if let n = counts["Other"] { parts.append("used \(n) tool\(n == 1 ? "" : "s")") }

        return parts.isEmpty ? "Used tools" : parts.joined(separator: ", ")
    }

    /// Categorize MCP tool names for summary display
    private static func mcpCategory(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("search") || lower.contains("web") { return "WebSearch" }
        if lower.contains("mem") || lower.contains("knowledge") { return "Memory" }
        return "MCP"
    }

    private var groupIcon: String {
        let toolNames = tools.compactMap { $0.role == .toolUse ? $0.toolName : nil }
        let hasMCP = toolNames.contains { $0.hasPrefix("mcp__") }
        if hasMCP {
            let lower = toolNames.joined().lowercased()
            if lower.contains("search") || lower.contains("web") { return "globe" }
            if lower.contains("mem") || lower.contains("knowledge") { return "brain" }
            return "puzzlepiece.extension.fill"
        }
        return "wrench.fill"
    }

    private var statusIcon: String {
        if !isComplete { return "circle.dotted" }
        let hasError = tools.contains { $0.role == .toolError }
        return hasError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if !isComplete { return FamiliarApp.toolBlue }
        let hasError = tools.contains { $0.role == .toolError }
        return hasError ? .red : FamiliarApp.toolBlue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FamiliarApp.toolBlue)
                        .frame(width: 12)
                    Image(systemName: groupIcon)
                        .font(.callout)
                        .foregroundStyle(FamiliarApp.toolBlue)
                    Text(summaryText)
                        .font(.callout.bold())
                        .foregroundStyle(FamiliarApp.toolBlue)
                    Spacer()

                    // Status indicator
                    Image(systemName: statusIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: !isComplete)
                }
            }
            .buttonStyle(.plain)
            .padding(8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tools) { tool in
                        ToolGroupItemView(message: tool)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(FamiliarApp.toolBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToolGroupItemView: View {
    let message: ChatMessage
    @State private var isExpanded = true

    /// Whether this is a result from a Task/subagent tool
    private var isAgentResult: Bool {
        message.role == .toolResult && message.content.count > 200
    }

    private var icon: String {
        switch message.role {
        case .toolUse:
            let name = (message.toolName ?? "").lowercased()
            if name.contains("search") || name.contains("web") { return "globe" }
            if name.contains("mem") || name.contains("knowledge") { return "brain" }
            if name.hasPrefix("mcp__") { return "puzzlepiece.extension.fill" }
            return "wrench.fill"
        case .toolResult: return "checkmark.circle.fill"
        case .toolError: return "xmark.circle.fill"
        default: return "circle.fill"
        }
    }

    private var color: Color {
        switch message.role {
        case .toolUse: return FamiliarApp.toolBlue
        case .toolResult: return FamiliarApp.toolBlue
        case .toolError: return .red
        default: return .secondary
        }
    }

    private var label: String {
        switch message.role {
        case .toolUse: return Self.displayName(for: message.toolName ?? "Tool")
        case .toolResult: return "Result"
        case .toolError: return "Error"
        default: return "Tool"
        }
    }

    /// Turn `mcp__brave-search__brave_web_search` into `Web Search (Brave)`
    private static func displayName(for toolName: String) -> String {
        guard toolName.hasPrefix("mcp__") else { return toolName }
        let parts = toolName.dropFirst(5).split(separator: "__", maxSplits: 1)
        let server = parts.first.map { String($0) } ?? ""
        let tool = parts.count > 1 ? String(parts[1]) : server

        // Clean up the tool name: strip server prefix, replace underscores, title-case
        var cleaned = tool
        // Remove redundant server prefix from tool name (e.g. brave_web_search from brave-search)
        let serverPrefix = server.replacingOccurrences(of: "-", with: "_") + "_"
        if cleaned.hasPrefix(serverPrefix) {
            cleaned = String(cleaned.dropFirst(serverPrefix.count))
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        let serverDisplay = server.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        return "\(cleaned) (\(serverDisplay))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color.opacity(0.6))
                        .frame(width: 10)
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color)
                    if !isExpanded && !message.content.isEmpty {
                        Text(message.content.prefix(60) + (message.content.count > 60 ? "…" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !message.content.isEmpty {
                if isDiffContent(message.content) {
                    DiffContentView(content: message.content)
                        .padding(.leading, 14)
                        .padding(.top, 2)
                } else if isAgentResult {
                    // Rich display for agent/Task results
                    ScrollView {
                        Text(LocalizedStringKey(message.content))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)
                    .padding(.leading, 14)
                    .padding(.top, 4)
                } else {
                    Text(message.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 14)
                        .padding(.top, 2)
                        .frame(maxHeight: 200)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let path = extractFilePath(from: message.content) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                Divider()
            }
            Button("Copy Content") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
        }
    }

    private func extractFilePath(from content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["file_path:", "path:", "file:"] {
                if trimmed.hasPrefix(prefix) {
                    let path = trimmed.dropFirst(prefix.count)
                        .trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"")))
                    if path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
                        return path
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch message.role {
            case .user:
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.body)
                    .lineSpacing(6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 3,
                        topTrailingRadius: 12
                    ))
                    .textSelection(.enabled)

            case .assistant:
                VStack(alignment: .leading, spacing: 4) {
                    if !message.content.isEmpty {
                        MarkdownContentView(content: message.content)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .overlay(alignment: .topTrailing) {
                    if isHovered && !message.content.isEmpty {
                        CopyButton(message.content)
                            .padding(6)
                    }
                }
                .onHover { isHovered = $0 }
                Spacer(minLength: 60)

            case .toolUse:
                ToolDisclosureView(
                    icon: "wrench.fill",
                    label: message.toolName ?? "Tool",
                    content: message.content,
                    color: FamiliarApp.toolBlue,
                    defaultExpanded: true
                )
                .frame(maxWidth: 500, alignment: .leading)
                Spacer()

            case .toolResult:
                ToolDisclosureView(
                    icon: "checkmark.circle.fill",
                    label: "Result",
                    content: message.content,
                    color: FamiliarApp.toolBlue,
                    defaultExpanded: false
                )
                .frame(maxWidth: 500, alignment: .leading)
                Spacer()

            case .toolError:
                ToolDisclosureView(
                    icon: "xmark.circle.fill",
                    label: "Error",
                    content: message.content,
                    color: .red,
                    defaultExpanded: true
                )
                .frame(maxWidth: 500, alignment: .leading)
                Spacer()

            case .thinking:
                ToolDisclosureView(
                    icon: "brain",
                    label: "Thinking",
                    content: message.content,
                    color: FamiliarApp.thinkingPink,
                    defaultExpanded: true
                )
                .frame(maxWidth: 500, alignment: .leading)
                Spacer()

            case .system:
                Text(message.content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
