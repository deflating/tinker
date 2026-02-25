import Foundation
import USearch
import os.log

/// HNSW vector index backed by USearch for fast approximate nearest neighbor search.
final class VectorIndex: @unchecked Sendable {

    private let logger = Logger(subsystem: "app.tinker", category: "VectorIndex")

    private var index: USearchIndex?
    private let dimensions: UInt32 = 384
    private let connectivity: UInt32 = 16

    private static let indexPath: String = {
        NSHomeDirectory() + "/.familiar/knowledge/vectors.usearch"
    }()

    var count: Int { (try? index?.count) ?? 0 }
    var isReady: Bool { index != nil }

    // MARK: - Init

    init() {
        createIndex()
        loadFromDisk()
    }

    private func createIndex() {
        do {
            index = try USearchIndex.make(
                metric: .cos,
                dimensions: dimensions,
                connectivity: connectivity,
                quantization: .f32
            )
            logger.info("Created HNSW index (dims=\(self.dimensions), M=\(self.connectivity))")
        } catch {
            logger.error("Failed to create index: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    func loadFromDisk() {
        guard let index else { return }
        let path = Self.indexPath
        guard FileManager.default.fileExists(atPath: path) else {
            logger.info("No saved index at \(path)")
            return
        }
        do {
            try index.load(path: path)
            logger.info("Loaded index: \(self.count) vectors")
        } catch {
            logger.error("Failed to load index: \(error.localizedDescription)")
        }
    }

    func saveToDisk() {
        guard let index else { return }
        do {
            try index.save(path: Self.indexPath)
            logger.info("Saved index: \(self.count) vectors")
        } catch {
            logger.error("Failed to save index: \(error.localizedDescription)")
        }
    }

    // MARK: - Add / Remove

    func add(key: USearchKey, vector: [Float]) throws {
        guard let index else { return }
        try index.add(key: key, vector: vector)
    }

    func contains(key: USearchKey) -> Bool {
        (try? index?.contains(key: key)) ?? false
    }

    func remove(key: USearchKey) throws {
        guard let index else { return }
        _ = try index.remove(key: key)
    }

    func reserve(_ count: Int) throws {
        guard let index else { return }
        try index.reserve(UInt32(count))
    }

    func clear() throws {
        guard let index else { return }
        try index.clear()
    }

    // MARK: - Search

    func search(vector: [Float], count: Int) -> (keys: [USearchKey], distances: [Float]) {
        guard let index, self.count > 0 else { return ([], []) }
        do {
            let (keys, distances) = try index.search(vector: vector, count: count)
            return (keys, distances)
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return ([], [])
        }
    }

    // MARK: - Key Hashing

    /// FNV-1a hash for deterministic string→UInt64 mapping.
    static func hashKey(_ id: String) -> USearchKey {
        var hash: UInt64 = 14695981039346656037
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return USearchKey(hash)
    }
}
