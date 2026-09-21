# Axis D — Change detection, content-addressed manifests, and derived-output bookkeeping

Evidence for/against L2 (manifest + change set) and L3 (idempotent converters) of the lead's layered
hypothesis. Every claim marked **[E]** empirical (cited or measured here) or **[T]** theoretical (my
reasoning). Measurements were run on this machine (macOS, Apple Silicon) and the commands are given
so they can be re-derived rather than re-quoted.

---

## Verdict, first

**Adopt no build system. Adopt three of their ideas, and the third one is the one everybody skips.**

1. **git's index model** for "did the source change" — a stat cache that lets you decide *without
   reading bytes*, plus its racily-clean correction. This is the only layer that matters at 100 GB,
   because the corpus is a OneDrive/File-Provider sync root where **opening a file downloads it**.
2. **Bazel's action key** for "may I reuse the derived output" — a digest over
   `(input content, converter identity+version, normalized args, env)`. git's own `cachetextconv` is
   the cautionary tale here: it keys on the converter's *config string* and therefore silently serves
   stale output after a converter *binary* upgrade, and the git docs say so out loud.
3. **ninja's `restat` / Shake's early cutoff** for "did anything *downstream* change" — hash the
   converter's **output** and stop if it is byte-identical. For an Office corpus this is not an
   optimisation, it is the correctness fix: **an Excel/Word/PowerPoint save mutates the container even
   when the content is unchanged**, so a source-side hash alone produces a permanent stream of
   phantom diffs into `docs/` and into the agent's "what changed since I last looked" git diff.

**DVC is the wrong tool** (measured: 343 stages → ~4 min `dvc commit`, quadratic; outputs deleted at
`repro` start by default; `dvc remove` does not delete outs). **Bazel/Buck2 are the right *model* and
the wrong *deployment*** (hermetic input root ⇒ the whole 100 GB must be digested into a CAS).
**Content-defined chunking is a near-total loss on OOXML** (measured: a 1-byte edit inside a deflate
stream leaves 13 of 11,137 bytes in common) and useful only on extracted parts and PDFs.

---

## 1. The comparison table

| Approach | What it hashes | How it finds the diff | Derived-output tracking | Deletion propagation | Fits docs pipeline? | Evidence |
|---|---|---|---|---|---|---|
| **git index (stat cache)** | file content → SHA-1/256 blob OID, but **only after** a stat-tuple mismatch | `lstat(2)` per path; compares `st_mtime`, `st_ctime`, `st_uid`, `st_gid`, `st_ino`, `st_size`, file type + exec bit; content read only on mismatch or racily-clean | n/a (git tracks sources, not derived) | `git status` reports missing paths; nothing auto-deletes derived files | **Yes — the core of L2.** Copy the stat tuple verbatim, incl. the racily-clean rule | [E] `racy-git.adoc` L34-45, L79-92; `gitformat-index.adoc` cache-entry fields |
| **git cache-tree (TREE ext.)** | subtree → tree OID over its children | "sections of the index can be skipped when a tree comparison demonstrates equality"; on a path update, **all ancestor nodes are invalidated** (`entry_count = -1`) | n/a | n/a | **Yes — this is the Merkle layer, already specified.** Directory digests give O(changed) not O(n) | [E] `gitformat-index.adoc` § Cache tree |
| **git `textconv` + `cachetextconv`** | the **blob OID** of a binary file → cached converted text, stored in `refs/notes/textconv/<driver>` | diff-time; cache hit keyed on blob OID | **Yes — this is a derived-output cache for Office/binary files, built into git** | none (notes ref grows; manual `git update-ref -d`) | **Closest existing primitive to the whole L3 layer** — and its documented defect is the design lesson | [E] `gitattributes.adoc` L979-998 |
| **make** | nothing. mtime ordering only | "The recompilation must be done if the source file … is more recent than the object file, or if the object file does not exist" | target file's existence + mtime | **none** — a removed source leaves its `.o` forever | No. mtime-only ⇒ a re-uploaded older file with an older mtime is invisible | [E] GNU Make manual, *How make Processes a Makefile* |
| **ninja** | command line + inputs, via a build log ("verifying traces") | mtime, **plus** "changing e.g. compilation flags will cause the outputs to rebuild" because the command used is recorded per built file | `.ninja_log` records every built file | **Yes, explicitly: `cleandead` — "remove files produced by previous builds that are no longer in the build file"** | **Yes — `cleandead` is the deletion-propagation primitive to copy, and `restat` is the early-cutoff primitive** | [E] ninja manual, §build log, §`restat`, §`cleandead` |
| **Bazel / Remote Execution API** | `Action` = digest(`command_digest`, `input_root_digest`); input root is a **Merkle tree of `Directory` messages**; env vars MUST be lexicographically sorted so equivalent Commands hash equal | action-cache lookup on the action digest; CAS holds blobs | outputs = "a list of output file names and the hashes of their contents", stored in CAS | `bazel clean`; known issues with orphaned/stale outputs after crashes | **Model: yes. Tool: no** — every input must be declared and digested into the input root | [E] `remote_execution.proto` Action/Command; bazel.build/remote/caching; GH bazel#29564, #2774 |
| **Bazel hermeticity trap** | — | — | — | — | **The single most important warning for key question (c)** | [E] bazel.build/remote/caching: "two users with different compilers installed will wrongly share cache hits because the outputs are different but they have the same action hash" |
| **DVC** | per-stage `md5`/`etag`/`checksum` of `deps` and `outs`, recorded in `dvc.lock`; dir outputs get an `nfiles` count | `dvc status`/`repro` compare lock hashes against the workspace; `foreach`/`matrix` generate one stage per item | `outs` in `dvc.lock`, plus a content-addressed cache | **Partial/manual.** `persist` defaults false: "outputs are deleted when dvc repro starts". `dvc remove` does **not** delete `outs` unless `--outs`; orphaned cache needs `dvc gc` | **No — the stage model fights a per-file pipeline.** See §6a | [E] doc.dvc.org dvcyaml-files (stages/deps/outs/foreach/matrix/persist/always_changed); command-reference/remove; **GH iterative/dvc#10629: 343 stages, `dvc repro --no-commit` ≈2.5 min, `dvc commit -f` ≈4 min, "dvc opens the dvc.lock file at least twice per stage", author's claim: time "grows quadratically in the number of stages"** |
| **Nix** | input-addressed store path = digest over the **derivation itself** (ATerm), type prefix `"output:" id`; content-addressed variants use `"source:"`/`"fixed:"` | any change to a build input ⇒ different store path ⇒ rebuild | the store; GC roots | `nix-collect-garbage` deletes unreferenced paths | Model: the cleanest statement of "converter version is part of the key". Tool: no | [E] nix.dev store-path protocol spec |
| **Buck2** | content-addressed action graph; **deferred materialization**: "Buck2 will avoid downloading outputs until they are required by a local action"; on-disk materializer state in **SQLite** | — | SQLite-tracked materialization state, "remember what files are on disk across restarts" | — | Two transferable ideas: SQLite as the bookkeeping store, and *don't materialize what nobody reads*. Caveat: CAS TTL — "It expects that the TTL returned from action cache entries … always exceeds the TTL of all output artifacts it references" | [E] buck2.build/docs/users/advanced/deferred_materialization |
| **Pants** | fine-grained invalidation on **file contents, not timestamps**; local store is **LMDB** (`~/.cache/pants/lmdb_store`) | — | LMDB store | — | Confirms an embedded KV store is the right shape for the manifest | [E] pantsbuild.org using-pants-in-ci |
| **restic / CDC** | variable-length blobs cut by a 64-byte sliding window (Rabin); "Files smaller than 512 KiB are not split, Blobs are of 512 KiB to 8 MiB … aims for 1 MiB … on average"; "For modified files, only modified Blobs have to be saved … even … if bytes are inserted or removed at arbitrary positions" | index of plaintext chunk hashes | pack files + index | repository prune | **Storage/transfer only, and near-useless on OOXML.** See §7 | [E] restic `doc/design.rst`; FastCDC (USENIX ATC '16): "about 10x faster than the best of open-source Rabin-based CDC … while achieving nearly the same deduplication ratio" |
| **Cursor codebase index (golden example)** | "a cryptographic hash of every file, along with hashes of each folder that are based on the hashes of its children" | "Cursor compares those hashes to the server's version to see exactly where the two Merkle trees diverge… walks only the branches where hashes differ" | server-side vectors keyed by obfuscated path | **"Any entry missing on the client is deleted from the server, and any entry missing on the server is added"** | **This is the reference implementation of exactly the loop you want** | [E] cursor.com/blog/secure-codebase-indexing. Scale datum: "In a workspace with fifty thousand files, just the filenames and SHA-256 hashes add up to roughly 3.2 MB" (~64 B/file) |
| **Theory frame — Build Systems à la Carte** | — | Rebuild strategies: dirty bit → verifying traces → constructive traces → deep constructive traces | — | — | Names the property you must not lose: **early cutoff** | [E] Mokhov/Mitchell/Peyton Jones, ICFP 2018, Table 2 (Make/Excel = dirty bit; **Ninja/Shake = verifying traces**; CloudBuild/Bazel = constructive; Buck/Nix = deep constructive) and §4.2.2: "all traces except for deep traces support early cutoff" |

---

## 2. The finding the table understates: **you need three hashes, not one**

A single content hash per source file cannot express this pipeline. Three distinct questions, three
distinct keys, in this order — each one exists to avoid paying for the next:

| # | Question | Key | Cost avoided | Precedent |
|---|---|---|---|---|
| **H0** | Might this file have changed? | stat tuple `(size, mtime_ns, ctime_ns, ino, mode)` | **reading the bytes** — which on a sync root means *downloading them* | git index stat cache [E] |
| **H1** | Did the *content* change? | `sha256` of bytes, or of the canonicalised part set (see §7) | **running the converter** | Bazel action key / Nix derivation [E] |
| **H2** | Did the *derived markdown* change? | `sha256` of the converter's output | **the git commit, the re-embed, and the agent's attention** | ninja `restat`; Shake early cutoff [E] |

**H2 is the one that is normally omitted and the one this corpus most needs.** Measured: an OOXML
package is a ZIP whose entries carry per-entry timestamps, and the Excel-produced `.xlsx` on this
machine has every one of its 14 entries stamped `10-10-2025 06:45`, i.e. the save time. Repacking the
*identical* extracted parts twice gives two different whole-file digests while the per-part rollup is
identical:

```
whole-file sha256 of two repacks of IDENTICAL parts:  9ac872024f3a673c…  vs  3fc8bb6ecf41c1a3…
per-part rollup sha256 (both):                        e220070560e9e023f1f3805090b83aade428cbd2…
```

and the volatile metadata is structural, not incidental: `docProps/core.xml` carries
`<dcterms:modified>2025-07-31T01:37:27Z</dcterms:modified>`, `docProps/app.xml` carries `<TotalTime>`
and `<AppVersion>`. **[E], measured; commands in §7.**

Consequence, stated plainly: **without H2, every "Save" a colleague presses on an unchanged workbook
produces a source diff, a re-conversion, and a `docs/` commit that says nothing.** With H2 the
re-conversion still runs (cheap, local, parallel) but the mirror stays byte-stable and the agent's
`git log docs/` stays honest. H2 is what makes L5 ("what changed since I last looked = a git diff")
true rather than aspirational.

---

## 3. Recommended manifest schema

One row per **source object**, plus one row per **derived output**, plus one row per **directory** for
the Merkle layer. Store it in **SQLite** (Buck2's materializer choice [E]; Pants uses LMDB [E]) and
export a deterministic JSON/NDJSON snapshot into git so the manifest itself is diffable.

Measured sizing: a 200,000-row manifest with path+size+mtime+sha256 serialises to **31.1 MB JSON
(155 B/row)**, loads in **0.12 s**, and a full stat-compare of all 200k rows takes **0.051 s**; a
`hash → paths` index for rename detection builds in **0.088 s** [E, measured]. Independently, Cursor
reports ~64 B/file for names+SHA-256 at 50k files [E]. **The bookkeeping layer is free. Every
optimisation belongs on the byte-reading side.**

### `source` table — one row per object in `docs-source/` or per remote driveItem

| Field | Why it must be there |
|---|---|
| `source_id` | **Stable identity independent of path.** Graph `driveItem.id` remotely; `(volume_uuid, inode)` or a content-derived id for manual drops. Without it, a rename is indistinguishable from delete+create. [T] |
| `source_kind` | `graph` \| `fileprovider` \| `manual` — decides which freshness token is authoritative |
| `path` | current logical path; **not** the identity |
| `prev_path` | lets a rename be *reported* as a rename to L4 curation, not as churn |
| `size`, `mtime_ns`, `ctime_ns`, `inode`, `mode` | the H0 stat tuple, copied from git's list: git compares "file type … and executable bits from `st_mode`, `st_mtime` and `st_ctime` timestamps, `st_uid`, `st_gid`, `st_ino`, and `st_size`" [E]. Keep `ctime` — it catches in-place writes that preserve `mtime`. Note git deliberately **excludes `st_dev`** ("not stable on network filesystems") [E] — do the same for a File Provider root |
| `dataless` | **macOS-specific and load-bearing.** `SF_DATALESS 0x40000000 /* file is dataless object */`, `sys/stat.h:359` on this machine [E, verified in SDK headers]. A dataless row means *present but not materialised*: never hash it, never convert it, and never treat its absence of a hash as a change |
| `content_hash` | `sha256` of bytes (H1). **Nullable** — null is legal and means "not materialised / not yet read", and that must be a distinct state from "hash mismatch" |
| `canonical_hash` | H1 for container formats: rollup over the *normalised* part set (§7). This is the field the converter cache actually keys on |
| `provider_hash` | **`quickXorHash` only.** Graph's `hashes` resource says `sha256Hash`: *"This property isn't supported. Don't use."* and *"quickXorHash is the only value that is guaranteed to be available for both OneDrive for work or school and OneDrive for home"* [E]. It is **not** comparable to your own sha256 — it is a self-consistent remote change detector, nothing more. Two hash columns, never one |
| `etag`, `ctag` | Graph change tokens. cTag moves on content change, eTag on metadata — cheapest possible H1 proxy with zero bytes read |
| `first_seen_run`, `last_seen_run` | a row not stamped with the current run id is a **deletion candidate** — the Cursor rule: "Any entry missing on the client is deleted" [E] |
| `state` | `live` \| `dataless` \| `tombstone` \| `quarantined` (unreadable/encrypted/corrupt). A tombstone is not a deleted row: it is how L4 learns a page's source went away |

### `output` table — one row per derived file in `docs/`

| Field | Why |
|---|---|
| `output_path` | the markdown file |
| `owner` | **`mirror` \| `curated`.** See §5 — this single field is what stops deletion propagation from eating agent-authored pages |
| `source_ids[]` | the dependency edge. Many-to-one for a per-sheet/per-slide fan-out; many-to-many for curated pages |
| `action_key` | the Bazel-style digest — see §6c |
| `output_hash` | H2. The early-cutoff key |
| `unit` | `whole` \| `sheet:<name>` \| `slide:<n>` \| `page:<n>` — the sub-file coordinate |
| `converter_id`, `converter_version` | recorded, not just hashed, so a bad converter release is auditable and selectively re-runnable |
| `built_run`, `build_ms`, `status` | `ok` \| `failed` \| `skipped-dataless`; a failure must be a **row**, not a log line, or it becomes invisible and permanent |

### `dirnode` table — the Merkle layer

`path`, `children_digest`, `entry_count`, `valid`. Follow git's cache-tree exactly: "When a path is
updated in index, Git invalidates all nodes of the recursive cache tree corresponding to the parent
directories of that path", marking them invalid with `-1` [E]. That gives you Cursor's "walk only the
branches where hashes differ" [E] and makes a no-op scan O(changed) rather than O(corpus).

---

## 4. Change-set algorithm

```
# ── phase 0: freshness token (L1 — other axis owns the acquisition) ─────────────
#   graph      : deltaLink  → server hands you only changed driveItems, incl. deletes/moves
#   fileprovider/manual : FSEvents/watchman clock, else a full stat walk
run_id = new_run()

# ── phase 1: candidate set, WITHOUT READING ANY BYTES ──────────────────────────
for each observed object o:
    row = manifest.source[o.source_id]          # identity, never path
    stamp(row, last_seen_run = run_id)

    if row is None:                     classify CREATED;  continue
    if o.path != row.path:              record rename(prev_path=row.path)   # not churn
    if o.dataless:                      classify DATALESS; continue         # macOS SF_DATALESS
                                                                           # NEVER open: opening hydrates
    if o.provider_hash and row.provider_hash:
        classify (o.provider_hash != row.provider_hash) ? MAYBE_CHANGED : UNCHANGED
        continue                                            # zero bytes, zero downloads
    if stat_tuple(o) == stat_tuple(row):
        # git's racily-clean correction: a same-second in-place edit is invisible to stat.
        if row.mtime_ns >= manifest.written_at_ns:  classify MAYBE_CHANGED   # force a content read
        else:                                       classify UNCHANGED
        continue
    classify MAYBE_CHANGED

# deletions: any live row whose last_seen_run < run_id
for row in manifest.source where state='live' and last_seen_run < run_id:
    classify DELETED                                  # Cursor: "missing on the client is deleted"

# ── phase 2: H1 — content identity (only MAYBE_CHANGED ∪ CREATED) ─────────────
for o in MAYBE_CHANGED ∪ CREATED:
    bytes = materialise(o)             # the ONLY place a download can happen; budget + rate-limit it
    o.content_hash   = sha256(bytes)
    o.canonical_hash = canonicalise(o)  # §7: per-part rollup for OOXML, per-page for PDF
    if o.canonical_hash == row.canonical_hash:
        classify TOUCHED_NOT_CHANGED    # the Office-save case. Update stat cache; DO NOT convert.
    else:
        classify CHANGED

# ── phase 3: unit expansion (sub-file granularity) ───────────────────────────
units = []
for o in CHANGED ∪ CREATED:
    for u in units_of(o):                       # sheets / slides / pages / whole
        if u.hash != manifest.unit_hash(o.source_id, u.id): units += [(o, u)]

# ── phase 4: H2 — build, with early cutoff ───────────────────────────────────
for (o, u) in units:
    key = action_key(o.canonical_hash, u.id, converter_id, converter_version,
                     normalised_args, sorted(relevant_env))           # §6c
    if cache.has(key):
        new_text = cache.get(key)                                    # constructive trace
    else:
        new_text = convert(o, u); cache.put(key, new_text)
    if sha256(new_text) == manifest.output[path].output_hash:
        mark UNCHANGED_OUTPUT                 # ninja `restat` / Shake early cutoff.
        continue                              # no write, no git churn, no re-embed, no agent signal
    write(path, new_text); record(output_hash, action_key, built_run=run_id)

# ── phase 5: deletion propagation, ownership-aware ───────────────────────────
for row in DELETED:
    for out in manifest.outputs_of(row.source_id):
        if out.owner == 'mirror':   delete(out.output_path)      # ninja `cleandead`
        else:                       flag_stale(out, reason='source deleted', source=row.path)
    manifest.tombstone(row)

# ── phase 6: Merkle roll-up + commit ─────────────────────────────────────────
invalidate_ancestors(all touched paths)          # git cache-tree, entry_count = -1
recompute_invalid_dirnodes()                     # bottom-up
snapshot_manifest_to_git()                       # deterministic key order, so it diffs
git commit docs/ manifest/                       # L5
```

Two properties worth naming because they are easy to lose:

- **Phase 1 reads zero file bytes.** That is the whole design. [T, from the hydration evidence in §8]
- **Phase 4's early cutoff makes the pipeline idempotent in the eyes of git**, which is what makes a
  human's redundant re-upload of "Report v3 (final).xlsx" over "Report v3.xlsx" cost one manifest row
  and no diff. [T]

---

## 5. Deletion propagation — and the trap in it

ninja's `cleandead` ("remove files produced by previous builds that are no longer in the build file")
[E] and Cursor's "any entry missing on the client is deleted from the server" [E] are the same rule
and it is correct **only over machine-owned outputs**.

**[T] The trap:** L4 curation produces agent-authored pages that aggregate many sources. Auto-deleting
those when a source disappears destroys human/agent work — the same class of failure as a build system
reclaiming a file someone hand-edited. Bazel avoids it structurally by putting every generated file
under `bazel-out/`, never in the source tree.

**Recommendation:** split `docs/` by ownership and let the manifest claim only half of it.

```
docs/
  reference/     ← owner=mirror.  1:1, machine-owned, deleted freely, never hand-edited.
  <curated>/     ← owner=curated. agent-authored, never auto-deleted; a lost source sets
                   a `stale:` field in the page's frontmatter and files a work item.
```

A `mirror` page carries provenance frontmatter (`source_id`, `canonical_hash`, `converter_version`,
`unit`) so the manifest can be rebuilt from `docs/` alone if it is ever lost — the manifest becomes a
cache, not a single point of truth. [T]

---

## 6. The four key questions

### (a) Is DVC a good fit, or does its stage model fight it?

**It fights it, on three independent counts, and any one is disqualifying.** [E]

1. **Outputs are deleted before the work starts.** `persist` is "false by default: outputs are
   deleted when dvc repro starts". A single whole-directory stage over `docs/` therefore *deletes the
   entire mirror* and rebuilds it — the exact opposite of incremental. Per-file stages avoid this but
   hit (2).
2. **Per-file stages do not scale, and the cost is in the lock file, not the work.** Measured in
   iterative/dvc#10629: **343 stages** (a 7×7×7 `matrix`) → `dvc repro --no-commit` ≈ 2.5 min,
   `dvc commit -f` ≈ **4 min** — "the commit step takes longer than the repro step" — because "dvc
   opens the dvc.lock file at least twice per stage"; the reporter's claim is quadratic growth. A
   corpus of thousands of files is one to two orders of magnitude past that. Related: #9805 (parallel
   `repro` contends on `dvc.lock`), #7681/#7607 (slow with many files).
3. **Deletion propagation is manual.** `dvc remove` "safely removes .dvc files or stages" but the
   `outs` "are not removed by this command, unless the `--outs` option is used", and orphaned cache
   entries need `dvc gc`. So a deleted source requires: regenerate `dvc.yaml`, `dvc remove --outs`,
   `dvc gc`. Three human-ordered steps where ninja has one verb.

DVC's `foreach`/`matrix` templating is the right *idea* for generating one unit of work per file, and
its `dvc.lock` "content hash field (md5, etag, or checksum)" is the right *shape* for a manifest row.
Take those; leave the runtime. **[T]** DVC's content-addressed cache is also redundant here: the
derived artefact is small text living in git, which already is a content-addressed store.

### (b) Minimal manifest for rename detection + same-name update

Both cases reduce to one rule: **identity ≠ path, and identity ≠ content.** Three columns are the
irreducible minimum:

| Case | Signature | Needs |
|---|---|---|
| **same-name update in place** | same `source_id`, same `path`, **new** `canonical_hash` | `source_id` + `canonical_hash` |
| **rename** | same `source_id`, **new** `path`, same `canonical_hash` | `source_id` + `path` |
| **messy re-upload as `…v2.xlsx`** | **new** `source_id`, new `path`, **hash equal to an existing row** | a `canonical_hash → source_ids` index |
| **delete** | `last_seen_run < run_id` | `last_seen_run` |

So: **`source_id`, `path`, `canonical_hash`, `last_seen_run`** — four fields — plus the stat tuple
purely as an optimisation. **[T]**

Note the asymmetry with git: git does **not** store renames; it infers them at diff time by content
similarity (`-M`). You should store them, because remote sources hand you the answer for free (Graph
delta reports moves) and because the messy-re-upload case is a *near*-duplicate, not an exact one —
a hash index catches the exact case, and only the exact case. Detecting "v3 (final)" as a revision of
"v3" needs similarity, not hashing, and belongs to L4 curation, not L2. **[T]** The Merkle/dirnode
layer is likewise for *skipping*, not *matching*: "In a workspace with fifty thousand files, just the
filenames and SHA-256 hashes add up to roughly 3.2 MB" [E] — you can afford to ship the whole flat
manifest; the tree buys you the *walk*, not the *transfer*.

### (c) How should converter version enter the cache key?

**Verbatim from the Bazel docs, because it is the failure mode:** "two users with different compilers
installed will wrongly share cache hits because the outputs are different but they have the same
action hash" [E]. And git's `cachetextconv` ships exactly that bug and documents it: "If you change
the textconv config variable for a diff driver, Git will automatically invalidate the cache entries
and re-run the textconv filter. If you want to invalidate the cache manually (e.g., **because your
version of 'exif' was updated and now produces better output**), you can remove the cache manually
with `git update-ref -d refs/notes/textconv/jpg`" [E]. The *config string* is keyed; the *binary* is
not. Nix's answer is the opposite extreme: the store path digest is over the derivation itself
("`"output:" id` … hashes the derivation itself using ATerm serialization" [E]), so any input change
— toolchain included — yields a new path.

**Recommendation (Bazel's structure, per-converter granularity):**

```
action_key = sha256(
    "v1",                          # key-schema version — lets YOU invalidate everything deliberately
    converter_id,                  # e.g. "xlsx->md"
    converter_semver,              # e.g. "pandoc 3.1.11" — captured by RUNNING --version, not assumed
    sha256(converter_binary)?,     # optional: only where the binary is stable/vendored
    normalise(args),               # sorted, defaults expanded
    sorted(env_allowlist),         # Bazel: env vars MUST be lexicographically sorted [E]
    unit_id,                       # sheet:Q3 | slide:7 | page:12 | whole
    canonical_hash(source)         # H1
)
```

Per-converter, not global, is the point: a PDF-extractor upgrade must not invalidate 40,000 Excel
mirrors. **[T]** And the blast radius of a legitimate converter bump is absorbed by **H2**: the
conversions re-run, but only the outputs that actually differ reach git. A pandoc upgrade then costs
CPU, not a 40,000-file commit. **[T]** Record `converter_version` as a column too, not only inside the
digest — otherwise you can detect a mismatch and never explain it. **[T]**

### (d) Where a 100 GB corpus breaks each approach

| Approach | Breaking point | Evidence |
|---|---|---|
| **Any full-corpus content hash** | **Hydration, not CPU.** sha256 runs at ~2,384 MB/s here (100 GB ≈ 42 s of CPU) [E, measured] — irrelevant. The break is that the corpus is a sync root: Windows placeholders "consume only 1 KB of storage … and automatically hydrate into full files under normal use conditions", and "Whether you use file system APIs, the Command Prompt, or a desktop or a UWP app to access a placeholder file, the file will hydrate", with full-hydration providers giving "the file being fully hydrated on first access" [E]. macOS is the same shape: `SF_DATALESS` exists in `sys/stat.h:359` [E]. **One naive `find … -exec sha256` downloads the entire tenant share.** | Win32 cfapi; macOS SDK headers; local benchmark |
| **git-as-the-manifest** | The index is a single file rewritten wholly on update; the **Split index** extension exists precisely so that "the majority of index entries could be stored in a separate file" with an ewah delete/replace bitmap on top [E]. At 100k+ entries plus large binaries you are fighting git's own scaling problem. Track `docs/` (small text) in git; keep the source manifest in SQLite | `gitformat-index.adoc` § Split index |
| **DVC** | ~343 stages already costs 4 min of pure bookkeeping; quadratic [E] | dvc#10629 |
| **Bazel / Buck2** | Hermeticity: the whole input root must be digested into the CAS and every input declared. Buck2's deferred materialization softens the *output* side ("avoid downloading outputs until they are required by a local action" [E]) but not the input side; and remote artefacts carry a TTL hazard — "It expects that the TTL returned from action cache entries … always exceeds the TTL of all output artifacts it references" [E] | REAPI; buck2 docs |
| **make** | mtime-only ⇒ silently wrong here. A file re-downloaded by the sync client, or restored from a backup, can arrive with an *older* mtime than the derived markdown and never rebuild [T]; and no deletion propagation at all [E] | GNU Make manual |
| **CDC / restic** | Chunk index memory and the OOXML compression problem (§7) | restic design; measured |

---

## 7. Sub-file granularity — measured

**OOXML is already a per-unit container; you do not need to invent the granularity, only to read it.**
Measured with `unzip -lv` on a real Excel-produced `.xlsx` and a real PowerPoint `.pptx` on this
machine:

```
xlsx: [Content_Types].xml  _rels/.rels  docProps/{app,core,custom}.xml
      docMetadata/LabelInfo.xml  xl/printerSettings/printerSettings1.bin
      xl/sharedStrings.xml  xl/styles.xml  xl/theme/theme1.xml
      xl/workbook.xml  xl/_rels/workbook.xml.rels
      xl/worksheets/sheet1.xml          ← one part per sheet
pptx: ppt/slides/slide1.xml … slide6.xml ← one part per slide
      docProps/app.xml  (contains <TotalTime>, <AppVersion>16.0000)
```

So: **hash `xl/worksheets/sheetN.xml` → one edited sheet re-converts one derived markdown file.**
Same for `ppt/slides/slideN.xml`. This is real per-unit granularity at zero inference cost. **[E]**

**But per-part hashing must be preceded by normalisation, and the exclusion list is not optional.**
Two measured facts:

1. **Whole-file hashing of an OOXML container is not a content identity.** Repacking the *same*
   extracted parts twice yields different archive digests (`9ac8…` vs `3fc8…`) while the per-part
   rollup is identical (`e2200705…`) — because ZIP local headers carry per-entry timestamps, and the
   Excel-produced file stamps all 14 entries with the save time.
2. **Volatile parts exist and are named.** `docProps/core.xml` → `<dcterms:modified>`;
   `docProps/app.xml` → `<TotalTime>`, `<AppVersion>`; plus `xl/calcChain.xml`,
   `xl/printerSettings/*.bin`, `docMetadata/LabelInfo.xml` (sensitivity labelling — changes when IT
   policy changes, not when content does).

```bash
# reproduce (both facts), ~10 s:
unzip -lv file.xlsx                       # per-entry Date/Time column = save time
mkdir x && (cd x && unzip -q ../file.xlsx)
(cd x && find . -type f | sort | zip -qX ../r1.zip -@)
(cd x && touch -t 203001010101 $(find . -type f) && find . -type f | sort | zip -qX ../r2.zip -@)
shasum -a256 r1.zip r2.zip                # differ
(cd x && find . -type f | sort | xargs shasum -a256) | shasum -a256   # stable
```

**[T] Honest limit on this measurement, and it changes the recommendation.** I proved that
*repacking* identical parts changes the container hash. I did **not** prove that Excel's own re-save
leaves `sheet1.xml` byte-identical when nothing changed — it very likely does not (attribute order,
shared-string renumbering, `calcChain` rebuild). Per-part hashing therefore *narrows* the volatility
surface; it does not close it. **This is precisely why H2 (output-side early cutoff) is
non-negotiable rather than an optimisation** — it is the only layer that is immune to producer-side
serialisation noise, because it compares the *converted text*.

**PDF.** No part structure; use page text. Measured: `pdftotext -f N -l N | sha256` costs ~20 ms/page
(6 pages of a 29-page paper in 0.125 s wall, 156% CPU) [E]. PDF whole-file hashes are as unstable as
OOXML's for the same reason — `pdfinfo` on that file reports `ModDate: Fri Jul 13 18:01:50 2018` and
a `/Producer` string, and PDF writers rewrite the trailer `/ID` and support incremental append. Page
text hashing gives a stable per-page unit and a natural markdown fan-out. Caveat **[T]**: an inserted
page shifts every subsequent page number, so the *unit id* must be `page:<n>` **plus** the page's own
text hash, or an insertion re-converts the tail of the document. Content-addressing the unit, not
positionally addressing it, fixes this — the same reason Merkle trees beat offsets.

---

## 8. Content-defined chunking: a clear no, with one narrow yes

**[E, measured] A 1-byte edit inside a deflate stream destroys the entire compressed byte stream.**
Compressing a 2,048,000-byte input and the same input with byte 500 incremented:

```
plain   : common prefix 500 / 2,048,000
deflate : common prefix  13 / 11,137 bytes, and the two lengths differ (11,137 vs 11,143)
```

Since `.xlsx`/`.docx`/`.pptx` are deflate-compressed ZIPs, **CDC over the container recovers
essentially nothing** — neither for dedup nor for transfer. restic's own design is explicit that
chunking is applied to plaintext ("The data from each file is split into variable length Blobs …
Rabin Fingerprints") and that its insertion-robustness claim is about plaintext blobs [E]. FastCDC's
"about 10x faster than the best of open-source Rabin-based CDC … nearly the same deduplication ratio"
[E] improves the throughput of an operation that has no purchase here.

**The narrow yes [T]:** if you keep a local mirror of raw bytes (for reconversion after a converter
upgrade without re-downloading 100 GB), CDC pays on the **extracted parts** and on **PDFs**, where the
version-suffix problem produces genuine near-duplicates. Store extracted, uncompressed parts and let
CDC dedup them; never chunk the containers. And note the cheaper alternative: **you may not need the
raw mirror at all** — H2 means a converter upgrade produces no git churn, so re-downloading on demand
is often better than storing 100 GB twice.

---

## 9. Failure modes to design against

1. **The hydration stampede.** Any full-corpus hash, or any converter that opens a dataless file,
   downloads the tenant share — slowly, visibly, and possibly against an IT policy on
   "Automatic file downloads". Gate every `materialise()` behind a per-run byte budget and a
   dataless check. **[E, mechanism]**
2. **Phantom diffs from Office saves.** Without H2, `docs/` churns on every save and the agent's
   "what changed" signal degrades to noise. **[E, measured]**
3. **Manifest/reality divergence with no detector.** A converter that fails silently leaves a stale
   `docs/` page and an `output_hash` that matches it. Fix: `status` is a column, and a periodic audit
   re-derives `output_hash` from disk. **[T]**
4. **Deletion propagation eating curated work.** §5. **[T]**
5. **`mtime` regression.** A sync client or restore can write an *older* mtime; an mtime-*ordering*
   rule (make) misses it, an mtime-*equality* rule (git) catches it. Compare for inequality, never
   for "newer than". **[E, from the make vs git contrast]**
6. **Racily-clean in-place edits.** Two writes inside one mtime tick. git's fix is to force a content
   read when `st_mtime >= index mtime`, and to truncate cached `st_size` to zero when writing an index
   containing racily-clean entries [E]. Copy both halves; the second is the one people omit.
7. **Provider hash confusion.** Comparing a `quickXorHash` to a `sha256` yields permanent
   "everything changed". Two columns. **[E]**
8. **Converter upgrade as a corpus-wide event.** §6c. **[T]**
9. **Unreadable sources become invisible.** Password-protected workbooks, sensitivity-labelled
   (`docMetadata/LabelInfo.xml` is present on a real file here [E]) or IRM-protected files will fail
   conversion forever. `state='quarantined'` + a counted row, so the gap is a number rather than a
   silence. **[T]**
10. **The manifest is the only copy.** Keep provenance in each mirror page's frontmatter so the
    manifest is reconstructible. **[T]**

---

## 10. Alternatives considered and ruled out

| Considered | Ruled out because |
|---|---|
| **DVC as the pipeline runner** | §6a — three independent disqualifiers, all cited |
| **Bazel/Buck2 as the runner** | Hermetic input root over 100 GB; corporate-macOS install burden; REAPI TTL hazard. Model adopted, tool rejected |
| **Nix** | Same input-addressing insight as Bazel, heavier deployment, no advantage for text outputs living in git |
| **make + hash stamps** (`.hash` sentinel files) | Works, and is the cheapest thing that could — but reimplements verifying traces in the filesystem with no deletion propagation and no unit granularity. If you want this shape, use **ninja**: you get `restat` (early cutoff) and `cleandead` (deletion propagation) as *documented verbs* rather than idioms [E] |
| **CDC/restic for invalidation** | §8, measured |
| **Whole-file sha256 as the only key** | §7, measured — not a content identity for OOXML or PDF |
| **git as the source-side manifest (index + textconv cache)** | Genuinely close (`cachetextconv` is a content-keyed derived-output cache for binary docs [E]) but: no unit granularity, cache invalidation keyed on config string not converter version [E], and the index's own scaling problem (hence Split index [E]) |
| **A pure symlink farm with no manifest** | Cannot answer "what changed since last time" at all: a symlink has no memory, and the sync root's placeholders make a stat walk the *only* safe read. The manifest is the memory |

---

## 11. Open questions / blockers

1. **[Unmeasured, and it is the one experiment worth running]** Does Microsoft Excel/Word/PowerPoint
   leave `xl/worksheets/sheetN.xml` / `ppt/slides/slideN.xml` byte-identical across a no-op
   open-and-save? I proved container instability and part-list structure but could not run Office
   here. The answer decides whether H1-on-parts is a useful filter or merely a narrower one — it does
   **not** change the recommendation, because H2 covers both outcomes. Experiment: open a workbook,
   Save, diff the per-part rollup.
2. **macOS dataless detection end-to-end.** `SF_DATALESS` is in the SDK headers [E], but no OneDrive
   File Provider root exists on this machine (`~/Library/CloudStorage/` is absent), so I could not
   verify that OneDrive-for-Mac actually sets it on online-only files, nor that `lstat` alone avoids
   materialisation. Verify on the corporate machine before trusting the no-hydration guarantee:
   `ls -lO`, `stat -f '%f %z %b'`, and watch network bytes during a walk.
3. **Graph `quickXorHash` availability on SharePoint document libraries** (as opposed to OneDrive) is
   stated as guaranteed for "OneDrive for work or school and OneDrive for home" [E]; the note "Not all
   services provide a value for all hash properties" means it must be probed per drive, and the
   pipeline must degrade to stat+content when it is absent.
4. **Whether `docs/` should be one git repo or a git repo plus a SQLite manifest outside it.** The
   measurement (31 MB JSON at 200k rows [E]) says a committed NDJSON snapshot is affordable and
   diffable; the counter-argument is 200k-line diffs on every run. Sharding the snapshot by top-level
   directory is the obvious fix but is untested here.
5. **Unit-level cost of PDF page extraction at corpus scale.** 20 ms/page measured on one document;
   a 100 GB corpus of scanned PDFs (needing OCR, not `pdftotext`) is a different cost class entirely
   and was out of scope.

---

## Sources

- git — [gitformat-index](https://git-scm.com/docs/index-format) · [`racy-git.adoc`](https://raw.githubusercontent.com/git/git/master/Documentation/technical/racy-git.adoc) · [`gitformat-index.adoc`](https://raw.githubusercontent.com/git/git/master/Documentation/gitformat-index.adoc) (Cache tree, Split index) · [`gitattributes.adoc`](https://raw.githubusercontent.com/git/git/master/Documentation/gitattributes.adoc) (textconv / cachetextconv)
- ninja — [manual](https://ninja-build.org/manual.html) (build log, `restat`, `cleandead`)
- GNU make — [How make Processes a Makefile](https://www.gnu.org/software/make/manual/html_node/How-Make-Works.html)
- Bazel — [Remote caching](https://bazel.build/remote/caching) · [`remote_execution.proto`](https://raw.githubusercontent.com/bazelbuild/remote-apis/main/build/bazel/remote/execution/v2/remote_execution.proto) · [bazel#29564](https://github.com/bazelbuild/bazel/issues/29564) · [bazel#2774](https://github.com/bazelbuild/bazel/issues/2774)
- Buck2 — [Deferred Materialization](https://buck2.build/docs/users/advanced/deferred_materialization/)
- Pants — [Using Pants in CI](https://www.pantsbuild.org/stable/docs/using-pants/using-pants-in-ci)
- Nix — [Store path specification](https://nix.dev/manual/nix/2.35/protocols/store-path)
- DVC — [dvc.yaml files](https://doc.dvc.org/user-guide/project-structure/dvcyaml-files) · [`dvc remove`](https://dvc.org/doc/command-reference/remove) · [iterative/dvc#10629](https://github.com/iterative/dvc/issues/10629) · [dvc#9805](https://github.com/treeverse/dvc/issues/9805) · [dvc#7681](https://github.com/treeverse/dvc/issues/7681) · [dvc#7607](https://github.com/treeverse/dvc/issues/7607)
- restic — [design.rst](https://github.com/restic/restic/blob/master/doc/design.rst)
- FastCDC — [USENIX ATC '16](https://www.usenix.org/conference/atc16/technical-sessions/presentation/xia)
- Build Systems à la Carte — [Mokhov, Mitchell, Peyton Jones, ICFP 2018](https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems.pdf)
- Cursor — [Securely indexing large codebases](https://cursor.com/blog/secure-codebase-indexing)
- Microsoft Graph — [hashes resource type](https://learn.microsoft.com/en-us/graph/api/resources/hashes)
- Windows — [Build a Cloud Sync Engine that Supports Placeholder Files](https://learn.microsoft.com/en-us/windows/win32/cfapi/build-a-cloud-file-sync-engine)
- macOS — `SF_DATALESS`, `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/stat.h:359`
