import SwiftUI
import ElevenCore

struct ContentView: View {
    @Binding var examples: [Example]
    @Binding var selection: Example.ID?
    @State private var editableRect: CGRect = Device.knob1.screenRect
    @State private var editableCornerRadius: CGFloat = Device.knob1.screenCornerRadius
    @State private var isCalibrating = false

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
            ZStack(alignment: .top) {
                if let id = selection, let example = examples.first(where: { $0.id == id }) {
                    DetailView(
                        example: example,
                        calibrationBinding: isCalibrating ? $editableRect : nil,
                        cornerRadius: isCalibrating ? editableCornerRadius : Device.knob1.screenCornerRadius
                    )
                } else {
                    WelcomeView(
                        calibrationBinding: isCalibrating ? $editableRect : nil,
                        cornerRadius: isCalibrating ? editableCornerRadius : Device.knob1.screenCornerRadius
                    )
                }

                if isCalibrating {
                    CalibrationBanner(rect: $editableRect,
                                      cornerRadius: $editableCornerRadius) {
                        isCalibrating = false
                    }
                    .padding(.top, 12)
                }
            }
        }
        .background(
            // Invisible shortcut handler so ⌘E toggles calibration from anywhere
            Button("Calibrate") { isCalibrating.toggle() }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        )
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }
}

struct WelcomeView: View {
    let calibrationBinding: Binding<CGRect>?
    let cornerRadius: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Device photo in its native state — no simulator overlay.
            DeviceView(device: .knob1, screenContent: nil,
                       editableRect: calibrationBinding,
                       cornerRadius: cornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("eleven")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                Text("Build apps that go to eleven.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 8)
                Label("Pick an example from the sidebar to preview.",
                      systemImage: "arrow.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Tip: press ⌘E to calibrate the screen rect.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(24)
            .frame(width: 320, alignment: .topLeading)
        }
    }
}

struct CalibrationBanner: View {
    @Binding var rect: CGRect
    @Binding var cornerRadius: CGFloat
    var onDone: () -> Void
    @State private var step: CGFloat = 2   // photo pixels per click

    /// Physical knob screen h/w — always enforced.
    private let physicalAspect: CGFloat = 310.0 / 100.0

    var body: some View {
        VStack(spacing: 10) {
            // Row 1: all values in one screenshottable line
            HStack(spacing: 16) {
                Image(systemName: "ruler")
                Text(String(format: "x=%.0f  y=%.0f  w=%.0f  h=%.0f  r=%.0f",
                            rect.minX, rect.minY, rect.width, rect.height,
                            cornerRadius))
                    .font(.body.monospaced().bold())
                Text(String(format: "aspect %.2f (locked)", physicalAspect))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 16)

                Button("Copy") {
                    let s = String(
                        format: "screenRect: CGRect(x: %.0f, y: %.0f, width: %.0f, height: %.0f),\nscreenCornerRadius: %.0f,",
                        rect.minX, rect.minY, rect.width, rect.height,
                        cornerRadius
                    )
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(s, forType: .string)
                }
                Button("Done", action: onDone)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
            .onAppear {
                // Snap to the correct aspect the moment calibration opens
                rect.size.height = rect.width * physicalAspect
            }

            // Row 2: position (directional buttons) + size (± buttons)
            HStack(spacing: 12) {
                // Position nudge
                Text("Move").font(.caption.weight(.medium))
                nudgeButton("arrow.left",  dx: -step)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                nudgeButton("arrow.right", dx:  step)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                nudgeButton("arrow.up",    dy: -step)
                    .keyboardShortcut(.upArrow, modifiers: [])
                nudgeButton("arrow.down",  dy:  step)
                    .keyboardShortcut(.downArrow, modifiers: [])

                Divider().frame(height: 20)

                // Size (scale from top-left anchor, aspect preserved)
                Text("Size").font(.caption.weight(.medium))
                sizeButton("minus", by: -step)
                    .keyboardShortcut("-", modifiers: [])
                sizeButton("plus", by:  step)
                    .keyboardShortcut("=", modifiers: [])  // ⌘= is common for zoom-in

                Divider().frame(height: 20)

                // Step picker
                Text("Step").font(.caption.weight(.medium))
                Picker("", selection: $step) {
                    Text("1").tag(CGFloat(1))
                    Text("2").tag(CGFloat(2))
                    Text("5").tag(CGFloat(5))
                    Text("10").tag(CGFloat(10))
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Text("px").font(.caption.monospaced()).foregroundStyle(.secondary)

                Spacer()
            }

            // Row 3: corner-radius slider
            HStack(spacing: 12) {
                Image(systemName: "app.badge.fill").imageScale(.small)
                Text("Corners").font(.caption.weight(.medium))
                Slider(value: $cornerRadius, in: 0...200)
                    .frame(width: 280)
                Text(String(format: "%.0f px", cornerRadius))
                    .font(.caption.monospaced())
                    .frame(width: 60, alignment: .leading)
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange, lineWidth: 2))
        .shadow(radius: 8)
    }

    private func nudgeButton(_ icon: String, dx: CGFloat = 0, dy: CGFloat = 0) -> some View {
        Button {
            rect.origin.x += dx
            rect.origin.y += dy
        } label: {
            Image(systemName: icon).frame(width: 20, height: 20)
        }
    }

    private func sizeButton(_ icon: String, by amount: CGFloat) -> some View {
        Button {
            // Scale from top-left — origin unchanged. Width changes by
            // `amount`; height is always derived from the PHYSICAL aspect
            // so the rect never drifts from the device's true ratio.
            let newW = max(8, rect.width + amount)
            let newH = newW * physicalAspect
            rect.size = CGSize(width: newW, height: newH)
        } label: {
            Image(systemName: icon).frame(width: 20, height: 20)
        }
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
