All paths are relative to `/tmp/s55/repo-47c3317eb`. The brief names `/tmp/o55probe-repo-47c3317eb`, but my rules restricted me to `/tmp/s55/repo-47c3317eb`, so I read only that. Every `path:line` below is a line I read. I hit the 25-call limit and did not open `recycle_engaged`. I also did not check `tests/handoff-goal-arm.bats:305`, which `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:35` cites. Line numbers refer to `scripts/handoff-fire.sh` unless a file is named.

## Summary

`--recycle` does the following, in order:
1. It resolves the predecessor's session id from the pane.
2. It scans that session's transcript for the last `goal_status` attachment.
3. If that record is unmet and not failed, it copies the condition into the global `FIRE_GOAL` and re-runs `check_goal_arm`.
4. It passes `FIRE_GOAL` to the detached watcher as argv #8.
5. The watcher calls `arm_goal` only after it confirms the successor's first real assistant turn.

## 1. The read

**Decision function.** `inherit_recycle_goal() { # $1=predecessor-sid → always 0` is defined at `:5840`.
- Every early exit is `return 0` (`:5842`, `:5843`, `:5844`, `:5845`, `:5846`), and the final line is `return 0` (`:5854`).
- It returns nothing useful. It mutates the global `FIRE_GOAL` (`:5847` sets it, `:5852` clears it), and the caller reads `FIRE_GOAL` afterwards.

**Oracle.** `:5845` is `_inh_cond="$(goal_live_for_sid "$1")" || return 0`. `goal_live_for_sid() { # $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)` is at `:5809`.

**Predecessor identity.** At `:12524`, `rcy_old_sid="$(cc_sid_for_pane "$SID")"`, and `:12540` passes it in. `cc_sid_for_pane` (`:4955`) tries two sources:
- **Registry row (first choice):** it takes the first `"session_id"` match in `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (`:4959-4962`).
- **CC's own per-pid files (fallback):** it globs `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (`:4984`). It requires a live pid (`:4988`) whose `ITERM_SESSION_ID` env ends in `:$_pane` (`:4989-4991`), then reads `"sessionId"` (`:4994`).
- If neither yields an id it returns empty (`:4997`). Then `[ -n "${1:-}" ] || return 0` (`:5844`) makes inheritance a silent no-op.

**Directory roots.** `CC_PROJECTS_DIRS` defaults at `:416` to five roots: `~/.claude/projects`, `~/.claude-next/projects`, `~/.claude-secondary/projects`, `~/.claude-tertiary/projects` and `~/.claude-quaternary/projects`. The environment can override it. The loop is `for pdir in $CC_PROJECTS_DIRS` (`:5814`), and it skips roots that aren't directories (`:5815`).

**Locating the transcript.** `find "$pdir" -name "$sid.jsonl" -type f` (`:5829`, fed to the `while` through the heredoc at `:5828-5830`).
- It matches at any depth, so it finds the per-cwd project subdirectory.
- If several files match, the first hit that yields a non-empty record decides.

**Record used.** `:5818-5819` runs `grep -a 'goal_status' "$hit" | jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'`.
- The answer is the last `goal_status` attachment in file order.
- The `type=="attachment"` filter discards assistant prose that mentions goals.
- It is "live" iff `(.met // false) or (.failed // false)` is `"false"` (`:5823`). It then prints `.condition // ""` (`:5824`) and returns 0.
- Nothing tests `sentinel`, so an ARM marker with `met:false` that was never evaluated counts as live.

## 2. `hooks/lib/goal-state.sh` is not used on this path

`scripts/handoff-fire.sh` never sources it or calls `goal_live_condition` or `goal_liveness`. My grep for `goal-state.sh` and `goal_live_condition` in the file matched only the comment at `:5803`. `goal_live_for_sid` is a duplicate; `:5803-5806` admit this ("duplicated here deliberately").

| | lib `goal_live_condition` (`hooks/lib/goal-state.sh:60`) | recycle `goal_live_for_sid` (`:5809`) |
|---|---|---|
| Input | a transcript path (`:60`); expands `~` (`:63`); requires `-f` (`:64`) | a session id; searches `CC_PROJECTS_DIRS` with `find` (`:5814-5829`) |
| jq and liveness test | `:66-68`, `:70`, `:71` | the same expressions at `:5818-5819`, `:5823`, `:5824` |
| grep leg | `_goal_grep` (`lib:52-58`): `grep -a`, then `[ "$_gg_rc" -le 1 ] && return 0`, so only no-match is neutralised and rc ≥2 still fails | bare `grep -a … \| jq …` (`:5818`), with `\|\| continue` (`:5819`) |

The file runs under `set -euo pipefail` (`:343`), and I read the whole function without finding a reset. So a transcript with no `goal_status` line makes grep exit 1 and the pipeline fail. That is the "absent reported as unreadable" bug the lib's `_goal_grep` header describes (`lib:36-42`).

The hardening changes nothing on the recycle path, for two reasons:
- In the twin, a no-match pipeline failure goes to `|| continue`, and an empty `rec` goes to `[ -n "$rec" ] || continue` (`:5820`). Both then fall through to `return 1` (`:5832`).
- `inherit_recycle_goal` treats every non-zero return as "do nothing" (`:5845`), and nothing on this path distinguishes absent from unreadable.

The only behavioural difference is in search. The twin's `|| continue` keeps looking after a grep or jq error on one file, while the lib returns 1 immediately. I inferred this from the code and did not test it.

## 3. Precedence over an explicit `--goal`

The rule is the first statement of the function: `[ -z "${FIRE_GOAL:-}" ] || return 0` (`:5842`). If `FIRE_GOAL` is non-empty, the oracle is never consulted.

- **The flag:** `--goal) FIRE_GOAL="${2:?--goal needs a condition}"` (`:8950`).
- **The environment also trips the rule:** `FIRE_GOAL="${FIRE_GOAL:-}"` (`:508`) seeds the variable from an exported `FIRE_GOAL`. The header comment at `:34` says this too, but `:508` is what settles it.
- **An empty `--goal` is impossible.** `${2:?}` also rejects a null value.
- **A `--goal` condition is checked earlier.** An explicit or env `FIRE_GOAL` is checked by `check_goal_arm || exit 1` at `:9015`, before any side effect, so a bad explicit goal aborts the recycle. An inherited one only gets dropped (see item 6).
- **Where `--goal` gets discarded.** The `--resume-launcher` branch at `:12535-12538` runs `FIRE_GOAL=""` unconditionally. That discards an explicit `--goal` too, not only inheritance. I did not check whether `--goal` combined with the resume launcher is refused elsewhere.

## 4. The opt-out

- **Name and default:** `CC_RECYCLE_GOAL_INHERIT`, default `1`.
- **Comparison:** `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (`:5843`). Inside `[ ]` this is a string comparison.
- **Turns inheritance off:** only the exact string `0`.
- **Does not turn it off:** unset; empty, because `:-` turns an empty value into `1`; `1`; `off`; `false`; `no`; `00`.
- **Doc discrepancy:** `docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md:170` says "disabled with `=off`/`=0`". The code honours only `0`.
- **Where it is read:** it is read in the foreground at `:12540`. The watcher never consults it.

## 5. Terminal or absent predecessor goals

- **Terminal (met or failed):** the last record has `met` or `failed` true, so `:5823` is not `"false"`. The function falls to `return 1` at `:5827` and stops searching (the comment at `:5821-5822` says so, and the code agrees).
- **`/goal clear`:** the oracle has no `sentinel` branch, so a clear marker is terminal only if it carries `met:true`. That is asserted at `hooks/lib/goal-state.sh:21-22`, which is a comment. I did not confirm it from code.
- **Never armed:** with no `goal_status` line, grep exits 1 and the pipeline fails, so `|| continue` (`:5819`). A prose-only file gives an empty `rec`, so `continue` (`:5820`). In both cases the search keeps going through remaining hits and roots, then `return 1` at `:5832`.
- **Also `return 1`:** an empty sid (`:5811`), no `jq` (`:5812`), or no file found (`:5832`).
- **Live:** `return 0` at `:5825` after printing the condition.
- **Empty condition:** a live record with an empty condition is dropped at `:5846`.
- **What the caller does:** `inherit_recycle_goal` returns 0 with `FIRE_GOAL` still empty, and prints and records nothing.

## 6. Validating an inherited condition

**Validator.** `check_goal_arm` (`:5734`), called with no arguments at `:5848`. It reads the global `FIRE_GOAL`, which `:5847` has just set (`:5735`), and `GOAL_MAX_CHARS` (default 4000, `:5735`).

**Rejections (each returns 1):**
- **A newline** (`:5745-5749`). The arming paste submits at the first CR and would strand the rest in the composer (`:5746`).
- **A leading `/`** (`:5754-5758`). The line is pasted as `/goal <cond>`, so the condition would read as another command (`:5755`).
- **More than the cap in characters** (`:5759-5765`). The harness hard-caps at that length and sets nothing (`:5761`).

An inherited condition ending in a newline passes validation, because `$(…)` at `:5845` strips trailing newlines.

**On refusal:**
- `:5851` echoes `⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself…` to stderr.
- `:5852` sets `FIRE_GOAL=""`, and `:5854` returns 0, so the recycle continues.
- The empty goal goes to the watcher (`:12628`), where `arm_goal` returns silently on an empty condition (`:5867`) and `goal_unreachable` is a no-op (`:5802`).

**Who can read it.**
- The `:5851` message goes to fd 2 of the foreground `handoff-fire` process, so only whoever launched `--recycle` sees it.
- On a self-recycle that is the session about to be replaced. The comment at `:12496-12497` says this about a neighbouring refusal, and I am applying the same reasoning here.
- The `:5851` branch has no `cc-notify` call and nothing addressed to the successor.

**Is a record written?** Yes, but not by `:5851`. `check_goal_arm` itself calls `emit_fire_refusal` on each failing branch (`:5748`, `:5756`, `:5763`).
- `emit_fire_refusal` (`:758-759`) calls `emit_fire_event refused …`.
- That appends a JSON row to `$HOME/.claude/logs/handoffs.jsonl` (`:683`, `:711`), unless `CC_FIRE_REFUSAL_LOG=0` (`:684`).
- The row has `engaged:false`, `refuse_reason` set to `payload-goal-arm-multiline`, `-slash` or `-cap`, `gate:"payload"` (`:742`) and `verdict:"refuse"` (`:703-705`).
- The detail text is hard-coded to "--goal condition is …" (`:5748`, `:5756`, `:5763`). It does not say the condition was inherited and does not include it.
- The stderr text from `check_goal_arm` (`:5746-5747`, `:5755`, `:5761-5762`) also says "--goal … Fix: --goal '…'", which is misleading for an inherited condition.
- No `goal-arm` row is written, because `arm_goal` exits at `:5867` before `emit_goal_event`.
- I did not check whether the per-fire telemetry row (`goal_requested`, `:870`) is emitted on the recycle path.

## 7. Where it sits and how the goal reaches the successor

**The call site.** The only call is `inherit_recycle_goal "$rcy_old_sid"` at `:12540`, inside `recycle_fire()` (`:12354`), which is called once, at `:12964`. The first column-0 `}` after `:12541` is at `:12747`, so the call is inside the function. Other mentions of the name are the definition and comments (`:4824`, `:5837`, `:12531`).

**Before the call:**
- The composer gate runs first (`:12467-12507`), then the ordering comment (`:12508-12523`).
- `:12524` resolves the predecessor sid.
- `:12535` is the `if [ -n "$RESUME_LAUNCHER" ]` test.

**The skipping branch.** `:12535-12538` runs `FIRE_GOAL=""` when a resume launcher is set. The reason is at `:12536-12537`: a same-uuid `--resume` carries an unmet goal with it, so inheriting would arm it twice. That is a comment; the code is the unconditional blanking, and `inherit_recycle_goal` is never reached on that arm. This answers the open question at `docs/research/voluntary-inplace-switch-2026-09-22/A03-precheck-healthy-source.md:96` and `:348`.

**After the call:**
- `RCY_T0` is set (`:12542`), then `pin_term_verdict_for_watcher` (`:12543`).
- The submit-token derivation follows (`:12555-12627`).
- Then the detach at `:12628`.

**Transport:**
1. **Hand-off.** `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (`:12628`). This re-execs the script; `:6938` is `if [ "${1:-}" = "__recycle" ]`. The goal is positional #8. It is not in the environment, the brief, or the relaunch command. The only `FIRE_GOAL` references in the file are the ones I grepped (`:508` … `:13233`).
2. **Read-back.** `RCY_OLD_SID="${6:-}"`, `RCY_MARKER="${7:-}"`, `FIRE_GOAL="${8:-}"` (`:7156-7158`).
3. **When it is armed.** The watcher types the relaunch and waits for the process. It then loops up to `RCY_ENGAGE_TIMEOUT` (`:7339`) until `recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"` succeeds, or `resume_engaged` in resume mode (`:7358-7359`). The sequence is:
   - `:7360` prints "ENGAGEMENT CONFIRMED".
   - `:7365` runs `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"`.
   - `:7368` emits `recycle-engaged`.
   - So the goal is armed after the successor's first real assistant turn, not at launch.
   - If it never engages, `goal_unreachable recycle-dead` runs (`:7397`; also `:7333`, `:7446`) and nothing is armed.
4. **How the arm works.** `arm_goal` (`:5864`) returns silently on an empty condition (`:5867`). Otherwise `it2_paste_submit_verified "$it2" "$pane" "/goal $cond"` (`:5886`).
   - Return codes 3, 4 and other are the held, mangled and abstained verdicts. Each emits a ledger row and a `cc-notify` to the pane (`:5887-5903`).
   - On rc 0 it polls `goal_armed_for_pane` (`:5905-5906`) for `FIRE_GOAL_VERIFY_TIMEOUT` (default 45s, `:5866`).
   - The poll looks in the successor's own transcript for a `goal_status` with `met==false` and `condition==$cond` (`:5792`). A match gives `verdict=set` (`:5907`), and a timeout gives `unverified` (`:5915`).

## Stale line citations

The actual anchors are the definition at `:5840`, the call at `:12540`, the resume-branch blanking at `:12535-12538`, and the watcher's arm at `:7365`. I read each cited line in `scripts/handoff-fire.sh` and none of them resolves to this machinery. The exception is `:5805`, which sits inside the oracle's header comment, not on the decision function.

| Citation | Where it is cited | What the line actually is |
|---|---|---|
| `inherit_recycle_goal (:5089, called at :11070)` | `scripts/handoff-fire.sh:4824` | `:5089` is a comment about a refusal naming each agent; `:11070` is a worktree `claim` line |
| `:5805`, `:11070` | `A03-precheck-healthy-source.md:96`, `:348` | `:5805` is in the oracle's header comment, 35 lines above the decision function; `:11070` is unrelated |
| `:12406-12412 → :5805` | `A05-recycle-engagement.md:106` | `:12406` is an `as_tty_classified` line and `:12412` a "session not found in iTerm2" error; the real branch is `:12535-12538` |
| `:4676-4684` | `CLAUDE.global.md:223`; `docs/research/exhaustive-drive-2026-09-08/CRITIC.md:62`, `:305`; `SYNTHESIS.md:37` | `:4676` is a comment about cc-reaper's `find_transcript`; `:4684` is `for pdir in $CC_PROJECTS_DIRS` in another function |
| `:4642` (`goal_live_for_sid`) | `CRITIC.md:63` | a bare `#` line |
| `:4671-4688` | `hooks/goal-inert-watch.sh:36` | a stamp-recovery comment, then another `for pdir` loop |
| `:3778-3800` | `recon-wave.md:35`, `:169` | a `pid_is_cc` comment and an `ps -o tpgid=` line |
| `:3574` (`goal_live_for_sid`) | `docs/plans/LIVENESS_DETECTOR_FAILNEG.md:208` | a `1:custody) return 0 ;;` row |
| `:4994-5009` | `docs/plans/NONLIMIT_RESUME_LADDER.md:753` | `:4994` is `cc_sid_for_pane`'s `sessionId` read; `:5009` is a comment |

The claims those citations support are mostly correct in substance. The `A07-clean-code-standards.md:170` `=off` claim is wrong on substance, as covered under item 4.
