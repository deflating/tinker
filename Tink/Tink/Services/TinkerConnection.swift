import Foundation
import Network
import Observation
import os.log
import Security

// MARK: - Discovered Host

struct DiscoveredHost: Identifiable, Hashable {
    let id: String  // Bonjour instance name
    let name: String
    let endpoint: NWEndpoint

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool { lhs.id == rhs.id }
}

// MARK: - Connection

@Observable
final class TinkerConnection {

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case error(String)
    }

    // Discovery
    var discoveredHosts: [DiscoveredHost] = []
    var isSearching = false

    // Connection
    var state: ConnectionState = .disconnected
    var connectedHost: DiscoveredHost?
    var messages: [ChatMessage] = []
    var sessions: [Session] = []
    var currentSession: Session?
    var isLoading = false
    var runState = ""
    var model = ""
    var gitBranch: String?

    private let logger = Logger(subsystem: "app.tinker.tink", category: "TinkerConnection")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var authToken: String?

    init() {
        loadToken()
    }

    // MARK: - Discovery

    func startSearching() {
        guard !isSearching else { return }
        isSearching = true
        discoveredHosts = []

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_tinker._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.discoveredHosts = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredHost(id: name, name: name, endpoint: result.endpoint)
                }
            }
        }

        browser?.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                if case .failed(let error) = newState {
                    self?.logger.warning("Browse failed: \(error.localizedDescription)")
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    // MARK: - Connect / Disconnect

    func connect(to host: DiscoveredHost) {
        stopSearching()
        connectedHost = host
        state = .connecting

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwConnection = NWConnection(to: host.endpoint, using: params)
        self.connection = nwConnection

        nwConnection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    self.logger.info("Connected to \(host.name)")
                    self.authenticate()
                case .failed(let error):
                    self.logger.error("Connection failed: \(error.localizedDescription)")
                    self.state = .error("Connection failed")
                    self.connection = nil
                case .cancelled:
                    self.state = .disconnected
                    self.connection = nil
                default:
                    break
                }
            }
        }

        nwConnection.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connectedHost = nil
        state = .disconnected
        messages = []
        sessions = []
        currentSession = nil
    }

    // MARK: - Send

    func sendMessage(_ text: String) {
        sendJSON(["type": "send", "text": text])
    }

    func switchSession(_ sessionId: String) {
        sendJSON(["type": "switch_session", "sessionId": sessionId])
    }

    func createNewSession() {
        sendJSON(["type": "new_session"])
    }

    // MARK: - Auth

    private func authenticate() {
        state = .authenticating
        guard let token = authToken else {
            state = .error("No auth token")
            return
        }
        sendJSON(["type": "auth", "token": token])
        receiveMessages()
    }

    // MARK: - Receive

    private func receiveMessages() {
        guard let connection else { return }

        connection.receiveMessage { [weak self] content, context, _, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.logger.warning("Receive error: \(error.localizedDescription)")
                    self.state = .error("Connection lost")
                    self.connection = nil
                    return
                }

                if let data = content {
                    self.handleData(data)
                }

                self.receiveMessages()
            }
        }
    }

    private func handleData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch type {
        case "sync":
            if state != .connected { state = .connected }

            if let messagesJSON = json["messages"],
               let messagesData = try? JSONSerialization.data(withJSONObject: messagesJSON),
               let decoded = try? decoder.decode([ChatMessage].self, from: messagesData) {
                messages = decoded
            }

            if let sessionJSON = json["session"],
               let sessionData = try? JSONSerialization.data(withJSONObject: sessionJSON),
               let decoded = try? decoder.decode(Session.self, from: sessionData) {
                currentSession = decoded
            }

            if let sessionsJSON = json["sessions"],
               let sessionsData = try? JSONSerialization.data(withJSONObject: sessionsJSON),
               let decoded = try? decoder.decode([Session].self, from: sessionsData) {
                sessions = decoded
            }

            if let stateDict = json["state"] as? [String: Any] {
                isLoading = stateDict["isLoading"] as? Bool ?? false
                runState = stateDict["runState"] as? String ?? ""
                model = stateDict["model"] as? String ?? ""
                gitBranch = stateDict["gitBranch"] as? String
            }

        case "message":
            if let messageJSON = json["message"],
               let messageData = try? JSONSerialization.data(withJSONObject: messageJSON),
               let decoded = try? decoder.decode(ChatMessage.self, from: messageData) {
                if let idx = messages.firstIndex(where: { $0.id == decoded.id }) {
                    messages[idx] = decoded
                } else {
                    messages.append(decoded)
                }
            }

        case "state":
            isLoading = json["isLoading"] as? Bool ?? false
            runState = json["runState"] as? String ?? ""

        case "pong":
            break

        default:
            logger.info("Unknown message type: \(type)")
        }
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: Any]) {
        guard let connection, let data = try? JSONSerialization.data(withJSONObject: dict) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])

        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.warning("Send error: \(error.localizedDescription)")
            }
        })
    }

    var isConnected: Bool { state == .connected }

    // MARK: - Keychain

    private func loadToken() {
        authToken = readKeychainToken(synchronizable: true)

        if authToken == nil {
            authToken = readKeychainToken(synchronizable: false)
        }

        if authToken == nil {
            authToken = readTokenFromFile()
        }

        if authToken == nil {
            logger.warning("No auth token found in keychain or file")
        }
    }

    private func readKeychainToken(synchronizable: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.familiar.session-auth",
            kSecAttrAccount as String: "session-token",
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue!
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func readTokenFromFile() -> String? {
        #if targetEnvironment(simulator)
        let path = "/Users/mattkennelly/.tinker-auth-token"
        #else
        let path = NSHomeDirectory() + "/.tinker-auth-token"
        #endif
        return try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
