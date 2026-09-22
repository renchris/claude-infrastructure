# Which Cloudflare attack classes reach reso — and the three nobody has run there

**Verdict: for reso, `cloudflare/security-audit-skill` is ADDITIVE, not redundant — and the reason
is the inverse of the one you would guess.** Its overlap with our existing coverage is concentrated
in the one class codex-security already scanned (web protocol + auth), while three of the classes it
ships are explicitly OUT of scope for reso's own `security-audit` skill and were never in
codex-security's reso run either. The redundancy risk is real but it lives in a different repo
(see the matched-scope A/B on `claude-infrastructure/hooks/`,
`security-auditor-ab-cloudflare-vs-codex-2026-09-21.md`).

This is an APPLICABILITY MAPPING, not a scan. It reads each class file's own "Core discipline"
against reso's architecture and against what the two existing auditors already cover. Nothing here
is a finding, and no reso code was audited to produce it.

## What already covers reso

| Auditor | Scope on reso | Explicit exclusions |
|---|---|---|
| `security-guidance` (Anthropic, v2.0.8) | the diff being written — hooks on edit / Stop / `git commit` | whole-tree by construction: it never sees code nobody is editing |
| `codex-security` (OpenAI, Apache-2.0) | `e6ead3ce5_20260729T174332Z`, **partial** — 15 `src/app/api/` handlers, `middleware.ts`, `lib/auth/` (16 files) | `src/app/actions/` never covered (backlog `0bfec4faa593`); `/api/replicache-pull` recorded `deferred_replicache_pull` |
| reso `.claude/skills/security-audit` | 8 phases over auth surface, Drizzle injection, secrets archaeology, Replicache push, Soketi, OWASP, STRIDE | **skips A06 (`pnpm audit`) and A08 (CI/CD) BY NAME**; FP-exclusion 7 auto-discards React XSS; FP-exclusion 1 auto-discards DoS except LLM cost amplification |

## The mapping

`reach` is judged from the class file's own Core discipline against reso's stack: Next.js App
Router + React 19 RSC, Turso/SQLite + Drizzle, passkey/WebAuthn sessions with `SameSite=None`,
Replicache push/pull, Soketi/Pusher, per-tenant databases, Amplify Oregon + Fly Path F + Lambda.

| Class file | Reach | Why — and who covers it today |
|---|---|---|
| `WEB-PROTOCOL-AND-AUTH.md` | **high** | Its challenge-binding class ("a successful challenge upgrades the wrong session, account, tenant, action") is almost a restatement of reso plan 002, the passkey upgrade-challenge defect. Also the `SameSite=None` exposure codex filed `high`. **Already well covered** — this is the overlap, not the value. |
| `DATA-ISOLATION-AND-LIFECYCLE.md` | **high** | "A tenant or owner field on a record is not isolation — find the query, key, path, policy or row-level control that enforces it for each read and write path." reso is multi-tenant with venue scoping; plan 016 was a venue-scoping write-gate asymmetry. Partly covered by the reso skill's STRIDE phase, **but its derived-copy clause is not**: Replicache's client IndexedDB, the CVR tables, previews, exports and logs are sanitized-primary-becomes-unsafe surfaces nobody audits as such. |
| `CLOUD-AND-DEPLOYMENT.md` | **high** | "Map each workload's identity to specific operations and resources." reso's deploy identity surface is real — SSM-resolved per-group Turso tokens, the Amplify `start-job` trigger, Path F's `refs/heads/release` filter, `invokeLambdaFunction`. **Covered by nobody**: the reso skill skips A08 outright and codex's run stopped at the request surface. |
| `SUPPLY-CHAIN-AND-RELEASE.md` | **medium-high** | Release/update integrity and CI automation across every handoff. **Covered by nobody** — reso's skill skips A06 and A08 by name. |
| `PROTOCOLS-RPC-AND-MESSAGING.md` | **medium-high** | "'Internal' is not authentication… schema validation proves message shape, not provenance, resource authority, ordering, or safe values." Replicache push is exactly an ordering-sensitive protocol (sequential mutations; `Promise.all` is silent data loss per Critical Rule 3) and Soketi channels carry peer identity. The reso skill covers push auth + rate limit; it does **not** cover ordering-as-a-security-property. |
| `CLIENT-SIDE.md` | **medium** | Mostly discharged by reso's FP-exclusion 7 (React escapes by default) — but that exclusion answers XSS, and this file's sink list includes **shared persistence**, i.e. the Replicache client store. That is a live reso surface, unaudited. |
| `RESOURCE-EXHAUSTION-AND-AVAILABILITY.md` | **medium** | Compatible with reso's own carve-out rather than in conflict with it: it requires impact on "another user, shared service, safety function, or **operator-owned spend**", which is precisely the LLM-cost-amplification exception reso already carves out of its DoS discard. |
| `AI-AND-LLM.md` | **low (reso) / high (claude-infrastructure)** | reso is not an agent product. Its MCP and sub-agent trust classes have **no analogue anywhere in our tooling**, and the fleet they describe is this one — see the A/B doc. |
| `DESKTOP-MOBILE-AND-LOCAL-IPC.md` | **low** | Web app. Deep-link/callback classes graze the web-push/VAPID flow and PWA launch paths; not a priority. |
| `MEMORY-SAFETY-AND-BINARY.md` | **n/a** | No native code in the repo. |

## What this settles, and what it does not

**Settles:** three classes with real reso reach — cloud/deployment identity, supply-chain/release,
and the derived-copy half of data isolation — are covered by *no* auditor pointed at reso today, and
two of them are excluded by name rather than by oversight. A third auditor is therefore not
duplicate capacity on this repo.

**Does not settle:** whether Cloudflare's *hunting* actually finds defects in those classes, as
opposed to shipping a good taxonomy of them. A rubric that saturates has not ranked anything. The
matched-scope A/B on `claude-infrastructure/hooks/` is the instrument for that question, and its
verdict governs; this mapping only says where the two tools would NOT collide.

**Method limit:** read from each class file's Core discipline and from the two auditors' recorded
scopes. reso's code was not re-read for this, so every "covered by nobody" is a claim about the
ledgers, not a claim that the surface is sound.
