# U09 — LIMIT_RECOVER_100P.md: plan claims vs. 2026-09-19 measured behaviour

**Verdict.** The plan is `status: complete` on an acceptance of **n=1** — one throwaway session, one
turn old, in a pane the E2E itself had just spawned runner-rooted (plan:270-287). Today's first
production run was **n=5, 1 RECOVERED / 4 PARTIAL**, and the one success was an artefact of a stale
refusal counter, not of the design. Four of the five §7/§8 claims that carry the plan's DoD are
refuted by a single composition the plan never modelled: **the driver gates with a NON-charging
probe in its own process, and the relaunch is re-gated by a CHARGING copy of the same gate in a
different process that inherits none of the driver's environment.** Everything the operator asked
for today — screenshot identification, one command, non-blocking invocation, no abandoned husks,
latency/token budgets — is **not a regression against this plan; it was never in its scope.** The
plan contains the word "screenshot" exactly once, inside the operator quote (plan:10), and the words
latency/second/minute/token appear in no requirement anywhere.

---

## 1. The decisive measurement — `~/.claude/autonomy/idl.jsonl`, 2026-09-19

`grep '"caller":"lr-fire-resume"' ~/.claude/autonomy/idl.jsonl` (15 rows lifetime, 8 today) and
`grep '"caller":"lr-fleet"'` (40 rows today). Verbatim, in time order, with the fleet result rows
from `~/.reso/limit-recover/fleet/one-*/results.tsv` interleaved:

| time (UTC) | caller | verdict | detail |
|---|---|---|---|
| 17:05:38 → 17:15:38 | lr-fleet | **31× `refuse probe`** | `load 99.60 on 10 cores = 9.96/core > ceiling 2.0/core (probe — budget untouched)` … decaying to 6.7/core |
| 17:15:48 | — | **PARKED** | `d02d8feb 112 112 next4 next2 parked capacity` (600 s cap, `LR_FLEET_CAP_WAIT_S:-600`, lr-fleet.sh:283) |
| 17:19:59 | lr-fire-resume | refuse measured load | `2.86/core > 2.0` — **`(refusal 3 of budget 3)`** |
| 17:20:48 | lr-fire-resume | **admit `budget-expired`** | `load term over after 3 consecutive refusals — admitting and paging: 2.72/core` |
| 17:21:05 | — | **RECOVERED** | `d02d8feb 112 112 next4 next2 recycle-in-place/RECOVERED` |
| **17:22:03** | **lr-fleet (probe)** | **admit `headroom-only`** | **`load term off` · 6 sessions mid-turn** |
| **17:22:17** | **lr-fire-resume** | **refuse `measured` load** | **`load 25.70 on 10 cores = 2.57/core > ceiling 2.0/core (refusal 1 of budget 3)`** |
| 17:23:07 | lr-fire-resume | refuse measured load | `2.54/core` — `(refusal 2 of budget 3)` |
| 17:23:54 | — | **PARTIAL** | `09e64dcb 111 111 next4 next3 recycle-in-place/PARTIAL` |
| 17:26:24 | lr-fire-resume | admit measured | `1.61/core` — the operator's **manual** third attempt |
| 17:44:39 / 17:44:55 / 17:45:45 / 17:46:35 / 17:47:14 | fleet probe **admit (load term off)** / refuse / refuse / **PARTIAL** `e442434c 121` / manual admit `headroom-only, load term off` | | identical shape |
| 17:49:36 / 17:49:47 / 17:50:37 / 17:51:26 / 17:51:43 | same | | identical shape, `28f07827 114` |
| 17:52:54 / 17:53:06 / 17:53:55 / 17:54:45 / 17:55:00 | same | | identical shape, `cb227486 117` (peak `6.73/core`) |

**Three facts fall out of this table and each kills a plan claim.**

**(a) 14 seconds apart, the same gate on the same box returned opposite verdicts.** 17:22:03 lr-fleet
probe: `load term off`. 17:22:17 lr-fire-resume: `load … > ceiling 2.0/core`. The lead's
`CC_ADMIT_LOAD_TERM=off` was in the lr-fleet process's environment; the relaunch is **typed as text
into another pane's shell** (`handoff-fire.sh:6789 it2_type_verified … "$(cat "$CMDFILE")"`), and a
typed command line inherits the *pane's* environment, never the driver's. The plan's §4 constraint
and the command doc's fleet §2 both assert the probe makes this safe — "*a pane is never `/exit`ed
unless its relaunch can be admitted*" (`commands/limit-recover.md:420-422`). It is structurally
incapable of that assurance, for **two independent reasons**: different process ⇒ different env, and
non-charging probe ⇒ cannot predict a verdict that depends on a **charging** counter's state.

**(b) The watcher makes 2 attempts; the budget releases on the 3rd.** `handoff-fire.sh:6810-6816`:
15×3 s = 45 s wait, one retype if still `at_shell`, another 15×3 s = **90 s / 2 launcher
invocations**. `capacity-admit.sh` default `CC_ADMIT_BUDGET=3` (line 92). All four failures show
*exactly* `refusal 1 of budget 3` then `refusal 2 of budget 3`, ~50 s apart, then the fleet row goes
PARTIAL ~50 s later. **The bound that makes the gate "delayable but never permanently blockable"
(`lr-fire-resume.sh:306-309`) releases one attempt after the watcher has already given up.** The gate
is bounded; the *composition* is not.

**(c) The one RECOVERED session succeeded on a two-day-old counter.** d02d8feb's 17:19:59 row reads
`refusal 3 of budget 3`, releasing at 17:20:48 as `budget-expired`. The preceding lr-fire-resume
refusal in the IDL is **2026-09-17T23:58:51Z** (`refusal 2 of budget 3`, a different session on
next2). The counter is keyed per **caller**, not per session or per run
(`_cc_admit_state_file "$caller"` → `~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals`,
capacity-admit.sh:510-513) and resets only on an admit. So the single success in five was bought by a
stale refusal left over from two days earlier. **1/5 is the measured success rate and it is not even
1/5 by design — it is 0/5 by design plus one carry-over.**

---

## 2. Gap table — every plan claim today refuted or never covered

Class: **R** = refuted by today's evidence · **U** = never covered (no requirement, no test) ·
**V** = vacuous (the stated proof cannot fail) · **D** = deferred/dropped by the plan itself.

| # | Plan claim (verbatim) | Where | Today's evidence | Gap | Class |
|---|---|---|---|---|---|
| 1 | "*engagement proven by a fresh non-error assistant turn in the target's copy*" | `commands/limit-recover.md:427-428`; plan:287 | 4 of 5 never reached the engagement check at all — they died in the **earlier** gate, "`relaunch typed but no claude process appeared within 90s`" (all four `.stderr`, e.g. `fleet/one-20260919T172126Z/09e64dcb….stderr`) | Engagement verification is downstream of a process-birth wait the plan never sized. The plan's acceptance exercised only the path where birth succeeds | R |
| 2 | "*no husk, no orphan*" (frozen scope, plan:18-21; repeated `commands/limit-recover.md:407-408`) | plan:20 | 4 husks in one run: "*the source pane is a tombstoned husk (handed-off-session-guard blocks its prompts)*" — identical line in 4 `.stderr` files | The in-place path **creates** the exact artefact §1-§2 was written to abolish, whenever the relaunch fails after the transplant. Transplant is irreversible and happens first (§7.4 ordering: "transplant → `/exit` → relaunch") | R |
| 3 | "*the pane IS the continuation*" (title; plan:286 "*measured*") | plan:5, 51-56, 286 | For 4/5 the pane held **no process** after the run. `results.tsv` still printed `111 111`, `121 121`, `114 114`, `117 117` | The report's "pane before == pane after" column is printed from one variable — `pane_after="$pane"` at `lr-fleet.sh:327`, changed only for REPLACED/spawn (328-332). It reads identical on total failure. **A proof that cannot fail is not a proof** | R + V |
| 4 | "*the fleet report proves it per session (pane before == pane after)*" | plan:149-150 | see #3 | Same vacuity; §7.7's answer to Q5/Q6 rests on it | V |
| 5 | "*recoveries run one at a time behind it [`cc_capacity_probe`]; the 3-refusal budget is never spent by asking*" | plan:152-153 | True of the probe (31 `probe` rows, `budget untouched`) and **false of the recovery**: 8 charging `lr-fire-resume` refusals today, budget spent to exhaustion twice | The probe protects the budget of a caller (`lr-fleet`) that was never going to spend it. The caller that spends it (`lr-fire-resume`, in the pane) is un-probed and un-sequenced | R |
| 6 | "*a fleet recovery fires N resumes at once and MUST sequence against it rather than spending its 3-refusal budget*" (the §4 hard constraint) | plan:88-90 | ditto | The constraint was implemented on the wrong side of the pane boundary | R |
| 7 | "*the capacity gate refuses a resume above 2.0 load/core*" treated as the thing to sequence against | plan:88-89 | `capacity-admit.sh:149-159`: "*`load1 does not move with the spawn it gates`… the **INPUT** is wrong, not the number. The load term therefore DEFAULTS OFF in `capacity_gate()` … and has been off on the Agent-tool path since Wave D*" — yet `cc_capacity_admit` still defaults it **ON** (`[ "${CC_ADMIT_LOAD_TERM:-on}" = off ] \|\| CC_ADMIT_TERMS="load"`, line 555) | The plan accepted a term its own library documents as wrong-input, and built a 600 s wait loop around it instead of turning it off for this caller. **Every refusal today, without exception, was the load term** (8/8 IDL rows, `term:"load"`) | R |
| 8 | "*sequenced, one session at a time, each behind the NON-charging capacity probe*" — framed as a virtue | `commands/limit-recover.md:418-422` | `lr-fleet --one` wall time from run-dir mtime to `results.tsv` row: **1.9 / 2.5 / 2.5 / 2.6 / 2.6 min**, plus one **11.0 min** park (17:04:50→17:15:48). Bounds: `lf_capacity_wait` 600 s (lr-fleet.sh:283) then `recycle_await_verdict` `max = 600 + 180 + 120 = 900 s` (handoff-fire.sh:11788) | The invocation is **synchronously blocking for up to 25 min per session**, in the caller's Bash tool. The plan has no non-blocking requirement and no latency budget; "sequenced" is stated as correctness with its cost unpriced | U |
| 9 | Q5/Q6 — "*with an in-place recycle nothing new appears and nothing is left over, so the 'which pane' question cannot arise*" | plan:149-151 | The question arose in a new form: the operator had to identify panes from **screenshots**, and three candidate sessions shared the cwd basename `claude-infrastructure` | The plan dissolved *provenance of new panes* and never addressed **identification of a halted pane from what is on screen** — the operator's actual entry point | U |
| 10 | Identification from a screenshot | **absent** — "screenshot" occurs once, in the operator quote at plan:10 | Statusline renders `GLYPH_PREFIX + PCT_SEG + OUTPUT` = instance-N glyph · context % · cwd **basename** · git short sha · effort (`statusline.sh` final `echo -e` line; glyph at 325-340). Registry rows carry `{paneUUID, name, cwd, account, pid, session_id, surface, lstart}` (`jq keys ~/.claude/cc-registry/140.json`) | **The two sides share only (account, cwd-basename), which is not unique.** The screenshot's discriminators (git sha, context %) are in no registry; the registry's discriminators (pane, sid) are on no screen. No requirement, no code, no test | U |
| 11 | "*Autonomous resume is prompt-free at the SOURCE (no human in the loop)*" + the **verified submit** ("*re-send CR until the running-turn indicator appears*") | `commands/limit-recover.md:22-23, 389-393`; implemented `lr-fire-resume.sh:564-581` | Pane 111 sat with the ingest prompt in the composer, **unsubmitted**, through three waits of 6 + 4 + 3 min. `cc-pane send` delivered nothing (shell-mode); `it2 session send CR` did nothing; `kitty @ send-text <text>` + `'\r'` worked; a literal ESC cleared the composer; `kitty @ send-key ctrl+u` rendered as literal `^[[117;5u` (lead's transcript, T2) | The verify-submit loop lives **inside `expect`, downstream of the capacity gate at `lr-fire-resume.sh:324`**; on a refused or hand-restarted relaunch it is never reached, and nothing else on the box owns "a prompt is sitting unsubmitted". Its only failure output is `send_user "WARNING — prompt may not have submitted"` into a log nobody reads (line 579-581) | R |
| 12 | "*`DUPLICATE` (more than one live process — resolve with `--duplicates` first, never recover over two writers)*" · plan fix 2: "*The census keeps only leaves*" | `commands/limit-recover.md:416-418`; plan:208-211 | `--locate` labelled two **successfully recovered** sessions DUPLICATE; `--duplicates` said none | Two different definitions in one script. `lr-fleet.sh:217`: `if [ "$n" -gt 1 ] \|\| lr_resume_procs "$sid" …; then disp=DUPLICATE` — **ORs** a registry row with an argv `--resume` process, so one pane whose own process is a resume is always DUPLICATE. `lr-fleet.sh:496-499` (the `--duplicates` arm) correctly subtracts a registry pid that IS a resume pid. The leaf filter (`lr-lib.sh:252`) only collapses the `cc-close-attrib` **parent/child chain**; it never cross-checks against the registry | R |
| 13 | "*The target is `claude-accounts --rank` walked PAST the limited account*" — presented as a settled routing decision | `commands/limit-recover.md:418-420`; `lr-fleet.sh:294-309` | `claude-accounts --rank fable` ranked **next3** first (weekly 11%) while lr-fleet's dry run picked **next**(weekly 98-99%) for both Fable sessions; operator overrode by hand. Measured now, 3 consecutive runs 1 s apart: `route-meta: … k_src=panes k_cap=40 k=8` → next3 rankable; seconds later `k_src=work k_cap=8 k_work=3` → `next3=kmax-concurrency`, **excluded**. The ranker is a time-varying function of live concurrency, not of quota | `lr-fleet.sh:301` runs `"$ACCOUNTS" --rank "$kind" 2>/dev/null` — **the `route-meta:` line and the exclusion list are on stderr and are discarded**. The chosen target is recorded with no rationale, so a wrong-looking pick is unauditable and the operator can only override blind | R |
| 14 | Fault visibility — the plan's own §6 cure: "*Without this, the driver's only signal was a line inside a detached watcher log, 90 seconds after the session had already moved*" | plan:266-267 | The 2026-09-09 preflight cure covers **one** class (missing parser arm). Today's failure class emits **nothing durable**: `handoff-fire.sh:6878-6880` types a comment into the pane, echoes to stderr, `exit 1` — **no `emit_recycle_event`, no `hf_alarm`**, unlike both sibling branches (relaunch-write-failed → `emit_recycle_event` + `hf_alarm recycle-relaunch-failed`, 6795-6797; never-engaged → `emit_recycle_event recycle-dead` + `hf_alarm recycle-dead`, 6873-6875) | The one branch that fired 4/4 times today is the one branch with no disk-visible record. `autonomy-sweep.sh:1921` sweeps handoff alarms by class (`strand-risk · husk-pane · recycle-dead · handoff-orphan`) and `bin/cc-husk-sweep` finds husks — **neither can ever see these four**, because nothing was written. Visible only synchronously, to a caller that was blocking anyway | R |
| 15 | "*The reset poller is the daemon half of the same design*" — the un-blocked, un-classified actuator | `commands/limit-recover.md:437-443, 455-459` | Not used today: all six runs were `lr-fleet --one` from inside a session, `FROM_DAEMON` unset (`lr-fleet.sh:324`). The plan itself **DROPPED** `WatchPaths` on the requests dir, accepting "*≤10 min of latency*" (plan:312-315) | The one path that is non-blocking and classifier-immune costs up to 10 min of latency by explicit decision, so nobody uses it interactively. The plan traded away exactly the property the operator now asks for | D |
| 16 | "*every recovered window is RUNNER-rooted*"; a launcher-rooted source "*is REPLACED in place*" | plan:138-143; `commands/limit-recover.md:429-432` | 0 REPLACED rows today (`grep 'REPLACED in place'` over all 5 `.stderr` → none). All four failures reached `at_shell` and typed, so the shell-root gate passed | The replace path is untested against production panes; the actual failure was *after* a successful type. Not refuted — **unexercised** | U |
| 17 | Acceptance population | plan:270-287 | n=1: pane 695, a **fresh kitty OS-window spawned by the E2E itself**, session age ≈ 1 turn, `next4→next3`, no subagents, the box quiet enough for the load term to pass. Today: n=5 long-lived operator-launched panes, 3 in real worktrees, **one with a live in-flight subagent** (`fleet/one-20260919T174851Z/…stderr`: "*⚠ recycle proceeding with 1 IN-FLIGHT subagent(s) … they are being KILLED deliberately*"), box at 2.1–6.7 load/core | The control fixture never reached the regime the bug lives in (memory `control-fixture-must-reach-the-bugs-regime`). A green n=1 E2E closed the plan | R |
| 18 | Token/latency/effort budget | **absent** | 98.7 min wall, 146 tool calls, 68.8 min inside tool calls for 5 sessions; 24.4 min in wait/poll alone | The plan has no cost DoD of any kind. `grep -i "latenc\|second\|minute\|token" docs/plans/LIMIT_RECOVER_100P.md` returns only prose about the E2E and the dropped `WatchPaths` item | U |

---

## 3. What the plan explicitly deferred, dropped, or left open

| item | plan line | disposition recorded | still true today |
|---|---|---|---|
| launchd `WatchPaths` on the requests dir | 180-181, 312-315 | **DROPPED** — "*an operator step to buy ≤10 min of latency on a path that already has a manual accelerator*" | Yes, and it is now the binding constraint on the daemon route the operator wants (gap #15) |
| `pane_shell_root` login-wrapper false-YES | 143-144, 178-180, 306-311 | **DRIVEN** (4 red-proof cases, `tests/handoff-recycle-pane-survives.bats` §3b) | Unexercised today — all four panes passed `at_shell` |
| tmux `lr-resume-*` orphans (6) + 616/630 duplicates | 181-182, 231-239, 288-299 | filed as 6 operator rows, all `done` by 2026-09-10 | Closed; the `--locate` DUPLICATE mislabel (gap #12) is a **different** defect and is open |
| pane 616 retirement | 290-295 | REFUSED by design — `self-close` needs a live claude on the successor pane's own tty; tmux-nested successor invisible (ttys045 vs ttys049). "*Not 'fixed' — that check is one of the protections this wave is forbidden to weaken*" | The same protection is why today's 4 husks could not be auto-retired either |
| in-flight subagents of a transplanted source | `.stderr` line, all 5 runs: "*in-flight subagents of <sid> (if any) are re-audited by the ingest, not protected here*" | never stated as a plan item at all | Fired for real today on pane 114 — one subagent killed deliberately. No plan requirement covers the loss |
| `git cherry`-class provenance of the recovered work | — | — | Iron rule 7 (recovery never lands) unchanged and unbroken today |

---

## 4. The four operator targets, mapped to plan coverage

| operator target (today) | plan requirement | nearest existing machinery | verdict |
|---|---|---|---|
| screenshot/keyword → session+pane in <2 s | **none** | `/tmp/cc-telemetry/<sid>.json` already stores **exactly the statusline's fields**: `{session_id, cwd, config_dir, model, effort, pid, window, used_pct, input_tokens}` (written by `statusline.sh:149-158`). A halted session stops rendering, so its row is **frozen at the value the screenshot shows**. Coverage today: 23 `.json` rows; 3 of today's 5 sids present, 2 absent (`ls /tmp/cc-telemetry/*.json \| wc -l` → 23; `e442434c*`/`28f07827*` → no matches) | **U — never specified.** A join key exists and is unused. Caveats: `/tmp` is wiped at boot; the row is overwritten by the successor after recovery; the jq-on-PATH hole (`statusline.sh:45-47`) explains the 2 misses |
| ONE command, in place, verified engaged | plan §2/§7.7 | `lr-fleet --one` | **R** — 1/5, blocking, and the report cannot distinguish success from failure on its own "pane before == pane after" column |
| non-blocking invocation | **none** | `fleet --enqueue` + poller (classifier-immune, non-blocking) — but ≤10 min latency, deliberately (plan:312-315) | **U/D** |
| every failure named, never a fire-and-forget husk | plan:20, §6 preflight | `hf_alarm` classes + `cc-husk-sweep` + `autonomy-sweep.sh:1921` | **R** — the branch that fired 4/4 writes to neither store (`handoff-fire.sh:6878-6880`) |

---

## 5. Open questions (stated as such, not as findings)

1. **Did all four failures die on the capacity gate, or only provably-two-of-them?** The IDL proves
   two charging refusals per session inside each watcher window and a PARTIAL ~50 s later, for 4/4 —
   consistent, but the pane's screen (which holds `✗ capacity-admit: … exit 9`) was not captured, and
   `lr-fire-resume`'s exit code is not recorded anywhere the driver reads. Confirm by capturing the
   pane text at the moment of failure, or by making the launcher write its rc to the run dir.
2. **Does `cc-husk-sweep --resume` do the right thing over a TRANSPLANTED husk?** Its header
   (`bin/cc-husk-sweep:2-11`) describes a husk over a **dead** session and says it "*resolves the
   session AND its account*". A transplanted session is alive in another store; resuming it under the
   source account would be a split brain the tombstone guard should block. Untested composition.
3. **Why does the refusal counter persist across days?** `lr-fire-resume.refusals` was at 2 from
   2026-09-17T23:58Z when today's first recovery ran. Is a per-caller lifetime counter the intended
   semantics for a recovery tool, or should it be per-run?
4. **Is the `--locate` DUPLICATE OR (lr-fleet.sh:217) reachable in a way that blocks a real
   recovery?** `lf_one`'s dispatch at line 399 parks a DUPLICATE row outright. Today the mislabel hit
   *already-recovered* sessions; whether it can park a recoverable one was not tested.
5. **Which of the ranker's terms should a recovery honour?** `k_src`/`k_cap` flipping between
   `panes/40` and `work/8` inside seconds changes the answer. A recovery re-homes an *existing*
   session rather than adding one — arguably it should not be priced against a concurrency cap at
   all. Not a finding; a design question the plan never asked.

---

## 6. Exact commands used (re-derivable)

```bash
grep '"caller":"lr-fire-resume"' ~/.claude/autonomy/idl.jsonl | tail -20
grep '"caller":"lr-fleet"'       ~/.claude/autonomy/idl.jsonl | grep 2026-09-19
cat ~/.reso/limit-recover/fleet/one-20260919T17*Z/results.tsv
cat ~/.reso/limit-recover/fleet/one-20260919T17*Z/*.stderr
cat ~/.claude/autonomy/capacity-admit/lr-fire-resume.refusals   # 0 bytes, mtime Sep 19 12:55
claude-accounts --rank fable 2>/dev/null                        # stdout: ranked rows only
claude-accounts --rank fable 2>&1 >/dev/null                    # stderr: route-meta + exclusions
jq -c 'keys' ~/.claude/cc-registry/140.json
cat /tmp/cc-telemetry/09e64dcb-16c7-4c65-8b11-fd854d50f299.json
grep -i "latenc\|second\|minute\|token\|screenshot" docs/plans/LIMIT_RECOVER_100P.md
```
