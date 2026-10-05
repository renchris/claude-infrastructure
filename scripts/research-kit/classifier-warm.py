#!/usr/bin/env python3
"""classifier-warm.py — the resident (warm) classifier for the re-ask router (decision 4bf73c4e55d5
option 3; wave E1c of docs/plans/RESEARCH_PROGRAM_BUILD.md).

A cold `claude -p` spends 2-4 s starting before the classifier reads a word, which is what pushes a
thinking classifier past the router's 9 s limit. This daemon pays that start ahead of time: it keeps
a small pool of classifier processes already started and waiting for their one prompt, and hands a
prompt to the oldest of them. A process labels ONE prompt and is ended, so no prompt ever shares a
context with another; the pool is refilled behind it.

  classifier-warm.py serve     the daemon (launchd job com.claude.research-classifier-warm, staged)
  classifier-warm.py ping      "ready N" and exit 0 when the daemon answers within 1 s; else exit 1
  classifier-warm.py ask [--timeout S]
                               classifier input on stdin, the classifier's raw answer on stdout;
                               exit 3 when the daemon is absent or has no process ready (make the
                               cold call), exit 1 when a process took the prompt and failed

It never chooses a label: router.py `classify` parses the answer exactly as it parses a cold call's,
and when this daemon is absent, busy or wrong the router makes the cold call or records
`unavailable` (§10 item 3). The 9 s limit is the router's and is not changed here.

One JSON line each way on a unix socket ($CC_RESEARCH_HOME/classifier-warm/sock, mode 0600 in a 0700
directory): {"op":"ask","text":…,"timeout":S} -> {"ok":true,"text":…} | {"ok":false,"why":…,
"cold":bool}; {"op":"ping"} -> {"ok":true,"ready":N}. `cold` true means no process took the prompt.

Test seams: CC_RESEARCH_WARM_SOCK (socket path; a unix socket path is capped near 100 bytes),
CC_RESEARCH_WARM_CHILD (a shell command standing in for the classifier process: one stream-json user
line on stdin, one {"type":"result","result":…} line on stdout), CC_RESEARCH_WARM_POOL,
CC_RESEARCH_WARM_MAX_AGE (seconds an unused process is kept).
"""

from __future__ import annotations

import argparse
import json
import os
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "lib"))
sys.path.insert(0, str(HERE))
import kit  # noqa: E402

POOL = 2  # processes kept waiting; two cover a prompt arriving while the pool refills
MAX_AGE_S = 900.0  # an unused process is replaced after this long, so none waits on a stale login
PING_TIMEOUT_S = 1.0
STREAM_FLAGS = [
    "--input-format",
    "stream-json",
    "--output-format",
    "stream-json",
    "--verbose",
]


def sock_path() -> Path:
    env = os.environ.get("CC_RESEARCH_WARM_SOCK")
    return Path(env) if env else kit.research_home() / "classifier-warm" / "sock"


def child_argv() -> Optional[List[str]]:
    env_cmd = os.environ.get("CC_RESEARCH_WARM_CHILD")
    if env_cmd:
        return ["/bin/bash", "-c", env_cmd]
    import router  # the one definition of the classifier's command line

    argv = router.classifier_argv()
    if argv is None or os.environ.get("CC_RESEARCH_CLASSIFIER"):
        return None
    return argv + STREAM_FLAGS


class Child:
    def __init__(self, argv: List[str]):
        self.dir = tempfile.mkdtemp(prefix="cc-research-warm-")
        self.born = time.time()
        self.proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=self.dir,
            env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"),
        )

    def alive(self) -> bool:
        return self.proc.poll() is None

    def end(self) -> None:
        try:
            self.proc.kill()
            self.proc.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass
        for f in (self.proc.stdin, self.proc.stdout):
            try:
                if f:
                    f.close()
            except OSError:
                pass
        shutil.rmtree(self.dir, ignore_errors=True)

    def ask(self, text: str, timeout: float) -> Tuple[Optional[str], str]:
        """(answer, why). The process's `result` line, read until the deadline."""
        deadline = time.time() + timeout
        line = (
            json.dumps({"type": "user", "message": {"role": "user", "content": text}})
            + "\n"
        )
        try:
            assert self.proc.stdin and self.proc.stdout
            self.proc.stdin.write(line.encode())
            self.proc.stdin.flush()
            fd = self.proc.stdout.fileno()
            buf = b""
            while True:
                left = deadline - time.time()
                if left <= 0:
                    return None, f"the warm classifier did not answer in {timeout:g} s"
                if not select.select([fd], [], [], left)[0]:
                    continue
                chunk = os.read(fd, 65536)
                if not chunk:
                    return None, "the warm classifier process ended without an answer"
                buf += chunk
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    try:
                        ev = json.loads(raw)
                    except ValueError:
                        continue
                    if isinstance(ev, dict) and ev.get("type") == "result":
                        if ev.get("is_error") or not isinstance(ev.get("result"), str):
                            return None, "the warm classifier process reported an error"
                        return ev["result"], "warm"
        except (OSError, AssertionError) as e:
            return None, f"the warm classifier process failed: {e.__class__.__name__}"


class Pool:
    def __init__(self, argv: List[str], size: int, max_age: float):
        self.argv, self.size, self.max_age = argv, size, max_age
        self.lock = threading.Lock()
        self.kids: List[Child] = []
        self.wake = threading.Event()
        self.stop = False
        self.early_deaths = 0

    def take(self) -> Optional[Child]:
        with self.lock:
            while self.kids:
                c = self.kids.pop(0)  # the oldest has had the longest to start
                if c.alive():
                    self.wake.set()
                    return c
                threading.Thread(target=c.end, daemon=True).start()
        self.wake.set()
        return None

    def ready(self) -> int:
        with self.lock:
            return sum(1 for c in self.kids if c.alive())

    def fill(self) -> None:
        """Keep `size` unused processes alive; back off when they die at once (a login that is out)."""
        while not self.stop:
            now = time.time()
            with self.lock:
                keep, drop = [], []
                for c in self.kids:
                    if not c.alive():
                        self.early_deaths += 1 if now - c.born < 30 else 0
                        drop.append(c)
                    elif now - c.born > self.max_age:
                        drop.append(c)
                    else:
                        keep.append(c)
                self.kids = keep
                need = self.size - len(keep)
            for c in drop:
                c.end()
            if need > 0 and self.early_deaths:
                self.wake.wait(min(60.0, 2.0 ** min(self.early_deaths, 6)))
            for _ in range(max(need, 0)):
                if self.stop:
                    break
                try:
                    c = Child(self.argv)
                except OSError:
                    self.early_deaths += 1
                    break
                with self.lock:
                    self.kids.append(c)
            if need <= 0:
                self.early_deaths = 0
            self.wake.wait(1.0)
            self.wake.clear()

    def close(self) -> None:
        self.stop = True
        self.wake.set()
        with self.lock:
            kids, self.kids = self.kids, []
        for c in kids:
            c.end()


def handle(conn: socket.socket, pool: Pool) -> None:
    try:
        conn.settimeout(5.0)
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk
        try:
            req = json.loads(buf.split(b"\n", 1)[0] or b"{}")
        except ValueError:
            req = {}
        if req.get("op") == "ping":
            out: Dict[str, Any] = {"ok": True, "ready": pool.ready()}
        elif req.get("op") == "ask" and isinstance(req.get("text"), str):
            child = pool.take()
            if child is None:
                out = {
                    "ok": False,
                    "cold": True,
                    "why": "no warm classifier process is ready",
                }
            else:
                try:
                    timeout = min(max(float(req.get("timeout") or 9.0), 0.1), 60.0)
                    answer, why = child.ask(req["text"], timeout)
                finally:
                    threading.Thread(target=child.end, daemon=True).start()
                out = (
                    {"ok": True, "text": answer}
                    if answer is not None
                    else {"ok": False, "cold": False, "why": why}
                )
        else:
            out = {"ok": False, "cold": True, "why": "not an ask or a ping"}
        conn.sendall(json.dumps(out).encode() + b"\n")
    except OSError:
        pass
    finally:
        conn.close()


def request(req: Dict[str, Any], timeout: float) -> Optional[Dict[str, Any]]:
    """One request to the daemon; None when it is absent or does not answer in time."""
    p = sock_path()
    if not p.exists():
        return None
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(PING_TIMEOUT_S)
        s.connect(str(p))
        s.sendall(json.dumps(req).encode() + b"\n")
        s.settimeout(timeout)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        out = json.loads(buf.split(b"\n", 1)[0])
        return out if isinstance(out, dict) else None
    except (OSError, ValueError):
        return None
    finally:
        s.close()


def serve() -> int:
    argv = child_argv()
    if argv is None:
        print(
            "classifier-warm: no classifier command (`claude` is not on PATH)",
            file=sys.stderr,
        )
        return 1
    p = sock_path()
    if request({"op": "ping"}, PING_TIMEOUT_S) is not None:
        print(f"classifier-warm: a daemon already answers on {p}", file=sys.stderr)
        return 0
    p.parent.mkdir(parents=True, exist_ok=True)
    p.parent.chmod(0o700)
    try:
        p.unlink()  # a socket nobody answers on is a dead daemon's
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old = os.umask(0o177)
    try:
        srv.bind(str(p))
    finally:
        os.umask(old)
    srv.listen(16)
    try:
        size = max(1, int(os.environ.get("CC_RESEARCH_WARM_POOL") or POOL))
        max_age = float(os.environ.get("CC_RESEARCH_WARM_MAX_AGE") or MAX_AGE_S)
    except ValueError:
        size, max_age = POOL, MAX_AGE_S
    pool = Pool(argv, size, max_age)
    threading.Thread(target=pool.fill, daemon=True).start()

    def bye(*_: Any) -> None:
        pool.close()
        try:
            p.unlink()
        except OSError:
            pass
        os._exit(0)

    signal.signal(signal.SIGTERM, bye)
    signal.signal(signal.SIGINT, bye)
    print(
        f"classifier-warm: serving on {p}, {size} process(es) kept ready",
        file=sys.stderr,
    )
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn, pool), daemon=True).start()


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="classifier-warm.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    sub.add_parser("serve")
    sub.add_parser("ping")
    p = sub.add_parser("ask")
    p.add_argument("--timeout", type=float, default=9.0)
    a = ap.parse_args(argv)
    if a.verb == "serve":
        return serve()
    if a.verb == "ping":
        out = request({"op": "ping"}, PING_TIMEOUT_S)
        if not out or not out.get("ok"):
            print("classifier-warm: no daemon answered within 1 s", file=sys.stderr)
            return 1
        print(f"ready {out.get('ready', 0)}")
        return 0
    out = request(
        {"op": "ask", "text": sys.stdin.read(), "timeout": a.timeout}, a.timeout + 1.0
    )
    if out and out.get("ok"):
        print(out.get("text", ""))
        return 0
    why = (out or {}).get("why") or "no daemon answered"
    print(f"classifier-warm: {why}", file=sys.stderr)
    return 3 if out is None or out.get("cold") else 1


if __name__ == "__main__":
    sys.exit(main())
