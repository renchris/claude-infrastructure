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

### reso-landing-app

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `d3ebdcee_20261016T160016Z` | `d3ebdcee` (branch `deps-upgrade-2026-10`, Next 16.4.1; **not** production `main`) | whole repo, 107 tracked files | **complete** | 0 |

First codex scan of this repo (P1 full enumeration), run as lens H of `/exhaust-improvements
--plan-only` (reso-management-app `1fcd7827e`), prompt-only and single-agent (no fan-out; recorded in
`scan-manifest.json` `scope.context`). Sealed 2026-10-16T16:15:46Z, 15 artifacts hashed.

**Covered:** all 31 `src/` files read in full; 24 SVGs parsed by element; 13 build/config files;
`pnpm-lock.yaml` structurally (224 entries, all sha512, registry-only). 8 candidates, all rejected at
the policy pass (pricing `?tier`, the dead `/login` form, headers/CSP, Fontshare CSS without SRI,
`target=_blank`, the branch's image optimizer, raster metadata, the Amplify build pipeline).
**As lens G's confirmer** it reproduced Cloudflare's one lead locally (in-process harness, network
guard, 0 connection attempts): `/_next/image` keys its cache on the URL `#fragment`, so anonymous GETs
force a fresh sharp transform each time (~380 ms CPU vs 3.6 ms on a hit); rated **low**. Fix:
`images: { unoptimized: true }`, the same change as decision `58f292806fd7`. Report:
`/tmp/sibling-deps-2026-10-16/exhaust/reso-landing-app/h-validate/VALIDATION.md` (swept; its verdict is
in the repo's `docs/plans/EXHAUST_IMPROVEMENTS_2026-10-16.md` as LND-01).

**P2 — these surfaces rest on a NEGATIVE search and suppress nothing next run:**
`api-routes-middleware-server-actions`, `auth-session-csrf`, `server-side-io`,
`browser-storage-and-third-party-scripts` (all `not_applicable`), plus `redirect-and-navigation-sinks`
and `secrets-tree-and-history` (`no_issue_found`, search-derived).

**NOT covered:** advisories for next 16.4.1 / react 19.3.1 / sharp 0.35.5 published after June 2026 (no
network); Amplify console state for app `d3ce74t8uneoh0` (custom headers, WAF, body logging, build
cache); raster images beyond metadata; production `main` (Next 14.2.11), which is a different tree.

### reso-web-app

| Scan | Revision | Scope | Completeness | Findings |
|---|---|---|---|---|
| `f0f3b89_20261016T155948Z` | `f0f3b89` (`main`, Next 15.5.28) | whole repo, 600 tracked files | **complete** | 4 (all **low**) |

First codex scan of this repo (P1), lens H of the same `/exhaust-improvements --plan-only` pass,
single-agent; sealed 2026-10-16T16:20:18Z (re-sealed once to correct a count in `validationMode`).
Validation harness: a copy of `src/` with the AWS SDK mocked and the endpoint at `127.0.0.1:9`, 10/10;
nothing contacted, nothing written.

**Findings, by class only (all open at the time of writing):** two unauthenticated write endpoints
accept a client-chosen partition key with no overwrite condition, one accepts staff-owned fields from
the public, and the API rate limiter keys on a client-writable header. Detail, line numbers and the
proof-of-concept live in the private repo's backlog (`docs/plans/EXHAUST_IMPROVEMENTS_2026-10-16.md`,
WEB-01/02/04/07). **The sealed bundle is NOT committed here**, unlike the other rows: this repo is public
and the findings are unfixed on a live site, so it sits in the private store at
`$CC_PRIVATE_DIR/docs/research/codex-security-scans/reso-web-app/f0f3b89_20261016T155948Z/`.

**As lens G's confirmer** it re-checked Cloudflare's 8 leads: 7 reproduced, 1 confirmed statically (a
credential committed in the private repo's old history; the scan itself missed it because it reads
the tree, not history — WEB-13 in that backlog). **Process lesson:** a tree-only secret search marked
`surface_secrets_in_tree` clean while the history held a key; give the next scan a history sweep.

**P2 — resting on a NEGATIVE search, suppress nothing next run:** `surface_server_injection_classes`,
`surface_csrf_session` (`not_applicable`); `surface_html_pages_client` (most of 53 component files were
searched, not read), `surface_public_static_assets`, `surface_dev_scripts`, `surface_tests`,
`surface_secrets_in_tree` (tree only — **history was not scanned, which is exactly where the key was**),
and the missing-framing-headers sub-claim.

**NOT covered:** yarn.lock advisory matching (dep-audit's lens); sibling consumers of the guestlist table
(GuestlistProcessor, GuestlistProcessor-Python, sevenrooms-bridge, the door app); production facts
(legacy ids, the real XFF chain, whether `scripts/cloudfront/normalise-accept.js` is deployed); 112
`docs/**/*.md` regex-scanned only; 264 binaries and 6 `.gz` baselines; branch `next16`.

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

---

# Cloudflare `security-audit-skill` scan ledger

**A separate producer, a separate ledger — these rows do NOT inherit from the codex-security rows
above and the codex rows do not inherit from these.** Tool identity, version and attack-class roster
together are the options-hash; move any of them and every coverage record the other producer wrote is
stale for this one. That is rule **P3** in reso's `.claude/commands/exhaust-improvements.md`. Rule
**P2** binds too: a `no_issue_found` or `not_applicable` record derived from a *negative search* may
not suppress a unit here — so codex's four `no_issue_found` surfaces on reso
(`surface_dev_bypass_routes`, `surface_debug_secret_exposure`, `surface_route_authn`,
`surface_cookie_config`) suppress nothing below.

Tool: `cloudflare/security-audit-skill` @ `c1c8a8c` (MIT), cloned at
`~/Development/.tools/cf-security-audit-skill`, not installed into any `skills/` directory.
Artifacts live OUTSIDE the target, at `~/security-audit-skill/<repo>/run-<N>/`, as the skill requires.

## Coverage by repo

### reso-management-app

| Scan | Revision | Scope | Profile | Enumeration | Confirmed | Needs validation |
|---|---|---|---|---|---|---|
| `reso-src-app-actions/run-1` | `f87d878d0` | `src/app/actions/` (112 files: 41 source / 18,481 lines + 71 test / 18,061 lines) | `standard` | **complete for the scope · partial for the repository** | **6** (2 high, 4 medium) | **20** |

**`enumeration_complete[cloudflare, reso]` was `false` before this run** — lens G had never run on
this repo, so by rule **P1** this was a full first enumeration of its scope, and absence may only be
counted inside it.

**Covered.** 69 ledger units, all terminal: 37 `candidate`, 13 `covered`, 17 `out_of_scope`, 1
`deferred`, 1 `blocked`. All **41 of 41** in-scope source files were opened (cross-checked
independently of the critics by intersecting the ledger's `starting_paths` / `reviewed_paths` against
`find src/app/actions -type f`). Both independent coverage critics returned `stop: true` with no
missing units and no reassignments. All 34 candidates carry a verifier verdict — 6 confirmed, 20
needs_validation, 8 rejected — so nothing is unvalidated and `validation_budget_exhausted` does not
apply. Both skill validators PASS: `validate-findings.cjs` → *34 findings valid*;
`validate-coverage-ledger.cjs` → *69 coverage units valid*. 29 agents spent against a budget of 45.

**NOT covered — the remainder, by unit.** 17 out-of-scope surfaces discovered during the run and
recorded as `out_of_scope` rather than `covered`, so a later whole-repo pass turns them into current
work: `amplify.yml#build pipeline` · `drizzle/db.ts#getDBAndGroupForSessionTenant` ·
`drizzle/db.ts#getNamedDB` · `drizzle/rp.ts#getRelayingPartySettings` ·
`lib/auth/**#module 'use server' exports` · `lib/auth/credential-change-notifier.ts#notifyCredentialAdded` ·
`lib/auth/session.ts#getValidatedSessionCached` · `lib/auth/venue-authz.ts#getScopingFlag` ·
`lib/messaging/guest-message-outbox.ts#enqueue and drain` · `lib/venue-resolution.ts#getInitialVenues` ·
`src/app/(app)/**#SSR seed consumers of resolveActiveVenueRow` ·
`src/app/(app)/admin/(settings)/deviceActions.ts#module exports` ·
`src/app/(guest)/t/[claimToken]/_actions#guest claim surface` ·
`src/app/api/notifications/subscribe/route.ts#POST` · `src/app/api/replicache-push/route.ts#POST` (×2) ·
`src/middleware.ts#request middleware`. Plus **1 deferred** unit
(`operationalHistoryActions.ts#getOperatorShiftDetail` × `lib/operational-detail.ts#formatOperationalDetail`,
reason `late_uncovered_no_remaining_wave`) and **1 blocked** unit
(`replicache/pullActions.ts#pull entrypoint` × `DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or
owner enforcement`). The 71 test files were discharged by **sweep**, not per-file citation (34 cited
individually). **Coverage is per UNIT — a surface × boundary × class tuple — not per file: a file
opened under one attack class was not thereby examined under all of them.**

**Execution policy — read this before trusting any "no issue" here.** The run executed **no target
code at all**. Measured on the audit host, not assumed: nested `sandbox-exec` is refused
(`Operation not permitted`), the Docker daemon is down, there is no podman/lima/colima/bwrap/firejail/
nsjail, the checkout is not read-only mounted, and macOS cannot enforce a memory ceiling
(`ulimit -v` → `setrlimit failed: invalid argument`). Independently the target worktree has no
`node_modules/`. So every ledger check is `method: "source"` with `artifact: null`, and anything whose
decisive fact needed execution is `needs_validation` carrying that blocker rather than a verdict —
19 of the 20 leads carry it, alongside a deployment-, data-state- or third-party fact.
**A later run on a host with a real sandbox can claim something this one structurally cannot.**

**No finding overturns reso's own by-design list.** Four sit adjacent to one (two at the boundary of
Decision 4's share-graph exemption, one at FP-exclusion 5's host-control carve-out, one clearing
FP-exclusion 1 through its stated operator-owned-spend exception) and each carries the distinguishing
evidence in its record rather than an assertion.

Full report: `~/security-audit-skill/reso-src-app-actions/run-1/REPORT.md`.
Write-up: [`../cf-audit-reso-actions-2026-09-22.md`](../cf-audit-reso-actions-2026-09-22.md).

#### The uncovered remainder, enumerated — W5, 2026-09-22

**The 19 uncovered units above are now enumerated per unit and ranked, and the enumeration found
three things this ledger did not say.** Not an audit of them: a record of *absence of coverage*,
read against reso `origin/main` (`d10b8c1cc`, 6 commits ahead of the audit sha `f87d878d0`, and
**no file named by any of the 19 changed between them** — only three bottle-catalog files did, so
every line cited is true at both). Full document:
[`../cf-audit-reso-uncovered-surfaces-2026-09-22.md`](../cf-audit-reso-uncovered-surfaces-2026-09-22.md).

**C1 — 17 of the 19 were never opened.** Every `out_of_scope` unit carries `reviewed_paths: []`, so
its `reason` is the parent's pre-hunt hypothesis rather than a reading. Only the **blocked** unit has
a reviewed set (9 files); the **deferred** one was read by a sibling unit under a different class.
Demonstrated rather than asserted: unit `amplify.yml#build pipeline`'s reason cites *"amplify.yml:32
curls a jq binary over the network"* — at the **audit sha itself** the curl is at `:35`, is
SHA256-pinned per architecture with `sha256sum -c -` gating the `chmod +x`, and line `:32` is part of
the comment that says so. **Read every `reason` on those 17 as a lead to check, never as a finding to
inherit.** The surfaces remain uncovered regardless.

**C2 — one path in the set does not exist.** `src/middleware.ts` is not a file; it is `middleware.ts`
at the repository root. It does CSP-nonce + `x-pathname` work only — no authentication, no tenant
resolution, **no Host or `x-forwarded-host` validation** — and its matcher excludes `api`, so every
API surface in the set runs with no middleware at all. A later pass handed the recorded class *Host
and forwarded-header trust* at that path finds nothing and is at risk of recording a false
`not_applicable`; the class is live in `domainActions.getSubdomain`, `drizzle/db.ts`, `drizzle/rp.ts`
and `pokeTenantFromHost` instead. Separately: **neither of this ledger's two
`parent_boundary_correction`s falls inside the 19** — both sit on units that reached a verdict — but
the corrected push limiter (`lib/rate-limit/durable-limiter.ts:237`) does govern unit
`replicache-push/route.ts#POST`, so it is carried. **One boundary inside the 19 is wrong and W5
corrects it:** `guest-message-outbox.ts#enqueue and drain` is recorded against
`guest-message-consent-gate.ts#consent gate`, and the consent gate governs **enqueue only** —
`drainGuestMessages` performs no send-time consent re-read (the only consent calls in the file are at
`:371-389`), its sole per-row gate before `send` being `staleAfter` (`:582`, default 1 h). Read that
unit as `guest-message-outbox.ts#staleAfter`.

**C3 — the uncovered SET is incomplete: three network-reachable surfaces carry no unit at all.** A
repo-wide census of modules whose first line is `'use server'` returns **35** (18 in
`src/app/actions/`, matching the run's own endpoint count; 17 outside, of which 15 appear in the 19).
Missing: **`src/app/api/replicache-pull/route.ts#POST`** — the push route got *two* units, the pull
route *none*, while unit 18's own text says *"the sibling pull route likely shares it"*, and codex
recorded it `deferred_replicache_pull` in July, which under P3 transfers nothing; plus
**`drizzle/migrate.ts`** (0 mentions) and **`drizzle/initializeDatabase.ts`** (surface of 0). The
pull route also carries **0** `checkSameOrigin`/`requireJsonContentType` call sites against the push
route's **4**, with the session cookie `SameSite=none` in production.

**Ranking.** The 19 are ranked by downstream relevance to the 6 confirmed findings and 20 leads, not
by recorded status — two `out_of_scope` units outrank the `blocked` one. Top five:
`guest-message-outbox.ts#enqueue and drain` (the store **confirmed #4**'s erasure gap persists in) ·
`lib/auth/**#module 'use server' exports` · `drizzle/db.ts#getNamedDB` ·
`drizzle/db.ts#getDBAndGroupForSessionTenant` · `replicache-push/route.ts#POST` × header tenant and
venue selection (the entry point above **leads 9, 12, 13, 17**). Lowest:
`admin/(settings)/deviceActions.ts#module exports` — one session-gated export with the ownership
predicate inside the UPDATE, **which is a scope statement and not a clean verdict** (P2).

**Seven CANDIDATES, none a finding.** This pass executed no target code either, so nothing below is
verified and nothing in the 19 is called clean. Three match the *unauthenticated / privileged-export*
shape and were escalated to the programme lead as they were found: `lib/auth/guest-session.ts:107`
`setGuestSession` — a `'use server'` export minting a guest session from two caller-supplied
arguments, whose docblock *"called ONLY after a claim token has been verified"* governs its internal
callers and is silent on the caller a `'use server'` export has by construction;
`drizzle/db.ts:215` `getNamedDB` / `:267` `getDBAndGroupForSessionTenant`, where the second's stated
control is *"the parameter is the session tenant OBJECT, never a string, so passing a HOST-DERIVED
tenant is a compile error"* (`:260-263`) — **a compile-time type on a runtime POST endpoint**, which
is this run's own structural fact #1; and `drizzle/migrate.ts:7` `migrateDB`, an ungated migration
runner against a caller-named database sitting in zero units. **`eslint-rules/no-ungated-db-export.mjs`
is structurally blind to all three**: it fires only on a DB-ACCESS signal, and a cookie write, a
returned handle and a `migrate()` call each evade it.

**The decisive fact is a build, and the programme lead owns it** (ruling 2026-09-22): whether Next
registers these exports is readable from `.next/server/server-reference-manifest.json`, which needs a
`pnpm build` that would contend with the wave-1 land queue. W5 ran no build and entered no reso
repo. The document carries a § Manifest lookup keys hand-off — export name, `file:line`, and the one
question each answers — with the two-step recipe (**the manifest keys actions by hashed id, not by
export name**, so grepping the name proves nothing) and a **positive control**, `updateTenantConfig`,
a known-live action by virtue of confirmed #5: if the recipe cannot find *it*, every negative is an
instrument artifact rather than a fact.

**`enumeration_complete[cloudflare, reso]` is unchanged by this row.** Enumerating uncovered units is
not auditing them, and nothing here may be counted as absence of a defect.

### reso-landing-app

| Scan | Revision | Scope | Profile | Enumeration | Confirmed | Needs validation |
|---|---|---|---|---|---|---|
| `reso-landing-app/run-1` | `d3ebdcee` (branch `deps-upgrade-2026-10`) | whole repo | `quick` | **complete** (first run, P1) | 0 | 1 |

`enumeration_complete[cloudflare, reso-landing-app]` is now **true** at `d3ebdcee`. 22 ledger units: 16
`covered`, 1 `candidate` (the lead), 3 `blocked`, 2 `deferred`; 3 hunters and 1 verifier, 6 companion
files. Both validators PASS (`1 findings valid`, `22 coverage units valid`). No target code ran (no
OS-enforced sandbox). The run's phase-6 markdown was refused to the workflow's subagents and rendered
afterwards from the final JSON; `run-metadata.json` records it as `phase6_rendered_by`.

**The one lead is the codex-reproduced `/_next/image` fragment cache-key miss** (codex row above). It
stays `needs_validation` in this run's own records: codex's harness is not the OS sandbox this skill
requires, so the verdict was not promoted. **Blocked/deferred units** wait on facts outside source:
how Amplify WEB_COMPUTE serves `/_next/image` (minimal mode or not), its CloudFront query-string policy
and WAF, console custom headers, request-body logging for the dead `/login` POST, and build-cache
scoping for previews. Artifacts: `~/security-audit-skill/reso-landing-app/run-1/` (outside every repo).

### reso-web-app

| Scan | Revision | Scope | Profile | Enumeration | Confirmed | Needs validation |
|---|---|---|---|---|---|---|
| `reso-web-app/run-1` | `f0f3b89` (`main`) | whole repo | `standard` | **partial** (first run, P1; `coverage_complete: false`) | 0 | 8 |

43 ledger units: 18 `covered`, 17 `candidate`, 3 `deferred`, 1 `blocked`, 4 `out_of_scope`; 7 hunters
over two waves plus a post-wave and a final critic; 17 candidates folded to 15 records (0 confirmed, 8
needs_validation, 7 rejected). Both validators PASS (`15 findings valid`, `43 coverage units valid`). No
target code ran. Codex then reproduced 7 of the 8 leads and confirmed the eighth statically (codex row
above), and two of Cloudflare's 7 rejections were overruled by the repo's other lenses (the guestlist
field-allowlist gap, backlog WEB-01). **`enumeration_complete[cloudflare, reso-web-app]` stays false.**

**NOT covered — the next run's work:** 3 units deferred at the wave-2 stop (`early_stop_after_wave_2`):
the paid downstream work an anonymous guestlist row triggers (email/SNS stream fan-out), value injection
into the `/api/agent-content` `Link` header from the raw `?path=`, and the distinct `422
email_reservation_cap` as an email-enumeration oracle; 1 blocked unit: the live IAM policy of the Amplify
SSR compute role , readable only by the operator. Artifacts:
`~/security-audit-skill/reso-web-app/run-1/` (outside every repo).
