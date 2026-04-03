import XCTest
@testable import GemmaDemo

final class ModelStoreTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_scanDirectory_returnsOnlyGGUFFiles() {
        writeFile("model.gguf", magic: true)
        writeFile("readme.txt", magic: false)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        XCTAssertEqual(store.availableFiles.count, 1)
        XCTAssertEqual(store.availableFiles.first?.name, "model.gguf")
    }

    func test_invalidMagic_fileExcluded() {
        writeFile("bad.gguf", magic: false)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        XCTAssertTrue(store.availableFiles.isEmpty)
    }

    func test_validGGUF_hasSizePopulated() {
        writeFile("model.gguf", magic: true)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        XCTAssertGreaterThan(store.availableFiles.first?.sizeBytes ?? 0, 0)
    }

    func test_assignSlot_persists() {
        writeFile("model.gguf", magic: true)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        let file = store.availableFiles.first!
        store.assign(file: file, to: .e2b)
        XCTAssertEqual(store.assignment(for: .e2b)?.name, "model.gguf")
    }

    func test_clearSlot_removesAssignment() {
        writeFile("model.gguf", magic: true)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        store.assign(file: store.availableFiles.first!, to: .e2b)
        store.clearAssignment(for: .e2b)
        XCTAssertNil(store.assignment(for: .e2b))
    }

    private func writeFile(_ name: String, magic: Bool) {
        let url = tempDir.appendingPathComponent(name)
        let data: Data = magic
            ? Data([0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00])
            : Data([0x00, 0x01, 0x02, 0x03])
        try! data.write(to: url)
    }
}
