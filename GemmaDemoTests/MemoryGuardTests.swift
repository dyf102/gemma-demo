import XCTest
@testable import GemmaDemo

final class MemoryGuardTests: XCTestCase {

    func test_e2b_iPhone15Pro_returnsDefault() {
        XCTAssertEqual(
            MemoryGuard.config(for: .e2b, deviceIdentifier: "iPhone16,1"),
            .default
        )
    }

    func test_e4b_iPhone15Pro_returnsReduced() {
        XCTAssertEqual(
            MemoryGuard.config(for: .e4b, deviceIdentifier: "iPhone16,1"),
            .reduced
        )
    }

    func test_e4b_iPhone15ProMax_returnsReduced() {
        XCTAssertEqual(
            MemoryGuard.config(for: .e4b, deviceIdentifier: "iPhone16,2"),
            .reduced
        )
    }

    func test_e4b_unknownDevice_throwsInsufficient() {
        XCTAssertThrowsError(
            try MemoryGuard.configOrThrow(for: .e4b, deviceIdentifier: "iPhone14,2")
        ) { error in
            guard case LlamaError.memoryInsufficient = error else {
                return XCTFail("Expected memoryInsufficient, got \(error)")
            }
        }
    }

    func test_e2b_unknownDevice_returnsDefault() throws {
        XCTAssertEqual(
            try MemoryGuard.configOrThrow(for: .e2b, deviceIdentifier: "iPhone14,2"),
            .default
        )
    }

    func test_liveDevice_doesNotCrash() {
        XCTAssertFalse(MemoryGuard.currentDeviceIdentifier().isEmpty)
    }
}
