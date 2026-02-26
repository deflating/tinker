import Foundation
import os

private let log = Logger(subsystem: "app.tinker", category: "iCloud")

final class iCloudSyncService {
    static let shared = iCloudSyncService()

    private let fm = FileManager.default
    private let containerID = "iCloud.app.tinker"

    struct SyncMapping {
        let localPath: String
        let cloudRelativePath: String
    }

    private let mappings: [SyncMapping] = [
        .init(localPath: "~/.memorable/data", cloudRelativePath: "memorable"),
        .init(localPath: "~/.familiar/seeds", cloudRelativePath: "familiar/seeds"),
        .init(localPath: "~/.familiar/transcripts", cloudRelativePath: "familiar/transcripts"),
    ]

    func setup() {
        log.info("Starting iCloud sync setup...")

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard let containerURL = fm.url(forUbiquityContainerIdentifier: containerID) else {
                log.error("Container '\(self.containerID)' not available. Check entitlements and iCloud sign-in.")
                return
            }

            log.info("Container found: \(containerURL.path)")
            let docsURL = containerURL.appendingPathComponent("Documents")

            for mapping in mappings {
                let cloudDir = docsURL.appendingPathComponent(mapping.cloudRelativePath)
                let localDir = NSString(string: mapping.localPath).expandingTildeInPath

                log.info("Processing: \(mapping.localPath) → \(mapping.cloudRelativePath)")
                ensureDirectoryExists(cloudDir)
                migrateIfNeeded(from: localDir, to: cloudDir)
                createSymlinkIfNeeded(from: localDir, to: cloudDir)
                pinFiles(in: cloudDir)
            }

            log.info("Sync setup complete")
        }
    }

    private func ensureDirectoryExists(_ url: URL) {
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                log.info("Created directory: \(url.path)")
            } catch {
                log.error("Failed to create directory \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private func migrateIfNeeded(from localPath: String, to cloudURL: URL) {
        guard fm.fileExists(atPath: localPath) else {
            log.info("Local path doesn't exist, skipping migration: \(localPath)")
            return
        }

        // Don't migrate if localPath is already a symlink
        if let _ = try? fm.destinationOfSymbolicLink(atPath: localPath) {
            log.info("Already a symlink, skipping migration: \(localPath)")
            return
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: localPath, isDirectory: &isDir), isDir.boolValue else { return }

        let contents = (try? fm.contentsOfDirectory(atPath: localPath)) ?? []
        for file in contents where !file.hasPrefix(".") {
            let src = (localPath as NSString).appendingPathComponent(file)
            let dst = cloudURL.appendingPathComponent(file)

            if !fm.fileExists(atPath: dst.path) {
                do {
                    try fm.copyItem(atPath: src, toPath: dst.path)
                    log.info("Migrated \(file) → iCloud")
                } catch {
                    log.error("Failed to migrate \(file): \(error.localizedDescription)")
                }
            }
        }
    }

    private func createSymlinkIfNeeded(from localPath: String, to cloudURL: URL) {
        let parentDir = (localPath as NSString).deletingLastPathComponent

        if !fm.fileExists(atPath: parentDir) {
            try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        if let dest = try? fm.destinationOfSymbolicLink(atPath: localPath) {
            if dest == cloudURL.path {
                log.info("Symlink already correct: \(localPath)")
                return
            }
            try? fm.removeItem(atPath: localPath)
        } else if fm.fileExists(atPath: localPath) {
            let backup = localPath + ".pre-icloud"
            do {
                try fm.moveItem(atPath: localPath, toPath: backup)
                log.info("Backed up \(localPath) → \(backup)")
            } catch {
                log.error("Failed to backup \(localPath): \(error.localizedDescription)")
            }
        }

        do {
            try fm.createSymbolicLink(atPath: localPath, withDestinationPath: cloudURL.path)
            log.info("Symlinked \(localPath) → \(cloudURL.path)")
        } catch {
            log.error("Failed to create symlink: \(error.localizedDescription)")
        }
    }

    private func pinFiles(in directoryURL: URL) {
        guard let contents = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { return }
        for fileURL in contents {
            try? (fileURL as NSURL).setResourceValue(false, forKey: .ubiquitousItemIsExcludedFromSyncKey)
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
        }
    }
}
