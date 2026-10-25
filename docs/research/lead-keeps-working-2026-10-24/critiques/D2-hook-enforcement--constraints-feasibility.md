# Critique: D2 (hook and ledger enforcement), lens: constraints and feasibility

Reviewer lens: hard constraints (no settings edit, no new hook registration, never weaken a gate),
instruction-budget headroom, deploy path, testability (RED without the change), and size.
Worktree `lead-idle-fix` at `b6b53ea89`. `D2:n` = line n of `designs/D2-hook-enforcement.md`.
Read-only review. Only this file was written.

**Verdict: sound with fixes. Score 6.5/10.** The design meets the two registration constraints
exactly. It keeps the ⛔ glyph and its order, and its rule edit really does shrink the
always-loaded tier (I re-measured it). But one ledger edit weakens an existing gate, and it does so
while the design claims the opposite. Four other defects would also bite at land or in production.
The work spans about 27 files, so it needs teammates.

---

## 1. Hard constraints

### 1.1 Settings edits and new hook registration: met

- Every actuator rides something that already runs:
  - session-continue (Stop, timeout 10 s);
  - anti-deference-nudge (Stop, 5 s);
  - completion-assert (Stop, 10 s);
  - boundary-handoff (Stop, 10 s);
  - operator-readout (Stop, 10 s);
  - the lead-supervisor launchd daemon.
- Measured, read-only: `jq '.hooks.Stop[]?.hooks[]?|{c,t:.timeout}' ~/.claude/settings.json`.
- The daemon's plist runs the shared checkout's script directly
  (`launchd/com.claude.lead-supervisor.plist:6`). A script edit therefore needs no plist edit.
- dod-persist is called as a CLI from session-continue. It is not a new registration.
- One exception, operational rather than formal: goal (d) cannot work unattended without a settings
  edit. See defect M5.

### 1.2 "Never weaken an existing gate": violated once, with two near-misses

**The violation (M1).** D2:290 says "📦/🚀 still outrank it". That holds for 📦, which is decided
before the ✅-eligible branch (`scripts/wrap-ledger.sh:2615`). It is false for 🚀:

- The pseudo-diff (D2:281-287) inserts `elif [ "$LOOP_OPEN" -eq 1 ]` right after `CLOSE_FLOOR`
  (`wrap-ledger.sh:2670`) and before `elif [ -z "$TRUNK" ]` (`:2674`).
- The 🚀 arm `LIVE_BREACH` sits at `:2685`, below that insertion. So does the re-check ⛔ at `:2717`.
- So a loop-scoped session in the live-layer repo whose real state is "landed but not live" now reads
  🔧. Two gates go dark:
  - completion-assert's 🚀 contradiction is keyed on `RUNG=🚀` exactly
    (`hooks/completion-assert.sh:1166`). A false "done" over an unconverged layer is no longer
    convicted.
  - The ship floor's 🚀 converge nudge is keyed on `case "$rung" in "📦"|"🚀")`
    (`hooks/session-continue.sh:1216`). It stops firing.
- `CLOSE_FLOOR` has the same rank today, so there is precedent. But the design asserts the property
  it breaks, and the brief forbids the weakening.

**Near-miss 1 (M2).** The scope floor's discharge (2) tells the model to re-file as class B and then
run `cc-decide action <old id> --evidence "superseded…"` (D2:525-528). The class-C stderr hint says
the same, unconditionally and with no classifier (D2:711-717). Two facts make this dangerous:

- `cc-decide action` has no class guard. `cmd_transition` sets `.status=actioned` on any packet
  (`bin/cc-decide:364-388`).
- The floor fires on every ⛔ that has ungated work. That includes the design's own control C2
  (d610, a self-modification packet) whenever nothing is in flight (D2:993).

So forced-turn text now teaches a lead to retire a genuine C10/C6 packet itself and re-file it as a
B whose default fires. That opens a laundering path through the class-C ceiling, which the brief
says must hold for money, self-modification and permission gates. The design concedes it cannot
classify: gate-classify routes the money packet `a247b7288149` to B (D2:716).

**Near-miss 2.** The mechanical 🔧 arm would also arm on ⛔ (D2:400-416). But its budget file
`${f}.mech` is per session, and the same session never gets a second wind
(`hooks/session-continue.sh:1139-1152`, "the same session does not get a second wind"). Arms spent
under ⛔ are therefore taken from later 🔧 dirty-tree lapses. The total stays bounded, but 🔧
coverage shrinks (minor).

**Checked and acceptable:**
- The completion-assert double-block yield is generic on the per-Stop marker
  (`hooks/completion-assert.sh:1287-1291`). The turn is forced anyway, and no budget is spent.
- The anti-deference yield follows the same pattern.
- handoff-fire stays keyed on REMAINDER and UNLANDED (D2:1016).
- The ⛔ READOUT prefix is unchanged (D2:271-272).
- Fields are emitted after `LIVE=` (D2:305). The memo key is bumped to `v2` (D2:321).

---

## 2. Instruction budget: verified

- **Measured.** I replayed the design's `old R:n` / `new R:n` blocks in memory with
  `hooks/lib/instruction_budget.py` `parse(text, path, True).units`, using `python3 -I -B -c`:
  - each of the 16 old blocks occurs exactly once;
  - R goes from **30,287 to 30,218 (−69)**, which matches D2:912.
- **Measured.** Strings pinned by `tests/research-program-exemption-rules.bats:24-40` survive in the
  edited R:
  - `- F2 well-researched:`
  - `timebox receipt satisfies`
  - `- E0, read-only turn:`
  - `relaying the certificate`
  - `Offering researched, in-scope remaining work` / `is not an offer`

  `Research to raise conviction under Follow-On Gate F2` lives in S, which is untouched.
- Per-file cap: 40,000 (`config/instruction-budget.json:7`). The verdict is "DENY iff new > budget
  AND new > cur" (`hooks/lib/instruction_budget.py:28-30`). A net shrink passes the land ratchet and
  the Write/Edit gate.
- **Residual.** The user tier stays in breach: 61,005 > 60,000 (estimated from the measured R units
  plus S 28,503 plus the mission board at 2,284).
- **Residual.** The held-out re-gate the operator deferred "until the next slim edit"
  (`docs/plans/INSTRUCTION_BUDGET.md:127`, about $403 list, needs the operator's go-ahead) is
  triggered in principle. D2 §9.4 flags it but does not decide it.
- **What the cuts drop (minor).**
  - R:15 is the always-loaded anti-hang sentence: "waiting on a trunk-wide stamp you do not control
    is not diligence, it is a hang". This change exists to stop idling.
  - R:21 holds the custody verbs. The design says the ledger READOUT prints them "whenever they
    apply" (D2:842). In fact the custody READOUT exists only on the ✅-eligible path
    (`wrap-ledger.sh:2622-2641`). Under ⛔, 🔧-dirty or 📦 custody is `skip`, so those verbs vanish
    there.

---

## 3. Deploy path: works, with skew

- **New hook libraries.** `hooks/lib/loop-scope.sh` and `hooks/lib/live-waves.sh` are linked by
  install.sh's glob (`install.sh:342-344`). Parity classes them want=1 (`hooks/lib/*.sh`,
  `scripts/deploy-parity-assert.sh:551`). So until converge they count as LIVE_ADDS, a transient
  🚀 on the landing session.
  - Both consumers resolve their own symlink first, so the libraries are reachable on the
    fast-forward (the pattern at `hooks/session-continue.sh:103-118`).
- **Rule files.** R reaches `~/.claude/rules/10-session-close.md` by install.sh copy. G goes to
  `CLAUDE.full.md` (`maps/rules-text.md` §1). Both go live at converge.
- **Grants file.** `config/standing-grants.json` is not deployed. It is referenced by its absolute
  path in the shared checkout, which is fine on this single machine.
- **Public-repo hygiene.** I checked the redaction map: it holds no username, truememory or
  agentsync terms (measured with `grep -ci`). So the grant JSON's quote and paths do not trip
  `public-hygiene-lint` at land.
- **Skew (minor).** Hooks change for every running session at converge. Rules load once at session
  start. A multi-day lead like B13 (3 days) would run the new floor under the old R:217 ("clear it
  … as soon as the state becomes … ⛔") and the old R:38 ("Stop and ask"). The floor quotes a rule
  that session never loaded (D2:520-521). The cap of 2 bounds the fight.
- **Shadow first (minor).** P3 says the supervisor nudge runs "24-48 h in `shadow`, then live"
  (D2:1125). But the code default is `CC_SUP_SUBJECT_NUDGE:-1`, which is live (D2:639). The plist
  carries only `CC_PAGE_TO` (`launchd/…plist:10`), so shadow-first needs a shadow code default and
  a second commit to flip it. The scope floor has no shadow phase at all (`CC_SCOPE_FLOOR:-1`,
  D2:443).

---

## 4. Testability: RED without the change

**Mostly feasible.** Each piece follows a known pattern:

- **ledger:** real `bin/cc-decide` with `open_blocking` (`tests/wrap-ledger.bats:1832`);
- **floors:** a `WRAP_LEDGER_BIN` stub (`tests/ship-floor.bats` style);
- **supervisor:** the T40 checks in `scripts/supervisor-e2e.sh`;
- **rules:** a grep-pin suite (`tests/close-research-pending-rules.bats`).

New suites satisfy rule 1 (fixture HOME). L1, L6, S1, I1, I7, the rules pin and the supervisor
checks are all red on origin/main.

**Defects:**

- **M4: the stderr hint breaks the existing cc-decide suite.** bats `run` merges stderr into
  `$output`. These tests use `$output` as the packet id after a class-C `open`:
  - `tests/cc-decide.bats:72`, `:428`, `:438`, `:458`, `:468`, `:477`, `:719` (at least 7);
  - the file has 42 `run … open` sites (measured: `grep -nE 'run (bash )?"?\$\{?[A-Z_]*(CD|DECIDE)…open'`).

  An unconditional class-C stderr hint (D2:711) turns them red. §7 lists no `cc-decide.bats` change.
- **Vacuous guard tests.** About 10 guard tests have "—" in the red-without column: S6, S8, S10,
  S11, S12, S14 and S16 (D2:1073-1083). Each passes on origin/main because no floor exists. Each
  needs its own named mutant (`maps/test-infra.md` §6). Plan about 10 mutants.
- **Verification cost (estimated).**
  - P1 alone touches wrap-ledger, session-continue and boundary-handoff. The latter is touched
    because of the live-waves move; see m3 below.
  - Measured direct-suite counts from `maps/test-infra.md` §2.3: 31 + 23 + 7. The smoke is
    guaranteed to be cut at 900 s.
  - At about 6 s per test under load ~250 (the one measured rate, 456 s for 76 tests), the big four
    alone take about 46 min wall:
    - wrap-ledger.bats, 142 tests: about 14 min;
    - completion-assert.bats, 193 tests: about 19 min;
    - session-continue.bats, 61 tests: about 6 min;
    - anti-deference-nudge.bats, 62 tests: about 6 min.
  - All direct suites together run to several hours.
  - cc-bats admits only 2 live bats roots machine-wide (`bin/cc-bats:514`). Teammates therefore
    cannot parallelize verification beyond 2.

---

## 5. Size

**Production, 17 files (P1-P3):**
- `scripts/wrap-ledger.sh`
- `hooks/dod-persist.sh`
- `hooks/lib/loop-scope.sh` (new)
- `hooks/lib/live-waves.sh` (new)
- `hooks/boundary-handoff.sh`
- `hooks/session-continue.sh`
- `hooks/completion-assert.sh`
- `hooks/anti-deference-nudge.sh`
- `hooks/operator-readout.sh`
- `hooks/dispatch-assert.sh`
- `hooks/lib/why-tier.sh`
- `commands/wrap.md`
- `scripts/lead-supervisor.sh`
- `bin/cc-decide`
- `CLAUDE.rules.slim.10-session-close.md`
- `CLAUDE.global.md`
- `config/standing-grants.json` (new)

**Tests, 10 files:**
- `tests/wrap-ledger.bats`
- `tests/scope-floor.bats` (new)
- `tests/scope-intake.bats` (new)
- `tests/session-continue.bats`
- `tests/completion-assert.bats`
- `tests/anti-deference-nudge.bats`
- `tests/operator-readout*.bats`
- `scripts/supervisor-e2e.sh`
- `tests/lead-supervisor.bats`
- `tests/lead-keeps-working-rules.bats` (new)

`tests/cc-decide.bats` should be added (M4).

**Totals.** About 27 files. Estimated, by summing the pseudo-diffs:
- about 650 production LOC: session-continue ~200, wrap-ledger ~130, lead-supervisor ~75,
  anti-deference ~30, the two libraries ~45, rules and other text ~170;
- about 1,100 test LOC.

**Over the 6-file line, so it needs teammates.** P1 alone is about 16 files. A split that keeps file
ownership disjoint:
- **T1:** wrap-ledger and the loop-scope library, with the ledger tests.
- **T2:** session-continue, dod-persist and the live-waves library, with scope-floor and
  scope-intake.
- **T3:** lead-supervisor and supervisor-e2e.
- **T4:** R, G, the grants JSON and the rules pin.
- **T5:** completion-assert, anti-deference, operator-readout, dispatch-assert, why-tier, wrap.md
  and cc-decide.

---

## 6. Defects

| # | Sev | Issue | Evidence | Fix |
|---|---|---|---|---|
| M1 | major | The loop-🔧 arm outranks 🚀 (and no-trunk, re-check ⛔, 👤). completion-assert's 🚀 conviction and the ship floor's 🚀 nudge go dark for loop sessions, while the design claims 🚀 still outranks it | D2:281-290; `wrap-ledger.sh:2670,2674,2685,2717`; `completion-assert.sh:1166`; `session-continue.sh:1216` | Insert the loop arm after the `LIVE_BREACH` arm (at 👤's rank, or just above `BLOCKED_RECHECKED`); add a bats pin "loop scope + past-budget live layer ⇒ RUNG=🚀" |
| M2 | major | Forced-turn text and an unconditional stderr hint teach the lead to `cc-decide action` its own class-C packet and re-file it as B. Nothing guards the class, and the floor fires over genuine C10/C6 packets too | D2:525-528, :711-717, :993; `bin/cc-decide:364-388` | Drop discharge (2) from the floor reason: the work or `Scope (held)` discharge it. Teach the B route only at filing time (R:160). Never tell an agent to action a class-C packet. Optionally log a self-action of an own C within 24 h to the operator block |
| M3 | major | The supervisor oracle takes the session's last scope-floor row. The floor is SILENT on ✅, 📦 and non-loop 🔧, so after the decision is answered or the loop is done, a stale `ungated:1` row wakes a correctly idle session up to 3 times | D2:454-457 (`*) return 0 ;; # SILENT`), D2:648-656 | Accept the row only if it is the session's newest session-continue row, or newer than its newest completion-assert or boundary-handoff row. Or log one `scope-floor-clear` row when a state file exists and the rung leaves ⛔ or loop-🔧 |
| M4 | major | The unconditional class-C stderr hint reds cc-decide.bats tests that read `$output` as the id. §7 omits this | `tests/cc-decide.bats:72,428,438,458,468,477,719`; D2:711-717 | Export `CC_DECIDE_HINTS=0` in cc-decide.bats `setup` (and in any suite that `run`s open), add one positive hint test, list the suite in §7 |
| M5 | major | Goal (d) is written down but not executable unattended. The auto-mode classifier refused Codex as exfiltration 6 min after the operator's grant. Live settings have `defaultMode: auto` and no codex allow rule, and the design cannot add one | TX:4683 (18:17:32Z); `jq .permissions ~/.claude/settings.json` (measured: no codex/git-archive rule); D2:861-862 | State the dependency in the grant text. File the exact allow rule as an operator step (permission, class C) and keep the grant "ask-free, not prompt-free" until it lands |
| M6 | major | New R:26 mandates `dod-persist.sh set "Scope (frozen)…"` for every session at intake. That is the DOD_SCOPE crosstalk the design rejected for capture (D2:112-115, :1021). DRAIN_SCOPE is a substring match feeding CLOSE_FLOOR for every session in the checkout. The design's own loop fixture "keep going until the backlog is empty" also flips DRAIN_SCOPE for siblings when intake-captured | D2:750-751; `wrap-ledger.sh:924-928,945`; `completion-assert.sh:1142`; `maps/wrap-ledger.md` §2.4 (50/362 frozen lines contain backlog/drain) | Compute DRAIN_SCOPE from the own-session frozen line when one exists (the same awk as `compute_own_scope`). Or keep R:26's wording and mandate `set` only for loop scopes |
| m1 | minor | The mechanical arm on ⛔ spends the shared per-session `.mech` budget | `session-continue.sh:1139-1152` | A separate `${f}.mech.blk` budget |
| m2 | minor | Skipping `open_packet_B` under ⛔ drops the "Genuine-3 → durable packet" record for an unrelated value fork. Its default is literally "park … and continue other work" | `anti-deference-nudge.sh:477-489`; D2:567-572 | Skip only when the fork text matches an open packet of this session; otherwise keep filing |
| m3 | minor | Moving `bh_live_waves` into a library puts boundary-handoff into P1 (contradicting "P5 optional", D2:582, :1123) and flips its fail direction: library absent ⇒ 0 waves ⇒ the free-win in-flight abstain is silently off | D2:919-920; `boundary-handoff.sh:875-909` | Copy, don't move, for P1. In boundary-handoff, absent ⇒ unknown ⇒ abstain |
| m4 | minor | Rule cuts drop the always-loaded anti-hang sentence (R:15) and the custody verbs (R:21). The claimed replacement never prints under ⛔, 🔧-dirty or 📦. The user tier stays over budget anyway | D2:836-844; `wrap-ledger.sh:2622-2641` | Keep a 1-line custody pointer; prefer other cuts or the `tiers.user` ruling |
| m5 | minor | Several guard tests are not red-able without a mutant | D2:1073-1083 | Name one mutant per guard in the plan |
| m6 | minor | Shadow phases are claimed but the code defaults are live | D2:443, :639, :1125 | Ship `shadow` defaults; flip in a follow-up commit |
| m7 | minor | The intake marker holds one sid per (cfg, cwd), so shared checkouts rescan on every alternation. `.scope.<sid>` state files are never GC'd | D2:366-369, :480 | Per-sid marker; a 7-day mtime sweep beside the supervisor's |
| m8 | minor | The operator-hold check reads `_sc_lum` from the kill-switch memo. With `CC_SC_KILL_MEMO=0` it is unset, so the hold is never seen and the floor fails toward blocking | D2:504-510; `session-continue.sh:1309-1315` | Fall back to `last_user_msg` when the memo is off |
| m9 | minor | Size: about 27 files and about 1,750 LOC (estimated). Verification needs hours of wall time under a 2-root bats cap | §5 above; `bin/cc-bats:514` | Split as in §5; run direct suites outside the land and assert `1..N` |

---

## 7. Best ideas worth grafting into the final design

1. **The predicate comes from this session's own DoD contract.** It reads `session=<SID>`-stamped
   blocks for an open loop, its own boxes and a stale-checked `Scope (held): <id>`. It needs no
   packet schema field, no prose matching, and avoids alarm polarity (D2:14-38, :153-190). Stale
   `held` (it names only answered packets) correctly reads as not held.
2. **`dod-persist set` accepts `Scope (held):` and `Scope (done):`.** These are durable, auditable
   state-change discharges (D2:331-346), and the change is a two-line diff.
3. **Loop-only intake capture of the FIRST genuine user record, inside an already-registered Stop
   hook.** Measured at 0.207 s on the 9 MB transcript. Its anchored regex reproduces: I replayed
   the design's fixtures with macOS awk 20200816 and got the same verdicts.
4. **The ⛔ glyph and order are kept, with fields appended after `LIVE=`.** No pin changes, no
   renderer `case` misses, a `v2` memo key. Custody and residents are computed under ⛔ only when
   ungated work exists (D2:252-276).
5. **The scope floor's bound: key (sid, open-C ids, kind, scope head) + HEAD latch + cap 2.** The
   state is written before the block and fails closed when unwritable. In-flight abstains on
   CUSTODY/LANDING/RESIDENT/waves, and an armed watcher alone does not count (D2:442-497).
6. **`nudge_subject` keyed on the decision state.** It backs off 2 h then 4 h, caps at 3 per state
   and 3 per sweep, and writes its marker only on `enqueued=1`. It also fixes `advise_subject`'s
   wrong-verdict parse (D2:643-700). Graft it only with the M3 fix.
7. **A rule edit that is net-shrinking and measured** (−69 units, which I reproduced), with every
   always-loaded change made in one file.
8. **completion-assert stays informative only** (`blocked-answered:ungated=N`). Anti-deference
   TELLS stay untouched, which respects the pins at `tests/anti-deference-nudge.bats:706-717`.
