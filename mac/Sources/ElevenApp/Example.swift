import Foundation
import ElevenCore

/// One discoverable example app on disk. Either a single `.py` file or a
/// project directory with `app.py` (+ optional `worker.py`).
struct Example: Identifiable, Hashable {
    enum Kind: String { case singleFile, projectDir }

    let id: String           // examples-relative path, e.g. "hello.py" or "cpu/"
    let displayName: String  // pretty name for UI
    let kind: Kind
    let appPath: URL         // path to app.py
    let workerPath: URL?     // for projectDir, optional
    let summary: String      // first non-shebang comment block from app.py

    /// Path you'd pass to `eleven run` — for project-dirs that's the dir,
    /// for single-files that's the .py.
    var runPath: URL {
        switch kind {
        case .singleFile: return appPath
        case .projectDir: return appPath.deletingLastPathComponent()
        }
    }
}

enum ExampleScanner {
    static func scan() -> [Example] {
        let dir = Runtime.examplesDir()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir,
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else {
            return []
        }
        var out: [Example] = []
        for entry in entries {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            if isDir.boolValue {
                let app = entry.appendingPathComponent("app.py")
                guard fm.fileExists(atPath: app.path) else { continue }
                let worker = entry.appendingPathComponent("worker.py")
                let workerExists = fm.fileExists(atPath: worker.path)
                let name = entry.lastPathComponent
                out.append(Example(
                    id: name + "/",
                    displayName: name + "/",
                    kind: .projectDir,
                    appPath: app,
                    workerPath: workerExists ? worker : nil,
                    summary: extractSummary(from: app)
                ))
            } else if entry.pathExtension == "py" {
                let name = entry.deletingPathExtension().lastPathComponent
                out.append(Example(
                    id: entry.lastPathComponent,
                    displayName: name,
                    kind: .singleFile,
                    appPath: entry,
                    workerPath: nil,
                    summary: extractSummary(from: entry)
                ))
            }
        }
        return out.sorted { $0.displayName < $1.displayName }
    }

    /// Pull the first comment block from a Python file as a one-line summary.
    private static func extractSummary(from url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        var lines: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(20) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#!") { continue }
            if line.hasPrefix("#") {
                let stripped = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { lines.append(stripped) }
                continue
            }
            if line.isEmpty && lines.isEmpty { continue }
            // Stop at first non-comment, non-blank line
            break
        }
        return lines.joined(separator: " ").prefix(160).description
    }
}
