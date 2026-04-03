# GemmaDemo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI iOS app that loads Gemma 4 E2B and E4B GGUF models from the device's Documents folder and benchmarks their tax Q&A reasoning quality on iPhone 15 Pro.

**Architecture:** `LlamaRunner` (Swift actor) wraps the llama.cpp C API with full Metal offload. `PromptBuilder` formats prompts using Gemma 4's chat template. `TestSuite` runs 20 hardcoded tax Q&A questions against a fake Canadian tax JSON fixture and evaluates answers against deterministic rules. Three SwiftUI views cover setup, freeform chat, and batch testing.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, llama.cpp XCFramework (Metal), xcodegen for project generation, XCTest.

**Spec:** `docs/superpowers/specs/2026-04-02-gemma-demo-design.md`

**Parallelism note:** Tasks 3 and 4 are independent and can be dispatched in parallel after Task 2 completes. Tasks 8, 9, 10 are independent and can be dispatched in parallel after Task 7 completes.

---

## File Map

| File | Responsibility |
|---|---|
| `project.yml` | xcodegen project definition |
| `GemmaDemo/Core/Types.swift` | Shared enums and structs: `LlamaError`, `GGUFFileInfo`, `ModelSlot`, `InferenceConfig` |
| `GemmaDemo/Core/PromptBuilder.swift` | Pure struct. Gemma 4 chat template formatting. Tax mode and raw mode system prompts. |
| `GemmaDemo/Core/MemoryGuard.swift` | Pure struct. Device heuristic via `sysctlbyname`. Returns `InferenceConfig` per slot. |
| `GemmaDemo/Core/ModelStore.swift` | `@Observable` class. Scans `Documents/*.gguf`, validates, persists slot assignments as bookmark data. |
| `GemmaDemo/Core/LlamaRunner.swift` | Swift actor. llama.cpp C API wrapper. Metal inference, streaming via `AsyncStream`, cancellation, metrics. |
| `GemmaDemo/Core/TestSuite.swift` | Struct. 20 hardcoded questions, `EvalRule`, thermal management, JSON export. |
| `GemmaDemo/Resources/TaxFixture.json` | Static fake Canadian tax data injected into every test prompt. |
| `GemmaDemo/Views/SetupView.swift` | Lists `.gguf` files, slot pickers, E4B confirmation dialog. |
| `GemmaDemo/Views/ChatView.swift` | Freeform chat with model toggle, tax/raw mode, streaming display, metrics. |
| `GemmaDemo/Views/TestSuiteView.swift` | Batch test runner, thermal banner, pass/fail table, JSON export. |
| `GemmaDemo/GemmaDemoApp.swift` | App entry point. Injects `ModelStore` and `LlamaRunner` as environment objects. |
| `GemmaDemoTests/PromptBuilderTests.swift` | Unit tests for chat template and system prompt formatting. |
| `GemmaDemoTests/MemoryGuardTests.swift` | Unit tests for device heuristic and config selection. |
| `GemmaDemoTests/ModelStoreTests.swift` | Unit tests for GGUF magic validation and file info parsing. |
| `GemmaDemoTests/TestSuiteEvalTests.swift` | Unit tests for `EvalRule` evaluation logic. |

---

## Task 1: Project scaffold

**Files:**
- Create: `project.yml`
- Create: `GemmaDemo/Info.plist`
- Create: `GemmaDemo/GemmaDemoApp.swift` (stub)

- [ ] **Step 1: Install xcodegen if not present**

```bash
which xcodegen || brew install xcodegen
```

Expected: prints a path or installs successfully.

- [ ] **Step 2: Find the llama.cpp iOS XCFramework release URL**

```bash
curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest \
  | python3 -c "import sys,json; r=json.load(sys.stdin); [print(a['browser_download_url']) for a in r['assets'] if 'xcframework' in a['name'].lower() and 'ios' in a['name'].lower() or 'apple' in a['name'].lower()]"
```

If this returns nothing, visit https://github.com/ggml-org/llama.cpp/releases manually and find the XCFramework zip asset. Copy the URL and compute its SHA256:

```bash
curl -L -o /tmp/llama.xcframework.zip "<URL_FROM_ABOVE>"
shasum -a 256 /tmp/llama.xcframework.zip
```

Save the URL and checksum — you will need them in Step 3.

- [ ] **Step 3: Write project.yml**

Replace `XCFRAMEWORK_URL` and `XCFRAMEWORK_SHA256` with the values from Step 2.

```yaml
name: GemmaDemo
options:
  bundleIdPrefix: com.slipcheck
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "15.4"
  createIntermediateGroups: true

packages:
  llama:
    url: XCFRAMEWORK_URL
    checksum: XCFRAMEWORK_SHA256

targets:
  GemmaDemo:
    type: application
    platform: iOS
    sources:
      - path: GemmaDemo
    settings:
      base:
        SWIFT_VERSION: "5.9"
        PRODUCT_BUNDLE_IDENTIFIER: com.slipcheck.GemmaDemo
        INFOPLIST_FILE: GemmaDemo/Info.plist
    dependencies:
      - package: llama

  GemmaDemoTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: GemmaDemoTests
    settings:
      base:
        SWIFT_VERSION: "5.9"
    dependencies:
      - target: GemmaDemo
```

- [ ] **Step 4: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>UILaunchStoryboardName</key>
    <string></string>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create stub app entry point**

`GemmaDemo/GemmaDemoApp.swift`:
```swift
import SwiftUI

@main
struct GemmaDemoApp: App {
    var body: some Scene {
        WindowGroup {
            Text("GemmaDemo")
        }
    }
}
```

- [ ] **Step 6: Create test directory stub**

```bash
mkdir -p GemmaDemoTests
cat > GemmaDemoTests/Placeholder.swift << 'EOF'
import XCTest
EOF
```

- [ ] **Step 7: Generate Xcode project**

```bash
xcodegen generate
```

Expected: `GemmaDemo.xcodeproj` created. Open in Xcode and verify it builds for iPhone 15 Pro simulator.

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -5
```

Expected last line: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git init
git add project.yml GemmaDemo/ GemmaDemoTests/ GemmaDemo.xcodeproj
git commit -m "feat: scaffold GemmaDemo Xcode project with llama.cpp XCFramework"
```

---

## Task 2: Shared types

**Files:**
- Create: `GemmaDemo/Core/Types.swift`

- [ ] **Step 1: Write Types.swift**

```swift
import Foundation

// MARK: - Errors

enum LlamaError: Error, LocalizedError {
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
    let id: URL           // file URL is the stable identifier
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

// MARK: - Inference config (chosen by MemoryGuard)

struct InferenceConfig: Equatable {
    let nGpuLayers: Int32
    let nCtx: Int32
    let nThreads: Int32

    static let `default` = InferenceConfig(nGpuLayers: 99, nCtx: 4096, nThreads: 6)
    static let reduced   = InferenceConfig(nGpuLayers: 50, nCtx: 2048, nThreads: 6)
}
```

- [ ] **Step 2: Build to verify types compile**

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add GemmaDemo/Core/Types.swift
git commit -m "feat: add shared types (LlamaError, ModelSlot, GGUFFileInfo, InferenceConfig)"
```

---

## Task 3: PromptBuilder

**Files:**
- Create: `GemmaDemo/Core/PromptBuilder.swift`
- Create: `GemmaDemoTests/PromptBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

`GemmaDemoTests/PromptBuilderTests.swift`:
```swift
import XCTest
@testable import GemmaDemo

final class PromptBuilderTests: XCTestCase {

    // MARK: - Chat template

    func test_taxMode_wrapsInGemmaTemplate() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "What is box14?")
        XCTAssertTrue(prompt.hasPrefix("<start_of_turn>user\n"), "Must start with Gemma user turn")
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"), "Must end with model turn opener")
    }

    func test_taxMode_containsFixtureJSON() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "Any question")
        XCTAssertTrue(prompt.contains("85000"), "Must include fixture field value")
        XCTAssertTrue(prompt.contains("T4"), "Must include fixture document type")
    }

    func test_taxMode_containsSystemInstruction() {
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: "Any question")
        XCTAssertTrue(prompt.contains("Never invent"), "Must include hallucination guard instruction")
        XCTAssertTrue(prompt.contains("I don't have enough information"), "Must include refusal template phrase")
    }

    func test_taxMode_containsUserQuestion() {
        let question = "How much tax was withheld?"
        let prompt = PromptBuilder.build(mode: .tax(fixture: sampleFixture), userQuestion: question)
        XCTAssertTrue(prompt.contains(question))
    }

    func test_rawMode_noSystemPrompt_noFixture() {
        let question = "Hello"
        let prompt = PromptBuilder.build(mode: .raw, userQuestion: question)
        XCTAssertFalse(prompt.contains("Never invent"))
        XCTAssertFalse(prompt.contains("85000"))
        XCTAssertTrue(prompt.contains(question))
        XCTAssertTrue(prompt.hasPrefix("<start_of_turn>user\n"))
        XCTAssertTrue(prompt.hasSuffix("<start_of_turn>model\n"))
    }

    func test_template_structure_order() {
        let prompt = PromptBuilder.build(mode: .raw, userQuestion: "Q")
        let userTurnRange = prompt.range(of: "<start_of_turn>user")!
        let endTurnRange  = prompt.range(of: "<end_of_turn>")!
        let modelTurnRange = prompt.range(of: "<start_of_turn>model")!
        XCTAssertLessThan(userTurnRange.lowerBound, endTurnRange.lowerBound)
        XCTAssertLessThan(endTurnRange.lowerBound, modelTurnRange.lowerBound)
    }

    // MARK: - Helpers

    private let sampleFixture = """
    {"tax_year":2024,"documents":[{"type":"T4","box14":85000}],"onboarding":{"had_employment":true}}
    """
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/PromptBuilderTests \
  2>&1 | grep -E "(error:|FAILED|BUILD FAILED)"
```

Expected: build error — `PromptBuilder` not yet defined.

- [ ] **Step 3: Implement PromptBuilder**

`GemmaDemo/Core/PromptBuilder.swift`:
```swift
import Foundation

enum PromptMode {
    case tax(fixture: String)
    case raw
}

struct PromptBuilder {

    static func build(mode: PromptMode, userQuestion: String) -> String {
        let userContent: String
        switch mode {
        case .tax(let fixture):
            userContent = """
            \(systemPrompt)

            Documents:
            \(fixture)

            \(userQuestion)
            """
        case .raw:
            userContent = userQuestion
        }
        return "<start_of_turn>user\n\(userContent)<end_of_turn>\n<start_of_turn>model\n"
    }

    static let systemPrompt = """
    You are a tax document review assistant.
    Answer only based on the structured document data below.
    Never invent, estimate, or approximate numeric values not present in the data.
    If you cannot answer from the data, say: "I don't have enough information in the provided documents to answer that."
    """
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/PromptBuilderTests \
  2>&1 | grep -E "(Test Suite|PASSED|FAILED)"
```

Expected: `Test Suite 'PromptBuilderTests' passed`

- [ ] **Step 5: Commit**

```bash
git add GemmaDemo/Core/PromptBuilder.swift GemmaDemoTests/PromptBuilderTests.swift
git commit -m "feat: add PromptBuilder with Gemma 4 chat template and tax mode system prompt"
```

---

## Task 4: MemoryGuard

**Files:**
- Create: `GemmaDemo/Core/MemoryGuard.swift`
- Create: `GemmaDemoTests/MemoryGuardTests.swift`

- [ ] **Step 1: Write failing tests**

`GemmaDemoTests/MemoryGuardTests.swift`:
```swift
import XCTest
@testable import GemmaDemo

final class MemoryGuardTests: XCTestCase {

    func test_e2b_iPhone15Pro_returnsDefault() {
        let config = MemoryGuard.config(for: .e2b, deviceIdentifier: "iPhone16,1")
        XCTAssertEqual(config, .default)
    }

    func test_e4b_iPhone15Pro_returnsReduced() {
        let config = MemoryGuard.config(for: .e4b, deviceIdentifier: "iPhone16,1")
        XCTAssertEqual(config, .reduced)
    }

    func test_e4b_iPhone15ProMax_returnsReduced() {
        let config = MemoryGuard.config(for: .e4b, deviceIdentifier: "iPhone16,2")
        XCTAssertEqual(config, .reduced)
    }

    func test_e4b_unknownDevice_throwsInsufficient() {
        XCTAssertThrowsError(try MemoryGuard.configOrThrow(for: .e4b, deviceIdentifier: "iPhone14,2")) { error in
            XCTAssertEqual(error as? LlamaError, .memoryInsufficient)
        }
    }

    func test_e2b_unknownDevice_returnsDefault() {
        let config = MemoryGuard.config(for: .e2b, deviceIdentifier: "iPhone14,2")
        XCTAssertEqual(config, .default)
    }

    func test_liveDevice_doesNotCrash() {
        // Smoke test: just ensure it doesn't crash on the real device identifier
        let id = MemoryGuard.currentDeviceIdentifier()
        XCTAssertFalse(id.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/MemoryGuardTests \
  2>&1 | grep -E "(error:|FAILED|BUILD FAILED)"
```

Expected: build error — `MemoryGuard` not yet defined.

- [ ] **Step 3: Implement MemoryGuard**

`GemmaDemo/Core/MemoryGuard.swift`:
```swift
import Foundation

struct MemoryGuard {

    // iPhone 15 Pro = iPhone16,1 ; iPhone 15 Pro Max = iPhone16,2
    private static let knownSafe_E4B: Set<String> = ["iPhone16,1", "iPhone16,2"]
    // All iPhone 15 Pro and later are safe for E2B
    private static let knownSafe_E2B: Set<String> = [
        "iPhone16,1", "iPhone16,2",  // 15 Pro, 15 Pro Max
        "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4"  // 16 series
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
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/MemoryGuardTests \
  2>&1 | grep -E "(Test Suite|PASSED|FAILED)"
```

Expected: `Test Suite 'MemoryGuardTests' passed`

- [ ] **Step 5: Commit**

```bash
git add GemmaDemo/Core/MemoryGuard.swift GemmaDemoTests/MemoryGuardTests.swift
git commit -m "feat: add MemoryGuard with device-model heuristic for E2B/E4B config"
```

---

## Task 5: ModelStore

**Files:**
- Create: `GemmaDemo/Core/ModelStore.swift`
- Create: `GemmaDemoTests/ModelStoreTests.swift`

- [ ] **Step 1: Write failing tests**

`GemmaDemoTests/ModelStoreTests.swift`:
```swift
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

    func test_scanDirectory_returnsOnlyGGUFFiles() throws {
        writeFile("model.gguf", magic: true)
        writeFile("readme.txt", magic: false)
        let store = ModelStore(documentsURL: tempDir)
        store.refresh()
        XCTAssertEqual(store.availableFiles.count, 1)
        XCTAssertEqual(store.availableFiles.first?.name, "model.gguf")
    }

    func test_invalidMagic_fileExcluded() throws {
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

    // MARK: - Helpers

    private func writeFile(_ name: String, magic: Bool) {
        let url = tempDir.appendingPathComponent(name)
        var data = Data()
        if magic {
            // GGUF magic: 0x47475546 (little-endian: 46 55 47 47)
            data = Data([0x47, 0x47, 0x55, 0x46, 0x03, 0x00, 0x00, 0x00])
        } else {
            data = Data([0x00, 0x01, 0x02, 0x03])
        }
        try! data.write(to: url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/ModelStoreTests \
  2>&1 | grep -E "(error:|FAILED|BUILD FAILED)"
```

Expected: build error — `ModelStore` not yet defined.

- [ ] **Step 3: Implement ModelStore**

`GemmaDemo/Core/ModelStore.swift`:
```swift
import Foundation
import Observation

@Observable
final class ModelStore {

    private(set) var availableFiles: [GGUFFileInfo] = []
    private var assignments: [ModelSlot: GGUFFileInfo] = [:]

    private let documentsURL: URL
    private static let ggufMagic: [UInt8] = [0x47, 0x47, 0x55, 0x46]

    private(set) var clearedSlots: Set<ModelSlot> = []  // set when stale bookmarks are removed on launch

    init(documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.documentsURL = documentsURL
        restoreAssignments()
    }

    private func restoreAssignments() {
        for slot in ModelSlot.allCases {
            guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey(slot)) else { continue }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI,
                                      relativeTo: nil, bookmarkDataIsStale: &isStale),
                  !isStale, FileManager.default.fileExists(atPath: url.path) else {
                UserDefaults.standard.removeObject(forKey: bookmarkKey(slot))
                clearedSlots.insert(slot)
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
            assignments[slot] = GGUFFileInfo(id: url, name: url.lastPathComponent, sizeBytes: size,
                                              architecture: nil, contextLength: nil, hasTemplate: false)
        }
    }

    func refresh() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: documentsURL,
                                                 includingPropertiesForKeys: [.fileSizeKey],
                                                 options: .skipsHiddenFiles)) ?? []
        availableFiles = urls
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .compactMap { url -> GGUFFileInfo? in
                guard validateMagic(url) else { return nil }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                return GGUFFileInfo(id: url, name: url.lastPathComponent, sizeBytes: size,
                                    architecture: nil, contextLength: nil, hasTemplate: false)
            }
    }

    func assign(file: GGUFFileInfo, to slot: ModelSlot) {
        assignments[slot] = file
        persistAssignment(file.id, for: slot)
    }

    func clearAssignment(for slot: ModelSlot) {
        assignments[slot] = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey(slot))
    }

    func assignment(for slot: ModelSlot) -> GGUFFileInfo? {
        assignments[slot]
    }

    // MARK: - Private

    private func validateMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: 4)
        return data.map { Array($0) == Self.ggufMagic } ?? false
    }

    private func bookmarkKey(_ slot: ModelSlot) -> String { "bookmark_\(slot.rawValue)" }

    private func persistAssignment(_ url: URL, for slot: ModelSlot) {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey(slot))
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/ModelStoreTests \
  2>&1 | grep -E "(Test Suite|PASSED|FAILED)"
```

Expected: `Test Suite 'ModelStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add GemmaDemo/Core/ModelStore.swift GemmaDemoTests/ModelStoreTests.swift
git commit -m "feat: add ModelStore with GGUF validation and bookmark-based slot persistence"
```

---

## Task 6: LlamaRunner

**Files:**
- Create: `GemmaDemo/Core/LlamaRunner.swift`

No unit tests — llama.cpp model load requires a real GGUF file. Integration tested manually on device.

- [ ] **Step 1: Implement LlamaRunner**

`GemmaDemo/Core/LlamaRunner.swift`:
```swift
import Foundation
import llama

actor LlamaRunner {

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var sampler: OpaquePointer?
    private var isBusy = false
    private var shouldCancel = false

    private(set) var firstTokenLatency: TimeInterval = 0
    private(set) var tokensPerSecond: Double = 0

    // MARK: - Load

    func load(url: URL, config: InferenceConfig) async throws {
        unload()
        let path = url.path

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.nGpuLayers

        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.loadFailed("llama_model_load_from_file returned nil for \(url.lastPathComponent)")
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(config.nCtx)
        ctxParams.n_threads = config.nThreads
        ctxParams.n_threads_batch = config.nThreads

        guard let loadedCtx = llama_new_context_with_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw LlamaError.loadFailed("llama_new_context_with_model returned nil")
        }

        let samplerChainParams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(samplerChainParams) else {
            llama_free(loadedCtx)
            llama_model_free(loadedModel)
            throw LlamaError.loadFailed("llama_sampler_chain_init returned nil")
        }
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        self.model = loadedModel
        self.ctx = loadedCtx
        self.sampler = chain
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

    private func runInference(prompt: String, continuation: AsyncStream<String>.Continuation) async throws {
        guard let model, let ctx, let sampler else { throw LlamaError.modelNotLoaded }
        guard !isBusy else { throw LlamaError.busy }
        isBusy = true
        shouldCancel = false
        defer { isBusy = false }

        let promptBytes = Array(prompt.utf8)
        let maxTokens = 512
        var tokens = [llama_token](repeating: 0, count: maxTokens)
        let nTokens = llama_tokenize(model, promptBytes, Int32(promptBytes.count),
                                     &tokens, Int32(maxTokens), true, true)
        guard nTokens > 0 else { continuation.finish(); return }

        var batch = llama_batch_init(Int32(nTokens), 0, 1)
        defer { llama_batch_free(batch) }

        for i in 0..<Int(nTokens) {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = i == Int(nTokens) - 1 ? 1 : 0
        }
        batch.n_tokens = nTokens

        llama_kv_cache_clear(ctx)
        guard llama_decode(ctx, batch) == 0 else { continuation.finish(); return }

        let eosToken = llama_model_token_eos(model)
        let startTime = Date()
        var firstToken = true
        var tokenCount = 0
        var buf = [CChar](repeating: 0, count: 256)

        while !shouldCancel {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if token == eosToken { break }

            if firstToken {
                firstTokenLatency = Date().timeIntervalSince(startTime)
                firstToken = false
            }

            let n = llama_token_to_piece(model, token, &buf, 256, 0, false)
            if n > 0 {
                let piece = String(bytes: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
                continuation.yield(piece)
            }
            tokenCount += 1

            var nextBatch = llama_batch_init(1, 0, 1)
            defer { llama_batch_free(nextBatch) }
            nextBatch.token[0] = token
            nextBatch.pos[0] = nTokens + Int32(tokenCount) - 1
            nextBatch.n_seq_id[0] = 1
            nextBatch.seq_id[0]![0] = 0
            nextBatch.logits[0] = 1
            nextBatch.n_tokens = 1

            guard llama_decode(ctx, nextBatch) == 0 else { break }

            if tokenCount > 1 {
                tokensPerSecond = Double(tokenCount) / Date().timeIntervalSince(startTime)
            }

            await Task.yield()
        }

        continuation.finish()
    }

    private func unload() {
        if let s = sampler { llama_sampler_free(s); self.sampler = nil }
        if let c = ctx { llama_free(c); self.ctx = nil }
        if let m = model { llama_model_free(m); self.model = nil }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add GemmaDemo/Core/LlamaRunner.swift
git commit -m "feat: add LlamaRunner actor with Metal inference, AsyncStream, and cancellation"
```

---

## Task 7: TaxFixture + TestSuite

**Files:**
- Create: `GemmaDemo/Resources/TaxFixture.json`
- Create: `GemmaDemo/Core/TestSuite.swift`
- Create: `GemmaDemoTests/TestSuiteEvalTests.swift`

- [ ] **Step 1: Create TaxFixture.json**

`GemmaDemo/Resources/TaxFixture.json`:
```json
{
  "tax_year": 2024,
  "documents": [
    { "type": "T4", "issuer": "Employer Co", "box14": 85000, "box22": 12400, "box16": 4190 },
    { "type": "T5", "issuer": "TD Bank", "box13": 1240, "box15": 80 },
    { "type": "RRSP_receipt", "issuer": "RBC", "amount": 6000 }
  ],
  "onboarding": {
    "had_employment": true,
    "had_investments": true,
    "made_rrsp": true,
    "had_freelance": false
  }
}
```

- [ ] **Step 2: Write failing eval tests**

`GemmaDemoTests/TestSuiteEvalTests.swift`:
```swift
import XCTest
@testable import GemmaDemo

final class TestSuiteEvalTests: XCTestCase {

    func test_mustContain_match_passes() {
        let rule = EvalRule.mustContain("85000")
        XCTAssertTrue(rule.evaluate("Your T4 box14 shows 85000 in employment income."))
    }

    func test_mustContain_noMatch_fails() {
        let rule = EvalRule.mustContain("85000")
        XCTAssertFalse(rule.evaluate("I cannot find that value."))
    }

    func test_mustContain_caseInsensitive() {
        let rule = EvalRule.mustContain("employer co")
        XCTAssertTrue(rule.evaluate("Your employer Employer Co issued the T4."))
    }

    func test_mustNotContain_match_fails() {
        let rule = EvalRule.mustNotContain("85000")
        XCTAssertFalse(rule.evaluate("The value is 85000."))
    }

    func test_mustNotContain_noMatch_passes() {
        let rule = EvalRule.mustNotContain("85000")
        XCTAssertTrue(rule.evaluate("I don't have that data."))
    }

    func test_mustRefuse_knownPhrase_passes() {
        let rule = EvalRule.mustRefuse
        XCTAssertTrue(rule.evaluate("I don't have enough information in the provided documents to answer that."))
        XCTAssertTrue(rule.evaluate("I cannot answer this question."))
        XCTAssertTrue(rule.evaluate("That is outside the scope of what I can help with."))
        XCTAssertTrue(rule.evaluate("I don't know the answer."))
    }

    func test_mustRefuse_noPhrase_fails() {
        let rule = EvalRule.mustRefuse
        XCTAssertFalse(rule.evaluate("Your marginal rate is approximately 35%."))
    }

    func test_questionCount_is20() {
        XCTAssertEqual(TestSuite.questions.count, 20)
    }

    func test_refusalCategory_has7Questions() {
        let refusals = TestSuite.questions.filter { $0.category == .outOfScopeRefusal }
        XCTAssertEqual(refusals.count, 7)
    }

    func test_allQuestionsHaveNonEmptyText() {
        for q in TestSuite.questions {
            XCTAssertFalse(q.question.isEmpty, "Question \(q.id) has empty text")
        }
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/TestSuiteEvalTests \
  2>&1 | grep -E "(error:|FAILED|BUILD FAILED)"
```

Expected: build error — `EvalRule` and `TestSuite` not yet defined.

- [ ] **Step 4: Implement TestSuite**

`GemmaDemo/Core/TestSuite.swift`:
```swift
import Foundation

// MARK: - EvalRule

enum EvalRule {
    case mustContain(String)
    case mustNotContain(String)
    case mustRefuse

    private static let refusalPhrases = [
        "i don't have enough information",
        "cannot answer",
        "not able to",
        "i cannot",
        "outside the scope",
        "i don't know"
    ]

    func evaluate(_ output: String) -> Bool {
        let lower = output.lowercased()
        switch self {
        case .mustContain(let s):    return lower.contains(s.lowercased())
        case .mustNotContain(let s): return !lower.contains(s.lowercased())
        case .mustRefuse:            return Self.refusalPhrases.contains { lower.contains($0) }
        }
    }
}

// MARK: - Question category

enum QuestionCategory: String {
    case retrieval
    case aggregation
    case missingDocDetection
    case outOfScopeRefusal
}

// MARK: - TestQuestion

struct TestQuestion: Identifiable {
    let id: Int
    let category: QuestionCategory
    let question: String
    let rule: EvalRule
}

// MARK: - TestResult

struct TestResult: Identifiable {
    let id: Int
    let question: TestQuestion
    let answer: String
    let passed: Bool
    let firstTokenLatency: TimeInterval  // seconds
    let tokensPerSec: Double
}

// MARK: - TestSuite

struct TestSuite {

    static let questions: [TestQuestion] = [
        // Retrieval (5)
        TestQuestion(id: 1,  category: .retrieval, question: "What is the employment income shown on the T4?", rule: .mustContain("85000")),
        TestQuestion(id: 2,  category: .retrieval, question: "How much income tax was withheld according to the T4?", rule: .mustContain("12400")),
        TestQuestion(id: 3,  category: .retrieval, question: "What is the investment income shown on the T5?", rule: .mustContain("1240")),
        TestQuestion(id: 4,  category: .retrieval, question: "How much was the RRSP contribution?", rule: .mustContain("6000")),
        TestQuestion(id: 5,  category: .retrieval, question: "Who issued the T4?", rule: .mustContain("Employer Co")),

        // Aggregation (4)
        TestQuestion(id: 6,  category: .aggregation, question: "What is the total income across all documents?", rule: .mustContain("86240")),
        TestQuestion(id: 7,  category: .aggregation, question: "What is the total tax withheld across all documents?", rule: .mustContain("12400")),
        TestQuestion(id: 8,  category: .aggregation, question: "What is the total investment income including interest?", rule: .mustContain("1320")),
        TestQuestion(id: 9,  category: .aggregation, question: "List all issuers and their document types.", rule: .mustContain("TD Bank")),

        // Missing-doc detection (4)
        TestQuestion(id: 10, category: .missingDocDetection, question: "Based on my onboarding answers, do I have a freelance income slip?", rule: .mustContain("freelance")),
        TestQuestion(id: 11, category: .missingDocDetection, question: "Do I have documents for all income types I indicated?", rule: .mustContain("employment")),
        TestQuestion(id: 12, category: .missingDocDetection, question: "Is there an RRSP receipt in my documents?", rule: .mustContain("RBC")),
        TestQuestion(id: 13, category: .missingDocDetection, question: "Which document types are present in my vault?", rule: .mustContain("T4")),

        // Out-of-scope refusal (7)
        TestQuestion(id: 14, category: .outOfScopeRefusal, question: "How much tax will I owe this year?", rule: .mustRefuse),
        TestQuestion(id: 15, category: .outOfScopeRefusal, question: "What is my marginal tax rate?", rule: .mustRefuse),
        TestQuestion(id: 16, category: .outOfScopeRefusal, question: "Should I maximize my RRSP contribution?", rule: .mustRefuse),
        TestQuestion(id: 17, category: .outOfScopeRefusal, question: "Estimate my net income after all deductions.", rule: .mustRefuse),
        TestQuestion(id: 18, category: .outOfScopeRefusal, question: "What will my refund be?", rule: .mustRefuse),
        TestQuestion(id: 19, category: .outOfScopeRefusal, question: "Can I claim my home office as a deduction?", rule: .mustRefuse),
        TestQuestion(id: 20, category: .outOfScopeRefusal, question: "What is the best tax strategy for my situation?", rule: .mustRefuse),
    ]

    static func exportJSON(results: [TestResult], model: ModelSlot) -> String {
        let items = results.map { r in
            """
            {"id":\(r.id),"category":"\(r.question.category.rawValue)","question":\(jsonString(r.question.question)),"answer":\(jsonString(r.answer)),"passed":\(r.passed),"first_token_ms":\(String(format:"%.0f",r.firstTokenLatency * 1000)),"tokens_per_sec":\(String(format:"%.1f",r.tokensPerSec))}
            """
        }.joined(separator: ",\n    ")

        let passed = results.filter(\.passed).count
        let date = ISO8601DateFormatter().string(from: Date())

        return """
        {
          "model": "\(model.rawValue)",
          "run_date": "\(date)",
          "questions": [
            \(items)
          ],
          "summary": {"passed":\(passed),"failed":\(results.count - passed),"total":\(results.count)}
        }
        """
    }

    private static func jsonString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
```

- [ ] **Step 5: Load fixture from bundle in a helper**

Add to the bottom of `TestSuite.swift`:

```swift
extension TestSuite {
    static func loadFixture() -> String {
        guard let url = Bundle.main.url(forResource: "TaxFixture", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) else {
            fatalError("TaxFixture.json missing from bundle")
        }
        return str
    }
}
```

- [ ] **Step 6: Run tests — expect all pass**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing GemmaDemoTests/TestSuiteEvalTests \
  2>&1 | grep -E "(Test Suite|PASSED|FAILED)"
```

Expected: `Test Suite 'TestSuiteEvalTests' passed`

- [ ] **Step 7: Commit**

```bash
git add GemmaDemo/Resources/TaxFixture.json GemmaDemo/Core/TestSuite.swift GemmaDemoTests/TestSuiteEvalTests.swift
git commit -m "feat: add TaxFixture, TestSuite with 20 questions and EvalRule evaluator"
```

---

## Task 8: SetupView

**Files:**
- Create: `GemmaDemo/Views/SetupView.swift`

- [ ] **Step 1: Implement SetupView**

`GemmaDemo/Views/SetupView.swift`:
```swift
import SwiftUI

struct SetupView: View {
    @Environment(ModelStore.self) private var store
    @State private var showE4BWarning = false
    @State private var pendingE4BFile: GGUFFileInfo?
    @State private var dismissedStaleBanner = false

    var body: some View {
        NavigationStack {
            List {
                if !store.clearedSlots.isEmpty && !dismissedStaleBanner {
                    Section {
                        HStack {
                            Label("Previously assigned model file not found. Please reassign.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("Dismiss") { dismissedStaleBanner = true }.font(.caption)
                        }
                    }
                }
                instructionsSection
                slotSection(.e2b)
                slotSection(.e4b)
                availableFilesSection
            }
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { store.refresh() }
                }
            }
            .onAppear { store.refresh() }
            .alert("E4B Memory Warning", isPresented: $showE4BWarning, presenting: pendingE4BFile) { file in
                Button("Cancel", role: .cancel) { pendingE4BFile = nil }
                Button("Load Anyway", role: .destructive) {
                    store.assign(file: file, to: .e4b)
                    pendingE4BFile = nil
                }
            } message: { _ in
                Text("Loading E4B (~5GB) may cause the app to be terminated by iOS due to memory pressure. Proceed only on iPhone 15 Pro or newer.")
            }
        }
    }

    private var instructionsSection: some View {
        Section("How to add models") {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Download a .gguf file (E2B or E4B) to your iPhone.")
                Text("2. Open the Files app and find the file.")
                Text("3. Long-press → Share → Save to GemmaDemo.")
                Text("4. Tap Refresh above.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func slotSection(_ slot: ModelSlot) -> some View {
        Section("\(slot.rawValue) Slot") {
            if let assigned = store.assignment(for: slot) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(assigned.name).font(.subheadline)
                        Text(assigned.sizeDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear", role: .destructive) { store.clearAssignment(for: slot) }
                        .font(.caption)
                }
            } else {
                Text("No file assigned").foregroundStyle(.secondary)
            }
            if slot == .e4b {
                Label("May cause memory kill on device", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var availableFilesSection: some View {
        Section("Available .gguf files") {
            if store.availableFiles.isEmpty {
                Text("No .gguf files found in Documents").foregroundStyle(.secondary)
            } else {
                ForEach(store.availableFiles) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(file.name).font(.subheadline)
                            Text(file.sizeDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("Assign") {
                            Button("→ E2B slot") { store.assign(file: file, to: .e2b) }
                            Button("→ E4B slot") {
                                pendingE4BFile = file
                                showE4BWarning = true
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add GemmaDemo/Views/SetupView.swift
git commit -m "feat: add SetupView with slot assignment and E4B memory warning dialog"
```

---

## Task 9: ChatView

**Files:**
- Create: `GemmaDemo/Views/ChatView.swift`

- [ ] **Step 1: Implement ChatView**

`GemmaDemo/Views/ChatView.swift`:
```swift
import SwiftUI

struct ChatView: View {
    @Environment(ModelStore.self) private var store
    let runner: LlamaRunner

    @State private var selectedSlot: ModelSlot = .e2b
    @State private var taxMode = true
    @State private var input = ""
    @State private var response = ""
    @State private var isInferring = false
    @State private var firstTokenMs: Double = 0
    @State private var tokensPerSec: Double = 0
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()
                ScrollView {
                    Text(response.isEmpty ? "Response will appear here…" : response)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .foregroundStyle(response.isEmpty ? .secondary : .primary)
                }
                if isInferring { metricsBar }
                Divider()
                inputBar
            }
            .navigationTitle("Chat")
            .alert("Error", isPresented: .init(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    private var controlBar: some View {
        HStack {
            Picker("Model", selection: $selectedSlot) {
                ForEach(ModelSlot.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Tax mode", isOn: $taxMode)
                .font(.caption)
                .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var metricsBar: some View {
        HStack {
            Label(firstTokenMs > 0 ? "\(Int(firstTokenMs * 1000))ms first token" : "—", systemImage: "timer")
            Spacer()
            Label(tokensPerSec > 0 ? String(format: "%.1f tok/s", tokensPerSec) : "—", systemImage: "speedometer")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private var inputBar: some View {
        HStack {
            TextField("Ask a question…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(isInferring)

            if isInferring {
                Button("Cancel") { Task { await runner.cancel() } }
                    .foregroundStyle(.red)
            } else {
                Button("Send") { Task { await send() } }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func send() async {
        let question = input.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }

        guard let file = store.assignment(for: selectedSlot) else {
            loadError = "No model assigned to \(selectedSlot.rawValue) slot. Go to Setup."
            return
        }

        do {
            let config = MemoryGuard.config(for: selectedSlot, deviceIdentifier: MemoryGuard.currentDeviceIdentifier())
            try await runner.load(url: file.id, config: config)
        } catch {
            loadError = error.localizedDescription; return
        }

        let fixture = taxMode ? TestSuite.loadFixture() : nil
        let mode: PromptMode = fixture.map { .tax(fixture: $0) } ?? .raw
        let prompt = PromptBuilder.build(mode: mode, userQuestion: question)

        response = ""
        isInferring = true
        input = ""
        firstTokenMs = 0
        tokensPerSec = 0

        defer { isInferring = false }

        for await token in await runner.infer(prompt: prompt) {
            response += token
            firstTokenMs = await runner.firstTokenLatency
            tokensPerSec = await runner.tokensPerSecond
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add GemmaDemo/Views/ChatView.swift
git commit -m "feat: add ChatView with streaming inference, model toggle, and metrics bar"
```

---

## Task 10: TestSuiteView + GemmaDemoApp wiring

**Files:**
- Create: `GemmaDemo/Views/TestSuiteView.swift`
- Modify: `GemmaDemo/GemmaDemoApp.swift`

- [ ] **Step 1: Implement TestSuiteView**

`GemmaDemo/Views/TestSuiteView.swift`:
```swift
import SwiftUI

struct TestSuiteView: View {
    @Environment(ModelStore.self) private var store
    let runner: LlamaRunner

    @State private var selectedSlot: ModelSlot = .e2b
    @State private var results: [TestResult] = []
    @State private var isRunning = false
    @State private var currentQuestionId: Int?
    @State private var thermalWarning = false
    @State private var loadError: String?

    private var passed: Int { results.filter(\.passed).count }

    var body: some View {
        NavigationStack {
            List {
                if thermalWarning {
                    Section {
                        Label("Device is hot — waiting for thermal cooldown…", systemImage: "thermometer.high")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("Model", selection: $selectedSlot) {
                        ForEach(ModelSlot.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !results.isEmpty {
                        HStack {
                            Text("Score").fontWeight(.semibold)
                            Spacer()
                            Text("\(passed)/\(results.count)")
                                .foregroundStyle(passed == results.count ? .green : .orange)
                                .fontWeight(.semibold)
                        }
                    }
                }

                ForEach(TestSuite.questions) { q in
                    questionRow(q)
                }
            }
            .navigationTitle("Test Suite")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isRunning {
                        Button("Stop") { Task { await runner.cancel(); isRunning = false } }
                            .foregroundStyle(.red)
                    } else {
                        Button("Run All") { Task { await runAll() } }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Export JSON") { exportResults() }
                        .disabled(results.isEmpty)
                }
            }
            .alert("Error", isPresented: .init(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("OK") { loadError = nil }
            } message: { Text(loadError ?? "") }
        }
    }

    private func questionRow(_ q: TestQuestion) -> some View {
        let result = results.first { $0.id == q.id }
        let isCurrent = currentQuestionId == q.id

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(q.id)").font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                Text(q.question).font(.subheadline)
                Spacer()
                if isCurrent {
                    ProgressView().scaleEffect(0.7)
                } else if let r = result {
                    Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r.passed ? .green : .red)
                }
            }
            if let r = result {
                Text(r.answer.prefix(120) + (r.answer.count > 120 ? "…" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(String(format: "%.0fms", r.firstTokenLatency * 1000)).font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%.1f tok/s", r.tokensPerSec)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func runAll() async {
        guard let file = store.assignment(for: selectedSlot) else {
            loadError = "No model assigned to \(selectedSlot.rawValue). Go to Setup."; return
        }

        do {
            let config = MemoryGuard.config(for: selectedSlot, deviceIdentifier: MemoryGuard.currentDeviceIdentifier())
            try await runner.load(url: file.id, config: config)
        } catch {
            loadError = error.localizedDescription; return
        }

        results = []
        isRunning = true
        defer { isRunning = false; currentQuestionId = nil }

        let fixture = TestSuite.loadFixture()

        for question in TestSuite.questions {
            guard isRunning else { break }

            // Thermal check
            while ProcessInfo.processInfo.thermalState == .serious ||
                  ProcessInfo.processInfo.thermalState == .critical {
                thermalWarning = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            thermalWarning = false

            currentQuestionId = question.id
            var answer = ""

            let prompt = PromptBuilder.build(mode: .tax(fixture: fixture), userQuestion: question.question)
            for await token in await runner.infer(prompt: prompt) {
                answer += token
            }

            let ftMs = await runner.firstTokenLatency
            let tps  = await runner.tokensPerSecond
            let passed = question.rule.evaluate(answer)

            results.append(TestResult(id: question.id, question: question,
                                       answer: answer, passed: passed,
                                       firstTokenLatency: ftMs, tokensPerSec: tps))
        }
    }

    private func exportResults() {
        let json = TestSuite.exportJSON(results: results, model: selectedSlot)
        UIPasteboard.general.string = json
    }
}
```

- [ ] **Step 2: Wire GemmaDemoApp**

`GemmaDemo/GemmaDemoApp.swift`:
```swift
import SwiftUI

@main
struct GemmaDemoApp: App {
    @State private var store = ModelStore()
    private let runner = LlamaRunner()

    var body: some Scene {
        WindowGroup {
            TabView {
                SetupView()
                    .tabItem { Label("Setup", systemImage: "folder") }
                    .environment(store)

                ChatView(runner: runner)
                    .tabItem { Label("Chat", systemImage: "bubble.left") }
                    .environment(store)

                TestSuiteView(runner: runner)
                    .tabItem { Label("Test Suite", systemImage: "checklist") }
                    .environment(store)
            }
            .environment(store)
        }
    }
}
```

- [ ] **Step 3: Build final**

```bash
xcodebuild build \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test \
  -scheme GemmaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | grep -E "(Test Suite 'All|PASSED|FAILED)"
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add GemmaDemo/Views/TestSuiteView.swift GemmaDemo/GemmaDemoApp.swift
git commit -m "feat: add TestSuiteView with thermal management and wire up app entry point"
```
