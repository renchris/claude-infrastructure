#!/usr/bin/env bats
# cc-cannot — every case below is a defect REPRODUCED against the frozen corpus
# (docs/research/silver-platter-enforcement-2026-09-12/). Each test names the amendment it pins.
# rc: 0 HUMAN · 1 REFUTED · 2 UNRESOLVED.

setup() { CC="${BATS_TEST_DIRNAME}/../bin/cc-cannot"; }

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
  ! printf '%s' "$output" | grep -q "tui"

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
  run bash "$CC" -- "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
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
  ! printf '%s' "$output" | grep -q "read-only"
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
  run bash "$CC" -- "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 1 ]                       # the plain form IS scheduler-owned
  printf '%s' "$output" | grep -q "scheduler-owned"

  run bash "$CC" -- "bash ~/Development/claude-infrastructure/scripts/deploy-live.sh --force"
  [ "$status" -eq 2 ]                       # the escape hatch is NOT covered by that receipt
  printf '%s' "$output" | grep -q "flag-divergence"
}
