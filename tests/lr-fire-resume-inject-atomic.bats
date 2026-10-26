#!/usr/bin/env bats
# lr-fire-resume.sh — the prompt reaches the TUI as ONE bracketed paste, and the Enter after it.
#
# THE INCIDENT (lr-wake 2026-10-18, pane 430, e §2 and §5 A). The expect program typed the prompt as
# raw keystrokes (`send -- $prompt_b`), and Claude Code splits an unframed burst by read timing: a
# 2,050-byte brief became two paste chips plus a 7-character literal tail, the reader could not
# prove the box was ours, and the Enter was lost. Four reader patches (751, 815, 4fe9935f, 430) never
# touched the delivery. The TUI enables bracketed paste (DECSET 2004), so a framed paste is one event
# whatever the pty does to the bytes, and the CR, sent only once the composer shows our text, is a
# separate keystroke.
#
# The TUI here is a python pty child in RAW mode that turns on 2004 and logs every read() it gets,
# so the assertions are about bytes as the TUI received them, not about what expect meant to send.
# The pane reader shows our text only once the child has received the paste end marker, which is the
# real dependency: a composer paints a paste after the TUI has consumed it.

load helpers/pty-reap
teardown() { pty_reap; } # no stub spawned on a pty outlives its test (tests/helpers/pty-reap.bash)

setup() {
  command -v expect >/dev/null || skip "expect(1) not installed"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIRE="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off      # hermeticity ratchet: never read live machine load
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_RESERVE_TERM=off
}

exp_setup() {
  EXP="$BATS_TEST_TMPDIR/resume.exp"
  sed -n "/^expect -c '\$/,/^' ||/p" "$FIRE" | sed '1d;$d' > "$EXP"
  [ -s "$EXP" ] || { echo "extraction of the expect body from $FIRE failed" >&2; return 1; }
  export LR_TEST_READS="$BATS_TEST_TMPDIR/reads.jsonl"; : > "$LR_TEST_READS"
  TUI="$BATS_TEST_TMPDIR/tui"
  cat > "$TUI" <<'PY'
#!/usr/bin/python3
import json, os, select, sys, termios, time, tty
def stage(s):
    with open(os.environ["LR_TEST_READS"] + ".stages", "a") as f:
        f.write("%.2f %s\n" % (time.time(), s))
stage("started")
try:
    tty.setraw(0, termios.TCSANOW)    # TCSANOW: the default TCSAFLUSH would discard typed input
    stage("raw")
except Exception as e:
    stage("setraw failed: %r" % (e,))
# READY only once raw: python can take longer than any quiet budget to start on a loaded box, and a
# prompt typed into the still-cooked pty is not what this test is about.
os.write(1, b"\x1b[?2004hTUI-READY\r\n")
end = time.time() + 120
while time.time() < end:
    r, _, _ = select.select([0], [], [], 0.5)
    if not r:
        continue
    try:
        b = os.read(0, 65536)
    except OSError:
        break
    if not b:
        break
    with open(os.environ["LR_TEST_READS"], "a") as f:
        f.write(json.dumps({"t": time.time(), "hex": b.hex()}) + "\n")
PY
  chmod +x "$TUI"
  IT2="$BATS_TEST_TMPDIR/it2"
  cat > "$IT2" <<'SH'
#!/bin/bash
b='────────────────────────────────'
# no composer box at all until the TUI is raw, so no arm of the program can type before then
grep -q ' raw$' "$LR_TEST_READS.stages" 2>/dev/null || { printf '%s\n' "  booting"; exit 0; }
if grep -q '1b5b3230317e' "$LR_TEST_READS" 2>/dev/null; then
  printf '%s\n' "  chrome" "$b" " ❯ $LR_PROMPT" "$b" " ? for shortcuts"
else
  printf '%s\n' "  chrome" "$b" " ❯ " "$b" " ? for shortcuts"
fi
SH
  chmod +x "$IT2"
  # the probe answers SUBMITTED at once, so the run ends right after the first CR
  PROBE="$BATS_TEST_TMPDIR/probe"; printf '#!/bin/bash\necho "submitted 2099-01-01T00:00:00.000Z"\n' > "$PROBE"; chmod +x "$PROBE"
  local never='ZZZ-NEVER-MATCHES-ZZZ'
  export LR_RE_MENU="$never" LR_RE_ASIS_STRONG="$never" LR_RE_ASIS="$never" LR_RE_TRUST="$never" \
         LR_RE_TRUST_RB="$never" LR_RE_FS="$never" LR_RE_FS_RB="$never" LR_RE_OVERAGE="$never" LR_RE_READY="TUI-READY"
  export LR_CFG="$BATS_TEST_TMPDIR/cfg" LR_BIN="$TUI" LR_MODEL=m LR_EFFORT=high LR_SID=cccc3333 LR_ASIS=1 LR_WRAP=""
  export LR_PROMPT="continue the work (submit token: run:cccc3333:20261018T100712Z:2bd71e0a)"
  export LR_SUBMIT_TOKEN="run:cccc3333:20261018T100712Z:2bd71e0a" LR_PROBE="$PROBE"
  export LR_IT2="$IT2" LR_PANE=5 LR_SCREEN_WANT="continuethework(submittoken:run:cccc3333"
  # Only the READY arm may type: python can take over a minute to start at load 35/core, so the quiet
  # budget is set past the case bound and the quiet arm can never race the child going raw.
  export LR_QUIET_S=500 LR_SUBMIT_POLL_S=2 RCY_ENGAGE_TIMEOUT=3
  LR_SCREEN_SH="$(sed -n "/<<'LRSCREENSH'/,/^LRSCREENSH\$/p" "$FIRE" | sed '1d;$d')"; export LR_SCREEN_SH
  [ -n "$LR_SCREEN_SH" ] || { echo "LR_SCREEN_SH extraction failed" >&2; return 1; }
  export LR_SAY_LOG="$BATS_TEST_TMPDIR/say.log"
}

@test "RED-PROOF the prompt arrives inside exactly one 200~/201~ pair, and the CR in a later read" {
  exp_setup
  run pty_timeout 1800 expect -f "$EXP" </dev/null
  [ -s "$LR_TEST_READS" ] || { echo "the TUI received nothing; its stages:"; cat "$LR_TEST_READS.stages" 2>&1; cat "$LR_SAY_LOG" 2>&1; echo "$output" | tail -20; false; }
  run python3 - "$LR_TEST_READS" "$LR_PROMPT" <<'PY'
import json, sys
reads = [bytes.fromhex(json.loads(l)["hex"]) for l in open(sys.argv[1]) if l.strip()]
want = sys.argv[2].encode()
s, e = b"\x1b[200~", b"\x1b[201~"
allb = b"".join(reads)
print("reads:", [r[:60] for r in reads])
assert allb.count(s) == 1 and allb.count(e) == 1, "want ONE frame, got %d start / %d end" % (allb.count(s), allb.count(e))
body = allb[allb.index(s) + len(s):allb.index(e)]
assert body == want, "the frame holds %r, not the prompt" % body
ei = next(i for i, r in enumerate(reads) if e in r)
assert b"\r" not in reads[ei].split(e, 1)[1], "the CR rode in the same read as the paste end"
assert any(b"\r" in r for r in reads[ei + 1:]), "no CR in any read after the paste"
assert b"\r" not in body and b"\n" not in body, "a line break inside the paste"
print("ok")
PY
  [ "$status" -eq 0 ] || { echo "$output"; cat "$LR_SAY_LOG" 2>/dev/null; false; }
}

@test "LR_BRACKETED_PASTE=off is the old raw-keystroke delivery, exactly (the kill switch)" {
  exp_setup
  export LR_BRACKETED_PASTE=off LR_SUBMIT_PAINT_S=0
  run pty_timeout 1800 expect -f "$EXP" </dev/null
  run python3 -c 'import json,sys; b=b"".join(bytes.fromhex(json.loads(l)["hex"]) for l in open(sys.argv[1]) if l.strip()); sys.exit(0 if b"\x1b[200~" not in b and sys.argv[2].encode() in b else 1)' "$LR_TEST_READS" "$LR_PROMPT"
  [ "$status" -eq 0 ] || { echo "the kill switch did not restore raw keys"; cat "$LR_TEST_READS"; false; }
}

@test "a prompt over 800 characters is never typed: it goes to a file and a short pointer line is typed" {
  # The block runs as the subject runs it: the fallback dir, then the pointer, then the flatten.
  local blk
  blk="$(sed -n '/^LR_NOTE_DIR="\${LR_RUN_DIR:-/,/^PROMPT=\${PROMPT\/\/\$'"'"'\\e'"'"'\/}$/p' "$FIRE")"
  [[ "$blk" == *LR_PROMPT_FILE* && "$blk" == *'PROMPT=${PROMPT//'* ]] || { echo "the block moved — its anchors are stale:"; printf '%s\n' "$blk"; false; }
  local long; long="$(printf '[limit-recover rescue] line one\nline two %.0s' $(seq 1 120))"
  run env LR_STATE_DIR="$BATS_TEST_TMPDIR/state" bash -c 'exec 2>/dev/null; SID=cccc3333-x; PROMPT="$1"; lr_state() { :; }; eval "$2"; printf "%s\n%s" "$PROMPT" "$LR_PROMPT_FILE"' _ "$long" "$blk"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local typed file; typed="$(printf '%s\n' "$output" | sed -n 1p)"; file="$(printf '%s\n' "$output" | sed -n 2p)"
  [ "${#typed}" -lt 800 ] || { echo "the typed line is ${#typed} characters"; false; }
  [[ "$typed" == "[limit-recover] "*"read $file and follow it." ]] || { echo "typed: $typed"; false; }
  [ "$(cat "$file")" = "$long" ] || { echo "the file does not hold the prompt as given, newlines intact"; false; }
  # under the threshold nothing changes but the flatten
  run env LR_STATE_DIR="$BATS_TEST_TMPDIR/state" bash -c 'exec 2>/dev/null; SID=cccc3333-x; PROMPT="$1"; lr_state() { :; }; eval "$2"; printf "%s|%s" "$PROMPT" "$LR_PROMPT_FILE"' _ $'short\nprompt' "$blk"
  [ "$output" = "short prompt|" ] || { echo "got: $output"; false; }
}
