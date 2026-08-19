# Codex Security scan ledger

**Read this BEFORE running a codex-security scan on any repo below.** It records what surface was
already covered at which commit, so a routine re-run scans the *remainder* instead of re-deriving
findings that are already filed. The sibling directories hold the sealed bundles those scans
produced — `scan-manifest.json`, `findings.json`, `coverage.json`, the generated `report.md`, and
SARIF 2.1.0.

Methodology + why the port exists: [`../codex-security-in-claude-code-2026-07-29.md`](../codex-security-in-claude-code-2026-07-29.md).
How to run one: the `codex-security` skill (`skills/codex-security/SKILL.md`).

**Why these bundles are committed.** They were produced into `$TMPDIR/codex-security-scans/…`, which
is swept. Losing them costs the whole scan — the coverage ledger, the severity reasoning, and the
seal that proves the bundle passed OpenAI's own validator. A future scan can diff its
`coverage.json` against the one here to see what genuinely changed.

---

## Coverage by repo

### claude-infrastructure

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `dc12c8db_20260729T053818Z` | `dc12c8db` | `hooks/` (69 files, 10,459 lines) | **complete** | 2 |
| `38eec335_20260729T1750Z` | `38eec335` | `bin/`, `scripts/` | **partial** | 2 |

**Covered:** `hooks/` exhaustively (every file accounted for, 7 surfaces dispositioned).
`bin/` + `scripts/` partially — see its three `deferred` entries.

**NOT covered — the remaining surface for a next run:**
`commands/`, `lib/`, `tests/`, `launchd/`, and the three deferrals recorded in the bin/scripts
bundle (`deferred_lr_handoff_branch_name`, `deferred_line_by_line_review`,
`deferred_esc_scan_binary_diff`).

**`openQuestions[0]` (lr-reset-poller plist vs deployed AUTOFIRE) — RESOLVED 2026-07-30, and the
resolution is a methodology note worth more than the finding.** The question asked which side was
authoritative between the committed plist (`Auto-resume is OFF by default`, block commented out) and
the deployed LaunchAgent (`LR_POLLER_AUTOFIRE=1`). Answer: **live is authoritative and the template
already matched it** — `4b0efff2` reconciled the plist on 2026-07-25, four days before the scan.
The scan revision `38eec335` forked BEFORE that commit, so it observed a snapshot where the drift was
still real. **A scan pinned to a revision reports that revision's truth, not trunk's — date every
finding against the fix that may already have landed on another branch, or you rebuild a closed fix.**

The residue it surfaced WAS real, and is what the follow-up actually fixed: reconciling the plist had
not reconciled the *subsystem*. Four sibling surfaces still told the pre-activation story 12 days
after the flip — `lr-reset-poller.sh`'s own header ("OFF by default … set it ONLY after eyeballing a
live cycle"), `limit-reset-safety-gate.sh` (asserting "activation C10-queued: plist NOT in
~/Library/LaunchAgents" on every run), `wiring-all.sh` ① (presenting the completed flip as a pending
hand-step), and the poller's own dry-run notification (advising the operator to set a variable already
set to 1). The plist's recorded activation date was also wrong — `2026-07-21` with no supporting
evidence, versus a LaunchAgent mtime of `2026-07-18T17:00:15-0700` and a `RESUMED … (autofire)` log
line 10 s later. **`launchd-parity-lint.sh` guarded the one file it knew about and was structurally
blind to prose in siblings; `LR-v` in `tests/lr-reset-poller.bats` now pins the plist↔header pair.**

### doc_classifier

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `398ee1b9_20260729T164452Z` | `398ee1b9` | `reviewapp/api/` (34 files, 8,090 lines) | **complete** | 1 |

**Covered:** the FastAPI network surface — authn/authz, SQL construction, deserialization, SSRF,
CORS, reflected input. The auth design was reviewed and found sound (JWKS validation, Entra RBAC
with unknown roles dropped, a local-principal bypass correctly gated on *both* a launcher marker
and a loopback origin).

**NOT covered — and this is the highest-value gap in any of the three repos:**
`pipeline/` (document ingestion) and `contracts/`. For a system whose input is untrusted documents,
the parsing surface is the primary attack surface and it has never been scanned. → `769c22b99fec`

### reso-management-app

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `e6ead3ce5_20260729T174332Z` | `HEAD` @ 2026-07-29 | `src/app/api/`, `middleware.ts`, `lib/auth/` (16 files) | **partial** | 1 (**high**) |

**Covered:** all 15 API route handlers, the middleware, and the session/auth lib. The dev and
load-test login bypass routes were reviewed and found sound (`dev-login` triple-gated;
`load-test-login` four-gated, uniform 404s, constant-time compare, inert without a ≥16-char
secret). `debug/vapid` returns only a boolean for the private key.

**NOT covered:**
- `src/app/actions/` — Next.js **server actions**. These are state-changing POST endpoints carrying
  the *same* `SameSite=None` exposure as the reported finding, and there are more of them than API
  routes. Largest remaining gap in this repo. → `0bfec4faa593`
- `/api/replicache-pull` — recorded as `deferred_replicache_pull`; read path, so CORS blocks
  reading the response, but its tenant-scoping was never traced.

---

## Findings — 6 total: 3 landed, 1 fixed-but-parked, 2 open

**Status re-verified 2026-07-30 by CONTENT on each repo's `origin/main`, not from the backlog's
`done` records** — and the two disagree. `cb9ab22e7b12` reads `done` in `backlog.jsonl`, but its fix
sits on an unlanded branch, so the vulnerable code is still what `origin/main` serves. A `done`
record proves a commit was made; only `git ls-tree`/`show` against the trunk proves it shipped.

| Severity | Where | Backlog | Status |
|---|---|---|---|
| **high** | `reso` `src/app/api/replicache-push/route.ts:30,85` — both CSRF defences default to `report`-only while the prod session cookie is `SameSite=None` | `6bc76053887e` | **landed** `cfbddc09b` |
| medium | `claude-infra` `scripts/limit-recover/lr-reset-poller.sh:391` — `json.dumps`-quoted parked-record fields `eval`'d inside a **loaded launchd job** | `bad94a1a0659` | **landed** `29431edd` |
| medium | `claude-infra` `hooks/validate-bash.sh:94` — catastrophic-command denylist bypassed by equivalent flag spellings | `c3568d7982af` | **landed** `27753483` |
| medium | `doc_classifier` `reviewapp/api/routers/corpus.py:64` — arbitrary-directory census gated on the launcher marker but not caller origin | `cb9ab22e7b12` | ⚠️ **fixed but PARKED** — `0e9215b3` is on branch `wt-cb9ab22e7b12` only; `origin/main`'s `corpus.py` still has no loopback check |
| low | `claude-infra` `scripts/limit-recover/lr-reset-poller.sh:430` — launcher scripts written + `chmod +x` at predictable `/tmp` paths | `7f3b2061dd5d` | open (claimed) |
| low | `claude-infra` `hooks/notify.sh:35,39` — fixed predictable paths in world-writable `/tmp`, append at `:88` follows a symlink | `170ee7570b1a` | open |

**Every finding carries its remediation and remediation-tests inside its bundle's `findings.json`
— read that before re-deriving a fix.** Severities were deliberately calibrated *down* where a
sibling control already mitigates; the reasoning is in each finding's `severity.rationale`.

## The pattern across all four scans

Five of six findings are **internal inconsistencies, not unknown risks** — the codebase had already
identified the attack class and defended it correctly *somewhere else*:

- `auth.py`'s loopback check exists; `/api/corpus/scan` omits it.
- `passkey-login` enforces its origin check; `replicache-push` reports only.
- The rm-deny regex anchors its `~` branch on `$`; its `/` branch does not.

That is what a whole-tree audit finds and a diff reviewer structurally cannot: the defect is in code
nobody is currently editing. Worth pointing the next scan at *asymmetries between sibling
controls*, which is where the signal has been concentrated.

## Process lessons for the next run

1. **File every finding to `cc-backlog` as it is validated, not at the end.** `hooks/notify.sh:35`
   sat unfiled for a day because it was reported in prose and never queued.
2. **A 1-second `claim`→`done` in `backlog.jsonl` is not proof of a skipped scan.** It read as a
   false-done and a duplicate re-scan item was filed; the bundle existed all along. Check for the
   bundle before re-filing.
3. **`$TMPDIR` is not storage.** Copy the bundle into this directory as the last step of any scan.
4. Pass `realpath` output as `--scan-dir` — the finalizer rejects a non-canonical path, and
   `$TMPDIR` on macOS resolves under the `/var` symlink.
5. **A `done` in the backlog is not a landing.** Fold this table's Status column from the trunk
   (`git ls-tree origin/main`, or grep the fixed construct out of `git show origin/main:<file>`),
   never from the ledger record. One of the four `done` rows above was a commit stranded on an
   unlanded branch — read as fixed, still exploitable on `main`.

---

## Path B (upstream Codex CLI) — one scan, and it contradicts a "found sound" above

Added 2026-07-29T23:00Z. Background, measured cost, and the three-repo runbook:
[`../codex-security-three-repos-2026-07-29.md`](../codex-security-three-repos-2026-07-29.md).
`npx @openai/codex-security@0.1.4` **is** runnable here (Codex CLI + ChatGPT login, no API key) —
the prior doc's claim that it was not is corrected there.

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `doc_classifier/pathB-c1ae7ce8_20260729T2300Z` | `c1ae7ce8` | `reviewapp/api/auth.py` | **complete** | 3 (1 medium, 2 low) |

⚠️ **This scope is a strict subset of `398ee1b9`'s "complete" `reviewapp/api/` scan above, and it
returned 3 findings on the two controls that scan named as sound.** Do not read the rows as
duplicates:

| `398ee1b9` recorded | `pathB-c1ae7ce8` found | Backlog |
|---|---|---|
| "JWKS validation" sound | **medium** — fresh `PyJWKClient` per token ⇒ pre-auth JWKS fetch amplification; **PoC observed 4 fetches from 2 rejected tokens** | `ce7651b02a17` |
| local-principal bypass "correctly gated on … a loopback origin" | **low** — DNS rebinding inherits the launcher's all-role principal; the loopback *peer* check carries no Host/Origin binding | `a36f2a81e3ee` |
| — (new surface) | **low** — UPN local-part mapping merges distinct reviewer identities | filed with the two above |

**Status of the medium row, 2026-08-19 — still open on trunk, and blocked on venue, not on the fix.**
`ce7651b02a17` was re-verified against doc_classifier `origin/main` @ `cc6a30a6` on 2026-08-09
(`../../plans/backlog-consolidation-2026-08-09/OUT-docclf.md:49`: the per-token `PyJWKClient` is live
at `auth.py:73`), and `origin/main` has not moved since 2026-07-30. It has now burned cloud sessions
that cannot reach `doc_classifier` at all, and it is member 3 of ordered cluster **M-P-2** — do not
work it standalone. Disposition and the operator's `cc-backlog block` line:
`../venue-foreign-repo-recurrence-2026-08-17.md` § SEVENTH DISPATCH. Lesson 5 above applies to its
eventual fix as much as to `cb9ab22e7b12`'s.

Neither engine is wrong about the code; they asked different questions. The amplification defect is
about a *client lifecycle*, and rebinding defeats a peer-address check precisely because the victim's
browser really does connect from `127.0.0.1`. **Lesson for this ledger: `completeness: complete`
means every file was visited, not that every class was considered — a later scan may legitimately
re-target a scope already marked complete, and should say so rather than skip it.**

Path B costs **~$14.22 / ~998s / 17.2M input tokens for that one 170-line file**, and OpenAI's cyber
classifier **refuses** `claude-infrastructure/hooks/validate-bash.sh` outright, so Path A stays the
default and is the *only* path for this repo. Before the refusal, Path B did emit 10 candidates
against that hook — the known `-rf` gap plus **6 of one unmodelled family: shell token concatenation
defeats raw-text matchers** (`drizzle-kit pu''sh` executes as `push`). Those are unvalidated leads;
running them down on Path A is free.
