import Foundation
import Observation
import CoreGraphics
import AppKit
import ElevenCore

/// Drives a single `eleven run` invocation: spawns the subprocess (and
/// the worker.py if applicable), streams merged stdout to the UI line by
/// line, exposes a Stop affordance, and streams the live framebuffer so
/// the device-photo preview animates in real time.
@MainActor
@Observable
final class RunSession {
    enum State: Equatable { case idle, running, exited(Int32), failed(String) }

    private(set) var state: State = .idle
    private(set) var lines: [String] = []
    /// Latest live frame from the running app. Updated at display rate.
    private(set) var latestFrame: NSImage?

    private var process: Process?
    private var workerProcess: Process?
    private var framebuffer: SharedFramebuffer?
    private var frameTimer: Timer?
    private var fbPath: String?
    private var inputPath: String?
    let example: Example

    init(_ example: Example) {
        self.example = example
    }

    func start() {
        guard state != .running else { return }
        lines.removeAll()
        latestFrame = nil
        state = .running

        let micropython: URL
        do { micropython = try Runtime.micropythonBinary() }
        catch { state = .failed(String(describing: error)); return }

        // Unique path per session — lets us mmap it from Swift.
        let sessionFBPath = "/tmp/eleven-fb-\(getpid())-\(Int.random(in: 1...9999)).raw"
        self.fbPath = sessionFBPath

        // Input-injection stream. We create the file fresh (truncate)
        // so host_headless.py starts from offset 0.
        let sessionInputPath = "/tmp/eleven-input-\(getpid())-\(Int.random(in: 1...9999)).jsonl"
        FileManager.default.createFile(atPath: sessionInputPath, contents: nil)
        self.inputPath = sessionInputPath

        var env = ProcessInfo.processInfo.environment
        env["ELEVEN_APP_PATH"] = example.appPath.path
        env["ELEVEN_GEOMETRY"] = "100x310"
        env["ELEVEN_TITLE"] = example.displayName
        env["ELEVEN_CORE_DIR"] = Runtime.coreDir().path
        env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
        env["ELEVEN_PLATFORM"] = env["ELEVEN_PLATFORM"] ?? "knob-v1"
        env["ELEVEN_FB_PATH"] = sessionFBPath
        env["ELEVEN_INPUT_PATH"] = sessionInputPath

        // Worker.py if this is a project-dir example
        if let worker = example.workerPath {
            do {
                let port = try ephemeralPort()
                env["ELEVEN_WORKER_PORT"] = String(port)
                let logURL = URL(fileURLWithPath: "/tmp/eleven-app-worker-\(getpid())-\(port).log")
                let python3 = try findInPath("python3")
                workerProcess = try spawnBackground(
                    python3,
                    arguments: [
                        Runtime.coreDir().appendingPathComponent("worker_runner.py").path,
                        worker.path,
                        String(port)
                    ],
                    environment: env,
                    logPath: logURL
                )
                appendLine("[worker spawned on port \(port), log: \(logURL.path)]")
            } catch {
                state = .failed("worker spawn failed: \(error)")
                return
            }
        }

        // Launch the headless host (no SDL window; writes framebuffer to file)
        let host = Runtime.coreDir().appendingPathComponent("host_headless.py")
        do {
            process = try spawnStreaming(
                micropython,
                arguments: [host.path],
                environment: env,
                onLine: { [weak self] line in
                    Task { @MainActor in self?.appendLine(line) }
                },
                onExit: { [weak self] status in
                    Task { @MainActor in self?.handleExit(status) }
                }
            )
        } catch {
            state = .failed("spawn failed: \(error)")
            stopWorker()
            return
        }

        // Connect to the shared framebuffer and start polling frames
        attachFramebuffer(path: sessionFBPath)
    }

    private func attachFramebuffer(path: String) {
        Task.detached { [weak self] in
            // Opening mmaps the file; it waits briefly for the host to create it.
            let fb: SharedFramebuffer
            do {
                fb = try SharedFramebuffer(path: path, width: 100, height: 310)
            } catch {
                await MainActor.run {
                    self?.appendLine("[framebuffer attach failed: \(error)]")
                }
                return
            }
            await MainActor.run {
                guard let self else { return }
                self.framebuffer = fb
                // Poll at ~60fps
                self.frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0,
                                                       repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.pollFrame() }
                }
            }
        }
    }

    private func pollFrame() {
        guard let fb = framebuffer,
              let cgImage = fb.pollForNewFrame() else { return }
        let size = NSSize(width: CGFloat(fb.width), height: CGFloat(fb.height))
        latestFrame = NSImage(cgImage: cgImage, size: size)
    }

    func stop() {
        process?.terminate()
        stopWorker()
        stopFramebuffer()
        stopInput()
    }

    /// Inject a top-encoder tick into the running app. `delta` is +1 for
    /// clockwise, -1 for counter-clockwise. No-op when nothing's running.
    func injectEncoder(_ delta: Int) {
        guard state == .running, let path = inputPath else { return }
        writeInputLine("{\"type\":\"encoder\",\"idx\":0,\"val\":\(delta)}",
                       path: path)
    }

    private func writeInputLine(_ line: String, path: String) {
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        if let data = (line + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    private func stopInput() {
        if let path = inputPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        inputPath = nil
    }

    private func stopWorker() {
        if let w = workerProcess, w.isRunning {
            w.terminate()
        }
        workerProcess = nil
    }

    private func stopFramebuffer() {
        frameTimer?.invalidate()
        frameTimer = nil
        framebuffer = nil
        if let path = fbPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        fbPath = nil
    }

    private func appendLine(_ line: String) {
        lines.append(line)
        // Cap the buffer so a runaway app doesn't consume unbounded memory
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
    }

    private func handleExit(_ status: Int32) {
        stopWorker()
        stopFramebuffer()
        if state == .running {
            state = .exited(status)
        }
    }
}


// Small helper duplicated from the CLI — same logic, different module
@inline(__always)
func findInPath(_ name: String) throws -> URL {
    let env = ProcessInfo.processInfo.environment
    let path = env["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    for dir in path.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    throw CLIError.generic("\(name) not found in PATH")
}
