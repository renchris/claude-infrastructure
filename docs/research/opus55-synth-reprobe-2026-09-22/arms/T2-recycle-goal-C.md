<!-- arm C = claude-opus-5-5 @xhigh · brief T2-recycle-goal · raw worker output, verbatim -->

**Summary.** At `scripts/handoff-fire.sh:12540`, `recycle_fire` calls `inherit_recycle_goal "$rcy_old_sid"`. That function asks `goal_live_for_sid` for the predecessor's live condition. `goal_live_for_sid` is a copy of `hooks/lib/goal-state.sh::goal_live_condition`, not a call to it. If a condition comes back, it goes into the global `FIRE_GOAL` and is checked again by `check_goal_arm`. `FIRE_GOAL` then travels as the 8th positional argument to the detached `__recycle` watcher. The watcher pastes `/goal <cond>` into the successor pane only after it sees a real assistant turn.

Several line-number citations for this code in the repo's own comments no longer match the code (section 8).

---

## 1. The read

**Decision function.** `inherit_recycle_goal` is defined at `scripts/handoff-fire.sh:5840-5855`.
- **Return contract:** it always returns 0. Every exit is `return 0` (`:5842`, `:5843`, `:5844`, `:5845`, `:5846`, `:5854`). Its header says "Mutates FIRE_GOAL; always 0 (inheritance must never fail a recycle)" (`:5835-5837`).
- **Result:** it only works by side effect.
  - It sets `FIRE_GOAL="$_inh_cond"` (`:5847`).
  - It clears it with `FIRE_GOAL=""` if validation refuses (`:5852`).
  - It prints `→ goal INHERITED from predecessor $1 …` to stdout (`:5849`) or a `⚠ … NOT inherited` line to stderr (`:5851`).

**Oracle.** The function runs `_inh_cond="$(goal_live_for_sid "$1")" || return 0` (`:5845`). `goal_live_for_sid` is defined at `:5809-5833`. It takes a session id and returns rc 0 plus the condition on stdout, or rc 1 for "none (or terminal, or unreadable)" (`:5809`).

**How the predecessor's identity is obtained.**
- The argument is `rcy_old_sid`, computed in the foreground as `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`). This happens before `/exit` is typed (`:12725`), while the pane still belongs to the predecessor.
- `$SID` is this pane's own id: `SID="${SESSION_ID:-$(self_pane_id)}"` (`:9786`), verified by `verify_self_pane` (`:9796-9797`).
- `cc_sid_for_pane` (`:4955-4997`) has two sources:
  1. It greps `"session_id"` out of `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4962`).
  2. If that misses, it scans `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (`:4984`). It requires a live pid (`kill -0`, `:4988`), whose `ITERM_SESSION_ID` env ends in `:$_pane` (`:4989-4992`), and takes that file's `sessionId` (`:4994`).
- If the sid is empty, the function stops with `[ -n "${1:-}" ] || return 0` (`:5844`).

**Directory roots searched.** `for pdir in $CC_PROJECTS_DIRS` (`:5814`), skipping any that is not a directory (`:5815`). The default is set at `:416`, in this order:
- `$HOME/.claude/projects`
- `$HOME/.claude-next/projects`
- `$HOME/.claude-secondary/projects`
- `$HOME/.claude-tertiary/projects`
- `$HOME/.claude-quaternary/projects`

It can be overridden from the environment.

**How the transcript file is found.** `find "$pdir" -name "$sid.jsonl" -type f`, fed to the loop through a heredoc (`:5828-5830`). This `find` has no depth limit. By contrast, `transcript_for_sid` uses `-mindepth 2 -maxdepth 2` (`:4690`).

**Which record counts as the answer.**
- `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` (`:5818-5819`).
- The goal is live iff `(.met // false) or (.failed // false)` evaluates to `"false"` (`:5823`).
- If live, it prints `.condition // ""` (`:5824`).

**Which record wins when there are several.**
- **Within one transcript:** the last `goal_status` attachment in file order (`last`, `:5819`).
- **Across files and roots:** the first transcript that yields any record decides. Live gives `return 0` (`:5825`); terminal gives `return 1` (`:5827`). Because `~/.claude/projects` is searched first (`:416`), and the comment at `:414-415` says account 1 mirrors `projects/` into `~/.claude`, a mirrored copy would be read before the `~/.claude-next` copy. That last point is inferred from the search order, not observed.

## 2. `hooks/lib/goal-state.sh`: not on the recycle path

The chain `:12540` → `:5845` → `goal_live_for_sid` never calls `goal_live_condition` (`hooks/lib/goal-state.sh:60-73`). The header at `:5801-5808` calls the copy a deliberate "Twin of hooks/lib/goal-state.sh::goal_live_condition". Caveat: I read roughly half of this 13,381-line file. I cannot rule out `goal-state.sh` being sourced somewhere else in it for another purpose, but it is not on this path.

**Interface differences**
- `goal_live_condition`: takes a transcript **path**, expands `~` (`goal-state.sh:63`), and requires `[ -f ]` (`:64`).
- `goal_live_for_sid`: takes a **session id** and searches every root with `find` (`handoff-fire.sh:5814-5830`).

**What is identical**
- Same jq filter (`goal-state.sh:66-68` vs `handoff-fire.sh:5818-5819`).
- Same liveness test (`:70` vs `:5823`).
- Same condition extraction (`:71` vs `:5824`).
- Same jq-presence check (`:65` vs `:5812`).

**The hardening difference.**
- `goal-state.sh` sends grep through `_goal_grep` (`:52-58`). That helper treats grep's no-match (rc 1) as success and reports only a real grep error (rc ≥ 2) as a failure. It was added because, under `pipefail`, "never armed" was being reported as "unreadable" (`:32-51`).
- `handoff-fire.sh` pipes a bare `grep` into jq (`:5818`) under `set -euo pipefail` (`:343`). So:
  - no match → pipeline rc 1 → `|| continue` (`:5819`)
  - a grep error → `continue`
  - a jq error → `continue`
  - an empty record → `continue` (`:5820`)
  - All of these end at `return 1` (`:5832`).

**What that changes: nothing about whether a goal is inherited.** `goal_live_condition` also returns 1 for every non-live case (`goal-state.sh:62-69`). The three-way distinction `_goal_grep` preserves only matters to `goal_liveness`, which separates "absent" from "unreadable" (`:104-144`, `:120`, `:140-141`). The recycle path never asks that question.

Two behavioural differences remain:
- On the recycle path, an unreadable predecessor transcript and a never-armed one look the same. Both drop the goal silently at `:5845`.
- `goal_live_for_sid` moves on to other files and roots after a corrupt or grep-failing file. `goal_live_condition` returns 1 immediately.

## 3. An explicit `--goal` wins

**How it is enforced.** `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`) is the first test. It runs before the opt-out and before the oracle, so nothing is read when a goal is already set.

**Where `FIRE_GOAL` comes from.**
- `--goal) FIRE_GOAL="${2:?--goal needs a condition}"` (`:8950`). Because of `:?`, the flag can never set it to empty.
- The flag value is validated before the fire by `check_goal_arm || exit 1` (`:9015`). A bad explicit goal therefore **aborts** the recycle, while a bad inherited one is only dropped (`:5852`).

**What else trips the same rule.** `FIRE_GOAL="${FIRE_GOAL:-}"` (`:508`) takes its initial value from the environment. An exported `FIRE_GOAL` in the caller's environment:
- suppresses inheritance, and
- becomes the goal that gets armed (it also passes through `:9015`).

**Resume mode discards even an explicit goal.** The resume branch sets `FIRE_GOAL=""` unconditionally (`:12535-12538`), after `:9015` has already validated it.

## 4. The opt-out

- **Name:** `CC_RECYCLE_GOAL_INHERIT`.
- **Test:** `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`).
- **Default:** 1. Both unset and empty become `1` because of `:-`.
- **Comparison:** an exact string match against `0`. Only the literal `0` turns inheritance off.
- **Values that do not turn it off:** `off`, `false`, `no`, `00`, `" 0"`, and every other value.
- This differs from nearby conventions:
  - The subagent gate accepts `off|0|false|no` (`:5185-5186`).
  - The usage header describes env kill switches as "`=off` restores the prior behaviour" (`:230`).
  - Anyone who generalises from those would not actually disable this one.

## 5. Terminal or absent predecessor goals

The decision is made only on the **last** record (`:5819`), using `(.met // false) or (.failed // false)` (`:5823`):

| Predecessor state | What the oracle sees | Result |
|---|---|---|
| **Met** | `met:true` | `return 1` (`:5827`) |
| **Failed** | `failed:true` | `return 1` (`:5827`) |
| **`/goal clear`** | marker is `sentinel:true met:true` (dictionary at `goal-state.sh:18-22`) | treated as met, not live |
| **Re-armed after being met** | a later `sentinel:true met:false` record | live, because it is last |
| **Never armed** | no attachment: grep no-match fails the pipeline, or the record is empty | `continue` (`:5819-5820`) |

**Stop or keep looking.**
- A terminal record stops the search immediately inside the loop (`:5827`). That matches the comment "stop searching other dirs either way" (`:5821-5822`).
- A never-armed or unreadable transcript keeps the search going through the other `find` hits and roots. It ends at `return 1` (`:5832`). The comment's "either way" does not cover this case.

In every non-live case, `inherit_recycle_goal` returns silently at `:5845`. It prints nothing and `FIRE_GOAL` stays empty.

## 6. Validating an inherited condition

**Which validator, and what it reads.**
- `check_goal_arm` (`:5734-5767`) is called with no arguments (`:5848`), right after `FIRE_GOAL="$_inh_cond"` (`:5847`).
- It reads the global `local cond="${FIRE_GOAL:-}"` and the env `GOAL_MAX_CHARS`, default 4000 (`:5735`).
- This is the same function that validates `--goal` at `:9015`.

**What it rejects, and why.**
1. **A newline** (`:5744-5750`). The arming paste submits at the first carriage return and leaves the rest stranded in the composer (`:5737-5738`, `:5746`). `jq -r` (`:5824`) would pass an internal newline through, so this case is reachable.
2. **A leading `/`** (`:5754-5758`). Pasted as `/goal <cond>`, it would read as another command.
3. **More than 4000 characters** (`:5759-5765`). The harness refuses without setting anything.

**What happens to the condition and the recycle.**
- stderr gets `⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited…` (`:5851`).
- `FIRE_GOAL=""` (`:5852`), then `return 0` (`:5854`). The recycle continues with no goal.
- The watcher receives an empty `$8`, so `arm_goal` returns at `[ -n "$cond" ] || return 0` (`:5867`) and writes no goal-arm row.

**Who can read the refusal.**
- It goes to stderr of the foreground `handoff-fire` process. `recycle_fire` runs in the non-dry `--recycle` branch (`:12915-12964`).
- That process is the recycling session's own Bash call. The remote form requires `--resume-launcher` (`:9775`, `:8990-8991`), which takes the skip branch, so this code only ever runs in the self form.
- A few steps later the same process types `/exit` (`:12725`). The code's own comment says that interrupt kills this very Bash tool (`:12509-12515`).
- The refusal is not in the watcher's log, which is minted at `:12391` and handed to `detach` at `:12628`.
- It is not in the successor's brief, which is assembled at `:10668-10848` before `recycle_fire` is called (`:12964`).
- In practice, the only possible reader is the session that is about to die.

**Whether a record is written.** Yes, but it is mislabelled.
- `check_goal_arm` calls `emit_fire_refusal payload-goal-arm-{multiline,slash,cap}` (`:5748`, `:5756`, `:5763`).
- That becomes `emit_fire_event refused … refuse <gate>` (`:758-760`), which appends to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`).
- The row carries `engaged:false`, `refuse_reason`, `verdict:"refuse"` (`:702-705`) and `gate:"payload"` (`:742`).
- The detail reads "--goal condition is …", although no `--goal` was passed.
- The write is skipped if `CC_FIRE_REFUSAL_LOG=0` (`:684`) or jq is missing (`:686`).
- So a recycle that went ahead is logged as a refused payload fire, and nothing marks the condition as inherited.
- **Denominator skew:** the `recycle-intent` row is emitted at `:12378`, before inheritance (`:12540`). Its `goal_requested` is computed from `FIRE_GOAL` at that moment (`:870`), so it never reflects an inherited goal.

## 7. Where the call sits, and the transport

**The call site.** `:12540`, inside `recycle_fire` (`:12354-12747`). I read all of `recycle_fire` and found no other call in the lines I read.

**Immediately before.**
- `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (`:12524`).
- Earlier: the pane-state switch (`:12419-12456`) and the composer gate (`:12468-12507`).
- In the `shell` arm of that switch, the relaunch is typed immediately and the function returns at `:12446`, before `:12540`. On that path no goal is inherited or armed, including an explicit `--goal`, and `goal_unreachable` is not called.

**Immediately after.** `RCY_T0="$(date -u +%FT%T)"` (`:12542`), then `pin_term_verdict_for_watcher` (`:12543`).

**The branch that deliberately skips inheritance.** `if [ -n "$RESUME_LAUNCHER" ]; then FIRE_GOAL=""` (`:12535-12538`). The reason given is that a same-uuid `--resume` already carries an unmet goal, so inheriting would arm the same condition twice (`:12536-12537`). The usage text (`:188-189`) and the dry-run output (`:12796`) say the same.

A dry run never reaches `recycle_fire` (`:12787` vs `:12915-12964`), so an inherited goal is never previewed.

**Hand-off.**
- `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`). `FIRE_GOAL` is the 8th word after `__recycle`.
- It is not written into the prompt file.
- I did not read `detach`'s body. The argument positions are confirmed by the reading end.

**Read-back.**
- The watcher's entry point is `if [ "${1:-}" = "__recycle" ]` (`:6938`).
- It reads `RCY_OLD_SID="${6:-}"` (`:7156`), `RCY_MARKER="${7:-}"` (`:7157`) and `FIRE_GOAL="${8:-}"` (`:7158`).
- The argv list in the comment at `:6955-6956` matches.

**When it is armed.**
1. The watcher waits for a shell (`:6996-7069`).
2. It types the relaunch (`:7183-7186`).
3. It waits for boot (`:7223-7309`).
4. It polls for engagement (`:7339-7372`).
5. Only when `recycle_engaged` passes (`:7358-7359`) and it has printed "ENGAGEMENT CONFIRMED … (a real assistant turn, not just a process)" (`:7360`) does it call `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (`:7365`).
   - `IT2` is the shim `$HOME/.claude/bin/it2` (`:6963`).
   - No provenance argument is passed.
6. The `recycle-engaged` row follows (`:7368`).

**Inside `arm_goal`.**
- It pastes `/goal $cond` with `it2_paste_submit_verified` (`:5886`), which reports several outcomes (`:5887-5904`).
- It then polls `goal_armed_for_pane` every 3 s for up to 45 s (`FIRE_GOAL_VERIFY_TIMEOUT` / `FIRE_GOAL_VERIFY_INTERVAL`, `:5866`, `:5905-5912`).
- `goal_armed_for_pane` resolves pane → sid with `cc_sid_for_pane` (`:5778`), which by now is the successor's sid. It looks for an attachment with `goal_status`, `met==false` and a condition exactly equal to the one pasted (`:5792`).
- Outcome: `verdict=set` (`:5907-5908`) or `unverified` (`:5915-5916`).

**Consequence (inferred from the ordering).** The successor's first turn runs without the goal. The goal can only act at Stops after it has been pasted in.

**When the watcher fails.**
- These failure paths call `goal_unreachable` (`:801-806`), which logs `verdict=unreachable`:
  - `recycle-unverified` (`:7333`)
  - never engaged (`:7397`)
  - relaunch refused or stale (`:7446`)
- These failure paths make no goal call, so an inherited goal disappears without a goal-arm row:
  - pane vanished (`:7070-7079`)
  - never reached a shell (`:7081-7131`)
  - relaunch write failed (`:7187-7193`)

## 8. Line-number citations that no longer resolve

| Where it is cited | What it claims | What is actually there | What it should point to |
|---|---|---|---|
| `:4824` | `inherit_recycle_goal (:5089, called at :11070)` | `:5087-5090` is a subagent comment; `:11070` is the worktree-pool `claim` line | definition `:5840`, call `:12540` |
| Global CLAUDE.md loaded in this session (I did not open `CLAUDE.global.md` in the snapshot) | `inherit_recycle_goal`, `scripts/handoff-fire.sh:4676-4684` | `transcript_for_sid`'s header (`:4674-4684`) | `:5840` / `:12540` |
| `:6942` | watcher positional arguments "at :5686" | inside the TWO-MESSAGE GOAL PATH comment | `:7153-7158` |
| `:12358`, `:859` | watcher outcome emits at `:4828/:4844/:4861` | the self-retire inheritance block (`:4818-4861`) | e.g. `:7332`, `:7368`, `:7396` |
| `:855` | `recycle-intent` at `:8747` | not that emit | `:12378` |
| `:860` | watcher "invoked positionally at :8827" | self-close announce code | `:12628` |
| `:862-864` | says a positional argument for the brief was deliberately not added | contradicted: `$9` now carries it (`:6945`, `:12628`), as `:662-670` records | — |
| `:663-665` | watcher re-exec at `:6241`, `$9` parsed at `:6248` | not those lines | `:12628`, `:6945` |
| `:7404-7405` | `:6796` / `:6699` / `:6873` | not those arms | `:7187-7193`, `:7070-7079`, `:7390-7399` |
| `:5163-5166`, `:7865-7866` | `:399` always sets `CC_PROJECTS_DIRS` | `:399` is the PANE-SPAWN LOG header | `:416` (the substance, that it is always set, holds) |
| `:10697`, `:11341` | `set -euo pipefail` at `:197` | inside the usage text | `:343` |
| `:12552` | `PROMPT_FILE` rewritten at `:8543` | not that line | `:10846-10847` |
| `:644` | same rewrite at `:7416-7417` | not those lines | `:10846-10847` |
| `:840` | `FIRING_SID` assigned at `:5884` | inside `arm_goal` | `:11279` |

**Citations that do still resolve.**
- "Twin of … goal_live_condition" (`:5803`) → `hooks/lib/goal-state.sh:60`, by name.
- "the same nested-project `find` goal_armed_for_pane uses" (`:5805`) → `:5795`, which matches `:5829`.
