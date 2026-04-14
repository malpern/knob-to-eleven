import Foundation

/// Discover where things live: MicroPython binary, repo root, core dir.
public enum Runtime {

    /// Path to the lv_micropython binary.
    /// Resolution order:
    /// 1. ELEVEN_MICROPYTHON env var
    /// 2. <repoRoot>/bin/micropython
    /// 3. ~/local-code/worklouder/spikes/lvgl-mpy-macos/lv_micropython/ports/unix/build-lvgl/micropython
    ///    (the dev location while we don't have a bootstrap script yet)
    public static func micropythonBinary() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["ELEVEN_MICROPYTHON"] {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
            throw CLIError.micropythonNotFound(
                tried: [env],
                hint: "ELEVEN_MICROPYTHON points to a missing or non-executable file"
            )
        }

        var tried: [String] = []
        let candidates: [URL] = [
            repoRoot().appendingPathComponent("bin/micropython"),
            URL(fileURLWithPath: NSString(string:
                "~/local-code/worklouder/spikes/lvgl-mpy-macos/lv_micropython/ports/unix/build-lvgl/micropython"
            ).expandingTildeInPath),
        ]
        for c in candidates {
            tried.append(c.path)
            if FileManager.default.isExecutableFile(atPath: c.path) {
                return c
            }
        }
        throw CLIError.micropythonNotFound(
            tried: tried,
            hint: "Build lv_micropython, drop the binary at <repo>/bin/micropython, or set ELEVEN_MICROPYTHON"
        )
    }

    /// Repo root = parent of `mac/`. Inferred from the running binary's location
    /// when run via `swift run`, or from CWD/PATH discovery otherwise.
    /// MVP heuristic: walk up from the running executable to find the dir
    /// containing both `core/` and `mac/`.
    public static func repoRoot() -> URL {
        // 1. ELEVEN_REPO_ROOT override (useful for tests)
        if let env = ProcessInfo.processInfo.environment["ELEVEN_REPO_ROOT"] {
            return URL(fileURLWithPath: env)
        }
        // 2. Walk up from this binary
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<10 {
            let core = dir.appendingPathComponent("core")
            let macDir = dir.appendingPathComponent("mac")
            if FileManager.default.fileExists(atPath: core.path)
                && FileManager.default.fileExists(atPath: macDir.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        // 3. Fall back to CWD
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// Absolute path to `<repo>/core`.
    public static func coreDir() -> URL {
        repoRoot().appendingPathComponent("core")
    }

    /// Absolute path to `<repo>/examples`.
    public static func examplesDir() -> URL {
        repoRoot().appendingPathComponent("examples")
    }
}

public enum CLIError: Error, CustomStringConvertible {
    case micropythonNotFound(tried: [String], hint: String)
    case appNotFound(path: String)
    case appDirInvalid(path: String, reason: String)
    case workerSpawnFailed(reason: String)
    case generic(String)

    public var description: String {
        switch self {
        case .micropythonNotFound(let tried, let hint):
            let triedStr = tried.map { "  - \($0)" }.joined(separator: "\n")
            return "couldn't find micropython binary. Tried:\n\(triedStr)\nhint: \(hint)"
        case .appNotFound(let path):
            return "app not found: \(path)"
        case .appDirInvalid(let path, let reason):
            return "invalid app dir \(path): \(reason)"
        case .workerSpawnFailed(let reason):
            return "worker subprocess failed: \(reason)"
        case .generic(let msg):
            return msg
        }
    }
}
