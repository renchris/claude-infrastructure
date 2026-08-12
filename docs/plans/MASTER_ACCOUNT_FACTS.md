---
status: open
---

# MASTER: account facts — which account, which model, and whether it can still authenticate

**Condition key:** `master-account-facts` · **Live members 2026-08-12:** 22 (17 open · 5 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-account-facts" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Every routing decision in the fleet reads these facts, so an error here is
never local: a stale `providers.json` row, an account whose CLI→GitHub link is missing, a router that
is built and landed but NOT WIRED. And the facts have a hard property the rest of the store does not —
**they perish.** A grant can die long before its quota resets, and only a new `/login` moves the login
cliff, so any conclusion cached about an account is wrong by default and must be re-measured.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **A1 · router + start latency** | **S** | `claude1` pins account 1, bare `claude` auto-routes, start cost cannot regress | — |
| **A2 · auth durability** | **S** | a forced logout is RECORDED; the refresh herd stops losing races | — |
| **A3 · provider surface** | **S** | MCP / multi-provider / adversarial-slot facts are current and probed | — |
| **A4 · the skills fork** | **S** | the 19 untracked skills have a tracked source | — |

**Lead context budget:** ≥50%. **Succession point:** after A1 — it is the one the operator feels, and
it is the largest single sub-wave.

## Sub-waves

### A1 · Router + start latency (the operator-visible one)
The interactive account router is **built, tested and landed but NOT wired** — wiring it edits
`~/.zshrc`, which is why it stalled (that row is `master-operator-gated`; coordinate rather than
re-deciding). The measured start-time terms: `SessionStart` burns 5 s per launch on a function that is
killed and returns EMPTY; `probe_provider` is 4.31 s of a 4.37 s warm `claude-accounts --json` (6
providers, 8 child CLI processes); `claude-accounts collect()` can go 2,480 ms → 340-674 ms with a
5-way parallel. Also here: the router's KMAX keys on RESIDENT rather than ACTIVE sessions, so one
integer refuses the 33rd session.

⚠️ **A config flip is not a shell flip** — a new launcher name exists only in shells started AFTER the
rc change, so pin it via an env prefix when verifying (memory: `config-flip-is-not-a-shell-flip`).

### A2 · Auth durability
**No instrument records a forced logout** — build the per-account auth-state time series (the recorder
is built + wired but NOT armed; arming loads a LaunchAgent and is operator-gated). The oauth refresh
herd is a losing race: jitter the refresh within an account and let `heal()` run with live sessions.
`next2` carries a `.linked` marker but cannot create and falls back to bundle mode. A PARITY GUARD row
names two hand-copied implementations (`cc-relogin live_sessions()` vs `claude-accounts concurrency()`)
that must not drift.

### A3 · Provider surface
`providers.json`'s `pi-codex` row is STALE on the live layer (the fix landed and is not live — that is
`master-convergence-deadlock`'s chain, not a second bug). MULTI-PROVIDER PLANS, MCP MEMORY 100P, and
the CODEX ADVERSARIAL SLOT PROBE (certify or reject `gpt-5.6-sol`) are the design rows. The Fable probe
fails on ALL FOUR accounts with an undocumented signature.

⚠️ **A version claim is about the running process, not the launcher** — `ps -o command= -p $PPID`, never
a launcher's `--version` (memory: `version-identity-is-the-running-process-not-the-launcher`).

### A4 · The skills fork
19 skills live in `~/.claude/skills` with no tracked source: untracked, unlandable, and forked across
the four config dirs. The fix is a tracked source plus the parity mechanism from
`master-enforcing-store` E1 — do not build a second one.

## Definition of done
Every account fact the fleet routes on is produced by a probe that runs on a schedule and records that
it ran; the router is wired; a forced logout appears in a time series rather than in a surprise; and no
skill or provider row is enforced from an untracked file.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 22 rows on this condition
  (5 pre-existing from the 2026-08-09 triage, 4 by its verdict replay, the rest semantic).
