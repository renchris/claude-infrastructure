Status: the search is done, and this is the write-up. I read the snapshot at `/tmp/s55/repo-47c3317eb`, since the brief's own path `/tmp/o55probe-repo-47c3317eb` isn't the pinned snapshot I was given.

# How the repo bounds a session's use of the frontier (Fable) tier

**Short version.** One hook, `hooks/frontier-spawn-gate.sh`, implements the whole budget. The Agent arm is wired in the default template. The Bash (session-fire) arm is not registered by the template. It only becomes live if the c10 migration `0029` has been run on the operator's machine. The repo snapshot cannot say whether it has been.

## 1. The enforcer

**Files.** Enforcement is entirely in `hooks/frontier-spawn-gate.sh`. It reads the SSOT `model-config.yaml`. The tests are in `tests/frontier-spawn-gate.bats`.

**Carrier split.** The hook reads `tool_name` from stdin (`hooks/frontier-spawn-gate.sh:85`) and defaults to the agent path:
- `path=agent` at `:88`.
- `if [ "${tool_name:-}" = "Bash" ]; then path=session` at `:90-91`.

**Agent arm** (`:99-107`):
- It reads `.tool_input.model` with jq (`:102`).
- Without jq it falls back to a grep for `"model": "…"` (`:104`).
- An empty model exits 0 (`:106`).

**Session arm** (`:92-98`):
- It reads `.tool_input.command` (`:94`).
- An empty command exits 0 (`:96`).
- `req_model="$(frontier_fire_model "$cmd")" || exit 0` (`:97`) then decides the model.

**"Is this the frontier tier"** is the same predicate on both arms (`:110`: `is_frontier_model "$req_model" || exit 0`). It is defined at `:51-54`:

```
case "${1:-}" in
  fable|claude-fable-5*) return 0 ;;
  "$fmodel") [ -n "${fmodel:-}" ] && return 0 ;;
esac
```

`fmodel` comes from the SSOT: `grep -m1 '  model:'` inside the `frontier_access:` block (`:39-40`). Today that key is `claude-fable-5-1` (`model-config.yaml:663`).

**What makes a Bash call a session fire** (`frontier_fire_model`, `:58-78`):
- Exclusion: `case "$c" in *--dry-run*) return 1 ;; esac` (`:62`).
- Entry point: the command must match a launcher regex (`:67`). It is a `grep -qE` for `handoff-fire\.sh|claude|claude-latest|claude-next[0-9]*|claude[0-9]+`, word-anchored, with the optional path prefix `([A-Za-z0-9_./~$"{}-]*/)?`.
- Model: every `--model[= ]+X` occurrence is extracted with `grep -oE -- '--model[= ]+[A-Za-z0-9._-]+'` (`:75`). The call counts if any of them passes `is_frontier_model` (`:71-73`).
- Only `--model` counts. A launcher name is deliberately not a frontier signal (`:25-32`). That mirrors `scripts/handoff-fire.sh:10140-10147`, where `FABLE_EFFECTIVE` is set by `case "$MODEL" in claude-fable-5*) FABLE_EFFECTIVE=1`.

## 2. Where the number comes from

**The cap.** It comes from `model-config.yaml`, key `frontier_discovery_budget.max_fable_spawns_per_session`. The literal today is `6` (`model-config.yaml:938-939`).

**Parsing** (`hooks/frontier-spawn-gate.sh:120-121`):
```
cap="$(grep -m1 'max_fable_spawns_per_session:' "$CFG" | awk '{print $2}')"
case "${cap:-}" in ''|*[!0-9]*) cap=6 ;; esac
```
- The scoping is the whole file, first match. It is not confined to the `frontier_discovery_budget:` block, unlike the `frontier_access` fields, which use `sed` block extraction at `:39`.
- The read fails or is non-numeric, and the fallback is `6`.
- I saw no earlier `max_fable_spawns_per_session:` line in the `model-config.yaml` lines I read. `:517`, `:939` and `:996` were the only mentions in the grep output, and only `:939` has the trailing colon.

**Runtime modifier.** This is the production-support reserve:
- The SSOT key is `frontier_discovery_budget.reserve_dates`. It is `""` today (`model-config.yaml:949`).
- The read is `grep -m1 'reserve_dates:' "$CFG" | sed …` (`hooks/frontier-spawn-gate.sh:125`).
- The arithmetic is `*" $today "*) cap=$(( cap / 2 )); [ "$cap" -lt 1 ] && cap=1 ;;` (`:126-128`). It halves the cap, using integer division, with a floor of 1.
- The match is against a space-padded string. A list must be space-separated, and a comma-separated list would not match. That follows from the pattern and I did not test it.
- With `""` it is currently a no-op. Test 14 pins the halving on the session path (`tests/frontier-spawn-gate.bats:161`).

## 3. Counting and storage

**State file.** It is `cnt_file="${TMPDIR:-/tmp}/frontier-gate-${sid}.count"` (`hooks/frontier-spawn-gate.sh:133`).

**Key.** It is keyed on `session_id` from the hook input (`:130`).

**Unresolved key.** If jq is missing, `sid` is unset. Otherwise `.session_id // "nosid"` applies. Either way `sid="${sid:-nosid}"` (`:130-132`). All key-less callers therefore share one `frontier-gate-nosid.count`.

**Unreadable counter.** A missing or non-numeric counter is treated as 0 (`:134-135`).

**Write timing.** The check `[ "$cnt" -ge "$cap" ]` comes first (`:136`). If the call passes, the counter is written (`:144`: `echo $((cnt + 1)) > "$cnt_file"`), and `exit 0` follows (`:145`). This is at PreToolUse time, before the tool runs.

**Refunds.** There are none.
- `cnt_file` is referenced only at `:133-144`, and nothing decrements it.
- The SSOT comment says a premature spawn would "burn a per-session spawn-count slot the gate can't refund" (`model-config.yaml:690-691`).
- A refused call is never written. It exits 2 before `:144`.

**One budget or two.** There is one shared budget. The same `cnt_file` and the same `$cap` serve both arms, and no code branches on `path` between `:133` and `:144`.
- The session refusal text says "Agent spawns and frontier session FIRES share one budget" (`:138`).
- Test 8 runs an agent spawn and a `handoff-fire.sh --model fable` on the same session id `H` and asserts `count_of H = 2` (`tests/frontier-spawn-gate.bats:107-112`).

## 4. At and over the cap

**Behaviour.** At or over the cap (`cnt >= cap`), the message goes to stderr (`>&2`) and the hook does `exit 2` (`hooks/frontier-spawn-gate.sh:136-142`).

**Wording differs by carrier, because the remedy differs:**
- **Session** (`:138`): "…frontier session FIRES share one budget). Do NOT retry: **fire this session on the default tier instead (--model opus** — handoff-fire resolves it to versions.opus_latest, and to the binary's own alias on a recycle), or park…".
- **Agent** (`:140`): "Do NOT retry: **park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's wrap-up batch runs them.**" This text has no re-fire advice.

**Why.**
- The comment at `:81-82` says a session fire must never be told to "re-spawn this agent", since that names a tool the operator did not use.
- Test 13 asserts the session text contains `--model opus `, does not contain `--model claude-opus-`, and does not contain "Re-spawn this agent" (`tests/frontier-spawn-gate.bats:147-159`).
- Test 12 asserts the agent text contains `cap reached (6/6` and `FRONTIER_HOLES.md` (`:139-145`).

## 5. The window

**Fields read** (`hooks/frontier-spawn-gate.sh:112-114`):
- `active`: `grep -m1 '  active:'`.
- `end`: `grep -m1 '  end:'`, then `tr -d '"'`.
- `fallback`: `grep -m1 '  fallback:'`.

All three are taken from the `frontier_access:` block, which `sed` extracts at `:39`. `permanent` is not read: `grep permanent` on the hook returns nothing.

**Comparison** (`:117`):
```
[ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]
```
This is a lexicographic string comparison of ISO dates.

**Shut window.** If the condition fails, the hook falls to the refusal at `:148-153` and does `exit 2`. That path never touches the counter.

**Reachable today?** No, not with the current SSOT values.
- `active: true` (`model-config.yaml:687`).
- `end: "2099-12-31"` (`:682`).
- `permanent: true` (`:676`), which the hook ignores.
- The SSOT itself says the fallback is "Read only on the window-CLOSED path of frontier-spawn-gate, which cannot fire while `permanent: true` holds" (`:699-702`). That is true only indirectly. The gate never reads `permanent`. It is unreachable because `active` and `end` say so, and flipping either would reopen the path.

**What the closed-window refusal advises, against the SSOT:**
- The SSOT fallback is `claude-opus-5-5` (`model-config.yaml:699`).
- The session branch says `--model ${fallback:-claude-opus-5}` (`hooks/frontier-spawn-gate.sh:149`).
- The agent branch says `${fallback:-claude-opus-4-8}` (`:151`).
- The SSOT value wins whenever `fallback:` is present. The two hardcoded defaults are stale and differ from each other and from the SSOT. They would only surface if `fallback` were missing.
- The test fixture uses `fallback: claude-opus-5` (`tests/frontier-spawn-gate.bats:47`).

## 6. Kill switches and bypasses

**What stops the gate from counting or refusing:**

| Bypass | Line |
|---|---|
| No SSOT file at `${FRONTIER_GATE_CFG:-$HOME/.claude/model-config.yaml}` | `:36-37` (exit 0) |
| `FRONTIER_GATE_CFG` repointed to another file. It is also the test seam. | `:36` |
| `TMPDIR` changed, so the counter lives elsewhere and resets | `:133` |
| Empty `tool_name` (for example jq absent) makes a Bash call take the agent path. A Bash command has no `.tool_input.model`, so the grep fallback usually finds nothing and the call is allowed. | `:83-88`, `:104-106` |
| Empty Bash command | `:96` |
| Any `--dry-run` substring anywhere in the command | `:62` |
| No launcher token matched | `:67` |
| No `--model` flag in the command | `:71-77` |
| Model not in the family (`fable`, `claude-fable-5*`, or the current `$fmodel`) | `:110` |
| Agent spawn with no `tool_input.model` | `:106` |
| Non-numeric or missing counter, reset to 0 | `:135` |
| Window shut: this refuses rather than bypasses | `:148-153` |

**Quoted invocations.** I derived this from the regex (`:67`) and did not test it. A command like `bash -c "handoff-fire.sh --model fable"` puts `"` immediately before the launcher. The leading delimiter class is only `^|whitespace|;&|(`, so it appears not to match. A quoted path like `"…/handoff-fire.sh" --model fable` has a `"` after the token, where whitespace or end is required, so it appears not to match either.

**Hazard from the prefix rule.** The family test is `claude-fable-5*` plus the current SSOT id. A future `claude-fable-6` would pass unless `frontier_access.model` was updated. The comment at `:43-50` describes the same failure class for the 5→5.1 bump.

**The `CC_LADDER=off` kill switch.**
- `CLAUDE.global.md:334` states "Kill-switch: `CC_LADDER=off`".
- I ran `grep -rn "CC_LADDER" --exclude-dir=docs .` over the whole repo. The only hit was `CLAUDE.global.md`.
- No executable file reads it. The hook has no env-var kill switch at all.
- I excluded `docs/` from that grep, so mentions there are not covered.

## 7. Registration: is the session arm live?

**Default template.**
- The frontier gate is registered only under the `"matcher": "Agent"` group of `settings-templates/settings.example.json` (matcher at `:151`, command at `:160`, `timeout` 5).
- The first PreToolUse Bash group (`:102-129`) lists `curl-gate.py`, `validate-bash.sh`, `git-worktree-guard.sh`, `keychain-guard.sh` and `rm-safe-allowlist.sh`. It has no frontier gate.
- A grep for `frontier` in the template returned 2 matches (`grep -c`), consistent with the Agent-group entry.
- The gate's header says "(Agent + Bash matchers)" (`hooks/frontier-spawn-gate.sh:2`). That is true of the code and false of the template wiring.

**The artifact that would register the Bash arm.** It is `migrations/0029-frontier-gate-session-path.sh`, class `c10` (`:2`).
- c10 means "staged, never run": the runner files one operator-owned step and does not run it (`migrations/README.md:68`).
- The migration says it "STAGES and never self-runs" (`0029…:23-25`).

**Preconditions it asserts before touching anything:**
- `jq` is present (`:65`).
- The live hook file exists and is executable (`:73-77`).
- The live hook contains `frontier_fire_model` (`:78-83`). The migration checks this by content, because "landed is not live" (`:67-72`).

**What it writes.**
- The loop covers `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary` and `~/.claude-quaternary` (`:86`).
- It skips any that lack `settings.json`, or lack a PreToolUse Bash group (`:88-95`).
- It skips any that are already registered (`:97-102`).
- It backs up each one first (`:104-105`).
- It appends `{"type":"command","command":"~/.claude/hooks/frontier-spawn-gate.sh","timeout":5}` to the first Bash group (`:112-114`).
- The loop hardcodes `$HOME` dirs. `HOOK_FILE` and the verify line use `CC_CLAUDE_DIR` (`:61`, `:6`).

**What it verifies afterwards (`:121-125`), before the `mv` at `:126`:**
- The Bash entry appears exactly once.
- `asyncRewake` is false.
- `timeout == 5`.
- The Agent entry survived, appearing exactly once.

On failure it leaves the file unchanged and sets `rc=1` (`:127-131`).

**The conflict oracle** (`:7`) flags an existing entry with `asyncRewake` set or `timeout > 10` as `overridden`.

**The one command for a live machine.**
- `scripts/registration-state.sh --only 0029` is the command I'd give.
- It runs `0029`'s declared `migration-verify` once per config dir with `CC_CLAUDE_DIR` set (`scripts/registration-state.sh:149,161-172`).
- It reports `registered` (all dirs), `partial`, `staged-pending` (c10 awaiting the operator, by design), `not-delivered`, `overridden` and so on (`:73-83`, `:174-202`).
- I have not run it and can't from the snapshot.
- `CLAUDE.global.md:334` gives a narrower jq one-liner against `~/.claude/settings.json`. It checks a single config dir.

**I can't say from the repo which state a live machine is in.** By default, and until `0029` is applied, the Bash arm is inert.

## 8. Stale and contradicting cross-references

**Citations that no longer land:**
- `hooks/frontier-spawn-gate.sh:27` cites `scripts/handoff-fire.sh:9303-9311` as the sole-`--model` predicate. Those lines are `CC_FIRE_INFLIGHT` / `hf_inflight_key` code (`scripts/handoff-fire.sh:9295-9310`, which I read). The predicate is now at `:10140-10147`.
- `model-config.yaml:545` cites `hooks/frontier-spawn-gate.sh:30` as the line `fable|"$fmodel")`. Line 30 is a comment. The `case` is now at `:52-53`. It also says "It now reads `fable|claude-fable-5*|"$fmodel")`" (`:548`), which matches the current `:52-53`.
- `hooks/agent-teams-enforce.sh:366` cites `frontier-spawn-gate.sh:52-63` as "per-session cap, hard refusal, 'do NOT retry'". Those lines are the `case` and the start of `frontier_fire_model`. The cap and refusal are at `:120-143`.
- Under `docs/research/` I saw citations that are also off, and did not open each target:
  - `p15-escalation.md:44` cites `:59-67`.
  - `A5-harness.md:357` cites `:37-69`.
  - `A6-mechanics.md:245` and `:500` cite `:26-38` and `:23`.
  - `L1-census.md:62` says line 138 tells the session `--model claude-opus-5`. Line 138 now says `--model opus`. The census line for `:149` is still accurate.

**Doc claims true of the code and false of the live wiring:**
- `CLAUDE.global.md:334` says the hook "counts **both** carriers against one per-session budget… and refuses at `…max_fable_spawns_per_session`". True of the code, false of the default wiring, and the same paragraph flags this itself.
- The same paragraph names the `CC_LADDER=off` kill switch. Nothing reads it (§6).
- `hooks/frontier-spawn-gate.sh:2` says the hook is registered on the Agent and Bash matchers. Only Agent is in the template.
- `model-config.yaml:939-949` still carries the "TIGHTENED 8→6 for the scarce 2026-07-01→07-07 window" rationale, and says `reserve_dates` is "no known live-event reserve in the 07-01→07-07 window". The value `6` is current, but the rationale is stale.
- `migrations/0029…:11` says the tests are "24/24, 4 mutants killed". `grep -c '^@test' tests/frontier-spawn-gate.bats` returns 24, and the mutants are tests 20-23 (`tests/frontier-spawn-gate.bats:214-237`). That one checks out.
