import Foundation

// MARK: - Errors

enum LlamaError: Error, LocalizedError, Equatable {
    case modelNotLoaded
    case busy
    case loadFailed(String)
    case invalidGGUF
    case memoryInsufficient

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "No model loaded. Assign a .gguf file in Setup."
        case .busy: return "Inference already in progress."
        case .loadFailed(let msg): return "Model load failed: \(msg)"
        case .invalidGGUF: return "File is not a valid GGUF."
        case .memoryInsufficient: return "Insufficient memory to load this model."
        }
    }
}

// MARK: - Model slot

enum ModelSlot: String, CaseIterable {
    case e2b = "E2B"
    case e4b = "E4B"
}

// MARK: - GGUF file info

struct GGUFFileInfo: Identifiable, Equatable {
    let id: URL
    let name: String
    let sizeBytes: Int64
    let architecture: String?
    let contextLength: Int32?
    let hasTemplate: Bool

    var sizeDescription: String {
        let gb = Double(sizeBytes) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - Inference config

struct InferenceConfig: Equatable {
    let nGpuLayers: Int32
    let nCtx: Int32
    let nThreads: Int32

    static let `default` = InferenceConfig(nGpuLayers: 99, nCtx: 4096, nThreads: 6)
    static let reduced   = InferenceConfig(nGpuLayers: 50, nCtx: 2048, nThreads: 6)
}
