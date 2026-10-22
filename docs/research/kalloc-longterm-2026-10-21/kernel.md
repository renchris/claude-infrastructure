# Kernel mechanism of the `#!` leak (kernel axis, 2026-10-22)

Scope: from public sources, find which allocation leaks on each `#!` exec and under what condition.
Questions: does it need an ES or MAC client; do path length, relative paths, symlinks or posix_spawn
change it; can any supported setting avoid the code path. Box: MacBookPro18,2, macOS 15.8.1 (24H32),
running kernel `xnu-11417.140.69.712.69~1/RELEASE_ARM64_T6000` (`uname -v`).

Source tree: the published tag closest to the running kernel is `xnu-11417.140.69` (macOS 15.x).
Line numbers marked "15.x" refer to it. "26.3" is `xnu-12377.81.4`, and "26.4+" is `xnu-12377.101.15`
and `.121.6`. The repository has no `xnu-13432` (macOS 27) tag yet (`gh api repos/apple-oss-distributions/xnu/git/refs/tags`),
so the 27.0 fix cannot be diffed. AppleSystemPolicy (ASP) is closed source.

Labels: **MEASURED** (the command is named), **SOURCE** (read in XNU source: file:line),
**REPORTED** (a public third party measured it), **INFERRED** (my reasoning; not verified).

## Bottom line

1. **What leaks.** One 1 KiB generic kernel data allocation per successful exec whose image
   activation went through the `#!` interpreter branch. The allocation is made in AppleSystemPolicy's
   `cred_label_update_execve` MAC hook (`AppleSystemPolicy::credLabelUpdateExecve`) and holds the
   script's pathname. It is **not** the core kernel's `vfs.namei` (`ZV_NAMEI`) path buffer, as
   claimed upthread (evidence chain in §1). REPORTED + SOURCE + INFERRED, about 80%.
2. **The kernel condition** is `imgp->ip_scriptvp != NULL` when the MAC framework runs the exec
   credential-label transition. Only the `-3` (interpreter) branch of `exec_activate_image` sets it.
   `/bin/bash script` never sets it, and neither does any Mach-O exec. SOURCE.
3. **No ES client or third-party policy is needed.** ASP is an Apple MAC policy compiled into the
   sealed kernel collection. XNU calls its exec hook for every exec, whoever is watching. This Mac has
   no third-party kext or ES extension. Its only ES clients are `watchdogd` (Apple, always on) and
   the temporary `eslogger` census. MEASURED.
4. **Path length, relative path, symlink, execve vs posix_spawn, `#!/usr/bin/env`: none of them
   avoids it.** Failed execs and Mach-O children of scripts cost nothing. SOURCE/REPORTED/INFERRED (§4).
5. **No supported setting turns the code path off.** The MAC enforce sysctls are read-only on
   release kernels, ASP has no off switch, and boot-args need Reduced Security. Two reversible toggles
   are untested and are diagnostics, not fixes: the Developer Tools exemption for kitty, and turning
   Gatekeeper off (§5).
6. **Consequence for the fix.** The leak hinges on a single kernel-visible bit (was this image
   reached through `#!`?), so a compiled launcher that execs `/bin/bash <script>` removes the trigger
   completely. Measure the shim's own per-exec retention first, and do not deploy it as hard links (§6).

## 1. What allocation leaks

### 1a. The exec path for a `#!` file (SOURCE, 15.x)

- `exec_activate_image` (`bsd/kern/kern_exec.c:2289`) runs `namei` on the path, then the image
  activators. `exec_shell_imgact` (`:601`) returns `-3` for `#!`. In the `-3` branch
  (`:2394-2441`) the kernel copies the script's MAC label into `imgp->ip_scriptlabelp`
  (`:2401-2411`). It also takes a vnode reference on the script, `imgp->ip_scriptvp = imgp->ip_vp`
  (`:2416-2421`), then looks up the interpreter and goes back to `again`.
- The Mach-O activator `exec_mach_imgact` (`:1212`) then calls `exec_handle_sugid` (`:1682`, defined at
  `:6717`). That function asks every MAC policy whether the label transitions:
  `mac_cred_check_label_update_execve(..., imgp->ip_scriptvp, imgp->ip_scriptlabelp, ...)` (`:6736-6744`).
  If any policy says yes, it calls `kauth_proc_label_update_execve(..., imgp->ip_scriptvp, ...)` (`:6826-6845`).
- `kauth_proc_label_update_execve` (`bsd/kern/kern_credential.c:4366-4376`) builds a new model cred:
  `mac_cred_label_init(model)`, `mac_cred_label_associate(parent, model)`, then
  `mac_cred_label_update_execve(..., scriptvp, scriptl, ...)`. The last one walks every
  policy's `mpo_cred_label_update_execve` hook and passes it `scriptvp` (`security/mac_vfs.c:777-852`).
- An explicit interpreter (`/bin/bash leaf.sh`) never enters the `-3` branch, so `ip_scriptvp` stays
  NULL for the whole exec.

### 1b. Which hook allocates (REPORTED)

- willmcginnis, on a SIP-off 26.6.2 VM, ran DTrace `vminfo:::kalloc`/`zfree` paired by address with
  N=800 per arm. One 1024-class stack grew by about N with no matching free:
  `AppleSystemPolicy::credLabelUpdateExecve` under ASP's `cred_label_update_execve` hook. It allocated
  **801** times in the `#!` arm and **once** in the explicit-interpreter arm
  ([#66020 comment](https://github.com/anthropics/claude-code/issues/66020#issuecomment-5839216939),
  "Allocation-site trace").
- Photon forced a panic and used LLDB `showallocatedzoneelement` on 600 leaked elements. Every one held
  the pathname of a shell script (481 `/opt/homebrew/bin/brew`, 85 `.../shims/shared/git`, ...). None
  held the path of a compiled binary that the same workload ran 495-891 times
  ([Photon](https://photon.codes/blog/we-found-a-kernel-memory-leak-in-macos-that-any-shell-script-can-trigger),
  fetched with curl to `~/.cache/kalloc-longterm-ab/kernel/web/photon.txt`).
- ASP is a loaded MAC policy on this Mac: `sysctl security.mac.asp` ⇒ 19 OIDs, including
  `security.mac.asp.stats.exec_hook_count: 17196500` (MEASURED 2026-10-22 00:08, uptime 10.0 h).
  `AppleSystemPolicy.kext/Contents/Info.plist` links against `com.apple.driver.AppleMobileFileIntegrity`,
  `com.apple.kpi.private`, `com.apple.security.quarantine` and `com.apple.security.sandbox` (MEASURED, `plutil -p`).

### 1c. It is a generic data allocation, not the `vfs.namei` view (SOURCE + REPORTED ⇒ INFERRED)

- `ZV_NAMEI` ("vfs.namei") is pinned to the private data heap, whose zones are named `data.*`, in every
  release checked: `bsd/kern/kern_malloc.c:82` is `KHEAP_ID_DATA_BUFFERS` in 15.x and in 26.0-26.3,
  and `KHEAP_ID_DATA_PRIVATE` in 26.4+. Both map to the `"data."` prefix (`osfmk/kern/kalloc.c:172`
  15.x, `:175` 26.3 and 26.4).
- On 26.3 only, generic `kalloc_data` goes to `GET_KEXT_KHEAP_DATA()` =
  `static_if(kexts_enroll_data_shared) ? KHEAP_DATA_SHARED : KHEAP_DATA_BUFFERS`, with
  `kexts_enroll_data_shared` defaulting to TRUE (`osfmk/kern/kalloc.h:208-209,543-544` and
  `osfmk/kern/kalloc.c:489,2586-2590` at `xnu-12377.81.4`). In 15.x and 26.4+, `kalloc_data_external`
  goes to the `data.` heap (`kalloc.c:2473-2477` 15.x, `:2570-2574` 26.4).
- Photon: "On macOS 26.3, `data.kalloc.1024` remained nearly empty, but `data_shared.kalloc.1024`
  grew instead", while on 26.5 it was `data.kalloc.1024`. leonasdev also saw it in `data_shared` on 26.3.1.
- Inference: an element that moves to `data_shared` exactly in the one release where generic data
  allocations were routed there cannot have come through `ZV_NAMEI`, because that view stayed in
  `data.` throughout. So the `#!` element is a generic `kalloc_data`/`IOMallocData`-class allocation,
  which fits a kext (ASP) allocating a MAXPATHLEN path buffer. The upthread "vfs.namei" readings
  (Exelery on 26.3.1, `sudo zprint` all `[vfs.namei]`; DimitarTachev) are therefore a **different**
  leak (§2).
- **Testable prediction for this Mac (needs root):** in `sudo zprint data.kalloc.1024`, the growth
  should sit outside the `data.kalloc.1024[vfs.namei]` view (in `[raw]` or a non-view bucket). If it
  is all `[vfs.namei]`, this inference is wrong. The doc's "Untested" item 2 already proposes the read.

### 1d. Why the 1 KiB outlives the process (MEASURED + INFERRED)

- Measured here: a `#!` exec adds about 0 to the `cred` zone net and about +1 to the
  `data.kalloc.1024 − cred` residual (`panic-2026-10-18-zone-map-shebang-leak.md:70-72`, 15.7.9 A/B).
  The 15.8.1 re-measure gave 1.098 ± 0.104 per exec against 0.007 ± 0.101
  (`~/.cache/kalloc-158-ab/rows-n3000.tsv`, `fit.py`). The model cred is freed when the process exits
  (`mac_cred_label_free` ⇒ `MAC_PERFORM(cred_label_destroy)`, `security/mac_process.c:125-137`),
  but the 1 KiB is not. ASP drops the buffer on some branch of its label lifecycle. Which branch is
  unknowable without disassembly; the boot KC on this Mac has no ASP symbol strings
  (`strings -a BootKernelExtensions.kc | grep -i credLabel` ⇒ 0 hits; MEASURED).
- One candidate fits Photon's 26.5 pattern ("only when scripts launched other scripts": depth 1 =
  0.016 KiB, then about +1 KiB per extra level) and willmcginnis's "lineage" result on the M1 26.6.2:
  `mac_cred_label_associate(parent, model)` (`security/mac_process.c:240`) lets ASP copy the parent
  label's script state into the model, and `credLabelUpdateExecve` then overwrites that slot with the
  new script's path without freeing the copy. INFERRED, not verified.
- **On 15.x the first `#!` in a lineage also leaks.** Our 15.8.1 harness ran `run2.sh` as `bash run2.sh`
  (`run2.sh` is mode 0644, so it is not a `#!` exec; MEASURED, `ls -la`), and the leaf still cost 1.1.
  This session's ancestry has no `#!` exec in it either: kitty → login → zsh → `/bin/bash lr-fire-resume.sh`
  → expect → `bash cc-close-attrib` → claude.exe (Mach-O) (MEASURED, `ps -o pid,ppid,command`). So on this
  build, converting only the "outer" script of a chain is not enough. Every `#!` exec counts, as on
  willmcginnis's M4 26.4.1.

## 2. The other leak upthread (mechanism "A", `vn_getpath failed: 0x2`) and why it is not ours

- An XNU error-path leak in `build_path_with_parent` matches it exactly (SOURCE, 15.x `bsd/vfs/vfs_cache.c`).
  When a vnode is a hard link (`VISHARDLINK`), the mount supports path-from-id, and the caller allows
  entering the filesystem (`fixhardlink`, `:633-635`), the function allocates
  `va.va_name = zalloc(ZV_NAMEI)` (`:739-741`). If `vnode_getattr` fails or does not return
  `va_parentid`, it does `ret = ENOENT; goto out` (`:748-752`); if `VFS_VGET` of the parent fails, it
  does `goto out` (`:757-759`). Both skip the only `zfree(ZV_NAMEI, va.va_name)` (`:800`), and `out:`
  (`:890`) does not free it. 26.4+ has the same shape (`:747`, `:758`, `:765`, `:806` at
  `xnu-12377.121.6`). That is a 1 KiB `vfs.namei` element per failed resolution, returned as ENOENT
  (0x2). It matches DimitarTachev's 1:1 meter and Exelery's all-`[vfs.namei]` breakdown.
  INFERRED as the mechanism of "A". The ES kext's own scratch-buffer theory (ariccio) is the alternative.
- Plain `vn_getpath` passes `BUILDPATH_NO_FS_ENTER` (`bsd/vfs/vfs_subr.c:3649-3651,3728-3731`), so it
  cannot reach this branch. Only the fsenter variants can: `vn_getpath_fsenter`, which the XNU comment
  says "is called by MAC hooks to authorize operations for every thing" (`:3734-3767`), and
  `vn_getpath_ext` with `VN_GETPATH_FSENTER`.
- **Inactive on this Mac:** `/usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "vn_getpath failed"'`
  ⇒ 0 kernel lines; the only matches were `log`'s own invocation lines (MEASURED 2026-10-22 00:06).
- **But one precondition is armed:** every pinned `claude.exe` under `~/.claude-*/node_modules/...`
  and `~/.claude-versions/*` has a link count of 2 (`stat -f %l`, 13 of 13; MEASURED), so they are
  `VISHARDLINK` vnodes. If a pinned version's other link or its directory is removed while sessions
  still run from it, mechanism A can switch on. INFERRED; this is the npm-orphaning pattern upthread.
  Keep the `vn_getpath failed` count as a second alarm input.

## 3. Does it need an ES client or a third-party MAC policy?

- **No.** The hook is ASP's, inside the MAC framework's exec label transition (§1a). XNU calls it for
  every registered policy regardless of ES subscribers (`security/mac_vfs.c:800-847`). SOURCE.
- Inventory of this Mac (MEASURED, 2026-10-22 00:00-00:10):
  - `systemextensionsctl list`: Tailscale network extension, Karabiner DriverKit VirtualHIDDevice,
    and two Razer DriverKit drivers ("waiting for user"). None is an ES or MAC extension.
  - `kextstat | grep -v com.apple`: header only, so no third-party kexts.
  - ES-client entitlement scan over all 532 running executables (`codesign -d --entitlements`):
    `com.apple.developer/private.endpoint-security.client` is held only by `/usr/libexec/watchdogd`
    (pid 1049, Apple, always on) and `/usr/bin/eslogger` (pid 90981, the census). Everything else
    holds only `endpoint-security.submit.*` (syspolicyd, tccd, XprotectService, authd and others).
    `endpointsecurityd` is running and hosts no extensions. Santa, Little Snitch, LuLu, CrowdStrike
    and Jamf are absent (`ps`). Docker has only `com.docker.vmnetd`.
  - MAC policies visible through sysctl: amfi, endpointsecurity, acm, sandbox, qtn, asp
    (`security.mac.max_slots: 7`).
- A rough natural experiment: during the `eslogger exec` census (an extra exec ES subscriber, started
  23:51:12), the residual grew 2,223 elements in 223 s = **10.0/s** at load ~128 (two zprint reads,
  00:04:25→00:08:08; MEASURED). The capacity-alarm series for the two hours before gives 7.9-11.1/s
  (`~/.claude/logs/kalloc-zone-series.tsv`, raw bytes/1024; MEASURED). No visible step, but load is
  not controlled.
- **The volume adds up** (MEASURED, with the ratio ESTIMATED):
  - ASP saw 17.08M exec hooks in 35,875 s of uptime, 476/s on average, and 114,659 in the 223 s
    above, 514/s (`sysctl security.mac.asp.stats.exec_hook_count`).
  - The census's first 1 GB (04:51:16-04:54:22Z, 186 s) holds 125,065 exec events, of which 2,916
    have a non-null `script` = **15.7/s, 2.3% of execs** (`grep -c` on `head -c 1e9 exec.jsonl`).
  - Against a residual of about 10-12/s, `#!` execs alone can carry the whole leak: about 0.7 elements
    per script exec across windows that do not quite match (estimate). No second source is needed
    to explain this box.

## 4. Variants: what changes the count and what doesn't

| Variant | Effect | Basis |
|---|---|---|
| Explicit interpreter `/bin/bash x.sh` | ≈ 0 | MEASURED here (0.007 ± 0.101, 15.8.1); SOURCE: `ip_scriptvp` stays NULL |
| Mach-O exec, including a Mach-O child of a script | ≈ 0 | MEASURED here 15.7.9: `#!` that runs a binary +0.89 vs one `#!` +0.94; `/usr/bin/true` −0.02 |
| `#!/usr/bin/env bash` | still about 1 (it is a `#!` exec; `env` is the interpreter) | REPORTED (willmcginnis M1: 1.27/trial) |
| Failed `#!` exec (missing, non-exec or directory interpreter) | ≈ 0.0003 | REPORTED (willmcginnis 26.6.2 VM) |
| execve vs posix_spawn | same | SOURCE: both call `exec_activate_image` (`kern_exec.c:4345` posix_spawn, `:5360` `__mac_execve`), then `exec_mach_imgact` → `exec_handle_sugid` |
| `exec script` inside a script (replace in place) | still about 1: it is an execve of a `#!` | SOURCE (same path) |
| Path length | none: fixed MAXPATHLEN (1024) buffer, one element per exec, independent of length | INFERRED from 1 KiB elements holding paths (Photon) |
| Relative path or a symlink in the path (e.g. `~/.claude` → repo) | none expected: the hook gets the resolved vnode (`scriptvp`), not the typed string; `namei` resolves the link first (`kern_exec.c:2323-2334`) | SOURCE + INFERRED |
| `sh -c 'script.sh'` (how Claude Code runs a shell-form hook) | about 1 per script; `sh` is Mach-O, the script is the `#!` exec | REPORTED (willmcginnis: `spawn(command, {shell:true})`) |
| Nesting depth | +1 per `#!` level on 15.x, including the first | MEASURED here (1, 2, 3 levels: +0.94, +1.98, +2.86) |

## 5. Settings, sysctls, boot-args

- `security.mac.{proc,vnode,...}_enforce`: read-only on release kernels, and the in-hook enforce
  checks are compiled out: `SECURITY_MAC_CTLFLAGS (CTLFLAG_RD ...)` and `SECURITY_MAC_CHECK_ENFORCE 0`
  unless `DEBUG` (`security/mac.h:104-110`). Disabling them would also disable Sandbox and AMFI. Not an option.
- ASP sysctls (MEASURED): `logging_mode: 0`, `policy.gatekeeper_enabled: 1`, `policy.change_scans: 1`,
  `policy.strict_sip: 0`. No OID disables the exec hook.
- **Developer Tools exemption for kitty** (`sudo spctl developer-mode enable-terminal`, then Privacy &
  Security → Developer Tools → add kitty). Community reports say it skips syspolicyd's per-executable
  assessment for processes the tool is responsible for ([billmill notes](https://notes.billmill.org/computer_usage/mac_os/Avoiding_gatekeeper_in_your_terminal.html),
  [mjtsai 2024-02-15](https://mjtsai.com/blog/2024/02/15/mac-app-launches-slowed-by-malware-scan)). Apple does not
  document it. Whether ASP's `credLabelUpdateExecve` allocation is skipped too is **unknown**; the
  allocation sits in the credential transition, not obviously in the assessment upcall. My estimate is
  about 20-30%. It is reversible and costs one A/B: `~/.cache/kalloc-158-ab/run2.sh` from a kitty window, before
  and after. It needs operator GUI action and sudo. Cost: weaker Gatekeeper coverage for everything
  kitty launches.
- **Turning Gatekeeper off** (`spctl --global-disable`, which flips `security.mac.asp.policy.gatekeeper_enabled`):
  untested, and it could only matter if ASP gates the hook on that flag. It removes a real protection.
  It is a diagnostic at most; I do not recommend it.
- **boot-args:** `sysctl kern.bootargs` is empty and `nvram boot-args` is not set (MEASURED). No ASP
  boot-arg is documented. `zlog<n>=` (allocation backtraces), `zone_map_jetsam_limit` and
  `ZONE_MAP_MAX` (32 GiB on 64-bit) exist (`osfmk/kern/zalloc.c:165,3196-3325,5036-5050` 15.x), but
  they only diagnose or move the ceiling. On Apple silicon, any boot-arg needs Reduced Security set
  from recoveryOS, and Photon reports zone logging gave no usable backtraces there. Not a supported route.
- `security.mac.amfi.developer_mode_status: 1` (AMFI Developer Mode is already on; MEASURED) is
  unrelated to ASP's script path.
- Upgrading moves the leak only within the zone map: on 26.3 it moved to `data_shared` (§1c), with
  the same panic. The only reported fix is 27.0 (davidgibbons, souliane, and willmcginnis's 27 VM at
  0.006-0.012 per exec).

## 6. What this means for the long-term fix (kernel-axis view)

- The trigger is a single kernel-visible bit per exec: whether the image was reached through the
  `#!` branch. A **compiled launcher** that every `bin/`/`scripts/` entry resolves to, and that execs
  `/bin/bash <real script>` (with the shebang's own flags), never sets `ip_scriptvp`. It removes the
  trigger for every caller (hooks, launchd, other tools, `sh -c`, `env`) with no help from them.
  This is the most scalable lever that exists short of Apple's fix. SOURCE + MEASURED (the bash arm).
- Three kernel-side caveats before rollout:
  1. **Measure the shim itself.** It will be a non-platform, ad-hoc-signed Mach-O, which ASP and
     syspolicyd treat differently from `/bin/bash` (assessment per new cdhash and path; ASP keeps a
     cache: `cache_entry_count` 4317, `cache_allocation_count` 133,099, `cache_release_count` 128,782,
     MEASURED). Upthread bounds for non-platform binaries are ≤0.22/exec, inside noise (ariccio). Ours
     have never been measured on 15.8.1. Run 3000 execs per arm, shim vs `/bin/bash`, before cutover.
  2. **Use symlinks or copies, not hard links,** for the per-name entry points. A hard-linked shim
     is a `VISHARDLINK` vnode, which arms mechanism A's error path (§2) on every fsenter path lookup
     that fails.
  3. **Use one binary (one cdhash) at a fixed path** so assessment results stay cached. Avoid
     rebuilding it into new paths, which triggers a fresh syspolicyd assessment for each one
     (mjtsai/billmill reports).
- A lint has to catch `exec ./x.sh` and `#!/usr/bin/env bash` targets too (§4). `env` does not help.
- Scripts we don't own (Homebrew `brew` and its shims, `bats-exec-*`, npm `.bin` JS shims with
  `#!/usr/bin/env node`) take the same path. The census already shows `bats-core/.../bats-exec-test`
  among the script execs (MEASURED, first record with a script).

## Tests I would run next (none run here; all need the operator or root)

1. `sudo zprint data.kalloc.1024`: check the view split against §1c's prediction (`[vfs.namei]`
   should **not** hold the growth).
2. The Developer Tools A/B for kitty (§5).
3. The shim's per-exec retention vs `/bin/bash`, 3000 per arm, interleaved, with the
   `data.kalloc.1024 − cred` residual (§6.1).
4. Once a 27.x source tag appears, diff it against 15.x for MAC exec-transition changes. ASP itself
   stays closed, so the Apple Feedback report should name `AppleSystemPolicy::credLabelUpdateExecve`
   and include this Mac's 15.8.1 per-exec figure.

## Deviations and provenance

- Scratch data was written under `~/.cache/kalloc-longterm-ab/kernel/`. The brief allows that directory
  for the measurement axis, and I used it for read-only material: XNU sources (a sparse clone of
  `xnu-11417.140.69` plus single files from other tags), the #66020 comment dump, the Photon text, a
  `strings` dump of the boot KC, and a process list. I ran no exec A/B and added nothing to the zone.
- `ls -d ~/.claude*/` printed one entry that reads as a directory named like a ship-land warning
  ("`⚠ ship-land: stranded-sweep flags commit(s) for REVIEW ...`"). I did not touch it; it is outside this axis.

## Critique

Adversarial review, 2026-10-22 00:13-00:50 CDT (05:13-05:50Z). I re-checked the cited sources and
re-ran the reads; every verdict names its basis. My reads were zprint, sysctl, ps, stat, grep and
gh api only. I ran no exec A/B.

### Verdicts on the main claims

| # | Claim | Verdict | Basis |
|---|---|---|---|
| 1 | The allocation is ASP `credLabelUpdateExecve` | **Upheld as REPORTED, for 26.6.2 only.** On 15.8.1 the allocation site is INFERRED: no trace has been run on this build. | Quote checked: `kernel/issue66020-comments.md:1087-1098` (801 vs 1, 26.6.2 VM). Photon's 600 buffers: `kernel/web/photon.txt:85-111`. |
| 1c | It is not the `vfs.namei` view | **Plausible but weaker than "about 80%"; I put it near 70% (estimate).** The source lines are right: `ZV_NAMEI` is `KHEAP_ID_DATA_BUFFERS` at 11417.140.69 (`kern_malloc.c:82`) and at 12377.81.4 (`gh api …/kern_malloc.c?ref=xnu-12377.81.4`, line 82). `GET_KEXT_KHEAP_DATA` ⇒ `KHEAP_DATA_SHARED` at 26.3 (`gh api …/kalloc.h?ref=xnu-12377.81.4`, lines 206-209; `kalloc-xnu-12377.81.4.c:489,2589`). The weak link is the premise that "the `#!` element moved to `data_shared` on 26.3". Photon's 26.3 evidence is one whole machine accumulating 12.3 GB over 38 days "under a comparable workload" (`photon.txt:247-258`), not a per-`#!` A/B on 26.3. So that premise is itself INFERRED. | Confirmed that the test needs root: non-root `zprint data.kalloc.1024` prints no `[view]` rows (MEASURED 00:13). |
| 2 | The kernel condition is `ip_scriptvp != NULL` | **Upheld (SOURCE),** with three details the doc leaves out. (a) The `-3` branch also allocates `ip_scriptlabelp` (`kern_exec.c:2405`) and sets `IMGPF_INTERPRET` (`:623`). (b) `ip_scriptvp` also reaches `mac_proc_check_inherit_ipc_ports` (`:6863`). (c) The label update runs only when some policy's `check_label_update_execve` asks for it (`:6736-6744`, `:6826`), so "XNU calls its exec hook for every exec" overstates. None of this changes the shim conclusion: all of it is absent with an explicit interpreter. | Lines re-read in `kernel/xnu-11417`. Also re-read: `kern_credential.c:4364-4377`, `mac_vfs.c:777-852`, posix_spawn `:4345`, execve `:5360`, `FOLLOW` namei `:2323`, `mac.h:104-110`. |
| 3 | No ES or third-party client is needed | **Upheld for the source argument.** The natural experiment is weak, as the doc says. One correction: eslogger has run far longer than 10 minutes. `ps` at 00:42 showed `/usr/bin/eslogger exec` (pid 90981) still live since 23:51:16, with its stop command (`sudo -A pkill -INT -f ^/usr/bin/eslogger exec$`, started 00:01:16) waiting on an osascript password dialog. `exec.jsonl` was 22.0 GB at 00:42 and growing about 7 MB/s (`ls -l`). All later windows in this file, mine included, ran with eslogger attached. | MEASURED (`ps -axo pid,ppid,lstart,command`, `ls -l`). |
| 4 | Script execs explain the whole leak | **Upheld and tightened.** The doc's "about 0.7 per script exec" came from windows that did not match. Time-matched, 05:14:50-05:18:04Z (194 s): residual `data.kalloc.1024 − cred` 386,952 ⇒ 389,194 = **+2,242 (11.6/s)**. In the same window the census holds **2,339 script execs (12.1/s)**, which is **0.96 elements per script exec**, close to the 1.098 harness figure. Exec totals agree: census 117,842 events = 607/s against ASP `exec_hook_count` +121,935 = 628/s. The first-1 GB figures re-count exactly: 2,916 with a script, 122,149 null, 125,065 in total. | MEASURED: zprint plus cred reads at T0/T2 (load 69-97), `sysctl security.mac.asp.stats.exec_hook_count`, and `grep -o` of `"script":{`/`"time"` tokens over `tail -c 2.5e9 exec.jsonl`. Pairing tokens left 4,489 times with no script token, about 1.5% (key-order noise). |
| 5 | "On 15.x the first `#!` in a lineage leaks too" | **Refuted as evidence; the question is open.** It is labelled MEASURED, but the evidence is confounded. Details below. | |
| 6 | The vn_getpath hard-link error path | **Upheld (SOURCE).** `vfs_cache.c:633-635, 739-741, 750-752, 757-759, 800`, and `out:` at `:890-915` frees nothing. Inactive here per the doc. Link count: 10 of 10 `~/.claude-*/node_modules/.../claude.exe` have nlink 2 (MEASURED, `stat -f '%l %i'`). The doc's "13 of 13" also counted paths I did not find under `~/.claude-versions/` (only `MANIFEST.jsonl` matched as a file). | |
| 7 | No supported setting avoids the path | **Upheld.** `sysctl security.mac.asp` re-read: 19 OIDs, none of them a switch; `kern.bootargs` is empty. The Developer Tools 20-30% figure is a guess and is labelled as one. | MEASURED (sysctl). |

### Claim 5 in detail: the harness lineage was not `#!`-free

- **The ancestry the doc cites contains a `#!` exec.** `lr-fire-resume.sh:1740` spawns
  `env … $wrap $bin …`, and `:1181` sets `LR_WRAP="$HOME/.claude/bin/cc-close-attrib"`. That file's
  first line is `#!/usr/bin/env bash` (`head -1`; it is a symlink into the repo). So `env` execs a
  `#!` script by path. What `ps` shows, `bash /Users/chrisren/.claude/bin/cc-close-attrib …`
  (pid 14451 in my own chain), is exactly the argv an env-shebang script run by path produces.
  `~/.zshrc:504,508` also start sessions through `"$HOME/.claude/bin/cc-close-attrib"` by path.
  23 such wrappers were live at 00:4x (`ps -axo ppid=,command= | grep -c`). MEASURED.
- **`ps` cannot prove the absence of a `#!` exec.** The kernel rewrites argv to
  `interpreter [args] script`, so a `#!` launch and an explicit-interpreter launch look the same
  (willmcginnis says so: `issue66020-comments.md:1048`). "MEASURED, `ps -o pid,ppid,command`" cannot
  support "no `#!` exec in ancestry". The 10-21 harness run came from a Claude session, so its
  lineage very likely included this wrapper (INFERRED).
- **The curve matches a one-level shift.** Our 15.7.9 depth A/B reads +0.94, +1.98, +2.86 for 1, 2
  and 3 levels (`panic-2026-10-18-zone-map-shebang-leak.md:79-82`). Photon's 26.5 reads 0.016, 0.99,
  2.00 and 3.01 for 1 to 4 levels (`photon.txt:229-240`). Ours is Photon's shifted by exactly one
  level, which is what one hidden `#!` ancestor predicts. The doc's own §1d candidate mechanism
  (associate copies the parent's script state, update overwrites it unfreed) also predicts that the
  first `#!` costs nothing. The doc never reconciles that with its §1d conclusion.
- **Status.** "Lineage-only" versus "every `#!`" on 15.8.1 is untested: about 50/50 (estimate).
  §4's "Nesting depth" row ("including the first") inherits the same confound.

### Cheaper levers the doc missed

1. **Root de-shebang (try first, three lines).** Launch the session wrapper through its interpreter:
   `lr-fire-resume.sh:1740` `$wrap` ⇒ `/usr/bin/env bash $wrap` or a resolved bash, and
   `~/.zshrc:504,508` likewise. Also check how the pane-successor path starts `lr-fire-resume.sh`.
   If 15.8.1 behaves like Photon's 26.5 and willmcginnis's M1 26.6.2 (first `#!` 0.01-0.37,
   `issue66020-comments.md:1015,1022`), this would make the **first** `#!` exec of every hook, Bash
   tool command and test command under the ~40 sessions nearly free. That includes scripts no shim
   can reach (Homebrew, bats, `/usr/bin/shasum`, pytest stubs). It does not replace the shim:
   script→script calls would still cost about 1 each. **Test before relying on it:** `leaf.sh` by
   path ×3000 from a lineage with no `#!` ancestor, against the same from inside a session. A clean
   lineage comes from LaunchServices with no launchd edit:
   `open -n -a kitty --args /bin/bash ~/.cache/kalloc-158-ab/run2.sh` gives launchd → kitty →
   `/bin/bash`. It opens a window, so it needs the operator's OK. The zone cost is about 6 MB
   (estimate: 2 arms × 3000 × 1 KiB).
2. **Swap `/usr/bin/shasum`** (an Apple Perl `#!`) for `/sbin/sha256sum` (Mach-O; `file`,
   `ls -la /sbin/sha256sum`). It was 27 of 2,339 script execs in the matched window and 57 of 658
   in the later one (MEASURED, census). The OS ships 286 `#!` files in `/usr/bin /bin /usr/sbin /sbin`
   (MEASURED, `head -c2` loop). Only rewriting call sites or a lint reaches those; the shim cannot.

### Shim caveats the doc missed

- **Coverage. The shim reaches less of the census than the user's plan (b) implies.** In the
  matched window, the 40 largest (responsible pid, path) groups hold 850 of 2,339 script execs:
  - `$TMPDIR` pytest and bats stubs (`launchctl-stub`, `stubbin/scutil`, `stub-notify`, `stub-ps`): ≥589, at least 25%.
  - Main-repo `bin/`: 100 (`cc-kqwait` 59, `cc-settings-parity` 41).
  - `.worktrees/` copies: 76.
  - A postland fixture: 34.
  - `shasum`: 27.
  - Homebrew `bats-exec-test`: 24.

  The later window (05:27:30-05:31:28Z, without the measurement axis's 3,000 `leaf.sh`) had 658:
  main repo 322 (49%), worktree copies 140 (21%), Homebrew 72 (11%), `shasum` 57 (9%),
  `$TMPDIR` stubs 53 (8%), npm 6. All MEASURED (perl over `grep '"script":{'` of the census tail).
  The mix swings with test load. So the shim must:
  - be tracked in git, so every worktree checkout gets it;
  - be reachable from test stub generators (stubs written as symlinks to the shim, or tests calling code through an explicit interpreter);
  - come with a lint for unowned calls by path (`shasum`, `bats` under `#!` chains, `pytest` entry-point scripts as opposed to `python -m pytest`).
- **Interpreter fidelity.** §6 says the shim "execs `/bin/bash <real script>`". For
  `#!/usr/bin/env bash` targets that changes the interpreter wherever PATH holds Homebrew bash 5. The
  repo already records that trap (`.claude/rules/agent-operating-lessons.md:47`), and so does
  willmcginnis (`issue66020-comments.md:1072`). The shim should parse the shebang and exec its
  interpreter itself, resolving `env NAME` through PATH to a Mach-O. Hardcoding `/bin/bash` is wrong.
- **The shebang-less alternative is rightly not proposed.** A file without `#!` gets ENOEXEC and
  costs nothing, but only shells fall back to interpreting it. CPython keeps walking PATH
  (`.claude/rules/agent-operating-lessons-situational.md:184`), and launchd and posix_spawn fail.
- **Exec volume.** The shim doubles execs per shimmed call (shim, then bash). The A/B should also
  log `security.mac.asp.stats.exec_hook_work_time`, not just the zone residual. The current rate is
  607-628 execs/s (MEASURED above).
- **Hard-link advice is harmless but over-weighted.** The leak path also needs `vnode_getattr` or
  `VFS_VGET` of the parent to fail (`vfs_cache.c:750-759`), which a stable repo path does not do.
  `/sbin/sha256sum` has nlink 8 (`ls -la`) and is not leaking. Use symlinks anyway.

### Reviewer deviations

- I wrote one scratch token file, `/tmp/claude-kcrit-tok.txt`, and removed it (`rm -f`). The
  background job outputs went to Claude Code's task directory. The rest was reads.
- One categorisation pass over the matched window did not finish (it was scanning the growing
  22 GB file). The matched-window shares above therefore come from the top-40 groups only and are
  lower bounds.
