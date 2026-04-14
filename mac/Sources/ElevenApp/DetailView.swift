import SwiftUI
import ElevenCore
import Foundation

struct DetailView: View {
    let example: Example
    var calibrationBinding: Binding<CGRect>? = nil
    var cornerRadius: CGFloat = 0
    var backingBinding: Binding<CGRect>? = nil
    @State private var session: RunSession?
    @State private var renderingPNG = false
    @State private var screenImage: NSImage?
    @State private var showConsole = false
    /// Clock-card tuning — live-applied. Clock.py polls
    /// `/tmp/eleven_clock_tuning.json` each frame.
    @State private var clockCardRadius: Double = 20
    @State private var clockCardW: Double = 91
    @State private var clockCardH: Double = 68
    @State private var clockCardX: Double = 0
    @State private var clockCardY: Double = 5
    /// Reference-photo overlay. When `> 0`, DeviceView draws
    /// `references/clock-native.png` on top of the running screen at
    /// this opacity so you can eyeball alignment against the native
    /// widget.
    @State private var referenceOpacity: Double = 0
    /// Hidden by default — toggle via Settings → Developer.
    @AppStorage("showClockTuning") private var showClockTuning: Bool = false

    /// Cached reference image. Bundle.module resource lookups flatten
    /// the folder hierarchy, so the filename alone is enough.
    static let clockReferenceImage: NSImage? = {
        if let url = Bundle.module.url(forResource: "clock-native",
                                       withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    var body: some View {
        HStack(spacing: 0) {
            // Full-height device preview — no padding, so the photo uses
            // every pixel of available height
            // Live frame from the running session takes precedence over
            // the one-shot rendered PNG. Falls back to the PNG when idle.
            DeviceView(device: .knob1,
                       screenContent: session?.latestFrame ?? screenImage,
                       editableRect: calibrationBinding,
                       cornerRadius: cornerRadius,
                       editableBackingRect: backingBinding,
                       referenceImage: (showClockTuning && referenceOpacity > 0) ? Self.clockReferenceImage : nil,
                       referenceOpacity: referenceOpacity,
                       onEncoder: { delta in
                           session?.injectEncoder(delta)
                       })
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right panel: metadata + actions + (optional) console
            rightPanel
                .frame(width: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(example.displayName)
                        .font(.title3.bold().monospaced())
                    Spacer()
                }
                StatusPill(state: session?.state ?? .idle)
                if !example.summary.isEmpty {
                    Text(example.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(example.appPath.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .truncationMode(.head)
                    .lineLimit(2)
            }
            .padding()

            Divider()

            // Actions — vertical list, full width
            VStack(spacing: 8) {
                Button {
                    if isRunning { stop() } else { run() }
                } label: {
                    Label(isRunning ? "Stop" : "Run",
                          systemImage: isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(isRunning ? "." : "r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .accentColor)
                .controlSize(.large)

                Button {
                    render()
                } label: {
                    Label(renderingPNG ? "Rendering…" : "Render PNG",
                          systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(renderingPNG)
                .controlSize(.large)

                Button {
                    openInZed(example.appPath)
                } label: {
                    Label("Open app.py in Zed", systemImage: "pencil.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding()

            // Per-app live tuning for the clock. Values written as JSON
            // to /tmp/eleven_clock_tuning.json; Python polls each frame.
            // Hidden by default — enable via Settings → Developer.
            if showClockTuning &&
               (example.id.hasSuffix("clock.py") ||
                example.displayName.lowercased().contains("clock")) {
                Divider()
                clockTuningPanel
                    .padding()
            }

            Divider()

            // Console — collapsible at bottom
            DisclosureGroup(isExpanded: $showConsole) {
                ConsolePane(lines: session?.lines ?? [])
                    .frame(minHeight: 180)
                    .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                    Text("Console")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if let count = session?.lines.count, count > 0 {
                        Text("\(count)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Spacer(minLength: 0)
        }
        .background(.background)
    }

    private var isRunning: Bool {
        session?.state == .running
    }

    @ViewBuilder
    private var clockTuningPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clock tuning")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Readout — all current values on one monospaced line so
            // they're always visible.
            Text(String(format: "x=%d  y=%d  w=%d  h=%d  r=%d",
                        Int(clockCardX), Int(clockCardY),
                        Int(clockCardW), Int(clockCardH),
                        Int(clockCardRadius)))
                .font(.caption.monospaced())
                .foregroundStyle(.primary)

            // Position nudges
            HStack(spacing: 6) {
                Text("Position").font(.caption).frame(width: 60, alignment: .leading)
                tuningNudge("arrow.left")  { clockCardX -= 1; commitTuning() }
                tuningNudge("arrow.right") { clockCardX += 1; commitTuning() }
                tuningNudge("arrow.up")    { clockCardY -= 1; commitTuning() }
                tuningNudge("arrow.down")  { clockCardY += 1; commitTuning() }
                Spacer()
            }

            tuningSlider(label: "Radius", value: $clockCardRadius, range: 0...45, suffix: "px")
            tuningSlider(label: "Width",  value: $clockCardW,      range: 20...100, suffix: "px")
            tuningSlider(label: "Height", value: $clockCardH,      range: 20...200, suffix: "px")

            Divider()

            // Reference-photo overlay
            HStack(spacing: 6) {
                Image(systemName: "photo").imageScale(.small)
                Text("Reference overlay")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(referenceOpacity * 100))%")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $referenceOpacity, in: 0...1)
        }
    }

    private func tuningNudge(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func tuningSlider(label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: 1)
                .onChange(of: value.wrappedValue) { _, _ in commitTuning() }
            Text("\(Int(value.wrappedValue)) \(suffix)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func commitTuning() {
        writeTuningFile()
        // If no live session, trigger a fresh preview render so the
        // static PNG reflects the change too.
        if !isRunning {
            renderForPreview()
        }
    }

    private func writeTuningFile() {
        let payload: [String: Int] = [
            "card_radius": Int(clockCardRadius),
            "card_w":      Int(clockCardW),
            "card_h":      Int(clockCardH),
            "card_x":      Int(clockCardX),
            "card_y":      Int(clockCardY),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/eleven_clock_tuning.json"))
    }

    private func run() {
        syncTuningStateForSession()
        let s = RunSession(example)
        session = s
        s.start()
    }

    /// Keep the tuning file in sync with the visible UI before starting
    /// a session. If the tuning panel is hidden, wipe any stale file so
    /// clock.py uses its own in-source defaults. If it's visible, write
    /// the current slider values so they take effect immediately.
    private func syncTuningStateForSession() {
        let url = URL(fileURLWithPath: "/tmp/eleven_clock_tuning.json")
        if showClockTuning {
            writeTuningFile()
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stop() {
        session?.stop()
    }

    private func render() {
        syncTuningStateForSession()
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
        syncTuningStateForSession()
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
            env["ELEVEN_GEOMETRY"] = "100x310"
            env["ELEVEN_OUT"] = outURL.path
            env["ELEVEN_FRAMES"] = "1"
            env["ELEVEN_PRE_EVENTS"] = ""
            env["ELEVEN_CORE_DIR"] = Runtime.coreDir().path
            env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
            env["ELEVEN_PLATFORM"] = "knob-v1"

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

/// Opens `fileURL` in Zed when available; falls back to Launch Services
/// default so users without Zed still get *some* editor instead of an
/// error beep. Zed ships with bundle id `dev.zed.Zed`.
private func openInZed(_ fileURL: URL) {
    let ws = NSWorkspace.shared
    if let zed = ws.urlForApplication(withBundleIdentifier: "dev.zed.Zed") {
        let cfg = NSWorkspace.OpenConfiguration()
        ws.open([fileURL], withApplicationAt: zed, configuration: cfg)
    } else {
        ws.open(fileURL)
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
