# Security Review: renchris/reso-landing-app (branch deps-upgrade-2026-10, worktree landing-review-w3)

## Scope

First Codex Security full repository scan (P1, no prior bundle) of reso-landing-app at d3ebdcee, the deps-upgrade-2026-10 branch (Next 16.4.1, React 19.3.1) that is not yet on production main. All 107 tracked files were inventoried and reviewed sequentially by one agent; 8 candidates were discovered, validated and run through the policy pass; none survived as a finding.

- Scan mode: repository
- Target kind: git_worktree
- Target ID: target_sha256_475223fe15647e8ebfe2b63883183108
- Revision: d3ebdcee6c0fa80d2efb68196e05c1bad85a3998
- Snapshot digest: codex-security-snapshot/v1:sha256:3f10a1c4be6b257c14c5e50fb0cd929c794a68f859a81b173957e78e9c884d97
- Inventory strategy: repository
- Included paths: .
- Excluded paths: none
- Runtime or test status: No server was started and no network or AWS call was made. Four harmless local harnesses ran under Node with mocked I/O: the real pricing and login pages transpiled with the repo TypeScript and rendered with the repo react-dom/server, Next server-action request classification, and Next image-optimizer parameter validation against the branch runtime config.
- Artifacts reviewed: 107 tracked files (git ls-files): 31 runtime source under src/, 24 public SVGs, 29 raster images (metadata only), 13 build/config files, 10 docs and agent-tooling files, Untracked local .next build manifests (routes, images, server-reference, required-server-files) as framework-behaviour evidence, Installed next@16.4.1 internals: image-config defaults, image-optimizer validateParams and fetchInternalImage, server-action request classifier, action handler, next/link, Git history across 80 commits on all refs (secret sweep)
- Scan context: Threat model generated during Phase 1 of this scan (no SECURITY.md, AGENTS.md or prior model). snapshotDigest = sha256 over sorted (path NUL sha256(file) LF) for every git ls-files path of the clean worktree. Dedup source docs/plans/DEPENDENCY_UPGRADE_PLAN.md read before reporting; production image-optimizer exposure is decision 58f292806fd7 (context only). No subagent fan-out was available: inventory, file review, validation and attack-path steps ran sequentially in the parent.

Limitations and exclusions:
- Raster images and favicon.ico are binary: inspected for EXIF/XMP/GPS metadata only, not as code.
- keyboard.tsx (99 KB of SVG paths) was reviewed through a structural filter that printed every non-path line plus a sink-token grep.
- Advisories for the pinned dependency versions published after June 2026 were not checked (no network by rule).
- Amplify console settings (custom headers, WAF, cache scoping) are outside the repository and were not queried (no AWS calls by rule).
- The inventory follows git ls-files rather than the raw rg listing: rg listed the worktree .git pointer file and omitted the tracked but gitignored next-env.d.ts.
- Excluded node_modules/\*\*: Untracked installed third-party packages; reviewed only where needed to confirm framework behaviour (image optimizer, server-action classifier, next/link).
- Excluded .next/\*\*: Untracked local build output from another lens; read only as build-manifest evidence (routes, images, server-reference manifests), not as source.
- Excluded .claude/tmp/\*\*: Untracked, gitignored scratch output of other review lenses; not repository content.

### Scan Summary

| Field | Value |
| --- | --- |
| Reportable findings | 0 |
| Severity mix | none |
| Confidence mix | none |
| Coverage | complete |
| Validation mode | Compact standard-scan validation and attack-path passes over one candidate ledger; interface-level harnesses for 4 candidates, static code, config and metadata evidence for the rest; final policy-adjustment matrix applied mechanically. |

Canonical artifacts: `scan-manifest.json`, `findings.json`, and `coverage.json`. This report is a deterministic projection of those files.

## Threat Model

Public, unauthenticated Next.js marketing site on AWS Amplify with seven routes, no API routes, server actions, middleware, database, sessions or secrets. The realistic attacker is an anonymous internet visitor controlling URL, query string, method, body and headers; the meaningful outcomes are script or content injection on join.reso.gl, tampering with the pricing CTAs, framework-level RCE/SSRF on the Amplify compute, and build-pipeline integrity.

### Assets

- Brand integrity and visitor trust of join.reso.gl
- Integrity of the pricing CTAs to Stripe Payment Links and zcal
- Credentials visitors might type into the /login template form
- Amplify build and deploy pipeline for production main
- Availability and compute cost of server-rendered and image-optimizer endpoints

### Trust Boundaries

- Anonymous internet visitor -\> Amplify/CloudFront -\> Next.js server (query string, method, body, headers, /_next/image params)
- Visitor browser -\> third-party origins (api.fontshare.com stylesheet, buy.stripe.com, zcal.co)
- Repository writers and Amplify owner -\> build spec, lockfile and config
- npm registry -\> build box

### Attacker Capabilities

- Send arbitrary GET/POST requests with any query, body and headers to every route and framework endpoint
- Frame the site from a third-party page
- Not assumed: repository write, Amplify console access, or compromise of npm, Fontshare, Stripe or zcal

### Security Objectives

- No attacker-controlled data reaches HTML, script or URL contexts
- Pricing CTAs always point to the genuine payment and booking pages
- Framework endpoints cannot be turned into SSRF, file read or code execution
- Production builds only ship integrity-pinned dependencies

### Assumptions

- Every route is public; there is no session to protect
- Amplify console headers and WAF are not visible from the repository
- Production main still runs an older tree; its image-optimizer exposure is tracked separately

## Findings

### No findings

No reportable findings survived the canonical discovery, validation, and reportability gates.

## Reviewed Surfaces

| Surface | Risk Area | Outcome | Notes |
| --- | --- | --- | --- |
| GET /pricing ?tier query parameter (src/app/pricing/page.tsx:537-544) | Reflected XSS / content injection / link tampering | Rejected | candidate-c2cde6d450e560cc: validation=suppressed. Strict-equality allowlist over three constant slugs with tiers\[0\] fallback; nine crafted values rendered through the real page: none reflected, none altered a link, none threw. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/candidate-c2cde6d450e560cc/pricing_tier_results.txt, artifacts/02_discovery/validation_artifacts/candidate-c2cde6d450e560cc/render_harness.js |
| /login credential form (src/app/login/page.tsx:21) | Credential handling | Rejected | candidate-27894790d5bbed1b: validation=suppressed. Non-functional template form: POSTs to the same first-party route over HTTPS; Next classifies it as an unsupported URL-encoded MPA action and renders the page; no code reads or stores the body. Product follow-up: link to the real app login or remove the form. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/candidate-27894790d5bbed1b/action_meta_results.txt, artifacts/02_discovery/validation_artifacts/candidate-27894790d5bbed1b/login_form_render.txt, artifacts/02_discovery/validation_artifacts/candidate-27894790d5bbed1b/next_action_handler_excerpt_396_420.txt |
| HTTP response headers and CSP (next.config.mjs:8-11) | Clickjacking / missing CSP and transport headers | Rejected | candidate-d997de2ed46e4ca6: validation=reportable, attack_path=ignore (impact ignore, likelihood high, severity ignore). No headers() and no middleware; built routes-manifest headers \[\]. Nothing state-changing to frame and no injection sink for CSP to backstop, so policy ignore. Hardening backlog: frame-ancestors none, X-Content-Type-Options nosniff, Referrer-Policy, HSTS, CSP allowing self plus api.fontshare.com. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/03_coverage/negative_searches.txt |
| Fontshare stylesheet in the root layout (src/app/layout.tsx:19-22) | Third-party resource integrity / privacy | Rejected | candidate-a8440707cf39bd09: validation=reportable, attack_path=ignore (impact low, likelihood ignore, severity ignore). CSS-only capability, needs a Fontshare compromise; SRI impossible on dynamic font CSS. Self-hosting Switzer would also stop sending every visitor IP to a third party. Evidence: artifacts/02_discovery/candidate_ledger.jsonl |
| Pricing CTAs to Stripe/zcal with target=_blank (src/app/pricing/page.tsx:203) | Reverse tabnabbing | Rejected | candidate-847925d58617afa4: validation=suppressed. Anchors render target=_blank without rel (next/link adds none), but browsers imply noopener for target=_blank and the destinations are constant Stripe/zcal URLs. The job modal mailto uses noopener,noreferrer explicitly. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/candidate-847925d58617afa4/outbound_anchor_attrs.txt |
| Default-enabled /_next/image on this branch (next.config.mjs, Next 16.4.1) | SSRF / framework RCE / resource use | Rejected | candidate-a4f467a486d58c3c: validation=suppressed. DEDUP: production main (Next 14.2.11) optimizer exposure is decision 58f292806fd7, and the images.unoptimized mitigation is tracked separately; this row checks the branch only. Real validator: remote/metadata URLs rejected (remotePatterns \[\]), SVG disallowed, 15 widths x q75 x webp, cached 4 h; local hrefs re-enter Next routing as a mocked GET. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/validation_artifacts/candidate-a4f467a486d58c3c/image_params_results.txt, artifacts/02_discovery/validation_artifacts/candidate-a4f467a486d58c3c/image_params_harness.js |
| EXIF/XMP metadata in served images under public/ | Information disclosure | Rejected | candidate-081c3af2ede93d08: validation=reportable, attack_path=ignore (impact ignore, likelihood high, severity ignore). No GPS in any of 29 rasters; camera model, capture dates, and one photographer name plus camera serial (harriet-chan.jpg). Strip on export as hygiene. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/work_ledger.jsonl |
| Amplify build spec and dependency install (amplify.yml, pnpm-lock.yaml) | Build / supply-chain integrity | Rejected | candidate-2744ce1791fbece2: validation=reportable, attack_path=ignore (impact high, likelihood ignore, severity ignore). Exact pins, 224/224 sha512 lockfile entries, registry-only sources, no allowlisted lifecycle scripts. Residual gaps (global pnpm without repo-pinned hash, cached node_modules) need repo/Amplify control or registry compromise. Hardening: packageManager +sha512 via corepack; cache the pnpm store, not node_modules. Evidence: artifacts/02_discovery/candidate_ledger.jsonl, artifacts/02_discovery/work_ledger.jsonl |
| Same-origin SVG assets under public/ (24 files) | Stored XSS via active SVG content | No issue found | Affirmative review: every SVG parsed with xml.etree and its full element/attribute inventory checked; only inert shapes, no script/foreignObject/on\* handlers/external href or url(). adobe-creative-cloud.svg embeds an inert data:image/png. Evidence: artifacts/02_discovery/work_ledger.jsonl |
| All runtime source under src/ (31 files: 8 app routes, 22 components, 1 stylesheet) | XSS / DOM sinks / unsafe client logic | No issue found | Affirmative review: every file read in full (keyboard.tsx via a structural filter that printed all non-SVG-path lines). All rendered data is constant; client components handle only UI state. Corroborated by the sink searches in negative_searches.txt. Evidence: artifacts/02_discovery/work_ledger.jsonl, artifacts/03_coverage/negative_searches.txt |
| Dependency manifest, lockfile and package-manager config | Dependency source integrity | No issue found | Structural review of all 224 lockfile package entries (sha512 on every one, registry sources only); .npmrc and pnpm-workspace.yaml carry no registry override or token. Advisory currency of the pinned versions is not judged here (see open questions; owned by the dependency lens). Evidence: artifacts/02_discovery/work_ledger.jsonl, artifacts/03_coverage/negative_searches.txt |
| docs/, README, CHANGELOG, LICENSE, .claude/ agent tooling | Secret leakage / unsafe automation instructions | No issue found | Affirmative review: read in full. Not served by Next. Agent tooling instructs read-only git and aws list/get commands under developer control. Evidence: artifacts/02_discovery/work_ledger.jsonl |
| Route handlers, API routes, middleware/proxy, server actions, RSC action decoding | Auth bypass / injection / RSC deserialization | Not applicable | NEGATIVE SEARCH: no route/middleware/proxy files, no "use server"; built server-reference manifest is empty, so Next rejects multipart and fetch action requests before decoding (action-handler.js:415-419). Evidence: artifacts/03_coverage/negative_searches.txt, artifacts/02_discovery/validation_artifacts/candidate-27894790d5bbed1b/server_reference_manifest_actions.txt |
| Authentication, sessions, cookies, authorization, CSRF | Account takeover / CSRF / IDOR | Not applicable | NEGATIVE SEARCH: no cookies(), headers(), session, or auth code in src/; the only form is the non-functional /login template. Evidence: artifacts/03_coverage/negative_searches.txt |
| Server-side fetch, filesystem, process, env, database access in application code | SSRF / path traversal / command and query injection | Not applicable | NEGATIVE SEARCH: no fetch/axios/http, fs, child_process, process.env or DB client in src/ or package.json dependencies. Evidence: artifacts/03_coverage/negative_searches.txt |
| Redirects and navigation sinks | Open redirect | No issue found | NEGATIVE SEARCH plus review of the single hit: not-found.tsx:4 redirect("/") with a constant target; no window.location or router.push with input. Evidence: artifacts/03_coverage/negative_searches.txt |
| Browser storage, postMessage, third-party scripts and embeds | Client-side data exposure / script supply chain | Not applicable | NEGATIVE SEARCH: no localStorage/sessionStorage/postMessage/cookie access, no next/script, script, iframe, embed or analytics tags in src/. Evidence: artifacts/03_coverage/negative_searches.txt |
| Secrets in the tracked tree and in git history (all refs) | Credential exposure | No issue found | NEGATIVE SEARCH: secret patterns 0 hits in tracked text; history sweep over 80 commits found 0 literal secrets (the removed Sanity blog read env vars only). A node_modules snapshot exists only on local refs/original filter-branch backups and was not scanned (third-party code). Evidence: artifacts/03_coverage/negative_searches.txt, artifacts/03_coverage/history_secret_scan.txt |

## Open Questions And Follow Up

- Do any Next.js 16.4.1 or React 19.3.1 security advisories published after June 2026 apply to this branch? This scan had no network by rule and its model knowledge ends June 2026.
  - Follow-up prompt: On branch deps-upgrade-2026-10 (d3ebdcee), check GitHub advisories for next@16.4.1, react@19.3.1, react-dom@19.3.1 and sharp@0.35.5 published 2026-06-01 to today, and say whether any affects the image optimizer, RSC decoding or static serving paths this site exposes.
- Which response headers, WAF rules and build-cache scoping does the Amplify app d3ce74t8uneoh0 apply outside the repository?
  - Follow-up prompt: Read-only: list the custom headers, WAF association and branch auto-build settings for Amplify app d3ce74t8uneoh0 and compare them with the header hardening backlog in surface http-security-headers.
- Should the branch disable the unused image optimizer (images.unoptimized: true) before the production merge? This is already tracked (decision 58f292806fd7 and the separate images.unoptimized item); listed here only so the merge checklist does not lose it.
- Should /login keep a non-functional credential form, or link to the real Reso app sign-in? Users who type real credentials there cannot sign in; the values are discarded first-party.
