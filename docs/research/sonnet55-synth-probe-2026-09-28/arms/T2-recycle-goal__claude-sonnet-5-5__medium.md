# How `scripts/handoff-fire.sh --recycle` carries a predecessor's live `/goal` onto the successor

All paths are relative to the snapshot root, `/tmp/s55/repo-47c3317eb`. The brief names `/tmp/o55probe-repo-47c3317eb`, but my instructions pinned the `/tmp/s55` path, so I read only that. Every `handoff-fire.sh` line below is code I read. The stale comment citations are collected in the last section.

## 1. The read

- **Decision function.** `inherit_recycle_goal()` is defined at `scripts/handoff-fire.sh:5840` (`inherit_recycle_goal() { # $1=predecessor-sid → always 0`).
  - **Return contract.** It always returns 0, and every path ends `return 0` (`:5842-5846`, `:5854`). Its effect is to mutate the global `FIRE_GOAL`.
  - **Where it mutates.** It sets `FIRE_GOAL="$_inh_cond"` at `:5847`, or resets it to `FIRE_GOAL=""` at `:5852`.
- **Oracle.** It calls `goal_live_for_sid "$1"` at `:5845`, defined at `:5809`.
  - **Its contract** is `# $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)`.
  - **When it aborts.** Every "no" result makes the caller `return 0` through `|| return 0` at `:5845`. An empty printed condition also aborts, at `:5846` (`[ -n "$_inh_cond" ] || return 0`).
- **Predecessor identity.** The caller passes `rcy_old_sid`, set at `:12524` (`rcy_old_sid="$(cc_sid_for_pane "$SID")"`) and passed at `:12540`.
  - **Where `cc_sid_for_pane` looks.** It is defined at `:4955`. It first greps `"session_id"` out of `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4961`).
  - **Fallback.** If that finds nothing, it scans `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (`:4984`) for a live pid whose `ITERM_SESSION_ID` ends in the pane id (`:4988-4991`), then reads `sessionId` (`:4994`).
  - **Empty sid.** An empty result makes `inherit_recycle_goal` a no-op via `[ -n "${1:-}" ] || return 0` (`:5844`).
- **Directory roots.** The oracle loops `for pdir in $CC_PROJECTS_DIRS` (`:5814`) and skips missing dirs (`:5815`).
  - **Default value.** `:416` sets it to five roots: `$HOME/.claude/projects`, `.claude-next/projects`, `.claude-secondary/projects`, `.claude-tertiary/projects` and `.claude-quaternary/projects`.
- **Locating the transcript.** It uses `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`), fed to a `while read` loop through a heredoc. So it finds the file at any depth under a root, not at `$pdir/$sid.jsonl`.
- **Record that counts.** `:5818-5819` runs `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'`.
  - **What that selects.** The record is a top-level `type=="attachment"` line whose `.attachment.type=="goal_status"`.
  - **Why the filter matters.** The `type=="attachment"` filter drops assistant prose that merely mentions goals.
- **Which record wins.** The last `goal_status` attachment in the file (`last`).
  - **Live test.** At `:5823`, `(.met // false) or (.failed // false)` must equal `"false"`. It then prints `.condition // ""` (`:5824`) and returns 0.

## 2. Which library is involved

- **The recycle path does not use `hooks/lib/goal-state.sh`.**
  - **Sourcing.** The only `goal-state` / `goal_live_condition` hits in `scripts/handoff-fire.sh` are the comment at `:5803`. There is no `source` or `.` line for it. The call at `:5845` goes to the local `goal_live_for_sid`.
  - **Verdict.** So the library is not involved. The goal-state library defines `goal_live_condition` (`hooks/lib/goal-state.sh:60`) and `goal_liveness` (`:104`), and neither is called from the fire script.
- **Interface difference.**
  - **Library:** `goal_live_condition` takes a transcript path. It expands a leading `~` (`:63`), requires `-f` (`:64`) and prints the condition with rc 0 only if live. Its output goes through `printf '%s'` at `:71`.
  - **Fire script:** `goal_live_for_sid` takes a session id and resolves the path itself with `find` across `CC_PROJECTS_DIRS` (`handoff-fire.sh:5809-5829`).
- **Implementation difference.** The record selection (`last` attachment) and the live test (`met or failed` must be false) are the same. The library has one hardening that the fire script lacks.
  - **Library:** it wraps grep in `_goal_grep` (`hooks/lib/goal-state.sh:52-58`). That returns 0 for grep rc 0 or 1 and returns 1 only for rc ≥ 2. This keeps a no-match from failing the pipeline under `pipefail`. The `goal_live_condition` pipeline is at `:66`.
  - **Fire script:** it uses a bare `grep -a … | jq …` (`handoff-fire.sh:5818`). `set -euo pipefail` is on (`:343`), so a no-match grep (rc 1) fails the `$(…)`. The `|| continue` at `:5819` then swallows it.
- **What the difference changes.** For this caller, nothing observable.
  - **Absent goal and grep error.** A no-match, or a grep that could not open the file, both end in `continue`. That leads to the next `find` hit or root and finally `return 1` at `:5832`. So the oracle cannot tell "never armed" from "unreadable". The library's three-outcome design exists to tell them apart, but the caller here only needs yes or no.
  - **Fail direction.** Both failure paths end in no inheritance.

## 3. Precedence versus an explicit `--goal`

- **Mechanism.** The first line of the function is `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). If `FIRE_GOAL` is non-empty, the function exits before reading anything.
- **What can set `FIRE_GOAL` besides the flag.**
  - **The `--goal` flag** sets it (`:8950`).
  - **The environment variable** does too. `:508` reads `FIRE_GOAL="${FIRE_GOAL:-}"`, so an inherited `FIRE_GOAL` env var also trips the rule.
- **A related but opposite case: the resume branch.** At `:12535-12538`, if `$RESUME_LAUNCHER` is non-empty the script sets `FIRE_GOAL=""`, and this also discards an explicit `--goal` or env goal.
  - **What it protects.** The comment there says a same-uuid `--resume` carries an unmet goal itself.
  - **What the code does.** The code only shows the blanking. It does not show the resume carrying the goal, which the comment claims.

## 4. The opt-out

- **Name and default.** The variable is `CC_RECYCLE_GOAL_INHERIT`. It defaults to `1` through `${CC_RECYCLE_GOAL_INHERIT:-1}` at `:5843`.
- **Comparison.** The test is `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0`. It is a string comparison against the literal `0`.
- **Which values turn it off.** Only exactly `0`.
- **Which values leave it on.** Unset, the empty string, `1`, `off`, `false`, `no`, `00`, `0 ` and anything else.
  - **Empty string.** `:-` also replaces an empty value with `1`.

## 5. Terminal or absent predecessor goals

- **Met or failed.** The last record has `met` or `failed` true, so the `:5823` test is not `"false"`. Control falls to `return 1` at `:5827`.
- **Never armed.** No `goal_status` line survives the grep and the jq filter. `rec` is empty (`last // empty`), so `[ -n "$rec" ] || continue` fires at `:5820`.
- **Cleared.** `:5821` names "met/failed/cleared" as terminal.
  - **What settles it in code.** A `/goal clear` marker has `met:true`, according to the record dictionary at `hooks/lib/goal-state.sh:22`. That makes it terminal under the `met` test.
- **Does the search continue or stop?** It depends on which case.
  - **Terminal record found:** it stops. The `return 1` at `:5827` exits the whole function, so no other roots or hits are searched. The comment at `:5821-5822` agrees ("stop searching other dirs either way").
  - **No record, or an unreadable transcript:** it continues. The `continue` statements at `:5817`, `:5819` and `:5820` move to the next hit and then the next root. The function then ends with `return 1` at `:5832`.
- **Net effect.** The caller does `|| return 0` (`:5845`), so `FIRE_GOAL` stays empty and the recycle proceeds without a goal.

## 6. Validation of an inherited condition

- **Validator.** `check_goal_arm`, called at `:5848` after `FIRE_GOAL="$_inh_cond"` (`:5847`).
- **How it is invoked.** It takes no arguments. It reads the global `FIRE_GOAL` (`local cond="${FIRE_GOAL:-}"`, `:5735`) and the limit `${GOAL_MAX_CHARS:-4000}` (`:5735`). That is why the code assigns `FIRE_GOAL` before calling it.
- **What it rejects.**
  - **Multi-line conditions** (`*"$nl"*`, `:5745`), reason `payload-goal-arm-multiline` (`:5748`). The message at `:5746` says "The arming paste submits at the first CR", so the rest would be stranded in the composer.
  - **A leading `/`** (`:5754`), reason `payload-goal-arm-slash` (`:5756`). The pasted line is `/goal <cond>`, so a leading slash would make the condition read as a second command. That line is built at `:5886`.
  - **Length over the limit.** `chars=${#cond}` at `:5759` and `[ "$chars" -gt "$limit" ]` at `:5760`, reason `payload-goal-arm-cap` (`:5763`). The limit is 4000 by default.
- **What happens on refusal.** `inherit_recycle_goal` takes the `else` branch (`:5850-5853`).
  - **The condition is dropped.** It sets `FIRE_GOAL=""` (`:5852`).
  - **The recycle continues.** There is no `exit`, and the function returns 0 (`:5854`). The caller has no error check, so the successor launches without a goal.
- **Where the refusal is announced.**
  - **Direct message.** The `⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself…` line goes to stderr (`>&2`, `:5851`).
  - **Reason-specific messages.** `check_goal_arm` also prints its own `!!` message to stderr (`:5746`, `:5755`, `:5761`).
  - **Who can read it.** Only whoever sees the fire script's stderr.
  - **On a self-recycle.** That process runs in the pane about to be replaced. The comment at `:12494-12497` says the same about a different message: the stderr "reaches only the process that refused". That is a comment, not code, so I did not verify the delivery path. The code shows only the `>&2`.
- **Is a record written?** Yes, but only through `check_goal_arm`'s `emit_fire_refusal` call.
  - **The write.** `emit_fire_refusal` (`:758-760`) calls `emit_fire_event refused …`. That appends a JSON line to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`).
  - **Row contents.** The row has `class:"refused"`, `engaged:false` and `refuse_reason` set to one of the `payload-goal-arm-*` names (`:703`).
  - **Gate label.** The gate is `payload`, from `payload-*) printf payload` (`:742`).
  - **Log switch.** It is skipped when `CC_FIRE_REFUSAL_LOG` is `0` (`:684`).
  - **No other record.** The "predecessor holds a LIVE goal…" line itself has no ledger row. I found no emitter call in `inherit_recycle_goal`. The recycle row is therefore an ordinary "refused" row, even though the recycle proceeds.

## 7. Where in the recycle flow the call sits

- **Single call site.** `inherit_recycle_goal "$rcy_old_sid"` at `:12540`. A grep for the name shows only the definition (`:5840`), this call, and comments.
- **Immediately before.**
  - **Sid lookup.** `rcy_old_sid="$(cc_sid_for_pane "$SID")"` at `:12524`.
  - **Composer gate.** Before that, the composer gate refuses the recycle with `exit 1` at `:12505`.
  - **Order.** The comment at `:12508` says the watcher must be armed first and `/exit` last.
- **Immediately after.**
  - **Baseline timestamp.** `RCY_T0="$(date -u +%FT%T)"` at `:12542`.
  - **Watcher pin.** `pin_term_verdict_for_watcher` at `:12543`.
  - **Later setup.** The submit-token derivation runs at `:12597-12609`.
- **The branch that skips inheritance.** The `if [ -n "$RESUME_LAUNCHER" ]` branch at `:12535-12538` sets `FIRE_GOAL=""` and does not call the function.
  - **Why:** the comment at `:12536-12537` says a same-uuid `--resume` carries an unmet goal with it, and inheriting would arm it twice in one session. The header at `:188-189` says the same.
- **Transport to the successor.**
  1. **Handoff.** The condition is passed as an argument to the detached watcher (`:12628`): `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …`.
     - **Why it is an argument.** The watcher is a separate re-exec, so the value crosses as a positional argument, not a shell variable. The comment at `:12511-12515` gives the reason: the caller may be killed at `/exit`.
  2. **Read back.** In the watcher, `FIRE_GOAL="${8:-}"` at `:7158` (comment: `# --goal condition to re-arm as MESSAGE 2`).
     - **Argument numbering.** It is `$8` because `__recycle` itself is `$1`. Here `RCWD` is `${5:-}` (`:7153`), the old sid is `${6:-}` (`:7156`) and the marker is `${7:-}` (`:7157`). In the call at `:12628` the goal is the seventh argument after `__recycle`.
  3. **Armed.** In the poll loop, once engagement is confirmed (`recycle_engaged … ` or `resume_engaged`, `:7358-7359`), it prints `→ relaunched + ENGAGEMENT CONFIRMED` (`:7360`) and then calls `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (`:7365`).
     - **Timing.** This is after the successor has produced a real assistant turn, before the `recycle-engaged` row (`:7368`) and `exit 0` (`:7369`). The successor is never armed before it is proven engaged.
  4. **The paste itself.** `arm_goal` (`:5864`) pastes `/goal $cond` with `it2_paste_submit_verified` (`:5886`).
     - **Empty composer.** It pastes only into a proven-empty composer.
     - **Read-back.** It sends the CR only after the read-back matches. `arm_rc` 3 and 4 give the `held` and `mangled` verdicts (`:5889-5895`).
     - **Empty condition.** An empty `$cond` makes it return 0 immediately (`:5867`).
  - **Dead recycle.** If no engagement is confirmed, the loop ends at the dead path, which calls `goal_unreachable recycle-dead` (`:7397`).
    - **What it does.** It warns and emits a `goal-arm` row with verdict `unreachable` (`:801-804`), but only when `FIRE_GOAL` was non-empty.
- **Explicit `--goal` still goes through validation.** `check_goal_arm || exit 1` runs at `:9015`, before any side effect. That is the only place `exit 1` applies to a goal. It never applies to an inherited one.

## Stale or non-resolving citations

- **Comment at `:4824-4825`:** "inherit_recycle_goal (:5089, called at :11070)". Checked against the code: the definition is at `:5840` and the call is at `:12540`. **Both numbers no longer resolve.**
- **Not checked.** Other line-number citations in comments I saw but did not verify: `:10715` / `:10723` (`:3520`) and `:8543` (`:12552`).
- **`hooks/lib/goal-state.sh` header.** It has no `handoff-fire.sh` line citations. I did not check its `docs/research/…` references.
- **Docs.** I did not open any plan or research docs, so nothing about them is confirmed.
- **Comment versus code.** The comment block at `:5801-5808` says the oracle is a "twin" of `goal_live_condition`. The code confirms the same record selection and the same live test. It does not confirm identical hardening; see section 2.
