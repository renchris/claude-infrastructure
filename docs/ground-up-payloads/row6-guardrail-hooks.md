STEP -1 — RECONCILE BEFORE YOU BUILD. THIS PAYLOAD WAS COMPOSED 2026-07-30 AND IS OLDER THAN THE
SUBSYSTEM IT DESCRIBES. The campaign's own measured law (GROUND_UP_REBUILD_MAP.md Learnings,
2026-08-07): **an open row is not a row that needs a rebuild — a dormant row's subsystem keeps moving
without it.** Two of the three rows open on 2026-08-07 had already been answered out-of-band, one of
them *better* than its own spec. A session that fires against a stale payload rebuilds shipped code.
So before any design or build work, run THIS row's own acceptance reads against `origin/main` and
write down, per AC, one of: MET (cite the trunk sha, content-verified — `git ls-tree`/`git grep`, never
a sha lookup alone) · FAILS (quote the read that fails) · SUPERSEDED (a different, shipping answer
exists — say what it is and why it wins). **Design only against what actually FAILS.** If an AC is
MET or SUPERSEDED, say so and move on; do not re-implement it to match the spec's wording.
Two hard-won corollaries: when two oracles disagree, **the shipping side wins and the stranded doc is
the stale one**, however carefully it was measured; and a cited sha that reads NOT-ON-TRUNK may be a
**dangling pre-rebase object whose content did land** — verify by CONTENT before concluding absence
(this exact trap sat in row 9's cell for 3 days; see the 2026-08-11 wave-log entry).

YOUR TASK — a from-first-principles GROUND-UP rebuild of ONE subsystem: the guardrail/hook layer
(row 6) — what a session may do. You were fired by the ground-up campaign coordinator. **You are the
LAST row of a 13-row campaign, and you are last on purpose: you are every other row's enforcement
surface, so you rebuild after your customers have stabilised their contracts.**

**Row 6 status as re-derived 2026-08-11: GENUINELY UNTOUCHED — no design doc, no build** (only this
payload landed, `53c6eee9`). It is the campaign's one row with no `docs/plans/*_V2.md`, which is
exactly why it went dormant: the `plan-open` generator that mints dispatcher-reachable backlog rows
for rows 2 and 11 takes an OPEN PLAN DOC as its input, so it is structurally blind to a row that has
never had one. Your first landed artifact should therefore be the design doc — the moment
`docs/plans/GUARDRAIL_HOOKS_V2.md` exists and is open, this row self-heals into the dispatch wave and
stops depending on any coordinator being alive. **Known live overlap to reconcile against, not
duplicate:** `cc-backlog 4ce34a4f703c` (hook-wiring parity across the 5 config dirs has no checker;
a permission rail missing from 2 of 5) is your AC territory and is already filed — read it, and
either subsume it with evidence or leave it to its own worker; do not re-file it.

Scope (frozen): every session gets the SAME guardrails, and a guardrail's presence is provable rather
than assumed — no session silently running with a rail its siblings have. Measured, landed, and
verified by disk-truth acceptance reads.

STEP 0 — ARM YOUR WAKE PATH FIRST, BEFORE ANYTHING ELSE. Run this as a Bash tool call with
run_in_background=true, substituting YOUR OWN pane uuid from `~/.claude/bin/cc-notify --self`:
  ~/.claude/bin/cc-await-ping <YOUR-PANE-UUID> --timeout 14400 --interval 15
**RE-ARM IT AFTER EVERY WAKE — it is single-shot, and one wake makes you deaf.**
🚨 **ARM BOTH KEYS — THE PANE AND THE SESSION. Neither alone works, and this is measured end-to-end.**
An earlier version of this payload said "use the pane uuid, never your session id"; a later one said the
opposite. **Both were half right, and the coordinator shipped each in turn.** The system derives the
mailbox key independently at three hops and they disagree:
  · **SENDERS write the PANE box.** `bin/cc-notify` has **ZERO** `mailbox_resolve_key` call sites
    (positive control: `hooks/session-continue.sh` has 3) and at `:508` appends to
    `$MAILBOX_DIR/$uuid.md` with the key it is handed, unresolved.
  · **The DRAIN and the WAKE FLOOR read the SESSION box** — `hooks/mailbox-drain.sh:64-65` sets
    `own_uuid="$own_sid"` whenever `CC_MBX_SESSION_KEY` (default 1) is on.
  · **`cc-notify:644` checks `wake_path_armed` against the PANE**, so its `reason=no-watcher` field is a
    FALSE NEGATIVE against a session-armed peer. Do not trust that field.
Measured cost of getting this wrong: a sibling counted **79 pane-keyed boxes holding 1,747 unacked lines
against 30 session-keyed holding 267**, and the coordinator killed its own pane watchers on a
half-correct reading and lost a row's DONE ping to the gap. Therefore:
  · Arm **TWO** background watchers — one on your PANE uuid (`~/.claude/bin/cc-notify --self`), one on
    the key the `🔔 WAKE FLOOR` Stop-hook message prints. Both are single-shot; **re-arm each after
    every wake.** The pane one catches peer mail; the session one satisfies the floor.
  · Verify each with the lib's own predicate, never `pgrep` (which returned 0 for a watcher that `ps`
    and the lib both confirmed alive):
      bash -c '. ~/.claude/hooks/lib/mailbox-pending.sh; mailbox_wake_armed <KEY> && echo ARMED'
**THE DURABLE LESSON, and it generalises past mailboxes: A FIX TO THE ADVERTISER IS NOT A FIX TO THE
WRITER.** Commit `9586f1ac` corrected what the hook *tells* you to arm, and every verification of it
passed because the advertiser and the reader genuinely agreed — the hop nobody re-checked was the
SENDER. When a key is derived independently at N hops, verify the ROUND TRIP end-to-end (write as a
peer, drain as the recipient), never one hop against its neighbour.

STEP 1 (one short command): arm your standing goal so you drive to DONE across recycles —
  ~/.claude/hooks/dod-persist.sh set "Scope (frozen): row 6 guardrail/hook layer — every session gets
  the same guardrails and each rail's presence is PROVABLE, not assumed; a hook failure never blocks a
  tool by accident and an absent hook never silently blocks nothing. Rebuild per skills/ground-up/SKILL.md."
  NOTE: earlier payloads on this campaign said to run "/goal ...". THAT COMMAND DOES NOT EXIST —
  verified absent from all five config dirs; it silently did nothing for every row that ran it.

STEP 2: run /ground-up guardrail-hooks. Before any other tool call, READ: GROUND_UP_REBUILD_MAP.md row
6 + the "What DONE means" ruling + the unowned-surface rulings register + the Learnings (you are last,
so all of them are yours to inherit) · skills/ground-up/SKILL.md · docs/plans/LAND_PIPELINE_V2.md
(exemplar) · docs/plans/OPERATOR_SURFACE_V2.md (row 10 — its alarm-polarity learning is the single most
load-bearing idea for your row) · docs/plans/SESSION_LIFECYCLE_V2.md (row 2 — cell falsification done
right).

[locate] your own worktree on branch gu-guardrail-hooks (base origin/main) of claude-infrastructure.
Commit ONLY here — NEVER in the shared checkout.

🚨 THE HAZARD BLOCK — YOURS IS THE WORST ON THE CAMPAIGN, BECAUSE YOUR SUBJECT CAN HALT THE FLEET 🚨
A `PreToolUse` hook that exits non-zero BLOCKS the tool call. Your surface is wired into **12 events
across 5 config dirs**, and roughly 30 live sessions — including two in-flight rebuild rows and the
coordinator — execute your hooks on every turn. A bad edit does not fail politely; it stops everyone.
  · NEVER edit a live `~/.claude*/settings.json` in place as an experiment. Copy a config dir to your
    own temp path, point a scratch session at it, and exercise there.
  · Before any change to a live settings file, write the rollback FIRST and say out loud what restores
    it. Assume you will need it.
  · A hook that is slow is a hook that is broken: row 13 measured the Stop chain at 3688ms/turn before
    its fix, times every session times every turn. Cost is a correctness property here.
  · Never test a blocking rail by triggering it against a live session's tool call.

YOU OWN: hook DISPATCH and WIRING — which hooks are registered, on which events, in which config dirs —
plus the permission rails, the Stop asserts, `hooks/validate-bash.sh`, the OVERWRITE guard
(`hooks/backup-before-write.sh`), `hooks/completion-assert.sh`, and the
settings-template ↔ live-config parity contract.
SEAMS NOT YOURS — and this split is the binding precedent from rows 2 and 11, now applied in reverse:
**row 6 owns hook DISPATCH, NOT an individual hook's SEMANTICS.** Each hook's behaviour belongs to its
subsystem's row: `mailbox-drain.sh` semantics → row 3 · `operator-readout.sh` rendering → row 10 ·
`session-deregister.sh`'s registry contract → row 4 · `session-continue.sh` → row 8 ·
`worktree-setup.sh` / `git-worktree-guard.sh` → row 11 · the pane-CLOSE actuators
(`teammate-auto-shutdown.sh` `close_pane()`, `lead-crash-watchdog.sh --close-panes`) → row 2 by explicit
ruling. **You own WHETHER AND WHERE each is wired. They own what it does.** Every one of those rows is
DONE except row 11 — so if you find a semantics defect, name it as a remainder with its owner; do not
fix it, and do not route new work into a closed row without pinging me.

🚨 YOUR HEADLINE TAKE, MEASURED THIS SESSION — WHAT A SESSION MAY DO DEPENDS ON WHICH ACCOUNT FIRED IT.
There is **no checker for hook-wiring parity across the five config dirs**, and the drift is live. I
enumerated every `(event, script)` pair in all five `settings.json` files: **62 distinct pairs, 58 wired
in all five, 4 drifting.**
  | event | script | wired in | MISSING from |
  |---|---|---|---|
  | `Stop` | `operator-readout.sh` | 4/5 | `.claude-next` |
  | `PreToolUse` | `cc-unattended-ask-guard.sh` | 3/5 | `.claude-next`, `.claude-quaternary` |
  | `SessionEnd` | `session-deregister.sh` | 3/5 | `.claude-next`, `.claude-quaternary` |
  | `SessionStart` | `desk-brief-inject.sh` | 3/5 | `.claude-next`, `.claude-quaternary` |
**Why this is not bookkeeping: the second row is a PERMISSION RAIL — your own named surface — absent for
two of five config dirs. And the drift hits this campaign's own rows.** Row 7 runs under
`.claude-next` (verified from its transcript root), so for its entire rebuild it has had no
`operator-readout` Stop hook, no unattended-ask guard, and no `session-deregister`. Because the fleet
picks a config dir BY ACCOUNT at fire time, the guardrail set a session gets is a side effect of quota
routing. **This also independently confirms row 10's remainder R-2 ("`operator-readout` is registered in
4 of 5 config dirs and no alarm covers a hook's own wiring") and names the missing dir, which row 10
could not.** Reproduce it yourself before designing — the command is in Phase 1 (a).
  · **A HYPOTHESIS TO TEST, NOT A FACT TO INHERIT:** `session-deregister.sh` missing from two dirs
    means sessions fired on those accounts never deregister at `SessionEnd`. A census in the campaign
    record found **134/134 assignee panes carrying no registry row**. Test whether the wiring gap
    explains part of that, using row 4's registry as the oracle. It may not — say either way.
  · **CANDIDATE RENAME for your standing-constraint cell, which reads "a hook failure must never block a
    tool by accident."** That half is real, but its MIRROR may be the binding one: **an absent hook
    cannot block anything at all, and nothing notices.** That is row 10's ratified duality in your
    surface — an alarm that always fires and an alarm that cannot fire are the same alarm. Six of the
    eight closed rows renamed or falsified their cell; a rename is a first-class outcome. Decide from
    your own measurements, not from my framing.

PHASE 1 IS NOT OPTIONAL — three checks BEFORE you design anything:
  (a) RE-DERIVE YOUR ROW'S CELL from primary disk truth. The cell says "69 hook entries / 12 events".
      **12 events is exactly right; 69 entries is not a number that exists** — I measured 67 · 67 · 67 ·
      64 · 63 across the five dirs, and the fact that it is FIVE DIFFERENT NUMBERS is the finding, not a
      correction to one. Derive it, and hand no carried number forward:
        for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary ~/.claude-next; do
          printf '%s ' "$d"; python3 -c "import json,sys;h=json.load(open('$d/settings.json')).get('hooks',{});print(len(h),'events',sum(len(e.get('hooks',[])) for v in h.values() for e in v),'entries')"
        done
      Then enumerate `(event, script)` pairs per dir and diff them — that is how the table above was
      produced. Give it a positive control (a pair you know is in all five) and a negative one.
  (b) CHECK ACTIVATION/DEPLOY TRUTH for every mechanism your metric depends on:
        git -C ~/Development/claude-infrastructure rev-list --count HEAD..origin/main   # deploy lag
        for f in ~/.claude/autonomy/pending-activation/*-activate.sh; do \
          [ -e "$f.done" ] || echo "UN-RUN $(basename "$f")"; done
      Lag is a SAWTOOTH, not a state. Prefer an EFFECT-READ: most of `hooks/` is per-file symlinks into
      the checkout, so landing IS deploying for those — but `~/.claude/CLAUDE.md` is a real file, and
      **`~/.claude*/settings.json` are NOT symlinks into the repo at all**, which is exactly why the
      drift above can exist. Establish that distinction early; your whole row turns on it.
      ⚠ **A `.done` marker proves the SCRIPT RAN, never that the EFFECT LANDED** — verified live this
      session: `10-lead-crash-orphan-close-activate.sh` ran, wrote its env file, got its `.done`, and is
      100% inert because nothing sources that file (backlog `80321b2556e6`). Env-var-armed activations
      escape both existing health axes.
  (c) SWEEP THE BRANCH GRAVEYARD before you build. **Your slice, re-verified by me with `git ls-tree`
      and both controls:** `hooks/curl-gate.py` · `hooks/keychain-guard.sh` · `hooks/subagent-stop.sh` ·
      `tests/subagent-stop.bats` · `tests/hook-jq-abstain.bats` — **all five absent from trunk, all five
      present in `fix/infra-perfection`**; `tm/hygiene` has curl-gate, keychain **and
      `tests/hook-jq-abstain.bats`**, but NOT `subagent-stop{.sh,.bats}`. **That is a correction to the
      campaign graveyard table, which records hygiene as "curl-gate, keychain only".** Take from
      `fix/infra-perfection` with `cherry-pick -x`. Do NOT treat the cherry-pick as the fix — a stranded
      suite is evidence a fix never landed, so establish what each guards and whether that hole is open.
      `tests/hook-jq-abstain.bats` is worth reading first: a hook that abstains because `jq` failed is
      your standing constraint in miniature.

FIVE HARNESS TRAPS — each produced a WRONG VERDICT for someone on this campaign:
  · **zsh eats `:t` / `:h` in `"$var:path"` as a glob MODIFIER, manufacturing false absences.**
    `"$b:hooks/foo"` parses `:h` as the HEAD modifier, git fatals rc=128, and under the `2>/dev/null`
    every sweep applies that is indistinguishable from "file absent". **`hooks/` is your row's main
    directory and is one of the two worst-hit prefixes.** Use `"$b:$p"` or `git ls-tree "$b" -- "$p"`.
  · **TWO LAWS ABOUT CONTROLS.** (i) A control must be able to fail the same way — make it share the
    first path segment's initial letter with the paths under test (mine: `hooks/dod-persist.sh` for the
    `h`-paths, `tests/no-such.bats` for the `t`-paths). (ii) A control DECAYS on the next commit to the
    code it guards — pin the unfixed shape by what the FIX ADDS, and when a control starts failing
    suspect the CONTROL first, then make it STRICTER.
  · **GREP THE SYMBOL, NEVER THE CLAIM — AND READ THE HIT.** Four times today a coordinator grep
    produced a false verdict, twice from *guessed filenames* that did not exist. An absence from a path
    you guessed is not evidence. Enumerate the directory, then read the hits.
  · NEVER pipe a test run into `tail`/`head` and read the exit code — that is the PIPE's status, and it
    reported exit 0 over two RED tests. Redirect to a file, read `$?` unpiped, key on the `not ok`
    COUNT — **and reconcile the `1..N` header**: a 164-test run exited 124 with 11 tests NEVER RUN,
    which a not-ok count alone reads as green. A missing verdict is a THIRD state, not a pass.
    Also: `BATS_TEST_TIMEOUT` in `setup()` is a SILENT NO-OP — file-level only.
  · A suite that tests a WRAPPER must not inherit that wrapper's env (`bin/cc-bats` exports
    `CC_BATS_ACTIVE=1`; a shim under test then short-circuits — 16/16 green plain, 14/16 through the
    shim). Unset it in `setup()`. And `pgrep -f X` counts processes that merely MENTION X, including a
    hook's own argv under `~/.claude` — match on the command position.

DoD (all four, or you are not done):
1. `docs/plans/GUARDRAIL_LAYER_V2.md` with the four load-bearing sections — measured constants WITH
   citations, failure-mode table (every observed mode → its structural answer), rejected alternatives
   with reasons, acceptance criteria as disk-truth reads.
2. Adversarially proven to the skill's Phase 4 bar: RED-proof every new test against a pristine
   pre-change tree recovered via `git archive` at a DERIVED rev; a positive control beside every absence
   assertion, per the two laws; `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts
   under `/bin/bash` (the Bash tool runs zsh, so repros lie). Run gate corpora through `bin/cc-bats`.
   Config-mutating tests target a COPIED config dir ONLY (hazard block).
3. Landed via the project-local `/ship` CONTINUOUSLY — never batch. RESOLVE CITED SHAS AFTER LANDING
   from origin/main via `git merge-base --is-ancestor <sha> origin/main` — ship-land rebases, so a local
   sha reads NOT-ancestor while its content is on trunk. Do NOT edit tracked files while a ship-land is
   in flight. **Never pipe `ship-land.sh`** — the pipe's exit code masks a dropped land; content-verify
   on `origin/main` afterwards either way.
4. `GROUND_UP_REBUILD_MAP.md` row 6 updated with status + plan link + landed shas, landed too —
   including the entry-count correction and any cell rename you land.

**INBOUND REMAINDERS ARE ADDRESSED TO YOU — derive the list, do not trust mine.** You are last, so
other rows named work as yours. Two I know of: row 10's **R-2** (no alarm covers a hook's own wiring —
the table above is its evidence) and row 13's **PreToolUse Bash admission term** for its QoS coverage
ceiling (AC1 is capped at ~70% because ~30% of `bats` invocations use an ABSOLUTE path that never
consults PATH; row 13 named a Bash PreToolUse term as one of the two ways to close it, and called it an
operator decision — treat it as a candidate, not a mandate). Find the rest yourself rather than
inheriting a stale list:
  grep -n 'row 6\|(6)\|R-[0-9].*hook\|row 6 owns' docs/plans/*_V2.md docs/plans/GROUND_UP_*.md

CONSUME OTHER ROWS' MECHANISMS FAIL-SOFT. DONE on this map means designed + landed + proven +
activation STAGED AND PLATTERED — it does NOT mean live. Assume anything you depend on may be
landed-but-inert, degrade cleanly, and say in your plan what your design does when the dependency is
dark. Check for existence evidence; never trust a status cell. **If you stage an activation, commit it
to the repo SSOT as well as the live queue** — an untracked live-only activation script is one `rm` from
unrecoverable, and that gap blocked a sibling row's DONE earlier today.

Every new mechanism ships with an env kill switch, never revert-as-plan. Ping me
(cc-notify 71B42B48-1331-4F60-8DA3-6849F2682CA2) at Phase 1 close, on any seam question, and at DONE
with your landed shas. **You are the last row — at DONE, say plainly in your ping what the campaign as a
whole still leaves open, because there is no row after you to inherit it.**
