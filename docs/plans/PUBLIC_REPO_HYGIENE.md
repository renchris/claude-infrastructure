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
| Dia profile names | KEEP (values moved to the overlay anyway) | generic labels, not identifying |
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
| A1 | Identity overlay: `hooks/lib/identity.{py,sh}`, `identity.example.json`, `tests/fixtures/identity.fixture.json`, `tests/identity-overlay.bats` | DONE `d588b356d` |
| A2 | Readers: `claude-accounts` load_cfg merge, `cc-offload`, `cc-url-open`, e1 probe; `accounts.json` loses email/mailbox/dia_profile. `keychain_account` STAYS (it is the macOS short name — owner identity, KEEP). Proof: `--relogin-info` byte-equal for all 4 accounts | DONE `178e0f595` |
| A3 | Email gate: MAILBOXES + RECIPE rule 5 rendered from overlay `ms365.{mailboxes,roles}`; read as JSON, not imported (suites run mutant copies from tmp). Rendered RECIPE differs only in the generalised vendor anecdote | DONE `728db7499` |
| A4 | Git identity gate reads `git_identity.email`; missing overlay refuses in-scope commits | DONE `668c450d4` |
| A5 | Relocation to `~/Development/claude-private`: vendor/uidotsh, grok-wiki-cli, grok-wiki-custom, repo-wiki, kpmg-deck (its own nested repo, moved whole), BMO renders; install.sh private-overlay leg; MIT/Apache notices; visual-direction example rewritten | DONE `6ced7d2aa` |
| A6 | 112 personal-life docs moved whole to the private store (same relative path) + `skills/outlook-cleanup` made local-only (`771383db4`); model-facing texts name mailboxes by role (`354d43e1e`); the remaining 96 files take the projection's own tip tree, so **working tip tree == projected tip tree** by construction | DONE (see git log) |
| A7 | `scripts/public-hygiene-lint.py` (private-map identifier arm + unlisted e-mail + phone + local-only paths; `--own-range`/`--tree`/`--history`; rg fast path) wired into `scripts/ship-land.sh` every land, own-scope; `--selftest` + 2 mutation tests in `tests/public-hygiene.bats` | DONE (see git log) |

Ordering constraint (from the consumer map): re-point every live link to the private store first,
then untrack. `deploy-live`'s `orphan_prune` deletes dead links whose target is inside the
checkout, and never judges links that point elsewhere.

## Phase B — clean the public history without rewriting the working one

**Decision (conviction 92%): rename the current repo to a PRIVATE working origin, publish a
deterministic `git filter-repo` projection of `main` at the original URL.** Measured
(`/tmp/prh-census/S5-phaseB.md`, experiment scripts `/tmp/prh-phaseb/`):
- Determinism: 6 cut points (incl. a pruned-empty tip, the one merge, its side branch) — every
  shorter projection is a strict prefix of the longer one, 0 of 5,799 commit-map rows disagree;
  a re-run is bit-identical. **`--preserve-commit-hashes` is mandatory**: without it the output
  depends on emission order (4,130 commits differ under `--date-order`) and on the ref set.
- Full projection ~25 s; build from a dedicated main-only clone, never `--source <bare> --push`.
- Rejected: rewrite-in-place + force-push (all 5,799 main shas change; 2,221 cited in docs and
  3,821 in the autonomy stores); private-only (hermetic CI ≈ 30,700 macOS min/month ≈ $1,900 on a
  private repo, and contradicts the ruling); GitHub-native (nothing redacts history).
- Rule-set freeze: any later change to the redaction map re-projects old commits = a
  non-fast-forward republish. The publish script must refuse non-FF unless explicitly re-baselined.
- Cutover couplings (all must be handled before the public repo takes the name):
  `scripts/cloud-create-api.py:500` default `--repo` slug; `hooks/lib/dod-path.sh` keys the DoD
  store on `sha(remote.origin.url)`; `bin/cc-offload` `attached_project` uses the origin basename;
  `scripts/offbox-green-pull.sh` queries check-runs on origin by private sha (must query the
  public repo and map via the persisted commit-map); `.github/workflows/hermetic.yml` must be
  disabled on the private repo before the visibility flip (macOS minutes).
- Exposure that cannot be recalled: fork `zeroxvee/claude-infrastructure` (305 commits; 2 tip
  files carry identifiers); GitHub cached views of old shas until Support purges them.

### Phase B — built

- `scripts/public-publish.sh`: main-only clone → `git filter-repo --preserve-commit-hashes`
  (paths, replace-text, replace-message, mailmap) → verifier (lint `--history` + gitleaks over the
  projection) → fast-forward check → optional `--push --confirm <owner/repo>`; persists the
  commit-map to the private store. Measured on this branch: 5,792 commits, ~2.5 min end to end,
  `projection-verifier: 0 identifier hit(s), 0 gitleaks finding(s)`.
- **The redaction map is LITERALS ONLY.** filter-repo runs every regex rule as a full pass over
  ~1.3 GB of history blobs: a 12-regex map ran >11 min, 142 literals ~106 s. Each spelling was
  enumerated from ALL of main's history (`rg -o -i` over exported blobs), longest first; a NEW
  spelling is caught by the lint's generic e-mail/phone arms and then added. filter-repo applies
  all literals before any regex and does NOT skip `#` lines — the publisher strips them.
- Couplings, each inert until the cutover sets its key: `cc.canonicalUrl` (DoD store key,
  `cc-offload` project label), `cc.publicRepo` + commit-map (`offbox-green-pull.sh`, selftest P8),
  `cloud-create-api.py` default `--repo` = this checkout's origin (a cloud VM pushes, so it must
  follow the PRIVATE repo).
- Recurring publisher: `scripts/public-publish-tick.sh` via launchd `com.claude.public-publish`
  (every 3 h), declared `staged`; inert until `publish-enabled` exists in the private store.
- The one irreversible step is the operator's: `docs/activation/pending-activation/46-public-repo-cutover.sh`
  (dry run by default; `--confirm renchris/claude-infrastructure` executes; bundle backup first;
  self-verifying post-check re-clones the public repo and scans its whole history). Tested offline
  end to end in `tests/public-hygiene.bats` (gh state machine incl. the rename redirect).
- After the cutover: flip `launchd/fleet.manifest`'s `com.claude.public-publish` row to `run`.

## Known constraints

- One fork and two stars predate this work; whatever the fork copied cannot be recalled.
- GitHub keeps serving orphaned commits by sha until GC; purging cached views needs a GitHub
  Support request (operator step).
- No LICENSE is added (out of scope; a public repo without one is lawful, all rights reserved).
