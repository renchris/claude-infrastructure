---
status: in-progress
---

# Public repo hygiene — keep github.com/renchris/claude-infrastructure public, safely

Scope (frozen): make github.com/renchris/claude-infrastructure safe to stay PUBLIC — no personal
identifiers, no licensed or unlicensed third-party content, in the current tree AND in the public
git history — with ZERO loss of function or quality on this machine (every hook, skill, tool, test
and the fleet's 88 live worktrees keep working; no sha cited in docs, backlog, decision packets or
stamps is invalidated for the working repo).

Operator ruling 2026-09-26: "clean this without a loss in functionality and quality such that we
can have this as a public repository." Supersedes decision packet `760e13cf37ca` ("make it
private"). Evidence that started this: `docs/research/plugin-packaging-2026-09-26/README.md`
§ Live exposure.

## Phase 0 — orchestration

**Execution locus per wave: L (lead-inline) for every wave.** Why not S (the default): capacity
was MEASURED at intake (`claude-accounts --fresh`, 2026-09-26 ~14:10 CDT): `next` 99% weekly,
`next4` 95%, `next3` stale token (`cc-relogin next3` exits 6, needs the email-code leg), `next2`
refresh rejected. A dispatched session per wave would route onto a 99% account and die mid-wave.
The waves also share one private artifact (the redaction map) that only the lead holds.
Read-only census ran as 5 background subagents (reports under `/tmp/prh-census/`, not tracked
because they quote the identifiers verbatim).

**Lead context budget:** recycle at ~60% via `handoff-fire.sh --recycle`; everything a successor
needs is this file plus `~/Development/claude-private/` (the private store, below).

## What counts as a personal identifier (classification, decided here)

| Class | Verdict | Why |
|---|---|---|
| The operator's e-mail addresses (all mailboxes, `+tag` variants, company domain) | REMOVE | contact data |
| Phone numbers, street/home/lodging data, order/case/account numbers | REMOVE | contact / financial data |
| Private third parties (names with contact data, their addresses, quoted messages) | REMOVE | not ours to publish |
| Personal-life documents (housing, disputes, vendor claims, message-history extracts) | REMOVE (whole file → private store) | the file IS the personal data |
| Dia profile names | REMOVE (overlay) | per-account personal labels |
| Owner name "Chris Ren", GitHub login, macOS short name in `/Users/<name>` paths, hostname, `com.<name>.` launchd labels | KEEP | the public repo's OWNER identity: already public on the GitHub profile and on every commit; rewriting ~7,500 path hits would break fixtures and launchd plists for zero privacy gain |
| Customer business names and public tenant hostnames | KEEP | public businesses; guest data / private contacts under them are REMOVE |

## The private store

`~/Development/claude-private/` — a git repo with NO remote (precedent: `~/Development/personal`,
see `skills/LOCAL_ONLY.md`). Holds:
- `identity.json` — the identity overlay; live as `~/.claude/identity.local.json` (symlink).
- relocated third-party content (`vendor/`, `skills/`, `assets/`) and personal docs (`docs/`).
- `public-projection/` — the redaction map (`replace-text.txt`), the path-removal list and the
  mailmap. Private because each one names what it hides.

## Phase A — clean the tree, keep every function

| # | Item | State |
|---|---|---|
| A1 | Identity overlay: `hooks/lib/identity.{py,sh}`, `identity.example.json`, `tests/fixtures/identity.fixture.json`, `tests/identity-overlay.bats` | in progress |
| A2 | Readers: `bin/claude-accounts` load_cfg merge; `bin/cc-relogin`, `bin/cc-url-open`, `scripts/cloud-create-api.py`, `scripts/handoff-fire.sh` keychain, `scripts/relogin-probes/e1-concurrent-logins.sh`; strip the 4 personal fields from `accounts.json` | todo |
| A3 | `hooks/enforce-email-formatting.py`: MAILBOXES + RECIPE rendered from the overlay; its 6 suites on the fixture; pinned-blob red-proof arms derive inputs from the blob | todo |
| A4 | Git identity gate: `githooks/pre-commit`, `githooks/pre-push`, `scripts/git-identity-assert.sh`, `scripts/postland-verify.sh` read `git_identity` from the overlay (fail CLOSED when absent; `CC_IDENTITY_FILE` honoured only under `CC_GIT_IDENTITY_TEST=1`, added to the validate-bash seal) | todo |
| A5 | Local-only relocation: `vendor/uidotsh`, `skills/{grok-wiki-cli,grok-wiki-custom,repo-wiki,kpmg-deck}`, BMO character renders; live links re-pointed into the private store BEFORE untracking; install.sh private leg; `skills/LOCAL_ONLY.md` rows; NOTICE for `test-audit` (MIT) and `agent-browser` (Apache-2.0); rewrite the quoted ui.sh example in `skills/visual-direction` | todo |
| A6 | Docs/tests/prose scrub: personal docs moved whole to the private store; the rest rewritten with the SAME redaction map Phase B uses, so the projected tip tree equals the working tip tree | todo |
| A7 | Land-gate lint `scripts/public-hygiene-lint.sh` wired into `scripts/ship-land.sh`, with `--selftest` mutation control | todo |

Ordering constraint (from the consumer map): re-point every live link to the private store first,
then untrack. `deploy-live`'s `orphan_prune` deletes dead links whose target is inside the
checkout, and never judges links that point elsewhere.

## Phase B — clean the public history without rewriting the working one

Design and measurements: to be filled from the determinism experiment (see § Phase B research).

## Known constraints

- One fork and two stars predate this work; whatever the fork copied cannot be recalled.
- GitHub keeps serving orphaned commits by sha until GC; purging cached views needs a GitHub
  Support request (operator step).
- No LICENSE is added (out of scope; a public repo without one is lawful, all rights reserved).
