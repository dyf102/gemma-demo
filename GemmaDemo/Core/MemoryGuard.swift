import Foundation
import Darwin

struct MemoryGuard {
    private static let knownSafe_E4B: Set<String> = [
        "iPhone16,1",
        "iPhone16,2",
        "iPhone17,1",
        "iPhone17,2",
        "iPhone17,3",
        "iPhone17,4",
    ]

    static func config(for slot: ModelSlot, deviceIdentifier: String) -> InferenceConfig {
        switch slot {
        case .e2b:
            return .default
        case .e4b:
            return knownSafe_E4B.contains(deviceIdentifier) ? .reduced : .default
        }
    }

    static func configOrThrow(for slot: ModelSlot, deviceIdentifier: String) throws -> InferenceConfig {
        switch slot {
        case .e2b:
            return .default
        case .e4b:
            guard knownSafe_E4B.contains(deviceIdentifier) else {
                throw LlamaError.memoryInsufficient
            }
            return .reduced
        }
    }

    static func currentDeviceIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)

        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)

        return String(cString: machine)
    }
}
