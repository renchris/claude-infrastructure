# D1 preflight — what is settled before the two-week window closes, and what is not

**Row:** backlog `b1432e348362` (D1 / RC-5b, janitor scope). **Plan:** `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md` § W5.
**Written 2026-09-20T03:30Z**, 2 h 23 min after W3 (`f710200f8`, committed 2026-09-19T20:06:15-05:00) landed.
**This document decides nothing.** It exists so the session that takes D1 on/after **2026-10-03** re-derives
none of the below, and so it does not take the two wrong turns recorded in § Method warnings.

## 1. The decision, restated

D1's rule (plan § W5) is: choose **(b)** — restrict `hooks/teammate-auto-shutdown.sh` to members whose lead is
DEAD — **only if** the post-W3 lead-side shutdown rate exceeds the closer's live-lead reap share (36.7 % of
teardowns) **AND** P1 passes; **otherwise (a)**, keep the closer as it is after W1, and say why.

- **P1's term is SATISFIED** (W5 `dd070aaa1`: survivors 0 over 2 runs, 4/4 idle notifications). Not re-measured here.
- **The rate term is UNMEASURABLE TODAY.** The window required is two weeks; the window available is **2 h 23 min**.
  This is a calendar fact, not a judgment call, and it is the whole reason the row is parked rather than decided.

So D1 turns entirely on one number that does not exist yet. Everything below is about making that number cheap
and safe to read when it does.

## 2. The baseline REPLICATES — the instrument is sound

W3's heredoc (`git show f710200f8`, "AXIS-H BASELINE") re-run verbatim, unmodified, 2026-09-20T03:29Z:

| | W3, 2026-09-19 | this run, 2026-09-20 |
|---|---|---|
| leads that spawned a named member, 30 d | 101 | **105** |
| sent `shutdown_request` to EVERY member | 23 (22.8 %) | **24 (22.9 %)** |
| to SOME | 10 (9.9 %) | **10 (9.5 %)** |
| to NONE | 68 (67.3 %) | **71 (67.6 %)** |
| named members | 490 | **502** |
| got NOTHING | 334 (68.2 %) | **345 (68.7 %)** |

Every cell moves in the direction and by the magnitude a sliding 30-day mtime window predicts. The instrument
reproduces. **Re-run it, never quote this table** — that is W3's own instruction and it still binds.

## 3. A plausible argument for (b) that is FALSE — tested and refuted

The residual W3 named (`scripts/wrap-ledger.sh` § THE RESIDUAL) says the team config is a **survivor set**: CC
removes a member row when its shutdown completes. Read alongside "68.7 % of members got no `shutdown_request`",
that invites a tidy and wrong inference:

> The closer reaps members behind live leads, which removes their config rows, which is the input `RESIDENT_MINE`
> reads — so option (a) suppresses the very signal W3 built, the rate can never rise, and the rule is a gate that
> cannot ease with evidence. Therefore (b).

**This was tested and it is false.** Partitioning the 418 distinct members spawned in 30 d by how they ended, and
asking whether their config row still exists:

| arm | n | row survives |
|---|---|---|
| lead sent `shutdown_request` | 130 | 6 (**4.6 %**) |
| no shutdown, **closer reaped it** | 132 | 19 (**14.4 %**) |
| no shutdown, **closer did NOT reap** | 156 | 3 (**1.9 %**) |

If the closer were the eraser, the third arm would be the high one. It is the **lowest**. Closer-reaped members
retain their rows *more* often than anything else. Rows disappear near-universally regardless of the closer, so
the closer does not suppress `RESIDENT_MINE`'s input and this argument may not be used to choose (b).

This is the one-armed-adjudication discipline (`docs/lessons/one-armed-adjudication-only-convicts.md`) paying
off: the hypothesis was attractive, the arm that could refute it was named and run, and it refuted.

## 4. What removes the rows is still UNIDENTIFIED — and it is (b)'s real risk

- **It is not us.** No file under `bin/`, `hooks/` or `scripts/` on `origin/main` writes `teams/*/config.json`;
  every reference is a read. The removal agent is the vendor.
- **It is not decay.** Split by config age, the share retaining ≥1 member row is flat, not falling:
  0–6 h **7.1 %** (n=14) · 6–24 h 0 % (n=7) · 3–7 d **8.7 %** (n=23) · 7–14 d 0 % (n=41) · 14–30 d **16.7 %** (n=12).
  A 30-day snapshot therefore cannot be age-corrected into a statement about fresh teams.
- **Aggregate:** 92 of 97 configs created in the last 30 d (**94.8 %**) now list only the lead. This replicates
  W3's 91/95.

Option (b)'s premise is "let W3's 🔧 plus the vendor's lead-exit cleanup carry live leads." That premise is only
as good as how often `RESIDENT_MINE` actually fires. Nobody has measured that, and D1's rule does not price it.
**The session that takes D1 should read the fire rate directly rather than inferring it — but note that no
store currently records it** (§ 6). Pricing (b) may therefore require standing up that observation first.

## 5. Method warnings — two turns that look right and are not

1. 🚨 **Do NOT quote 94.8 % as `RESIDENT_MINE`'s blindness.** That population is **92 % dead leads**, and
   `RESIDENT_MINE` fires at the lead's *close*, while the lead is still alive. Split by whether the lead process
   is still running, live-lead configs retain rows at **12.5 % (1/8)** against **4.2 % (4/95)** for dead leads —
   directionally opposite to the pessimistic reading, and at n=8 **not a verdict either way**. The snapshot
   cannot answer this question; only the prospective window can. I formed this hypothesis, tested it, and it is
   recorded here as unresolved rather than as a finding.
2. **The three `not-yet-true` "re-land X" rows are not this row's shape.** Their precondition (an author's pane
   closing) arrives in hours and dispatching them is correct. D1's precondition is a **date**. A blanket park on
   the `not-yet-true` class would wrongly park the re-land majority — which is why this row was blocked
   individually and no dispatcher mechanism was built. The plan deliberately put the arming date in the row's
   `whyNotNow` prose after removing an inverted falsifier
   (`docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md`); that decision stands and was not reopened.

## 6. The two commands D1 needs, on or after 2026-10-03

```sh
# 1 — the rate term. Verbatim W3 heredoc; window slides, so RE-RUN, never re-quote §2.
#     Verified to extract and execute cleanly on 2026-09-20.
git show f710200f8 --no-patch --format=%B | sed -n '/^  python3 - <</,/^  PY$/p' | sed 's/^  //' | sh
```

🚨 **There is no command 2, and that is itself a finding.** The obvious one —
`grep RESIDENT_SRC ~/.claude/logs/*.log` — was written, run, and **withdrawn**: `RESIDENT_SRC` is emitted only
by `wrap-ledger.sh --machine` (`scripts/wrap-ledger.sh:2214`) and is written to **no log by any code on trunk**.
That grep returns 0 for a reason with nothing to do with the phenomenon, and a 0 here reads as "the arm never
fires" — the `store-silence-is-evidence-only-if-it-has-a-writer` trap, which this note exists to stop the next
session walking into.

**So the fire rate is not observable retrospectively today.** The only honest reads are prospective:
`bash scripts/wrap-ledger.sh --machine | grep RESIDENT_` point-sampled on live lead sessions, or adding a writer
— which is new mechanism on a Stop-hook path, outside D1's scope, and should be a decision rather than a rider.

Then apply the rule in § 1 as written: **(b)** only if command 1's "sent to EVERY" exceeds **36.7 %**; otherwise
**(a)**, and say why. If (b) is chosen, its falsifier is unchanged — residency p90 (H: 2.2 h) must not rise over
the two weeks following.

## 7. Provenance

Every number above is from this box on 2026-09-20T03:29–03:31Z, against `origin/main` with the worktree 0 behind
trunk, the repository not shallow, and `bin/cc-dispatch` blob EQUAL to trunk's. Sources: `~/.claude*/projects/*/*.jsonl`
(lead transcripts, the durable record), `~/.claude*/teams/*/config.json` (deduped by realpath across all five
config dirs), `~/.claude/logs/teammate-lifecycle.log` (closer reaps, `✓ closed pane`).
