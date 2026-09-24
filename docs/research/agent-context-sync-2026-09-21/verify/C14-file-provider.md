# C14 — OneDrive File Provider: hydration, GEN_COUNT, walk cost and web-edit events (measured 2026-09-23)

**Verdict.** On a real OneDrive for Business File Provider domain the design's arm-B assumptions hold, with one correction that matters: **a launchd job does not download online-only files by default.** Its process-default materialization policy is OFF, so a plain read of a dataless file fails with `EDEADLK` (errno 11), while the same read from a login shell downloads it. `ATTR_CMN_GEN_COUNT` is returned for every File Provider item, and a `getattrlistbulk` walk costs the same as on local APFS. A web-side edit to a downloaded file raises a normal FSEvent on the `~/Library/CloudStorage/…` path within about 20 s. A file created on the web in a folder the Mac has never listed produced a directory event only, and the file itself surfaced only when something enumerated that folder.

## 1. Setup

macOS 15.7.9, OneDrive 26.168.0830, domain `OneDrive-Reso` (tenant `resogl.onmicrosoft.com`, user chris@reso.gl, Microsoft 365 Business Standard trial), mounted at `~/Library/CloudStorage/OneDrive-Reso`. Test folder `agentsync-probe/` held `note.txt`, `note2.txt`, `doc.docx`, a 2 MB `blob.bin` and `walk/` (20 dirs × 100 files). Files were made online-only with `FileManager.evictUbiquitousItem(at:)`, which works for any File Provider domain, not only iCloud (`fileproviderctl` has no evict verb). Probe sources are described in §7.

## 2. Probe 4 — the dataless state and hydration, in both contexts

| check | result |
|---|---|
| `ls -l%` on an evicted file | `%` in the mode column |
| `stat -f '%f %z %b'` | flags `0x40000060` (`SF_DATALESS` 0x40000000 + `UF_TRACKED` 0x40 + `UF_COMPRESSED` 0x20), full logical size, **0 blocks** |
| read, login shell, policy forced OFF (`setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`) | `open()` succeeds, **`read()` fails `EDEADLK`, errno 11**; file stays dataless |
| read, login shell, default policy (reads as 2 = ON) | downloads: 27 B in 0.48 s, flags drop to `0x40`, 8 blocks |
| same, first attempts right after sign-in | `read()` failed **`ETIMEDOUT`, errno 60**, in 40–60 ms, twice; succeeded on the third try 10 s later. A `getattrlistbulk` over the domain hit the same `ETIMEDOUT` on one directory during that window |
| read from a **launchd job** (`launchctl submit`), default policy | **policy reads 1 = OFF; `read()` fails `EDEADLK`, errno 11** after 1.66 s; nothing downloaded |
| launchd job that calls `setiopolicy_np(…, IOPOL_MATERIALIZE_DATALESS_FILES_ON)` first | downloads 2,000,000 B in 0.16 s |
| launchd job whose plist sets `<key>MaterializeDatalessFiles</key><true/>`, default policy | policy reads 2; downloads 2,000,000 B in 0.66 s |

**Consequences.** (a) A scheduled sync that runs under launchd must opt in explicitly — the plist key, or `…_ON` before any read — or every online-only file becomes an `EDEADLK` it has to classify. The design's fail-closed `…_OFF` for the walk and hash stages is already the launchd default; only `materialise()` needs `…_ON`. (b) `ETIMEDOUT` from a dataless read means the provider is not serving yet, not that the file is bad: retry with backoff and record it as `dataless`, never as changed or empty.

## 3. Probe 5 — GEN_COUNT and walk cost on File Provider

`ATTR_CMN_GEN_COUNT` is present in `ATTR_CMN_RETURNED_ATTRS` for **every** File Provider item (2,000/2,000 in `walk/`, all non-zero). The same holds for dataless items: `fresh/Document.docx`, created on the web and never downloaded, returned `gen=1` with the dataless flag set. `getattrlist` needs `FSOPT_ATTR_CMN_EXTENDED` to return it (without that it is `EINVAL`), while `getattrlistbulk` returns it directly.

| walk (`getattrlistbulk`, 2,000 files / 21 dirs) | wall-clock |
|---|---|
| OneDrive File Provider, 3 passes | 0.002 s, 0.002 s, 0.004 s |
| local APFS, same tree | 0.002 s, 0.002 s |

The File Provider domain lives on the Data volume, so enumerating directories already listed is a local metadata read. The C11 local figure (0.13–0.31 s per 10⁵ files) carries over. A directory that has never been enumerated is a provider round-trip, and that is where the startup `ETIMEDOUT` above appeared.

**GEN_COUNT moves on hydration churn.** `blob.bin` went from 490 to 494 across evict → download with no content change. T3 must therefore treat a moved `(FILEID, GEN_COUNT)` as "hash to confirm", which is what §4.2 already prescribes; it is not proof of an edit. An in-place overwrite test inside the synced folder was refused by this session's permission classifier and was **not measured**.

## 4. Probe 3 — which events fire on a web-side edit

An FSEvents stream (`kFSEventStreamCreateFlagFileEvents`) watched `~/Library/CloudStorage/OneDrive-Reso`, `~/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite` and `~/Library/Containers/com.microsoft.OneDrive.FileProvider`. The operator made the edits in OneDrive on the web. Timestamps are measured from the moment the operator pressed Return after saving, so each latency is an upper bound. Raw log: §6.

| case | what the operator did | events on `CloudStorage/…` | events in OneDrive's private store | outcome |
|---|---|---|---|---|
| (i) downloaded file | appended "hello" to `note.txt` | `Modified,ChangeOwner,XattrMod,IsFile` on `note.txt` at +19.7 s, twice more within 0.4 s | `…/OneDrive - Reso.noindex/OneDrive - Reso/agentsync-probe/note.txt` `InodeMetaMod` at +19.0 s, then `Removed`/`Renamed`; a `Hydrations/N.hydration` staging file created and renamed | local copy updated in place to the web version (29 → 34 B), still downloaded |
| (ii) online-only file | **not measured** — `note2.txt` never appeared in the web listing (see §5) | only events from this session's own download/re-evict | same | — |
| (iii) folder never listed on the Mac | created `fresh/` on the web and a Word document inside it | **`fresh` directory only** (`Renamed,IsDir`); **no event for `fresh/Document.docx`** | `fresh/` `Created,IsDir`, and `fresh/Document.docx` `Created,Modified` | the file became visible — dataless, `gen=1` — only when something listed `fresh/` |

**Consequences for arm B.** T1 on the canonical `CloudStorage` path does fire for server-side edits to downloaded files, so T1/T2 exist on File Provider. For new subtrees T1 carries only the directory. The children are found by enumeration, which is what the T3 walk does, so T3 stays the authority and an event on a new directory must trigger a walk of that directory. OneDrive's private store (`UBF8T346G9.OneDriveStandaloneSuite/OneDrive - Reso.noindex/`) mirrors the whole tree and raises the most detailed events. It is undocumented internal state (its `note.txt` showed `blocks=0 flags=0` while the canonical copy was downloaded), so the design should **not** depend on it.

## 5. An observation that bounds arm A vs arm B

`note2.txt` was created on the Mac at 23:20. At 23:24 File Provider reported it `isUploaded = 1` (`fileproviderctl evaluate`) and allowed it to be evicted; a later default-policy read downloaded its correct 33 bytes. Yet OneDrive on the web did not list it at 23:26, 23:28 or 23:30, across hard refreshes and a new tab, while `note.txt` and `walk/`, written minutes earlier, were listed. The upload queue at the time also held the 2,000 `walk/` files. The cause is **not established**: server-side processing lag, listing cache, or the Mac-side flag running ahead of the server. What this bounds: "the Mac says uploaded" is not "Graph lists it", so when arm A and arm B disagree about whether an object exists, the manifest must record a divergence rather than let either side's view delete the other's row. That is the arm-precedence rule in §4.2 (arm C paragraph), and it now has an observed case.

## 6. Raw event log (path-filtered)

`/tmp/fp-webedit-result.txt` from the run, 55 lines; the MARK lines are Unix timestamps.

```
MARK 1790223910.781 i-saved      → CloudStorage note.txt Modified at 1790223930.458 (+19.7 s)
MARK 1790224373.739 iii-saved    → private-store fresh/ Created 1790224348.373; CloudStorage fresh Renamed,IsDir 1790224348.575;
                                   private-store fresh/Document.docx Created 1790224361.099 / 1790224365.195; no CloudStorage event for the file
total FSEvents recorded during the run: 22,916 (almost all walk/ upload bookkeeping)
```

## 7. Probe sources

- `readfp.c`: read under `on|off|default` policy, printing the policy, flags before and after, the errno and the wall-clock time.
- `walkfp.c`: the C11 walker extended to report per entry whether `GEN_COUNT` was returned, its value, and the dataless flag. The buffer is packed in attribute **bit order**: FLAGS 0x40000, GEN_COUNT 0x80000, then FILEID 0x2000000. Parsing FILEID first yields plausible-looking wrong ids.
- `fswatch.swift`: FSEvents with file events, one TSV line per event.
- `evict.swift`: `FileManager.evictUbiquitousItem(at:)`.

All sources were kept under `/tmp/c14/` for the session. The walker and reader are small enough to rebuild from the descriptions above.
