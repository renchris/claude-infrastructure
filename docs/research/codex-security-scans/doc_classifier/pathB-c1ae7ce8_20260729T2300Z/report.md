# Security Review: doc_classifier

## Scope

Exhaustive standard scoped-path review of the configured authentication and RBAC module. Every requested file was reviewed from start to finish; nearby callers, identity/state stores, launcher composition, deployment assumptions, dependency implementation, and focused tests were used as supporting evidence.

- Scan mode: scoped_path
- Target kind: git_worktree
- Target ID: target_sha256_f45f2ca5c4014aa5923f5c946b3d72a913b83a084f2aa7edd6fb8f0846c749d0
- Revision: c1ae7ce85b65f0a0ce0cd08d4a931f98c6211798
- Snapshot digest: codex-security-snapshot/v1:sha256:75fbb470ba9a92d6c31ed0d10c0a9c5726b6f4305b405a9c9d1de9f9aa56d65c
- Inventory strategy: scoped_path
- Included paths: reviewapp/api/auth.py
- Excluded paths: none
- Runtime or test status: Focused auth and launcher test suites passed 24 tests. A targeted PoC against the actual `_decode` implementation observed four JWKS fetches from two attacker-shaped token attempts.
- Artifacts reviewed: reviewapp/api/auth.py, reviewapp/api/settings.py, reviewapp/cli.py, contracts/base.py, reviewapp/api/decisions.py, reviewapp/api/db.py, tests/reviewapp/test_auth.py, tests/reviewapp/test_launcher.py, PyJWT 2.13 PyJWKClient implementation
- Scan context: The repository-scoped threat model was generated during Phase 1. Applicable SECURITY.md guidance was resolved and was empty.

Limitations and exclusions:
- No live production gateway, Entra tenant account inventory, or browser DNS-rebinding environment was available.
- Browser Private Network Access behavior and production request throttling remain deployment-dependent.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable DSS findings | 3 |
| Report instances | 3 |
| Report severity mix | medium: 1, low: 2 |
| Report confidence mix | high: 2, medium: 1 |
| Coverage | complete |
| Validation mode | Compact standard-scan validation using targeted PoC, focused tests, and static source/control/sink tracing. |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

The ReviewApp is a privileged human-decision surface for confidential contract processing. Deployed requests cross an Entra JWT and role boundary, while the local launcher deliberately grants an all-role principal only to loopback peers. Identity attribution, reviewer separation, decision integrity, confidentiality, and bounded pre-authentication resource use are key objectives.

### Assets

- Confidential contract evidence and review artifacts
- Reviewer, adjudicator, auditor, and admin authority
- Append-only decisions, blind-entry state, second-key witnesses, and queue assignments
- ReviewApp and identity-provider availability

### Trust Boundaries

- Unauthenticated API caller to Entra bearer-token validation
- Remote browser origin to the tokenless local launcher
- Signed Entra identity to per-reviewer workflow state
- ReviewApp process to the configured JWKS endpoint

### Attacker Capabilities

- Send arbitrary bearer-token bytes and JWT header values to a reachable authentication boundary
- Operate a web origin and influence DNS answers viewed by a victim browser
- Use a valid role-bearing Entra account provisioned in the accepted tenant
- Trigger repeated requests within the limits of surrounding network controls

### Security Objectives

- Reject invalid tokens without attacker-amplified identity-provider work
- Never grant the launcher principal to a remote web origin
- Keep distinct Entra principals distinct in all authorization and workflow-state keys
- Preserve least privilege, decision attribution, and service availability

### Assumptions

- The deployed ReviewApp is private but remains exposed to enclave clients and configuration drift.
- The launcher binds to loopback by default and opens a local browser.
- The Entra deployment is single-tenant, but local parts are not proven unique across verified UPN domains.
- Production gateway throttling and browser private-network defenses were not available as repository-enforced controls.

## Findings

| Findings | Reports | Severity | Confidence | Detailed write-up |
| --- | --- | --- | --- | --- |
| Fresh JWKS client per token enables pre-authentication fetch amplification | [occ_e734b99678915e5e44795ff8](#finding-1) | medium | high | occ_e734b99678915e5e44795ff8: inline below |
| UPN local-part mapping merges distinct reviewer identities | [occ_4c8ab7a720c6a8ae1b2de1fc](#finding-2) | low | high | occ_4c8ab7a720c6a8ae1b2de1fc: inline below |
| DNS rebinding can inherit the local launcher's all-role principal | [occ_7ad23d253e3074207f545354](#finding-3) | low | medium | occ_7ad23d253e3074207f545354: inline below |

### Confidence Scale

| Label | Meaning |
| --- | --- |
| high | Direct evidence supports the finding with no material unresolved blocker. |
| medium | Evidence supports a plausible issue, but material runtime or reachability proof remains. |
| low | Evidence is incomplete and the item is retained only for explicit follow-up. |

<a id="finding-1"></a>

### [1] Fresh JWKS client per token enables pre-authentication fetch amplification

| Field | Value |
| --- | --- |
| Severity | medium |
| Confidence | high |
| Confidence rationale | The actual `_decode` implementation and installed PyJWT 2.13 code were traced, and a focused PoC observed four JWKS fetches for two rejected token attempts. |
| Category | Uncontrolled resource consumption |
| CWE | CWE-400 |
| Affected lines | reviewapp/api/auth.py:73-75, reviewapp/api/auth.py:117-139 |

#### Summary

Every supplied bearer token creates a new `PyJWKClient`, discarding both JWKS and key caches. An unauthenticated caller can make each valid-shaped token perform a synchronous JWKS request, while an unknown `kid` forces a second refresh before the request is rejected.

#### Root Cause

The violated invariant is that repeated authentication failures must not cause unbounded identity-provider work. `_decode` creates the cache-owning client inside the request, so even `cache_keys=True` cannot amortize JWKS retrieval across requests.

**Any supplied bearer token enters decoding** — `reviewapp/api/auth.py:133-139`

Authentication has not succeeded when attacker-controlled bearer bytes are passed into `_decode`.

```python
if credentials is None:
    ...
settings = getattr(request.app.state, "settings", None) or load_settings()
claims = _decode(credentials.credentials, settings)
```

**Client and caches are recreated for every decode** — `reviewapp/api/auth.py:70-75`

The client that owns the JWKS-set and signing-key caches is temporary, so no cached state survives to the next request.

```python
def _decode(token: str, settings: Settings) -> dict[str, object]:
    try:
        signing_key = jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt(
            token
        )
```

#### Validation

Two calls with an attacker-selected unknown `kid` caused four mocked JWKS fetches against the actual `_decode` path; PyJWT source confirms a miss refreshes once.

Validation method: targeted PoC plus static source and dependency trace

**Any supplied bearer token enters decoding** — `reviewapp/api/auth.py:133-139`

Authentication has not succeeded when attacker-controlled bearer bytes are passed into `_decode`.

```python
if credentials is None:
    ...
settings = getattr(request.app.state, "settings", None) or load_settings()
claims = _decode(credentials.credentials, settings)
```

**Client and caches are recreated for every decode** — `reviewapp/api/auth.py:70-75`

The client that owns the JWKS-set and signing-key caches is temporary, so no cached state survives to the next request.

```python
def _decode(token: str, settings: Settings) -> dict[str, object]:
    try:
        signing_key = jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt(
            token
        )
```

#### Dataflow

Bearer token -\> `get_principal` -\> `_decode` -\> fresh `PyJWKClient` -\> JWKS fetch/refresh -\> rejection

- **Source:** Unauthenticated bearer bytes and JWT `kid`

- **Sink:** Synchronous JWKS retrieval

- **Outcome:** Request capacity and identity-provider resources are consumed

**Any supplied bearer token enters decoding** — `reviewapp/api/auth.py:133-139`

Authentication has not succeeded when attacker-controlled bearer bytes are passed into `_decode`.

```python
if credentials is None:
    ...
settings = getattr(request.app.state, "settings", None) or load_settings()
claims = _decode(credentials.credentials, settings)
```

**Client and caches are recreated for every decode** — `reviewapp/api/auth.py:70-75`

The client that owns the JWKS-set and signing-key caches is temporary, so no cached state survives to the next request.

```python
def _decode(token: str, settings: Settings) -> dict[str, object]:
    try:
        signing_key = jwt.PyJWKClient(settings.jwks_url, cache_keys=True).get_signing_key_from_jwt(
            token
        )
```

#### Reachability

Any enclave or otherwise network-positioned caller that reaches the API auth boundary can trigger the work without credentials.

- **Attacker:** Unauthenticated API caller

- **Entry point:** Any route using `get_principal`

- **Outcome:** Availability degradation and outbound JWKS pressure

Preconditions:
- Network reachability to the ReviewApp

#### Severity

**Medium** — The path is pre-authentication and the PoC deterministically amplifies each unknown-key attempt into two synchronous outbound requests. The impact is availability and identity-provider pressure rather than confidentiality or code execution.

A persistent shared client with effective pre-authentication throttling would lower severity; demonstrated public exposure and production worker exhaustion would increase operational urgency.

#### Remediation

Create one long-lived `PyJWKClient` per immutable JWKS configuration, reuse it across requests, set bounded fetch timeouts, and rate-limit authentication failures before repeated network retrieval.

Tests:
- Submit many tokens with the same valid `kid` and assert only one JWKS fetch within the cache lifetime.
- Submit repeated unknown `kid` values and assert fetch refreshes are globally bounded.
- Verify timeout and upstream JWKS failures fail closed without exhausting request workers.

Preventive controls:
- Pre-authentication request throttling
- Metrics and alerts for JWKS fetch rate, latency, and failure volume
- Asynchronous or isolated outbound identity-provider I/O

<a id="finding-2"></a>

### [2] UPN local-part mapping merges distinct reviewer identities

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | high |
| Confidence rationale | The exact UPN transform and every relevant database predicate are visible in source, and unit tests explicitly confirm domain removal. |
| Category | Identity collision / improper authentication |
| CWE | CWE-287 |
| Affected lines | reviewapp/api/auth.py:140-149, contracts/base.py:114-137, reviewapp/api/decisions.py:190-203 |

#### Summary

The signed full UPN is reduced to its case-folded local part before per-reviewer blind-entry, second-key, and queue checks. Distinct accepted-tenant accounts sharing that local part across domains therefore operate under the same workflow identity.

#### Root Cause

The violated invariant is that every authenticated human must have a collision-resistant workflow key. The bridge removes the UPN domain and the state gates use only that shortened value, so identity distinctions established by token validation are lost.

**Authenticated UPN is converted into workflow identity** — `reviewapp/api/auth.py:140-149`

The signed full principal name is passed to the lossy bridge before workflow authorization state is queried.

```python
upn = claims.get("preferred_username")
...
return Principal(upn=upn, reviewer_id=reviewer_id_from_upn(upn), roles=roles)
```

**Domain is discarded** — `contracts/base.py:131-137`

Two distinct full UPNs with the same local part are deliberately mapped to the same `reviewer_id`.

```python
local_part = upn.split("@", 1)[0].casefold()
if not _REVIEWER_ID_RE.match(local_part):
    raise ContractValidationError(...)
return local_part
```

**Lane-C gates trust the lossy handle** — `reviewapp/api/decisions.py:190-203`

Blind-entry and second-key authorization state is selected by the colliding handle rather than the full authenticated identity.

```python
if decision.lane is Lane.C:
    ...
    if not await blind_entries.has_blind_entry(cell_key, principal.reviewer_id):
        ...
    if not await second_keys.has_second_key(
        cell_key, principal.reviewer_id, decision.second_key_ref
    ):
```

#### Validation

Tests prove the bridge removes domains, and source tracing shows the resulting handle is used in blind-entry, second-key, and queue predicates.

Validation method: static identity/state trace plus focused unit tests

**Authenticated UPN is converted into workflow identity** — `reviewapp/api/auth.py:140-149`

The signed full principal name is passed to the lossy bridge before workflow authorization state is queried.

```python
upn = claims.get("preferred_username")
...
return Principal(upn=upn, reviewer_id=reviewer_id_from_upn(upn), roles=roles)
```

**Domain is discarded** — `contracts/base.py:131-137`

Two distinct full UPNs with the same local part are deliberately mapped to the same `reviewer_id`.

```python
local_part = upn.split("@", 1)[0].casefold()
if not _REVIEWER_ID_RE.match(local_part):
    raise ContractValidationError(...)
return local_part
```

**Lane-C gates trust the lossy handle** — `reviewapp/api/decisions.py:190-203`

Blind-entry and second-key authorization state is selected by the colliding handle rather than the full authenticated identity.

```python
if decision.lane is Lane.C:
    ...
    if not await blind_entries.has_blind_entry(cell_key, principal.reviewer_id):
        ...
    if not await second_keys.has_second_key(
        cell_key, principal.reviewer_id, decision.second_key_ref
    ):
```

#### Dataflow

Signed UPN -\> local-part bridge -\> colliding `reviewer_id` -\> per-reviewer workflow lookup

- **Source:** Valid token for a distinct colliding Entra account

- **Sink:** Blind-entry, second-key, and queue state predicates

- **Outcome:** Distinct-account reviewer separation is bypassed

**Authenticated UPN is converted into workflow identity** — `reviewapp/api/auth.py:140-149`

The signed full principal name is passed to the lossy bridge before workflow authorization state is queried.

```python
upn = claims.get("preferred_username")
...
return Principal(upn=upn, reviewer_id=reviewer_id_from_upn(upn), roles=roles)
```

**Domain is discarded** — `contracts/base.py:131-137`

Two distinct full UPNs with the same local part are deliberately mapped to the same `reviewer_id`.

```python
local_part = upn.split("@", 1)[0].casefold()
if not _REVIEWER_ID_RE.match(local_part):
    raise ContractValidationError(...)
return local_part
```

**Lane-C gates trust the lossy handle** — `reviewapp/api/decisions.py:190-203`

Blind-entry and second-key authorization state is selected by the colliding handle rather than the full authenticated identity.

```python
if decision.lane is Lane.C:
    ...
    if not await blind_entries.has_blind_entry(cell_key, principal.reviewer_id):
        ...
    if not await second_keys.has_second_key(
        cell_key, principal.reviewer_id, decision.second_key_ref
    ):
```

#### Reachability

Requires two accepted-tenant accounts with the same local part and a relevant role on the second account.

- **Attacker:** Authenticated reviewer with a colliding UPN local part

- **Entry point:** Any role-gated workflow route

- **Outcome:** Reuse of another account's per-reviewer workflow identity

Preconditions:
- Colliding tenant accounts
- Relevant app role

#### Severity

**Low** — The collision breaks distinct-reviewer workflow integrity, but exploitation requires a specifically provisioned role-bearing account and does not itself grant a new role.

Evidence of live colliding accounts or cross-role state reuse would raise likelihood; keying state by immutable Entra object ID or full normalized UPN removes the issue.

#### Remediation

Use the immutable Entra object identifier (`oid`) plus tenant identifier (`tid`) as the canonical workflow key, or use the complete normalized UPN if immutable IDs cannot be adopted; migrate existing state with an explicit collision check.

Tests:
- Assert `reviewer@domain-a` and `reviewer@domain-b` receive distinct workflow identifiers.
- Verify blind-entry, second-key, claims, and audit records all use the same collision-resistant key.
- Fail migration when existing shortened identifiers map to multiple Entra principals.

Preventive controls:
- Repository-wide principal-key type backed by Entra `tid` and `oid`
- Tenant account collision audit during deployment
- Database uniqueness and foreign-key constraints on canonical principal identity

<a id="finding-3"></a>

### [3] DNS rebinding can inherit the local launcher's all-role principal

| Field | Value |
| --- | --- |
| Severity | low |
| Confidence | medium |
| Confidence rationale | Source and tests prove the all-role grant and absence of application-layer origin binding, but no live browser DNS-rebinding/PNA reproduction was run. |
| Category | Authorization bypass / DNS rebinding |
| CWE | CWE-346 |
| Affected lines | reviewapp/api/auth.py:106-114, reviewapp/cli.py:313-320 |

#### Summary

The tokenless launcher grants every ReviewApp role based only on an app-state marker and loopback TCP peer. It does not bind the grant to the expected Host, Origin, or an unguessable launcher credential, so a browser DNS-rebinding origin can potentially reach protected routes as the local principal.

#### Root Cause

The launcher treats loopback network location as sufficient proof of browser origin. DNS rebinding preserves the attacker hostname as the browser origin while causing the browser to connect to loopback, satisfying the peer check without proving the request came from the launcher page.

**Launcher installs every reviewer role** — `reviewapp/cli.py:313-320`

The launcher marker carries reviewer, adjudicator, auditor, and admin authority.

```python
app.state.local_principal = Principal(
    upn=_LOCAL_UPN,
    reviewer_id=reviewer_id_from_upn(_LOCAL_UPN),
    roles=frozenset(ReviewerRole),
)
```

**Peer address is the only request-bound control** — `reviewapp/api/auth.py:106-114`

A tokenless request receives the privileged principal whenever its socket peer is loopback; no Host, Origin, or launcher secret is checked.

```python
principal = getattr(request.app.state, "local_principal", None)
if not isinstance(principal, Principal):
    return None
client = request.client
if client is None or client.host not in _LOOPBACK_HOSTS:
    return None
return principal
```

#### Validation

Tests confirm tokenless loopback requests succeed and non-loopback peers receive 401. Source review found no application-layer origin or nonce control.

Validation method: static boundary trace plus focused launcher tests

**Launcher installs every reviewer role** — `reviewapp/cli.py:313-320`

The launcher marker carries reviewer, adjudicator, auditor, and admin authority.

```python
app.state.local_principal = Principal(
    upn=_LOCAL_UPN,
    reviewer_id=reviewer_id_from_upn(_LOCAL_UPN),
    roles=frozenset(ReviewerRole),
)
```

**Peer address is the only request-bound control** — `reviewapp/api/auth.py:106-114`

A tokenless request receives the privileged principal whenever its socket peer is loopback; no Host, Origin, or launcher secret is checked.

```python
principal = getattr(request.app.state, "local_principal", None)
if not isinstance(principal, Principal):
    return None
client = request.client
if client is None or client.host not in _LOOPBACK_HOSTS:
    return None
return principal
```

#### Dataflow

Attacker origin -\> rebound DNS -\> browser loopback connection -\> `local_principal` -\> protected route

- **Source:** Attacker-controlled web origin and DNS

- **Sink:** Return of the all-role `Principal`

- **Outcome:** Unauthorized local ReviewApp reads or actions

**Launcher installs every reviewer role** — `reviewapp/cli.py:313-320`

The launcher marker carries reviewer, adjudicator, auditor, and admin authority.

```python
app.state.local_principal = Principal(
    upn=_LOCAL_UPN,
    reviewer_id=reviewer_id_from_upn(_LOCAL_UPN),
    roles=frozenset(ReviewerRole),
)
```

**Peer address is the only request-bound control** — `reviewapp/api/auth.py:106-114`

A tokenless request receives the privileged principal whenever its socket peer is loopback; no Host, Origin, or launcher secret is checked.

```python
principal = getattr(request.app.state, "local_principal", None)
if not isinstance(principal, Principal):
    return None
client = request.client
if client is None or client.host not in _LOOPBACK_HOSTS:
    return None
return principal
```

#### Reachability

Requires a running launcher, a victim browser visit, and browser behavior that permits the private-network request.

- **Attacker:** Remote web attacker

- **Entry point:** Tokenless local ReviewApp route

- **Outcome:** The attacker origin acts with local reviewer roles

Preconditions:
- Launcher running
- Victim visits attacker origin
- DNS rebinding/PNA path succeeds

#### Severity

**Low** — Successful exploitation crosses a remote web-origin boundary into local confidential review data and roles, but requires a running launcher, a victim browser visit, DNS rebinding, and browser private-network behavior that was not dynamically proven.

A supported-browser PoC reaching binding write routes would raise confidence and possibly impact; a strict Host/Origin/nonce check would eliminate the path.

#### Remediation

Generate a high-entropy per-launch secret and require it on every local API request; also reject unexpected Host and Origin values and keep loopback-only binding.

Tests:
- Reject a loopback-peer request with an attacker Host or Origin.
- Reject tokenless requests that omit or guess the per-launch secret.
- Confirm the real launcher page supplies the secret and retains intended local functionality.

Preventive controls:
- Explicit TrustedHost/Origin validation
- Per-launch capability token
- Browser security regression test for DNS rebinding

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| Bearer JWT validation and JWKS retrieval | Authentication availability and outbound identity-provider resource use | Reported | Signature, issuer, audience, and algorithm controls fail closed, but the per-request cache lifecycle creates a reportable resource-amplification path. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/candidate-204fcb4fa7b16ade/poc_output.txt |
| Tokenless loopback launcher principal | Local authorization boundary and browser-origin trust | Reported | Marker and loopback peer checks reject direct remote clients, but no application-layer Host, Origin, or launcher capability binds browser requests. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
| UPN role parsing and reviewer identity bridge | Principal uniqueness, reviewer separation, and workflow-state attribution | Reported | Unknown roles are dropped and route guards are enforced, but domain removal creates a collision-prone workflow key. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
