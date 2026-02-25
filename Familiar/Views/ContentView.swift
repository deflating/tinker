import SwiftUI

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @State private var seedManager = SeedManager()
    @State private var showCommandPalette = false
    @State private var showDoctor = false
    @State private var showSpotlight = false
    @State private var showTerminalPane = false
    @State private var terminalSession = EmbeddedTerminalSession()
    @State private var splitSession: Session?
    @State private var splitMessages: [ChatMessage] = []
    @State private var agentTeamWatcher = AgentTeamWatcher()
    @State private var showInspector = false
    var body: some View {
        NavigationSplitView {
            SessionSidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Group {
                if let split = splitSession {
                    HSplitView {
                        chatWithBottomPanes
                            .layoutPriority(1)

                        SplitSessionView(session: split, messages: splitMessages)
                            .frame(minWidth: 300, idealWidth: 420)
                            .overlay(alignment: .topTrailing) {
                                Button(action: { self.splitSession = nil; splitMessages = [] }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(8)
                            }
                    }
                } else {
                    chatWithBottomPanes
                }
            }
            .navigationTitle("")
            .toolbarBackground(FamiliarApp.canvasBackground.opacity(0.75), for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 4) {
                        ChatToolbarTerminal(isOpen: showTerminalPane) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTerminalPane.toggle()
                            }
                            if showTerminalPane {
                                terminalSession.startIfNeeded(in: viewModel.workingDirectory)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    ChatToolbarLeading(viewModel: viewModel)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        GitToolbarView(viewModel: viewModel)
                        ChatToolbarNotifications()
                    }
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            SessionInspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 360)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showSettings },
            set: { viewModel.showSettings = $0 }
        )) {
            SettingsConfiguratorView(
                seedManager: seedManager,
                onDismiss: { viewModel.showSettings = false }
            )
            .frame(width: 920, height: 640)
        }
        .sheet(isPresented: $showDoctor) {
            DoctorView(workingDirectory: viewModel.workingDirectory)
                .frame(width: 920, height: 640)
        }
        .overlay {
            if showCommandPalette {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }

                VStack {
                    CommandPaletteView(isPresented: $showCommandPalette) { action in
                        handlePaletteAction(action)
                    }
                    .padding(.top, 80)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay {
            if showSpotlight {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSpotlight = false
                    }

                SpotlightOverlay(isPresented: $showSpotlight) { text in
                    viewModel.newSession()
                    viewModel.sendMessage(text)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showCommandPalette)
        .animation(.easeOut(duration: 0.15), value: showSpotlight)
        .tint(Color(nsColor: .systemGray))
        .background(FamiliarApp.canvasBackground)
        .frame(minWidth: 600, minHeight: 450)
        .modifier(ContentNotificationHandlers(
            viewModel: viewModel,
            showCommandPalette: $showCommandPalette,
            showDoctor: $showDoctor,
            showSpotlight: $showSpotlight,
            showTerminalPane: $showTerminalPane,
            showInspector: $showInspector,
            splitSession: $splitSession,
            splitMessages: $splitMessages,
            terminalSession: terminalSession
        ))
    }

    @ViewBuilder
    private var chatWithBottomPanes: some View {
        if showTerminalPane {
            VSplitView {
                ChatView(viewModel: viewModel, agentTeamWatcher: agentTeamWatcher)
                    .padding(.leading, 30)
                    .layoutPriority(1)

                EmbeddedTerminalPaneView(
                    session: terminalSession,
                    workingDirectory: viewModel.workingDirectory
                )
                .frame(minHeight: 150, idealHeight: 250)
            }
        } else {
            ChatView(viewModel: viewModel, agentTeamWatcher: agentTeamWatcher)
                .padding(.leading, 30)
        }
    }

    private func handlePaletteAction(_ action: CommandPaletteView.PaletteAction) {
        switch action {
        case .newSession: viewModel.newSession()
        case .clearConversation: viewModel.clearConversation()
        case .cancelRequest: viewModel.cancelRequest()
        case .openSettings: viewModel.showSettings = true
        case .runDoctor: showDoctor = true
        case .pickDirectory: viewModel.pickWorkingDirectory()
        case .compactContext:
            viewModel.messages.append(ChatMessage(role: .system, content: "Compacting conversation context…"))
            viewModel.sendMessage("/compact")
        case .exportMarkdown:
            if let session = viewModel.currentSession {
                viewModel.exportSessionAsMarkdown(session)
            }
        }
    }
}

// MARK: - Notification Handlers (extracted to help SwiftUI type-checker)

private struct ContentNotificationHandlers: ViewModifier {
    let viewModel: ChatViewModel
    @Binding var showCommandPalette: Bool
    @Binding var showDoctor: Bool
    @Binding var showSpotlight: Bool
    @Binding var showTerminalPane: Bool
    @Binding var showInspector: Bool
    @Binding var splitSession: Session?
    @Binding var splitMessages: [ChatMessage]
    let terminalSession: EmbeddedTerminalSession

    func body(content: Content) -> some View {
        content
            .modifier(CoreNotificationHandlers(
                viewModel: viewModel,
                showCommandPalette: $showCommandPalette,
                showDoctor: $showDoctor,
                showSpotlight: $showSpotlight,
                splitSession: $splitSession,
                splitMessages: $splitMessages
            ))
            .modifier(ExtendedNotificationHandlers(
                viewModel: viewModel,
                showTerminalPane: $showTerminalPane,
                showInspector: $showInspector,
                terminalSession: terminalSession
            ))
    }
}

private struct CoreNotificationHandlers: ViewModifier {
    let viewModel: ChatViewModel
    @Binding var showCommandPalette: Bool
    @Binding var showDoctor: Bool
    @Binding var showSpotlight: Bool
    @Binding var splitSession: Session?
    @Binding var splitMessages: [ChatMessage]

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newSession)) { _ in
                viewModel.newSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearConversation)) { _ in
                viewModel.clearConversation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelRequest)) { _ in
                viewModel.cancelRequest()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectSession)) { notification in
                if let index = notification.object as? Int {
                    viewModel.selectSessionByIndex(index)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                viewModel.showSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
                showCommandPalette.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDoctor)) { _ in
                showDoctor = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSpotlight)) { _ in
                showSpotlight.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSplitSession)) { notification in
                if let session = notification.object as? Session {
                    splitMessages = viewModel.loadMessagesForSplit(sessionId: session.id)
                    splitSession = session
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .applyWorkflowPreset)) { notification in
                if let preset = notification.object as? WorkflowPreset {
                    viewModel.applyPreset(preset)
                }
            }
    }
}

private struct ExtendedNotificationHandlers: ViewModifier {
    let viewModel: ChatViewModel
    @Binding var showTerminalPane: Bool
    @Binding var showInspector: Bool
    let terminalSession: EmbeddedTerminalSession

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .exportSession)) { _ in
                if let session = viewModel.currentSession {
                    viewModel.exportSessionAsMarkdown(session)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .duplicateSession)) { _ in
                if let session = viewModel.currentSession {
                    viewModel.duplicateSession(session)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .changeDirectory)) { _ in
                viewModel.pickWorkingDirectory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleTerminal)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    showTerminalPane.toggle()
                }
                if showTerminalPane {
                    terminalSession.startIfNeeded(in: viewModel.workingDirectory)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    showInspector.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
                NotificationCenter.default.post(name: .focusInputField, object: nil)
            }
    }
}

@Observable
@MainActor
final class EmbeddedTerminalSession {
    private var process: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?

    private(set) var output: String = ""
    private(set) var isRunning: Bool = false
    private(set) var currentDirectory: String = NSHomeDirectory()
    private(set) var statusText: String = "Idle"

    func startIfNeeded(in directory: String) {
        if isRunning {
            if currentDirectory != directory {
                setWorkingDirectory(directory)
            }
            return
        }
        start(in: directory)
    }

    func start(in directory: String) {
        stop()
        currentDirectory = directory

        let proc = Process()
        let outPipe = Pipe()
        let inPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-il"]
        proc.currentDirectoryURL = URL(fileURLWithPath: directory)
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        proc.standardInput = inPipe

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        proc.environment = env

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendOutput(chunk)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.statusText = "Exited"
            }
        }

        do {
            try proc.run()
            process = proc
            outputPipe = outPipe
            inputPipe = inPipe
            isRunning = true
            statusText = "Running"
            appendOutput("familiar shell @ \(directory)\n")
        } catch {
            statusText = "Failed to start shell"
            appendOutput("Failed to start shell: \(error.localizedDescription)\n")
        }
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        outputPipe = nil
        inputPipe = nil
        isRunning = false
    }

    func restart(in directory: String) {
        start(in: directory)
    }

    func clear() {
        output = ""
    }

    func interrupt() {
        process?.interrupt()
    }

    func run(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isRunning {
            start(in: currentDirectory)
        }
        writeToShell(trimmed + "\n")
    }

    func setWorkingDirectory(_ directory: String) {
        currentDirectory = directory
        run(command: "cd \(shellQuote(directory))")
    }

    private func writeToShell(_ text: String) {
        guard let input = inputPipe?.fileHandleForWriting,
              let data = text.data(using: .utf8) else { return }
        do {
            try input.write(contentsOf: data)
        } catch {
            appendOutput("\nwrite failed: \(error.localizedDescription)\n")
        }
    }

    private func appendOutput(_ chunk: String) {
        output += chunk
        let maxChars = 250_000
        if output.count > maxChars {
            output.removeFirst(output.count - maxChars)
        }
    }

    private func shellQuote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

struct EmbeddedTerminalPaneView: View {
    @Bindable var session: EmbeddedTerminalSession
    let workingDirectory: String
    @State private var commandText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Terminal", systemImage: "terminal")
                    .font(.callout.weight(.semibold))
                Text(session.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { session.clear() }
                    .buttonStyle(.borderless)
                Button("Interrupt") { session.interrupt() }
                    .buttonStyle(.borderless)
                Button("Restart") { session.restart(in: workingDirectory) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(FamiliarApp.surfaceBackground)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.output.isEmpty ? "Starting shell…" : session.output)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.86, green: 0.9, blue: 0.88))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear
                        .frame(height: 1)
                        .id("terminal-bottom")
                }
                .background(Color.black.opacity(0.92))
                .onChange(of: session.output) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("terminal-bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("Enter command", text: $commandText)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let cmd = commandText
                        commandText = ""
                        session.run(command: cmd)
                    }
                Button("Run") {
                    let cmd = commandText
                    commandText = ""
                    session.run(command: cmd)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(FamiliarApp.surfaceBackground)
        }
        .background(FamiliarApp.canvasBackground)
        .overlay(alignment: .leading) {
            Divider()
        }
        .onAppear {
            session.startIfNeeded(in: workingDirectory)
        }
        .onChange(of: workingDirectory) {
            session.setWorkingDirectory(workingDirectory)
        }
    }
}
