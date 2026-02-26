import Foundation
import Network
import Observation
import os.log
import Security

// MARK: - Models

struct DiscoveredHost: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool { lhs.id == rhs.id }
}

struct SavedHost: Identifiable, Codable, Hashable {
    var id: String { "\(host):\(port)" }
    let name: String
    let host: String
    let port: UInt16
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

    // Saved hosts
    var savedHosts: [SavedHost] = []

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
    private var connection: NWConnection?
    private var authToken: String?

    init() {
        loadToken()
        loadSavedHosts()
    }

    // MARK: - Connect / Disconnect

    func connect(host: String, port: UInt16, name: String? = nil) {
        let displayName = name ?? host
        let endpoint = NWEndpoint.hostPort(host: .init(host), port: .init(rawValue: port)!)
        connectedHost = DiscoveredHost(id: "\(host):\(port)", name: displayName, endpoint: endpoint)
        state = .connecting

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwConnection = NWConnection(to: endpoint, using: params)
        self.connection = nwConnection

        nwConnection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                switch newState {
                case .ready:
                    self.logger.info("Connected to \(displayName)")
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

    // MARK: - Saved Hosts

    func saveHost(_ host: SavedHost) {
        if !savedHosts.contains(where: { $0.id == host.id }) {
            savedHosts.append(host)
            persistSavedHosts()
        }
    }

    func removeSavedHost(_ host: SavedHost) {
        savedHosts.removeAll { $0.id == host.id }
        persistSavedHosts()
    }

    private func loadSavedHosts() {
        guard let data = UserDefaults.standard.data(forKey: "savedHosts"),
              let hosts = try? JSONDecoder().decode([SavedHost].self, from: data) else { return }
        savedHosts = hosts
    }

    private func persistSavedHosts() {
        if let data = try? JSONEncoder().encode(savedHosts) {
            UserDefaults.standard.set(data, forKey: "savedHosts")
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

    func setToken(_ token: String) {
        authToken = token
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.tinker.session-auth",
            kSecAttrAccount as String: "session-token"
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = token.data(using: .utf8)!
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.warning("Failed to save token to keychain: \(status)")
        }
    }

    private func loadToken() {
        authToken = readKeychainToken(synchronizable: true)

        if authToken == nil {
            authToken = readKeychainToken(synchronizable: false)
        }

        if authToken == nil {
            authToken = readTokenFromiCloud()
        }

        if authToken == nil {
            authToken = readTokenFromFile()
        }

        if let token = authToken {
            logger.info("Auth token loaded (\(token.prefix(8))...)")
        } else {
            logger.warning("No auth token found")
        }
    }

    private func readTokenFromiCloud() -> String? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.app.tinker") else {
            return nil
        }
        let tokenURL = containerURL.appendingPathComponent("Documents/.auth-token")
        return try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readKeychainToken(synchronizable: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.tinker.session-auth",
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
