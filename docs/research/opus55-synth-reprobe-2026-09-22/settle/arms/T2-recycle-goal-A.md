<!-- arm A = claude-sonnet-5 @max · brief T2-recycle-goal · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

## How `scripts/handoff-fire.sh --recycle` carries a predecessor session's live `/goal` onto the successor

Repo root below is `/tmp/o55probe-repo-47c3317eb`; all paths are relative to it, all lines 1-based, pinned at sha `47c3317eb`.

### 1. The read: inheritance decision, oracle, and store

The inheritance **decision** function is `inherit_recycle_goal()`, defined at `scripts/handoff-fire.sh:5840`:
```
5840:inherit_recycle_goal() { # $1=predecessor-sid → always 0
```
Its return contract is stated in its own signature comment and confirmed by its body: it takes `$1` = the predecessor's session id and **always returns 0** — every guard (`scripts/handoff-fire.sh:5842-5846`) is a bare `return 0` on the "nothing to do" paths, never a failure code, because (per the header at `5836`) "inheritance must never fail a recycle." Its side effect is mutating the caller's `FIRE_GOAL` variable (`5847`, `5852`), not a printed value.

The **oracle** it calls is `goal_live_for_sid()`, defined at `scripts/handoff-fire.sh:5809-5833`, invoked at `5845`:
```
5845:  _inh_cond="$(goal_live_for_sid "$1")" || return 0
```
`goal_live_for_sid()` reads the store as follows:
- **Predecessor identity**: not passed down from anywhere earlier — it is looked up fresh, at the recycle call site, via `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`scripts/handoff-fire.sh:12524`), where `$SID` is this pane's identity and `cc_sid_for_pane()` (defined `4955-4989`) resolves the *currently running* CC session id for that pane. It does so by reading `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` and grepping the `"session_id":"..."` field (`4959-4962`); if that registry row is absent/sid-less, it falls back to scanning `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` for a row whose `pid` is alive (`kill -0`, `4988`) and whose process env carries the matching `ITERM_SESSION_ID`, reading the `{pid,sessionId}` schema documented at `4972`.
- **Directory roots searched**: `$CC_PROJECTS_DIRS`, defaulted at `scripts/handoff-fire.sh:416`:
  ```
  416:CC_PROJECTS_DIRS="${CC_PROJECTS_DIRS:-$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
  ```
  `goal_live_for_sid` iterates this list at `5814`.
- **Locating the transcript**: `find "$pdir" -name "$sid.jsonl" -type f` (`scripts/handoff-fire.sh:5829`) — a recursive find, not a direct path join, because (comment `5780-5786`) the transcript lives one level down in a per-cwd project subdirectory.
- **Record shape treated as the answer**: JSONL records with top-level `.type=="attachment"` whose `.attachment.type=="goal_status"` (`scripts/handoff-fire.sh:5818-5819`), matching the SSOT dictionary documented in `hooks/lib/goal-state.sh:15-22`.
- **Which record wins**: within one transcript file, jq's `last` over the filtered array (`scripts/handoff-fire.sh:5819`, `... | last // empty`) — the chronologically last `goal_status` attachment in that file. Across multiple `find` hits for the same sid (a defensive case), the **first** hit that contains *any* `goal_status` record wins outright and search stops there (terminal → `return 1` at `5827`; live → `return 0` at `5825`); a hit with zero such records is skipped via `continue` (`5820`) and the next hit/root is tried. This matches the comment at `5821-5822`: "LAST record wins in both directions... this transcript IS the answer — stop searching other dirs either way."

**Stale citation found.** `scripts/handoff-fire.sh:4824` claims:
```
4824:#     holds. inherit_recycle_goal (:5089, called at :11070) re-arms the PREDECESSOR's live /goal
```
Neither line resolves to this machinery. Line `5089` (read directly) is mid-comment prose about a subagent-SIGKILL gate ("FAILURE DIRECTION IS DELIBERATE... A subagent SIGKILLed earlier..."), unrelated to goal inheritance. Line `11070` is inside the worktree-pool claim logic (`elif [ "$POOL_ELIGIBLE" = 1 ]; then ... claimed="$(cd "$REPO" && "$POOL" claim ...)"`), also unrelated. The real definition is `5840` and the real call site is `12540` (below). The same stale `:11070` call-site citation is repeated externally in `docs/research/voluntary-inplace-switch-2026-09-22/A03-precheck-healthy-source.md:96` ("`inherit_recycle_goal`, `handoff-fire.sh:5805`, called `:11070`") — and that doc's own `:5805` is likewise not the function definition; it is a line inside `goal_live_for_sid`'s header comment (the phrase "nested-project `find` goal_armed_for_pane uses, and adding a cross-tree source seam to the fire", read at `scripts/handoff-fire.sh:5805`), four lines above the real `goal_live_for_sid() {` at `5809`. Separately, `CLAUDE.global.md:223` and `docs/research/exhaustive-drive-2026-09-08/{SYNTHESIS.md:37,CRITIC.md:62,305}` all cite `handoff-fire.sh:4676-4684` for `inherit_recycle_goal`; that range is actually `transcript_for_sid()` (`scripts/handoff-fire.sh:4679`, `transcript_for_sid() { # $1=session-id → echoes path or nothing`), a different, more general sid→transcript resolver, not the goal machinery.

### 2. `hooks/lib/goal-state.sh` — involved as a spec, not as code

The recycle path does **not call** `hooks/lib/goal-state.sh`. `goal_live_for_sid()` in `scripts/handoff-fire.sh` is a deliberate duplicate, stated explicitly in its own header (`scripts/handoff-fire.sh:5801-5808`):
```
5801:# GOAL INHERITANCE oracle (2026-08-10). Reads the PREDECESSOR session's transcript and prints its
5802:# LIVE goal condition — the last goal_status ATTACHMENT with met==false and not failed. Twin of
5803:# hooks/lib/goal-state.sh::goal_live_condition (the SSOT for the record dictionary); duplicated
5804:# here deliberately: this file resolves the transcript BY SID across CC_PROJECTS_DIRS with the same
```
Interface difference: `hooks/lib/goal-state.sh:60` `goal_live_condition()` takes **`$1` = a transcript path** directly. `scripts/handoff-fire.sh:5809` `goal_live_for_sid()` takes **`$1` = a session id** and resolves the transcript itself via the `find`-over-`CC_PROJECTS_DIRS` logic described above — the SSOT function has no such resolution step and cannot be handed a sid.

Implementation difference / hardening: `hooks/lib/goal-state.sh` wraps every grep in `_goal_grep()` (`52-58`), which normalizes grep's "no match" exit (1) to rc 0 so a genuinely empty result survives `set -o pipefail` and is distinguishable from a real read error (rc ≥ 2, per `52-57`); both `goal_live_condition` (`66`) and `goal_liveness` (`112`) go through it. `scripts/handoff-fire.sh:5818-5819`'s `goal_live_for_sid` does **not** use `_goal_grep` or any equivalent — it pipes a raw grep straight into jq:
```
5818:      rec="$(grep -a 'goal_status' "$hit" 2>/dev/null | jq -rc --slurp '
5819:        [ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty' 2>/dev/null)" || continue
```
The script has `set -euo pipefail` in force (`scripts/handoff-fire.sh:343`), so this is exactly the pipefail hazard `_goal_grep`'s header documents (`hooks/lib/goal-state.sh:34-51`). **What the difference does and does not change here:** it does not change observable behavior for `goal_live_for_sid`, because a "genuinely no `goal_status` lines" grep-rc-1 and a "grep errored" rc≥2 both make the pipeline non-zero under pipefail, both trip the `|| continue` on the assignment (`5819`) or the immediately following `[ -n "$rec" ] || continue` (`5820`) — and both outcomes are treated identically by this consumer (keep looking / eventually fail closed to "no inheritance"). That is unlike `goal_liveness()` (`hooks/lib/goal-state.sh:104-144`), whose jq program explicitly emits a distinct `"absent\t0\tnone\t0\t"` value for a genuinely-empty match (`120`) and whose header states the fail direction must NOT collapse "absent" into "unreadable" (`100-103`) — that is the case the hardening was measured to matter for (comment `34-42`: 375 of 469 evaluations mislabeled). `goal_live_for_sid` never needs that distinction because its own two "not usable" outcomes (never-armed vs unreadable) already resolve to the same action.

The pane-side counterpart oracle, `goal_armed_for_pane()` (`scripts/handoff-fire.sh:5774-5799`), is a **third, separate** function — it verifies a *just-pasted* goal took effect on the successor by matching `.attachment.condition==$c` for a specific condition (`5792`); it is not involved in inheritance (called only at `5906`, inside the paste-verification loop), and item 1's oracle is `goal_live_for_sid`, not this one.

### 3. Precedence vs an explicit `--goal`

"Explicit wins" is implemented as the very first guard in `inherit_recycle_goal`:
```
5842:  [ -z "${FIRE_GOAL:-}" ] || return 0
```
If `FIRE_GOAL` is already non-empty when this runs, the function returns immediately without touching it. `FIRE_GOAL` is set from the `--goal` CLI flag at `scripts/handoff-fire.sh:8950`:
```
8950:  --goal)           FIRE_GOAL="${2:?--goal needs a condition}"; shift 2 ;;
```
**What else can trip the same guard, besides the flag**: `scripts/handoff-fire.sh:508`, a top-level (not-in-a-function) initializer that runs unconditionally near the top of the script, before argument parsing:
```
508:FIRE_GOAL="${FIRE_GOAL:-}"                       # --goal: MESSAGE 2, armed AFTER engagement (arm_goal)
```
This seeds `FIRE_GOAL` from any pre-existing environment variable of the same name (e.g. `FIRE_GOAL='...' scripts/handoff-fire.sh --recycle`). Since `inherit_recycle_goal`'s guard at `5842` only tests non-emptiness, an inherited **environment variable** blocks inheritance exactly as an explicit `--goal` flag does — the code cannot and does not distinguish the two.

### 4. The opt-out

Name: `CC_RECYCLE_GOAL_INHERIT`. Default: `1` (inherit). Exact comparison, `scripts/handoff-fire.sh:5843`:
```
5843:  [ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0
```
This is a literal string test against the single character `0`. Consequences: only `CC_RECYCLE_GOAL_INHERIT=0` (exactly) turns inheritance off. An **unset** variable defaults to `1` via `:-1` → inherits. An **explicitly empty** value (`CC_RECYCLE_GOAL_INHERIT=`) is also unset-or-null for `:-`, so it too defaults to `1` → inherits. Any other non-`0` string — `off`, `false`, `no` — is simply `!= 0` and leaves inheritance **on**; the guard never fires for those.

**Doc inaccuracy found on exactly this point**: `docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md:170` states:
```
170:`${CC_RECYCLE_GOAL_INHERIT:-1}` — default-on, disabled with `=off`/`=0`. The `:-off`/`:-0` spellings
```
The `=off` half is not supported by the code read at `scripts/handoff-fire.sh:5843` — only `=0` disables it. This doc is dated 2026-09-22, i.e. the same date as "today" in this environment.

### 5. Terminal or absent predecessor goals

Inside `goal_live_for_sid`, the liveness test is `scripts/handoff-fire.sh:5823`:
```
5823:      if [ "$(printf '%s' "$rec" | jq -r '(.met // false) or (.failed // false)' 2>/dev/null)" = "false" ]; then
```
This is the identical boolean expression used by the SSOT predicate (`hooks/lib/goal-state.sh:70`), confirming the "twin" claim from §2. It does **not** distinguish *met* from *failed* from *cleared* — all three make `(.met // false) or (.failed // false)` true and are treated as one "terminal" outcome (per `hooks/lib/goal-state.sh:20-22`'s dictionary, "cleared" is `sentinel:true met:true`, which is subsumed by `.met`). For a **terminal** record, the oracle takes the `else` branch, `scripts/handoff-fire.sh:5827`: `return 1` — and per the comment at `5821-5822` ("this transcript IS the answer — stop searching other dirs either way"), the search **stops immediately**; it does not keep scanning other `$CC_PROJECTS_DIRS` roots or other hits.

For a predecessor that **never armed** a goal at all — its transcript file has zero `goal_status` attachment records — `rec` computes to the empty string, and `scripts/handoff-fire.sh:5820`:
```
5820:      [ -n "$rec" ] || continue
```
fires `continue`, i.e. the search **keeps looking** — the next `find` hit within the same root, then the next root in `$CC_PROJECTS_DIRS`. Only after every root/hit is exhausted with no non-empty `rec` does the function fall through to the final `return 1` at `scripts/handoff-fire.sh:5832`. So "never armed" and "terminal" both ultimately deny inheritance, but via different control flow: terminal stops the search on first contact, never-armed lets it continue trying other roots.

A live, un-evaluated arm marker (`sentinel:true met:false`, per `hooks/lib/goal-state.sh:18`) takes the `if` branch at `scripts/handoff-fire.sh:5824-5825`, printing `.condition` and `return 0` — it **is** inheritable, matching `inherit_recycle_goal`'s own header (`scripts/handoff-fire.sh:5837`): "terminal/absent predecessor goal → no-op."

### 6. Validation of an inherited condition

The validator is `check_goal_arm()`, `scripts/handoff-fire.sh:5734-5767`, invoked from within `inherit_recycle_goal` at `scripts/handoff-fire.sh:5848`:
```
5848:  if check_goal_arm; then
```
It reads only `FIRE_GOAL` (local `cond="${FIRE_GOAL:-}"`, `5735`) — by the time it runs here, `FIRE_GOAL` has just been set to the inherited condition at `5847`. It rejects three shapes, each with a stated reason:
- a condition containing a newline (`5745-5749`) — because the arming paste's Enter key submits only the first line, stranding the rest in the composer;
- a condition starting with `/` (`5754-5757`) — because it is pasted as `/goal <condition>`, so a leading slash would be parsed as a second slash-command;
- a condition over `${GOAL_MAX_CHARS:-4000}` characters (`5760-5764`) — because the harness hard-caps `/goal` input and silently sets nothing over that cap.

Each rejection calls `emit_fire_refusal` (`5748`, `5756`, `5763`) with reason codes `payload-goal-arm-multiline` / `payload-goal-arm-slash` / `payload-goal-arm-cap`, and also prints a specific `echo "!! ..." >&2` line (`5746-5747`, `5755`, `5761-5762`) — this happens in the **foreground** predecessor process, before `/exit` is typed (the whole recycle branch containing `inherit_recycle_goal` at `12540` runs before the watcher is detached at `12628`), so it is visible to whoever is watching that pane at that moment.

What happens to the **condition** and the **recycle**: `inherit_recycle_goal`'s `else` branch (`scripts/handoff-fire.sh:5850-5852`):
```
5850:  else
5851:    echo "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session" >&2
5852:    FIRE_GOAL=""
```
prints a **second**, generic stderr warning, resets `FIRE_GOAL` back to empty, and the function still `return 0`s (`5854`) — the recycle is **not** aborted; it proceeds goal-less. This is a materially different consequence from the same validator's other call site, `scripts/handoff-fire.sh:9015`:
```
9015:check_goal_arm || exit 1
```
which runs once, unconditionally, early (outside the `if [ -z "$RESUME_LAUNCHER" ]` payload-check block that closes at `9012`) for every invocation — for an **explicit** `--goal` (or a leaked `FIRE_GOAL` env var, §3), a validation failure there `exit 1`s the whole script before any side effect. So the identical validator is fail-**open** (drop and warn, keep going) when validating an inherited condition, and fail-**closed** (abort the invocation) when validating an explicit one.

Record of the refusal: yes — `emit_fire_refusal()` (`scripts/handoff-fire.sh:758-760`) calls `emit_fire_event refused "$1" "$2" refuse "$(_fire_gate_of "$1")"`, and `emit_fire_event()` (`682-714`) appends a JSON line to `$HOME/.claude/logs/handoffs.jsonl` (path at `683`), gated only by `CC_FIRE_REFUSAL_LOG` (default on, `684`). The row carries `class:"refused"`, `refuse_reason:<one of the three payload-goal-arm-* codes>`, `gate:"payload"` (via `_fire_gate_of`'s `payload-*) printf payload ;;` arm at `742`), `verdict:"refuse"`, plus `detail`, `ts`, `firing_sid`, `account`, `prompt_file`. So beyond the two stderr lines (ephemeral, pane-local), there is a durable, disk-persisted, machine-readable record any later reader of that log can find.

### 7. Where in the recycle flow the call sits, and the transport to the successor

The single call site is `scripts/handoff-fire.sh:12540`, inside a branch at `12535-12541`:
```
12535:  if [ -n "$RESUME_LAUNCHER" ]; then
12536:    # A same-uuid --resume carries an UNMET goal with it (recycle-100p §2.3, measured on 2.1.220);
12537:    # inheriting it here would arm the same condition twice in one session.
12538:    FIRE_GOAL=""
12539:  else
12540:    inherit_recycle_goal "$rcy_old_sid"
12541:  fi
```
This is the **deliberate skip branch**: when `$RESUME_LAUNCHER` is set (an in-place `--resume`, not an ordinary recycle), `FIRE_GOAL` is forced empty instead of calling `inherit_recycle_goal` at all — because `--resume` restores the same session uuid, which per the comment already carries its own unmet goal forward, and inheriting here would try to arm the same condition a second time. This matches the summary line printed for that mode at `scripts/handoff-fire.sh:12796`: `"...no goal inheritance (an unmet goal rides --resume)"`.

Immediately **before** the call: `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`12524`, §1's predecessor-identity resolution). Immediately **after** it: `RCY_T0="$(date -u +%FT%T)"` (`12542`, the resume-mode engagement baseline) then `pin_term_verdict_for_watcher` (`12543`).

**Transport path.** `FIRE_GOAL` (now holding either the inherited condition, an explicit one, or empty) is passed as a positional argument to `detach`, which re-execs this same script file as a detached watcher process with subcommand `__recycle`, at `scripts/handoff-fire.sh:12628`:
```
12628:  WATCHER_PID="$(detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" "${PROMPT_FILE_ORIG:-$PROMPT_FILE}" "$RESUME_CFG" ... )"
```
`$FIRE_GOAL` is the 8th argument after `__recycle`. The watcher branch begins at `scripts/handoff-fire.sh:6938-6941`:
```
6938:if [ "${1:-}" = "__recycle" ]; then
6939:  RSID="${2:?__recycle needs a session id}"
6940:  TTY_PATH="${3:?__recycle needs the pane tty}"
6941:  CMDFILE="${4:?__recycle needs the command file}"
```
and it reads the goal back as its own positional `$8` at `scripts/handoff-fire.sh:7158`:
```
7158:  FIRE_GOAL="${8:-}"                               # --goal condition to re-arm as MESSAGE 2
```
This detached watcher then waits out the predecessor's `/exit`, retypes the relaunch command, and polls for the successor's engagement. Only once engagement is **proven** — a real assistant turn, not merely a live process — does it arm the goal, at `scripts/handoff-fire.sh:7358-7365`:
```
7358:      if { [ -n "$RCY_RESUME_SID" ] && resume_engaged "$RCY_RESUME_CFG" "$RCY_RESUME_SID" "$RCY_T0" "${RCY_SUBMIT_TOKEN:-}"; } \
7359:         || { [ -z "$RCY_RESUME_SID" ] && recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"; }; then
7360:        echo "→ relaunched + ENGAGEMENT CONFIRMED in $RSID (a real assistant turn, not just a process)"
...
7365:        arm_goal "$IT2" "$RSID" "$FIRE_GOAL"
```
`arm_goal()` (defined `5864-...`) is the function that actually delivers the condition, as a second, separate message after the brief: a bracketed-paste of `/goal <condition>` into the now-engaged pane, verified read-back via `goal_armed_for_pane()` (`5774-5799`, called from inside `arm_goal` at `5906`) against the successor's own freshly-written transcript. So the moment in the successor's life at which the inherited goal is armed is **after its first proven assistant turn**, not at process launch — exactly matching the design comment at `scripts/handoff-fire.sh:5849`: "re-arming on the successor after engagement."