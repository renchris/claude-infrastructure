# H — Version mess: Graph version history, filename chaos, dedup, and lineage in /docs

Axis: how the docs-source → docs pipeline survives (a) in-place overwrites, (b) re-uploads with
mangled names, (c) copies, (d) version trimming. Evidence is primary-source except where marked
THEORETICAL. Empirical probes were run read-only against the operator's own **consumer** OneDrive
(`ren.chris@outlook.com`, `driveType: personal`) — labelled CONSUMER-PROBE; ODB/SPO differs in two
places named below and was **not** testable here (no business tenant on this account).

---

## 0. The verdict first

**Graph's version history is a display feature, not a lineage substrate. Do not build on it.**
Three independent facts kill it: `driveItemVersion` carries **no hash** (so "has this version's
content changed" is undecidable without downloading each version); versions are **trimmed by
tenant/site/library policy, permanently, bypassing the recycle bin**; and a **copy** produces an
entirely new item with no history at all. The pipeline must therefore keep *its own*
content-addressed history — which the lead's L5 (`git`-tracked `docs/`) already is. Graph version
history is useful only as a **read-only corroborating witness** for "when did this item's content
change and who did it", and as the thing that tells you a same-name overwrite happened *without a
new item id*.

**The change key is `cTag`, and on a real item it decomposes into `{stable-GUID},content-counter`.**
That is the single most operationally useful thing measured here, and it is not stated in any doc.

**Near-duplicate detection must PROPOSE, never DECIDE.** The best-published thresholds run at
precision ≈0.75 (Manku, web corpus) and collapse to **0.38–0.50 on same-site pairs** (Henzinger) —
and a corporate document library, where every file shares a template, letterhead and client name, is
the same-site case by construction.

---

## 1. Graph version-history capability table

| Capability | Verdict | Evidence |
|---|---|---|
| List versions of a file | YES — `GET /drives/{d}/items/{i}/versions`, newest-first | "Versions are returned in descending order (newest to oldest). The OData `$orderby` query string parameter isn't supported." — [driveitem-list-versions](https://learn.microsoft.com/en-us/graph/api/driveitem-list-versions?view=graph-rest-1.0) |
| Per-version **hash** | **NO** | `driveItemVersion` properties are exactly `content, id, lastModifiedBy, lastModifiedDateTime, publication, size` — no `file` facet, no `hashes`. [driveitemversion](https://learn.microsoft.com/en-us/graph/api/resources/driveitemversion?view=graph-rest-1.0). CONSUMER-PROBE confirms: a live `list versions` returned only `id: "1.0"`, `lastModifiedDateTime`, `size`, `lastModifiedBy`, `@microsoft.graph.downloadUrl`. |
| Per-version **metadata** (columns) | Only via the *list* API, not the *drive* API | `listItemVersion` has a `fields` relationship: "A collection of the fields and values for this version of the list item." [listitemversion](https://learn.microsoft.com/en-us/graph/api/resources/listitemversion?view=graph-rest-1.0). `driveItemVersion` has none. |
| Download a specific version | YES, short-lived URL | "The `@microsoft.graph.downloadUrl` value is a short-lived URL and can't be cached. The URL is only available for a short period of time (1 hour)" — driveitemversion |
| Restore a version | YES, **non-destructive** | "This operation creates a new version with the contents of the previous version, and it preserves all existing versions of the file." → `204 No Content`. [driveitemversion-restoreversion](https://learn.microsoft.com/en-us/graph/api/driveitemversion-restore?view=graph-rest-1.0) |
| Version retention | **Policy-bounded and destructively trimmed** | "When versions exceed the limits set at the library, versions matching the criteria are marked for permanent deletion. This version deletion workflow bypasses the normal recycle bin and the deleted versions can't be recovered from recycle bin." Also: "If time version history limits are configured on a library, the file version expiration date is stamped on a version at creation time." [document-library-version-history-limits](https://learn.microsoft.com/en-us/sharepoint/document-library-version-history-limits) |
| Metadata completeness of old versions | Explicitly incomplete | "OneDrive doesn't preserve the complete metadata for previous versions of a file." — driveitem-list-versions |
| Copy preserves history | Only if asked, and it is a NEW item | "Metadata isn't retained when a **driveItem** is copied, including system metadata and custom metadata. An entirely new **driveItem** is created in the target location instead." / "File versions are only retained when the **includeAllVersionHistory** parameter is explicitly set to `true`." [driveitem-copy](https://learn.microsoft.com/en-us/graph/api/driveitem-copy?view=graph-rest-1.0) |
| `conflictBehavior=replace` on **copy** | **Destroys** the target's history | "The preexisting file item is deleted and replaced with the new item when a conflict occurs… The old item's history is deleted." — driveitem-copy |
| `conflictBehavior` on **upload** | Different default per surface | PUT content: "The default for PUT is *replace*." ([driveitem](https://learn.microsoft.com/en-us/graph/api/resources/driveitem?view=graph-rest-1.0) instance attributes). createUploadSession body: `"@microsoft.graph.conflictBehavior": "fail (default) | replace | rename"` ([driveitem-createuploadsession](https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession?view=graph-rest-1.0)). |
| `rename` conflict behavior | **This is a named generator of filename noise** | "Appends the lowest integer that guarantees uniqueness to the name of the new file or folder" — driveitem-copy |

### 1a. Key question (a) — same-name re-upload: new version, or new item?

**Both, depending on the writer. The distinction is addressing, not naming.**

- `PUT /drives/{d}/items/{item-id}/content` names the item in the URL. Same item id by construction;
  content replaced; a version is added. (Primary: the endpoint form under "To replace an existing
  item", [driveitem-put-content](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0).)
- Path-addressed `PUT …/items/{parent}:/{filename}:/content` with default `replace`, and the browser
  "Replace" upload, resolve by NAME. SharePoint's documented library behaviour is to add the upload
  as a new version of the existing list item (the "Add as a new version to existing files" setting) —
  i.e. item identity is preserved. **SECONDARY** (Microsoft Q&A / community docs, not a normative
  reference page); I could not find a normative Graph sentence asserting id-preservation on the
  path-addressed replace. Treat as *probable, verify per tenant*.
- `POST …/copy?@microsoft.graph.conflictBehavior=replace` is the opposite: the old item is **deleted**
  and a **new item** takes its place, history gone (quoted above). Anything driving a "sync" by
  copy-replace silently destroys lineage.

**Design consequence:** never key the manifest on `(name, path)`. Key it on
`(driveId, itemId)` — the id survives rename and in-place overwrite — and treat the name as a
*mutable attribute*, exactly as the delta doc instructs: "**When using delta you should always track
items by id**." ([driveitem-delta](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0))

### 1b. Key question (b) — are version contents hashable without download?

**No.** Schema has no hash field (§1) and the live probe confirms. The only server-side content
identity is on the **current** item: `file.hashes.quickXorHash`. Therefore:

- "Did the *current* content change since last pull?" → free (cTag / quickXorHash). This is the
  question the pipeline actually needs.
- "Which historical version equals this blob?" → costs one download per version. Do this **never**
  in steady state, and at most once during a one-off backfill of a named high-value family.

### 1c. cTag/eTag decomposition — CONSUMER-PROBE, and the most useful measured fact

Live `GET /drives/{d}/items/{id}?$select=…` on a real PDF returned:

```
"eTag": "\"{6504381E-BE71-4B56-B320-3DC21BA72C36},4\""
"cTag": "\"c:{6504381E-BE71-4B56-B320-3DC21BA72C36},2\""
"file": { "mimeType": "application/pdf",
          "hashes": { "quickXorHash": "/0HsTDb2RYdwWKiZy1b4BezvGxc=" } }
```

Same GUID in both; **different counters** — eTag 4 (metadata + content), cTag 2 (content only), matching
the documented split: "cTag … An eTag for the content of the item. This eTag isn't changed if only the
metadata is changed." / "eTag for the entire item (metadata + content)." (driveitem). So:

- `cTag` counter increments ⇒ **content** changed ⇒ re-convert.
- `eTag` counter increments while `cTag` counter holds ⇒ **rename/move/metadata** only ⇒ update the
  manifest's path field, **do not re-convert, do not re-embed, do not touch the derived page body**.
  This is the whole token-efficiency win on the rename case.
- The GUID is the item identity and is visible even in a projection that omits `id`.

Note the version id sequence is *independent*: the same item showed `versions: ["1.0"]` while its cTag
counter read 2. Do not map version ids to cTag counters.

**ODB/SPO CAVEAT — an unresolved contradiction between two Microsoft docs.** The scan guidance says
"If your processing requires downloading the contents of an individual file, you can use the cTag
property to determine if the contents of the file have changed since the last time you downloaded it."
([scan-guidance](https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/scan-guidance)).
But delta's own Remarks table says that for **OneDrive for Business**, `ctag` is *omitted* on
Create/Modify (and `ctag`,`name` on Delete). So on a business tenant the delta feed may hand you no
cTag at all, and the documented advice is unusable from the feed alone. **Fallback that is safe on
both:** `file.hashes.quickXorHash` + `size`, both present on the item. Delta's omission table does
**not** list `file`/`hashes`, so hashes should survive the feed — *untested on ODB*, and it is the
single highest-value live probe to run on the corporate tenant before committing L1.

### 1d. Two further CONSUMER-PROBE corrections to the docs

- Delta's remark "The `parentReference` property on items won't include a value for **path**" was
  **false** in the observed response — `"path": "/drives/A29C86DED2D9BE1E/root:"` was present. Do not
  build on path being absent *or* present; take the id.
- The `/search` projection returned `file: { mimeType }` with **no hashes**, and returned
  `lastModifiedDateTime: 2025-07-24T19:29:59Z` for an item whose direct `GET` returned
  `19:32:01Z`. Search timestamps are **index-time values**, not item state. Never drive a change
  decision from the search endpoint. (Observed once each; replicate before hardening.)

---

## 2. Filename chaos: normalize against the GENERATORS, not against your imagination

The productive framing: every mangled name has a **producer**, and most producers are documented or
deterministic. Enumerate producers; write one rule per producer; refuse to invent regexes for
patterns with no producer.

| Generator | Signature it leaves | Status |
|---|---|---|
| Graph / OneDrive `conflictBehavior: rename` | "Appends the lowest integer that guarantees uniqueness" → `Report 1.xlsx` | EMPIRICAL (driveitem-copy) |
| Windows Explorer copy-paste | ` - Copy`, ` - Copy (2)`, `Copy of ` | THEORETICAL (ubiquitous Windows behaviour; no normative citation found) |
| Browser/Outlook attachment download collision | `Report (1).xlsx` | THEORETICAL |
| OneDrive sync-client conflict | `Budget-DELL-XPS15.xlsx` — original keeps its name, the later writer gets `-<COMPUTERNAME>` | SECONDARY (consistently reported across MS Q&A + vendor writeups; no learn.microsoft.com normative page found) |
| Humans | `v2`, `_v2`, ` V2`, `final`, `FINAL`, `FINAL2`, `draft`, `rev B`, `(clean)`, `(redline)`, `signed` | THEORETICAL |
| Humans, dated | `2026-09-21`, `20260921`, `21Sep26`, `Sept 2026` | THEORETICAL |

### 2a. Normalization algorithm (THEORETICAL, but each step has a stated falsifier)

```
stem, ext      := splitext(name)
s0             := NFKC(stem); collapse whitespace/underscores/hyphens to single space; casefold
s1             := strip trailing conflict-integer   ^(.*?)[ _-]*[\(\[]?(\d{1,3})[\)\]]?$   → (base, n)
                  ACCEPT the strip ONLY IF a sibling item with stem==base exists in the same folder
                  (or existed, per the manifest's tombstones). Otherwise the integer is CONTENT.
s2             := strip trailing sync-conflict suffix  -<HOSTNAME>  where HOSTNAME matches a token
                  seen as a conflict suffix ≥2 times in this corpus (learn the host list, don't guess)
s3             := extract-and-remove version tokens:  v?\d+(\.\d+)?  |  final\d* | draft | rev [a-z]
                  → version_hint (ordered, but NEVER authoritative — see §4 failure 2)
s4             := extract-and-remove date tokens → date_hint
family_key     := s4 (the residue)
```

Worked examples:

| Input | family_key | version_hint | date_hint | note |
|---|---|---|---|---|
| `Report v2.xlsx` | `report` | `2` | — | |
| `Report_final_FINAL (1).xlsx` | `report` | `final, final` | — | `(1)` stripped **only** because `Report_final_FINAL.xlsx` exists |
| `Report - Copy.xlsx` | `report` | — | — | ` - copy` is a version-neutral token |
| `Q3 Forecast 2026-09-21.pptx` | `q3 forecast` | — | `2026-09-21` | |
| **`Lyft Receipt 3.pdf`** | **`lyft receipt 3`** | **—** | — | **no sibling `Lyft Receipt.pdf` exists ⇒ the 3 is CONTENT, not a version.** Real case from the probed drive: `Lyft Receipt 3.pdf` (1,051,760 B) and `Lyft Receipt 4.pdf` (1,055,899 B) are two different receipts. |

The sibling-existence guard on s1 is what stops the enumerated-siblings catastrophe. It is cheap —
the manifest already has the folder listing — and it is the difference between a correct and a
corpus-destroying normalizer.

---

## 3. Dedup / near-dup: a three-tier ladder, and only tier 1 may decide alone

**Tier 0 — bytes-identical (free, on the raw container).**
`sha256(raw bytes)` equal ⇒ identical file. The asymmetry that matters: *unchanged bytes imply
unchanged content, but changed bytes do NOT imply changed content.* An OOXML file (.docx/.xlsx/.pptx)
is a ZIP whose parts carry save-time metadata (`docProps` revision/editing-time, part ordering,
per-part zip timestamps), so a no-op open-and-save mutates the bytes. Using raw-byte hashes as the
"same document" test therefore mints false "updates". **Use raw-byte hash only as a negative fast
path** ("identical ⇒ skip entirely"). THEORETICAL (mechanism), and it is the reason tier 1 exists.

**Tier 1 — text-identical (the actual dedup key).**
`text_sha256 := sha256(normalize(extracted_markdown))` where `normalize` = strip the converter's own
volatile output (page numbers, extraction timestamps), collapse whitespace, NFKC. Equal ⇒ **exact
duplicate**, decide automatically: one canonical page, the other recorded as an alias. This is the
key the manifest should store and the key `docs/` pages should carry in frontmatter.

**Tier 2 — near-duplicate (PROPOSE ONLY).**
Two published options; take both, because the literature says neither alone is good enough here.

| Method | Parameters with evidence | What it buys |
|---|---|---|
| **Broder shingling / resemblance** | "A contiguous subsequence contained in D is called a shingle… we define its w-shingling S(D,w) as the set of all unique shingles of size w"; AltaVista used **w = 10** words, 40-bit Rabin fingerprints, mod-25 selection. [Broder, SRC-1997-015](https://acberg.com/bigdata/papers/broder_shingling.pdf) | Symmetric resemblance **and** asymmetric **containment** c(A,B) — the only published measure that answers *which* of two docs is the superset |
| **Charikar simhash** | "for a repository of 8B webpages, **64-bit simhash fingerprints and k = 3** are reasonable"; "Choosing k = 3 is reasonable because both precision and recall are near **0.75**." [Manku, Jain, Das Sarma, WWW 2007](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/33026.pdf) | 8 bytes/doc, O(1)-ish lookup; cheap enough to run over the whole corpus on every change |

**The containment insight is the one to build on, and Broder states our exact case:** "resemblance is
not transitive… consecutive versions of a paper might well be 'roughly the same,' but version 100 is
probably quite different from version 1. Nevertheless, the resemblance distance … is a metric and
obeys the triangle inequality." ⇒ **Chain lineage pairwise between adjacent candidates; never
transitively cluster a family.** A union-find over "similar" pairs (what Broder's own web clustering
did) will merge v1 with v100 and with an unrelated doc that shares the template. Broder's own caveat
applies too: "the estimation of the containment of very short documents into substantially larger
ones is rather error prone due to the paucity of samples" — so suppress containment verdicts below a
minimum shingle count.

**Tier 3 — embedding cosine.** Ruled out as a decider: corpus-dependent thresholds, per-document cost,
and it cannot distinguish "same document, edited" from "different document, same template" any better
than simhash does on the same-site case. Keep as a tie-breaker the agent may consult, never as an
automatic edge.

### 3a. The adversarial number that governs the whole design

Henzinger (SIGIR 2006, 1.6B pages) evaluated exactly these two algorithms: **"neither of the algorithms
works well for finding near-duplicate pairs on the same site, while both achieve high precision for
near-duplicate pairs on different sites"**, with same-site precision **0.50 (Charikar) vs 0.38
(Broder)**; a *combined* algorithm (Broder candidates filtered by a Charikar threshold) reaches
**precision 0.79 at 79% of the recall**. [dblp](https://dblp.org/rec/conf/sigir/Henzinger06.html) /
[Semantic Scholar](https://www.semanticscholar.org/paper/b6f3576c31ee197afcc91ae7ef23c82eab41aad5)
— *numbers via search-result abstract; the PDF was not retrievable, so treat as SECONDARY-quoted.*

A corporate document library **is** the same-site case: one template, one letterhead, one client name,
recycled boilerplate sections. THEORETICAL transfer, but the mechanism (shared chrome dominating the
shingle set) is identical. Two consequences, both binding:

1. **Strip the chrome before fingerprinting.** Drop headers/footers, cover pages, legal boilerplate,
   and any n-gram appearing in >X% of the corpus, *then* shingle. This is the document-world analogue
   of main-content extraction, which the literature finds materially changes near-dup outcomes.
2. **Adopt Henzinger's combination, not one algorithm.** Broder generates candidates (recall), simhash
   filters them (precision). Even then, 0.79 precision means ~1 in 5 proposed lineage edges is wrong —
   which is exactly why tier 2 output goes to a review queue, not to the page.

### 3b. How SharePoint itself does it — prior art, not an API

SharePoint's own duplicate trimming is shingling, and its internals are deliberately opaque:
"The Document stream – content text only (no titles, no filenames, no metadata, no urls) is broken
into what are known as minima. The exact number of minima is Microsoft confidential… Each group of
chunks is then hashed into a larger chunk known as a supershingle. One or more supershingles are then
hashed together to produce a megashingle… If more than one hash is the same for two given documents
then those are said to be near duplicates… The key point is that we are looking for NEAR DUPLICATES,
not exact duplicates. Note: megashingle hash values = DocumentSignature"
([archived MS blog](https://learn.microsoft.com/en-us/archive/blogs/fesiro/sharepoint-2013-search-near-duplicates-and-documentsignature)).
Two design lessons, one warning:

- **Lesson:** it fingerprints **content text only — no titles, no filenames, no metadata, no URLs.**
  Our tier-1/tier-2 keys should do the same (which the "hash the extracted markdown, not the
  container" rule already achieves).
- **Lesson:** it is a *grouping/collapse* feature with a keep-count, not a delete:
  `TrimDuplicatesKeepCount`, `TrimDuplicatesIncludeId` to retrieve the collapsed set, and
  `CollapseSpecification` as the modern form ("In SharePoint, use **CollapseSpecification** wherever
  possible. **TrimDuplicatesOnProperty** is available for backward compatibility only.")
  ([customizing-search-results](https://learn.microsoft.com/en-us/sharepoint/dev/general-development/customizing-search-results-in-sharepoint)).
  **Collapse, never delete** — which is precisely the `/docs` lineage policy proposed in §4.
- **Warning:** not usable as a pipeline component. Graph exposes only a boolean —
  `trimDuplicates`, "only supported on files hosted in SharePoint. The default value is `false`"
  ([search-concept-trim-duplicate](https://learn.microsoft.com/en-us/graph/api/search-concept-trim-duplicate))
  — and no retrievable, stable DocumentSignature. Its *existence* is the strongest available evidence
  that shingling-over-text is the right family of answer for Office documents.

Golden examples of the "resolve a duplicate group by policy" step, already shipped:
- **`rclone dedupe`**: "Files are identical if they have the same file path and the same hash";
  `--dedupe-mode` ∈ {interactive, skip, first, newest, oldest, largest, smallest, rename, list}, where
  `skip` "removes identical files, leaves other duplicates untouched"
  ([rclone dedupe](https://rclone.org/commands/rclone_dedupe/)). Our policy is `skip` for tier 1 and
  `interactive`(→queue) for tier 2 — never `newest`, for the reason in §4 failure 2.
- **`git` rename detection**: models a rename as a delete/add pair rescued by similarity —
  "The default similarity index is 50%"; "The similarity index is the percentage of unchanged lines…
  The similarity index value of 100% is thus reserved for two equal files"; `-M100%` limits detection
  to exact renames ([git-diff](https://git-scm.com/docs/git-diff)). Git deliberately scopes detection
  to files changed *in the same changeset* by default (`--find-copies-harder` is the opt-in, "a very
  expensive operation"). **Adopt both**: scope lineage matching to the change-set window plus the
  normalized family, not to the whole corpus, and keep 50% as the defensible starting threshold with
  100% (exact) as the only auto-decidable one.

---

## 4. Lineage representation in `/docs` (proposal)

Design constraints: the agent reads `/docs` by grep and by opening files; it must never be able to
read a superseded page without seeing that it is superseded; and the record of *why* two files were
linked must be inspectable and reversible.

**(i) One derived page per source item — never per family.** Path is stable across renames because it
is derived from the family key, not the filename: `docs/<area>/<family-slug>--<version-label>.md`.

**(ii) Frontmatter is the manifest row.**

```yaml
source:
  drive_id: b!…
  item_id:  01ABC…            # stable across rename AND in-place overwrite
  guid:     6504381E-…        # the GUID inside eTag/cTag; second witness to identity
  path:     /Shared Documents/Clients/Acme/Report v2.xlsx
  name:     Report v2.xlsx
  ctag:     'c:{6504381E-…},2'   # content counter — re-convert iff this moves
  etag:     '{6504381E-…},4'     # metadata counter — path-only update iff only this moves
  quick_xor: /0HsTDb2RYdwWKiZy1b4BezvGxc=
  size:     1055899
  svc_modified: 2025-07-24T19:32:01Z   # driveItem.lastModifiedDateTime  (service clock)
  cli_modified: 2025-07-24T19:29:59Z   # fileSystemInfo.lastModifiedDateTime (client clock)
  versions_count_at_capture: 1
content:
  bytes_sha256: …            # negative fast path only
  text_sha256:  …            # THE dedup key
  simhash64:    0x…
lineage:
  family:        acme-report
  status:        superseded            # latest | superseded | alias-of | disputed
  supersedes:    [acme-report--v1]
  superseded_by: acme-report--v3
  basis:         text_sha256-equal | containment=0.94,simhash_hd=2 | human
  decided_by:    auto | agent | operator
  decided_at:    2026-09-21
```

**(iii) A superseded page is never deleted and never silently kept.** Line 1 of its body is a
machine- and grep-visible banner:

`> SUPERSEDED 2026-09-21 by [acme-report--v3](./acme-report--v3.md) — basis: containment 0.94. Do not cite.`

Deleting loses the ability to answer "what did the previous version say"; keeping it unmarked poisons
retrieval, which is the failure the whole `/docs` idea exists to avoid.

**(iv) One family file, and it is the lineage table.** `docs/<area>/_family/<family>.md`:

| label | source name | item_id | cli_modified | svc_modified | size | text_sha (8) | relation to prev | status |
|---|---|---|---|---|---|---|---|---|
| v1 | Report.xlsx | 01AB… | 2026-03-02 | 2026-03-02 | 410 K | `a91f…` | — | superseded |
| v2 | Report v2.xlsx | 01AB… | 2026-06-11 | 2026-06-11 | 455 K | `c3d0…` | edit-of v1 (cont. 0.94) | superseded |
| v2b | Report_final_FINAL (1).xlsx | 01CD… | 2026-06-11 | 2026-08-02 | 455 K | `c3d0…` | **exact dup of v2** | alias-of v2 |
| v3 | Report v2 SIGNED.pdf | 01EF… | 2026-08-30 | 2026-08-30 | 460 K | `77ba…` | edit-of v2 (cont. 0.99) | **latest** |

Same `item_id` across v1/v2 ⇒ in-place overwrite (one item, two cTags). Different `item_id` with
identical `text_sha` ⇒ a re-upload or copy. Both are visible in one table, which is the point.

**(v) `docs/_lineage/DISPUTED.md` is the work queue.** Every tier-2 proposal that did not clear the
auto thresholds lands here with its two candidates, its scores, and the one-line question the agent
or human must answer. The queue being a tracked file means "what is unresolved" is a `git diff`, and
an unresolved item can never quietly become a resolved one.

**(vi) The durable version history is `git log docs/`, not SharePoint.** This is forced by the
trimming quote in §1: a version policy can permanently delete the upstream evidence, bypassing the
recycle bin. Once a source revision has been converted and committed, the pipeline owns the only copy
of that revision's *text* that is guaranteed to persist.

---

## 5. Failure modes

| # | Failure | Detector | Response |
|---|---|---|---|
| 1 | **Two different documents share a stem** (`Lyft Receipt 3/4.pdf`, observed live) | trailing integer with **no** un-suffixed sibling; text_sha differs; containment low | Do not strip the integer — it is content. Separate families. |
| 2 | **A "v2" that is actually older** | `cli_modified` (client clock, user-supplied) vs `svc_modified` (service clock) disagree in order; or version_hint order contradicts both. Documented: "The values on the DriveItem resource are the created and modified date and time as seen from the service. The values stored in the **FileSystemInfo** resource are provided by the client" and "if a file was created on the device on Monday, but not uploaded to the service until Tuesday… the created date for the item will reflect Tuesday" ([fileSystemInfo](https://learn.microsoft.com/en-us/graph/api/resources/filesysteminfo?view=graph-rest-1.0)). Observed live: two items whose `createdDateTime` order is the **inverse** of their `fileSystemInfo.lastModifiedDateTime` order. | **Never order a family by filename tokens, and never by a single clock.** Order by containment direction (v_new contains v_old) with the two clocks as corroboration; disagreement ⇒ DISPUTED, not a guess. |
| 3 | **Template boilerplate inflates similarity** (Henzinger same-site, precision 0.38–0.50) | corpus-frequency of the matching shingles is high | Strip corpus-common n-grams before fingerprinting; require the *distinctive* residue to match; combine Broder+simhash (0.79). |
| 4 | **Upstream version trimming erases the evidence** | `versions_count_at_capture` drops between pulls; or a library switches to Automatic limits | Nothing recoverable upstream — the committed `docs/` history is the record. Log the drop; never re-derive lineage from a trimmed history. |
| 5 | **A copy looks like a brand-new document** — new item id, fresh `createdDateTime`, no history ("An entirely new **driveItem** is created") | text_sha equal to an existing page (tier 1) | Mark `alias-of`; never emit a second page. |
| 6 | **Restore-version replays an old hash** ("creates a new version with the contents of the previous version") | incoming text_sha matches an **ancestor** in the family | Emit `reverted-to: v_n`; do not create v_{n+1} as novel, and do not loop. |
| 7 | **cTag missing on ODB delta** (§1c contradiction) | cTag absent in feed | Fall back to `quickXorHash`+`size`; if hashes are also absent, per-item GET for changed ids only. **Probe this first on the corporate tenant.** |
| 8 | **`conflictBehavior=replace` on copy destroys the target's history** | item_id changed while path+name held | Treat as a delete+create pair, warn loudly; any sync tool doing this to `docs-source` is unsafe. |
| 9 | **Search-endpoint timestamps are index-time** (observed: 19:29:59 vs 19:32:01 for one item) | — | Never read change state from `/search`. Use delta + per-item GET. |
| 10 | **quickXorHash is not collision-resistant** — "A quick, simple non-cryptographic hash algorithm that works by XORing the bytes in a circular-shifting fashion" ([quickXorHash](https://learn.microsoft.com/en-us/onedrive/developer/code-snippets/quickxorhash)), 160-bit, length XOR'd in | — | Use it only as an *equality hint against the server's own value*; the canonical content address stays a local SHA-256. |

---

## 6. Alternatives considered and ruled out

- **Make SharePoint version history the lineage store.** Ruled out: no per-version hash, destructive
  trimming outside the recycle bin, incomplete old-version metadata, and copies carry none of it.
- **Use `trimDuplicates` / `DocumentSignature` as the dedup engine.** Ruled out: query-time only,
  SharePoint-hosted files only, signature not retrievable as a stable value, internals "Microsoft
  confidential". Kept as prior art (§3b).
- **Order families by filename version tokens.** Ruled out by failure 2 and by the `Lyft Receipt`
  counterexample.
- **Embedding cosine as the near-dup decider.** Ruled out (§3, tier 3).
- **Raw-byte SHA as the "same document" key.** Ruled out — OOXML containers churn on save; kept as a
  one-way negative fast path.
- **Auto-resolving duplicate groups by `newest`** (rclone's mode, tempting and cheap). Ruled out by
  failure 2 — "newest" is only well-defined once you have picked a clock, and the two clocks disagree.

## 7. Blockers / what is not established

1. **ODB delta payload shape** — does a business-tenant delta carry `file.hashes` when it omits `ctag`?
   Untestable on this account (consumer only). This decides whether L2's change key is cTag or
   quickXorHash. **Run this probe first.**
2. **Item-id preservation on path-addressed `replace` and on browser "Replace" upload** — probable,
   documented only at the SharePoint-behaviour level, no normative Graph sentence found.
3. **Henzinger's precision figures** are quoted from abstract-level secondary sources; the PDF was not
   retrievable through the available fetchers. The *direction* (same-site is where these algorithms
   fail) is stated consistently across sources; the exact 0.38/0.50/0.79 should be re-verified before
   being cited to anyone outside the team.
4. **Near-dup thresholds for Office-document text are unmeasured here.** k=3/64-bit and 50% similarity
   are borrowed constants (web pages; git source lines). They must be calibrated against a labelled
   sample of the actual `docs-source` corpus before any edge is auto-accepted; until then every tier-2
   edge goes to DISPUTED.
5. **Enterprise-search vendor dedup practice** (Glean/Coveo/Elastic) — searched, returned only
   marketing comparisons. No primary evidence obtained; no claim made.
6. Two CONSUMER-PROBE observations (delta `parentReference.path` present; search timestamps stale) are
   single observations and should be replicated before being hardened into rules.
