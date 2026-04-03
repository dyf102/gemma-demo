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
            .alert("Error", isPresented: .init(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
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
            Label(firstTokenMs > 0 ? "\(Int(firstTokenMs))ms first token" : "—", systemImage: "timer")
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
            firstTokenMs = await runner.firstTokenLatency * 1000
            tokensPerSec = await runner.tokensPerSecond
        }
    }
}
