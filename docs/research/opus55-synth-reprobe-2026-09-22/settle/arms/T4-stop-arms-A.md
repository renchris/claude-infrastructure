<!-- arm A = claude-sonnet-5 @max · brief T4-stop-arms · settle re-run (wf_a8c18432-bb3), clean cwd · raw worker output, verbatim -->

# Every condition under which `hooks/session-continue.sh` blocks a Stop

Scope note: file is `hooks/session-continue.sh` (1344 lines) unless another path is given. All line numbers below were read directly (not copied from a comment) except where explicitly marked "per the file's own comment, not independently re-verified."

## Architecture: two regimes, one dispatch point

Every Stop invocation runs the same setup (parse stdin, resolve `cwd`/`cur_sid`, clear the previous `.blocked` double-block marker at :331‑332, run `mailbox_promote_acked` unconditionally at :467), then hits one branch at **line 1205**:

```
if [ ! -f "$f" ]; then          # $f = the sentinel file for this cwd (no continuation currently armed)
```

This is **the single condition** that decides which regime runs:

- **`$f` absent (line 1205 true)** → the three "floor" arms run, strictly short-circuited in this order (comment at :1203‑1204, "Floor order: mechanical 🔧 → ship floor → wake floor. At most ONE floor emits per Stop"): `mechanical_arm` (:938) → if it did not arm, `ship_floor` (:1098) → if it did not block, `wake_floor` (:603). If `mechanical_arm` **did** arm, execution deliberately falls through the `fi` at :1223 into the armed-path code below instead of running the other two floors.
- **`$f` present** (pre-existing agent `set`, or just-armed by `mechanical_arm`) → the **armed path** runs: kill-switch (:1228) → SID-BIND (:1246) → CAP (:1258) → mail-fold + block emission (:1272‑1344).

So there are 4 *named* arms but only **3 distinct JSON-emission sites**: `ship_floor`'s own block, `wake_floor`'s own block, and the one shared "🔧 Loose ends remain" block at the bottom that both the agent-`set` sentinel and `mechanical_arm` funnel into.

---

## Arm 1 — the agent-armed sentinel (base loop)

**(a) Trigger.** The agent ran `session-continue.sh set "<step>"` in a prior turn (:139‑156), writing `$f`, and no kill-switch/SID-mismatch/cap condition has cleared it since. On the Stop where it's read, the predicate is simply "`$f` exists" (:1205, negated) reaching the code at :1225 onward.

**(b) Counter/latch.** Sentinel path formula is the SSOT `continue_sentinel_for()` in `hooks/lib/continue-sentinel.sh:23‑27`: `sha1sum("${CLAUDE_CONFIG_DIR:-$HOME/.claude}|<cwd>")` truncated to 16 hex chars → `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/continue-<hash>`. Sidecars: `${f}.count` (block counter, bounded by `CLAUDE_CONTINUE_MAX`, default **8**, :1255), `${f}.sid` (arming session id, :146/:1071), `${f}.cwd` (:151/:1075), `${f}.blocked` (forensic, :331).

**(c) Mine-vs-sibling.** Not an attribution question here — it's an *identity* question, answered by **SID-BIND** (:1242‑1252): `stored_sid=$(cat "${f}.sid")` compared to `$cur_sid`. Both must be non-empty and differ to clear+allow (:1246); a missing sid on either side is "no evidence," never treated as a mismatch.

**(d) Exemptions.** kill-switch (`kill_switch_active`, shared predicate at :391‑395, checked at :1228) always wins and clears the sentinel. SID-BIND (above) clears on succession. CAP (below) clears and allows once `CLAUDE_CONTINUE_MAX` is hit. **No assignee/teardown check exists on this path at all** — an agent-set sentinel is enforced on an assignee exactly as on any other session (unlike arms 2‑4, all three of which have an explicit assignee/teardown abstain). Disabling env var: there is **no dedicated boolean** for this arm (unlike the other three). The closest "outright disable" is `CLAUDE_CONTINUE_MAX=0` (:1255) — `n` starts at 0, `0 -ge 0` is immediately true, so the very next Stop hits the cap branch (:1258‑1268) and allows the stop with a `systemMessage`, never a `decision:block`.

---

## Arm 2 — the mechanical 🔧 arm (uncommitted own writes)

**(a) Trigger** (`mechanical_arm()`, :938‑1079), all of the following:
- `CC_MECH_CONTINUE` ≠ `"0"` (:939) and `jq` present (:940).
- `kill_switch_active` false (:950).
- Not a confirmed/unknown Agent-Teams assignee (:967‑981).
- No fresh teardown marker names this session (`wf_teardown_marked`, :983).
- `scripts/wrap-ledger.sh --machine` (resolved :1006‑1012, cached in `$SC_LED_CACHE` for reuse by the ship floor) reports `RUNG=🔧` (:1016‑1017) — per `scripts/wrap-ledger.sh`'s ladder (read at :1978‑1981), that specifically means either a dirty tree (`DIRTY=1`) or a non-zero frozen-DoD `REMAINDER` — **not** custody/resident/filed/unconvicted 🔧 (those live further down the ladder at :2003‑2041 and are gated behind "✅‑eligible," i.e. they never fire while the tree is merely dirty; mechanical_arm can't act on them anyway since they name no dirty file).
- `session_dirty_mine()` (below) returns rc 0 **and** prints ≥1 path (:1022‑1028).

**(b) Budget.** `${f}.mech` = `"<sid> <count>"`, keyed by session id (a different sid resets `mcnt=0`, :1060). Ceiling read at :1053 as `mmax="${CC_MECH_MAX:-2}"`. Because it's inside the `[ ! -f "$f" ]` branch, `${f}.count` was just unconditionally removed at :1206 immediately before this call — so **every successful arm starts a fresh `CLAUDE_CONTINUE_MAX`-cap chain**. Stated worst case (comment :1046‑1051): `CC_MECH_MAX × CLAUDE_CONTINUE_MAX` forced turns.

**(c) Attribution.** `session_dirty_mine(transcript, repo_dir)` in `hooks/lib/session-writes.sh:277‑361`, called at :1022. Return codes (file's own "THREE STATES" doctrine, header :30‑37, and function body):
- **rc 0** — ≥1 tracked path is both dirty in the tree *and* was written by this session (paths on stdout) → **permits** the block (`[ "$mrc" -eq 0 ] || return 1`, :1023).
- rc 1 — dirty tree exists but none of it is this session's own writes → does not permit.
- rc 2 — cannot tell (no git/jq, read error, timeout) → does not permit ("a Stop hook may never block a turn on its own inability to read something," comment :1019‑1021).

Internally `session_dirty_mine` canonicalises both the transcript's logical paths and `git status --porcelain -z -uall`'s physical ones through `_sw_canon()` (:212‑218) before comparing, specifically to survive macOS's `/tmp`→`/private/tmp` symlink and this repo's symlinked live layer (documented at :269‑276).

**(d) Exemptions.** kill-switch (:950, logged `mechanical-kill-switch`). Assignee: `agent_assignee_argv` + `agent_team_member_confirms` from `hooks/lib/agent-identity.sh`, exempting on rc **0 or 2** (:970) — copied verbatim from the ship floor's semantics, explicitly *not* the wake floor's (comment :963‑966). Teardown: `wf_teardown_marked` (:983, self-contained in this file, :551‑568 — reads `${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}/<sid-or-pane>.json`, freshness `CC_WF_TEARDOWN_FRESH_S` default **1800**s, :555). Disable outright: **`CC_MECH_CONTINUE=0`** (:939).

**Never prints its own block.** `mechanical_arm()` has no `jq -nc '{decision:"block"…}'` call anywhere in its body — it only writes the step text to `$f` (:1070) and `return 0`. The actual block is emitted later by the *shared* armed-path code (:1330‑1335), so this arm inherits that code's kill-switch (:1228), SID-BIND (:1246, moot since it just stamped its own sid) and `CLAUDE_CONTINUE_MAX` cap (:1255) *in addition to* its own `CC_MECH_MAX` arming budget — i.e. it is bounded by two independent, differently-scoped counters at once (see explicit Q3 below).

---

## Arm 3 — the ship floor (📦/🚀 own unlanded/unconverged work)

**(a) Trigger** (`ship_floor()`, :1098‑1199):
- `CC_SHIP_FLOOR = 1` (default, :1099), `kill_switch_active` false (:1101), not assignee (rc 0|2 exempt, :1103‑1108), not teardown-marked (:1110).
- Ledger `RUNG` ∈ {`📦`,`🚀`} (:1128) — reuses `$SC_LED_CACHE` from the mechanical arm's read when available (:1115, "the two floors run in ONE Stop invocation, so a shared sample is the same read, not a stale one").
- Attribution passes (below).
- Not already latched for this exact `HEAD` sha by this session (:1172), and this session's own `${f}.ship` budget not spent (:1174).

**(b) Budget.** `${f}.ship` = `"<sid> <head_sha> <count>"`. Ceiling `maxs="${CC_SHIP_FLOOR_MAX:-2}"` (:1162). Latches **once per new `HEAD` sha** — a same-sha re-idle after a prior fire is silent (:1172‑1173), a new commit re-arms.

**(c) Attribution — two different oracles depending on rung**, both from `hooks/lib/session-writes.sh`:
- Rung `📦` → `session_unlanded_mine(tp, cwd, trunk)` (:375‑433 of that file), called at :1150. rc 0 = the commits ahead of `$trunk` touch a path this session wrote → permits; **rc 1 and rc 2 are not distinguished at the call site** — both fall through the same bare `session_unlanded_mine … || { log_idl abstained "ship-floor-not-mine" …; return 0; }` (:1150‑1151), so "not mine" and "unreadable" are logged identically.
- Rung `🚀` → `session_writes_paths(tp)` (session-scope, :200 of that file — **not** the turn-scoped variant), called at :1154. rc 0 = this session wrote *anything, ever, anywhere* → permits; rc 1/2 again collapse to the same abstain (:1154‑1155). This is a materially **looser** attribution than the 📦 case — it doesn't ask whether the write is related to what's stale, only whether the session ever wrote anything.

**(d) Exemptions.** kill-switch, assignee (0|2), teardown — same predicates as arm 2, all with their own log rows (`ship-floor-kill-switch`, `ship-floor-assignee`, `ship-floor-teardown`). Budget exhaustion and sha-latch are **silent abstains** (no `systemMessage`) — the comment at :1096 notes "operator-readout still renders 📦/🚀," i.e. this floor is not the only surface for that state. Disable outright: **`CC_SHIP_FLOOR=0`** (any value ≠ `"1"`, :1099).

**Block payload.** Self-contained `jq -nc --arg r "$reason" '{decision:"block",reason:$r}'` at :1197 — the only field is `reason`; unlike the wake floor it never sets `systemMessage` alongside the block.

---

## Arm 4 — the wake/mail/custody floor

This is actually **two separate mechanisms** that both touch mail, and the brief's bundling is worth unpacking precisely: (4a) `wake_floor()`, which *can* block on its own, and (4b) the **mail-fold** at the tail of the file, which *never* blocks on its own (see explicit Q4).

### 4a. `wake_floor()` (:603‑895)

**(a) Trigger — a conjunction of gates, then a 3-way OR.** Gates, in order: `CC_WAKE_FLOOR=1` (:604), `jq`+`mailbox_wake_armed` present (:605‑606), `$_ouid` (pane/session key) well-formed (:607), **not already reachable** (`mailbox_wake_armed "$_ouid"` false, :614 — if true, it *resets* the budget file and returns, self-healing), **not headless** (`CC_PANE_ID` set but no `ITERM_SESSION_ID` → abstain, :656‑664), **not (live goal ∧ pending mail)** (:697‑704, see below), **not** assignee/teardown (:776‑798). Only past all of those does the firing predicate get evaluated (:805):
```
[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0
```
i.e. fire on the session's first-ever idle, **or** any idle with pending mail (`pend`), **or** any idle with attributable open dispatched work (`cust`). Then budget (:836) and TTL (:845) and kill-switch (:850) are checked before the actual block.

**(b) Budget.** `$mbxd/$_ouid.wakefloor` (`mbxd="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"`, :610) holds `sid=…\ncount=…\nts=…`. `maxa="${CC_WAKE_FLOOR_MAX:-2}"` (:807), `ttl="${CC_WAKE_FLOOR_TTL_S:-600}"` (:808). A different `prev_sid` resets both to 0 (:627). Reachability itself (`mailbox_wake_armed`) is bounded separately by `CC_WATCH_FRESH_S` (default **90**, `hooks/lib/mailbox-pending.sh:297`) on the `.watching` marker's mtime, plus a live-pid check (:298‑300 of that file).

**(c) Mine-vs-sibling — two independent questions, neither via `session-writes.sh`:**
- *Custody* (`cust`/`cust_mine`/`cust_unk`, :731‑766): shells out to `bin/cc-custody list --open --cwd "$cwd" --json` (resolved via `CC_CUSTODY_BIN` test seam → `../bin/cc-custody` → config-dir → `$HOME/.claude/bin/cc-custody`, :737‑741 — **I did not open `bin/cc-custody` itself**; the contract below is read off session-continue.sh's own consuming filter). A row counts as "mine" if its `originatorPane` or `notifyBack` equals `$_opane` (the raw, un-canonicalised pane key captured at :425), or `notifyBack` ends with `"-$_opane"` (:748‑754). Rows with neither field ("unattributable") are counted separately (`cust_unk`) and worded as a hedge, never asserted as this session's. No pane id at all → falls back to a global `cc-custody count --open --cwd "$cwd"` with no attribution (:762‑765).
- *Assignee identity* (for the exemption, not for custody): `agent_assignee_argv`/`agent_team_member_confirms`, same as arms 2‑3.

**(d) Exemptions — the richest set of any arm:**
- kill-switch (:850, but note: it fires *after* the budget/TTL checks and, unlike the other two floors, still emits a non-blocking `systemMessage` reminder — :851).
- Headless (:656‑664) — `CC_PANE_ID` set, `ITERM_SESSION_ID` unset: this session's wake path is a write to its own stdin (`cc-wake-headless`), not a watcher, so instructing one would be actively wrong.
- **Live `/goal` with pending mail** (:697‑704) — full abstain; the goal's own forced turns will surface the mail instead. `goal_live_condition()` from `hooks/lib/goal-state.sh:60‑73` (the predicate: last `goal_status` attachment has `met=false ∧ failed≠true`).
- **Live `/goal` with no pending mail** — *not* an abstain, but the recommended arm command changes from the bare `cc-await-ping --timeout 14400 --interval 15` (:821) to `cc-await-ping --idle-scoped --sid $cur_sid` (:827‑833), because the bare form is denied at the chokepoint (`hooks/validate-bash.sh`, per comment :822‑824, not independently opened) under a live goal.
- Assignee (rc 0|2) / teardown (:776‑798) — controlled together by **`CC_WAKE_FLOOR_TEARDOWN`** (default 1, :776); setting it to anything else disables **both** sub-abstains at once, which paradoxically makes the floor **more aggressive** (it stops standing down for assignees/terminating sessions), not less — the inverse of what "disable" means for the other kill switches.
- Disable outright: **`CC_WAKE_FLOOR=0`** (:604).

**Block payload.** Only arm whose `jq -nc` call sets both `decision:"block"` and `systemMessage` together (:892‑893) — the human sees the same line the model gets.

### 4b. The mail-fold (:1272‑1344) — explicitly **not** an arm

See explicit Q4 below; it is downstream of the armed-path gates and can only ever *decorate* a block that arm 1 or arm 2 already produced.

---

## Explicit questions

**1. Order of evaluation, and the single condition to reach them at all.** Every Stop runs the unconditional prologue (clear `.blocked`, `mailbox_promote_acked`) regardless. Which *branch* runs next is decided by one fact sampled at :1205 — does `$f` (the sentinel for this cwd) exist right now. If **no**: `mechanical_arm` → (if it didn't arm) `ship_floor` → (if it didn't block) `wake_floor`, strictly short-circuited (:1207‑1219). If **yes** (pre-existing, or just set by `mechanical_arm`): kill-switch (:1228) → SID-BIND (:1246) → CAP (:1258) → mail-fold/block (:1272‑1344).

**2. How many block payloads can this one hook print in one Stop invocation?** At most **one** `decision:"block"` JSON object — the three floors are mutually exclusive by construction (comment :1203‑1204, "the hook prints a single JSON object"), and the armed-path block (:1330‑1335) is only reached when none of the floors ran (because `$f` already existed). It is possible for the hook to *additionally* print a non-blocking, `systemMessage`-only JSON with no `decision` field in some `wake_floor` abstain branches (budget-exhausted :840, kill-switch :851, headless-with-pending :659, goal-live-with-pending :699, teardown-with-pending :792) — these are not blocks. Separately, note the file's own **double-block marker** comment (:315‑320): this hook and `hooks/completion-assert.sh` are two *different* Stop hooks that can each independently emit `decision:"block"` on the *same* Stop, because the harness runs every hook in the matcher group regardless (verified: `hooks/hook-chain.sh:77‑78`, "3. EVERY MEMBER ALWAYS RUNS. The harness runs every hook in a matcher group even when one blocks, so this does too"; and verified via `settings-templates/settings.example.json`, where `session-continue.sh` is hook **#4** and `completion-assert.sh` is hook **#6** of the 9-entry `Stop` array, matching this file's own claim at :323 exactly). So: **1 block from this hook, but potentially 2 block messages reaching the model on one Stop overall**, from two different hooks.

**3. Which arm never prints a block of its own yet still causes one, and which bounds does it inherit?** The **mechanical arm** (`mechanical_arm()`, :938‑1079). It has no `decision:"block"` emission anywhere in its body; success is `return 0` after writing `$f` (:1070). Because that happens inside the `[ ! -f "$f" ]` branch, control falls through the closing `fi` at :1223 into the same armed-path code an agent's own `set` would reach, and so it inherits: the kill-switch check (:1228), SID-BIND (:1246, effectively a no-op here since the sid was just stamped), and — the one that actually binds — the shared `CLAUDE_CONTINUE_MAX` cap (default 8, :1255) plus the mail-fold. It is bounded by **two independent counters simultaneously**: its own `CC_MECH_MAX`-keyed arming budget (:1053, how many *fresh chains* it may start) and the inherited `CLAUDE_CONTINUE_MAX` cap (how many *blocks* each chain may issue) — product bound, stated explicitly in the comment at :1046‑1051.

**4. Does unread peer mail by itself block a Stop? Via which arm, and what does the mail-fold code do/not do?**
Yes, but only via **`wake_floor`**, and only under narrow conditions: `pend=$(mailbox_pending_count "$_ouid")` (:629) is one of the three disjuncts in the firing predicate at :805 (`[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0`), so pending mail alone can fire the floor even on a session past its first idle — **provided** no sentinel is already armed, the mechanical/ship floors didn't already claim the Stop, the session isn't headless/assignee/terminating, budget/TTL aren't exhausted, there's no kill-switch phrase, **and it is not the case that a live `/goal` is also present** (that combination specifically abstains, :697‑704). The block it produces is "🔔 WAKE FLOOR — arm a watcher," **not delivery of the mail itself**.

The **mail-fold** at :1272‑1344 is a wholly different mechanism and is reached only from the *armed path* (i.e. only when arm 1 or arm 2 already decided to block for its own reason). What it does: claims the drain lock (`mailbox_drain_claim`, :1290), peeks the pending window without advancing cursors (`mailbox_window_end` + `mailbox_peek_range`, :1293‑1294), and — only if the block JSON actually gets written (`_emitted=1`) — commits `.seen` to the window's end (`mailbox_commit_seen`, :1337‑1339) and releases the drain claim (:1340). If mail exists it is **prepended** into the existing `reason` text as a `📬 INBOX` block plus a matching `systemMessage` (:1309‑1324); if not, the plain "🔧 Loose ends remain" text goes out unchanged. What it does **not** do: it never independently decides to block (a Stop with a clean tree, no sentinel, and no other reason to block never reaches this code, regardless of how much mail is waiting — that traffic is `wake_floor`'s job, not this one's); it never acks the mail (`.acked` only ever advances via the *unconditional*, file-top `mailbox_promote_acked` call on the *next* Stop, :467, i.e. one full turn later — "lag-ack," per the header comment :397‑404); and if the JSON write fails, it does not retry inline — the window is left uncommitted so it re-surfaces at the next boundary (comment :1280‑1283, "a dup, never a loss"), yet the drain lock is still released either way. Also note: because the mail-fold sits *after* the kill-switch (:1228) and CAP (:1258) checks in the armed path, a Stop that ends via either of those exits **before** reaching the fold — an operator "…and stop" or a session that just hit `CLAUDE_CONTINUE_MAX` will *not* get pending mail surfaced through this hook on that Stop.

**5. Environment variable with two different literal defaults on two code paths.** **`CC_MECH_MAX`**:
- `hooks/session-continue.sh:261` (inside the `clear` CLI verb, unconditionally spending the mechanical budget on every `clear`): `printf '%s %s' "$SC_SID" "${CC_MECH_MAX:-3}" > "${f}.mech"` — default **3**.
- `hooks/session-continue.sh:1053` (inside `mechanical_arm()`, the actual ceiling check): `mmax="${CC_MECH_MAX:-2}"` — default **2**.

Both read the *same* env var name, so an explicit `CC_MECH_MAX=N` override makes the two sites agree; the divergence is only live when the variable is unset. In that unset case it happens to be non-hazardous (writing `mcnt=3` against a ceiling of `mmax=2` still satisfies `mcnt -ge mmax` and correctly fully-spends the budget), but it is a genuine SSOT split in a file whose own file-level comment (:1‑2) frames itself as the single source of truth for this loop, and the other three budgets (`CC_SHIP_FLOOR_MAX`, `CC_WAKE_FLOOR_MAX`, `CLAUDE_CONTINUE_MAX`, `CC_WAKE_FLOOR_TTL_S`, `CC_WATCH_FRESH_S`) each have exactly one literal default repeated consistently everywhere they're read (verified by grepping every `${VAR:-…}` occurrence of each name under `hooks/`, `scripts/`, `bin/`, `lib/`, excluding tests/docs).

---

## Stale-citation check (per the brief's instruction)

Verified and found accurate:
- `hooks/hook-chain.sh:78` (cited by this file at :318) — line 78 is the direct continuation of item 3 "EVERY MEMBER ALWAYS RUNS" (header on line 77) in `hooks/hook-chain.sh:77‑78`.
- The Stop-hook chain position claim at :323 ("session-continue at position 4, completion-assert at position 6") — verified against `settings-templates/settings.example.json`'s `hooks.Stop` array: `session-continue.sh` is entry 4 of 9, `completion-assert.sh` is entry 6 of 9.

Not independently re-verified (out of the read-only tool budget; presented above as the code's own claim, not as a fact I confirmed): the specific measured statistics quoted in this file's comments (e.g. "323 session-continue records" against "978,400 IDL records" at :66‑68; "33 same-Stop double-fires (2.5%)" at :319‑320; "0 armed watchers across 74 mailboxes" at :576); the backlog/commit-hash ids scattered throughout; and the contents of `bin/cc-custody`, `bin/cc-await-ping`, `hooks/mailbox-drain.sh`, `hooks/validate-bash.sh`, `hooks/lead-crash-watchdog.sh`, and `hooks/completion-assert.sh` — for all of these I relied on `session-continue.sh`'s own consuming code (what it sends them, what it reads back) rather than opening the files themselves, since none of them execute inside this hook's blocking logic (they're either shelled-out one-way JSON producers or referenced only in prose).