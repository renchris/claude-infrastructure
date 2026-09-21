# F — Incremental / diff-only ingestion: how the mature frameworks actually do it

Axis: **reusable mechanisms for "process only the diff"**, read from primary sources (framework source
code, vendor API reference, connector source). Verdict first, then the table, then the patterns to
steal with the failure each one prevents, then the adversarial pass.

---

## Verdict

**The lead's L1→L5 hypothesis is the shape every mature system converges on, and the one thing it is
missing is the part every mature system pays for separately: a periodic full ID-only listing whose
only job is to find deletions.** Not one of the frameworks surveyed propagates a vanished source
document from its incremental path alone. LangChain's `incremental` mode cannot
(documented: "the `incremental` and `scoped_full` mode will not"). Onyx *receives* Graph's delete
tombstones and **throws them away** (`drive_items.py:639`), then recovers deletes from a separate
`prune` job that diffs `all_indexed_document_ids - all_connector_doc_ids.keys()`. Glean's model is
the inverse and the most honest: the bulk endpoint **is** the reconcile, and it ships a 20%
circuit-breaker because a truncated source listing would otherwise wipe the corpus. Airbyte states
the limit outright: standard incremental does not propagate deletes; that needs CDC.

Second load-bearing finding, and it kills a naive `/docs/<mirrored path>.md` scheme: Graph delta
**does not return the descendants of a renamed folder**, and tells you so — *"renaming a folder
doesn't result in any descendants of the folder being returned from delta. **When using delta you
should always track items by id**"*. A path-keyed mirror silently strands an entire subtree on one
rename. The manifest must be keyed on `driveItem.id` with path as a *derived, mutable* attribute.

Third: the cheapest correct "did the bytes change" test is **`file.hashes.quickXorHash`**, not `cTag`
— even though the scan-guidance page recommends cTag — because delta omits `ctag` for OneDrive for
Business on create/modify.

---

## Table

| Framework | Dedup key | How updates are detected | How deletes propagate | Granularity | Evidence |
|---|---|---|---|---|---|
| **LangChain indexing API** | The document's **id IS the hash** of `page_content` + JSON-serialised `metadata` (sha1→uuid5 default; sha256/sha512/blake2b/callable) | `record_manager.exists([doc.id])`; a hit ⇒ skip, only the `updated_at` timestamp is refreshed. No hit ⇒ new id ⇒ write | `incremental`: after each batch, `list_keys(group_ids=source_ids, before=index_start_dt)` → delete. `full`: same with `group_ids=None` over the whole namespace. **A vanished source is only caught by `full`** | **Chunk** (post-split; the hash is computed on whatever documents you hand `index()`) | [api.py](https://raw.githubusercontent.com/langchain-ai/langchain/master/libs/core/langchain_core/indexing/api.py) L157-231 (hash), L505-600 (skip/delete); [how-to](https://github.com/langchain-ai/langchain/blob/langchain%3D%3D0.3.27/docs/docs/how_to/indexing.ipynb) |
| **LangChain `SQLRecordManager`** | `(key, namespace)` unique | — | — | — | `upsertion_record` table: `uuid` PK, `key`, `namespace` (NOT NULL), `group_id` (nullable), `updated_at` Float; `UniqueConstraint("key","namespace")` + `Index("ix_key_namespace")`. [source](https://raw.githubusercontent.com/langchain-ai/langchain/langchain==0.3.27/libs/langchain/langchain/indexes/_sql_record_manager.py) L53-82 |
| **LlamaIndex `IngestionPipeline`** | `doc_id` (`node.ref_doc_id or node.id_`) → `doc_hash` in the docstore's metadata collection | `get_document_hash(ref_doc_id) != node.hash` ⇒ `delete_ref_doc()` + `vector_store.delete(ref_doc_id)` then re-run all transformations. Equal ⇒ `continue` | Only under `UPSERTS_AND_DELETE`: `existing_doc_ids_before - doc_ids_from_nodes`, then `delete_document` + `vector_store.delete` | **Document** — one changed paragraph deletes and re-embeds *every chunk of that document* | [pipeline.py](https://raw.githubusercontent.com/run-llama/llama_index/main/llama-index-core/llama_index/core/ingestion/pipeline.py) L242-259 (enum), L469-506 (`_handle_upserts`) |
| **LlamaIndex transformation cache** | `get_transformation_hash(nodes, transform)` | separate from dedup: "each node + transformation combination is hashed and cached" | n/a | node × transform | pipeline.py L58-108 |
| **Onyx (ex-Danswer) SharePoint/OneDrive** | Graph `driveItem.id`; document id per drive item | `GET /drives/{id}/root/delta`, cursor = **URL-encoded ISO timestamp** in `?token=`, not the opaque deltaLink. 410 Gone ⇒ full delta re-enumeration. Per-page checkpoint stores the `@odata.nextLink` | **Not from delta** — tombstones are filtered out. A separate Celery `prune` task on `prune_freq` enumerates slim (ID-only) docs and deletes `all_indexed_document_ids - all_connector_doc_ids.keys()` | Document | [drive_items.py](https://raw.githubusercontent.com/onyx-dot-app/onyx/main/backend/onyx/connectors/microsoft_utils/drive_items.py) L633-641, L698-786; [sharepoint/connector.py](https://raw.githubusercontent.com/onyx-dot-app/onyx/main/backend/onyx/connectors/sharepoint/connector.py) L1060-1093; [pruning/tasks.py](https://raw.githubusercontent.com/onyx-dot-app/onyx/main/backend/onyx/background/celery/tasks/pruning/tasks.py) L690-705 |
| **Glean indexing API** | datasource + document id, grouped by `uploadId` | `/indexdocuments` for incremental upserts | **Bulk-replace**: *"The bulk upload endpoints delete all entries that are not a part of the most recent upload."* Async, after `isLastPage`. Guard: removals pause 7 days if deletions would exceed 20% of previously indexed docs, overridable with `disableStaleDocumentDeletionCheck` | Document | [bulk-upload-model](https://developers.glean.com/api-info/indexing/documents/bulk-upload-model) |
| **Unstructured Platform** | source path + file **version** | "Reprocess All" unchecked ⇒ only new files, or files whose *version* changed since the last run | not documented as automatic | File | [docs.unstructured.io](https://docs.unstructured.io/) — see confidence note below |
| **Airbyte incremental append+dedup** | primary key (or composite); ordering by **cursor field** | cursor field = *"the property in the record that defines when the record was last updated"*; dedup keeps "the latest de-duplicated data row" per PK | **It does not.** *"Delete operations are not propagated correctly with standard incremental sync"* — deletes require CDC (Debezium), where deletions "are correctly transmitted… because they are logged just like any other modification" | Record | [incremental-append-deduped](https://docs.airbyte.com/platform/using-airbyte/core-concepts/sync-modes/incremental-append-deduped) |
| **Microsoft Graph driveItem delta** (the substrate) | `driveItem.id` | `@odata.deltaLink` replayed; or `?token=<URL-encoded ISO timestamp>` (**ODB/SharePoint only**); `?token=latest` to get a cursor without an initial crawl | `deleted` facet: *"Items with this property set should be removed from your local state"* | Item | [driveitem-delta](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0) |
| **Cursor codebase index** | per-file SHA-256 rolled into a **Merkle tree** (folder hash = hash of children) | client and server compare tree roots and walk only diverging branches: *"Entries whose hashes differ get synced. Entries that match are skipped."* | implied by tree divergence | File → chunk | [cursor.com/blog/secure-codebase-indexing](https://cursor.com/blog/secure-codebase-indexing) |
| **rclone `--onedrive-delta`** | path + quickXorHash | delta listing for recursive lists; QuickXorHash is the default hash for all OneDrive backends since 1.62 | n/a (sync semantics) | File | [rclone.org/onedrive](https://rclone.org/onedrive/) |

---

## The four key questions, answered

### (a) How do they avoid re-embedding unchanged chunks when one paragraph changes?

**Only two of the surveyed systems actually do.** The discriminator is *where the hash is computed*.

- **LangChain hashes AFTER chunking**, and the hash *is* the vector-store id. So an inserted
  paragraph produces new ids for the chunks it touched; every other chunk keeps its id, `exists()`
  returns True, and `record_manager.update(uids_to_refresh, …)` bumps only a timestamp — the
  embedding call never happens (api.py:505-528). The how-to states the goal in those words: *"Avoid
  re-computing embeddings over unchanged content."*
- **Cursor** does it at two levels: Merkle tree to find changed *files*, then (secondary sources
  only) a content-hash-keyed embedding cache so unchanged chunks reuse embeddings.
- **LlamaIndex does NOT.** `_handle_upserts` compares one hash per `ref_doc_id`; on mismatch it calls
  `delete_ref_doc(ref_doc_id)` and `vector_store.delete(ref_doc_id)` and re-runs the whole
  transformation chain. Its `IngestionCache` (`node + transform` hash) recovers some of this, but the
  *node* it keys on is the changed document, so the cache misses for that document entirely.
- **Airbyte / Onyx / Glean / Unstructured** are all document- or record-granular. A one-word change
  re-processes the whole file.

**Design implication for /docs:** the diff must be computed at the *markdown page* level, and the
page boundary should be the unit a human edit naturally touches (one source doc → one page, or one
section → one page). A converter that renumbers or re-paginates the whole document on any edit
destroys chunk-level reuse no matter which framework sits downstream.

### (b) A document that disappears from the source — tombstone or delete?

Three distinct answers, and the operator's pipeline needs the third:

1. **True tombstone, pushed by the source** — Graph's `deleted` facet. Free, exact, arrives in the
   same delta page as updates. Requires the `Prefer: deltashowremovedasdeleted` header in the
   permissions-scanning configurations. **This is the best available and Onyx discards it.**
2. **Absence-from-a-full-listing** — Glean's bulk-replace, Onyx's prune, LangChain's `full`. Exact,
   but costs a full enumeration and is catastrophic if the enumeration is truncated (hence Glean's
   20% breaker and LangChain's warning that `full` mode *"Any documents that are not passed into the
   indexing function and are present in the vectorstore will be deleted!"*).
3. **Never** — Airbyte standard incremental, LangChain `incremental`/`scoped_full`, Unstructured.

### (c) The record-manager schema

LangChain's is the only one published as a table, and it is deliberately tiny:

```
upsertion_record
  uuid       String  PK, indexed, default uuid4
  key        String  indexed            -- the document content+metadata hash
  namespace  String  indexed, NOT NULL  -- e.g. "chromadb/my_docs"
  group_id   String  indexed, nullable  -- the SOURCE id (the join to "which file produced this")
  updated_at Float   indexed            -- server-side clock
  UniqueConstraint(key, namespace); Index(key, namespace)
```

The `RecordManager` interface is six methods: `create_schema`, `get_time`, `update(keys, *, group_ids,
time_at_least)`, `exists(keys) -> list[bool]`, `list_keys(*, before, after, group_ids, limit)`,
`delete_keys(keys)`. Two contract details matter more than the columns:

- `get_time()` is documented as *"Get the current server time… It's important to get this from the
  server to ensure a monotonic clock, otherwise there may be data loss when cleaning up old
  documents!"*
- `time_at_least` exists *"to help prevent time-drift issues since time may not be monotonically
  increasing!"*

Because deletion is `list_keys(before=index_start_dt)`, **the whole design rests on one comparison
against a clock**, which is why the docs carry an explicit Caution: *"If two tasks run back-to-back,
and the first task finishes before the clock time changes, then the second task may not be able to
clean up content."*

LlamaIndex's equivalent is a two-collection KV store: `<namespace>/data` for nodes and
`<namespace>/metadata` holding `{"doc_hash": …}` per doc id, with `get_all_document_hashes()`
returning the map **hash → doc_id** (keyval_docstore.py:651-658).

### (d) Graph delta vs periodic full listing — who uses which, and why

| | Uses | Why |
|---|---|---|
| **Graph delta, opaque deltaLink** | Microsoft's own recommendation: *"Always remember to keep the URL returned by @odata.deltaLink"*; and *"Clients should use the deltaLink provided by delta queries when possible, rather than generating their own token."* | O(changes); tombstones included; the *only* enumeration MS guarantees is complete — *"Other approaches, such as paging through the children collection of a folder, are not guaranteed to return every single item if any writes take place during the enumeration."* |
| **Graph delta, timestamp token** | **Onyx** (`token=quote(start.isoformat(timespec="seconds"))`) | The connector framework already carries a `(start, end)` poll window, so a timestamp cursor needs no extra persisted state and cannot 410 from staleness. Cost: MS supports it **only on OneDrive for Business and SharePoint**, and advises against it when a deltaLink is available. |
| **Periodic full listing** | Glean (bulk), Onyx (prune), LangChain (`full`) | It is the only way to observe *absence*. Onyx gates it behind `prune_freq` for exactly that reason. |
| **Webhooks + delta** | MS's recommended pattern | *"Polling the service repeatedly or at high rates causes your app to be throttled due to excessive calling patterns."* Drives support the `update` change type; MS recommends *"a periodic delta query… no more than once per day"* as the safety net, and *"using delta query with your last change token immediately after you subscribe to webhooks"* to close the gap between crawl and subscription. |

---

## Patterns to steal, and the failure each prevents

1. **Make the content hash the primary key, not a column beside it.** (LangChain: `Document(id=hash_, …)`.)
   *Prevents:* the update path and the dedup path disagreeing. If the id is independent of content,
   "has this changed?" is a second lookup that can be wrong; if the id *is* the content, an unchanged
   item is a cache hit by construction and there is no state to get stale.
   *Pipeline slot:* L2 manifest — key markdown pages by `sha256(rendered markdown)`.

2. **Carry a `group_id` / `source_id` on every derived record.** (LangChain `group_ids=source_ids`; the
   how-to: *"if these documents are representing chunks of some parent document, the `source` for both
   documents should be the same and reference the parent document."*)
   *Prevents:* the orphan-chunk failure. Without it, a shrinking source (v2 of the deck has 30 slides,
   not 40) leaves ten stale pages that no delete can ever find, because nothing records that they
   came from that file.
   *Pipeline slot:* L3 provenance frontmatter, and it must be the **immutable source id**, not the path.

3. **Two cadences, two mechanisms: delta for content, ID-only full listing for deletion.** (Onyx
   `poll` + `prune`; MS webhooks + a daily delta; Glean incremental + bulk.)
   *Prevents:* both halves of the obvious trap — a delta-only pipeline that never notices deletions,
   and a full-listing pipeline that re-reads 200 GB to learn that nothing changed. The ID-only listing
   is cheap precisely because it fetches no content (`$select=id` + the hash field).
   *Pipeline slot:* L1 acquisition (delta) + a weekly L2 reconcile.

4. **A stale-deletion circuit breaker on the reconcile.** (Glean: pause removals 7 days if they exceed
   20% of the corpus; `disableStaleDocumentDeletionCheck` to override.)
   *Prevents:* the single worst failure available to this architecture. A OneDrive sync client that has
   not finished hydrating, an interrupted delta enumeration, a 429 storm that truncates a page — each
   produces a *short but syntactically valid* listing, and an unguarded reconcile reads it as "the team
   deleted 8,000 files" and empties `/docs`. This is the pattern most worth copying verbatim.
   *Pipeline slot:* L2, as a hard gate before any delete is written.

5. **Refuse to run the incremental modes without a source key.** (LangChain raises
   `ValueError("Source id key is required when cleanup mode is incremental or scoped_full.")` and again
   per-document if any `source_id` is None.)
   *Prevents:* a pipeline that silently degrades to append-only. A missing provenance field is a
   *configuration* error that manifests months later as duplicate content, so it must fail at call time.
   *Pipeline slot:* L3 converter contract — a page without `source_id` in frontmatter is a build failure.

6. **Track items by immutable id; treat path as derived state.** (Graph: *"When using delta you should
   always track items by id"*; delta returns no `path` on `parentReference`.)
   *Prevents:* the folder-rename subtree strand. Also gives same-name-overwrite detection for free, and
   makes "messily re-uploaded as `Deck v3 FINAL.pptx`" a *new item* that the manifest can link to its
   predecessor by `(parent id, name-stem)` rather than a mystery.
   *Pipeline slot:* L2 manifest keyed `driveItemId → {path, quickXorHash, size, lastModified, pageIds[]}`.

7. **Ask the server for the content hash before downloading.** `file.hashes.quickXorHash` is *"A
   proprietary hash of the file that can be used to determine if the contents of the file change"* and
   is *"the only value that is guaranteed to be available for both OneDrive for work or school and
   OneDrive for home."*
   *Prevents:* downloading a 40 MB deck to discover only its `lastModifiedDateTime` moved (an
   open-and-save with no edit, a metadata/permission change, a sync-client touch). At the operator's
   volume this is the difference between a diff pass costing MBs and costing GBs.
   *Pipeline slot:* L1 → L2 boundary. **Do not use `cTag` for this** despite the scan-guidance
   recommendation — see adversarial pass.

8. **Checkpoint mid-enumeration, at page granularity.** (Onyx stores `current_drive_delta_next_link`
   and `seen_document_ids` in a resumable checkpoint; Glean's `uploadId` + `isFirstPage`/`isLastPage`
   with `forceRestartUpload`.)
   *Prevents:* a throttled or crashed pass costing the whole window, and — worse — a *partial* pass
   being mistaken for a complete one by the reconcile. An explicit "this upload is not finished" flag is
   what lets the breaker in (4) stay armed.

9. **A per-item time window that attributes each change to exactly one pass.** (Onyx uses
   `max(createdDateTime, lastModifiedDateTime)` and documents the reason: *"a file copied or synced into
   a drive keeps its original modification date, which can predate the window even though the file is
   new to the drive"*, with the next window starting `POLL_CONNECTOR_OFFSET` before this one ends.)
   *Prevents:* the drag-and-drop miss — the exact manual-inbox case the operator described. A file
   dropped into `docs-source` carries its *old* mtime and a window filter on mtime alone never sees it.

10. **Accept and absorb duplicate emission; never assume the cursor is exclusive.** (Graph: *"The same
    item may appear more than once in a delta feed… You should use the last occurrence you see"*; Airbyte:
    *"It is acceptable for sources to re-send some data when ran incrementally."*)
    *Prevents:* double-writing a page, or worse, a converter that appends. Every L3 converter must be
    **idempotent on (source id, content hash)** — which pattern 1 gives for free.

---

## Adversarial pass (integrated)

**The metadata trap in LangChain's hash — this is the one that will bite the operator's design.**
The id is `hash(hash(page_content) + hash(json.dumps(metadata, sort_keys=True)))` (api.py:213-223).
The L3 plan puts *provenance frontmatter* on every page. If that frontmatter contains anything
positional or temporal — `chunk_index`, `page_number`, `converted_at`, `source_mtime`, a version
suffix — then inserting one paragraph changes the metadata of **every** chunk after it, every id
changes, and the chunk-level reuse that motivated the whole design evaporates. Empirical, from the
hash source. *Mitigation:* the hashed payload carries only `source_id` (stable) and content; volatile
provenance lives in a sidecar the manifest owns, not in the chunk metadata. And note the docstring's
own warning, which makes this irreversible: *"When changing the key encoder, you must change the index
as well to avoid duplicated documents in the cache."*

**`cTag` is the documented recommendation and the wrong choice here.** The scan-guidance page says *"you
can use the cTag property to determine if the contents of the file have changed since the last time you
downloaded it."* The delta reference then states that for **OneDrive for Business**, delta query omits
`ctag` on Create/Modify (and omits `ctag`, `name` on Delete). So the property the best-practices page
tells you to key on is absent from the feed the same page tells you to use. Use `quickXorHash`. Two
Microsoft pages, in conflict; resolved by reading the omission table.

**Onyx is a good architecture and a bad thing to copy line-for-line.** `_delta_item_is_indexable`
returns False for any item carrying the `deleted` facet — *"Folders and tombstones carry no content, so
only files in window index."* True of *content*, and it throws away the free, exact delete signal. The
consequence is structural: a file deleted from SharePoint stays in the index until `prune_freq` elapses
and a full slim enumeration runs. For `/docs`, consume the tombstone in the same pass.

**LlamaIndex `UPSERTS_AND_DELETE` has a latent correctness bug worth knowing before adopting it.**
`existing_doc_ids_before = set(self.docstore.get_all_document_hashes().values())` — and that map is
keyed by **hash**, so two documents with byte-identical content collapse to a single entry. The
duplicate's `doc_id` is then absent from `existing_doc_ids_before`, and the delete set is computed over
an incomplete "before" population. (Theoretical, derived from pipeline.py:495-500 +
keyval_docstore.py:651-658; the direction of the error is "a stale doc is not deleted", not "a live doc
is".) Two identical boilerplate cover pages in a corporate corpus is not an exotic input.

**"Same-name re-upload" is not one case, it is three, and only one framework documents all three.**
Unstructured: unchecked Reprocess All processes new files and files whose *version* changed; *"a renamed
file is always treated as a new file, regardless of whether the file's original contents have changed"*;
and *"a file that is removed but is added back later with the same file name is processed on future runs
only if the file's contents have changed."* Under a content-addressed manifest all three fall out
correctly — rename = same hash, new path (a manifest path update, no re-convert); re-upload of identical
bytes = no-op; re-upload of changed bytes = one page rewrite. This is the strongest single argument for
L2 being content-addressed rather than mtime- or version-addressed.

**Cursor is a golden example for the mechanism and a weak one for the citation.** The Merkle tree,
root comparison and skip-on-match are in Cursor's own blog, verbatim. The *chunk-level embedding cache
keyed by chunk content hash* — the part that most resembles what `/docs` needs — I could only source to
third-party write-ups, not to Cursor or turbopuffer. Treat it as a design idea with a plausible
provenance, not a documented one.

**DeepWiki is not a golden example for this problem.** Nothing Cognition publishes describes a
diff-only ingestion path; the observable behaviour is a re-index on a lag (reported ~5 days for
unbadged repos, more often with a badge). Whatever it does incrementally is undocumented. Do not cite
it as precedent.

**The no-API path is the weakest-evidenced leg of the whole design, and it is the one the operator may
be forced onto.** Watchman gives a clock-based since-query and the docs do promise *"a race free
assessment of changed files"*, but I could not verify from primary sources how it reports deletions or
whether a clock survives a daemon restart, and — the real hazard — a macOS OneDrive sync folder is a
File Provider mount whose unhydrated files are dataless placeholders, so a watcher's `stat` and a
content hash can disagree, and hashing a directory tree can *trigger* multi-GB hydration. That is
reasoning, not measurement. It needs a local probe before any architecture rests on it.

---

## Alternatives considered and ruled out

- **Graph `subscriptions` (webhooks) as the primary trigger, no polling.** Right per MS guidance, but
  it needs a publicly reachable HTTPS notification endpoint and a subscription-renewal loop, which
  the brief's "IT may restrict app registrations" constraint makes the least likely thing to be
  approved. Keep it as the optimisation; make the timestamp/deltaLink poll the load-bearing path.
- **`?token=latest` to skip the initial crawl.** Correct for a change-only consumer, wrong here: the
  operator wants a *mirror*, so the initial full enumeration is required, and MS says delta is the only
  enumeration guaranteed complete.
- **Airbyte as the ingestion engine.** Its incremental semantics are record-shaped, not file-shaped, and
  it explicitly cannot propagate deletes without CDC — which SharePoint does not expose as a log. Its
  value here is vocabulary (cursor field, inclusive cursor, dedup by PK), not implementation.
- **`git` as the change detector over `docs-source`.** Attractive (it is already L5) but a 200 GB binary
  inbox in git is a non-starter, and git's stat-cache would re-hash on every clone/checkout. L5 stays
  over `/docs` (text) only, which is what the hypothesis already says.
- **Vendor connectors (Ragie, Carbon, Vectorize).** Searched; none publishes its SharePoint delta
  semantics, deletion model, or record schema at a level worth citing. Ragie's SharePoint guide contains
  no incremental-sync detail at all. Ruled out as evidence, not as products.

---

## Open questions / blockers

1. Does a delta pass with `Prefer: deltashowremovedasdeleted` return tombstones for items removed *to the
   recycle bin* vs *permanently*, and does a restore re-surface as create or as update? Untested; it
   decides whether `/docs` deletions should be soft (git rm, recoverable) or hard.
2. Watchman's deletion reporting and clock durability across restarts — unverified above.
3. macOS OneDrive File Provider placeholder behaviour under a hashing walker — unverified, and it is the
   gate on the whole no-API path.
4. Whether `quickXorHash` is populated for **all** file types in a SharePoint document library, or only
   after some server-side processing settles. The `hashes` resource says only *"Not all services provide
   a value for all hash properties"*, which is not an answer.
5. Chunk-level embedding-cache provenance for Cursor — no primary source found.
