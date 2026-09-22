# A05 — How the pane is recycled onto the new account, and how the successor is engaged and re-identified

**Scope.** A VOLUNTARY move of a HEALTHY session: same window, same session uuid, new account.
Read-only investigation of the existing limit-recovery rail; nothing was actuated and no repo file
outside this one was modified. Every claim carries `file:line` against the checkout at
`/Users/chrisren/Development/claude-infrastructure` (branch `main`, HEAD `8e3ab2e38`).

---

## 0. The five findings that decide the design

1. **The voluntary move is already reachable for a SELF-recycle and REFUSED for a driver-recycle,
   and the code says so in as many words.** `lr-handoff.sh:808-810` — *"a healthy session probes
   `REFUSED:not-limited` and exits 5: letting that rc reach the branch above would refuse every
   self-recovery of a session that is merely low on context **or being moved to a fresher
   account**."* The SELF arm (`lr-handoff.sh:797-822`) therefore ignores the probe's rc. The DRIVER
   arm (`lr-handoff.sh:757-771`) does **not**: it returns 6 on any non-zero rc, and
   `--probe-recycle-preconditions` exits 5 `REFUSED:not-limited` for a healthy session
   (`handoff-fire.sh:7833-7836`). The command shape in the brief (`--source-pane P
   --source-session S`) is the DRIVER shape. **This is gate #1 the voluntary path must address.**
2. **`handoff-fire.sh --recycle --transplanted-source` itself has no limitedness gate.** Its five
   preconditions are the pair+class flags, the registry binding, the tty-ancestry pin, the
   transplant tombstone, and tombstone-target == `--resume-cfg` (`handoff-fire.sh:9683-9691`).
   None asks whether the session died. So the voluntary path needs no change to the actuator — only
   to what drives it.
3. **The transplanted-source class force-enables `--allow-live-subagents`, and its justification is
   the ingest that a voluntary move does not run.** `handoff-fire.sh:9716-9723` sets
   `ALLOW_LIVE_SA=1` because *"the ingest audit … is where their partial results are judged."* With
   no ingest, that override silently SIGKILLs live subagents with nothing re-auditing them. **Gate
   #2: the voluntary path must not inherit this.** A healthy session is exactly the population most
   likely to have subagents in flight.
4. **"Submit nothing" is mechanically unsound, in both directions.** With `--prompt ""`,
   `lr-fire-resume.sh:826/854` never sets `injected`, so the whole submit-verification block
   (`:874-984`) is skipped and the session resumes to an empty composer. Downstream:
   with a submit token armed, `resume_engaged` returns 1 because no user record carries it
   (`handoff-fire.sh:3932-3936, 3972`) ⇒ the watcher convicts a perfectly healthy move at 180 s;
   with no token it falls back to wall-clock, where *"a background-task notification, a peer message
   drained at a turn boundary, a Stop-hook continuation"* each satisfy it
   (`handoff-fire.sh:3920-3925`) ⇒ a false ENGAGED over an idle pane.
5. **Neither `/goal` nor a DoD restatement belongs in the successor prompt.** `--resume` restores
   the goal from the transcript (`restoreGoalFromTranscript` / `tengu_goal_restored_on_resume`,
   recorded at `docs/research/goal-condition-best-practice-2026-08-09.md:200`), which is precisely
   why resume mode zeroes `FIRE_GOAL` (`handoff-fire.sh:12406-12412`). The frozen DoD is re-injected
   by `hooks/dod-persist.sh` SessionStart (`:177-228`) from a store at `~/.claude/autonomy/dod`
   (`hooks/lib/dod-path.sh:34`) that is keyed on repo identity and is **not** under
   `CLAUDE_CONFIG_DIR`, so it survives the account hop untouched.

---

## 1. The recycle, end to end

Numbered by the order the code executes. Failure returns are named at each step.

### Phase A — argv and coherence, before any side effect

| # | Step | Site | Refusal |
|---|---|---|---|
| A1 | Parse `--recycle --source-pane --source-session --transplanted-source --resume-launcher --resume-cfg --resume-cwd --await` | `handoff-fire.sh:8864-8872` | — |
| A2 | Every one of those is a `--recycle` flag | `:8912-8915` | **exit 2** |
| A3 | Remote form needs `--resume-launcher/--resume-cfg` | `:8916-8918` | **exit 2** — *"the only thing a transplanted source may be relaunched INTO is its own uuid on the transplant target"* |
| A4 | Launcher/cfg are a PAIR; launcher exists and is non-empty; cfg is a dir | `:8919-8922` | **exit 2** (pair) / **exit 1** (missing file, missing dir) |
| A5 | `--session-id` forbidden; `--prompt-file` forbidden; `--worktree/--cwd` forbidden | `:8923-8925` | **exit 2** each |
| A6 | Payload gates (`check_slash_head`, empty-file, `/goal` cap) are **skipped in resume mode** | `:8927-8938` | — (see §6.2) |
| A7 | `check_goal_arm` | `:8941` | **exit 1** |
| A8 | `capacity_gate` **exempt** — a recycle is net-zero panes | `:8944` | (exit 9 only for non-recycle) |
| A9 | Surface flags excluded | `:9646` | **exit 1** |

### Phase B — the remote binding that replaces self-identity

| # | Step | Site | Refusal |
|---|---|---|---|
| B1 | Resolve which TERMINAL owns `--source-pane`, by **enumerating the pane**, not by walking this process's ancestry (a `detach`ed / launchd driver has no kitty ancestor) | `:9666-9672` → `hf_remote_pane_term:2114` | **exit 2** — rc 1 `REMOTE-PANE-ABSENT`, rc 3 `REMOTE-PANE-RESOLVER-UNAVAILABLE` |
| B2 | `--source-pane` admissible ONLY with `--transplanted-source` | `:9683` | **exit 2** |
| B3 | `hf_remote_source_bind` — `cc-registry/<pane>.json` must name exactly `<source-session>` | `:9685` → `:2027` | **exit 2** (mismatch / no row / row without `.session_id` / no `jq` — `:2031,:2047`) |
| B4 | `hf_remote_source_pin` — the row's pid must be ALIVE with that pane's tty in its ancestry | `:9686` → `:2219` | **exit 2** |
| B5 | `hf_transplant_evidence` — the source sid must carry a transplant TOMBSTONE (`<sid>.HANDOFF.json`) with `.handed_off_to` ≠ its own cfg and the split-brain lock still held | `:9687` → `:2256` | **exit 2** |
| B6 | Tombstone target must equal `--resume-cfg` | `:9688-9691` | **exit 2** — *"a relaunch anywhere but the transplant target is a second live copy"* |
| B7 | `SID := RCY_SOURCE_PANE; RCY_REMOTE=1`; `verify_self_pane` is SKIPPED (replaced, not bypassed) | `:9692-9707` | — |
| B8 | In-flight subagent gate. **`--transplanted-source` force-sets `ALLOW_LIVE_SA=1` here** | `:9716-9724` → `subagent_gate:5156` | **exit 4** — only if the force-set is not in effect |
| B9 | Resume mode pins `LAUNCHER="bash"`, `EXPLICIT_LAUNCHER=1`, `ACCOUNT="(resume)"` — no ranking, no account probe | `:9729-9733` | — |

### Phase C — composing the one line that gets typed

* `CMD = cd <resume-cwd> && nocorrect bash <launcher>` — `handoff-fire.sh:10850`.
  `RCY_CWD` = `--resume-cwd`, else the registry row's cwd, else `$PWD` (`:10848-10849`).
* **`bash`, never `exec bash`** (`:10842-10847`, echoed at `lr-handoff.sh:1020-1022`): the launcher
  runs as a CHILD of the pane's shell, so the zsh stays the pane's root process and the pane is
  recyclable again next time. An `exec`'d launcher is the pane-625/632 shape that can never be
  recycled.
* No prompt copy is made: `ENGAGE_VERIFY` is 0 for every recycle (`:10533`) and `RECYCLE_VERIFY` is
  explicitly 0 in resume mode (`:10538`, *"resume mode verifies by transcript, not marker"*), and
  `hf_recycle_inherits_peer` returns 1 on the remote flag (`:4823`), so the trailer block at
  `:10539` is never entered.

### Phase D — `recycle_fire`, the ordered actuation (`handoff-fire.sh:12225`)

| # | Step | Site | Failure |
|---|---|---|---|
| D1 | Emit `recycle-intent` FIRST — the denominator, before any risky call | `:12248` | — |
| D2 | Mint `$cmdfile` + `$log` in a per-uid 0700 tmp dir | `:12259-12264` | **exit 1** |
| D3 | `pin_term_verdict_for_watcher`, then `as_tty_classified` | `:12269-12284` | **exit 1** — rc 3 is *"resolver CANNOT TELL"*, wording deliberately distinct from rc 1 *"not found in iTerm2"* |
| D4 | `pane_cc_state` — **three** states. `cc` ⇒ proceed · `shell` ⇒ type the relaunch now and return 0 · `unknown` ⇒ REFUSE | `:12290-12327` | **exit 1** on `unknown` (*"Typing on an unconfirmed pane is exactly what put a shell command into a live Claude composer on 2026-08-06"*) |
| D5 | **SURVIVABILITY GATE** — `pane_shell_root` must not answer `no`. A pane whose ROOT process is its own launcher is destroyed by the `/exit` | `:12301-12310` → `:3854` | **exit 1**, message *"has NO shell under its session"* — the string `lr-handoff.sh:1068` greps to switch to REPLACE-beside. Kill switch `CC_RECYCLE_SURVIVE_GATE=off` |
| D6 | **COMPOSER GATE** — ≤180 s wait for an empty composer. This rail's OWN abandoned paste is scrubbed (receipt-matched); a FOREIGN draft defers and then refuses, paging `--role desk` and the pane itself | `:12339-12378` | **exit 1** `recycle-held-draft` |
| D7 | Resolve `rcy_old_sid` in the FOREGROUND (the watcher must not re-derive it or the row-change baseline compares a value to itself) | `:12395` | — |
| D8 | **Goal: `FIRE_GOAL=""` in resume mode** — a same-uuid `--resume` carries an unmet goal with it; inheriting would arm it twice. Non-resume recycles call `inherit_recycle_goal` | `:12406-12412` → `:5805` | — |
| D9 | `RCY_T0` = engagement baseline, UTC `%FT%T` | `:12413` | — |
| D10 | **Submit-token arming gate** — read `LR_SUBMIT_TOKEN` out of the launcher, then prove the token will actually be TYPED: ARM 1 the launcher's own text carries it twice, ARM 2 the program the launcher `exec`s carries `LR_SUBMIT_TOKEN_IN_PROMPT` — checked on the **live** path the launcher names, not this worktree | `:12468-12498` | degrades LOUDLY to the wall-clock oracle with the token dropped |
| D11 | `detach` the watcher — 15 positional args; `setsid`, never `nohup` (a `nohup` watcher dies in the `/exit` process-group reap: 2× 2026-07-13) | `:12499`, `:12379-12386` | — |
| D12 | `await_armed` (heartbeat) | `:12500-12504` | **exit 1**, `/exit` NOT typed |
| D13 | `await_pane_proof` — refused (rc 1) and stalled (rc 2) get different messages | `:12507-12516` | **exit 1** |
| D14 | `write_teardown_marker … recycle` BEFORE the `/exit`, so the crash watchdog reads a PLANNED teardown | `:12521` | — |
| D15 | **Freshness re-read** of the composer, narrowing the type-over-draft race to ~1 s | `:12525-12535` | **exit 1**, watcher disarmed |
| D16 | `as_write "$SID" "/exit"`, 3 attempts across both transports | `:12536-12544` | **exit 1**, watcher disarmed |
| D17 | `--await` (remote only) → `recycle_await_verdict` | `:12552-12559` → `:12569` | **0** engaged · **1** dead/failed · **3** no verdict inside `180+600+180+180+60 = 1200 s` |

### Phase E — the detached watcher `__recycle` (`handoff-fire.sh:6871-7390`)

| # | Step | Site | Terminal state |
|---|---|---|---|
| E1 | `pane_proof` | `:6898` | exit 1 |
| E2 | Poll ≤`HF_RECYCLE_SHELL_WAIT_S` (600 s) for `at_shell`. Every 15 s: `pane_enumerated` vanish probe (only `absent` acts) and the background-work-dialog answerer (≤2 keystrokes, index read off the screen) | `:6929-7002` | — |
| E3 | Pane VANISHED | `:7003-7013` | `recycle-dead` + `hf_alarm`; names the brief and the raw relaunch line. **exit 1** |
| E4 | Never reached a confirmed shell | `:7014-7063` | `recycle-dead` + alarm. `unknown` is explicitly labelled *an ABSTENTION, not a finding* (7 branches of `pane_cc_state` return it). **exit 1** |
| E5 | Fold any re-created source stub into `<sid>.jsonl.handed-off` so no census reads a live-looking copy | `:7066-7081` | — |
| E6 | Clear `relaunch.rc`, record `rcy_typed_at`, type the relaunch via `it2_type_verified` ×2 | `:7110-7119` | on failure: `recycle-dead` + `recycle-relaunch-failed` alarm, **exit 1** (`:7120-7126`) |
| E7 | **Boot wait — three POSITIVE discriminators, no retype.** (1) `relaunch.rc` newer than `typed_at`; (2) an `lr-fire-resume` `verdict:"refuse"` IDL row after `typed_at`; (3) a claude on the tty. 0.5 s tick for the two file reads, pane read every 6th tick | `:7128-7225` | `FAILED:relaunch:rc=<n>` / `FAILED:relaunch:gate` |
| E8 | 60 s with no evidence ⇒ `INDETERMINATE:boot` — *a state and an alarm, never a verdict* — then keep reading to 180 s ⇒ `STALE:boot` | `:7226-7242` | — |
| E9 | Claude is up ⇒ verify ENGAGEMENT (§5) | `:7243-7305` | — |
| E10 | Nothing ever appeared | `:7334-7389` | joins the IDL for the launcher's own refusal (`term=…  basis=…`), writes the row, the alarm, and **paints the verdict to the pane's tty by path** |

---

## 2. Exit codes, collected

| rc | Meaning | Sites |
|---|---|---|
| 0 | armed (self form) / ENGAGED (`--await`) | `:12552-12559` |
| 1 | generic recycle abort — pane unresolvable, `unknown` state, no shell under the session, held draft, watcher unarmed, pane unwritable, `/exit` untypeable; also `--await` DEAD | `:12280-12544`, `:12580-12585` |
| 2 | argv / coherence / remote-binding refusal (every Phase-A and Phase-B refusal) | `:8912-8925`, `:9666-9691` |
| 3 | `--await` **no verdict inside the window** — retry/read the log, NOT a failure | `:12589-12590` |
| 4 | in-flight subagents would be killed | `subagent_gate:5195` |
| 9 | capacity — **unreachable for a recycle** | `:8944` |
| probe 0/3/5 | `--probe-recycle-preconditions`: pass / `HELD:<check>` / `REFUSED:<check>` | `:7755-7894` |
| lr-handoff 4 | in-place recycle did not verify (transplant is DONE, source is a tombstoned husk) | `lr-handoff.sh:1077-1090` |
| lr-handoff 6 | precheck HELD/REFUSED/PARKED — nothing moved | `lr-handoff.sh:754,767-771` |

---

## 3. The successor's identity artifacts

"Successor" = the same uuid, same pane, running under the target `CLAUDE_CONFIG_DIR`.

| Artifact | Store / key | Survives the move? | Who re-creates it | Voluntary-path action |
|---|---|---|---|---|
| **Pane id** (`ITERM_SESSION_ID` / `KITTY_WINDOW_ID`) | the terminal | **Yes** — the relaunch is typed into the pane's own shell, which already holds it; the `expect` spawn's env filter unsets only `CLAUDE_CODE_CHILD_SESSION`, `LR_*` and `CC_ADMIT_*` (`lr-fire-resume.sh:725-727`) | the pane's zsh (`~/.zshrc` synthesizes it under kitty — `bin/cc-pane-runner:35-38`) | none |
| **Registry row** `~/.claude/cc-registry/<pane>.json` | FIXED `$HOME/.claude`, pane-keyed (`hooks/session-register.sh:9,172`) | **Rewritten, correctly** — same pane, same `session_id`, NEW `pid`/`lstart`/`account` (`:289-297`) | `session-register.sh` SessionStart in the TARGET cfg | none — but **assert it** before firing anything from the successor (see §6.3) |
| **Session uuid** | the transcript filename | **Yes, identical** — that is the whole point of `--resume` | `lr-fire-resume.sh:725-727` `--resume $sid` | none |
| **`/goal`** | transcript `goal_status` attachment | **Yes** — restored by `restoreGoalFromTranscript` on resume (`docs/research/goal-condition-best-practice-2026-08-09.md:200`) | the harness | **do NOT re-arm** — `handoff-fire.sh:12406-12412` zeroes `FIRE_GOAL` for exactly this reason |
| **Frozen DoD** | `~/.claude/autonomy/dod/repo-<sha16>.md`, keyed on `remote.origin.url` (`hooks/lib/dod-path.sh:34-42`) | **Yes** — not under `CLAUDE_CONFIG_DIR` | `hooks/dod-persist.sh` SessionStart injects it as `additionalContext` (`:177-228`) | none — restating it in the prompt is redundant |
| **Custody debts** | `~/.claude/autonomy/custody/<cwd-key>.jsonl`, cwd-keyed (`bin/cc-custody:14-16`) | **Yes** — same cwd, HOME-rooted | — | none; the successor inherits them and they fold into its `🔧` |
| **Task list** | `CLAUDE_CODE_TASK_LIST_ID` | **Only because the launcher re-exports it** — `lr-handoff.sh:966` writes `export CLAUDE_CODE_TASK_LIST_ID=…` into the launcher, sourced from the source process env/argv (`:457,467-472`). It *"lives only in the PROCESS env/argv and dies with it"* (`:199`) | the minted launcher | **must be carried** — a voluntary launcher that omits it silently switches boards |
| **`session-continue` sentinel** | `${CLAUDE_CONFIG_DIR}/state/continue-<sha(cfg\|cwd)>` (`hooks/lib/continue-sentinel.sh:17-26`), **sid-bound** (`hooks/session-continue.sh:143-145`) | **NO** — the hash includes `CLAUDE_CONFIG_DIR`, so an account change relocates the path | nobody | a pre-move `set` is **inert**; if you want one, it must be armed **after** the move, under the target cfg |
| **fired-peer stamp** `~/.claude/cc-fired/<pane>.json` | pane-keyed + cwd-validated (`hooks/lib/origin-identity.sh:38-67`) | Left untouched; a same-cwd stamp still reads `valid`. But `hf_recycle_inherits_peer` returns 1 on the REMOTE flag (`handoff-fire.sh:4823`), so no contract trailer is delivered | — | the successor is an **ORIGIN** session for close purposes; it owes the origin close contract |
| **Roles / mailbox forwards** | `$CC_ROLES_DIR` | Re-pointed to the same id (`handoff-fire.sh:12720` `refresh_roles_for "$SID" "$SID"`) | handoff-fire | none |
| **Transcript / full history** | `<target-cfg>/projects/*/<sid>.jsonl` | **Yes** — copied by `lr-transplant.sh`; the source is renamed `.handed-off` and any re-created stub is folded by the watcher (`handoff-fire.sh:7066-7081`) | lr-transplant + the watcher | none |
| **Split-brain protection on the source** | `<sid>.HANDOFF.json` tombstone + `~/.reso/limit-recover/locks/<sid>.lock` (`lr-transplant.sh:78-80`) | **Yes**, and it is what ADMITS the recycle (`handoff-fire.sh:9687`) | lr-transplant | **required** — a voluntary move still needs a real transplant, not a hand-copy |
| **Handed-off guard** | `hooks/handed-off-session-guard.sh` UserPromptSubmit, exit 2 | Blocks prompts into a husk | — | none |

---

## 4. What the successor should be submitted (question b)

**Answer: a single-line, plain-text-headed, token-carrying CONTINUATION prompt — roughly 2–3
sentences — and nothing else.** Not nothing; not a scope restatement; not `session-continue.sh set`;
not a re-armed `/goal`.

**Why not each alternative:**

| Candidate | Verdict | Reason |
|---|---|---|
| **Nothing at all** | **Unsound** | `injected` never set ⇒ no submit verification (`lr-fire-resume.sh:826,874`). Then either the strict oracle convicts a healthy move (`handoff-fire.sh:3932-3936`) or the wall-clock oracle falsely confirms on a notification turn (`:3920-3925`). Finding #4. |
| **Scope / DoD restatement** | **Redundant, and lossy if it drifts** | `dod-persist.sh:177-228` already injects the CURRENT contract plus the wave's lineage-filtered history at SessionStart, from an account-independent store. A hand-restated scope is a second copy of a contract that has one authoritative writer — the precise `ssot-edit-dies-at-the-splicer` shape. |
| **`session-continue.sh set`** | **Inert across this boundary, and wrong tier anyway** | The sentinel path hashes `CLAUDE_CONFIG_DIR` (`continue-sentinel.sh:25`), so a pre-move arm lands in the SOURCE account's `state/` and the successor's Stop hook never finds it. Separately: a sentinel drives the *next* turn at a Stop; it cannot produce the *first* turn, which is the only thing engagement is measured on. |
| **Re-arm `/goal`** | **Double-arms** | `--resume` restores it; `handoff-fire.sh:12406-12412` zeroes `FIRE_GOAL` in resume mode with that measurement cited. Arming again would register the same condition twice in one session. |
| **`/limit-recover ingest <bundle>`** (today's successor) | **Wrong population** | The ingest exists to re-audit workflow slots, subagents and tasks that died mid-flight at a limit. A voluntary move of a healthy session has no gap ledger; running the ingest would burn a full audit pass re-verifying units that never stopped. `lr-handoff.sh:628` sets it as the fail-closed default; the launcher substitutes a one-line fast path when `lr-ingest-verify.sh` returns 0 (`:621-627`). For the voluntary path the correct move is to supply the prompt directly, not to hope the fast path fires. |

**Constraints the prompt must satisfy** (each measured, each cited):

1. **One line.** `lr-fire-resume.sh:437-438` — *"the composer submits on CR; newlines are unsafe
   here"*, and `PROMPT` is flattened (`PROMPT=${PROMPT//$'\n'/ }`).
2. **Plain-text head, no leading `/`.** Resume mode bypasses `check_slash_head`
   (`handoff-fire.sh:8927-8938`), so nothing would stop you — but `lr-fire-resume.sh:890-893` records
   the 2026-07-11 stranded-ingest incident: *"a leading-/ prompt whose first CR the slash-command
   autocomplete swallowed as a menu-select"*. The voluntary path has no reason to take that risk.
3. **Carries the run's `LR_SUBMIT_TOKEN`.** `lr-fire-resume.sh:460-468` appends
   `(submit token: <tok>)` if the composer of the prompt did not already include it, and sets the
   `LR_SUBMIT_TOKEN_IN_PROMPT` contract identifier that `handoff-fire.sh:12489` greps on the LIVE
   layer. Without it the engagement oracle degrades to wall-clock and a stale notification turn
   satisfies it.
4. **Says the one thing the transcript cannot.** The transcript, the goal, the DoD, the task board
   and the custody ledger all arrive intact. What the resumed model cannot know from its own record
   is *that the account changed, voluntarily, and that nothing was lost.* Without that it is likely
   to spend its first turn re-auditing.

**Recommended shape** (single line; `<>` substituted by the driver):

```
ACCOUNT MOVE, not an interruption: you are the SAME session (uuid <sid8>) resumed on <target-account> after a deliberate switch off <source-account>. Nothing was lost — your full transcript, your /goal and your frozen DoD are all here and were re-injected at start. Re-read your own last turn and CONTINUE the work that was in flight; do not re-plan, do not re-audit, do not re-derive state you already hold. (submit token: <tok>)
```

The `--prompt` flag carries it: `lr-fire-resume.sh:38`. Driver-side, that means minting the launcher
with a `--prompt` other than `INGEST_PROMPT`, which is a one-value change at `lr-handoff.sh:628` /
its `TARGS` composition (`:858` shows the same pattern for `--task-list`).

---

## 5. How engagement is PROVEN, and what to do when proof does not arrive (question d)

### The oracle

`resume_engaged` (`handoff-fire.sh:3912-4001`), run by the watcher at `:7291`:

* **Token present** — scan `<target-cfg>/projects/*/<sid>.jsonl` for the newest **user** record,
  non-sidechain, newer than `RCY_T0`, whose text contains the token (`:3942-3974`). That timestamp
  becomes the new baseline. **No token record ⇒ rc 1, deliberately** (`:3932-3936`): *"it means the
  prompt is not in the transcript at all, so there is nothing for a turn to be an answer TO"*.
* **Then** require a **content-bearing, non-error assistant turn newer than that baseline**
  (`:3975-3999`). Excluded: `isApiErrorMessage` (the limit hitting again on the target) and the
  synthetic `"No response requested."`.
* Two ledger rows, not one: `recycle-submitted` the moment the prompt appears
  (`:7279-7290`), then `recycle-engaged` on the turn (`:7301`) — because *"a prompt that never left
  the composer is re-typed, a prompt that landed and is waiting is left alone"*.

A second, independent proof runs INSIDE the pane: `lr-fire-resume.sh:899-982` polls the transcript
via `lr-submit-probe.sh` and emits `submitted` / `queued` / `none` / `unreadable` / `skip`.

### Correct behaviour when proof does not arrive

The rail's doctrine is explicit and should be preserved verbatim for the voluntary path:

| State | Site | Action |
|---|---|---|
| `queued` (accepted, behind a running turn) | `lr-fire-resume.sh:912,971-973` | extend the deadline to `RCY_ENGAGE_TIMEOUT`; **never** re-CR — that would append a SECOND copy of the prompt |
| `none` + screen shows OUR draft (`DRAFT-MINE`) | `:913-920` | exactly **ONE** more Enter, then a 10 s window |
| `none` + screen `EMPTY` or `UNKNOWN` | `:921-960` | **no keystroke.** An EMPTY composer is what a successful submit LEAVES BEHIND, and UNKNOWN means no pane was read. Poll the transcript to the engagement budget |
| `unreadable` | `:974-976` | `INDETERMINATE:submit` — *"not a failure and not a success; read the pane"* |
| No claude within 60 s of the type | `handoff-fire.sh:7226-7231` | `INDETERMINATE:boot` — a state line and an alarm, then **keep reading** to 180 s. *"A BOUND EXPIRING IS NOT A VERDICT"* (`:7144-7148`) |
| Still nothing at 180 s | `:7241`, `:7334-7389` | `STALE:boot`, joined with the launcher's own IDL refusal row; row + alarm + **verdict painted to the pane's tty by path**. **NO retype** — *"a second identical command cannot clear a real refusal"* (`:7128-7136`) |
| Claude alive, no assistant turn in 180 s | `:7306-7332` | `RECYCLE FAILED — never engaged`; **deliberately no re-type** (the pane holds a LIVE claude; pasting would interrupt its turn). The token splits the two remedies: *submitted and never answered* ⇒ read the transcript; *never reached the transcript* ⇒ re-type (`:7312-7322`) |
| `--await` window expires | `:12589-12590` | **rc 3, not rc 1** — *"the pane may still be exiting; read the log before acting"* |

Two standing cautions from the corpus apply and should be repeated in any voluntary-path runbook:
a `FIRE FAILED — never engaged` verdict is the **dispatcher's window**, not the peer's state
(`memory: dispatcher-verdict-is-not-the-fired-sessions-state`); and *engaged is not running* — a
transcript turn proves the account is clear and the resume landed, not that the process persists,
so liveness needs its own process/window census.

---

## 6. Adversarial pass

### 6.1 The brief's premise about the verified submit is one generation stale

> *"a verified submit that re-sends CR until 'esc to interrupt' appears"*

That is the **replaced** implementation, and `lr-fire-resume.sh:875-884` names both ways it failed:
it is a SCREEN PHRASE (width- and version-coupled, and when it stops rendering the loop fires five
blind CRs), and it renders while **any** turn is running, so a harness notification turn satisfied
it while the prompt sat unsubmitted — *"the reason 1 in 5 RECOVERED verdicts was false."* The
current mechanism is the transcript **token**, with **at most one** re-CR, gated on the screen
affirmatively showing OUR draft. The only surviving `esc to interrupt` consumers in the tree are
`bin/reso-keepalive:5,85,95` and a caveat at `bin/cc-resume-layout.sh:24`. Any voluntary-path design
that re-derives "re-CR until the chrome appears" would be re-introducing a measured defect.

### 6.2 Resume mode disables the payload gates, and the voluntary prompt is the first payload to need them

`handoff-fire.sh:8927-8938` wraps `check_slash_head`, the empty-file check and the `/goal` cap in
`if [ -z "$RESUME_LAUNCHER" ]`. That is right for today's rail — the payload is a launcher, not a
brief. But the voluntary path introduces a hand-authored prompt on a path with **no** payload
validation: a multi-line prompt would submit at its first CR, and a `/`-headed one would be parsed
as a command. Both hazards are documented elsewhere in the tree (`:5622-5645`, `lr-fire-resume.sh:437`)
and neither is enforced here. **Recommendation:** validate the voluntary prompt at the driver
(single line, non-empty, non-slash-headed) before minting the launcher.

### 6.3 The three gaps the voluntary path must close, ranked

| | Gap | Evidence | Fix shape |
|---|---|---|---|
| **G1** | The DRIVER precheck refuses a healthy session at `REFUSED:not-limited` | `lr-handoff.sh:764-771` + `handoff-fire.sh:7833-7836`; the SELF arm already exempts itself at `:805-811` | give the driver arm the same record-only treatment the SELF arm has, gated on an explicit voluntary flag — **do not** reach for `LRH_PRECHECK=off`, which also discards the registry binding, the teammate test, the pane-state read and the composer read |
| **G2** | `--transplanted-source` force-enables `--allow-live-subagents` on a justification (the ingest) that the voluntary path does not run | `handoff-fire.sh:9716-9723` | the voluntary path must NOT inherit the force-set: let `subagent_gate` refuse **exit 4** and require an explicit, loud `--allow-live-subagents`. A healthy session is the population most likely to have subagents in flight, and `:9716`'s premise — *"a limit-blocked lead's subagents died with it"* — is false for it |
| **G3** | The successor is an ORIGIN session with no contract trailer | `hf_recycle_inherits_peer:4823` returns 1 on the remote flag; the trailer block `:10539` is unreachable in resume mode | acceptable as-is for a voluntary move (the operator/driver is present), but state it: the successor owes the origin close contract and will not self-retire |

### 6.4 Three things I checked that turned out to be non-issues

* **`ITERM_SESSION_ID` loss.** The repo lesson
  (`memory/transplanted-session-loses-dispatch-identity.md`) carries a **CORRECTION 2026-09-10**: the
  cause was removed for runner-rooted panes (`109cfe4cf`, `73e8b596a`), and the expect spawn's env
  filter (`lr-fire-resume.sh:725-727`) never unsets it. The manual re-registration recipe still
  applies only to panes the recovery path did NOT spawn. **Assert `pane_shell_root` and the registry
  row rather than assuming either way** — the correction says so in its own `⚠️` clause.
* **Custody and the DoD crossing an account boundary.** Both stores are `$HOME/.claude`-rooted and
  keyed on cwd / repo-origin, never on `CLAUDE_CONFIG_DIR` (`bin/cc-custody:14-16`,
  `hooks/lib/dod-path.sh:34-42`). They survive.
* **Whether `lr-transplant` itself gates on limitedness.** It does not — its refusals are all about
  the split-brain lock and the destination file (`lr-transplant.sh:50-80,158-212`). The `limit`
  vocabulary in that file is about the *second-hop* case, not an admission test.

---

## 7. Recommended command shape for a voluntary move

Stated as the sequence, not as a script to run. Each step is what the existing rail already does,
with the two voluntary-specific deltas marked **▲**.

1. **Probe, read-only** — `handoff-fire.sh --probe-recycle-preconditions --source-pane P
   --source-session S`. **▲** Expect and ignore `REFUSED:not-limited` (exit 5); harvest the
   `live_subagents:` line, which prints on every path since `:7809-7822`.
2. **▲ Subagent decision** — if `live_subagents: > 0`, either wait or assert
   `--allow-live-subagents` explicitly. Do not let the class flag decide it.
3. **Transplant** — `lr-transplant.sh` writes `<sid>.HANDOFF.json` + the split-brain lock. This is
   what admits the remote recycle (`handoff-fire.sh:9687`) and what arms
   `hooks/handed-off-session-guard.sh` on the source.
4. **Mint the launcher** with the source's `CLAUDE_CODE_TASK_LIST_ID`, model, effort,
   permission-mode, a fresh `LR_SUBMIT_TOKEN`, and **▲ the continuation prompt from §4 instead of
   `/limit-recover ingest <bundle>`**. Keep the durable-path requirement
   (`lr-handoff.sh:655-682`) — the launcher runs the LIVE layer, so preflight the live
   `lr-fire-resume.sh` parser before the first irreversible step.
5. **Recycle** — `handoff-fire.sh --recycle --transplanted-source --source-pane P --source-session S
   --resume-launcher <launcher> --resume-cfg <target-cfg> --resume-cwd <wt> [--await]`. Use
   `--await` only from an interactive driver; a detached driver should read
   `~/.claude/logs/handoffs.jsonl` instead (`lr-handoff.sh:1042-1053`).
6. **Read the verdict, not the rc alone** — rc 3 means *no verdict*, which is a RETRY, and rc 1
   means *dead*. The `recycle-submitted` / `recycle-engaged` row pair tells you which of the two
   dead-path remedies applies.
7. **After engagement**, if a cross-turn driver is wanted, arm
   `session-continue.sh set "<next step>"` **from inside the successor** — it cannot be armed for it
   in advance (`continue-sentinel.sh:25`).

---

## Blockers / uncertainties named

* **Not measured here:** whether `lr-fire-resume.sh`'s `lr_screen` `DRAFT-MINE` needle (the prompt's
  first 40 characters, `:452-454`) behaves as well for a long prose continuation prompt as for the
  short `/limit-recover ingest …` it was calibrated against. The needle is a prefix, so it should
  hold, but it has not been exercised on this shape — a live A/B is the honest check.
* **Not measured here:** whether a voluntary move's target account passes `lr-fire-resume`'s own
  capacity re-gate in the pane. `handoff-fire.sh:7344-7349` records 10/10 refusals on `term=load` on
  one morning — a term `capacity-admit`'s own comment calls WRONG INPUT for this caller. If the
  voluntary path is fired under load, expect `FAILED:relaunch:gate` and read the IDL row.
* **Read-only claim about `lr-handoff.sh:966`:** the launcher re-exports the task list only when
  `SRC_TASK_LIST` was resolvable from the source process env or argv (`:457,467-472`). A source
  session whose process is already gone yields an empty value and the successor silently lands on
  the default board. Worth asserting non-empty at mint time for a voluntary move, where the source
  process is by definition still alive and the value is therefore always obtainable.
