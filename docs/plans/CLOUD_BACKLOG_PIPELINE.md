---
status: open
---

# CLOUD BACKLOG PIPELINE — cc-backlog drained end-to-end through Anthropic cloud VMs

**Mission.** Turn a proven cloud *arm* into a managed *pipeline*: an open `cc-backlog` item is routed
to a venue, dispatched to a cloud VM, steered two-way while it runs, landed, verified live, and
closed — with no human in the loop and no step that depends on someone remembering to poll.

**The state this plan starts from (measured 2026-08-11, one session, four live cloud round trips).**
The arm works. The pipeline does not exist. Both halves of that sentence are load-bearing and neither
is a guess — every claim below was read off the live control plane or the tree, not inferred.

---

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** Every implementation wave here is **S — a dispatched handoff session**
(the default; no justification needed). The lead holds ≥50% of its window for deciding *which venue
an item belongs in*, which is the judgment this plan exists to encode and the one thing a worker
cannot be handed.

One deliberate exception, and it is a hard constraint rather than a preference: **W1 (the venue
producer) must NOT be built by a cloud session.** It is the component that decides what runs off-box;
a cloud VM building its own admission rule is a circular dependency, and its 50-commit clone cannot
read the history that justifies the exclusions. W1 is a local dispatched session.

| Wave | Locus | Deliverable | Depends on |
|---|---|---|---|
| **W1 · venue producer** | S (local) | something labels an item `venue=cloud\|local` against the VM's real constraints | — |
| **W2 · management rails** | S | custody + wake + goal + auto-land for a cloud session | — (parallel with W1) |
| **W3 · refusal loop** | S | a land refusal routes back to the session that caused it | W2 |
| **W4 · cost A/B** | S | the same brief run local vs cloud, both arms measured | — (parallel) |

W1 and W2 are independent (one decides *what* goes, the other manages *what came back*) and should
fire concurrently. W3 needs W2's return path. W4 is measurement and blocks nothing.

**Lead context budget:** recycle at the seam between waves, never mid-wave. Succession point = after
W1+W2 return and their results are landed and content-verified.

---

## 1 · What is already true (do not re-derive; all of it is landed)

- **The create works.** `cc-offload up --via api` fires a two-call sequence — resolve an
  `anthropic_cloud` environment, then `POST /v1/sessions` with `environment_id` + `config.sources` —
  and REFUSES (exit 5) unless the session reads back with `environment_kind: anthropic_cloud` AND
  exactly one `git_repository` source. Mechanism + why it is a different ENDPOINT rather than a
  missing field: `CLOUD_OBSERVABILITY.md` § 13.3/13.4.
- **The land works, unattended.** `cc-offload land --all` re-authors the VM's commits (the VM commits
  as `noreply@anthropic.com`, which GitHub renders as a permanently unattributed grey user and this
  repo's identity gate refuses on purpose), carries provenance in `Cloud-session:` /
  `Original-commit:` / `Original-branch:` trailers, and self-heals a stale same-name local branch left
  by its own failed attempt. § 13.4/13.5.
- **Four items have gone through it.** `08df84d2`, `e950eccb` (the instrument pair), `355975c5` (the
  wrap-ledger memo), plus the original round-trip testimony. All landed on trunk and content-verified.

🚨 **Verify a cloud land BY CONTENT, never by sha.** The land re-authors, so the sha the VM pushed is
never the sha that lands. A checker written against the pushed sha reads "not landed" on a perfect
land. (`git ls-tree` / `git show origin/main:<path>`, never `merge-base --is-ancestor <pushed-sha>`.)

---

## 2 · The gap, stated exactly

**There is no producer.** `bin/cc-dispatch:470` says it in its own words:

> `cc-backlog claim --venue local|cloud` shipped fully built and fully tested with **ZERO PRODUCERS**.

The dispatcher has the plumbing — `fire_venue`, cloud-ineligibility handling, the `--venue cloud`
actuator, 38 references. Measured 2026-08-11: **0 of 294 open items carry a cloud venue**, and the IDL
records 3 cloud mentions ever. Nothing decides what should run off-box, so nothing does.

That decision is not a lookup. Of four briefs triaged by hand this session, **one was rejected
outright** (`7c6ff16259a0` — it patches `scripts/handoff-fire.sh`, the fleet's own spawn rail, flagged
in its own brief as "strands real work box-wide if wrong", and its premise had gone stale against the
same day's landings) and **one needed 215 commits of history inlined by hand** before a VM could
attempt it. A producer that routed on keywords would have sent both.

**And there is no return path.** A local `handoff-fire` gives the lead a notify-back ping, custody
that blocks a false `✅`, a `--goal` re-judged every turn, and mid-flight steering. A cloud fire gives
an id. Everything else this session did by hand:

| # | Gap | What it cost, concretely | Filed |
|---|---|---|---|
| 1 | no wake on completion | the lead polls, or the work sits done and unnoticed | `4f2eaa26ae83` |
| 2 | no custody | a `✅ SAFE TO CLOSE` is reachable with a cloud session mid-flight — the close-integrity mechanism is blind to cloud work | `4f2eaa26ae83` |
| 3 | no `--goal` | nothing re-judges a cloud session against a measurable end state | `4f2eaa26ae83` |
| 4 | gate refusals do not route back | the memo's land was refused by one lint; nothing told the VM. Diagnosed and hand-sent | `4f2eaa26ae83` |
| 5 | `cc-offload say` refuses on a stale binary | it lacks the `CC_CLAUDE_BIN` default `up` carries — the steering arm was DEAD until pinned by hand | `6ad6ec4121d2` |
| 6 | landed results read ELIGIBLE forever | declarations record `paths=` empty, so every sweep re-attempts finished work | `a435e3987fbf` |

Gaps 1-3 are why fire-and-forget is the only available mode today: **the cloud lane has no return
path into the machinery that manages local work.**

---

## 3 · Constraints a worker must be handed (the VM's own testimony)

From `docs/research/cloud-vm-roundtrip-2026-08-10.md`, written from inside the VM, plus
`docs/research/cloud-vm-shallow-clone-blast-radius-2026-08-11.md`:

- **The clone is SHALLOW — 50 commits.** Any brief whose work walks past that (`git show` on an older
  sha, a merge-base against an old branch, blame through the truncation) fails or quietly answers
  wrong. This is the single biggest determinant of cloud-suitability.
- **No `gh` CLI.** GitHub reaches the VM only through MCP tools scoped to one repository. Anything
  needing a PR is out.
- **A remote-tracking ref is seeded at provision time**, so `git branch -r` listing a branch is NOT
  evidence the remote has it. A push-detector keyed on that ref is a false positive.
- **The machine is a Firecracker microVM**, hostname `vm`, `/home/user`, reclaimed at session end.
  Nothing unpushed survives.
- **`~/.claude` does not exist there.** Every laptop-shaped brief step — `cc-backlog claim`,
  `cc-bats`, `ship-land.sh` — is unavailable; the backlog store is machine-local
  (`$HOME/.claude/autonomy/backlog.jsonl`). Claim locally BEFORE firing; the VM commits and pushes,
  the laptop lands and marks done.

---

## 4 · Cost — what is measured, and the one thing that is not

Per-session usage is readable at `external_metadata.usage` on `GET /v1/code/sessions/<id>`.

| session | task | output | cache read |
|---|---|---|---|
| round trip | write one file | 4,080 | 581K |
| instruments | 2 script fixes + 2 test suites | 50,302 | 7.44M |
| wrap-ledger memo | 1 perf fix, 20 tests, a benchmark | 84,109 | 16.4M |

Cache reads dominate and scale with task complexity — 28× across that range. **Idle is free**, proven
two ways: an 11-hour-idle session's usage is byte-identical across reads, and the *older* session has
8× *less* output than a newer one, so usage cannot be time-based. There is no VM line item at all —
the cost is tokens from the account's Max quota, which is why an account at 100% weekly is the real
ceiling.

⚠️ **UNMEASURED, and it must not be asserted: whether cloud costs MORE than local for the same task.**
n=4 cloud, zero controlled local arms. It IS measurable — `cc-ctx-audit --sessions` gives per-session
peak tokens locally — so W4 is a real experiment, not a thought experiment. The a priori case cuts
both ways: a VM starts cold with a shallow clone (inflating cache reads) but does not consume the
lead's context, which is the resource a long-horizon plan actually runs out of.

---

## 5 · Definition of done

The pipeline is done when an open `cc-backlog` item reaches `done` with **no human action and no lead
polling**, and each of these is demonstrated on a real item, not a fixture:

1. a producer labelled it `venue=cloud` and can articulate why (and correctly refuses an item that
   needs deep history, a PR, or touches the spawn rail)
2. it dispatched to a cloud VM without a hand-written brief
3. custody opened at fire, so a close during its flight is mechanically impossible
4. a goal was armed and evaluated against a measurable end state
5. its completion WOKE the lead rather than being polled for
6. a gate refusal routed back to the session and it amended without a human reading the log
7. it landed, was content-verified on trunk, and the item was marked done
8. the live layer carries the result (landed ≠ live — the `🚀` rung)

**Anti-goal:** a pipeline that dispatches blind. A wrongly-routed item is worse than an unrouted one —
it burns quota, produces a plausible-looking wrong answer against missing history, and reports success.

---

## Status log

- **2026-08-11** — plan opened. Arm proven end-to-end (create + land + 4 items landed); pipeline
  absent. Gaps enumerated from live failures, not speculation; filed `4f2eaa26ae83`,
  `6ad6ec4121d2`, `a435e3987fbf`. Cost measured for the cloud arm; local arm deliberately unmeasured.
  Next: W1 (venue producer, local session) + W2 (management rails) concurrently.
- **2026-08-11 (dispatch)** — W1 fired → pane 347 / next3 / worktree `w1-venue-producer`; W2 fired →
  pane 348 / next2 / worktree `w2-cloud-rails`; W4 fired → pane 349 / next3 / worktree `w4-cost-ab`.
  All three goal-armed (verified from their own transcripts) with custody open against the lead
  (pane 345). W2 owns the three filed gap items; W4 measures §4's open question. W3 holds for W2's
  return path. One fire-lint lesson: a brief that NAMES the notify binary without a resolvable
  target is refused (F3) — reference the rail generically, the fire materializes the trailer.
