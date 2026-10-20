# 07 — The terminal control plane under sustained load

Axis: why kitty's remote-control socket (`/tmp/kitty-853`) "stops answering within 10 s at load 300",
and how limit-recover can stop depending on it. Read-only investigation, 2026-10-20 ~04:20-04:50Z.
I typed into no pane, signalled no process, and changed no setting. The only things I ran against the
live system were read-only kitty RPCs (`ls`, `ls --match`, `get-text`, `it2 session list --json`), about
70 in all, plus `ps`, `netstat`, `lsof`, `pmset -g log` and `log show`. Probe processes of my own were
run under `taskpolicy -c utility|background` to reproduce the callers' QoS bands. Labels: **[M]** is
measured, with the command named. **[E]** is estimated, with the method named. **[H]** is a hypothesis
that has not been verified.

## 0. Answer

1. **In this incident kitty was mostly not deaf. The callers were starved.** The whole LR control
   plane runs in Darwin's **utility band (PRI 20)**, because `com.reso.lr-reconciler` (and the reset
   poller, watchdog, rig and boot-resume) have no `ProcessType`. Every worker, `lr-handoff`,
   `handoff-fire`, recycle watcher and `kitten @` client inherits that band [M]. The ~676 session
   processes run at PRI 31 [M]. At load 168-234 I ran the same kitty call from each band [M]:

   | caller band | `kitten @ ls --match id:38` | python connect probe (the 3 s-bounded one) | `it2 session list --json` (the watcher's pane probe, 10 s bound) |
   |---|---|---|---|
   | PRI 31 (default) | 0.051-0.083 s (5/5) | 0.078-0.199 s | 0.38-1.25 s (5/5 pass) |
   | PRI 20 (utility = the reconciler's band) | 0.99-5.65 s | 1.26-3.79 s (1/5 over 3 s) | 10.5 s, 24.6 s, >30 s, >30 s, 6.1 s (**1/5 inside 10 s**) |
   | PRI 4 (background) | >30 s, 4/4 timed out | >30 s, 4/4 | >30 s, 4/4 |

   The incident failure signatures reproduce exactly from PRI 20, while kitty answers in ~0.1 s:
   - "the probe's own 3s bound fired (rc 124) … (0 queued)": the kernel listen queue was empty, so the
     probe process never reached `connect()`.
   - "listing rc=124 in 13s" on the watcher's pane probe.
   - `composer: unreadable`.
   - `REMOTE-PANE-RESOLVER-UNAVAILABLE`.
2. **kitty's own log agrees.** Stock 0.48.2 logs `write() to peer socket failed … Broken pipe`
   whenever it answers a client that has already given up. In `log show --predicate 'processID == 853'`
   from 02:00 to 04:35Z there is **one** such line (03:12:14Z) [M]. Against it stand at least 6
   kitty-attributed client failures in the same window. On the 10-01 kitty-side deafness the same
   instrument read about 180 lines (`session-durability-2026-10/C3-socket-robustness.md:107`).
   Requests that never reach kitty leave no broken pipe; requests that kitty answers late leave one each.
3. **kitty itself is healthy at load 200.** Its main thread sits at PRI 46-54 (`ps -M -p 853`). A 20-sample
   sampler (`bash /tmp/k07-sampler.sh`, 12 s apart, load 196-217) gave **20/20 answers in
   0.064-0.165 s**, listen Recv-Q 0 and kitty CPU 1-16% [M]. Load per core does not by itself make
   kitty deaf.
4. **Three kitty-side classes are real but were not the main cause this time.** Each has a cheap
   operator-side fix (§5):
   - **App Nap:** PRI 4 measured on 10-01 with the screen locked. `NSAppSleepDisabled` is still unset [M].
   - **Stock-0.48.2 talk-thread death:** the running `.so` lacks the patch string; the patched build sits
     staged since 10-16 [M].
   - **The fd ceiling:** 121 fds open against a probable 256 soft limit [M/H].
5. **How to recover reliably without depending on kitty.** The fix is not a second socket or a faster
   kitty. It has two parts:
   - **(a)** Run the control plane in the band of the work it gates (`ProcessType Interactive` on the
     reconciler, with heavy census children explicitly clamped back to utility).
   - **(b)** Remove kitty from the critical path of the in-place recycle. Its tail is already
     kitty-free and proved itself in the incident: SIGTERM exit plus a staged successor, 6/6 claimed
     "nothing typed". What still needs kitty are five **pre-commit reads**: pane→tty resolver, connect
     probe, focus, composer, and the watcher's pane probe. Each has a kernel- or disk-side substitute,
     or can be made advisory once the successor is staged (§6).

## 1. Measurements

| # | What | Reading | Command | M/E |
|---|---|---|---|---|
| 1 | kitty build | 0.48.2, started 2026-10-18 19:40 CDT; running `kitty.fast_data_types.so` dated Jul 30, `strings … \| grep -c 'still serving'` → 0; staged `/Applications/kitty.app.staged/…/fast_data_types.so` (Oct 16) → 1 | `kitty --version`, `strings` | M |
| 2 | kitty threads / priority | main thread `46T` (sampled 46/47/54 over 4 min); all other threads `31T` | `ps -M -p 853`; sampler | M |
| 3 | kitty App Nap setting | `NSAppSleepDisabled` does not exist (the 10-01 recommendation was never applied) | `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` | M |
| 4 | kitty fds | 121 numeric fds (55 PIPE, 34 CHR, 30 REG, 2 unix); kitty never raises RLIMIT_NOFILE (C3 §1.1), so the soft limit is probably launchd's 256 | `lsof -p 853 -a -d 0-9999` | M (limit: H) |
| 5 | windows | 7 OS windows, 7 tabs, **32 windows**, 111 foreground processes | `kitten @ ls` → python count | M |
| 6 | cost of a full `ls` | **~650 KB** JSON per call, of which 558 KB is `foreground_processes`, built on kitty's MAIN thread | same | M |
| 7 | `ls` latency, PRI 31 caller | full: 0.14-0.18 s; `--match id:38`: 0.10-0.19 s (49 KB); `get-text --extent screen`: 0.08-0.09 s; load1 87-207 | timed `kitten @ … ` ×3 each | M |
| 8 | sustained sampler | 20/20 rc 0, 0.064-0.165 s, listen Recv-Q 0, load1 196-217 | `bash /tmp/k07-sampler.sh` | M |
| 9 | caller-band experiment | table in §0.1 (rounds r1-r5, load1 168-234) | `bash /tmp/k07-qos.sh` (own processes under `/usr/sbin/taskpolicy -c utility\|background`) | M |
| 10 | LR band | `lr_recon` pid 51148 **PRI 20**; its child `caffeinate` PRI 20; `com.reso.lr-reconciler`, `-reset-poller`, `-reconciler-watchdog`, `-reconciler-rig`, `com.claude.boot-resume`: no `ProcessType` | `ps -o pri`, `plutil -extract ProcessType` | M |
| 11 | what "no ProcessType" means | "If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth" | `man launchd.plist` | M |
| 12 | inheritance | a child of a utility-clamped parent cannot climb back to 31, even with `taskpolicy -a` | `scripts/limit-recover/lr-reset-poller.sh:249-252`; `docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md:154-159` | M (prior) |
| 13 | worker spawn | `subprocess.Popen(..., start_new_session=True)` with no QoS change | `lr_recon/act.py:315-329`, `__main__.py:521-526`, `plan.py:331` | M |
| 14 | late kitty answers in the window | 1 `write() to peer socket failed … Broken pipe` (03:12:14Z) in 8,721 kitty log lines, 02:00-04:35Z | `log show --predicate 'processID == 853'` | M |
| 15 | display / operator | `displaysleep 0`, no display-off in the window; HID idle from ~02:56Z to 04:08Z (powerd `UserIsActive` ages); no explicit lock event found | `pmset -g`, `pmset -g log`, `log show` (loginwindow) | M; lock state unknown |
| 16 | kitty client timeout | `kitten @` defaults to a 10 s response timeout (`kitty/rc/base.py:343` `response_timeout: float = 10.`); `ls` exposes no `--response-timeout` | v0.48.2 source; `kitten @ ls --help` | M |

## 2. How kitty answers a remote-control call (v0.48.2 source)

- **Talk thread** `KittyPeerMon` (`child-monitor.c:2009-2087`) runs at PRI 31 [M row 2]. It polls the
  listen fd and the peers, accepts, reads until `ESC \`, and queues the message under `talk_lock`
  (`queue_peer_message`, `:1856-1874`). Then it wakes the main loop.
- **Main thread** (PRI 46) handles queued messages inside `parse_input` (`:521-551`). That runs once per
  main-loop iteration, beside the VT parse of every window's pending pty bytes and `render()`
  (`process_global_state`, `:1394-1426`). The response goes back to the talk thread
  (`send_response_to_peer`, `:2089-2116`).
- **I/O thread** `KittyChildMon` (`:1647`) only reads pty bytes into each screen's buffer. It stops
  polling a pty when that buffer is full (`vt_parser_has_space_for_input`, `:1666`).
- **One socket, one main thread.** `listen_on` takes one address (`kitty/options/definition.py:2797-2815`;
  "Changing this option by reloading the config is not supported"). A second socket would feed the same
  talk thread and the same main-thread queue.
- **Abandoned peers are kept until the main thread answers.** `prune_peers` (`:1964-1975`) does this, so a
  deaf main thread accumulates fds. Combined with stock 0.48.2's `accept_peer` → `goto end` (`:1821-1826`,
  `:2058`), that is the 10-01 permanent death. The fix is `docs/patches/kitty-talk-thread-survives-v0.48.2.patch`.
- **Cost of `ls`.** It serialises every window's `foreground_processes` (cmdline and cwd per process) on the
  main thread, about 650 KB for 32 windows (rows 5-6). `ls --match id:N` cuts the payload 13× (49 KB) but
  not the round trip (row 7), so kitty-side cost is not the bottleneck at PRI 31.

**Implication.** A call has four hops: client process start, connect/write, kitty, then client read and
exit. The two client hops run at the caller's priority. At PRI 20 or PRI 4 under ~20-30 runnable
threads per core, those hops dominate (row 9). At PRI 31 the whole round trip is about 0.1 s.

## 3. The incident through this lens (2026-10-20, next3 weekly cap)

Kitty-touching outcomes, from `~/.reso/limit-recover/recon/actlogs/*.R.log` and
`~/.claude/logs/handoffs.jsonl` [M]:

| time (Z) | session / pane | step | outcome |
|---|---|---|---|
| ≈03:12 | d7eb73d2 / 32 | precheck `hf_remote_pane_term` (ls) | `HELD:pane:resolver-unavailable`, NOTMOVED |
| ≈03:15 | 7aae55e1 / 38 | precheck composer read (get-text) | `HELD:composer-unreadable`, NOTMOVED (hid_idle 1144 s, not focused) |
| ≈03:18 | e80b61f4 / 55 | precheck connect probe | "3s bound fired (rc 124) … (0 queued)", then OK on try 2 |
| 03:24:39 → 03:28:11 | db755a94 / 41 | **after transplant**, watcher `it2 session list` | `pane-NO-ANSWER rc=124 in 13s`, recycle ABORTED, admit rolled back (phases `gates@69s … intent@239s … detach@410s`) |
| ≈03:44 | d7eb73d2 / 32 | precheck connect probe | 3 s bound fired, then OK on try 2 → recycled; engaged 03:53:31 |
| 04:21:53 → 04:23:25 | pane 30 | watcher pane probe | `recycle-held-unreachable` again, after `detach@310s` |

Two cross-checks:

- **The kitty-free tail worked every time it was reached.** `recycle-exit-signal` (SIGTERM, "nothing
  typed") was followed by `recycle-successor-claimed` in 10-65 s, 6/6 times (panes 27, 32, 31, 24, 55, 38),
  each ending `recycle-engaged`.
- **A natural experiment points at the band.** Pane 27's recycle at 02:31Z was a self-recycle from inside
  its session, so it ran at PRI 31. It went from gates to engaged in **133 s**
  (`gates@0s … intent@16s … armed@41s`, engaged 02:33:48). The reconciler-driven (PRI 20) recycles of panes
  32, 55, 31 and 24 took **7.0-8.7 min** from gates to engaged. Their gates alone took 69-174 s, and
  "foreground has not written exit-committed" persisted 244-310 s after the watcher armed [M, handoffs.jsonl
  phases]. Load differed between the runs, so this is suggestive rather than controlled [H]. Row 9 is the
  controlled version.

Counted as estimated from code reading [E]: one reconciler in-place move issues about **8-10 full `ls`
plus 3-4 `get-text`** before its commit. Each one is a fresh `bash → timeout → kitten|it2 → python` chain:

- precheck: `hf_remote_pane_term`, kitty probe (connect plus ls), `as_tty` with up to 5 retries,
  `kt_window_field pid`, focus, and the composer get-text (`handoff-fire.sh:13806-13950`);
- recycle: resolver, composer gate, focus, the watcher's pane probe, and the freshness get-text
  (`:19880-20010`).

On top of these, the reconciler runs its own `kitten @ ls` every pass with a 5 s bound
(`lr_recon/observe.py:235-252`). When that fails, every pane reads `unknown` (`evidence.py:113`). At
PRI 20 each chain costs about 1-30 s (row 9). So a move pays minutes of kitty-shaped latency and gets
roughly 8-14 chances to hit a bound.

## 4. Failure classes and their discriminators

| class | signature | discriminator (lower layer) | this incident | remedy |
|---|---|---|---|---|
| A. **caller starved** (utility/background band) | rc 124 at the client bound; connect probe times out with **listen Recv-Q 0**; no broken pipe in kitty's log | caller's `ps -o pri` ≤ 20; kitty log has no late-answer lines | **dominant** (rows 9, 14) | ProcessType Interactive; fewer process hops per call |
| B. kitty main thread de-prioritised (App Nap / PRI 4) | client accepted, request read, answer late → **broken pipe per timed-out client**; kitty `ps -o pri` = 4 | `ps -o pri= -p <kitty>`; kitty's broken-pipe count | not observed (1 line); kitty pri unknown during 02:31-04:14Z | `NSAppSleepDisabled YES` (operator, next kitty start) |
| C. talk thread dead (stock 0.48.2) | connect accepts, Recv-Q on accepted rows grows, never answers; hours | `netstat -anv -f unix` rows with Recv-Q>0 in two samples; `sample` lacks `KittyPeerMon` | no (answered later) | swap to the staged patched build (operator) |
| D. main thread busy (huge `ls`, output floods) | slow but answering | kitty pcpu high; `ls --match` vs full `ls` | no (0.06-0.18 s at load 200) | prefer `ls --match id:N` / `get-text` |

`docs/lessons/two-causes-one-rc-ask-a-lower-layer.md` already says "ask connect(2)". This axis adds
that connect(2) only discriminates when the **asker** gets a CPU slice. A 3 s-bounded python connect
probe started at PRI 20 measured 3.79 s with **kitty idle and Recv-Q 0** (row 9, r1). So "the probe's
own bound fired" is a fact about the prober's band and says nothing about kitty. `hf_kprobe_connect_say`
already words it as "could not tell", which is correct. The callers that hold on it act as if it were a
kitty fact.

## 5. Kitty-side alternatives the brief asked about

- **kitty at higher QoS.** The main thread is already at PRI 46-54, above every session process [M
  row 2]. Raising it buys nothing while kitty is foreground-eligible. The real kitty-side QoS risk is a
  drop to the **background** band (App Nap). It was measured at PRI 4 on 10-01 (screen locked,
  `recycle-unreachable-2026-10-01.md:13`), and on 10-01 a staged non-frontmost kitty sat at PRI 4
  (`C3-socket-robustness.md:301-303`). `NSAppSleepDisabled` is still unset [M row 3]. Recommended as
  operator hygiene: `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES` at the next kitty
  start, then read `ps -o pri= -p <kitty>` back while the screen is locked. It is not the fix for this
  incident.
- **A second kitty listen socket.** Rejected. kitty accepts one `listen_on` (definition.py:2797). Even
  with two, both would feed one talk thread and one main-thread queue (§2). It adds an fd and a
  second identity to keep, and it changes nothing for a starved caller.
- **Talk-thread patch and fd headroom.** Adopt the staged build: the running `.so` lacks it [M row 1].
  It removes class C, the multi-hour outage. Measure kitty's fd count beside every kitty probe (121 of a
  probable 256 now) [M/H].
- **`--response-timeout` / longer client waits.** `ls` has none, and the client default is 10 s (row 16).
  Waiting longer does not help a starved caller, whose own process hops are the slow part. It also holds
  a kitty fd per abandoned peer (`prune_peers`). A retry from a properly-banded caller is the effective
  "longer wait".

## 6. Removing kitty from recovery's critical path

Today's in-place recycle already has a kitty-free **tail**:

- exit by SIGTERM to a pid+lstart-pinned claude (`hf_exit_signal`, `handoff-fire.sh:3975-4060`; incident
  rows "SIGTERM … nothing typed");
- relaunch by a **staged successor** that the pane's own shell claims by atomic rename keyed on its tty
  (`lib/pane-successor.sh:1-40`; "Delivery becomes a local atomic rename: load can delay it but cannot
  fail it");
- verification from disk (transcript / registry engagement oracle).

What is left are the **pre-commit kitty reads**. Each is replaceable or demotable:

| kitty read today | what it proves | kitty-free substitute | residual risk |
|---|---|---|---|
| `hf_remote_pane_term`, `as_tty`, `kt_window_field pid` (window → root pid → tty) | pane P exists and is this tty | **Registry pid+tty plus a cached window identity**. The reconciler's census already holds `(kitty_pid, window_id, root_pid, root_lstart, tty)` per record (`lr_recon/census.py:376-395`, `evidence.py:118-129`). Verify with the kernel only: `ps` shows `root_pid` alive with the same lstart and `ppid == kitty_pid`; the claude pid of the registry row is on the same tty. A window's root process (`/usr/bin/login`) lives exactly as long as the window, so pid+lstart is the identity. tty alone is not (kitty re-issues ttys, `lib/pane-successor.sh:38-40`). | a window closed and its root pid reused with the same lstart: negligible. Pass the census identity to lr-handoff (env/argv) instead of re-deriving it through kitty. |
| `hf_recycle_kitty_probe` (connect + ls) | "the later kitty steps will work" | Not needed when none of the later steps needs kitty. Keep it advisory: log it, never hold on it when the successor is staged and the exit is a signal. | none beyond the rows below |
| focus (`hf_pane_focused` = `ls is_focused`) | the operator may be typing in P | **kitty not the frontmost app** (`lsappinfo front` → not `net.kovidgoyal.kitty`; LaunchServices, no kitty IPC) means no kitty window can take keystrokes. Otherwise use HID idle ≥ the focus-gate gap (`lr_hid_idle_s`, already logged: 1144-3520 s in the incident). | a programmatic `send-text` from another tool; it submits, so it leaves no draft |
| composer read (`get-text`) | no operator draft would be lost or merged | **last-good read + HID idle**: when a composer read succeeded at T0 (cache content and time per pane) and HID idle > now−T0, no human typed since T0, so the box still holds what it held. Typed `/exit` is gone (SIGTERM), so a draft cannot be *merged*; the residual is *losing* one. | a draft typed before T0 with an unreadable read ever since: refuse only that case. [H] whether Claude Code persists an unsent draft across SIGTERM; unverified. |
| watcher `pane_proof` (`it2 session list --json`, one shot, 10 s) | the watcher can type the relaunch | With a **staged successor and signal exit**, the watcher types only on the fallback (no claim within `CC_RECYCLE_CLAIM_GRACE_S` 20 s). Make the probe **advisory** in that mode, or at least retry it (it is one-shot today, `handoff-fire.sh:4362-4421`, `:19967-20004`). It held 2 recycles *after* their transplant (41, 30), wasting 310-410 s each. | stage unclaimed and kitty deaf at the same time: the watcher's typed fallback already retries to a 600 s deadline (`:12567`), and an unclaimed pane still holds a transplanted, resumable session (no data loss). |
| freshness composer re-read right before `/exit` (`:20015-20032`) | race of a draft typed in the last ~1 s | same HID-idle rule; with SIGTERM there is no keystroke to race | as above |
| reconciler's per-pass `kitten @ ls` (5 s) → `unknown` panes | window table | Same census, banded at 31; when it fails, use the cached identity from the last good read (verified by `ps`) instead of `unknown` for records that already carry a root pid+lstart (`evidence.py:113`). | none new |

**Two transport alternatives the brief asked about are not viable:**

- **"tty write for the relaunch".** Writing to `/dev/ttysNNN` (the slave) only paints output. Injecting
  *input* needs `TIOCSTI`, and XNU refuses it to a non-root caller unless the tty is the caller's
  controlling terminal (`bsd/kern/tty.c:1431-1436`: `suser(...) && !isctty(p, tp)` → error) [M, source].
  A setsid'd reconciler worker has no ctty. The staged successor *is* the kitty-free relaunch, and it
  already works under load (6/6 in the incident).
- **"Launch the replacement in a new window when the socket is slow".** `kitty @ launch` is the same RPC
  on the same main thread. A new window without RPC means a new **kitty process** (`open -na kitty.app
  --args …`). That gives a separate OS window and process, no layout, and about 100-180 MB RSS each [E,
  kitty's RSS 177 MB from `ps` row 1, as a ceiling]. It is not better than in-place. Keep it at most as a
  last-resort fallback for a pane that is provably gone, because in-place via the staged successor is
  strictly more kitty-free.

## 7. Levers (ranked)

1. **Put the LR control plane in the Interactive band.** Add `ProcessType Interactive` to
   `com.reso.lr-reconciler` (and the reset poller / move kick, `boot-resume`). Clamp the heavy census
   children back to `taskpolicy -c utility`, as `lr-move-batch.sh:333-339` already does.
   - Mechanism: the client hops of every kitty call (and of every probe and bound in the lane) get a
     PRI 31 slice.
   - Measured effect at load ~200: `kitten @ ls` 1-5.6 s → 0.05-0.08 s; the watcher's `it2 session
     list` 6.1→>30 s → 0.38-1.25 s (1/5 → 5/5 inside its 10 s bound).
   - Risk: the reconciler's own CPU now competes at 31 [E: census 19-27 CPU-s per
     `lr-move-batch.sh:335-336`, clamped].
   - Operator step: launchctl reload.
   - The staged `launchd/staged/com.reso.lr-move-kick.plist` covers only the poller's move lane and is
     not installed (`ls ~/Library/LaunchAgents` → absent) [M].
2. **Kitty-free pre-commit identity.** Hand the census identity `(kitty_pid, window_id, root_pid,
   root_lstart, tty)` to lr-handoff / handoff-fire and verify it with `ps` only.
   `hf_remote_pane_term`/`as_tty` fall back to it on rc 3 instead of `HELD:pane:resolver-unavailable`.
3. **Make the watcher pane probe advisory when the successor is staged and the exit is a signal.**
   Otherwise retry it on a schedule before rolling back a transplant. It cost 2 transplants in this
   incident (410 s and 310 s of work rolled back).
4. **Composer/focus gate from kernel and HID facts when kitty does not answer.** The rules are: kitty
   not frontmost, or HID idle > now − last good read, with the cached content. Turns
   `HELD:composer-unreadable` (7aae55e1, hid_idle 1144 s) into a proceed.
5. **Fewer process hops per kitty call.** `it2 session list --json` costs 6-15× `kitten @ ls` even at
   PRI 31 (0.47-1.25 s vs 0.05-0.08 s) because it is bash + kitten + python over 650 KB. Use `kitten @ ls
   --match id:N` (49 KB) for single-pane probes, and one census read per pass shared by all consumers.
6. **Kitty hygiene (operator, not this incident's cause):**
   - `NSAppSleepDisabled YES`;
   - swap to the staged talk-thread-patched build;
   - watch kitty's fd count against 256.

## 8. Open questions

- What was kitty's own priority between 02:31 and 04:14Z? Nothing samples it. A per-minute
  `ps -o pri= -p <kitty>` plus a broken-pipe count in the LR heartbeat would settle class B in future
  incidents.
- Does Claude Code persist an unsent composer draft across SIGTERM? [H, unverified] This decides whether
  the composer gate is needed at all once the exit is a signal.
- What was the remaining ~244-310 s between "armed" and "exit-committed" for panes 32/24/31/55? It is
  not a kitty step that I can identify: `lr-transplant --phase confirm` and the transcript at-rest read
  sit there. It runs at PRI 20 too, so lever 1 probably shrinks it [H].
- Is the 2.3× (sibling 05) vs 10-90× (here) utility-band slowdown a property of the call shape (process
  spawns per call)? My calls spawn 1-4 processes. The slowdown appears to scale with the number of
  processes spawned per call [H].

## Deviations

- I ran about 70 read-only kitty RPCs, two small scripts of my own (`/tmp/k07-sampler.sh`,
  `/tmp/k07-qos.sh`, written with the Write tool), and `taskpolicy` on my own child processes. The
  background-band runs stayed starved for >30 s each and were killed by their own `timeout`. No system
  process, pane, setting or credential was touched.
- `/tmp/k07-qos.sh` round 5's background row was still running when this was written. The table uses
  rounds r1-r5 for the default and utility bands and r1-r4 for the background band (load1 168-234).

## Skeptic review

Adversarial re-check, 2026-10-20 ~04:50-05:00Z (local 23:50 CDT on 10-19). It was read-only. I ran
about 20 read-only kitty RPCs (`ls`, `ls --match`, `get-text`, `it2 session list --json`) from my own
processes, plus `ps`, `plutil`, `lsof`, `log show`, `strings` and `git show` on local kitty clones. Labels
follow the doc: [M] is measured, with the command named. My replication script is `/tmp/k07skep-qos.sh`
(4 rounds, default band and `taskpolicy -c utility`, load1 188-234), and its output is in
`/tmp/k07skep-qos.out`.

### Findings

| # | claim (short) | verdict | evidence |
|---|---|---|---|
| F1 | callers starved: PRI 20 blows the bounds, PRI 31 answers in ~0.1 s | **CONFIRMED** | Replication [M, `bash /tmp/k07skep-qos.sh`]. At PRI 31: `kitten @ ls --match id:38` 0.047-0.084 s, `get-text` 0.042-0.093 s, `it2 session list --json` 0.438-0.679 s, 4/4 rc 0. Under utility: kitten 1.07-4.56 s, get-text 1.11-2.32 s, it2 9.92 / 10.75 / 15.9 / 24.5 s (1/4 inside the 10 s bound). Sibling 04 measured this independently (0.05-0.06 s vs 0.41-0.83 s, `04-darwin-priority.md:188-190`). Caveat: nothing has been measured above ~23/core, and the incident peaked at 35-37/core. |
| F2 | the PRI 20 clamp comes from no ProcessType and is inherited | **CONFIRMED** | [M] `ps -o pri -p 51148` gives 20, and its children 39440 (python) and 70097 (caffeinate) are also 20. The plist has no ProcessType, no Nice and no taskpolicy wrapper (`plutil -p`). **Natural control:** `com.claude.research-classifier-warm` (ProcessType Interactive) runs pid 60282 at PRI 31, with claude children at 31/37. `com.reso.sevenrooms-sidecar` (ProcessType Standard) runs pid 1425 at PRI 20. The lr-move-kick plist is staged with Interactive (`launchd/staged/`) and is absent from `~/Library/LaunchAgents`. |
| F3 | kitty itself stays responsive at load ~200 | **CONFIRMED** | [M] `ps -M -p 853` shows the main thread at 47T and the other threads at 31T. A full `kitten @ ls` took 0.052 s for 660,430 B at load ~180, with 558,244 B of it foreground_processes, across 32 windows. Caveat: kitty was frontmost during my run (`lsappinfo front` gave "kitty"). The screen-locked band is not measured here; on 10-01 it was PRI 4. |
| F4 | kitty's log shows almost no late answers, so the requests never reached it | **CONFIRMED (core), one sub-inference invalid** | [M] `log show --start '2026-10-19 21:00' --end '23:35' --predicate 'processID == 853'` returned 9,725 lines with exactly 1 broken pipe (22:12:14 CDT = 03:12:14Z). The mechanism checks out in v0.48.2 source (`git show v0.48.2:kitty/child-monitor.c`): `write_to_peer` logs at :1949, and `prune_peers` (:1964-1975) keeps a peer until it has been answered. **Invalid:** "(0 queued) ⇒ the probe never reached connect()". `hf_kitty_queue_depth` (`lib/kitty-queue.sh:41-47`) counts rows with Recv-Q > 0, and it runs *after* the probe has been killed (`handoff-fire.sh:1527-1545`). The python probe also never sends a byte. So "0 queued" cannot tell whether the probe connected. Also, the one broken pipe falls 15 s before d7eb73d2.1's 18-minute precheck ended (actlog mtime 03:12:29Z). That hold therefore coincides with a real late (or mid-read-abandoned) kitty answer. |
| F5 | the tail is kitty-free and worked 6/6; kitty losses were all pre-commit, 2 of them after the transplant | **CONFIRMED, count corrected** | [M] handoffs.jsonl 02:00-04:59Z has **5** `recycle-exit-signal` rows (panes 32, 31, 24, 55, 38), claimed after 22, 48, 44, 65 and 10 s. Pane 27 did **not** exit by signal: "keep-work (2) dialog … Esc then /exit re-submitted" (02:32:46Z), i.e. typed. Staged successors were claimed 7/7. Pane 41 and pane 30 watcher logs show "listing rc=124 in 13s" and "in 12s". Pane 41: `db755a94.1.R.log:24,34` reads "transplant ok", then "abort … withdrew the admit". Pane 30's argv carries `--transplanted-source` (bundle 04:13:52Z). Outside this axis: two more post-transplant rollbacks were **not** kitty. `7aae55e1.2` and `e80b61f4.1` both read "--recycle REFUSED: another actuator holds session …'s move claim (pid 38189 / 47282, lr-reconciler)". |
| F6 | self-recycle at PRI 31 took 133 s against 7.0-8.7 min for reconciler (PRI 20) recycles | **REFUTED as stated** | [M] handoffs.jsonl `phases`/`elapsed_s`. Pane 38 (7aae55e1, a reconciler attempt `recon:…:7aae55e1:1:3`, PRI 20) had gates@22s, exit-signal at 79 s and engaged at **128 s**, faster than pane 27's 133 s. The doc's PRI 20 cohort leaves it out. The numbers are also misattributed. Pane 55's gates were **14 s**, not 69-174; 69 s belongs to pane 41. The real engaged `elapsed_s` values are 433 (55), 559 (32), 725 (31) and 726 (24), which is 7.2-12.1 min. Panes 31 and 24 are move-lane (`move-…` attempts), not reconciler. Load also differed: ~250 at 02:31Z against 102-144 at 04:13Z (load1 in events.jsonl). The band thesis rests on F1's controlled data, not on this comparison. |
| F7 | a second socket and higher kitty QoS are non-levers; a tty write cannot carry the relaunch | **CONFIRMED** | [M] `git show v0.48.2:kitty/options/definition.py`: `listen_on` is a single value, and "Changing this option by reloading the config is not supported". `child-monitor.c` v0.48.2 :521-551 has messages handled in parse_input, :2009 has `talk_loop`, and :2058 has `accept_peer → goto end`. XNU `bsd/kern/tty.c` (apple-oss-distributions/xnu main) refuses TIOCSTI with EACCES for a caller that is not root and not on its controlling tty. One nuance: kitty can also take remote-control DCS sequences written to a pane's tty (one `write()`, no client process). `~/.config/kitty/kitty.conf:136` sets `allow_remote_control socket-only`, which disables that path. Opening it would be a security change, and the commands would still run on kitty's main thread. |
| F8 | kitty-side classes are latent and their fixes are not applied | **CONFIRMED** | [M] `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` reports that the key does not exist. `strings` on the running `kitty.fast_data_types.so` (Jul 30) gives 0 'still serving' matches; the staged .so (Oct 16) gives 1. `lsof -p 853` shows 125 fds. `git grep beginActivity\|NSAppSleepDisabled v0.48.2` finds nothing, so kitty does not opt out of App Nap itself. The 256 soft limit is still unverified (it cannot be read without launchctl or root). |

### Levers

| # | lever | verdict | evidence / caveats |
|---|---|---|---|
| L1 | ProcessType Interactive for the LR control plane | **CONFIRMED (main change)**; the census-clamp sub-step is questionable | The mechanism is proven by the live control in F2: an Interactive LaunchAgent runs at PRI 31. The effect size is replicated in F1. **Caveat 1:** "clamp heavy census children back to utility" conflicts with sibling 04 L5 (`04-darwin-priority.md:310-313`). The move-batch census feeds the workers that are waiting on it (`lr-move-batch.sh:316-341`, `<sid>.waiting` → snap.tsv), so clamping it leaves a critical-path read under the 20-153× utility slowdown. Never clamp a census that carries kitty reads; that recreates F1. **Caveat 2:** the effect is unmeasured at 35-40/core. **Caveat 3:** it does not survive a kitty-side PRI 4 (screen lock or App Nap); see L6. |
| L2 | kitty-free pre-commit identity (pid+lstart via ps) | **WEAKENED** | The data exists [M]: `recon/sessions/3d1d988a….json` carries identity `{kitty_pid 853, window_id 30, tty ttys051, root_pid 61659, root_lstart}`, and `ps` shows 61659 as `/usr/bin/login` on ttys051. **Holes:** (a) kitty 853 has **111 zombie children** right now [M `ps -axo pid,ppid,stat` → 111 `Z`]. A zombie keeps its pid, lstart and ppid. The bash helper `_hf_lstart` (`handoff-fire.sh:3343-3345`) returns an lstart for a zombie [M: pid 436 `Z` → lstart]. The reconciler excludes zombies (`types.py:621-623`), but a bash port would not unless written to. (b) The root process is not always login: 3 of 32 windows have `/bin/zsh` as root. `close_on_child_death no` (`kitty.conf:1038`) lets a window outlive its root, which only fails closed. (c) Alone, this lever moves the hold to the next kitty read (focus or composer get-text). Its effect depends on L4 or L1. |
| L3 | watcher pane probe advisory when staged and SIGTERM | **WEAKENED** | The losses it targets are real (F5). **But the precondition does not exist when the probe runs.** `hf_succ_stage` runs at `handoff-fire.sh:20089` (its failure is tolerated by `|| true`). That is *after* `await_pane_proof` (:19967) and the watcher's own `pane_proof` (:11574). The signal exit is decided later still, in `recycle_fire_commit`. Implementing the lever needs a reorder (stage before the probe) plus a check after staging: if the stage failed, the typed path needs kitty and the probe must hold. The 600 s typed fallback is confirmed (`:11592`, `CC_RECYCLE_TYPE_DEADLINE_S` at `:12567`). With L1, the same probe passes 4/4 at PRI 31 [M], so L3 is mostly insurance. |
| L4 | composer/focus gates from HID idle and the frontmost app | **WEAKENED** | (a) "kitty not frontmost" rules out live typing only. It says nothing about a draft already in the box, so the composer half rests entirely on a cached good read. 7aae55e1's **first** attempt read `composer: unreadable` (`7aae55e1.1.R.log:27`), and no cached read is persisted today. The reconciler reads composers per pass (`lr_recon/__main__.py:669-695`) but does not store them with a time. Under the lever's own refuse-if-no-cache rule, the claimed 7aae55e1 save is not shown. (b) The code itself names non-HID composer writers: "a stray keystroke, a leaked terminal reply or this rail's own unsubmitted prompt" (`handoff-fire.sh:13926-13930`). HID idle cannot see these. (c) Whether a draft survives SIGTERM is still unverified. (d) The frontmost app changes over time: at 04:57Z `lsappinfo front` returned kitty. |
| L5 | fewer process hops per kitty call | **CONFIRMED** | [M] PRI 31: it2 0.438-0.679 s against kitten `ls --match` 0.047-0.084 s (6-10×). PRI 20: 9.9-24.5 s against 1.07-4.56 s. Sizes are 48,888 B against 660,430 B (`wc -c`). `kitten @ ls --match id:99999` exits rc 1 with "No matching windows", so absence is distinguishable from no answer (rc 124). The it2 path is bash shim → `cc-in-kitty` ancestry walk → `it2-kitty` → kitten (`~/.claude/bin/it2:111-122`). |
| L6 | NSAppSleepDisabled, the patched talk-thread build, fd watch | **CONFIRMED** (facts), with one link still a hypothesis | Preconditions verified (F8). That NSAppSleepDisabled lifts the PRI 4 clamp is unproven (`C3-socket-robustness.md:301-303`, open question 3). **Ranking caveat:** under the 24/7 premise, an overnight screen lock is a recurring scenario. On 10-01, kitty at PRI 4 failed 9/9 calls at 10 s (`recycle-unreachable-2026-10-01.md:11-13`), and in that state L1 cannot help. That makes this lever a prerequisite for L1 rather than hygiene. Restarting kitty ends all 32 windows, so it needs a planned boot-resume. |

**Net.** L1 and L5 are the measured, safe core. F6's natural experiment should be dropped. L2, L3 and L4 are
plausible, but each needs the design fixes named above (zombie exclusion, a stage-before-probe reorder,
a persisted composer cache) before it is safe.
