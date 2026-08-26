#!/usr/bin/env bats
# handoff-fire.sh — a recycle may not type /exit into a pane that the /exit will DESTROY.
#
# THE INCIDENT (2026-08-26T06:21Z, pane 32). The reso undo session fired `--recycle` to relocate
# itself out of a reaped worktree. Every existing gate passed: pane_cc_state read `cc`, the composer
# gate proved the box empty, the watcher armed and pane_proof enumerated pane 32. The /exit landed
# — and the pane went with it.
#
#   bin/cc-resume-layout.sh:303  kitty @ launch --type=os-window … -- "$RESUME_ONE" …
#   bin/reso-resume-one:395      exec expect -c '… spawn … claude … interact'
#
# The pane's argv IS the session's launcher, so there is no shell under the CC to fall back to.
# expect exited with claude, kitty destroyed the window, and /dev/ttys021 was released. The detached
# watcher's only sensor is pane_cc_state on that tty; a tty with no processes answers `unknown`,
# which is an ABSTENTION ("could not read"), not a finding — so the watcher held at 60/150/300 s and
# gave up at 600 s. The successor was never typed and its brief was never used. lead-supervisor then
# reaped the session as `clean-completion-shipped-clean-worktree`, so nothing anywhere recorded that
# a recycle had failed.
#
# WHAT IS PINNED HERE, in the order the two remedies act:
#   1. pane_shell_root — the missing PRECONDITION. "A session is running here" and "this pane will
#      outlive that session" are different questions, and the recycle contract depends on the
#      second. Fixtures are the measured shapes, shared verbatim with
#      tests/handoff-recycle-expect-probe.bats.
#   2. THE POLARITY. It refuses only on affirmative evidence — roots READ and not one a shell. An
#      unreadable tty is `unknown` and proceeds. A gate that refused whenever it could not see
#      would convert working recycles into manual steps, which the expect-probe suite already names
#      as just as broken as one that always types.
#   3. THE ACTUATOR, and its CONTROL. recycle_fire is extracted and RUN. With the gate OFF the same
#      fixture must NOT be refused for this reason — otherwise these tests would pass against an
#      implementation that refuses for some other cause, and would keep passing if the gate were
#      deleted.
#   4. pane_enumerated — the DETECTION half, so a pane that dies anyway is reported in seconds
#      rather than at the 600 s bound, and reported as a finding rather than as an abstention.
#
# NOTHING HERE EXECUTES A REAL FIRE. Functions are sed-extracted (the established idiom) and both
# `ps` and the it2 shim are fixture-driven stubs, so no live pane is read and no keystroke reaches a
# terminal.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`: `[[ ]]` is errexit-EXEMPT in bats and is
# silently DEAD anywhere but a body's last line.

setup() {
  # PIN THE TERMINAL — handoff-fire's primitives branch on KITTY_WINDOW_ID, so an unpinned suite
  # becomes a function of the developer's terminal.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  unset CC_TERM
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing: $HF" >&2; return 1; }
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # Seams that do NOT resolve under $HOME — an absolute /tmp default and a bare PATH name — so
  # fixturing $HOME alone would still let this suite read the operator's live state.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"

  hf_bounded() { "$@"; }                       # the timeout(1) wrapper is out of scope when extracted

  # ── the process-table fixture + the `ps` that answers from it ────────────────────────────────
  # TSV: pid<TAB>ppid<TAB>pgid<TAB>tpgid<TAB>tty<TAB>comm<TAB>args
  # One table, every query form the subject makes — a stub answering only the forms the CURRENT
  # implementation happens to call would silently pass a rewrite that asked a different question.
  PSTABLE="$BATS_TEST_TMPDIR/pstable.tsv"; export PSTABLE
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  cat > "$STUB/ps" <<'FAKEPS'
#!/usr/bin/env bash
fmt=""; sel=""; val=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-axo|-Ao) fmt="$2"; [ "$1" = -o ] || sel="all"; shift 2 ;;
    -t) sel="tty";  val="${2##*/}"; shift 2 ;;
    -g) sel="pgid"; val="$2"; shift 2 ;;
    -p) sel="pid";  val="$2"; shift 2 ;;
    -ax*) fmt="${1#-ax}"; fmt="${fmt#o}"; sel="all"; shift ;;
    *) shift ;;
  esac
done
awk -F'\t' -v fmt="$fmt" -v sel="$sel" -v val="$val" '
  ($1 == "" || $1 ~ /^#/) { next }
  {
    keep = (sel == "all") || (sel == "tty" && $5 == val) \
        || (sel == "pgid" && $3 == val) || (sel == "pid" && $1 == val)
    if (!keep) next
    out = ""
    n = split(fmt, f, ",")
    for (i = 1; i <= n; i++) {
      gsub(/=/, "", f[i])
      v = (f[i] == "pid") ? $1 : (f[i] == "ppid") ? $2 : (f[i] == "pgid") ? $3 \
        : (f[i] == "tpgid") ? $4 : (f[i] == "tty") ? $5 : (f[i] == "comm") ? $6 : $7
      out = (out == "") ? v : out " " v
    }
    print out
  }' "$PSTABLE"
FAKEPS
  chmod +x "$STUB/ps"
  PATH="$STUB:$PATH"

  eval "$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_cc_state() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_shell_root() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_enumerated() {/,/^}/p' "$HF")"
}

# ── fixtures, each transcribed from a measured pane ──────────────────────────────────────────────

fixture_pane32() {      # THE INCIDENT: cc-resume-layout's os-window — argv IS reso-resume-one,
                        # which exec'd expect. No shell anywhere on the tty.
  cat > "$PSTABLE" <<'EOF'
1427	1	1427	-1	??	/Applications/kitty.app/Contents/MacOS/kitty	/Applications/kitty.app/Contents/MacOS/kitty
9568	1427	9568	9568	ttys021	expect	expect -c set timeout 240 spawn -noecho env claude --resume 30614274
9570	9568	9570	9570	ttys022	/Users/chrisren/.claude-220/node_modules/.bin/claude	/Users/chrisren/.claude-220/node_modules/.bin/claude --resume 30614274
EOF
}

fixture_normal_pane() { # THE SHAPE THAT WORKS (measured pane 27 / ttys000, 2026-08-26): kitty →
                        # zsh → cc-close-attrib(bash) → claude, plus the p10k gitstatusd daemon.
  cat > "$PSTABLE" <<'EOF'
19848	1427	19848	19848	ttys000	/bin/zsh	/bin/zsh
20138	1	20138	19848	ttys000	gitstatusd-darwin-arm64	gitstatusd-darwin-arm64
93683	19848	93683	93683	ttys000	bash	bash /Users/chrisren/.claude/bin/cc-close-attrib claude
93721	93683	93683	93683	ttys000	/Users/chrisren/.claude-220/node_modules/.bin/claude	claude --effort high
EOF
}

fixture_idle_shell() {  # A BARE PROMPT with the p10k daemon in a BACKGROUND group (measured ttys017)
  cat > "$PSTABLE" <<'EOF'
38853	37816	38853	38853	ttys017	/bin/zsh	-zsh
38887	1	38885	38853	ttys017	/bin/zsh	/bin/zsh
39507	38887	38885	38853	ttys017	gitstatusd-darwin-arm64	gitstatusd-darwin-arm64
EOF
}

# ── 1. THE PRECONDITION: the incident shape is positively identified ─────────────────────────────

@test "pane 32: pane_cc_state still says cc — every gate that existed PASSED" {
  # The control for the whole file. The incident is not "a gate said no and we ignored it"; it is
  # that no gate asked this question at all. If this ever stops reading `cc`, the fixture has
  # stopped modelling the incident and everything below proves something else.
  fixture_pane32
  run pane_cc_state /dev/ttys021
  [ "$output" = "cc" ]
}

@test "pane 32: pane_shell_root says NO — the pane cannot outlive its own /exit" {
  fixture_pane32
  run pane_shell_root /dev/ttys021
  [ "$output" = "no" ]
}

@test "pane 32: the verdict comes from the ROOT, not from the closure" {
  # `bash cc-close-attrib` is a shell INSIDE every CC, so a predicate that walked the descendant
  # closure would answer `yes` for every pane on the box — including this one. The discriminator has
  # to be the process whose parent is not itself on this tty, i.e. the pane's argv.
  fixture_pane32
  run grep -c 'cc-close-attrib' "$PSTABLE"
  [ "$output" = "0" ]                          # this pane has none; the normal one below does
  fixture_normal_pane
  run grep -c 'cc-close-attrib' "$PSTABLE"
  [ "$output" = "1" ]
  run pane_shell_root /dev/ttys000
  [ "$output" = "yes" ]                        # …and it is the ROOT zsh that earns the yes
}

# ── 2. THE POSITIVE CONTROL, so the gate cannot be "always refuse" ───────────────────────────────

@test "a normal CC pane says yes — the shape 99% of recycles run in" {
  fixture_normal_pane
  run pane_shell_root /dev/ttys000
  [ "$output" = "yes" ]
}

@test "a bare prompt says yes, and a background gitstatusd does not spoil it" {
  # A predicate that demanded EVERY root be a shell would refuse on every powerlevel10k pane, since
  # gitstatusd is reparented to launchd and therefore reads as a root of this tty.
  fixture_idle_shell
  run grep -c gitstatusd "$PSTABLE"
  [ "$output" = "1" ]
  run pane_shell_root /dev/ttys017
  [ "$output" = "yes" ]
}

# ── 3. THE POLARITY: unknown is not no, and only `no` may act ────────────────────────────────────

@test "a tty with no processes is unknown, never no" {
  fixture_normal_pane
  run pane_shell_root /dev/ttys999
  [ "$output" = "unknown" ]
}

@test "an empty tty argument is unknown, never no" {
  fixture_normal_pane
  run pane_shell_root ""
  [ "$output" = "unknown" ]
}

# ── 4. THE ACTUATOR — the branch that types, and its kill-switch control ─────────────────────────

setup_recycle() {
  TYPED="$BATS_TEST_TMPDIR/typed.log"; : > "$TYPED"
  export TYPED
  export SID="PANE-1" CMD="claude --resume abc" LAUNCHER="claude" RECYCLE_MARKER="MK"
  export PROMPT_FILE="$BATS_TEST_TMPDIR/brief.txt"
  pin_term_verdict_for_watcher() { :; }
  as_tty() { printf '/dev/%s' "$STUB_TTY"; }
  as_tty_classified() { [ -n "$STUB_TTY" ] || return 1; printf '/dev/%s' "$STUB_TTY"; }
  it2_type_verified() { printf '%s\n' "$3" >> "$TYPED"; return 0; }
  cc_sid_for_pane() { printf 'old-sid'; }
  write_teardown_marker() { :; }
  emit_recycle_event() { printf '%s %s\n' "$1" "$4" >> "$BATS_TEST_TMPDIR/events.log"; }
  detach() { printf '4242'; }
  # ARM-REACHED SENTINEL. `await_armed` is the first thing recycle_fire calls AFTER the gates, so a
  # file written here is un-fakeable evidence that the gate let the fire through. Returning 1 stops
  # the path there, loudly, before anything irreversible.
  await_armed() { : > "$BATS_TEST_TMPDIR/armed"; return 1; }
  rm -f "$BATS_TEST_TMPDIR/armed" "$BATS_TEST_TMPDIR/events.log"
  export CC_RECYCLE_COMPOSER_GATE=off          # a different gate; out of scope here
  eval "$(sed -n '/^recycle_fire() {/,/^}/p' "$HF")"
}

@test "recycle_fire: the pane-32 shape is REFUSED before the watcher arms — nothing typed" {
  fixture_pane32
  setup_recycle
  STUB_TTY=ttys021
  run recycle_fire
  [ "$status" -ne 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/armed" ]           # it never reached the arm, so no /exit was queued
  run cat "$TYPED"
  [ "$output" = "" ]
}

@test "recycle_fire: the refusal NAMES the remedy — a handoff, not a retry" {
  # A refusal whose advice is "re-run --recycle" would loop forever on this pane shape. The one
  # thing that works is firing the successor into its OWN pane and retiring this one.
  fixture_pane32
  setup_recycle
  STUB_TTY=ttys021
  run recycle_fire
  [[ "$output" == *"recycle REFUSED"* ]] || false
  [[ "$output" == *"self-close"* ]] || false
  [[ "$output" != *"→ recycled"* ]] || false
}

@test "recycle_fire: the refusal is LEDGERED, so a refused recycle is not invisible" {
  fixture_pane32
  setup_recycle
  STUB_TTY=ttys021
  run recycle_fire
  run grep -c 'recycle-refused-no-shell' "$BATS_TEST_TMPDIR/events.log"
  [ "$output" = "1" ]
}

@test "CONTROL: with the gate OFF the same pane is NOT refused — it reaches the arm" {
  # Without this, every assertion above would be satisfied by an implementation that refuses this
  # fixture for some unrelated reason, and would keep passing if the gate were deleted outright.
  fixture_pane32
  setup_recycle
  STUB_TTY=ttys021
  CC_RECYCLE_SURVIVE_GATE=off run recycle_fire
  [ -f "$BATS_TEST_TMPDIR/armed" ]
  run cat "$TYPED"
  [ "$output" = "" ]                           # still nothing typed — await_armed stopped it
}

@test "recycle_fire: a normal CC pane still reaches the arm — no regression" {
  fixture_normal_pane
  setup_recycle
  STUB_TTY=ttys000
  run recycle_fire
  [ -f "$BATS_TEST_TMPDIR/armed" ]
}

@test "recycle_fire: a CONFIRMED bare prompt still types — the gate is not a blanket refusal" {
  fixture_idle_shell
  setup_recycle
  STUB_TTY=ttys017
  run recycle_fire
  [ "$status" -eq 0 ]
  run cat "$TYPED"
  [ "$output" = "claude --resume abc" ]
}

# ── 5. THE DETECTION HALF — pane_enumerated, so a pane that dies anyway is seen in seconds ───────

stub_it2() {  # $1 = the payload `session list --json` should print
  IT2="$BATS_TEST_TMPDIR/it2"
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/listing"
  cat > "$IT2" <<'SHIM'
#!/usr/bin/env bash
[ "$1" = session ] && [ "$2" = list ] || exit 64
cat "$LISTING"
SHIM
  chmod +x "$IT2"
  export LISTING="$BATS_TEST_TMPDIR/listing"
}

@test "pane_enumerated: a listed pane is present" {
  stub_it2 '[{"id": "27", "title": "a"}, {"id": "32", "title": "b"}]'
  run pane_enumerated "$IT2" 32
  [ "$output" = "present" ]
}

@test "pane_enumerated: the pane-32 outcome — other panes listed, this one gone" {
  # The live listing at 23:24:36, 3 minutes after the /exit: six ids, none of them 32.
  stub_it2 '[{"id": "27"}, {"id": "62"}, {"id": "59"}, {"id": "60"}, {"id": "46"}, {"id": "63"}]'
  run pane_enumerated "$IT2" 32
  [ "$output" = "absent" ]
}

@test "pane_enumerated: a COMPACT single-line array does not lose every id but the last" {
  # pane_proof's own lesson: sed's greedy `.*` matches to the LAST \"id\" on the line, so a compact
  # producer would report every pane but one as absent. Both fixtures above are single-line, and
  # this asserts the first id of a compact array specifically.
  stub_it2 '[{"id": "27"}, {"id": "62"}, {"id": "63"}]'
  run pane_enumerated "$IT2" 27
  [ "$output" = "present" ]
}

@test "pane_enumerated: a RENDERED TABLE is unknown, never absent" {
  # An it2 that ignored --json returns ellipsis-truncated ids that can never match at any width.
  # Reading that as `absent` would alarm "your pane is gone" about a healthy pane.
  # NOTE ON ITS MUTANT: the subject carries no dedicated rendered-table arm, because one was written
  # and deleted when its mutant came back GREEN — the id-extraction path already yields nothing here
  # and lands in the same `unknown`. This test therefore shares a mutant with the no-ids case above,
  # and that is stated rather than hidden: it pins the BEHAVIOUR, and the behaviour is what a future
  # rewrite (say, one that adds pane_proof's bare-shape fallback) would break.
  stub_it2 '│ 27  … │
│ 32  … │'
  run pane_enumerated "$IT2" 32
  [ "$output" = "unknown" ]
}

@test "pane_enumerated: an EMPTY listing is unknown, never absent" {
  stub_it2 ''
  run pane_enumerated "$IT2" 32
  [ "$output" = "unknown" ]
}

@test "pane_enumerated: a well-formed payload carrying NO ids is unknown, never absent" {
  # A distinct guard from the empty-output one above, and it needs its own mutant: a shim that
  # answers with a valid but id-less document (a schema change, an error object) must not be read as
  # "every pane on this box has vanished".
  stub_it2 '{"error": "no sessions"}'
  run pane_enumerated "$IT2" 32
  [ "$output" = "unknown" ]
}

@test "pane_enumerated: a FAILED transport is unknown, never absent" {
  IT2="$BATS_TEST_TMPDIR/it2-broken"
  printf '#!/usr/bin/env bash\nexit 3\n' > "$IT2"; chmod +x "$IT2"
  run pane_enumerated "$IT2" 32
  [ "$output" = "unknown" ]
}

@test "pane_enumerated: an absent shim is unknown, never absent" {
  run pane_enumerated "$BATS_TEST_TMPDIR/no-such-it2" 32
  [ "$output" = "unknown" ]
}

# ── 6. THE OTHER HALF OF THE ROOT CAUSE: the resumed pane now outlives its session ───────────────

@test "reso-resume-one no longer makes expect the pane's TERMINAL process" {
  # The source-level assertion, because the behaviour needs a real pty and a real resume to observe.
  # `exec expect` is what made the pane die with the session; running expect as a child and exec'ing
  # a login shell afterwards is what lets pane_cc_state ever reach its `shell` verdict.
  RR="$REPO/bin/reso-resume-one"
  [ -f "$RR" ] || { echo "subject missing: $RR" >&2; return 1; }
  run grep -c '^exec expect -c' "$RR"
  [ "$output" = "0" ]
  run grep -c '^expect -c' "$RR"
  [ "$output" = "1" ]
  run grep -c '^exec "\${SHELL:-/bin/zsh}" -l -i' "$RR"
  [ "$output" = "1" ]
}

@test "reso-resume-one: the headless harness must NOT be handed an interactive shell" {
  # CC_RR_NO_INTERACT is the test path; exec'ing zsh -i there would hang the suite forever. The
  # guard is an AFFIRMATIVE check on that variable and on stdin being a tty, not an absence.
  RR="$REPO/bin/reso-resume-one"
  run grep -c 'CC_RR_NO_INTERACT:-' "$RR"
  [ "$status" -eq 0 ]
  [ "$output" != "0" ]
  run grep -c '\[ ! -t 0 \]' "$RR"
  [ "$output" = "1" ]
}
