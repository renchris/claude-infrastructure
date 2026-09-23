<!-- arm B = claude-opus-5-5 @high · brief T2-recycle-goal · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# How `handoff-fire.sh --recycle` carries a live `/goal` to the successor (snapshot 47c3317eb)

All paths are relative to `/tmp/o55probe-repo-47c3317eb`. Unless noted, "hf" means `scripts/handoff-fire.sh`. The script runs under `set -euo pipefail` (hf:343). Several points below depend on that.

## 1. The read

**Decision function.** `inherit_recycle_goal() { # $1=predecessor-sid → always 0` is defined at hf:5840. Its contract is that it changes the global `FIRE_GOAL` and always returns 0. The header says so: "Mutates FIRE_GOAL; always 0 (inheritance must never fail a recycle)" (hf:5836). Every exit in the body is `return 0` (hf:5842–5846, 5854). Its steps are:
- It returns early if `FIRE_GOAL` is already non-empty (hf:5842), if the opt-out is set (hf:5843), or if no sid was given (`[ -n "${1:-}" ] || return 0`, hf:5844).
- It calls the oracle: `_inh_cond="$(goal_live_for_sid "$1")" || return 0` (hf:5845). An empty result is also a no-op (hf:5846).
- Otherwise it sets `FIRE_GOAL="$_inh_cond"` (hf:5847) and validates it (hf:5848).

**Oracle.** `goal_live_for_sid() { # $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)` is at hf:5809.

**How the predecessor's identity is obtained.** At the call site, `rcy_old_sid="$(cc_sid_for_pane "$SID")"` (hf:12524). Here `$SID` is the pane id, not a session id:
- On the local path it comes from `SID="${SESSION_ID:-$(self_pane_id)}"` (hf:9786) and is then pinned by `verify_self_pane … --recycle` and `SID="$HF_VERIFIED_PANE"` (hf:9796–9797).
- On the remote form it comes from `SID="$RCY_SOURCE_PANE"` (hf:9783).

`cc_sid_for_pane` (hf:4955) converts the pane id to a session id in two steps:
1. It first greps `"session_id"` from `${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json` (hf:4959–4961).
2. If that fails, it scans `${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json` (hf:4984). It keeps only live pids (`kill -0`, hf:4988) and matches the pane through that process's `ITERM_SESSION_ID` env (hf:4989).

**Roots searched.** The oracle loops over `$CC_PROJECTS_DIRS` (hf:5814). The default is `$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects` (hf:416). It skips any root that is not a directory (hf:5815).

**How the transcript is found.** It runs `find "$pdir" -name "$sid.jsonl" -type f` (hf:5829), so a transcript nested in a per-cwd project directory is found. It does not call the file's own `transcript_for_sid` helper (hf:4679). That helper has a `*/*` guard on the sid (hf:4682); the oracle has no such guard.

**Which record counts.** It pipes `grep -a 'goal_status' "$hit"` into `jq -rc --slurp '[ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty'` (hf:5818–5819). Only top-level records with `type=="attachment"` whose `.attachment.type=="goal_status"` count. Assistant prose that merely mentions goal_status is filtered out.

**Which record wins.**
- Within a file, the last matching attachment in file order wins (`| last`, hf:5819).
- Across files, the first transcript that yields any such record ends the search, whether that record is live or terminal. The code is `if … = "false"; then printf … condition; return 0; fi; return 1` (hf:5823–5827), and the comment says "this transcript IS the answer — stop searching other dirs either way" (hf:5821–5822).
- Order is therefore `CC_PROJECTS_DIRS` order, then `find` order.
- The condition is printed with `jq -r '.condition // ""'` (hf:5824).

## 2. `hooks/lib/goal-state.sh` is not used on the recycle path

The script never sources it. The only mention in hf is the comment at hf:5803 ("Twin of hooks/lib/goal-state.sh::goal_live_condition … duplicated here deliberately"). The library is sourced elsewhere: `scripts/wrap-ledger.sh:695`, `hooks/mailbox-drain.sh:67`, `hooks/session-continue.sh:412`.

**Interface difference.**
- `goal_live_condition() { # $1 = transcript path …` (hooks/lib/goal-state.sh:60) takes a path. It expands `~` (:63) and requires `-f` (:64).
- `goal_live_for_sid` takes a session id and locates the file itself (hf:5809, 5829).

**The shared rule.** Both use the same jq selection (goal-state.sh:66–68 vs hf:5818–5819). Both use the same liveness test, `(.met // false) or (.failed // false)` equal to `"false"` (goal-state.sh:70 vs hf:5823).

**Hardening present only in the library.** The library wraps grep in `_goal_grep`, which turns grep's no-match exit (rc 1) into 0 and keeps only real errors (rc ≥ 2) as failures (goal-state.sh:52–57). Its stated purpose is keeping "absent" separate from "unreadable" under pipefail (goal-state.sh:34–51). The oracle uses a bare `grep -a 'goal_status' "$hit" … | jq` inside `rec="$(…)" || continue` (hf:5818–5819).

**What the difference changes.** For this predicate, nothing:
- Under pipefail (hf:343), a no-match makes the pipeline exit 1, and `|| continue` moves to the next file.
- Without the hardening, the result would be an empty `rec`, and `[ -n "$rec" ] || continue` (hf:5820) moves on the same way.
- A grep error and a jq error also `continue`.
- The library's own predicate also returns 1 for both "absent" and "unreadable" (goal-state.sh:68–69).

The hardening only matters for the separate reporting function `goal_liveness` (goal-state.sh:104), which the recycle path does not use. One cosmetic difference: the library prints with `printf '%s'` (goal-state.sh:71), while the oracle prints with `jq -r`, whose trailing newline `$(…)` removes (hf:5845).

## 3. When an explicit `--goal` wins, and what else triggers it

The rule is the first line of the decision: `[ -z "${FIRE_GOAL:-}" ] || return 0` (hf:5842). Any non-empty `FIRE_GOAL` by then counts as "explicit". Two things can set it:
- **The flag:** `--goal) FIRE_GOAL="${2:?--goal needs a condition}"` (hf:8950). An empty `--goal ""` is refused by `:?`.
- **The environment:** `FIRE_GOAL="${FIRE_GOAL:-}"` (hf:508) keeps an inherited or exported `FIRE_GOAL` variable. Such a value blocks inheritance exactly as the flag does, and it is also validated up front by `check_goal_arm || exit 1` (hf:9015).

**Resume mode drops the goal outright, explicit or not.** `if [ -n "$RESUME_LAUNCHER" ]; then … FIRE_GOAL=""` (hf:12535–12538). This clears even an explicit `--goal`, so "explicit wins" does not hold on the `--resume-launcher` path. `--resume-launcher` is only allowed with `--recycle` (hf:8942, 8988).

## 4. The opt-out

- **Name and test:** `[ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0` (hf:5843).
- **Default:** `1`. `:-` also replaces an empty value, so `CC_RECYCLE_GOAL_INHERIT=` (empty) leaves inheritance on.
- **Comparison:** a string `!=` against `0`. Only the exact string `0` turns inheritance off. `off`, `false`, `no`, `00` and ` 0` all differ from `0`, so inheritance stays on.
- **Doc error:** `docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md:170` says it is "disabled with `=off`/`=0`". The `=off` half is wrong.

## 5. Terminal or absent predecessor goals

- **Met, failed, or cleared:** the last record gives `(.met // false) or (.failed // false)` = `true`. The oracle returns 1 and does not look further (hf:5823, 5827). The header says "a terminal goal (met/failed/cleared) inherits nothing" (hf:5821–5822). A `/goal clear` marker carries `met:true` (goal-state.sh:22), so it is also terminal.
- **Never armed, or only prose mentions:** no qualifying attachment is found. The oracle continues to the next file (hf:5819–5820) and then the next root. If nothing is found anywhere it falls through to `return 1` (hf:5832).
- **No sid or no jq:** it returns 1 immediately (hf:5811–5812).
- **Effect on the decision:** `|| return 0` (hf:5845) makes all of these a no-op, and `FIRE_GOAL` stays empty.

## 6. Validation of an inherited condition

**Which validator.** `check_goal_arm` (hf:5734), called with no arguments at hf:5848. It reads the global `FIRE_GOAL`, which was just assigned at hf:5847: `local cond="${FIRE_GOAL:-}" limit="${GOAL_MAX_CHARS:-4000}"` (hf:5735). It is the same function the pre-fire gate uses for an explicit `--goal` (hf:9015).

**What it rejects.**

| Rejection | Why | Log reason | Where |
|---|---|---|---|
| A newline in the condition | "The arming paste submits at the first CR" | `payload-goal-arm-multiline` | hf:5746, 5748 |
| A leading `/` | The pasted text `/goal /x…` would be read as another command | `payload-goal-arm-slash` | hf:5755–5756 |
| Length over `GOAL_MAX_CHARS` (default 4000) | The harness hard-caps a goal condition at that length | `payload-goal-arm-cap` | hf:5761, 5763 |

**What happens on refusal.**
- The condition is discarded: `FIRE_GOAL=""` (hf:5852).
- The recycle continues: `return 0` (hf:5854). The watcher later receives an empty `$8`, and `arm_goal` returns at once on an empty condition (`[ -n "$cond" ] || return 0`, hf:5867).

**Where the refusal is announced.**
- `check_goal_arm`'s own stderr lines (hf:5746–5761). They are worded for a `--goal` flag ("Fix: … --goal '<objective>…'", hf:5747), which is misleading for an inherited condition.
- One extra stderr line: "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session" (hf:5851).

**Who can read it.** Only whoever holds the foreground recycle process's stderr. In the usual self-recycle, that is the predecessor session's own Bash tool. That session is about to receive `/exit`, and the code's own comment says a typed `/exit` "INTERRUPTS the in-flight turn … kills this very Bash tool" (hf:12509–12511). The message is not passed to the detached watcher. The watcher's log gets only the watcher's own output (`stdout=log, stderr=STDOUT` in `detach`, hf:1692–1699). The successor therefore never sees it.

**Record written.** Yes. Each `check_goal_arm` rejection calls `emit_fire_refusal` (hf:5748/5756/5763), which is `emit_fire_event refused … refuse` (hf:758–760). That appends to `$HOME/.claude/logs/handoffs.jsonl` (hf:683) a row with `class:"refused"`, `engaged:false`, `refuse_reason:payload-goal-arm-*`, and `gate:"payload"` (via `payload-*) printf payload`, hf:742). This happens unless `CC_FIRE_REFUSAL_LOG=0` (hf:684) or jq is absent.

The row misdescribes events: it records a refused fire although the recycle went ahead without the goal. The "⚠ … NOT inherited" line (hf:5851) and the success line "→ goal INHERITED …" (hf:5849, stdout) write no rows of their own.

## 7. Where the call sits in the recycle flow, and how the condition travels

**Call site.** There is one: `inherit_recycle_goal "$rcy_old_sid"` (hf:12540), inside `recycle_fire()` (defined at hf:12354, called at hf:12964).

**Immediately before.**
- The composer-draft gate, which may refuse with `exit 1` (hf:12491–12505).
- The predecessor-sid capture at hf:12524, described as "resolved FOREGROUND" so the watcher compares against the pre-recycle value (hf:12520–12522).
- The resume branch that deliberately skips inheritance (hf:12535–12538). Its stated reason: "A same-uuid --resume carries an UNMET goal with it … inheriting it here would arm the same condition twice in one session" (hf:12536–12537).

**Immediately after.** `RCY_T0="$(date -u +%FT%T)"` (hf:12542), then `pin_term_verdict_for_watcher` (hf:12543).

**A second branch that skips it.** If the pane is confirmed to be at a shell prompt, the code types the relaunch and `return 0`s (hf:12441–12446). That happens before hf:12540 and before any watcher starts, so no goal is inherited and not even an explicit `--goal` is armed.

**Transport path.**
1. **Handoff.** The condition is passed as an argument: `detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL" …` (hf:12628). `detach` starts `sys.argv[2:]` in a new session through Python `subprocess.Popen(…, start_new_session=True)` (hf:1692–1699). The `/exit` is only typed after `await_armed` confirms the watcher is running (hf:12629).
2. **Read-back of the argument.** The re-executed script enters `if [ "${1:-}" = "__recycle" ]` (hf:6938), with `RSID="${2:?…}"` being the pane id (hf:6939), and reads `FIRE_GOAL="${8:-}"` (hf:7158). Counting the detach line (`__recycle`=$1 … `$FIRE_GOAL`=$8) confirms the index. `IT2="$HOME/.claude/bin/it2"` (hf:6963).
3. **Arming time.** Only after engagement is confirmed, meaning a real assistant turn from the successor (`resume_engaged` / `recycle_engaged`), does the watcher call `arm_goal "$IT2" "$RSID" "$FIRE_GOAL"` (hf:7365). The degraded branch with nothing to verify against calls `goal_unreachable` (≈hf:7333; defined at hf:801) and does not arm.
4. **Arming.** `arm_goal` (hf:5864) pastes `"/goal $cond"` into the running successor via `it2_paste_submit_verified` (hf:5886).
5. **Proof of arming.** It then polls `goal_armed_for_pane "$pane" "$cond"` (hf:5906), by default every 3 s for up to 45 s (hf:5866). That function resolves pane → sid again with `cc_sid_for_pane` (hf:5778), which by now returns the successor's sid. It finds `<sid>.jsonl` under `CC_PROJECTS_DIRS` and requires an attachment with `type=="goal_status"`, `met==false` and `condition==$c` (hf:5792).
6. **Verdict.** It prints `goal-arm verdict=set` (hf:5907). Otherwise it reports held, mangled, abstained or unverified (hf:5889–5916), and it never fails the recycle.

## Line citations for this machinery that no longer resolve

| Citation | What it claims | What the line holds now | Status |
|---|---|---|---|
| hf:4824 (comment) | `inherit_recycle_goal (:5089, called at :11070)` | :5089 is a comment about agent refusals; :11070 is a `"$POOL" claim` line | Stale. Actual: hf:5840 and hf:12540 |
| `CLAUDE.global.md:223` | `scripts/handoff-fire.sh:4676-4684` | That span is the head of `transcript_for_sid` (hf:4679) | Stale |
| `docs/research/backlog-pipeline-recon-2026-08-12/recon-wave.md:35` and `:169` | `handoff-fire.sh:3778-3800` | A comment about `pid_is_cc` | Stale |
| `docs/research/voluntary-inplace-switch-2026-09-22/A03-precheck-healthy-source.md:96` | `handoff-fire.sh:5805`, called `:11070` | :5805 is inside the oracle's header comment, not either function; :11070 is `"$POOL" claim` | Both stale |
| Same file, `hooks/lib/goal-state.sh:60` | `goal_live_condition` | `goal_live_condition` | Resolves |
| hf:5706–5708 (comment, content not a line number) | "`--goal` therefore has to be re-passed on every recycle" | — | Superseded by the inheritance at hf:12540 |