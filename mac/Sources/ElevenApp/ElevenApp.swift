import SwiftUI
import ElevenCore

@main
struct ElevenAppMain: App {
    @State private var examples: [Example] = ExampleScanner.scan()
    @State private var selection: Example.ID?

    var body: some Scene {
        WindowGroup("eleven") {
            ContentView(examples: $examples, selection: $selection)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh examples") {
                    examples = ExampleScanner.scan()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
