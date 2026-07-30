# Security Review: reso-management-app

## Scope

The scan reviewed the canonical include paths and exclusions listed below.

- Scan mode: scoped_path
- Target kind: git_revision
- Target ID: reso-management-app
- Revision: HEAD
- Inventory strategy: scoped_path
- Included paths: src/app/api/, middleware.ts, lib/auth/
- Excluded paths: none
- Runtime or test status: not recorded

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable findings | 1 |
| Severity mix | high: 1 |
| Confidence mix | high: 1 |
| Coverage | partial |
| Validation mode | not recorded |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

reso-management-app is a multi-tenant Next.js App Router application whose clients sync via Replicache against /api/replicache-pull and /api/replicache-push. Authentication is WebAuthn passkeys with an iron-session cookie named `next-webauthn`. That cookie is deliberately SameSite=None in production (lib/auth/session.ts:33) because WebKit bug #255524 breaks the passkey flow otherwise — a documented, accepted trade-off. The consequence is that SameSite contributes NO CSRF protection in production: the cookie rides cross-site requests. Every state-changing endpoint must therefore carry its own CSRF defence. The primary attacker is a web attacker who gets an authenticated user to visit an unrelated page; the asset is the tenant's business data, mutable through the Replicache push channel.

## Findings

| Finding | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- |
| [Both CSRF defences on the state-changing Replicache push endpoint default to report-only, leaving cross-site mutation live in production](#finding-1) | high | high | inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Both CSRF defences on the state-changing Replicache push endpoint default to report-only, leaving cross-site mutation live in production

| Field | Value |
| --- | --- |
| Severity | high |
| Confidence | high |
| Confidence rationale | The defaults, the fall-through branches, the cookie configuration and the absence of any enforce assignment were each read directly. The residual uncertainty is deployment configuration, not code behaviour, and it is recorded as an open question rather than assumed either way. |
| Category | Cross-site request forgery |
| CWE | CWE-352, CWE-1173 |
| Affected lines | src/app/api/replicache-push/route.ts:30, src/app/api/replicache-push/route.ts:85, src/app/api/replicache-push/route.ts:51-58, src/app/api/replicache-push/route.ts:92-111, lib/auth/session.ts:33, src/app/api/passkey-login/route.ts:36-37 |

#### Summary

POST /api/replicache-push applies arbitrary client mutations to tenant data. Its two CSRF controls — a same-origin check and a Content-Type pin — both default to 'report', which logs a mismatch and continues. The production session cookie is SameSite=None, so it is attached to cross-site requests, and a cross-site text/plain POST carrying a JSON body is a CORS simple request that is delivered without a preflight. An authenticated victim who loads an attacker's page can therefore have arbitrary mutations written to their tenant.

#### Root Cause

/api/replicache-push implements the two correct CSRF defences and leaves BOTH disabled by default. `PUSH_ORIGIN_CHECK ?? 'report'` (route.ts:30) and `PUSH_CONTENT_TYPE_CHECK ?? 'report'` (route.ts:85) each default to observe-only: on a mismatch they call logInfo and fall through, and only the 'enforce' value returns 403/415. Nothing in the repository assigns either variable — .env.example:298 carries `# PUSH_ORIGIN_CHECK=report`, commented out, restating the default. The session gate below them (route.ts:115) authenticates the caller but cannot stop CSRF, because in a CSRF the victim IS authenticated and their SameSite=None cookie is attached automatically. The route's own comment at lines 76-79 states the attack precisely: 'Next parses request.json() by body content, ignoring this header, so a cross-site text/plain POST carrying a JSON body is a CORS simple request (no preflight) that rides the SameSite=none cookie.' The Content-Type pin that closes it is named 'the PRIMARY simple-request CSRF defence' in the same comment, and it is the one running in report mode. The sibling endpoint /api/passkey-login enforces its origin check (route.ts:36) for this identical reason, so the codebase is internally inconsistent about which state-changing routes get a live defence.

#### Validation

The defaults, the fall-through branches, the cookie configuration and the absence of any enforce assignment were each read directly. The residual uncertainty is deployment configuration, not code behaviour, and it is recorded as an open question rather than assumed either way. Validation details were not recorded separately.

Validation method: Source trace of both knob defaults and their non-enforce branches, the session cookie configuration, and a repository-wide search for any assignment of either variable in env files, compose, Dockerfiles, IaC, CI or scripts.

#### Dataflow

The canonical finding records the affected path at src/app/api/replicache-push/route.ts:30, src/app/api/replicache-push/route.ts:85, src/app/api/replicache-push/route.ts:51-58, src/app/api/replicache-push/route.ts:92-111, lib/auth/session.ts:33, src/app/api/passkey-login/route.ts:36-37, but no expanded source-to-sink narrative was recorded.

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**High** — Every link was verified in source: the cookie is SameSite=None in production (lib/auth/session.ts:33), both knobs default to 'report' (route.ts:30, 85), the non-enforce branches only logInfo, and no assignment to either variable exists anywhere in the repository. Impact is arbitrary authenticated writes to tenant business data with no victim interaction beyond visiting a page. Not critical: the attacker cannot read the response (CORS still blocks reading), so this is blind write, not disclosure.

Drops to informational the moment either knob is set to 'enforce' in the production environment — which this scan cannot observe from the repository. Rises if mutation handlers accept cross-tenant identifiers, since a blind write would then also cross a tenant boundary.

#### Remediation

Set PUSH_CONTENT_TYPE_CHECK=enforce in production first: the route's own comment records that it has NO false-415 surface, unlike the origin check, so it closes the simple-request path at once and without the sync-isolation risk that is gating the other flip. Then complete the origin-check report window and set PUSH_ORIGIN_CHECK=enforce. Treat 'enforce' as the default in code and 'report' as the opt-out, so a fresh environment is safe rather than open.

Tests:
- Cross-site POST with Content-Type: text/plain and a JSON body, carrying a valid session cookie, must return 415 and apply no mutation.
- Same-origin POST with Content-Type: application/json must still succeed, so the legitimate Replicache client is unaffected.
- Cross-site POST with a mismatched Origin must return 403 once the origin check is enforced.

Preventive controls:
- A security control introduced in report mode needs an explicit expiry — a date or a metric threshold that flips it — otherwise the observation window becomes the permanent state.
- Where SameSite cannot be relied on, make the CSRF defence a shared route wrapper rather than per-route code, so no state-changing endpoint can omit it.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| CSRF on state-changing endpoints | Cross-site request forgery | Reported | The reported finding. /api/passkey-login enforces its origin check for the same stated reason, so the gap is an inconsistency rather than an oversight of the class. |
| Development and load-test authentication bypass routes | Authentication bypass | No issue found | dev-login is triple-gated: NODE_ENV must be development, the caller must be localhost, and the userId must resolve to a seeded row absent from production databases. load-test-login is four-gated, fail-closed on every gate, returns a uniform 404 so the route's existence is not disclosed, uses a length-checked constant-time comparison, and is inert unless LOAD_TEST_SECRET is set to at least 16 characters. Both are sound. |
| Debug endpoint secret exposure | Sensitive data exposure | No issue found | /api/debug/vapid reads VAPID_PRIVATE_KEY but returns only the boolean hasPrivateKey; the only key material returned is a prefix and suffix of the PUBLIC key. Admin-gated with a 403 otherwise. |
| Session authentication on data routes | Missing authentication | No issue found | replicache-push validates the session at route.ts:115 and returns on an absent user. METHODOLOGY NOTE: a grep census for getSession/session.user reported auth=0 for this route because it imports the helper under the alias getServerActionSession — a symbol-name census produces false negatives and must be resolved against the import, not the call site. |
| Session cookie configuration | Insecure cookie attributes | No issue found | httpOnly true, secure in production, SameSite=None in production only. The None value is a documented WebKit #255524 accommodation and is not itself a defect; it is recorded as the precondition that makes per-route CSRF defence mandatory. The separate sameSite:'lax' at cookieActions.ts:209 belongs to the THEME cookie, not the session — checked because the two could easily be conflated. |

## Open Questions And Follow Up

- Does the production environment set PUSH_CONTENT_TYPE_CHECK or PUSH_ORIGIN_CHECK to 'enforce'? The repository sets neither and .env.example documents 'report', but deployment configuration is not visible from source. This single fact decides whether the finding is live or already closed, and it is the first thing to check.
- Server actions (src/app/actions/) were NOT scanned. Next.js server actions are state-changing POST endpoints with the same SameSite=None exposure, and there are more of them than API routes. This is the largest remaining gap.
- Tenant isolation inside the Replicache mutation handlers was not traced — whether a mutation can name another tenant's row. That determines whether the blind write in the reported finding stays inside the victim's tenant.
- /api/replicache-pull carries no origin or content-type check at all. It is a read path and CORS prevents an attacker reading the response, so it is not the same class of exposure, but its tenant-scoping was not traced in this scan.
  - Follow-up prompt: Review deferred unit deferred_replicache_pull and close its stated proof gap. Paths: src/app/api/replicache-pull/route.ts.
