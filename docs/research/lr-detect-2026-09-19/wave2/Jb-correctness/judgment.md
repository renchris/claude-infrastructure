# Jb — adversarial judgment of Db-derive-on-read (lens: CORRECTNESS + FAULT-VISIBILITY)
2026-09-19T22:50Z · all receipts re-measured this unit, read-only · SCORE 5/10

## F1 (FATAL) — the copy-selection rule picks a FROZEN transplant snapshot as "the LIVE copy", and the design's own showcase row is the proof
Rule, design.md §1.2 step 4: "Order copies (.handed-off last, size desc); the LIVE copy = first
.jsonl with >=1 assistant record in its 128 KB tail" + "No mtime is ever read for ordering".
Measured NOW for the sid the design celebrates (`ls -la ~/.claude*/projects/*/07e30aeb*`):
  .claude-secondary/.../07e30aeb....jsonl        1157520  Sep 19 15:32  <- cp -p snapshot, FROZEN 2h16m
  .claude-tertiary/.../07e30aeb....jsonl            5339  Sep 19 16:29  <- GROWING (2886 at the design's 21:14Z run)
  .claude-tertiary/.../07e30aeb....jsonl.handed-off 1157520 Sep 19 15:32
  .claude-tertiary/.../07e30aeb....HANDOFF.json      341
The tertiary file has **0 assistant records** (python scan: types = queue-operation/system/
bridge-session/cost-state/last-prompt/ai-title/mode/permission-mode/atis-latch). So size-desc
selects the secondary snapshot, reads a rate_limit record written before the transplant, and
reports `RECOVERABLE #147`. §2 states this explicitly: "step 4 picked the 1,157,520-byte live copy
under .claude-secondary and step 5 read the death record there". It is not the live copy.
Three compounding causes: (a) `lr-transplant.sh:72 cp -p` makes the copy size-identical and
mtime-identical to the source, so SIZE cannot order them and the design banned MTIME, which here
is the only discriminator that works (15:32 frozen vs 16:29 advancing); (b) the successor's own
file starts EMPTY, so size is monotone in the WRONG direction by construction after every
transplant; (c) the rule overrides `marker.transcript_path` — the one pointer written by the dying
process itself, which points at the tertiary file. The `UNKNOWN-STUB` state that exists for
exactly this shape is UNREACHABLE: it fires only when NO copy anywhere has an assistant record.
Consequence: every transplanted-then-relaunched sid can be reported blocked/RECOVERABLE off a dead
snapshot while the live pane has never made a request.

## F2 (FATAL) — one enumerator, five silent abstain paths, a 500-line cap, and a clean empty screen at exit 0
Enumerators are markers ∪ parked (§1.1). `hooks/stop-failure-marker.sh` exits 0 with NO marker row on:
`:64 no-stdin` · `:65 no-jq` · `:66 unparseable-payload` · `:79 no-error-field` · `:99 marker-dir-unwritable`
· `:115-118 marker-capped` (CAP=500 per cause-key file, :23/:42). All six land only in the IDL, which
the census never reads. The `no-jq` path is the machine's own recorded failure class (memory:
"a bare-name binary in a HOOK is a SILENT no-op ... PATH can be /usr/bin:/bin"; jq is in
/opt/homebrew/bin) — under it a whole fleet's deaths produce ZERO marker rows and `cc-limited`
prints "0 need attention", exit 0. That is precisely what §1.4 exit 5 forbids ("a census may never
print an empty list at exit 0 over a broken read, lr-fleet.sh:441-447") — applied to 4 inputs of the
10 in §1.1 and not to the enumerator itself. The cap binds hardest in the operator's stated
scenario (many sessions capping at once on ONE account share ONE file); today's load is 36/500 rows
on rate_limit__next4.jsonl, so it is a tail risk, not today's — but the census has no `wc -l` on its
own enumerator and cannot tell a quiet fleet from a capped one.

## F3 (FATAL) — the fault row is derived-only and SELF-ERASING; for a Fable/monthly cap it has no second enumerator at all
§9 sells CLAIMED-NOT-LIVE as the answer to "a claimed recovery that produced nothing must be NAMED,
never silently abandoned". But it is a pure function of the enumerators: §14.2 says the marker is a
24 h rolling window and "the second enumerator is parked/". §10.2 then states that `fable` and
`monthly_spend` rows "are logged LIMITED-NOWAIT (never parked)". So a Fable-capped session whose
transplant produced nothing is named for <=24 h and then **disappears from every surface with no
ack, no record, and no operator action** — the exact silent abandonment the requirement forbids. The
design names the seven_day/TICK-SKIP residual honestly and misses this structurally guaranteed one.
There is also no ACK: a true CLAIMED-NOT-LIVE either re-renders at every census forever or vanishes
at TTL; nothing records that a human saw it. (Da's FAULT — "never auto-removed ... leaves only
through `lr-state ack`", renders FIRST above the groups — is strictly better here.)

## M1 — the §2 screen is presented as probe output but the probe cannot produce it
Header: "probe output 2026-09-19T21:14Z, `census-probe.py`, 0.199 s". `grep -c
'CLAIMED-NOT-LIVE\|CLAIM_GRACE' census-probe.py` => 0. The probe implements `TRANSPLANTED/NO-PANE`
with a `lock->acct` tail and no grace, no claim ts, no pid, no log path. So the design's
crown-jewel state, its 120 s grace, its results.tsv/results.json claim sources and its reason
strings are UNIMPLEMENTED AND UNTIMED; the 0.199 s budget covers a resolver that omits them. The
three `CLAIMED-NOT-LIVE` lines in §2, with "by pid 32971 ... after 21m", are hand-composed.

## M2 — no cross-check that the chosen transcript's root agrees with the live registry row's account
The probe computes `cfg_of_live` and uses it ONLY in the TRANSPLANTED branch; §1.3 never uses it in
RECOVERABLE/DUPLICATE/RESET-PASSED. So a registry row on account A is joined to a death record from
account B's file and rendered as an in-place recovery (F1's row is exactly that). A one-line
disagreement state is missing.

## M3 — the transcript roots are a HARDCODED list, and this exact assumption has already blinded a whole account once
`census-probe.py:56` `for root in ['.claude','.claude-secondary','.claude-tertiary','.claude-quaternary']`.
`accounts.json` names `~/.claude-next` (not `~/.claude`) for `next`; the list is correct today only
because `~/.claude-next/projects` symlinks onto `~/.claude/projects`. `lr-reset-poller.sh` carries
the receipt of the same bug in its own comment: "Measured 2026-09-10: 0 transcripts without -H, 123
with it — the poller had never detected, parked or resumed a single `next` session (17 next2, 42
next3, 4 next4, 0 next)". Derive the roots from accounts.json and dedupe by `readlink -f`, and
assert coverage of every config_dir, or the next topology change is silent.

## M4 — the 120 s claim grace is justified against the wrong measurement
§9 anchors it to the 90 s dead-wait at handoff-fire.sh:6811-6815. The quantity that decides a false
fault is the END-TO-END transplant+relaunch duration (lock at lr-transplant.sh:68-69 is written
BEFORE `cp -p` of a 1.16 MB file, an rsync of the session dir, a shasum pair, a tombstone, and the
pane relaunch), which the design never measures. Under it, any slow transplant is named a fault.

## M5 — the lock is permanent and pre-write, so it cannot support the reason string
`lr-transplant.sh:60-69` writes the lock BEFORE the copy and `:63-66` REFUSES on an existing lock;
nothing ever removes it (47 lock files on disk). A FAILED transplant (sha mismatch, `:86-88 exit 2`)
and a SUCCEEDED-but-unengaged one leave identical lock evidence, yet §9 renders one story
("transplant to next2 claimed ... no live process on next2 after 21m") whose next action differs
between them (re-run the transplant vs prompt the pane).

## M6 — a live successor with no registry row is falsely named CLAIMED-NOT-LIVE
The predicate's backstops are a live registry row and "no beat of kind prompt|stop younger than the
claim". P5 measured 21.4% of rate_limit sessions with NO registry row, and
`hooks/session-register.sh:127-132` returns without registering when the pane address is empty. A
successor that is live but has NOT been prompted has no prompt beat by definition (that IS
AWAITING-ENGAGE). So it renders "no live process ... after 21m" — a false statement about a running
process, on the one signal the operator asked to trust.

## M7 — predicate inconsistency between §6 and the only measured artifact
§6.1 specifies `re.search(r"You've (?:hit|reached) your ...")` (unanchored). `census-probe.py:22-23`
uses `^`-anchored patterns with `.search()`, so any prefix on the message yields `unclassified`.
Separately, `hooks/stop-failure-marker.sh:127` stores `last_assistant_message` through
`cut -c1-200`, and §1.2 step 1 classifies `cap` from that truncation — a 200-char, byte-split field.

## Not defects (checked and cleared, so nobody re-opens them)
- `quotaLimits.resetsAt` is seconds, not ms (`1789894800`), so the probe's `reset <= now` is unit-correct.
- Subagent records live in `projects/<slug>/<sid>/subagents/agent-*.jsonl`, NOT inline; 0 `isSidechain:true`
  assistant records in a main transcript sampled. A subagent turn cannot postdate the death record and fake RE-ENGAGED.
- `session-beat.sh:58 kind="${1:-prompt}"`, `:62` who-gate, `:124` entry, and
  `scripts/lib/spawn-presence.sh:319 select(.kind == "prompt" ...)` are all exactly as claimed.
- `lr-reset-poller.sh` teammate rule IS `head -c 8000 | grep '"agentName"'` as stated.
- The alias correction is right: accounts.json carries `next` -> `~/.claude-next`, `aliases:["claude"]`,
  and the live markers are `rate_limit__{next,next3,next4}.jsonl` with `authentication_failed__.claude.jsonl`
  as the phantom class.
