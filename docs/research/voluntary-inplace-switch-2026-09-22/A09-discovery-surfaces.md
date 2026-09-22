# A09 — Discovery surfaces for a VOLUNTARY in-place account switch

**Question.** Where must a voluntary in-place account switch be advertised so the session that needs
it actually reaches it, and who decides to fire it?

**Verdict, three lines.**

1. The capability is **fully built, one command, measured live today** — and so is the *verdict* that
   says whether to use it. Nothing is missing on the capability axis.
2. The discovery gap is worse than "nothing references it": **two always-resident instruction
   surfaces state that an account change REQUIRES a new pane**, which the code refutes. An advisory
   cannot outrank a resident instruction that says the thing is impossible — fix that first.
3. The switch verdict today runs **only as a passenger on a context-triggered recycle**. There is no
   surface on which account pressure is the *trigger*. That is the whole build.

---

## 0 — The live instance, measured while writing this (the strongest single finding)

This report's own pane is the failure it describes. Run 2026-09-22 from
`~/Development/claude-infrastructure`, `--dry-run`, nothing launched:

```
$ CC_RECYCLE_SUBAGENT_GATE=off bash scripts/handoff-fire.sh --recycle --prompt-file X --dry-run
♻ recycle RE-PICK: next2 → next3 — next2 is NOT routable (kmax-concurrency);
  router: claude-accounts --route general (kill switch: CC_RECYCLE_REPICK=off)
account:  next3
launcher: claude3
surface:  (recycle — this pane: 540)
```

And with an explicit target:

```
$ … --recycle --account next2 --prompt-file X --dry-run
account:  next2   launcher: claude2   surface: (recycle — this pane: 540)
command:  cd <repo> && nocorrect CC_ACCOUNT_PINNED=1 CLAUDE_ISOLATION_SKIP=1 claude2 … "$(cat X)"
```

So: **this pane is on an account the router has EXCLUDED, the switch verdict is one read-only
command away, and no surface in the fleet told the session.** The rank confirms it independently —
`claude-accounts --rank general` prints `general excluded — next=keychain…no OAuth credentials;
next2=kmax-concurrency`, `repick_ratio=4`, and only `next3 0.000018 / next4 0.000009` are routable.

---

## 1 — What already exists (capability axis: closed)

| Piece | Where | State |
|---|---|---|
| In-place switch actuator | `scripts/handoff-fire.sh` `--recycle --account <acct>` (parse `:8847`; recycle branch `:9706-9750`) | **Built.** Exit-then-relaunch in the SAME pane = a NEW process, so launch-time account identity is honoured, not violated — the same argument already recorded for `--model` at `docs/plans/NONLIMIT_RESUME_LADDER.md:709-711` |
| Automatic re-pick | `recycle_repick()` `scripts/handoff-fire.sh:9456`, called `:9742` | **Built and LIVE on every `--recycle` with `--account auto`** (the default). Re-picks on exclusion *and* on measured pressure |
| The pressure threshold | `bin/claude-accounts:1988` `REPICK_RATIO_DEFAULT = 4.0`, emitted on every route-meta as `repick_ratio=` (`:6266`) | **Built.** Deliberately "orders of magnitude, not percent … raising it makes the re-pick rarer, never wrong" (`:1985-1987`) |
| Transcript-preserving variant | `scripts/limit-recover/lr-handoff.sh --in-place --target <acct>` | **Built, and opened for THIS use today**: `:806-810` records that a healthy self-recovery probes `REFUSED:not-limited`/rc 5 and that the rc is deliberately ignored, because refusing it "would refuse every self-recovery of a session that is merely low on context **or being moved to a fresher account**" (dated 2026-09-22) |
| Read-only verdict probe | `handoff-fire.sh --recycle --prompt-file <f> --dry-run` | **Built.** Prints the `♻ recycle RE-PICK` line and the target account, launches nothing, charges nothing (`--assign` is gated on `DRY=0`, `:9556`-ish in the repick tail) |
| Self-knowledge | `bin/cc-context --me --quota` (`:19`, `:107-125`) | **Built, but half.** Fuses own fill with **own** account's headroom — no comparison to other accounts, no verdict. The comparison is `claude-accounts --rank general` |

**Alternative ruled out:** a new `cc-switch` binary. Every part exists; a new entrypoint would be a
second routing opinion, which `recycle_repick`'s own comment forbids in terms — *"A threshold
hardcoded HERE would be a routing policy authored outside the router and free to drift"*
(`handoff-fire.sh` repick block, pressure half).

---

## 2 — The three discovery defects, ranked

### D1 — The resident instructions say it is impossible (the blocking one)

| Surface | Line | What it says |
|---|---|---|
| `CLAUDE.global.md` | **:715** | `📤 Handoff` = *"Work remains AND it needs a setup THIS PANE CANNOT BECOME — a different **account** or **model** (both are launch-time identity)"* |
| `commands/handoff.md` | **:426** | *"Recycle first; spawn a new pane only for what a pane cannot BECOME (a different account or model)."* |

Both are **false as written**, and the repo already knows it for the `model` half: the same
`CLAUDE.global.md` § Frontier Tier Routing says *"The ladder is three same-pane recycles, each a NEW
process, so launch-time model identity is honoured: `handoff-fire.sh --recycle --model
claude-fable-5-1 …`"*, and `NONLIMIT_RESUME_LADDER.md:709-711` refutes the premise explicitly. The
**account** half is uncorrected in both files.

This is the *exact shape* of the 2026-08-08 worktree correction one field over
(`CLAUDE.global.md` § Context Stewardship: *"'It needs a fresh worktree' is NOT a reason to Handoff
— that was a TOOL LIMIT, and it is gone"*). Same sentence, same table, same remedy — and the cost
named there was a pane that *"survives holding nothing"*, idling from 05:39 on.

**No advisory can fix this.** A hook that says "switch in place" arrives out-of-band and attributed
to a hook, against a resident instruction the model reads as operator intent. `boundary-handoff.sh:32-35`
already records that the model *"may classify it as a prompt injection and refuse (observed: same
payload, opposite outcomes across two runs)"*. Correct :715 and :426 first; everything else is
downstream.

### D2 — The verdict is a passenger, never a trigger

`recycle_repick` runs **only when a recycle is already happening**. Every trigger for a recycle in
this fleet is CONTEXT or INTERRUPTION:

| Trigger | Where | Keys on |
|---|---|---|
| idle free-win / rot / size | `hooks/waiting-recycle.sh` §4 (header `:56-63`) | `used_pct`, transcript bytes, RSS |
| boundary advisory | `hooks/boundary-handoff.sh` (header `:1-4`, `:36-40`) | `used_pct`, burn forecast, size |
| interruption | `commands/recover.md`, `lr-fleet.sh` | death predicates |

Account pressure is **never** a trigger. The measured hole is narrow and exact: `waiting-recycle`'s
adaptive idle threshold floors at `T_IDLE_FLOOR=25` (`:56-59`), so **a session idle below ~25% fill
never recycles** — and that is precisely the session for which a switch is free (nothing to lose).
A session idle at 12% fill on an excluded account sits there forever.

### D3 — The one account surface is invisible to the model and fires once

`hooks/accounts-board.sh` is the fleet's only standing account surface. Its header (`:7-16`) records
the channel decision in the product's own terms:

- top-level `systemMessage` → **renders in the operator's terminal, 0 model tokens** ✅ chosen
- `additionalContext` → enters model context, billed every start ❌ rejected

So the board reaches **the operator, at SessionStart, once, and the model never sees it**. It is also
`compact`-excluded (`:69-74`) and `source`-gated. Its producer `com.claude.accounts-keepwarm` IS
loaded (pid 60819) but the file was 8 min old when read against `CC_BOARD_STALE_S=300` — i.e. a
session starting now gets the `⚠ STALE by 8m` band.

---

## 3 — (a) Surface enumeration: does the advisory belong there?

Ordered by decision value. "Reaches" = who actually receives the bytes.

| # | Surface | File:line | Reaches / when | Exact text or row to add | Verdict |
|---|---|---|---|---|---|
| S1 | **Resident disposition table** | `CLAUDE.global.md:715` | **Model, every turn, every session** | Replace the account clause: `📤 Handoff — Work remains AND it needs a setup THIS PANE CANNOT BECOME — a different **model**, or this pane should retire. 🚨 **A different ACCOUNT is NOT one of these** — `--recycle` is exit-then-relaunch, a NEW process, and `--account <acct>` composes with it (`handoff-fire.sh:8847`); a bare `--recycle` already RE-PICKS the account under router pressure (`recycle_repick`, `:9456`). Moving accounts is a ♻ Recycle, not a 📤 Handoff.` | **YES — do this first.** Only surface with 100% session reach; currently carries the opposite claim |
| S2 | **`/handoff` command body** | `commands/handoff.md:426` | Model, when `/handoff` loads | Replace *"spawn a new pane only for what a pane cannot BECOME (a different account or model)"* with *"spawn a new pane only when this pane should RETIRE — a different account rides `--recycle --account <acct>`, and a bare `--recycle` re-picks it automatically; a different model rides `--recycle --model`"* | **YES.** Same defect, second copy; a single-file fix would leave the other contradicting it (repo lesson: *integrating review findings by local edits manufactures contradictions*) |
| S3 | **`boundary-handoff.sh`** (Stop) | `hooks/boundary-handoff.sh`, emit `:721-723` | **Model, at the moment it goes idle.** Registered, latched, `decision:"block"` | Add an ACCOUNT arm beside the forecast/size arms, firing ONLY on `ratio ≥ repick_ratio` ∧ SAFE ∧ low fill. Reason text: `♻ Your account is not the one to be spending: <cur> scores <c> against <best> at <b> (router threshold <r>x). Nothing of yours is in flight and your context is cheap to rebuild, so this is a FREE move: bash ~/.claude/scripts/handoff-fire.sh --recycle --prompt-file <dod> (bare --recycle re-picks for you).` | **YES — the carrier.** Only registered, model-facing, turn-boundary surface that reaches an idle session with no migration |
| S4 | **`waiting-recycle.sh`** (PostToolUse:Bash) | `hooks/waiting-recycle.sh:56-63` (trigger §4), emit `:1112` | Model, between polls of an ACTIVE desk | Add ACCOUNT as a 4th orthogonal trigger axis beside `used_pct` / rot-tell / SIZE | **Second, not first.** Architecturally the right home (it owns SAFE/BUSY, cooldown, cap, shadow-then-arm), but it is **registered `PostToolUse` matcher `Bash` ONLY — never `Stop`**, so it "structurally cannot fire at idle-at-the-prompt" (`docs/research/idle-recycle-not-proactive-2026-08-08.md`, gate C, re-verified live in `~/.claude/settings.json` today). It is also `disarmed` on 2 of 5 config dirs — same doc, gates A/B |
| S5 | **SessionStart accounts board** | `hooks/accounts-board.sh` (whole file); producer `bin/claude-accounts --keepwarm` `:5927`, renderer `--readout --narrow` `:64-68` | **Operator only, 0 model tokens**, at start/clear/resume | Add ONE line to the renderer (never to the hook — `:22-30` forbids the hook forking `claude-accounts`): `♻ pane <N> is on <cur>, which the router excludes (<reason>) — it can move in place: --recycle --account <best>` | **YES, for the operator half.** Must go in `render_readout` so there is ONE renderer (`commands/accounts.md:40-55`). Cannot be the trigger: model never sees it, fires once, currently in the STALE band |
| S6 | **`/accounts` command** | `commands/accounts.md` (no line mentions moving an existing session; only `/handoff` and `/resume-sessions` appear under "Consumers") | Model, when it asks *"which account should I use"* | Add a § **Moving a session that is already running**: the trigger phrases, the one command, the read-only probe, and the explicit statement that this is a Recycle not a Handoff | **YES.** This is the `/limit-recover` defect verbatim: the skill description already fires on *"which account should I use"*, and the body answers only for a NEW unit |
| S7 | **`operator-readout.sh`** (Stop) | `hooks/operator-readout.sh:12-15` — *"pure-advisory `{"systemMessage"}` — NEVER `decision:"block"`"* | **Operator only**, every write-turn close | — | **NO.** Cannot reach the model by design; and this hook's contract is the operator's *pile*, not a session's own disposition |
| S8 | **`scripts/wrap-ledger.sh` / the close rungs** | grep for account/quota returns ONE incidental hit (`:2023`) | Model composes S1 of the close from it | — | **NO new rung.** The rung ladder is MECE over *work state* (⛔📤🔧📦🚀👤✅); "wrong account" is not a work state and would fire on a session with nothing open — the alarm-polarity defect `CLAUDE.global.md` names for `👤`. Correct home is S3, which already blocks |
| S9 | **`session-continue.sh`** (Stop) | `hooks/session-continue.sh`, floors gated on session WRITES / mail / armed sentinel | Model, forces next turn | — | **NO.** Its floors are attribution-gated on *your own uncommitted work*; an account fact has no author and would make the mechanical arm fire on a clean session |
| S10 | **Statusline** | `statusline.sh:276` — *"WHICH account and HOW FULL are the two fields read on a glance"* | **Operator only**, every render | Optionally a `♻` mark beside the account glyph when the incumbent is excluded | **Marginal.** Already carries the account identity; adding the *verdict* costs a fork per redraw (the exact cost `:80-90` measures and defends). Defer |
| S11 | **`cc-digest`** | `bin/cc-digest:3-17` — *"the DESIGNED operator touch: batched, never an interrupt"* | Operator, morning | A count of switches taken/declined, if the IDL records them | **Later, for the tally only.** Never the trigger — it is explicitly the never-interrupt surface |
| S12 | **Mailbox + asyncRewake** | `hooks/mailbox-wake-arm.sh` (SessionStart, `asyncRewake:true`, `timeout:14400`, live in `~/.claude/settings.json`); transport `bin/cc-notify:30-36` | **Model, on an ALREADY-idle session** — the only such path | A producer-written line: `♻ <cur> is excluded (<reason>); this pane can move in place — …` | **The only way to reach a session idle for hours**, and the one to use SPARINGLY: each wake burns a model turn, and a >1h-idle wake pays full `cache_creation`, which `hooks/cache-expiry-warning.sh:47` records as a charged class. Spending the expensive account to say "stop spending the expensive account" is self-defeating unless the fire is deterministic. **Use only if S3 is proven insufficient** |
| S13 | **`desk-brief-inject.sh`** | `hooks/desk-brief-inject.sh:1-12` | Model, SessionStart, **desk role only** | — | **NO.** Role-scoped to one pane; and `~/.claude/cc-roles/desk` has been absent since 2026-07-26 (same header, `:19-26`) |
| S14 | **`activation-watch.sh`** | `hooks/activation-watch.sh:16-22` | Model, SessionStart, advisory | — | **NO.** Explicitly *"NO LONGER WHERE NEW WIRING GOES"* — a registration now lands as a migration |
| S15 | **`cc-context --me --quota`** | `bin/cc-context:19`, `:107-125` | Model, on demand | Extend to emit `{repick: {best, cur_score, best_score, ratio, threshold, reason}}` by reading `claude-accounts --rank general` it already forks | **YES, as the PULL half.** This is the documented *"stay or go?"* primitive and it currently cannot answer "go where" |

---

## 4 — (b) Which advisory already computes account state at a turn boundary?

**None does — and that is the finding.** Full census of what each turn-boundary surface reads:

| Surface | Event | Reads account/quota? |
|---|---|---|
| `boundary-handoff.sh` | Stop | **No** — telemetry `used_pct`, forecast, size only |
| `session-continue.sh` | Stop | No — git/session-writes |
| `operator-readout.sh` | Stop | No — backlog/decisions/pending-activation + git |
| `completion-assert.sh` | Stop | Incidental mention only |
| `wrap-ledger.sh` | /wrap | No (one incidental hit `:2023`) |
| `waiting-recycle.sh` | PostToolUse:Bash | No |
| `cache-expiry-warning.sh` | UserPromptSubmit | Reasons about **charge class**, not account identity (`:47`) |
| `accounts-board.sh` | SessionStart | **Yes — and it is the only one.** Operator-facing, `cat` of a pre-rendered file, once |

**The computation that must be carried already exists in one place and must not be re-derived:**
`recycle_repick()` (`handoff-fire.sh:9456`). Its inputs are one bounded call —
`claude-accounts --rank general` — yielding (i) the `<name> <score>` lines, (ii) the
`general excluded — <acct>=<reason>` stderr map, (iii) the `repick_ratio=` on the route-meta. One
call answers exclusion *and* magnitude, which the function's own comment says is why `--rank` was
chosen over `--route`.

**Recommendation:** factor that read into `hooks/lib/` (beside `context-econ.sh`, which
`boundary-handoff.sh` and `waiting-recycle.sh` already share) so **one** predicate serves the
actuator and the advisory. Two spellings of "is this account worth spending" is the sibling-auditor
defect this repo has recorded repeatedly (`sibling-auditors-must-share-the-state-model`).

**No new daemon is needed on either side.** `com.claude.accounts-keepwarm` is already loaded and
already sweeps + renders every tick; `claude-accounts`' own 90 s shared cache means the hook's read
is a cache hit, not a sweep.

---

## 5 — (c) Agent-initiated, operator-initiated, or advisory-then-agent?

**Recommendation: ADVISORY-THEN-AGENT for a session's own pane; ADVISORY-ONLY for a peer's.** The
split is mechanical, not stylistic — the classifier already enforces it.

| Case | Ruling | Why, from the repo's own rules |
|---|---|---|
| **A session switches ITSELF** | **Agent fires it, no ask** | Follow-On Gate F1-F4 passes cleanly: F1 net-positive (the router already priced it); F2 well-researched — the verdict is a live read with a receipt, not speculation, and conviction is the router's own ≥4× ratio; F3 same safety envelope (G3: local, sanctioned rail — `--recycle` is the documented succession, not a deploy); F4 bounded by the 4× threshold and `CC_RECYCLE_REPICK=off`. The direct precedent is **`/frontier-run`**: *"AGENT-INITIATED under the bounded-autonomy policy … the human never model-switches or starts frontier sessions"*, bounded by `hooks/frontier-spawn-gate.sh` and a kill switch. Empirically, self-recycle is already routine and unasked: `git log` carries `docs(drain): recycle #332/#333/#334` |
| **A session switches a PEER's pane** | **Advisory only — file it, never fire it** | Measured: in `--permission-mode auto` the classifier refused `kill <claude pid>`, `cc-teardown <pane>`, and even `cc-notify <pane> "… run /exit now"` — *"the boundary is the TARGET being a live Claude session, not the verb"* (memory `auto-mode-classifier-denies-acting-on-a-live-session`, 3 refusals / 3 tools, 2026-09-04). A peer-directed switch is the same class |
| **A DAEMON switches a peer's pane** | **Allowed in principle, gated in practice** | `lr-fleet.sh` already does exactly this shape for recoveries (`lr-fleet.sh:18` — *"one actuator, two callers … lr-handoff.sh --in-place"*), sequenced + capacity-gated. But arming an unattended loop that spends quota is a standing operator call: backlog `c109e9e850fb` records the classifier refusing precisely that write, *"correctly, since an agent should not arm its own autonomous spend"* |
| **Registering a NEW hook for this** | **Operator (c10)** | Any `settings.json` edit is c10 by fleet rule. Cost is real and current: `hooks/recover-inject.sh` — the precedent's OWN remedy — is landed with `tests/recover-inject.bats` 18/18 + 5 mutants killed, staged as `migrations/0026`, and **is absent from the live `settings.json`**; `net-recover-arm.sh` (`migrations/0030`) likewise. The `/recover` discovery fix is itself sitting undiscovered behind an unrun migration |

**The design consequence of that table:** put the advisory on a hook that is **already registered**
(`boundary-handoff.sh`), because a new registration inherits `0026`'s latency. And prefer a
**deterministic fire over a model-facing advisory for the idle case** — a hook firing
`handoff-fire.sh --recycle` costs zero model turns, and an idle session's state is
disk-reconstructible, which is precisely the argument `waiting-recycle.sh` Stage 2 already makes
(`:22-27`). Ship it SHADOW-then-`arm --live`, exactly as that hook does.

**One explicit non-recommendation:** do NOT make this a `⛔`/decision packet. The `cc-decide open
--class C` gate demands `--conviction N` with `N ≤ 90`; conviction here is above 90 by construction
(the router's own ≥4× threshold), and `CLAUDE.global.md` § F2 says above 90 *"there is nothing to
ask, so you implement"*. Filing it would be the deference-fishing defect.

---

## 6 — (d) Command text and wording that avoids the `/limit-recover` defect

**The precedent, stated precisely.** `commands/limit-recover.md:3` enumerated *error spellings*
(`"You've hit your session/weekly limit"`, `invalid_grant`, …). `commands/recover.md:24-31` replaced
them with a **structural class** — three predicates (process boundary, api-error record, non-success
notification) and the explicit note *"A denylist of spellings is not a class."*

**The voluntary switch is HARDER than either, and this must be said in the design, not discovered
later: its trigger is a NON-EVENT.** Nothing happens. Nothing errors. The session is healthy and
idle. There is no text to match, no record to structurally detect. Therefore:

> **A description can never be the carrier here. It can only be the landing page.** The push must be
> a hook (S3); the description's job is to make the hook's one command legible and to catch the
> operator/agent who asks the question unprompted.

### Trigger phrases an operator or agent would ACTUALLY use

Collected by asking what a session or human says at the moment the switch is right — deliberately
including the *healthy-state* phrasings that no error-keyed description would ever match:

| Class | Phrases |
|---|---|
| Direct | "switch accounts", "move this session to another account", "am I on the right account?", "switch in place", "rehome this pane", "change accounts without losing this session" |
| Router-derived | "the router excludes my account", "recycle re-pick", "kmax-concurrency", "5h-cutoff", "which account should I be on", "next2 is excluded" |
| Economic | "spend it before it strands", "stranding quota", "this account resets soon", "the weekly is about to roll", "spread the load", "least worth spending", "free up next3 for the wave" |
| Situational | "I'm idle on a busy account", "this pane is cheap to recycle", "nothing in flight — move me", "the wave needs this account" |
| Negative-space (the ones that must NOT be required) | any error text, any limit message, any `/limit-recover` trigger — **if the description only fires on those, it has repeated the defect** |

### Where each string goes

| Target | Text |
|---|---|
| `commands/accounts.md`, new § | *"**Moving a session that is already running.** A different account is NOT a new-pane property. `--recycle` is exit-then-relaunch — a new process — so `--account` composes with it, and a bare `--recycle` already re-picks the account when the router excludes yours or scores the best ≥`repick_ratio`× higher (`handoff-fire.sh:9456`). Read the verdict without moving anything: `… --recycle --prompt-file <f> --dry-run`."* |
| The ONE command (silver-platter form, `▶ Run this:` payload) | `bash ~/.claude/scripts/handoff-fire.sh --recycle --prompt-file /tmp/<dod>.txt` |
| The read-only probe | `bash ~/.claude/scripts/handoff-fire.sh --recycle --prompt-file /tmp/probe.txt --dry-run` |
| `commands/recover.md` cross-ref | one line: *"A HEALTHY session moving accounts is not a recovery — it is a recycle. See `/accounts` § Moving a session that is already running."* — this keeps the class boundary honest instead of widening `/recover` until it means everything |

**Wording rule, stated so it cannot be lost:** the advisory must name the **action** (`♻ recycle`),
never the **capability** ("an in-place switch exists"). A capability announcement is what
`/limit-recover` was; an action with its command is what `/recover` and `recover-inject.sh` are
(`hooks/recover-inject.sh:16-18`: *"It emits CONTEXT… and this hook's text says so in the
imperative."*).

---

## 7 — Adversarial self-pass

Three gaps hunted with real calls; all three changed the report.

**G1 — "Reach the idle session" may be the wrong objective.** An idle session **spends nothing**.
Its account membership costs only at its next wake. So the value of switching an idle session is
`P(wake) × spend × score-gap`, and the cheapest correct moment to act is **the moment it goes idle**
(one Stop hook, already registered, free) — not a push into a session that may never wake. This
retires the "we need a new daemon / a wake watcher" framing and is why S3 outranks S12. The
counter-case is real but narrow: a session idle for hours that the dispatcher *will* wake. For that
one, S12 is the only path, and it costs a full `cache_creation` on the very account we are trying to
stop spending — so it must fire deterministically, never as a model-facing "please consider".

**G2 — The switch is not free; it is a context reset.** `--recycle` is exit + relaunch: the context
is discarded. So an account advisory can never be independent of the context decision. Cheapest
exactly when a recycle is already warranted — which is *today's* design and is defensible. The
genuine hole is therefore **narrower than the brief assumes**: not "idle sessions never hear about
accounts", but **"a session idle BELOW `T_IDLE_FLOOR=25` has no context reason to recycle, so the
re-pick that would have moved it never runs"** (`waiting-recycle.sh:56-59`). Any advisory must carry
the fill number, and must say *free move* only when the fill is genuinely low and the tree is clean.

**G3 — Alarm polarity / thrash.** Checked before recommending S3, because an account advisory that
fires often would be `alarm-polarity-and-attention-budget` all over again. It cannot:
`REPICK_RATIO_DEFAULT = 4.0` is documented as *"orders of magnitude, not percent … never on the
jitter between two comparable accounts"* (`claude-accounts:1985-1988`), and the `--assign` phantom
charge (`ASSIGN_TTL_MIN`, `:2094`-ish) already stops a burst of moves stacking on one winner.
Reusing the router's own threshold inherits both properties; inventing a new one forfeits them.

**G4 — Does the classifier block the self-fire?** The memory says auto mode denies acting on "a live
Claude session", and a self-recycle's target IS a live Claude session. Checked against behaviour
rather than the rule: `git log` carries `docs(drain): recycle #332/#333/#334` from unattended drain
sessions, and `waiting-recycle` Stage 2 is built to exec the same command. So the boundary is
**peer**, not **self** — but this is inference from behaviour, not a measured A/B, and it is the one
claim in this report I would want re-run before building on it.

---

## 8 — Blockers and uncertainties, named

| # | Item | State |
|---|---|---|
| B1 | S1/S2 edits touch `CLAUDE.global.md` and `commands/handoff.md` — always-resident surfaces. INTEGRATE, never rewrite; and they must move **together** or the two copies will contradict (`docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md`) | Agent-drivable |
| B2 | S3 adds a NEW fire condition to a hook whose alarm budget is currently context-only. Needs the IDL abstain/fire discipline `boundary-handoff.sh:17-19` (B-3) already mandates, and a shadow soak | Agent-drivable |
| B4 | Any NEW registration is c10 → operator. Live evidence of the cost: `migrations/0026` (recover-inject) and `0030` (net-recover-arm) are both staged and **absent from `~/.claude/settings.json`** today | Operator |
| B5 | `waiting-recycle` is `disarmed` on 2 of 5 config dirs and registered on `PostToolUse:Bash` only — so choosing S4 as the carrier silently covers 3 of 5 accounts (`idle-recycle-not-proactive-2026-08-08.md`, gates A/B/C; re-verified live today) | Blocks S4 |
| B6 | The transcript-preserving path (`lr-handoff --in-place`) reaches the pane only through rails whose front door refuses a healthy session (`bin/cc-lr:202`: *"NO in-place recycle exists for this class — every downstream rail … is gated on the quota predicate"*). `lr-handoff.sh:806-810` opened the SELF branch today; the **front door has not been widened** | Open — a separate wave item |
| U1 | G4 above: self-vs-peer classifier boundary is inferred from behaviour, not measured | Re-measure before building |
| U2 | The board was in its STALE band (8 min vs `CC_BOARD_STALE_S=300`) at read time; whether that is normal or a producer defect is unmeasured here | Out of scope |

### Line-citation caveat

`NONLIMIT_RESUME_LADDER.md:723` cites the re-pick at `handoff-fire.sh:8303`; it is at **`:9456`**
today. Every `handoff-fire.sh` line in this report was read on 2026-09-22 against a clean `main` at
`8e3ab2e38` — re-derive, never re-quote (`docs/lessons/a-record-correction-wave-breaks-the-record.md`).
