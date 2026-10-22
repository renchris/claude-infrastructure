---
status: complete
---

All five waves landed 2026-10-22. Waves ran in parallel, so the cut was measured once for all of
them, not per phase: one census window read 0.09 GiB/day (§ Measurements). The standing verdict on the
≤ 0.3 GiB/day target is W5's hourly SLO check (`scripts/kalloc-slo.sh`), which files the census row
itself on a breach. Operator-only items left out of scope: `~/.zshrc:504,508,705-706`, T-0's
clean-lineage window, off-box CI (money), migration 0076's `--confirm launchd` (row `5e6ea2dc29e0`).

# Stop setting off the #! kernel leak (2026-10-22)

Scope (frozen): cut this Mac's data.kalloc.1024 leak from ~0.93 to ≤0.3 GiB/day without the macOS 27
upgrade, by removing `#!` execs at their sources (trampoline for by-name stubs, call-site fixes, lints)
and a census loop that keeps it fixed; measured per phase.

Why: macOS 15.8.1 still keeps ~1.1 KiB per `#!` exec (measured 2026-10-21); the operator ruled no
macOS 27 until a release explicitly ships the fix (decision `a172a41d0d79`). The kernel bug itself is
out of our reach (SIP; `docs/research/kalloc-longterm-2026-10-21/kernel.md`).

Evidence: `docs/research/kalloc-longterm-2026-10-21/REPORT.md` (8 axes, each critiqued; census of
34,157 real `#!` execs in 63 min, 2026-10-21 23:51-00:54). Shares: test and rehearsal harnesses 81%
(one agent-context-sync `launchctl-stub` alone 29%), our production tools 18%, Homebrew/npm/git <1%.
A hook daemon cuts load, not the leak (`daemon.md`).

## Phase 0 — orchestration

| Wave | Locus | Owns | Content |
|---|---|---|---|
| W0+W1 measure and point fixes | S | `scripts/kalloc-exec-census.sh` (new), `bin/cc-await-ping`, the 60 `shasum` call sites, `hooks/lib/shasum-direct.sh`, `migrations/0012,0036` call lines, `scripts/c10-batch.sh`, `bin/cc-kitty-bin`, `bin/it2-kitty`, `bin/cc-resume-layout.sh`, `hooks/session-end.sh`, `lr-fire-resume.sh` | REPORT §3 Phase 0 (T-1 trampoline cost; census tool tracked with env stripped, bounded, filtered) and Phase 1 table, except `~/.zshrc` (operator dotfile) |
| W2 agent-context-sync harness | owner session `agent-context-sync-16` (its repo, its CLAUDE.md) | that repo's tests and `scripts/install.sh` hashing | REPORT §3 Phase 2; routed by message, not fired from here |
| W3 infra test suites | S, after W1's T-1 verdict | `tools/cc-shim/`, `vendor/bats-core`, `tests/lib/cc-stub.bash`, top-12 test files, lint R4 | REPORT §3 Phase 3 |
| W4 call sites and Mach-O entries | S, after W3 | `scripts/lib/cc-run.sh`, `scripts/lib/cc-common.sh`, `scripts/exec-form-lint.sh`, `bin/it2`, `bin/cc-qos-exec` | REPORT §3 Phase 4 |
| W5 keep-it-fixed loop | S, after W1 | capacity-alarm SLO rows | REPORT §3 Phase 5 |

Lead: session 551eb39b fires W0+W1 and routes W2, then recycles; W3-W5 fire from the successor once
W1's T-1 verdict is on disk. Operator calls, not built: `~/.zshrc:504,508` session-root change; T-0's
clean-lineage window (`open -n -a kitty`); off-box CI (money); a root census LaunchDaemon.

## Waves

### W0+W1 measure and point fixes — DONE 2026-10-22 (session kte-w01; landed through `c04753169`, lead-verified by content; operator row `5e6ea2dc29e0` runs migration 0076)

- **Census tool** `scripts/kalloc-exec-census.sh` (`1615ea04c`, `tests/kalloc-exec-census.bats`): one
  bounded `sudo -A gtimeout -s INT`, filtered in the stream to script execs and an allow-list of fields;
  the bats test feeds secrets through a stubbed eslogger and proves none reach disk. The 26 GB file of
  2026-10-21 was already gone when this ran (its dirs are 0700).
- **T-1: PASS.** L − B = +0.020 ± 0.017 per exec (95% CI −0.012..+0.053), 12 interleaved pairs of 3000,
  shebang-parsing trampoline, +2.2 ms per call (`e40c43b41`, `measure.md` § T-1). W3 and W4 are unblocked.
- **Point fixes:** cc-await-ping → `env bash cc-kqwait` (`db5828bfe`); cc-in-kitty via `/bin/sh`
  (`bdd199890`); kitty resolvers unwrap Homebrew's cask wrapper (`96d43d707`); it2-kitty runner and the
  lr-fire-resume `cc-close-attrib` root through their interpreter (`07ad2628e`); cc-settings-parity through
  python3 in all 26 migrations that call it and in c10-batch, not only the three lines the REPORT named
  (`1ab1a938a`); shasum → `/sbin/sha{256,1}sum` in 63 files with byte-identical output, plus
  `scripts/shasum-lint.sh` at the land gate (`b32af6d4f`, `4c749b938`, `31730cb2a`); 36 launchd plists through their own
  interpreter, `hook-shebang-lint.sh` extended to plists, and c10 migration 0076 for the installed copies
  (teammate ld, `b508bc635`, `55e900e2f`, `1492549c3`).
- **Learnings:** the PATH-stub fork census (`tests/stop-hook-forks-helpers.bash`) cannot see a tool run by
  absolute path, so the `shasum` count pins in the beacon and waiting-recycle fork suites now assert 0
  and lean on the paired `cut` count. Migration 0076 is c10: it waits for the operator's
  `--confirm launchd`, and until then the LOADED jobs still run their mains by path.
- **Follow-up land** `67a27da86`: a function extracted or run before the `shasum-direct.sh` source read
  `CC_SHA256`/`CC_SHA1` empty (handoff-fire's recycle lock hashed to `<no digest>`); every use site now
  defaults itself to `/sbin`. Its 168-suite sweep found that one regression; the other reds failed
  identically on the pre-wave base `c11e679c3`. Also re-pinned cc-fleet #20 (label count 56 → 57).
- **Not built, and why:** `~/.zshrc:504,508,705-706` (operator dotfile); the `technical-analysis` and
  `reso-management-app` project hooks (other repos); T-0 (needs the operator's clean-lineage window).
  Same `exec "$CC_PANE_RUNNER"` root also sits at `scripts/handoff-fire.sh:1318` and
  `scripts/limit-recover/lr-lib.sh:1338`, and the `reso-resume-one` callers in `bin/cc-resume-layout.sh`
  and `scripts/boot-resume-launch.sh` run it by path: left to W4 (call sites), sized by T-0.
### W2 agent-context-sync harness — DONE 2026-10-22 (that repo's round 23 lane K, item A97; `eb0938ee..9b8471d4` on its main, lead-verified ancestry, its CI green)

- Test stubs run by path are Mach-O trampolines (a copy per stub, built in its conftest, not cc-shim);
  agentsync's own stand-ins stay `#!` because macOS SIGKILLs a Mach-O copied over one that already ran.
  `scripts/install.sh` hashes with `/sbin/sha256sum`, shasum only where it is missing; `launcher/build.sh`
  unchanged (editing it changes its source hash, which costs a TCC re-approval). REPORT's launchctl-poll
  premise refuted (18 getenv + 2 print calls per run, not polls). Its subset: 5,309 → 141 `#!` execs.
  Detail: that repo's CONTRACTS §16.170.
### W3 infra test suites — DONE 2026-10-22 (session kte-w3; landed through `a3ff099a4`, lead-verified by content)

Scope (frozen): tools/cc-shim + tests/cc-shim.bats, vendored bats-core 1.13.0 with "$BASH" internal
calls run by bin/cc-bats, the tests/helpers cc_stub helper + tests/cc-stub.bats, the top-12 census test
files converted, lint R4 wired into ship-land beside the HOOK SHEBANG arm.

- **cc-shim** `tools/cc-shim/cc-shim.c` + `build.sh` (cache `~/.cache/cc-shim/<sha16>-<arch>/`, link
  `~/.claude/libexec/cc-shim`, 0555, `--selftest` 26/26), best-effort build in `install.sh`. Matches the
  kernel on 19/19 #! forms measured on 15.8.1; deliberate differences: no newline in 512 bytes, 513-byte
  lines and bare `#!` exit 126 (the kernel's ENOEXEC lets a bash caller run the file silently);
  `env NAME` is resolved on the caller's PATH and exec'd directly only when it is a Mach-O. Hop guard 16.
  `tests/cc-shim.bats` is differential against by-path kernel runs (~17 kernel execs per run).
- **bats-core 1.13.0** under `vendor/bats-core` (upstream tarball, = Homebrew's bytes), nine internal
  execs run as `"$BASH" <path>` (`# cc-kalloc:` hunks; the six the REPORT named plus bin/bats, the
  preprocessor and built-in formatters). `bin/cc-bats` prefers it (after the CC_BATS_REAL pin;
  `CC_BATS_VENDORED=0` opts out), runs it through bash, and exports CC_SHIM. Upstream PR drafted, not
  opened: `docs/research/kalloc-longterm-2026-10-21/upstream-bats-pr.md`.
- **cc_stub** `tests/helpers/cc-stub.bash` (REPORT's `tests/lib/` does not exist): `cc_stub DIR NAME
  BODY|-`, batch form `cc_stub_dir`/`cc_stub_finish`, plain fallback without CC_SHIM.
- **R4** `scripts/test-stub-lint.sh` + `config/test-stub-baseline.tsv`; a `cc_stub` body never counts;
  the ship-land arm refuses a count over baseline and a raised baseline row.
- **Learnings.** A converted stub must be one the subject EXECS: `python3 "$x"`, `bash "$x"`, read,
  listed or committed-as-data fixtures stay plain (a link to a Mach-O breaks them). A body keyed on
  `$0` sees `.<D>-real/NAME`. At load 300-480 teammate panes would not spawn (kitty launch rc 124), so
  the conversions ran on the three existing teammates and the lead.
- **Converted, census order** (exec'd stubs converted / left plain; every file run before, with
  cc-shim, and plain): boot-resume 27/1 (93/93), boundary-handoff-forks + bash-hook-trims-forks via
  `tests/stop-hook-forks-helpers.bash` (batch form, every PATH name; 6 and 10 tests, same results all
  arms — boundary-handoff test 5 is a pre-existing wall-clock flake), ship-land 15/~95 (185/185),
  autonomy-sweep 11/22 (mostly red at load ~370 before and after on its 30 s subject bound; the 26
  cases that reach a converted stub pass with the bound raised), accounts-board 4/1 (42/42),
  operator-readout 8/56 (134/134), cc-reaper 49/3 (236/236), lr-fleet 36/4 (same 5 reds as before),
  cc-offload 24/4 (60/60), deploy-live 9/13 (168/168), postland-verify 19/13 (second land; 16 targeted
  cases that reach every converted helper, 16/16 in all three arms — the full 152-test run was cut by
  load ~500, ~10 min a case). The ~95 left in ship-land are fixture-repo content the gate commits and
  shellchecks.
- **Vendored shellcheck.** Upstream's files fail bare shellcheck on SC1091/SC2034/SC2154 only;
  `vendor/bats-core/.shellcheckrc` waives those three for that tree (the patch adds none).
- **Not built, and why:** the `-j` GNU-parallel path of the bats patch is untested (no `parallel` on
  this box); the upstream bats PR is drafted, not opened (brief); delisting boot-resume and
  operator-readout from `scripts/offbox-excluded.manifest` (the land's off-box arm reads both green now)
  needs a named mechanism, which this wave did not establish. ship-land.bats' plain arm finished
  185/185 after the land. Landed through `40de48c0b`; `git log origin/main --grep 'cc_stub\|cc-shim\|R4'`.

### W4 call sites and Mach-O entries — DONE 2026-10-22 (session kte-w4 + teammate macho; landed through `e2808f9c5`, lead-verified by content; `~/.claude/bin/it2` read back as Mach-O)

Scope (frozen): cc-run.sh runner + python twin, resolve_bin's callers through it, lint R2 with a ratchet
baseline wired into ship-land, call sites in census order incl. W1's session roots, Mach-O entries for
`~/.claude/bin/it2` and the cc-qos-exec names; no blanket shim.

- **Runner** `scripts/lib/cc-run.sh`: `cc_argv PATH` sets `CC_ARGV` to the argv the kernel would build
  from the `#!` line (xnu space/tab split); `cc_run PATH args` runs it. A Mach-O, a no-`#!` file, a bare
  name, a non-+x file, a `#!` interpreter and a missing file pass through unchanged. Fork-free, bash 3.2
  safe. `scripts/lib/cc_run.py` is the same rule for subprocess sites (cc-venue `_run`,
  cc-model-registered), loaded by file location. `tests/cc-run-lib.bats` 9/9 is differential against
  by-path runs under /bin/bash 3.2 and Homebrew bash. (`tests/cc-run.bats` belongs to `bin/cc-run`, the
  unrelated heartbeat tool.)
- **resolve_bin**: its output contract (a path) is unchanged; `cc-common.sh` sources the runner, so its
  callers run results through it. autonomy-sweep maps inside `_bounded`/`sweep_bounded`, boot-resume runs
  its nine helpers with `cc_run`.
- **Lint R2** `scripts/exec-form-lint.sh` (ratchet) + `scripts/exec-form-lint.py` (predicate) +
  `config/exec-form-baseline.tsv`; ship-land arm after HOOK SHEBANG, same shape as R4 (selftest,
  non-verdict on 2, raise refused without `SHIP_LAND_EXEC_FORM_RAISE_OK=1`). Sees literal repo paths,
  beside-script paths and same-file variables (seam defaults, `resolve_bin`), through exec, timeout,
  gtimeout, nohup, taskpolicy, env, xargs, `find -exec` and local `*bounded` relays; a wrapper that maps
  its command through `cc_argv` (or hands it to one that does) is safe. `tests/exec-form-lint.bats`.
- **Call sites**: 260 findings → 42 after the conversion. The census-order hot paths went first:
  ship-land's `own_run`/`lint_own_scope`/`selftest_ok` and its cc-backlog sites, postland-verify's
  prelint runner, wrap-ledger's `_bounded` and its cache filler, operator-readout's cc-research,
  session-start-dispatch's ten children, the `*bounded` relays (handoff-fire `hf_bounded_s`,
  lr-reset-poller, lead-crash-watchdog, pane-close-retry, cc-pane-close, strand-fill-arm), then the
  direct sites in ~60 files. W1's roots: `exec /bin/bash "$CC_PANE_RUNNER"` in handoff-fire and lr-lib;
  boot-resume-launch and cc-resume-layout build the reso-resume-one argv from `cc_argv`.
- **Learnings.** (1) bash 3.2 under `set -e` EXITS on a failed `.` even inside `||`; bash 5 does not.
  Every runner source is `if [ -f X ]; then . X; else <fallback>; fi`. The bug showed up as
  banner-video's copied-script suite going 0/6. (2) Suites `sed`-extract functions and eval them alone,
  so relays guard with the builtin `declare -F cc_argv` (no fork), and the seven suites that eval a
  function that now calls `cc_run` load the runner first. (3) shlex is a weak shell reader: it splits
  `${X:-d}` on its braces, cuts `${#a[@]}` at the `#`, glues `));`, and cannot see inside a quoted
  `"$(cmd)"`. Each of these hid real sites until it was fixed.
- **Mach-O entries (teammate macho).** With cc-shim built, install.sh makes `~/.claude/bin/it2` and
  every `config/qos-shim.names` entry a link to `libexec/cc-shim`. The real file moves to
  `.bin-real/<name>`: a copy of it2-wrapper, or a link to cc-qos-exec. `CC_SHIM_ENTRIES=0` restores
  today's layout, and no `cp` writes through a link. Claude Code reaches it2 through kitty-setup's
  `shims/it2 → bin/it2`, and cc-shim derives its target from the unresolved path, so
  `.shims-real/it2 → .bin-real/it2` keeps that route working. it2-wrapper maps a `.bin-real` dir to its
  `bin` siblings. cc-qos-exec and cc-bats skip a cc-shim candidate in their PATH walk, and qos-rewrite
  accepts the shim layout. deploy-parity reads the `.bin-real` copy, and deploy-link-parity reports
  `SHIMMISS`. `tests/install-cc-shim-entries.bats` runs the real built shim through `bin/it2`,
  `shims/it2` (and a control without `.shims-real`) and `bin/shellcheck`.
- **Left (baseline 42):** zsh-sourced libs (`lib/cc-resume-shell.sh` 10, `lib/*.zsh`; the bash runner
  is not zsh-safe), applied migrations (9, one-shots), `install.sh` and `deploy-parity-assert.sh` (the
  teammate's files this wave), test and bench drivers, and one false positive (`bin/cc-kqwait:301` execs
  its compiled cache binary). By-name calls (`cc-backlog add` typed or in scripts) are outside R2: they
  are a PATH lookup, and only a launcher at `~/.claude/bin` reaches them (REPORT §2 row 9, not built).
- Earlier: two fires on 2026-10-22 ~13:30Z came back outcome UNKNOWN with no session: kitty pid 1881 answered
  every `kitten @` with `Error: EOF` for ~3 h (258 peerless unix sockets held). It recovered WITHOUT a
  restart (the third fire engaged); row `13c537f2ed69` closed. Learning: a deaf kitty can come back on
  its own as load falls, and the 5-minute heartbeat's `hb.kitty-ls.json` mtime shows it first. Check
  that before recommending a restart, and if one is needed it is `cc-restore --restart-kitty --confirm
  <pid>` (waits for in-flight lands, restores the recorded layout), never a bare quit and reopen.
- Brief scope: `scripts/lib/cc-run.sh` runner (bash 3.2 safe), `resolve_bin` (`scripts/lib/cc-common.sh:35`)
  through it, lint R2 `scripts/exec-form-lint.sh` beside the HOOK SHEBANG arm (`scripts/ship-land.sh:~3956`),
  call sites in census order including W1's leftovers (`handoff-fire.sh:~1321`, `lr-lib.sh:~1338`,
  `reso-resume-one` callers), Mach-O entries for `~/.claude/bin/it2` (copied from `bin/it2-wrapper`,
  `install.sh:~1164`) and `bin/cc-qos-exec` (PATH walk `:55-66`, `qos-rewrite.sh:~188`). No blanket shim.
### W5 keep-it-fixed loop — DONE 2026-10-22 (session kte-w5; landed through `f35645dea`, lead-verified by content)

- **SLO check** `scripts/kalloc-slo.sh` (`tests/kalloc-slo.bats`), ticked by `capacity-alarm.sh`'s launchd
  run (fail-soft, bounded 120 s, after the zone state; damped to once an hour; `CC_CAP_KALLOC_SLO=off`).
  Breach: this boot's trailing-24 h slope > 0.45 GiB/day, or growth per Bash call > 1.5x the previous
  boot's last 24 h (`kalloc-leak-rate.sh --span`, new, on both sides). Target reported, never filed: the
  median of the last 7 days' per-boot-day fits (each ≥ 12 h, ≥ 4 days) ≤ 0.30. Boot segments come from
  the series itself (a reboot halves the zone). Abstain (exit 3, stored with its reason) under ~22 h of
  boot or an unreadable series. State `~/.claude/autonomy/kalloc-slo.state`, history `logs/kalloc-slo.log`;
  the hand-run report prints the stored line. No new launchd job, no plist edit.
- **Operator row:** one `cc-backlog needs … --class needs-human --run "bash <abs>/kalloc-exec-census.sh 600"`,
  constant title; none while the filed row is live, none for 7 d after it closes. The `--run` path is
  absolute, not the brief's `scripts/…`: cc-do runs a row's command with `bash -c` in the operator's cwd.
- **Census ranking:** `ranking.tsv` (every script, per 10 min, class, top caller) and `lint-drafts.txt`
  (paths above N that the previous census in the same dir did not have above N), drafts only. N = 50
  per 10 min: ~2.5% of the 0.30 GiB/day budget (~1,990 execs per 10 min at 1.1 KiB); on REPORT §7 it
  flags the two paths W1 fixed (282, 124) and none of the 31-41 tail W4 covers.
- **First live read (2026-10-22 08:13Z):** abstain, boot 11.7 h old; trailing slope 0.95 GiB/day,
  previous boot 40.5 elements per Bash call. Unless W2-W4 land first, it breaches and files the census
  row once this boot passes ~22 h.

## Measurements after W1, W3, W4, W5 (W2 not yet landed)

- **Census 2026-10-22 17:55-18:05 CDT** (`~/.cache/kalloc-exec-census/20261022T175520/`, 604 s): 875
  `#!` execs = 5,215/h, against 32,530/h in the 2026-10-21 baseline hour (−84%). No agent-context-sync
  stub in the top rows, so this window carries no W2-class load; the like-for-like figure (baseline
  without its ~53% agent-context-sync share, ~15,300/h) is about −66%.
- **Zone over the same window:** `data.kalloc.1024` +876 elements in 835 s (series row 17:52:15 →
  direct `zprint` 18:06:10) ≈ **0.09 GiB/day**, i.e. ~0.7 elements per counted `#!` exec, so the census
  explains the zone and no second source shows (REPORT §6 Q5). 15-min zone slopes before it: 0.33,
  0.28, 0.01 GiB/day; trailing 3 h 0.70, 24-12 h ago 1.06 (heavier land and test load earlier).
- **One window is not the verdict** (shares swing 3-8x between windows): the W5 SLO's trailing-24 h
  slope (`scripts/kalloc-slo.sh`) is. Target ≤ 0.30 GiB/day; this window reads at the REPORT's ~0.1.
- **Residue named by the census:** test harnesses running worktree `bin/` scripts by path (`cc-backlog`
  106, `cc-premise` 54, postland `shim/jq` 72; the three `lint-drafts.txt` rows, all class=test, from
  the `kte-w01` worktree's own suite runs and postland temp trees); `/usr/bin/shasum` 30, 26 from
  `kte-w01` (unverified whether these are W1's byte-identity fixture, which runs shasum on purpose),
  1 from `tm-upstream-wt`. Neither is attributed further; the next census after W2 lands re-ranks.
