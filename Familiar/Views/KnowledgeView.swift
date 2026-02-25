import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeView: View {
    let ragService: RAGService
    @Environment(\.dismiss) private var dismiss
    @State private var importMode: ImportMode?
    @State private var showFilePicker = false
    @State private var importStatus: String?
    @State private var searchQuery = ""
    @State private var searchResults: [RAGService.SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var backfillStatus: String?

    private enum ImportMode {
        case document, claudeAI, claudeCode
    }

    private var allowedTypes: [UTType] {
        switch importMode {
        case .document: return [.plainText, .sourceCode, .data, .text]
        case .claudeAI: return [.json]
        case .claudeCode: return [.folder]
        case nil: return [.plainText]
        }
    }

    private var allowsMultiple: Bool {
        importMode == .document
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Knowledge Base")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search knowledge base…", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .onChange(of: searchQuery) {
                searchTask?.cancel()
                let query = searchQuery
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await MainActor.run { searchResults = [] }
                    } else {
                        let results = ragService.hybridSearch(query: query)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { searchResults = results }
                    }
                }
            }

            Divider()

            if !searchQuery.isEmpty {
                // Search results view
                if searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No results")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(searchResults) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    SourceBadge(sourceType: result.sourceType)
                                    Text(result.filename)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                Text(result.text.prefix(300))
                                    .font(.callout)
                                    .lineLimit(4)
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else if ragService.documentIndex.isEmpty && !ragService.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No documents imported")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Import documents to give Familiar context\nabout your projects, notes, or reference material.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    ForEach(ragService.documentIndex) { entry in
                        HStack {
                            SourceBadge(sourceType: entry.sourceType)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.filename)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text("\(entry.chunkCount) chunks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.importDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                ragService.removeDocument(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            // Status + Import buttons
            VStack(spacing: 8) {
                if let progress = ragService.importProgress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                        HStack {
                            Text("\(progress.completed)/\(progress.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(progress.currentItem)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                } else if let status = importStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                HStack {
                    if ragService.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(ragService.documentIndex.count) documents · \(ragService.documentIndex.map(\.chunkCount).reduce(0, +)) chunks")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Menu("Import") {
                        Button("Document…") {
                            importMode = .document
                            showFilePicker = true
                        }
                        Divider()
                        Button("Claude.ai Export (JSON)…") {
                            importMode = .claudeAI
                            showFilePicker = true
                        }
                        Button("Claude Code Sessions (~/.claude/projects)…") {
                            importMode = .claudeCode
                            showFilePicker = true
                        }
                    }
                    .disabled(ragService.importProgress != nil)

                    Button("Backfill") {
                        backfillStatus = "Starting…"
                        Task.detached {
                            let sCount = await ragService.backfillSurrogates()
                            await MainActor.run {
                                backfillStatus = sCount > 0
                                    ? "Surrogates done (\(sCount)). Starting embeddings…"
                                    : "Surrogates up to date. Starting embeddings…"
                            }
                            let eCount = await ragService.backfillEmbeddings { processed, total in
                                Task { @MainActor in
                                    backfillStatus = "Embedding: \(processed)/\(total)"
                                }
                            }
                            // Build HNSW index if needed
                            if ragService.vectorIndex.count == 0 {
                                await MainActor.run { backfillStatus = "Building search index…" }
                                let indexed = await ragService.buildVectorIndex { processed, total in
                                    Task { @MainActor in
                                        backfillStatus = "Indexing: \(processed)/\(total)"
                                    }
                                }
                                await MainActor.run {
                                    backfillStatus = indexed > 0
                                        ? "Done! Indexed \(indexed) vectors"
                                        : eCount > 0 ? "Done! \(eCount) new embeddings" : "Everything up to date"
                                }
                            } else {
                                await MainActor.run {
                                    backfillStatus = eCount > 0
                                        ? "Done! \(eCount) new embeddings"
                                        : "Everything up to date"
                                }
                            }
                            await MainActor.run {
                                Task {
                                    try? await Task.sleep(for: .seconds(5))
                                    backfillStatus = nil
                                }
                            }
                        }
                    }
                    .disabled(backfillStatus != nil)
                }

                if let status = backfillStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FamiliarApp.canvasBackground)
        .tint(FamiliarApp.accent)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: allowsMultiple
        ) { result in
            guard case .success(let urls) = result else { return }
            let mode = importMode
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                Task {
                    switch mode {
                    case .document:
                        await ragService.importFile(url: url)
                    case .claudeAI:
                        importStatus = "Importing Claude.ai conversations…"
                        let count = await ragService.importClaudeAIExport(url: url)
                        importStatus = "Imported \(count) conversations"
                        try? await Task.sleep(for: .seconds(3))
                        importStatus = nil
                    case .claudeCode:
                        importStatus = "Importing Claude Code transcripts…"
                        let count = await ragService.importClaudeCodeTranscripts(directoryURL: url)
                        importStatus = "Imported \(count) session transcripts"
                        try? await Task.sleep(for: .seconds(3))
                        importStatus = nil
                    case nil:
                        break
                    }
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
    }
}

// MARK: - Source Type Badge

private struct SourceBadge: View {
    let sourceType: RAGService.SourceType

    private var color: Color {
        switch sourceType {
        case .claudeAI: return .purple
        case .claudeCode: return .green
        case .file: return .blue
        }
    }

    var body: some View {
        Text(sourceType.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
