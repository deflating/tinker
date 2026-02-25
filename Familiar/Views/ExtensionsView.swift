import SwiftUI

struct ExtensionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = MCPExtensionManager()
    @State private var selectedTab: ExtTab = .installed
    @State private var searchText = ""
    @State private var showAddCustom = false
    @State private var installTarget: MCPCatalogEntry?
    @State private var installEnvValues: [String: String] = [:]

    enum ExtTab: String, CaseIterable {
        case installed = "Installed"
        case catalog = "Catalog"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extensions")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Add Custom") {
                    showAddCustom = true
                }
                .buttonStyle(.bordered)
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

            // Tool count warning
            if manager.hasToolWarning {
                toolWarningBanner
            }

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(ExtTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search extensions…", text: $searchText)
                    .font(.callout)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Divider()

            // Content
            ScrollView {
                switch selectedTab {
                case .installed:
                    installedList
                case .catalog:
                    catalogList
                }
            }
        }
        .background(FamiliarApp.canvasBackground)
        .tint(FamiliarApp.accent)
        .sheet(isPresented: $showAddCustom) {
            AddCustomExtensionSheet(manager: manager)
        }
        .sheet(item: $installTarget) { entry in
            InstallExtensionSheet(entry: entry, manager: manager)
        }
    }

    // MARK: - Tool Warning Banner

    private var toolWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("Too many extensions active")
                    .font(.callout.weight(.medium))
                Text("\(manager.enabledCount) enabled (~\(manager.estimatedTotalTools) tools). Performance may degrade with more than \(MCPExtensionManager.extensionWarningThreshold) extensions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Installed List

    private var installedList: some View {
        LazyVStack(spacing: 0) {
            let filtered = manager.extensions.filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
            }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image("MCPIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .opacity(0.3)
                    Text("No extensions installed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Browse the catalog to add extensions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(filtered) { ext in
                    InstalledExtensionRow(extension_: ext, manager: manager)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Catalog List

    private var catalogList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            let filtered = MCPCatalogEntry.catalog.filter {
                searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
            }
            let grouped = Dictionary(grouping: filtered, by: \.category)

            ForEach(MCPCatalogEntry.MCPCategory.allCases, id: \.self) { category in
                if let entries = grouped[category], !entries.isEmpty {
                    Text(category.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(entries) { entry in
                        CatalogEntryRow(
                            entry: entry,
                            isInstalled: manager.extensions.contains { $0.id == entry.id },
                            onInstall: {
                                if entry.envKeys.isEmpty {
                                    manager.install(from: entry)
                                } else {
                                    installTarget = entry
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

// MARK: - Installed Extension Row

private struct InstalledExtensionRow: View {
    let extension_: MCPExtension
    let manager: MCPExtensionManager
    @State private var isHovered = false
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon from catalog or MCP logo
            if let icon = MCPCatalogEntry.find(extension_.id)?.icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            } else {
                Image("MCPIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .opacity(0.6)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(extension_.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(extension_.displayType)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if !extension_.description.isEmpty {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(extension_.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { extension_.enabled },
                set: { _ in manager.toggle(extension_) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            // Remove button
            Button(action: { manager.remove(extension_) }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 46)
        }
    }
}

// MARK: - Catalog Entry Row

private struct CatalogEntryRow: View {
    let entry: MCPCatalogEntry
    let isInstalled: Bool
    let onInstall: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 16))
                .foregroundStyle(FamiliarApp.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 46)
        }
    }
}

// MARK: - Install Extension Sheet (with env var prompts)

private struct InstallExtensionSheet: View {
    let entry: MCPCatalogEntry
    let manager: MCPExtensionManager
    @Environment(\.dismiss) private var dismiss
    @State private var envValues: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: entry.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(FamiliarApp.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install \(entry.name)")
                        .font(.title3.weight(.semibold))
                    Text(entry.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Required Configuration")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(entry.envKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    SecureField("Enter value…", text: binding(for: key))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install") {
                    manager.install(from: entry, env: envValues)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(entry.envKeys.contains { envValues[$0]?.isEmpty ?? true })
            }
        }
        .padding(20)
        .frame(width: 420, height: 300)
        .onAppear {
            for key in entry.envKeys {
                envValues[key] = ""
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { envValues[key] ?? "" },
            set: { envValues[key] = $0 }
        )
    }
}

// MARK: - Add Custom Extension Sheet

private struct AddCustomExtensionSheet: View {
    let manager: MCPExtensionManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var extensionId = ""
    @State private var type: MCPExtension.MCPType = .stdio
    @State private var command = ""
    @State private var args = ""
    @State private var url = ""
    @State private var envPairs: [(key: String, value: String)] = [("", "")]

    private var isValid: Bool {
        !name.isEmpty && !extensionId.isEmpty && (
            (type == .stdio && !command.isEmpty) ||
            (type != .stdio && !url.isEmpty)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Extension")
                .font(.title3.weight(.semibold))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Basic info
                    LabeledField("Name") {
                        TextField("My Extension", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: name) { _, newValue in
                                if extensionId.isEmpty || extensionId == slugify(name) {
                                    extensionId = slugify(newValue)
                                }
                            }
                    }

                    LabeledField("ID") {
                        TextField("my-extension", text: $extensionId)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                    }

                    // Type
                    LabeledField("Type") {
                        Picker("", selection: $type) {
                            Text("Local Command (stdio)").tag(MCPExtension.MCPType.stdio)
                            Text("Remote HTTP").tag(MCPExtension.MCPType.http)
                            Text("Remote SSE").tag(MCPExtension.MCPType.sse)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Connection details
                    if type == .stdio {
                        LabeledField("Command") {
                            TextField("npx, uvx, node, etc.", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                        }
                        LabeledField("Arguments") {
                            TextField("-y @org/package", text: $args)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                        }
                    } else {
                        LabeledField("URL") {
                            TextField("https://mcp.example.com/mcp", text: $url)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                        }
                    }

                    // Environment variables
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Environment Variables")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: { envPairs.append(("", "")) }) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(envPairs.indices, id: \.self) { idx in
                            HStack(spacing: 6) {
                                TextField("KEY", text: Binding(
                                    get: { envPairs[idx].key },
                                    set: { envPairs[idx].key = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                                .frame(maxWidth: 140)

                                SecureField("value", text: Binding(
                                    get: { envPairs[idx].value },
                                    set: { envPairs[idx].value = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())

                                Button(action: { envPairs.remove(at: idx) }) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Extension") {
                    let env = Dictionary(uniqueKeysWithValues: envPairs.filter { !$0.key.isEmpty })
                    let argsList = args.isEmpty ? nil : args.split(separator: " ").map(String.init)
                    manager.installCustom(
                        id: extensionId,
                        name: name,
                        type: type,
                        command: type == .stdio ? command : nil,
                        args: type == .stdio ? argsList : nil,
                        url: type != .stdio ? url : nil,
                        env: env
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480, height: 500)
    }

    private func slugify(_ str: String) -> String {
        str.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}

// MARK: - Helpers

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}
