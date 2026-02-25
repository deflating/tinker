import SwiftUI

struct MemorySettingsView: View {
    @AppStorage("daemonBatchSize") private var daemonBatchSize = 5
    @State private var bufferContent = ""
    @State private var episodicContent = ""
    @State private var semanticContent = ""
    @State private var bufferStatus = ""
    @State private var episodicStatus = ""
    @State private var semanticStatus = ""
    @State private var selectedLayer: MemoryLayer = .buffer

    private enum MemoryLayer: String, CaseIterable {
        case buffer = "Buffer"
        case episodic = "Episodic"
        case semantic = "Semantic"

        var filename: String {
            switch self {
            case .buffer: return "buffer.md"
            case .episodic: return "episodic.md"
            case .semantic: return "semantic.md"
            }
        }

        var icon: String {
            switch self {
            case .buffer: return "tray.and.arrow.down"
            case .episodic: return "clock.arrow.circlepath"
            case .semantic: return "brain.head.profile"
            }
        }

        var description: String {
            switch self {
            case .buffer: return "Raw observations extracted from conversations by AFM"
            case .episodic: return "Curated memories promoted from buffer by Ollama"
            case .semantic: return "Long-term knowledge distilled from episodic memories"
            }
        }

        var path: String {
            NSHomeDirectory() + "/.familiar/memory/" + filename
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Pipeline overview
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Three-layer memory pipeline that runs during conversations.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 0) {
                            ForEach(MemoryLayer.allCases, id: \.self) { layer in
                                layerCard(layer)
                                if layer != .semantic {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 6)
                                }
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Memory Pipeline", systemImage: "memorychip")
                }

                // Settings
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AFM extraction batch size")
                                .font(.callout)
                            Spacer()
                            Picker("", selection: $daemonBatchSize) {
                                Text("5").tag(5)
                                Text("10").tag(10)
                                Text("15").tag(15)
                                Text("20").tag(20)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Configuration", systemImage: "gearshape")
                }

                // File viewer
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("", selection: $selectedLayer) {
                            ForEach(MemoryLayer.allCases, id: \.self) { layer in
                                Text(layer.rawValue).tag(layer)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text(selectedLayer.filename)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(statusFor(selectedLayer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView {
                            Text(contentFor(selectedLayer))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 250)
                        .padding(8)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Button("Refresh") {
                                loadAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Open in Finder") {
                                NSWorkspace.shared.selectFile(selectedLayer.path, inFileViewerRootedAtPath: "")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))
                                Text("~/.familiar/memory/")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Memory Files", systemImage: "doc.text")
                }
            }
            .padding(20)
        }
        .onAppear { loadAll() }
        .onChange(of: selectedLayer) { loadAll() }
    }

    private func layerCard(_ layer: MemoryLayer) -> some View {
        Button { selectedLayer = layer } label: {
            VStack(spacing: 6) {
                Image(systemName: layer.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selectedLayer == layer ? FamiliarApp.accent : .secondary)
                Text(layer.rawValue)
                    .font(.caption.weight(.medium))
                Text(statusFor(layer))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selectedLayer == layer ? FamiliarApp.accent.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func contentFor(_ layer: MemoryLayer) -> String {
        switch layer {
        case .buffer: return bufferContent.isEmpty ? "Empty — no observations yet" : bufferContent
        case .episodic: return episodicContent.isEmpty ? "Empty — nothing curated yet" : episodicContent
        case .semantic: return semanticContent.isEmpty ? "Empty — nothing distilled yet" : semanticContent
        }
    }

    private func statusFor(_ layer: MemoryLayer) -> String {
        switch layer {
        case .buffer: return bufferStatus
        case .episodic: return episodicStatus
        case .semantic: return semanticStatus
        }
    }

    private func loadAll() {
        let memDir = NSHomeDirectory() + "/.familiar/memory"
        bufferContent = (try? String(contentsOfFile: memDir + "/buffer.md", encoding: .utf8)) ?? ""
        episodicContent = (try? String(contentsOfFile: memDir + "/episodic.md", encoding: .utf8)) ?? ""
        semanticContent = (try? String(contentsOfFile: memDir + "/semantic.md", encoding: .utf8)) ?? ""
        bufferStatus = fileStatus(memDir + "/buffer.md")
        episodicStatus = fileStatus(memDir + "/episodic.md")
        semanticStatus = fileStatus(memDir + "/semantic.md")
    }

    private func fileStatus(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? UInt64 else {
            return "No data"
        }
        let ago = RelativeDateTimeFormatter()
        ago.unitsStyle = .abbreviated
        let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return "\(sizeStr) · \(ago.localizedString(for: modified, relativeTo: Date()))"
    }
}
