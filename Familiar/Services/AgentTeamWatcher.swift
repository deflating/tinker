import Foundation

// MARK: - Data Models

struct TeamConfig: Equatable {
    let name: String
    let description: String
    let createdAt: Date
    let members: [TeamMember]
    let directoryPath: String
    let leadSessionId: String?
}

struct TeamMember: Equatable, Identifiable {
    let agentId: String
    let name: String
    let agentType: String
    let model: String
    let color: String
    var id: String { agentId }

    var isCoordinator: Bool { agentType == "coordinator" }
}

struct TeamTask: Identifiable, Equatable {
    let id: String
    let owner: String?
    let description: String
    let status: String  // "pending", "in_progress", "completed", "blocked"
}

struct InboxMessage: Identifiable, Equatable {
    let id: String  // Stable ID derived from content
    let from: String
    let text: String
    let summary: String?
    let timestamp: Date
    let color: String
    let isRead: Bool
    let isIdleNotification: Bool
}

// MARK: - AgentTeamWatcher

@Observable
@MainActor
final class AgentTeamWatcher {
    private(set) var activeTeam: TeamConfig?
    private(set) var tasks: [TeamTask] = []
    private(set) var messages: [InboxMessage] = []
    private(set) var idleAgents: Set<String> = []

    var hasActiveTeam: Bool { activeTeam != nil }

    private var timer: Timer?
    private let teamsDirectory: String
    private var fileMonitor: DispatchSourceFileSystemObject?

    init() {
        let home = NSHomeDirectory()
        teamsDirectory = "\(home)/.claude/teams"
        startPolling()
    }

    func cleanup() {
        timer?.invalidate()
        timer = nil
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    func startPolling() {
        refresh()
        // Poll every 1.5s as a fallback — FSEvents would be better but this is simpler
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: teamsDirectory) else {
            if activeTeam != nil { activeTeam = nil }
            if !messages.isEmpty { messages = [] }
            return
        }

        guard let teamDirs = try? fm.contentsOfDirectory(atPath: teamsDirectory) else { return }

        // Find teams and check if they're still alive
        var latestTeam: TeamConfig?
        var latestDate: Date = .distantPast

        for dir in teamDirs {
            let configPath = "\(teamsDirectory)/\(dir)/config.json"
            guard let data = fm.contents(atPath: configPath),
                  let parsed = parseTeamConfig(data: data, dirPath: "\(teamsDirectory)/\(dir)") else { continue }

            // Check if team is still active by looking for recent file modifications
            let isAlive = isTeamAlive(dirPath: "\(teamsDirectory)/\(dir)")
            guard isAlive else { continue }

            if parsed.createdAt > latestDate {
                latestDate = parsed.createdAt
                latestTeam = parsed
            }
        }

        activeTeam = latestTeam

        if let team = latestTeam {
            loadTasks(teamName: team.name)
            loadInboxMessages(teamDir: team.directoryPath)
        } else {
            if !tasks.isEmpty { tasks = [] }
            if !messages.isEmpty { messages = [] }
            if !idleAgents.isEmpty { idleAgents = [] }
        }
    }

    /// Check if a team directory has been modified recently (within last 5 minutes)
    private func isTeamAlive(dirPath: String) -> Bool {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-300) // 5 minutes

        // Check config.json modification time
        let configPath = "\(dirPath)/config.json"
        if let attrs = try? fm.attributesOfItem(atPath: configPath),
           let modDate = attrs[.modificationDate] as? Date,
           modDate > cutoff {
            return true
        }

        // Check inbox directory for recent messages
        let inboxDir = "\(dirPath)/inboxes"
        if let files = try? fm.contentsOfDirectory(atPath: inboxDir) {
            for file in files where file.hasSuffix(".json") {
                if let attrs = try? fm.attributesOfItem(atPath: "\(inboxDir)/\(file)"),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate > cutoff {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Parsing

    private func parseTeamConfig(data: Data, dirPath: String) -> TeamConfig? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let createdAtMs = json["createdAt"] as? Double,
              let membersArray = json["members"] as? [[String: Any]] else { return nil }

        let description = json["description"] as? String ?? ""
        let createdAt = Date(timeIntervalSince1970: createdAtMs / 1000)
        let leadSessionId = json["leadSessionId"] as? String

        let colors = ["blue", "green", "orange", "purple", "pink", "cyan", "red", "yellow"]
        let members: [TeamMember] = membersArray.enumerated().compactMap { index, m in
            guard let agentId = m["agentId"] as? String,
                  let mName = m["name"] as? String else { return nil }
            let color = m["color"] as? String ?? colors[index % colors.count]
            return TeamMember(
                agentId: agentId,
                name: mName,
                agentType: m["agentType"] as? String ?? "general-purpose",
                model: m["model"] as? String ?? "",
                color: color
            )
        }

        return TeamConfig(
            name: name,
            description: description,
            createdAt: createdAt,
            members: members,
            directoryPath: dirPath,
            leadSessionId: leadSessionId
        )
    }

    private static let sharedISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func loadTasks(teamName: String) {
        let tasksDir = "\(NSHomeDirectory())/.claude/tasks/\(teamName)"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tasksDir) else {
            if !tasks.isEmpty { tasks = [] }
            return
        }

        var loaded: [TeamTask] = []
        for file in files where file.hasSuffix(".json") {
            guard let data = fm.contents(atPath: "\(tasksDir)/\(file)"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else { continue }

            loaded.append(TeamTask(
                id: id,
                owner: json["owner"] as? String ?? json["subject"] as? String,
                description: json["description"] as? String ?? "",
                status: json["status"] as? String ?? "pending"
            ))
        }

        loaded.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        tasks = loaded
    }

    private func loadInboxMessages(teamDir: String) {
        let inboxDir = "\(teamDir)/inboxes"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: inboxDir) else {
            if !messages.isEmpty { messages = [] }
            return
        }

        var allMessages: [InboxMessage] = []
        var idle: Set<String> = []

        for file in files where file.hasSuffix(".json") {
            guard let data = fm.contents(atPath: "\(inboxDir)/\(file)"),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }

            for (index, msg) in array.enumerated() {
                guard let from = msg["from"] as? String else { continue }

                let ts = msg["timestamp"] as? String ?? ""
                let color = msg["color"] as? String ?? memberColor(for: from)
                let isRead = msg["read"] as? Bool ?? false
                let summary = msg["summary"] as? String

                let date = Self.sharedISOFormatter.date(from: ts)
                    ?? ISO8601DateFormatter().date(from: ts)
                    ?? Date()

                // Stable ID based on file + index
                let stableId = "\(file)-\(index)"

                // Parse message content
                let text = msg["text"] as? String ?? msg["content"] as? String ?? ""

                // Check if this is an idle notification
                var isIdle = false
                if text.hasPrefix("{"), let jsonData = text.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let type = parsed["type"] as? String, type == "idle_notification" {
                    isIdle = true
                    idle.insert(from)
                } else {
                    // If we see a real message from an agent, they're not idle
                    idle.remove(from)
                }

                let displayText: String
                if isIdle {
                    displayText = "\(from) is idle"
                } else if let s = summary, !s.isEmpty {
                    displayText = s
                } else {
                    displayText = text
                }

                allMessages.append(InboxMessage(
                    id: stableId,
                    from: from,
                    text: displayText,
                    summary: summary,
                    timestamp: date,
                    color: color,
                    isRead: isRead,
                    isIdleNotification: isIdle
                ))
            }
        }

        allMessages.sort { $0.timestamp < $1.timestamp }
        messages = allMessages
        idleAgents = idle
    }

    private func memberColor(for name: String) -> String {
        guard let team = activeTeam else { return "gray" }
        return team.members.first { $0.name == name }?.color ?? "gray"
    }
}
