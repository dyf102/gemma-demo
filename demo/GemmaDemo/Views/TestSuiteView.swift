import SwiftUI
import UIKit

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
                        Label("Device is hot - waiting for thermal cooldown...", systemImage: "thermometer.high")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Model", selection: $selectedSlot) {
                        ForEach(ModelSlot.allCases, id: \.self) { slot in
                            Text(slot.rawValue).tag(slot)
                        }
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
                        Button("Stop") {
                            Task {
                                await runner.cancel()
                                isRunning = false
                            }
                        }
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
            .alert("Error", isPresented: .init(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK") { loadError = nil }
            } message: { Text(loadError ?? "") }
        }
    }

    @ViewBuilder
    private func questionRow(_ q: TestQuestion) -> some View {
        let result = results.first { $0.id == q.id }
        let isCurrent = currentQuestionId == q.id
        VStack(alignment: .leading, spacing: 4) {
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
                Text(String(r.answer.prefix(120)) + (r.answer.count > 120 ? "..." : ""))
                    .font(.caption).foregroundStyle(.secondary)
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
            loadError = "No model assigned to \(selectedSlot.rawValue). Go to Setup."
            return
        }
        do {
            let config = MemoryGuard.config(for: selectedSlot, deviceIdentifier: MemoryGuard.currentDeviceIdentifier())
            try await runner.load(url: file.id, config: config)
        } catch {
            loadError = error.localizedDescription
            return
        }
        results = []
        isRunning = true
        defer {
            isRunning = false
            currentQuestionId = nil
        }
        let fixture = TestSuite.loadFixture()
        for question in TestSuite.questions {
            guard isRunning else { break }
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
            let ftLatency = await runner.firstTokenLatency
            let tps = await runner.tokensPerSecond
            results.append(TestResult(
                id: question.id,
                question: question,
                answer: answer,
                passed: question.rule.evaluate(answer),
                firstTokenLatency: ftLatency,
                tokensPerSec: tps
            ))
        }
    }

    private func exportResults() {
        UIPasteboard.general.string = TestSuite.exportJSON(results: results, model: selectedSlot)
    }
}
