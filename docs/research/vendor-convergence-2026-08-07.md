# The order converges. The precedence does not.

*Measured 2026-08-07. Repo dates are `git log --all --diff-filter=A` shas; Claude Code dates are the
npm publish timestamp of the exact version string that carries the changelog line.*

Anthropic ships Claude Code. Heavy users extend it — hooks, skills, agents, scripts. Both sides keep
building on the same artifact, and the same capabilities keep appearing on both sides weeks apart.
That reads two ways: a power user anticipating the roadmap, or a power user rebuilding what already
shipped. We tested six of our own priority claims against the changelog. It is neither.

> **Revised 2026-08-08.** The first version of this note refuted the research-fan-out claim. That was
> wrong twice over, and both errors were mine as author. (1) I dated our side from git (`2026-06-06`)
> without sweeping `~/Desktop`, where a 10-file, 213 KB corpus — including a 37 KB, 24-citation
> evidence document — has sat since **2026-05-24**, four days *before* Dynamic Workflows shipped.
> (2) I used Anthropic's cookbook *sizing ladder* to defeat a claim about *role differentiation*;
> `research_lead_agent.md` assigns subagents different **topics**, never different **roles**, and
> contains no adversarial, verification or red-team slot at all. §1 and §3 below are corrected.
> The governing thought is unchanged — if anything the order-not-precedence reading is stronger,
> since the two parties now land four days apart on the same idea.

## 1. Behind on mechanisms — three of six claims refuted

Claude Code's first npm publish is `0.2.6`, **2025-02-24**. This repository's first commit is
`aa391e46`, **2026-03-24** — thirteen months later, and that commit already contained four agents,
nine commands, a status line and twenty-two hooks. It was an adoption layer from birth.

| Capability | Anthropic | Here | Gap |
|---|---|---|---|
| Hooks | `1.0.38` 2025-06-30 | 2026-03-24 | −9 months |
| Skills | `2.0.20` 2025-10-16 | 2026-06-06 | −7.7 months |
| Status-line `current_usage` | `2.0.70` 2025-12-15 | consumed 2026-07-14 | −7 months |
| Task management + dependencies | `2.1.16` 2026-01-22 | 2026-07-18 | −6 months |
| File-based auto-memory | `2.1.59` 2026-02-25 | 2026-06-06 | −3.4 months |
| `--worktree` flag | `2.1.49` 2026-02-19 | *never adopted* | 33 days before this repo existed |
| Subagent count scaling with complexity | cookbook ladder, ≤ Jun 2025 | 2026-05-24 | −11 months |
| Adversarial-role research team | `2.1.154` 2026-05-28 | 2026-05-24 | **+4 days — see §3** |
| Peer session messaging | `2.1.224` 2026-08-07 | 2026-07-10 | **+28 days — see §3** |

One example we believed in inverts. One splits.

**The status line.** We thought the fields for an accurate context percentage did not exist and were
added silently months later. They were already there — `current_usage` 2025-12-15, `used_percentage`
at `2.1.6`, 2026-01-13 — both present in the very `2.1.114` binary (2026-04-17) we believed lacked
them, and unread here until 2026-07-14. A consumption gap of our own making. (`2.1.114` is also a
single-file executable with no `cli.js`, so the introspection we remember cannot have happened.)

**Research fan-out splits in two, and only one half is inherited.** *Scaling agent count with problem
size* was already Anthropic's published ladder — `research_lead_agent.md`: "Simple queries: 1 subagent
· Standard: 2-3 · Medium: 3-5 · High complexity: 5-10 (maximum 20)" — and our own evidence document
quotes it, concluding our 10-30 default sat in their **pre-pruning** regime. That sub-claim is theirs
by eleven months. *Differentiating the roles* is not: see §3.

**The denominator matters.** ~316 live artifacts across ~60–100 subsystems, of which roughly six have
a vendor counterpart *at all*. Two survivors from six tested is close to the base rate for parallel
obvious needs; hits published without that denominator are selection bias.

## 2. Level on sequence — each fix manufactures the next bottleneck

No shared mind is needed. Both parties optimise the same objective — useful agent-hours per
human-hour — over the same resource lattice (context, sessions per human, quota, human attention,
wall-clock, trust) through the same affordance set. With one binding constraint at a time the greedy
path is nearly unique: relieve single-session quality and throughput binds; relieve throughput and the
shared checkout collides; isolate the checkouts and context exhausts; recycle contexts and the sessions
cannot hear each other. The *sequence* belongs to the tool and the workload, not the builder.

Written as a prediction before reading the history, that cascade matched this repo's chronology on
**eight of nine rungs, in order**. The one deviation explains itself: worktrees arrived two rungs early
because Anthropic bundled them into the team primitive.

The commit curve is the mechanism's own instrument — 4 in March, 24 in April, **zero in May**, 19 in
June, 1,515 in July, 422 in seven days of August. The May zero is the predicted inter-ceiling plateau: a
curiosity-driven builder trickles, a ceiling-driven one goes silent. July compounds because each ceiling
removed multiplies throughput toward the next.

The lead, where it exists, is mostly *shipping latency* rather than foresight. We built a 380-line
writer-lock stack on 2026-06-02 and deleted it on 2026-06-03 on its own soak verdict — build, measure,
retire in thirty hours. No vendor cycles a shipped surface that fast.

**What proves convergence rather than derivation is the two places we arrived *second* at the same
invariant.** Our auto-continue loop caps at `CLAUDE_CONTINUE_MAX:-8`; Anthropic's hard cap (`2.1.143`,
2026-05-15) is eight consecutive blocks — same number, seven weeks apart, our code naming neither their
variable nor their cap. And peer messages must not carry the operator's authority: theirs `2.1.166`,
2026-06-05; ours some five weeks later. Same law, reached from the other side. Nothing here predicts a
vendor feature; the only forward-looking notes are *waiting-on-vendor* ones. This was lived, not tracked.

## 3. Ahead only on the policy layer — and there, uncontested

The steady state is legible: **Anthropic owns the substrate, this repo owns the policy above it.** That
is why ~80% of the texture here is hooks, gates and verifiers rather than features — hooks are the
extension point the substrate affords. When a general rail arrives, the local stack migrates onto it and
keeps only the delta.

Five things still have no counterpart as of `2.1.225`, today:

- **Session succession** (2026-07-02). Their entire context surface is intra-session compression
  (compaction, context editing) plus same-session relocation (`--resume`, `--fork-session`, `--teleport`).
  Nothing writes a bridge, launches a *new* session on a chosen account and model, and auto-submits it.
  Nearest neighbour postdates it: `/fork`, `2.1.212`, 2026-07-16.
- **Frozen-scope carryover** (2026-07-18). Compaction summarises what happened; it does not re-inject what
  must still be true. *Their unit of continuity is the conversation; ours is the contract.*
- **Claim leases on a cross-account work queue** (2026-07-19; one board across four accounts 2026-07-29).
  A vendor claim locks at the instant of claim and nothing after; their own docs name the hole and
  prescribe *"update the task status manually or tell the lead to nudge the teammate."* Ours is a sweep.
  Their store path encodes the session id, so cross-session sharing is foreclosed by construction.
- **Merge-back discipline** (≤2026-06-06): rebase-onto-default with `--ff-only`, smallest-diff-first,
  `git rerere`, one owner per shared file, and the four conflict classes worktrees do *not* prevent —
  same-hunk, JSON-array-append, lockfile, semantic. Zero of 5,370 changelog lines mention `rerere`,
  `ff-only`, merge-back or conflict classes. Anthropic owns getting you *into* an isolated checkout;
  nobody upstream owns getting the work back out.
- **Enforcement where they warn.** Off-allowlist teammate models are hard-denied at spawn here
  (2026-04-17); Anthropic added a *warning* at `2.1.223`, 2026-08-05, and was still fixing the silent
  demotion at `2.1.224`, 2026-08-07. A hundred and ten days, and we deny where they warn.

**And a sixth that was contested for four days: a research team that verifies against its own output.**
Anthropic always let you *scale* searchers; until Dynamic Workflows it never shipped a team any of whose
members attack the team's findings. `research_lead_agent.md` is explicit — subagents get different
**topics**, never different **roles**, and *"no adversarial, verification, or red-team roles exist …
the synthesis responsibility rests entirely with the lead."* Across all 481 versions only four changelog
lines mention adversarial/critic/judge/verifier/refute at all, and the sole pre-`2.1.154` one is a
guardrail verifier attached to a hook (`2.1.118`, 2026-04-22), not a research role; Anthropic's own
`/deep-research` grew a verifier stage only at `2.1.196`, 2026-06-29. Our mandatory 15–20% adversarial
floor across four distinct brief types dates to **2026-05-24**; Dynamic Workflows' adversarial-verify,
judge-panel and completeness-critic patterns to **2026-05-28**. Four days, and neither borrowed the
other's vocabulary — zero shared distinctive terms in either direction.

**Peer messaging is the clearest lead, and the vendor dates it themselves.** Ours: registry and ping
2026-07-10, mail 2026-07-20; theirs `2.1.224`, 2026-08-07 — 28 and 18 days later. Their changelog does
name "cross-session messaging" under repair at `2.1.162`/`2.1.166` (2026-06-03/05), but that is teammate
mailbox scope on a different transport, and their own docs settle it: *"Cross-session messaging requires
Claude Code v2.1.224 or later"*, with `/list-agents` as the test for whether a session has the feature at
all. Both designs landed on the same shape anyway: a per-session box plus an on-disk registry,
plain-text-only payloads, delivery at safe tool boundaries, sender-side loop damping.

---

**So the claim worth making is not that a power user sees the roadmap.** It is that the roadmap and the
power user descend the same gradient on the same landscape — and the user arrives first only where they
can ship in thirty hours, or where the ceiling exists solely at fleet scale. Everywhere else the substrate
lands first, and the correct move is to migrate onto it and keep the delta.

*Stated once: vendor dates are npm publish timestamps, which can trail the code — that can only make our
position worse, never better. Two of our dates are bounded rather than pinned (the worktree section of
`CLAUDE.md` ≤2026-06-06; `corpus-to-skill` by filesystem birth) and are labelled above.*
