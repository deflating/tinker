import Foundation
import os.log

/// Lightweight git operations service — runs git commands and parses output
@Observable
@MainActor
final class GitService {
    private let logger = Logger(subsystem: "app.familiar", category: "Git")

    // MARK: - Published State

    var branch: String?
    var isDirty: Bool = false
    var aheadBehind: (ahead: Int, behind: Int)?
    var recentCommits: [GitCommit] = []
    var changedFiles: [GitFileStatus] = []
    var branches: [String] = []
    var diffStats: (added: Int, removed: Int) = (0, 0)

    // MARK: - Worktree Management

    private static let worktreeRoot: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Familiar/worktrees", isDirectory: true)
    }()

    /// Creates a git worktree for the given session, returns the worktree path
    func createWorktree(sessionId: String, from directory: String) async -> String? {
        let worktreePath = Self.worktreeRoot.appendingPathComponent(sessionId).path
        let branchName = "familiar/\(sessionId.prefix(8))"

        // Ensure parent directory exists
        try? FileManager.default.createDirectory(at: Self.worktreeRoot, withIntermediateDirectories: true)

        // Create the worktree with a new branch
        let result = await runGit(in: directory, args: ["worktree", "add", "-b", branchName, worktreePath])
        if result.exitCode == 0 {
            logger.info("Created worktree at \(worktreePath) on branch \(branchName)")
            return worktreePath
        } else {
            logger.error("Failed to create worktree: \(result.stderr)")
            return nil
        }
    }

    /// Removes a git worktree
    func removeWorktree(path: String, from repoDirectory: String) async {
        // First try to remove the worktree via git
        let _ = await runGit(in: repoDirectory, args: ["worktree", "remove", path, "--force"])
        // Also try to delete the branch
        let branchName = await worktreeBranch(at: path)
        if let branch = branchName {
            let _ = await runGit(in: repoDirectory, args: ["branch", "-D", branch])
        }
        // Clean up directory if it still exists
        try? FileManager.default.removeItem(atPath: path)
        logger.info("Removed worktree at \(path)")
    }

    /// Gets the branch name for a worktree path
    func worktreeBranch(at path: String) async -> String? {
        let result = await runGit(in: path, args: ["rev-parse", "--abbrev-ref", "HEAD"])
        guard result.exitCode == 0 else { return nil }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    // MARK: - Status Refresh

    /// Full refresh — branch, status, ahead/behind, recent commits, diff stats
    func refresh(in directory: String) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshBranch(in: directory) }
            group.addTask { await self.refreshStatus(in: directory) }
            group.addTask { await self.refreshAheadBehind(in: directory) }
            group.addTask { await self.refreshRecentCommits(in: directory) }
            group.addTask { await self.refreshDiffStats(in: directory) }
        }
    }

    /// Quick refresh — branch, dirty state, and diff stats (for after agent turns)
    func quickRefresh(in directory: String) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshBranch(in: directory) }
            group.addTask { await self.refreshStatus(in: directory) }
            group.addTask { await self.refreshDiffStats(in: directory) }
        }
    }

    func refreshBranch(in directory: String) async {
        let result = await runGit(in: directory, args: ["rev-parse", "--abbrev-ref", "HEAD"])
        if result.exitCode == 0 {
            let b = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            branch = b.isEmpty ? nil : b
        } else {
            branch = nil
        }
    }

    func refreshStatus(in directory: String) async {
        let result = await runGit(in: directory, args: ["status", "--porcelain", "-uall"])
        if result.exitCode == 0 {
            let lines = result.stdout.split(separator: "\n").map(String.init)
            isDirty = !lines.isEmpty
            changedFiles = lines.prefix(50).compactMap { GitFileStatus(porcelainLine: $0) }
        } else {
            isDirty = false
            changedFiles = []
        }
    }

    func refreshAheadBehind(in directory: String) async {
        let result = await runGit(in: directory, args: ["rev-list", "--left-right", "--count", "@{u}...HEAD"])
        if result.exitCode == 0 {
            let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
            if parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) {
                aheadBehind = (ahead: ahead, behind: behind)
            } else {
                aheadBehind = nil
            }
        } else {
            aheadBehind = nil // no upstream
        }
    }

    func refreshRecentCommits(in directory: String) async {
        let result = await runGit(in: directory, args: [
            "log", "--oneline", "--no-decorate", "-10",
            "--format=%h\t%s\t%ar"
        ])
        if result.exitCode == 0 {
            recentCommits = result.stdout.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2)
                guard parts.count == 3 else { return nil }
                return GitCommit(hash: String(parts[0]), message: String(parts[1]), relativeDate: String(parts[2]))
            }
        } else {
            recentCommits = []
        }
    }

    func fetchBranches(in directory: String) async {
        let result = await runGit(in: directory, args: [
            "branch", "--sort=-committerdate", "--format=%(refname:short)"
        ])
        if result.exitCode == 0 {
            branches = result.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            branches = []
        }
    }

    func switchBranch(to branchName: String, in directory: String) async -> Bool {
        let result = await runGit(in: directory, args: ["checkout", branchName])
        if result.exitCode == 0 {
            await refresh(in: directory)
            return true
        }
        logger.error("Branch switch failed: \(result.stderr)")
        return false
    }

    func refreshDiffStats(in directory: String) async {
        let result = await runGit(in: directory, args: ["diff", "--stat", "HEAD"])
        if result.exitCode == 0 {
            // Also include untracked file count
            let untrackedResult = await runGit(in: directory, args: ["ls-files", "--others", "--exclude-standard"])
            let untrackedCount = untrackedResult.exitCode == 0 ? untrackedResult.stdout.split(separator: "\n").count : 0

            // Parse the summary line: " 12 files changed, 345 insertions(+), 67 deletions(-)"
            let lines = result.stdout.split(separator: "\n")
            if let summary = lines.last {
                var added = 0
                var removed = 0
                let parts = summary.split(separator: ",")
                for part in parts {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("insertion") {
                        added = Int(trimmed.split(separator: " ").first ?? "0") ?? 0
                    } else if trimmed.contains("deletion") {
                        removed = Int(trimmed.split(separator: " ").first ?? "0") ?? 0
                    }
                }
                diffStats = (added: added + untrackedCount, removed: removed)
            } else {
                diffStats = (added: untrackedCount, removed: 0)
            }
        } else {
            diffStats = (0, 0)
        }
    }

    // MARK: - Git Actions

    func commit(message: String, includeUnstaged: Bool, in directory: String) async -> Bool {
        if includeUnstaged {
            let _ = await runGit(in: directory, args: ["add", "-A"])
        }
        let result = await runGit(in: directory, args: ["commit", "-m", message])
        if result.exitCode == 0 {
            await refresh(in: directory)
            return true
        }
        logger.error("Commit failed: \(result.stderr)")
        return false
    }

    func push(in directory: String) async -> Bool {
        let result = await runGit(in: directory, args: ["push"])
        if result.exitCode == 0 {
            await refreshAheadBehind(in: directory)
            return true
        }
        logger.error("Push failed: \(result.stderr)")
        return false
    }

    func pull(in directory: String) async -> Bool {
        let result = await runGit(in: directory, args: ["pull"])
        if result.exitCode == 0 {
            await refresh(in: directory)
            return true
        }
        logger.error("Pull failed: \(result.stderr)")
        return false
    }

    func getRemoteURL(in directory: String) async -> String? {
        let result = await runGit(in: directory, args: ["remote", "get-url", "origin"])
        guard result.exitCode == 0 else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    // MARK: - Private

    private struct GitResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runGit(in directory: String, args: [String]) async -> GitResult {
        await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", directory] + args
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: GitResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: outData, encoding: .utf8) ?? "",
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    continuation.resume(returning: GitResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Models

struct GitCommit: Identifiable {
    let id = UUID()
    let hash: String
    let message: String
    let relativeDate: String
}

struct GitFileStatus: Identifiable {
    let id = UUID()
    let status: String  // "M", "A", "D", "??"
    let path: String

    init?(porcelainLine: String) {
        guard porcelainLine.count >= 4 else { return nil }
        let idx = porcelainLine.index(porcelainLine.startIndex, offsetBy: 3)
        self.status = String(porcelainLine.prefix(2)).trimmingCharacters(in: .whitespaces)
        self.path = String(porcelainLine[idx...])
    }

    var icon: String {
        switch status {
        case "M": return "pencil.circle.fill"
        case "A": return "plus.circle.fill"
        case "D": return "minus.circle.fill"
        case "??": return "questionmark.circle.fill"
        case "R": return "arrow.right.circle.fill"
        default: return "circle.fill"
        }
    }

    var color: String {
        switch status {
        case "M": return "orange"
        case "A": return "green"
        case "D": return "red"
        case "??": return "gray"
        default: return "secondary"
        }
    }
}
