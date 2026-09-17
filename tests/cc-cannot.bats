#!/usr/bin/env bats
# cc-cannot — every case below is a defect REPRODUCED against the frozen corpus
# (docs/research/silver-platter-enforcement-2026-09-12/). Each test names the amendment it pins.
# rc: 0 HUMAN · 1 REFUTED · 2 UNRESOLVED.

setup() {
  CC="${BATS_TEST_DIRNAME}/../bin/cc-cannot"

  # RULE 1 — cc-cannot resolves script bodies and cc-owner under $HOME (bin/cc-cannot:147-150,184-185),
  # so unfixtured this suite read the OPERATOR's live ~/. That is not a style point: it passed 13/13 on
  # the desk and went 4-RED (1,7,11,13) on a cloud VM that simply lacks those paths, which is how a
  # correct diff reached the land gate carrying a red nobody could reproduce. Seed the state instead.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy" "$HOME/.claude/scripts" "$HOME/.claude/bin" \
           "$HOME/Development/claude-infrastructure/scripts"

  # A2b's contrasting pair, seeded to the ONE property each case turns on: a /dev/tty GUARD inside
  # cc-cannot's head -80 band (HUMAN) versus incidental terminal handling below it (must abstain).
  printf '%s\n' '#!/usr/bin/env bash' \
                 '# drain the approval queue' \
                 'read -r -p "proceed? " ans </dev/tty' \
    > "$HOME/.claude/autonomy/approval-queue-drain.sh"
  { printf '%s\n' '#!/usr/bin/env bash'
    i=0; while [ "$i" -lt 90 ]; do printf '%s\n' '# orchestration preamble - no human gate here'; i=$((i+1)); done
    printf '%s\n' 'printf "" >/dev/tty   # drives a PANE it spawned, far below the guard band'
  } > "$HOME/.claude/scripts/handoff-fire.sh"

  # The scheduler arm's subject. Its body must carry no guard signature, or A2 would answer first.
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
    > "$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"

  # cc-owner stub — the two-line OWNED shape bin/cc-owner emits. cc-cannot reads line 2 and scans it
  # for the handed-over command's flags (bin/cc-cannot:195-203), which is the whole flag-divergence
  # test; stubbing keeps that composition under test without reading the operator's live launchd.
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "$1" in' \
    '  *deploy-live.sh*)' \
    '    printf "OWNED - something already runs this; do NOT hand it to the operator:\n" ;' \
    '    printf "  launchd:com.claude.deploy-live (LOADED every 600s) - names deploy-live.sh\n" ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    > "$HOME/.claude/bin/cc-owner"
  chmod +x "$HOME/.claude/bin/cc-owner"

  # RULE 2 — this suite NAMES handoff-fire, so the lint requires the pin even though it never
  # executes it: capacity_gate() reads live vm.loadavg and would make a fire red-by-load.
  export CC_FIRE_CAPACITY_GATE=off

  # RULE 5 — seams that do NOT resolve under $HOME: two absolute /tmp defaults and one bare name the
  # subject would execute off the operator's PATH. An ABSENT path is the right value here.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
}

@test "A1+A2 · the corpus's largest hand-off is HUMAN even though /tmp copy is gone" {
  # approval-queue-drain.sh — 270 emissions, 20% of the whole corpus. Deleted from /tmp; a durable
  # copy lives under ~/.claude/autonomy. Its header: "a permission prompt is answerable only in its
  # own pane, by a human." The previous design REFUTED it, because the script is designed to be
  # agent-run first and so its own correct use produces the receipt that convicts it. That block
  # would strand the operator and every pane queued behind him.
  run bash "$CC" -- "bash /tmp/approval-queue-drain.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^HUMAN"
}

@test "A2 · an unreadable body ABSTAINS; it must never convict" {
  # Decay is one-directional: acquitting evidence lives in the perishable body, convicting evidence
  # in the durable transcript. A body we cannot read is UNREADABLE evidence, not absent evidence.
  run bash "$CC" -- "bash /tmp/definitely-not-here-$$.sh"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q "script-gone"
  ! printf '%s' "$output" | grep -q "REFUTED"
}

@test "A3 · the slash test is anchored — /usr/bin/env is not a TUI command" {
  # The prior form was a bash glob where * matched / and spaces, making `/usr/bin/env <anything>`
  # a universal one-token acquittal wrapper.
  run bash "$CC" -- "/usr/bin/env cc-blockers"
  [ "$status" -ne 0 ]
  ! printf '%s' "$output" | grep -q "tui" || false

  run bash "$CC" -- "/deploy"          # the real thing still acquits
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "tui"
}

@test "A4 · a read-only sibling must not license the money-spending call" {
  # `aws amplify list-jobs` must never put `aws amplify start-job … RELEASE` on a REFUTED path.
  # Signature matching did exactly that, converting a read into a production deploy.
  run bash "$CC" -- "aws amplify start-job --app-id x --branch-name main --job-type RELEASE"
  [ "$status" -ne 1 ]
}

@test "genuinely-human arms: sudo, physical, interactive login" {
  run bash "$CC" -- "open tel:7143346077";               [ "$status" -eq 0 ]
  run bash "$CC" -- "gh auth refresh -h github.com -s user"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "login"   # must NOT fall through to the `gh` self-runnable arm
}

@test "AFFIRM-BEFORE-REFUTE · a sudo prefix outranks the self-runnable family" {
  # `git …` is self-runnable, but `sudo git …` is a different call and the password gate wins.
  run bash "$CC" -- "sudo git -C /opt/thing pull"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "sudo"
}

@test "scheduler-owned refutation composes with cc-owner rather than duplicating it" {
  run bash "$CC" -- "bash $HOME/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "com.claude.deploy-live"
}

@test "POLARITY · an empty or unrecognised command is UNRESOLVED, never a verdict" {
  run bash "$CC" -- ""
  [ "$status" -eq 2 ]
  run bash "$CC" -- "frobnicate --widget 7"
  [ "$status" -eq 2 ]
}

# ── arms added 2026-09-12 after scoring against the 429-command gold set ────────────────────────

@test "R0 · a READ-ONLY command under an imperative marker is always a defect" {
  # The one arm measured at 100% precision (42 distinct / 147 emissions, zero false positives).
  # It asks "does this CHANGE anything" — a closed set — instead of "does a human have to run it",
  # which is not visible in the command at all.
  for c in "cc-blockers" "cc-decide list --open" "git log --oneline -5" "cursor docs/OWNER_BRIEF.md"; do
    run bash "$CC" -- "$c"
    [ "$status" -eq 1 ]
    printf '%s' "$output" | grep -q "read-only"
  done
}

@test "R0 · a mutating flag or a chain disqualifies the read-only match" {
  # `gh pr view --web` opens a browser; `git show … && rm …` is not a read.
  run bash "$CC" -- "gh pr view 1 --repo x/y --web"
  ! printf '%s' "$output" | grep -q "read-only" || false
  run bash "$CC" -- "git show abc123 && rm -rf /tmp/x"
  ! printf '%s' "$output" | grep -q "read-only"
}

@test "A2b · the body signature must be a GUARD, not an incidental match" {
  # approval-queue-drain.sh gates on /dev/tty at :46, before its work → HUMAN.
  run bash "$CC" -- "bash /tmp/approval-queue-drain.sh"
  [ "$status" -eq 0 ]
  # handoff-fire.sh contains /dev/tty handling for the panes it DRIVES, far down the file. Every
  # `--recycle` in the corpus was wrongly called HUMAN before this bound → must now abstain.
  run bash "$CC" -- "bash ~/.claude/scripts/handoff-fire.sh --recycle"
  [ "$status" -eq 2 ]
}

@test "the cc-* family is NOT blanket self-runnable (the deleted arm's defect)" {
  # cc-do is the operator's ACTION RUNNER. The removed arm refuted it on the shape of its name.
  run bash "$CC" -- "cc-do 042b5a4dede3"
  [ "$status" -ne 1 ]
}

@test "A4 on the scheduler arm · a receipt covers only the invocation the scheduler makes" {
  # com.claude.deploy-live runs `deploy-live.sh --auto`. `--force` is the escape hatch that
  # DISCARDS the green-stamp gate, and is the operator's decision. cc-owner resolves on basename,
  # so without this the gate told the operator "a launchd agent already does this" about a command
  # no launchd agent ever runs. Every false block in the corpus was this one bug; with it, zero.
  run bash "$CC" -- "bash $HOME/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 1 ]                       # the plain form IS scheduler-owned
  printf '%s' "$output" | grep -q "scheduler-owned"

  run bash "$CC" -- "bash ~/Development/claude-infrastructure/scripts/deploy-live.sh --force"
  [ "$status" -eq 2 ]                       # the escape hatch is NOT covered by that receipt
  printf '%s' "$output" | grep -q "flag-divergence"
}

@test "no undrained early-exit consumer survives on a CONTINUATION line (the ratchet is blind here)" {
  # THE RATCHET CANNOT SEE THESE LINES, which is why this pin exists rather than an allowlist row.
  # pipefail-sigpipe-lint's qmask() "does not join CONTINUATION lines" (scripts/pipefail-sigpipe-lint.sh
  # :532, a residual that file names and declines to widen). Measured 2026-09-17, one variable per
  # fixture: `p | grep -Eq P && act` on ONE physical line IS reported, and the identical shape split
  # across a `\` is NOT — so `&&` is not the blind axis, the continuation is.
  #
  # 0ea2ab91c drained the five sites the ratchet DID flag. Three more in this file were the same bug
  # wearing a continuation: :136 (open tel:/sms:), :140 (interactive credential flows) and :208 (the
  # editor refutation). Each gates an `&&` that fires a VERDICT, so under pipefail a match SIGPIPEs
  # the producer and the guard fails OPEN exactly when it should speak — the polarity 0ea2ab91c names.
  # (Line 174's `head -80 … | grep -Eom1` stays untouched: its rc dies in a command substitution, so
  # no verdict can be corrupted. Drained vs not is about whether an rc is READ, not about the shape.)
  local bad
  bad="$(awk '/\\$/ { prev=$0; sub(/\\$/,"",prev); n=NR; if ((getline nxt) > 0) {
                        j = prev " " nxt
                        if (j ~ /\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q/) printf "%d: %s\n", n, prev } }' "$CC")"
  [ -z "$bad" ] || { echo "undrained early-exit consumer hidden on a continuation line:"; echo "$bad"; false; }
}
