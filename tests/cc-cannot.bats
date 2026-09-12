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
