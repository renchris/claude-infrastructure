# How the repo bounds a single session's use of the frontier (Fable) tier

The whole bound is one PreToolUse hook, `hooks/frontier-spawn-gate.sh`, backed by one SSOT key. In the repo's shipped template only the Agent arm is registered. The session-fire arm is inert until c10 migration `0029` is run by an operator.

The brief names `/tmp/o55probe-repo-47c3317eb`. I read `/tmp/s55/repo-47c3317eb` instead, as the task instructions say.

## 1. The enforcer and the two carriers

**Files.**
- `hooks/frontier-spawn-gate.sh` is the only implementer. Its header says "PreToolUse (Agent + Bash matchers)" (`hooks/frontier-spawn-gate.sh:2`).
- I grepped `hooks lib scripts bin` for `frontier-gate-`. The only hit is the gate's counter path at `hooks/frontier-spawn-gate.sh:133`, so no other file reads or writes the counter.

**Path split.** The gate branches on `.tool_name`, not on the registered matcher.
- `hooks/frontier-spawn-gate.sh:85`: `tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' ...)"`
- `hooks/frontier-spawn-gate.sh:88`: `path=agent`
- `hooks/frontier-spawn-gate.sh:90-91`: `if [ "${tool_name:-}" = "Bash" ]; then path=session`

**Agent arm.**
- It reads `.tool_input.model`: `hooks/frontier-spawn-gate.sh:102`, `jq -r '.tool_input.model // empty'`.
- An empty model exits 0 (`hooks/frontier-spawn-gate.sh:106`: `[ -n "${req_model:-}" ] || exit 0`).
- Any `tool_name` other than `Bash` takes this branch (`hooks/frontier-spawn-gate.sh:88,99`).

**Session arm.** It reads `.tool_input.command` (`hooks/frontier-spawn-gate.sh:94`) and calls `req_model="$(frontier_fire_model "$cmd")" || exit 0` (`hooks/frontier-spawn-gate.sh:97`). `frontier_fire_model` has three parts:
- Dry-run exclusion, `hooks/frontier-spawn-gate.sh:62`: `case "$c" in *--dry-run*) return 1 ;; esac`
- Entrypoint requirement, `hooks/frontier-spawn-gate.sh:67`: `printf '%s' "$c" | grep -qE '(^|[[:space:]]|[;&|(])([A-Za-z0-9_./~$"{}-]*/)?(handoff-fire\.sh|claude|claude-latest|claude-next[0-9]*|claude[0-9]+)([[:space:]]|$)' || return 1`
- Model extraction, `hooks/frontier-spawn-gate.sh:75`: `grep -oE -- '--model[= ]+[A-Za-z0-9._-]+' | sed -E 's/^--model[= ]+//'`. It checks every `--model` occurrence in a loop (`hooks/frontier-spawn-gate.sh:71-73`).

**The frontier predicate.** Both arms use the same function, `is_frontier_model`, and the same call site (`hooks/frontier-spawn-gate.sh:110`: `is_frontier_model "$req_model" || exit 0`).
```
hooks/frontier-spawn-gate.sh:51-54
  case "${1:-}" in
    fable|claude-fable-5*) return 0 ;;
    "$fmodel") [ -n "${fmodel:-}" ] && return 0 ;;
  esac
```
- `$fmodel` is `frontier_access.model` from the SSOT (`hooks/frontier-spawn-gate.sh:39-40`).
- The session arm keys on `--model` only. A launcher name is deliberately not a signal (`hooks/frontier-spawn-gate.sh:25-32`; code at `:75`).

## 2. Where the number comes from

**Config file.**
- The gate reads `CFG="${FRONTIER_GATE_CFG:-$HOME/.claude/model-config.yaml}"` (`hooks/frontier-spawn-gate.sh:36`). That is the *live* copy, not the repo copy.
- A missing file exits 0 (`hooks/frontier-spawn-gate.sh:37`).

**Cap.**
- The key is `frontier_discovery_budget.max_fable_spawns_per_session`.
- Its literal value is `6` (`model-config.yaml:939`).

**Parsing expression** (`hooks/frontier-spawn-gate.sh:120-121`):
```
cap="$(grep -m1 'max_fable_spawns_per_session:' "$CFG" | awk '{print $2}')"
case "${cap:-}" in ''|*[!0-9]*) cap=6 ;; esac
```
- **Scoping:** it is not scoped to the `frontier_discovery_budget:` block. It takes the first matching line in the whole file.
- **Today:** I grepped `model-config.yaml` for `max_fable_spawns_per_session:`. The only hit is `model-config.yaml:939`, so it is safe today.
- **Contrast:** the window fields are scoped to the `frontier_access:` block by `sed -n '/^frontier_access:/,/^[a-z_]/p'` (`hooks/frontier-spawn-gate.sh:39`).
- **Fallback:** an empty or non-numeric read gives `cap=6`, not unbounded.
- **Zero:** `0` is numeric and passes, so it refuses everything (`cnt >= cap` at `:136`).

**Runtime modifier.**
- The SSOT key is `frontier_discovery_budget.reserve_dates`. It is currently `""` (`model-config.yaml:949`), so it never fires today.
- It is read with `grep -m1 'reserve_dates:' "$CFG" | sed 's/.*reserve_dates:[[:space:]]*"\{0,1\}//; s/".*//'` (`hooks/frontier-spawn-gate.sh:125`). That is also unscoped, and `model-config.yaml:949` is the only hit.
- The arithmetic is at `hooks/frontier-spawn-gate.sh:126-128`:
```
case " ${reserve:-} " in
  *" $today "*) cap=$(( cap / 2 )); [ "$cap" -lt 1 ] && cap=1 ;;
esac
```
- So on a listed date the cap is halved with integer division and floored at 1. With 6 it becomes 3.
- `tests/frontier-spawn-gate.bats:161-167` pins this: the cap is 3 and the refusal text says `(3/3`.

**Stale-justification comment.** `model-config.yaml:939-948` explains the 6 as a tightening "for the scarce 2026-07-01→07-07 window". The same file says that window era is closed and Fable is permanent (`model-config.yaml:676-681`). The value is what the code reads. The rationale is stale.

## 3. Counting and storage

**State file.** `cnt_file="${TMPDIR:-/tmp}/frontier-gate-${sid}.count"` (`hooks/frontier-spawn-gate.sh:133`).

**Key.**
- The key is `.session_id` from the hook payload (`hooks/frontier-spawn-gate.sh:130`).
- `path` is not in the filename.
- A fired session is a new process with its own `session_id`. By construction of `:130-133` it starts at 0, so the cap bounds fires per launching session, not per ladder.

**Unresolvable key.**
- The jq expression falls back to `"nosid"`: `jq -r '.session_id // "nosid"'` (`hooks/frontier-spawn-gate.sh:130`).
- If jq is absent, `sid` is never set, and `sid="${sid:-nosid}"` (`hooks/frontier-spawn-gate.sh:132`) applies.
- Every such session then shares one `frontier-gate-nosid.count`.
- I grepped `tests/frontier-spawn-gate.bats` for `nosid`. No test pins it.

**Write timing.**
- The read is at `hooks/frontier-spawn-gate.sh:134-135`.
- The refusal check is at `:136`.
- The write is at `hooks/frontier-spawn-gate.sh:144`: `echo $((cnt + 1)) > "$cnt_file"`, followed by `exit 0` at `:145`.
- The write comes before the tool runs, and it happens as part of the allow.
- A refused call exits 2 at `:142` before any write, so refusals are not counted. This is the opposite of `hooks/agent-teams-enforce.sh:367-369`, which charges attempts.

**No refund.**
- I grepped the gate for `refund`. There are no hits.
- Nothing decrements the counter, and `:133` is the only reference to the file anywhere in `hooks lib scripts bin`.
- The SSOT states the consequence: a premature spawn would "burn a per-session spawn-count slot the gate can't refund" (`model-config.yaml:690-691`).
- The read-modify-write has no lock (`:134-144`), so parallel spawns can under-count. That is my reading of the code, not something I tested.

**One shared budget.**
- Code: one `cnt_file`, with no path component (`hooks/frontier-spawn-gate.sh:133`).
- Refusal text: "Agent spawns and frontier session FIRES share one budget" (`hooks/frontier-spawn-gate.sh:138`).
- Test: `tests/frontier-spawn-gate.bats:107-111` (case 8). It sends `agent_call H fable` and then `bash_call H 'handoff-fire.sh --model fable'`, and asserts `[ "$(count_of H)" = 2 ]`.

## 4. At and over the cap

- **Exit code:** 2 (`hooks/frontier-spawn-gate.sh:142`).
- **Stream:** stderr, via `>&2` on `:138` and `:140`.
- **Trigger:** `[ "$cnt" -ge "$cap" ]` (`:136`).

**Session-path clause** (`hooks/frontier-spawn-gate.sh:138`):
> "Do NOT retry: fire this session on the default tier instead (--model opus — handoff-fire resolves it to versions.opus_latest, and to the binary's own alias on a recycle), or park the remaining hole(s) in docs/research/FRONTIER_HOLES.md …"

**Agent-path clause** (`hooks/frontier-spawn-gate.sh:140`):
> "Do NOT retry: park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's wrap-up batch runs them."

**Why they differ.**
- A blocked fire must not be told to "re-spawn this agent", because that names a tool the operator did not use (`hooks/frontier-spawn-gate.sh:81-82`).
- The session text uses the family alias `opus`, not a full id, because an old pane refuses full ids. The test comment says so (`tests/frontier-spawn-gate.bats:152-155`).
- Test 13 asserts `--model opus ` is present, `--model claude-opus-` is absent, and `Re-spawn this agent` is absent (`tests/frontier-spawn-gate.bats:154-158`). Test 12 pins the agent text (`:139-145`).

## 5. The window

**Fields read** (`hooks/frontier-spawn-gate.sh:112-114`):
- `active` comes from `grep -m1 '  active:'`.
- `end` comes from `grep -m1 '  end:'` and then `tr -d '"'`.
- `fallback` comes from `grep -m1 '  fallback:'`.
- `model` is read earlier at `:40`.
- The gate never reads `permanent`. I grepped it for `permanent` and got no hits.

**Comparison** (`hooks/frontier-spawn-gate.sh:117`):
```
if [ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]; then
```
This is a lexicographic string compare of ISO dates. The window is open when `today <= end`. `today` is `$(date +%F)` (`:115`).

**When shut.**
- Any other state falls through to the refusal at `hooks/frontier-spawn-gate.sh:148-153` and exits 2 (`:153`).
- The test fixtures for the shut window are `tests/frontier-spawn-gate.bats:170-183` (cases 15 and 16).

**Reachable in production today? No.**
- The SSOT has `active: true` (`model-config.yaml:687`) and `end: "2099-12-31"` (`model-config.yaml:682`).
- The `permanent: true` at `model-config.yaml:676` is not what keeps it open. `active` and `end` do.
- A hand-edit of `active`, an empty or garbled `end`, or a `fallback` change could reach the branch. The SSOT comment says it "cannot fire while `permanent: true` holds" (`model-config.yaml:701-702`). That is true only because of `active` and `end`.

**What the refusal advises versus the SSOT.**
- The SSOT fallback is `claude-opus-5-5` (`model-config.yaml:699`).
- Session path: `--model ${fallback:-claude-opus-5}` (`hooks/frontier-spawn-gate.sh:149`). This resolves to a full id, `--model claude-opus-5-5`.
- Agent path: `omit model, or model: "opus" → ${fallback:-claude-opus-4-8}` (`hooks/frontier-spawn-gate.sh:151`).
- The hardcoded defaults `claude-opus-5` (`:149`) and `claude-opus-4-8` (`:151`) are stale against the SSOT. They apply only if the `fallback` read comes back empty.
- The session closed-window text contradicts the alias rationale the cap branch encodes. `CLAUDE.global.md:334` says "Pin the ALIAS `opus` by hand while any 2.1.260 session lives — it refuses the full id". The closed branch advises a full id, and the cap branch advises `opus`.
- Test 15 asserts only the substring `--model claude-opus-5` (`tests/frontier-spawn-gate.bats:175`). That matches the fixture's `fallback: claude-opus-5` (`:47`) and would also match `claude-opus-5-5`, so it cannot catch this.

## 6. Kill switches and bypasses

Each row below stops the gate from counting or refusing.

| Bypass | Implementing line |
|---|---|
| SSOT file absent, or `FRONTIER_GATE_CFG` pointed at a nonexistent path | `hooks/frontier-spawn-gate.sh:36-37` (pinned by test 17, `tests/frontier-spawn-gate.bats:186`) |
| Empty command, or garbage or absent `tool_input` | `hooks/frontier-spawn-gate.sh:96` (tests 18-19, `tests/frontier-spawn-gate.bats:194-202`) |
| `--dry-run` anywhere in the command string. It is a substring match, so it also matches inside a quoted prompt. | `hooks/frontier-spawn-gate.sh:62` |
| Command is not a session-launcher entrypoint | `hooks/frontier-spawn-gate.sh:67` |
| Non-frontier `--model` | `hooks/frontier-spawn-gate.sh:73,110` |
| `--model` value not starting with `[A-Za-z0-9._-]`, for example `--model "fable"`. I ran the gate's regex from `:75` through `grep -oE` on `handoff-fire.sh --model "fable" --prompt-file x` and got 0 matches. `frontier_fire_model` then returns 1 and the gate exits 0. | `hooks/frontier-spawn-gate.sh:75,97` |
| Model chosen by env var instead of `--model`. I grepped the gate for `CLAUDE_NEXT_MODEL` and `ANTHROPIC_MODEL` and found nothing. The launcher does read `CLAUDE_NEXT_MODEL` (`model-config.yaml:521-523`, `:553`). | `hooks/frontier-spawn-gate.sh:75` (only `--model` is parsed) |
| Launcher name alone (`--launcher claude-fable3`) is not a signal | `hooks/frontier-spawn-gate.sh:25-32` (code at `:75`) |
| Agent spawn with no `model` (it inherits the parent's) | `hooks/frontier-spawn-gate.sh:106` |
| jq absent: `tool_name` stays empty (`:84-86`), so a Bash call is treated as the agent path. The fallback grep on the whole payload (`:104`) finds no `"model"` key, so it exits 0 at `:106`. The session arm is silently off. This is my reading of the code, not something I ran. | `hooks/frontier-spawn-gate.sh:84-88,104-106` |
| `TMPDIR` override, or OS cleanup of `/tmp`, resets the counter | `hooks/frontier-spawn-gate.sh:133` |
| Bash matcher not registered | Not a code line. See §7. |
| Registered with `asyncRewake: true` or `timeout > 10`, which the migration's conflict oracle calls "reads registered, gates nothing" | `migrations/0029-frontier-gate-session-path.sh:7,27-30` |

There is no other env var or flag. I grepped the gate for `CC_LADDER`, `refund`, `permanent`, `CLAUDE_NEXT_MODEL` and `ANTHROPIC_MODEL` and got zero hits.

Bad values fail toward a limit, not toward "unbounded":
- A garbled cap becomes 6 (`:121`).
- A garbled counter file becomes 0 (`:135`).

**The `CC_LADDER=off` kill switch.**
- `CLAUDE.global.md:334` says "Kill-switch: `CC_LADDER=off`". `docs/plans/NONLIMIT_RESUME_LADDER.md:840` says it is "read by the fire path, refusing the stage-1→2 recycle".
- I ran `grep -rIn "CC_LADDER" .` across the whole repo. It returned exactly three lines: `CLAUDE.global.md:334`, `docs/plans/NONLIMIT_RESUME_LADDER.md:840` and `:866`.
- I also ran `grep -rIln "CC_LADDER"` over `hooks lib scripts bin launchd tools autonomy commands skills agents`. It returned nothing.
- **No executable file in the repo reads `CC_LADDER`.** It is documentation only.
- Setting it changes nothing about the gate or `handoff-fire.sh`. `scripts/handoff-fire.sh` does have real kill-switch env vars, such as `CC_FIRE_INFLIGHT=off` (`scripts/handoff-fire.sh:9296`), but none is `CC_LADDER`.

## 7. Registration: is the session arm live?

**What registers the gate today.**
- `settings-templates/settings.example.json`, `PreToolUse` (`:100`), the `"matcher": "Agent"` group (`:151`).
- Alongside `agent-teams-enforce.sh`, it lists `~/.claude/hooks/frontier-spawn-gate.sh` with `timeout: 5` (`:160-161`).

**The Bash group.**
- The Bash group at `:102-130` contains `curl-gate.py`, `validate-bash.sh`, `git-worktree-guard.sh`, `keychain-guard.sh` and `rm-safe-allowlist.sh`. This is from a grep of `command` lines in that slice. The next matcher group starts at `:131`.
- I grepped `settings-templates` and `config` for `frontier-spawn-gate`. The only hit is `settings-templates/settings.example.json:160`.
- `install.sh` and `sync.sh` mention `frontier` only in comments (`install.sh:509`, `sync.sh:73`).
- **By default, the Bash (session-fire) arm is unregistered and inert.** The gate's code reads Bash calls, but the harness is never handed one.

**The artifact that would register it.** `migrations/0029-frontier-gate-session-path.sh`, `migration-class: c10` (`:2`).
- c10 means it is staged and waits for an operator. It edits `settings.json` (`:23-25`).
- Its `migration-run:` line is `bash ~/Development/claude-infrastructure/migrations/0029-frontier-gate-session-path.sh` (`:4`).
- `migrations/0029-frontier-gate-session-path.sh:20-21` states the inert-until-registered fact directly.

**Preconditions it asserts before touching anything:**
- `jq` is present (`:65`).
- `${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/frontier-spawn-gate.sh` exists and is executable (`:61,73-77`).
- That live hook contains the string `frontier_fire_model` (`:78-83`). This is checked by content, not by a lag counter.
- Gap: the precondition looks only at the primary dir's hook (`:61`), while the write loop covers five dirs (`:86`).

**Config dirs it writes** (`:86`): `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary`. Per dir:
- It skips a dir with no `settings.json` (`:88`).
- It skips a dir with no PreToolUse Bash group (`:92-95`).
- It skips a dir where the entry is already registered (`:97-102`).

**Write steps:**
1. It backs up the file to `.bak-0029-<timestamp>` (`:104-105`).
2. It appends `{"type":"command","command":"~/.claude/hooks/frontier-spawn-gate.sh","timeout":5}` to the first Bash group (`:112-114`).

**What it verifies afterwards** (`:121-125`), on the temp file before `mv`:
- The gate appears exactly once in the Bash group.
- `asyncRewake` is false.
- `timeout == 5`.
- The Agent entry still appears exactly once.

If verification fails it deletes the temp file, leaves the live file unchanged and sets `rc=1` (`:127-129`).

**The one command to establish live state.** `CLAUDE.global.md:334` prescribes this:
```
jq '[.hooks.PreToolUse[]|select(.matcher=="Bash")|.hooks[]?.command]|any(.=="~/.claude/hooks/frontier-spawn-gate.sh")' ~/.claude/settings.json
```
- `true` means the session arm is live in that one config dir. `false` means it is inert.
- It checks only `~/.claude`, and it uses `any` where the migration's own oracle uses `length == 1` (`0029:6`).
- For the fleet-wide view, `scripts/registration-state.sh [--json] [--only <name-substring>]` reads each migration's `migration-verify:` line across all five config dirs (`scripts/registration-state.sh:131-132`). It reports `registered`, `staged-pending`, `partial` and other verdicts (`:73-84`). `--only 0029` should select this migration. I did not run the script or confirm how `--only` matches.

**Which state is live on any machine?** I cannot tell from this read-only snapshot. `CLAUDE.global.md:334` says the arm waits for the operator to run 0029.

## 8. Stale or contradicting cross-references

I checked each citation against the gate as it stands now. I could see only the cited lines of the research docs. Whether their numbers were right when written I cannot say, since the snapshot has no git history.

| Citation | Where it lands now | Where the code actually is |
|---|---|---|
| `hooks/frontier-spawn-gate.sh:27` → `scripts/handoff-fire.sh:9303-9311` ("the sole source of truth") | `scripts/handoff-fire.sh:9303-9311` is the in-flight claim helper (`hf_inflight_key`, `:9305`). | The `--model`-only oracle is `scripts/handoff-fire.sh:10146-10147`: `FABLE_EFFECTIVE=0` and `case "$MODEL" in claude-fable-5*) FABLE_EFFECTIVE=1`. |
| `model-config.yaml:545` → `hooks/frontier-spawn-gate.sh:30` (`fable\|claude-fable-5*\|"$fmodel")`) | `:30` is a comment line ("haiku. Re-introducing a name arm here …"). | The predicate is split across `hooks/frontier-spawn-gate.sh:52` and `:53`. The single-line form no longer exists. |
| `hooks/agent-teams-enforce.sh:366` → `hooks/frontier-spawn-gate.sh:52-63` ("per-session cap, hard refusal, 'do NOT retry'") | `:52-63` is the tail of `is_frontier_model` and the head of `frontier_fire_model`. | The cap logic is `hooks/frontier-spawn-gate.sh:117-146`. |
| `docs/research/opus55-utilization-2026-09-22/census/L1-census.md:62` (`gate:138`, "tells the session `--model claude-opus-5`") | The line is right, but its claim is stale. | `hooks/frontier-spawn-gate.sh:138` says `--model opus`. Test 13 pins the alias (`tests/frontier-spawn-gate.bats:154-155`). |
| `L1-census.md:63` (`gate:149`, closed-window, dormant) | Lands correctly. | `hooks/frontier-spawn-gate.sh:149` |
| `docs/research/desk-audit-2026-07-18/p15-escalation.md:44` (`gate:59-67`, "exit 2 … past window/cap") | `:59-67` is the `frontier_fire_model` preamble. | Exit 2 is at `hooks/frontier-spawn-gate.sh:142` and `:153`. |
| `docs/research/fable51-vs-opus5-routing-2026-09-16/A6-mechanics.md:245` (`gate:26-38`, "reads `frontier_access.model`, matches …") | `:26-38` is header comment plus `input`/`CFG` setup. | The model read is `:39-40` and the match is `:51-54`. |
| `A6-mechanics.md:500` (`gate:23`, "exits 0 when `tool_input.model` is absent") | `:23` is a comment. | `hooks/frontier-spawn-gate.sh:106` |
| `docs/research/fable51-vs-opus5-routing-2026-09-16/A5-harness.md:357` (`gate:37-69`, "caps ordinary Agent spawns at 6") | `:37-69` is the setup and the two helper functions. | The cap is `hooks/frontier-spawn-gate.sh:120-146`. |

**Doc sentences that are true of the code but false of the live wiring.**
- `hooks/frontier-spawn-gate.sh:2,7-11` describe an "Agent + Bash matchers" gate. The shipped template registers only the Agent matcher (`settings-templates/settings.example.json:151-160`).
- `model-config.yaml:935-937` says the bounds are "hook-enforced" and that the gate "reads this block". That holds for the Agent carrier. For the session carrier it holds only after `0029` is run.
- `CLAUDE.global.md:334` says the gate "counts both carriers against one per-session budget". This is true of the code. The same paragraph then gives the caveat that it is live only once `0029` is run. That is the accurate framing, and it is not a stale claim.
- `docs/plans/NONLIMIT_RESUME_LADDER.md:840` and `CLAUDE.global.md:334` describe `CC_LADDER=off` as a working kill switch. It is false of the code and the wiring alike (§6).
- The gate's own purpose statement at `hooks/frontier-spawn-gate.sh:4-5` is "stale routing after the frontier_access window closes". The window is now permanent (`model-config.yaml:676-687`), so the cap arm is the only part that can fire in production.

**What I did not verify:**
- I did not run any repo script, including the bats suite.
- I did not read the bodies of `hooks/frontier-status.sh` or `hooks/escalation-watch.sh`. `hooks/hook-chain.sh` does not appear in my `grep -il frontier` over `hooks`.
