import Foundation
import os.log

/// Diagnostic checks for Claude Code CLI environment.
@Observable
@MainActor
final class DoctorService {

    private let logger = Logger(subsystem: "app.tinker", category: "Doctor")

    struct Check: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        var status: Status = .pending
        var detail: String = ""
        var fix: String?

        enum Status {
            case pending, running, passed, warning, failed
        }
    }

    var checks: [Check] = []
    var isRunning = false

    func runAll(workingDirectory: String) {
        isRunning = true
        checks = [
            Check(name: "Claude CLI", description: "Claude Code binary is available on PATH"),
            Check(name: "Authentication", description: "API key or session token is configured"),
            Check(name: "Working Directory", description: "Current directory exists and is accessible"),
            Check(name: "Git Repository", description: "Working directory is a git repository"),
            Check(name: "Network", description: "Can reach Anthropic API"),
            Check(name: "Node.js", description: "Node.js runtime is available"),
        ]

        Task {
            await checkCLI()
            await checkAuth()
            await checkWorkingDirectory(workingDirectory)
            await checkGit(workingDirectory)
            await checkNetwork()
            await checkNode()
            isRunning = false
        }
    }

    // MARK: - Individual Checks

    private func checkCLI() async {
        updateCheck("Claude CLI", status: .running)
        let (exitCode, output) = await runProcess("/usr/bin/which", args: ["claude"])
        if exitCode == 0 {
            let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let (versionCode, versionOutput) = await runProcess(path, args: ["--version"])
            if versionCode == 0 {
                updateCheck("Claude CLI", status: .passed, detail: "\(path) — \(versionOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                updateCheck("Claude CLI", status: .passed, detail: path)
            }
        } else {
            // Check common locations
            let commonPaths = [
                "\(NSHomeDirectory())/.local/bin/claude",
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude"
            ]
            for p in commonPaths {
                if FileManager.default.isExecutableFile(atPath: p) {
                    updateCheck("Claude CLI", status: .warning, detail: "Found at \(p) but not on PATH", fix: "Add \(p) directory to your PATH")
                    return
                }
            }
            updateCheck("Claude CLI", status: .failed, detail: "claude binary not found", fix: "Install Claude Code: npm install -g @anthropic-ai/claude-code")
        }
    }

    private func checkAuth() async {
        updateCheck("Authentication", status: .running)
        let configPath = "\(NSHomeDirectory())/.claude.json"
        if FileManager.default.fileExists(atPath: configPath) {
            updateCheck("Authentication", status: .passed, detail: "Config file exists at ~/.claude.json")
        } else {
            let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            if envKey != nil {
                updateCheck("Authentication", status: .passed, detail: "ANTHROPIC_API_KEY environment variable set")
            } else {
                updateCheck("Authentication", status: .warning, detail: "No config file or API key found", fix: "Run 'claude' in terminal to authenticate, or set ANTHROPIC_API_KEY")
            }
        }
    }

    private func checkWorkingDirectory(_ dir: String) async {
        updateCheck("Working Directory", status: .running)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir, isDirectory: &isDir)
        if exists && isDir.boolValue {
            let writable = FileManager.default.isWritableFile(atPath: dir)
            if writable {
                updateCheck("Working Directory", status: .passed, detail: dir)
            } else {
                updateCheck("Working Directory", status: .warning, detail: "\(dir) — not writable", fix: "Check directory permissions: chmod u+w \"\(dir)\"")
            }
        } else {
            updateCheck("Working Directory", status: .failed, detail: "\(dir) — does not exist", fix: "Select a valid working directory from the status bar")
        }
    }

    private func checkGit(_ dir: String) async {
        updateCheck("Git Repository", status: .running)
        let (exitCode, _) = await runProcess("/usr/bin/git", args: ["-C", dir, "rev-parse", "--git-dir"])
        if exitCode == 0 {
            let (_, branchOutput) = await runProcess("/usr/bin/git", args: ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"])
            let branch = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            updateCheck("Git Repository", status: .passed, detail: "Branch: \(branch)")
        } else {
            updateCheck("Git Repository", status: .warning, detail: "Not a git repository", fix: "Initialize with: cd \"\(dir)\" && git init")
        }
    }

    private func checkNetwork() async {
        updateCheck("Network", status: .running)
        let (exitCode, _) = await runProcess("/usr/bin/curl", args: ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "5", "https://api.anthropic.com"])
        if exitCode == 0 {
            updateCheck("Network", status: .passed, detail: "api.anthropic.com reachable")
        } else {
            updateCheck("Network", status: .failed, detail: "Cannot reach api.anthropic.com", fix: "Check your internet connection and firewall settings")
        }
    }

    private func checkNode() async {
        updateCheck("Node.js", status: .running)
        let (exitCode, output) = await runProcess("/usr/bin/which", args: ["node"])
        if exitCode == 0 {
            let nodePath = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let (_, versionOutput) = await runProcess(nodePath, args: ["--version"])
            updateCheck("Node.js", status: .passed, detail: versionOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            updateCheck("Node.js", status: .warning, detail: "Node.js not found on PATH", fix: "Install Node.js from nodejs.org or via brew install node")
        }
    }

    // MARK: - Helpers

    private func updateCheck(_ name: String, status: Check.Status, detail: String = "", fix: String? = nil) {
        if let idx = checks.firstIndex(where: { $0.name == name }) {
            checks[idx].status = status
            if !detail.isEmpty { checks[idx].detail = detail }
            if let fix { checks[idx].fix = fix }
        }
    }

    private func runProcess(_ path: String, args: [String]) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: (process.terminationStatus, output))
                } catch {
                    continuation.resume(returning: (1, ""))
                }
            }
        }
    }
}
