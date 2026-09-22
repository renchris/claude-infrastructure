# FACTS lens — agent-context-sync-2026-09-21.md

Checks run: every number/mechanism in the one-screen summary, §2 table, §3, §4.1–4.7, §5, §6, §8, §9 grepped against A1..I2 and verify/C1..C10; local re-measurement of the symlink rows (bare `find`, `find -type f`, `grep -R`/`-RS`, git 120000 blob, tool versions) in scratchpad/review/fx; live re-read of the v1.0 `driveItem: delta` page; installed ms365 server (`@softeria/ms-365-mcp-server` 0.143.0) inspected for the cited line; OneDrive client presence checked (`/Applications/OneDrive.app`, `pluginkit`).

Verified and holding (no finding): throttling RU/egress numbers (C9); consent table + default consent policy (C6); Glob 100/25,000 and Grep 250 (C7); webhook latency/expiry/45-min/`updated`-only (C8); SF_DATALESS, EDEADLK, `getiopolicy_np`=ON, inheritance (C5); ZIP-timestamp/core.xml churn (C10); cTag/eTag file-vs-folder rules (C2); quickXorHash absence classes (C1); rclone token commented out / no deltaLink persisted (C3); 200k-row manifest 31 MB/0.12 s/0.051 s, deflate 13/11,137, DVC 343 stages/4 min (D); converter figures 5.5 p/s, 6 of 15, NaN/100.0, blank header, no .eml, 1.9x (E); Glean 20 %/7 d, LangChain, Onyx (F); 42 %/50 % rename, 61–73 chars/line, 146 K chars, 1,192 files, 25 KB, Debezium (G); simhash 0.75/0.38–0.50/0.79, driveItemVersion no hash, conflictBehavior, Lyft 3/4 (H); 12/12 stale, median ~1 month, worst 17 months, Zoekt, Cody 24 h (A2); 3.2 MB, +0.3 %/+2.6 %, forum 144970, WAL 1/s (A1); 400 "Provided sync token is malformed", token=latest, folder-scoped delta works on consumer (B1); `@removed` on move, Teams scopes, MCP token dropped (B2).

## Findings

### F1 — MAJOR · §4.7 "rclone, demoted to transport"
Claim: "measured floor ~1.35 s per 1,000-item page, 482 delta calls and ~11 min to conclude nothing changed on a large library (rclone #9226)".
Problem: the preamble defines **measured** as "run on this Mac or against a live Graph tenant during the wave". C4-rclone.md:21 says "Nothing here was measured by me; the one performance measurement quoted is a…" — it is the #9226 reporter's wall-clock (chscott, 2026-03-09); C3 adds "No local rclone binary was exercised". The report also cannot settle the library size (line 12 says ~0.5 M items, line 294 says 482 calls contradicts 3 M).
Fix: "rclone #9226's reporter measured 482 delta calls and ~11 min (~653 s, ~1.35 s per 1,000-item page) to conclude nothing had changed on a large SharePoint library — the number to plan with; nothing rclone-side was run in this wave."
Evidence: C4-rclone.md:12, :21, :55-58, :294-297; verify/C3.md "Scope".

### F2 — MAJOR · §8 "Webhooks as the trigger"
Claim: "up to 6 h latency, root-only, id-only payload, public HTTPS or Event Hubs required".
Problem: C8 §4 REFUTES root-only for OneDrive personal ("you can subscribe to the root folder or any subfolder"), confirms it only for OneDrive for Business, and notes a SharePoint library is a `list` subscription. C8 §5: the payload carries **no id of the changed item** — only `subscriptionId`, `expirationDateTime`, `resource` (the subscribed folder), `clientState`; "id-only" overstates what arrives. §4.2 already states this correctly; the §8 row still carries the pre-verification wording.
Fix: "up to 6 h latency; root-only on OneDrive for Business (any subfolder on personal; a SharePoint library subscribes as a `list`); payload names the subscribed folder, never the changed item; public HTTPS or Event Hubs required".
Evidence: verify/C8.md §4, §5.

### F3 — MAJOR · one-screen summary, "The golden examples, as they actually work"
Claim: "Cursor does two-level content addressing — per-file/dir SHA-256 Merkle tree polled every 10 minutes for the what…" (present tense, framed as "as they actually work, not as the marketing says").
Problem: A1 M4 records the 10-minute text as "Documented on the security page as of the 2026-01-01 capture; absent from the live page", and A1:73 says verbatim "do not quote 'every 10 minutes' as today's behaviour; quote it as the documented design of the Merkle-sync generation". §2 hedges with "(security page, archived 2026-01)"; the summary does not.
Fix: "Cursor's Merkle-sync generation does two-level content addressing — a per-file/dir SHA-256 Merkle tree with a documented 10-minute hash-mismatch poll (security page as archived 2026-01; the sentence is gone from the live page and its current default search is a local index) for the what…"
Evidence: A1-cursor.md:16 (M4), :26 (M14), :73.

### F4 — MAJOR · §7 "The no-API path"
Claim: "The Claude desktop app cannot start sessions under `~/Library/CloudStorage` even with Full Disk Access (claude-code #34554)".
Problem: `#34554` appears in no axis report and no verifier report (`grep -rn 34554` over the evidence dir returns nothing). The only Claude issue in the receipts is #40783 (C5), which is a *read* failure from a Linux-VM sandbox, not a session-start refusal. The claim is unreceipted.
Fix: either add the receipt (issue URL + the quoted sentence) to a report, or replace with "claude-code #40783 shows a sandboxed Claude reading a File-Provider path failing every read with EDEADLK — another reason the agent never works from the sync root."
Evidence: `grep -rn 34554 agent-context-sync-2026-09-21/` → no matches; verify/C5.md §(c).

### F5 — MAJOR · one-screen summary, item 2 "A manifest keyed on stable identity, with three hashes"
Claim: "Same-name in-place overwrites are caught by H1 with zero download when the server supplies `quickXorHash`, and by H0/H1 locally otherwise."
Problem: contradicts the document's own definitions. H1 is "a canonical content hash" computed from materialised bytes (§4.1 #2, §4.3 `canonical_hash`, classifier step "MAYBE_CHANGED ∪ CREATED → materialise → content_hash, canonical_hash"). The zero-download signal is `provider_hash` (`quickXorHash`, "comparable only to itself", §4.3), which §4.1 #3 puts *before* H0. quickXorHash is not H1.
Fix: "Same-name in-place overwrites are caught with zero download by the provider hash (`quickXorHash`) where the server supplies it, and by H0 — then H1 on the survivors — locally otherwise."
Evidence: document §4.1 #2–#3, §4.3 table rows `provider_hash` / `canonical_hash`, classifier block; verify/C1.md §1.

### F6 — MINOR · one-screen summary, §9 intro, one-screen "What to measure"
Claim: "this Mac has no OneDrive client" / "there is no OneDrive client here".
Problem: `/Applications/OneDrive.app` is installed and `com.microsoft.OneDrive.FileProvider (26.158.0816)` is registered (`pluginkit -m`); C5 says the same. What is absent is a signed-in sync domain — `~/Library/CloudStorage` is empty. I2:3 is the source of the wrong wording.
Fix: "this Mac has the OneDrive client and File Provider extension installed but no signed-in sync domain — `~/Library/CloudStorage` is empty, so no dataless placeholder exists to probe".
Evidence: verify/C5.md header; `ls /Applications/OneDrive.app`; `pluginkit -m -i com.microsoft.OneDrive.FileProvider`.

### F7 — MINOR · one-screen summary and §3 table, `find` row
Claim: "`find <link>` returns zero" / "on a symlinked start dir returns 0 rows".
Problem: bare `find <link>` prints the link itself (1 row, measured: `rows=1`). The measured zero is `find <link> -type f` (C1:69-71; scratchpad re-run `rows=0`).
Fix: "`find <link> -type f` returns zero rows (the bare form prints only the link)". §3 table cell: "skipped; **`find <link> -type f` on a symlinked start dir returns 0 rows** (bare `find` prints the link itself)".
Evidence: C1-macos-onedrive-symlinks.md:55, :69-72; scratchpad/review/fx run.

### F8 — MINOR · §4.7 "Cadence"
Claim: "daily full reconcile regardless (Microsoft's ceiling is 'no more than once per day')".
Problem: the source sentence is "We recommend no more than once per day for this periodic check" — a recommendation, not a ceiling or limit.
Fix: "daily full reconcile regardless (Microsoft recommends 'no more than once per day' for the periodic check)".
Evidence: verify/C9.md §(a); B1-graph-drive-delta.md:105.

### F9 — MINOR · §2 table, "Microsoft scan guidance" row
Claim: the row attributes "'Delta with a token is the most efficient way to scan content in SharePoint' (1 RU vs 2 for children paging)" to the scan-guidance page.
Problem: C9 §(a) names this exact misattribution: scan-guidance never compares delta to children paging; the sentence and the 1-vs-2 RU pricing are from the SharePoint throttling reference (avoid-throttling). The completeness clause is correctly from the delta reference.
Fix: "…periodic reconciling delta 'no more than once per day'; the SharePoint throttling reference adds 'Delta with a token is the most efficient way to scan content in SharePoint' (1 RU vs 2 for children paging), and the delta reference is the enumeration that stays complete under concurrent writes".
Evidence: verify/C9.md "The misattribution".

### F10 — MINOR · §4.4 PDF scanned/table-critical row
Claim: "1.3 p/s on an M3 Max: tens of GB of scans is a backfill measured in days on one laptop".
Problem: E:108 gives that figure from Docling's own report with **OCR off** ("225-page set, OCR off: M3 Max 1.27 p/s @4 threads"). The row is the OCR tier; its real throughput is lower and unmeasured, so the "days" estimate is a floor, not the estimate.
Fix: "~1.3 p/s on an M3 Max with OCR *off* (Docling's own report; the OCR-on rate for scans is unmeasured and lower), so tens of GB of scans is a backfill measured in days *at best* on one laptop".
Evidence: E-converters.md:108-109, :253.

### F11 — MINOR · §4.4 `.pptx` row
Claim: "both byte-stable; both emit speaker notes".
Problem: E tested MarkItDown pptx ×3 [tested]; Docling's pptx path was not run (E:19: "MarkItDown is 0-model and byte-stable [tested]"; E:96 marks Docling "batch-sensitive [cited]"). "both byte-stable" is asserted for one measured and one untested converter.
Fix: "MarkItDown byte-stable (measured); Docling's pptx backend is pure-XML and expected stable but was not run; both emit speaker notes".
Evidence: E-converters.md:19, :33-40, :96.

### F12 — MINOR · §4.2 "The locally installed ms365 MCP server"
Claim: "the parameter is dropped with a `logger.warn` at `graph-tools.js:723`".
Problem: B2 cites the range `dist/graph-tools.js:640-726`; in the installed copy (`@softeria/ms-365-mcp-server` 0.143.0) the `logger.warn('Dropping unrecognized parameter …')` line is 725. No report says 723.
Fix: "…dropped with a `logger.warn` (`dist/graph-tools.js:725`, server 0.143.0)".
Evidence: B2-graph-notify-mail-teams.md:44-50; `/opt/homebrew/lib/node_modules/@softeria/ms-365-mcp-server/dist/graph-tools.js:725`.

### F13 — MINOR · §5 "Filename version chaos", first bullet
Claim: "Live counterexample: `Lyft Receipt 3.pdf` and `Lyft Receipt 4.pdf` are different documents, and their `createdDateTime` order is the *inverse* of their client-supplied modified order."
Problem: H records two separate live facts — the Lyft pair are different receipts (H:167, :354) and "two items whose `createdDateTime` order is the inverse of their `fileSystemInfo.lastModifiedDateTime` order" (H:355) — and never says the inverted-clock items are the Lyft receipts. The document welds them into one observation.
Fix: "Live counterexamples: `Lyft Receipt 3.pdf` and `Lyft Receipt 4.pdf` are different documents; separately, two probed items had a `createdDateTime` order that is the *inverse* of their client-supplied modified order."
Evidence: H-version-mess.md:167, :354, :355.

### F14 — MINOR · §3, EDEADLK paragraph
Claim: "claude-code #40783 is that case, read through a Linux-VM sandbox over bindfs".
Problem: C5 narrows the issue's provider: "Google Drive primarily, OneDrive only listed as an also-affected provider". Cited as the OneDrive case without that scope.
Fix: "claude-code #40783 is that case — Cowork's Ubuntu VM sandbox reading a File Provider path over bindfs, Google Drive primarily with OneDrive listed as also affected".
Evidence: verify/C5.md §(c).

### F15 — MINOR · §4.1 #2
Claim: "(measured: identical member bytes, a 2 s difference, container sha differs at exactly four offsets)".
Problem: the four offsets [10, 69, 133, 198] come from C10's two-entry stdlib fixture (one local + one central-directory mod-time field per entry); on the 9-part xlsx the count is 18, and the sentence reads as a property of OOXML.
Fix: "(measured on a two-entry ZIP: identical member bytes, a 2 s difference, container sha differs at exactly four offsets — the 2-byte mod-time field of each entry's local header and central-directory header; on a real 9-part xlsx every entry's `date_time` moved)".
Evidence: verify/C10.md "ZIP-timestamp axis isolated", "openpyxl".

### F16 — MINOR · §2 table, DeepWiki / Devin Wiki row
Claim: "billed per wiki (~20-40 ACUs)".
Problem: A2:110 gives the tiers: Low (default) Free, Medium ~5-10 ACUs, High ~20-40 ACUs. The quoted figure is the High tier only.
Fix: "billed per wiki (Low effort free, Medium ~5-10 ACUs, High ~20-40 ACUs)".
Evidence: A2-deepwiki-indexers.md:18, :110.

### F17 — MINOR · one-screen summary, "What to measure on the corporate tenant"
Claim: "…Microsoft's *default* consent policy excludes exactly those four scopes from what end users may grant".
Problem: only two scopes are named in the sentence, so "those four" is unresolvable to a reader; the four are in C6 §2.
Fix: "…Microsoft's *default* consent policy excludes `Files.Read.All`, `Files.ReadWrite.All`, `Sites.Read.All` and `Sites.ReadWrite.All` from what end users may grant".
Evidence: verify/C6.md §2.

### F18 — MINOR · §4.2 "One cursor per drive"
Claim: "the documented v1.0 delta surface is root-scoped".
Problem: true of the page's HTTP-request list, but the same v1.0 page's SDK snippets and PowerShell cmdlet take a driveItem id (`Drives["{drive-id}"].Items["{driveItem-id}"].Delta`, `Get-MgDriveItemDelta -DriveItemId`), so "undocumented" (B1's wording) overstates it. The design rule is unaffected.
Fix: "the v1.0 reference's HTTP-request list is root-scoped (its own SDK snippets and `Get-MgDriveItemDelta` take a driveItem id), and rclone reports that off-root delta recurses from the root and discards".
Evidence: live v1.0 driveitem-delta page (fetched 2026-09-21, updated_at 2026-06-06), "HTTP request" and Example 1 SDK tabs; B1-graph-drive-delta.md:214.
