---
status: measured
date: 2026-08-11
---

# Cloud vs local — a controlled cost A/B on the same brief

**Verdict, scoped: for a small self-contained write-one-tool-plus-tests task, a cloud VM does NOT
cost more than a local dispatched session — it costs slightly less, and the difference is inside the
noise.** Cloud ran at **0.72× the local arm's cache reads, 0.82× its cache writes and 1.09× its
output tokens**; on a price-weighted total that is **≈0.81× local**. But the spread *within* the
local arm (877K–1,297K cache-read tokens, 1.5×) is larger than the gap *between* the arms (302K on
the mean), so the honest claim is **parity, trending cloud-cheaper** — not a win.

This closes `docs/plans/CLOUD_BACKLOG_PIPELINE.md` §4's one explicitly unmeasured question. Before
today the record was n=4 cloud sessions and **zero controlled local arms**, so nothing could be said
at all.

---

## 1 · What was run

The **same brief text, byte-identical**, on both arms:
`tools/cost-ab-probe/wordfreq.py` (a stdlib-only top-N word-frequency CLI with a specified
tie-break and two exit-2 error paths) plus `tools/cost-ab-probe/test_wordfreq.py` (≥6 unittest
cases), run green with `python3 -m unittest discover`, committed, and pushed. The brief forbids
reading git history, opening a PR, landing, and installing anything — the four things the VM's
50-commit shallow clone, missing `gh`, and reclaimed filesystem make impossible — so **both arms can
genuinely run it**, which is the precondition for the comparison meaning anything.

| | arm A — cloud | arm B — local |
|---|---|---|
| venue | `environment_kind: anthropic_cloud` Firecracker VM | dispatched session in a fresh worktree off `origin/main` |
| created by | `cc-offload up --task <brief> -n 2 --account next3` (`--via api`) | `handoff-fire.sh --prompt-file <brief> --worktree ab-local-N --base origin/main --account next3` |
| model | `claude-opus-5` (control plane `last_served_model`) | `claude-opus-5` (transcript `message.model`) |
| account | next3 | next3 |
| n | 2 | 2 |
| instrument | `external_metadata.usage` on `GET /v1/code/sessions/<id>` | per-message `message.usage` summed over the transcript, once per `message.id` |

Both arms ran on the **same account** so the quota axis is controlled, and on the **same model**, so
the comparison is venue-vs-venue rather than model-vs-model.

**The axes map exactly** — this is not an approximate alignment:

| cloud `external_metadata.usage` | local transcript `message.usage` |
|---|---|
| `input_tokens` | `input_tokens` |
| `output_tokens` | `output_tokens` |
| `cache_read_tokens` | `cache_read_input_tokens` |
| `cache_write_tokens` | `cache_creation_input_tokens` |

---

## 2 · Raw numbers

### Per session

| arm | id / transcript | input | output | cache read | cache write | wall |
|---|---|---|---|---|---|---|
| cloud 1 | `session_01KhXLG6LVAVU5DQQLPAmVuH` | 27 | 7,904 | 896,510 | 73,489 | 502 s |
| cloud 2 | `session_01U4gQ1VEAfPyE6rDbUEW4MK` | 21 | 6,942 | 673,810 | 71,625 | 371 s |
| local 1 | `2cee38f6…` (pane 350, branch `ab-local-1`) | 17 | 6,211 | 876,923 | 89,116 | 655 s |
| local 2 | `ab5372f2…` (pane 352, branch `ab-local-2`) | 25 | 7,446 | 1,297,143 | 88,715 | 164 s |

Wall clock is `created_at → updated_at` from the control plane for cloud, and first→last transcript
message for local. Adding the local fire's out-of-transcript provisioning (worktree create + launch
+ engagement: 22 s and 28 s) gives fire→completion-ping of **667 s** and **187 s**.

### Mean per arm, and the ratio

| axis | cloud (mean) | local (mean) | cloud ÷ local |
|---|---|---|---|
| input tokens | 24 | 21 | 1.14 — both negligible (<30) |
| output tokens | 7,423 | 6,829 | **1.09** |
| cache read tokens | 785,160 | 1,087,033 | **0.72** |
| cache write tokens | 72,557 | 88,916 | **0.82** |
| wall clock | 437 s | 410 s (427 s incl. provisioning) | 1.07 (1.02) |

### Price-weighted, as an equivalence — not a bill

Nothing here is metered in dollars: the cost is **Max-quota tokens**, and there is no VM line item
(§4). Weighting is only a way to put four axes on one number. At Opus 5's published $5/MTok input ·
$25/MTok output, with cache read at 0.1× input and cache write at 1.25× input:

| | cloud | local |
|---|---|---|
| cache read | $0.393 | $0.544 |
| cache write | $0.453 | $0.556 |
| output | $0.186 | $0.171 |
| **total** | **$1.03** | **$1.27** — cloud is **0.81×** |

The ordering is robust to the one assumption in it: at a 1-hour-TTL 2× cache-write multiplier the
totals become $1.31 vs $1.60 and the ratio is still **0.81**.

---

## 3 · The finding the a priori case got backwards

§4 predicted the tradeoff as *"a VM starts cold with a shallow clone (inflating cache reads) but does
not consume the lead's context."* **Both halves are wrong for this task shape**, and the reason is
the same in each case.

**The cold VM is the LEAN arm, not the fat one.** The local session's *first turn alone* establishes
**81,635** (L1) / **78,845** (L2) cache-write tokens — 92% and 89% of everything it caches all
session. That is the always-resident preamble: `~/.claude/CLAUDE.md`, the project `CLAUDE.md`, the
hooks, the memory index, the skill roster, the tool schemas. **The cloud VM's entire session
established less context than that** — 73,489 and 71,625 — because `~/.claude` does not exist there.
The shallow clone is 50 commits of a repo the brief forbids reading; it costs nothing. The thing that
actually inflates a session's cached context is **our own laptop configuration**, and it is paid on
turn 1 whether the task needs it or not.

**The lead-context argument does not favour cloud — it favours DISPATCH, which both arms already
are.** A fired local session's tokens land in *its* window, not the lead's, exactly like a VM's. The
lead paid one `cc-offload up` call for both cloud sessions, versus one fire plus one blocking
`cc-wait` per local session; the work's ~1M cache-read tokens entered no lead context on either arm.
So "does not consume the lead's context" is a property of *dispatching*, not of *the cloud*. What
cloud uniquely spares is **this box's CPU, RAM, pane and worktree** — the capacity gate read
`load 12.67 on 10 cores` at fire time, and each local arm additionally cost a pane and a worktree on
disk.

---

## 4 · Controls that were actually run

A cost comparison between arms that produced *different* work would be meaningless, so equivalence
was verified rather than assumed:

- **Same deliverable.** All four branches contain exactly `tools/cost-ab-probe/wordfreq.py`,
  `test_wordfreq.py`, and an `__init__.py`. All four arms independently hit the same wrinkle
  (`unittest discover -t .` raises `ImportError: Start directory is not importable` on py3.11
  without a package marker) and all four added the same third file — strong evidence they solved the
  same problem, not merely similar ones.
- **Same outcome.** Each branch's suite was checked out and executed here: `Ran 10 tests … OK`
  (cloud 1), `Ran 9 tests … OK` (cloud 2, local 1, local 2). Nobody was cheap by being wrong.
- **Idle is free, re-confirmed.** Both cloud sessions' usage objects were re-read 8–10 minutes after
  their last turn and were **byte-identical**, with `updated_at` unmoved. Consistent with §4's
  existing two proofs; it also means the cloud numbers above are terminal, not a mid-flight sample.
- **Same account, same model**, asserted from each side's own record (above), not inferred.

---

## 5 · Threats to validity

Stated as limits on the verdict, not as disclaimers:

1. **n=2 per arm, and the within-arm spread exceeds the between-arm gap.** Local cache reads ranged
   877K–1,297K (1.5×) while the arms' means differ by 302K. The direction was consistent on 3 of 4
   axes, but **this experiment cannot resolve a difference smaller than ~30%.** It CAN refute "cloud
   costs much more" — there is no 2× penalty hiding here.
2. **Wall clock is the least trustworthy axis.** Local ranged 164 s–655 s (4.0×) against cloud's
   371 s–502 s (1.35×). The local arms shared a loaded laptop; the 4× spread is plausibly contention
   but n=2 cannot demonstrate it, and L1 ran concurrently with both cloud sessions' creation.
3. **Task-size sensitivity — the largest unknown.** §4's existing cloud table spans 4,080 → 84,109
   output tokens (28× on cache read) with complexity. This A/B sits at the *small* end. The local
   preamble is a **fixed** ~80K cost while the task-driven term grows, so cloud's relative advantage
   should *shrink* as tasks get bigger — the opposite of a shallow-clone penalty, and untested.
4. **Cache-TTL and warm-state effects are uncontrolled.** Both arms started cold in the sense that
   neither reused another session's cache, but prefix-cache hit rates across four near-simultaneous
   sessions on one account are not observable from either instrument.
5. **The local brief is not byte-identical at the payload level.** The fire rail appends its standard
   back-channel and self-retire trailers (~40 lines) to a *copy* of the brief. That is the ordinary
   local rail and was kept deliberately, but it is ~500 tokens the cloud arm did not receive, and it
   buys the local arm one or two extra turns (the ping and the retire). It slightly *inflates* local
   — i.e. it works against the measured result, so correcting it would only widen cloud's margin.
6. **Account throttle state was not a factor** but is not controlled either: next3 sat at 1% weekly
   before and 2% after, with the 5-hour window moving 3%→8% across all four sessions. The published
   figure is 1-point granular, so **it cannot attribute consumption per arm** — the per-session token
   counts above are the only per-arm quota evidence.
7. **The work products were deliberately NOT landed.** All four branches remain on origin as
   evidence; the probe tool is throwaway and does not belong on trunk. Only this document lands.

---

## 6 · What this changes

- **Routing an item to a cloud VM is not a cost decision** for small self-contained tasks — it is a
  *capacity* decision. Cloud buys back this box's cores, RAM, panes and worktrees at token parity.
- **The venue producer (W1) should not price cloud as a premium.** On this evidence the admission
  rule should turn on the VM's *constraints* (shallow clone, no `gh`, no `~/.claude`), which is what
  it already does, and not on a cost penalty that does not exist at this size.
- **The next measurement worth making is task size**, per threat 3 — the same A/B at the
  50K-output-token end, where the fixed local preamble stops dominating.

**Reproduce it:** the brief, both readers (`cloud-usage.py` reads `external_metadata.usage` by
importing `scripts/cloud-create-api.py`'s own credential + GET path; `local-usage.py` sums transcript
usage once per `message.id`) were scratchpad tools; the four branches
(`claude/fire-20260811T180903Z-57078-1`, `claude/fire-20260811T180908Z-57078-2`, `ab-local-1`,
`ab-local-2`) and the two session ids above are the durable evidence.
