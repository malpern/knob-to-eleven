import ArgumentParser
import ElevenCore
import Foundation

@main
struct Eleven: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eleven",
        abstract: "Build apps that go to eleven — Work Louder SDK simulator + dev tool.",
        subcommands: [Run.self, Test.self, Render.self]
    )
}

// MARK: - Common options

struct GeometryOption {
    let width: Int
    let height: Int

    static func parse(_ s: String) -> GeometryOption? {
        let parts = s.split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]),
              w > 0, h > 0 else { return nil }
        return GeometryOption(width: w, height: h)
    }
    var asString: String { "\(width)x\(height)" }
}

// MARK: - run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Launch an app in an SDL window."
    )

    @Argument(help: "Path to app.py, or to a project directory containing app.py + optional worker.py")
    var path: String

    @Option(name: .long, help: "Display geometry as WxH (default: 170x320)")
    var geometry: String = "170x320"

    @Option(name: .long, help: "Window title (default: filename)")
    var title: String?

    func run() async throws {
        let resolved = try AppLocation.resolve(path)
        guard let geom = GeometryOption.parse(geometry) else {
            throw CLIError.generic("invalid --geometry \(geometry); expected WxH like 170x320")
        }
        let micropython = try Runtime.micropythonBinary()
        let coreDir = Runtime.coreDir()

        var env = ProcessInfo.processInfo.environment
        env["ELEVEN_APP_PATH"] = resolved.appPath.path
        env["ELEVEN_GEOMETRY"] = geom.asString
        env["ELEVEN_TITLE"] = title ?? resolved.appPath.deletingPathExtension().lastPathComponent
        env["ELEVEN_CORE_DIR"] = coreDir.path
        env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
        env["ELEVEN_PLATFORM"] = env["ELEVEN_PLATFORM"] ?? "nomad-v1"

        // If the project includes worker.py, spawn it on a TCP loopback port
        // and tell the host how to reach it.
        if let workerPath = resolved.workerPath {
            let port = try ephemeralPort()
            let logPath = URL(fileURLWithPath: "/tmp/eleven-worker-\(getpid()).log")
            let python3 = try findInPath("python3")
            _ = try spawnBackground(
                python3,
                arguments: [
                    coreDir.appendingPathComponent("worker_runner.py").path,
                    workerPath.path,
                    String(port)
                ],
                environment: env,
                logPath: logPath
            )
            env["ELEVEN_WORKER_PORT"] = String(port)
            FileHandle.standardError.write(
                "eleven: worker started on port \(port), log: \(logPath.path)\n".data(using: .utf8)!
            )
        }

        let host = coreDir.appendingPathComponent("host.py")
        let status = try runForeground(micropython, arguments: [host.path], environment: env)
        if status != 0 {
            throw ExitCode(status)
        }
    }
}

// MARK: - test

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run an automated test script (headless by default)."
    )

    @Argument(help: "Path to a test script")
    var path: String

    @Option(name: .long, help: "Display geometry (default: 170x320)")
    var geometry: String = "170x320"

    @Flag(name: .long, help: "Keep an SDL window visible during the test")
    var show: Bool = false

    func run() async throws {
        let resolved = try AppLocation.resolveScript(path)
        guard let geom = GeometryOption.parse(geometry) else {
            throw CLIError.generic("invalid --geometry \(geometry)")
        }
        let micropython = try Runtime.micropythonBinary()
        let coreDir = Runtime.coreDir()

        var env = ProcessInfo.processInfo.environment
        env["ELEVEN_TEST_SCRIPT"] = resolved.path
        env["ELEVEN_GEOMETRY"] = geom.asString
        env["ELEVEN_CORE_DIR"] = coreDir.path
        env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
        env["ELEVEN_PLATFORM"] = env["ELEVEN_PLATFORM"] ?? "nomad-v1"
        if show { env["ELEVEN_TEST_SHOW"] = "1" }

        let testHost = coreDir.appendingPathComponent("test_host.py")
        let status = try runForeground(micropython, arguments: [testHost.path], environment: env)
        if status != 0 {
            throw ExitCode(status)
        }
    }
}

// MARK: - render

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render an app to a PNG headlessly."
    )

    @Argument(help: "Path to app.py")
    var path: String

    @Option(name: .long, help: "Output PNG path (required)")
    var out: String

    @Option(name: .long, help: "Display geometry (default: 170x320)")
    var geometry: String = "170x320"

    @Option(name: .long, help: "Frames to advance before capturing (default: 1)")
    var frames: Int = 1

    @Option(name: .long, help: "Synthetic events: e.g. \"encoder:+3,button:0,step:30\"")
    var events: String = ""

    func run() async throws {
        let resolved = try AppLocation.resolve(path)
        guard let geom = GeometryOption.parse(geometry) else {
            throw CLIError.generic("invalid --geometry \(geometry)")
        }
        let micropython = try Runtime.micropythonBinary()
        let coreDir = Runtime.coreDir()
        let outURL = URL(fileURLWithPath: out)
        let outAbs = outURL.standardizedFileURL.path

        var env = ProcessInfo.processInfo.environment
        env["ELEVEN_APP_PATH"] = resolved.appPath.path
        env["ELEVEN_GEOMETRY"] = geom.asString
        env["ELEVEN_OUT"] = outAbs
        env["ELEVEN_FRAMES"] = String(frames)
        env["ELEVEN_PRE_EVENTS"] = events
        env["ELEVEN_CORE_DIR"] = coreDir.path
        env["ELEVEN_REPO_ROOT"] = Runtime.repoRoot().path
        env["ELEVEN_PLATFORM"] = env["ELEVEN_PLATFORM"] ?? "nomad-v1"

        let renderHost = coreDir.appendingPathComponent("render_host.py")
        let status = try runForeground(micropython, arguments: [renderHost.path], environment: env)
        if status != 0 { throw ExitCode(status) }

        // Convert PPM to PNG via macOS sips
        let sips = URL(fileURLWithPath: "/usr/bin/sips")
        let conv = try runForeground(
            sips,
            arguments: ["-s", "format", "png", outAbs + ".ppm", "--out", outAbs]
        )
        if conv != 0 {
            throw CLIError.generic("sips conversion failed (PPM at \(outAbs).ppm)")
        }
        try? FileManager.default.removeItem(atPath: outAbs + ".ppm")
        print("wrote \(outAbs)")
    }
}

// MARK: - path resolution

struct AppLocation {
    let appPath: URL
    let workerPath: URL?

    /// Resolve `path` as either a file (single app.py) or a directory
    /// (project with app.py + optional worker.py).
    static func resolve(_ path: String) throws -> AppLocation {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw CLIError.appNotFound(path: path)
        }
        if isDir.boolValue {
            let dir = URL(fileURLWithPath: path).standardizedFileURL
            let app = dir.appendingPathComponent("app.py")
            guard FileManager.default.fileExists(atPath: app.path) else {
                throw CLIError.appDirInvalid(path: path, reason: "no app.py inside")
            }
            let worker = dir.appendingPathComponent("worker.py")
            let workerExists = FileManager.default.fileExists(atPath: worker.path)
            return AppLocation(appPath: app, workerPath: workerExists ? worker : nil)
        }
        return AppLocation(appPath: URL(fileURLWithPath: path).standardizedFileURL,
                           workerPath: nil)
    }

    /// For test scripts: must be a file, never a directory.
    static func resolveScript(_ path: String) throws -> (path: String, url: URL) {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.appNotFound(path: path)
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return (url.path, url)
    }
}

// MARK: - misc

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
