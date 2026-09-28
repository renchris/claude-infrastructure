# How the repo bounds a session's use of the Fable tier

Everything below is read from the files cited. I did not run anything, and I could not inspect a live machine. Paths are relative to the repo root.

## 1. The enforcer

The enforcer is one file, `hooks/frontier-spawn-gate.sh`. Its header says it runs as "PreToolUse (Agent + Bash matchers)" (`hooks/frontier-spawn-gate.sh:2`).

**Carrier split.** Both arms read `.tool_name` (`hooks/frontier-spawn-gate.sh:83-86`). The Bash arm is chosen at `:90-98`:
```
path=agent
if [ "${tool_name:-}" = "Bash" ]; then
  path=session
  ...
  cmd="$(… jq -r '.tool_input.command // empty' …)"
  [ -n "$cmd" ] || exit 0
  req_model="$(frontier_fire_model "$cmd")" || exit 0
else
  req_model="$(… jq -r '.tool_input.model // empty' …)"   # :102
  [ -n "${req_model:-}" ] || exit 0
```
- **Agent arm:** it reads `tool_input.model`. It also has a grep fallback when `jq` is absent (`:104`). An Agent call with no model exits 0 (`:106`).
- **Session arm:** it reads `tool_input.command`.

**"Frontier tier" predicate**, shared by both arms (`:42-56`, called at `:110`):
```
case "${1:-}" in
  fable|claude-fable-5*) return 0 ;;
  "$fmodel") [ -n "${fmodel:-}" ] && return 0 ;;
esac
```
- `fmodel` is `frontier_access.model` from the SSOT (`:39-40`).
- The `claude-fable-5*` prefix exists so the prior id `claude-fable-5` is still counted (`:43-50`).

**Session-arm predicate**, `frontier_fire_model` (`:58-78`):
- A `--dry-run` anywhere in the command returns 1 (`:62`).
- The entry point must match this regex (`:67`):
  ```
  (^|[[:space:]]|[;&|(])([A-Za-z0-9_./~$"{}-]*/)?(handoff-fire\.sh|claude|claude-latest|claude-next[0-9]*|claude[0-9]+)([[:space:]]|$)
  ```
- Then every `--model X` or `--model=X` is extracted with `grep -oE -- '--model[= ]+[A-Za-z0-9._-]+'` (`:75`). Each value goes through `is_frontier_model` (`:73`).
- The launcher name is deliberately not a signal (`:25-31`). `scripts/handoff-fire.sh:10144-10147` has the same rule: `case "$MODEL" in claude-fable-5*) FABLE_EFFECTIVE=1`.

## 2. Where the number comes from

- **SSOT:** `model-config.yaml`, key `frontier_discovery_budget.max_fable_spawns_per_session: 6` (`model-config.yaml:938-939`). The value today is **6**.
- **Parsing expression** (`hooks/frontier-spawn-gate.sh:120`): `cap="$(grep -m1 'max_fable_spawns_per_session:' "$CFG" | awk '{print $2}')"`.
  - It has no block scoping: it takes the first line in the whole file containing that key followed by a colon.
  - The other mentions I found have no colon after the key (`model-config.yaml:517`, `:996`), so they don't match.
  - By contrast, `fmodel`, `active`, `end` and `fallback` are read from the `frontier_access:` block only (`:39`, `:112-114`).
- **Fallback:** `case "${cap:-}" in ''|*[!0-9]*) cap=6 ;; esac` (`:121`). A failed or non-numeric read gives 6, the same as the SSOT value.
- **Runtime modifier:** `reserve_dates`, SSOT key `frontier_discovery_budget.reserve_dates`.
  - It is currently `""` (`model-config.yaml:949`).
  - The hook reads it at `:125`.
  - The arithmetic is at `:126-128`: `*" $today "*) cap=$(( cap / 2 )); [ "$cap" -lt 1 ] && cap=1`.
  - So it is integer division by 2, floored at 1, and applies only when today's date is in the space-separated list.
  - Because the list is empty, it is not active today.

## 3. Counting and storage

- **Path:** `cnt_file="${TMPDIR:-/tmp}/frontier-gate-${sid}.count"` (`:133`).
- **Key:** `sid` is `.session_id` from the hook input (`:130`).
  - If `jq` is missing or `session_id` is absent, it becomes `nosid` (`:130`, `:132`).
  - All such calls then share one `frontier-gate-nosid.count` file.
- **Read:** a missing or non-numeric counter is treated as 0 (`:134-135`).
- **Write timing:**
  - The cap check runs first (`:136`), and refusal exits before any write.
  - The counter is written at `:144`, `echo $((cnt + 1)) > "$cnt_file"`, immediately before `exit 0` at `:145`.
  - So it is incremented at allow time, before the spawn or fire actually happens.
- **Refunds:** none exist.
  - Nothing in the file decrements or rewrites the counter after the allow.
  - The SSOT comment says a failed spawn burns "a per-session spawn-count slot the gate can't refund" (`model-config.yaml:684`, the `active:` history comment).
  - A refused call is never counted, because it exits at `:142` before `:144`.
  - The window-closed branch (`:148-153`) also never writes the counter.
- **One shared budget.** Both carriers use the same `cnt_file` and `cap`; there is no `path` term in `:133`. The refusal text says the same (`:138`).
  - Test 8 pins it: "the two paths share ONE budget — an agent spawn and a fire both advance the same counter". It runs an agent call, then a Bash fire, and asserts `count_of H` equals 2 (`tests/frontier-spawn-gate.bats:107-112`).
  - The test sets `TMPDIR` and `FRONTIER_GATE_CFG` per test (`tests/frontier-spawn-gate.bats:32-34`).

## 4. At and over the cap

- **Exit code and stream:** exit 2, with the message on stderr (`>&2` at `hooks/frontier-spawn-gate.sh:138`, `:140`, `:142`).
- **Session refusal** (`:138`) contains this clause: "Agent spawns and frontier session FIRES share one budget … fire this session on the default tier instead (--model opus …), or park the remaining hole(s) in docs/research/FRONTIER_HOLES.md".
- **Agent refusal** (`:140`) says only "Do NOT retry: park the remaining hole(s) … a later session's wrap-up batch runs them."
- **Why they differ:** the header comment says a blocked session fire must never be told to "re-spawn this agent", a tool the operator didn't use (`:81-82`). The session text offers a re-fire on `--model opus` instead.
- **Tests:** cases 12 and 13 (`tests/frontier-spawn-gate.bats:139`, `:147`).

## 5. The window

- **Fields read:** `active`, `end` and `fallback` from the `frontier_access:` block (`hooks/frontier-spawn-gate.sh:112-114`).
- **Comparison** (`:117`): `[ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]`. It is a lexicographic string compare of `date +%F` against `end`.
- **Shut window:** falls through to the closed-window refusal at `:148-153`, which exits 2.
  - An unset `active` or `end` also counts as shut.
- **Reachable today? No.** `model-config.yaml:676-687` has `permanent: true`, `end: "2099-12-31"` and `active: true`.
  - The SSOT says `end` is a sentinel and the window era is closed (`model-config.yaml:676-682`).
  - So the gate can only reach the shut branch if someone edits the SSOT.
  - Tests 15 and 16 pin that branch with their own config (`tests/frontier-spawn-gate.bats:170`, `:178`).
- **What the refusal advises:**
  - **Session** (`:149`): `--model ${fallback:-claude-opus-5}`.
  - **Agent** (`:151`): `model: "opus" → ${fallback:-claude-opus-4-8}`.
  - **SSOT** fallback is `claude-opus-5-5` (`model-config.yaml:696`).
  - Both hardcoded defaults are stale against the SSOT. They only surface if `fallback` is unreadable. The default is also inconsistent between the two arms.

## 6. Kill switches and bypasses

Each of these makes the gate not count or not refuse:

| Bypass | Line |
|---|---|
| `FRONTIER_GATE_CFG` pointing to a missing file, or `~/.claude/model-config.yaml` absent, means silent exit 0 | `hooks/frontier-spawn-gate.sh:36-37` |
| Empty Bash command | `:96` |
| `--dry-run` anywhere in the command | `:62` |
| No session-launcher token (`handoff-fire.sh`, `claude`, `claude-latest`, `claude-next*`, `claude<digits>`) | `:67` |
| No frontier `--model` value | `:71-77` |
| Launcher name alone (e.g. `claude-fable3`) is not a signal | `:25-31` |
| Agent call with no `tool_input.model` | `:106` |
| Non-frontier model | `:110` |
| Missing `jq`: `tool_name` stays empty, so a Bash call is treated as the agent path and needs a `"model"` key that a Bash call lacks. The session arm is effectively off | `:84-86`, `:88`, `:101-106` |

- **Regex gaps.** By reading `:75`, `--model "fable"` (quoted) or a `$VAR` value is not matched, because quotes and `$` are outside the character class. I did not find a test for these.
- **Effect on the cap:**
  - A different `TMPDIR` gives a fresh counter (`:133`).
  - A `reserve_dates` match lowers the cap instead of bypassing it (`:127`).
- **No cap-off env var.** The hook reads only `FRONTIER_GATE_CFG` and `TMPDIR` as environment variables.
- **`CC_LADDER=off`:** the always-resident instructions name it as the "Kill-switch" (`CLAUDE.global.md:334`).
  - I grepped the whole repo with `grep -rlI "CC_LADDER" .`. It appears only in `CLAUDE.global.md` and `docs/plans/NONLIMIT_RESUME_LADDER.md` (`:840`, `:866`).
  - No hook, script, `bin/` file or test reads it.
  - The plan says it is "read by the fire path" (`NONLIMIT_RESUME_LADDER.md:840`). That is not true of any executable file. It is a documented switch with no implementation.

## 7. Registration: is the session arm live?

- **What is registered by default:** `settings-templates/settings.example.json:152-162` has a PreToolUse `"matcher": "Agent"` group. It holds `agent-teams-enforce.sh` and `frontier-spawn-gate.sh` (`:160`, timeout 5).
  - The Bash matcher groups are at `:102`, `:203`, `:607` and `:704`. I grepped `frontier-spawn-gate` in `settings-templates/`, `config/`, `install.sh` and `sync.sh`, and the only hit was `:160`.
  - **The Bash arm is therefore not wired by the repo's default template.**
- **The registering artifact:** `migrations/0029-frontier-gate-session-path.sh`.
  - **Class:** `# migration-class: c10` (`:2`). It edits `settings.json`, so it is staged and never self-runs (`:23-25`; `migrations/README.md:68-74`).
  - **Preconditions:**
    - `jq` present (`:65`).
    - The live `$HOME/.claude/hooks/frontier-spawn-gate.sh` exists and is executable (`:73-77`).
    - That live file contains `frontier_fire_model` (`:78-83`).
  - **Config dirs written:** `~/.claude`, `-next`, `-secondary`, `-tertiary` and `-quaternary` (`:86`).
    - It skips a dir with no `settings.json` (`:88`) or no PreToolUse Bash group (`:92-95`).
    - It skips a config that already has the entry (`:97-102`).
    - It backs up first as `.bak-0029-<ts>` (`:104-105`).
    - It appends `{"type":"command","command":"~/.claude/hooks/frontier-spawn-gate.sh","timeout":5}` to the first Bash group (`:112-114`).
  - **Post-verification, before `mv`** (`:121-125`):
    - The entry appears exactly once in the Bash group.
    - `asyncRewake` is false.
    - `timeout == 5`.
    - The Agent entry survived.
    - Otherwise it deletes the temp file and leaves the config unchanged (`:128`).
  - **Its declared verifier** is the `# migration-verify:` header (`:6`).
- **Command to establish a live machine's state** (from `CLAUDE.global.md:334`): `jq '[.hooks.PreToolUse[]|select(.matcher=="Bash")|.hooks[]?.command]|any(.=="~/.claude/hooks/frontier-spawn-gate.sh")' ~/.claude/settings.json`.
  - It checks only `~/.claude`. The migration writes five dirs, so repeat it per dir if needed.
  - `scripts/deploy-migrations.sh --status` shows applied, pending and staged migrations (`migrations/README.md:109`).

## 8. Stale citations and code-versus-wiring claims

**Citations that no longer land:**
- The gate header cites `scripts/handoff-fire.sh:9303-9311` for the model-only predicate (`hooks/frontier-spawn-gate.sh:27`). Lines 9295-9315 there are the in-flight claim code (`hf_inflight_key`). The predicate is now at `scripts/handoff-fire.sh:10140-10147`.
- `model-config.yaml:545` cites `hooks/frontier-spawn-gate.sh:30` as the line `fable|"$fmodel")`.
  - Line 30 of the hook is a header comment.
  - The `case` is now at `:51-54`, and it reads `fable|claude-fable-5*)` plus a separate `"$fmodel")` arm.
- `hooks/agent-teams-enforce.sh:366` cites `hooks/frontier-spawn-gate.sh:52-63` as "per-session cap, hard refusal, 'do NOT retry'".
  - Lines 52-63 are the tail of `is_frontier_model` and the start of `frontier_fire_model`.
  - The cap and refusal logic is at `:117-146`.
- Reference-only, not a stale citation: the migration header says "24/24" tests (`migrations/0029-frontier-gate-session-path.sh:11`). I did not count the `@test` blocks beyond noting cases 1-23 plus 9b.

**True of the code, false of the live wiring:**
- `CLAUDE.global.md:334` says the hook "counts both carriers against one per-session budget … and refuses at" the cap. That is true of the code (`hooks/frontier-spawn-gate.sh:133-144`). The same paragraph says it is live only once 0029 is run and tells the reader to check first.
- The hook's own header says "PreToolUse (Agent + Bash matchers)" (`hooks/frontier-spawn-gate.sh:2`), but the default template registers only the Agent matcher (`settings-templates/settings.example.json:160`).
- The `CC_LADDER=off` "Kill-switch" (`CLAUDE.global.md:334`) is stated as a live lever. No executable file reads it.
- The window-closed branch is described as a working backstop (`hooks/frontier-spawn-gate.sh:3-5`, `:148-153`). With the SSOT at `active: true` and `end: "2099-12-31"` it is unreachable today.
