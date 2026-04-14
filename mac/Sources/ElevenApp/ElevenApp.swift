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
                // Allow content to extend under the traffic-light area so
                // the device preview uses the full window height.
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh examples") {
                    examples = ExampleScanner.scan()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("showClockTuning") private var showClockTuning: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Show clock tuning controls", isOn: $showClockTuning)
                Text("Exposes card size, position, radius, and reference-overlay controls in the right panel when the Clock example is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Developer")
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
