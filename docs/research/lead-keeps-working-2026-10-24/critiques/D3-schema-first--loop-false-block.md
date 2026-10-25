# Critique: D3-schema-first, lens loop-false-block

Reviewed: `docs/research/lead-keeps-working-2026-10-24/designs/D3-schema-first.md` (cited as `D3:n`), plus the code
it touches. Code anchors are `path:line` in worktree `lead-idle-fix`. `TX:n` is a line of the B13 transcript.
Read-only. The only scratch files are `/tmp/d3crit/{scan.sh,peers.sh,frozen-lines.tsv,loop-hits.tsv,dod.txt,big.txt}`.
Nothing under `~/.claude` was written.

**Verdict: unsound as written (score 5/10).** Most paths are bounded, but the latch that carries the
"≤2 per commit, ≤16 total" claim (`D3:500-515`, `D3:965`) has two holes that remove the bound. The design also adds a
new "land" push under an open class-C packet, and it lets one `--category escalation --gates all` switch off every
floor and nudge. Each fix is small; with them applied the design is sound on this lens.

---

## 1. Measurements taken for this critique

| # | What | Result | Label |
|---|---|---|---|
| M1 | `Scope (frozen):` lines in human (non-isMeta) user records and assistant text, main transcripts under `~/.claude*/projects` modified in the last 14 days, >20 KB (`bash /tmp/d3crit/scan.sh`) | 547 lines in 532 sessions; D3's loop regex (`D3:347`) matches 8 lines in 8 sessions | measured |
| M2 | Those 8 hits (`/tmp/d3crit/peers.sh`) | All 8 are B13 lead sessions (666022fd plus 7 recycled or fired successors). Every brief is `type=user, isMeta=false, origin.kind="human"`, so D3's intake filter (`D3:620-622`) takes all 8. One brief, 502bd860, matches `machine_env` and is still taken, because `origin.kind` wins. Lane briefs carrying the loop line: 0 | measured |
| M3 | Sessions whose first `Scope (frozen):` line is mid-line rather than line-anchored | 99 of 532. Many are real declarations ("DoD ref: none. Scope (frozen): …") | measured (awk over M1) |
| M4 | Telemetry rows sharing a `(config_dir, cwd)` key (`/tmp/cc-telemetry/*.json`) | 19 of 38 rows share their key with at least one other row (4 of 23 keys). Liveness overlap not measured | measured |
| M5 | Box load at review time (`uptime`) | 270 / 300 / 269 | measured |
| M6 | Worst-case intake scan with no match, over the first 4 MiB of a 5.0 MB transcript (`head -c 4194304 \| jq … \| grep -m1 <absent>`) | 0.05 s per pass | measured |
| M7 | The design's awk under macOS `/usr/bin/awk`, on a B13-shaped store block | prints `own 1 loop until dry…`. It also matches `repeat until-green` | measured |
| M8 | Stop hook timeouts (`jq` on `~/.claude/settings.json`, `~/.claude-quaternary/settings.json`) | session-continue, completion-assert, boundary-handoff, operator-readout: 10 s | measured |
| M9 | How the cc-wake frame is recorded (`TX:5067`) | `type=user, isMeta=true, origin.kind="peer"`. So a nudge does not count as an operator prompt: it does not start the 6 h adopted hold and does not touch the kill switch | measured |
| M10 | Last operator prompt before the idle | `2026-10-24T02:22:12Z`, "Are we seriously making progress going 33 rounds? is this forever?…" (jq over TX:4100-4500) | measured |

M1 and M2 limit the loop-floor blast radius. The loop regex had no false positives in 14 days, and its whole
population was B13 leads. The defects below are mostly about the *latch* and the *part/all fold*, not the regex.

---

## 2. Per change: loop path and false-block path

| Change | Loop path found? | Bound in design | Holds? | False-block path found? |
|---|---|---|---|---|
| `scope_floor` drive (`D3:468-519`) | Yes: §3 D-1, D-2, D-3 | ≤2 per (setk, HEAD:trunk), ≤16 per setk | **No.** The single-record state file resets on any other sid or setk. TRUNK moves without this session's work | Yes: D-4 (store error), D-6 (live exchange), D-7 (opposite block), D-11 (in-flight work it cannot see), D-12 (foreign box) |
| `scope_floor` challenge | Yes: D-2 (a new id per forced turn gets a new challenge) | 1 per setk | Only per setk | D-9 (an honest soft stop draws 3 more nudges) |
| Mechanical arm on ⛔ (`D3:559-564`) and the new 🔧 "Decision open, not gating" (`D3:378`) | No (`CC_MECH_MAX`×`CLAUDE_CONTINUE_MAX`, sid-keyed) | existing | Yes | **Yes, and it weakens a gate: D-5** |
| Ledger fold, `LOOP_OPEN`, `SCOPE_FLOOR` (`D3:306-448`) | No (a pure function) | n/a | n/a | D-4 (error polarity), D-12 (REMAINDER leg), D-14 (research rung change) |
| `nudge_subject` (`D3:652-683`) | Rate-limited by STALL_S. D-10: a re-send every SWEEP=30 s when cc-notify exits non-zero after enqueueing | 3 per key, backoff | Per key only | D-8 (ignores the hook's own abstains), D-9 |
| Intake (`D3:545-552`, `D3:616-629`) | No (one-shot marker) | marker | Yes. Cost measured small (M6) | D-13 (fired-peer brief, mid-line quote) |
| completion-assert loop fact (`D3:577-581`) | No | `COMPLETION_MAX`, latch | Yes | A done-claim over a finished loop with no `Scope (done):` is convicted. Bounded by the assert cap. Acceptable |
| `cc-decide` refusal and hints | No | CLI | Yes | No |

---

## 3. Defects

### D-1 (major: loop with no bound) The latch is one record per (config dir, cwd), so sessions and setks reset each other

- **Evidence.**
  - The latch file is `sfile="${f}.scope"`. It holds one line, `sid setk prog cnt tot`, overwritten on every fire, and any mismatch zeroes both counters: `{ [ "$psid" = "$cur_sid" ] && [ "$pset" = "$setk" ]; } || { pprog=""; pcnt=0; ptot=0; }` (`D3:508-514`).
  - `$f` is keyed by config dir plus cwd only: `printf '%s|%s' "${CLAUDE_CONFIG_DIR…}" "$1" | sha1` (`hooks/lib/continue-sentinel.sh:29-31`, header `:11`).
  - So "Hard total CC_SCOPE_FLOOR_TOTAL=16 per (sid, sorted open class-C ids, own loop head)" (`D3:965`) is not a hard total. It is a total since the last time a different (sid, setk) fired in this cwd.
- **Loop A, two sessions.**
  - Sessions A and B share one account and one cwd (19 of 38 telemetry rows share such a key, M4). Both sit at `SCOPE_FLOOR=drive`, and neither makes progress, for example because both believe they are blocked.
  - A's Stop fires and writes A. B's Stop finds `psid≠B`, resets, fires, and writes B. A's next Stop resets and fires again.
  - This continues for as long as their Stops interleave. The harness cap does not bind it: `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=50` resets whenever a tool runs (`bin/claude-latest:344-355`; `maps/stop-hooks.md:66`).
- **Loop B, one session.**
  - Two drive setks alternate. One example: the decide read fails (BLOCKED_SRC=error, ids "") on one Stop, and on the next it succeeds with a part-gating id X. Each fire resets the other. See D-4 for why an error read can still fire.
- **Fix.**
  - Key the state per sid: `${f}.scope.${cur_sid}`. Keep a small map setk→(prog, cnt), not one record.
  - Add a per-sid rolling cap that no key change resets, for example ≤6 fires per 24 h. A per-sid lifetime cap would repeat the "spent two days earlier" failure (`maps/stop-hooks.md:137-139`); a rolling window does not.

### D-2 (major: unbounded by compliance-shaped actions) A setk change re-arms both counters

- **Evidence.**
  - `setk = sha(sid | BLOCKED_IDS | LOOP_HEAD)` (`D3:503`).
  - The model changes BLOCKED_IDS by filing any new class-C packet (`mk_id` = class+sid+what, so any rewording makes a new id; `D3:77-78`) or by `--supersedes`.
  - It changes LOOP_HEAD with any `dod-persist.sh set "Scope (frozen): …"`. The newest own frozen line wins (`D3:349`).
  - Each change gives `pcnt=0, ptot=0`. A challenge is "asked once per decision set" (`D3:507`), so a model that files a new pick or legacy packet on each forced turn is challenged on every turn.
  - This is the class `hooks/session-continue.sh:1119-1124` names: "a budget the demanded action RESETS never binds".
- **Fix.**
  - Make the no-progress latch setk-independent: ≤2 fires (drive and challenge combined) per (sid, own HEAD), whatever the ids.
  - Keep setk only to choose the reason text, and for the one-shot challenge inside that cap.

### D-3 (major: the latch re-arms on other sessions' work) `prog` includes the trunk sha

- **Evidence.**
  - `prog="$(git rev-parse HEAD):$(git rev-parse "$(led_field "$led" TRUNK)")"` (`D3:505`).
  - TRUNK is a remote-tracking ref (`origin/HEAD`, `origin/main`; `scripts/wrap-ledger.sh:816-818`). It moves on any fetch or land by any worktree of the repo, because refs are shared across worktrees.
  - The design's own premise is "A new commit, which requires real work, re-arms" (`D3:965`). A sibling's land is not this session's work.
  - In a busy repo, every wake (mail, nudge) after a trunk move buys 2 more forced turns on a session that is correctly stopped. That continues up to the "16", which D-1 and D-2 already show is resettable.
- **Fix.** `prog = HEAD` only. Better still, use the count of this session's own commits (`session_unlanded_mine` already exists, `hooks/session-continue.sh:1235-1239`).

### D-4 (major: false block over a genuine hard gate) An unreadable decision store fails toward the drive floor

- **Evidence.**
  - Every early return in `count_blocking_decisions` sets `BLOCKED=0; BLOCKED_SRC="error"` (`scripts/wrap-ledger.sh:1508-1511, 1547, 1551`). The read is bounded at 5 s (`:1510`), and the box was at load 270-300 (M5).
  - With BLOCKED=0 the ladder reaches the ✅-eligible branch. D3's new loop arm (`D3:391-392`) then gives 🔧.
  - `compute_scope_floor` (`D3:413-428`) never reads `BLOCKED_SRC`, so it returns `drive`, with ids "".
  - Result: a session correctly stopped on a hard, gates-all money or self-mod packet, with an own loop scope, is told "run the next round as scoped" whenever the store read times out.
  - The design's test W12 covers only "SCOPE_FLOOR none (no loop)" (`D3:1144`). Today's behaviour on an error read is silence, so this is new.
- **Fix.**
  - `compute_scope_floor`: `[ "$BLOCKED_SRC" = error ] && { SCOPE_FLOOR_WHY=decide-unreadable; return 0; }`.
  - The ledger's loop arm should not fire on an error read either.
  - Treat `CUSTODY_SRC=error` the same way (`scripts/wrap-ledger.sh:1706-1708` sets OPEN=0 and SRC=error; `D3:425` then proceeds).

### D-5 (major: weakens an existing gate) The mechanical arm now says "then land" under an open class-C packet

- **Evidence.**
  - The arm's step text is "Run the repo's gate, commit with explicit paths, **then land per the repo's ship policy**" (`hooks/session-continue.sh:1156`).
  - Today any open class-C packet gives ⛔, and the arm returns at `:1103`.
  - D3 reaches that text in two new ways:
    1. ⛔ plus own dirt (`D3:559-560`);
    2. the new 🔧 "Decision open, not gating", which fires on DIRTY alone (`D3:378`).
  - In claude-infrastructure, landing plus converge *is* deployment to every session: `~/.claude` is a symlink farm over the checkout, and 🚀 means "landed but not live".
  - Example: a session with a dirty rule-text or hook edit and an open C packet asking whether to make that change (L12/L1, `maps/legit-stops.md:134,145`) is pushed by the hook to land the very act it asked about. For a part-gated `--gates "the land"` / production-deploy packet (L7/L8, `maps/legit-stops.md:140-141`), the push goes straight at the gated item.
  - The design defends ⛔-above-📦 precisely so "the ship floor is never armed over a land that may be the gated act" (`D3:396-398`), then routes the same push through the mechanical arm. "Committing is never the gated act; landing is" (`D3:564`) is the argument against its own text.
- **Fix.**
  - When `BLOCKED>0`, the arm's step must be "commit on your branch; do not land while decision(s) <ids> are open, unless the land is outside what they gate". Pass `BLOCKED_IDS` through `led_field`.
  - Apply §5.1(c) only when no open packet is `category=self-mod`, or drop the "land" clause on ⛔ altogether.

### D-6 (major: false block on a read-only turn or a live exchange) No conversation hold

- **Evidence.**
  - `scope_floor` has no equivalent of boundary-handoff's `CONV_S=900` exchange hold (`hooks/boundary-handoff.sh:164, 846-848`).
  - When the operator asks a question and the lead answers in a read-only turn, the very next Stop is an "idle" with `LOOP_OPEN=1`, and the floor fires "run the next round as scoped". In a pair-programming exchange each committed turn re-arms it (new HEAD).
  - Concretely for B13: the operator asked "is this forever?" at 02:22:12Z (M10). Under D3, the lead's 02:36Z answer turn would be followed at once by a forced round 27, while the operator was mid-question. Such a round is a multi-hour, multi-lane spend.
- **Fix.**
  - Abstain when the last genuine human prompt is younger than `CC_SCOPE_FLOOR_CONV_S` (900) **and** the ending turn made no writes (`turn_scan … .w == false`, already used at `hooks/session-continue.sh:1417`).
  - The supervisor nudge covers the idle that follows. B13's F1 at 06:44Z, 4 h after the last prompt, still fires.

### D-7 (major: two opposite blocks on one Stop) The context-high abstain checks one of boundary-handoff's five fire axes

- **Evidence.**
  - `scope_floor` abstains only on `used_pct ≥ CC_BOUNDARY_T` (`D3:485-487`).
  - boundary-handoff also fires a recycle block below T on four other axes:
    - transcript ≥25 MB, RSS ≥1500 MB, input tokens ≥700k (`hooks/boundary-handoff.sh:165-167, 452-461, 665, 916-921`);
    - forecast-early, at used ≥55 and ≤20 min to the wall (`:162`, `:664`).
  - Its compose guard checks only the sentinel file (`:687-694`), which floors never write. It does not read `${f}.blocked`.
  - Long leads, the population this floor targets, are exactly the ones over 25 MB. On one Stop the model gets "recycle now" and "run the next round now". D3 claims "never two opposite blocks on one Stop" (`D3:638`).
- **Fix.**
  - `scope_floor` sources the same context-econ lib (`ce_size`, `ce_burn`) and abstains on any axis.
  - Or boundary-handoff reads `${sentinel}.blocked` with arm `scope-floor` and its reason says "recycle; the successor runs the next round".

### D-8 (major: wakes a legit stop) The supervisor's oracle drops the hook's abstains

- **Evidence.**
  - `SCOPE_FLOOR` is the ledger predicate (`D3:413-428`). Kill switch, assignee, teardown, context-high and busy are applied only inside the hook (`D3:481-499`).
  - `nudge_subject` keys on the readout row's `scope_floor` (`D3:661-663`).
  - Its STALL? branch exempts only a registered desk, a permission beacon and an operator-adopted hold (`scripts/lead-supervisor.sh:1046, 1067, 1077`).
  - The adopted hold lasts 6 h from the operator's last real prompt (`bin/cc-classify:57`). STALL? visibility runs from telemetry age 1800 s to `GC_S`=21600 s (`scripts/lead-supervisor.sh:139,146`).
  - So a session the operator told "…and stop", whose last turn after that prompt ran Δ long, is exposed for about Δ after the hold lapses. In that window it gets "drive the next in-scope step now" (`D3:689-694`).
  - The same gap nudges a session at ≥T fill to "drive" rather than recycle, and nudges a confirmed assignee.
  - Bound: 3 nudges per key. That is bounded, but it violates L13/C11 (`maps/legit-stops.md:146`, `:264`).
- **Fix.**
  - session-continue already logs every scope-floor disposition (`D3:477-517`).
  - The supervisor should nudge only when the subject's **last `session-continue` scope-floor row** is `fired` or `scope-floor-latched`, never when it is `abstained` for kill switch, assignee, teardown or context-high.

### D-9 (minor: an honest soft stop draws nudges) The challenge discharge is a sentence, not a state change

- **Evidence.**
  - The challenge says "If the next in-scope step truly builds on the answer, reply with one line naming that step and stop" (`D3:536-537`). That leaves `SCOPE_FLOOR=challenge` in the ledger.
  - `regate --gates all` on a `pick` stays soft (`D3:153-154, 421`).
  - So a legit pick that gates a loop-shaped scope (the fd91140d shape, `maps/legit-stops.md:167`) costs 1 challenge plus 3 supervisor nudges (`D3:654, 668-670`).
  - The design's own rule is "A discharge must be a state change, not a sentence" (`D3:171`).
- **Fix.**
  - Add `regate <id> --gates all --confirm-builds-on "<step>"`. It appends `{confirmed:true}`, and the fold maps a confirmed soft gates-all to `SCOPE_FLOOR=none` (why `confirmed`).
  - Alternatively, the supervisor never nudges on `challenge`.

### D-10 (minor-major: duplicate inbox lines) `nudge_subject` ignores cc-notify's `enqueued=` contract

- **Evidence.**
  - The marker is written only on `rc=0` (`D3:676-680`). Test N4 pins "stub rc 3 leaves no marker, retried" (`D3:1184`).
  - cc-notify says "Callers MUST read `enqueued=` before treating a non-zero rc as a lost message". A timeout returns 124 after the line is already in the inbox (`bin/cc-notify:96-111`).
  - Under load, each 30 s sweep (`scripts/lead-supervisor.sh:89`) re-enqueues while STALL? holds. `NUDGE_PER_SWEEP` caps sessions per sweep, not sends per session.
- **Fix.** Write the marker when `enqueued=1`, whatever the rc. Retry only on `enqueued=0`.

### D-11 (minor: false block during in-flight work) Waits that neither custody nor the cwd scan can see

- **Evidence.**
  - The abstains are custody, LANDING, and a process scan of this cwd (`D3:424-426, 488-498`).
  - Not seen:
    - in-process background Agent subagents;
    - workflows or lanes in another cwd that registered no custody row.
  - The scan "PROCEEDS" on timeout (`D3:489-491`). That scan took 1.5-2.0 s at load ~38 (`hooks/session-continue.sh:1093-1097`). At the measured 270-300 (M5) it will usually exceed the 2 s bound. So under the load that rounds themselves create, the busy abstain is effectively off.
  - The risk is a duplicate round launched while one is in flight (money).
  - Bounded: 2 per HEAD, but see D-3.
- **Fix.**
  - Abstain on `CUSTODY_SRC=error` (D-4).
  - Add a transcript-side check for background task ids with no matching `<task-notification>`, which is cheap and needs no process table.

### D-12 (minor) The REMAINDER leg revives the floor session-continue deliberately refused

- **Evidence.**
  - `UNGATED = REMAINDER + LOOP_OPEN` (`D3:369`). REMAINDER keeps unattributable blocks and "can only ever fail toward too many" (`scripts/wrap-ledger.sh:929-933`).
  - So a part-gating packet plus any foreign box gives drive, and a soft gates-all packet plus a foreign box gives challenge.
  - `hooks/session-continue.sh:997-999`: "a remainder is the steady state, not a loose end. Firing on it would block every close in this worktree forever."
  - It is dormant today, because 0 of 78 DoD files hold a box (`maps/wrap-ledger.md`, measured there).
- **Fix.** The floor's UNGATED counts `LOOP_OPEN` plus boxes inside **own-sid** blocks only.

### D-13 (minor) Intake can adopt a contract that is not the session's

- **Evidence.**
  - Rule (i) takes any `origin.kind=="human"` record (`D3:620-622`), and fire and recycle briefs typed into panes are `origin.kind="human"` (M2: 8/8, including one matching `machine_env`).
  - A lane brief that quotes the lead's loop line before the lane's own scope makes the peer's **first** line a loop. The peer is then driven to "run the next round". Fired peers get no assignee abstain (`hooks/session-continue.sh:1047-1061` covers only Agent-Teams assignees).
  - Rule (ii) matches a mid-line quote in the session's own text. 99 of 532 first lines are mid-line (M3), so analysis sessions quoting B13 qualify.
  - Measured exposure today: 0 lane briefs with the loop line (M2).
- **Fix.**
  - For rule (ii), require the line to begin with `Scope (frozen):` (allowing markdown bullets).
  - Skip intake when the session is a fired peer: its sid is a custody row's `firedSession`, or the brief carries `HANDOFF-ENGAGE-`. Otherwise take the brief's **last** `Scope (frozen):` line.

### D-14 (minor) Research-kit packets are relabelled, which changes the program rung

- **Evidence.**
  - `gate_sweep.py` is forced to `--category pick --gates "<decision id>"` (`D3:278`), so program operator gates become part-gating.
  - With dirt, the rung becomes 🔧 (`D3:378`) and the mechanical arm fires "…then land" (D-5).
  - The floor's research exemption (`D3:415`) does not cover the ladder or the arm.
  - Program gates include paid runs (money), which `pick` mislabels.
- **Fix.** Pass `--gates all`, so today's ⛔ is preserved exactly, and take the category from the program frame.

### D-15 (minor) The loop end marker is not durable, and the scope can be re-frozen silently

- **Evidence.**
  - **Resurrection.** `last_recorded_scope` greps only `Scope (frozen):` (`hooks/dod-persist.sh:140`). PreCompact appends the newest transcript frozen line whenever it differs from that (`:622-631`). A paraphrased restatement of the loop after `Scope (done):` therefore appends a new frozen block, which gives `LOOP_OPEN=1` again under a new LOOP_HEAD, with a fresh setk budget. The SessionStart frame still calls the loop "THE CURRENT CONTRACT … Do NOT … declare done" (`:462`).
  - **Silent off-switch.** Any `dod-persist.sh set "Scope (frozen): <non-loop>"` gives `n-a` (`D3:349, 367`) and switches off both floor and nudge, with no `done` claim to audit. §11 lists only the false `Scope (done):` (`D3:984`).
- **Fix.**
  - Teach `last_recorded_scope`, the PreCompact dedup and the SessionStart frame about `Scope (done):`.
  - Log a loop→non-loop re-freeze by the same sid as an IDL row, so the census can count it.

### D-16 (minor) Leftovers

- The busy probe runs `timeout N bash -c '. lib && sb_busy_jobs'` (`D3:497`). `sb_busy_jobs` creates a `mktemp` file (`hooks/lib/session-busy.sh:308`) that leaks when the probe is killed.
- A usage-limited session is not abstained. Each forced turn fails at once, so this is bounded by 2 per HEAD, but cc-wake already has the predicate (`maps/legit-stops.md:239-240`).
- The R:4 text the design keeps ("Stop hooks check facts only, never scope", `D3:796`) now sits beside a floor keyed on a regex reading of scope text. The hook needs the same "why this is not the banned scope-blind hook" paragraph the mechanical arm carries (`hooks/session-continue.sh:987-990`).

---

## 4. Gaming: what the model can do and what bounds it

| Gaming move | Effect in D3 | Bound | Assessment |
|---|---|---|---|
| File (or regate to) `--category escalation --gates all` | `ghard` is true (`D3:153-154`). `BLOCKED_ALL_HARD>0` returns `gates-all-hard` (`D3:417`): no floor, no challenge, no nudge, for **every** packet of the session | **None: zero forced turns** | **Major (D-17).** `escalation` is open-textured ("a surface a rule … reserves", `D3:262-264`). It is excluded from the router cross-check (`D3:241-243`), and the status-quo check runs only on `pick` (`D3:248-250`). The drive text itself teaches `regate <id> --gates all` (`D3:527`). The B13 lead wrote "No round 27 until you answer", so it believed this; declaring a loop-stop question "escalation: the operator decides the scope" reproduces B13 exactly. The replay's variant L assumes `pick` (`D3:1030`) |
| `--category pick --gates all` | ⛔, 1 challenge, then the honest-sounding one-line answer, latched, 3 nudges | 4 turns | Bounded. The B13 lead would answer "round 27 builds on e869" and idle. §12's "re-filing … gives the drive floor" is optimistic |
| `Scope (done): <anything>` | `LOOP_OPEN=0` permanently for the sid | none | Acknowledged (`D3:984`). Auditable only |
| Re-freeze to a non-loop line | `LOOP_OPEN=0` | none | Not acknowledged (D-15) |
| Edit the DoD store file directly, or rewrite the `session=` stamp | the floor reads whatever is on disk | none | Same as today's DoD trust model |
| Tick a box | REMAINDER falls | n/a | Boxes are almost unused (0/78) |
| `session-continue.sh clear` | does not touch `.scope` | n/a | Good: `clear` cannot disarm the floor |
| `CC_SCOPE_FLOOR=0` in its own shell | no effect (harness environment) | n/a | Correct (`D3:987`) |

**D-17 fix (major).**
- Restrict `ghard` to cc-decide's own reserve plus destructive: `self-mod|money|permission|credential|destructive`. Fold `escalation` as soft.
- Run the status-quo-option check for every category. A packet with a status-quo option reads `challenge` whatever its category.
- Give even a hard gates-all packet one challenge turn per (sid, HEAD) when `UNGATED>0`. The cost is at most one turn on a legit stop. Legit stops almost never have `UNGATED>0`: 7 of 11 transcript-checked idles had finished their ungated work (`maps/legit-stops.md:26-27,170-173`).
- Have the challenge text quote the rule "a question about when a loop stops never gates the scope it would change" for all categories (`D3:535-536`).

---

## 5. The named legitimate stops

| Case | Behaviour with D3 as written | With the fixes above |
|---|---|---|
| Genuine C10/C6/permission/credential gate, declared gates-all | ⛔, `gates-all-hard`, no floor, no nudge ✓. **But** on a decide-read error with an own loop: drive (D-4). With own dirt: the mechanical arm says "land" (D-5) | ✓ (store error ⇒ none; commit without land) |
| The same, honestly declared part-gating, with every loop round needing the act | ≤2 per HEAD:trunk, re-armed by trunk moves, ≤16. Discharge: `regate --gates all` (one command) | ≤2 per own HEAD, ≤6 per 24 h |
| Research program | floor `none` ✓. Program packets relabelled, rung changes (D-14) | `--gates all` keeps today's rung |
| Fired peer | no abstain. Driven if its first frozen line is a loop (D-13; 0 measured) | intake skips peers, or takes the brief's last line |
| Teammate (Agent-Teams assignee) | abstain (copied from the ship floor) ✓. The supervisor still nudges (D-8) | the supervisor keys on the hook's disposition |
| Read-only turn in a live exchange | fires (D-6) | conversation hold |
| Goal whose condition has an operator-only conjunct (e.g. "loop until the operator approves") | drive ≤2 per HEAD. The discharge needs a filed packet or a false `done` | Bounded. Acceptable once D-1, D-2 and D-3 are fixed |
| Money-landing repo at 📦 | rung 📦 ⇒ `none` ✓. With a part-gating packet, a loop and unlanded commits the rung becomes 🔧 and drives (the next round, not the land). Acceptable, but inconsistent with the no-packet case (📦, silent) | n/a |
| Operator "…and stop" | the hook abstains ✓. The supervisor may nudge after the 6 h hold (D-8) | ✓ |

---

## 6. Best ideas worth grafting

1. **The refusal is the escape path, printed last for `tail -3`** (`D3:126-143`). On B13 the lead's own pipe would have shown "LIKELY ALREADY RULED — eb3dbe1e5e94 … keep looping until dry" and a ready class-B command built from its own `--what` and conviction. This acts before any hook has to, so it carries zero loop risk.
2. **The `has()` fold rather than `//`** for `gates_all`/`gate_hard` (`D3:312-314`), with the mutant test W1 (`D3:1133`). jq's `//` turns `false` into `true`, and that trap would silently make every part-gating packet read as gates-all.
3. **A session-scoped loop floor with a one-command end marker**, plus the `dod-persist.sh:487` fix so `Scope (done):` is not rewritten into a new frozen contract (`D3:611-615`). Session scoping avoids the repo-keyed alarm that inherits other sessions' scope (`D3:363-365`).
4. **One predicate (`SCOPE_FLOOR`) computed in the ledger and consumed elsewhere**, with B-3 logging of every ⛔ stand-down (`D3:476-479`). This closes the "stood down vs never ran" ambiguity. (The consumers need the hook's disposition too; see D-8.)
5. **A latch keyed on decision state and progress**, not session lifetime or HEAD alone (`D3:500-515`). This is the right axis. It needs a per-sid store, a setk-independent no-progress cap, and HEAD-only progress (D-1, D-2, D-3).
6. **`--supersedes` as a validated state-change discharge**: same sid, no producer, soft category only, new packet written first and the old one transitioned after, failing toward today (`D3:174-193`).
7. **⛔ stays above 📦 for any open class-C packet**, to protect a land that may be the gated act (`D3:396-398`). Extend the same reasoning to the mechanical arm's text (D-5).
8. **completion-assert stays log-only** (`blocked-answered:ungated=N`, `D3:574-576`), with no second blocker.
9. **Supervisor nudge via direct cc-notify, shadow-mode first week, the marker surviving `clear_page`, and the `advise_subject` verdict-parse fix** (`D3:696-708`). Add the `enqueued=` read (D-10).
10. **The `pick` status-quo option check on stderr** (`D3:248-252`). Generalize it to every category and let it decide challenge-eligibility (D-17).
11. **`config/standing-grants.json` plus `xvendor-review.sh` enforcing the envelope**, with the 80% meter failing closed (`D3:715-764`). This removes decision 2 with no hook at all.

---

## 7. Deviations

- Two scratch read-only scripts were written to `/tmp/d3crit/` with the Write tool (no heredoc) and run with `bash`. Outputs are in the same directory.
- Nothing else was written besides this file.
