import SwiftUI

struct ProjectItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isGit: Bool
    let fileCount: Int
    let lastModified: Date
}

struct EmptyStateView<InputCard: View>: View {
    @Bindable var viewModel: ChatViewModel
    @ViewBuilder var inputCard: () -> InputCard

    @State private var projects: [ProjectItem] = []
    @State private var hoveredProject: String?
    @AppStorage("projectsRootPath") private var projectsRootPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Projects").path

    private var projectsPath: String { projectsRootPath }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Greeting
            Text(Self.pickGreeting())
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.bottom, 28)

            // Project pills
            if !projects.isEmpty {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text("PROJECTS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.secondary.opacity(0.6))

                        Button {
                            pickProjectsRoot()
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Change projects folder")
                    }

                    projectGrid
                }
                .padding(.bottom, 24)
            }

            // Input card
            inputCard()

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .background {
            TinkerApp.canvasBackground
            BlueprintGridBackground()
        }
        .onAppear {
            ensureProjectsDirectory()
            loadProjects()
        }
    }

    // MARK: - Project Grid

    @ViewBuilder
    private var projectGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)], spacing: 8) {
            ForEach(projects) { project in
                ProjectPill(
                    project: project,
                    isHovered: hoveredProject == project.id,
                    isCurrent: viewModel.workingDirectory == project.path
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.setWorkingDirectory(project.path)
                        viewModel.newSession()
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredProject = hovering ? project.id : nil
                    }
                }
            }
        }
        .frame(maxWidth: 600)
    }

    // MARK: - Data Loading

    private func ensureProjectsDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: projectsPath) {
            try? fm.createDirectory(atPath: projectsPath, withIntermediateDirectories: true)
        }
    }

    private func loadProjects() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: projectsPath) else {
            projects = []
            return
        }

        var isDir: ObjCBool = false
        projects = entries
            .filter { !$0.hasPrefix(".") }
            .filter {
                fm.fileExists(atPath: "\(projectsPath)/\($0)", isDirectory: &isDir) && isDir.boolValue
            }
            .map { name in
                let fullPath = "\(projectsPath)/\(name)"
                let isGit = fm.fileExists(atPath: "\(fullPath)/.git")
                let count = (try? fm.contentsOfDirectory(atPath: fullPath))?.count ?? 0
                let modified = Self.mostRecentModification(in: fullPath)
                return ProjectItem(id: name, name: name, path: fullPath, isGit: isGit, fileCount: count, lastModified: modified)
            }
            .sorted { $0.lastModified > $1.lastModified }
    }

    private static func mostRecentModification(in path: String) -> Date {
        let fm = FileManager.default
        let folderDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
        guard let children = try? fm.contentsOfDirectory(atPath: path) else { return folderDate }

        var latest = folderDate
        for child in children.prefix(50) {
            let childPath = "\(path)/\(child)"
            if let attrs = try? fm.attributesOfItem(atPath: childPath),
               let date = attrs[.modificationDate] as? Date,
               date > latest {
                latest = date
            }
        }
        return latest
    }

    private func pickProjectsRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your projects folder"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            projectsRootPath = url.path
            loadProjects()
        }
    }

    // MARK: - Greeting

    private static func pickGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "Late night?"
        default: return "What are we working on?"
        }
    }
}

// MARK: - Project Pill

private struct ProjectPill: View {
    let project: ProjectItem
    let isHovered: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isCurrent ? TinkerApp.accent : .secondary)

                    if project.isGit {
                        Circle()
                            .fill(TinkerApp.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: 10, y: -8)
                    }
                }
                .frame(width: 24)

                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: TinkerApp.radiusMedium)
                    .fill(pillBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: TinkerApp.radiusMedium)
                            .strokeBorder(pillBorder, lineWidth: 1)
                    }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var pillBackground: some ShapeStyle {
        if isCurrent {
            return AnyShapeStyle(TinkerApp.accent.opacity(0.1))
        } else if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.06))
        } else {
            return AnyShapeStyle(TinkerApp.surfaceBackground)
        }
    }

    private var pillBorder: some ShapeStyle {
        if isCurrent {
            return AnyShapeStyle(TinkerApp.accent.opacity(0.3))
        } else {
            return AnyShapeStyle(Color.primary.opacity(isHovered ? 0.1 : 0.06))
        }
    }
}
