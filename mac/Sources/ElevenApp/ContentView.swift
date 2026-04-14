import SwiftUI
import ElevenCore

struct ContentView: View {
    @Binding var examples: [Example]
    @Binding var selection: Example.ID?

    var body: some View {
        NavigationSplitView {
            List(examples, selection: $selection) { example in
                NavigationLink(value: example.id) {
                    ExampleRow(example: example)
                }
            }
            .navigationTitle("Examples")
            .listStyle(.sidebar)
        } detail: {
            if let id = selection, let example = examples.first(where: { $0.id == id }) {
                DetailView(example: example)
            } else {
                ContentUnavailableView(
                    "Pick an example",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("Choose one from the sidebar to run, render, or inspect.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }
}

struct ExampleRow: View {
    let example: Example

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: example.kind == .projectDir ? "folder.fill" : "doc.text.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text(example.displayName)
                    .font(.body.monospaced())
                if example.workerPath != nil {
                    Text("RPC")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            if !example.summary.isEmpty {
                Text(example.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
