import Foundation
import CoreML
import os.log

/// WordPiece tokenizer + CoreML MiniLM inference for 384-dim sentence embeddings.
final class EmbeddingService: @unchecked Sendable {

    private let logger = Logger(subsystem: "app.tinker", category: "Embedding")

    private var model: MLModel?
    private var vocab: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]
    private let seqLen = 128
    private let embeddingDim = 384

    // Special token IDs
    private var clsId: Int { vocab["[CLS]"] ?? 101 }
    private var sepId: Int { vocab["[SEP]"] ?? 102 }
    private var padId: Int { vocab["[PAD]"] ?? 0 }
    private var unkId: Int { vocab["[UNK]"] ?? 100 }

    private static let knowledgeDir: String = {
        NSHomeDirectory() + "/.familiar/knowledge"
    }()

    var isReady: Bool { model != nil && !vocab.isEmpty }

    // MARK: - Init

    init() {
        loadVocab()
        loadModel()
    }

    // MARK: - Load

    private func loadVocab() {
        let path = Self.knowledgeDir + "/vocab.txt"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            logger.warning("No vocab.txt at \(path)")
            return
        }
        let lines = content.components(separatedBy: .newlines)
        for (idx, token) in lines.enumerated() where !token.isEmpty {
            vocab[token] = idx
            idToToken[idx] = token
        }
        logger.info("Loaded vocab: \(self.vocab.count) tokens")
    }

    private func loadModel() {
        let path = Self.knowledgeDir + "/MiniLM.mlpackage"
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("No MiniLM model at \(path)")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine if available
            model = try MLModel(contentsOf: MLModel.compileModel(at: url), configuration: config)
            logger.info("Loaded MiniLM CoreML model")
        } catch {
            logger.error("Failed to load MiniLM: \(error.localizedDescription)")
        }
    }

    // MARK: - WordPiece Tokenizer

    /// Tokenize text into WordPiece token IDs with [CLS] and [SEP].
    func tokenize(_ text: String) -> (inputIds: [Int], attentionMask: [Int]) {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic tokenization: split on whitespace + punctuation
        let words = basicTokenize(cleaned)

        // WordPiece tokenization
        var tokens: [Int] = [clsId]
        for word in words {
            let subTokens = wordpieceTokenize(word)
            if tokens.count + subTokens.count >= seqLen - 1 { break }  // leave room for [SEP]
            tokens.append(contentsOf: subTokens)
        }
        tokens.append(sepId)

        // Pad to seqLen
        let attentionMask = Array(repeating: 1, count: tokens.count) + Array(repeating: 0, count: seqLen - tokens.count)
        let inputIds = tokens + Array(repeating: padId, count: seqLen - tokens.count)

        return (inputIds, attentionMask)
    }

    /// Basic pre-tokenization: lowercase, split on whitespace and punctuation.
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in text {
            if char.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if char.isPunctuation || char.isSymbol {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// WordPiece: split a word into subword tokens.
    private func wordpieceTokenize(_ word: String) -> [Int] {
        if word.count > 100 { return [unkId] }  // skip absurdly long tokens

        var tokens: [Int] = []
        var start = word.startIndex
        var isFirst = true

        while start < word.endIndex {
            var end = word.endIndex
            var found = false

            while start < end {
                let substr = isFirst ? String(word[start..<end]) : "##" + String(word[start..<end])
                if let id = vocab[substr] {
                    tokens.append(id)
                    start = end
                    found = true
                    isFirst = false
                    break
                }
                end = word.index(before: end)
            }

            if !found {
                tokens.append(unkId)
                break
            }
        }

        return tokens
    }

    // MARK: - Embedding

    /// Compute a 384-dim embedding for the given text.
    func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }

        let (inputIds, attentionMask) = tokenize(text)

        // Create MLMultiArray inputs
        guard let idsArray = try? MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float32),
              let maskArray = try? MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .float32) else {
            return nil
        }

        for i in 0..<seqLen {
            idsArray[i] = NSNumber(value: Float(inputIds[i]))
            maskArray[i] = NSNumber(value: Float(attentionMask[i]))
        }

        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: idsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])

        guard let provider,
              let output = try? model.prediction(from: provider),
              let embeddingValue = output.featureValue(for: "embedding"),
              let embeddingArray = embeddingValue.multiArrayValue else {
            return nil
        }

        // Extract embedding vector
        var result = [Float](repeating: 0, count: embeddingDim)
        for i in 0..<embeddingDim {
            result[i] = Float(truncating: embeddingArray[i])
        }
        return result
    }

    /// Compute embeddings for multiple texts in batch.
    func embedBatch(_ texts: [String]) -> [[Float]?] {
        return texts.map { embed($0) }
    }

    /// Compute cosine similarity between two embedding vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
