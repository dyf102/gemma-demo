# GemmaDemo — Design Spec
**Date:** 2026-04-02  
**Status:** Approved (v2 — post Codex review)  
**Purpose:** Native iOS demo app to benchmark Gemma 4 E2B vs E4B on-device reasoning for SlipCheck POC validation.

---

## Goal

Test whether Gemma 4 E2B and E4B GGUF models can reliably answer structured tax Q&A questions on iPhone 15 Pro without hallucinating numeric values or inventing out-of-scope answers. Results inform SlipCheck's Tier 1 vs Tier 2 architecture decision.

---

## Target device

iPhone 15 Pro, A17 Pro, 8GB RAM, iOS 17+.

---

## Models

| Slot | Model | GGUF source | Q4_K_M size | Status |
|---|---|---|---|---|
| E2B | gemma-4-E2B-it | ggml-org/gemma-4-E2B-it-GGUF | ~3GB | Primary |
| E4B | gemma-4-E4B-it | ggml-org/gemma-4-E4B-it-GGUF | ~5GB | Experimental — E4B jetsam kills are likely, not just possible. iOS reserves ~1.5GB for OS/kernel leaving ~6.5GB addressable. 5GB weights + Metal heap + app overhead pushes the limit. E4B load requires explicit user confirmation dialog before proceeding. |

User copies `.gguf` files into the app's Documents directory via the iOS Files app.

---

## Project structure

```
GemmaDemo/
├── Core/
│   ├── LlamaRunner.swift        # llama.cpp actor wrapper, Metal, streaming
│   ├── MemoryGuard.swift        # preflight memory admission check
│   ├── ModelStore.swift         # Documents dir scan, slot assignment
│   ├── PromptBuilder.swift      # Gemma 4 chat template + system prompts
│   └── TestSuite.swift          # 20 tax Q&A questions + evaluator
├── Views/
│   ├── SetupView.swift          # .gguf file picker, E2B/E4B slot assignment
│   ├── ChatView.swift           # freeform chat + metrics bar
│   └── TestSuiteView.swift      # batch run + pass/fail report
├── Resources/
│   └── TaxFixture.json          # fake Canadian tax vault (T4, T5, RRSP)
└── GemmaDemoApp.swift
```

---

## Components

### LlamaRunner (Swift actor)

Wraps llama.cpp C API. All `llama_*` calls are actor-isolated to serialize access.

```swift
actor LlamaRunner {
    func load(url: URL) async throws
    func infer(prompt: String) -> AsyncStream<String>
    func cancel()
    var firstTokenLatency: TimeInterval { get }
    var tokensPerSecond: Double { get }
}
```

- `n_gpu_layers = 99` (full Metal offload on A17 Pro)
- `n_ctx = 4096` (default); falls back to `2048` if `MemoryGuard` signals reduced headroom
- `n_threads = 6` — applies to CPU prompt evaluation only; generation is GPU-bound on Metal. 6 matches A17 Pro performance core count.
- C callbacks use a nonisolated trampoline; never call actor-isolated methods synchronously from C. Trampoline posts to the actor via `Task { await runner.handleToken(...) }`.
- **Cancellation contract:** calling `cancel()` sets a flag checked in the token loop. `infer` stream ends normally (no throw). Teardown of model/context/backend happens in `cancel()` and `deinit`. After `cancel()` returns, the actor accepts a new `load` call.
- **Backpressure:** `AsyncStream` uses a continuation with a bounded buffer of 64 tokens. If the consumer lags and the buffer fills, the token loop yields (`await Task.yield()`) until space is available. This prevents unbounded memory growth under a slow UI consumer.
- **GGUF load safety:** `llama_model_load` errors must be caught at the call boundary and thrown as a Swift error — never allowed to crash. A malformed GGUF that passes magic byte validation can still fail here.
- Single-run exclusivity: `infer` throws `LlamaError.busy` if inference is already in progress.

### MemoryGuard

Preflight check called before model load. Uses device model heuristic rather than `os_proc_available_memory()` — that API is Darwin-private and not safe for App Store submission.

**Strategy:** read device model identifier via `sysctlbyname("hw.machine")`. Map known models to safe load thresholds:

| Device | E2B | E4B |
|---|---|---|
| iPhone 15 Pro / 15 Pro Max | Proceed default | Proceed with reduced params: `n_gpu_layers=50`, `n_ctx=2048` |
| Unknown / older | Proceed default | Block with error |

This is conservative by design — a POC on a known device. Not a general-purpose memory manager.

### ModelStore (@Observable)

Scans `Documents/*.gguf` on launch and on manual refresh. For each file:
1. Validates GGUF magic bytes (`0x47475546`)
2. Reads model metadata: architecture, declared context length, tokenizer template key presence
3. Exposes `GGUFFileInfo` (name, size, architecture, contextLength, hasTemplate)

User assigns validated files to `e2b` or `e4b` slot via SetupView. Slot assignments persisted as **bookmark data** (not raw URLs) in `UserDefaults` using `URL.bookmarkData(options:)` — this survives app reinstalls and OS upgrades. On next launch, stale/unresolvable bookmarks silently clear the slot and SetupView shows an unassigned state with a banner: "Previously assigned model file not found. Please reassign."

### PromptBuilder

Centralises all prompt construction. Gemma 4 uses the following chat template (must match GGUF metadata template exactly):

```
<start_of_turn>user
{user_message}<end_of_turn>
<start_of_turn>model
```

**Tax mode system prompt** (injected as first user turn before the actual question):

```
You are a tax document review assistant.
Answer only based on the structured document data below.
Never invent, estimate, or approximate numeric values not present in the data.
If you cannot answer from the data, say: "I don't have enough information in the provided documents to answer that."

Documents:
{TaxFixture.json contents}
```

**Raw mode:** no system prompt, no fixture injection. Used in ChatView for freeform testing.

`PromptBuilder` is a pure struct with no state — takes mode + user question, returns a formatted string.

### TestSuite

20 hardcoded questions in 4 categories. Each question uses tax mode prompt (fixture always injected).

**Categories:**
1. Retrieval (5 questions) — exact field lookup, `EvalRule.mustContain`
2. Aggregation (4 questions) — cross-document sums, `EvalRule.mustContain` with numeric match
3. Missing-doc detection (4 questions) — based on onboarding flags, `EvalRule.mustContain`
4. Out-of-scope refusal (7 questions) — tax advice, estimates, invented values, `EvalRule.mustRefuse`

**EvalRule:**
```swift
enum EvalRule {
    case mustContain(String)           // case-insensitive substring match
    case mustNotContain(String)        // case-insensitive
    case mustRefuse                    // output contains any refusal signal phrase
}
```

**Refusal signal phrases** (any match = pass for `mustRefuse`):
- `"i don't have enough information"`
- `"cannot answer"`
- `"not able to"`
- `"i cannot"`
- `"outside the scope"`
- `"i don't know"`

**Thermal management:** before each question, check `ProcessInfo.processInfo.thermalState`. If `.serious` or `.critical`, pause and show a banner in TestSuiteView: "Device is hot — waiting for thermal cooldown." Poll every 3s until state drops to `.nominal` or `.fair`, then continue. The fixed 5s delay is removed in favour of this adaptive check.

Results exported as JSON to clipboard. Schema:
```json
{
  "model": "E2B|E4B",
  "run_date": "ISO8601",
  "questions": [
    { "id": 1, "category": "retrieval", "question": "...", "answer": "...", "rule": "mustContain:85000", "passed": true, "first_token_ms": 1200, "tokens_per_sec": 24.3 }
  ],
  "summary": { "passed": 18, "failed": 2, "total": 20 }
}
```

### TaxFixture.json

Fake Canadian tax data, deterministic and reusable:
```json
{
  "tax_year": 2024,
  "documents": [
    { "type": "T4", "issuer": "Employer Co", "box14": 85000, "box22": 12400, "box16": 4190 },
    { "type": "T5", "issuer": "TD Bank", "box13": 1240, "box15": 80 },
    { "type": "RRSP_receipt", "issuer": "RBC", "amount": 6000 }
  ],
  "onboarding": {
    "had_employment": true, "had_investments": true,
    "made_rrsp": true, "had_freelance": false
  }
}
```

---

## llama.cpp integration

**Not** raw SPM from source repo. Use a prebuilt XCFramework binary target built with `GGML_METAL=ON`.

```swift
// Package.swift binary target
.binaryTarget(
    name: "llama",
    url: "<pinned-release-xcframework-url>",
    checksum: "<sha256>"
)
// First implementation task: find latest stable XCFramework release at
// https://github.com/ggml-org/llama.cpp/releases — filter for assets named
// *ios*.xcframework.zip or *xcframework* with Metal support confirmed.
// Pin to a specific tag. Do NOT use master.
```

Verify Metal init succeeds on A17 Pro before merging any llama.cpp version bump.

---

## Info.plist requirements

```xml
<key>UIFileSharingEnabled</key><true/>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

Required for user to copy `.gguf` files into app Documents via iOS Files app.

---

## Views

**SetupView:** Lists detected `.gguf` files with metadata (size, architecture, context length, template present/missing). Two slot pickers (E2B, E4B). Step-by-step copy instructions. Refresh button. E4B slot shows a persistent warning: "Loading E4B may cause the app to be terminated by iOS due to memory pressure. Proceed anyway?" — user must confirm before E4B is loaded.

**ChatView:** Model selector toggle (E2B / E4B). System prompt mode toggle (tax mode / raw). Text input, streaming response with token-by-token display. Metrics bar: first token latency (ms) and tokens/sec. Cancel button during inference.

**TestSuiteView:** Model selector. Run All button. Per-question progress with streaming output preview. Pass/fail badge + latency per question. Thermal warning banner (shown when device is hot). Summary row (X/20 passed). Export JSON to clipboard button.

---

## Success criteria for POC

| Metric | E2B target | E4B target |
|---|---|---|
| Numeric grounding (retrieval + aggregation) | 100% | 100% |
| Out-of-scope refusal | 100% | 100% |
| First token latency | < 4s | < 6s |
| Tokens/sec | > 20 | > 12 |
| Memory stability (no jetsam kill) | Required | Best-effort — expect possible kills |
