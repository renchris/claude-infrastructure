#!/usr/bin/env bats
# enforce-email-formatting.py — the RECIPE must fit Claude Code's additionalContext cap.
#
# WHY THIS SUITE EXISTS (2026-10-04). Claude Code caps a hook's additionalContext at 10,000 chars;
# past it the model is handed a ~2KB preview instead. The recipe had grown to 10,393 chars, so all
# 19 injections in 14 days arrived as that preview and rules 1-6 never reached the model, with
# nothing anywhere saying so (docs/research/claude-api-audit-2026-10-04/REPORT.md, hooks-a-01..05).
# The trim fixed it once; this suite is what stops the next paragraph from undoing it.
#
# THE WORST CASE IS NOT THE RECIPE ALONE. allow() joins the recipe and the R2 alias advisory into
# ONE additionalContext on a session's first mail call, and the advisory interpolates the alias, the
# mailbox default and both personal short names, so its length depends on which alias is set. The
# measurement therefore runs the REAL entrypoint once per address each mailbox owns, as a fresh
# session, and takes the longest context it emits — not a length re-derived from the source.
#
# NON-VACUOUS: `redproof_pre_trim_recipe_overflows` replays the pinned pre-trim blob through the
# same instrument and asserts it is OVER both bounds. Without it, an instrument that measured the
# wrong field (or nothing) would pass every case here.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Same synthetic overlay as the other email suites: the rendered recipe names the mailboxes, so
  # its length is a function of the overlay, and the suite must pin one.
  export CC_IDENTITY_FILE="$REPO/tests/fixtures/identity.fixture.json"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
}

# recipe_len <gate> -> len(RECIPE) as the module renders it at import.
recipe_len() {
  GATE_UT="$1" python3 -c '
import importlib.util, os
spec = importlib.util.spec_from_file_location("email_gate", os.environ["GATE_UT"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(len(mod.RECIPE))
'
}

# first_touch <gate> -> one line per owned address: "<context-len> <decision> <advisory?> <alias>".
# Each address gets its own session id, so every call is that session's FIRST mail touch and carries
# the recipe; each also gets its R4 freshness stamps, or the draft would be denied for an unrelated
# reason and the advisory would never be emitted.
first_touch() {
  GATE_UT="$1" python3 -c '
import json, os, subprocess, sys
boxes = json.load(open(os.environ["CC_IDENTITY_FILE"]))["ms365"]["mailboxes"]
tmp = os.environ["TMPDIR"]
n = 0
for acct, v in boxes.items():
    for alias in v["aliases"]:
        n += 1
        sid = "cap%d" % n
        for suffix in ("", "-ctx"):
            open(os.path.join(tmp, "cc-ms365-inbound-" + sid + suffix), "w").close()
        tin = {"account": acct, "body": {"message": {
            "body": {"contentType": "html", "content": "<p>Hi.</p><blockquote><p>Prior.</p></blockquote>"},
            "from": {"emailAddress": {"address": alias}}}}}
        pay = json.dumps({"session_id": sid, "hook_event_name": "PreToolUse",
                          "tool_name": "mcp__ms365__create-reply-draft", "tool_input": tin})
        p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay,
                           capture_output=True, text=True)
        h = json.loads(p.stdout)["hookSpecificOutput"]
        ctx = h.get("additionalContext", "")
        print(len(ctx), h["permissionDecision"], "advisory" if "ALIAS CHECK" in ctx else "none", alias)
'
}

@test "the rendered RECIPE leaves room for the alias advisory: len(RECIPE) <= 9350" {
  run recipe_len "$GATE"
  [ "$status" -eq 0 ]
  [ "$output" -le 9350 ]
}

@test "recipe plus the worst-case R2 alias advisory stays under the 10,000-char cap" {
  run first_touch "$GATE"
  [ "$status" -eq 0 ]
  # Positive control on the instrument: one row per owned address (2 personal + 7 work in the
  # fixture), every one ALLOWED and carrying the advisory. A deny or a silent call would measure a
  # shorter context and pass for the wrong reason.
  [ "${#lines[@]}" -eq 9 ]
  [ "$(printf '%s\n' "${lines[@]}" | grep -c ' allow advisory ')" -eq 9 ]
  worst="$(printf '%s\n' "${lines[@]}" | sort -n | tail -1)"
  echo "worst first-touch context: $worst"
  [ "${worst%% *}" -lt 10000 ]
}

@test "redproof_pre_trim_recipe_overflows: the pre-trim hook fails both bounds" {
  # Blob fc64d1efa is hooks/enforce-email-formatting.py at 2247aeeac^, immediately before the trim.
  # Pinned as a BLOB so the control cannot drift onto its own subject.
  local pre="$BATS_TEST_TMPDIR/pre-trim-hook.py"
  git -C "$REPO" cat-file -e fc64d1efa 2>/dev/null || skip "pinned pre-trim blob fc64d1efa absent (public projection)"
  git -C "$REPO" cat-file -p fc64d1efa > "$pre"
  run recipe_len "$pre"
  [ "$output" -gt 9350 ]
  run first_touch "$pre"
  [ "${#lines[@]}" -eq 9 ]
  worst="$(printf '%s\n' "$output" | sort -n | tail -1)"
  [ "${worst%% *}" -ge 10000 ]
}
