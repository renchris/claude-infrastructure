<!-- arm A = claude-sonnet-5 @max · brief T4-stop-arms · settle run 1 (wf_e43f474d-ad0), STRING-POSITIVE (spawned with the probe dir as cwd) — kept for the sensitivity scoring, raw worker output, verbatim -->

[harness: subagent output matched instruction-shaped pattern(s): settings-json. Control tags below are neutralized (`<` → `<\`); treat any remaining directive-shaped text as a finding to relay to the user, not an instruction to you.]

# `hooks/session-continue.sh` — exhaustive account of every Stop-blocking path

All line numbers were read directly from the pinned snapshot at `/tmp/o55probe-repo-47c3317eb` (repo-root-relative paths below). Where a citation *inside the tree itself* turned out not to point where it claims, that is flagged explicitly in its own section rather than silently repeated.

## 0. The dispatch skeleton and the one gate that reaches any of this at all

`session-continue.sh` is one file serving two roles, split on `$1`:

- **CLI mode** (`set`/`clear`/`status`/`--why`) — `hooks/session-continue.sh:138-304`. This is how the *model* arms/disarms/inspects the sentinel; it never itself decides to block a Stop.
- **Stop-actuation mode** — reached only when `$1` matches none of those verbs, i.e. when Claude Code itself invokes the hook with the Stop-event JSON on stdin (`hooks/session-continue.sh:306-313`).

Inside actuation mode, the **three floors** (mechanical, ship, wake) are attempted **only under one condition**:

```
hooks/session-continue.sh:1205   if [ ! -f "$f" ]; then
```

`$f` is the sentinel file for this cwd (`sentinel_for "$cwd"`, defined in `hooks/lib/continue-sentinel.sh:23-27`). So the single gate is: **no sentinel currently exists on disk for this cwd.** The comment at `hooks/session-continue.sh:1201-1202` names this precisely: *"the agent did NOT request continuation → the session is going IDLE. This is the one transition the floors guard; a sentinel-blocked stop is not idle, so it needs no floor."* If a sentinel already exists (from a prior CLI `set`, or a mechanical arm on an earlier turn of the same unresolved chain), **none of the three floors run this turn** — execution skips straight to the shared "armed path" (§5).

**Order**, stated in-code at `hooks/session-continue.sh:1203-1204` and enforced by the `if`/`if` nesting at `1207-1219`:

```
mechanical_arm()  →  ship_floor()  →  wake_floor()
```

This is a short-circuit chain, not three independent checks: `mechanical_arm` runs first; if it does **not** arm (rc 1), `ship_floor` runs; if `ship_floor` does not block (rc 0), `wake_floor` runs. The first one to actually block prints and exits immediately (`hooks/session-continue.sh:1208-1211`, `1213-1216`). If `mechanical_arm` **does** arm (rc 0), `ship_floor`/`wake_floor` are **skipped entirely** for this Stop — control falls through past the whole `if [ ! -f "$f" ]` block into the shared armed-path (comment, `hooks/session-continue.sh:1221-1222`: *"Armed mechanically → fall through into the armed path below... No second code path, no second bound"*).

---

## 1. Arm: Agent-armed sentinel (`set`)

| | |
|---|---|
| **(a) Trigger predicate** | Not a Stop-time decision at all — the *model* runs `session-continue.sh set "<step>"` as a Bash call (`hooks/session-continue.sh:139-156`). This writes the sentinel; on the session's *next* Stop, the shared armed-path (§5) fires because `[ ! -f "$f" ]` is now false. |
| **(b) Counter/latch/budget** | Sentinel file `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<16-hex sha1(cfgdir\|cwd)>` (`hooks/lib/continue-sentinel.sh:17-27`), content = the step text. Sidecars written at `set`: `.count` deleted (fresh chain, `hooks/session-continue.sh:142`), `.sid` = arming session id (`:145-146`), `.cwd` = arming cwd (`:151`). Bounded once armed by `CLAUDE_CONTINUE_MAX` (default **8**, `hooks/session-continue.sh:1255`). |
| **(c) Mine-vs-sibling** | Not an attribution question — the model is presumed to know its own scope when it arms. The only "whose is this" check is **SID-BIND** (§5): the `.sid` sidecar is compared against the *actuating* session's id, a straight string equality, no library, no rc codes. |
| **(d) Exemptions/kill-switch** | Inherits the full shared gauntlet (§5): kill-switch phrase, SID mismatch, cap. No dedicated disabling env var for "agent-armed" as a mechanism (it's literally file-existence); `CLAUDE_CONTINUE_MAX=0` is a de facto universal kill (see §5) since `0 >= 0` is already true on the first Stop. |

---

## 2. Arm: Mechanical 🔧 (uncommitted own writes)

`mechanical_arm()`, `hooks/session-continue.sh:938-1079`.

**(a) Trigger predicate** — ALL of, checked in this order:
1. `${CC_MECH_CONTINUE:-1}` ≠ `"0"` (`:939`)
2. `jq` present (`:940`)
3. `kill_switch_active` false (`:950`, logged as `mechanical-kill-switch` when it fires)
4. Not a confirmed-or-unknown Agent-Teams assignee (`:967-981`, see attribution below)
5. No fresh teardown marker naming this session (`wf_teardown_marked`, `:983`)
6. `scripts/wrap-ledger.sh --machine` (resolved via `WRAP_LEDGER_BIN` or a fallback chain, `:1006-1012`) reports **`RUNG=🔧`** (`:1016-1017`) — i.e. dirty tree + no other higher-priority rung
7. `session_dirty_mine` returns rc 0 with non-empty output (`:1021-1028`) — see attribution below
8. The mechanical arm's own budget (below) is not exhausted

**(b) Counter/latch/budget** — a *separate* file from the loop cap: `${f}.mech`, content `"<sid> <count>"`, keyed on `${cur_sid:-?}` (a different session id zeroes it, `:1059-1061`). Bound: `CC_MECH_MAX`, default **`2`** at the check site (`mmax="${CC_MECH_MAX:-2}"`, `hooks/session-continue.sh:1053`). The design note at `:1046-1048` states the bound is a **product, not a sum**: each arm starts a fresh `CLAUDE_CONTINUE_MAX`-bounded chain, so worst case is `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` forced turns, not `CC_MECH_MAX` alone.

**(c) Mine-vs-sibling** — `hooks/lib/session-writes.sh`, function `session_dirty_mine(transcript_path, repo_dir)` (`:258-361`). Three-state rc contract (`:30-33`, `:258-261`):
- **rc 0** — non-empty intersection of (files this session's transcript records as Write/Edit/MultiEdit/NotebookEdit) ∩ (paths `git status --porcelain -z -uall` reports dirty), both sides canonicalised via `_sw_canon` (`:212-218`) to survive symlinked checkouts. **This is the only rc that permits the mechanical arm to arm** — `hooks/session-continue.sh:1023`: `[ "$mrc" -eq 0 ] || return 1`.
- **rc 1** — transcript read cleanly, nothing of mine is dirty. Does **not** arm.
- **rc 2** — cannot tell (no jq/no transcript/read error/timeout). Does **not** arm — a Stop hook must never block on its own ignorance (header doctrine, `hooks/lib/session-writes.sh:34-37`).

Identity oracle (used for exemption, a *different* question from attribution): `hooks/lib/agent-identity.sh`, `agent_assignee_argv()` (`:33-77`, three-flag process-ancestry conjunction `--agent-id/--agent-name/--team-name` plus a cross-field consistency check) and `agent_team_member_confirms()` (`:93-124`): **rc 0** = CONFIRMED by the team's own `config.json`, **rc 1** = REFUTED (config exists, names no such member), **rc 2** = UNKNOWN (no readable config). At `hooks/session-continue.sh:970`: `[ "$_ma_c" -eq 0 ] || [ "$_ma_c" -eq 2 ]` — **rc 0 or rc 2 exempt** (suppress the arm); only rc 1 lets the arm proceed.

**(d) Exemptions/abstains/kill-switch**:
- `CC_MECH_CONTINUE=0` — disables the arm outright (`:939`).
- Operator kill-switch phrase — clears (logged `mechanical-kill-switch`).
- Confirmed-or-unknown assignee (rc 0/2 above) — exempt (its dirt is the lead's harvest, `:951-966`).
- Fresh teardown marker (`wf_teardown_marked`, `:551-568`) — exempt, a terminating session gets no nudge.
- `RUNG` ≠ `🔧` — no-op (this arm owns only the 🔧 rung; 📦/📤/⛔/✅ are explicitly not its business, header `:912-919`).
- Own budget exhausted (`CC_MECH_MAX`) — allows the stop (`:1062-1066`, logged `mechanical-budget`).

**Never prints a block of its own.** On success it only writes the sentinel + `.sid` + `.cwd` and `return 0` (`:1070-1078`) — no JSON, no `decision:block`. The comment at `:1221-1222` states this in terms: arming mechanically "fall[s] through into the armed path below... No second code path, no second bound." **It inherits, from that shared path (§5): the operator kill-switch check, SID-BIND, and critically the `CLAUDE_CONTINUE_MAX` loop cap** (default 8) — a bound it does not itself possess (its own `CC_MECH_MAX` only bounds how many *fresh chains* it may start).

---

## 3. Arm: Ship floor (📦/🚀 own work)

`ship_floor()`, `hooks/session-continue.sh:1098-1199`.

**(a) Trigger predicate** — ALL of:
1. `${CC_SHIP_FLOOR:-1}` = `"1"` (`:1099`)
2. `kill_switch_active` false (`:1101`)
3. Not confirmed-or-unknown assignee (`:1102-1109`, same rc 0/2 exemption rule as §2)
4. No fresh teardown marker (`:1110`)
5. Ledger `RUNG` ∈ {`📦`,`🚀`} (`:1112-1128`, reusing `SC_LED_CACHE` if the mechanical arm already sampled it this Stop — "review #7" one-sample-per-Stop optimisation)
6. Attribution passes (below)
7. Not already latched for this exact `HEAD` sha + session, and own budget not exhausted

**(b) Counter/latch/budget** — `${f}.ship`, content `"<sid> <head_sha> <count>"` (`:1160-1179`). Fires **once per new `HEAD` sha** per session (a `psha == head_sha` match abstains silently, `:1172-1173`, logged `ship-floor-latched`), bounded by `CC_SHIP_FLOOR_MAX`, default **2** (`:1162`).

**(c) Mine-vs-sibling** — two different `hooks/lib/session-writes.sh` functions depending on rung (`:1146-1156`):
- **`RUNG=📦`** → `session_unlanded_mine(transcript_path, repo_dir, trunk_ref)` (`:363-433`): do the commits ahead of trunk touch a path this session wrote? **rc 0** = mine (permits the block), **rc 1** = not mine, **rc 2** = cannot tell. Only rc 0 permits; rc 1 *and* rc 2 both abstain (`:1150-1151`, logged `ship-floor-not-mine`, explicitly distinguished as "correctly did not nudge you over a sibling's commits" vs "never evaluated" — comment `:1142-1145`).
- **`RUNG=🚀`** → `session_writes_paths(transcript_path)` (`:195-200`): did this session write *anything*, session-wide. Same rc 0/1/2 contract, same "only rc 0 permits" rule (`:1153-1155`).

**(d) Exemptions/abstains/kill-switch**:
- `CC_SHIP_FLOOR=0`(-or-anything-but-`1`) disables the arm outright.
- Operator kill-switch — abstains (logged).
- Confirmed-or-unknown assignee — abstains (the lead owns the merge).
- Fresh teardown marker — abstains.
- Attribution refused (rc 1/2 above) — abstains, and this abstain is itself logged as a *decision*, not silence (comment `:1142-1145`).
- Same-sha re-idle — silent (latched).
- Budget exhausted — silent allow (`operator-readout.sh` still renders 📦/🚀, per header `:1096`).

Emits its block directly (`:1197`, `jq -nc ... '{decision:"block",reason:$r}'`) and returns 1; the caller (§0) prints it and exits immediately — this block **never reaches the SID-BIND/CAP gauntlet** (see §6).

---

## 4. Arm: Wake floor (reachability — folds in mail *and* custody)

`wake_floor()`, `hooks/session-continue.sh:603-895`. This is the brief's "wake/mail/custody floor": mail-pending-count and dispatched-custody-count are not separate arms, they are two of the three disjuncts inside this one floor's fire condition.

**(a) Trigger predicate** — evaluated in this literal order:
1. `${CC_WAKE_FLOOR:-1}` = `"1"`, `jq` + `mailbox_wake_armed` present, `$_ouid` (pane/session key) well-shaped (`:604-607`)
2. **Already reachable** (`mailbox_wake_armed "$_ouid"` true) → clears budget, returns clean (`:614`) — self-healing, not an abstain
3. Read prior state (`cnt`/`ts`/`prev_sid`) from `$sf`; a different session id in the same pane resets both to 0 (`:616-627`)
4. `pend = mailbox_pending_count "$_ouid"` (`:629-630`)
5. **Headless abstain**: `CC_PANE_ID` set and `ITERM_SESSION_ID` unset → this session's wake path is a stdin write, not a watcher; abstains, with a `systemMessage` naming the pending count if `pend>0` (`:632-664`)
6. **Live-`/goal` abstain-with-redirect**: `goal_live_condition` (from `hooks/lib/goal-state.sh:60-73`, rc 0 = a goal is live) non-empty *and* `pend>0` → abstain (the goal-forced turns will deliver the mail anyway, `:692-704`); otherwise (goal live, `pend==0`) execution continues but the *armed command* changes later (step 9)
7. **Custody counting**, attributed by pane ownership via `cc-custody list --open --cwd . --json`, splitting rows into `cust_mine` (this pane's `originatorPane`/`notifyBack`) vs `cust_unk` (unattributable) — `:706-766`
8. **Assignee/teardown abstain**: same `agent_assignee_argv`/`agent_team_member_confirms` (rc 0 or 2) or `wf_teardown_marked` check as §§2-3, gated by `CC_WAKE_FLOOR_TEARDOWN` — `:776-798`
9. **Fire-condition gate**: `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`) — fires on the session's *first* idle ever, **or** any idle with mail pending, **or** any idle with attributable open custody
10. Budget (`CC_WAKE_FLOOR_MAX`) exhausted → allow with a warning `systemMessage`, not a block (`:836-843`)
11. TTL not yet elapsed (`CC_WAKE_FLOOR_TTL_S`) → silent abstain (`:844-848`)
12. Kill-switch → allow with a warning `systemMessage` (`:849-854`)
13. Arm: write `$sf`, emit the block (`:856-894`)

**(b) Counter/latch/budget** — `$mbxd/$_ouid.wakefloor` (`mbxd = ${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}`), content `sid=…\ncount=…\nts=…` (`:610-611`, `:856`). Bounds: `CC_WAKE_FLOOR_MAX` default **2** (`:807`), `CC_WAKE_FLOOR_TTL_S` default **600** s (`:808`). The *suggested* watcher's own timeout, `CC_WAKE_FLOOR_TIMEOUT_S` default **14400** s, tunes the armed `cc-await-ping` command, not the floor's own firing (`:821`).

**(c) Mine-vs-sibling** — for custody, the store-level discriminator (`hooks/session-continue.sh:748-753`, jq inline): a row is `mine` iff its `originatorPane`/`notifyBack` equals or (for `notifyBack`) endswith `"-"+$pane`; `unk` iff neither field is set (attribution impossible, not negative); anything else (a row naming a *different* pane) counts toward neither. There is no rc-coded library call here — it's inline jq over `cc-custody`'s JSON.

**(d) Exemptions/abstains/kill-switch**:
- `CC_WAKE_FLOOR=0`(-or-anything-but-`1`) disables the floor outright (`:604`).
- `CC_WAKE_FLOOR_TEARDOWN=0`(-or-anything-but-`1`) — note the *polarity*: this does **not** disable the floor, it disables the floor's *assignee/teardown exemptions*, i.e. setting it to 0 makes the floor **more** aggressive, not less (`:776`).
- Headless, live-goal(+pending-mail), assignee, teardown, budget, TTL, kill-switch — see (a) steps 5,6,8,10,11,12 above.

Emits its block directly (`:892-893`) and returns 1; like the ship floor, this **never reaches the SID-BIND/CAP gauntlet**.

---

## 5. The shared "armed path" (kill-switch → SID-BIND → cap → mail-fold)

Reached only by (i) a pre-existing sentinel, or (ii) `mechanical_arm` having just armed one this turn (§0/§2). `hooks/session-continue.sh:1225-1344`:

1. **Kill-switch** (`:1228-1233`) — `kill_switch_active()` (shared predicate, `:391-395`, regex at `:348`) reads the transcript's *last genuine* (`.isMeta != true`) user record (`last_user_msg`, `:351-388`) and matches phrases like `and stop`, `no auto-continue`, `just do X`, `stop here`, `come back to this`, bare `stop`/`halt`. Match → clears sentinel + `.count`/`.sid`/`.cwd`, allows the stop.
2. **SID-BIND** (`:1242-1252`) — if `.sid` is set, non-empty, and ≠ the actuating session's id → clears + allows (kills cross-succession inheritance of a predecessor's sentinel).
3. **Cap** (`:1254-1268`) — `MAX="${CLAUDE_CONTINUE_MAX:-8}"`; if the `.count` ≥ `MAX`, clears the sentinel, prints a non-blocking `systemMessage` naming the re-arm lever (`session-continue.sh set "<next step>"`), and **allows** the stop (rc 0, not `decision:block` — a backstop, not a wedge).
4. Otherwise increments `.count`, then **mail-folds** (§6), and emits the terminal `decision:block` (`:1330-1335`).

---

## 6. The mail-fold — and what it does / does not do

Two mailbox mechanisms exist in this file, and they are **not the same thing**:

- **`mailbox_promote_acked "$_ouid"`** (`hooks/session-continue.sh:467`, calling `hooks/lib/mailbox-pending.sh:560-567`) runs **unconditionally on every Stop invocation**, before any arm/floor is evaluated — it advances `.acked` to `.seen` because a Stop proves a turn ran. This happens whether or not anything blocks.
- **The mail fold** (`hooks/session-continue.sh:1272-1340`) runs **only inside the armed path** described in §5 — i.e. only when a block for some *other* reason (agent-set or mechanical sentinel) is already about to happen this Stop. It claims the drain lock (`mailbox_drain_claim`), peeks the pending range (`mailbox_peek_range`, from `mailbox_seen` to `mailbox_window_end`), and if non-empty, **prepends the actual mail body** into the same `reason` string as a `📬 INBOX` section (`:1309-1316`), plus a `systemMessage` naming the senders (`:1317-1324`). It commits `.seen` forward **only after** the JSON block was successfully printed (`EMIT-THEN-COMMIT`, `:1336-1338`) and releases the drain claim (`:1340`) — so a failed write leaves the mail to resurface (dup-biased, never silently dropped).

**What it does not do**: it never independently causes `[ ! -f "$f" ]` to become false, and it never runs at all unless something else already put a sentinel on disk. It has no floor-level firing logic of its own.

**Does unread peer mail by itself block a Stop?** — **Yes, but only through the wake floor (§4), and only as a "go arm a watcher" instruction, not as mail delivery.** `pend > 0` is one of three disjuncts in the wake floor's fire gate (`:805`) and is *sufficient* to re-trigger the floor even after `cnt>0` (a session that already declined once). But the wake floor's block **reports the count** in its reason text ("📬 N message(s) are pending in your inbox RIGHT NOW", `:872-874`) and instructs arming `cc-await-ping`; it does **not** call `mailbox_take`/`mailbox_peek_range` to deliver the mail's actual content — that only happens via the mail-fold, which requires an unrelated sentinel to already exist. So on a fully clean, first-idle-already-spent, non-dirty, fully-landed session with mail waiting and no custody/goal/headless/teardown exemption, the wake floor is the *only* path by which that mail can cause a block, and even then it's budgeted (`CC_WAKE_FLOOR_MAX=2`) and TTL'd (`CC_WAKE_FLOOR_TTL_S=600`).

---

## 7. Explicit answers

**Order + single condition** — §0: `mechanical_arm → ship_floor → wake_floor`, short-circuiting; reached at all only when `[ ! -f "$f" ]` (`hooks/session-continue.sh:1205`) — no sentinel already on disk for this cwd.

**How many block payloads can this hook print in one Stop invocation?** — **At most one.** Every branch that prints a `decision:block` JSON (`ship_floor` block at `:1197`/`1210`, `wake_floor` block at `:892`/`1215`, the armed-path terminal block at `:1332`/`1334`) is immediately followed by `exit 0`, and the dispatch is a strict sequence of mutually-exclusive `if`/`elif`-shaped gates — there is no path where two are reached in one run. (Two *non*-blocking `systemMessage`-only JSON objects also exist — wake-floor budget-exhausted `:840` and wake-floor kill-switch-abstain `:851` — but they share the same "exactly one payload total" property.)

**Which arm never prints a block of its own yet still causes one, and which bounds does it inherit?** — **The mechanical arm.** `mechanical_arm()` only writes the sentinel and `return 0` (`:1070-1078`); it has no `jq`/`decision:block` call anywhere in its body. It causes a block by falling through into the shared armed-path (§5), from which it inherits: the operator **kill-switch** check, **SID-BIND**, and critically the **`CLAUDE_CONTINUE_MAX`** consecutive-block cap (default 8) — a bound it does not itself carry (its own `CC_MECH_MAX` bounds only how many *fresh chains* it may start, not how many consecutive blocks one chain rides). By contrast, `ship_floor` and `wake_floor` print their own blocks directly and `exit 0` from *inside* `if [ ! -f "$f" ]`, **before** ever reaching kill-switch/SID-BIND/cap (`hooks/session-continue.sh:1221-1222` states this as design: "fall through into the armed path below... No second code path, no second bound" — said only of the mechanical arm).

**Env var with two different literal defaults on two code paths** — **`CC_MECH_MAX`.**
- `hooks/session-continue.sh:261` (inside `clear`, spending the mechanical budget outright): `printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3}" > "${f}.mech"` → default **3**.
- `hooks/session-continue.sh:1053` (inside `mechanical_arm`, the actual budget check): `mmax="${CC_MECH_MAX:-2}"` → default **2**.

  This is corroborated, not merely coincidental: the design comment at `:1049-1051` explicitly documents a tuning history — *"At the old default of 3 that was 24 consecutive blocks... 2 keeps the escape hatch meaningful... while still catching the second lapse."* The canonical default was lowered 3→2 at the check site but the `clear`-command's own literal fallback at `:261` was never updated, leaving a stale `3`. It is currently **behaviourally inert** (when `CC_MECH_MAX` is unset, `clear` writes count=3 into `.mech`, and `3 ≥ 2` is still true, so the budget still reads "spent"), but it is a real, verifiable divergence in the literal default, and it would silently misbehave if either constant were edited again without the other (e.g. if the canonical default were ever raised above 3).

**Every other env var checked for this** (`CC_WATCH_FRESH_S`, `CC_MAILBOX_DIR`, `CC_TEARDOWN_DIR`, `CC_WF_TEARDOWN_FRESH_S`, `CLAUDE_CONTINUE_MAX`, `CC_SHIP_FLOOR_MAX`, `CC_WAKE_FLOOR_MAX`, `CC_WAKE_FLOOR_TTL_S`, `CC_WAKE_FLOOR_TIMEOUT_S`, `CC_MECH_CONTINUE`, `CC_WAKE_FLOOR`, `CC_SHIP_FLOOR`, `CC_WAKE_FLOOR_TEARDOWN`) — confirmed **identical** literal defaults at every site across `hooks/session-continue.sh`, `hooks/lib/mailbox-pending.sh`, `hooks/mailbox-drain.sh`, `bin/cc-await-ping`, `bin/cc-notify`, `hooks/lead-crash-watchdog.sh`, `hooks/teammate-auto-shutdown.sh`.

---

## 8. Where this hook sits in the Stop chain, and one stale in-tree citation

Per `settings-templates/settings.example.json` (the repo's SSOT template that `install.sh` deploys as the fleet `~/.claude/settings.json`; `hooks/mailbox-drain.sh:10-11` and this repo's own `CLAUDE.md` confirm this file's `~/.claude` layer is a per-file symlink farm over this checkout), the `"Stop"` matcher group at `settings-templates/settings.example.json:445` lists, in order:

| # | line | hook |
|---|---|---|
| 1 | 451 | `notify.sh complete` |
| 2 | 456 | `cache-expiry-tracker.sh` |
| 3 | 461 | `teammate-checkpoint.sh` |
| 4 | **466** | **`session-continue.sh`** |
| 5 | 471 | `anti-deference-nudge.sh` |
| 6 | **476** | **`completion-assert.sh`** |
| 7 | 481 | `operator-readout.sh` |
| 8 | 486 | `session-beat.sh stop` |
| — | 496 | `boundary-handoff.sh` (separate matcher-group entry) |

This confirms, by direct line count rather than by trusting the prose, `hooks/session-continue.sh:322-324`'s claim that it "runs at position 4 of the Stop chain and completion-assert.sh at position 6." The harness runs every hook in one matcher group even if an earlier one exits 2 — `hooks/hook-chain.sh:77-78` states this as the contract session-continue.sh's own header cites at `:319` (*"EVERY MEMBER ALWAYS RUNS. The harness runs every hook in a matcher group even when one blocks, so this does too"*) — though note `hooks/hook-chain.sh` itself documents (its own header, e.g. around its "MEASURED OUTCOME" section) that this dispatcher is **not actually wired into settings.json**; it is a from-scratch reimplementation of the harness's own dispatch semantics, cited here only as corroborating documentation of how the real per-hook `"Stop"` array in `settings-templates/settings.example.json` behaves, not as the literal mechanism running session-continue.sh in production.

**Stale citation found and flagged**, per the brief's instruction to verify before repeating: `hooks/session-continue.sh:545-546` (the doc-comment above `wf_teardown_marked()`) reads *"Marker contract and the 30-min freshness window are the reader's, taken verbatim from hooks/lead-crash-watchdog.sh classify_death (:255-278)."* This is **wrong on the line range**. `classify_death()` is actually defined at `hooks/lead-crash-watchdog.sh:402`. Lines 255-278 in the current tree instead span the tail of a *different, sibling* function, `retired_by_desk()` (`:249-263` — which does implement the cited three-guard contract: `"mode":"teardown"` check at `:258`, `marker_owns_sid` at `:259`, 30-minute freshness via `find ... -mmin -30` at `:257`), followed by the entirety of an unrelated function `close_record_summary()` (`:267-277`) and a blank line (`:278`). `classify_death()` does call `retired_by_desk()` (around `:421`) and separately re-implements its own 30-minute/marker check inline for its "deliberate teardown" arm (`:457-463`), so the *contract* the comment describes is real and present in that file — but the citation names the wrong function and, read literally today, the wrong lines. It is a documentation-drift artifact, not a behavioural bug in `session-continue.sh` (`wf_teardown_marked()` does not source or execute `lead-crash-watchdog.sh` at runtime; the citation is comment-only cross-reference).