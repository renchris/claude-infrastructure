# Slot H: gates, recycle path, signoff memory

Slot H-gates-recycle, 2026-10-18. This slot only read files: no repo file other than this one was written, and no live store was touched. Scratch work is in `/tmp/rpic-H/` (`open.json`, `joined.tsv`, `tiers.tsv`, `join.py`, `tiers.py`).

## Verdict first

1. **H1, the stakes rule.** No new gate is needed. Composing four existing tables gives the whole rule:
   - **G2** escalation surfaces, plus each project's own escalation greps.
   - the **gate-classify C surface** (the C10 self-modification and C6 money-path classes).
   - the **manual-command-delivery blast-radius classes**.
   - the **C1–C10 gate-manifest taxonomy**, whose C3, C4, C5 and C7 classes are already the "reversible, non-breaking" classes.

   These tables do not overlap, so the rule must OR them: any one is enough to send a change to a checkpoint. gate-classify alone misses every G2 surface (it returned B on all 7 probes below). Conviction >90 is the existing auto-proceed bar, and in the incident **0 of 59 live decisions** cleared it on a non-surface change. The only decision above 90 was `b4373234dd78` (92), and it touches an auth surface. So the operator's "reversible and lower stakes, just do it" cannot be met unless reversibility changes the conviction bar. That bar comes from the 2026-09-08 ruling, so changing it needs an operator ruling (open question 1).
2. **H2, the recycle path.** It works mechanically today with no new code. The operator replies in the session, and in that turn the agent runs `handoff-fire.sh --recycle [--worktree W] --prompt-file <impl brief naming the research doc> --goal '<impl end state>'` as its last act. The incident already used half of this flow on `bb7c893b31ba`: the operator replied, a session was fired, it landed, and the agent ran `cc-decide action`.
   - **Missing: a sign-off that arrives after the session is gone.** Nothing turns a class-C packet moving to `actioned` or `vetoed` into a wake or recycle of the session that filed it.
   - **cc-decide has no verb that records which option was chosen.** Its only verbs are `veto` and `action` ("carried out").
   - **Hazards:**
     - The goal is not inherited when the research goal is terminal or absent. The incident session had **0** `goal_status` records, so `--goal` must be passed explicitly.
     - A background `cc-await-ping` makes an armed `/goal` inert.
     - The recycle defers to the end of the turn and kills in-process children, such as running workflows or uncollected custody.
3. **H3, the signoff memory.** The new request **narrows** the standing rule; it does not contradict it. Conviction **80%**.
   - The memory, the "Delegated acceptance" contract and cc-signoff are all scoped to registered kit programs. The incident's cwd is not in one (measured below).
   - The checkpoint the operator now asks for is a one-line decision answer. He showed in the incident that he does give those. It is not a read of an artifact, which is what he refused to do.
   - Inside an active program, the delegation still governs.

---

## H1: reversibility and stakes rule

### Existing stakes classifiers (cited)

| # | Gate | Where | What it classifies | What it misses |
|---|---|---|---|---|
| 1 | **G1–G4 auto-continue** | `CLAUDE.global.md:610-614`; slim `CLAUDE.rules.slim.10-session-close.md:45` | G2 surfaces: "auth/session, destructive migration, navigation pattern, DB timeout"; G3: local action plus `/ship` where policy allows | money, third parties, publishing, C10 |
| 2 | **Follow-On Gate F1–F4** | `CLAUDE.global.md:651-671`; slim `:67-69` | F1 net-positive, F2 well-researched **plus a conviction number**, F3 same envelope (G2/G4 bind), F4 bounded. Line 668: "Asking the user to re-affirm an F1-F4 PASS is itself a defect" | no reversibility axis |
| 3 | **Conviction protocol** | `CLAUDE.global.md:657` ("If conviction of a decision is not >90% then research exhaustively, and then implement if now >90% or then ask"); `bin/cc-decide:29-35,100,209-214` (refuses any open with N>90: "implement it") | how sure the agent is of its course | blind to stakes: a 92% auth change passes F2 and still fails F3 |
| 4 | **E0 row** | `CLAUDE.global.md:721`; slim `:99` | "A read-only turn that NAMES drivable work is not E0: run the Follow-On Gate on each item and DRIVE the passes"; "Nothing on this box catches it" | no mechanism |
| 5 | **cc-decide A/B/C** | `bin/cc-decide:13-19` | A = already ruled and acted, the packet is the audit trail. B = default fires at a deadline ("async early-veto, never a sync approval"). C = C10 self-mod / C6 money-path / permission: waits, no default, should carry "staged one-action artifact + rollback one-liner" | the class is **chosen by whoever files the packet**; `cc-decide open` never calls gate-classify (the only reference is the comment at `:13`) |
| 6 | **gate-classify.sh** | `scripts/gate-classify.sh:5-15` (C checked first, can never be demoted to A, "ANY doubt routes B"); `:34` C_SURFACE; `:37` A_SETTLED | C: settings/hooks/launchd/plist/permission/credential/token/login/cookie/purchase/pay/sudo/self-mod. A: lexical "ship…green / net-positive / time-zero" | **no G2 terms** (`auth`, `session`, `migration`, `drop`, `timeout`, `router`), no `buy`, `publish`, `deploy` or `production`, no third-party contact. Only caller is prose: `hooks/cc-unattended-ask-guard.sh:63` |
| 7 | **gate-manifest C1–C10** | `scripts/gate-manifest.sh:2-18,42-62` | C3 "reversible refactor / cleanup (reversible with a tag)", C4 "additive test / doc / observability (no served-surface behavior change)", C5 "in-tree dependency / config change (non-escalation surface)", C7 "land verified net-positive work"; C6 money and C8 next-wave-go are conditional; C9 /ship and C10 self-mod are excluded | dormant: `gate-manifest.sh current` reports "no active (non-expired) manifest — nothing is pre-signed"; the store `~/.claude/autonomy/gate-manifest` does not exist; `sign` has no operator-ancestry arm (grep finds no `operator_sign`) |
| 8 | **manual-command-delivery blast radius** | `skills/manual-command-delivery/SKILL.md:20-28,47-53`; slim `CLAUDE.global.slim.md:197` | "**Reversible** ⇒ driven silently." Gated: "Irreversible, production-mutating, money-spending, credential-writing, or refused by a classifier or permission prompt." "Those five are the ONLY gate classes, and the list is EXHAUSTIVE" | covers operator steps, not code changes |
| 9 | **Project escalation greps** | `reso-management-app/CLAUDE.md:543-546` (grep `drizzle/migrations/*.sql` for `DROP (TABLE\|COLUMN)`, `*auth*\|*session*\|*cookie*\|*token*`, `router.push` vs `<Link>`, DB-timeout constants); infra `.claude/CLAUDE.md:18-30` (standing land), `:41-50` (standing converge) | per-repo G2 made concrete | only where a repo wrote them |
| 10 | **Operator-only acts (memory)** | `feedback-operator-will-not-read-signoffs.md` ("talking to third parties…, creating public repos, spending money, publishing, and sealed-set third-read overrides"); `feedback-autonomous-to-100-boundary.md` ("genuinely HIGH-RISK… money/auth builds, destructive migration… is a LEGITIMATE checkpoint") | external acts | not machine-checked |
| 11 | **Human-signed completion ruling** | `bin/cc-signoff:8-9` ("bottle service, floor plan HAS TO BE HUMAN SIGNED OFF") | named product areas | n/a |

**gate-classify's blind spots, measured** (`bash scripts/gate-classify.sh "<text>"`, 7 probes, all returned `B`): "land the auth change to session handling", "buy the dedicated Mac mini at 56 dollars a month", "publish the rebuilt homepage", "text the promoter today", "run the destructive migration that drops a column", "redeploy production", "write the chord into the tracked example config". So C_SURFACE (C10/C6) and G2 are **disjoint tables**, and gate-classify cannot stand in for G2. Its selftest is green: `gate-classify.sh --selftest` => `21 passed, 0 failed`.

### Proposed rule: a composition, nothing new invented

After research, for each implementation item X:

```
CHECKPOINT (class C, wait) if ANY:
  H-a  gate-classify(X) == C                                (C10 self-mod / C6 money; gate-classify.sh:34)
  H-b  X touches a G2 surface (+ the project's escalation greps)   (CLAUDE.global.md:612; reso CLAUDE.md:543)
  H-c  X is in a manual-command-delivery gate class: irreversible · production-mutating ·
       money-spending · credential-writing · classifier/permission-refused    (SKILL.md:26-27)
  H-d  X is an operator-only external act: third-party contact · public repo · publishing · purchase
       (signoff memory "Keep with him only acts no agent can do")
  H-e  X falls under a named human-signoff ruling (bin/cc-signoff:8-9)
  H-f  X's class in the gate-manifest taxonomy is C6 · C8 · C9-as-deploy · C10   (gate-manifest.sh:12-18)
AUTO-PROCEED (drive now; no packet, or a class-A trail) iff ALL:
  A-1  none of H-a…H-f
  A-2  X's taxonomy class ∈ {C3 reversible refactor, C4 additive test/doc/obs, C5 in-tree non-escalation config,
       C7 land verified}  — i.e. "reversible + non-breaking" in the fleet's OWN words (gate-manifest.sh:55-58)
  A-3  F1–F4 PASS (CLAUDE.global.md:651-671)  — F3 re-asserts G2/G4; F4 = finish→gate→commit
  A-4  conviction > 90 (CLAUDE.global.md:657; cc-decide:100)
  A-5  repo ship policy auto (CLAUDE.global.md:617-626 / project CLAUDE.md)
OTHERWISE (A-1 and A-2 hold, but A-4 fails, or it is a value fork the standing values don't settle):
  class B — default = the recommendation, a short deadline, default_effect change|no-change;
  the existing actuator fires it: cc-decide expire-sweep → autonomy-sweep files a backlog item against
  subject_project → cc-dispatch spawns a worker (autonomy-sweep.sh:18-24, 1189-1218; cc-dispatch:1-30).
```

Why this order: the checkpoint test runs first and can never be demoted. That mirrors gate-classify's asymmetry at `:9-14` ("a false-A ACTS on an unratified decision (catastrophic); a false-B merely queues"). The operator's word "reversible" maps onto C3/C4/C5/C7, and "non-breaking" onto C4's "no served-surface behavior change" together with G2.

**Gap the rule exposes (inferred from reading the code; I did not run it, because the brief forbids `cc-decide open`).** The refusal of conviction >90 at `bin/cc-decide:210` has no class guard. Yet its own message (`:211`) and `:221-222` tell the agent to "IMPLEMENT it (and file class A as the trail)". So a class-A trail cannot carry the >90 number that justified it. No test covers class A with N>90: `grep -n 'conviction 9[1-9]' tests/cc-decide.bats` finds only class-C cases at `:569,574`.

**Gap: packets record no reversibility.** The packet schema keys (from `cc-decide list --open --json`, first record) are: class, conviction, created, default_effect, default_if_no_veto, id, options, receipt, recommendation, route_around_taken, session_pane_uuid, session_sid, staged_artifact_path, status, subject_project, veto_deadline, what_plain. There is no reversibility field. Across the 59 LIVE re-checked packets (measured by a jq loop over `~/.claude/autonomy/decisions/<id>.json`): **1/59** has a `staged_artifact_path`, and **5/59** mention rollback, revert, undo or reversible anywhere in the what, options or recommendation text. Class C promises a "rollback one-liner" (`cc-decide:18-19`), but packets do not carry one. The A-2 test therefore needs a field declared by whoever files the packet. The precedent is `default_effect` at `cc-decide:48-69`, whose comment explains that inferring meaning from prose wording is the shape-classifier that must not be built.

### The incident's 74 decisions under the rule

**Source.** `~/.claude/autonomy/research/decision-recheck-2026-10-18/table.tsv` has 74 rows: LIVE 59, MOOT 15. I joined it to the packet files and ran gate-classify on what plus recommendation (`/tmp/rpic-H/join.py`, measured). I then hand-coded each LIVE row against H-a…H-f and A-2 (`/tmp/rpic-H/tiers.py`; the per-row reasons are in `/tmp/rpic-H/tiers.tsv`). **The tiers are my inference, not a measurement.**

**Packet class against the router (measured).** Of 57 LIVE class-C packets, gate-classify routes **45 as B and 12 as C**, and none as A. Filers over-use C, so the packet class is not a reliable stakes signal.

| Tier | n / 59 LIVE | Conviction | Examples |
|---|---|---|---|
| **T1 auto-proceed** (A-1…A-5) | **0** | n/a | only `b4373234dd78` is >90 (92), and it is a G2 auth surface (H-b), so it goes to a checkpoint |
| **T2 reversible, in-repo, non-surface, conviction ≤90**: class B, or auto if the operator lowers the bar | **12** | 62, 65, 70, 70, 75, 80, 80, 82, 85, 85, 88, 88 | `aae2ed87f5e2` write the kitty chord into the tracked example (C4/C5, 85) · `d4a4cc00d8a9` sky-blue focus-ring token (C5, 88) · `shipland-esc-86b7c96` land the July research docs that ship-land refused on a false positive (C4/C7, 85) · `6f7937778b05` delete /after-dark plus a 301 (git-revertable, 88) · `4fa97119fec0` archive branches as tags (C3, 62) · `4dce9ca65af4` and `56c6862291f2` handoff/launcher script behaviour with a kill switch (70, 75) · `5a3a17bc8977` remove the table-booking line (80) · `15792f2f3239` and `8599cb379db6` UX value forks (70, 65) · `0bcb44c79819` land K1 with ceiling 20 (80) · `bf8ca4704b7b` accept 13 recorded defaults (82) |
| **T2-nochange** (the recommendation changes nothing): class B with `default_effect no-change`, which never dispatches a worker | **10** | 60–80 | keep kitty width, keep load cap 8, keep Fable deliberate, keep the README line, decline the Turso A/B, don't buy the Linux box, drop the Azure preflight, keep five design choices, agentsync keep-rule, cloud lane stays on |
| **T3 checkpoint** | **33** | 60–92 | C10: `6b0e8ec5c970`, `88bb832a93c3`, `bdf17e77ae10`, `fd210155c6b6`, `1819ec8f4ebc`, `169adfa161af` (launchd), `ba5a4070d164` (install/deploy) · C6 money: `ad7b88aa886b`, `1a8aba9c99d3`, `3f41a96d7e87`, `747c966582f8`, `f3461cfebee3` · G2 auth: `1d0b3a2e5f8f`, `b4373234dd78` · production-mutating: `87a39bda74ed`, `918b96c143e9`, `9ab471897bc1` · third party or publishing: `27941a6880ea`, `586fd0d38e68`, `6ca67b7a0ed0`, `25314c12b75e`, `3af586c867bc`, `ee92750b4239`, `fb998d1cdccf`, `35551116505f`, `8daf14ec04b2` (its code half is T2) · human-signoff ruling: `8e0ccb1f19ed`, `f94c56446f07` · facts only the operator holds: `703a320486b8`, `b31f0fa39806`, `890d519cc58b` · disruptive standing rule: `ee0ad84e8974` (reboot) · C8-like autonomous spawn: `58d62776eb1f` |
| closed as duplicate / already done | 3 / 1 | n/a | `2015d93348ca`, `84939900d08f`, `c8295adf5c40` / `bb7c893b31ba` |

**The T3 tier against gate-classify.** Of the 33 T3 rows, gate-classify routes **23 as B and 10 as C**. On real decision text, then, the router under-detects the checkpoint set by about 70%, which is why H-b…H-e must be ORed in. It also over-detects in 2 cases: `shipland-esc-86b7c96` matched "password" quoted in research prose, and `bf8ca4704b7b` matched "token".

**Ownership (measured).** Packets filed by the incident session: **0 of 74** (jq `.session_sid` over the 74 packet files against `74728043…`). `wrap-ledger.sh` counts ⛔ only over packets whose `.session_sid == $SID` (`scripts/wrap-ledger.sh:1343,1500`). So a session that re-checks other sessions' packets has nothing of its own for the ledger to count.

---

## H2: the self-recycle path

### Mechanics that exist today

- **`--recycle`** (`scripts/handoff-fire.sh:153-183`). It exits and relaunches the same pane, never `/clear` plus a queued payload. It composes with `--worktree`/`--cwd` (the "relocating recycle", `:176-183`) and with `--account`. The payload goes in through `--prompt-file`, which is REQUIRED (`:14`).
- **Mid-turn.** "the recycle is DEFERRED to the end of the turn… End the turn; do not re-run" (`:171-175`). `hf_recycle_defer` at `:5289-5348` prints "END YOUR TURN NOW and start no other work".
- **`--goal COND`** (`:17-39`). This is message 2, armed after engagement is proven. It is limited to one line of at most 794 chars, and it is "re-armed across --recycle".
- **`inherit_recycle_goal`** (`:9707-9724`, called at `:19006`; the background-job path is `:6866`). With no `--goal`, it inherits the predecessor's **LIVE** goal. "a terminal goal (met/failed/cleared) inherits nothing" (`:18995-19001`). In resume mode it inherits nothing (`:19002-19005`). Tests are named in `tests/handoff-goal-arm.bats:402-456`. I tried to run them, but `bats -f inherit tests/handoff-goal-arm.bats` returned `cc-bats: REFUSED — 2 concurrent bats execution root(s)… this is a DEFERRAL, not a test result`, so they did **not run**.
- **Disposition rule.** ♻️ Recycle applies when "Everything of value is already on disk (committed · plan · memory · packet)" (`CLAUDE.global.md:798`). `commands/handoff.md:456-466` says "Mode A fire (single track) → RECYCLE this pane, not a new pane", and the `--goal` default is at `:203-216`.
- **Doc drift.** `commands/handoff.md:314-315` still says "a `--recycle` successor carries none (measured). `--goal` re-arms it". The code inherits by default (`handoff-fire.sh:18995`), and `hooks/goal-inert-watch.sh:34-38` says so too. This is stale but harmless.
- **`hooks/session-continue.sh`** does not take part in a recycle. Its floors fire only on own uncommitted writes, 📦/🚀, pending mail or an armed sentinel (`:1291`; `CLAUDE.global.md:721`: "every `session-continue.sh` floor is gated on session WRITES, pending mail, or an armed sentinel"). So a research turn trips none of them.
  - It already reads the operator's last real message for stop phrases (`KILL_RE`, `:386`; `.isMeta` filter, `:407-442`). That is the existing parser of operator replies.
  - Its sentinel is bound to the arming sid, so a recycled successor does not inherit it (`:29-31`).

### Which event carries the sign-off

| Carrier | Exists? | What happens today | What is missing |
|---|---|---|---|
| **Operator reply in the session** | **Yes, and used in the incident** | Transcript line 493 (1-indexed JSONL): operator "dedicated handoff session the item for <`bb7c893b31ba` block>". Line 507: `Skill(handoff)`. Line 545: `handoff-fire.sh --prompt-file /tmp/fire-ssn-image.txt --repo …reso-landing-app --worktree ssn-image-fix`, a **new** session, because the operator asked for one. Line 623: "It's done… the decision is marked actioned". | Nothing. A `--recycle --prompt-file --goal` in the reply turn is the same machinery. The only rule needed: a reply that answers the checkpoint is the sign-off, and the agent records it with `cc-decide action <id> --evidence "operator in-session <ts>"` once the work lands. |
| **`cc-decide action/veto`** (operator runs it out of band) | Verbs exist (`bin/cc-decide:36-37,350-374`) | Changes status only. The only consumer of `actioned` is `scripts/c10-batch.sh:73-105`, which holds migrations until a packet is actioned. Measured with a grep for `actioned\|vetoed` over hooks/, scripts/ and bin/. | **New:** (1) an `answer <id> --option <label>` verb. `action` means "the decision was carried out" (`:37`), not "approved option X". (2) An actuator that, when a packet changes to actioned or vetoed and its `session_pane_uuid` is live, `cc-notify`s that pane. That wakes it through its armed `cc-await-ping`, and the session then recycles. Packets already store `session_sid` and `session_pane_uuid`. |
| **`cc-signoff`** | Exists, but for other domains | Covers customer rows plus `research:<slug>/…` (`bin/cc-signoff:55-75`). It refuses any claude ancestor (ARM 1, `:17-21`), so it cannot run under `!`. | **Wrong carrier for ordinary sessions.** There is no row type for "session X: research → implementation". It needs the operator's own terminal, which is the friction the memory rules out. A new `research:` target would only be meaningful inside a program. |
| **Class-B default at deadline** | **Yes, end to end** | `cc-decide expire-sweep` marks the packet `expired-actioned` and prints `fired <id> <project> <change\|no-change> <default>`. `autonomy-sweep.sh` (launchd, 300 s) then files a cc-backlog item against `subject_project`; `no-change` files nothing (`:18-24`, `:1189-1218`). `cc-dispatch --once` spawns a worker (`bin/cc-dispatch:1-30`). | It spawns a **new worker**, not a recycle of the session that filed the packet. That is fine for T2: the brief must sit in the default text or name the research doc. |
| **gate-manifest pre-signature** | Exists, never used | `sign --wave --classes C3,C4,C5,C7` auto-ratifies the classes it names (`gate-manifest.sh:4-9,21`) | No ancestry arm. Scoped to waves, not sessions. An operator-run standing sign of C3/C4/C5/C7 is the natural way to record the 10-18 directive "reversible → just do it" as data. |

### Recommended mechanical sequence (no new code needed for the reply carrier)

1. Research turn ends. The research doc is persisted durably. In the incident, `/tmp/xd/REPORT.md` was named in the close, which a reboot erases, and was only copied to `~/.claude/autonomy/research/decision-recheck-2026-10-18/` later (JSONL line 597). T1 items are driven. Each T3 item is filed as class C and each T2 item as class B. The close leads with "research done — implementation pending your sign-off" (other slots own that shape).
2. The operator answers in the session.
3. In the reply turn, the agent writes `/tmp/fire-impl-<slug>.txt` (locate line, research-doc path, the approved item ids, DoD). As the **last act** of the turn it runs `handoff-fire.sh --recycle [--worktree <impl>] --prompt-file … --goal '<impl end state>; DoD at <path>'`.
4. The successor implements, lands, and runs `cc-decide action <id> --evidence <sha>`.

### Hazards

1. **The goal is not carried over unless passed.** When the research goal is met or absent, nothing is inherited (`handoff-fire.sh:9707-9724`). The incident session had **0** `goal_status` records: `grep -c '"goal_status"' <incident jsonl>` => `0`. Always pass `--goal` explicitly. Never let a still-live research goal be inherited into the implementation session, because an explicit `--goal` is the only way to override it (`:9709`).
2. **Background Bash makes /goal inert.** Any non-terminal `local_bash` task defers goal evaluation; `cc-await-ping` is one, measured "2h / ~12 turns / 0 evaluations" (`hooks/goal-inert-watch.sh:42-50`). The incident session armed `cc-await-ping --timeout 3300` in the background (JSONL line 702; `cc-await-ping` appears in 28 records). A successor that arms the same watcher has its goal backstop silently skipped.
3. **The recycle clears the goal on the background-work dialog.** When `/exit` raises "Background work is running", the watcher dismisses it, runs `/goal clear` on the **predecessor**, and re-submits (`handoff-fire.sh:11210-11225`, `:11667-11670`). The successor's goal is `$8`, captured before that point. It is lost if no `--goal` was passed and the inherited goal was empty.
4. **"Clean+landed ≠ nothing in hand"** (`.claude/rules/agent-operating-lessons-situational.md:167`). A recycle kills in-process children. The incident session still had 4 dispatched sessions plus workflows outstanding (JSONL line 706, "4 dispatched session(s) have NOT returned"). Recycle only after custody returns, or the custody debt (`bin/cc-custody`, `CLAUDE.global.md` floors §(2)) is left dangling under a new sid.
5. **Mid-turn deferral.** The recycle runs after the turn ends. Any further prompt, or a draft left in the composer, holds it (`handoff-fire.sh:5348`). The sign-off reply turn must do nothing after the fire.
6. **The sid changes on recycle.** Packets filed by the research session carry the old `session_sid`, so the successor's ledger shows them as not its own (`wrap-ledger.sh:1343`). An actuator that wakes on packet changes must key on the pane, or on the recycle chain (`handoff.md:654-661`, "recycle-engaged" rows).
7. **Wrong model.** If implementation needs a different model, recycle is not available and it becomes a 📤 handoff (`CLAUDE.global.md:800`).

---

## H3: does the request narrow or contradict the signoff memory?

**Texts.**
- **Memory**, `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/feedback-operator-will-not-read-signoffs.md`:
  - Its description is "research programs run zero human in loop via a one-time delegated acceptance".
  - It quotes the operator: "I WILL NOT look at any of the contenet for said sign off as this has to be exhaustive research into exhaustive plan into exhaustive implementation, zero human in loop".
  - How to apply: "never stop a research **program** to ask the operator to 'read and sign'"; "Keep with him only acts no agent can do: talking to third parties…, creating public repos, spending money, publishing".
- **`scripts/research-kit/RECORDS.md:909-985` ("Delegated acceptance").** The delegation covers a registered slug or `*` ("every registered program"), and only the kit actions cert, frame, implementation, extra-round, profile, adopt, extend-decision and reopen. Vetoes and third reads stay with the operator.
- **`bin/cc-signoff:1-6,55-75`.** Its domain is customer rows and `research:<slug>/…` only.
- **Operator, 10-18, verbatim** (JSONL line 567, a `queued_command` attachment with `origin.kind=human`, 2026-10-19T02:50:55Z): "…I would expect a human checkpoint sign off, but have our stop hook status very clearly and at the top indicate the Pyramid Principle leading with the answer status, and then once good to go, self-recycle into implementation, or if its reversable and not breaking changes and lower stake, to just do so."

**Live scope (measured).**
- `~/.claude/autonomy/research/delegations.jsonl` holds one `{"program":"*","action":"delegate","at_iso":"2026-10-17T07:26:02Z"}`.
- `programs.json` registers one program, `truememory-2-0`, state `certified`, with `cwd_roots` `[…/.worktrees/tm2-plan]`.
- `bash ~/.claude/scripts/lib/research-program.sh is-active /Users/chrisren/Development/.worktrees/wt-cc-192325-42328` => `rc=1`.

So the incident session was **not** in a program. The delegation, the exemption at `CLAUDE.global.md:673-699`, and the memory's how-to-apply did not reach it.

**Case that it CONTRADICTS.**
- The 10-16 quote names exactly this transition ("research into … plan into … implementation") and says "zero human in loop… before moving on". The 10-18 request puts a human at research → implementation.
- The memory's description generalises. Its body says "The operator will not read **any** artifact before a signoff".
- A reader who applies the memory fleet-wide would treat the new checkpoint as a reversal. The later ruling would then win, and the memory would be stale.

**Case that it NARROWS.**
1. **Disjoint scope.**
   - Every operative clause of the standing rule names programs or kit verbs. The delegation is keyed to registered slugs, and the exemption is keyed to the registry: "The key is the registry, never a DoD marker or the wording of a prompt" (`CLAUDE.global.md:695-697`).
   - The 10-18 request concerns ordinary sessions ("We almost always never research for the sake of research").
2. **Different object.** He refused to *read content* ("will not look at any of the content"). The new checkpoint is a one-line, answer-first decision with a conviction number.
   - Twice in the incident he answered such lines without reading the 126 KB REPORT.md: JSONL 472 (asked "What is on October 23rd…") and 493 (OK'd `bb7c893b31ba` by pasting its line).
   - The memory itself keeps acts no agent can do with him. Those are the T3 set: 33/59 rows, mostly third-party, money, publishing and C10.
3. **The same rule appears in both.** "Reversible, non-breaking, lower stakes → just do it" is the zero-human half restated for ordinary sessions. It matches the 07-19 boundary memory: "routine = drive silently; high-risk money/auth/destructive = legitimate checkpoint".

**Verdict: it NARROWS. Conviction 80%.**
- The new checkpoint applies to ordinary sessions, and only to T3 (plus T2 unless he lowers the bar).
- Inside an active program (`research-program.sh is-active` exit 0), the delegated acceptance governs and no checkpoint is inserted.
- The remaining 20% is the risk that he meant "zero human in loop" universally. Even then, the later 10-18 words govern for ordinary sessions, and the build is the same either way. The memory should gain one scope line saying so (recommendation 6).

---

## Open questions

1. **The conviction bar for reversible items.** Should reversibility (C3/C4/C5/C7 and no H-a…H-f) lower the >90 bar, for example to ≥80 with a revert one-liner? Doing so amends the 2026-09-08 ruling. As things stand, 0/59 auto-proceed, and 12 T2 items at 62–88 need a checkpoint the operator said he did not want for "lower stake".
2. **"Just do it" for T2.** Should it mean act now with a class-A trail plus rollback, or class B (act at the deadline unless vetoed)? Class B already actuates end to end. Act-now matches his wording better.
3. **Should C9 (`/ship`) stay in the excluded set** while the global ship policy says auto-`/ship` (`CLAUDE.global.md:617-626`)? The manifest was written before standing-land.
4. **Recycle or fire a new session for implementation?** In the incident he asked for "dedicated handoff session" on `bb7c893b31ba`. The 10-18 request says "self-recycle". Is the choice per item, or recycle by default?

## Recommendations

1. Put the H1 composition into one predicate, owned by gate-classify or a sibling: H-a…H-f first and never demotable, then A-2…A-4. Add G2 and project-grep terms (`auth`, `session`, `migration`, `DROP`, `timeout`, `router.push`) plus `buy`, `publish`, `deploy`/`production` and third-party verbs. Do not widen the C10 meaning of C_SURFACE: emit a distinct reason so the class stays honest.
2. Add filer-declared `--reversible yes|no --rollback "<cmd>"` and `--change-class C3|C4|C5|C7|…` fields to `cc-decide open`, which fail open the way `default_effect` does (`cc-decide:48-69`). Today 1/59 packets carries a staged artifact.
3. Fix the gap at `cc-decide:210`: exempt class A from the >90 refusal (the trail of a decision already made), and add the missing bats case.
4. Add `cc-decide answer <id> --option <label>` and a sweep arm that `cc-notify`s a live `session_pane_uuid` when a packet changes, so an out-of-band sign-off wakes the filing session.
5. Write the recycle recipe into `commands/handoff.md`: explicit `--goal`, last act of the turn, custody returned first, research doc durable first. Also fix the stale `:314-315` line.
6. Add a scope line to `feedback-operator-will-not-read-signoffs.md`: "applies inside registered research programs; ordinary sessions use the research→implementation checkpoint for T3 only". Operator memory is not this slot's to write.
