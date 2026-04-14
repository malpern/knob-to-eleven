import Foundation

/// Tracks subprocesses started during a run and ensures they're killed on
/// any exit path — normal completion, signals (Ctrl-C), or uncaught errors.
///
/// The bash CLI relied on bash traps; this is the Swift equivalent. Using
/// a singleton because POSIX signal handlers can't easily capture state.
public final class ProcessGroup {
    public static let shared = ProcessGroup()

    private var pids: [pid_t] = []
    private let lock = NSLock()
    private var signalHandlersInstalled = false

    private init() {}

    public func track(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        pids.append(process.processIdentifier)
        installSignalHandlersIfNeeded()
    }

    /// Send SIGTERM to all tracked processes, wait briefly, then SIGKILL
    /// any survivors.
    public func killAll() {
        lock.lock()
        let snapshot = pids
        pids.removeAll()
        lock.unlock()

        for pid in snapshot {
            kill(pid, SIGTERM)
        }
        // Brief grace period — most well-behaved children exit on SIGTERM
        usleep(200_000) // 200ms
        for pid in snapshot {
            // killpg too in case the child set its own pgrp; ignore failures
            kill(pid, SIGKILL)
        }
    }

    private func installSignalHandlersIfNeeded() {
        guard !signalHandlersInstalled else { return }
        signalHandlersInstalled = true
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig) { sigNum in
                ProcessGroup.shared.killAll()
                // Re-raise default handler so the process actually exits
                signal(sigNum, SIG_DFL)
                raise(sigNum)
            }
        }
        atexit {
            ProcessGroup.shared.killAll()
        }
    }
}

/// Run a Process inheriting stdio, with signal-aware cleanup. Blocks until
/// it exits and returns its termination status.
@discardableResult
public func runForeground(
    _ executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil
) throws -> Int32 {
    let p = Process()
    p.executableURL = executable
    p.arguments = arguments
    if let env = environment { p.environment = env }
    p.standardInput = FileHandle.standardInput
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    try p.run()
    ProcessGroup.shared.track(p)
    p.waitUntilExit()
    return p.terminationStatus
}

/// Spawn a Process in the background. Output goes to the given log path
/// (created if missing). Returns the started Process.
@discardableResult
public func spawnBackground(
    _ executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    logPath: URL
) throws -> Process {
    FileManager.default.createFile(atPath: logPath.path, contents: nil)
    guard let logHandle = try? FileHandle(forWritingTo: logPath) else {
        throw CLIError.workerSpawnFailed(reason: "couldn't open log at \(logPath.path)")
    }
    let p = Process()
    p.executableURL = executable
    p.arguments = arguments
    if let env = environment { p.environment = env }
    p.standardOutput = logHandle
    p.standardError = logHandle
    try p.run()
    ProcessGroup.shared.track(p)
    return p
}

/// Pick a free TCP port on 127.0.0.1.
public func ephemeralPort() throws -> Int {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw CLIError.generic("socket() failed")
    }
    defer { close(fd) }
    let bindResult = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            bind(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        throw CLIError.generic("bind() failed: errno \(errno)")
    }
    var assigned = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let getResult = withUnsafeMutablePointer(to: &assigned) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
            getsockname(fd, ptr, &len)
        }
    }
    guard getResult == 0 else {
        throw CLIError.generic("getsockname() failed")
    }
    let port = UInt16(bigEndian: assigned.sin_port)
    return Int(port)
}


// MARK: - Stream-based subprocess (used by the SwiftUI app)

/// Spawn a Process and stream its merged stdout/stderr to `onLine` callback,
/// one line at a time. Returns the started Process so the caller can
/// observe `isRunning` and call `terminate()`.
///
/// `onLine` is invoked from a background queue. Callers are responsible
/// for hopping to the main actor before touching UI state.
@discardableResult
public func spawnStreaming(
    _ executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    onLine: @escaping @Sendable (String) -> Void,
    onExit: @escaping @Sendable (Int32) -> Void = { _ in }
) throws -> Process {
    let p = Process()
    p.executableURL = executable
    p.arguments = arguments
    if let env = environment { p.environment = env }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe

    // Read in chunks; split on newlines.
    let handle = pipe.fileHandleForReading
    var buffer = Data()
    handle.readabilityHandler = { fh in
        let chunk = fh.availableData
        if chunk.isEmpty {
            // EOF — flush any partial buffered line and detach
            if !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8), !s.isEmpty {
                onLine(s)
            }
            buffer.removeAll()
            fh.readabilityHandler = nil
            return
        }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<nl)
            buffer.removeSubrange(0...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine(line)
            }
        }
    }

    p.terminationHandler = { proc in
        // Closing the pipe ensures readabilityHandler sees EOF
        try? handle.close()
        onExit(proc.terminationStatus)
    }

    try p.run()
    ProcessGroup.shared.track(p)
    return p
}
