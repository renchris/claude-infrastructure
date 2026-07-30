# Security Review: doc_classifier

## Scope

The scan reviewed the canonical include paths and exclusions listed below.

- Scan mode: scoped_path
- Target kind: git_revision
- Target ID: doc_classifier
- Revision: 398ee1b9
- Inventory strategy: scoped_path
- Included paths: reviewapp/api/
- Excluded paths: none
- Runtime or test status: not recorded

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable findings | 1 |
| Severity mix | medium: 1 |
| Confidence mix | high: 1 |
| Coverage | complete |
| Validation mode | not recorded |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

doc_classifier's reviewapp is a FastAPI service with two deployment shapes that share one codebase. The DEPLOYED shape (Azure App Service, Gate-2) authenticates every caller with an Entra bearer JWT validated against the tenant JWKS, with app-role RBAC. The LOCAL shape (`pipeline launch`) serves the review SPA to a single stakeholder on their own machine, where no Entra tenant exists; it therefore opts in to a local principal so the nav is not dead on arrival. The security question for this scan is whether the local-shape affordances are confined to the local shape. The primary attacker is a remote unauthenticated caller who can reach a launcher process that has been bound to a routable address — a mistyped --host, a REVIEWAPP_HOST override, or a container port publish, all three named by the codebase itself. Assets: the operator's filesystem layout, and the integrity of the authentication boundary.

## Findings

| Finding | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- |
| [Unauthenticated filesystem census on GET /api/corpus/scan is gated only by the launcher marker, not by request origin](#finding-1) | medium | high | inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Unauthenticated filesystem census on GET /api/corpus/scan is gated only by the launcher marker, not by request origin

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | Every link was checked rather than assumed: the route's dependency list, the include_router call, and the dependency's implementation. No router-level or app-level guard exists. |
| Category | Missing authentication for critical function |
| CWE | CWE-306, CWE-497 |
| Affected lines | reviewapp/api/routers/corpus.py:64-68, reviewapp/api/routers/corpus.py:83-91, reviewapp/api/deps.py:97-98, reviewapp/api/main.py:93, reviewapp/api/auth.py:112-113 |

#### Summary

`GET /api/corpus/scan?path=<any absolute path>` takes an arbitrary operator filesystem path verbatim and returns a census of it — existence, enumerated file count, admitted-PDF count, total bytes, and a defect-keyed skip histogram. Its only control is a 503 raised when `run_monitor_root` is unwired. That marker proves the process was composed as the local launcher; it does not prove the CALLER is local. Any launcher bound to a routable address therefore exposes arbitrary directory enumeration to unauthenticated remote callers.

#### Root Cause

The launcher-only affordances are guarded by two different, unequal tests. `auth.local_principal` requires BOTH the launcher marker (`app.state.local_principal`) AND that `request.client.host` is in `_LOOPBACK_HOSTS`, and its own docstring calls the host half 'the load-bearing one' precisely because a launcher bound to a routable address must make a remote caller anonymous again. `GET /api/corpus/scan` reaches for the same launcher-only concept but tests only the marker: `get_run_monitor_root` (deps.py:97) reads `app.state.run_monitor_root` via `getattr` and returns it, with no origin check. The route declares no principal dependency, and `main.py:93` includes the router with no `dependencies=`, so nothing supplies one at include time. The result is that the exact scenario auth.py was written to defend leaves this route undefended: the caller does not fall through to a 401, because no authentication is consulted on this path at all.

#### Validation

Every link was checked rather than assumed: the route's dependency list, the include_router call, and the dependency's implementation. No router-level or app-level guard exists. Validation details were not recorded separately.

Validation method: Static trace of the route's declared dependencies, the include_router call site, and the dependency implementation; plus a negative check that no proxy-header middleware exists that could make client.host attacker-controlled.

#### Dataflow

The canonical finding records the affected path at reviewapp/api/routers/corpus.py:64-68, reviewapp/api/routers/corpus.py:83-91, reviewapp/api/deps.py:97-98, reviewapp/api/main.py:93, reviewapp/api/auth.py:112-113, but no expanded source-to-sink narrative was recorded.

#### Reachability

Reachability was not recorded beyond the canonical finding summary and affected locations.

#### Severity

**Medium** — Confirmed by reading: no principal dependency on the route, no `dependencies=` at `main.py:93`, and `get_run_monitor_root` performs no origin test. Disclosure is metadata only — counts, sizes and existence, never file text, so the app's no-text-egress property is not broken. Not high, because reachability requires a non-default bind: `REVIEWAPP_HOST` defaults to 127.0.0.1 at cli.py:116.

Rises to high if the launcher is ever documented, scripted or containerised with a routable bind, or if any future field on CorpusScanView carries file names or text rather than counts.

#### Remediation

Apply the same two-condition test the auth module already implements. Either add a loopback-origin dependency to this route (reusing auth._LOOPBACK_HOSTS so the two cannot drift), or include the corpus router with `dependencies=[Depends(get_principal)]` at main.py:93 so an unauthenticated remote caller receives the ordinary 401 the auth module intends.

Tests:
- With run_monitor_root wired and a simulated non-loopback client host, assert GET /api/corpus/scan returns 401 or 403 rather than a census.
- Assert the loopback case still returns 200, so the legitimate local-launcher affordance is preserved.

Preventive controls:
- Every launcher-only affordance must test the CALLER's origin, not only the process composition marker — one shared dependency, not a per-route re-derivation.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Authentication and authorization (auth.py, route dependencies) | Missing authentication / broken access control | Reported | JWT-vs-JWKS validation, Entra app-role RBAC with unknown roles dropped at validation so a role rename cannot silently grant access, and a local-principal bypass correctly gated on BOTH a launcher marker and a loopback origin, failing closed on an absent origin. That design is sound. The reported finding is a route that reaches for the same launcher-only concept with only half the test. |
| Trustworthiness of request.client.host | Spoofed origin | No issue found | The loopback test is only as good as client.host. No proxy_headers, forwarded_allow_ips, ProxyHeadersMiddleware or X-Forwarded handling exists anywhere in the repository, so client.host is the real transport peer and cannot be set by a request header. |
| SQL construction | SQL injection | No issue found | No f-string, concatenation or .format interpolation reaches an execute/text/raw call in scope. The single f-string hit was a log-prefix builder, not SQL. |
| Deserialization of untrusted input | Unsafe deserialization | Not applicable | No pickle, marshal, yaml.load, eval or exec anywhere in scope. |
| Outbound requests from request handlers | SSRF | Not applicable | No requests, httpx, aiohttp or urlopen call in scope; no attacker-influenced destination exists. |
| CORS and debug configuration | Overly permissive origin policy | Not applicable | No CORSMiddleware, allow_origins, allow_credentials or debug=True in scope. |
| Reflection of caller input in error bodies | Reflected input | No issue found | The corpus 400 deliberately does not echo the supplied path back, and says so in its docstring. Auth failures surface a failure CLASS only, never the token or claims. |

## Open Questions And Follow Up

- Is any documented or scripted launcher invocation binding a routable address? This scan covered reviewapp/api only; REVIEWAPP_HOST is read at reviewapp/cli.py:116 and defaults to loopback, but deployment scripts, container manifests and provisioning/ were out of scope and would settle the finding's real-world reachability.
- pipeline/ (document ingestion) and contracts/ were not scanned — for a system whose input is untrusted documents, the parsing surface is the other high-value target.
