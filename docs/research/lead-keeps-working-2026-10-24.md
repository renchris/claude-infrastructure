# A lead keeps working while a decision is open — synthesis design (ruling d610f8473106)

Synthesis of four rival designs (`designs/D1..D4`) and twelve adversarial critiques (`critiques/`), for the
operator ruling `d610f8473106` ("Yes, upon a comprehensive Dynamic Workflow research … before implementing",
`~/.claude/autonomy/decisions/d610f8473106.json` `.evidence`). Worktree `lead-idle-fix` at `b6b53ea89`. This is
a design only: nothing in the repo or under `~/.claude` was changed; this file is the only write.

Labels. `R` = `CLAUDE.rules.slim.10-session-close.md` (deployed `~/.claude/rules/10-session-close.md`), `S` =
`CLAUDE.global.slim.md` (deployed `~/.claude/CLAUDE.md`), `G` = `CLAUDE.global.md` (deployed
`~/.claude/CLAUDE.full.md`, loaded by no session). `TX:n` = line n of the B13 lead transcript
`~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/666022fd-ed3e-4e72-b293-7caae899d585.jsonl`.
`IDL` = `~/.claude/autonomy/idl.jsonl`. Maps and critiques are cited as `maps/<name>.md` and
`crit/<design>--<lens>.md` (both under `docs/research/lead-keeps-working-2026-10-24/`); designs as `D1:n`..`D4:n`.
Every number is labelled **measured** (command named) or **estimated** (method named). Measurements new in
this synthesis are collected in §9.3 with their commands.

---

## 1. Decision

**Build the contract-keyed scope floor: D4's minimal skeleton, carrying D2's recorded-contract markers, with every
blocker and major the critics found fixed.** One ledger predicate (`SCOPE_UNGATED`: this session's own recorded
loop scope or own unchecked boxes, minus a recorded hold) drives one new Stop actuator (a fourth floor in the
already-registered `hooks/session-continue.sh`) and one off-Stop actuator (`nudge_subject` in
`scripts/lead-supervisor.sh`, which wakes the session itself through `cc-notify`). Neither reads close prose or packet
class, so it fires at the B13 F1 close (06:44:40Z) whatever the lead wrote, and ⛔ stays first in the ladder, so all
48 open class-C packets keep today's behaviour (measured, §9.3 M3). The bounds are per session id and survive key
changes. A loop scope reaches the store from the human prompt that stated it, at the first idle Stop. Rule text stops
licensing the idle, sends status-quo judgment calls to class B, records the Codex grant where every session loads it,
and does not grow the always-loaded tier (measured, §5.3). It was chosen because the replay critics found that only a
ledger-keyed Stop floor plus a wake of the subject breaks the idle whatever the lead writes (crit/D2--incident-replay.md
§3; crit/D4--incident-replay.md §0 and §5 item 2), and keying it on the session's own recorded contract does that without
a packet schema the lead can game (crit/D3-schema-first--loop-false-block.md D-17) or a rung reorder.

**Revision after the completeness critic (same day).** Three changes reach the decision itself. (1) A hold is no
longer a free off-switch: `dod-persist.sh hold` refuses a packet that neither declares an operator-only ceiling nor
routes C under `scripts/gate-classify.sh`, and a hold that has only one of the two lapses after 6 h (§3.2); both
B13 packets route B (measured, §9.3 M16), so the incident's likeliest escape is closed. (2) `cc-decide open --class C`
from a session must declare `--ceiling self-mod|money|permission|credential|g2|program`, so goal (b) has a
deterministic gate, not only text (§3.6). (3) The deterministic coverage of goals (a) and (e) is stated honestly:
it is the loop scope. The "own unchecked boxes" half reads 0 today, because the DoD store holds no unchecked box
(measured, §9.3 M17), so a ⛔ idle over a non-loop scope is an accepted residual that rule text alone addresses
(§3.0, §4.2). The rest of the revision fixes mechanics: the supervisor's oracle, its nudge ladder, the in-flight
detector, the context-high abstain, the reclose guard and the grant's read confinement. §9.4 lists every critic gap
and where it was fixed or rebutted.

---

## 2. The incident and the replay

**The incident in one paragraph.** The B13 lead (session `666022fd`) was recycled on 2026-10-22 with the frozen scope
"loop until dry … repeat until a round confirms nothing new" (TX:14). At 02:22Z the operator asked "is this forever?"
(TX:4114). At 02:36Z the lead filed two judgment calls as class C: `e869fac7eb34` (stop the loop; its "no" option was
the frozen scope) and `290215743799` (send committed code to OpenAI via the Codex plan the operator had bought for that
purpose in `a247b7288149`), copying R:160's class-C template flag for flag (TX:4254, TX:4260; crit/D4--incident-replay.md
§2). It wrote "No round 27 until e869fac7eb34 is answered" (TX:4270). After round 26 landed it closed idle three times
(F1 06:44:40Z TX:4437, F2 07:39:47Z TX:4458, F3 08:34:59Z TX:4476), tore down its watcher at F3, and sat idle until the
operator wrote at 18:11:47Z (TX:4488). Every Stop hook accepted the idle: the ledger made ⛔ first
(`scripts/wrap-ledger.sh:2603-2610`), session-continue returned silently at `hooks/session-continue.sh:1103` and `:1216`,
completion-assert abstained `no-close-tell` before reading the ledger (`hooks/completion-assert.sh:469-471`;
maps/stop-hooks.md §0.1), and lead-supervisor's 160 STALL? and 66 ESCALATED rows reached nobody because the page channel
had no target (`scripts/lead-supervisor.sh:414-415`; maps/wake-path.md §2.2). The loop scope was not even in the DoD
store during the idle: its only capture is a manual `set` at 20:15:35Z (maps/wrap-ledger.md §0.2).

**The replay, step by step, with this design live from 2026-10-22.** "Det." = a hook or daemon acts whatever the model
believes; "Adv." = text the model may ignore. Outcomes after a block are estimated; inputs are measured where cited.

| Time (Z) | Event | Component that acts | Det./Adv. | Outcome |
|---|---|---|---|---|
| 10-22 07:41 | Recycle brief TX:14 (`type:user`, `origin.kind:human`, scope on line 5, verb-first; measured §9.3 M5) | **C1 intake**: first idle Stop with rung ⛔/✅/👤 and no own loop capture runs `dod-persist.sh capture-loop` (§3.2, §3.4) | Det. | Store gains `(stop-capture) · session=666022fd…` + the loop line; from the next Stop `LOOP_OPEN=1` |
| 10-23 05:15:50, 15:46:53, 23:40:13 | ✅ closes while the round's lanes were being fired from a background Bash job (crit/D4--loop-false-block.md §2.1) | **C2 ledger** reads loop 🔧; **C4 floor** abstains `scope-floor-inflight` on the live non-watcher background task (§3.3) | Det. | No false block (D4 as written fired twice here and spent its budget) |
| 10-24 02:25-02:36 | "is this forever?" (TX:4114); research finds `a247b7288149` but reads it as TrueMemory-only (TX:4235) | **C9 rule text** R:68 (look for a ruling; re-ask as class B), R:160 (class routing), R:38/R:103 (keep driving) | Adv. | Most likely class-B filing with "keep running rounds" as default (the lead copies R:160's template verbatim, TX:4254 vs R:160) |
| 02:36:16 | `cc-decide open --class C … 2>&1 \| tail -3` (TX:4254), no `--ceiling` | **C7 cc-decide** refuses rc 2 (a session's class-C open must declare a ceiling, §3.6 item 2b) and prints the full class-B command last; the re-filed open (class B, or C with a ceiling) then prints the closest answered packet last: `eb3dbe1e5e94` ratio 2.88, "default fired: keep looping until dry" (maps/ruling-discovery.md §4.2) | **Det.** refusal; Adv. re-file | Most likely a class-B re-file with "keep running rounds" as default (no ⛔ at all; the floor below then fires with kind `loop`). The worse branch, a re-file with a false `--ceiling self-mod`, is written with gate-classify's disagreement on stderr (both packets route B, §9.3 M16); the rows below follow that worse branch |
| 02:36-05:02 | ⛔ closes with round-26 lanes and then the land in flight | **C4 floor** abstains `scope-floor-inflight` (custody computed under ⛔ when ungated work exists, LANDING) | Det. | Correct allow (control C1) |
| **06:44:40 F1** | Land done, watcher re-armed, close "❌ Good to close: no … Nothing more runs until you answer" (TX:4437) | **C4 floor fires 1/3**: ⛔, `SCOPE_UNGATED=1`, nothing in flight (the watcher `bpctefji1` is `/Users/chrisren/.claude/bin/cc-await-ping`, excluded by basename, TX:4434), turn opened by a task-notification (TX:4428) | **Det.** | The idle is refused with "run the next round as scoped"; both ids glossed; hold/done discharges named with their criteria |
| F1 forced turn | Model answers | — | Adv. | Compliant: round 27 starts ~06:45Z (estimated; evidence and its limits in §9.1). Non-compliant re-close: `scope-floor-reclose` (no second block in the burst; logged `ungated:1`) |
| F1 forced turn, hold branch | Model runs `dod-persist.sh hold e869fac7eb34 "round 27 waits on the stop rule"` (the block text names the verb) | **C3 hold verb** (§3.2) | **Det.** | Legacy packet (no ceiling) that routes B ⇒ refused rc 2, store unchanged, the refusal prints the class-B route. In the false-ceiling branch the packet routes B but declares a ceiling ⇒ accepted as a **lapsing** hold: F2 and F3 log `nothing-ungated held:true` instead of firing, the supervisor sends its one re-confirm at the first STALL? (~09:11Z) plus a `held-idle` digest cause, and at ~12:45Z, when the hold lapses, it reads the row's `held_until` as passed and nudges the session itself, whose next Stop fires the floor again (§3.5). Either way the hold cannot end the drive for good |
| 07:39:47 F2 | Woken by the watcher timeout (TX:4445), same close (TX:4458) | **C4 fires 2/3** (turn opened by a task-notification, not by the floor) | Det. | Refused again (meets maps/incident-replay.md §7 F2 MUST) |
| 08:34:59 F3 | Detached `cc-await-ping … &` (TX:4469), "I'm stopping the inbox watcher" (TX:4476) | **C4 fires 3/3** | Det. | Refused at the last Stop (meets the §7 F3 MUST "Block at F3") |
| ~09:11 | First STALL? after F3 (measured in crit/D2--incident-replay.md §2 S9) | **C6 supervisor**: newest `scope-floor*` row is the F3 `scope-floor` fire, or its `scope-floor-reclose` row, with `ungated:1` → nudge 1 by `cc-notify <sid>`. The orphan watcher likely makes cc-notify report `wake-path-armed` (maps/wake-path.md §4.3) → recorded, re-check allowed after 1 h | Det. send | Line queued; probably no wake yet |
| ~10:11 | STALL? (rows 10:09-10:15Z, crit/D3--incident-replay.md §2) | **C6** nudge 2; the orphan died by ~09:31Z (3,300 s timeout + 90 s freshness), so cc-notify socket-wakes via cc-wake (W1-W5, maps/wake-path.md §4.1) | **Det. wake** | A turn about 8 h before the operator's message. The floor is key-capped for this turn (3 fires in the window): it logs `scope-floor-key-cap ungated:1`, and wake_floor then logs `wake-floor-mechanical-arm` after it (`hooks/session-continue.sh:690`); the oracle skips that row (§3.5), so the session stays eligible |
| ~11:11 | Back-off 1 h after nudge 2 (ladder 30 min, 1 h, inside the 6 h GC horizon, §3.5) | **C6** nudge 3 (wake); the woken re-close is key-capped again (F1-F3 are inside the 6 h window); nudge 3 is the cap → `subject_nudge_capped` → **operator digest** (Notification Center, `digest_add`/`digest_flush`, `scripts/lead-supervisor.sh:361-404`) | Det. | The operator is told at ~11:11Z instead of discovering it at 18:11Z; the telemetry GC at 6 h (`scripts/lead-supervisor.sh:146`) can no longer pre-empt the digest |

**Would 290215743799 still have been filed?** In a faithful replay, yes. The grant this design records is the
operator's 18:11:47Z words (TX:4488), so it did not exist at 02:36Z; crediting it with preventing the 02:36Z filing is
anachronistic (crit/D2--incident-replay.md §4). In a future incident the always-loaded grant (§3.7 R-19) removes the
consent ask. It does not remove the auto-mode classifier refusal, which denied the Codex call as "[Data Exfiltration]"
six minutes after the operator's grant (TX:4640, TX:4678, TX:4683); an allow rule is a settings change only the
operator may make. The operator already ruled on that class of question (`29d62f1ad390`, 2026-10-20: "Permission
prompts are virtually always a yes, so improve the allowlist/config"), so Phase 2 asks nothing: it files the allow rule
once as an operator step (`cc-backlog needs … --class needs-human`, §8.4), and the grant text says that until it
lands, a refusal is that one pending step: run Claude-only, do not re-ask per repo.

**Would it have re-asked a ruling?** Decision 1 would most likely still be asked, as class B. The operator's "is this
forever?" (TX:4114) is new input that fairly reopens `eb3dbe1e5e94` (crit/D2--incident-replay.md §4), and R:68 now
says exactly that: re-ask on new evidence or when the operator reopened it, as class B with the ruling's course as the
default. The fix for decision 1 is the class, not suppression of the ask.

**Controls** (maps/incident-replay.md §7 Controls):

| Control | Under this design | Why |
|---|---|---|
| C1 ⛔ with lanes or land in flight (03:09-05:02Z) | allowed | `scope-floor-inflight` (custody, then LANDING) |
| C2 legitimate class C (`d610f8473106`, C10) gating a subset while round 27 runs (18:31:59Z, TX:4769) | allowed | round 27 was a live workflow (`wf_e887b970-e18`, D4 §1 F8): `scope-floor-inflight` on the wave count |
| C3 permission denial gating Codex only (18:17:32Z, TX:4683) | allowed; with nothing in flight, one push to "run round 27 Claude-only" | the decision holds only the Codex act |
| C4 all-gating money/self-mod gate, scope exhausted | allowed, byte-identical readout | no loop and no own boxes ⇒ `SCOPE_UNGATED=0` ⇒ `scope-floor-nothing-ungated` |
| C5 class-B re-file (`b4780d7bb60e`) with the loop open | 🔧 loop, not a false ✅; the floor drives; no free-win recycle | loop arm on the ✅-eligible path (§3.1) |
| C6 the operator answers the loop's named packet "stop" through cc-decide (no chat message) | the loop stops being driven | `b4780d7bb60e` is named in the loop line itself; an actioned or vetoed packet named there sets `LOOP_SRC=answered` (§3.1 (ii)) |

---

## 3. The design, per goal

### 3.0 Components and goals

| # | Component | Files | Goals |
|---|---|---|---|
| C1 | Stop-time loop-scope capture (`capture-loop`) | `hooks/dod-persist.sh`, `hooks/session-continue.sh` | (e) |
| C2 | Ledger contract facts (`LOOP_*`, `HELD*`, `SCOPE_UNGATED`, `BLOCKED_IDS`/`GLOSS`), ⛔ readout clauses, loop 🔧 arm just above ✅ | `scripts/wrap-ledger.sh` | (a)(e) |
| C3 | Hold/done/release verbs (a hold only over a declared or routed operator-only gate; durable, lapsing or refused), `set` guard, PreCompact `isMeta` filter | `hooks/dod-persist.sh` | (a)(e) |
| C4 | Scope floor (fourth floor) | `hooks/session-continue.sh`, `hooks/lib/inflight.sh` (new) | (a)(e) |
| C5 | Mechanical arm on ⛔ for own dirt (commit, never land) | `hooks/session-continue.sh` | (a)(e) |
| C6 | Subject nudge + held re-confirm + operator digest at cap; `advise_subject` verdict-parse fix | `scripts/lead-supervisor.sh`, `scripts/supervisor-e2e.sh` | (f) |
| C7 | `cc-decide open --help`, class header, required `--ceiling` on a session's class-C open with gate-classify's cross-check on stderr, stderr ruling hint | `bin/cc-decide`, `bin/cc-memory-search` (`--decisions`), `hooks/anti-deference-nudge.sh` (one env prefix), `scripts/research-kit/lib/gate_sweep.py` (passes `--ceiling program`) | (b)(c) |
| C8 | Machine text that steered to class C or to disarming | `hooks/dispatch-assert.sh`, `hooks/lib/why-tier.sh`, `commands/wrap.md`, `commands/handoff.md` (name open ids in a brief), `hooks/session-continue.sh` (text), `hooks/operator-readout.sh` (loop term) | (a)(b) |
| C9 | Rule text R/S (tier-neutral) and G twins | R, S, G | (a)(b)(c)(d)(e) |
| C10 | Grant envelope in tracked code | `scripts/xvendor-review.sh` (new) | (d) |
| C11 | Record entries | decision store (Phase 2 writes) | (c)(d) |

| Goal | Mechanism | Kill switch (no settings edit needed) |
|---|---|---|
| (a) keep working on every ungated in-scope item | **Deterministic for a loop scope only**: C4 blocks the idle with the next step; C2's ⛔ readout gains `Not gated by it: …` and `→ Next` says `continue`; C5 forces the commit of own dirt under ⛔. For a non-loop scope the deterministic half (own unchecked boxes, `OWN_REMAINDER`) reads 0 in production, because the store holds no unchecked box and `dod-persist` writes one `Scope` line per block (measured, §9.3 M17), so a ⛔ idle over unfinished non-loop work is an **accepted residual** addressed only by R:38/R:103/R:217 (crit/D4-minimal-sufficient--constraints-feasibility.md D-14) | floor: `CC_SCOPE_FLOOR=0` or `touch ~/.claude/state/scope-floor.off`; C5: `CC_MECH_BLOCKED=0` or `~/.claude/state/mech-blocked.off` |
| (b) status-quo judgment calls → class B; C kept for its reserve | **Det.:** a session's `cc-decide open --class C` without a closed `--ceiling` is refused with the class-B command printed (§3.6). Adv.: R:160 class routing with the full class-B command; cc-decide header; dispatch-assert/why-tier/wrap text | hint: `CC_DECIDE_HINTS=0` or `~/.claude/state/decide-hints.off`; ceiling: `CC_DECIDE_CEILING=0` or `~/.claude/state/decide-ceiling.off` |
| (c) find an existing ruling first | R:68 search sentence and re-ask valve; `cc-memory-search --decisions`; the stderr ruling hint printed last; the class-A grant record is itself searchable | same hint switch |
| (d) standing grants every session loads | R § Standing operator grants (always loaded), G full record, `xvendor-review.sh` envelope (export only, reads confined to it, fail closed), class-A record + one needs-human operator step for the allow rule (already ruled, `29d62f1ad390`) | text: revert; code: not a hook |
| (e) close stack refuses a Blocked idle over ungated work, incl. box-less loops | C1 + C2 + C4 (+ C5 for dirt) for a recorded loop scope; the non-loop case is the residual named in row (a) | ledger: `WRAP_LOOP_SCOPE=off` or `~/.claude/state/loop-scope.off` (all new fields 0, readout byte-identical) |
| (f) wake the stalled session itself | C6 `nudge_subject` via `cc-notify <sid>`, operator digest at cap | `CC_SUP_SUBJECT_NUDGE=0` (or `=shadow`), or `~/.claude/state/subject-nudge.off` (or `.shadow`) |

The file switches follow the existing `~/.claude/state/<feature>.off` precedent (`bin/claude-accounts:4936`, `:6777`;
`hooks/stop-failure-marker.sh:242`). Hooks read the harness environment, so an env switch alone would need a
settings edit; the file switch does not. They live under `$HOME/.claude/state` (not `CLAUDE_CONFIG_DIR`) so one file
disables a feature on all five accounts.

**Why the non-loop residual is accepted rather than closed by counting plan-file boxes.** 80 of the store's frozen
lines name a `docs/plans/` file (measured, §9.3 M17), so counting `- [ ]` boxes in the plan a session's own frozen line
names would reach most non-loop work. It is not taken here because a plan's boxes are not the frozen scope: a line such
as "implement W6 of docs/plans/X.md" freezes one section while the file carries every phase's boxes, many of them other
sessions' or deliberately later. Counting them would turn the floor into the scope-blind nag `hooks/session-continue.sh:4-10`
bans, and the floor has no discharge for "those boxes are not mine" short of `done`. It is filed as a measured
follow-on (§8.1 step 10): a plan-section-scoped count, validated against the 80 lines before it may block.

### 3.1 C2 — `scripts/wrap-ledger.sh` (producer; fields plus one rung arm; ⛔ stays first)

**(i) Keep the lineage-filtered DoD stream** inside the per-file loop (`:913-944`), zero forks:

```diff
 DOD_SCOPE=""; DRAIN_SCOPE=0
+_WL_FF_ALL=""                                   # § LOOP reads it after _wl_resolve_sid (:960)
 …
   if command -v dod_filter_for >/dev/null 2>&1; then
     _wl_ff="$(dod_filter_for "$PWD" "$_wl_df")"
+    _WL_FF_ALL="${_WL_FF_ALL}${_wl_ff}
+"
```

The no-lib fallback (`:926`) leaves `_WL_FF_ALL` empty, so every new field reads 0 there (`LOOP_SRC=nolib`).

**`DOD_SCOPE` skips `(stop-capture)` blocks.** `DOD_SCOPE` is the newest frozen line of the whole checkout's lineage
stream (`:919`), and `DRAIN_SCOPE=1` whenever it mentions backlog or drain (`:945`), which arms CLOSE_FLOOR for every
session there. A captured "loop until the backlog is empty" would therefore hand siblings a false CLOSE_FLOOR 🔧. The
`grep 'Scope (frozen):' | tail -1` at `:919` becomes one `awk` (same single fork) that skips lines under a `## … (stop-capture)`
header. The capturing session reads its loop through the own-session `LOOP_*` fields instead; a manual `set` keeps
today's effect, because that is today's behaviour.

**(ii) `compute_loop_scope`, called just before `count_blocking_decisions`** (between `:2594` and `:2603`, after
`compute_research` is defined at `:1059` and run at `:2594`; the SID resolved at `:960`): one `awk` over the stream,
only when a DoD is present and the SID resolved. It reads the session's own recorded contract and the lineage's
verdicts on it.

```bash
+# § LOOP (ruling d610f8473106). THIS session's recorded contract, never the toplevel's newest line
+# (DOD_SCOPE is shared by every session in the checkout: alarm polarity, header :49-52). Rules:
+#  · Only INTENTIONAL captures count: labels manual-set / stop-capture / manual-hold / manual-done.
+#    PreCompact:* blocks scrape any user OR assistant text (dod-persist.sh:143-150), so an assistant
+#    quote of a loop line could otherwise open a loop, and a quoted non-loop line close one.
+#  · The thread is the session's newest intentional `Scope (frozen):` line, matched at column 0.
+#  · done: a `Scope (done):` line in ANY lineage session whose current frozen text equals the thread
+#    text (a successor inherits its predecessor's stop; crit/D3--incident-replay.md #9).
+#  · superseded: a later intentional frozen line with the same text by ANOTHER session (the successor's
+#    capture) — the handed-off predecessor stops driving it (crit/D4--loop-false-block.md §2.3).
+#  · hold: the newest own `Scope (held): <id|none> [until=<epoch>] — <why>` after the thread line.
+#  · answered: a 12-hex packet id named in the thread line whose packet is actioned or vetoed.
+# Fail OPEN: any unknown leaves every field 0, i.e. today's rung and readout bytes.
+LOOP_SCOPE=0; LOOP_OPEN=0; LOOP_SRC="n-a"; LOOP_HEAD=""; LOOP_RUNG=0; OWN_REMAINDER=0
+HELD=0; HELD_SRC="n-a"; HELD_WHY=""; _WL_HELD_ID=""; _WL_HELD_UNTIL=""; SCOPE_UNGATED=0
+LOOP_RE='^[*_`]*(loop|repeat|iterate|keep (going|looping|running))[ \t]+until([^a-z]|$)'
+compute_loop_scope() {
+  case "${WRAP_LOOP_SCOPE:-on}" in off|0|no|OFF|NO) LOOP_SRC="off"; return 0 ;; esac
+  [ -e "$HOME/.claude/state/loop-scope.off" ] && { LOOP_SRC="off"; return 0; }
+  [ -n "$SID" ] || { LOOP_SRC="nosid"; return 0; }
+  # no store file for this checkout yet: nothing is recorded, so the capture is eligible
+  # (dod-persist's persist_dod creates the file, hooks/dod-persist.sh:185-190)
+  [ "$DOD" = present ] || { LOOP_SRC="none"; return 0; }
+  [ -n "$_WL_FF_ALL" ] || { LOOP_SRC="nolib"; return 0; }
+  local out has lp dn sup bx head held
+  out="$(printf '%s' "$_WL_FF_ALL" | awk -v sid="$SID" -v re="$LOOP_RE" '
+    /^## / { s=""; if (match($0, /session=[^ ]+/)) s=substr($0, RSTART+8, RLENGTH-8)
+             lab=""; if (match($0, /\([^)]*\)/)) lab=substr($0, RSTART+1, RLENGTH-2)
+             intent=(lab !~ /^PreCompact/); own=(s==sid); next }
+    !intent { next }
+    /^Scope \(frozen\):/ { t=$0; sub(/^Scope \(frozen\):[ \t]*/, "", t); cur[s]=t
+                           if (s != "") last_by[t]=s
+                           if (own) { L=t; held=""; nb=0 }; next }
+    /^Scope \(done\):/   { if (cur[s] != "") done[cur[s]]=1; next }
+    /^Scope \(held\):/   { if (own && L != "") held=$0; next }
+    /^[ \t]*[-*][ \t]+\[[ \t]\]/ { if (own && L != "") nb++; next }
+    END { if (L == "") { print "0"; exit }
+          lp=(tolower(L) ~ re); sup=(last_by[L] != "" && last_by[L] != sid)
+          gsub(/[\t\r\037]/, " ", L); gsub(/[\t\r\037]/, " ", held)
+          printf "1\037%d\037%d\037%d\037%d\037%s\037%s\n", lp, (done[L] ? 1 : 0), sup, nb, L, held }' \
+        2>/dev/null)" || { LOOP_SRC="error"; return 0; }
+  IFS=$'\037' read -r has lp dn sup bx head held <<< "$out"
+  [ "$has" = 1 ] || { LOOP_SRC="none"; return 0; }        # no own intentional contract → capture eligible
+  case "$bx" in ''|*[!0-9]*) bx=0 ;; esac
+  OWN_REMAINDER="$bx"; LOOP_HEAD="${head:0:160}"           # bash slicing: whole characters under UTF-8
+  case "$held" in "Scope (held): "*) _WL_HELD_ID="$(printf '%s' "$held" | sed -E 's/^Scope \(held\): ([0-9a-f]{12}|none).*/\1/')"
+                                    [[ "$held" =~ \ until=([0-9]+)\  ]] && _WL_HELD_UNTIL="${BASH_REMATCH[1]}"
+                                    HELD_WHY="${held:0:200}" ;; esac
+  [ "$lp" = 1 ] || { LOOP_SRC="n-a"; return 0; }
+  LOOP_SCOPE=1
+  [ "$dn" = 1 ]  && { LOOP_SRC="done"; return 0; }
+  [ "$sup" = 1 ] && { LOOP_SRC="superseded"; return 0; }
+  # research programs: residuals are not open work (R:74-80). compute_research runs only in
+  # machine/full mode (:2594); call it here so RUNG is identical in every mode.
+  case "$MODE" in machine|full) ;; *) compute_research ;; esac
+  [ "$RESEARCH_PROGRAM" = none ] || { LOOP_SRC="program"; return 0; }
+  # an operator answer given through cc-decide, not in chat, ends a loop whose line names the packet
+  # (B13's line ends "…or the operator answers decision b4780d7bb60e 'stop'"; crit/D4--loop-false-block.md §2.4).
+  # Pure-bash scan of the FULL line (LOOP_HEAD is cut at 160); one bounded cc-decide fork only when an id is named.
+  local ids="" r="$head"
+  while [[ "$r" =~ (^|[^0-9a-f])([0-9a-f]{12})([^0-9a-f]|$) ]]; do ids="$ids ${BASH_REMATCH[2]}"; r="${r#*"${BASH_REMATCH[2]}"}"; done
+  if [ -n "$ids" ]; then
+    case "$(_wl_any_resolved $ids)" in            # cc-decide list --all --json | jq: actioned|vetoed ⇒ yes
+      yes) LOOP_SRC="answered"; return 0 ;; no) ;; *) LOOP_SRC="error"; return 0 ;; esac
+  fi
+  LOOP_OPEN=1; LOOP_SRC="own"
+}
+compute_loop_scope
```

`_wl_any_resolved` runs `_bounded "${WRAP_DECIDE_TIMEOUT_S:-5}" "$bin" list --all --json` (the same bounder and binary as
`:1510`) and `jq --args 'any(.[]; (.id as $i | $ARGS.positional | index($i)) and (.status=="actioned" or .status=="vetoed"))'`.
A fired default (`expired-actioned`) does not count: B13's packet defaults to "keep running rounds", which is the loop's
own course. An error prints neither word and reads `LOOP_SRC=error`, so every field stays 0 (today's behaviour). The
answered state ends the drive, never the contract: the 🔧 and the floor go quiet, and the lead records `done` or a new
scope from the answer. A lead that actions its own named packet ends its loop exactly as `done` would; that is the
same exposure as §9.1 risk 3.

**`OWN_REMAINDER` is kept but is not a production mechanism.** It counts `- [ ]` boxes in the session's own
intentional blocks after its thread line. The store holds 0 unchecked boxes in 78 files, and every block has a single
`Scope` line, because `persist_dod` writes `$2` as one line (`hooks/dod-persist.sh:172-194`) and PreCompact keeps only
the `Scope (frozen):` line (`:143-150`) (measured, §9.3 M17). It costs nothing and would count a box a session wrote into
its own block, but no claim in this design rests on it (§3.0 row (a)).

`compute_research` already runs before the ladder in machine/full mode (`scripts/wrap-ledger.sh:2594`); calling it from
here in the other modes costs one fork only for a session with an own open loop. A program session's
`OWN_REMAINDER` is also zeroed (same reason). The loop test is **verb-first** on the text after the prefix: measured,
it matches 1 of 362 store lines (B13's) and 8 of 1,648 recent transcripts, all B13 lineage, with 0 false positives
(§9.3 M1, M2), and it rejects every phrasing that fooled D2's 40-character-prefix pattern ("add the loop until dry
floor…", "review why a loop until dry lead idled", crit/D2--loop-false-block.md §2.3).

**(iii) Ids and glosses ride the existing cc-decide fork** (`count_blocking_decisions`, jq at `:1527-1546`). D4's padded
id cell goes in line 1 before the free-text cell; D2's `GL` rows follow line 1 (`count_rechecked` already skips any row
whose tag is not `RC`, `:1608-1609`):

```diff
       | [ ($ask | length | tostring),
           ((($mine | length) - ($ask | length)) | tostring),
+          (if ($ask|length)==0 then "-" else ($ask | map((.id // "?")|tostring) | sort | join(",")) end),
           (if ($ask | length) == 1 …what_plain… end) ] | @tsv,
+        ( $ask[] | select(((.id // "") | tostring) != "")
+          | [ "GL", (.id | tostring), ((.what_plain // "") | tostring | gsub("[\\t\\r\\n]"; " ") | .[0:90]) ] | @tsv ),
         ( $all[] | select((.session_sid // "") != $sid) …RC rows unchanged… )'
-  IFS=$'\t' read -r n u what <<< "$line"
+  IFS=$'\t' read -r n u ids what <<< "$line"
+  BLOCKED_IDS=""; [ "${ids:--}" = "-" ] || BLOCKED_IDS="$ids"
+  BLOCKED_GLOSS="$(printf '%s\n' "$line" | awk -F'\t' '$1=="GL"{printf "%s%s (\"%s\")", (n++?"; ":""), $2, $3}')"
```

(The gloss can also be built in pure bash, as D2:224-231 does, to avoid the awk.)

The row shape changes, so the per-file exemption in `scripts/tsv-pad-lint.sh:144`, whose discharge argument
describes `count_blocking_decisions`' row as "count FIRST, free text LAST", is rewritten in the same step: cells 1-2
are `tostring` lengths, cell 3 is the sorted id list or the literal `-` (never empty), and the free text stays last;
`GL` rows open with a literal tag, carry an id the `select` guarantees non-empty, and end with the gloss, whose
`[\t\r\n]` are replaced. The argument is the same; only its description of the cells changes (§8.1 step 1).

**(iv) HELD and SCOPE_UNGATED, right after `count_blocking_decisions` (`:2603`)**, zero forks:

```bash
+compute_held() {   # a hold counts only while it names a packet in THIS session's ⛔ set
+  [ -n "$_WL_HELD_ID" ] || { HELD_SRC="absent"; return 0; }
+  [ "$_WL_HELD_ID" = none ] && { HELD_SRC="released"; return 0; }
+  case ",${BLOCKED_IDS},${RECHECKED_IDS}," in *",${_WL_HELD_ID},"*) ;;
+    *) HELD_SRC="stale"; return 0 ;; esac  # answered (or never this session's) ⇒ the loop resumes on its own
+  if [ -n "$_WL_HELD_UNTIL" ]; then     # a lapsing hold (§3.2): counts only until its epoch
+    [ "$(date +%s)" -lt "$_WL_HELD_UNTIL" ] 2>/dev/null || { HELD_SRC="lapsed"; return 0; }
+    HELD=1; HELD_SRC="lapsing"; return 0
+  fi
+  HELD=1; HELD_SRC="own"
+}
+[ "$LOOP_SRC" = off ] || compute_held
+if [ "$HELD" -eq 1 ]; then SCOPE_UNGATED=0; else SCOPE_UNGATED=$(( LOOP_OPEN + OWN_REMAINDER )); fi
```

A hold over a predecessor's packet requires the successor to make it its own ⛔ first (`cc-decide recheck <id>`, the
existing verb for "this turn re-checked a foreign decision", which puts it in `RECHECKED_IDS`). A hold naming a class-B
packet is refused at write time (§3.2) and would read `stale` anyway, because class B never enters `BLOCKED_IDS`
(`scripts/wrap-ledger.sh:47-49`). The one `date` fork runs only for a lapsing hold. A `lapsed` hold leaves
`SCOPE_UNGATED` at its unheld value, so the floor fires again in a new window (§3.4) and the supervisor's held branch
re-confirms once per window (§3.5). `HELD_SRC` gains `lapsing|lapsed`.

**(v) The ⛔ branch gains in-flight facts and two readout clauses** (`:2604-2610`). Custody and residents are skipped
under ⛔ today (`:2622-2648`); the floor needs them to tell "awaiting lanes" from "idle", so they are computed only when
ungated work exists:

```diff
 if [ "$BLOCKED" -gt 0 ]; then
   RUNG="⛔"
+  [ "$SCOPE_UNGATED" -gt 0 ] && { count_open_custody; count_resident_members; }
   …READOUT exactly as today (:2606-2609)…
+  if [ "$SCOPE_UNGATED" -gt 0 ]; then
+    if [ "$LOOP_OPEN" -eq 1 ]; then _wl_ug="your loop scope (\"${LOOP_HEAD:0:80}…\")"
+    else _wl_ug="${OWN_REMAINDER} item(s) of your frozen DoD"; fi
+    READOUT="${READOUT} Not gated by it: ${_wl_ug} — keep driving it; the frozen scope is the course until it is answered."
+  elif [ "$HELD" -eq 1 ]; then
+    READOUT="${READOUT} Held by this session: ${HELD_WHY#Scope (held): }."
+  fi
```

The prefix is untouched, so the pins `tests/wrap-ledger.bats:1848-1851` and `:1866-1867` (substring greps) stay green.
The readout never names the hold command (crit/D2--incident-replay.md D1 fix 1); the hold, once written, is shown to
the operator on every ⛔ close, because operator-readout prints the ⛔ READOUT verbatim (`hooks/operator-readout.sh:1541-1548`).
The same two clauses are added to the re-check ⛔ arm (`:2717-2725`) for a successor that re-checked and holds.

**(vi) The loop 🔧 arm sits immediately above the ✅ arms**, after `YOURS` (👤, `:2726-2734`) and before `DOD=absent`
(`:2735`). It therefore never masks 🚀 (`:2685`), the re-check ⛔ (`:2717`) or 👤, which fixes the gate weakening all
three D2/D4 critics found (crit/D2--constraints-feasibility.md M1; crit/D4--constraints-feasibility.md D-1;
crit/D4--loop-false-block.md §2.2). `DOD=absent` cannot co-occur with `LOOP_OPEN=1`.

```diff
   elif [ "$YOURS" -gt 0 ]; then … 👤 … (unchanged)
+  elif [ "$LOOP_OPEN" -eq 1 ]; then
+    # A loop has no boxes, so REMAINDER=0 cannot say it is unfinished. Without this arm a class-B re-file
+    # turns the false ⛔ into a false ✅ and boundary-handoff's free-win advises a recycle (control C5).
+    RUNG="🔧"; LOOP_RUNG=1
+    READOUT="🔧 Loose ends — your frozen scope is a loop with no recorded stop (\"${LOOP_HEAD:0:80}…\"); run the next round as scoped, or record its stop: ~/.claude/hooks/dod-persist.sh done \"<evidence>\"."
   elif [ "$DOD" = "absent" ]; then …
```

👤 outranking the loop is deliberate: it is the release for "every remaining round needs an operator-only act"
(maps/legit-stops.md §6 C7) — file that act with `cc-backlog needs … --class needs-human` and the session may close,
visibly, in the operator block.

**(vii) `rung_next` (`:3096-3103`)**:

```diff
     "⛔") if [ "$BLOCKED" -eq 0 ] && [ "$BLOCKED_RECHECKED" -gt 0 ]; then …unchanged…
+          elif [ "${SCOPE_UNGATED:-0}" -gt 0 ]; then
+            printf 'continue → drive the in-scope work the open decision(s) do not gate (%s); the decision(s) stay in line 1' \
+              "$( [ "$LOOP_OPEN" -eq 1 ] && printf 'loop scope: run the next round as scoped' || printf '%s DoD item(s)' "$OWN_REMAINDER")"
           else …today's STOP-ASK text…
```

`"🔧"` keeps `continue → finish · run-gate · commit`; when `LOOP_RUNG=1` it reads `continue → run the next round as scoped`.

**(viii) Emit** after `RECHECKED_SRC=` (`:2913`), all after `LIVE=` (line 18), so the BUSY splice check (`:575-599`)
is untouched; numeric fields first, free text last: `BLOCKED_IDS`, `LOOP_SCOPE`, `LOOP_OPEN`, `LOOP_SRC`
(`n-a|own|done|superseded|program|answered|none|nosid|nolib|off|error`), `LOOP_RUNG`, `OWN_REMAINDER`, `HELD`, `HELD_SRC`
(`n-a|own|lapsing|lapsed|stale|released|absent`), `HELD_UNTIL` (epoch or empty), `SCOPE_UNGATED`, `LOOP_HEAD`, `HELD_WHY`, `BLOCKED_GLOSS`. `emit_full` gains one
`LOOP` row.

**(ix) Memo key (`:637`)**: `v1|` → `v2|` (the emit shape changed; maps/wrap-ledger.md §4) and append
`|${WRAP_LOOP_SCOPE:-}|${_wl_lsoff}`, where `_wl_lsoff=""; [ -e "$HOME/.claude/state/loop-scope.off" ] && _wl_lsoff=F`
runs just before the key is built (a builtin test in the current shell, no fork; a `$(…)` here would fork).

**(x) Header (`:20-31`)**: ⛔ "an open class-C decision packet THIS SESSION filed … carries `SCOPE_UNGATED`/`HELD`: a ⛔
with ungated own scope is a decision to relay AND work to drive"; 🔧 gains "∨ an own recorded loop scope with no
recorded stop (§ LOOP), ranked just above ✅". The ladder line (`:20`) and its four doc copies (`G:710`, `R:90`,
`commands/wrap.md:74`, `hooks/lib/why-tier.sh:83`) stay true: no rung is reordered, no glyph is added.

### 3.2 C1 + C3 — `hooks/dod-persist.sh`

New CLI modes beside `set|path|get` (`:484-517`), plus two guards. Every new mode exits 0 on success, 2 on refusal, and
writes through the existing `persist_dod` (`:172-194`), so the producer stays the store's single writer.

```bash
+  hold)   # dod-persist.sh hold <12-hex id|none> "<what it gates and why>"
+    id="${2:-}"; why="${3:-}"; sid="${CLAUDE_CODE_SESSION_ID:-}"; until=""
+    { [ -n "$sid" ] && [ -n "$why" ] && [[ "$id" =~ ^([0-9a-f]{12}|none)$ ]]; } \
+      || { printf 'usage: dod-persist.sh hold <decision id|none> "<what it gates and why>" (needs a session)\n' >&2; exit 2; }
+    case "$why" in *"Scope ("*) printf 'refused: the reason may not contain a Scope line\n' >&2; exit 2 ;; esac
+    if [ "$id" != none ]; then   # a hold names an OPEN class-C decision: a class-B default fires, so it holds nothing
+      pkt="$(_dp_decide_open_c "$id")" || { printf 'refused: %s is not an open class-C decision (cc-decide list --open --class C)\n' "$id" >&2; exit 2; }
+      # ...and only an OPERATOR-ONLY gate holds the drive. Two independent signals: the ceiling the filer
+      # declared (§3.6) and scripts/gate-classify.sh on the packet's what_plain (the repo's own router).
+      ceil="$(printf '%s' "$pkt" | jq -r '.ceiling // ""')"
+      case "$ceil" in self-mod|money|permission|credential|g2) dc=1 ;; *) dc=0 ;; esac
+      rt="$("${CC_GATE_CLASSIFY_BIN:-<self-resolved>/../scripts/gate-classify.sh}" "$(printf '%s' "$pkt" | jq -r '.what_plain // ""')" 2>/dev/null | cut -c1)"
+      case "$dc$rt" in
+        1C) ;;                                                     # durable: lapses only when answered
+        1*|0C) until=$(( $(date +%s) + ${CC_SCOPE_FLOOR_WINDOW_S:-21600} )) ;;   # one signal: lapsing
+        *) printf 'refused: %s declares no operator-only ceiling and gate-classify routes it %s. A judgment call with a status-quo course is class B and holds nothing: cc-decide open --class B --what … --default "<the frozen-scope course>" --deadline <ISO> --default-effect no-change --project <repo> --conviction N --receipt R. If it truly is a money, self-modification, permission, credential or G2 gate, file it again with --ceiling.\n' "$id" "${rt:-?}" >&2; exit 2 ;;
+      esac
+    fi
+    dod_prime "$PWD"; f="$(dod_path_for "$PWD" write)"
+    persist_dod "$f" "Scope (held): $id${until:+ until=$until} — $why" "$PWD" "manual-hold" "$sid"
+    printf 'held%s → %s\n' "${until:+ (lapses in ${CC_SCOPE_FLOOR_WINDOW_S:-21600} s: one signal only)}" "$f"; exit 0 ;;
+  done)   # dod-persist.sh done "<evidence the loop's condition holds, or the operator's ruling>"
+    ev="${2:-}"; sid="${CLAUDE_CODE_SESSION_ID:-}"
+    { [ -n "$sid" ] && [ -n "$ev" ]; } || { printf 'usage: dod-persist.sh done "<evidence>" (needs a session)\n' >&2; exit 2; }
+    case "$ev" in *"Scope ("*) printf 'refused: the evidence may not contain a Scope line\n' >&2; exit 2 ;; esac
+    dod_prime "$PWD"; f="$(dod_path_for "$PWD" write)"
+    persist_dod "$f" "Scope (done): $ev" "$PWD" "manual-done" "$sid"; printf 'done → %s\n' "$f"; exit 0 ;;
+  capture-loop)   # C1, called by session-continue at Stop. Prints captured|captured-rescope|not-loop|own-exists|none
+    tp="${2:-}"; sid="${CLAUDE_CODE_SESSION_ID:-}"
+    { [ -n "$sid" ] && [ -f "$tp" ] && command -v jq >/dev/null 2>&1; } || { echo none; exit 0; }
+    # NEWEST human-origin prompt line that STARTS with the prefix. Human origin: type user, not isMeta,
+    # origin.kind human or absent, no tool_result in the content (lane briefs live in tool_results: TX:3875).
+    scope="$(grep -a 'Scope (frozen):' "$tp" | jq -r 'select(.type=="user" and (.isMeta != true)
+               and ((.origin.kind // "human") == "human")) | .message.content
+             | if type=="string" then . elif type=="array" then
+                 (if ([.[]?|select(.type=="tool_result")]|length) > 0 then empty
+                  else ([.[]?|select(.type=="text")|.text]|join("\n")) end) else empty end' 2>/dev/null \
+             | grep -aE '^[[:space:]>*-]*Scope \(frozen\):' | tail -1 | sed -E 's/^[[:space:]>*-]*//')"
+    [ -n "$scope" ] || { echo none; exit 0; }
+    dod_prime "$PWD"; f="$(dod_path_for "$PWD" write)"
+    own="$(_dp_own_intent_scope "$f" "$sid")"          # newest own non-PreCompact frozen line, "" if none
+    if [ -z "$own" ]; then
+      _dp_is_loop "${scope#Scope (frozen):}" || { echo not-loop; exit 0; }   # loop scopes only: no DRAIN_SCOPE crosstalk
+      persist_dod "$f" "$scope" "$PWD" "stop-capture" "$sid"; echo captured; exit 0
+    fi
+    # the operator re-scoped a LOOP session in a later prompt: record it so the loop stops being driven
+    if _dp_is_loop "${own#Scope (frozen):}" && [ "$own" != "$scope" ]; then
+      persist_dod "$f" "$scope" "$PWD" "stop-capture" "$sid"; echo captured-rescope; exit 0
+    fi
+    echo own-exists; exit 0 ;;
```

`_dp_is_loop` applies the same verb-first pattern as the ledger (`LOOP_RE`, one definition in a new
`hooks/lib/loop-scope.sh` sourced by both, so producer and consumer cannot drift; D2:95-96). `_dp_decide_open_c` runs
`"${CC_DECIDE_BIN:-<self-resolved>/../bin/cc-decide}" list --open --class C --json | jq -ec --arg id "$id" 'first(.[] | select(.id==$id))'`
and prints that packet (rc 1 when absent). The gate-classify path resolves beside the hook (`~/.claude/scripts/gate-classify.sh`
is the deployed link, measured `ls -la`); the router is pure text matching with no write (`scripts/gate-classify.sh:16-22`).

**The hold tiers** (the critic's blocker: the block text names `hold`, and before this revision any open own class-C id
was accepted, so one `hold e869fac7eb34 …` would have set `SCOPE_UNGATED=0` for good and turned the 11-hour idle into a
reported one). A hold now needs an operator-only gate, judged by two independent signals: the ceiling the filer
declared (`--ceiling`, §3.6) and `gate-classify`'s route of the packet text.

| Ceiling declared (`self-mod\|money\|permission\|credential\|g2`) | gate-classify | Hold | Example |
|---|---|---|---|
| yes | C | **durable** (lapses only when the packet is answered) | a settings or hook edit filed with `--ceiling self-mod` |
| yes | B | **lapsing**: counts for `CC_SCOPE_FLOOR_WINDOW_S` (6 h), then the floor fires again and the supervisor re-confirms | `a247b7288149` re-filed with `--ceiling money` (it routes B, a router false negative, maps/cc-decide.md §5); a false ceiling on "stop the loop?" |
| no (legacy packet) | C | **lapsing** | the 15 open legacy class-C packets that route C (§9.3 M16) |
| no | B | **refused**, rc 2, with the class-B command | `e869fac7eb34` and `290215743799` (both route B, §9.3 M16); 33 of the 48 open class-C packets |

Neither signal alone can end the drive for good: the router misses genuine gates (`a247b7288149`), and a ceiling is
the filer's own claim. A false ceiling costs the lead one floor fire and one supervisor re-confirm per 6 h, and its
ceiling is printed beside gate-classify's disagreement at open time (§3.6). A legacy genuine gate the router misses
(router B, no ceiling) is refused; the lead's route is to file it again with `--ceiling` (a new id, since `mk_id` keys
on class, session and text, `bin/cc-decide:341-342` per maps/cc-decide.md §7) and hold that. That is one more packet in
the operator's queue, visible, and it is confined to sessions with an own loop capture (none of the 48 open class-C
packets sits in one, §9.3 M3).

Guards on existing modes:

```diff
   set)
     scope="${2:-}"
+    case "$scope" in "Scope (held):"*|"Scope (done):"*)
+      printf 'refused: use `dod-persist.sh hold` or `dod-persist.sh done`\n' >&2; exit 2 ;; esac
```

Today `set "Scope (done): …"` is rewritten to `Scope (frozen): Scope (done): …` and becomes the new contract
(maps/wrap-ledger.md §2.5(b)). And `extract_scope` (PreCompact, `:143-150`) gains `and (.isMeta != true)` on user
records, so an injected skill or command body, or any hook text, can never become a captured contract (Stop-hook
feedback and the cc-wake frame are `isMeta:true`, TX:4274, TX:5067; crit/D4--incident-replay.md §4). No new text
written by this design contains the literal `Scope (frozen):` (pinned, §7), and the rule text never shows a loop line
with that prefix, because an assistant quote of it would be scraped by PreCompact (crit/D4--loop-false-block.md §3.2).

**Capture recall: a loop the lead itself restates.** `capture-loop` reads only human-origin prompts. A lead that
restates "loop until X" itself, as R:26 directs, is recorded today only by PreCompact (0 PreCompact blocks among the
store's 367 headers, and excluded here as non-intentional) or by a manual `set` (measured, §9.3 M17). R:26's
parenthetical "(`dod-persist.sh` captures it)" is therefore false in practice. Two fixes were weighed. Accepting the
session's own assistant text as a capture source was measured first: over the 1,272 recent transcripts that contain
`Scope (frozen):`, 33 sessions state a line-anchored scope line in assistant text outside a code fence, and **0** of
those lines is a verb-first loop (§9.3 M18). That source adds no recall, so it is not built. The fix is the rule: R-06
replaces the false parenthetical with "record it: `~/.claude/hooks/dod-persist.sh set "<that line>"`", the same command
`commands/handoff.md:133-134` already prescribes before a recycle. A `set` is an intentional `manual-set` capture, so the
ledger reads it at once.

### 3.3 `hooks/lib/inflight.sh` (new)

Two pure functions, sourced by session-continue through the same `$0`-symlink resolution as `_sc_turn_lib`
(`hooks/session-continue.sh:1388-1398`), so a brand-new lib is reachable on the fast-forward before install.sh links it:

- `inflight_waves <transcript>` — a **verbatim copy** of `bh_live_waves` (`hooks/boundary-handoff.sh:875-903`). Copy,
  not move: moving it would put boundary-handoff and its 71-test suite into the change and add a fail-open path to its
  free-win guard (crit/D4--constraints-feasibility.md D-5; crit/D2--constraints-feasibility.md m3). A parity test runs
  both on one fixture (§7).
- `inflight_bg_tasks <transcript>` — started ids are every `Command running in background with ID: <id>` in the
  transcript (TX:4435) **and every `agentId: <id>` in an `Async agent launched` tool result** (a background Agent
  subagent: `Agent` with `run_in_background`; measured in 192 of 1,681 recent transcripts, §9.3 M19); finished ids are
  every `<task-id><id></task-id>` in **any** record kind, which already covers both, because an async agent finishes
  with `<task-id><agentId></task-id>` (measured: `a8e552e552430265c` in `d2aecafb…jsonl`). Notifications arrive as
  user records (TX:4428) but also, when the model is mid-turn, as `queued_command` attachments and `queue-operation`
  records (TX:4472-4473). Live = started − finished, minus Bash tasks whose command is a watcher: the **basename** of
  the command's first word that is not a `VAR=value` assignment, `timeout <n>`, `gtimeout <n>` or `env` is
  `cc-await-ping` (`${w##*/}`), because B13 launched every watcher by absolute path (73 × `/Users/chrisren/.claude/bin/cc-await-ping`,
  0 bare, §9.3 M20; a literal first-word match would count `bpctefji1` and `b5rshfkra` as work and silence F1 and F2,
  the M14 trap in a new form). A watcher is not work (maps/incident-replay.md §8.3). A task is counted only while it is
  fresh: a Bash task's output file (the path in the same tool result), or an agent's transcript
  `<transcript dir>/<sid>/subagents/agent-<id>.jsonl` (measured layout, `d2aecafb…/subagents/`), written within
  `CC_BH_WAVE_WARM_S` (1800 s), the waves' freshness rule, so an orphaned id cannot hold the floor down forever. Three
  `grep -oE` passes over the whole transcript plus one `jq` lookup of the commands of the (few) live Bash ids; prints the
  count with the kinds (`bg`, `agent`), or `?` when unreadable. This is the fix for D4's measured false fires on
  2026-10-23, where each round was fired from a background Bash job (crit/D4--loop-false-block.md §2.1), and for the
  background-subagent blind spot crit/D3-schema-first--loop-false-block.md D-11 named.
  **Measured trap:** a detector that reads finished ids only from user records reports 7 "live" tasks at F1, F2 and
  F3 (watchers plus a round-23 `scripts/ship-land.sh` started on 10-22), which would have silenced the floor at all
  three idle closes; counting every record kind leaves only the armed watcher (F1 `bpctefji1`, F2 `b5rshfkra`) and
  nothing at F3 (§9.3 M14).

### 3.4 C4 + C5 — `hooks/session-continue.sh`

**(i) The scope floor**, a fourth floor between `ship_floor` and `wake_floor` (`:1316-1328`):

```diff
   if ! mechanical_arm; then
     if ! _sf_json="$(ship_floor)"; then …unchanged… fi
+    if ! _scf_json="$(scope_floor)"; then
+      mark_blocked scope-floor          # completion-assert yields its ledger arm (hooks/completion-assert.sh:1275-1298)
+      printf '%s' "$_scf_json"; exit 0
+    fi
     if ! _wf_json="$(wake_floor)"; then …unchanged…
```

```bash
+# ── SCOPE FLOOR (ruling d610f8473106; the B13 idle, 2026-10-24) ────────────────────────────────────
+# Reads ONLY ledger facts about THIS session's recorded contract (SCOPE_UNGATED: an own loop line or
+# own boxes, minus a recorded hold) — never close prose, never packet class. Not the banned scope-blind
+# hook (:4-10): the scope it reads is the contract line the session itself recorded, not a judgment of
+# the tree. BOUNDS, all per session id (never per cwd) and never reset by a key change:
+#   · no fire on a Stop whose turn THIS floor's block opened, directly or through a chain of other
+#     Stop hooks' feedback turns since it                                  → scope-floor-reclose
+#   · ≥ CC_SCOPE_FLOOR_GAP_S (600) between two fires to one session         → scope-floor-gap
+#   · ≤ CC_SCOPE_FLOOR_MAX (3) fires per key per CC_SCOPE_FLOOR_WINDOW_S (21600) → scope-floor-key-cap
+#   · ≤ CC_SCOPE_FLOOR_DAY_MAX (6) fires per session per rolling 86400 s   → scope-floor-day-cap
+#   · state unwritable ⇒ no block (fail closed)                            → scope-floor-unwritable
+# LOGGED (B-3, :64-79): every evaluation on a relevant rung, and one scope-floor-clear when a session
+# this floor fired on reaches an irrelevant rung (the supervisor's oracle must never read a stale row).
+# SILENT: switches off, no jq, no ledger, irrelevant rung with no state.
+# Seams: CC_SCOPE_FLOOR (1|0|shadow) · ~/.claude/state/scope-floor.off · CC_SCOPE_FLOOR_MAX ·
+#   CC_SCOPE_FLOOR_WINDOW_S · CC_SCOPE_FLOOR_DAY_MAX · CC_SCOPE_FLOOR_GAP_S · CC_SCOPE_CAPTURE · WRAP_LEDGER_BIN ·
+#   INFLIGHT_LIB · TURN_SCAN_LIB · DOD_PERSIST_BIN · CC_TELEMETRY_DIR · CONTEXT_ECON_LIB · CC_BOUNDARY_T ·
+#   CC_BOUNDARY_T_MIN · CC_BOUNDARY_LEAD_MIN · CC_BOUNDARY_SIZE_MB · CC_BOUNDARY_RSS_MB · CC_BOUNDARY_TOK_K
+OPHOLD_RE='(^|[^[:alnum:]])(hold off|hold on|wait (for|on|until|till) (me|my|i)|pause|park (this|it|the)|no more rounds|stop the loop|until i (say|reply|answer|decide|review|look|get back|am back|.m back)|don.?t (start|run|continue|do anything)|not yet)([^[:alnum:]]|$)'
+SF_MACHINE_RE='^(Stop hook feedback|<task-notification|\[handoff |<teammate-message|<local-command-stdout>|Another Claude session sent a message|⏯ )|HANDOFF-ENGAGE-'
+scope_floor() { # → JSON on stdout + rc 1 to BLOCK; rc 0 otherwise. Never fails.
+  case "${CC_SCOPE_FLOOR:-1}" in 0|off) return 0 ;; esac
+  [ -e "$HOME/.claude/state/scope-floor.off" ] && return 0
+  command -v jq >/dev/null 2>&1 || return 0
+  local led="${SC_LED_CACHE:-}"
+  if [ -z "$led" ]; then                     # mechanical_arm returned before its read: never fork the
+    sf_is_assignee && return 0               # ledger for an assignee or a torn-down session
+    wf_teardown_marked && return 0           # (crit/D4--constraints-feasibility.md D-8)
+    led="$(sc_read_ledger)"                  # the resolution factored out of ship_floor (:1203-1214); memo hit
+  fi
+  [ -n "$led" ] || return 0
+  # fields (absent ⇒ today's behaviour: an old ledger is silent) …
+  [ "$lsrc" = none ] && case "$rung" in "⛔"|"✅"|"👤") sc_capture_loop ;; esac   # C1; effective next Stop
+  case "$rung" in
+    "⛔") { [ "$blocked" -gt 0 ] || [ "$rechk" -gt 0 ]; } || { sf_clear_if_active; return 0; }; kind=blocked ;;
+    "🔧") [ "$lrung" = 1 ] || { sf_clear_if_active; return 0; }; kind=loop ;;       # only the loop arm's 🔧
+    *)    sf_clear_if_active; return 0 ;;
+  esac
+  # ── decision-bearing from here: every exit is logged with {kind,ungated,held,ids,head,key,count,day} ──
+  { [ "$bsrc" = error ] || [ "$lsrc" = error ] || [ "$csrc" = error ] \
+    || { [ "$kind" = blocked ] && [ "$csrc" = skip ] && [ "$ung" -gt 0 ]; }; } && { sf_log abstained unknown; return 0; }
+  [ "$ung" -gt 0 ]                   || { sf_log abstained nothing-ungated; return 0; }  # held, or nothing left
+  kill_switch_active                 && { sf_log abstained kill-switch;   return 0; }
+  sf_operator_hold                   && { sf_log abstained operator-hold; return 0; }      # OPHOLD_RE on last_user_msg
+  sf_is_assignee                     && { sf_log abstained assignee;      return 0; }
+  sf_headless                        && { sf_log abstained headless;      return 0; }      # no terminal to continue in
+  wf_teardown_marked                 && { sf_log abstained teardown;      return 0; }
+  [ "$research" = none ]             || { sf_log abstained research;      return 0; }
+  [ "$goal" = live ]                 && { sf_log abstained goal;          return 0; }      # the /goal evaluator owns it
+  sf_context_high                    && { sf_log abstained context-high;  return 0; }      # boundary-handoff recycles
+  # in flight: custody · land · teammates · workflow waves · non-watcher background tasks
+  sf_inflight || { sf_log abstained "$SF_INFLIGHT_WHY"; return 0; }                       # inflight | unknown
+  # the turn now ending: who opened it, and did it write? Six turns, newest first: walk back over turns that
+  # other Stop hooks' feedback opened; a floor block anywhere in that chain makes this a re-close of it.
+  _sc_turn_lib || { sf_log abstained unknown; return 0; }
+  local scan b w; scan="$(turn_scan "$_sc_tp" 6)" || { sf_log abstained unknown; return 0; }
+  printf '%s\n' "$scan" | jq -sre 'reverse | until(length == 0 or ((.[0].b // "") | startswith("Stop hook feedback") | not)
+       or ((.[0].b // "") | contains("⟳ SCOPE FLOOR")); .[1:]) | (length > 0 and ((.[0].b // "") | contains("⟳ SCOPE FLOOR")))' \
+       >/dev/null 2>&1 && { sf_log abstained reclose; return 0; }
+  b="$(printf '%s\n' "$scan" | tail -1 | jq -r '.b // ""')"; w="$(printf '%s\n' "$scan" | tail -1 | jq -r '.w')"
+  if [ "$w" = false ] && ! printf '%s' "$b" | grep -qE "$SF_MACHINE_RE"; then
+    sf_log abstained conversation; return 0        # a read-only answer to the operator is not an idle
+  fi
+  case "${CC_SCOPE_FLOOR:-1}" in shadow)                                                   # BEFORE the budget:
+    # shadow must not spend the real windows, or switching shadow → on would start with them spent;
+    # the same accounting on a separate <sid>.shadow map still records where a cap would have bitten
+    sf_budget_take --shadow || { sf_log abstained "shadow-$SF_BUDGET_WHY"; return 0; }
+    sf_log abstained shadow; return 0 ;; esac
+  # ── latch: per-sid map + rolling windows (state written BEFORE the block; unwritable ⇒ no block) ──
+  sf_budget_take || { sf_log abstained "$SF_BUDGET_WHY"; return 0; }                      # gap | key-cap | day-cap | unwritable
+  sf_log fired ""
+  jq -nc --arg r "$(sf_reason)" '{decision:"block",reason:$r}'; return 1
+}
```

Helper contracts (each ≤ 15 lines; the implementer writes them):

- `sf_budget_take`: state file `"$(continue_state_dir)/scope-floor/<sid>"` (sid sanitized with `tr -c 'A-Za-z0-9-' _`),
  lines `F <epoch> <key>`, one per fire. Refuse `gap` when the newest `F` line is younger than `CC_SCOPE_FLOOR_GAP_S`
  (600 s); count lines with this key and epoch ≥ now − window, and all lines with epoch ≥
  now − 86400; refuse at the caps; else append `F <now> <key>` with `>>` and verify the append (fail closed). Prune
  lines older than 86400 s on write. Key = `sha1(kind|sorted BLOCKED_IDS∪RECHECKED_IDS|LOOP_HEAD)[0:12]` with the
  `${CC_SHA1:-/sbin/sha1sum}` + `sha1sum` fallback the repo already uses (`hooks/accounts-board.sh:51`;
  crit/D2--incident-replay.md D9). A map of fires, not a single slot, so A→B→A cannot re-arm A
  (crit/D2--loop-false-block.md §1.1); a per-session file, so two sessions in one cwd cannot reset each other
  (crit/D3--loop-false-block.md D-1, crit/D4--loop-false-block.md §1.2); no HEAD or trunk in the key, so a sibling's
  land cannot re-arm it (crit/D3--loop-false-block.md D-3).
- `sf_clear_if_active`: when the state file's last line is not `C …`, append `C <epoch>` and log
  `abstained scope-floor-clear` once; silent otherwise.
- `sf_inflight`: `CUSTODY_OPEN>0`, `LANDING=1`, `RESIDENT_MINE>0`, `inflight_waves>0`, `inflight_bg_tasks>0` ⇒ `inflight`
  (with `{what,n}`); a lib that does not resolve, or a `?`, ⇒ `unknown`. An armed watcher alone is **not** in flight.
- `sf_context_high`: all five of boundary-handoff's fire axes, with its defaults (`hooks/boundary-handoff.sh:154`,
  `:162-167`, decision at `:661-672`): telemetry `used_pct ≥ ${CC_BOUNDARY_T:-73}`; **forecast-early**, `used_pct ≥
  ${CC_BOUNDARY_T_MIN:-55}` with `0 ≤ forecast ≤ ${CC_BOUNDARY_LEAD_MIN:-20}` min to the wall; transcript bytes ≥
  `${CC_BOUNDARY_SIZE_MB:-25}` MiB; **process RSS ≥ `${CC_BOUNDARY_RSS_MB:-1500}` MiB**; telemetry input tokens ≥
  `${CC_BOUNDARY_TOK_K:-700}` K. It sources the same `hooks/lib/context-econ.sh` (resolved as boundary-handoff does,
  `:196-198`) and calls its read-only `ce_size "$_sc_tp" "$tel"` (bytes and RSS, one `ps`) and `ce_burn "$tel"` (the
  forecast from the `.hist` samples), never `ce_sample`, which writes and stays boundary-handoff's. A missing lib or a 0
  reading is "unknown" on that axis and cannot clear a positive threshold, the same rule boundary-handoff applies
  (`:450-452`). So the floor yields wherever the recycle advisory can fire and the two never send opposite blocks on one
  Stop; boundary-handoff does not read `${sentinel}.blocked` (measured, `grep -c '\.blocked'` = 0), so the yield has to
  sit in the floor (crit/D3--loop-false-block.md D-7). `CC_TELEMETRY_DIR` is an existing seam of this hook (pinned at
  `tests/session-continue.bats:28`).
- `sf_headless`: wake_floor's own predicate, verbatim (`hooks/session-continue.sh:734`: `[ -n "${CC_PANE_ID:-}" ] && [ -z
  "${ITERM_SESSION_ID:-}" ]`, a resident stream-json agent, for which a blocked Stop is a death, not a nag, `:715-717`),
  or an empty pane address (`_ouid`, `:468`; a `claude -p` one-shot run from no pane). A floor turn in either extends a
  run nobody is watching; the supervisor nudge cannot reach them either. Fails toward today's behaviour.
- `sf_operator_hold`: `OPHOLD_RE` on the memoized last genuine user message (`last_user_msg`, `:420-433`); falls back to
  a live read when `CC_SC_KILL_MEMO=0` (crit/D2--constraints-feasibility.md m8). Measured: 14 of 14 hold phrasings
  match and B13's own last operator messages (TX:4114, TX:4163) do not (§9.3 M4). A false match only abstains, which
  is today's behaviour.
- `sf_log`: `log_idl "$1" "scope-floor${2:+-$2}" '{kind,ungated,held,held_id,held_until,ids,head(≤80),key,count,day,max,rung}'`
  (`held_until` = the lapsing hold's epoch, `null` for a durable one; the ledger emits it as `HELD_UNTIL`)
  with a literal `'{}'` default for the extras object, never `${4:-{\}}`, which `/bin/bash` 3.2 expands to `{\}`
  (crit/D4--constraints-feasibility.md D-7).
- `sc_capture_loop` (C1 trigger): one `grep -c 'Scope (frozen):'` of the transcript (measured 0.012 s on 9 MB, D4 §1
  F4); a per-sid marker `…/scope-floor/<sid>.cap` holding that count, written **before** the call, so an unchanged
  count never re-runs it; then `dod-persist.sh capture-loop "$_sc_tp"` under `CLAUDE_CODE_SESSION_ID=$cur_sid`; logs
  `captured scope-capture` on `captured*`. Runs only while `LOOP_SRC=none` and only on ⛔/✅/👤 Stops. `LOOP_SRC=none`
  now also covers a checkout with **no store file yet** (§3.1 (ii)); before this revision such a checkout read `n-a`
  and was never captured, which is where goal (e) needs the capture most (9 of the 78 store files are repo-keyed,
  measured `ls`). A count of 0 writes no marker and forks nothing, so the many sessions with no store pay one `grep -c`.

**Block reason (`sf_reason`), kind `blocked`** — fixed template, no literal `Scope (frozen):`:

```
⟳ SCOPE FLOOR — you are going idle on ⛔ while in-scope work your open decision(s) do not gate remains:
<your loop scope ("<head>…") | N unchecked item(s) of your frozen DoD>. Nothing is in flight (no open custody,
land, teammate, workflow, background task or background agent); an armed watcher wakes you only on mail, so this
work does not move until you run it.
An open decision holds only the act it names; until it is answered the frozen scope is the course
(operator ruling d610f8473106). Open: <id ("gloss"); …>.
Do the next ungated step now (a loop scope: run the next round as scoped). Never build the gated act itself.
[If you hold unlanded commits the decisions do not gate, land them first (ship policy).]
Only if EVERY remaining in-scope item truly waits on one of these decisions, and it is a money,
self-modification, permission, credential or G2 gate (a question about when a loop stops never gates the loop):
~/.claude/hooks/dod-persist.sh hold <id> "<what it gates and why>" — it refuses a packet that declares no such
ceiling and does not route C, and your close then shows the hold to the operator.
If the loop's stop condition holds, or the operator ruled it stopped: ~/.claude/hooks/dod-persist.sh done "<evidence>".
(scope floor <n>/3 for this state · <m>/6 today)
```

Kind `loop` (no decision open): "⟳ SCOPE FLOOR — your frozen scope is a loop with no recorded stop ("<head>…") and you
are going idle with nothing in flight. Run the next round as scoped. If its stop condition holds or the operator ruled it
stopped: `~/.claude/hooks/dod-persist.sh done "<evidence>"`. If every remaining round needs an operator-only act, file
that act (`cc-backlog needs "<step>" --class needs-human`): the ledger then reads 👤 and you may close. (scope floor n/3 ·
m/6 today)". No re-file-and-action recipe appears in any machine text: telling an agent to `cc-decide action` its own
class-C packet would launder a genuine C10/C6 gate (crit/D2--constraints-feasibility.md M2).

**(ii) C5 — the mechanical arm also arms on ⛔ for own dirt** (`:1103`). Committing to a branch is never the gated
act; landing may be. So the ⛔ text forbids landing, and the ⛔ arm has its own budget so it cannot spend the 🔧 one
(crit/D2--constraints-feasibility.md m1; crit/D3--loop-false-block.md D-5):

```diff
-  [ "$rung" = "🔧" ] || return 1
+  local _ma_blk=0
+  case "$rung" in
+    "🔧") ;;
+    "⛔") case "${CC_MECH_BLOCKED:-1}" in 0|off) return 1 ;; esac
+         [ -e "$HOME/.claude/state/mech-blocked.off" ] && return 1
+         _ma_blk=1 ;;
+    *) return 1 ;;
+  esac
   …attribution unchanged (session_dirty_mine rc 0 only)…
-  mfile="${f}.mech"; mmax="${CC_MECH_MAX:-2}"
+  if [ "$_ma_blk" = 1 ]; then mfile="${f}.mech.blk"; mmax="${CC_MECH_BLK_MAX:-1}"; else mfile="${f}.mech"; mmax="${CC_MECH_MAX:-2}"; fi
   …
-  printf '%s' "Commit the … Run the repo's gate, commit with explicit paths, then land per the repo's ship policy. …"
+  if [ "$_ma_blk" = 1 ]; then _ma_land="Run the repo's gate and commit with explicit paths on your branch. Do NOT /ship while decision(s) $(led_field "$led" BLOCKED_IDS) are open unless the land is outside what they gate."
+  else _ma_land="Run the repo's gate, commit with explicit paths, then land per the repo's ship policy."; fi
+  printf '%s' "Commit the ${n_files} file(s) you edited this turn that are still uncommitted: ${shown}. ${_ma_land} Deliberately parked, or not yours? Run \`~/.claude/hooks/session-continue.sh clear\` and say so in your close." > "$f"
   …
-  log_idl armed "mechanical-dirty" "$(jq -cn … '{cwd:$c,files:$n,source:"session-writes"}')"
+  log_idl armed "mechanical-dirty" "$(jq -cn … --arg r "$rung" '{cwd:$c,files:$n,source:"session-writes",rung:$r}')"
```

Worst case: `CC_MECH_BLK_MAX` (1) × `CLAUDE_CONTINUE_MAX` (8) = 8 forced turns per session, self-clearing on commit
(`:1112-1154`), and `clear` spends the budget rather than deleting it.

The ⛔ arm deliberately does **not** test `SCOPE_UNGATED`: it arms on **any** ⛔ with own uncommitted edits, including a
genuine all-gating C10/C6 gate. Committing to a branch is never the gated act, and R:38 (kept in R-07) already says
"commit in-progress work first" before stopping on a decision; so a genuine gate with own dirt now costs one commit
turn, and §4.2 says so. A test pins this (M1b, §7.4) so a later change to gate it on `SCOPE_UNGATED` is deliberate.

**(iii) Text in the same file.** Header `:13-14`: "arm — on 🔧, or on a ⛔ whose readout says `Not gated by it`; the
mechanical arm also arms once on any ⛔ with own uncommitted edits (commit only, never land)" and
"disarm — on ✅/📦/held ⛔/📤, read-only, or …and stop". `continue_reason` (`:1368`, the one builder the re-block skip
compares against): "When done (✅/📦), held on the user for everything that remains (a held ⛔), or out of context (📤)".

### 3.5 C6 — `scripts/lead-supervisor.sh`

After the last idle Stop no Stop hook can act (maps/incident-replay.md §8.6); the supervisor's STALL? branch can, and
`cc-notify <sid>` to a watcher-less live pane socket-wakes it (proven on this session at 20:27:36Z, TX:5065-5069;
maps/wake-path.md §3). The nudge must not ride `page()`/`send_page`, whose target is empty (`:414-415`).

```bash
+SUBJECT_NUDGE="${CC_SUP_SUBJECT_NUDGE:-1}"         # 1 | shadow | 0 ; or ~/.claude/state/subject-nudge.{off,shadow}
+NUDGE_MAX="${CC_SUP_NUDGE_MAX:-3}"                 # per key (the floor row's key = decision state)
+NUDGE_BACKOFF_S="${CC_SUP_NUDGE_BACKOFF_S:-1800}"  # attempt k+1 waits BACKOFF·2^(k-1) after attempt k (30 min, 1 h)
+NUDGE_ARMED_S="${CC_SUP_NUDGE_ARMED_S:-3600}"      # after verdict reason=wake-path-armed: re-check in 1 h (detached-watcher hole)
+NUDGE_SID_DAY="${CC_SUP_NUDGE_SID_DAY:-4}"         # per session, rolling 24 h, whatever the key
+NUDGE_GAP_S="${CC_SUP_NUDGE_GAP_S:-1800}"          # minimum gap between any two nudges to one session
+NUDGE_PER_SWEEP="${CC_SUP_NUDGE_PER_SWEEP:-3}"     # fleet cap, FILE-backed ($PAGEDIR/.nudge-sweep): assess() runs in $(…)
+NUDGE_HORIZON_SLACK_S="${CC_SUP_NUDGE_HORIZON_SLACK_S:-1200}"  # digest before GC_S - this (2 × SUPERVISOR_SWEEP_MAX_S)
+nudge_subject(){ # $1=sid $2=transcript_age_s $3=telemetry_age_s — called in assess()'s STALL? branch. Never fails.
+  # 1. oracle: the session's NEWEST `scope-floor*` row, void only if a NEWER session-continue row shows the
+  #    session was re-armed or forced on (reason `continue`, `cli-set`, or any event `fired`). Rows other floors
+  #    log on the same or a later Stop (`wake-floor-*`, `ship-floor-*`, `mechanical-*` abstains) never void it:
+  #    wake_floor runs right after scope_floor whenever the latter returns 0 (hooks/session-continue.sh:1316-1328)
+  #    and logs `wake-floor-mechanical-arm` on every such Stop with no watcher (:690; 19 rows in production,
+  #    §9.3 M21), so "the newest session-continue row" would read that row and never nudge again.
+  rows="$(sup_bounded 5 grep -F "\"sid\":\"$sid\"" "$IDL" | grep -F '"hook":"session-continue"' | tail -200)"
+  [ -n "$rows" ] || rows="$(newest idl.jsonl.2*.gz, same filter)"   # rotation; never the idl.jsonl.chain.* archive
+  row = newest of $rows with reason starting "scope-floor"; void if a later row in $rows has reason continue|cli-set
+     or event fired.
+  accept scope-floor | scope-floor-reclose | scope-floor-gap | scope-floor-key-cap | scope-floor-day-cap with
+     ungated==1 (scope-floor-shadow only when SUBJECT_NUDGE=shadow); a held row (scope-floor-nothing-ungated,
+     held==true) goes to the held branch below; scope-floor-inflight goes to the stale-inflight rule below;
+     anything else (kill-switch, operator-hold, conversation, clear, assignee, headless …) ⇒ return 0.
+  stale-inflight rule: a `scope-floor-inflight` row whose `what` is only time-bounded legs (`bg`, `agent`, `wave`,
+     freshness CC_BH_WAVE_WARM_S = 1800 s) is accepted once the row is older than 1800 + STALL_S (1 h): those legs
+     have lapsed by then and the floor, which re-evaluates only at a Stop, cannot see it. Rows whose `what` includes
+     `custody`, `landing` or `resident` stay suppressed: a dead lane's custody is custody-deathwatch's to report
+     (it wakes the originator, scripts/custody-deathwatch.sh:1-3).
+  # 2. damping, read BEFORE any send: key first, then back-off (crit/D4--incident-replay.md #8)
+  marker $PAGEDIR/<sid>.nudged: lines `N <epoch> <key> <armed01>`; refuse if this key has NUDGE_MAX sends, if the sid
+     has NUDGE_SID_DAY sends in 24 h, if the last send to the sid is < NUDGE_GAP_S ago, or if the key's last send is
+     younger than its back-off (NUDGE_ARMED_S when that send's reason was wake-path-armed). Marker dir unwritable ⇒
+     send nothing (fail closed). Sweep counter at NUDGE_PER_SWEEP ⇒ return.
+  # 3. send — no --no-wake, no CC_NOTIFY_WAKE=0, no CC_WAKE=off
+  out="$(sup_bounded "$SUP_NOTIFY_TIMEOUT_S" "$NOTIFY_BIN" "$sid" --from lead-supervisor \
+         --subject "keep driving the ungated scope" "$(nudge_text "$row" "$2")" 2>&1)"; rc=$?
+  parse ONLY the `^cc-notify: verdict=` line (cc-wake's own token comes first, cc-notify:1494; maps/wake-path.md §5.2):
+     verdict, enqueued, reason. Record the attempt when enqueued=1 WHATEVER rc (a 124 after enqueue is a delivered
+     line, bin/cc-notify:96-111); enqueued=0 ⇒ no marker, retried next sweep within the caps.
+  # 4. operator digest, once per key, at the FIRST of: (a) this key's NUDGE_MAX-th send; (b) a second recorded
+  #    send whose reason is neither `woken` nor `wake-path-armed` (cc-notify prints `reason=woken` only when the
+  #    waker returned 0, bin/cc-notify:1506-1513), i.e. the nudges are not reaching the session, e.g. cc-wake's
+  #    `refused-busy` (58 such rows for 666022fd, maps/wake-path.md §3); (c) the next attempt's earliest time
+  #    would put the telemetry age past GC_S - NUDGE_HORIZON_SLACK_S. digest_add "subject-idle-capped" + idl
+  #    subject_nudge_capped {why: cap|not-woken|horizon} (digest_flush posts it, :384-404).
+  idl subject_nudge {sid,key,attempt,notify_rc,verdict,enqueued,reason,kind,ids}
+}
```

**The ladder fits the GC horizon.** `gc_stale` drops a live owner's telemetry row once it is `GC_S` (21,600 s) stale
(`scripts/lead-supervisor.sh:146`, `:903-916`), and `assess()` never sees that session again. The first draft's 2 h then
4 h back-off put nudge 3 and the cap digest 6-6.5 h after the last telemetry whenever nudges 1-2 did not wake the
session, so the operator fallback was unreachable in exactly the case it exists for (maps/wake-path.md §2: "Any nudge
must fire inside roughly [30 min, 6 h] of telemetry staleness"). With 30 min then 1 h (1 h after `wake-path-armed`),
three sends land within about 2 h of the first STALL? (estimated from the constants), and rule (c) digests early if a slow sweep or the per-day cap
would push the next attempt past the horizon. A woken session re-exports telemetry on its turn, which restarts the
clock; that is the success path.

**Held branch** (crit/D2--incident-replay.md D1 fix 4): when the newest floor row is `scope-floor-nothing-ungated` with
`held:true` and the session is a STALL? candidate, send **one** re-confirm line per hold key ("you are idle on a hold
over <id> (<why>). A decision gates only the act it asks about; if the remaining work does not truly wait on it,
release the hold with `dod-persist.sh hold none "<why>"` and drive it; otherwise leave it") and add one digest cause
`held-idle`. So a self-declared hold is never silent to the operator. A **lapsing** hold (§3.2) cannot rely on a Stop
to notice its lapse, because the held session is idle: so when the newest floor row is a held row whose `held_until`
has passed, the supervisor treats it as an `ungated:1` row and runs the subject-nudge ladder above; the woken session's
next Stop reads `HELD_SRC=lapsed` and the floor fires again. If the lead re-holds, the new hold line is a new hold key
(its `until=` differs), so the re-confirm and the `held-idle` cause repeat each window instead of once.

**Text** (`nudge_text`, one line, because cc-notify collapses newlines; machine-authored, no operator authority, R:223):
"⏯ IDLE WITH UNGATED SCOPE (lead-supervisor, machine text addressed to THIS session; not an operator answer) — idle ~Nm.
Your last close went idle while your frozen scope still has in-scope work no open decision gates (<loop scope "<head>…"
| N DoD item(s)>; open decisions: <ids or none>). Run the next ungated step now (a loop scope: the next round as scoped).
If every remaining item truly waits on an open money, self-modification, permission, credential or G2 decision,
`~/.claude/hooks/dod-persist.sh hold <id> "<what it gates>"`; if the loop's stop condition holds or the operator ruled
it stopped, `~/.claude/hooks/dod-persist.sh done "<evidence>"`. Then close."

**Call site**: between `page "$sid" "STALL?" …` (`:1089`) and `[ "$had_page" = 1 ] && resolve_page …` (`:1090`). That
point is already past the registered-desk (`:1046`), permission-beacon (`:1067`) and operator-adopted (`:1077`)
exemptions and inside the [STALL_S, GC_S] window (`:139`, `:146`). ESCALATED is reachable only through the same branch
(`:744-752`), so one site suffices. `sweep()` (`:1356`) resets the per-sweep counter file before its loop.
**Marker lifetime**: `clear_page` (`:524`) and `clear_page_recovered` (`:583-609`) do not touch `.nudged`; `reap_clean`
(`:823`) deletes it, and a 7-day `-mtime` sweep in `gc_stale` prunes the rest. **Same parse fix** for `advise_subject`
(`:557`), whose 20:15:41Z row recorded cc-wake's `refused-busy` while cc-notify's verdict was `delivered`
(maps/wake-path.md §5.2). Usage-limited sessions: cc-wake refuses them (`refused-limited`, `bin/cc-wake:170-240`),
and a usage-limit death is a `StopFailure`, not a `Stop`, so the floor never runs on it (measured: `StopFailure` →
`stop-failure-marker.sh` in `~/.claude/settings.json`). The daemon picks the change up by its sha self-restart
(`:92-104`, `:1393`); no plist edit. It runs under `/bin/bash` 3.2 (`.claude/rules/agent-operating-lessons.md:47`).

### 3.6 C7 — `bin/cc-decide`, `bin/cc-memory-search`, `hooks/anti-deference-nudge.sh`

1. **`open --help`** (D3:92): `-h|--help) usage; return 0 ;;` in `cmd_open`'s parser (`:169-187`). The B13 lead asked
   for exactly this before filing and got "unknown arg --help" (TX:4249-4250).
2. **Header (`:13-19`)**, which `usage()` prints (`:93`):
   ```
   #   B  QUEUE-FOR-REVIEW — a judgment call with a status-quo course (usually the frozen scope), or external
   #      info the values don't settle: carries default_if_no_veto + veto_deadline; the default FIRES at the
   #      deadline, and the filer keeps that course meanwhile (async early-veto, never a sync approval).
   #   C  HARD-BLOCK (human-only) — C10 self-mod / C6 money-path / permission denial / credential / a G2
   #      escalation surface (auth, destructive migration, nav pattern, DB timeout), declared with
   #      --ceiling self-mod|money|permission|credential|g2 (research-kit programs: program): WAITS, has
   #      NO default. It is the filer's ⛔ and holds only the act it names; the filer keeps driving every
   #      in-scope item it does not gate. A pick among new options is class B with your pick as --default.
   ```
   The reserve is cc-decide's own (`bin/cc-decide:18-19`: C10, C6, permission denial) plus the credential and G2
   surfaces R already treats as operator-only (R:189 "credential, sudo, destructive migration"; G2's escalation surfaces,
   `CLAUDE.global.md:612`). The first draft also admitted "a pick
   among new options with no status quo"; that clause is dropped everywhere (R-13, R-15, G-05, G-06, the floor's block
   text, §3.8), because a lead can claim it for any judgment call and the ruling's goal (b) keeps class C to the reserve.
   Such a pick has a course: the filer's recommended option, filed as the class-B default.
   and the comment at `:103-104` becomes "A class-C packet is the ⛔ rung: it hands the operator a question and holds
   only the act it names; the session keeps driving every in-scope item it does not gate (ruling d610f8473106)". The
   vacuity note at `tests/cc-decide.bats:763-766` reasons from `usage()` containing "implement it", "REFUSED" and
   "unknown id"; those words sit outside the edited lines and are kept.
2b. **Required `--ceiling` on a session's class-C open** (goal (b)'s deterministic gate; maps/cc-decide.md §8). In
   `cmd_open` (`bin/cc-decide:163-245`): parse `--ceiling`; refuse any value outside
   `self-mod|money|permission|credential|g2|program` (closed set, the `--default-effect` precedent at `:202-214`);
   refuse `--ceiling` on class A/B; refuse `program` without `--project`. When the class is C, a session id is set
   (`CLAUDE_CODE_SESSION_ID` or `CLAUDE_SESSION_ID`, the hint gate's predicate) and no ceiling is given, refuse rc 2
   with stdout empty and print, last, the full class-B command (`--default "<the frozen-scope course>" --deadline <ISO>
   --default-effect no-change --project <repo> --conviction N --receipt R`) and the `--ceiling` set. When a ceiling other
   than `program` is given, run `scripts/gate-classify.sh` on `--what` (resolved beside the binary, pure text, no
   write) and, if it routes B, print the disagreement and the class-B command on stderr **without refusing**: the
   router misses genuine gates (`a247b7288149`, a money path, routes B; maps/cc-decide.md §5). The ceiling is stored as
   `.ceiling` (outside `mk_id`, like the other annotations, `:341-342`) and shown by `list --json`; an absent field is
   a legacy packet and folds to today's ⛔. Producers: sessions (the rules); `scripts/research-kit/lib/gate_sweep.py`,
   whose `file-packet --class C` runs in program sessions with a session id and so must pass `--ceiling program`
   (built at `:135-160`); `ship-land.sh` writes `shipland-esc-*` packets directly and never calls `open` (maps/cc-decide.md
   §7). Tests: the 61 existing `open --class C` call sites (maps/cc-decide.md §7) stay green where the suite unsets the
   session ids (`tests/cc-decide.bats:22`, `tests/operator-readout.bats`, `tests/wrap-ledger.bats:32`,
   `tests/wrap-ledger-memo.bats`); the two suites that open class C **without** unsetting them, `tests/cc-do.bats`
   (5 sites, `:183-436`) and `tests/research-kit-gate.bats` (1 site, `:875`), would be refused when run from an agent
   shell, so step 5 adds `unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID` to their `setup()` (measured with
   `grep -c` per suite, §9.3 M22). Kill switch: `CC_DECIDE_CEILING=0` or `~/.claude/state/decide-ceiling.off`.
   `program` is not an operator-only ceiling for a hold (§3.2): program sessions are exempt from the floor anyway.
3. **Stderr hints**, inserted after the existing-packet early return (`:313-328`) and before the options build, so a
   re-open never searches. Gated: class ≠ A, `CLAUDE_CODE_SESSION_ID` (or `CLAUDE_SESSION_ID`) set, `CC_DECIDE_HINTS ≠ 0`,
   no `~/.claude/state/decide-hints.off`, and not under bats (`BATS_TEST_FILENAME`, `BATS_TEST_TMPDIR` or
   `BATS_RUN_TMPDIR` set; the `bin/cc-notify:510` precedent) unless `CC_DECIDE_HINTS=1` forces it, which the hint tests
   do. The first draft claimed every bats suite unsets the session ids; that is false: nine suites call `cc-decide open`
   with no unset (autonomy-sweep, cc-digest, cc-do, cc-unattended-ask-guard, dispatch-assert, lr-reset-poller,
   research-kit-gate, research-program-briefs, ship-land; measured, §9.3 M22). Run from an agent shell, as Phase 2 runs
   cc-bats, each of their class B/C opens would have forked the search (up to 3 s) and written stderr; the bats predicate
   removes that (crit/D2--constraints-feasibility.md M4).
   Daemons carry no session id and pay nothing. stdout stays exactly the id and the exit code never changes
   (`gate_sweep.py:161-163`, `lr-reset-poller.sh:1179-1196`). Order, most useful **last**, because filers pipe
   `2>&1 | tail -3` (TX:4254):
   - class C only, and only when the open was not refused (a ceiling was given): `cc-decide: class C waits with no
     default and is reserved for self-modification, a money path, a permission denial, a credential or a G2 surface;
     a judgment call with a status-quo course is class B (--default "<that course>" --deadline <ISO> --default-effect
     no-change --project <repo>).`, followed by gate-classify's disagreement when it routes B (item 2b).
   - the ruling line: `cc-decide: <PRIOR ANSWER (default fired)|similar answered packet>: <id> · <status> <date> ·
     "<what_plain[:120]>" · <default fired: … | evidence[:120]> — act on it and file class A citing it; re-ask only as
     class B with it as --default.` "PRIOR ANSWER" when top-1/top-2 ≥ 1.5 (maps/ruling-discovery.md §4.2: ranks
     `eb3dbe1e5e94` first for e869's text at 2.88 and `a247b7288149` first for 290215743799's at 1.62; the 1.5 cut is
     fitted on 7 cases, estimated precision ≈0.8 for "related", hence never a refusal, §4.3). The wording avoids
     "already ruled" because a fired default can legitimately be reopened (crit/D4--incident-replay.md #6).
   - Engine: `python3 -I "${CC_MEMORY_SEARCH_BIN:-$(dirname "$(self_path)")/cc-memory-search}" --decisions --exclude "$id"
     --top 3 --json -- "$what"`, run as `python3 -I <path>` so the exec-form lint sees an interpreter, not a beside-script
     path under a bounder (crit/D4--constraints-feasibility.md D-10), bounded by `timeout`/`gtimeout`
     (`CC_DECIDE_HINT_TIMEOUT_S`, 3 s; 0.73 s measured end to end, maps/ruling-discovery.md §4.2); no bounder, an error
     or a timeout prints nothing (fail open). One IDL row `ruling-hint {top1,ratio}` via the existing `log_idl`.
4. **`bin/cc-memory-search --decisions [--exclude ID]`**: a corpus mode that replaces the default scope (as `--lessons`
   does, `:644`): answered packets only (`actioned|vetoed|expired-actioned`) from `${CC_DECISIONS_DIR:-…}`, text =
   `what_plain`, object options' outcomes (string options skipped, `ship-land.sh:686-690`), `recommendation`,
   `default_if_no_veto`, `evidence`; never globs `~/.claude/projects` (the 7.4 s cost, maps/ruling-discovery.md §2);
   scored by the existing `search()` (`:488`); `--json` adds the top-1/top-2 ratio. Usable directly:
   `cc-memory-search --decisions stop the loop`. The Phase-2 class-A grant record (§8.4) is an actioned packet, so a
   Codex question surfaces the grant through this same path with no separate grants file.
5. **`hooks/anti-deference-nudge.sh:131`**: prefix `CC_DECIDE_HINTS=0` on `open_packet_B`'s call — a 5 s Stop hook must
   never pay the search. Nothing else in that hook changes: no phrase is added to `TELLS` (`:170`), because "need your
   call" is the ledger's own ⛔ readout and is pinned silent (`tests/anti-deference-nudge.bats:706-717`;
   maps/legit-stops.md §6 C10).

### 3.7 C9 — rule text

The blocks below are byte-exact. Each `old` occurs exactly once in its file; a read-only script applied them in memory
and measured them with the repo's own `hooks/lib/instruction_budget.py` (§5.3). Design rules for the text: no literal
`Scope (frozen):` loop line (an assistant quote would be scraped by PreCompact); the slim text carries the G2
carve-out itself (crit/D1-rule-text--loop-false-block.md §3); every always-loaded addition is paid by a cut whose
content survives in R, S, G or machine text (named per cut).

#### 3.7.1 R — `CLAUDE.rules.slim.10-session-close.md`

**R-01 (R:4) cut**: the Stop-hook pointer folds into R:225 (R-18).
```old:R:01
 Before writing or debugging a Stop hook, read the reference `~/Development/claude-infrastructure/CLAUDE.global.md` § Session Close Protocol for which hook output fields reach the model and which extend the turn.
```
```new:R:01
```

**R-02 (R:14-18) cut** of three restatements: the 🚀 parenthetical (R:96 says it), the background-verifier sentence
(R:106: "a marker only a background verifier advances … close on your own state"), the 👤 sentence (R:97, R:193).
G keeps all three (crit/D3-schema-first--constraints-feasibility.md §3, verified).
```old:R:02
(`wrap-ledger.sh` computes `🚀` instead of `✅` for you when the live layer has breached its
  converge budget). Any one unknown ⇒ not ✅; say which. Where a background verifier owns the full-suite claim (claude-infrastructure v2), *your
  diff green + content-verified land* is the standard — waiting on a trunk-wide stamp you do not
  control is not diligence, it is a hang. The "no operator step left unrun" clause is no longer
  prose discipline: file each one (below) and `wrap-ledger.sh` computes `👤` instead of `✅` for you.
```
```new:R:02
(else `🚀`). Any one unknown ⇒ not ✅; say which.
```

**R-03 (R:19, R:20) trims**: the lib path and the ship-floor bound are printed by the hooks themselves; G:547 keeps the bound.
```old:R:03
 (per `hooks/lib/session-writes.sh`)
```
```new:R:03
```
```old:R:04
, once per HEAD sha and at most `CC_SHIP_FLOOR_MAX`=2 per session.
```
```new:R:04
.
```

**R-05 (R:24) compaction**: the resident 🔧 READOUT prints the shutdown procedure whenever it applies
(`scripts/wrap-ledger.sh:2659-2661`); G:581 keeps the full text.
```old:R:05
Resident teammates: `~/.claude/scripts/wrap-ledger.sh` reports `RESIDENT_MINE`, the members of this session's team whose process is still running, as a 🔧, including their dirty files in a shared cwd; those files are yours to commit, since only the lead can. A teammate ends only when its lead ends it: send each a `shutdown_request` and escalate to `TaskStop` after about 60 s; the rung clears when the process is gone, not when the pane closes. The check kills nothing; to keep a member working, say so in the close as a stated park. Kill switch `WRAP_RESIDENT=off`.
```
```new:R:05
Resident teammates: `~/.claude/scripts/wrap-ledger.sh` reports this session's still-running team members as a 🔧 (`RESIDENT_MINE`), and its readout says how to end them; their dirty files in a shared cwd are yours to commit. To keep a member working, say so in the close as a stated park. Kill switch `WRAP_RESIDENT=off`.
```

**R-06 (R:26) goal (e)**: the loop scope, how it is recorded, its end marker, and who may write the store. The
parenthetical "(`dod-persist.sh` captures it)" was false in practice (0 PreCompact blocks in the store; a lead's own
restated loop line is never captured, §3.2 *Capture recall*), so it becomes the command that does record it.
```old:R:06
 in the plan or else inline (`dod-persist.sh` captures it). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask.
```
```new:R:06
 in the plan or else inline; `~/.claude/hooks/dod-persist.sh set "<that line>"` records it, at once for a loop scope (its line opens `loop until <condition>`). Close-time completeness is a diff against that line, not a fresh judgment. If the scope cannot be reconstructed, stop and ask. A loop scope is open until `~/.claude/hooks/dod-persist.sh done "<evidence>"`; never a `- [ ]` box. Only the scope's own session runs `dod-persist.sh set|hold|done`, never a subagent.
```

**R-07 (R:38) goal (a)**: the core license, scoped to what the decision gates.
```old:R:07
| Stop and ask, overriding auto-continue; commit in-progress work first. |
```
```new:R:07
| Commit in-progress work, file it, and keep driving every in-scope item it does not gate, never the gated act; a question that would change the frozen scope gates none of it. Stop only when it gates all that remains. |
```

**R-08 (R:39) cut**: R:72 states PASS/FAIL in full.
```old:R:08
| Follow-On Gate: PASS → do it now and append `Scope (grown): +<item>` where the DoD lives; FAIL → drop it, or file it only if it passes the FILED test (§ Three dispositions). Security
```
```new:R:08
| Follow-On Gate (below). Security
```

**R-09 (R:68) goals (c)(a)**: look for a ruling first; the re-ask valve; handing over pauses nothing ungated; the
refusal mechanics cut (the tools print them on refusal: `bin/cc-decide:225-245`, `bin/cc-backlog:2211`, `:2242`,
`:2505`; wrap-ledger's 🔧 READOUT prints the unconvicted-ask rule, `scripts/wrap-ledger.sh:2669`; G:657 keeps the long
form; no test greps the cut words, §9.3 M13). This revision cuts the refusal sentence the first draft kept, to pay for
the R-17 and R-23 text the completeness critic showed had no loaded copy.
```old:R:09
otherwise hand it to the operator with the number, the research receipt and the measured options in operator terms. Above 90% there is nothing to ask: implement. `cc-backlog add --why-not-now "needs-human: …"` and `cc-decide open --class C` refuse without `--conviction N --receipt PATH|"<cmd> => <output>"` (class C also needs two `--option`s) and refuse N > 90; `wrap-ledger.sh` counts an unconvicted ask of yours as your own 🔧 (`UNCONVICTED_MINE`), not 👤 or ⛔.
```
```new:R:09
otherwise first look for a ruling (`cc-memory-search <terms>`, its `--decisions` mode, the plan's decision log): an answered packet on the question (a fired class-B default too), a purchase for the purpose, a standing grant or the operator's words this session is the answer; act on it and file class A citing it. Re-ask only on new evidence or when the operator reopened it, as class B with that course as `--default`. Else hand it to the operator with the number, the research receipt and the measured options in operator terms; that pauses nothing it does not gate. Above 90% there is nothing to ask: implement.
```

**R-10 (R:92)**: the ⛔ definition names its source; the prescribed readout phrase is kept byte-for-byte.
```old:R:10
- ⛔ Blocked: a decision or information is needed.
```
```new:R:10
- ⛔ Blocked: an open class-C decision or information is needed.
```

**R-11 (R:103) goals (a)(e)**: the second core license, now conditional, with the G2 carve-out in the slim text. The
`hold` verb is deliberately not in the always-loaded text: it appears in the floor's block reason and in G-04, each time
next to its criterion, so the off-switch is never advertised without the rule (crit/D2--incident-replay.md D1 fix 1).
```old:R:11
Only ⛔, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work.
```
```new:R:11
Only ⛔ when every remaining in-scope item waits on an open decision, and 📦 in a repo whose own `CLAUDE.md` says landing spends money, may end a turn holding work. A decision gates the act it asks about and work built on its answer, never the rest of the frozen scope (a loop's next round included); the gated act itself waits even where the scope names it.
```

**R-12 (R:146) cut**: the example repeats R:144's.
```old:R:12
S1 carries one rung and states a conclusion, not a category (`12 runnable now, 195 need your call`, not `205 manual steps`).
```
```new:R:12
S1 carries one rung and states a conclusion, not a category.
```

**R-13 (R:160) goal (b)**: file by class; class C keeps exactly cc-decide's reserve plus the credential and G2
surfaces, each declared with `--ceiling` (§3.6 item 2b); a pick among new options is class B with the pick as the
default (the first draft's "no-status-quo pick" clause is dropped, §3.6).
```old:R:13
File a decision you are holding the moment you have it; filing is what makes it the `⛔` rung: `cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. A class-B packet also carries `--conviction N --receipt R`; both follow the F2 number rule (Follow-On Gate). `wrap-ledger.sh` computes `⛔` from this session's open class-C packets; an unfiled decision is invisible to it, and `✅ SAFE TO CLOSE` would render over the open question.
```
```new:R:13
File a decision you are holding the moment you have it, by class (`cc-decide help`). Class C waits with no default and is the `⛔` rung, only for an act only the operator may authorize, named by its ceiling: `cc-decide open --class C --ceiling self-mod|money|permission|credential|g2 --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. Any other judgment call has a course (the frozen scope, or your pick), so it is class B and you keep that course meanwhile: `cc-decide open --class B --what … --default "<that course>" --deadline <ISO> --default-effect no-change --project <repo> --conviction N --receipt R`. Both follow the F2 number rule. An unfiled decision is invisible to `wrap-ledger.sh`.
```

**R-14 (R:184) cut**: R:186(c) and R:193 give the same routing; G's FILED row keeps the sentence.
```old:R:14
Sudo, physical and GUI-only steps are not decisions; they go through `cc-backlog needs "<step>" --class needs-human`, which carries no conviction.
```
```new:R:14
Sudo, physical and GUI-only steps are not decisions.
```

**R-15 (R:189)**: "a real value fork" read as covering "stop the loop?" (maps/rules-text.md §2a).
```old:R:15
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, a real value fork). It is S1's `⛔` rung, stated as the decision you need.
```
```new:R:15
- BLOCKED: a genuine operator-only gate (credential, sudo, destructive migration, money, self-modification). It is S1's `⛔` rung, stated as the decision you need; it holds only the act it gates.
```

**R-16 (R:207) cut**: S's Manual-Command Delivery says the same ("state the resolved target and one line on what it
cannot undo above the marker … Carry that consent in the handed command: `--confirm <target>`").
```old:R:16
 Consent to a gated step rides in the handed line (`--confirm <target>`), and the chat line above the marker says what it changes and cannot undo.
```
```new:R:16
```

**R-17 (R:215, R:217) goal (a)**: arm on an unheld ⛔ only when the ledger says work is ungated
(crit/D2-hook-enforcement--loop-false-block.md §2.5); a wait is never a step (crit/D1-rule-text--loop-false-block.md
§2); clear at the context boundary, because an armed sentinel mutes boundary-handoff on every axis
(`hooks/boundary-handoff.sh:694`; crit/D1-rule-text--constraints-feasibility.md D-2). The cap arithmetic moves out; G
keeps it (G:1128-1140). The anti-idle sentence "Within a turn, keep working rather than stopping on 🔧." stays: its only
copy in R, S or G is R:217 (measured `grep -n 'Within a turn'`), and the first draft deleted it without naming the cut.
```old:R:17
### Auto-continue actuation (🔧 only)

On 🔧, and only on 🔧, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires. Nothing bounds an agent-armed chain (each `set` resets the counter; `CLAUDE_CONTINUE_MAX`, default 8, bounds only the mechanical arm as `CC_MECH_MAX × CLAUDE_CONTINUE_MAX`, and `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` catches only a text-only wedge), so the stop conditions are the kill-switch, the frozen DoD, and your judgment; the hook does not judge scope. Within a turn, keep working rather than stopping on 🔧.
```
```new:R:17
### Auto-continue actuation

On 🔧, and on a ⛔ whose readout says `Not gated by it`, arm the continuation: `~/.claude/hooks/session-continue.sh set "<the one next step>"`; a Stop hook then feeds that step back as your next turn. A wait (on a person, a lane, a workflow or a packet) is never a step: wait with `cc-await-ping` under `run_in_background`. Clear it with `~/.claude/hooks/session-continue.sh clear` as soon as the state becomes ✅ / 📦 / a held ⛔ / 📤, at the context boundary (§ Context Stewardship), on a read-only turn, or when the kill-switch fires. Nothing but the kill-switch, the frozen DoD and your judgment bounds an armed chain (each `set` resets the counter). Within a turn, keep working rather than stopping on 🔧.
```

**R-18 (R:225)**: takes over R:4's Stop-hook pointer.
```old:R:18
read them before changing or disputing one of these rules.
```
```new:R:18
read them before changing or disputing one of these rules, or writing a Stop hook.
```

**R-19 (new paragraph before "### Asserting done") goal (d)**: the grant beside F2, in the format of the one other
standing ruling R records with its packet id (R:74). The grant wording is additive and routes no slot, so it does not
collide with "uncertified means unrouted" (`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`, `:227-228`), and it
keeps the personal-data asks (`f2e2c22bb83e`, `e3876aac762d`, `bb16a9bc1350`; maps/legit-stops.md §6 C9).
```old:R:19
### Asserting done
```
```new:R:19
Standing operator grants (record and the operator's words: `~/.claude/CLAUDE.full.md`, same section); an act inside one needs no ask and no packet:
- Cross-vendor review (operator, 2026-10-24, `d610f8473106`; plan bought in `a247b7288149`): in any repo, unasked, add non-Claude reviewers beside your Claude review via `~/.claude/scripts/xvendor-review.sh` (Codex plan, `codex exec -s read-only` on a `git archive` export of committed code, reads confined to that export or no run, stops at 80% of the weekly meter, never the paid API). Still ask for personal or customer data or a repo-listed escalation surface. A permission refusal is the operator's one pending allow rule: continue Claude-only, never re-ask. Routes no `model-config.yaml` slot.

### Asserting done
```

**R-20..R-23 additional cuts** (mechanism detail the named tools print, each kept in G: measured `grep -c` in G of
`close-shape.sh` 1, `origin-identity.sh` 1, `desk-strand-replay` 1; no test pins any of them, §9.3 M13). R-23 is now
a compaction, not a cut: the measured trap "judge capacity from the strand nowcast, not the `/accounts` weekly
percentage, which understates spend" has no loaded copy but R:184 (G:1041 keeps it, and G is loaded by no session), so
it stays, shortened; only the script's path goes, since `desk-strand-replay.py` is named.
```old:R:20
 (`completion-assert.sh` arm D6; template in `hooks/lib/close-shape.sh`, shared with `/wrap`): an origin session (no fired-peer stamp; `hooks/lib/origin-identity.sh`) closing
```
```new:R:20
 (`completion-assert.sh` arm D6): an origin session (no fired-peer stamp) closing
```
```old:R:21
 (`anti-deference-nudge.sh` blocks the common phrasings)
```
```new:R:21
```
```old:R:22
 (when a 🚀 needs reading: `~/.claude/commands/wrap.md`)
```
```new:R:22
```
```old:R:23
Unused weekly quota does not roll over, so idle accounts are capacity; judge capacity from the strand nowcast (`~/.claude/scripts/desk-strand-replay.py`), not the `/accounts` weekly percentage, which understates spend.
```
```new:R:23
Unused weekly quota does not roll over, so idle accounts are capacity; judge it from the strand nowcast (`desk-strand-replay.py`), never the `/accounts` percentage, which understates spend.
```

#### 3.7.2 S — `CLAUDE.global.slim.md`

**S-01 (S:203)**: a decision is filed by class, not "asked as ⛔".
```old:S:01
- If what remains is a decision, there is no script; ask it as the `⛔` rung.
```
```new:S:01
- If what remains is a decision, there is no script; file it by class (§ The close message).
```

**S-02..S-04 cuts** (budget payment outside the close protocol, so the commit body must name them; each removes a
rationale or citation that G keeps — D1 §3.2 verified each in G with `grep -c`, and crit/D1-rule-text--constraints-feasibility.md
D-4 objected only to two other S cuts, which this design does not take): S:116's version note, S:132's launcher flags,
S:3's source path (R:225 names the same file).
```old:S:02
Keep it: since 2.1.224 removed the per-session spawn cap, depth is the only runaway bound.
```
```new:S:02
Keep it: depth is the only runaway bound.
```
```old:S:03
 (SSOT `~/.claude/model-config.yaml` `opus_latest`; the `claude()` launcher passes `--model claude-opus-5-5 --effort high`)
```
```new:S:03
 (SSOT `~/.claude/model-config.yaml` `opus_latest`)
```
```old:S:04
 (source: ~/Development/claude-infrastructure/CLAUDE.global.md)
```
```new:S:04
```

#### 3.7.3 G — `CLAUDE.global.md` twins (not budgeted; the only text under the `global full` variant, `install.sh:1117`)

**G-01 (G:592-595)**: the loop scope, its capture, its end marker, no box, owner-only writes.
```old:G:01
**Freeze the DoD at intake.** The first time a task will write tracked files, restate the user's
ask as one line — **`Scope (frozen): …`** (in the plan, else inline). Close-time completeness is
then a *diff against that contract*, never a fresh re-judgment — the brake on scope-metastasis.
Unreconstructable scope is itself a STOP-ASK, never a guess.
```
```new:G:01
**Freeze the DoD at intake.** The first time a task will write tracked files, restate the user's
ask as one line — **`Scope (frozen): …`** (in the plan, else inline). Close-time completeness is
then a *diff against that contract*, never a fresh re-judgment — the brake on scope-metastasis.
Unreconstructable scope is itself a STOP-ASK, never a guess.
**A loop scope** — a frozen line that opens `loop until <condition>` (also `repeat|iterate until`,
`keep going|looping|running until`) — is open work until `~/.claude/hooks/dod-persist.sh done
"<evidence>"` records that the condition holds or the operator stopped it (an actioned or vetoed
decision packet whose id the loop line names also stops it). The ledger counts only `- [ ]` boxes,
so it reads a loop from this session's own recorded contract instead (`LOOP_OPEN`). Record a loop
scope at once with `~/.claude/hooks/dod-persist.sh set "<that line>"`; `session-continue.sh` also
captures one from the human prompt that stated it at the first idle Stop, but never a line you
restate yourself. (B13 lead `666022fd`, 2026-10-24: its `loop until dry` scope reached the store only
by a manual `set` two hours after an 11-hour idle, because dod-persist captured only at PreCompact and
`set`.) Never add
a box for a loop: the store is append-only, the box could never be checked off, and every later session
in the checkout would inherit a permanent 🔧. Only the session that owns a scope runs `dod-persist.sh
set|hold|done`: a subagent carries its parent's session id and would rewrite the lead's contract.
```

**G-02 (G:605)**: the R-07 twin.
```old:G:02
| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** | **STOP-ASK** (overrides auto-continue); commit in-progress work first. |
```
```new:G:02
| Needs a **decision** (destructive migration / auth / nav pattern / timeout) or **info** | Commit in-progress work, **file it** (§ The close message, *Corollary*) and **keep driving every in-scope item it does not gate**, never the gated act; a question that would change the frozen scope gates none of it. STOP-ASK only when it gates ALL remaining in-scope work (*Only ⛔ … may end a turn holding work*). |
```

**G-03 (G:657, inside F2)**: the R-09 twin with the B13 precedent and the re-ask valve.
```old:G:03
only still-below-90 after exhaustive research is the operator's, and it is handed over WITH the number, the receipt of that research, and the measured options in operator terms.
```
```new:G:03
only still-below-90 after exhaustive research is the operator's — **but first look for a ruling** (`cc-memory-search <terms>` for memory, `cc-memory-search --decisions <terms>` for answered packets including the standing-grant record, and the plan's decision log; `cc-decide open` also prints the closest answered packet on stderr): an answered packet on the same question (a fired class-B default included: `expired-actioned` is a ruling by silence), a purchase made for the purpose, a standing grant (§ Standing operator grants) or the operator's own words this session **is the answer: act on it and file class A citing it**. Re-ask only when material new evidence has arrived since that ruling or the operator reopened it this session, and then as class B with the ruling's course as `--default`. With no ruling it is handed over WITH the number, the receipt of that research, and the measured options in operator terms, and **handing over pauses nothing the question does not gate**. (B13, 2026-10-24: `eb3dbe1e5e94`'s default "keep looping until dry" had fired on 2026-10-15 and the lead's own plan recorded it; after the operator asked "is this forever?" a re-ask was legitimate, but it was filed as a hard block, `e869fac7eb34`. `a247b7288149` had bought the Codex plan for cross-vendor review, yet `290215743799` asked again because the purchase was worded TrueMemory-only.)
```

**G-04 (G:766-767)**: the R-11 twin, with the carve-out, the hold, the incident, the legit-stop evidence and the wake path.
```old:G:04
**Only ⛔, and 📦 in a repo whose OWN `CLAUDE.md` says landing spends money, may end a turn holding
work.** Everything else the agent drives:
```
```new:G:04
**Only ⛔ when EVERY remaining in-scope item waits on an open decision, and 📦 in a repo whose OWN
`CLAUDE.md` says landing spends money, may end a turn holding work.** A decision gates only the act it
asks about and work that builds on one of its answers; what the frozen scope already directs (a loop
scope's next round included) is not gated — the frozen scope is the course until the operator changes
it. The gated act itself still waits, even where the scope names it: "keep working" never means
building the destructive migration, the auth change or the deploy the packet asks about (G2 binds). A
⛔ with ungated work left is driven like a 🔧: the ledger's ⛔ readout then says `Not gated by it: …`,
its `→ Next` says `continue`, and `session-continue.sh`'s scope floor blocks an idle close over it (§
Stop-hook arms). When every remaining item truly waits on an open class-C decision that is a genuine
operator-only gate, record it with `~/.claude/hooks/dod-persist.sh hold <id> "<what it gates and why>"`:
the ⛔ readout then shows that hold to the operator on every close, `hold none "<why>"` releases it, and it
lapses on its own when the packet is answered. The hold refuses a packet that declares no
`--ceiling` and that `gate-classify.sh` routes B, and a hold backed by only one of the two lapses
after 6 h, so the floor and the supervisor ask again each window. *(Why, 2026-10-24, ruling `d610f8473106`: the B13 lead `666022fd` filed two
judgment calls as class C, wrote "Nothing more runs until you answer", and idled 11 h with its frozen
`loop until dry` scope ungated; round 27 depended on neither answer, and the same lead ran it under an
open class-C packet once told to. Every Stop hook accepted the idle, because this sentence let ⛔ end a
turn unconditionally. Legit stops are untouched: in 7 of 11 transcript-checked ⛔ idles the lead had
already finished or handed off all ungated work, `docs/research/lead-keeps-working-2026-10-24/maps/legit-stops.md` §4.)*
**Keep a wake path while a decision you filed is open and work waits on its answer:** the
`cc-await-ping` recipe under `run_in_background` (unless a `/goal` is live), never a detached
`cc-await-ping … &`, which reads as armed and wakes nobody; double `--timeout` after a wake that finds
nothing new; at each wake re-read your open packets and the frozen scope before closing again. A
recycle or hand-off names your open decision ids in the brief (`/handoff` prints the command that lists
them): a successor's ledger counts only its own session's packets (`wrap-ledger.sh:1529`). Everything else the agent drives:
```

**G-05 (G:1000-1002)**: the Corollary rewritten by class (from D1 G-5, with the C list matching R-13).
```old:G:05
**Corollary — a decision you are holding IS the rung, and filing it is what makes it one.** Open it
the moment you have it (`cc-decide open --class C --what <plain English, no codenames> --conviction N --receipt R --option "label::outcome" --option "label::outcome"` — and a class-B packet, the unattended ask whose default fires at its deadline, carries the same `--conviction N --receipt R` (extended 2026-09-08 by packet aa19d7b7a693: 19 of 19 class-B packets in the prior 30 days carried neither, 11 defaults fired unruled) — the F2 number rule: a class-C open without the number, the receipt and two measured options is refused, and one filed without them is your own 🔧, not ⛔);
`wrap-ledger.sh` then computes `⛔` from your own session's open class-C packets and it outranks
everything.
```
```new:G:05
**Corollary — a decision you are holding must be FILED, and its CLASS decides whether it is the rung.**
First look for a ruling (F2). Otherwise open it the moment you have it, by class (`cc-decide help`;
`bin/cc-decide:13-19`):
- **Class C** — waits, has no default, and is the only class `wrap-ledger.sh` counts as `⛔`: an act only the
  operator may authorize (self-modification, a money path, a permission denial, a credential, a G2 escalation
  surface: auth/session, destructive migration, navigation pattern, DB timeout), declared with its ceiling:
  `cc-decide open --class C --ceiling self-mod|money|permission|credential|g2 --what <plain English, no codenames>
  --conviction N --receipt R --option "label::outcome" --option "label::outcome"`. A session's class-C open without
  a ceiling is refused, and `gate-classify.sh`'s disagreement is printed when it routes the text B.
- **Class B** — every other judgment call, because it has a course to keep (a value fork, a stop rule, a method or
  scope question; a pick among new options takes your pick as the course): `cc-decide open --class B --what …
  --default "<the status-quo course, usually the frozen scope, or your pick>" --deadline <ISO> --default-effect
  no-change --project <repo> --conviction N --receipt R`. You keep
  that course meanwhile. The default fires at the deadline (`autonomy-sweep.sh` → `cc-decide expire-sweep`);
  `--default-effect no-change --project` keep a fired default from being filed as work in the wrong project
  (`df779857c4ff`, 2026-10-15).

Both carry `--conviction N --receipt R` (extended 2026-09-08 by packet aa19d7b7a693: 19 of 19 class-B packets in the
prior 30 days carried neither, 11 defaults fired unruled) — the F2 number rule: an open without the number and the
receipt (and, for class C, two measured options) is refused, and one filed without them is your own 🔧, not ⛔.
`wrap-ledger.sh` computes `⛔` from your own session's open class-C packets and it outranks everything, but under
*Only ⛔ … may end a turn holding work* a `⛔` ends a turn only when every remaining in-scope item waits on it.
*(Why the class matters: from 2026-08-07, the day class C became the only ⛔ sensor (`b08601974`), this corollary
said `--class C` for every held decision; class C then outgrew class B 522 to 166, and a 58-row audit found about
half of class-C packets were judgment calls, 36% with a stated status quo — class B by `cc-decide`'s own definition
(`docs/research/lead-keeps-working-2026-10-24/maps/legit-stops.md` §2.2). Both B13 packets were of that kind.)*
```

**G-06 (G:1042) BLOCKED row**: head and the "ordinary mid-work ⛔" phrase.
```old:G:06
| **BLOCKED** | a genuine operator-only gate — credential · sudo · destructive migration · a real value fork | it IS S1's rung (`⛔`), stated as the one decision you need.
```
```new:G:06
| **BLOCKED** | an open **class-C** decision — credential · sudo · destructive migration · money · self-modification (a value fork or a pick among new options has a course to keep, so it is class B and blocks nothing) | it IS S1's rung (`⛔`), stated as the one decision you need, and it holds only the act it gates.
```
```old:G:07
"the one decision you need" describes the ordinary mid-work `⛔`, not the exhaustion close
```
```new:G:07
"the one decision you need" describes a mid-work `⛔` whose decision gates everything left, not the exhaustion close
```

**G-08 (G:1125-1128)**: the R-17 twin.
```old:G:08
**Auto-continue actuation (🔧 only).** On the 🔧 state — and ONLY 🔧 — arm the continuation hook so a
turn-close re-prompts you instead of stopping with work left: `~/.claude/hooks/session-continue.sh set
"<the ONE next step>"`. **Clear it** (`~/.claude/hooks/session-continue.sh clear`) the instant the state
becomes ✅ / 📦 / ⛔ / 📤, on a read-only turn, or when the kill-switch fires — those MUST stop.
```
```new:G:08
**Auto-continue actuation.** On the 🔧 state — and on a ⛔ whose readout says `Not gated by it` — arm the
continuation hook so a turn-close re-prompts you instead of stopping with work left:
`~/.claude/hooks/session-continue.sh set "<the ONE next step>"`. A WAIT (on a person, a lane, a workflow,
a packet) is never a step: wait with `cc-await-ping` under `run_in_background`, or the armed path
re-prompts a session that has nothing to do. **Clear it** (`~/.claude/hooks/session-continue.sh clear`)
the instant the state becomes ✅ / 📦 / a held or all-gated ⛔ / 📤, at the context boundary (an armed
sentinel makes boundary-handoff abstain on every axis, `hooks/boundary-handoff.sh:694`), on a read-only
turn, or when the kill-switch fires — those MUST stop. The unarmed idle over ungated scope is the scope
floor's job, not a reason to arm (§ Stop-hook arms).
```

**G-09 (G:1172 tail)**: the S-01 twin.
```old:G:09
If the residue is a **decision**, there is no script to write; ask it as the `⛔` rung.
```
```new:G:09
If the residue is a **decision**, there is no script to write; file it by class (§ Session Close Protocol, *Corollary*) — class C is the `⛔` rung.
```

**G-10 (G:546-549, Stop-hook arms)**: the scope floor's paragraph after the ship floor's.
```old:G:10
  never a nudge over a sibling's commits), assignee/terminating/kill-switch exempt.
  **(2) CUSTODY**
```
```new:G:10
  never a nudge over a sibling's commits), assignee/terminating/kill-switch exempt.
  **(1b) The SCOPE FLOOR** (`session-continue.sh`, ruling `d610f8473106`): idling on a ⛔ (or on the loop
  🔧) while the ledger's `SCOPE_UNGATED` says this session's own recorded loop scope or own boxes are not
  gated by a recorded hold, with nothing in flight (custody, land, teammate, workflow wave, non-watcher
  background task or background agent), blocks with the next ungated step. It never reads close prose or
  packet class. Bounds, per session id: never on a turn its own block opened, directly or through other
  hooks' feedback turns; ≥10 min between fires; ≤3 fires per (kind, open ids, loop head) per 6 h; ≤6 per
  session per 24 h; unwritable state ⇒ no block. It abstains on kill-switch and operator-hold phrases, a
  read-only answer to the operator, assignees, headless or pane-less runs, teardown, research programs, a
  live `/goal`, and all five of boundary-handoff's context axes. Discharges are state changes only: the work;
  `dod-persist.sh hold <id> "<why>"` (only over a declared or routed operator-only gate); `dod-persist.sh
  done "<evidence>"`. After the last idle Stop, lead-supervisor's `nudge_subject` wakes the session itself
  through `cc-notify` (≤3 per decision state, 30 min then 1 h apart, inside the 6 h telemetry horizon, then
  an operator digest, sooner if the nudges do not wake it).
  **(2) CUSTODY**
```

**G-11 (after G:698-699, the end of the research-program exemption)**: the standing-grants record.
```old:G:11
research scope only — G1-G4, the ship policy and the ledger's dirty, unlanded and custody checks still
bind inside a program.
```
```new:G:11
research scope only — G1-G4, the ship policy and the ledger's dirty, unlanded and custody checks still
bind inside a program.

**Standing operator grants.** A standing grant is an operator ruling that covers a class of acts in every
repo. An act inside its envelope needs no ask and no decision packet; an act outside it is an ordinary
decision (F2). Each entry carries the operator's words, the envelope and how each limit is checked. The slim
rules carry the operative line (§ Follow-On Gate); this section is the record, and an answered class-A packet in
the decision store carries it for `cc-memory-search --decisions`. Adding, widening or revoking a grant is the
operator's: a rule edit is self-modification, class C.

- **Cross-vendor review** (operator, 2026-10-24, ruling `d610f8473106`; builds on the 2026-10-11 ChatGPT Pro
  purchase, packet `a247b7288149`, "Upgraded to 100. Continue."). The operator, 2026-10-24T18:11:47Z: *"I thought
  you had autonomous zero human in the loop proactiveness and permissions to do this with accounts; didn't we do
  this for our truememory review hence getting the $100 codex plan just for these adversarial reviews from agents
  that are not our own claude model class?"*
  - **Grant:** in any repo, on your own initiative, ADD non-Claude reviewers or judges beside the Claude review
    through the ChatGPT Codex plan's CLI. The Claude side still verifies what they find.
  - **Envelope, enforced by `~/.claude/scripts/xvendor-review.sh`:** a `git archive` export of committed code
    unpacked into a fresh temp dir — never the live home, the working tree, or a path the repo lists in
    `.claude/xvendor-review.exclude`; `codex exec -s read-only`, never widened
    (`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:248-249`); no new call at 80% or more of the plan's weekly meter
    (`used_percent` of the 10080-minute window in the newest `~/.codex/sessions/**/rollout-*.jsonl`, a file read;
    `:229-232`); `OPENAI_API_KEY` stripped, so the pay-per-token API is never reached. A read-only sandbox confines
    writes, not reads, so the wrapper also confines reads: the reviewer runs with `HOME` and `CODEX_HOME` set to a
    fresh temp dir holding only a copy of the Codex login, and with its readable roots limited to the export and
    that dir; a canary file under the real `$HOME` must be unreadable before each run, or the wrapper refuses.
    Without that, the reviewing model, or prompt-injection text inside the reviewed code, could read and send
    anything readable under `$HOME` (`~/.ssh`, `~/.claude`, other repos) — the exfiltration the classifier refused.
  - **Still ask first:** an export that would carry personal messages, mail, customer or guest data, or anything a
    repo's own `CLAUDE.md` lists as an escalation surface (for example a tenant name). Personal-data egress stayed
    an operator call (`f2e2c22bb83e`, `e3876aac762d`, `bb16a9bc1350`).
  - **Permission prerequisite:** the auto-mode classifier refused the Codex call as "[Data Exfiltration]" six
    minutes after these words (B13 transcript, 18:16:33Z and 18:17:21Z). The allow rule (or `autoMode.environment`
    line) for `xvendor-review.sh` is a settings change only the operator may make. It is not a question: the
    operator ruled on 2026-10-20 that permission prompts are "virtually always a yes, so improve the
    allowlist/config" (`29d62f1ad390`), so it is filed once as an operator step (`cc-backlog needs … --class
    needs-human`). Until it lands, a refusal is that one pending step: keep the work running Claude-only and
    never re-ask per repo.
  - **Not a routing change:** it routes no `model-config.yaml` slot. "Uncertified means unrouted" (operator,
    2026-08-10, `CODEX_ADVERSARIAL_SLOT_PROBE.md:25-31`) still governs slots, and a blanket "use Codex for
    adversarial work" is what that probe's REJECT warned against (`:227-228`). This grant is additive review
    beside Claude, the mixed-vendor judging the probe found real (`:263-267`).
  - **Open:** whether it also covers Google's Antigravity CLI (`agy`) is not decided here.
```

The pins of today's text all survive: `tests/research-program-exemption-rules.bats:24-40` ("- F2 well-researched:",
"timebox receipt satisfies", "- E0, read-only turn:", "relaying the certificate", "Offering researched, in-scope
remaining work", "is not an offer") and `tests/close-research-pending-rules.bats:15-27` (E0, untouched). Measured: no
test greps any phrase these blocks delete (`grep -rlF` over `tests/` for each; the one hit, "12 runnable now, 195", is
a close-text fixture in `tests/anti-deference-nudge.bats:419`, not a read of R).

### 3.8 C8 — other machine text

- `hooks/dispatch-assert.sh:237`, `:269`: "`cc-decide open --class C --what \"…\"` if it is a decision" → "`cc-decide
  open --class B --what \"…\" --default \"<the course you keep>\" --deadline <ISO> --default-effect no-change` if it is a
  judgment call (class C, with `--ceiling`, only for an operator-only act)". No test pins the old text (D2:626-627).
- `hooks/lib/why-tier.sh:268-269` ("set … # ONLY on 🔧", "clear # on ✅/📦/⛔/📤") → "# on 🔧, or ⛔ with `Not gated by
  it`" and "# on ✅/📦/held ⛔/📤"; `:312-313` "open-decision-hold … (file it: `cc-decide open --class C …`)" → "(file it
  by class: `cc-decide help`)" (crit/D1-rule-text--constraints-feasibility.md D-6).
- `commands/wrap.md:142-145`: "⛔ … from open class-C decision packets THIS session filed … " gains "a ⛔ ends a turn only
  when every remaining in-scope item waits on it; a judgment call with a status-quo course is class B".
- `hooks/operator-readout.sh:1513`: `[ "$(lf LOOP_OPEN)" = 1 ] && [ "$(lf HELD)" != 1 ] && parts="${parts:+$parts · }loop
  scope open (no recorded stop)"`, so a loop 🔧 does not render as a cause-less "loose ends" (the renderer-drops-the-cause
  defect recorded at `:1480-1488`). The ⛔ arm prints READOUT verbatim (`:1541-1548`), so the `Not gated by it` and
  `Held by this session` clauses reach the operator block with no change.
- `commands/handoff.md:133-134` (the "Freeze the mission/DoD for the successor" step): one added clause, "and name
  every open class-C decision id this session filed in the brief
  (`cc-decide list --open --class C --json | jq -r --arg s \"$CLAUDE_CODE_SESSION_ID\" '.[]|select(.session_sid==$s)|.id'`):
  a successor's ledger sees only its own packets, so it can neither relay nor `recheck` and hold one it was not told
  of". The first draft left this instruction only in G-04, which no session loads (§9.1 risk 5). A text change to an
  already-deployed command, not a hook; `scripts/handoff-fire.sh --recycle` (21,830 lines, measured `wc -l`) is not touched.
- Left as known stale phrases, filed as follow-ons with their own tests (each would pull completion-assert's 193-test
  suite into this change): `hooks/completion-assert.sh:1757` "(… a real value fork)" inside the D4 offer reason; and
  its ⛔ fact `BLOCKED ON YOU — N decision(s) filed this session are open …; that IS your rung;` (`:1236-1238`), which
  gains a `SCOPE_UNGATED`-conditional clause "— and in-scope work they do not gate remains: keep driving it (the
  readout's `Not gated by it`)". The floor fires on the same Stop regardless, so the follow-on is wording, not
  mechanism. `hooks/lib/close-shape.sh` needs no change: its template's verdict line is "`no — <what remains + who
  drives it>`" and the rung line copies READOUT verbatim (`:179-180`), so the new `Not gated by it` clause reaches the
  close through it, and it carries no ⛔-specific instruction to idle (measured `grep -n '⛔'`: only comment lines).

### 3.9 C10 — `scripts/xvendor-review.sh` (new; the grant's envelope in tracked code)

The 80% guard exists today only in the untracked `~/.cache/agentsync-bring-back/b13/tools/xverify.py:21-40` (measured
`sed -n`). The wrapper ports it and adds the export and key strip (D3 §7.2, with D4's fail-closed meter):

```
xvendor-review.sh --meter                    → prints used_percent=<n> window_minutes=<m> source=<file>
xvendor-review.sh <repo> <prompt-file|-> [--rev <sha>] [--model <m>]
  1. refuse unless <rev> (default HEAD) is a commit of <repo>
  2. meter, under an exclusive lock ($TMPDIR/xvr-meter.lock, `mkdir` lock, held through step 5's launch so two
     sessions cannot both read 79% and both call): newest 20 ${CODEX_HOME:-$HOME/.codex}/sessions/*/*/*/rollout-*.jsonl
     by mtime, last line holding "rate_limits"; the window with window_minutes ≥ 10080, else primary; used_percent.
     A reading whose resets_at (epoch s) has passed belongs to an expired window: discount it to 0 and say so.
     ≥ ${CC_XVR_METER_STOP:-80} ⇒ rc 5 · a rollout exists but no readable rate_limits ⇒ rc 4 (fail closed)
     · no rollout at all (never used) ⇒ proceed with a stderr note
  3. refuse unless `codex login status` reports a ChatGPT login (subscription, never the API)
  4. exp="$(mktemp -d "${TMPDIR:-/tmp}/xvr.XXXXXX")"; git -C <repo> archive <rev> | tar -x -C "$exp";
     remove the pathspecs in <repo>/.claude/xvendor-review.exclude
  4b. read confinement: ch="$(mktemp -d …)" holding only a copy of the real CODEX_HOME's auth.json (0600);
     readable roots = {$exp, $ch}: codex's own readable-roots / permission-profile support (0.147 lists
     `--sandbox-state-readable-root` and `-P/--permission-profile` under `codex sandbox --help`, measured) if step 0
     proves it confines the model's commands, else an outer `/usr/bin/sandbox-exec` profile denying file-read* outside
     $exp, $ch and the system and codex install paths (step 0 also proves codex's own seatbelt still applies inside it).
     Canary: write a random token to "$HOME/.cache/xvr-canary.$$" (under the real HOME, outside both roots) and run
     the same confinement over `cat` of it; readable ⇒ rc 6, no review (fail closed); then delete it.
  5. env -u OPENAI_API_KEY -u OPENAI_BASE_URL HOME="$ch" CODEX_HOME="$ch" timeout ${CC_XVR_TIMEOUT_S:-1800}
     <confinement> codex exec -s read-only --skip-git-repo-check -C "$exp" "<prompt>"
     (`-C/--cd` and `--skip-git-repo-check` exist on the installed codex-cli 0.147.0: measured `codex exec --help`)
  6. review on stdout; one IDL row {tool:"xvendor-review",repo,rev,meter_before,confine,rc};
     rm -rf "${exp:?}" "${ch:?}"; release the lock
```

The confinement step closes the exfiltration path the critic named: `-s read-only` confines writes, not reads, so
without 4b the reviewing model, or prompt-injection text in the reviewed code, could read `~/.ssh`, `~/.claude`, mail
caches or other repos and send them; that is the "[Data Exfiltration]" the auto-mode classifier refused (TX:4640,
TX:4678). Which mechanism confines is a step-0 measurement, not a guess: codex 0.147 advertises readable roots
(measured in its help text; whether `codex exec` honours them for the model's commands is not), and whether codex's
own seatbelt can still apply inside an outer `sandbox-exec` is not measured either, so the outer profile is the
fallback, not the plan. Until step 0 proves one, the wrapper
cannot pass its canary and refuses every run, which is the safe failure; R-19 and G-11 state "reads confined to that
export or no run".

---

## 4. Loop and false-block analysis

### 4.1 Per change

| Change | Can it extend a turn? Worst-case state | Bound (existing or new) | False-block exposure and mitigation |
|---|---|---|---|
| C2 ledger fields | No (fields) | n/a | none; all fields 0 on any unknown, readout byte-identical with the switch off |
| C2 loop 🔧 arm | No by itself; makes a clean loop session read 🔧 instead of ✅. Checked against the two Stop arms that react to a rung under a done-claim: completion-assert's done-claim contradiction is per-field (REMAINDER, CUSTODY_OPEN, FILED_MINE, UNCONVICTED_MINE, CLOSE_FLOOR, 🚀, ⛔; `hooks/completion-assert.sh:1103-1144`, `:1166`, `:1218`) and its D6/D7 shape arms need ✅/👤 (`:1535`, `:1643`); anti-deference's P0-4c contradiction is DIRTY ∨ UNLANDED ∨ REMAINDER>0, and it reads the rung "but not USED for the fire decision" (`hooks/anti-deference-nudge.sh:513-521`). None reads `LOOP_*` or RUNG=🔧, so a loop 🔧 under "Good to close: yes" draws no new block from either (test §7.3 S23) | ends on `done`, an answered named packet, a re-scope, supersession, a research program | population: own intentional verb-first loop lines only: 1/362 store lines, 8/1,648 transcripts, all B13 lineage (§9.3 M1-M2); placed below 🚀/re-check ⛔/👤 |
| C1 capture | No (writes the store) | one fork per change in the Scope-line count, only while `LOOP_SRC=none` (now including a checkout with no store file), marker written first | loop lines only, and `DOD_SCOPE` skips `(stop-capture)` blocks, so a capture never moves a sibling's `DRAIN_SCOPE` (§3.1 (i); crit/D4--constraints-feasibility.md D-9; crit/D3--constraints-feasibility.md D-3); newest human-origin line, line-anchored, verb-first |
| C3 hold/done/`set` guard/`isMeta` | No | n/a | hold refused unless an open own class-C id that declares a ceiling or routes C; one signal only ⇒ lapses after 6 h; hold/done refuse text containing `Scope (`; every hold lapses when the packet is answered |
| **C4 scope floor** | **Yes** (`decision:block`). Worst case: a stubborn session in a loop scope with an open decision, re-closing idle after every wake | no fire on a turn its own block opened, directly or through a chain of other hooks' feedback turns since it; ≥600 s between fires; ≤3 per key per 6 h; ≤6 per session per 24 h; per-sid map state; fail closed; only on the unarmed path; one floor per Stop; shadow spends no budget | see §4.2; every abstain is logged; headless and pane-less runs abstain |
| C5 mech arm on ⛔ | Yes | `CC_MECH_BLK_MAX` (1) × `CLAUDE_CONTINUE_MAX` (8) = 8 per session; separate budget; self-clearing on commit; `clear` spends it | own dirt only (`session_dirty_mine` rc 0); arms on any ⛔, a genuine all-gating gate included (one commit turn, which R:38 already asks for); the text forbids landing while the decisions are open |
| C6 nudge | Starts a turn (mail + socket wake); blocks nothing | ≤3 per key with 30 min/1 h back-off (1 h after `wake-path-armed`), all inside the 6 h telemetry horizon; ≤4 per session per 24 h; ≥30 min apart; ≤3 per sweep (file-backed); marker survives recovery; fail closed; cc-wake W5 ≤1 wake/120 s/sid (`bin/cc-wake:266-272`) | fires only when the session's newest `scope-floor*` row says `ungated:1` and no newer `continue`/`cli-set`/`fired` row exists, so kill-switch, operator-hold, conversation, fresh in-flight, clear and armed-path states all suppress it (crit/D2--loop-false-block.md §2.2, crit/D3--loop-false-block.md D-8); a time-bounded in-flight row older than 1 h no longer does |
| C6 held re-confirm | Starts ≤1 turn per hold key | 1 per hold key; a lapsing hold is a new key each window, so ≤4 per 24 h | the re-confirm asks a question; it never says "run the next round" |
| C7 hints | No | n/a | stderr only; stdout and rc unchanged; 3 s bound; fail open; sessions only, never under bats unless forced |
| C7 ceiling | No (a CLI refusal, rc 2) | n/a | a genuine gate filed without `--ceiling` costs one retry, with the flag printed; the router's disagreement never refuses; legacy packets fold to today's ⛔; kill switch `CC_DECIDE_CEILING=0` / `decide-ceiling.off` |
| C8/C9 text | Advisory | R:217 keeps the chain model-bounded; adds "a wait is never a step" and the context-boundary clear | the agent-armed chain is unchanged in kind (G:1128-1140 states it is unbounded by design) |

**Combined worst case for one stubborn session per 24 h:** 6 floor turns + 4 nudge turns + 4 held re-confirms (a
lapsing hold renewed each window), then an operator digest; every further turn needs a real state change (estimated
from the bounds above). In the B13 replay it spends 3 floor turns and 3 nudges between 06:44Z and ~11:11Z (§2).

**Why the floor's own forced turn cannot loop.** The floor never fires on a Stop whose turn its own block opened
(turn_scan `.b`), whatever that turn wrote, nor on one whose turn another Stop hook's feedback opened when that chain
of feedback turns leads back to a floor block (walked over the last 6 turns), and never twice within 600 s. The first
draft looked back one turn only, so a re-close that completion-assert, anti-deference or dispatch-assert blocked would
have reached the floor again inside the same 5-34 s burst. D4's no-progress guard skipped only an idle forced turn, so a forced turn that
appended to a notes file burned the second fire inside the same burst (crit/D4--incident-replay.md §1 F2 row); D3's
measured re-Stop interval after a floor block is 5-34 s (12 of 12 ship-floor fires, crit/D3--incident-replay.md §2), so a
burst-local second fire would have spent the budget before F2. Here fires 2 and 3 land at F2 and F3, which watcher
timeouts opened, exactly the closes maps/incident-replay.md §7 says MUST be caught.

**Why the budget cannot be reset by the demanded action.** New ids joining the set (a round's land filing a
`shipland-esc-*` packet under the lead's sid, crit/D4--loop-false-block.md §1.1) or a reworded hold make a new key, but the
per-session 24 h ceiling is keyed on nothing but the session, and the map keeps every key's fires, so revisiting a key
sees its history. A per-session lifetime cap was rejected on evidence: B13's ship-floor and assert budgets had been spent
two days before the idle (maps/stop-hooks.md §0.1).

### 4.2 Legitimate stops

| Case | Behaviour | Why it is not false-blocked |
|---|---|---|
| Genuine C10/C6/permission/credential gate that gates ALL work, no loop, no own boxes (C4; sessions 43055acd, e582464c, c56c729c, 79076bcf, fd91140d, maps/legit-stops.md §4) | allowed, byte-identical readout, no floor turn, no nudge; **one commit turn if the session holds own uncommitted edits** (C5, §3.4 (ii)) | `SCOPE_UNGATED=0` ⇒ `scope-floor-nothing-ungated`; the supervisor sees no `ungated:1` row. The 48 open class-C packets sit in 23 sessions none of which has a loop capture (measured, §9.3 M3). The first draft claimed "zero forced turns" here, which C5's code contradicted |
| The same gate inside a loop scope where every round needs the act | ≤1 forced turn, then a hold | the first fire names `hold` with its criterion; a packet with a declared ceiling that routes C takes a durable hold, the readout shows it and the floor reads `nothing-ungated`; one held re-confirm nudge per hold key. A ceiling the router disagrees with (a money path such as `a247b7288149`), or a legacy packet that routes C, takes a lapsing hold: one floor turn and one re-confirm per 6 h, which re-asks but never refuses the stop |
| A legacy genuine gate the router misses (no ceiling, routes B) inside a loop scope | the hold is refused; the lead re-files it with `--ceiling` and holds that | bounded: ≤3 floor turns per 6 h until it does; no such packet exists today in a loop-captured session (§9.3 M3) |
| ⛔ (or ✅) over an unfinished **non-loop** frozen scope | allowed, as today: an accepted residual | the deterministic half for non-loop scopes reads 0 in production (§3.0 row (a), §9.3 M17); R:38/R:103/R:217 are the only answer. Not a false block, a known false allow |
| Background Agent subagents in flight (`Agent` with `run_in_background`) | allowed | `inflight_bg_tasks` counts each `agentId` from an `Async agent launched` result until its `<task-id>` arrives or its `subagents/agent-<id>.jsonl` goes 30 min stale (§3.3); `scope-floor-inflight {what:agent}` |
| Headless (`CC_PANE_ID` without `ITERM_SESSION_ID`) or pane-less (`claude -p`) run | allowed | `scope-floor-headless`, wake_floor's own predicate (`hooks/session-continue.sh:734`); for a resident headless agent a blocked Stop is a death (`:715-717`) |
| The operator answers the loop's named packet ("stop") through cc-decide | allowed; the 🔧 and the floor go quiet | `LOOP_SRC=answered` when a 12-hex id in the loop line names an actioned or vetoed packet (§3.1 (ii)); B13's line names `b4780d7bb60e` |
| Research-program session | allowed | the ledger sets `LOOP_SRC=program` (`compute_research` in every mode); the floor also abstains `research` |
| Fired peer | allowed unless it has its own loop scope | lane briefs carry their own `Scope (frozen): drive this ONE item…` (`bin/cc-dispatch:3299`), the newest human-origin line, not a loop (measured 0 lane captures, crit/D4--loop-false-block.md §2.8); a fired peer with ⛔ and no loop/boxes reads `SCOPE_UNGATED=0` |
| Teammate (Agent Teams assignee) | allowed | `scope-floor-assignee` (rc 0 or 2, copied from `ship_floor`, `hooks/session-continue.sh:1189-1197`); its newest row is an abstain, so no nudge |
| Handed-off origin predecessor (B13 `666022fd` after 20:22Z) | allowed | custody stays open while its fired successor runs (measured: pane 134's `fire-lead-idle-fix` row open since 20:42:58Z, `custody/cb2bdf30….jsonl`) ⇒ `inflight`; once the successor's first Stop captures the same loop text, the predecessor reads `LOOP_SRC=superseded` |
| Read-only turn | allowed | a turn opened by a human prompt that wrote nothing ⇒ `scope-floor-conversation` (crit/D3--loop-false-block.md D-6); R:34 keeps read-only turns out of auto-continue |
| Operator pause ("wait for my answer", "stop the loop", "hold off …") | allowed | `OPHOLD_RE` (14/14 phrasings, §9.3 M4) plus `KILL_RE` (`:386`); a false match only abstains |
| `/goal` whose condition has an operator-only conjunct | allowed | `GOAL_SRC=live` ⇒ `scope-floor-goal`: the goal evaluator owns continuation, and the lesson is that such a goal never clears (`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md`) |
| Loop where every remaining round needs an operator-only act (C7) | allowed after one filing | `cc-backlog needs … --class needs-human` makes the ledger 👤, which ranks above the loop arm, and the floor is silent on 👤 |
| Money-landing repo at 📦 | allowed | 📦 is decided before the ✅-eligible branch (`:2615`); the floor and the loop arm never see it. Under ⛔ the floor says "run the next round", never "land" |
| Usage-limited session | not woken, not blocked | a limit death is `StopFailure`, not `Stop`; cc-wake refuses `refused-limited` (`bin/cc-wake:170-240`) |
| Context at or past the boundary | allowed | `scope-floor-context-high` on boundary-handoff's own axes; the recycle brief carries the loop line and the successor recaptures it |

---

## 5. Constraints check

### 5.1 No settings edit, no new hook registration

Every actuator rides something already registered or already running (measured: `jq '.hooks.Stop[]?.hooks[]?'
~/.claude/settings.json`): session-continue (Stop #4, 10 s), anti-deference-nudge (#5, 5 s), dispatch-assert (#7),
operator-readout (#9). dod-persist is called as a CLI from session-continue, not registered anew. lead-supervisor is the
launchd daemon, picked up by its sha self-restart (`scripts/lead-supervisor.sh:92-104`); no plist edit. cc-decide,
cc-memory-search and xvendor-review.sh are CLIs. Kill switches are env vars **or** files under `~/.claude/state` (§3.0),
so none needs a settings edit. The one thing that does need a settings change, the classifier allow rule for
`xvendor-review.sh`, is filed for the operator as a needs-human step under the existing ruling `29d62f1ad390` (§8.4),
never done by an agent
(measured: `defaultMode` auto, `autoMode` keys `environment` and `soft_deny`, 0 allow rules matching
`codex|xverify|xvendor`).

### 5.2 No gate weakened — the wrap-ledger consumer blast radius

Every consumer parses `KEY=` by name, so added fields are invisible to them (maps/wrap-ledger.md §3). What changes is
RUNG in one case (✅ → loop 🔧) and the ⛔/re-check ⛔ READOUT text in two cases (appended clauses).

| Consumer | Effect | Weakened? |
|---|---|---|
| session-continue mechanical arm (`:1099-1103`) | loop 🔧 passes the rung test but still needs own dirt; ⛔ now arms too (C5, own budget, no-land text) | No: strictly more coverage |
| ship floor (`:1203-1216`) | unchanged: ⛔ stays above 📦, the loop arm sits below 🚀 | No (the D2/D4 placement would have masked 🚀; fixed) |
| completion-assert ⛔ arm and `blocked-answered` (`:1218-1238`) | unchanged; the ⛔ prefix is unchanged | No |
| completion-assert 🚀 contradiction (`:1166`) | unchanged: 🚀 outranks the loop arm | No |
| completion-assert D6 close shape (`:1535`, ✅/👤 only) | a loop session that would have read ✅ now reads 🔧, where D6's predicate (a terminal close) does not hold, exactly as for any dirty-tree 🔧; the loop idle is now refused by the floor instead | No: D6 shapes terminal closes, and the state is no longer terminal |
| boundary-handoff free-win (`:629-660`) | a loop session no longer gets ✅ free-win recycle advice (control C5) | No: that advice over an open loop was the defect |
| operator-readout certificate (`:2458-2480`) | needs ✅; a loop session gets none | No: the certificate over an open loop was false (D1 L4) |
| operator-readout ⛔ state (`:1541-1548`) | prints the new clauses verbatim | No |
| anti-deference (`:500-521`) | RUNG logged only; the new ⛔ clause carries no TELL (test §7) | No |
| handoff-fire self-close refusal (`scripts/handoff-fire.sh:8664-8689`) | keys on REMAINDER/UNLANDED, never RUNG; `LOOP_OPEN` is never folded into REMAINDER | No |
| session-busy render (`hooks/lib/session-busy.sh:483-499`) | "IDLE … (rung 🔧)" instead of ✅ for loop sessions | No (more accurate) |
| class C itself | R-13 keeps cc-decide's reserve and adds the credential and G2 surfaces, so every rule-mandated operator-only act stays C; a session's class-C open must now declare which (`--ceiling`), a strictly added refusal; legacy packets keep ⛔; no machine text tells an agent to action a class-C packet | No: one more required field on a path that already refuses three missing ones (`bin/cc-decide:236-245`) |
| `dod-persist.sh hold` (new verb) | refuses a packet with neither a ceiling nor a C route; lapsing for one signal | No: a new discharge, narrowed |

### 5.3 Instruction budget (measured)

Measured with `python3 -I` reading this file's `old:`/`new:` blocks, checking each `old` occurs exactly once in its
file, applying them in memory, and measuring with `hooks/lib/instruction_budget.py` `parse()` (UTF-16 units, the
land gate's own predicate). Nothing was written.

| Block | old found | old units | new units | delta |
|---|---|---|---|---|
| R-01 Stop-hook pointer (into R-18) | 1 | 212 | 0 | -212 |
| R-02 three restatements | 1 | 529 | 48 | -481 |
| R-03 lib path | 1 | 36 | 0 | -36 |
| R-04 ship-floor bound | 1 | 66 | 1 | -65 |
| R-05 resident teammates | 1 | 568 | 321 | -247 |
| R-06 loop scope recorded by `set`, end marker, owner-only writes | 1 | 186 | 470 | +284 |
| R-07 decision row | 1 | 74 | 219 | +145 |
| R-08 PASS/FAIL restatement | 1 | 184 | 34 | -150 |
| R-09 ruling search, re-ask valve; refusal mechanics cut | 1 | 465 | 614 | +149 |
| R-10 ⛔ definition | 1 | 49 | 63 | +14 |
| R-11 ⛔ ends a turn only when all-gated | 1 | 102 | 357 | +255 |
| R-12 S1 example | 1 | 124 | 60 | -64 |
| R-13 class routing with `--ceiling` | 1 | 517 | 761 | +244 |
| R-14 sudo/GUI routing restatement | 1 | 146 | 52 | -94 |
| R-15 BLOCKED narrowed | 1 | 155 | 194 | +39 |
| R-16 consent restatement | 1 | 146 | 0 | -146 |
| R-17 auto-continue (keeps "Within a turn…") | 1 | 771 | 736 | -35 |
| R-18 pointer | 1 | 58 | 82 | +24 |
| R-19 standing grants | 1 | 18 | 767 | +749 |
| R-20 close-contract parentheticals | 1 | 174 | 81 | -93 |
| R-21 anti-deference parenthetical | 1 | 56 | 0 | -56 |
| R-22 🚀 pointer | 1 | 56 | 0 | -56 |
| R-23 capacity detail, trap kept | 1 | 218 | 189 | -29 |
| S-01 manual-command decision | 1 | 76 | 92 | +16 |
| S-02 version note | 1 | 90 | 41 | -49 |
| S-03 launcher flags | 1 | 123 | 51 | -72 |
| S-04 source path | 1 | 63 | 0 | -63 |
| **R whole file** | | **30,287** | **30,426** | **+139** |
| **S whole file** | | **28,503** | **28,335** | **-168** |
| **S + R** | | **58,790** | **58,761** | **-29** |
| G whole file (not loaded) | | 116,486 | 129,348 | +12,862 |

Added text 1,919 units, cuts 1,948 (measured, same pass, re-run on this revision; §9.3 M15). All 11 G `old` blocks also
occur exactly once (38 blocks in all). The user tier (S + R + the 2,284-unit mission board) goes from 61,074 to 61,045
(estimated by arithmetic from these measured units). The same pass confirmed that no edited file contains a
`Scope (frozen):` loop line. The revision's text changes (the R-06 `set` instruction, the R-13 ceiling, the narrowed
R-15, the kept R-17 and R-23 sentences, the R-19 confinement clause) are paid by cutting R-09's refusal-mechanics
sentence, whose content the tools print on refusal (R-09 note).

- Per-file caps (40,000, `config/instruction-budget.json`) hold for R and S.
- The land gate checks only the per-file cap for repo-side S and R (they classify as tier `source`,
  `hooks/lib/instruction_budget.py:474-480`, `:647-651`); the one-in-one-out policy is `destinations.user`. This change
  meets it.
- The user tier stays over its 60,000 budget by the amount it was over before (61,074 measured in maps/rules-text.md §6);
  this change neither causes nor fixes that.
- Re-gate: `docs/plans/INSTRUCTION_BUDGET.md:127` records the operator's 2026-10-04 ruling "to defer the run until the
  next slim edit" (about $403 list, ~100 runs ≈ 3-10 weekly pp across 3 accounts, `:125`; maps/rules-text.md §6).
  This is that edit, so the ruling already says what to do: §8.1 step 9 runs the held-out F1 re-gate after converge.
  The first draft proposed re-asking it as a class-B packet defaulting to "defer again", which is the incident's own
  failure (goal (c)); that question is withdrawn from §8.5.

### 5.4 Deploy path

R deploys to `~/.claude/rules/10-session-close.md` and S to `~/.claude/CLAUDE.md` by install.sh copy
(`install.sh:1113-1139`), G to `~/.claude/CLAUDE.full.md` (`:1080-1087`), all at the next converge
(`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, `.claude/CLAUDE.md` § Standing-converge; `deploy-live.sh:52`
runs install.sh). Hooks, scripts and bin are per-file symlinks that go live on the fast-forward; the two new files
(`hooks/lib/inflight.sh`, `hooks/lib/loop-scope.sh`) are reached through each consumer's own `$0`-symlink resolution
before install.sh links them (`hooks/session-continue.sh:1067-1070` records why). `scripts/xvendor-review.sh` is linked
by install.sh at converge and reads 🚀 (`LIVE_ADDS`) until then. Skew: a multi-day lead keeps the rules it loaded at
start, so it can meet the new floor under the old R:217; the floor's text carries its own instruction and the caps bound
the disagreement (crit/D2--constraints-feasibility.md §3).

---

## 6. Rejected designs, and what was grafted

| Design | Scores (replay / loop / constraints) | What sank it | Grafted |
|---|---|---|---|
| D1 rule text only | 3 / 4 unsound / 6 | No deterministic break anywhere: the lead already ignored text that told it to keep going (R:4, S:166), and "a lead that writes No round 27 until you answer is caught by no D1 mechanism" (crit/D1--incident-replay.md §0). Its arm-the-chain path claimed a bound it did not have in a non-converging loop (crit/D1--loop-false-block.md §1, blocker) and muted boundary-handoff while armed (crit/D1--constraints-feasibility.md D-2) | The gating definition (R-11), the class-B template (R-13), the G twins G-01..G-09 and G-11 (adapted), "never a box for a loop", "name open ids in a recycle brief", the positive-control tests (T7/T9/T11 shapes), the budget method |
| D2 hook enforcement | 6 / 4 unsound (2 blockers) / 6.5 | Single-slot latch re-armed by A→B→A; quoting discharges parsed as new contracts; `Scope (held)` as a silent off-switch advertised in the readout; stale supervisor oracle; loop arm above 🚀 (crit/D2--loop-false-block.md §1.1-1.2, §2.2; crit/D2--incident-replay.md D1; crit/D2--constraints-feasibility.md M1-M4) | Own-session contract facts; held/done markers (now line-anchored, refused if they quote a Scope line, written only by verbs); custody under ungated ⛔; GL glosses; `enqueued=1` marker rule; the verdict-parse fix; B-3 logging; the rule cuts |
| D3 schema first | 6 / 5 unsound / 5.5 | Required `--category/--gates/--why-gated` touches 62 test sites plus `gate_sweep.py`; a self-declared `escalation --gates all` silences every floor and nudge with zero forced turns; legacy hard packets launderable via `--supersedes`; the challenge discharged by a sentence; trunk-sha latch re-armed by siblings; dead per-sweep cap; ~35 files (crit/D3--loop-false-block.md D-1..D-4, D-17; crit/D3--constraints-feasibility.md D-1..D-4, D-14) | `open --help`; most-useful-line-last for `tail -3`; the class header text; the conversation hold and context-high abstain; `xvendor-review.sh`; the 1 h re-check after `wake-path-armed`; `has()`-style fail-safe reading as a general lesson |
| D4 minimal sufficient | 6 / 4 unsound (1 blocker) / 6 | Budget reset by the demanded action (new ids joining); per-cwd latch; loop arm above 🚀/👤; a self-certified discharge as a new frozen line, with a literal `Scope (frozen):` in hook text that PreCompact would capture; blind to background-Bash dispatch (two measured false fires on 10-23); stale oracle (crit/D4--loop-false-block.md §1-3; crit/D4--incident-replay.md #1-#3; crit/D4--constraints-feasibility.md D-1..D-3) | The K1-K4 skeleton itself; human-origin Stop-time capture; the live-wave abstain (F8); the turn_scan guard (now on any own-block turn); the cc-decide hint ordering; the tracked meter (now inside the wrapper) |

---

## 7. Test plan

All new suites `export HOME="$BATS_TEST_TMPDIR/home"` in `setup()` (hermeticity rule 1, maps/test-infra.md §5), unset
`CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID WRAP_SESSION_ID` and pass an explicit `WRAP_SESSION_ID`/`--session`, use
2099 or relative dates, and write negatives as `! cmd || false`. "Red without" = the test fails against
`origin/main`'s subject; every guard that is green on origin/main gets a named mutant instead (maps/test-infra.md §6).
Run every selected suite by hand and assert the `1..N` plan line; a cc-bats rc 75 is no verdict
(`.claude/rules/agent-operating-lessons.md:38`). Fixtures replay the real artifacts: TX:14's scope line, the F1/F2/F3 close
text (`mkfix` of TX:4437/4458/4476 lines 1-4), and e869/2902 packet copies (maps/incident-replay.md §7).

**Stubs go through `cc_stub`.** The suites need many stubs (`WRAP_LEDGER_BIN`, `DOD_PERSIST_BIN`, `CC_MEMORY_SEARCH_BIN`,
`CC_GATE_CLASSIFY_BIN`, `codex`, `git` and `sandbox-exec` on a fixture PATH, a cc-notify capture). The land gate runs
`scripts/test-stub-lint.sh` (`scripts/ship-land.sh:3924-3942`), which refuses any file whose inline `#!` stub writes
exceed its row in `config/test-stub-baseline.tsv`, and a new suite has no row ("absent = 0", `:1-5`). So every stub is
written with `cc_stub DIR NAME BODY` (or `cc_stub DIR NAME - <<'EOF'`), from `tests/helpers/cc-stub.bash`, never as a
heredoc `#!` file, and step 8 runs `scripts/test-stub-lint.sh` before the land.

### 7.1 `tests/wrap-ledger.bats` (grandfathered; real `bin/cc-decide`, `WRAP_DOD_FILE`)

| # | Test | Fixture | Assertion | Red without |
|---|---|---|---|---|
| L1 | B13 F1: own loop + two open class-C ⇒ ⛔ with ungated scope | `ok_state`; `## 2099-… (stop-capture) · toplevel=$PWD · session=$SID` + TX:14's scope line; `open_blocking` ×2 | `RUNG=⛔ LOOP_OPEN=1 LOOP_SRC=own SCOPE_UNGATED=1 BLOCKED_IDS=<a>,<b>` (sorted); READOUT has `need your call` and `Not gated by it: your loop scope`; `BLOCKED_GLOSS` names both | fields and clause absent |
| L2 | hold on an own open C ⇒ held | L1 + own `(manual-hold)` block `Scope (held): <a> — every round needs it` | `HELD=1 HELD_SRC=own SCOPE_UNGATED=0`; READOUT has `Held by this session:` and not `Not gated` | no HELD |
| L3 | hold lapses when answered | L2, then `cc-decide action <a>` | `HELD_SRC=stale SCOPE_UNGATED=1` | — (mutant: honour any held line ⇒ red) |
| L4 | `hold none` releases | L2 + own `Scope (held): none — …` | `HELD_SRC=released SCOPE_UNGATED=1` | — |
| L5 | foreign loop is not mine | loop block `session=OTHER` | `LOOP_OPEN=0 LOOP_SRC=none` | (mutant: drop session filter ⇒ red) |
| L6 | done ends the loop | own loop + own `(manual-done)` `Scope (done): …` | `LOOP_SRC=done` | done line today becomes a frozen line |
| L7 | predecessor's done is inherited | OTHER: loop L + done; own later block L | `LOOP_SRC=done` | — (mutant: own-only done ⇒ red) |
| L8 | successor supersedes predecessor | own L, later OTHER L | `LOOP_SRC=superseded`; same store with `WRAP_SESSION_ID=OTHER` ⇒ `own` | — |
| L9 | PreCompact blocks neither open nor close a loop | own `(PreCompact:auto)` loop line; then own intentional loop + later own `(PreCompact:auto)` non-loop line | first: `LOOP_SRC=none`; second: `LOOP_OPEN=1` | — (mutant: count PreCompact ⇒ red) |
| L10 | **C5**: class-B packet only + own loop, clean, landed ⇒ 🔧 not ✅ | real `open --class B …` | `RUNG=🔧 LOOP_RUNG=1`; READOUT names the loop and `dod-persist.sh done` | `RUNG=✅` today |
| L11 | precedence: the loop never masks 🚀, re-check ⛔ or 👤 | loop + `WRAP_LIVE_*` past budget; loop + a re-checked foreign packet; loop + a filed needs-human step | `RUNG=🚀`; `RUNG=⛔`; `RUNG=👤` | — (mutant: arm placed at CLOSE_FLOOR's rank ⇒ all three red) |
| L12 | verb-first pattern | positives: "Loop until dry. Each round…", "repeat until a round confirms nothing new", "keep going until the backlog is empty", "**loop until** green"; negatives: "add the loop until dry floor to session-continue", "review why a loop until dry lead idled 11 h", "PHASE 1 — research … a loop scope (\"loop until …\")", "dry-run the migration until it passes", "Fix gate-runaway-loop until landed" | `LOOP_SCOPE` 1 / 0 as listed | — (mutant: D2's 40-char prefix ⇒ negatives red) |
| L13 | research program | L1 + `CC_RESEARCH_REGISTRY` naming `$PWD` | `LOOP_SRC=program`; identical RUNG in default and `--machine` modes | mode divergence |
| L14 | switches and memo | L1 with `WRAP_LOOP_SCOPE=off`; L1 with `$HOME/.claude/state/loop-scope.off` | `LOOP_SRC=off`, READOUT byte-identical to a run without the change; on/off runs never share a memo body | stale serve (mutant: drop the key term) |
| L15 | `rung_next` | L1 `--full`; L2 `--full` | `continue → drive the in-scope work`; L2 the STOP-ASK text | — |
| L16 | custody under ungated ⛔ only | L1 + open `cc-custody` row; L2 + the same | L1 `CUSTODY_OPEN=1`, `CUSTODY_SRC≠skip`; L2 `CUSTODY_SRC=skip` | today always skip under ⛔ |
| L17 | BUSY splice and pins | any | `sed -n 18p` starts `LIVE=`; `:1934-1961` unchanged and green | control |
| L18 | id cell cannot shift fields | one open C with a tab/newline in `what_plain`; zero open | `BLOCKED_WHAT` intact; `BLOCKED_IDS=` empty | (mutant: no `-` pad ⇒ red) |
| L19 | no store file is capture-eligible | `WRAP_DOD_FILE` pointing at a missing file, SID set | `LOOP_SRC=none`, all other new fields 0, RUNG as today | red against the first-draft spec (`n-a`) |
| L20 | an answered named packet ends the drive | own loop line naming packet `<p>`; `<p>` actioned / vetoed / expired-actioned / open | `LOOP_SRC=answered LOOP_OPEN=0` / `answered` / `own` / `own`; cc-decide stub erroring ⇒ `LOOP_SRC=error`, fields 0 | — (mutant: count expired-actioned ⇒ third case red) |
| L21 | lapsing hold | L2 with `Scope (held): <a> until=<now+3600> — …`; then `until=<now-1>` | `HELD=1 HELD_SRC=lapsing`; then `HELD_SRC=lapsed SCOPE_UNGATED=1` and the `Not gated by it` clause | red against the first-draft spec |
| L22 | the non-loop residual is pinned | own non-loop frozen line naming a fixture `docs/plans/x.md` that holds `- [ ]` boxes | `SCOPE_UNGATED=0 LOOP_SCOPE=0` | control (a later widening must change this test deliberately) |
| L23 | a capture never moves a sibling's DRAIN_SCOPE | `(stop-capture) · session=A` block "loop until the backlog is empty"; ledger run as session B | B: `DRAIN_SCOPE=0`; a `(manual-set)` block with the same line ⇒ `DRAIN_SCOPE=1` (today's behaviour kept) | red against the first-draft spec |
| L24 | the TSV exemption still discharges | `scripts/tsv-pad-lint.sh` over the changed file | rc 0 | lint red if the exemption text is not updated |

### 7.2 `tests/dod-persist.bats`

| # | Test | Assertion | Red without |
|---|---|---|---|
| P1 | `hold <id> "<why>"` on an open class-C (`CC_DECIDE_BIN`/`CC_DECISIONS_DIR` fixture) | block `(manual-hold) · … · session=S` + `Scope (held): <id> — <why>`; rc 0 | unknown mode |
| P2 | `hold` refused: class-B id, actioned id, bad id, no session, why containing `Scope (` | rc 2 each; store `cmp`-identical | unknown mode (assert the message) |
| P2b | `hold` on a legacy open class-C packet carrying e869's exact `what_plain` and no ceiling (real `scripts/gate-classify.sh`) | rc 2; store `cmp`-identical; stderr names the class-B command; the same for 2902's text | red against the first-draft spec, which accepted any open own class-C id |
| P2c | hold tiers | `--ceiling self-mod` + a text that routes C (e.g. "edit settings.json") ⇒ line has no `until=`; `--ceiling money` + a247's text (routes B) ⇒ `until=<now+21600>`; legacy (no ceiling) + a C-routing text ⇒ `until=`; `CC_GATE_CLASSIFY_BIN` missing + ceiling ⇒ `until=`, + no ceiling ⇒ refused | — (mutant: accept on either signal durably ⇒ red) |
| P9 | `capture-loop` into a checkout with no store file | TX:14-shaped prompt; `dod_path_for` target absent | `captured`; the file now exists with the header and one `(stop-capture)` block | control (`persist_dod` creates the file, `hooks/dod-persist.sh:185-190`); the red half is S19b, the trigger |
| P3 | `done "<ev>"` and its refusals | written verbatim with `(manual-done)`; `Scope (` text and no session refused | unknown mode |
| P4 | `set "Scope (done): x"` and `set "Scope (held): …"` refused | rc 2; store unchanged | today rewritten to `Scope (frozen): Scope (done): x` |
| P5 | `capture-loop`: TX:14 shape (string, `origin.kind:human`, scope on line 5) + a newer tool_result lane brief `Scope (frozen): drive this ONE item` + an `isMeta` record and a task-notification each carrying a loop line | `captured`; one `(stop-capture) · session=S` block holding TX:14's line, not the lane's | unknown mode |
| P6 | `capture-loop` declines: newest human line non-loop; mid-line "DoD ref: none. Scope (frozen): loop until …"; not verb-first; own intentional block exists | `not-loop` / `none` / `not-loop` / `own-exists`; store unchanged | — (mutants: unanchored grep, no own-check ⇒ red) |
| P7 | `capture-loop` re-scope | own stop-capture loop; newest human line differs | `captured-rescope`; new block appended | — |
| P8 | PreCompact ignores `isMeta` user records | transcript whose only frozen line is in an `isMeta:true` record | no block appended | today captured |

### 7.3 `tests/scope-floor.bats` (new; `WRAP_LEDGER_BIN` stub driven by `STUB_*` env as `tests/ship-floor.bats:25-45`)

Common stub (F1, maps/incident-replay.md §7): `RUNG=⛔ BLOCKED=2 BLOCKED_SRC=env BLOCKED_IDS=290215743799,e869fac7eb34
SCOPE_UNGATED=1 LOOP_OPEN=1 LOOP_SRC=own HELD=0 CUSTODY_OPEN=0 CUSTODY_SRC=ok LANDING=0 RESIDENT_MINE=0
RESEARCH_PROGRAM=none GOAL_SRC=absent DIRTY=0 LOOP_HEAD=loop until dry. Each round = … BLOCKED_GLOSS=…`. Transcript:
last turn opened by a `<task-notification>` record, assistant text = TX:4437 lines 1-4. `CC_SHIP_FLOOR` is **not**
disabled (it must decline ⛔ itself); `CC_WAKE_FLOOR=0`, `CC_MECH_CONTINUE=0` unless stated; `INFLIGHT_LIB` = the real
lib; `CC_TELEMETRY_DIR` fixture at 64%.

| # | Test | Assertion | Red without |
|---|---|---|---|
| S1 | F1 blocks | `decision:block`; reason has `⟳ SCOPE FLOOR`, both ids, `run the next round as scoped`, `dod-persist.sh hold`, `dod-persist.sh done`, `an armed watcher wakes you only on mail`, `(scope floor 1/3`; reason lacks `Scope (frozen):`, `cc-decide action`, `nothing else will wake you` and `no status quo`; IDL `fired scope-floor` with `ungated:1`, `kind:"blocked"`, a key; `${sentinel}.blocked` arm `scope-floor` | no floor exists |
| S2 | F3 shape (verdict on line 3, watcher torn down) | same block | — (proves prose independence) |
| S3 | reclose | last turn opened by `Stop hook feedback:\n⟳ SCOPE FLOOR …`, with a write in it | no block; `scope-floor-reclose`, `ungated:1` | — (mutant: guard only when `.w=false` ⇒ red) |
| S3b | reclose through another hook's block | turns: task-notification (F1 shape) → `Stop hook feedback:\n⟳ SCOPE FLOOR …` → `Stop hook feedback:\n<completion-assert reason>`; and the same with an anti-deference reason in between too | no block; `scope-floor-reclose` | red against the first-draft one-turn guard |
| S3c | minimum gap | a fire, then a turn opened by a task-notification 60 s later (state file `F <now-60> <key>`) | no block; `scope-floor-gap`; at `now-700` ⇒ fires | — (mutant: no gap ⇒ red) |
| S4 | per-key window cap | 3 fires (task-notification-opened turns), 4th ⇒ `scope-floor-key-cap`; `CC_SCOPE_FLOOR_WINDOW_S=2`, sleep 3 ⇒ fires again | — (mutant: no cap ⇒ red) |
| S5 | A→B→A | key A ×3, key B ×1, key A ⇒ `key-cap` | — (mutant: single-slot state ⇒ red) |
| S6 | per-session day ceiling | 6 distinct keys, 7th ⇒ `scope-floor-day-cap` | — (mutant: no ceiling ⇒ red) |
| S7 | two sessions, one cwd | sid A spends 3 on a key; sid B same cwd, same key ⇒ fires | — (mutant: per-cwd state ⇒ red) |
| S8 | in flight | `CUSTODY_OPEN=1`; `LANDING=1`; `RESIDENT_MINE=1`; a live wave fixture; a live non-watcher bg task (tool_result `Command running in background with ID: b1`, no notification); **a live async agent** (tool_result `Async agent launched successfully.\nagentId: a8e552e552430265c`, no `<task-id>`, fresh `<sid>/subagents/agent-a8e552e552430265c.jsonl`) | each: no block, `scope-floor-inflight` with `what` (`agent` for the last) | the agent case is red against the first-draft lib (Bash ids only) |
| S8b | a finished or stale agent is not in flight | the same agent finished by `<task-id>a8e552e552430265c</task-id>` in a user record; and unfinished with its subagent transcript 3 h old | blocks in both | — (mutant: no agent freshness leg ⇒ second red) |
| S9 | a watcher alone is not in flight | bg task whose command is TX:4434's exact string `/Users/chrisren/.claude/bin/cc-await-ping 134 --timeout 3300 --interval 15`; also `timeout 3400 /x/cc-await-ping 134` and `CC_X=1 cc-await-ping 134` | still blocks in all three | red against a literal first-word match (the first-draft spec, which B13's 73 absolute-path watchers defeat); mutant: count watchers ⇒ red |
| S9b | finished tasks are finished, whatever record carries the notification | non-watcher bg task finished by a `queued_command` attachment / a `queue-operation` record (the TX:4472-4473 shapes); a non-watcher id never notified whose output file is 3 h old | blocks in all three | (mutant: user-record notifications only ⇒ red, the M14 trap; mutant: no freshness leg ⇒ third case red) |
| S10 | unknowns abstain | `BLOCKED_SRC=error`; `CUSTODY_SRC=skip` under ⛔; `INFLIGHT_LIB` missing | `scope-floor-unknown` | — |
| S11 | held / nothing ungated | `HELD=1 SCOPE_UNGATED=0` | `scope-floor-nothing-ungated` with `held:true` | — |
| S11b | a lapsed hold fires again | stub `HELD=0 HELD_SRC=lapsed SCOPE_UNGATED=1` with a state file whose three prior fires are > 6 h old | blocks; IDL `fired scope-floor` | red against the first-draft spec (no lapse: the hold held for good) |
| S12 | operator signals | last user message "…and stop"; "wait for my answer before round 27"; last turn opened by a human prompt with no writes | `kill-switch` / `operator-hold` / `conversation` | — |
| S13 | other abstains | assignee rc 0 and rc 2; teardown marker; `RESEARCH_PROGRAM=tm2`; `GOAL_SRC=live`; telemetry 80%; transcript ≥ `CC_BOUNDARY_SIZE_MB=1`; **RSS ≥ `CC_BOUNDARY_RSS_MB`** (a `CONTEXT_ECON_LIB` fixture whose `ce_size` prints `0 1600000`); **forecast-early** (telemetry 60% and a `.hist` fixture whose `ce_burn` forecast is 10 min); **headless** (`CC_PANE_ID=hdl-x`, `ITERM_SESSION_ID` unset); **pane-less** (both unset) | matching abstain rows (`context-high` ×5 axes, `headless` ×2) | RSS, forecast-early, headless and pane-less are red against the first-draft spec |
| S14 | loop kind | `RUNG=🔧 LOOP_RUNG=1 BLOCKED=0` ⇒ loop text block; `RUNG=🔧 LOOP_RUNG=0 LOOP_OPEN=1 DIRTY=1` ⇒ no scope-floor row | — |
| S15 | irrelevant rungs and clear | ✅/📦/🚀/👤 with no state ⇒ no row; after S1, ✅ ⇒ exactly one `scope-floor-clear`, then silent | — |
| S16 | old ledger | stub without the new fields | no row, no block | fail-open control |
| S17 | fail closed | state dir `chmod 555` | no block; `scope-floor-unwritable` | (mutant: `\|\| true` on the append ⇒ red) |
| S18 | switches | `CC_SCOPE_FLOOR=0`; `$HOME/.claude/state/scope-floor.off`; `CC_SCOPE_FLOOR=shadow` | none; none; `scope-floor-shadow`, no block, **the budget state file unchanged** (`cmp`), and a later `CC_SCOPE_FLOOR=1` Stop fires `1/3` | the shadow-budget half is red against the first-draft order (budget taken before the shadow check) |
| S19 | C1 trigger | `LOOP_SRC=none RUNG=⛔` with a `DOD_PERSIST_BIN` stub recording argv | invoked once with `capture-loop`; second Stop with the same count ⇒ not again | no trigger |
| S19b | C1 into a checkout with no store | real `scripts/wrap-ledger.sh` and real `hooks/dod-persist.sh`, `WRAP_DOD_FILE`/store dir with no file, TX:14-shaped transcript, rung ✅ | the Stop creates the store file with a `(stop-capture)` block; the next Stop's ledger reads `LOOP_OPEN=1` | red against the first-draft spec (`LOOP_SRC=n-a`, never captured) |
| S20 | composes with completion-assert | run session-continue then completion-assert on one Stop | completion-assert exoneration carries its double-block yield | control |
| S21 | `/bin/bash` 3.2 | S1 and S17 under `/bin/bash` | same results; IDL rows parse with `jq` | (the `{\}` trap) |
| S22 | wave parity | one fixture run dir through `inflight_waves` and through boundary-handoff's `bh_live_waves` | equal counts | drift guard |
| S23 | a loop 🔧 under a "yes" close draws no new block from the other arms | stub `RUNG=🔧 LOOP_RUNG=1 LOOP_OPEN=1 DIRTY=0 UNLANDED=0 REMAINDER=0`; close "✅ Good to close: yes — nothing left to do"; run session-continue, anti-deference-nudge and completion-assert on one Stop | session-continue blocks (kind `loop`, names `dod-persist.sh done`); anti-deference does not fire `false-done`; completion-assert raises no ledger contradiction | control for the §4.1 analysis (crit gap: "the loop 🔧 arm newly triggers completion-assert and P0-4c"; it does not) |

### 7.4 `tests/session-continue.bats` (existing)

| # | Test | Assertion | Red without |
|---|---|---|---|
| M1 | ⛔ + own dirt arms | step has `Do NOT /ship while decision(s)` and the ids; IDL `mechanical-dirty` with `rung:"⛔"`; budget in `.mech.blk` | `:1103` returns |
| M1b | ⛔ with `SCOPE_UNGATED=0` (a genuine all-gating gate) + own dirt | arms once (commit only, no land); a second Stop with the dirt still present does not (budget 1) | pins the chosen behaviour (§3.4 (ii)); a change to gate C5 on `SCOPE_UNGATED` must change this test |
| M2 | budgets are separate | spend the ⛔ budget; a later 🔧 lapse still arms | shared-file mutant |
| M3 | switches | `CC_MECH_BLOCKED=0`; `mech-blocked.off` | no arm | — |
| M4 | `continue_reason` | contains `a held ⛔`; the re-block skip still matches its own text | text |
| M5 | armed path unchanged under ⛔ | `arm "run round 27"` with a `RUNG=⛔` stub | blocks with the step (pins the rung-blind armed path R-17 relies on, D1 T11) | control |

### 7.5 Supervisor — `scripts/supervisor-e2e.sh` T41 (with `floor=` raised in `tests/lead-supervisor.bats:33-44`), run under `/bin/bash` 3.2

Fixture: a STALL? candidate (sleep pid, stale telemetry and transcript), IDL rows for its sid, `CC_NOTIFY_CAPTURE`.
Checks: (1) newest row `scope-floor-reclose ungated:1` ⇒ one send to the sid with `IDLE WITH UNGATED SCOPE` and the ids;
(2) a newer `scope-floor-clear`, `scope-floor-kill-switch`, fresh `scope-floor-inflight` or armed-path (`continue`, `cli-set`)
row ⇒ no send; (3) same key inside the back-off ⇒ no send; 30 min then 1 h ladder; cap 3 then one `subject_nudge_capped`
and one digest cause;
(4) `reason=wake-path-armed` ⇒ next send allowed after 1 h; (5) rc 124 with `enqueued=1` ⇒ marker written, no resend;
`enqueued=0` ⇒ retried; (6) per-sid 4/24 h and 1 h gap across keys; (7) 5 candidates ⇒ 3 sends in one sweep
(file-backed counter; red against an in-memory counter, crit/D3--constraints-feasibility.md D-4); (8) shadow and off by env
and by file; (9) non-uuid sid never addressed; (10) `clear_page`/`clear_page_recovered` keep `.nudged`; (11) verdict read
from the `^cc-notify: verdict=` line when a cc-wake `verdict=refused-busy` line precedes it (also for `advise_subject`);
(12) held row ⇒ exactly one re-confirm per hold key and one `held-idle` digest cause; (13) rotation fallback reads
`idl.jsonl.2*.gz`, never `idl.jsonl.chain.*.gz`; (14) the text lacks `Scope (frozen):`; (15) a `scope-floor-key-cap
ungated:1` row followed by a `wake-floor-mechanical-arm` row (the production shape: 19 such rows, §9.3 M21) ⇒ one send
(red against the first-draft "newest session-continue row" oracle); (16) a ladder whose next attempt would land past
`GC_S − NUDGE_HORIZON_SLACK_S` of telemetry age (`CC_SUP_GC_S=7200`) ⇒ digest `why:horizon` before GC; (17) nudges 1-2 both
recorded with cc-wake `refused-busy` and cc-notify `reason≠woken` ⇒ digest `why:not-woken` after the second send, before GC;
(18) a `scope-floor-inflight {what:"bg"}` row 2 h old ⇒ one send; `{what:"custody"}` 2 h old ⇒ no send; `{what:"bg"}` 10 min
old ⇒ no send; (19) a lapsing hold renewed after its window (two `nothing-ungated held:true` rows with different hold
keys) ⇒ two re-confirms; a `nothing-ungated held:true` row whose `held_until` has passed ⇒ a subject nudge (the ladder),
not a re-confirm. All red today (no function); (15)-(18) are also red against the first-draft spec.

### 7.6 cc-decide, cc-memory-search, anti-deference, operator-readout

| Suite | Test | Assertion | Red without |
|---|---|---|---|
| `tests/cc-decide.bats` | `open --help` | rc 0; prints `HARD-BLOCK` and "status-quo course" | "unknown arg --help" (TX:4250) |
| same | hint ordering | `CLAUDE_CODE_SESSION_ID` set; `CC_MEMORY_SEARCH_BIN` stub returns `eb3dbe1e5e94` at ratio 2.9; open class C | stdout is exactly the id (one line); the last stderr line names `eb3dbe1e5e94` and `default fired`; the line before it is the reserved-set reminder; `… 2>&1 \| tail -3` shows reminder, ruling, id | no hint |
| same | gates | no session id; `CC_DECIDE_HINTS=0`; the `.off` file; class A; a re-open of an existing packet; **session id set with `BATS_TEST_FILENAME` set and no `CC_DECIDE_HINTS=1`** | stub call counter 0 | (mutant: drop the session gate ⇒ the existing 62 sites see stderr; mutant: drop the bats predicate ⇒ the last case red, the nine non-unsetting suites' shape) |
| same | **ceiling required** | `CLAUDE_CODE_SESSION_ID` set; `open --class C` with conviction, receipt, two options and no `--ceiling` | rc 2; stdout empty; stderr's last lines carry `--class B`, `--default`, `--deadline` and the `--ceiling` set; no packet file | red today (the open succeeds) |
| same | ceiling values | `--ceiling bogus` ⇒ rc 2; `--ceiling money` on class B ⇒ rc 2; `--ceiling program` without `--project` ⇒ rc 2; `--ceiling self-mod` with e869's text ⇒ rc 0, `.ceiling=="self-mod"` in `list --json`, stderr names gate-classify's `B`; `--ceiling self-mod` with "edit settings.json in place" ⇒ no disagreement line; no session id ⇒ no ceiling needed (legacy callers); `CC_DECIDE_CEILING=0` and the `.off` file ⇒ not required | — |
| same | id stability | the same open with and without `--ceiling` | one id; the re-open is the existing early return (`mk_id` keys on class, session and text) | — (mutant: ceiling in `mk_id` ⇒ red) |
| `tests/research-kit-gate.bats` | program packets | `gate.sh file-packet --class C` with a session id set | the open carries `--ceiling program` and succeeds | red against the ceiling requirement without the `gate_sweep.py` change |
| `tests/cc-do.bats`, `tests/research-kit-gate.bats` | existing class-C sites | suite run with `CLAUDE_CODE_SESSION_ID` exported | green, because `setup()` now unsets the session ids | red without that `setup()` line once the requirement lands |
| same | fail open | stub absent; stub sleeping 10 s with `CC_DECIDE_HINT_TIMEOUT_S=1` | rc 0, id on stdout, no hint, wall < 5 s | — |
| same | existing suite | all 76 tests | green | regression |
| `tests/cc-memory-search.bats` | `--decisions` | fixture store: an expired-actioned class-B "Keep looping until a round confirms nothing…" (default "keep looping until dry"), an open C, a superseded and a string-options packet; query "Should the loop stop now" | top-1 is the class-B id, ratio ≥ 1.5 in `--json`; open packets never returned; no jq error; works with no `projects/` dir under the fixture HOME | unknown flag |
| `tests/anti-deference-nudge.bats` | new ⛔ readout clause | F1 lines 1-2 with the `Not gated by it` clause on line 2 | `no-tell` | guards TELLS/CATEGORY |
| same | `open_packet_B` env | stub decide records env | `CC_DECIDE_HINTS=0` | absent |
| `tests/operator-readout.bats` | loop 🔧 parts | stub `RUNG=🔧 LOOP_OPEN=1 HELD=0` | state contains `loop scope open` | renderer drops the cause |
| same | ⛔ held clause | stub READOUT with `Held by this session:` | rendered verbatim | control |

### 7.7 Rules and grant code

`tests/lead-keeps-working-rules.bats` (new; names `CLAUDE.rules.slim.10-session-close.md`, `CLAUDE.global.slim.md` and
`CLAUDE.global.md` literally so `scripts/gate-select.sh` selects it; pattern `tests/close-research-pending-rules.bats:11-43`;
normalise G's wrapping with `tr -s '[:space:]' ' '`):

- each clause present in R (or S) **and** in G: `keep driving every in-scope item it does not gate`; `a question that would
  change the frozen scope gates none of it`; `Only ⛔ when every remaining in-scope item waits on an open decision` (G:
  `EVERY`, case-insensitive); `the gated act itself waits` (G: `The gated act itself still waits`); `dod-persist.sh
  done`; `loop until <condition>`; `--default-effect no-change --project`; `--ceiling self-mod|money|permission|credential|g2`;
  `look for a ruling`; `--decisions`; `Re-ask only`; `is never a step`; `Not gated by it`; grant tokens in R and G:
  `xvendor-review.sh`, `codex exec -s read-only`, `git archive`, `80%`, `model-config.yaml`, `a247b7288149`,
  `d610f8473106`; R only: `dod-persist.sh set "<that line>"`, `Within a turn, keep working rather than stopping on 🔧`,
  `strand nowcast`, `which understates spend`, `reads confined to that export or no run`; G only: `dod-persist.sh hold`,
  `OPENAI_API_KEY`, `uncertified means unrouted` (case-insensitive), the verbatim 18:11:47Z quote, `Antigravity`,
  `29d62f1ad390`, `canary`. (Measured on the first draft: all present after the change; all absent before except
  `model-config.yaml`, which G already contains elsewhere, so that assertion greps inside the grants section only. The
  revision's new tokens were checked in the same in-memory pass, §9.3 M15.)
- negatives: R lacks `Stop and ask, overriding auto-continue`, `filing is what makes it the`, `and only on 🔧`, `a real
  value fork`, `` (`dod-persist.sh` captures it) ``, `no status quo`; G lacks `no status quo`; no file of R/S/G contains a
  line matching `Scope \(frozen\): *(loop|repeat|iterate|keep)`.
- budget: `python3 -I hooks/lib/instruction_budget.py measure` of S + R ≤ 58,790 (the measured pre-change sum).

`tests/xvendor-review.bats` (new; stub `codex` and `git` on a fixture PATH; rollout fixtures under `CODEX_HOME`):
79% runs; 80% rc 5; a rollout without `rate_limits` rc 4; no rollouts ⇒ runs with a note; the 10080-minute window is
chosen over a shorter one; the stub sees no `OPENAI_API_KEY` and `-s read-only` in argv; the export lacks an
uncommitted file and the `.claude/xvendor-review.exclude` paths; a non-ChatGPT `codex login status` refuses; the temp
dir is gone afterwards. **Read confinement:** the `codex` stub tries to `cat` a fixture `$HOME/secret` and the run's
output lacks its token; the stub sees `HOME` and `CODEX_HOME` equal to the temp dir holding only `auth.json`; a
confinement stub that lets the canary through ⇒ rc 6 and `codex` never invoked. **Meter:** a reading at 95% whose
`resets_at` is in the past ⇒ runs with a "window expired" note; a held lock dir ⇒ the second call waits, then reads
the meter again. All red today (no script).

### 7.8 Post-land content verification of the deployed copies

After `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` (never `--force`):

1. `diff -q CLAUDE.rules.slim.10-session-close.md ~/.claude/rules/10-session-close.md`,
   `diff -q CLAUDE.global.slim.md ~/.claude/CLAUDE.md` and `cmp CLAUDE.global.md ~/.claude/CLAUDE.full.md` are silent;
   `grep -c 'Standing operator grants' ~/.claude/rules/10-session-close.md` = 1.
2. `git -C ~/Development/claude-infrastructure merge-base --is-ancestor <landed sha> HEAD`;
   `readlink ~/.claude/hooks/session-continue.sh` resolves into the checkout and `grep -c 'SCOPE FLOOR'` on it ≥ 1;
   `ls -la ~/.claude/hooks/lib/inflight.sh ~/.claude/hooks/lib/loop-scope.sh ~/.claude/scripts/xvendor-review.sh` are links.
3. `scripts/deploy-parity-assert.sh` reports no `CLAUDEMD` drift (`:1350-1372`).
4. Live read: in `~/Development/agent-context-sync`, `WRAP_SESSION_ID=666022fd-ed3e-4e72-b293-7caae899d585
   ~/.claude/scripts/wrap-ledger.sh --machine | grep -E '^(LOOP_SRC|LOOP_OPEN|SCOPE_UNGATED|RUNG)='` prints the new
   fields (expected `LOOP_SRC=own` or `superseded`, depending on whether the successor has stopped since).
5. The supervisor restarted on the new sha (`supervisor_self_restart` IDL row), and the next 24 h of IDL show
   `scope-floor-*` rows only for sessions with an own loop capture (`grep '"reason":"scope-floor' idl.jsonl | jq -r .sid
   | sort -u` ⊆ the census of §8.1 step 0).

---

## 8. Implementation plan (Phase 2)

All of it is self-modification of the shared layer, authorized by `d610f8473106`. It touches about 31 files, far over the
6-file line, so it runs as an Agent Team with disjoint file ownership. cc-bats admits only 2 live bats roots
(`bin/cc-bats:514`), so verification, not authoring, is the long pole: about 1,300 existing tests in the touched suites
at about 6 s each under load ≈ 2.2 h serial (estimated, crit/D4--constraints-feasibility.md §4).

### 8.1 Steps

| Step | Owner | Files | Depends on | LOC (estimated from the sketches above) |
|---|---|---|---|---|
| 0 | lead | read-only census: own loop captures and their live pids (today: only `666022fd`, §9.3 M2); R/S/G budget baseline; `codex exec --help` flags (`-C`, `--skip-git-repo-check` already measured, §9.3 M23); **which read confinement works**: `codex sandbox` with a readable-roots state or permission profile, then the outer `sandbox-exec` fallback, each proven by a canary under the real `$HOME` that must be unreadable, with no model call; `xverify.py` meter logic | — | 0 |
| 1 | T1 ledger | `scripts/wrap-ledger.sh`, `hooks/lib/loop-scope.sh` (new), `scripts/tsv-pad-lint.sh` (the `:144` exemption text, §3.1 (iii)), `tests/wrap-ledger.bats`, `tests/wrap-ledger-memo.bats` | — (defines the field contract in §3.1 (viii)) | ~210 code, ~360 test |
| 2 | T2 store | `hooks/dod-persist.sh`, `tests/dod-persist.bats` | loop-scope lib (shared with T1; T1 owns it); the `.ceiling` field (step 5) for the hold tiers, stubbed until it lands | ~140 code, ~220 test |
| 3 | T3 floor | `hooks/session-continue.sh`, `hooks/lib/inflight.sh` (new), `tests/scope-floor.bats` (new), `tests/session-continue.bats` | the field contract and the `capture-loop` CLI (stubs until 1-2 land) | ~330 code, ~560 test |
| 4 | T4 supervisor | `scripts/lead-supervisor.sh`, `scripts/supervisor-e2e.sh`, `tests/lead-supervisor.bats` | the floor's IDL row contract (§3.4 `sf_log`) | ~190 code, ~290 test |
| 5 | T5 decide | `bin/cc-decide` (hints and `--ceiling`), `bin/cc-memory-search`, `hooks/anti-deference-nudge.sh`, `scripts/research-kit/lib/gate_sweep.py` (`--ceiling program`), `tests/cc-decide.bats`, `tests/cc-memory-search.bats`, `tests/anti-deference-nudge.bats`, `tests/research-kit-gate.bats` and `tests/cc-do.bats` (`setup()` unsets the session ids) | — | ~210 code, ~260 test |
| 6 | T6 text | R, S, G (§3.7 blocks verbatim), `hooks/dispatch-assert.sh`, `hooks/lib/why-tier.sh`, `commands/wrap.md`, `commands/handoff.md`, `hooks/operator-readout.sh`, `tests/lead-keeps-working-rules.bats` (new), `tests/operator-readout.bats` | — | ~30 lines of R/S, ~130 of G, ~20 code, ~190 test |
| 7 | T7 grant code | `scripts/xvendor-review.sh` (new), `tests/xvendor-review.bats` (new) | step 0's confinement finding | ~190 code, ~220 test |
| 8 | lead | integration: run every selected suite by hand (`1..N`), the mutant per guard, the B13 replay (S1-S3b + L1 + P2b + T41), `scripts/test-stub-lint.sh`, `scripts/ship-land.sh --precheck --working`; land; converge; §7.8 checks; §8.4 records | 1-7 | — |
| 9 | lead | the held-out F1 re-gate the operator ruled on 2026-10-04 for "the next slim edit" (`docs/plans/INSTRUCTION_BUDGET.md:127`; harness `docs/research/token-efficiency-2026-09-23/eval/harness/`, `build-arms.sh --dry-run` first): ~100 runs ≈ 3-10 weekly pp across 3 accounts (`:125`); run under the capacity rules, never asked again | 8 (the converged slim text is what it measures) | 0 code |
| 10 | follow-on, filed | a plan-section-scoped box count for non-loop scopes (§3.0), validated against the 80 plan-naming frozen lines before it may block; completion-assert's ⛔ fact clause and its `:1757` wording (§3.8) | 8 | — |

**Parallelism.** Steps 1, 2, 5, 6 and 7 are independent and start together; 3 and 4 start in parallel against stubs and
the contracts written in this document, and integrate once 1-3 have landed. **Land order**, each step safe alone because
every consumer reads an absent field as today: 1+2 (fields and verbs; only effect: loop sessions read 🔧 instead of ✅),
then 3, then 4; 5, 6 and 7 at any time, except that the hold tiers (2) read `.ceiling`, so 5 lands with or before 2's
tier code (absent `.ceiling` folds to "no ceiling", which only makes a hold stricter). Total ≈ 1,450 code/text lines +
≈ 2,100 test lines (estimated, sum of the rows).

### 8.2 Kill switches to verify before landing each hook step

`CC_SCOPE_FLOOR=0` / `~/.claude/state/scope-floor.off` (step 3), `CC_MECH_BLOCKED=0` / `mech-blocked.off` (3),
`WRAP_LOOP_SCOPE=off` / `loop-scope.off` (1), `CC_SUP_SUBJECT_NUDGE=0|shadow` / `subject-nudge.off|.shadow` (4),
`CC_DECIDE_HINTS=0` / `decide-hints.off` (5), `CC_DECIDE_CEILING=0` / `decide-ceiling.off` (5). Each has a test in §7.

### 8.3 Standing grant wording, verbatim

Always-loaded (R-19, `CLAUDE.rules.slim.10-session-close.md`, before "### Asserting done"):

> Standing operator grants (record and the operator's words: `~/.claude/CLAUDE.full.md`, same section); an act inside one needs no ask and no packet:
> - Cross-vendor review (operator, 2026-10-24, `d610f8473106`; plan bought in `a247b7288149`): in any repo, unasked, add non-Claude reviewers beside your Claude review via `~/.claude/scripts/xvendor-review.sh` (Codex plan, `codex exec -s read-only` on a `git archive` export of committed code, reads confined to that export or no run, stops at 80% of the weekly meter, never the paid API). Still ask for personal or customer data or a repo-listed escalation surface. A permission refusal is the operator's one pending allow rule: continue Claude-only, never re-ask. Routes no `model-config.yaml` slot.

The full record is G-11 (§3.7.3), carrying the operator's 18:11:47Z words verbatim (TX:4488).

### 8.4 Record entries (Phase 2 writes them after the land; nothing here was run)

1. **Class-A grant record** (no `--conviction`: `bin/cc-decide` refuses N > 90 on any class that passes one,
   `:221-228`), then actioned so it is an answered packet the `--decisions` search returns:
   ```
   cc-decide open --class A --project claude-infrastructure --session-sid "$CLAUDE_CODE_SESSION_ID" \
     --what "Standing grant recorded: in any repo a session may add non-Claude reviewers beside its Claude review through the ChatGPT Codex plan (cross-vendor review of git-archive exports of committed code, codex exec -s read-only via ~/.claude/scripts/xvendor-review.sh, no new call at 80% of the weekly meter, never the pay-per-token API), with no per-repo ask and no packet" \
     --recommendation "act under the grant; ask only for personal data, customer data or a repo-listed escalation surface" \
     --route-around "builds on a247b7288149 (the Codex plan bought for cross-vendor review: 'Upgraded to 100. Continue.') and ruling d610f8473106; operator's words 2026-10-24T18:11:47Z"
   cc-decide action <that id> --evidence "landed <sha>: CLAUDE.rules.slim.10-session-close.md § Standing operator grants and CLAUDE.global.md § Standing operator grants; builds on a247b7288149; ruled d610f8473106"
   ```
2. **Class-A implementation record** for `d610f8473106` itself, same shape: `--what "Ruling d610f8473106 implemented: a lead
   keeps driving in-scope work an open decision does not gate (scope floor, loop-scope capture, class-B routing, ruling
   search, subject nudge)"`, then `action … --evidence "landed <shas>; design docs/research/lead-keeps-working-2026-10-24.md"`.
3. **One operator step, not a question** (the grant's prerequisite; a settings change only the operator may make).
   The operator has already ruled on both halves: `a247b7288149` bought the Codex plan for exactly this review
   ("Upgraded to 100. Continue."), and `29d62f1ad390` (class C, actioned 2026-10-21) records "Permission prompts are
   virtually always a yes, so improve the allowlist/config so past command usage is pattern-recognized and allowed"
   (measured `jq` on both packets). A yes/no packet would re-ask a ruled question, the incident's own failure (goal (c)).
   So Phase 2 files the act, which carries no conviction (R:184):
   ```
   cc-backlog needs "add an autoMode.environment line or allow rule for ~/.claude/scripts/xvendor-review.sh, so the cross-vendor review grant runs unattended (ruled: 29d62f1ad390 allowlist; a247b7288149 Codex plan; d610f8473106 grant); until then sessions review Claude-only" --class needs-human
   ```
   It gates only the Codex lane and makes the implementer's ledger 👤, not ⛔, so it pauses nothing else. (The first
   draft filed it as a class-C yes/no packet; crit/D1-rule-text--constraints-feasibility.md D-1 had pointed at
   `29d62f1ad390`.)

### 8.5 Operator questions this design leaves open (none blocks Phase 2)

1. *(Withdrawn in this revision.)* The first draft listed the instruction-budget re-gate here as a question to file
   class B with default "defer again". The operator already ruled on 2026-10-04 to run it at the next slim edit
   (`docs/plans/INSTRUCTION_BUDGET.md:127`), and this is that edit, so it is §8.1 step 9, not a question.
2. Should the cross-vendor grant include Google's Antigravity CLI (`agy`)? The agentsync memory note includes it
   (maps/rules-text.md §5.5); the ruling's goal (d) names only the Codex plan.
3. A non-converging loop (B13's ~80 findings a round for 24 rounds, TX:4254) runs as long as its scope says. Should a
   loop scope carry a default round or meter cap? This design leaves the scope authoritative (crit/D1--loop-false-block.md §1.3).

---

## 9. Open risks, and what was not measured

### 9.1 Risks

1. **Compliance after a block is not mechanical.** The floor's fire is deterministic; what the forced turn does is not.
   This lead complied 2 of 2 times with blocks that matched its plan and 0 of 4 times with blocks that contradicted it
   (measured over the 16 Stop-hook feedback records in TX, crit/D4--incident-replay.md §2). Its one quick switch came after
   an operator rebuke, not a hook (TX:4488 → TX:4495). Estimated compliance with the first block ≈ 0.5-0.8 (critics'
   judgment ranges); the design's answer is repetition with bounds (3 floor fires, 3 wakes, then the operator digest),
   not certainty.
2. **A dishonest hold.** The first draft's version of this risk was the design's blocker: any open own class-C id was
   accepted, the block text names the verb, and this lead complied with 0 of 4 blocks that contradicted its plan, so
   one `hold e869fac7eb34 …` would have ended the drive for good. Now a hold needs a declared operator-only ceiling or a
   C route from gate-classify, and only both make it durable (§3.2). Both B13 packets would be refused (§9.3 M16). What
   remains is a lead that files a judgment call class C with a **false** `--ceiling`: the open prints gate-classify's
   disagreement, the hold is lapsing (one floor fire and one supervisor re-confirm per 6 h), it lapses when answered,
   and it is shown on every ⛔ close. A text that routes C but is a judgment call (the router is over-inclusive on C by
   design, `scripts/gate-classify.sh:11-15`) with a false ceiling gets a durable hold; that residual is the honest
   mis-declaration maps/cc-decide.md §8 names, and no field can detect it.
3. **`done` and re-scope abuse.** One verb ends a loop; it is durable, stamped and visible in the store and in the
   SessionStart injection, but not prevented. An operator message that pastes another scope at line start re-scopes a
   loop session (C1 `captured-rescope`); rare, visible.
4. **Blind spots of "in flight".** Peers reached by `cc-notify` without custody, or work in another cwd with no custody
   row, are invisible; the cost is ≤1 push per window per key. Background Agent subagents are no longer a blind spot
   (§3.3). An `inflight` abstain on a time-bounded leg no longer vetoes the nudge for good: the supervisor accepts such
   a row once it is older than the leg's freshness plus `STALL_S` (§3.5); a custody leg still suppresses it, and
   custody-deathwatch is the wake for a dead lane.
5. **Successor hold.** A successor whose predecessor's genuine gate covers every round must `cc-decide recheck` it before
   `hold`; until then it gets the first fire. `/handoff` now tells the predecessor to name its open class-C ids in the
   brief, with the command that lists them (§3.8); the first draft left that only in G-04, which no session loads. A
   recycle that skips `/handoff` still drops the ids; the cost is one floor fire.
6. **IDL rotation** can hide the oracle row; the nudge then reads the newest rotated archive or fails closed.
7. **Rule-load skew**: sessions started before converge keep the old R:217 until they recycle.
8. **Exposure growth**: the loop floor's population is B13's lineage today; it grows as leads write `loop until` scopes,
   which is the intent, and as follow-on briefs quote the incident (verb-first and line-anchored matching keeps quotes out;
   §7 L12, P6).
9. **The non-loop residual.** A ⛔ (or ✅) idle over an unfinished non-loop frozen scope is not caught by any mechanism
   here (§3.0 row (a)); goals (a) and (e) are deterministic only for loop scopes. Closing it needs a scope-aware box
   count that does not exist yet (§8.1 step 10).
10. **The ceiling refusal's false-block surface.** A session filing a genuine gate without `--ceiling` is refused once,
    with the flag printed; a caller that opens class C from a session and is not updated in step 5 breaks until it
    passes one. The producers were enumerated (sessions, `gate_sweep.py`; `ship-land.sh` bypasses `open`,
    maps/cc-decide.md §7), and the kill switch reverts it without a settings edit.

### 9.2 Not measured

- The floor's p95 cost on the no-sentinel path under load (it adds `turn_scan` over 6 turns, the bg/agent-task scan,
  `ce_size`'s one `ps` and `ce_burn`'s `awk`, and one `grep -c`, only on relevant rungs; the measured headroom at F1-F3 was 1,694, 1,268 and 2,098 ms against a 10 s timeout, TX:4440/4461/4485,
  crit/D4--incident-replay.md #11). Measure before landing step 3.
- The `OPHOLD_RE` false-match rate on ordinary operator prompts (a false match only abstains).
- Compliance with a scope-floor block: no such block has ever fired.
- Whether the orphan watcher of 08:34:49Z survived (maps/wake-path.md §4.3); the 1 h re-check makes either case reach a
  socket wake by ~10:11Z.
- The ruling hint's precision beyond the 25 hand-read flags (maps/ruling-discovery.md §4.2).
- Which read-confinement mechanism works for `codex exec` (its readable roots, or an outer `sandbox-exec` that codex's
  own seatbelt survives); step 0 proves one with a canary, and until then the wrapper refuses every run. (Whether
  `codex exec` accepts `-C` and `--skip-git-repo-check` is now measured: it does, §9.3 M23.)
- Whether a nudge-woken session complies better than a floor-blocked one; the B13 replay assumes neither.
- The precision of gate-classify on the hold path beyond the 48 open class-C packets (§9.3 M16); its known false
  negative (`a247b7288149`) is handled by the lapsing tier.

### 9.3 Measurements new in this synthesis (all read-only)

| # | Fact | Command |
|---|---|---|
| M1 | Strict extractor (newest human-origin user line, line-anchored `^[[:space:]>*-]*Scope \(frozen\):`, verb-first loop) over 1,648 top-level transcripts > 20 KB modified in 14 days on all five accounts: 8 sessions yield a loop (`1e7dc0e1 502bd860 666022fd 7046d8d0 98214164 b351c528 e739e5b5 f1997ec3`), all agent-context-sync B13 lineage; 0 false positives | `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl' -mtime -14 -size +20k` → `xargs grep -lE` prefilter → per file `jq` (user, not isMeta, origin human or absent, no tool_result) `\| grep -E` anchored `\| tail -1 \| grep -cE` verb-first |
| M2 | DoD store: 362 frozen lines, 361 at column 0; the verb-first pattern matches 1 (B13's, `session=666022fd`) | `cat ~/.claude/autonomy/dod/*.md \| grep -c '^Scope (frozen):'`; `… \| sed … \| grep -cE` |
| M3 | 691 packets; open: 48 class C across 23 sessions, 10 class B; none of the open C sits in the only loop-captured session (its C packets are all actioned) | `jq` over `~/.claude/autonomy/decisions/*.json` |
| M4 | `OPHOLD_RE` matches 14 of 14 hold phrasings (the 10 of crit/D2--loop-false-block.md §2.4 and 4 of crit/D2--incident-replay.md D7) and neither TX:4114 nor TX:4163 | `/usr/bin/grep -iqE` per phrase; `sed -n 'Np' TX \| jq -r … \| /usr/bin/grep -iqE` |
| M5 | TX:14 is `type:user`, `origin.kind:human`, string content; its scope is line 5, line-anchored and verb-first (count 1) | `sed -n 14p TX \| jq`; `grep -cE` |
| M6 | Instruction files arrive as `type:"attachment"` (TX:27), so rule text never reaches capture; TX:4728 is `origin.kind:task-notification`; TX:4910 is `isMeta:true` | `jq` per `grep -n 'Scope (frozen)' TX` hit |
| M7 | Stop order: session-continue 4, anti-deference 5, completion-assert 6, dispatch-assert 7, boundary-handoff 8, operator-readout 9; `StopFailure` → `stop-failure-marker.sh` | `jq -r '.hooks.Stop[]?.hooks[]?'` and `.hooks.StopFailure` on `~/.claude/settings.json` |
| M8 | `defaultMode: auto`; `autoMode` keys `environment`, `soft_deny`; 0 allow rules matching `codex\|xverify\|xvendor` | `jq` on `~/.claude/settings.json` |
| M9 | Budget baseline: S 28,503, R 30,287 | `python3 -I hooks/lib/instruction_budget.py measure CLAUDE.global.slim.md CLAUDE.rules.slim.10-session-close.md` |
| M10 | Background tasks: 92 `run_in_background:true` tool uses in TX; TX:4435 `Command running in background with ID: bpctefji1` (a `cc-await-ping` watcher, TX:4434); TX:4428 `<task-id>b5yelhdfm</task-id> … <status>completed</status>` | `grep -c`; `sed -n … \| jq` |
| M11 | Custody for B13's cwd: pane 134 `fire-lead-idle-fix` open 20:42:58Z; pane 271 fired round-27 lanes 21:18-21:24Z | `tail -6 ~/.claude/autonomy/custody/cb2bdf30d6a495298cb26b459fd886e4.jsonl \| jq` |
| M12 | No `666022fd….HANDOFF.json` beside its transcript (so a handed-off marker cannot be the supersession signal) | `ls` |
| M13 | No test greps any rule phrase this design deletes | `grep -rlF -- "<phrase>" tests/` per phrase |
| M14 | Live background tasks at F1/F2/F3 (`head -n 4437\|4458\|4476 TX`): started ids 89/90/91; with finished ids taken from `<task-id>` in any record, live = {`bpctefji1`} / {`b5rshfkra`} / {} — watchers only, so the floor fires at all three; with finished ids taken from user-record `<task-notification>` text only, 7 live at each close, including round 23's `scripts/ship-land.sh --lock /tmp/b13-r23-land.lock` (`b0agqk1e4`, output file last written 2026-10-22 20:17) | `grep -oE 'Command running in background with ID: [A-Za-z0-9]+'`, `grep -oE '<task-id>[A-Za-z0-9]+</task-id>'`, `comm -23`; the user-only variant by `jq` over user records; `ls -la` on the output file |
| M15 | Budget of the §3.7 blocks, re-run on this revision: S + R 58,790 → 58,761 (R 30,287 → 30,426, S 28,503 → 28,335, G 116,486 → 129,348); added 1,919, cut 1,948; every `old` found exactly once (27 R/S blocks, 11 G blocks); no edited file contains a `Scope (frozen):` loop line; every §7.7 positive pin present after (R or S, and G with whitespace normalised), every negative absent. (First draft: 58,767; all §7.7 tokens absent before except `model-config.yaml` in G) | `python3 -I -B` parsing this file's `old:`/`new:` fenced blocks, applying them in memory, `instruction_budget.parse().units`/`jslen()` |
| M16 | gate-classify on the packets' `what_plain`: `e869fac7eb34` → B, `290215743799` → B, `a247b7288149` → B (a money path: false negative), `29d62f1ad390` → B; over the 48 open class-C packets, 15 → C and 33 → B. The router is pure text matching with no write | `bash scripts/gate-classify.sh "$(jq -r .what_plain <pkt>)"` per packet; loop over `~/.claude/autonomy/decisions/*.json` selecting `.class=="C" and .status=="open"`, `cut -c1 \| sort \| uniq -c`; `grep -nE '>>\|tee\|log_idl\|mktemp' scripts/gate-classify.sh` (no hit outside comments) |
| M17 | DoD store: 78 files (9 repo-keyed), 0 unchecked `- [ ]` lines, 38 checked; 367 `## ` headers: 361 `(manual-set)`, 1 `(manual-set — recycle handoff …)`, 1 `(goal-set)`, **0 `PreCompact`**, 4 hand-written section headers; 80 frozen lines name a `docs/plans/` file | `awk` over `~/.claude/autonomy/dod/*.md` counting `^[ \t]*[-*][ \t]+\[[ \t]\]` and `\[[xX]\]`; `grep -h '^## ' … \| grep -oE '\((manual-set[^)]*\|goal-set\|PreCompact[^)]*\|stop-capture\|manual-hold\|manual-done)\)' \| sort \| uniq -c`; `grep '^Scope (frozen):' \| grep -c 'docs/plans/'`; `ls \| grep -c '^repo-'` |
| M18 | Capture recall of assistant-stated scopes: of 1,652 top-level transcripts > 20 KB modified in 14 days (roots `~/.claude`, `-secondary`, `-tertiary`, `-quaternary`), 1,272 contain `Scope (frozen):`; 33 sessions state a line-anchored scope line in assistant text outside a code fence; **0** of those lines is a verb-first loop (B13's own transcript has no assistant text scope line; its 5 hits are `tool_use` inputs) | `find … -maxdepth 3 -path '*/projects/*' -name '*.jsonl' -mtime -14 -size +20k` → `xargs grep -l 'Scope (frozen):'` → per file `grep -a 'Scope (frozen):' \| jq -r 'select(.type=="assistant") \| .message.content[]? \| select(.type=="text") \| .text' \| awk` (fence toggle, `^[[:space:]>*_-]*Scope \(frozen\):`) → prefix strip → `grep -ciE` the verb-first pattern |
| M19 | Background Agent subagents: `Async agent launched` appears in 192 of 1,681 top-level transcripts modified in 14 days (same roots); in `d2aecafb-e959-…jsonl` agent `a8e552e552430265c` finishes as `<task-id>a8e552e552430265c</task-id>` (3 hits) and its transcript is `d2aecafb-…/subagents/agent-a8e552e552430265c.jsonl` | `find … -mtime -14` → `xargs grep -l 'Async agent launched' \| wc -l`; `/usr/bin/grep -o`/`-c` on the file; `ls …/subagents` |
| M20 | B13 watchers: 73 `run_in_background` Bash commands contain `cc-await-ping`; the first word of every one is `/Users/chrisren/.claude/bin/cc-await-ping` (0 bare); TX:4434 is `/Users/chrisren/.claude/bin/cc-await-ping 134 --timeout 3300 --interval 15` | `grep -a '"run_in_background":true' TX \| jq -r '… select(.name=="Bash" and .input.run_in_background==true) \| .input.command' \| grep cc-await-ping \| awk '{print $1}' \| sort \| uniq -c`; `sed -n 4434p TX \| jq` |
| M21 | `wake-floor-mechanical-arm` abstains in production: 19 rows in IDL (0 for 666022fd); session-continue reasons by count: ship-floor-not-mine 295, ship-floor-assignee 132, mechanical-assignee 132, ship-floor-latched 36, cli-clear 26, continue 23, cli-set 22, wake-floor-mechanical-arm 19 | `grep -c '"reason":"wake-floor-mechanical-arm"' ~/.claude/autonomy/idl.jsonl`; `grep '"hook":"session-continue"' … \| grep -oE '"reason":"[^"]*"' \| sort \| uniq -c \| sort -rn` |
| M22 | Bats suites calling `cc-decide open`: unset of `CLAUDE_CODE_SESSION_ID` per suite — cc-decide 1, operator-readout 1, operator-readout-forks 1, wrap-ledger 3, wrap-ledger-memo 1; **0** in autonomy-sweep, cc-digest, cc-do, cc-unattended-ask-guard, dispatch-assert, lr-reset-poller, research-kit-gate, research-program-briefs, ship-land. Class-C opens among the 0-unset suites: cc-do 5 (`:183`, `:198`, `:213`, `:243`, `:436`), research-kit-gate 1 (`:875`). No production code opens class C except through `gate_sweep.py` (`file-packet --class B\|C`) | `grep -lE 'cc-decide[^\|]* open\|DECIDE[^ ]* open\|decide open' tests/*.bats`, then `grep -cE 'unset[^#]*CLAUDE_CODE_SESSION_ID'` and `grep -nE -- '--class C'` per file; `grep -rnE 'cc-decide"?[^\|]{0,40} open' scripts bin hooks` |
| M23 | `codex-cli 0.147.0`; `codex exec --help` lists `-C, --cd <DIR>` and `--skip-git-repo-check`; `codex sandbox --help` lists `--sandbox-state-readable-root` and `-P, --permission-profile`; `/usr/bin/sandbox-exec` exists; newest rollout's `rate_limits.primary` = `{used_percent: 0.0, window_minutes: 10080, resets_at: 1793413796}` (now 1792885341) | `codex --version`; `codex exec --help \| grep`; `codex sandbox --help`; `command -v sandbox-exec`; `grep -a '"rate_limits"' <newest rollout> \| tail -1 \| jq`; `date +%s` |
| M24 | `29d62f1ad390`: class C, actioned 2026-10-21T04:56:13Z, evidence "…Permission prompts are virtually always a yes, so improve the allowlist/config…"; `docs/plans/INSTRUCTION_BUDGET.md:127` "2026-10-04: the operator ruled to defer the run until the next slim edit"; `b4780d7bb60e` class B, open, options stop / keep looping, default "keep running rounds as scoped"; B13's store line (`repo-7030c1939664b2e4.md:27`) names it | `jq` on the packets; `sed -n 118,129p`; `sed -n 27p … \| grep -oE '[0-9a-f]{12}'` |

### 9.4 The completeness critic's gaps: where each was fixed, or why it was rebutted

Each gap was checked against the code before the doc changed; the evidence for every fix is in the section named.

| # | Gap (critic's severity) | Disposition | Where |
|---|---|---|---|
| 1 | `hold` is an unbounded escape for the B13 lead (blocker) | **Fixed.** Hold needs a declared ceiling or a C route; one signal ⇒ lapsing (6 h); neither ⇒ refused. Both B13 packets are refused (M16). Replay hold row; P2b, P2c, L21, S11b, T41 (19) | §2, §3.1 (iv), §3.2, §3.5, §9.1 risk 2 |
| 2 | Goal (b) has no deterministic mechanism (major) | **Fixed.** A session's class-C open requires `--ceiling`; gate-classify's disagreement is printed, never refused on; `gate_sweep.py` passes `program`; the two non-unsetting suites gain an unset | §3.6 item 2b, §7.6 |
| 3 | `OWN_REMAINDER` is dead in production (major) | **Fixed by stating the residual** (the critic's second option): goals (a)/(e) are deterministic for loop scopes only; plan-file box counting rejected for false-block risk and filed as a measured follow-on; L22 pins the residual | §1, §3.0, §3.1 (ii), §4.2, §8.1 step 10, §9.1 risk 9 |
| 4 | The wake floor's abstain row masks the supervisor oracle (major) | **Fixed.** Oracle = newest `scope-floor*` row, voided only by a newer `continue`/`cli-set`/`fired` row; T41 (15) | §2 rows ~10:11, §3.5 |
| 5 | The nudge ladder overruns the 6 h GC horizon (major) | **Fixed.** 30 min / 1 h ladder; digest also on two not-woken sends or a horizon breach; T41 (16)-(17) | §2 row ~11:11, §3.5, §4.1 |
| 6 | Background Agent subagents are not "in flight" (major) | **Fixed.** `agentId` from `Async agent launched` joins the started set, with a `subagents/agent-<id>.jsonl` freshness leg; S8, S8b; §4.2 row | §3.3, §4.2 |
| 7 | The watcher exclusion misses absolute-path watchers (major) | **Fixed.** Basename of the first non-assignment, non-`timeout`/`env` word; S9 uses TX:4434 verbatim | §2 F1 row, §3.3, §7.3 |
| 8 | Context-high abstain covers three of five axes (major) | **Fixed.** All five axes via context-econ's read-only `ce_size`/`ce_burn`; S13 | §3.4 |
| 9 | No capture where no store file exists (major) | **Fixed.** `DOD=absent` with a SID ⇒ `LOOP_SRC=none`; L19, P9, S19b | §3.1 (ii), §3.4 |
| 10 | Capture misses a loop the lead restates itself (major) | **Fixed by rule, after measuring:** 0 assistant-stated column-0 loop lines in 1,272 transcripts (M18), so no new capture source; R-06 replaces R:26's false "(captures it)" with the `set` command | §3.2, §3.7 R-06, G-01 |
| 11 | An `inflight` row vetoes nudges forever (major) | **Fixed** for time-bounded legs (accepted after freshness + `STALL_S`); custody legs stay suppressed, custody-deathwatch wakes the originator; T41 (18) | §3.5, §9.1 risk 4 |
| 12 | Phase 2 re-asks ruled questions (major) | **Fixed.** Re-gate is step 9 per the 2026-10-04 ruling; the class-C allow-rule packet becomes a needs-human step citing `29d62f1ad390` and `a247b7288149` | §2, §5.3, §8.1, §8.4, §8.5, G-11 |
| 13 | "git-archive exports only" does not confine reads (major) | **Fixed in design, proven in step 0.** Temp `HOME`/`CODEX_HOME` with only `auth.json`, readable roots limited to the export, canary under the real `$HOME`, fail closed (rc 6); R-19/G-11 say "reads confined to that export or no run" | §3.9, R-19, G-11, §7.7, §9.2 |
| 14 | The reclose guard looks back one turn (minor) | **Fixed.** Walk back through other hooks' feedback turns (6 turns) plus a 600 s minimum gap; S3b, S3c | §3.4, §4.1 |
| 15 | C5 code and claims disagree (minor) | **Fixed by correcting the claims** (header and §4.2: one commit turn under any ⛔ with own dirt); M1b pins it | §3.4 (ii)-(iii), §4.1, §4.2 |
| 16 | R-17 and R-23 delete loaded-only text (minor) | **Fixed.** "Within a turn, keep working…" kept; the strand-nowcast trap kept, compressed; paid by R-09's refusal sentence, which tool output carries; budget re-measured (M15) | §3.7 R-09, R-17, R-23, §5.3, §7.7 |
| 17 | Test plan ignores the test-stub lint (minor) | **Fixed.** Every stub via `cc_stub`; `test-stub-lint.sh` in step 8 | §7 preamble, §8.1 |
| 18 | "Every bats suite unsets the session ids" is false (minor) | **Fixed.** Claim corrected (nine suites, M22); hints skip under bats unless `CC_DECIDE_HINTS=1` (the `bin/cc-notify:510` precedent) | §3.6 item 3, §7.6 |
| 19 | No headless abstain (minor) | **Fixed.** `scope-floor-headless` on wake_floor's predicate or an empty pane address; S13 | §3.4, §4.2 |
| 20 | A loop ended by an operator answer stays open (minor) | **Fixed.** A 12-hex id in the loop line naming an actioned or vetoed packet ⇒ `LOOP_SRC=answered`; L20; control C6 | §2 controls, §3.1 (ii), §4.2 |
| 21 | Successor hold depends on an unloaded instruction (minor) | **Fixed** in `commands/handoff.md` (the command that lists the ids), not in `handoff-fire.sh` | §3.8, §8.1 step 6, §9.1 risk 5 |
| 22 | Step file lists incomplete (minor) | **Fixed** for `tsv-pad-lint.sh` (step 1). completion-assert's ⛔ fact: **named follow-on** (§8.1 step 10). `close-shape.sh`: **rebutted**: its template's "no — <what remains + who drives it>" and verbatim READOUT line (`hooks/lib/close-shape.sh:179-180`) carry the new clause, and its only ⛔ mentions are comments (`:195`) | §3.1 (iii), §3.8 |
| 23 | R-13 widens class C beyond the reserve (minor) | **Fixed.** "A pick with no status quo" dropped everywhere; credential and G2 kept with their sources | §3.6 item 2, R-13, R-15, G-05, G-06, §3.8 |
| 24 | Smaller correctness gaps (minor) | **Fixed.** (i) shadow checked before the budget (S18); (ii) block text reworded (S1); (iii) `DOD_SCOPE` skips stop-capture blocks (L23); (iv) meter discounts a passed `resets_at` and takes a lock (§7.7) | §3.1 (i), §3.4, §3.9 |
| 25 | The loop 🔧 arm newly triggers completion-assert and anti-deference P0-4c (minor) | **Rebutted, with a control test.** completion-assert's done-claim contradiction is per field (`hooks/completion-assert.sh:1103-1144`) and its shape arms need ✅/👤 (`:1535`, `:1643`); anti-deference's contradiction is DIRTY ∨ UNLANDED ∨ REMAINDER and the rung is "not USED for the fire decision" (`hooks/anti-deference-nudge.sh:513-521`). Neither reads `LOOP_*` or RUNG=🔧, so neither fires on a loop 🔧 alone; §4.1 now records that, and S23 pins it | §4.1, §7.3 S23 |

---

## Appendix: Research record

Every file under `docs/research/lead-keeps-working-2026-10-24/`, one line each (line counts measured with `wc -l`).

**Maps** (9 read-only evidence mappers, committed at `b6b53ea89`):
- `maps/cc-decide.md` (305 lines): `bin/cc-decide` end to end, packet schema, class-B firing, the gate-classify router and its false negatives, a ruling search at open time, a "gates"/"ceiling" field's cost.
- `maps/incident-replay.md` (454 lines): what each Stop hook saw at the B13 idle closes F1-F3, the MUST/controls list every design is replayed against.
- `maps/legit-stops.md` (822 lines): when stopping on a decision is right; the 11 transcript-checked ⛔ idles and the 58-row class-C audit.
- `maps/rules-text.md` (240 lines): the always-loaded rule sentences that licensed the idle, and the instruction-budget baseline.
- `maps/ruling-discovery.md` (339 lines): how a session can find an existing ruling (memory, answered packets, purchases) before asking; the hint's measured ranking.
- `maps/stop-hooks.md` (447 lines): the Stop hooks that accepted the Blocked idle, line by line, and their spent budgets.
- `maps/test-infra.md` (657 lines): the test and land infrastructure a Phase-2 change must pass (hermeticity, mutants, stub lint, cc-bats limits).
- `maps/wake-path.md` (341 lines): how machinery, not the operator, can wake a stalled lead; cc-notify/cc-wake verdicts and the [30 min, 6 h] window.
- `maps/wrap-ledger.md` (374 lines): `scripts/wrap-ledger.sh` and the ⛔ rung; the DoD store's capture paths and consumers.

**Designs** (4 rival designs):
- `designs/D1-rule-text.md` (888 lines): rule text only; the source of the G twins, the class-B template and the budget method.
- `designs/D2-hook-enforcement.md` (1,150 lines): hook and ledger enforcement; the source of the own-session contract facts and held/done markers.
- `designs/D3-schema-first.md` (1,238 lines): a packet declares what it gates, and only "gates all" may stop a lead; the source of `open --help`, the context-high abstain and `xvendor-review.sh`.
- `designs/D4-minimal-sufficient.md` (790 lines): the minimal hybrid whose K1-K4 skeleton this synthesis builds on.

**Critiques** (12 adversarial critiques, one per design and lens):
- `critiques/D1-rule-text--constraints-feasibility.md` (323 lines): the grant cannot be acted on without an allow rule; points at ruling `29d62f1ad390`.
- `critiques/D1-rule-text--incident-replay.md` (277 lines): no D1 mechanism catches "No round 27 until you answer".
- `critiques/D1-rule-text--loop-false-block.md` (262 lines): D1's armed chain claims a bound it lacks in a non-converging loop.
- `critiques/D2-hook-enforcement--constraints-feasibility.md` (279 lines): the loop arm above 🚀, laundering via `cc-decide action`, hint stderr on existing call sites.
- `critiques/D2-hook-enforcement--incident-replay.md` (366 lines): a `Scope (held)` off-switch advertised in the readout; the supervisor oracle; the anachronistic grant credit.
- `critiques/D2-hook-enforcement--loop-false-block.md` (306 lines): single-slot latch re-armed A→B→A; quoted discharges parsed as contracts.
- `critiques/D3-schema-first--constraints-feasibility.md` (241 lines): legacy hard class-C packets launderable via `--supersedes` (D-2), intake capture drifting the shared DoD scope (D-3), a dead per-sweep nudge cap (D-4), size (D-14).
- `critiques/D3-schema-first--incident-replay.md` (131 lines): the measured re-Stop interval after a floor block (5-34 s, 12 of 12 ship-floor fires) and what the lead would re-file at 02:36Z.
- `critiques/D3-schema-first--loop-false-block.md` (289 lines): opposite blocks on one Stop (D-7), in-flight blind spots incl. background agents (D-11), a gameable `escalation` field (D-17).
- `critiques/D4-minimal-sufficient--constraints-feasibility.md` (302 lines): placement masking 🚀/👤, `{\}` under bash 3.2, goal (e) covered for loops only (D-14).
- `critiques/D4-minimal-sufficient--incident-replay.md` (254 lines): how this lead treats hook blocks (§2: it complied with blocks that matched its plan, not with those that contradicted it) and a budget key that ignores class-B packets.
- `critiques/D4-minimal-sufficient--loop-false-block.md` (369 lines): measured false fires on 2026-10-23 from background Bash; a loop ended by an operator answer stays open (§2.4).
