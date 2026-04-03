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
