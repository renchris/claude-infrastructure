# How this repo caps a session's use of the frontier (Fable) tier

**Bottom line:** one hook, `hooks/frontier-spawn-gate.sh`, counts frontier Agent spawns and frontier session fires against a single per-session cap of 6. The session (Bash) arm is present in the code but not registered by default. It only becomes live after the operator runs `migrations/0029-frontier-gate-session-path.sh`. The kill switch the always-loaded instructions name, `CC_LADDER=off`, is not read by any executable file.

## 1. The enforcer

**Only one file enforces the budget: `hooks/frontier-spawn-gate.sh`.** Its counter file is written only at `hooks/frontier-spawn-gate.sh:133`. A repo-wide grep for `frontier-gate-` finds nothing else except the test suite and one doc (`docs/research/fable51-vs-opus5-routing-2026-09-16/A7-architecture.md:105`). `hooks/agent-teams-enforce.sh:362-368` has its own spawn budget. It is modelled on this gate, but it is not a frontier budget.

**What each arm reads from the PreToolUse payload:**
- Both arms read `.tool_name` (`hooks/frontier-spawn-gate.sh:85`) and `.session_id` (`:130`).
- **Agent arm:** reads `.tool_input.model` with jq (`:102`). Without jq it falls back to a grep for `"model": "…"` (`:104`).
- **Session arm:** reads `.tool_input.command` (`:94`).

**The code that tells the two carriers apart** (`hooks/frontier-spawn-gate.sh:88-107`). Anything that is not `tool_name == "Bash"` goes down the Agent path:
```bash
path=agent
req_model=""
if [ "${tool_name:-}" = "Bash" ]; then
  path=session
  ...
  [ -n "$cmd" ] || exit 0
  req_model="$(frontier_fire_model "$cmd")" || exit 0
  [ -n "${req_model:-}" ] || exit 0
else
  ...req_model="$(printf '%s' "$input" | jq -r '.tool_input.model // empty' 2>/dev/null)"
  ...
  [ -n "${req_model:-}" ] || exit 0
fi
```

**The shared "is this the frontier tier?" predicate** (`hooks/frontier-spawn-gate.sh:51-54`, applied at `:110` as `is_frontier_model "$req_model" || exit 0`):
```bash
  case "${1:-}" in
    fable|claude-fable-5*) return 0 ;;
    "$fmodel") [ -n "${fmodel:-}" ] && return 0 ;;
  esac
```
`$fmodel` is taken from the SSOT: `grep -m1 '  model:' | awk '{print $2}'` inside the `frontier_access` block (`:39-40`). Its value today is `claude-fable-5-1` (`model-config.yaml:663`).

**Session-arm extras** in `frontier_fire_model()`, which run before that predicate:
- **Dry-run exemption:** `case "$c" in *--dry-run*) return 1 ;; esac` (`:62`).
- **The command must start a session launcher:** `grep -qE '(^|[[:space:]]|[;&|(])([A-Za-z0-9_./~$"{}-]*/)?(handoff-fire\.sh|claude|claude-latest|claude-next[0-9]*|claude[0-9]+)([[:space:]]|$)' || return 1` (`:67`).
- **Model tokens:** every `--model[= ]+[A-Za-z0-9._-]+` in the command is extracted (`:75`). The first one that passes `is_frontier_model` is returned (`:71-73`), not the last one.
- **A launcher name alone is not a frontier signal.** This is deliberate (comment at `:25-32`). It matches `scripts/handoff-fire.sh:10146-10147`: `FABLE_EFFECTIVE=0` / `case "$MODEL" in claude-fable-5*) FABLE_EFFECTIVE=1 ;; esac`. There, the `fable` alias is first resolved from the same SSOT key (`scripts/handoff-fire.sh:9493`).

## 2. Where the number comes from

**Which file the hook reads:** `CFG="${FRONTIER_GATE_CFG:-$HOME/.claude/model-config.yaml}"` (`hooks/frontier-spawn-gate.sh:36`). That is the deployed copy under `~/.claude`, whatever `CLAUDE_CONFIG_DIR` is set to. The repo source is `model-config.yaml`.

**The cap:**
- **Key and value today:** `frontier_discovery_budget.max_fable_spawns_per_session: 6` (`model-config.yaml:938-939`).
- **Parse:** `cap="$(grep -m1 'max_fable_spawns_per_session:' "$CFG" | awk '{print $2}')"` (`hooks/frontier-spawn-gate.sh:120`).
- **Scoping:** this read is file-wide (first match anywhere), not limited to the `frontier_discovery_budget` block. The `frontier_access` fields, by contrast, are block-scoped through `sed -n '/^frontier_access:/,/^[a-z_]/p'` (`:39`).
  - Today the first match that has the colon is `:939`. The other mentions, `model-config.yaml:517` and `:996`, have no `:` right after the key.
  - So the comment "frontier-spawn-gate.sh reads this block" (`model-config.yaml:937`) is looser than the code.
- **Fallback when empty or non-numeric:** `case "${cap:-}" in ''|*[!0-9]*) cap=6 ;; esac` (`:121`). A literal `0` counts as numeric, so it is accepted. With a cap of 0, `cnt -ge cap` is true on the first request and every frontier request is refused (`:136`).

**The runtime modifier: reserve dates.**
- **Key and value today:** `frontier_discovery_budget.reserve_dates: ""` (`model-config.yaml:949`). It is empty, so there is no halving today.
- **Parse:** `grep -m1 'reserve_dates:' "$CFG" | sed 's/.*reserve_dates:[[:space:]]*"\{0,1\}//; s/".*//'`. This is also file-wide (`hooks/frontier-spawn-gate.sh:125`).
- **Arithmetic** (`:126-128`):
  ```bash
  case " ${reserve:-} " in
    *" $today "*) cap=$(( cap / 2 )); [ "$cap" -lt 1 ] && cap=1 ;;
  esac
  ```
  - This is integer floor division with a minimum of 1, so 6 becomes 3.
  - Side effect: on a reserve date a cap of 0 becomes 1.
  - Dates must be space-separated inside the one quoted string.
  - Pinned by `tests/frontier-spawn-gate.bats:161-167`, which expects `(3/3`.

## 3. Counting and storage

**Where the count lives:** `cnt_file="${TMPDIR:-/tmp}/frontier-gate-${sid}.count"` (`hooks/frontier-spawn-gate.sh:133`).

**Key:** `sid` is `jq -r '.session_id // "nosid"'` (`:130`).
- If there is no `session_id`, or jq is missing, it becomes `sid="${sid:-nosid}"` (`:132`).
- Every such call shares one file, `frontier-gate-nosid.count`, which pools across sessions.

**Read:** `cnt="$(cat "$cnt_file")"`. Anything empty or non-numeric resets to 0 (`:134-135`).

**When it is written, relative to the allow decision:**
1. Cap check: `[ "$cnt" -ge "$cap" ]` → `exit 2` (`:136-142`).
2. Otherwise: `echo $((cnt + 1)) > "$cnt_file"` (`:144`), then `exit 0 # window open, under cap — allow` (`:145`).

So the slot is charged at PreToolUse time, before the tool runs.
- **Refused requests are not charged:** both `exit 2` paths (`:142`, `:153`) come before `:144`, and the closed-window path never reaches the counter.
- **Failed spawns are not refunded:**
  - No other code touches the file (grep above).
  - The gate is registered only under PreToolUse (`settings-templates/settings.example.json:160` is the only template hit). No PostToolUse or PostToolUseFailure entry exists for it.
  - The SSOT comment agrees: a premature spawn would "burn a per-session spawn-count slot the gate can't refund" (`model-config.yaml:690-691`).
- **No locking (inference):** the read-modify-write at `:134`/`:144` takes no lock, so parallel frontier Agent calls in one turn could each read the same N.

**Shared or separate budgets:** one shared budget. `$path` is not part of `cnt_file` (`:133`). The session refusal says so outright: "Agent spawns and frontier session FIRES share one budget" (`:138`). The test that pins it is `tests/frontier-spawn-gate.bats:107-111`, "8 the two paths share ONE budget": one Agent spawn plus one fire gives `count_of H = 2`.

**"Per session" means per `session_id`, not per lineage.** The key holds only the session id (`:133`). Assuming each fired or recycled process gets a new session id (the ladder is "three same-pane recycles, each a NEW process", `CLAUDE.global.md:334`), every fired session starts again at 0.

## 4. At and over the cap

**Behaviour:** `exit 2` (`hooks/frontier-spawn-gate.sh:142`). The message goes to **stderr** (`>&2`, `:138` and `:140`). Tests capture it with `2>&1` and assert `status -eq 2` (`tests/frontier-spawn-gate.bats:141-143`, `:149-151`).

**The two texts, and their distinguishing clauses:**
- **Session** (`:138`): "per-session frontier cap reached … **Agent spawns and frontier session FIRES share one budget**). Do NOT retry: **fire this session on the default tier instead (--model opus — handoff-fire resolves it to versions.opus_latest, and to the binary's own alias on a recycle)**, or park the remaining hole(s)…"
- **Agent** (`:140`): "per-session frontier-spawn cap reached … Do NOT retry: **park the remaining hole(s) in docs/research/FRONTIER_HOLES.md; a later session's wrap-up batch runs them.**"

**Why they differ:**
- The comment at `:81-82` says a blocked SESSION fire must never be told to "re-spawn this agent", because that "names a tool the operator did not use".
- The session text uses the alias `opus` rather than a full id. Test 13 enforces both points: it requires `--model opus `, forbids `--model claude-opus-`, and forbids `Re-spawn this agent` (`tests/frontier-spawn-gate.bats:152-158`).
- The reason for the alias: a recycle types into the pane's existing shell (`scripts/handoff-fire.sh:9494-9495`), and "any 2.1.260 session … refuses the full id" (`CLAUDE.global.md:334`).

## 5. The window

**Fields read, all inside the `frontier_access` block:**
- `model` (`:40`)
- `active` (`:112`)
- `end`, with quotes stripped (`:113`)
- `fallback` (`:114`)

A read of the whole hook (`:1-153`) shows no read of `permanent`, `start`, `source` or `tracks`.

**The comparison** (`:115-117`):
```bash
today="$(date +%F)"
if [ "${active:-}" = "true" ] && [ -n "${end:-}" ] && [ ! "$today" \> "$end" ]; then
```
This is a lexical ISO-date comparison on local time, with `end` inclusive.

**When the window is shut:** there is no counting, a refusal goes to stderr (session `:149`, agent `:151`), and the hook exits `exit 2` (`:153`). The failure modes are asymmetric:
- A missing SSOT **allows** everything (`:37`).
- A present SSOT whose `active:` does not parse as exactly `true` **refuses** every frontier request.

**Is the closed branch reachable in production today? No.**
- The SSOT has `active: true` (`model-config.yaml:687`) and `end: "2099-12-31"` (`:682`, marked SENTINEL).
- The block range `/^frontier_access:/,/^[a-z_]/` runs from `:662` to `pricing_per_mtok:` at `:712`. The first `  active:` in that range is `:687` and the first `  end:` is `:682`, so the window parses as open until 2099.
- `model-config.yaml:701-702` says the branch "cannot fire while `permanent: true` holds". That is true in effect, but the gate never reads `permanent`. What keeps the window open is `active` plus the `end` sentinel.

**What the closed-branch refusal advises, compared with the SSOT:**
- **Session:** `Re-fire on the fallback tier (--model ${fallback:-claude-opus-5})` (`:149`).
  - With the SSOT's `fallback: claude-opus-5-5` (`model-config.yaml:699`) this prints a **full id**, `--model claude-opus-5-5`.
  - That is exactly what the cap branch avoids, and what `CLAUDE.global.md:334` says a 2.1.260 pane refuses on a recycle.
  - Test 15 pins the full-id form: it expects `--model claude-opus-5` against a fixture fallback of `claude-opus-5` (`tests/frontier-spawn-gate.bats:47`, `:175`).
- **Agent:** `omit model, or model: "opus" → ${fallback:-claude-opus-4-8}` (`:151`).
- **Stale defaults:** the hard-coded defaults (`claude-opus-5` at `:149`, `claude-opus-4-8` at `:151`) disagree with each other and with the SSOT. They only apply if `fallback:` fails to parse.

## 6. Kill switches and bypasses

| # | What skips counting or refusing | Implementing line |
|---|---|---|
| 1 | `FRONTIER_GATE_CFG` pointing at a non-file → silent allow (test 17) | `hooks/frontier-spawn-gate.sh:36-37`; `tests/frontier-spawn-gate.bats:186-192` |
| 2 | `~/.claude/model-config.yaml` absent → silent allow. The path is fixed to `$HOME/.claude` whatever `CLAUDE_CONFIG_DIR` is. | `:36-37` |
| 3 | **jq absent.** `tool_name` stays empty (`:84-86`), so the call takes the agent path (`:88`). The grep fallback (`:104`) finds no `"model":` key in a Bash payload → `exit 0` (`:106`). The session arm dies silently, and `sid` becomes `nosid` (`:132`). `tests/hook-jq-abstain.bats:6` notes that the gate has a jq guard but has no case for it. | `:84-106`, `:132` |
| 4 | Agent call with no `model` field → `exit 0`. A subagent that inherits a Fable parent's model is therefore uncounted (inheritance is harness behaviour, not repo code). No agent definition declares `model: …fable` today (grep of `agents/*.md` for `^model: .*fable`: no hits; `agents/frontier-derivation.md:5` is `model: opus`). | `:106` |
| 5 | A model string outside `fable\|claude-fable-5*\|$fmodel`, e.g. a differently-cased alias or a future family before the SSOT flip | `:51-54` |
| 6 | `--dry-run` **anywhere** in the Bash string, including a chained second command or inside a quoted prompt (test 10) | `:62`; `tests/frontier-spawn-gate.bats:126-130` |
| 7 | An entry point outside the regex. For example `claude-prev*`, `claude-plan`, `claude-x`/`-h`, `claude-desk*`, `cc`/`ccr` (names from `README.md:869`), or `bash -c 'claude --model fable'` (a quote character is not a valid left anchor). | `:67` |
| 8 | A model that is not a bare token: `--model "fable"`, `--model 'claude-fable-5-1'`, `--model "$M"`. Also a model passed by environment instead of the flag. `model-config.yaml:553` describes the launcher as `--model "${CLAUDE_NEXT_MODEL:-claude-opus-5}"`; that is a dated note, not checked against `~/.zshrc`. | `:75` |
| 9 | Several fires in one Bash call (`a --model fable; b --model fable`) cost **one** slot: the scan returns on the first match and the counter increments once. | `:73`, `:144` |
| 10 | Counter state: deleting the file, writing non-digits into it, or a different `TMPDIR` → count resets to 0 | `:133-135` |
| 11 | A new `session_id` (every fired or recycled session) → a fresh budget | `:130-133` |
| 12 | The Bash matcher is not registered → the entire session arm is inert (see §7) | `settings-templates/settings.example.json:101-129` |
| 13 | Config: a non-numeric cap → 6. A reserve date halves the cap, which tightens it rather than bypassing it. | `:121`, `:125-128` |
| 14 | Registering with `asyncRewake: true` → the hook "cannot return exit 2 in time" and reports as registered while gating nothing | `migrations/0029-frontier-gate-session-path.sh:27-30` (the conflict oracle is `:7`) |

**`CC_LADDER=off` is inert.** `CLAUDE.global.md:334` says "Kill-switch: `CC_LADDER=off`". `grep -rIn "CC_LADDER"` over the whole repo returns only:
- `CLAUDE.global.md:334`
- `docs/plans/NONLIMIT_RESUME_LADDER.md:840`, which describes it as "one env var, read by the fire path" — a plan item
- `docs/plans/NONLIMIT_RESUME_LADDER.md:866`

No file under `hooks/`, `scripts/` (including `scripts/handoff-fire.sh`), `bin/` or `lib/` reads it, so setting it changes nothing.

## 7. Registration: is the session arm live?

**Default state: inert.**
- The template registers the gate only in the **`Agent`** matcher group (`settings-templates/settings.example.json:150-163`, entry `:158-161`, timeout 5).
- The **`Bash`** group (`:101-129`) holds curl-gate, validate-bash, git-worktree-guard, keychain-guard and rm-safe-allowlist, but not the gate.
- `settings.example.json:160` is the only `frontier-spawn-gate` hit under `settings-templates/`.
- `install.sh` cannot add it either. Its merge "adds missing EVENTS only — never clobbers a populated event" (`install.sh:1201-1204`), and the template it merges from lacks the Bash entry anyway.

**The artifact that would register it:** `migrations/0029-frontier-gate-session-path.sh`.
- **Class:** `c10` (`:2`), which means "staged, never run … waits for a human" (`migrations/README.md:68-75`; ratification "has not happened", `:73`). The operator command is at `:4`.

**Preconditions it asserts before touching anything:**
1. jq is present (`:65`).
2. `${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/frontier-spawn-gate.sh` exists and is executable (`:61`, `:73-77`).
3. That live hook contains `frontier_fire_model`, checked by content (`:78-83`).

Per config dir it also requires:
- `settings.json` exists (`:88`).
- An existing PreToolUse Bash group (`:92-95`).
- The gate is not already registered (`:97-102`).
- A successful `cp -p` backup (`:104-105`).

**Config directories it writes:** `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary`. The list is hard-coded at `:86` and ignores `CC_CLAUDE_DIR`, unlike `:6`/`:61`.
- It appends `{"type":"command","command":"~/.claude/hooks/frontier-spawn-gate.sh","timeout":5}` to the first Bash group (`:112-114`).
- It does **not** cover `~/.claude-260`. `model-config.yaml:670` says `claude` maps to that directory, while `README.md:869` says `claude` uses `~/.claude-next`. The docs disagree.

**What it verifies afterwards, before `mv`** (`:121-126`):
- exactly one gate entry in the Bash groups
- `asyncRewake` false
- `timeout == 5`
- **and** exactly one gate entry still in the Agent groups

If any check fails, the live file is left unchanged and `rc=1` (`:128`).

**The one command to run** — the migration's own verify oracle (`:6`):
```sh
jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[]? | select(.command == "~/.claude/hooks/frontier-spawn-gate.sh")] | length == 1' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json"
```
- Exit 0 means live; exit 1 means inert.
- Set `CC_CLAUDE_DIR` to the config directory the session actually uses.
- To rule out a "registered but old hook" no-op, pair it with `grep -q frontier_fire_model ~/.claude/hooks/frontier-spawn-gate.sh` (`:68-72`).
- The check in `CLAUDE.global.md:334` is weaker: it looks only at `~/.claude/settings.json`, uses `any`, and checks neither the timeout nor `asyncRewake`.

## 8. Stale and contradicting cross-references

**Citations that no longer land on the code they describe:**

| Citing site | Cites | What is there now |
|---|---|---|
| `hooks/frontier-spawn-gate.sh:27` | `scripts/handoff-fire.sh:9303-9311` as handoff-fire's `--model` predicate | `hf_inflight_key()` (`scripts/handoff-fire.sh:9304-9315`). The predicate is at `:10146-10147`, and alias resolution at `:9493`. **Stale.** |
| `model-config.yaml:545-549` | `:30` "now reads `fable\|claude-fable-5*\|"$fmodel")`" | `:30` is a comment. The predicate is at `:51-53`, split into two case arms. **Stale.** |
| `model-config.yaml:512-514` | quotes `case "$req_model" in fable\|"$fmodel") ;; *) exit 0 ;; esac` | No longer in the file (now `:110` plus `:51-54`). It is marked as history and fixed at `:527-528`. |
| `hooks/agent-teams-enforce.sh:366` | `:52-63` "per-session cap, hard refusal, do NOT retry" | `:52-63` are the two predicates. The cap and refusal are at `:120-145`. **Stale.** |
| `docs/research/desk-audit-2026-07-18/p15-escalation.md:44` | `:59-67` exit 2 | The dry-run and entry-point guard. Exit 2 is at `:142`/`:153`. **Stale.** |
| `docs/research/fable51-vs-opus5-routing-2026-09-16/A5-harness.md:357` | `:37-69` "caps ordinary Agent spawns at 6, denies" | SSOT load and predicates. The cap is at `:120-121`, the deny at `:136-142`. Also no longer Agent-only. **Stale.** |
| `…/A6-mechanics.md:245` | `:26-38` reads `frontier_access.model` and matches | Comment and CFG setup. The read is at `:39-40`, the match at `:51-53`. **Stale.** |
| `…/A6-mechanics.md:500` | `:23` "exits 0 when `tool_input.model` is absent" | A comment. The code is at `:102`/`:106` and applies to the Agent path only. **Stale.** |
| `docs/research/opus55-utilization-2026-09-22/census/L1-census.md:62` | `:138` says `--model claude-opus-5` | The line lands on the session cap refusal, but it now says `--model opus`. **Content stale.** |

**Citations checked and correct:**
- `L1-census.md:63` (`:149`, closed-window only, dormant)
- `migrations/0029…:41` and `:44-45` (test cases 17-19, 9, 9b, 11 and 10 match `tests/frontier-spawn-gate.bats:114-136`, `:186-204`)
- `0029:33` ("5 s matches the Agent-matcher entry" = `settings.example.json:161`)
- `0029:11`, "24/24, 4 mutants": the file does hold 24 `@test`s, including mutants 20-23. Whether they pass was not verified, because running tests is outside the read-only rules.

**True of the code but false of the live wiring, or otherwise not backed by an executable line:**
- `hooks/frontier-spawn-gate.sh:2`, "PreToolUse (Agent + Bash matchers)": the template wires Agent only.
- `CLAUDE.global.md:334`, "counts **both** carriers against one per-session budget": true of `:133` and test 8, false until 0029 runs. The same paragraph does add that caveat.
- `docs/research/opus55-utilization-2026-09-22/census/L2a-policy-surfaces.md:93-94` states the caveat correctly.
- `model-config.yaml:944-945`, "hard cap, all fable spawns (panels + teammate_frontier)": in practice it covers only Agent calls that carry an explicit frontier `model` (`:106`), and sessions only after 0029.
- `model-config.yaml:937`, "reads this block": the keys are actually read file-wide (`:120`, `:125`).
- `model-config.yaml:701-702`: the gate never reads `permanent`.
- `CLAUDE.global.md:334` and `docs/plans/NONLIMIT_RESUME_LADDER.md:840`: `CC_LADDER=off` is described as a working kill switch but is read by nothing.
- `hooks/frontier-spawn-gate.sh:3-5` says the gate's job is catching stale routing "after the frontier_access window closes". With `end: "2099-12-31"` and `active: true`, that branch is dormant; the cap is the only part doing work.

*Scope note:* the brief names the snapshot as `/tmp/o55probe-repo-47c3317eb`. I read the same pinned snapshot at `/tmp/s55/repo-47c3317eb`, as the task setup directed. All paths above are repo-root-relative.
