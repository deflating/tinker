import Foundation

/// Tracks the lifecycle state of a Claude Code request.
enum CommandRunState: Equatable {
    case idle
    case running(startedAt: Date)
    case stopping
    case completed(duration: TimeInterval)
    case failed(message: String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .running, .stopping: return true
        default: return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    var displayLabel: String {
        switch self {
        case .idle: return "Ready"
        case .running: return "Working"
        case .stopping: return "Stopping"
        case .completed(let duration): return String(format: "Done (%.1fs)", duration)
        case .failed(let msg): return "Failed: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }

    var startedAt: Date? {
        if case .running(let date) = self { return date }
        return nil
    }
}
