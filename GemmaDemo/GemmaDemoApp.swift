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

                ChatView(runner: runner)
                    .tabItem { Label("Chat", systemImage: "bubble.left") }

                TestSuiteView(runner: runner)
                    .tabItem { Label("Test Suite", systemImage: "checklist") }
            }
            .environment(store)
        }
    }
}
