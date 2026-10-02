# How 93 off-identity commits reached main (2026-08-24 to 2026-09-04)

Backlog `8f4eae55a0c7` (the GitHub author-email ruleset row). Traced 2026-10-02.

## Answer

All 93 were written by **claude.ai/code cloud VMs that ran this repo's own `/ship` from their own
clone and pushed `main` directly**. A cloud clone has no `githooks/` installed (the identity gates
are installed per machine by `scripts/git-identity-assert.sh`) and no identity overlay, and
`scripts/ship-land.sh` carries no identity check of its own, so nothing stood between a VM's
`noreply@anthropic.com` commit and GitHub. GitHub had, and has, no ruleset and no branch
protection on `main`.

The route stopped carrying commits because the cloud brief changed, not because anything now
refuses the push. That residual is why `scripts/postland-verify.sh` now pages on any landed
off-identity commit (section 4).

## 1. The population

`git log origin/main` with author or committer email not the sanctioned address, author-dated
2026-08-24 to 2026-09-04: **93 commits** (88 `noreply@anthropic.com` as both author and committer;
5 authored by a second personal address of the operator (a Hotmail alias), one of them committed by `noreply@anthropic.com`).
61 carry a `Claude-Session: https://claude.ai/code/session_…` trailer. All 93 are on main's
first-parent line (fast-forward lands, no merge commits). None after 2026-09-04: of the 2,463
commits on main since 2026-09-05, zero are off-identity.

The older off-identity commits on main (`t@e.com`, `t@t` and two other personal aliases,
2026-07-26 to 2026-08-08) predate this window and are the local
`.git/config` leak covered by `docs/research/git-identity-leak-2026-08-05.md`; they are not part of
this trace.

## 2. Which land path carried them

The shared checkout's `refs/remotes/origin/main` reflog records how each commit first became
visible on this Mac. For each of the 93, the first reflog entry whose sha contains it:

| first seen via | commits |
|---|---|
| `fetch … : fast-forward` (pushed to GitHub by something other than this repo's object store) | 89 |
| `update by push` at 2026-08-24 21:48 PDT (`0612bdad2`, a local land) | 4 |

None was pushed from this Mac: a push from the checkout or any of its worktrees and sandboxes is
logged as `update by push`, and 89 of 93 never were. The other four (`fc7f4ac17`, `9a983e903`,
`6e900ea67`, `14287ae8e`) sit below eleven locally authored commits in `0612bdad2`'s ancestry. That
local push's pre-push range is `remote_sha..local_sha` with `remote_sha` taken from GitHub's own
advertisement, so commits already on GitHub's main are excluded. These four were already on GitHub
and were first *observed* here through that push's update of the tracking ref. All 93 entered
GitHub the same way.

The VM side is on record in the commits themselves. `8492afe70` (2026-08-29, authored by a VM)
records: *"First /ship from this VM died GATE-KILLED (exit 9) … `apt-get install -y shellcheck`
cleared it and the re-land went green first try."* A VM ran `ship-land.sh` and landed.

Why VMs ran `/ship`: until `0efcc073d` (2026-09-02T04:32Z) the brief that `bin/cc-dispatch`
composes gave every venue the same rail, "land ONLY via the project-local /ship". The cloud venue
had been the dispatcher's only venue since 2026-08-11 (`CC_DISPATCH_VENUE_ONLY=cloud`, recorded in
`da4719b42`). The off-identity lands from 2026-09-02 to 2026-09-04 are VMs fired before that
change.

## 3. Is the route closed?

**Stopped by instruction, not closed mechanically.**

* Since `0efcc073d` the cloud brief (`bin/cc-dispatch:3083-3084`) reads: "commit on THIS branch and
  PUSH it … the desk lands it for you (scripts/cloud-return.sh). Do NOT run /ship, do NOT push to
  trunk, do NOT land anything yourself." The desk land goes through `scripts/cloud-reconcile.sh`,
  which re-authors the range (`--reset-author`, with provenance trailers) before the pushes that
  pass the local `githooks/pre-push`.
* Cloud fires also stopped from 2026-09-04T19:38Z to 2026-09-07 (the pending-pile cap,
  `124c4da06`). The last off-identity land is 2026-09-04T18:07Z, so the clean run since then
  covers about 3.5 weeks of new-brief fires, not only the outage.
* Still open: a VM can push `main` (its GitHub credential allows it), and `ship-land.sh` does not
  refuse an off-identity range, so a VM that ignores the brief, or a brief regression, would land
  off-identity again. GitHub's server-side fix needs Enterprise Cloud (section 5).

## 4. What now detects it

`scripts/postland-verify.sh` `identity_landed_sweep`, run every launchd tick right after its fetch
of main and before any abstain. It scans the commits added to origin/main since the last scanned
tip and pages (`$PAGES/postland-identity-<tip>.page` plus an OS notification) when an author or
committer email is not the sanctioned address from the identity overlay. The first run seeds at
the current tip without paging, so these 93 are reported here once rather than paged forever.
Suite: `tests/postland-verify-identity.bats`. A recurrence is now visible within one 5-minute tick
instead of a month.

## 5. Why the GitHub ruleset row is won't-do

The rule that restricts commit author or committer email is a ruleset *metadata restriction*. It
is documented only for GitHub Enterprise Cloud:
<https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#metadata-restrictions>.
The same page in the Free/Pro/Team docs has no "Metadata restrictions" section (checked
2026-10-02: 1 occurrence of the heading in the enterprise-cloud version, 0 in the default one), and
`renchris/claude-infrastructure` is owned by a user account (`gh api repos/renchris/claude-infrastructure`:
`owner.type = User`). `gh api …/rulesets` returns `[]` and `…/branches/main/protection` returns
404.

## Out of scope

Rewriting the 93 commits needs a force-push of `main`. That is the operator's decision and is not
raised here.
