# How `scripts/handoff-fire.sh --recycle` carries a predecessor's live `/goal` onto the successor

All paths are relative to `/tmp/s55/repo-47c3317eb`. The brief names `/tmp/o55probe-repo-47c3317eb`. I read only the snapshot at the path I was given, `/tmp/s55/repo-47c3317eb`, at the same sha. Every line number below is in `scripts/handoff-fire.sh` unless another file is named. Claims about behaviour rest on the code lines I read. Comments are cited only where I say so.

## 1. The read

**Decision function.** `inherit_recycle_goal()` is defined at `scripts/handoff-fire.sh:5840` (`inherit_recycle_goal() { # $1=predecessor-sid → always 0`).
- Its return contract is "always 0". Every early exit is `return 0` (`:5842-5846`) and the last statement is `return 0` (`:5854`).
- Its only effect is to mutate the global `FIRE_GOAL`. It sets `FIRE_GOAL="$_inh_cond"` at `:5847`, or resets it to `""` at `:5852`.

**Oracle.** It calls `goal_live_for_sid "$1"` at `:5845` (`_inh_cond="$(goal_live_for_sid "$1")" || return 0`). That function is defined at `:5809`.
- On success (rc 0) it prints the condition.
- rc 1 means "none (or terminal, or unreadable)".
- An empty printed condition is also treated as "nothing" (`:5846`, `[ -n "$_inh_cond" ] || return 0`).

**What the oracle reads.** The store is Claude Code's per-session JSONL transcript.
- **Predecessor identity.**
  - The recycle path calls `rcy_old_sid="$(cc_sid_for_pane "$SID")"` at `:12524`.
  - It passes that to `inherit_recycle_goal "$rcy_old_sid"` at `:12540`.
  - `cc_sid_for_pane` is defined at `:4955`. Its first source is `"session_id"` grepped out of `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4961`).
  - Its fallback scans `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json`. A file counts only if its pid is alive (`:4988`, `kill -0`) and that process's `ITERM_SESSION_ID` ends in the pane (`:4989-4991`). It then takes `sessionId` from that file (`:4994`).
  - It can return empty. `inherit_recycle_goal` then stops at `[ -n "${1:-}" ] || return 0` (`:5844`).
- **Directory roots.** The oracle loops `for pdir in $CC_PROJECTS_DIRS` (`:5814`) and skips any non-directory (`:5815`).
  - The default is at `:416`: `$HOME/.claude/projects`, then `~/.claude-next`, `-secondary`, `-tertiary` and `-quaternary`, all under `.../projects`.
  - The variable is overridable from the environment.
- **Locating the file.** It uses `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`), fed to the loop through a here-doc (`:5816`, `:5828-5830`).
  - So it finds the transcript at any nesting depth, in the per-cwd project directory below the root.
  - A comment at `:5780-5786` explains why a direct `$pdir/$sid.jsonl` path is wrong. I rely on the `find` at `:5829`, not on that comment.
- **Record shape.** The oracle runs `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` (`:5818-5819`).
  - So the record is a transcript line with top-level `type=="attachment"` whose `.attachment.type=="goal_status"`.
  - `grep` runs first only to narrow the input. The `type=="attachment"` filter drops assistant prose that merely mentions goals.
- **Which record wins.** The last such record in the file wins (`last`), regardless of its state.
  - The condition is `.condition // ""`, printed at `:5824`.
  - Liveness is `(.met // false) or (.failed // false)` compared to `"false"` at `:5823`.

## 2. Which library is and is not involved

**The recycle path does not use `hooks/lib/goal-state.sh`.**
- The only references to `goal-state` in `scripts/handoff-fire.sh` are comments at `:4824` and `:5803`.
- Neither is a `source` or `.` line.
- The recycle path calls the file-local `goal_live_for_sid` (`:5845` → `:5809`).
- `goal_live_condition` and `goal_liveness` are defined in the library at `hooks/lib/goal-state.sh:60` and `:104`. `grep` found neither name in `handoff-fire.sh`, and the recycle path never calls them.
- `:5803-5808` says the twin is duplicated on purpose, so the fire path needs no cross-tree source. That is a comment. The code confirms the duplication: no source line exists.

**Interface differences.**
- `goal_live_condition` takes a transcript path (`$1 = transcript path`, `hooks/lib/goal-state.sh:60`).
  - It expands a leading `~` (`:63`) and requires `-f` (`:64`).
- `goal_live_for_sid` takes a session id and resolves the path itself, searching `CC_PROJECTS_DIRS` by `find` (`:5809`, `:5814`, `:5829`).
- The two are otherwise the same at the top: both return 1 for empty input or a missing `jq`.

**Implementation differences.**
- **Grep wrapper.** The library filters through `_goal_grep` (`hooks/lib/goal-state.sh:52-58`).
  - `_goal_grep` treats grep rc 0 and rc 1 (no match) as "grep ran". It returns 1 only for rc ≥ 2.
  - The library's own header (`:34-51`) says this exists because a bare `grep … | jq` under `set -o pipefail` reports a goal-less session as unreadable. That header is a comment, but the wrapper's code (`:54-57`) does what it says.
  - The recycle path uses a bare `grep -a 'goal_status' "$hit" 2>/dev/null | jq …` (`:5818`).
  - It has no `pipefail` handling. `grep` is the first stage of a `$(…)`, and the `|| continue` at `:5819` only sees the pipeline's status.
- **What the hardening changes here.** Whether `set -o pipefail` is active in `handoff-fire.sh`, I did not check.
  - If it is on, a transcript with no `goal_status` line makes the pipeline fail. The `|| continue` at `:5819` then moves to the next hit.
  - If it is off, `jq --slurp` on empty input yields `[]`, `last // empty` prints nothing, and `[ -n "$rec" ] || continue` (`:5820`) does the same.
  - Either way the outcome is "keep searching, eventually return 1". So "never armed" and "unreadable" both end as rc 1 and no inheritance.
  - That collapse is harmless here. The recycle consumer has one action and one fail direction: no goal, so nothing is inherited. It never needs to tell absent from unreadable.
- **Extra fields.** The library's `goal_liveness` (`hooks/lib/goal-state.sh:104`) additionally returns evaluation counts and state as TSV. The recycle path needs none of that.
- **Return handling.** The library's `goal_live_condition` returns 1 if the last record is terminal (`:70`). It then prints the condition and returns 0 (`:71-72`).
  - `goal_live_for_sid` has the same live test (`:5823`).
  - It also has extra control flow: it stops searching after the first transcript that contains a `goal_status` record (see §5).

## 3. Precedence vs an explicit `--goal`

**Mechanism.** The first statement of `inherit_recycle_goal` is `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). If `FIRE_GOAL` is non-empty, the function returns before any lookup.
- `--goal` sets it at `:8950` (`--goal) FIRE_GOAL="${2:?…}"`).
- `FIRE_GOAL` is initialised from the environment at `:508` (`FIRE_GOAL="${FIRE_GOAL:-}"`).
- A comment at `:34` also says "Env equivalent: FIRE_GOAL".

**What else trips the rule.**
- The `FIRE_GOAL` environment variable. Any non-empty inherited value has the same effect as the flag, because the check is on the variable and not the flag.
- No other path sets `FIRE_GOAL` before `:12540`. I saw only `:8950` and `:508`, plus the reset at `:12538`. I did not read the whole file, so "no other" is from the `FIRE_GOAL` grep list.

**One more thing.** An explicit `--goal` is validated at parse time by `check_goal_arm || exit 1` (`:9015`). A bad explicit goal refuses the whole recycle. An inherited one only loses the goal (§6).

## 4. The opt-out

- **Name and default.** The opt-out is `CC_RECYCLE_GOAL_INHERIT`, defaulting to `1` (`${CC_RECYCLE_GOAL_INHERIT:-1}`, `:5843`).
- **Comparison.** `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`). It is a string test against the literal `0`.
- **Which values turn inheritance off.**
  - Exactly the string `0`.
  - `00`, `false`, `off`, `no`, `1` and any other value do not turn it off.
  - An empty string is not `0` either (`:-1` also substitutes `1` for empty or unset).
- Contrast with the composer gate, which uses `!= off` (`:12468`, a different switch).

## 5. Terminal or absent predecessor goals

**What the oracle returns.**
- **Met, failed, or cleared.** Rc 1, with no output. The last record has `met` or `failed` true, so the test at `:5823` is not `"false"`, and the function falls to `return 1` at `:5827`.
  - A `/goal clear` marker is `sentinel:true met:true`, so it also counts as terminal. That mapping is from the library header comment (`hooks/lib/goal-state.sh:22`). The oracle code itself only tests `met` and `failed`, which covers it.
- **Never armed.** Rc 1, with no output. There is no matching record, so `rec` is empty and `[ -n "$rec" ] || continue` (`:5820`) fires.
  - The loop then tries the next `find` hit or root, and finally reaches `return 1` at `:5832`.
- **How the decision is made.** The last `goal_status` attachment in the file is tested for `met || failed` (`:5818-5823`).

**Does the search keep looking or stop?** It depends on the case.
- **A transcript with a record** stops the search. The comment `:5821-5822` says "this transcript IS the answer — stop searching other dirs either way". The code agrees: after any non-empty `rec`, the loop body ends in `printf …; return 0` (`:5824-5825`) or `return 1` (`:5827`).
  - So a terminal goal is final, and no other root or file is consulted.
- **Absent or unreadable** keeps looking. A file with no record, or a failed jq, hits `continue` (`:5819`, `:5820`). The loop advances to the next `find` hit, then the next root.
  - If nothing is found anywhere, it ends with `return 1` at `:5832`. `jq` missing returns 1 at `:5812`.

At the caller, rc 1 means `return 0` from `inherit_recycle_goal` with `FIRE_GOAL` untouched, so nothing is armed (`:5845`).

## 6. Validation of an inherited condition

**Which validator.** `check_goal_arm` (defined at `:5734`), called at `:5848` after `FIRE_GOAL="$_inh_cond"` at `:5847`.

**How it is invoked.** With no arguments. It reads the global: `local cond="${FIRE_GOAL:-}"` (`:5735`). This is why the inheritance function must assign `FIRE_GOAL` before calling it.

**What it rejects.**
- **A newline** (`*"$nl"*`, `:5745-5749`). The arming paste submits at the first CR and would strand the rest in the composer. It writes to stderr and calls `emit_fire_refusal payload-goal-arm-multiline`.
- **A leading `/`** (`:5754-5758`). The line pasted is `/goal $cond`, so a leading slash would make the condition read as another command. It calls `emit_fire_refusal payload-goal-arm-slash`.
- **More than `GOAL_MAX_CHARS`** (default 4000) characters (`:5759-5765`). It calls `emit_fire_refusal payload-goal-arm-cap`.
- Empty is accepted (`:5736`).

**What happens on refusal.**
- The condition is dropped. The `else` branch sets `FIRE_GOAL=""` (`:5852`).
- The recycle continues. The function returns 0 (`:5854`), and the caller carries on to the next statement (`:12542`).
- So a refused inherited goal costs the successor its goal, but does not stop the recycle.

**Where it is announced, and who can read it.**
- The inheritance function's own line goes to stderr: `echo "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session" >&2` (`:5851`).
- `check_goal_arm`'s reason lines also go to stderr (`:5746-5747`, `:5755`, `:5761-5762`).
- The reader is whoever holds the recycle process's stderr.
  - For a self-recycle that is the session about to be replaced, and that session is killed shortly after.
  - This comes from the comment at `:12494-12497`. It describes the composer-gate refusal, not this one, and I read it only as evidence of the same structural situation. I did not read the caller's process wiring to confirm it here.
  - The stderr is not cc-notify'd to anyone. Nothing in `inherit_recycle_goal` or `check_goal_arm` calls `cc-notify`, `hf_alarm` or the desk.
- The success message `→ goal INHERITED …` goes to stdout (`:5849`). It truncates the condition to 100 characters with `printf '%.100s'`.

**Is any record written?** Yes, but only as a side effect of `check_goal_arm`, and it misdescribes the event.
- Each refusal branch calls `emit_fire_refusal` (`:5748`, `:5756`, `:5763`).
- `emit_fire_refusal` calls `emit_fire_event refused …` (`:758-759`).
- `emit_fire_event` appends a JSON line to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`).
  - It is skipped only when `CC_FIRE_REFUSAL_LOG=0` (`:684`).
  - The row carries `engaged:false`, `refuse_reason:<payload-goal-arm-…>`, `class:refused`, and a `detail` string like "--goal condition is multi-line" (`:698-710`).
- So a refusal row exists, but its `detail` names `--goal`, and the row has no field saying "inherited". It reads like a refused fire, when in fact the recycle went on.
  - I did not check whether any consumer filters these rows for recycles.
- The `⚠ … NOT inherited` message itself (`:5851`) has no matching record. It goes to stderr only.

## 7. Where in the recycle flow the call sits

**The single call site** is `:12540`, `inherit_recycle_goal "$rcy_old_sid"`.
- The only other mentions in the file are the definition (`:5840`) and comments (`:4824`, `:12531`).
- The sequence at the call site, in order:
  - **Immediately before, `:12524`:** `rcy_old_sid="$(cc_sid_for_pane "$SID")"`. Before that come the composer gate (`:12468-12507`), and above it the pane-state `case` branches (`:12441-12456`).
  - **The call, `:12535-12541`:** an `if [ -n "$RESUME_LAUNCHER" ]` … `else` around it.
  - **Immediately after, `:12542-12543`:** `RCY_T0="$(date -u +%FT%T)"` and `pin_term_verdict_for_watcher`.
  - **Later, `:12628`:** the detached watcher is spawned. The watcher is spawned before `/exit` is typed, and the comment at `:12508-12515` says that ordering is required.

**The branch that skips inheritance.** `if [ -n "$RESUME_LAUNCHER" ]; then FIRE_GOAL=""` (`:12535-12538`).
- Resume mode also blanks `FIRE_GOAL`. That wipes even an explicit `--goal`, and the code does it without a warning.
- Why: the comment at `:12536-12537` says a same-uuid `--resume` carries the unmet goal with it, so inheriting "would arm the same condition twice". I cite that as the stated reason. The comment is what supports it, and the code only shows the reset.
- The `--help` text at `:188-189` agrees: "Goal inheritance is off (an unmet goal rides --resume)".

**Transport to the successor.**
1. **Handoff.** The mutated `FIRE_GOAL` is the eighth positional argument to the detached watcher: `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`).
   - `$1` is `__recycle`, `$2` `$SID`, `$3` `$tty`, `$4` `$cmdfile`, `$5` `$LAUNCH_DIR`, `$6` `$rcy_old_sid`, `$7` `$RECYCLE_MARKER`, `$8` `$FIRE_GOAL`.
   - The condition is passed by argv, not by file or environment.
2. **Read-back.** The watcher branch starts at `:6938` (`if [ "${1:-}" = "__recycle" ]`). It reads `FIRE_GOAL="${8:-}"` at `:7158`.
   - The comment beside that line says `--goal condition to re-arm as MESSAGE 2`, and the assignment shows the arity: an older arming side with 7 arguments gives an empty goal.
3. **When it is armed.** In the watcher, after the predecessor has exited and the relaunch has been typed, and only after engagement is confirmed.
   - The engagement loop is `:7339-7372`. The confirmation branch is `:7358-7360`, which echoes "ENGAGEMENT CONFIRMED".
   - Immediately inside that branch, `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` runs at `:7365`.
   - The `recycle-engaged` event is emitted after it (`:7368`), and then `exit 0` (`:7369`).
   - So the goal is armed only after a real assistant turn in the successor, not at launch and not on the prompt.
4. **The arming itself.** `arm_goal` (`:5864`) pastes `/goal $cond` into the successor pane through `it2_paste_submit_verified` (`:5886`).
   - It then polls `goal_armed_for_pane` (`:5906`) for a matching `goal_status` attachment. It does that for up to `FIRE_GOAL_VERIFY_TIMEOUT`, 45 s by default (`:5866`).
   - It reports `verdict=set` (`:5907`) or `verdict=unverified` (`:5915`).
   - It has other verdicts: `abstained` when no pane or `it2` is bound (`:5872-5875`), `held` for rc 3 (`:5889-5893`), `mangled` for rc 4 (`:5894-5898`), and `abstained` again for other rcs (`:5899-5903`). Every path returns 0.
   - `arm_goal` returns 0 at once if the condition is empty (`:5867`). So an empty `FIRE_GOAL` inherits nothing.
5. **Paths where it is never armed.** The unverifiable path at `:7321-7335` calls `goal_unreachable recycle-unverified` and exits before the arm.
   - That function prints a warning and writes a `goal-arm verdict=unreachable` row, but only if `FIRE_GOAL` is non-empty (`:801-805`).
   - The dead-recycle path (loop expiry, from `:7373`) also never reaches `arm_goal`. I did not read its tail to see whether it calls `goal_unreachable`.

## Stale line-number citations

I checked each numbered reference against the file. None of these resolves.
- **`:4824`** says `inherit_recycle_goal (:5089, called at :11070)`.
  - The function is at `:5840` and the call is at `:12540`.
  - Line 5089 is inside a different comment, about refusing agents, and line 11070 is a comment about a fire proceeding without a ping. Neither has anything to do with goals.
- **`:3520`** says the custody debt is at `:10715` and the goal arm at `:10723`.
  - The actual recycle arm is `:7365`, and the fire-path arm is `:13233`.
  - Line 10715 is a comment about the self-close stamp. Line 10723 is `claimed="$(cd "$REPO" && "$POOL" claim …)"`.
- **`:6942`** says a sibling is parsed "beside its positional siblings at :5686". I did not check where those siblings actually sit, so I don't call it stale or valid.
- **`:12552`** says `PROMPT_FILE` is rewritten "at :8543". I did not check that either.

Everything else I cite above I read directly at the stated line.

## What I did not verify

- **`set -o pipefail`.** I did not look for it in `handoff-fire.sh`. It matters only for the §2 note on how the bare grep behaves.
- **Whether anything reads the `handoffs.jsonl` refusal rows.**
- **How the dead-recycle tail behaves.** I did not read it, so I can't say whether it records a goal-unreachable row.
- **`--help` and header text at `:17-34` and `:188-207`.** I read them only as comments. They are not evidence of behaviour.
