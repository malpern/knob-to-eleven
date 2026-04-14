#!/usr/bin/env python3
"""
worker_runner — runs a user's worker.py with the wlsdk host-side
globals injected and a JSON-line bridge to the parent (the eleven host
running MicroPython) over TCP loopback.

Usage: worker_runner.py <worker.py> <port>

We use TCP on 127.0.0.1 (and not Unix sockets) because lv_micropython's
socket module accepts AF_UNIX as a constant but errors with ENOTSUP on
connect() — so Unix sockets aren't a viable transport on MicroPython
side, but TCP loopback works fine.

Wire format (newline-delimited JSON, both directions):

  Worker → device:
    {"type":"send_rpc","method":"wlsdk.cpu.update","params":{...}}
    {"type":"register_notify","method":"wlsdk.foo"}
    {"type":"log","msg":"..."}

  Device → worker:
    {"type":"notify","method":"wlsdk.foo","params":{...}}

We don't model RPC request/response correlation in v0.1 — most
patterns are fire-and-forget either direction.
"""

import json
import os
import socket
import subprocess
import sys
import threading
import time


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("worker_runner: usage: worker_runner.py <worker.py> <port>\n")
        sys.exit(2)
    worker_path = sys.argv[1]
    try:
        port = int(sys.argv[2])
    except ValueError:
        sys.stderr.write("worker_runner: port must be an integer\n")
        sys.exit(2)
    if not os.path.exists(worker_path):
        sys.stderr.write("worker_runner: not found: " + worker_path + "\n")
        sys.exit(2)

    # TCP loopback server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    server.settimeout(10.0)

    try:
        conn, _ = server.accept()
    except socket.timeout:
        sys.stderr.write("worker_runner: host did not connect within 10s\n")
        sys.exit(2)
    finally:
        server.close()

    # Wire I/O. We use a lock so emits from any thread serialize cleanly.
    write_lock = threading.Lock()

    def emit(obj):
        line = (json.dumps(obj) + "\n").encode("utf-8")
        with write_lock:
            try:
                conn.sendall(line)
            except (BrokenPipeError, OSError):
                # Host gone; nothing to do
                pass

    def _log(msg):
        emit({"type": "log", "msg": str(msg)})

    def _register_notify(method):
        if not method.startswith("wlsdk."):
            method = "wlsdk." + method
        emit({"type": "register_notify", "method": method})

    def _send_rpc(method, params=None):
        if not method.startswith("wlsdk."):
            method = "wlsdk." + method
        emit({"type": "send_rpc", "method": method, "params": params})

    def _exec_process(cmd):
        try:
            return subprocess.check_output(
                cmd, shell=True, timeout=10, text=True,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            return ""

    # Build the worker.py namespace. Mirrors the Pyodide environment
    # Work Louder ships in their Input app:
    #   log(msg)
    #   register_notify(method)
    #   send_rpc(method, params=None)
    #   exec_process(cmd) -> str
    ns = {
        "__name__": "__main__",
        "__file__": worker_path,
        "log": _log,
        "register_notify": _register_notify,
        "send_rpc": _send_rpc,
        "exec_process": _exec_process,
    }

    with open(worker_path) as f:
        src = f.read()

    # Spin the inbound socket reader on a daemon thread so worker.py is
    # free to do whatever it wants on the main thread (loop, sleep, etc.).
    # When main thread exits, this thread dies with it.
    def _reader():
        handle_notify_fn = None  # resolved lazily — worker may define later
        buf = b""
        while True:
            try:
                chunk = conn.recv(4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line.decode("utf-8"))
                except Exception:
                    _log("worker_runner: bad JSON")
                    continue
                if msg.get("type") == "notify":
                    if handle_notify_fn is None:
                        handle_notify_fn = ns.get("handle_notify")
                    if callable(handle_notify_fn):
                        method = msg.get("method", "")
                        params = msg.get("params")
                        try:
                            handle_notify_fn(method, params)
                        except Exception as e:
                            _log("handle_notify raised: " + repr(e))

    reader_thread = threading.Thread(target=_reader, daemon=True)
    reader_thread.start()

    try:
        exec(compile(src, worker_path, "exec"), ns)
    except Exception as e:
        _log("worker.py raised: " + repr(e))
    finally:
        try: conn.close()
        except Exception: pass


if __name__ == "__main__":
    main()
