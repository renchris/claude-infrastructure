---
status: in-progress
---

# Consolidation projects — audit 02 (`cc-backlog b13787e71c9f`)

**Scope (frozen):** drive backlog item `b13787e71c9f` to finished-verified-landed — the five
consolidation projects named by `audit02-deadbin 2026-07-25`.

**Source note:** audit 02 was an in-session audit; it left no doc. The ledger *title* is the only
spec, so every target below was **re-derived from disk truth** in this session before being acted on
(memory `re-derive-handed-down-measurements`: a handed-down count is a CLAIM, not data). Two of the
audit's five prescriptions did not survive that re-derivation — recorded below with evidence, because
a rejected prescription is a finding, not a silent scope cut.

## Phase 0 — orchestration

Single session, serial, one atomic commit per sub-item. Agent Teams **waived** for this item by
explicit session directive ("Do not call the AgentTool unless the user requested it"), which
overrides the global 2+-files Agent-Teams default. Sub-items are independent (no shared files), so
serial execution costs nothing but wall-clock.

Gate (from `scripts/ship-land.sh:165` `run_gate`): `shellcheck` + `bash -n` on changed shell files ·
`py_compile` on changed python · **`bats tests/` (whole suite)**. Land via project-local `/ship`
only (standing-land authorization, `.claude/CLAUDE.md`).

## Re-derivation results — what is actually on disk

| # | Audit prescription | Disk truth (2026-07-29) | Verdict |
|---|---|---|---|
| 1 | `lib/idl-inert-check.sh` — 4 lockstep copies | **CONFIRMED.** `log_idl()`+`abstain()` byte-lockstep in 4 hooks; a 5th `MODE`-guarded variant in `operator-readout.sh` | **DO** (relocated — see below) |
| 2 | `lib/cc-common.sh` — jq-guard ×23, `resolve_bin` ×5, selftest scaffold ×16 | jq-guard = **29** top-level guards with **4 different semantics**; `resolve_bin` = **2** definitions (×5 counted *call sites*); selftest scaffold = 16 files but **7 divergent variants** | **PARTIAL** — `resolve_bin` only; other two rejected |
| 3 | comms collapse `cc-mail{send,await,contract,announce,thread,guard}` | Named 6 do not exist. Family is `cc-notify`/`cc-announce`/`cc-await-ping`/`cc-inbox-guard`. ~~**`bin/cc-mail` is ABSENT from `origin/main`**~~ — *stale as of 2026-07-31: landed via `ff839f1f8f38` (cherry-pick of `57579877`); see §3 update. The `mail-v3` restructure is still unlanded on `feat/cc-mail` + `wt-02ba4e52389a`, which is what keeps the verdict.* | **STAND DOWN** (unchanged) |
| 4 | merge `plan-update` into `plan-conventions` (stale split-brain) | **CONFIRMED.** 479-line `plan-update/SKILL.md` vs 45-line `plan-conventions/SKILL.md`, cross-referencing each other | **DO** |
| 5 | unify `model-config.yaml` SSOT | **CONFIRMED, with teeth.** Template line 1 claims SSOT but **no consumer reads it**; all 8 consumers read `$HOME/.claude/model-config.yaml`, an **unversioned 36 KB real file** | **DO** |

### 1 — IDL logger lib → `hooks/lib/idl-log.sh` (NOT `lib/idl-inert-check.sh`)

Four byte-lockstep copies of `log_idl()`+`abstain()`, differing only in the hook-name literal, the
sid variable (`sid` vs `SID`), and boundary-handoff's missing `|| echo '?'` date fallback:

- `hooks/boundary-handoff.sh:98-112`
- `hooks/waiting-recycle.sh:285-297`
- `hooks/completion-assert.sh:38-52`
- `hooks/anti-deference-nudge.sh:59-73`
- (5th, variant) `hooks/operator-readout.sh:79-93` — adds `[ "$MODE" = hook ] || return 0`

**Why a lib at all** (this is a correctness coupling, not cosmetics): all four carry the same
load-bearing invariant in a comment — *jq-encode EVERY field, because one malformed IDL line aborts
the `cc-audit` `jq -rs` slurp, which reads as "no records" and silently flips the abstain alarm
GREEN*. An invariant that must hold identically in four places is exactly what a lib is for; today a
fix to one copy leaves three wrong.

**Why `hooks/lib/`, against the audit's `lib/`** — decided on disk truth, not preference:

- `install.sh:93-96` **globs** `hooks/lib/*.sh` and symlinks each → a brand-new file there
  auto-deploys. `sync.sh:56-59` round-trips it back.
- Top-level `lib/` is globbed by **neither**. Its two files are linked only by a hand-written
  operator activation script (`docs/activation/pending-activation/06-desk-bootstrap-activate.sh:78`).
  A hook-sourced lib placed there would be **silently missing until an operator acted** — the
  built-but-inert failure class (memory `feature-durability-mechanism-not-memory`), on the Stop path
  of every session.
- `hooks/lib/` is already a proven production pattern (10 libs, all live-symlinked) with an
  established 3-tier sourcing idiom (`hooks/session-continue.sh:44-47`): beside-script →
  `$CLAUDE_CONFIG_DIR/hooks/lib` → `$HOME/.claude/hooks/lib`.

**Why not delegate to `cc-idl append`** even though `bin/cc-idl` advertises itself as the canonical
writer: that would add a `perl`+`jq` fork to every Stop-hook invocation. One unbounded fork in a hook
is what blocked every gate for five days (memory `five-day-gate-blockage-rootcause`). The lib stays a
pure `jq` append — **behaviour-preserving, zero new dependencies on the hot path**. `cc-idl` already
covers these writers via its periodic `seal`, by its own design note ("the ~14 existing writers stay
UNCHANGED").

**Name:** `idl-log.sh`, not `idl-inert-check.sh` — the code being extracted *writes* the IDL; it does
not check inertness. `scripts/idl-abstain-alarm.sh` is the inert *check*, and it is not duplicated.

### 2 — `lib/cc-common.sh`: `resolve_bin` only; two targets rejected

**`resolve_bin` — DO.** Two definitions, not five (the audit counted 6 call sites across 2 files):
`scripts/boot-resume.sh:46` (3 params, searches a beside-script tier first) and
`scripts/autonomy-sweep.sh:42` (2 params, no beside tier). boot-resume's is a strict superset once
`beside` defaults to `$2`. Both consumers are launchd-loaded, so the resolution *order* change for
autonomy-sweep must be proven inert before it lands.

**jq-guard — REJECTED, with reason.** Not duplication; a shared *convention* with four distinct
semantics across 29 sites: `|| exit 0` (13 advisory hooks) · `|| { echo "<name>: jq required"; exit
1|2; }` (9 fail-closed CLIs) · `|| abstain "no-jq"` (5 IDL hooks) · `|| return 0` (1). Decisively:
**you cannot `source` a lib to discover whether `jq` exists** — that replaces a zero-dependency
one-line guard with a heavier dependency than the one being guarded, and converts 29 currently
self-contained scripts into 29 that fail if a lib is missing. Strictly worse; not landed.

**Selftest scaffold ×16 — REJECTED, with reason.** 16 files, but hashing the `okp()`/`badp()`
definitions yields **7 distinct variants** (largest cluster 4). They are not lockstep. Unifying them
would change selftest *output* in 16 independently-deployed scripts, each with bats tests pinned to
that output — large blast radius, no operational benefit, for a 3-line reporter.

### 3 — comms-family collapse: STAND DOWN (evidence-backed)

The six `cc-mail{send,await,contract,announce,thread,guard}` binaries named by the audit do not
exist. The real family is `cc-notify` · `cc-announce` · `cc-await-ping` · `cc-inbox-guard`. And the
blocker is decisive: **`bin/cc-mail` is absent from `origin/main`** while `~/.claude/bin/cc-mail`
runs live (4713 B, Jul 26). Its restructure — the `mail-v3` line, `bc313459` and siblings — is
committed only on `feat/cc-mail` and `wt-02ba4e52389a` (another worktree's branch), matching memory
`cross-session-mail-v3`: *"P2-P4 BUILT, LAND-BLOCKED"*.

> **UPDATE 2026-07-31 — this section's FIRST cited blocker is cleared; the STAND DOWN verdict still
> stands on its remaining two.** `bin/cc-mail` is **no longer absent from `origin/main`**: backlog
> `ff839f1f8f38` landed it by cherry-picking `57579877` off the stranded `feat/cc-mail` (byte-identical
> to the live file, plus its 146-line `tests/cc-mail.bats`; 19/19 green). So "absent from main" must
> **not** be re-cited as a blocker after this date. What is unchanged, and still decisive on its own:
> (a) the six `cc-mail{send,await,contract,announce,thread,guard}` binaries the audit named still do
> not exist, and (b) the `mail-v3` restructure (`bc313459` and siblings) is **still** unlanded on
> `feat/cc-mail` / `wt-02ba4e52389a` — only the single `bin/cc-mail` + test commit was recovered, not
> that stream. Collapsing the family would still collide with it. **STAND DOWN is unchanged.**

Collapsing this family from `main` would refactor a shape that **is not main's shape**, and would
collide head-on with an unlanded parallel stream that already restructures it (memory
`parallel-stream-convergence-protocol`: if theirs owns it, STAND DOWN). Correct sequence: land
`mail-v3` first, then re-derive whether a collapse is still wanted. Not attempted here.

### 4 — `plan-update` → `plan-conventions`

Split-brain confirmed: `plan-update/SKILL.md` (479 lines, the mechanical applier) and
`plan-conventions/SKILL.md` (45 lines, the ruleset) each point at the other as the companion.
Referenced by `hooks/validate-plan-structure.sh` + `docs/CLAUDEMD_LAZYLOAD_REVIEW.md` — both must be
swept so the merge cannot leave a dangling pointer.

### 5 — `model-config.yaml` SSOT

The split-brain has a live consequence: **the Opus 5 activation exists in no committed file.**

| | `templates/model-config.yaml` (committed) | `~/.claude/model-config.yaml` (live, unversioned) |
|---|---|---|
| `opus_latest` | `claude-opus-4-8` | `claude-opus-5` |
| `opus_staged` | `claude-opus-5` (staged) | `""` (activated) |
| `lead_default` | `claude-opus-4-8` | `claude-opus-5` |
| `non_firstParty_max` | no `claude-opus-5` | includes `claude-opus-5` |
| Read by consumers | **never** | all 8 |

Line 1 of the template claims *"Single source of truth for Claude model versions + role
assignments"*, yet every consumer (`bin/cc-route`, `bin/claude-accounts`, `bin/claude-bump-models`,
`scripts/claude-lint-models.sh`, `scripts/route-safety-gate.sh`, `hooks/frontier-spawn-gate.sh`,
`hooks/frontier-status.sh`, `tests/effort-parity.bats`) reads `$HOME/.claude/model-config.yaml`. So
the file that claims SSOT is authoritative for nobody, and the file everyone obeys — carrying the
whole `§ Opus 5 adoption` decision record — is one `rm` from unrecoverable. Same class as the
LIVE-ONLY activation-script drift the SessionStart banner reports.

**Fix shape:** commit the live content as the versioned SSOT, demote the template's self-description
to what it actually is, and add a drift assert so the split cannot silently recur (precedent:
`scripts/settings-drift-assert.sh`, `scripts/deploy-parity-assert.sh`). Replacing the live real file
with a symlink is a live-layer mutation → **staged as an operator activation script, never applied
in place** (C10).

> **UPDATE 2026-08-12 — the THIRD part of that fix shape had not been built, and the assert nearest
> the failure reported parity over it.** `69ddae7`. The first two parts landed; "add a drift assert"
> did not, and the Status checklist below recorded only the two. `deploy-parity-assert.sh` already
> enumerated `model-config.yaml` under a class it NAMED `root SSOT (link)` — but the check is `-e`,
> which **follows a symlink**, so it asked only "does a live counterpart exist?". Reproduced on a
> fixture before the fix: a live *real* file whose content had drifted from the repo SSOT — this
> section's exact finding — scored `ok  root SSOT (link)  2 tracked · 2 live · 0 missing`, **exit 0**.
> `deploy-link-parity.sh` does assert link-ness (`[ -L "$dest" ]`) but covers only the per-file
> directory surfaces and never the root SSOTs, so *neither* reporter could see this class of drift.
>
> Now asserted for that class: a symlink cannot drift, so **link-ness is the property that makes the
> SSOT claim true**. Verdicts reuse the strict-tools leg's vocabulary unchanged — `LINKED` /
> `UNLINKED` (a copy matching *today* is still drift: it diverges on the next repo edit and nothing
> would say so — precisely how the four-day drift happened) / `STALE` (content already diverged ⇒
> "split-brain is ACTIVE"). Scoped to this class deliberately, **not** widened to the per-file
> surfaces, whose failure class is the opposite one (a brand-new tracked file nobody linked).
>
> Two properties keep it from becoming a false RED. `pending_owner` is consulted **before** the
> verdict, so while `20-model-config-ssot-activate.sh` is un-run the live host reports `PENDING`, not
> drift — the operator is not convicted for obeying a design that is waiting on them (the false-RED
> scar this leg already carries). And `DRIFT` is its own class-table column rather than folded into
> `missing`, because the file *does* exist live and the "N tracked runtime file(s) have NO live
> counterpart" summary would otherwise be false; the segment renders only when non-zero, so every
> clean class stays byte-identical. Once the operator runs the activation, a real file reappearing
> there becomes a hard RED — which is the ratchet §5 asked for.

## Two findings surfaced along the way (not in the audit)

1. **`10-opus5-activate.sh` was marked `.done` while its own REMAINING step was never performed.**
   The marker is dated 2026-07-25 14:26; step 1 of its REMAINING block — *"land the SSOT change into
   the repo — the live edit must reach trunk, else it drifts"* — never happened, so it drifted for
   four days. A `.done` marker that absolves an unfinished tail is the absolution-token failure
   class. The step is now completed by sub-item 5 and its instruction rewritten.
2. **That instruction was itself destructive.** It read
   `cp ~/.claude/model-config.yaml <worktree>/templates/model-config.yaml`. Because the two copies
   had drifted in BOTH directions, running it would have silently destroyed the repo-only
   settings-floor documentation (10 lines of 2026-07-24 findings plus the effort-parity-assert
   mechanism). Rewritten in place to point at the new single-file SSOT.

## Concurrent convergence at land time (two sibling sessions, both absorbed)

The rebase onto `origin/main` conflicted twice. Neither was a "take mine" — both were sibling work
that had to survive:

1. **`d9c357bd feat(recycle): size-triggered recycle` added a capability INSIDE `log_idl`.** Both
   boundary-handoff and waiting-recycle now publish a measured size pair into a `SIZE_JSON` variable
   partway through the hook, which `log_idl` merges into every subsequent record — deliberately, per
   its own note: *"merged in log_idl rather than at each call site so 'every eval records what it
   measured' holds by construction: a dormant threshold must never be indistinguishable from broken
   wiring."* Taking my side would have silently deleted a just-landed feature. Instead the lib gained
   a **merge-var slot** (`idl_init <idl> <hook> [sid-var] [merge-var]`), read by indirection at CALL
   time and merged BEFORE `$extra` so a call site can still override — preserving upstream's
   by-construction property exactly. Directly verified: pre-measurement records carry no size,
   post-measurement records carry it, `$extra` overrides a merged field, and a caller with no slot
   configured emits byte-identical output to before.
2. **`3273ed90 chore(model-config): activate claude-opus-5 as opus_latest`** landed the value-resync
   half of sub-item 5 — the never-performed REMAINING step of `10-opus5-activate.sh`. So the
   activation is no longer uncommitted, and this work no longer claims to rescue it; what it lands is
   the *structure* (one versioned file + a symlink) so the two copies cannot drift again. All 15
   routing values are byte-identical to upstream's; the resolution kept upstream's formatting verbatim
   and changed only comments that had come to contradict their own values.

## Verification performed

Every change is behaviour-preserving, and that was *proved* rather than assumed — each check
replayed the real pre-change artifact recovered from git, not an approximation:

- **IDL lib:** for all 5 hooks, the emitted IDL record is **byte-identical** old vs new (`ts`
  normalised) — on the abstain path, on the `fired`-with-extra-JSON path (operator-readout, which
  carries `rung`/`steps_total`/`steps_shown`), and with a real session id flowing through the new
  sid indirection (`sid` → `SID-ABC-123`, including boundary-handoff's lowercase variable).
  `--render` writes 0 IDL lines in both, with the hook-mode write as the positive control.
- **`resolve_bin`:** identical resolutions old vs new for every helper both scripts resolve
  (`cc-notify`, `reso-keepalive`, `cc-decide`, `cc-backlog`), and boot-resume's load-bearing 3-arg
  beside tier still resolves `scripts/boot-resume-launch.sh`.
- **model-config:** all **15/15** routing values byte-identical to the live file (verified with a
  positive control after an initial check passed *vacuously* — zsh does not word-split an unquoted
  variable, so the first version compared empty strings; re-run under python with a real count).
  The merged file additionally retains the repo-only prose the live file lacks. YAML parses.
- Static: `shellcheck` + `bash -n` clean on every changed shell file.

## Status

- [x] Re-derivation of all five targets from disk truth
- [x] 1 — `hooks/lib/idl-log.sh` + 5 call sites (parity-proved)
- [x] 2 — `resolve_bin` → `scripts/lib/cc-common.sh` + install.sh deploy loop (parity-proved);
      jq-guard + selftest-scaffold rejected with reasons
- [x] 4 — `plan-update` frontmatter repaired + rules de-duplicated into `plan-conventions`
- [x] 5 — repo-root `model-config.yaml` SSOT + install.sh link + operator activation staged
- [x] 5b — **the drift assert** §5's fix shape named and this checklist had omitted (`69ddae7`,
      2026-08-12): `deploy-parity-assert.sh`'s `root SSOT (link)` class now asserts link-ness, not
      existence. +5 bats cases (STALE · UNLINKED-but-identical · staged-PENDING · a relative link
      resolving to the repo file · a link into a DIFFERENT checkout). 69/69 green
- [x] 3 — stood down (evidence above)

**Re-derived 2026-08-12, all four DO/PARTIAL sub-items still true on disk** (not read off the boxes
above — a checked box is a claim, not data): `hooks/lib/idl-log.sh` present with all 5 hooks sourcing
it and **zero** surviving lockstep `log_idl()` copies among them (the 9 other `log_idl` definitions
in the tree hash 9 different ways — distinct implementations, never the audit's lockstep class, so
not a regression); `resolve_bin` defined **once** in `scripts/lib/cc-common.sh` with both launchd
consumers on the 3-tier source idiom; `plan-update`/`plan-conventions` de-split with no dangling
pointer; `model-config.yaml` at the repo root with `templates/model-config.yaml` gone. All landed on
`origin/main` and verified BY CONTENT (`git ls-tree`), never by count. Sub-item 3's STAND DOWN also
re-checked and unchanged: the six `cc-mail{send,await,contract,announce,thread,guard}` binaries the
audit named still do not exist, which is decisive on its own.

**Operator-owned tail:** `docs/activation/pending-activation/20-model-config-ssot-activate.sh`
swaps the live `~/.claude/model-config.yaml` real file for a symlink into the checkout. It is C10
(mutates the live layer), fail-closed (refuses unless all 15 routing values already match, and
unless ≥15 keys were actually comparable — so the guard cannot pass vacuously), and backs up the
file it replaces. Until it runs, the repo copy is versioned but the live layer is still a separate
real file.
