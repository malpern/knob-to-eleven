import Foundation
import Observation
import ElevenCore

/// Drives a single `eleven run` invocation: spawns the subprocess (and
/// the worker.py if applicable), streams merged stdout to the UI line by
/// line, exposes a Stop affordance.
@MainActor
@Observable
final class RunSession {
    enum State: Equatable { case idle, running, exited(Int32), failed(String) }

    private(set) var state: State = .idle
    private(set) var lines: [String] = []
    private var process: Process?
    private var workerProcess: Process?
    let example: Example

    init(_ example: Example) {
        self.example = example
    }

    func start() {
        guard state != .running else { return }
        lines.removeAll()
        state = .running

        let micropython: URL
        do { micropython = try Runtime.micropythonBinary() }
        catch { state = .failed(String(describing: error)); return }

        var env = ProcessInfo.processInfo.environment
        env["ELEVEN_APP_PATH"] = example.appPath.path
        env["ELEVEN_GEOMETRY"] = "170x320"
        env["ELEVEN_TITLE"] = example.displayName
        env["ELEVEN_CORE_DIR"] = Runtime.coreDir().path
        env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
        env["ELEVEN_PLATFORM"] = env["ELEVEN_PLATFORM"] ?? "nomad-v1"

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

        let host = Runtime.coreDir().appendingPathComponent("host.py")
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
    }

    func stop() {
        process?.terminate()
        stopWorker()
    }

    private func stopWorker() {
        if let w = workerProcess, w.isRunning {
            w.terminate()
        }
        workerProcess = nil
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
