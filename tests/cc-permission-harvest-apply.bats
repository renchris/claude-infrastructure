#!/usr/bin/env bats
# cc-permission-harvest --check / --apply — the half that WRITES the permission allowlist, and so
# the half every guardrail in this fleet is built to keep an agent away from.
#
# WHY APPLY IS `proposed ∩ fresh`, AND WHY THESE ARMS PROVE IT. A proposal file is a claim made in
# the past by a run the operator did not watch. Between the weekly run and the operator's typed
# `yes` at cc-do it can be TAMPERED (a rule edited in that no gate would pass) or it can DECAY (the
# archive rows that justified it aged out of the window). The first design gated apply on the
# proposal's AGE, which re-derives nothing about the evidence (PERMISSION_HARVEST.md §10 B1-5/B3-5).
# This one re-runs the FULL pipeline against the live files and the live archive at apply time and
# writes only what both agree on — so a tampered rule can only SHRINK the set (exit 4, nothing
# written) and a decayed one is a NAMED DROP (exit 0), never an error. The arms below are the two
# directions of that intersection plus the four properties of the write itself: consent (CONFIRM=1,
# supplied by cc-do's typed yes — the tool must never demand a tty of its own), atomicity across
# the five forks (all or none, restored on failure), realpath writes that refuse a git worktree
# unless named, and the project-local consolidation that is the loop's largest denominator.
#
# Harness laws, following tests/cc-permission-prune.bats: L1 HOME is redirected and every target the
# tool could write is generated under it — five fleet forks and project A's gitignored local file —
# so the operator's real settings are never a target; L2 write arms key on BYTE IDENTITY (a digest
# snapshot before, compared after), which fails in opposite directions for a no-op and an
# over-write; L3 `[ ]`, `run`, `[[ ]] || false` — never a bare `[[ ]]` or `! cmd` mid-body; L4 every
# apply invocation strips the agent-session markers the RUNNER itself carries (CLAUDECODE,
# CLAUDE_CODE_SESSION_ID, CLAUDE_CODE_ENTRYPOINT) — the courtesy refusal is under test in exactly
# one arm, and a suite run from inside a session would otherwise read that refusal as every other
# arm's verdict. The hard stop (validate-bash.sh's deny arm) is unit C3's suite; it does not fire
# on a bats subprocess and is not what these arms measure.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HARVEST="$REPO/bin/cc-permission-harvest"
  FIXD="$REPO/tests/fixtures/permission-harvest"
  MK="$FIXD/mkfixture.py"
  Q="$FIXD/qjson.py"
  # The tool's own default out dir under the redirected HOME, so the one bare `--apply` arm resolves
  # latest.json the way the cc-do payload (which carries no path, §10 B1-5c) has to.
  OUT="$HOME/.claude/autonomy/permission-harvest"
  PROP="$OUT/latest.json"
  python3 "$MK" "$HOME" --scenario base
  export CC_PERMARCHIVE_DIR="$HOME/.claude/autonomy/permission-archive"
  export GIT_CONFIG_NOSYSTEM=1
  unset CLAUDE_CONFIG_DIR CC_PERMHARVEST_OUT
  # The five forks in discovery (sorted) order — "copy 3" below is .claude-next2 — plus project A's
  # local file: every path a correct apply may touch, and the population `unchanged` checks.
  FLEET=("$HOME/.claude/settings.json" "$HOME/.claude-next/settings.json"
         "$HOME/.claude-next2/settings.json" "$HOME/.claude-next3/settings.json"
         "$HOME/.claude-secondary/settings.json")
  PROJA="$HOME/Development/proj-a/.claude/settings.local.json"
  ALL=("${FLEET[@]}" "$PROJA")
}

teardown() {
  # The write-failure arm locks a directory; bats cannot sweep a 555 tree.
  chmod -R u+w "$HOME" 2>/dev/null || true
}

have_tool() { [ -f "$HARVEST" ] || skip "bin/cc-permission-harvest not present (unit C2)"; }

q() { python3 "$Q" "$PROP" "$@"; }

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# Digest every target into a snapshot; `unchanged` then fails on the first byte that moved. A
# symlinked target digests through the link, which is the file the tool must have written.
snap() {
  local f
  : > "$BATS_TEST_TMPDIR/snap"
  for f in "${ALL[@]}"; do printf '%s %s\n' "$(sha "$f")" "$f" >> "$BATS_TEST_TMPDIR/snap"; done
}

unchanged() {
  local line
  while IFS= read -r line; do
    [ "$(sha "${line#* }")" = "${line%% *}" ] || return 1
  done < "$BATS_TEST_TMPDIR/snap"
}

# One fresh 30-day proposal into the default out dir. Asserts the fleet rule the write arms key on
# is actually proposed, so a tool that proposes nothing fails HERE and not as a mysterious no-op.
gen() {
  have_tool
  run python3 "$HARVEST" 30 --json --out "$OUT"
  [ "$status" -eq 0 ]
  [ -f "$PROP" ]
  run q has "Bash(gh pr view:*)"
  [ "$status" -eq 0 ]
}

# `env -u` flags precede the assignments: BSD env reads the first NAME=VALUE as the end of options.
apply() { # $@ = [PROPOSAL] [--only R] [--skip R] [--target P]
  run env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CONFIRM=1 \
      python3 "$HARVEST" --apply "$@"
}

check() {
  run env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CONFIRM \
      python3 "$HARVEST" --check "$@"
}

allow_has() { # <settings file> <rule> — exit 0 iff the rule is in permissions.allow
  python3 -c 'import json, sys
allow = (json.load(open(sys.argv[1])).get("permissions") or {}).get("allow") or []
sys.exit(0 if sys.argv[2] in allow else 1)' "$1" "$2"
}

allow_n() { # <settings file> — the allow count
  python3 -c 'import json, sys
print(len((json.load(open(sys.argv[1])).get("permissions") or {}).get("allow") or []))' "$1"
}

# Clone the honest `gh pr view` entry under another rule name, so the tampered document is
# well-formed in every field but the one under test.
inject() { # <src proposal> <dst> <rule>
  python3 - "$1" "$2" "$3" <<'PY'
import copy, json, sys
doc = json.load(open(sys.argv[1]))
src = next(e for e in doc["proposed"] if e["rule"] == "Bash(gh pr view:*)")
entry = copy.deepcopy(src)
entry["rule"] = sys.argv[3]
doc["proposed"].append(entry)
with open(sys.argv[2], "w") as fh:
    json.dump(doc, fh, indent=2)
PY
}

# A REAL linked worktree at a `.worktrees` path — the shape the scope classifier reads AND the one
# `git rev-parse` reads, so the refusal fires whichever the tool asks — holding copy 4's real bytes
# behind a symlink.
wt_target() {
  local src="$HOME/wt-src" wt="$HOME/Development/.worktrees/wt-fx"
  git init -q "$src"
  git -C "$src" -c user.name=fx -c user.email=fx@example.test commit -q --allow-empty -m init
  git -C "$src" worktree add -q "$wt"
  mkdir -p "$wt/cfg"
  mv "$HOME/.claude-next3/settings.json" "$wt/cfg/settings.json"
  ln -s "$wt/cfg/settings.json" "$HOME/.claude-next3/settings.json"
}

# ── THE ANCHOR — the one arm that must never skip ────────────────────────────────────────────────
@test "the harvester exists and is executable" {
  [ -f "$HARVEST" ]
  [ -x "$HARVEST" ]
}

# ── --check: the read-only preview that doubles as the backlog row's falsifier ───────────────────

@test "--check exits 0 while at least one proposed rule would apply, and writes nothing" {
  gen; snap
  check "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(gh pr view:*)"* ]] || false
  unchanged
  run bash -c 'ls "$1"/.claude*/settings.json.permharvest-bak-* 2>/dev/null' _ "$HOME"
  [ "$status" -ne 0 ]
}

@test "--check exits 1 when nothing would apply — the falsifier that closes the queue row" {
  have_tool
  python3 "$MK" "$HOME" --scenario covered
  run python3 "$HARVEST" 30 --json --out "$OUT"
  [ "$status" -eq 0 ]
  check "$PROP"
  [ "$status" -eq 1 ]
}

@test "--check after a successful apply exits 1: the proposal has been consumed" {
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  check "$PROP"
  [ "$status" -eq 1 ]
}

@test "a proposal whose tool.sha is not the running tool's is named as a mismatch, never silently re-gated" {
  gen
  local stale="$BATS_TEST_TMPDIR/stale.json"
  python3 - "$PROP" "$stale" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["tool"]["sha"] = "0" * 40
with open(sys.argv[2], "w") as fh:
    json.dump(doc, fh, indent=2)
PY
  check "$stale"
  # A warning, never a gate: the check still runs (exit 0 while something applies) and the line
  # names BOTH shas, so the operator can see which tool wrote the proposal they are approving.
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool.sha"*"mismatch"* ]] || false
  [[ "$output" == *"0000000000"* ]] || false
}

# ── CONSENT — CONFIRM=1 from cc-do's typed yes, and the in-session courtesy refusal ──────────────

@test "--apply without CONFIRM=1 behaves as --check and writes nothing" {
  gen; snap
  run env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CONFIRM \
      python3 "$HARVEST" --apply "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(gh pr view:*)"* ]] || false
  unchanged
  run bash -c 'ls "$1"/.claude*/settings.json.permharvest-bak-* 2>/dev/null' _ "$HOME"
  [ "$status" -ne 0 ]
}

@test "CLAUDECODE=1 refuses --apply with the courtesy message, exit 4, nothing written" {
  gen; snap
  # The honour-system half: the tool reads the marker the agent could unset. The chokepoint that
  # cannot be unset is validate-bash.sh's deny arm (unit C3's suite). Either witness alone refuses.
  run env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CLAUDECODE=1 CONFIRM=1 \
      python3 "$HARVEST" --apply "$PROP"
  [ "$status" -eq 4 ]
  [[ "$output" == *[Ss]ession* || "$output" == *CLAUDECODE* || "$output" == *[Aa]gent* ]] || false
  unchanged
  run env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID=fx CONFIRM=1 \
      python3 "$HARVEST" --apply "$PROP"
  [ "$status" -eq 4 ]
  unchanged
}

# ── THE WRITE — five forks, atomically, with a backup of each ───────────────────────────────────

@test "CONFIRM=1 appends the rule to all five fleet forks, identically, with a backup of each" {
  gen; snap
  apply "$PROP"
  [ "$status" -eq 0 ]
  local f
  for f in "${FLEET[@]}"; do
    allow_has "$f" "Bash(gh pr view:*)"
    # …behind the entries that were there, in their order — an append, never a sorted rewrite.
    [ "$(python3 -c 'import json, sys
print(json.load(open(sys.argv[1]))["permissions"]["allow"][:5])' "$f")" = \
      "$(python3 -c 'import json, sys
print(json.load(open(sys.argv[1]))["permissions"]["allow"][:5])' "$FIXD/settings-fleet.json")" ]
    # Five forks, one result: a write that reached four is the "silently applies to one account"
    # failure the plan names.
    cmp -s "$f" "${FLEET[0]}"
    # …and the backup is the pre-apply bytes, exactly.
    run bash -c 'ls "$1".permharvest-bak-*' _ "$f"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    grep -q -F "$(sha "${lines[0]}") $f" "$BATS_TEST_TMPDIR/snap"
  done
}

@test "the written file keeps every other key, 2-space indent and a trailing newline" {
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  local f="${FLEET[0]}"
  python3 - "$f" <<'PY'
import json, sys
o = json.load(open(sys.argv[1]))
p = o["permissions"]
assert p["deny"] == ["Bash(git push --force:*)"], p["deny"]
assert "Bash(git push:*)" in p["ask"] and "Bash(git stash drop:*)" in p["ask"], p["ask"]
assert p["defaultMode"] == "auto", p.get("defaultMode")
assert o["enabledMcpjsonServers"] == ["ms365"], o.get("enabledMcpjsonServers")
PY
  [ -z "$(tail -c1 "$f")" ]
  grep -q '^  "permissions": {' "$f"
}

@test "a second CONFIRM=1 run is a no-op: bytes unchanged, no second backup" {
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  snap
  apply "$PROP"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  unchanged
  run bash -c 'ls "$1".permharvest-bak-*' _ "${FLEET[0]}"
  [ "${#lines[@]}" -eq 1 ]
}

@test "a bare --apply resolves latest.json under the default out dir, as the cc-do payload must" {
  gen
  # The queue row's --run carries no path and no rule text (§10 B1-5c): the tool finds its own.
  run env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CONFIRM=1 \
      python3 "$HARVEST" --apply
  [ "$status" -eq 0 ]
  allow_has "${FLEET[0]}" "Bash(gh pr view:*)"
}

@test "the apply prints every rule with its evidence and every per-file diff — the record the yes was given over" {
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(gh pr view:*)"* ]] || false
  [[ "$output" == *"gh pr view 12"* ]] || false
  local f
  for f in "${ALL[@]}"; do
    [[ "$output" == *"${f#"$HOME"}"* ]] || false
  done
}

# ── proposed ∩ fresh — tampering shrinks the set, decay is a named drop ─────────────────────────

@test "a rule injected into proposed[] that the fresh run does not produce is dropped by name, exit 0" {
  gen; snap
  local tampered="$BATS_TEST_TMPDIR/tampered.json"
  inject "$PROP" "$tampered" "Bash(zzinjected:*)"
  apply "$tampered"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(zzinjected:*)"* ]] || false
  local f
  for f in "${ALL[@]}"; do
    run allow_has "$f" "Bash(zzinjected:*)"
    [ "$status" -ne 0 ]
  done
  # …while the honest rule beside it still lands: the drop is per-rule, not per-run.
  allow_has "${FLEET[0]}" "Bash(gh pr view:*)"
}

@test "a tampered ACE rule exits 4 and every target is byte-identical" {
  gen; snap
  # `Bash(bash:*)` is the 2026-08-23 refuted set. The fresh run refuses it at ACE_CLASS, and a
  # gate failure at apply time is exit 4 — the whole run, all-or-nothing, so even the honest rule
  # beside it is not written.
  local tampered="$BATS_TEST_TMPDIR/tampered.json"
  inject "$PROP" "$tampered" "Bash(bash:*)"
  apply "$tampered"
  [ "$status" -eq 4 ]
  [[ "$output" == *"ACE_CLASS"* ]] || false
  unchanged
}

@test "a rule whose evidence aged out of the window is a named drop, exit 0, and is not written" {
  gen
  # Same proposal, a fixture whose archive no longer carries a single `gh pr view` row: MIN_EVIDENCE
  # fails on the fresh run. That is decay, not tampering, and the exit code is the distinction.
  local keep="$BATS_TEST_TMPDIR/keep.json"
  cp "$PROP" "$keep"
  python3 "$MK" "$HOME" --scenario decayed
  snap
  apply "$keep"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(gh pr view:*)"* ]] || false
  local f
  for f in "${FLEET[@]}"; do
    run allow_has "$f" "Bash(gh pr view:*)"
    [ "$status" -ne 0 ]
  done
}

# ── ATOMICITY — a failure on one fork restores every fork ───────────────────────────────────────

@test "a write failure on copy 3 exits 5 and leaves every copy byte-identical" {
  [ "$(id -u)" -ne 0 ] || skip "mode bits do not apply to uid 0"
  gen; snap
  # A 444 FILE alone does not stop an atomic os.replace — rename needs the DIRECTORY writable — so
  # the directory is locked too, and whichever step the tool takes first (backup, stage, replace)
  # fails there. teardown unlocks it.
  chmod 444 "$HOME/.claude-next2/settings.json"
  chmod 555 "$HOME/.claude-next2"
  apply "$PROP"
  [ "$status" -eq 5 ]
  chmod 755 "$HOME/.claude-next2"
  unchanged
}

# ── REALPATH — symlinks are written through; a git worktree behind one is refused unless named ──

@test "a symlinked fleet target is written through its realpath and the link survives" {
  have_tool
  mkdir -p "$HOME/cfg-real"
  mv "$HOME/.claude-next3/settings.json" "$HOME/cfg-real/settings.json"
  ln -s "$HOME/cfg-real/settings.json" "$HOME/.claude-next3/settings.json"
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  # An os.replace aimed at the LINK path would leave a regular file here and strand the real one.
  [ -L "$HOME/.claude-next3/settings.json" ]
  [ "$(readlink "$HOME/.claude-next3/settings.json")" = "$HOME/cfg-real/settings.json" ]
  allow_has "$HOME/cfg-real/settings.json" "Bash(gh pr view:*)"
  cmp -s "$HOME/cfg-real/settings.json" "$HOME/.claude/settings.json"
}

@test "a fleet target whose realpath is inside a git worktree is refused, exit 4, nothing written" {
  have_tool
  wt_target
  gen; snap
  apply "$PROP"
  [ "$status" -eq 4 ]
  [[ "$output" == *".claude-next3"* || "$output" == *"wt-fx"* ]] || false
  unchanged
}

@test "a worktree-resident target named by --target is written" {
  have_tool
  wt_target
  gen
  apply "$PROP" --target "$HOME/.claude-next3/settings.json"
  [ "$status" -eq 0 ]
  allow_has "$HOME/Development/.worktrees/wt-fx/cfg/settings.json" "Bash(gh pr view:*)"
}

# ── PROJECT-LOCAL — the consolidation lands in the file the acceptances came from ───────────────

@test "consolidation writes Bash(gh pr view:*) into project A's local file and prunes both exact entries" {
  gen
  apply "$PROP"
  [ "$status" -eq 0 ]
  allow_has "$PROJA" "Bash(gh pr view:*)"
  run allow_has "$PROJA" "Bash(gh pr view 12 --json state)"
  [ "$status" -ne 0 ]
  run allow_has "$PROJA" "Bash(gh pr view 7 --json title)"
  [ "$status" -ne 0 ]
  # The residue is untouched: no gate-passing prefix retires ssh -i, and a prune is only ever of
  # entries a prefix in the SAME file provably shadows.
  allow_has "$PROJA" "Bash(ssh -i $HOME/.ssh/id_fx root@host-a uptime)"
  allow_has "$PROJA" "Bash(ssh -i $HOME/.ssh/id_fx root@host-b uptime)"
  allow_has "$PROJA" "Bash(ssh -i $HOME/.ssh/id_fx root@host-c uptime)"
  allow_has "$PROJA" "Bash(zzfmt check:*)"
  run bash -c 'ls "$1".permharvest-bak-*' _ "$PROJA"
  [ "$status" -eq 0 ]
  # …and the fleet did not receive the project's prefix twice over: the fleet copy came from the
  # archive (2 projects), the local one from the acceptances — both legitimate, each once.
  [ "$(allow_n "$PROJA")" -le 7 ]
}

# ── --only / --skip — edit the set without editing JSON ─────────────────────────────────────────

@test "--only restricts the fleet write to the named rule" {
  gen
  apply "$PROP" --only "Bash(gh pr view:*)"
  [ "$status" -eq 0 ]
  local f
  for f in "${FLEET[@]}"; do
    allow_has "$f" "Bash(gh pr view:*)"
    [ "$(allow_n "$f")" -eq 6 ]
  done
}

@test "--skip removes the named rule from the fleet write" {
  gen
  apply "$PROP" --skip "Bash(gh pr view:*)"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
  local f
  for f in "${FLEET[@]}"; do
    run allow_has "$f" "Bash(gh pr view:*)"
    [ "$status" -ne 0 ]
  done
}

# ── --falsify: the QUEUE PROBE, and the inverse of --check (added 2026-09-09) ────────────────────
#
# `--check` is the human preview and exits 0 when there IS work. `cc-premise.run_falsifier` reads a
# stored probe's exit 0 as "the condition this row was filed for is GONE" and its 6-hourly sweep
# then closes the row — so wiring `--check` as the weekly row's `--falsifier` retired the operator's
# apply step while the apply was still pending, and left a decayed row open forever. These arms pin
# the two flags as inverses on the SAME state, which is the property a string comparison in the
# wiring suite structurally cannot see.

falsify() {
  run env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CONFIRM \
      python3 "$HARVEST" --falsify "$@"
}

@test "--falsify and --check are INVERSES on the same state, before and after the apply" {
  gen
  # before: work outstanding
  check "$PROP"; [ "$status" -eq 0 ]
  falsify "$PROP"; [ "$status" -eq 1 ]
  [[ "$output" == *"outstanding"* ]] || false
  apply "$PROP"
  [ "$status" -eq 0 ]
  # after: nothing left. The senses swap, together.
  check "$PROP"; [ "$status" -eq 1 ]
  falsify "$PROP"; [ "$status" -eq 0 ]
  [[ "$output" == *"nothing outstanding"* ]] || false
}

@test "--falsify writes nothing and reads no archive — it is the probe, not the pipeline" {
  gen; snap
  falsify "$PROP"
  [ "$status" -eq 1 ]
  unchanged
  run bash -c 'ls "$1"/.claude*/settings.json.permharvest-bak-* 2>/dev/null' _ "$HOME"
  [ "$status" -ne 0 ]
  # the archive is the 1,045-second half; the probe must answer without it (cc-premise's bound is
  # 20 s and a timed-out probe fails OPEN, i.e. answers nothing at all).
  rm -rf "$CC_PERMARCHIVE_DIR"
  falsify "$PROP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outstanding"* ]] || false
}

@test "--falsify FAILS CLOSED: a missing or unreadable proposal leaves the row live, never closes it" {
  have_tool
  falsify "$BATS_TEST_TMPDIR/no-such-proposal.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CANNOT TELL"* ]] || false
  printf 'not json at all' > "$BATS_TEST_TMPDIR/broken.json"
  falsify "$BATS_TEST_TMPDIR/broken.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreadable"* ]] || false
  # a well-formed proposal naming a target that cannot be read is also "cannot tell", not "gone"
  gen
  python3 - "$PROP" "$BATS_TEST_TMPDIR/badtarget.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["consolidation"] = [{"file": "/nonexistent/dir/.claude/settings.local.json",
                         "prefix": "Bash(gh pr view:*)", "shadows": [], "present": False}]
doc["proposed"] = []
json.dump(doc, open(sys.argv[2], "w"))
PY
  falsify "$BATS_TEST_TMPDIR/badtarget.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CANNOT TELL"* ]] || false
}

@test "--falsify with no argument resolves latest.json, so a DECAYED week closes its own stale row" {
  # §5/B3-1's self-retraction, kept reachable without a 17-minute run: the weekly job rewrites
  # latest.json, so a week whose fresh proposal names nothing leaves nothing outstanding.
  gen
  falsify
  [ "$status" -eq 1 ]
  python3 - "$PROP" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["proposed"] = []
doc["consolidation"] = []
json.dump(doc, open(sys.argv[1], "w"))
PY
  falsify
  [ "$status" -eq 0 ]
}

@test "--check, --apply and --falsify are mutually exclusive" {
  have_tool
  run python3 "$HARVEST" --check --falsify
  [ "$status" -eq 2 ]
  run python3 "$HARVEST" --apply --falsify
  [ "$status" -eq 2 ]
}

# ── THE PROJECT-LOCAL SAFETY GATE — the REFUSAL side, which no arm could reach ───────────────────
#
# §3.3: "project-local = the .claude/settings.local.json a consolidation cluster came from (must be
# gitignored — `git check-ignore`; a tracked `.claude/settings.json` needs an explicit `--target`)".
# Both refusals are exit-4, all-or-nothing paths, and the fixture supplies exactly ONE project file
# which mkfixture makes gitignored — so only the PASS side ever ran and the gate that stops this
# tool writing a TRACKED permission file could not fail any test.

@test "a project settings.local.json that is NOT gitignored is refused (exit 4) and nothing is written" {
  gen
  : > "$HOME/Development/proj-a/.gitignore"          # the file is now tracked-or-unignored
  snap
  apply "$PROP"
  [ "$status" -eq 4 ]
  [[ "$output" == *"not gitignored"* ]] || false
  [[ "$output" == *"target refused"* ]] || false
  unchanged                                          # all-or-nothing: the FLEET is untouched too
}

@test "a project .claude/settings.json (the TRACKED name) needs an explicit --target, and says so" {
  have_tool
  local tracked="$HOME/Development/proj-a/.claude/settings.json"
  mv "$PROJA" "$tracked"
  ALL=("${FLEET[@]}" "$tracked")
  run python3 "$HARVEST" 30 --json --out "$OUT"
  [ "$status" -eq 0 ]
  snap
  apply "$PROP"
  [ "$status" -eq 4 ]
  [[ "$output" == *"needs an"*"--target"* ]] || false
  unchanged
  # …and NAMING it is the sanctioned route: the same run with --target writes it.
  apply "$PROP" --target "$tracked"
  [ "$status" -eq 0 ]
  allow_has "$tracked" "Bash(gh pr view:*)"
}
