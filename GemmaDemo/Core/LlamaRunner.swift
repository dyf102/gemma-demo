import Foundation
import llama

actor LlamaRunner {

    private static let backendInitialized: Void = {
        llama_backend_init()
    }()

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var isBusy = false
    private var shouldCancel = false

    private(set) var firstTokenLatency: TimeInterval = 0
    private(set) var tokensPerSecond: Double = 0

    // MARK: - Load

    func load(url: URL, config: InferenceConfig) async throws {
        _ = Self.backendInitialized
        unload()

        firstTokenLatency = 0
        tokensPerSecond = 0

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.nGpuLayers

        let loadedModel = url.path.withCString { path in
            llama_model_load_from_file(path, modelParams)
        }
        guard let loadedModel else {
            throw LlamaError.loadFailed("llama_model_load_from_file returned nil for \(url.lastPathComponent)")
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(config.nCtx)
        ctxParams.n_batch = UInt32(config.nCtx)
        ctxParams.n_ubatch = UInt32(config.nCtx)
        ctxParams.n_seq_max = 1
        ctxParams.n_threads = config.nThreads
        ctxParams.n_threads_batch = config.nThreads

        guard let loadedCtx = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw LlamaError.loadFailed("llama_init_from_model returned nil")
        }

        let samplerChainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(samplerChainParams) else {
            llama_free(loadedCtx)
            llama_model_free(loadedModel)
            throw LlamaError.loadFailed("llama_sampler_chain_init returned nil")
        }
        guard let greedy = llama_sampler_init_greedy() else {
            llama_sampler_free(chain)
            llama_free(loadedCtx)
            llama_model_free(loadedModel)
            throw LlamaError.loadFailed("llama_sampler_init_greedy returned nil")
        }

        llama_sampler_chain_add(chain, greedy)

        model = loadedModel
        ctx = loadedCtx
        sampler = chain
    }

    // MARK: - Infer

    func infer(prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    try await self.runInference(prompt: prompt, continuation: continuation)
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Cancel

    func cancel() {
        shouldCancel = true
    }

    // MARK: - Private

    private func runInference(
        prompt: String,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        guard let model, let ctx, let sampler else {
            throw LlamaError.modelNotLoaded
        }
        guard !isBusy else {
            throw LlamaError.busy
        }

        isBusy = true
        shouldCancel = false
        firstTokenLatency = 0
        tokensPerSecond = 0
        defer { isBusy = false }

        guard let vocab = llama_model_get_vocab(model) else {
            continuation.finish()
            return
        }

        let promptTokens = tokenize(prompt, vocab: vocab)
        guard !promptTokens.isEmpty else {
            continuation.finish()
            return
        }

        llama_sampler_reset(sampler)
        if let memory = llama_get_memory(ctx) {
            llama_memory_clear(memory, true)
        }

        var promptBatch = llama_batch_init(Int32(promptTokens.count), 0, 1)
        defer { llama_batch_free(promptBatch) }

        guard populate(batch: &promptBatch, tokens: promptTokens, startPos: 0, logitsOnLastOnly: true) else {
            continuation.finish()
            return
        }

        guard llama_decode(ctx, promptBatch) == 0 else {
            continuation.finish()
            return
        }

        let eosToken = llama_vocab_eos(vocab)
        let startTime = Date()
        var generatedCount = 0
        var didEmitFirstToken = false

        while !shouldCancel {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if token == eosToken || token == LLAMA_TOKEN_NULL {
                break
            }

            if !didEmitFirstToken {
                firstTokenLatency = Date().timeIntervalSince(startTime)
                didEmitFirstToken = true
            }

            llama_sampler_accept(sampler, token)

            let piece = tokenPiece(for: token, vocab: vocab)
            if !piece.isEmpty {
                continuation.yield(piece)
            }

            generatedCount += 1

            var nextBatch = llama_batch_init(1, 0, 1)
            guard populate(
                batch: &nextBatch,
                tokens: [token],
                startPos: Int32(promptTokens.count + generatedCount - 1),
                logitsOnLastOnly: true
            ) else {
                llama_batch_free(nextBatch)
                break
            }

            let decodeResult = llama_decode(ctx, nextBatch)
            llama_batch_free(nextBatch)
            guard decodeResult == 0 else {
                break
            }

            let elapsed = Date().timeIntervalSince(startTime)
            if generatedCount > 1 && elapsed > 0 {
                tokensPerSecond = Double(generatedCount) / elapsed
            }

            await Task.yield()
        }

        continuation.finish()
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let textLength = Int32(text.utf8.count)
        var capacity = max(Int(textLength) + 8, 512)
        var tokens = [llama_token](repeating: 0, count: capacity)

        func runTokenize(into storage: inout [llama_token]) -> Int32 {
            storage.withUnsafeMutableBufferPointer { buffer in
                text.withCString { textPtr in
                    llama_tokenize(
                        vocab,
                        textPtr,
                        textLength,
                        buffer.baseAddress,
                        Int32(buffer.count),
                        true,
                        true
                    )
                }
            }
        }

        var count = runTokenize(into: &tokens)
        if count < 0 {
            capacity = max(Int(-count), capacity * 2)
            tokens = [llama_token](repeating: 0, count: capacity)
            count = runTokenize(into: &tokens)
        }

        guard count > 0 else {
            return []
        }

        return Array(tokens.prefix(Int(count)))
    }

    private func tokenPiece(for token: llama_token, vocab: OpaquePointer) -> String {
        var capacity = 256

        while capacity <= 16_384 {
            var buffer = [CChar](repeating: 0, count: capacity)
            let written = buffer.withUnsafeMutableBufferPointer { rawBuffer in
                llama_token_to_piece(
                    vocab,
                    token,
                    rawBuffer.baseAddress,
                    Int32(rawBuffer.count),
                    0,
                    false
                )
            }

            if written >= 0 {
                return String(
                    bytes: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) },
                    encoding: .utf8
                ) ?? ""
            }

            capacity = max(capacity * 2, Int(-written))
        }

        return ""
    }

    private func populate(
        batch: inout llama_batch,
        tokens: [llama_token],
        startPos: Int32,
        logitsOnLastOnly: Bool
    ) -> Bool {
        guard let tokenPtr = batch.token,
              let posPtr = batch.pos,
              let nSeqIDPtr = batch.n_seq_id,
              let seqIDPtr = batch.seq_id,
              let logitsPtr = batch.logits else {
            return false
        }

        for index in tokens.indices {
            tokenPtr[index] = tokens[index]
            posPtr[index] = startPos + Int32(index)
            nSeqIDPtr[index] = 1
            seqIDPtr[index]?[0] = 0
            logitsPtr[index] = logitsOnLastOnly && index != tokens.index(before: tokens.endIndex) ? 0 : 1
        }

        batch.n_tokens = Int32(tokens.count)
        return true
    }

    private func unload() {
        if let sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }

        if let ctx {
            llama_free(ctx)
            self.ctx = nil
        }

        if let model {
            llama_model_free(model)
            self.model = nil
        }
    }
}
