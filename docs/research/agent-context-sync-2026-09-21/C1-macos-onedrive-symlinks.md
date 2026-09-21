# C1 — macOS OneDrive/SharePoint sync client as a substrate for a local agent, and the symlink question

**Verdict in one line:** the OneDrive File Provider tree is a *good* metadata source and a *bad* content
source, and `docs-source → ~/Library/CloudStorage/...` as a symlink is **acceptable for access only if every
tool is aimed at the link itself** and **unusable for change awareness or for git** — 5 of 6 measured
traversal surfaces, including Claude Code's own `Grep`/`Glob`, silently skip it when walking from an
ancestor, and git stores it as a 120000 link blob whose content is never tracked.

**Instrument warning that bounds this whole report:** `~/Library/CloudStorage/` is **empty on this machine**
(`ls -la` → 2 entries, both `.`/`..`; `mount | grep -i cloud` → nothing). No OneDrive, Dropbox or Google
Drive sync client is installed, and `~/Library/Mobile Documents/com~apple~CloudDocs` is empty, so iCloud
Drive carries no content either. **Every dataless/placeholder behaviour below is therefore `documented`, not
`measured-here`.** Everything about symlink traversal, the agent's tools, git, and the local API surface *is*
measured here. I have not laundered one into the other; the `How verified` column says which.

---

## 1. The property table

| # | Property | Behaviour | How verified | Evidence |
|---|---|---|---|---|
| P1 | Sync-root path | Always `~/Library/CloudStorage/OneDrive-<Tenant>`; not relocatable | documented | *"With the new Files On-Demand experience, the sync root is always located within users' home directory… This location cannot be moved or changed and is controlled by macOS."* — [MS, Inside the new Files On-Demand Experience on macOS](https://techcommunity.microsoft.com/blog/onedriveblog/inside-the-new-files-on-demand-experience-on-macos/3058922) |
| P2 | **OneDrive already creates the symlink you were going to create** | A symlink is placed at the legacy location pointing into CloudStorage | documented | *"Via a symlink at the original location the user picked when setting up OneDrive… if the user chose to sync OneDrive at ~/OneDrive, then a symlink will be created from here to ~/Library/CloudStorage/OneDrive-Personal."* — ibid. |
| P3 | Placeholder metadata without hydration | name, size, mtime, icon are known to the OS for un-downloaded files | documented | *"As part of telling the File Provider platform about your files, we include metadata about them, so that the operating system knows how big they are, what icons to show, and so forth."* — ibid. |
| P4 | Dataless files consume no bytes and **do not count against free space** | `statfs` over-reports free space by the size of evictable content | documented | *"Files that are kept in the sync root do not count against disk space usage, unless they are marked as 'Always Keep on This Device.'… if an application asks, 'How much space is free on this disk?' that answer will exclude these files."* — ibid. |
| P5 | **Dataless *directories* exist, and listing one is a network round trip** | Eviction makes a directory dataless; the next access re-fetches its child list from the provider | documented | *"After it has successfully evicted all the content, it deletes its list of the directory's content, making the directory dataless. The next time the system accesses the directory, it requests a list of the contents using the protocol."* — [Apple, `evictItem(identifier:completionHandler:)`](https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager/evictitem(identifier:completionhandler:)) |
| P6 | **`ls` has a flag that exists solely because of P5** | `ls -%` marks dataless items **and suppresses directory materialization** | measured-here (man page on this box) | `man ls` → *"-% Distinguish dataless files and directories with a '%' character in long (-l) output, **and don't materialize dataless directories when listing them**."* |
| P7 | Items may not exist on disk **at all** until first browsed | The provider does not create local nodes until enumerated | documented | *"This will ensure all of your files and folders are created, but not downloaded, before you browse."* (describing the Always-Keep-on-This-Device pre-create trick) + heading *"Why is it sometimes slow to browse folders in my OneDrive?"* — MS blog |
| P8 | The dataless bit is a real, readable POSIX flag | `SF_DATALESS = 0x40000000` in `st_flags` | measured-here (SDK header on this box) | `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/stat.h:359` — `#define SF_DATALESS 0x40000000 /* file is dataless object */` |
| P9 | `st_flags` is reachable from shell and from Python without opening the file | `stat -f '%Sf'`, `ls -lO`, `ls -l%`, `os.stat().st_flags` | measured-here | `stat -f '%N flags=[%Sf] st_blocks=%b size=%z'` → `flags=[-] st_blocks=8 size=26`; `python3 -c "os.stat(p).st_flags"` → `0x0`, `SF_DATALESS set=False`. (Positive control unavailable — see §5 B1.) |
| P10 | **Hydration can be switched OFF per-process, and children inherit it** | `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)` | measured-here (header + man page on this box) | `sys/resource.h:509` `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES 3`; `:539` `IOPOL_MATERIALIZE_DATALESS_FILES_OFF 1`. `man 3 getiopolicy_np`: *"Disables materialization of dataless files by the current thread or process."* … *"New processes inherit the policy of their parent process."* |
| P11 | Hydration is **not durable** | macOS evicts hydrated content under disk pressure, at any time | documented | *"Files that have data in the sync root can be evicted at any time."* / *"in low disk space situations, these files can be automatically evicted from the disk to make room for more data."* — MS blog |
| P12 | The dataless *flag* is not a reliable "will this read hit the network" oracle | Content can be in OneDrive's private cache while the sync-root item still reads as dataless | documented | *"the current implementation of File Provider does not allow us to tell the operating system that we already have the file's contents available – so they appear to be online-only, even though their contents are safe in our cache"* — MS blog |
| P13 | **Spotlight indexes the names but not the contents** | `mdfind` is content-blind over a mostly-dataless library | documented | *"Spotlight indexes everything that is in your sync root, but note that Spotlight will not fetch (or hydrate) files that are dataless."* — MS blog |
| P14 | "Always Keep on This Device" = pinning; "Free Up Space" = eviction | Pinned ⇒ non-evictable and downloaded; folders inherit, including new children | documented | *"When a file is pinned, it is downloaded to disk and is always available offline… Folders can also be pinned, which means that all files and folders underneath the folder will inherit the state, and new files added to that folder will also inherit the state."* + *"'Free Up Space' option to immediately evict its data."* — MS blog |
| P15 | Symlinks inside the sync root are preserved locally but **corrupted on the round trip** | They upload as a plain text file containing the target path | documented | *"They are preserved as a symlink in the sync root but do not sync to the cloud as a symlink… the symlink will sync to the cloud as a plain text file with the symlink target as its contents."* — MS blog |
| P16 | Local CLI tooling for provider state exists | `brctl` (iCloud only) and `fileproviderctl` are both present | measured-here | `command -v` → `/usr/bin/brctl`, `/usr/bin/fileproviderctl`. `fileproviderctl dump` ran and printed `3 providers`, live domain state, and per-process enumerator rows. `fileproviderctl` subcommands: `dump`, `diagnose`, `evaluate`, `check|repair`, `obfuscate`. **Output shape over a populated OneDrive domain is unverified** (no such domain here). |
| P17 | Apple exposes "what is already local" as an API, not a CLI | `NSFileProviderManager` *"Returns an enumerator for all the items the system currently stores on disk."* | documented | [Apple, replicated File Provider extension](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension): *"The second lets your app enumerate the items stored locally by the system."* |
| P18 | The OS has a delta protocol — but it belongs to the **provider**, not to you | `enumerateChanges(for:from:)` + sync anchor is implemented *by* the extension | documented | [Apple, `NSFileProviderEnumerator`](https://developer.apple.com/documentation/fileprovider/nsfileproviderenumerator): *"Returns the current sync anchor."* / *"Requests the next batch of changes after the specified sync anchor."*; [`NSFileProviderChangeObserver`](https://developer.apple.com/documentation/fileprovider/nsfileproviderchangeobserver): *"Tells the observer that all of the changes have been enumerated up to the specified sync anchor."* |

---

## 2. Symlink traversal — fully measured on this machine

Fixture: `exp/top/{plain.txt, docs-source → exp/real/}`, where `exp/real` holds `a.txt` and `sub/b.txt`.
All three files contain the same needle. **Correct answer = 3 files.**

| Surface | From an **ancestor** (walk meets the symlink) | With the **symlink as the explicit start path** | Fix available? |
|---|---|---|---|
| `rg` 15.2.0 (default) | **1 of 3** — skips it silently | **2 of 2** — traverses | `rg --follow` → 3 of 3 |
| `rg --files` (the `Glob` analogue) | **1 of 3** | **2 of 2** | `--follow` |
| `rg --files --glob '**/*.txt'` | **1 of 3** | — | `--follow` |
| BSD `grep -r` | **1 of 3** | n/a | `grep -R -S` (see below) |
| BSD `grep -R` | **1 of 3** — `-R` does **not** follow on macOS | n/a | `-S` |
| BSD `find` (default `-P`) | **1 of 3** | **0 files — a silent empty result** | `find -L`, or `find -H`, or a trailing `/` |
| zsh `**/*.txt` | **1 of 3** | — | `***/` |
| **Claude Code `Grep`** | **1 of 3** (inherits rg's default) | **2 of 2** | **NONE — no flag exists** |
| **Claude Code `Glob`** | **1 of 3** | **2 of 2** | **NONE — no flag exists** |
| `git add -A` | records the link, **never its content** | n/a | none — this is by design |

Load-bearing details, each measured:

- **`grep -R` does not follow on macOS, and the man page says so.** `/usr/bin/grep --version` →
  `grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`; `man grep:208` → *"-S If -R is specified, all symbolic
  links are followed. The default is not to follow symbolic links."* The GNU habit (`-R` follows) transfers
  wrong. This extends the local lesson
  `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/recursive-grep-cannot-walk-the-symlink-layer.md`,
  which correctly says BSD `-r`/`-R` does not follow — here confirmed on macOS 15.7.9 with the `-S` cure named.
- **`find` on a symlinked start dir returns ZERO, not an error.** Exactly the failure recorded in
  `symlinked-store-invisible-to-find.md` (`~/.claude-next/projects`, 0 vs 123 files). Reproduced verbatim
  here: `find <symlink> -type f` → nothing; `find -H <symlink> -type f` and `find <symlink>/ -type f` → both
  files. A `docs-source` symlink plus any `find`-based scanner is that same bug with a cloud library behind it.
- **`git ls-files -s` → `120000 dc1dcfa11018776d586ba532eff01275de20d3fe 0 docs-source`.** Mode `120000` is a
  symlink blob; the blob's content is the 60-byte target path. `git status --porcelain` shows one entry.
  **No file under the link is ever tracked, diffed, or landed.** The lead's L5 ("git-tracked `docs/` so
  'what changed since I last looked' is a git diff") is unaffected — `docs/` is real files — but any notion
  of git-tracking `docs-source` through a symlink is dead on arrival.
- **Claude Code's tools have no escape hatch.** `~/.claude-versions/2.1.114/node_modules/@anthropic-ai/claude-code/sdk-tools.d.ts:413-483`:
  `GlobInput` is exactly `{pattern, path?}`; `GrepInput` is exactly
  `{pattern, path?, glob?, output_mode?, -B, -A, -C, context, -n, -i, type?, head_limit?, offset?, multiline?}`.
  The schema annotates `glob?` as *"maps to rg --glob"* and `path?` as *"File or directory to search in (rg PATH)"*
  — so `Grep` is a ripgrep wrapper and **exposes no follow/symlink parameter at all**. `strings` on the
  204 MB `bin/claude.exe` confirms `--follow`, `--files`, `--glob`, `--hidden`, `--no-ignore`, `ripgrep` are
  all present in the bundled ripgrep's own CLI, which means the capability ships and the tool simply does
  not surface it. Consequence: **an agent cannot repair this at call time.** The one thing that does work is
  aiming `path` at the link itself, which ripgrep follows because it is an explicit argument, not a walk edge.

---

## 3. The four key questions, answered

### (a) Can a script enumerate the whole synced library cheaply without hydrating files?

**Two different costs, and the honest answer splits.** *Bytes:* yes — P3 says name/size/mtime are known to
the OS for un-downloaded items, and P8/P9 give a per-file dataless bit readable by `stat`. *Network:* no —
P5 says an evicted (dataless) directory has no child list on disk and re-requests it from the provider on
next access, and P7 says items may have no local node until first browse. So a first `find` over a
never-browsed 200 GB library is **O(directories) provider round trips**, each of which can block, and a
subtree nobody has opened can read as *empty* rather than as *large*. That is the same failure shape as the
local `find`-on-symlink lesson: an honest-looking zero. `ls -%` (P6) existing at all is Apple conceding
that a plain listing materializes dataless directories.

- Theoretical, high confidence: **enumeration is cheap only on the second pass.** The design consequence is
  that L1's local arm must treat its first full walk as a one-time, explicitly-paced bootstrap (pin the
  library, or accept hours), and must never treat a zero-child directory as authoritative.
- Empirical corollary: **`mdfind` cannot be the content oracle** (P13) but is a legitimate *metadata* oracle
  (`kMDItemFSContentChangeDate`) that costs no provider round trips because the index is already built.

### (b) Does hashing require hydration, and can hydration be forced/avoided per file?

**Hashing local content necessarily requires hydration** — a content hash needs content; there is no
shell-reachable local API for the provider's own `NSFileProviderItemVersion`. Three consequences:

- **Avoiding it is a solved problem and the mechanism is P10.** A scanner that calls
  `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`
  and then `exec`s `find`/`rg`/`sha256sum` gets a **fail-closed walk** — children inherit the policy
  (`man 3 getiopolicy_np`), so the whole subtree of tooling becomes hydration-proof in one call, and an
  accidental `rg` over 200 GB errors instead of downloading it. *This is the single most valuable primitive
  on this axis and nothing in the lead's L1–L5 hypothesis currently names it.*
- **Forcing it per file** has no first-class CLI. Documented levers: open/read the file (the provider's
  `fetchContents` runs), or pin via Finder's "Always Keep on This Device" (P14, folder-inheriting — the
  correct bulk lever for a curated subset). `brctl download` exists but is **iCloud-only** (`brctl` is the
  CloudDocs/bird tool; OneDrive is a different File Provider domain). Third-party confirmation that
  download/evict are the only two verbs a tool gets: ChronoSync ships exactly *"Download Local Copy"* /
  *"Evict Local Copy"*, recursive on folders — [Econ Technologies, File Providers guide](https://www.econtechnologies.com/chronosync/guide-file-providers.html).
- **The right content-change oracle is the server's hash, not a local one.** Graph returns
  `file.hashes.quickXorHash` (Business/SharePoint) alongside `eTag`/`cTag`, so a same-name overwrite is
  detectable with **zero bytes downloaded**; the OneDrive scan guidance says so in as many words: *"If your
  processing requires downloading the contents of an individual file, you can use the cTag property to
  determine if the contents of the file have changed since the last time you downloaded it."*
  ([scan-guidance.md:108](https://raw.githubusercontent.com/OneDrive/onedrive-api-docs/live/docs/rest-api/concepts/scan-guidance.md))
  **This is the strongest argument in this report for keeping the Graph path as the primary L1 even though IT
  may restrict app registrations** — the no-API path cannot answer "did the content change" without paying
  for the content.
- No-API fallback, stated plainly: the tuple `(path, size, mtime, inode, SF_DATALESS)` from `stat`, with
  hydrate-and-hash **only** for the subset whose tuple moved. Weak against same-size/same-second edits;
  that residual is irreducible without Graph.

### (c) Do FSEvents fire for cloud-originated changes in CloudStorage?

**Unmeasurable on this machine — named as a blocker, not guessed.** No provider, and `pyobjc` is absent
(`python3 -c "import objc"` → ImportError; `pip list` shows no pyobjc/watchdog/fsevents), and neither
`fswatch` nor `watchman` is installed. What the evidence supports:

- Theoretical, high confidence: **for items that already have a local node, yes.** The system owns the local
  replica (*"the system takes responsibility for managing and storing the local copies"* — Apple, replicated
  extension) and the provider *"alerts the system to any remote changes to those items"*; the system then
  writes the replica's metadata, and a VFS write is what FSEvents reports. Corroborated indirectly: *"The
  system will immediately wake up and notify your File Provider extension when local changes happen"* —
  [Claudio Cambra, Build your own cloud sync using Apple FileProvider APIs](https://claudiocambra.com/posts/build-file-provider-sync/).
- Theoretical, high confidence: **for items with no local node (P7), no** — there is no inode to emit an
  event about. So an FSEvents watcher over a partially-browsed library has a **blind region proportional to
  how much of the library nobody has opened**, and its silence is indistinguishable from "nothing changed".
  That is the alarm-polarity failure this repo already has a rule for.
- Empirical, cited: FSEvents is lossy independent of cloud storage — the kernel drops events under load,
  renames do not always fire, and libuv multiplexes every watch of an event loop through one
  `FSEventStream` so not every event is delivered
  ([fswatch#111](https://github.com/emcrisostomo/fswatch/issues/111), [ttsc#1418](https://github.com/samchon/ttsc/issues/1418)).
- **Trap, theoretical and near-certain: FSEvents reports canonical paths.** A watcher started on
  `/repo/docs-source` (a symlink) receives paths under `/Users/<u>/Library/CloudStorage/...`. A consumer that
  prefix-matches on the symlink path gets **zero matches with no error** — the same silent-null shape as the
  `find` lesson, one layer up.

**Design consequence:** FSEvents is a *wake-up hint*, never the ledger. Pair it with a periodic
manifest reconcile — which is exactly what Microsoft prescribes for the API path too: *"even with webhooks
sending your application notifications, you may want to provide a periodic delta query to ensure that no
changes are missed… We recommend no more than once per day"* (scan-guidance.md:97).

### (d) Which agent tools silently skip symlinks?

Answered exhaustively in §2. Summary: **`rg` (default), `rg --files`, BSD `grep -r`/`-R`, BSD `find` (`-P`),
zsh `**/`, Claude Code `Grep`, Claude Code `Glob`** — all skip a symlinked directory met during a walk, all
with exit 0 and no diagnostic. `git` skips it by design and cannot be made to follow. Only `rg` with the
symlink as an explicit path, `rg --follow`, `grep -R -S`, `find -L`/`-H`, and zsh `***/` traverse.

---

## 4. Verdict on `docs-source → ~/Library/CloudStorage/...` — two questions, two answers

| Question | Verdict | Why |
|---|---|---|
| **(a) as an access mechanism** | **Conditionally yes, and it is what OneDrive itself does (P2)** | A symlink handed *explicitly* to a tool works: `rg <link>` traverses, `find -H <link>` traverses, `cat <link>/f` reads. It is fine for a human and for a script that always names the link as its root. |
| **(b) as a change-awareness mechanism** | **No — and not because symlinks are bad. Because a symlink carries no change information at all.** | It is a name, not a ledger. It has no since-token, no version, no event stream; `stat` on the link tells you about the link. Every diff still has to come from Graph delta, FSEvents on the *real* path, or a manifest walk. A symlink is orthogonal to the problem it is being considered for. |

**Therefore the recommendation is: do not make `docs-source` a symlink.** Not on symlink-fragility grounds
alone but because of a conjunction the measurements make concrete — (i) the agent's own `Grep`/`Glob` skip it
from the repo root and expose **no flag to fix it** (§2), so the *primary consumer* is blind by construction;
(ii) git records it as a `120000` blob so nothing under it is ever tracked, diffed or landed; (iii) FSEvents
paths come back canonical so watchers keyed on the link see nothing; (iv) even when traversal works, the
walk pays P5's per-directory round trips and risks P10-less hydration.

**Make `docs-source` a real directory** whose contents are placed there by L1's acquisition step — a
Graph-delta fetcher, or (no-API) a copier that reads from `~/Library/CloudStorage/...` under
`IOPOL_MATERIALIZE_DATALESS_FILES_OFF` with explicit hydration only for the changed set, or the operator's
drag-and-drop. The cloud tree then appears **exactly once** in the whole system, inside the acquisition
script, at a canonical absolute path — instead of appearing implicitly under every tool invocation.

---

## 5. Blockers and uncertainties, named

- **B1 — no positive control for the dataless detector.** P8/P9 give the bit and the readers, but with no
  dataless file on this box I never saw `stat -f '%Sf'` or `ls -l%` *print* `dataless`, and `chflags` is
  denied here by policy (attempting `chflags 0x40000000` was refused at the tool call), so I could not forge
  one. **Do not trust the flag-name string; read the bit.** Falsify with, on a real OneDrive Mac:
  `python3 -c "import os,sys;st=os.stat(sys.argv[1]);print(hex(st.st_flags), bool(st.st_flags&0x40000000), st.st_blocks, st.st_size)" <an online-only file>`
  then `ls -l%` and `stat -f '%Sf'` on the same path and record what each renders.
- **B2 — the man page says the system default is OFF, and observed behaviour says otherwise.**
  `man 3 getiopolicy_np` states that for `IOPOL_SCOPE_PROCESS`, `..._DEFAULT` means *"all accesses will
  follow the system default policy (IOPOL_MATERIALIZE_DATALESS_FILES_OFF)"* — read literally, a plain `cat`
  of a dataless file would **fail** rather than download. That contradicts the MS blog's *"if you
  double-click the files… they will be retuned and opened as expected"* and every user report of Files
  On-Demand. Candidate resolutions I could not choose between: the parenthetical is stale; the policy gates
  the kernel's automatic materialization of dataless *objects* while File Provider reads go through the
  extension's `fetchContents` on a different path; or GUI processes set `_ON` explicitly. **This does not
  change the recommendation** — setting `_OFF` explicitly is the fail-closed primitive either way — but it
  does mean *"a stray `rg` will download 200 GB"* is **not yet established**. Falsify on a real OneDrive Mac:
  `cat <online-only file> >/dev/null; echo rc=$?` under a shell where the policy is unset, then again under
  a tiny C/ctypes wrapper that sets `_OFF` first, and compare rc and network bytes.
- **B3 — `fileproviderctl dump` over a populated OneDrive domain is unverified.** It ran and printed live
  iCloud domain state here, and it is the obvious candidate for a no-API "what is materialized" read (P17's
  API, from the shell), but I have not seen whether it prints per-item dataless status for a third-party
  domain, nor whether reading it perturbs anything. Check before designing on it.
- **B4 — `NSFileProviderManager.enumeratorForMaterializedItems` may be provider-scoped.** Apple says *"The
  second lets your app enumerate the items stored locally by the system"* — whether "your app" means *any*
  app with access to the domain or only the provider's own containing app is not settled by the docs I read.
  If the former, it is a hydration-free materialized-set enumerator and is strictly better than a `stat` walk.
- **B5 — FSEvents on cloud-originated change: unmeasured** (§3c). The full experiment needs a Mac with
  OneDrive: watch the sync root, then change a file **from the web UI**, and record (i) whether an event
  arrives for a file that is currently materialized, (ii) for one that is dataless-but-locally-present, and
  (iii) for one in a never-browsed subtree. Case (iii) is the one that decides whether a watcher can be the
  primary no-API L1 at all.

---

## 6. Alternatives considered and ruled out

| Alternative to the symlink | Ruled out because |
|---|---|
| Hard-link the cloud files into `docs-source` | Hard links are files-only (no directories), and a dataless placeholder is not a normal file to duplicate; a second link also gives the provider two paths to reconcile. |
| APFS firmlink (what makes `/Users` work across the data volume) | Not user-creatable; firmlinks are created by the OS at volume-group setup. |
| `mount_nullfs` / bind mount | macOS ships no nullfs/bind mount. `mount -t nullfs` does not exist. |
| Finder alias (`.alias` bookmark) instead of a POSIX symlink | Strictly worse — an alias is an opaque resource-fork bookmark that `rg`, `find`, `grep` and git see as a small binary file, not as a directory at all. |
| `mdfind` as the content-diff oracle | P13: Spotlight does not hydrate dataless files, so content matching is blind over exactly the population that matters. Usable for metadata dates only. |
| Walk-and-hash the whole library each pass | P5 + P11: pays per-directory provider round trips and can hydrate hundreds of GB that macOS will then evict again. The server hash (Graph `quickXorHash`/`cTag`) answers the same question for free. |
| Pin the entire library ("Always Keep on This Device" at the root) to make everything a normal file | Defensible for a *bounded* curated subset (P14 folder inheritance makes it one action) and it does remove B2 and P5 entirely — but at tens-to-hundreds of GB it defeats the reason Files On-Demand exists and P4's free-space accounting stops protecting the disk. Recommend pinning only the `docs-source`-relevant subtrees. |

---

## 7. Golden example, on this axis

Cursor's local-side design is the right shape for the *manifest* layer (L2) and it is worth copying literally
rather than reinventing — [Cursor, Securely indexing large codebases](https://cursor.com/blog/secure-codebase-indexing):

> *"Cursor builds its first view of a codebase using a **Merkle tree**, which lets it detect exactly which
> files and directories have changed without reprocessing everything. The Merkle tree features a
> cryptographic hash of every file, along with hashes of each folder that are based on the hashes of its
> children."* … *"Small client-side edits change only the hashes of the edited file itself and the hashes of
> the parent directories up to the root."* … *"With the tree, Cursor walks only the branches where hashes
> differ."* … *"In a workspace with fifty thousand files, just the filenames and SHA-256 hashes add up to
> roughly 3.2 MB."*

Two transfers and one warning:

- **Transfer 1 — folder-level hashes give you a cheap "has anything under here changed".** For `docs/` (real
  markdown, always local) this is free and exactly right.
- **Transfer 2 — cache by content, not by path.** *"Cursor caches embeddings by chunk content. Unchanged
  chunks hit the cache"* — the same rule makes L3's converters idempotent across the operator's messy
  `report_v2 (1).xlsx` renames: a content-addressed converter output survives the rename for free.
- **Warning — a Merkle tree over `docs-source` does not transfer**, because it is the one design that
  requires hashing every file, i.e. hydrating the entire library (§3b). Merkle belongs over `docs/` and over
  the *manifest* (path + size + mtime + server hash), **never over the cloud tree's contents**. This is the
  axis where the local substrate and the Cursor analogy genuinely diverge, and the divergence is caused by
  P5/P11, not by scale.

---

## 8. Pipeline slots this axis constrains

| Slot | Constraint this axis imposes |
|---|---|
| **L1 acquisition** | Graph delta is not merely *preferable* to the local watcher — it is the only arm that answers "did the content change" without paying for content (§3b). The no-API arm is a legitimate fallback but must (i) run under `IOPOL_MATERIALIZE_DATALESS_FILES_OFF`, (ii) treat a zero-child directory as *unknown* not *empty* (P5/P7), (iii) treat FSEvents as a hint plus a daily reconcile (B5 + scan-guidance:97). |
| **L2 manifest** | The local no-API change key is `(path, size, mtime, inode, SF_DATALESS)`; the Graph key is `(id, cTag, quickXorHash)`. Store **both** so a tenant that later grants Graph access can re-key without a full re-read. Content hashes only for the hydrated subset. |
| **L3 converters** | Must assume the source file can vanish back to dataless between the manifest read and the convert (P11) — so convert is "hydrate → read → write markdown → optionally evict", and must be re-runnable after an `ENOENT`-shaped hydration failure rather than treating it as corruption. |
| **L5 git-tracked `docs/`** | Unaffected and correct — but `docs-source` must be a **real directory**, because a symlinked one is a `120000` blob (§2) and `docs-source` never enters git anyway. Add `docs-source/` to `.gitignore` explicitly; do not rely on a symlink to keep it out. |
| **Agent consumption of `docs/`** | Safe by construction *only if* `docs/` contains real local files. Any symlink inside `docs/` re-introduces the §2 blindness with no flag available to the agent. Recommend a land-gate lint: `find docs -type l` must return empty. |
