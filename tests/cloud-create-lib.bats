#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats: every @test body IS its own subshell, so an `export` inside one
#   is meant to be test-local (SC2030/SC2031), and setup()'s helpers are invoked from those test
#   subshells rather than from file scope (SC2329).
#
# scripts/lib/cloud-create.sh — THE cloud-create implementation, factored out of
# cloud-bundle-probe.sh:fire_one so that handoff-fire.sh --cloud could use it rather than become a
# fourth copy (CLOUD_OBSERVABILITY.md §10.4).
#
# WHAT THIS SUITE IS ACTUALLY DEFENDING. Not "does a create work" — that needs an account and real
# quota. It defends the three places where this library gives an ANSWER about a create, because
# each of them has already been observed to answer wrongly on this box:
#
#   1. THE NORMALISER decides whether a refusal is READABLE. Measured 2026-08-09 across the two
#      probe ledgers, `refused-other` — the bucket that means "we could not tell" — contained TEN
#      rows and not one of them was unknown: 7 real bundle refusals and 3 rig faults. The rows fuse
#      because a TUI positions text with cursor motion instead of spaces, and every classifier
#      pattern contains a space. Cases 1-4.
#   2. THE CLASSIFIER decides what KIND of refusal it was, which is what the retry rule reads.
#      fire_one accepted a bare `session_…` as a create — harmless in a probe that only tallies,
#      but on the fire path it declares a session that does not exist. Case 7.
#   3. THE ID EXTRACTION decides whether the created session can be DECLARED, and an undeclared
#      cloud session is unobservable by construction AND invisible to the 600 s orphan reaper.
#      Cases 8-11.
#
# EVERY NORMALISER CASE CARRIES ITS RED CONTROL. A normaliser test that only asserts the good
# output passes just as well on a function that deletes nothing at all, so each case that matters
# also replays the SAME bytes through the narrower predecessor and asserts the predecessor gets it
# WRONG (cases 2, 4, 7). Without that half these are shape checks, not evidence.
#
# THE FIXTURE BYTES ARE THE REAL ONES. `Error:\x1b[8GBundle\x1b[15Gupload\x1b[22Gfailed:` is the
# form recorded verbatim in scripts/lib/pty-run.py's own header from a live 2.1.220 refusal, and
# the create banner is the shape in ~/.claude/autonomy/cloud/bundle-probe.jsonl. A hand-invented
# approximation would pass vacuously (memory: control-must-replay-the-real-artifact).

# Required for `run --separate-stderr` (cases 15-18): flags on `run` are a 1.5.0 feature and bats
# only WARNS without this declaration — a warning that reads like noise while the flag it is about
# silently does nothing.
bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/cloud-create.sh"
  # Sourced HERE, not per-test: the runner runs setup() and the test body in the SAME shell, so the
  # library's functions are directly callable (and directly `run`-able) below. A `bash -c` wrapper
  # would fork a shell that never sourced it — every call would be a 127, which reads exactly like
  # a broken subject rather than a broken harness.
  # shellcheck source=scripts/lib/cloud-create.sh
  . "$LIB"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  E=$'\x1b'
  # The real fused refusal, in the byte form pty-run.py:47 records from a live 2.1.220 create.
  REAL_BUNDLE="${E}[<u${E}[>1u${E}[>4;2mError:${E}[8GBundle${E}[15Gupload${E}[22Gfailed:${E}[30GSocket${E}[37Gis closed after 3 attempts. Please setup GitHub on https://claude.ai/code${E}[0m"
  # The real create banner, in the shape recorded in bundle-probe.jsonl.
  REAL_CREATE="${E}[<u${E}[>1u${E}[>4;2mCreated cloud session: Print repository name${E}[8GView: https://claude.ai/code/session_01YNvuTse5TvLQLC9b6kkV35?from=cli&m=0 Resume with: claude --teleport session_01YNvuTse5TvLQLC9b6kkV35${E}[?1006l"
}

# The PREDECESSOR normaliser + classifier, lifted verbatim out of cloud-bundle-probe.sh as it stood
# before the factoring. This is the RED control: a case that passes under BOTH is not evidence that
# the change did anything.
old_normalise() {
  python3 -c '
import sys,re
d=sys.stdin.buffer.read().decode("utf-8","replace")
d=re.sub(r"\x1b\[[0-9;]*[CG]"," ",d)
d=re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]","",d)
d=re.sub(r"\x1b[]P][^\x07\x1b]*(\x07|\x1b\\\\)?","",d)
d=re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]","",d)
print(re.sub(r"[ \t]+"," ",d))'
}
old_classify() {
  local t; t="$(cat)"
  case "$t" in *"Created cloud session"*|*"session_"*) echo created; return ;; esac
  if printf '%s' "$t" | grep -qiE 'interactive terminal|tcgetattr|Operation not supported on socket|pty-run:|unknown option|no claude binary'; then echo refused-harness; return; fi
  if printf '%s' "$t" | grep -qiE 'Bundle upload failed|Repo is too large'; then echo refused-bundle; return; fi
  if printf '%s' "$t" | grep -qiE 'limit|quota|rate.?limit|exceeded'; then echo refused-quota; return; fi
  echo refused-other
}

# Pipeline helpers, so each case `run`s a function rather than forking a shell that never sourced
# the library. cls/sid_n normalise first (the production path); sid feeds raw text, which is what
# case 9 needs to prove the ANCHORING rather than the normalising.
nrm()     { printf '%s' "$1" | cc_cloud_normalise; }
cls()     { printf '%s' "$1" | cc_cloud_normalise | cc_cloud_classify; }
sid_n()   { printf '%s' "$1" | cc_cloud_normalise | cc_cloud_session_id; }
sid()     { printf '%s' "$1" | cc_cloud_session_id; }
old_cls() { printf '%s' "$1" | old_normalise | old_classify; }

# A stub `claude`. It writes $STUB_OUT and exits $STUB_RC, and it RECORDS each invocation so the
# retry cases can count attempts. `attempt N` output is served from $STUB_SEQ_N when present, which
# is what lets case 15 reproduce §S5.3's measured shape (fail, then succeed).
mkstub() {
  cat > "$BIN/claude" <<'EOF'
#!/bin/bash
n=$(( $(cat "$STUB_COUNT" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_COUNT"
# The pty is not decoration: the real binary refuses without one. Recording the answer here makes
# "we allocated a real terminal" an assertion rather than an assumption.
[ -t 1 ] && echo "tty=yes" >> "$STUB_TTY"
seq_var="STUB_SEQ_$n"
if [ -n "${!seq_var:-}" ]; then printf '%s' "${!seq_var}"; else printf '%s' "${STUB_OUT:-}"; fi
exit "${STUB_RC:-1}"
EOF
  chmod +x "$BIN/claude"
  export STUB_COUNT="$BATS_TEST_TMPDIR/count" STUB_TTY="$BATS_TEST_TMPDIR/tty"
  export CC_CLOUD_CREATE_BIN="$BIN/claude"
  export CC_CLOUD_CREATE_BACKOFF_S=0        # the retry's timing is not the subject; its POLICY is
}

# ── 1-4 · THE NORMALISER, each with the control that makes it evidence ─────────────────────────

@test "1 CSI n G becomes a space — the real fused refusal reads as words again" {
  run nrm "$REAL_BUNDLE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle upload failed"* ]] || false
  [[ "$output" == *"Socket is closed after 3 attempts"* ]] || false
}

@test "2 RED CONTROL — pty-run.py's strip_ansi FUSED those same bytes (the measured producer)" {
  # This is the defect's actual source, established by replay rather than by the obvious guess:
  # strip_ansi converts cursor-FORWARD to spaces and lets cursor-ABSOLUTE fall through to its
  # generic CSI delete. Reproducing it here pins WHICH component was wrong, so a future reader does
  # not re-fix the probes' normalise (which already handled G) and leave the shared allocator
  # broken. The `G`-handling line added to pty-run.py alongside this library is what closes it.
  run python3 -c '
import re,sys
d = sys.argv[1]
d = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", d)
d = re.sub(r"\x1b\[(\d*)C", lambda m: " " * max(1, int(m.group(1) or 1)), d)
d = re.sub(r"\x1b\[[0-9;?<>=]*[A-Za-z]", "", d)
sys.stdout.write(d)' "$REAL_BUNDLE"
  [ "$status" -eq 0 ]
  # The words are FUSED — the exact shape all over ceiling-probe.jsonl.
  [[ "$output" == *"Bundleuploadfailed"* ]] || false
  # …and therefore the classifier's spaced pattern cannot match it.
  [[ "$output" != *"Bundle upload failed"* ]] || false
}

@test "3 pty-run.py's strip_ansi now converts CSI n G too — fixed at the source" {
  # The library does not depend on this (it normalises raw bytes itself), but every OTHER consumer
  # of the shared allocator does, so the fix is asserted where it lives.
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_loader("ptyrun", loader=None)
src = open(sys.argv[1]).read()
ns = {}
exec(src.split("cmd = sys.argv[1:]")[0], ns)
sys.stdout.write(ns["strip_ansi"](sys.argv[2]))' "$REPO/scripts/lib/pty-run.py" "$REAL_BUNDLE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bundle upload failed"* ]] || false
}

@test "4 a private-mode CSI INSIDE the phrase — wide parameter class, with its RED control" {
  # Garbage at the head of a line is cosmetic. Garbage between two words the classifier greps is
  # not, and the narrow [0-9;?]* class leaves exactly that: it fails to match ESC[>4m, the later
  # control sweep eats the bare ESC, and `[>4m[<u` survives as literal text mid-phrase.
  local inphrase="Error: Bundle${E}[>4m${E}[<u upload failed: Socket is closed"
  run cls "$inphrase"
  [ "$output" = refused-bundle ]
  run old_cls "$inphrase"
  [ "$output" = refused-other ]        # ← the control: the predecessor calls a real refusal unknown
}

# ── 5-7 · THE CLASSIFIER ───────────────────────────────────────────────────────────────────────

@test "5 every refusal class resolves to its own token" {
  cls() { printf '%s' "$1" | cc_cloud_normalise | cc_cloud_classify; }
  [ "$(cls "$REAL_CREATE")" = created ]
  [ "$(cls "$REAL_BUNDLE")" = refused-bundle ]
  [ "$(cls "Error: Repo is too large to upload")" = refused-bundle ]
  [ "$(cls "You have reached your weekly limit for this model")" = refused-quota ]
  [ "$(cls "Error: --cloud requires an interactive terminal.")" = refused-harness ]
  [ "$(cls "script: tcgetattr/ioctl: Operation not supported on socket")" = refused-harness ]
  [ "$(cls "Error: something nobody has seen before")" = refused-other ]
}

@test "6 a RIG fault outranks a fleet verdict — harness is classified FIRST" {
  # The ordering is the assertion. "Operation not supported on socket" also contains no quota word,
  # but a rig fault that happened to mention one must never be published as a property of the fleet.
  run cls \
    "pty-run: cannot exec claude — and the weekly limit is irrelevant here"
  [ "$output" = refused-harness ]
}

@test "7 a bare session_ id is NOT a create — with the RED control that it used to be" {
  # A refusal that merely QUOTES an id (a resume hint, a not-found) classified as `created` under
  # fire_one. In a probe that only tallies that is a miscount; on the fire path it declares a
  # session that does not exist, against a branch nothing will ever push.
  local quoted="Error: session_01AAAAAAAAAAAAAAAAAAAAAA could not be resumed"
  run cls "$quoted"
  [ "$output" != created ]
  run old_cls "$quoted"
  [ "$output" = created ]              # ← the control: the predecessor invents a create
}

# ── 8-11 · THE ID, and the state that must not fold ────────────────────────────────────────────

@test "8 the id is read out of the real create banner" {
  run sid_n "$REAL_CREATE"
  [ "$status" -eq 0 ]
  [ "$output" = session_01YNvuTse5TvLQLC9b6kkV35 ]
}

@test "9 extraction is ANCHORED — a title quoting an id does not beat the URL" {
  # The banner's title is free text the CALLER chose, so an unanchored first-match would return an
  # id out of the fire's own prompt. The URL and the teleport line are where the CLI prints the id
  # as a machine handle.
  run sid \
    "Created cloud session: resume session_01DECOYDECOYDECOYDECOYDE please
View: https://claude.ai/code/session_01REALREALREALREALREALR?from=cli&m=0"
  [ "$output" = session_01REALREALREALREALREALR ]
}

@test "10 no id in the output is a REFUSAL to answer, not an empty answer" {
  run sid "no session here at all"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "11 created-unidentified — a create we cannot name is its OWN outcome, never plain created" {
  # The state this exists for: a live session, spending quota, that cannot be declared — so it is
  # unobservable by construction AND invisible to the 600s orphan reaper. Folding it into `created`
  # hands the caller an empty id to declare; folding it into a refusal reports "no session" while
  # one is running.
  mkstub
  export STUB_OUT="Created cloud session: a banner with no id anywhere" STUB_RC=0
  run cc_cloud_create_once "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == created-unidentified* ]] || false
  [[ "$output" != created$'\t'* ]] || false
}

# ── 12-13 · THE HARNESS ARM — a fault in OUR rig is never a fleet verdict ──────────────────────

@test "12 an absent binary refuses as HARNESS and spends no attempt" {
  export CC_CLOUD_CREATE_BIN="$BATS_TEST_TMPDIR/nope"
  run cc_cloud_create_once "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-harness* ]] || false
  [[ "$output" == *"no claude binary"* ]] || false
}

@test "13 an absent pty allocator refuses as HARNESS — the pty is not optional" {
  mkstub
  export CC_CLOUD_PTY_RUN="$BATS_TEST_TMPDIR/no-pty-run.py"
  run cc_cloud_create_once "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-harness* ]] || false
  [[ "$output" == *"no pty allocator"* ]] || false
  [ ! -s "$STUB_COUNT" ]               # …and the binary was never reached
}

@test "14 the child really gets a TTY — the whole reason pty-run.py is in the path" {
  mkstub
  export STUB_OUT="$REAL_CREATE" STUB_RC=0
  run cc_cloud_create_once "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == created* ]] || false
  grep -q 'tty=yes' "$STUB_TTY"
}

# ── 15-18 · THE RETRY POLICY — bounded, and ONLY over the measured-transient class ─────────────

@test "15 §S5.3's measured shape: refused-bundle then created — the retry reaches a session" {
  # `--separate-stderr` on every retry case: the "attempt N/M — retrying" line is PROGRESS and goes
  # to stderr on purpose, so a caller redirecting stdout gets the verdict alone. the runner merges the two
  # by default, which would leave these cases asserting against the notice instead of the result.
  mkstub
  export STUB_RC=0 STUB_SEQ_1="$REAL_BUNDLE" STUB_SEQ_2="$REAL_CREATE"
  run --separate-stderr cc_cloud_create "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == created$'\t'session_01YNvuTse5TvLQLC9b6kkV35* ]] || false
  [ "$(cat "$STUB_COUNT")" = 2 ]
}

@test "16 the retry is BOUNDED — a permanently failing bundle stops at CC_CLOUD_CREATE_ATTEMPTS" {
  mkstub
  export STUB_OUT="$REAL_BUNDLE" STUB_RC=1 CC_CLOUD_CREATE_ATTEMPTS=3
  run --separate-stderr cc_cloud_create "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-bundle* ]] || false
  [ "$(cat "$STUB_COUNT")" = 3 ]
}

@test "17 CONTROL — quota is NOT retried: one attempt, and the token survives" {
  # The pair with case 16 is what makes the retry a POLICY rather than a blanket. Retrying inside
  # one fire cannot clear a shared account limit; it just spends the next attempt on the same wall.
  mkstub
  export STUB_OUT="You have reached your weekly limit" STUB_RC=1 CC_CLOUD_CREATE_ATTEMPTS=3
  run --separate-stderr cc_cloud_create "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-quota* ]] || false
  [ "$(cat "$STUB_COUNT")" = 1 ]
}

@test "18 CONTROL — harness and other are NOT retried either" {
  mkstub
  export CC_CLOUD_CREATE_ATTEMPTS=3
  export STUB_OUT="Error: --cloud requires an interactive terminal." STUB_RC=1
  run --separate-stderr cc_cloud_create "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-harness* ]] || false
  [ "$(cat "$STUB_COUNT")" = 1 ]
  : > "$STUB_COUNT"
  export STUB_OUT="Error: a shape nobody has classified"
  run --separate-stderr cc_cloud_create "$HOME" "$BATS_TEST_TMPDIR" hi
  [[ "$output" == refused-other* ]] || false
  [ "$(cat "$STUB_COUNT")" = 1 ]
}

# ── 19 · THE BRANCH NAME ───────────────────────────────────────────────────────────────────────

@test "19 the declared branch is claude/-prefixed and UNIQUE per fire" {
  # Unique is the load-bearing half. §10.2c: a session declared against a SHARED branch reads ALIVE
  # forever, because O2 — "the declared ref advanced" — is the only off-box heartbeat and trunk
  # advances from everything else on this box. A per-fire name can only be advanced by its own
  # session. `claude/` is what scripts/cloud-reconcile.sh discovers.
  local a b
  a="$(cc_cloud_branch_name)"; b="$(bash -c ". '$LIB'; cc_cloud_branch_name")"
  [[ "$a" == claude/fire-* ]] || false
  [ "$a" != "$b" ]
  run git check-ref-format --branch "$a"
  [ "$status" -eq 0 ]
}

# ── 20-22 · THE RETURN CONTRACT (backlog 0c8b39b67665) ─────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 resolves the absence ambiguity by CONTRACT — "the session's brief
# requires its FIRST act to be pushing that branch" — and until this function that contract existed
# in prose only. What these cases defend is the ORDER and the BRANCH, because both halves have
# already been observed wrong on this repo's cloud lane: a payload that instructed a push to a name
# nothing held (case 17 of tests/handoff-fire-cloud.bats), and an API lane that instructed no push
# at all. A trailer whose beacon comes after the work is worth nothing: the whole value is that the
# ref exists inside `boot_s` (900 s), before any result does.

@test "20 the return contract instructs the BOOT BEACON, and instructs it FIRST" {
  local out beacon empty push work
  out="$(cc_cloud_return_contract claude/fire-testbranch)"
  # The beacon is an EMPTY commit — the cheapest thing that moves a ref, and the one thing that
  # cannot manufacture a path set and read as a false result downstream (cc-cloud fill-paths).
  beacon="$(printf '%s' "$out" | grep -n 'BOOT BEACON' | head -1 | cut -d: -f1)"
  empty="$(printf '%s' "$out" | grep -n -- '--allow-empty' | head -1 | cut -d: -f1)"
  push="$(printf '%s' "$out" | grep -n 'git push -u origin HEAD' | head -1 | cut -d: -f1)"
  work="$(printf '%s' "$out" | grep -n 'before you finish' | head -1 | cut -d: -f1)"
  [ -n "$beacon" ] || { echo "the contract never names a boot beacon"; false; }
  [ -n "$empty" ]  || { echo "the beacon is not an empty commit — it can manufacture a false result"; false; }
  [ -n "$push" ]   || { echo "the contract never instructs a push"; false; }
  [ -n "$work" ]   || { echo "the contract never instructs the RETURN push"; false; }
  [ "$beacon" -lt "$work" ] || { echo "the beacon must PRECEDE the return push (beacon=$beacon return=$work)"; false; }
  # FIRST means first: before reading, planning or editing. A beacon a worker gets to after its
  # investigation is a beacon that fires outside the boot budget, i.e. no beacon at all.
  printf '%s' "$out" | grep -qi 'YOUR FIRST ACT, BEFORE YOU READ' || false
}

@test "21 the contract names THE DECLARED BRANCH, and creates it idempotently" {
  local out
  out="$(cc_cloud_return_contract claude/fire-20260101T000000Z-1-1)"
  printf '%s' "$out" | grep -q 'claude/fire-20260101T000000Z-1-1' || false
  # `checkout -B`, never `switch -c`: on the API lane the VM is ALREADY standing on the authorised
  # branch, where `switch -c` fails outright ("already exists") and takes the beacon down with it.
  printf '%s' "$out" | grep -q "git checkout -B claude/fire-20260101T000000Z-1-1" || false
  ! printf '%s' "$out" | grep -q 'switch -c' || false
  # A push at an invented ref name is the pre-B1 defect; it must not come back through this text.
  ! printf '%s' "$out" | grep -q 'HEAD:claude/' || false
}

@test "22 a worker with nothing to commit is told what to push INSTEAD of nothing" {
  # §14/§15: silence from a VM is indistinguishable here from a session that never booted, so the
  # contract must name the two artifacts that make a no-work session returnable. Without this the
  # beacon invites the opposite reading — "I pushed the beacon, that is my push".
  local out
  out="$(cc_cloud_return_contract claude/fire-x)"
  printf '%s' "$out" | grep -q 'docs/research' || false
  printf '%s' "$out" | grep -q 'cloud-park.sh' || false
}

@test "23 the contract REFUSES to render without a branch — never a nameless push target" {
  run cc_cloud_return_contract
  [ "$status" -ne 0 ]
  [[ "$output" == *"branch is required"* ]] || false
}
