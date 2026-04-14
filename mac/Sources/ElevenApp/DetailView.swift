import SwiftUI
import ElevenCore
import Foundation

struct DetailView: View {
    let example: Example
    @State private var session: RunSession?
    @State private var renderingPNG = false
    @State private var screenImage: NSImage?
    @State private var showConsole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(example.displayName)
                        .font(.title2.bold().monospaced())
                    Spacer()
                    StatusPill(state: session?.state ?? .idle)
                }
                if !example.summary.isEmpty {
                    Text(example.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(example.appPath.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .truncationMode(.head)
            }
            .padding()

            // Toolbar
            HStack(spacing: 12) {
                Button {
                    if isRunning { stop() } else { run() }
                } label: {
                    Label(isRunning ? "Stop" : "Run",
                          systemImage: isRunning ? "stop.fill" : "play.fill")
                }
                .keyboardShortcut(isRunning ? "." : "r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .accentColor)

                Button {
                    render()
                } label: {
                    Label(renderingPNG ? "Rendering…" : "Render PNG",
                          systemImage: "camera.fill")
                }
                .disabled(renderingPNG)

                Button {
                    NSWorkspace.shared.open(example.appPath)
                } label: {
                    Label("Open app.py", systemImage: "pencil.circle")
                }
                Spacer()
            }
            .padding(.horizontal)

            Divider().padding(.vertical, 8)

            // Main content: device photo (default) or console
            if showConsole {
                ConsolePane(lines: session?.lines ?? [])
                    .padding(.horizontal)
                    .padding(.bottom)
            } else {
                DeviceView(device: .knob1, screenContent: screenImage)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $showConsole) {
                    Image(systemName: "rectangle.on.rectangle").tag(false)
                    Image(systemName: "terminal").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Toggle device preview / console")
            }
        }
        .onChange(of: example.id) {
            session?.stop()
            session = nil
            screenImage = nil
            // Auto-render so the device photo isn't empty when you select
            renderForPreview()
        }
        .onAppear {
            renderForPreview()
        }
    }

    private var isRunning: Bool {
        session?.state == .running
    }

    private func run() {
        let s = RunSession(example)
        session = s
        s.start()
    }

    private func stop() {
        session?.stop()
    }

    private func render() {
        renderingPNG = true
        Task.detached(priority: .userInitiated) {
            let result = await renderImpl()
            await MainActor.run {
                renderingPNG = false
                if let url = result {
                    NSWorkspace.shared.open(url)
                    // Also pick up the freshly-rendered PNG for the device view
                    screenImage = NSImage(contentsOf: url)
                }
            }
        }
    }

    /// Same as render() but doesn't open Preview — just updates the
    /// device-view's screen content. Called on selection change so the
    /// device photo isn't blank when you pick an example.
    private func renderForPreview() {
        Task.detached(priority: .background) {
            let result = await renderImpl()
            await MainActor.run {
                if let url = result {
                    screenImage = NSImage(contentsOf: url)
                }
            }
        }
    }

    private func renderImpl() async -> URL? {
        do {
            let micropython = try Runtime.micropythonBinary()
            let outURL = URL(fileURLWithPath: "/tmp/eleven-app-render-\(example.id.replacingOccurrences(of: "/", with: "_")).png")
            var env = ProcessInfo.processInfo.environment
            env["ELEVEN_APP_PATH"] = example.appPath.path
            env["ELEVEN_GEOMETRY"] = "170x320"
            env["ELEVEN_OUT"] = outURL.path
            env["ELEVEN_FRAMES"] = "1"
            env["ELEVEN_PRE_EVENTS"] = ""
            env["ELEVEN_CORE_DIR"] = Runtime.coreDir().path
            env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
            env["ELEVEN_PLATFORM"] = "nomad-v1"

            // For RPC examples, inject a sample value so the render isn't blank
            if example.workerPath != nil {
                env["ELEVEN_PRE_EVENTS"] = "rpc:cpu.update:42"
            }

            let renderHost = Runtime.coreDir().appendingPathComponent("render_host.py")
            let status = try runForeground(
                micropython, arguments: [renderHost.path], environment: env
            )
            guard status == 0 else { return nil }

            // Convert PPM to PNG
            let sips = URL(fileURLWithPath: "/usr/bin/sips")
            _ = try runForeground(
                sips,
                arguments: ["-s", "format", "png", outURL.path + ".ppm", "--out", outURL.path]
            )
            try? FileManager.default.removeItem(atPath: outURL.path + ".ppm")
            return outURL
        } catch {
            return nil
        }
    }
}

struct StatusPill: View {
    let state: RunSession.State

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .idle:       return .secondary
        case .running:    return .green
        case .exited(let s): return s == 0 ? .blue : .orange
        case .failed:     return .red
        }
    }

    private var label: String {
        switch state {
        case .idle: return "idle"
        case .running: return "running"
        case .exited(let s): return s == 0 ? "exited cleanly" : "exited (\(s))"
        case .failed(let msg): return "failed — \(msg.prefix(40))"
        }
    }
}

struct ConsolePane: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                    Color.clear.frame(height: 1).id("__bottom")
                }
                .padding(8)
            }
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: lines.count) {
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("__bottom", anchor: .bottom)
                }
            }
        }
        .foregroundStyle(.white)
    }
}
