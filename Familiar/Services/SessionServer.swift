import Foundation
import Network
import os.log

/// WebSocket server that exposes the current chat session to remote clients (e.g. the iOS companion app).
/// Uses Network.framework with Bonjour advertisement for local network discovery.
@MainActor
final class SessionServer {

    static let shared = SessionServer()

    private let logger = Logger(subsystem: "app.tinker", category: "SessionServer")
    private var listener: NWListener?
    private var connections: [UUID: ClientConnection] = [:]
    private let port: UInt16
    private let authToken: String

    /// Weak reference to the view model for reading state and forwarding messages.
    weak var viewModel: ChatViewModel?

    private init(port: UInt16 = 8385) {
        self.port = port
        self.authToken = KeychainSync.shared.token()
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("Failed to create listener: \(error.localizedDescription)")
            return
        }

        // Bonjour advertisement
        listener?.service = NWListener.Service(name: "Tinker", type: "_tinker._tcp")

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.logger.info("Session server listening on port \(self.port)")
                case .failed(let error):
                    self.logger.error("Listener failed: \(error.localizedDescription)")
                    self.listener = nil
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] nwConnection in
            Task { @MainActor in
                self?.handleNewConnection(nwConnection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, client) in connections {
            client.connection.cancel()
        }
        connections.removeAll()
    }

    // MARK: - Broadcasting

    /// Broadcast a new message to all authenticated clients.
    func broadcastMessage(_ message: ChatMessage) {
        let envelope = ServerEnvelope.message(message)
        broadcast(envelope)
    }

    /// Broadcast a state change to all authenticated clients.
    func broadcastState(isLoading: Bool, runState: String) {
        let envelope = ServerEnvelope.state(isLoading: isLoading, runState: runState)
        broadcast(envelope)
    }

    // MARK: - Private

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let id = UUID()
        let client = ClientConnection(id: id, connection: nwConnection, authenticated: false)
        connections[id] = client

        nwConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.logger.info("Client connected: \(id)")
                    self?.receiveMessage(from: id)
                case .failed, .cancelled:
                    self?.logger.info("Client disconnected: \(id)")
                    self?.connections.removeValue(forKey: id)
                default:
                    break
                }
            }
        }

        nwConnection.start(queue: .main)
    }

    private func receiveMessage(from clientId: UUID) {
        guard let client = connections[clientId] else { return }

        client.connection.receiveMessage { [weak self] content, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.warning("Receive error from \(clientId): \(error.localizedDescription)")
                    self.connections.removeValue(forKey: clientId)
                    return
                }

                if let data = content {
                    self.handleData(data, from: clientId)
                }

                // Continue receiving
                self.receiveMessage(from: clientId)
            }
        }
    }

    private func handleData(_ data: Data, from clientId: UUID) {
        guard var client = connections[clientId] else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        // Require explicit auth with valid token
        if !client.authenticated {
            guard type == "auth", let token = json["token"] as? String, token == self.authToken else {
                logger.warning("Rejected unauthenticated client \(clientId)")
                client.connection.cancel()
                connections.removeValue(forKey: clientId)
                return
            }
            client.authenticated = true
            connections[clientId] = client
            sendSync(to: clientId)
            return
        }

        switch type {
        case "send":
            if let text = json["text"] as? String {
                viewModel?.sendMessage(text)
            }
        case "send_attachment":
            handleAttachment(json)
        case "switch_session":
            if let sessionId = json["sessionId"] as? String,
               let session = viewModel?.sessions.first(where: { $0.id == sessionId }) {
                viewModel?.selectSession(session)
                // Send fresh sync to this client with the new session's data
                sendSync(to: clientId)
            }
        case "ping":
            send(data: #"{"type":"pong"}"#.data(using: .utf8)!, to: clientId)
        default:
            break
        }
    }

    private func handleAttachment(_ json: [String: Any]) {
        guard let filename = json["filename"] as? String,
              let base64 = json["data"] as? String,
              let data = Data(base64Encoded: base64) else { return }

        // Save to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let safeName = sanitizedAttachmentFilename(filename)
        let filePath = tempDir.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try? data.write(to: filePath)

        // Build message with file path
        let caption = json["text"] as? String
        let message: String
        if let caption {
            message = "\(caption)\n\(filePath.path)"
        } else {
            message = "Look at \(filePath.path)"
        }
        viewModel?.sendMessage(message)
    }

    private func sanitizedAttachmentFilename(_ raw: String) -> String {
        let base = URL(fileURLWithPath: raw).lastPathComponent
        let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "attachment.bin"
        }
        let filtered = cleaned.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || scalar == "/" || scalar == "\\" {
                return "_"
            }
            return Character(scalar)
        }
        return String(filtered)
    }

    private func sendSync(to clientId: UUID) {
        guard let vm = viewModel else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var dict: [String: Any] = ["type": "sync"]

        if let messagesData = try? encoder.encode(vm.messages),
           let messagesJSON = try? JSONSerialization.jsonObject(with: messagesData) {
            dict["messages"] = messagesJSON
        }

        if let session = vm.currentSession,
           let sessionData = try? encoder.encode(session),
           let sessionJSON = try? JSONSerialization.jsonObject(with: sessionData) {
            dict["session"] = sessionJSON
        }

        // Send all sessions for the sidebar
        if let sessionsData = try? encoder.encode(vm.sessions),
           let sessionsJSON = try? JSONSerialization.jsonObject(with: sessionsData) {
            dict["sessions"] = sessionsJSON
        }

        dict["state"] = [
            "isLoading": vm.isLoading,
            "runState": vm.runState.displayLabel,
            "model": vm.selectedModel,
            "gitBranch": vm.gitBranch as Any
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            send(data: data, to: clientId)
        }
    }

    private func broadcast(_ envelope: ServerEnvelope) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return }

        for (id, client) in connections where client.authenticated {
            send(data: data, to: id)
        }
    }

    private func send(data: Data, to clientId: UUID) {
        guard let client = connections[clientId] else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.warning("Send error to \(clientId): \(error.localizedDescription)")
            }
        })
    }
}

// MARK: - Supporting Types

private struct ClientConnection {
    let id: UUID
    let connection: NWConnection
    var authenticated: Bool
}

/// Codable envelope for server -> client messages.
private enum ServerEnvelope: Encodable {
    case message(ChatMessage)
    case state(isLoading: Bool, runState: String)

    private enum CodingKeys: String, CodingKey {
        case type, message, isLoading, runState
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let msg):
            try container.encode("message", forKey: .type)
            try container.encode(msg, forKey: .message)
        case .state(let loading, let state):
            try container.encode("state", forKey: .type)
            try container.encode(loading, forKey: .isLoading)
            try container.encode(state, forKey: .runState)
        }
    }
}
