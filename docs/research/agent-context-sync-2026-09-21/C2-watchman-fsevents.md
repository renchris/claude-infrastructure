# C2 — Local filesystem change tracking on macOS as the no-API "since token"

Axis: L1 acquisition (no-API path) + L2 change-set computation, for `docs-source/` fed by the
OneDrive/SharePoint sync client or by hand. Measured 2026-09-21 on macOS 15.7.9 (24G830), APFS.

---

## VERDICT (lead with this)

**No off-the-shelf watcher gives you a durable since-token. Watchman's clock dies with its daemon
(proved in source), and `fswatch` hardcodes "since now" (proved in source). The durable token exists
— it is the fseventsd per-volume journal event ID, the thing Time Machine has used since 10.5 — but
the only shipping consumer that exposes it to you is the `fsevents` npm binding, which accepts a
`since` argument and hands you per-event ids while never validating the journal UUID Apple requires
you to check.**

**And the biggest finding is not a watcher at all.** `getattrlist(2)`'s `ATTR_CMN_GEN_COUNT` is a
per-file, kernel-maintained, monotonic **data**-modification counter. Measured here, it is strictly
stronger than every change-detection heuristic in the brief: it fires on an in-place same-size
overwrite whose mtime was rolled backwards (which rsync's quick check cannot see), and it does **not**
fire on `chmod`, on an xattr write, or on `touch` (all of which move `ctime` and therefore produce
false positives in git's stat cache). Paired with `ATTR_CMN_FILEID` it also distinguishes an in-place
edit from an Office-style safe-save (write temp → rename over), which is the exact mutation shape the
operator described. It is obtainable in bulk by `getattrlistbulk(2)` — one syscall per directory, zero
file opens, therefore **zero cloud downloads**.

**Recommended combination — three tiers, with the fallback always cheap, never merely possible:**

| Tier | Mechanism | Role |
|---|---|---|
| **T1 — live** | `fsevents` npm (`FSEventStreamCreate` + `FileEvents` + `UseExtendedData`) on `docs-source/`, latency 1–5 s, persisting `(eventId, volumeUUID, wallclock)` after every drained batch | Sub-second "something under this path changed" → a **path candidate set**, never a change log |
| **T2 — catch-up** | Restart with the stored `eventId` as `sinceWhen`. Abort to T3 if the volume UUID changed, if `MustScanSubDirs`/`UserDropped`/`KernelDropped`/`EventIdsWrapped` arrives, or if the stored wallclock is older than your journal-horizon budget | Bounded downtime recovery without a full walk |
| **T3 — truth** | `getattrlistbulk` walk of `docs-source/` collecting `(relpath, FILEID, GEN_COUNT, SIZE, MODTIME, FLAGS)`; diff against the stored manifest; hash **only** rows whose `(FILEID,GEN_COUNT)` moved | The authority. Always available, so T1/T2 are pure accelerators and never correctness-critical |

T1 and T2 are optional optimisations. **T3 alone is a correct pipeline** — and on a metadata-only walk
it is cheap enough that "always sync on demand" is viable without any watcher, which removes
Watchman, Homebrew, launchd daemons and IT-approval from the critical path entirely.

---

## Comparison table

| Tool / mechanism | Since-token | Survives process restart? | Survives reboot? | Deletes reported? | Renames reported? | Catch-up cost after downtime | CloudStorage / File Provider | Evidence |
|---|---|---|---|---|---|---|---|---|
| **fseventsd journal** (`FSEventStreamCreateRelativeToDevice`, `sinceWhen=<stored id>`) | **yes** — 64-bit event id, guarded by `FSEventsCopyUUIDForDevice(dev)` | **yes** (the id is yours, on disk) | **yes** — "guaranteed to always be increasing … even across system reboots and moving drives from one machine to another" | as a **path to re-stat**, not as a delete record | `ItemRenamed` on both sides, no pairing except via `fileID` extended data | O(events since id), *if* still in the journal; horizon undocumented | UUID is `NULL` on read-only volumes ⇒ no historical events; FP behaviour **unmeasured** (see gap) | FSEvents.h:124-135, 666-680, 943-975 |
| **Watchman** `since` + clock id | yes *within one daemon* | **NO** | **NO** | yes — `exists:false` per file | as delete+create on the two paths | **full recrawl** of the tree (`is_fresh_instance:true`) | needs Homebrew + a launchd agent; FP behaviour unmeasured | `watchman/Clock.cpp` `ClockSpec::evaluate()`; `watchman/watcher/fsevents.cpp:518` |
| **Watchman** named cursor `n:foo` | yes, daemon-lifetime only | **NO** (`cursorMap` is in-memory, per-root) | **NO** | same as above | same as above | same as above | same | `Clock.cpp` `NamedCursor` branch; docs: "not possible to roll back a named cursor", "requires an exclusive lock on the view" |
| **fswatch** | **none** | n/a | n/a | via `Removed` flag while running | via `Renamed` flag while running | **every change during downtime is lost, silently** | same | `fsevents_monitor.cpp:361` passes `kFSEventStreamEventIdSinceNow` unconditionally |
| **chokidar / node `fsevents`** | **yes, exposed** — `fsevents.watch(path, since, cb)`, callback gets `(path, flags, id)` | yes if you persist `id` | yes (journal-backed) | `ItemRemoved` flag | `ItemRenamed` flag | O(events) — **but no UUID check, so a purged/wrapped journal silently under-reports** | same | `fsevents.js:16-37`; `src/fsevents.c:212` uses `FSEventStreamCreate` (per-host); `grep -c CopyUUIDForDevice\|RelativeToDevice` = **0** |
| **entr / kqueue** | none | n/a | n/a | only for watched fds | no | total loss | one fd per file — does not scale to thousands | fswatch README: kqueue "requires a file descriptor to be opened for every file being watched … scales badly" |
| **git-style stat cache** (`ino,size,mtime,ctime,uid,gid,mode`) | the stored index itself | **yes** | **yes** | yes (path absent from walk) | as delete+create unless you join on `ino` | **O(tree) metadata walk** | safe — `lstat` only, no opens | `Documentation/technical/racy-git.adoc` |
| **rsync quick check** (`size` + `mtime`) | the destination tree | yes | yes | with `--delete` | no | O(tree) metadata walk | safe | rsync.1: "a 'quick check' algorithm (by default) that looks for files that have changed in size or in last-modified time" |
| **`rsync -c`** | as above | yes | yes | yes | no | **O(bytes) — reads every file** | **catastrophic**: materialises the whole cloud tree | rsync.1 `-c`: "both sides will expend a lot of disk I/O reading all the data in the files" |
| **`getattrlistbulk` + `(FILEID, GEN_COUNT)`** ★ | the stored manifest | **yes** | **yes** | yes | yes — `FILEID` is stable across `rename(2)`, measured | **O(tree) metadata walk, one syscall per directory, no opens** | safe by construction; **`GEN_COUNT` support on FP volumes unmeasured** | `man 2 getattrlist`; measured below |
| **`eslogger`** (Endpoint Security) | none (live stream) | no | no | yes, authoritatively, with process attribution | yes, with source+target | total loss | needs **root + Full Disk Access**; corporate-hostile | `/usr/bin/eslogger` present on 15.7.9 |

★ = recommended as the authority.

---

## (a) Does Watchman's clock survive a daemon restart, and how does it recrawl?

**No, and this is structural, not a bug.** The clock string is `c:<proc_start_time>:<pid>:<root_number>:<ticks>`
(`Clock.cpp` `clock_id_string()`), and `ClockSpec::evaluate()` says so in a comment:

> `// If the pid, start time or root number don't match, they asked a`
> `// different incarnation of the server or a different instance of this`
> `// root, so we treat them as having never spoken to us before.`
> `since_clock.is_fresh_instance = true; since_clock.ticks = 0;`

A new daemon has a new pid **and** a new start time, so *every* persisted clock is a fresh instance.
Named cursors are worse: they live in an in-memory `folly::Synchronized<unordered_map>` passed to
`evaluate()`, so they vanish with the process and cannot be rolled back
(docs/clockspec: "it's not possible to 'roll back' a named cursor"; "we recommend not using the
`n:whatever` form as it requires an exclusive lock on the view").

Three further fresh-instance doors, all documented:

- **GC age-out.** `evaluate()`: `is_fresh_instance = clock.position.ticks < lastAgeOutTick`. config/gc_age_seconds
  (default 43200): "Any since queries based on a clock prior to the last prune clock will be treated as
  a fresh instance query."
- **Root re-watch.** `root_number` differs ⇒ fresh instance.
- **Dropped events.** `fsevents.cpp:724-732` → `root->scheduleRecrawl(flags_label)` on
  `UserDropped|KernelDropped`.

**And Watchman deliberately never replays the journal at startup.** `fsevents.cpp:518` creates the
initial stream with `kFSEventStreamEventIdSinceNow`. The journal-replay path exists
(`fsevents.cpp:325-385`, which correctly calls `FSEventsCopyUUIDForDevice` and refuses on a UUID
mismatch) but is only reachable from a mid-session drop, and its config default was **turned off**:

> `fsevents_try_resync` … *"Since December 2021. The default changed to false. There are possible
> undiagnosed correctness issues with this setting."*

⇒ **Cost of a Watchman restart on a hundreds-of-GB tree is a full metadata recrawl**, every reboot,
every `brew upgrade`, every OOM. Watchman is the wrong L1 for a durable pipeline. It remains excellent
as a *live* accelerator inside a long-lived session, and its `exists:false` per-file delete reporting
is genuinely better than raw FSEvents.

*(Empirical-from-source. Watchman is not installed on this machine — `command -v watchman` fails — so
this was read, not executed. The two claims that matter are single-expression code, not behaviour
under load.)*

---

## (b) FSEvents event-id persistence, and the "must rescan" flag

**Persistence — the strongest quote in the corpus** (`FSEvents.h:666-680`):

> "Event IDs all come from a single global source. They are **guaranteed to always be increasing,
> usually in leaps and bounds, even across system reboots and moving drives from one machine to
> another.** … if you were to stop processing events from this stream after this callback and resume
> processing them later from a newly-created FSEventStream, this is the value you would pass for the
> `sinceWhen` parameter."

And `FSEvents.h:124-135`:

> "Clients can store this value persistently **as long as they also store the UUID for the device**
> (obtained via `FSEventsCopyUUIDForDevice()`). … This works because the FSEvents service stores
> events in a **persistent, per-volume database**."

**The UUID is the invalidation token** (`FSEvents.h:943-975`):

> "If this (non-NULL) UUID is different than one that you stored from a previous run then the event
> stream is different (for example, because FSEvents were purged, because the disk was erased, or
> because the event ID counter wrapped around back to zero). **A NULL return value indicates that
> 'historical' events are not available**, i.e., you should not supply a 'sinceWhen' value … other
> than `kFSEventStreamEventIdSinceNow`."

**Must-rescan** (`kFSEventStreamEventFlagMustScanSubDirs`, 0x1):

> "Your application must rescan not just the directory given in the event, but all its children,
> recursively. … you may be able to get an idea of whether the bottleneck happened in the kernel
> (less likely) or in your client (more likely) by checking for … `UserDropped` or `KernelDropped`."

Also `EventIdsWrapped` (0x8) → "previously-issued event ID's are no longer valid arguments for the
`sinceWhen` parameter", and `RootChanged` (0x20, requires `WatchRoot`) → your watched directory itself
moved; event id is **zero**, so do not persist it.

**The caveat that outranks the whole mechanism** (`FSEvents.h` event-flags preamble):

> "event flags are simply hints about the sort of operations that occurred at that path. Furthermore,
> **the FSEvent stream should NOT be treated as a form of historical log that could somehow be
> replayed to arrive at the current state of the file system.** The FSEvent stream simply indicates
> what paths changed; and clients need to reconcile what is really in the file system with their
> internal data model."

⇒ *Architectural consequence, load-bearing for the lead's L2:* **FSEvents can only ever produce a
candidate path set. The content-addressed manifest is not an optimisation, it is the thing that turns
hints into a change set.** Any design that treats FSEvents flags as the created/updated/deleted verdict
is wrong by Apple's own statement.

Two more documented levers worth knowing:
- `FSEventsGetLastEventIdForDeviceBeforeTime(dev, t)` — "**conservative** … you will not miss any events
  that happened since that time. On the other hand, you might receive some (harmless) extra events."
  This converts a wallclock into a safe `sinceWhen`, which is how you recover when you have a timestamp
  but no id. Its own warning: clock changes and cross-machine drives break its accuracy.
- Golden example: **Time Machine.** "Time Machine simply keeps track of the last FSEvent identifier
  which it handled when making the last backup, and has no need for timestamps"; when the database is
  unusable its fallback is a **deep event scan** that "checks the last modified timestamp of all the
  files and folders on that volume." The journal is `/.fseventsd` on each volume, containing serialised
  hex-named `.fsevents` files ("typically 10-20 per day") plus `fseventsd-uuid`; an empty file named
  `no_log` in that folder disables recording. (eclecticlight.co, Howard Oakley.) **Our T1/T2/T3 ladder is
  literally Time Machine's architecture.**

**Undocumented and therefore a named risk:** Apple never says what happens when `sinceWhen` is older
than the pruned journal horizon. It is not an error and there is no flag for it, so the plausible
failure is *silent under-reporting* — the worst possible shape. Mitigation is already in the ladder:
store wallclock beside the id and fall through to T3 whenever the gap exceeds a conservative budget
(start at 7 days) rather than trusting the journal to have kept up.

---

## (c) `~/Library/CloudStorage` / File Provider — what is known, what is not

**Known, from Apple, primary:** a File Provider replicated extension's items can be *dataless*, and
**access is what downloads them**:

> "When users or system APIs access a dataless item (a file that has the metadata only), the system
> calls the method … to tell the file provider to fetch the file content"
> — *Synchronizing files using file provider extensions*, Apple

**Known, from the kernel headers, and this is the safety belt nobody in the brief has:**
`sys/resource.h:509,538-540` defines `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` with
`IOPOL_MATERIALIZE_DATALESS_FILES_OFF`, and `man 3 setiopolicy_np` documents it:

> "`IOPOL_MATERIALIZE_DATALESS_FILES_OFF` — Disables materialization of dataless files by the current
> thread or process. … New processes inherit the policy of their parent process."

⇒ **Run the whole scanner/converter tree under `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`.** Then a bug in a converter cannot
accidentally pull 200 GB down a corporate VPN; it gets an error instead. Note the man page also claims
the *system* default for `IOPOL_SCOPE_PROCESS` is already OFF, which **contradicts** the observed
behaviour that traversal materialises things (fish-shell#8399: a `**` glob took 9,486 ms and flipped
directories from dataless `%` to materialised `@`). Do not rely on the default; set it explicitly.

**Known, on-disk shape of the OneDrive case** (community investigation, lijunle gist — secondary but
specific and checkable): two paths, not one —
`~/Library/CloudStorage/OneDrive-<Account>/` (the File Provider presentation) and
`~/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite/OneDrive.noindex/OneDrive/` (the
client's private store) — with online-only = 0 copies, cached = 1, **pinned = 2 copies**, and
"`SF_DATALESS` … a kernel-level BSD file flag, maintained by the File Provider system" as the
online-vs-downloaded marker. `SF_DATALESS = 0x40000000` is confirmed in
`sys/stat.h:359`, and `st_flags` is already in the `getattrlistbulk` attribute set, so **the T3 walk
detects dataless-ness for free and can skip hashing those rows instead of downloading them.**

**NOT KNOWN — the gap, stated plainly.** This machine has **zero** File Provider domains
(`ls ~/Library/CloudStorage` is empty; `mount` shows no FP entry; `/` and `/System/Volumes/Data` share
`dev_t=16777234`), so **none of the following could be measured here**:

1. whether an FP domain is a distinct `dev_t` (⇒ a distinct fseventsd journal, or none at all);
2. whether `FSEventsCopyUUIDForDevice` returns non-NULL for it (NULL ⇒ **no durable since-token on
   that path, at all**, and the T1/T2 tiers collapse to "since now");
3. whether FSEvents fires for changes pushed *from the server* (as opposed to local writes), which is
   the only case that matters for an inbox fed by colleagues;
4. whether `ATTR_CMN_GEN_COUNT` is supported by the FP filesystem (if unsupported it is simply absent
   from `ATTR_CMN_RETURNED_ATTRS` — fail-visible, not fail-silent, which is the good failure mode).

**The ONE experiment that settles all four**, ~15 minutes on a machine with OneDrive signed in:

```
# 1. identity: is the domain its own device, and does it have a journal?
stat -f 'dev=%d %N' ~ ~/Library/CloudStorage/OneDrive-*      # same dev_t as $HOME, or not?
#    then, from a 20-line C program: FSEventsCopyUUIDForDevice(st.st_dev) on that path
#    -> NULL means: no durable token here, ever.
# 2. does GEN_COUNT survive the FP filesystem?
./gc4 ~/Library/CloudStorage/OneDrive-*/some.xlsx            # returned_attrs must include GEN_COUNT
# 3. server-pushed change visible?  Edit the SAME file in the web UI (or from a second machine),
#    with a since-token watcher already running on the CloudStorage path, and a second one running on
#    the Group Containers private store. Record which one fires, with which flags.
# 4. restart the watcher with the stored eventId and confirm the server-side edit replays.
```
Run arm 3 twice: once with the file **cached** and once **online-only**. My prediction (theoretical,
40% confidence, and the reason the experiment is worth running rather than reasoning about): the
CloudStorage path fires `ItemModified` for a locally-edited cached file, fires little or nothing useful
for a server-pushed change to an online-only file (the metadata changes but no data is written
locally), and `FSEventsCopyUUIDForDevice` on the FP dev returns **NULL** — which would make **T3 the
only correct tier for cloud paths** and make "sync the client, then walk metadata on demand" the whole
design.

**Cheap structural hedge that makes the experiment's outcome not matter:** point `docs-source/` at a
**local** directory and have a small scheduled job `rsync` (quick-check, no `-c`) from the cloud path
into it. Then every guarantee above is recovered on APFS, where it is proved, and the cloud path is
touched only by one metadata walk. Costs one copy of the corpus on disk; buys the entire correctness
story. Directory-symlinking `docs-source` → CloudStorage does **not** buy this: `FSEventStreamCreate`
watches the resolved hierarchy, and Watchman's `since` generator explicitly "does not consider the
targets of symlinks" (file-query docs), so symlinks move the problem rather than solving it.

---

## (d) How git and rsync detect changes cheaply — and the false-negative rate of mtime-only

**git** (`Documentation/technical/racy-git.adoc`): the index caches `lstat(2)` output and compares

> "the file type (regular files vs symbolic links) and executable bits (only for regular files) from
> `st_mode` member, `st_mtime` and `st_ctime` timestamps, `st_uid`, `st_gid`, `st_ino`, and `st_size`"

`st_dev` is excluded by default "because this member is not stable on network filesystems" — relevant:
do not put `dev` in your manifest key either. The documented false negative:

> ": modify 'foo' / `$ git update-index 'foo'` / : modify 'foo' again, in-place, without changing its
> size … the cached stat information the index entry records still exactly match what you would see in
> the filesystem, even though the file `foo` is now different."

git's two defences: re-hash any entry whose `st_mtime` is ≥ the index file's own mtime, and truncate
cached `st_size` to zero for racily-clean entries on write.

**rsync**: "a 'quick check' algorithm (by default) that looks for files that have changed in size or in
last-modified time." `-c` "changes this to compare a checksum for each file that has a matching size…
both sides will expend a lot of disk I/O reading all the data in the files." `--size-only` is weaker
still. `--modify-window` defaults to whole seconds; a negative value opts into nanoseconds.

**Measured false-negative rate of mtime-only, on the operator's actual mutation shapes** — probe
`getattrlist` with `ATTR_CMN_GEN_COUNT|ATTR_CMN_FILEID` under `FSOPT_ATTR_CMN_EXTENDED`, APFS,
macOS 15.7.9:

| Mutation | `size`+`mtime` (rsync) | `+ctime,ino` (git) | `(FILEID, GEN_COUNT)` |
|---|---|---|---|
| create, 4 B | n/a | n/a | GEN=2, FILEID=1066186937 |
| same-size in-place overwrite, **mtime rolled back** | **MISSED** | caught (ctime moved) | **caught** — GEN 2→4 |
| safe-save: write temp + `mv -f` over (Word/Excel) | caught | caught | **caught** — FILEID 1066186937→**1066186960**, GEN resets to 2 |
| `rename(2)` to a new name | — | joins on `ino` | FILEID **unchanged** — a true rename, not delete+create |
| `chmod 600` | no change | **FALSE POSITIVE** (ctime) | no change |
| `xattr -w` (Finder tag, quarantine, pin state) | no change | **FALSE POSITIVE** (ctime) | no change |
| `touch` (mtime bump, identical bytes) | **FALSE POSITIVE** | **FALSE POSITIVE** | no change |
| rewrite byte-identical content | false positive | false positive | false positive — GEN 2→4 |

`man 2 getattrlist`:

> "`ATTR_CMN_GEN_COUNT` — A `u_int32_t` containing a non zero monotonically increasing generation count
> for this file system object. The generation count tracks the number of times the data in a file system
> object has been modified. No meaning can be implied from its value. The value … can be compared
> against a previous value of the same file system object for equality; i.e. **an unchanged generation
> count indicates identical data.** Requesting this attribute requires the `FSOPT_ATTR_CMN_EXTENDED`
> option flag. A generation count value of 0 is invalid… An invalid generation count value of 0 will be
> returned for **mmap'ed** files."

So the practical rule: **`(FILEID, GEN_COUNT)` is a sound "may have changed" token with no
metadata-only false positives; it is not a content hash (a byte-identical rewrite bumps it), so hash
the survivors.** That is exactly two tiers, and the second tier is small.

**`ATTR_CMN_DOCUMENT_ID` is a trap — ruled out empirically.** Its documentation is perfect for this
problem ("used to track the data regardless of where it gets moved. The document id survives safe
saves; i.e it is sticky to the path it was assigned to"), but measured on plain files created by
`printf`/`cp`/`mv` on APFS it returned **0 for every case**, and "A document id of 0 is invalid." It is
assigned by document-based-app machinery, not by the filesystem for arbitrary files. Do not build
identity on it.

**Gotchas in the probe itself, recorded so the next session does not lose an hour:**
`ATTR_CMN_GEN_COUNT` and `ATTR_CMN_DOCUMENT_ID` go in **`commonattr`**, not `forkattr` — they "reuse
the bits originally allocated to `ATTR_CMN_NAMEDATTRCOUNT`/`NAMEDATTRLIST`" (xnu
`bsd/vfs/vfs_attrlist.c:3341-3361`), and putting them in `forkattr` yields a bare `EINVAL` with no
diagnostic. Always request `ATTR_CMN_RETURNED_ATTRS` and read it: an unsupported attribute is simply
absent, which is how you detect FP/SMB non-support instead of silently reading a zero. Working probe:
`scratchpad/gcprobe/{gc3.c,gc4.c}`.

---

## Alternatives considered and ruled out

| Ruled out | Reason |
|---|---|
| **Watchman as L1 since-token** | clock dies with the daemon (Clock.cpp), startup is always `SinceNow` (fsevents.cpp:518), journal resync default-off since Dec 2021 with "possible undiagnosed correctness issues". Also: not installed here, i.e. needs Homebrew in a managed corporate fleet. |
| **fswatch** | `kFSEventStreamEventIdSinceNow` hardcoded at fsevents_monitor.cpp:361. No catch-up, and downtime loss is silent. |
| **entr / kqueue** | one fd per file; "scales badly with the number of files being observed" (fswatch README) — a non-starter at thousands of files. |
| **Polling / `fswatch` poll monitor** | "performance … degrades linearly with the number of files being watched"; identical cost to T3 with none of T3's manifest, so use T3. |
| **`rsync -c` as the diff engine** | reads every byte; on a File Provider tree that means downloading the corpus. `rsync` quick-check is fine as a *copier*, never as the change detector of record. |
| **`eslogger` / Endpoint Security** | authoritative and rename-correct, but root + Full Disk Access + TCC prompts; the brief's premise is that IT restricts even a Graph app registration. |
| **Spotlight (`mdfind`/`kMDItemFSContentChangeDate`)** | its index is a *different* since-token with its own staleness, it is excluded on `.noindex` paths (OneDrive's private store is literally named `OneDrive.noindex`), and querying it can touch dataless items. |
| **`ATTR_CMN_DOCUMENT_ID` as identity** | measured 0 (= invalid) on every plain file. |
| **Symlinking `docs-source` → CloudStorage** | FSEvents watches the resolved tree; Watchman's since generator "does not consider the targets of symlinks". Moves the problem. |
| **`FSEventsPurgeEventsForDeviceUpToEventId`** | root-only, and destroys the journal other consumers (Time Machine) depend on. Never call it. |

---

## Adversarial pass

- **"gen_count makes hashing unnecessary."** False. It counts *writes*, not content changes: rewriting
  byte-identical content bumped GEN 2→4 in measurement. It shrinks the hash set; it does not remove it.
  The manifest still needs a content hash for idempotent conversion and for detecting the re-upload of
  an identical file under a new versioned name.
- **"gen_count is the perfect token, so drop mtime/size."** Don't. GEN is `u_int32_t` — it wraps, it is
  0 for mmap'ed files, and it is unsupported on some filesystems. Keep `(SIZE, MODTIME)` in the manifest
  as a second opinion and treat a *decrease* in GEN, or GEN==0, as "unknown ⇒ hash it".
- **"FSEvents gives me created/updated/deleted."** Apple's own header forbids that reading: the stream
  "should NOT be treated as a form of historical log that could somehow be replayed". Flags are hints.
- **"My in-place-overwrite test proves git's stat cache is broken."** It does not. `touch -t` moves
  `ctime`, and git compares `st_ctime`, so git catches my exact case; **rsync's quick check is the one
  that misses it.** The real-world case that beats git too is narrower: a same-second, same-size
  modification. The reason this still matters here is that a sync client writing a downloaded file sets
  mtime from the *server*, so preserved-mtime same-size overwrites are a normal event in this corpus,
  not a contrived one.
- **"Watchman's `exists:false` means Watchman handles deletes and FSEvents doesn't."** Only within one
  daemon lifetime, and only for up to `gc_age_seconds` (12 h default) after the delete, after which the
  node is pruned and the query becomes a fresh instance. A deletion that happens while your process is
  down is recovered by T3 for both tools.
- **"Persisting the id from node-fsevents is safe because Apple says ids persist."** No: Apple's
  persistence contract has two halves and the binding implements one. `src/fsevents.c:212` uses the
  **per-host** `FSEventStreamCreate`, and Apple says "if you are writing software that requires
  persistence, you should use per-disk streams to avoid any confusion due to ID conflicts"; `grep -c
  'CopyUUIDForDevice\|RelativeToDevice' src/fsevents.c` = **0**, so there is no UUID guard. Either shell
  out to a 20-line UUID reader before resuming, or read `/.fseventsd/fseventsd-uuid` on the volume
  (root-readable only here: `ls /System/Volumes/Data/.fseventsd` → *Permission denied*), or accept T3.
- **Every since-token in this space expires the same way, including the Graph one on the other axis.**
  Watchman → `is_fresh_instance`. FSEvents → UUID change / `EventIdsWrapped` / journal pruning. File
  Provider's own internal token → "If the system queries the working set enumerator with a sync anchor
  that's already aged out, the enumerator needs to report [expired] so the system restarts the sync
  operation from the beginning." Graph → deltaLink expiry ⇒ full resync. **Therefore the
  architecturally load-bearing decision is not which token to use; it is making the full-resync path
  cheap.** `getattrlistbulk` over metadata with no file opens is what makes it cheap. Design the
  pipeline so the token is an accelerator you could delete.
- **Unmeasured and I am not going to pretend otherwise:** throughput of a `getattrlistbulk` walk over a
  hundreds-of-GB / 10⁵-file corporate tree, cold vs warm cache, local vs File Provider. That number
  decides whether T1/T2 are worth building at all. It is one afternoon's measurement on a real
  `docs-source` and it should be taken before any watcher code is written.

---

## Pipeline slot rows (the brief's sample-row shape)

- **Mechanism:** fseventsd journal event id + device UUID | **Gives:** O(changes) path candidates since a
  stored id, surviving reboot | **Golden example:** Time Machine (`.fseventsd`, last-handled event id,
  deep-scan fallback) | **Limits:** paths only, never a change log; journal horizon undocumented; UUID
  NULL ⇒ unusable | **Slot:** L1 (accelerator) | **Evidence:** FSEvents.h:124-135, 666-680, 943-975;
  eclecticlight.co 2017-09-12.
- **Mechanism:** `getattrlistbulk` + `(ATTR_CMN_FILEID, ATTR_CMN_GEN_COUNT, SIZE, MODTIME, FLAGS)` |
  **Gives:** rename-correct, metadata-only-false-positive-free change set with one syscall per directory
  and zero file opens | **Golden example:** none found — this is the gap in every tool surveyed |
  **Limits:** O(tree) walk; GEN wraps, is 0 for mmap'ed files, FP support unmeasured | **Slot:** L2
  (authority) | **Evidence:** `man 2 getattrlist`/`getattrlistbulk`; measurements above.
- **Mechanism:** `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, …_OFF)` + `SF_DATALESS` in
  `st_flags` | **Gives:** a hard guarantee the pipeline never downloads the corpus, and a free
  online-only marker in the same attribute fetch | **Golden example:** the negative one — fish-shell
  `**` materialising a cloud tree in 9.5 s | **Limits:** turns an accidental read into an error, so
  converters must handle it | **Slot:** L1/L3 safety belt | **Evidence:** `man 3 setiopolicy_np`;
  `sys/resource.h:509,538-540`; `sys/stat.h:359`.
- **Mechanism:** Watchman `since` + clock | **Gives:** low-latency per-file change list with explicit
  `exists:false` deletes inside one session | **Limits:** clock dies with the daemon; startup is always
  `SinceNow`; recrawl on drop; needs Homebrew | **Slot:** L1 live accelerator only, never the token of
  record | **Evidence:** `Clock.cpp`, `watcher/fsevents.cpp:518`, config docs.
