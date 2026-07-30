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

## Findings — all 6, none implemented

| Severity | Where | Backlog | Status |
|---|---|---|---|
| **high** | `reso` `src/app/api/replicache-push/route.ts:30,85` — both CSRF defences default to `report`-only while the prod session cookie is `SameSite=None` | `6bc76053887e` | open |
| medium | `claude-infra` `scripts/limit-recover/lr-reset-poller.sh:391` — `json.dumps`-quoted parked-record fields `eval`'d inside a **loaded launchd job** | `bad94a1a0659` | open |
| medium | `claude-infra` `hooks/validate-bash.sh:94` — catastrophic-command denylist bypassed by equivalent flag spellings | `c3568d7982af` | open |
| medium | `doc_classifier` `reviewapp/api/routers/corpus.py:64` — arbitrary-directory census gated on the launcher marker but not caller origin | `cb9ab22e7b12` | open |
| low | `claude-infra` `scripts/limit-recover/lr-reset-poller.sh:430` — launcher scripts written + `chmod +x` at predictable `/tmp` paths | `7f3b2061dd5d` | open |
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
