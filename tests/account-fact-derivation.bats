#!/usr/bin/env bats
# account-fact-derivation — every account/runtime fact has ONE derivation, and this suite is the
# assertion that its consumers agree.
#
# WHY THIS FILE EXISTS. The recurring defect in this subsystem is not a bug, it is a SHAPE: a
# fact with one true source gets re-spelled in each consumer, and nothing checks the copies
# agree. Four measured instances, none of which the drifting party could have detected:
#
#   1. The eval binary was written THREE times — bin/cc-claude-bin, handoff-fire.sh's own
#      _resolve_eval_bin, and accounts.json:claude_bin. On 2026-08-09 the third pinned
#      ~/.claude-219 while `claude()` launched ~/.claude-220, so probe_account()'s account
#      certification and cc-relogin's two login legs were all measuring a build no session ran.
#      The second carried the same stale literal as its fallback.
#   2. The auth-state vocabulary was written twice. handoff-fire.sh's copy drifted to 3 of 5
#      states (fixed, 8eb83ed1); cc-relogin's copy was still 5 where the CLI's is 6 — it never
#      learned `probe-error` — so an account whose probe raised read as "nothing actionable".
#   3. The live-session count is written twice (concurrency() / live_sessions()) and drifted for
#      five days over the `claude.exe` spelling, showing 10 where 15 ran. Undercounting is the
#      failure that matters: run() refuses on k != 0, so a blind count does not degrade the
#      rotation gate, it OPENS it.
#   4. The login-renewal threshold was written three times (72/168/72), leaving a 96-hour band
#      in which the board printed a command the executor refused. Collapsed by 26d5c893; its
#      agreement is pinned by tests/cc-relogin-status.bats, not here.
#
# So the contract this suite enforces is: a consumer READS the derivation, and where a fallback
# copy must survive for version tolerance, THIS FILE pins it equal to the original. A copy that
# nothing compares is the defect; a copy under assertion is merely a cache.
#
# Hermetic: no network, no keychain, no real ps. The one thing it deliberately reads live is
# bin/cc-claude-bin's resolution, because "the consumers agree" is a claim about this machine.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CA_BIN="$REPO/bin/claude-accounts"
  export CR_BIN="$REPO/bin/cc-relogin"
  export RESOLVER="$REPO/bin/cc-claude-bin"
  export SSOT="$REPO/accounts.json"
  export HF="$REPO/scripts/handoff-fire.sh"
}

# Load either extensionless tool as a module without running its CLI (both are __main__-guarded).
LOADCA='
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
'
LOADCR='
import importlib.machinery, importlib.util, os
cr = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "cr", importlib.machinery.SourceFileLoader("cr", os.environ["CR_BIN"])))
importlib.machinery.SourceFileLoader("cr", os.environ["CR_BIN"]).exec_module(cr)
'

# ---- fact 1: the eval binary ------------------------------------------------------------------

@test "eval-bin: claude-accounts derives the same path as bin/cc-claude-bin" {
  want="$("$RESOLVER")" || { echo "resolver itself failed"; false; }
  run python3 -c "$LOADCA"'
print(ca.resolve_claude_bin("/nonexistent/fallback-that-must-lose"))'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$want" ] || {
    echo "claude-accounts resolved '$output' but cc-claude-bin says '$want'"; false; }
}

@test "eval-bin: handoff-fire.sh derives the same path as bin/cc-claude-bin" {
  want="$("$RESOLVER")" || { echo "resolver itself failed"; false; }
  # Rebuild the function in a tree shaped like the repo (scripts/ beside bin/) so its
  # BASH_SOURCE-relative lookup is exercised, not bypassed.
  mkdir -p "$BATS_TEST_TMPDIR/t/scripts" "$BATS_TEST_TMPDIR/t/bin"
  ln -sf "$RESOLVER" "$BATS_TEST_TMPDIR/t/bin/cc-claude-bin"
  sed -n '/^_resolve_eval_bin()/,/^}/p' "$HF" > "$BATS_TEST_TMPDIR/t/scripts/f.sh"
  [ -s "$BATS_TEST_TMPDIR/t/scripts/f.sh" ] || {
    echo "could not extract _resolve_eval_bin from $HF"; false; }
  run bash -c 'source "$1"; _resolve_eval_bin' _ "$BATS_TEST_TMPDIR/t/scripts/f.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$want" ] || {
    echo "handoff-fire resolved '$output' but cc-claude-bin says '$want'"; false; }
}

@test "eval-bin: no derivation site carries a hardcoded ~/.claude-NNN version literal" {
  # The anti-recurrence assertion. Both sites HAD one; both were wrong. A literal here can only
  # ever be a copy of a number that lives in ~/.zshrc, so the rule is that none may exist —
  # including as a "fallback", which is exactly what rotted last time.
  fn="$(sed -n '/^_resolve_eval_bin()/,/^}/p' "$HF" | grep -v '^[[:space:]]*#')"
  echo "$fn" | grep -qE '\.claude-[0-9]+' && {
    echo "handoff-fire.sh:_resolve_eval_bin has re-grown a version literal:"; echo "$fn"; false; }
  fn2="$(sed -n '/^def resolve_claude_bin/,/^def load_cfg/p' "$CA_BIN" | grep -v '^[[:space:]]*#')"
  echo "$fn2" | grep -qE '\.claude-[0-9]+"' && {
    echo "claude-accounts:resolve_claude_bin has re-grown a version literal"; false; }
  true
}

@test "eval-bin: the accounts.json fallback still names something executable" {
  # It is a fallback, not the answer, so it is NOT pinned equal to the live resolver — demanding
  # that would re-create the coupling this work removed. But a fallback pointing at a DELETED
  # directory is a real failure on the degraded path, and that is what this catches.
  run python3 -c '
import json, os, sys
p = os.path.expanduser(json.load(open(os.environ["SSOT"]))["claude_bin"])
sys.exit(0 if os.access(p, os.X_OK) else f"accounts.json claude_bin is not executable: {p}")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ---- fact 2: the auth-state vocabulary ---------------------------------------------------------

@test "auth-states: cc-relogin's fallback tuples equal claude-accounts' own" {
  # THE test that would have caught `probe-error`. cc-relogin keeps a copy only for §2 version
  # tolerance; the moment it stops equalling the CLI's, that copy is a wrong answer waiting for
  # an old binary to ask for it.
  run python3 -c "$LOADCA$LOADCR"'
a_act, r_act = set(ca.ACTIONABLE_AUTH), set(cr.AUTH_ACTIONABLE)
a_fix, r_fix = set(ca.LOGIN_FIXABLE), set(cr.LOGIN_FIXABLE)
assert a_act == r_act, f"ACTIONABLE drift: claude-accounts={sorted(a_act)} cc-relogin={sorted(r_act)} missing={sorted(a_act - r_act)} extra={sorted(r_act - a_fix)}"
assert a_fix == r_fix, f"LOGIN_FIXABLE drift: claude-accounts={sorted(a_fix)} cc-relogin={sorted(r_fix)}"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "auth-states: every state a producer assigns has a glyph and a classification" {
  # The producers are the ground truth (row["auth"] = "..."). AUTH_GLYPH/ACTIONABLE_AUTH are
  # hand-maintained relations over them, so a NEW state added at a producer silently falls out
  # of every consumer set — it renders blank and classifies as healthy.
  run python3 -c "$LOADCA"'
import os, re
src = open(os.environ["CA_BIN"]).read()
produced = set(re.findall(r"""row\[.auth.\]\s*=\s*.([a-z-]+).""", src))
produced |= set(re.findall(r""""auth":\s*"([a-z-]+)",""", src))
produced -= {"ok", "healed", "stale"}          # healthy states, deliberately not actionable
missing_glyph = sorted(s for s in produced if s not in ca.AUTH_GLYPH)
assert not missing_glyph, f"producer states with no AUTH_GLYPH entry: {missing_glyph}"
unclassified = sorted(s for s in produced if s not in ca.ACTIONABLE_AUTH)
assert not unclassified, f"producer states in neither healthy nor ACTIONABLE_AUTH: {unclassified}"
assert set(ca.LOGIN_FIXABLE) <= set(ca.ACTIONABLE_AUTH)
print("OK", sorted(produced))'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "auth-states: cc-relogin obeys the CLI's exported verdict over its own list" {
  # Proves the consumer READS rather than re-derives: a row the CLI calls actionable is acted on
  # even when the state string is one cc-relogin's own tuple does not contain, and vice versa.
  run python3 -c "$LOADCR"'
need, why = cr.need_relogin({"auth": "some-future-state", "auth_actionable": True}, {})
assert need is True, f"CLI verdict True ignored: {why}"
assert "DEGRADED" not in why, why
need, why = cr.need_relogin(
    {"auth": "logged-out", "auth_actionable": False, "login_expired": False,
     "login_expires_h": 999.0}, {})
assert need is False, f"CLI verdict False overridden by the local tuple: {why}"
# and with the field absent (old claude-accounts) it degrades to the copy AND says so
need, why = cr.need_relogin({"auth": "probe-error"}, {})
assert need is True and "DEGRADED" in why, why
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- fact 3: the live-session count ------------------------------------------------------------
#
# The parity test the subsystem never had. tests/cc-relogin.bats pins live_sessions per-file and
# says in its own comment that it does so "rather than trusting live_sessions()'s 'mirrors
# concurrency() exactly' docstring" — i.e. it deliberately does NOT compare the two. Nothing did.

PARITY='
import subprocess, json, os

def fake(mod, ps_out):
    mod.subprocess = type("S", (), {
        "run": staticmethod(lambda *a, **k: type("P", (), {"stdout": ps_out})()),
        "TimeoutExpired": subprocess.TimeoutExpired,
        "SubprocessError": subprocess.SubprocessError})
    mod.HOME = "/Users/c"

ACCTS = [{"name": "next",  "config_dir": "/Users/c/.claude-next"},
         {"name": "next2", "config_dir": "/Users/c/.claude-secondary"},
         {"name": "next3", "config_dir": "/Users/c/.claude-tertiary"},
         {"name": "next4", "config_dir": "/Users/c/.claude-quaternary"}]

def both(ps_out, accts=ACCTS):
    fake(ca, ps_out); fake(cr, ps_out)
    left = ca.concurrency({"accounts": accts})
    right = {a["name"]: cr.live_sessions(a["config_dir"]) for a in accts}
    assert left == right, f"PARITY BROKEN\\n  concurrency():   {left}\\n  live_sessions(): {right}\\n  ps fixture:\\n{ps_out}"
    return left
'

@test "live-count: both counters agree on the real launcher spellings" {
  run python3 -c "$LOADCA$LOADCR$PARITY"'
ps = (
  # interactive launch: the .bin/claude SYMLINK
  "/Users/c/.claude-220/node_modules/.bin/claude --model x CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  # dispatched worker / teammate / research subagent: the RESOLVED native binary
  "/Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@s "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  "/Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id v@s "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-secondary\n"
  # cli.js spelling — argv[0] IS the js entrypoint (both counters key on argv[0], so a
  # `node <...>/cli.js` line whose argv[0] is the interpreter counts for NEITHER; pinned below)
  "/Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/cli.js "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-quaternary\n"
  # ...and the interpreter-first spelling, which both must skip
  "node /Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/cli.js "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-next\n"
  # an MCP child that merely INHERITS the env — must not count for either
  "node /some/mcp/server.js CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  # a headless one-shot — skipped by both
  "/Users/c/.claude-220/node_modules/.bin/claude -p hello CLAUDE_CONFIG_DIR=/Users/c/.claude-next\n")
got = both(ps)
assert got == {"next": 0, "next2": 1, "next3": 2, "next4": 1}, got
print("OK", got)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "live-count: both counters agree that bare ~/.claude mirrors the .claude-next account" {
  run python3 -c "$LOADCA$LOADCR$PARITY"'
ps = ("/Users/c/.claude-220/node_modules/.bin/claude --resume CLAUDE_CONFIG_DIR=/Users/c/.claude\n"
      "/Users/c/.claude-220/node_modules/.bin/claude --resume\n")
got = both(ps)
assert got["next"] == 2, got
print("OK", got)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "live-count: both counters agree when a config_dir carries a trailing slash" {
  # concurrency() rstripped the OBSERVED dir but not its own KEYS, so this account scored 0
  # forever — silently, in the undercount direction, which is the direction that opens the gate.
  run python3 -c "$LOADCA$LOADCR$PARITY"'
accts = [{"name": "next", "config_dir": "/Users/c/.claude-next"},
         {"name": "next3", "config_dir": "/Users/c/.claude-tertiary/"}]
ps = ("/Users/c/.claude-220/node_modules/.bin/claude --model x "
      "CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n")
got = both(ps, accts)
assert got["next3"] == 1, got
print("OK", got)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "live-count: both counters agree that the LAST CLAUDE_CONFIG_DIR on the line wins" {
  # ps -E appends the environment AFTER argv, so an earlier match can be prompt text merely
  # mentioning the variable. Both must take the last.
  run python3 -c "$LOADCA$LOADCR$PARITY"'
ps = ("/Users/c/.claude-220/node_modules/.bin/claude -r fix CLAUDE_CONFIG_DIR=/Users/c/.claude-next "
      "CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n")
got = both(ps)
assert got == {"next": 0, "next2": 0, "next3": 1, "next4": 0}, got
print("OK", got)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "live-count: the ONE divergence is deliberate and stays pinned — ps failure" {
  # concurrency() feeds an ALARM (all-zero, keep rendering); live_sessions() feeds a GATE (-1 =
  # UNKNOWN, refuse). Opposite verdicts from one input, and both are correct for their consumer.
  # Pinned so it stays a decision rather than becoming a fourth silent drift.
  run python3 -c "$LOADCA$LOADCR"'
import subprocess
def blow(mod):
    mod.subprocess = type("S", (), {
        "run": staticmethod(lambda *a, **k: (_ for _ in ()).throw(OSError("no ps"))),
        "TimeoutExpired": subprocess.TimeoutExpired,
        "SubprocessError": subprocess.SubprocessError})
    mod.HOME = "/Users/c"
blow(ca); blow(cr)
assert ca.concurrency({"accounts": [{"name": "next3", "config_dir": "/Users/c/.claude-tertiary"}]}) == {"next3": 0}
assert cr.live_sessions("/Users/c/.claude-tertiary") == -1
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- the meta-assertion ------------------------------------------------------------------------

@test "no consumer re-implements the eval-bin resolution" {
  # The DoD's actual words: a test that FAILS if any consumer re-derives independently. A NEW
  # parser that reads ~/.zshrc to extract a claude binary path is a fourth spelling in the making
  # — that is exactly what handoff-fire.sh's _resolve_eval_bin was, and it disagreed with
  # bin/cc-claude-bin on tie-break (last match vs first) while carrying a stale literal besides.
  #
  # The detector: an EXECUTABLE line (comments stripped) that names .zshrc and, on that same
  # line, extracts a claude binary path. Comments are excluded deliberately — the whole point of
  # the surviving comments is to explain why the parse is gone.
  scan() {   # $1=dir → files whose live code parses ~/.zshrc for a claude path
    grep -rl 'zshrc' "$1" 2>/dev/null | while read -r f; do
      # Require an EXTRACTION FLAG on the line, not merely the nouns "zshrc" and "claude".
      # Prose explaining where the fact comes from is the opposite of a rival parser, and
      # convicting the explanation would push authors toward deleting the comment instead —
      # `-o`/`--only-matching`/`sed -n` is something only a real extractor writes.
      # LIMIT, stated: a parser built from `while read` rather than grep -o slips this. The
      # behavioural tests above (1 and 2) catch any such rival by its DISAGREEMENT, which is
      # the gate that actually matters; this one catches the rival before it can disagree.
      sed 's/[[:space:]]*#.*$//' "$f" 2>/dev/null \
        | grep -qE 'zshrc' \
        && sed 's/[[:space:]]*#.*$//' "$f" 2>/dev/null \
           | grep -E 'zshrc' \
           | grep -qE -- '-o[EPi]*[[:space:]]|--only-matching|sed[[:space:]]+-n' \
        && echo "$f"
    done
  }
  bad=0
  for f in $(scan "$REPO/bin"; scan "$REPO/scripts"; scan "$REPO/lib"); do
    case "$f" in
      "$REPO/bin/cc-claude-bin") continue ;;                 # THE resolver — the one allowed site
      # The upgrade gate's own independent read: it exists precisely to AUDIT the launcher, so it
      # must not consume the resolver it is checking (a gate must not key on its own signal).
      *check05_launcher.sh) continue ;;
    esac
    echo "new independent ~/.zshrc eval-bin parser: $f"
    bad=1
  done
  [ "$bad" -eq 0 ] || false

  # Positive control: the detector must be able to FAIL. A detector that cannot fire is not a
  # gate, it is a green light — and this suite's whole subject is checks that quietly stopped
  # checking. Plant the exact pattern handoff-fire.sh used to carry and require a hit.
  mkdir -p "$BATS_TEST_TMPDIR/ctl"
  printf '%s\n' '#!/bin/bash' \
    'suffix="$(grep -oE "/\.claude-[0-9]+/node_modules/\.bin/claude" "$HOME/.zshrc" | tail -1)"' \
    > "$BATS_TEST_TMPDIR/ctl/rival.sh"
  [ -n "$(scan "$BATS_TEST_TMPDIR/ctl")" ] || {
    echo "POSITIVE CONTROL FAILED: the detector does not fire on a planted rival parser"; false; }
}
