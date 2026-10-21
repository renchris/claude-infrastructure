#!/usr/bin/env python3
"""stub-claude — the lr-recon rig's fake `claude` (FLEET_V2 W5). Symlinked as `claude` first on PATH
and named by LR_CLAUDE_BIN, so every actuator that launches claude launches this.

It is a TUI in a real kitty pane, indistinguishable TO THE RECOVERY SCRIPTS from Claude Code 2.1.284:
it renders W0's captured frames (tests/fixtures/lr-recon/screens/*.txt), writes W0's JSONL record
shapes (tests/fixtures/lr-recon/jsonl/*.jsonl) to <cfg>/projects/<slug>/<sid>.jsonl, a
<cfg>/sessions/<pid>.json row and a rig-tagged registry row (the SessionStart hook's), and reacts to
the keys the scripts send: bracketed paste, \\r, \\x15, \\x7f, \\x0c, Esc, digits, /exit.

  claude --session-id SID            a fresh session: history, then its starting state (limit death,
                                     or idle at rest), then the composer. Writes the boot marker.
  claude --resume SID                the target side of a move: the transcript must already be under
                                     $CLAUDE_CONFIG_DIR, else "No conversation found" and exit 1.
  claude --rig-write-dead SID --rig-cwd DIR
                                     no UI: a limit-dead transcript and no process (a stale request).

Every fault knob is per sid, read from $LR_RIG_SPECS/<sid>.json (rig_lib.py expand). Per-sid progress
that must survive the process (a swallowed Enter happens once, a first-turn fault once) lives in
$LR_RIG/tmp/stub/<sid>.json. Stdlib only.

Load-harness knobs (B1 §9.2, W4). All off unless the spec carries them:
  busy_for_s N             a late death: WORKING until go + N, then an assistant partial and the
                           limit (records busy_until); replaces die_at_s for that member
  goal_meta_after_limit    after the limit, an isMeta /goal record stamped 1 s BEFORE it (769b7294)
  composer_unreadable_s N  from died_at to died_at + N the frame has no input box (garble_until)
  heavy_lead_subagents K   at death, K subagent transcripts with mtime died_at − 60 (plan weight)
  boot_delay_s N|[lo,hi]   per resume: sleep before READY; a [lo,hi] range is drawn per process
  slow_boots K             only the first K resumes take boot_delay_s; later ones take boot_delay_bin
  boot_delay_bin {median, p90, cap}  a lognormal draw per resume (gap-4's distribution for a bin)
  boot_cpu_s N             per resume: burn N CPU-s before READY (calibrated from real boots)
  busy_forever             a busy_extra pane: WORKING for ever, never dies (holds the restore budget)
  idle_then_limit          with idle: at rest from boot (so a move lane queues it straight into its
                           slot wait), then at go + die_at_s a user turn that hits the limit (W4b, T5)
  stop_failure_hook PATH   at death, pipe a StopFailure JSON to PATH (the G2 seam; B1 uses none)
Every invocation appends `t pid base stub mode` to $LR_RECON_ROOT/band-calls.log (F14: the band is
read INSIDE the call path, where a 5 s sampler cannot see a short-lived child). A draft member logs
any ^U, DEL or submit applied to its draft as `draft_mut` in its state file (H8).
"""

import hashlib
import json
import math
import os
import random
import select
import signal
import subprocess
import sys
import termios
import time
import tty
import uuid

RIG = os.environ.get("LR_RIG", "/tmp/lr-rig")
HERE = os.path.dirname(os.path.realpath(__file__))
FIX = os.path.join(HERE, "..", "fixtures", "lr-recon")
VERSION = "2.1.284"
ESC = "\x1b"
LIMIT_NOTICE = "  ⎿  You've hit your session limit · resets 1:30am (America/Chicago)"
PASTE_ON, PASTE_OFF = ESC + "[200~", ESC + "[201~"
HARNESS_FIX = os.path.join(HERE, "..", "fixtures", "lr-load-harness")


def band_record(mode):
    """F14: this process's BASE priority, read in the call path, one line per invocation. Never
    fatal: a stub that cannot record its band still runs (the harness counts the missing lines)."""
    try:
        sys.path.insert(0, os.path.join(HERE, "..", "..", "scripts", "limit-recover"))
        from lr_recon import band as _band  # type: ignore

        base = _band.base_priority(os.getpid())
    except Exception:  # noqa: BLE001 — a reader, never a crash
        base = None
    root = os.environ.get("LR_RECON_ROOT") or os.path.join(RIG, "state")
    try:
        with open(os.path.join(root, "band-calls.log"), "a") as fh:
            fh.write(
                "%d\t%d\t%s\tstub\t%s\n"
                % (time.time(), os.getpid(), "?" if base is None else base, mode)
            )
    except OSError:
        pass


def _limited_path(cfg):
    return os.path.join(RIG, "tmp", "limited", os.path.basename(os.path.realpath(cfg)))


def limited_until(cfg):
    """The epoch an account's own limit lifts (go_barrier matrices: the limit is account-wide)."""
    try:
        with open(_limited_path(cfg)) as fh:
            return float(fh.read().strip() or 0)
    except (OSError, ValueError):
        return 0.0


def mark_limited(cfg, until):
    os.makedirs(os.path.dirname(_limited_path(cfg)), exist_ok=True)
    with open(_limited_path(cfg), "w") as fh:
        fh.write("%.0f\n" % until)


def burn_cpu(seconds):
    """Real CPU in this process's band (the band tax is the point): sha256 over 1 MiB until
    process_time has advanced by ``seconds``."""
    if not seconds or seconds <= 0:
        return
    buf, end = b"\0" * (1 << 20), time.process_time() + float(seconds)
    while time.process_time() < end:
        hashlib.sha256(buf).digest()


def lognormal_draw(rng, median, p90, cap):
    """A lognormal with this median and p90 (z90 = 1.2816), capped: gap-4's boot+first-turn
    distribution for one load bin (30-40/core: median 46 s, p90 212 s)."""
    mu = math.log(max(0.1, float(median)))
    sigma = max(0.0, (math.log(max(float(p90), float(median) + 0.1)) - mu) / 1.2816)
    return min(float(cap), rng.lognormvariate(mu, sigma))


# ── files ───────────────────────────────────────────────────────────────────────────────────────


def slug(cwd):
    return cwd.replace("/", "-").replace(".", "-")


def now_iso(back_s=0.0):
    t = time.time() - back_s
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % (
        int(t * 1000) % 1000
    )


def fixture(name):
    with open(os.path.join(FIX, "jsonl", name + ".jsonl")) as fh:
        return json.loads(fh.readline())


def lstart(pid):
    out = subprocess.run(
        ["/bin/ps", "-o", "lstart=", "-p", str(pid)],
        capture_output=True,
        text=True,
        env=dict(os.environ, TZ="UTC", LC_ALL="C"),
    ).stdout
    return " ".join(out.split())


def atomic(path, obj):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        json.dump(obj, fh, separators=(",", ":"))
    os.replace(tmp, path)


class Session:
    def __init__(self, sid, cfg, cwd):
        self.sid, self.cfg, self.cwd = sid, cfg, cwd
        self.tx = os.path.join(cfg, "projects", slug(cwd), sid + ".jsonl")
        self.parent = None
        self.back_s = 0.0  # history written BEFORE now (an idle session's last turn predates the limit)
        try:
            with open(
                os.path.join(
                    os.environ.get("LR_RIG_SPECS", RIG + "/specs"), sid + ".json"
                )
            ) as fh:
                self.spec = json.load(fh)
        except (OSError, ValueError):
            self.spec = {"knobs": {}}
        self.knobs = self.spec.get("knobs") or {}
        self.state_path = os.path.join(RIG, "tmp", "stub", sid + ".json")
        os.makedirs(os.path.dirname(self.state_path), exist_ok=True)

    # per-sid progress across processes
    def state(self):
        try:
            with open(self.state_path) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return {}

    def mark(self, **kv):
        st = self.state()
        st.update(kv)
        atomic(self.state_path, st)

    def append(self, rec):
        rec.setdefault("uuid", str(uuid.uuid4()))
        rec["parentUuid"] = self.parent
        rec["sessionId"], rec["cwd"] = self.sid, self.cwd
        rec["timestamp"] = now_iso(self.back_s)
        rec.setdefault("version", VERSION)
        self.parent = rec["uuid"]
        os.makedirs(os.path.dirname(self.tx), exist_ok=True)
        with open(self.tx, "a") as fh:
            fh.write(json.dumps(rec, separators=(",", ":")) + "\n")
            fh.flush()
            os.fsync(fh.fileno())

    def user(self, text, origin="human"):
        rec = fixture("user-prompt")
        rec["message"] = {"role": "user", "content": text}
        rec["origin"] = {"kind": origin}
        rec["promptId"] = str(uuid.uuid4())
        self.append(rec)

    def assistant(self, text="Done.", model="claude-opus-5-5"):
        rec = fixture("assistant-turn")
        rec["message"]["content"] = [{"type": "text", "text": text}]
        rec["message"]["model"] = model
        rec["message"]["id"] = "msg_" + uuid.uuid4().hex[:24]
        rec["effort"] = "high"
        self.append(rec)

    def error(self, kind):
        name = {
            "limit": "death-quota-limits",
            "limit7d": "death-quota-limits-seven-day",
            "529": "api-error-529",
            "auth": "authentication-failed",
        }[kind]
        rec = fixture(name)
        rec.pop("requestId", None)
        rec["session_id"] = self.sid
        if kind.startswith(
            "limit"
        ):  # a reset 3 h out, so the stay rule never parks the rig — unless the knob asks
            at = int(time.time()) + int(self.knobs.get("reset_in_s") or 3 * 3600)
            rec["quotaLimits"]["resetsAt"] = at
            word = "weekly" if kind == "limit7d" else "session"
            when = time.strftime("%-I:%M%p", time.localtime(at)).lower()
            rec["message"]["content"] = [
                {
                    "type": "text",
                    "text": "You've hit your %s limit · resets %s (America/Chicago)"
                    % (word, when),
                }
            ]
        self.append(rec)

    def last_uuid(self):
        try:
            with open(self.tx, "rb") as fh:
                lines = fh.read().splitlines()
        except OSError:
            return None
        for ln in reversed(lines):
            try:
                return json.loads(ln).get("uuid")
            except ValueError:
                continue
        return None

    def unregister(self):
        try:
            os.unlink(self.row_path)
        except OSError:
            pass

    def register(self, pid):
        ls = lstart(pid)
        row = {
            "pid": pid,
            "sessionId": self.sid,
            "cwd": self.cwd,
            "startedAt": int(time.time() * 1000),
            "procStart": ls,
            "version": VERSION,
            "kind": "interactive",
            "entrypoint": "cli",
            "status": "idle",
            "updatedAt": int(time.time() * 1000),
        }
        d = os.path.join(self.cfg, "sessions")
        os.makedirs(d, exist_ok=True)
        self.row_path = os.path.join(d, "%d.json" % pid)
        atomic(self.row_path, row)
        import atexit

        atexit.register(self.unregister)
        wid = (
            os.environ.get("CC_PANE_ID")
            or os.environ.get("ITERM_SESSION_ID")
            or os.environ.get("KITTY_WINDOW_ID", "")
        ).split(":")[-1]
        reg = os.path.join(os.environ.get("HOME", ""), ".claude", "cc-registry")
        os.makedirs(reg, exist_ok=True)
        acct = os.path.basename(os.path.normpath(self.cfg)).lstrip(".")
        atomic(
            os.path.join(reg, "%s.json" % (wid or pid)),
            {
                "paneUUID": wid,
                "name": "rig s%02d" % int(self.spec.get("n", 0)),
                "cwd": self.cwd,
                "account": acct,
                "pid": pid,
                "startedAt": int(time.time()),
                "session_id": self.sid,
                "surface": "pane",
                "lstart": ls,
                "kitty_listen_on": os.environ.get("KITTY_LISTEN_ON") or None,
                "kitty_pid": int(os.environ["KITTY_PID"])
                if os.environ.get("KITTY_PID", "").isdigit()
                else None,
                "rig": True,
            },
        )


# ── the TUI ─────────────────────────────────────────────────────────────────────────────────────


class Tui:
    def __init__(self, sess, resumed):
        self.s = sess
        self.resumed = resumed
        self.buf = ""
        self.dialog = None  # None | "bgwork"
        self.sel = 0
        self.busy = False
        self.bg = []  # (Popen, label)
        self.banner = "" if resumed else ""
        self.notice = ""
        self.chip = None  # (offset of the pasted run in buf,) when shown as a chip
        # the positional prompt a relauncher passed after --resume SID: submitted once, by the stub
        # itself, right after its first frame (the real CLI's self-submit; B1 M10)
        self.pending_prompt = ""
        self.garble_until = 0.0
        self.is_draft = False  # the buffer holds a draft knob's text (H8 watches it)
        self.last_garble_draw = 0.0
        self.marked_draft = None

    def draft_mut(self, what):
        """H8: a key that would clear or send a draft, applied while the buffer holds one. Logged
        from the stub's own state (the world), never from the daemon's records."""
        if self.is_draft and self.buf:
            st = self.s.state()
            st.setdefault("draft_mut", []).append([time.time(), what])
            self.s.mark(draft_mut=st["draft_mut"])

    def shown(self):
        """CC collapses a big paste to a chip: over 800 chars or more than 2 newlines (HF:3159)."""
        if not self.chip:
            return self.buf
        head, body = self.buf[: self.chip[0]], self.buf[self.chip[0] :]
        k = body.count("\n")
        return head + "[Pasted text #1%s]" % (" +%d lines" % k if k else "")

    def cols(self):
        try:
            return max(40, os.get_terminal_size(sys.stdout.fileno()).columns)
        except OSError:
            return 120

    def draw(self):
        w = self.cols()
        rule = "─" * w
        out = [ESC + "[H" + ESC + "[2J"]
        if self.garble_until and time.time() < self.garble_until:
            # composer_unreadable_s: a frame with no input box (no rule rows), so the composer
            # reader returns unreadable, until garble_until; then the normal frame again
            with open(
                os.path.join(HARNESS_FIX, "composer-unreadable-%s.txt" % VERSION)
            ) as fh:
                out += fh.read().splitlines()
            sys.stdout.write("\r\n".join(out))
            sys.stdout.flush()
            return
        if self.is_draft and self.buf != self.marked_draft:
            self.marked_draft = self.buf
            self.s.mark(
                draft_now=self.buf
            )  # H8 reads what the composer holds at the end
        out.append(" ▐▛███▛█   Claude Code v%s" % VERSION)
        out.append("▝▜██████▀  Opus 5.5 · Claude Max")
        out.append(" ▝▝   ▝▝   %s" % self.s.cwd)
        out.append("")
        if self.notice:
            out.append(self.notice)
            out.append("")
        if self.dialog == "bgwork":
            out.append("❯ /exit")
            out.append("")
            out.append(rule)
            out.append("  Background work is running")
            out.append("  The following will stop when you exit:")
            out.append("")
            for _p, label in self.bg:
                out.append("  shell · %s" % label)
            out.append("")
            opts = ["Exit and stop tasks", "Stay"]
            if os.environ.get("CLAUDE_CODE_DISABLE_AGENT_VIEW") != "1":
                opts = ["Exit and stop tasks", "Move to background and exit", "Stay"]
            for i, o in enumerate(opts):
                out.append(
                    ("  ❯ %d. %s" if i == self.sel else "    %d. %s") % (i + 1, o)
                )
            out.append("")
            out.append("  Enter to confirm · Esc to cancel")
        else:
            if self.busy:
                out.append("✻ Working… (esc to interrupt)")
                out.append("")
            out.append(rule)
            if self.buf:
                out.append("❯ " + self.shown().replace("\n", " "))
            elif self.resumed:
                out.append("❯ ")
            else:
                out.append('❯ Try "refactor <filepath>"')  # C3: a whole-row placeholder
            out.append(rule)
            out.append("  ⏵⏵ auto mode on")
        sys.stdout.write("\r\n".join(out))
        sys.stdout.flush()

    # background work: a harness shell (argv carries shell-snapshots) as a DIRECT child
    def start_bg(self, seconds):
        snap = os.path.join(RIG, "tmp", "shell-snapshots")
        os.makedirs(snap, exist_ok=True)
        p = subprocess.Popen(
            [
                "/bin/zsh",
                "-c",
                # `& wait`, never a bare last command: zsh execs a trailing simple command, and the
                # process would lose the shell-snapshots argv the bg-work detectors key on
                "source %s/snapshot-zsh-rig.sh 2>/dev/null; sleep %d & wait"
                % (snap, seconds),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.bg.append((p, "sleep %d" % seconds))

    def live_bg(self):
        self.bg = [(p, l) for p, l in self.bg if p.poll() is None]
        return self.bg

    def exit_now(self, code=0):
        for p, _l in self.bg:
            try:
                p.kill()
            except OSError:
                pass
        sys.stdout.write(ESC + "[?2004l" + ESC + "[H" + ESC + "[2J")
        sys.stdout.flush()
        raise SystemExit(code)

    def submit(self, text):
        k, st = self.s.knobs, self.s.state()
        if text.strip() == "/exit":
            bgk = k.get("bg_job") or {}
            if bgk.get("at") == "exit" and not st.get("bg_exit_done"):
                self.s.mark(bg_exit_done=True)
                self.start_bg(int(bgk.get("seconds", 120)))
            if self.live_bg():
                self.dialog, self.sel = "bgwork", 0
                return
            if k.get("close_pane_on_exit") and not st.get("pane_closed"):
                self.s.mark(pane_closed=True)
                wid = os.environ.get("KITTY_WINDOW_ID", "")
                if wid:
                    subprocess.Popen(
                        [
                            os.environ.get("LR_KITTEN_BIN", "kitten"),
                            "@",
                            "close-window",
                            "--match",
                            "id:" + wid,
                        ],
                        start_new_session=True,
                    )
            self.exit_now(0)
        self.buf, self.chip = "", None
        self.busy = True
        self.draw()
        self.s.user(text)
        time.sleep(0.8)
        ft = k.get("first_turn") or ""
        target = self.resumed and os.path.realpath(self.s.cfg) != os.path.realpath(
            st.get("home_cfg", self.s.cfg)
        )
        walled = limited_until(self.s.cfg) > time.time()
        if ft and target and not st.get("first_turn_done"):
            self.s.mark(first_turn_done=True)
            self.s.error(ft)
            if ft.startswith("limit") and k.get("go_barrier"):
                mark_limited(
                    self.s.cfg, time.time() + float(k.get("reset_in_s") or 3 * 3600)
                )
        elif walled and k.get("go_barrier"):
            # a limited ACCOUNT refuses every session's turn, not one session's: without this the
            # other members on that account served turns after its limit, the daemon read the
            # limit as contradicted ("served a turn since") and never re-placed (W4 shakedown)
            self.s.error("limit")
        else:
            self.s.assistant("Continuing the task.")
        self.busy = False

    def key_loop(self):
        fd = sys.stdin.fileno()
        old = termios.tcgetattr(fd)
        tty.setraw(fd)
        sys.stdout.write(ESC + "[?2004h")
        pasting, pending = False, ""
        swallow = (
            bool(self.s.knobs.get("first_enter_swallow"))
            and self.resumed
            and not self.s.state().get("swallowed")
        )
        try:
            self.draw()
            if self.pending_prompt:
                prompt, self.pending_prompt = self.pending_prompt, ""
                self.submit(prompt)
                self.draw()
            while True:
                r, _w, _x = select.select([fd], [], [], 0.25)
                self.tick()
                if not r:
                    continue
                data = os.read(fd, 4096).decode("utf-8", "replace")
                if not data:
                    self.exit_now(0)
                pending += data
                while pending:
                    if pending.startswith(PASTE_ON):
                        pasting, pending = True, pending[len(PASTE_ON) :]
                        continue
                    if pending.startswith(PASTE_OFF):
                        pasting, pending = False, pending[len(PASTE_OFF) :]
                        continue
                    if pasting:
                        cut = pending.find(PASTE_OFF)
                        chunk = pending if cut < 0 else pending[:cut]
                        start = len(self.buf) if self.chip is None else self.chip[0]
                        self.buf += chunk.replace("\r\n", "\n").replace("\r", "\n")
                        body = self.buf[start:]
                        if len(body) > 800 or body.count("\n") > 2:
                            self.chip = (start,)
                        pending = "" if cut < 0 else pending[cut:]
                        continue
                    ch, pending = pending[0], pending[1:]
                    if ch == ESC:
                        if pending.startswith("[A") or pending.startswith("[B"):
                            if self.dialog:
                                self.sel = (
                                    max(0, self.sel - 1)
                                    if pending[1] == "A"
                                    else self.sel + 1
                                )
                            pending = pending[2:]
                        elif pending.startswith("["):
                            pending = pending[1:].lstrip("0123456789;~")
                        elif self.dialog:
                            self.dialog = None
                        continue
                    if self.dialog == "bgwork":
                        n = (
                            2
                            if os.environ.get("CLAUDE_CODE_DISABLE_AGENT_VIEW") == "1"
                            else 3
                        )
                        if ch.isdigit() and 1 <= int(ch) <= n:
                            self.sel = int(ch) - 1
                            ch = "\r"
                        if ch == "\r":
                            if self.sel == 0:
                                self.exit_now(0)
                            if self.sel == 1 and n == 3:
                                self.exit_now(0)
                            self.dialog = None
                        continue
                    if ch == "\r":
                        if swallow:
                            swallow = False
                            self.s.mark(swallowed=True)
                            continue
                        if self.buf.strip():
                            self.draft_mut("submit")
                            self.is_draft = False
                            self.submit(self.buf)
                    elif ch == "\n":
                        self.buf += "\n"
                    elif ch == "\x7f":
                        self.draft_mut("del")
                        if self.chip is not None:
                            self.buf, self.chip = self.buf[: self.chip[0]], None
                        else:
                            self.buf = self.buf[:-1]
                    elif ch == "\x15":
                        self.draft_mut("ctrl-u")
                        self.buf, self.chip = "", None
                    elif ch == "\x0c":
                        pass
                    elif ch == "\x03":
                        self.buf = ""
                    elif ch >= " ":
                        self.buf += ch
                self.draw()
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)

    def due_death(self):
        """go_barrier: the limit death, once $LR_RIG/go exists and die_at_s has passed. Only the
        ORIGINAL process dies, and only once: a resumed stub reads the same spec on the target
        account, so without both guards it would die again there and be moved twice (B1 C15)."""
        k = self.s.knobs
        if (
            not k.get("go_barrier")
            or (k.get("idle") and not k.get("idle_then_limit"))
            or k.get("busy_forever")
            or self.resumed
        ):
            return False
        try:
            go = os.stat(os.path.join(RIG, "go")).st_mtime
        except OSError:
            return False
        # busy_for_s is a LATE death (B1 C4): WORKING through the turn, limited at its end
        at = (
            k.get("busy_for_s")
            if k.get("busy_for_s") is not None
            else k.get("die_at_s")
        )
        if time.time() < go + float(at or 0):
            return False
        return not self.s.state().get("died_at")

    def die(self):
        """The limit death and every knob keyed to it, in transcript order."""
        k, now = self.s.knobs, time.time()
        self.s.mark(died_at=now)
        if k.get("busy_for_s") is not None:
            # the turn's assistant partial, then the limit: a turn that ran out mid-answer
            # stamped at go: the turn streamed this BEFORE the account hit its wall, then ran a long
            # tool call with no API request; a partial stamped at death reads as "the account served a
            # turn since its limit" and the daemon rightly calls the cohort NOT_NEEDED (W4 shakedown)
            try:
                go = os.stat(os.path.join(RIG, "go")).st_mtime
            except OSError:
                go = now
            self.s.back_s = max(0.0, time.time() - go)
            self.s.assistant("Partial output before the limit.")
            self.s.back_s = 0.0
            self.s.mark(busy_until=time.time())
        if k.get("idle_then_limit"):
            # a session at rest turns limited only by taking a turn: the prompt, then the limit
            self.s.user("One more thing on the rig task.")
        self.busy = False
        self.s.error("limit")
        if k.get("goal_meta_after_limit"):
            # 769b7294's shape: an isMeta /goal record written AFTER the limit but stamped 1 s
            # BEFORE it, so a reader that keys on "the last user record" sees a live turn
            with open(os.path.join(HARNESS_FIX, "goal-meta-after-limit.jsonl")) as fh:
                rec = json.loads(fh.readline())
            self.s.back_s = 1.0
            self.s.append(rec)
            self.s.back_s = 0.0
            self.s.mark(goal_meta_at=time.time())
        n = int(k.get("heavy_lead_subagents") or 0)
        if n:
            # plan.subagents_written counts files written in [death − 600, death]
            d = os.path.join(os.path.dirname(self.s.tx), self.s.sid, "subagents")
            os.makedirs(d, exist_ok=True)
            for i in range(n):
                p = os.path.join(d, "agent-%02d.jsonl" % i)
                with open(p, "w") as fh:
                    fh.write('{"type":"assistant","isSidechain":true}\n')
                os.utime(p, (now - 60, now - 60))
            self.s.mark(subagents_written=n)
        if k.get("composer_unreadable_s"):
            self.garble_until = now + float(k["composer_unreadable_s"])
            self.s.mark(garble_until=self.garble_until)
        hook = k.get("stop_failure_hook")
        if hook:
            # the G2 seam: the real StopFailure path, fed what Claude Code would feed it
            payload = {
                "session_id": self.s.sid,
                "transcript_path": self.s.tx,
                "cwd": self.s.cwd,
                "hook_event_name": "StopFailure",
                "error": "rate_limit",
            }
            try:
                subprocess.run(
                    [hook],
                    input=json.dumps(payload),
                    text=True,
                    timeout=60,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                self.s.mark(stop_failure_hook_at=time.time())
            except (OSError, subprocess.SubprocessError):
                self.s.mark(stop_failure_hook_at=-1)
        self.notice = LIMIT_NOTICE
        self.draw()

    def tick(self):
        """Faults that fire on their own clock: the go_barrier death, a draft typed after confirm,
        a stub re-created."""
        k, tx = self.s.knobs, self.s.tx
        if self.due_death():
            self.die()
        if self.garble_until:
            now = time.time()
            if now >= self.garble_until:
                self.garble_until = 0.0
                self.draw()  # the normal frame again
            elif now - self.last_garble_draw >= 2:
                self.last_garble_draw = now
                self.draw()
        confirmed = os.path.exists(tx + ".handed-off")
        dr = k.get("draft") or {}
        if (
            dr.get("at") == "confirm"
            and confirmed
            and not self.resumed
            and not self.s.state().get("draft_done")
        ):
            self.s.mark(draft_done=True)
            self.buf = dr.get("text", "draft")
            self.is_draft = True
            self.draw()
        if (
            k.get("recreate_stub_on_append")
            and confirmed
            and not self.resumed
            and not self.s.state().get("stub_done")
        ):
            self.s.mark(stub_done=True)
            rec = fixture("system-informational-retired-source")
            self.s.append(
                rec
            )  # appends to <sid>.jsonl, which no longer exists: re-creates it
        if self.dialog and not self.live_bg():
            pass


# ── entry points ────────────────────────────────────────────────────────────────────────────────


def write_dead(sid, cwd):
    cwd = os.path.realpath(cwd)
    s = Session(sid, os.path.join(os.environ["HOME"], ".claude-next"), cwd)
    # the registry row a crashed session leaves behind: rig-tagged, its pid long dead
    p = subprocess.Popen(["/usr/bin/true"])
    p.wait()
    reg = os.path.join(os.environ["HOME"], ".claude", "cc-registry")
    os.makedirs(reg, exist_ok=True)
    atomic(
        os.path.join(reg, "dead-%s.json" % sid[:8]),
        {
            "paneUUID": "",
            "name": "rig dead",
            "cwd": cwd,
            "account": "claude-next",
            "pid": p.pid,
            "startedAt": int(time.time()) - 3600,
            "session_id": sid,
            "surface": "pane",
            "rig": True,
        },
    )
    s.user("Work on the rig task.")
    s.assistant("Working on it.")
    s.error("limit")
    return 0


def fresh(sid):
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(
        os.environ["HOME"], ".claude"
    )
    s = Session(sid, cfg, os.getcwd())
    s.mark(home_cfg=cfg)
    s.register(os.getpid())
    k = s.knobs
    if k.get("idle"):
        s.back_s = 900.0
    s.user("Work on the rig task.")
    s.assistant("Working on it.")
    s.back_s = 0.0
    # go_barrier: alive and WORKING (a user turn in flight, the busy frame) until $LR_RIG/go +
    # die_at_s, never idle at rest, so the idle fan-out cannot move a member before it dies (C15).
    # Without it the member dies here, at boot, exactly as before.
    barrier = (bool(k.get("go_barrier")) or bool(k.get("busy_forever"))) and not k.get(
        "idle"
    )
    dies_now = not k.get("idle") and not barrier
    if dies_now:
        s.error("limit")
    t = Tui(s, resumed=False)
    if barrier:
        s.user("Keep going on the rig task.")
        t.busy = True
    bgk = k.get("bg_job") or {}
    if bgk.get("at") == "boot":
        t.start_bg(int(bgk.get("seconds", 3600)))
    dr = k.get("draft") or {}
    if dr.get("at") == "boot":
        t.buf = dr.get("text", "draft")
        t.is_draft = True
    if dies_now:
        t.notice = LIMIT_NOTICE
    boot = os.path.join(RIG, "tmp", "boot")
    os.makedirs(boot, exist_ok=True)
    open(os.path.join(boot, sid + ".ok"), "w").close()
    t.key_loop()
    return 0


def boot_delay(s):
    """Seconds this resume sleeps before READY (B1 F6). ``boot_delay_s`` is a number or a [lo, hi]
    range drawn per process; ``slow_boots`` K applies it to the first K resumes only, after which
    ``boot_delay_bin`` (a lognormal per resume) applies. Every draw is recorded in ``boots``."""
    k, st = s.knobs, s.state()
    n = int(st.get("resumes") or 0) + 1
    rng = random.Random("%s:%d" % (s.sid, n))
    fixed, slow = k.get("boot_delay_s"), k.get("slow_boots")
    d = 0.0
    if fixed is not None and (slow is None or n <= int(slow)):
        d = (
            rng.uniform(float(fixed[0]), float(fixed[1]))
            if isinstance(fixed, list)
            else float(fixed)
        )
    elif isinstance(k.get("boot_delay_bin"), dict):
        b = k["boot_delay_bin"]
        d = lognormal_draw(
            rng, b.get("median", 46), b.get("p90", 212), b.get("cap", 300)
        )
    boots = list(st.get("boots") or []) + [[round(time.time(), 1), round(d, 1)]]
    s.mark(resumes=n, boots=boots)
    return d


def resume(sid, prompt=""):
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(
        os.environ["HOME"], ".claude"
    )
    s = Session(sid, cfg, os.getcwd())
    if not os.path.exists(s.tx):
        found = [
            os.path.join(r, f)
            for r, _d, fs in os.walk(os.path.join(cfg, "projects"))
            for f in fs
            if f == sid + ".jsonl"
        ]
        if not found:
            print("No conversation found with session ID: %s" % sid)
            return 1
        s.tx = found[0]
    s.parent = s.last_uuid()
    delay = boot_delay(s)
    if delay:
        time.sleep(delay)
    burn_cpu(float(s.knobs.get("boot_cpu_s") or 0))
    s.register(os.getpid())
    if s.knobs.get("crash_after_boot") and not s.state().get("crashed"):
        s.mark(crashed=True)
        print("claude: crashed after boot (rig fault)")
        return 1
    t = Tui(s, resumed=True)
    t.pending_prompt = prompt
    t.key_loop()
    return 0


# flags of the real CLI that take a value: their value is never the positional prompt
VALUE_FLAGS = {
    "--model",
    "--effort",
    "--permission-mode",
    "--mcp-config",
    "--settings",
    "--append-system-prompt",
    "--session-id",
    "--resume",
    "-r",
}


def _resume_args(a):
    """(sid, prompt) from `--resume SID [flags…] [PROMPT]`. Both relaunchers spawn `… --resume $sid
    {*}$xargs {*}$prompt` (lr-fire-resume.sh, reso-resume-one); the stub used to drop the prompt, so
    an argv-relaunched member never engaged until fallback C typed it 600 s later (B1 M10, F21)."""
    i = a.index("--resume") if "--resume" in a else a.index("-r")
    sid, rest, prompt, j = a[i + 1], a[i + 2 :], "", 0
    while j < len(rest):
        if rest[j] in VALUE_FLAGS:
            j += 2
            continue
        if rest[j].startswith("-"):
            j += 1
            continue
        prompt = rest[j]
        j += 1
    return sid, prompt


def main(argv):
    signal.signal(signal.SIGHUP, lambda *_: os._exit(0))
    a = argv[1:]
    if "--version" in a or "-v" in a:
        # Real Claude Code prints and exits 0: no session, no transcript, no registry row. Without this
        # cc-close-attrib's version probe started a fresh stub session that overwrote the relaunched
        # pane's registry row and hid the sid from the rig daemon (W5 N=30, clean-idle stuck IN-FLIGHT).
        print("%s (Claude Code)" % VERSION)
        return 0
    band_record(
        "resume"
        if ("--resume" in a or "-r" in a)
        else ("dead" if "--rig-write-dead" in a else "fresh")
    )
    if "--rig-write-dead" in a:
        return write_dead(
            a[a.index("--rig-write-dead") + 1], a[a.index("--rig-cwd") + 1]
        )
    if "--resume" in a or "-r" in a:
        return resume(*_resume_args(a))
    if "--session-id" in a:
        return fresh(a[a.index("--session-id") + 1])
    return fresh(str(uuid.uuid4()))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except SystemExit:
        raise
