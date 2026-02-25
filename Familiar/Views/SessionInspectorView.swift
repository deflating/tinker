import SwiftUI

struct SessionInspectorView: View {
    @Bindable var viewModel: ChatViewModel

    private var toolUseCount: Int {
        viewModel.messages.filter { $0.role == .toolUse }.count
    }

    private var messageCount: Int {
        viewModel.messages.filter { $0.role == .user || $0.role == .assistant }.count
    }

    private var thinkingCount: Int {
        viewModel.messages.filter { $0.role == .thinking }.count
    }

    private var errorCount: Int {
        viewModel.messages.filter { $0.role == .toolError }.count
    }

    private var filesReferenced: [String] {
        let toolMessages = viewModel.messages.filter { $0.role == .toolUse }
        var files: [String] = []
        for msg in toolMessages {
            // Extract file paths from tool input (look for common patterns)
            let content = msg.content
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("file_path:") || trimmed.hasPrefix("path:") {
                    let path = trimmed.split(separator: ":", maxSplits: 1).last?
                        .trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\""))) ?? ""
                    if !path.isEmpty && !files.contains(path) {
                        files.append(path)
                    }
                }
            }
        }
        return files
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Inspector", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Session info
                    if let session = viewModel.currentSession {
                        inspectorSection("Session") {
                            inspectorRow("Name", value: session.name)
                            inspectorRow("Updated", value: session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    // Model & mode
                    inspectorSection("Configuration") {
                        inspectorRow("Model", value: viewModel.selectedModel.replacingOccurrences(of: "claude-", with: ""))
                        inspectorRow("Mode", value: viewModel.selectedPermissionMode)
                        inspectorRow("Directory", value: (viewModel.workingDirectory as NSString).lastPathComponent)
                        if viewModel.currentSession?.isWorktree == true {
                            inspectorRow("Type", value: "Worktree", color: FamiliarApp.agentPurple)
                        }
                    }

                    // Git
                    if let branch = viewModel.gitBranch {
                        inspectorSection("Git") {
                            inspectorRow("Branch", value: branch)
                            inspectorRow("Status", value: viewModel.gitService.isDirty ? "Modified" : "Clean",
                                        color: viewModel.gitService.isDirty ? .orange : .green)
                            if let ab = viewModel.gitService.aheadBehind {
                                if ab.ahead > 0 { inspectorRow("Ahead", value: "\(ab.ahead) commit\(ab.ahead == 1 ? "" : "s")", color: .green) }
                                if ab.behind > 0 { inspectorRow("Behind", value: "\(ab.behind) commit\(ab.behind == 1 ? "" : "s")", color: .orange) }
                            }
                        }

                        // Changed files
                        if !viewModel.gitService.changedFiles.isEmpty {
                            inspectorSection("Changed Files (\(viewModel.gitService.changedFiles.count))") {
                                ForEach(viewModel.gitService.changedFiles.prefix(20)) { file in
                                    HStack(spacing: 4) {
                                        Text(file.status)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(file.status == "M" ? .orange : file.status == "D" ? .red : file.status == "A" ? .green : .secondary)
                                            .frame(width: 16)
                                        Text((file.path as NSString).lastPathComponent)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                }
                            }
                        }

                        // Recent commits
                        if !viewModel.gitService.recentCommits.isEmpty {
                            inspectorSection("Recent Commits") {
                                ForEach(viewModel.gitService.recentCommits.prefix(5)) { commit in
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            Text(commit.hash)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                            Text(commit.relativeDate)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Text(commit.message)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }

                    // Stats
                    inspectorSection("Activity") {
                        inspectorRow("Messages", value: "\(messageCount)")
                        inspectorRow("Tool Calls", value: "\(toolUseCount)")
                        inspectorRow("Thinking", value: "\(thinkingCount)")
                        if errorCount > 0 {
                            inspectorRow("Errors", value: "\(errorCount)", color: .red)
                        }
                    }

                    // Cost
                    inspectorSection("Usage") {
                        if viewModel.totalSessionCost > 0 {
                            inspectorRow("Session Cost", value: String(format: "$%.4f", viewModel.totalSessionCost))
                        }
                        if viewModel.lastInputTokens > 0 {
                            inspectorRow("Last Input", value: formatTokens(viewModel.lastInputTokens))
                        }
                        if viewModel.lastOutputTokens > 0 {
                            inspectorRow("Last Output", value: formatTokens(viewModel.lastOutputTokens))
                        }
                        if viewModel.lastDurationMs > 0 {
                            inspectorRow("Last Duration", value: formatDuration(viewModel.lastDurationMs))
                        }
                    }

                    // Files touched
                    if !filesReferenced.isEmpty {
                        inspectorSection("Files (\(filesReferenced.count))") {
                            ForEach(filesReferenced.prefix(20), id: \.self) { path in
                                Button(action: {
                                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Text((path as NSString).lastPathComponent)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(FamiliarApp.canvasBackground)
    }

    @ViewBuilder
    private func inspectorSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func inspectorRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens > 1000 ? String(format: "%.1fk", Double(tokens) / 1000) : "\(tokens)"
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }
}
