# G2: each capped session recovers itself from its own PRI-31 tree (implementation design)

**Verdict:** BUILD. An agent can implement and test every part. The code is inert until the operator
creates a switch file. The design ships shadow-first, and only activation needs the operator (§7).

**Conviction:** 60%. The mechanism is sound and reuses the proven remote recycle path unchanged. What
holds the number down: (a) G2's marginal value over a reconciler that now runs at PRI 31 has not been
measured, because no cap has happened since the band fix (§1, row 9); (b) the at-rest/SIGTERM
behaviour on a weekly-cap modal, and the band after the claude exits, are only settled by a live
event (§10).

**Code base:** worktree HEAD `28b25a119`. `main` is `6fdf87eca`, and
`git diff --stat 28b25a119..main -- scripts/limit-recover scripts/handoff-fire.sh hooks/stop-failure-marker.sh scripts/lib bin/claude-accounts bin/cc-lr`
prints nothing [M]. So every file:line below is valid on `main`.

**Labels:**
- **[M]** measured; the command or file is named.
- **[E]** estimated; the method is named.
- **[H]** hypothesis, not verified.

**What I did:** read-only. My only writes were `/tmp/g2_*.py` (read-only analysis scripts) and this
file. I ran one router read, `claude-accounts --rank general --recovery --max-wait 0 --max-age 900`,
which is cache-only and records nothing (`bin/claude-accounts:11427-11428`). I typed into no pane,
sent no signals, ran no launchctl, and ran no cc-lr mutation.

---

## 0. Summary

**The idea.** When a session hits the cap, its StopFailure hook (`hooks/stop-failure-marker.sh`)
starts a detached worker in the session's own PRI-31 tree. The worker moves that one session onto
another account in the same pane. It does this without:
- a reconciler pass;
- the capacity probe;
- the `--place` placer.

Every capped session with a kitty pane recovers in parallel. The reconciler and the poller stay
exactly as they are and act as the backstop.

**The move itself is today's.** The worker drives the existing **remote** in-place form, unchanged:
`lr-handoff.sh --launch --in-place --source-pane P`, which runs `handoff-fire.sh --recycle
--transplanted-source --source-pane P --source-session S`. That form already does everything after
the transplant: confirm, last read, stage the successor, SIGTERM exit, claim, and watch for
engagement (`handoff-fire.sh:19387-19458`, `:20131`).

What G2 adds:

| # | Piece | Where |
|---|---|---|
| 1 | **ARM 4** in the hook: about 12 file tests, one O_EXCL latch, and one `perl` fork+setsid. It suppresses ARM 2's poller kick only when it actually spawned an act-mode worker. | `hooks/stop-failure-marker.sh` |
| 2 | **The worker**, `python3 -m lr_recon.selfrec`. Python, so cc-reaper's `orphan-bash` class cannot reap it (`bin/cc-reaper:965`). | new `scripts/limit-recover/lr_recon/selfrec.py` |
| 3 | **A lock-free per-account intake ledger** (O_EXCL slot files, verified by weight), plus a slot in the **existing shared boot-slot store** that the reconciler and `cc-lr move` already use. | new `lr_recon/seats.py`; reuses `admit.BootSlots` |
| 4 | **`LR_PLACED_BY=self`**: one clause in `lrh_placed` and one in the launcher-tail choice. | `scripts/limit-recover/lr-handoff.sh:315-321`, `:1851` |
| 5 | **The reconciler yields to a live self claim.** It does not place, own or actuate that sid. | `lr_recon/store.py`, `plan.py`, `act.py`, `__main__.py` (about 45 lines) |

**How gap 2's four blockers are resolved:**

- **R1 (the remote form refuses a caller carrying the subject's id).** The worker builds its child
  environment from an allowlist, the same shape launchd gives the reconciler. So
  `CLAUDE_CODE_SESSION_ID` is never present. R1's second proof (the claude pid must not be an
  ancestor) still runs and still passes, because the worker is setsid'd. **No handoff-fire change.**
  The rejected alternative is in §3.4.
- **The self form never reaches the SIGTERM exit.** The self form is not used, so this does not arise.
- **Kitty identity.** The worker resolves the session's kernel identity, and repairs a missing or
  stale registry row from that identity. handoff-fire's own bind and pin then re-verify it through
  kitty, which takes 0.05-1.25 s at PRI 31 (axis 07).
- **The placer seam and admission.** These are handled by `LR_PLACED_BY=self` plus a worker-minted
  `turn` token.

**What it buys [E].** Method: the measured phase costs below.

| Phase | Cost | Basis |
|---|---|---|
| Hook to worker | ≤0.05 s | perl start 0.023 s [M] |
| Python start and identity | ≤1 s | |
| At-rest settle | 5-120 s | |
| Cache-only rank | 0.85 s | [M] |
| Shared boot slot | 0 s while free | |
| lr-handoff spawned | about 10 s after death, typical | |

Per session it then costs the measured remote-tail times, about 2-4 min (gap-2 §5). That compares
with 81-166 min death-to-engaged in the incident (gap-2 §5 [M]).

**Coverage.** This covers sessions that die on a 5h/7d cap in a kitty pane: 43 of the 51 capped sids
on record [M, §1]. Everything else, and every fallback, goes to today's path.

---

## 1. Evidence I re-measured for this design

| # | Fact | Evidence |
|---|---|---|
| 1 | Load while I measured: 206.63 on 10 cores, i.e. 20.7/core | `sysctl -n vm.loadavg hw.ncpu` → `{ 206.63 229.54 214.75 }`, `10` [M] |
| 2 | `/usr/bin/perl` exists (5.34). Starting it with POSIX costs 0.023 s wall from this PRI-31 tree. `/usr/bin/python3` is 3.9.6. | `time /usr/bin/perl -MPOSIX -e 'exit 0'` → 0.023 total; `/usr/bin/python3 -c 'import sys;print(sys.version)'` → 3.9.6 [M] |
| 3 | A cache-only, recovery-floored router read takes 0.848 s wall. It returns the eligible order `next, next2, next4, next3` and `route-meta: … quota_age_s=278 cached=1 … recovery=1 k_src=panes-native k_cap=40 … k_eff=13` | `claude-accounts --rank general --recovery --max-wait 0 --max-age 900` [M] |
| 4 | Importing `bin/claude-accounts` as a module costs 0.36 s. The design does **not** depend on this; it uses the CLI. | `python3 -I -c '…SourceFileLoader…'` → `import s 0.36` [M] |
| 5 | The registry binds 26 of 31 live interactive sessions by sid; 5 have no row (16%) | python read of `~/.claude*/sessions/*.json` (live pid, `kind == interactive`) joined to `~/.claude/cc-registry/*.json` `.session_id` → `31 … 26 … 5` [M] |
| 6 | 51 capped sids are on record. 43 had a numeric (kitty) pane; 8 had no pane. | `/tmp/g2_panes.py` over `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` [M] |
| 7 | A resumed claude runs on expect's **nested** pty, not on the pane's tty: claude.exe 15002 on `ttys019` ← bash ← expect ← `bash lr-fire-resume.sh` ← zsh ← zsh ← login ← kitty 853, with the pane tty `ttys055`. Its env carries `KITTY_WINDOW_ID=32`, `KITTY_LISTEN_ON=unix:/tmp/kitty-853` and `CLAUDE_CONFIG_DIR`. | `ps -o pid,ppid,ucomm,tty` walk; `ps -Eww -o command= -p 15002` [M] |
| 8 | **Both zero-human flags now exist.** `recon/autorecover.on` was created at 12:10 CDT (17:10Z) today, after gap 2 recorded it absent. So hook-origin records are no longer plan-only, and the reconciler **will** compete for these sessions. | `ls -la ~/.reso/limit-recover/autorecover.on ~/.reso/limit-recover/recon/autorecover.on` [M]; rule at `lr_recon/__main__.py:225-231` |
| 9 | No cohort has formed since the band fix. In the last 12 h the reconciler logged 2 spawns (C, 07:23Z) and no new limited cohort. | `/tmp/g2_ev.py` over `recon/events.jsonl` [M] |
| 10 | `$LIM/.kick-on` is absent, so the limited arm's own poller kick (`:289-292`) is off | `ls -la ~/.claude/autonomy/limited/` → only `.paged` [M] |
| 11 | cc-reaper TERMs any launchd-parented **bash** older than 600 s that is not on its whitelist. No rule targets python. | `bin/cc-reaper:737` (`GARBAGE_WL`), `:965` (orphan-bash); `grep -o 'printf "[a-z-]*\\t'` → only orphan-{bash,ps,tool,zsh,agent-chrome} and stuck-wrapper [M] |
| 12 | The compressor sentinel's last row reads `"pct":11.11`, under 60 s old | `tail -1 ~/.claude/logs/compressor-sentinel.jsonl` [M] |

Row 8 changes the brief's premise: the reconciler is no longer plan-only on hook records. §3.9 is
therefore load-bearing, not optional.

---

## 2. The flow

```
claude (PRI 31) ── StopFailure(rate_limit) ──► stop-failure-marker.sh
  limited arm (beat/page)                                        [unchanged, :242-293]
  ARM 4 _sf_self_recover  ── perl fork+setsid ──► python3 -m lr_recon.selfrec  (PPID 1, PRI 31 [H+])
  ARM 2 _sf_request       (request written as today; kick SKIPPED iff ARM 4 spawned an act worker)
  ARM 3 fact              [unchanged]
  exit 0, stdout empty

selfrec (one per death):
  S0 switches, band log ── S1 kernel identity ── S2 scope/stay ── S3 fence ── S4 claim (owner lr-self-recover)
  S5 at rest ── S6 rank (cache-only router) ── S7 intake seat + weight ── S8 shared boot slot
  S9 memory hard predicate ── S10 registry binding ── S11 token + phantom
  S12 lr-handoff (remote in-place, LR_PLACED_BY=self, LR_INPLACE_AWAIT=0) ─► handoff-fire remote form
  S13 follow the watcher to its outcome row ── S14 settle: release claim/seat/slot; on failure, fall back
```

**Fall back** means: release everything taken, write a per-sid cooldown, and kick the poller
(only if `autorecover.on` exists, the hook's own rule at `:548`). Today's request→poller and
census→reconciler paths then run exactly as now.

**Yield** means: another actor owns the session, so do nothing.

---

## 3. Component designs

### 3.1 Hook entry: ARM 4 in `hooks/stop-failure-marker.sh`

**Placement.**
- Define `_sf_self_recover` after `_sf_lr_dir` (`:404-417`). It needs `_sf_enrich_once` (`:376-386`)
  and `_sf_lr_dir`, and bash needs both defined before the call.
- Call it first inside the existing `case "$ERR" in rate_limit|rate_limit_error)` block (`:555-562`),
  before `_sf_request`.
- `_sf_enrich_once` is memoised, so ARM 2 pays nothing extra.

**Gates.** All are cheap and fail open. Any "no" is a `log_idl passed self-skip-<why>`, and the
other arms then run as today.

1. Mode:
   - `$_SF_RQ_STATE/self-recover.off` exists → off. This wins over everything.
   - else `self-recover.on` → `act`;
   - else `self-recover.shadow` → `shadow`;
   - else return.

   `act` additionally requires `$_SF_RQ_STATE/autorecover.on`, the global zero-human consent. This
   mirrors D1.9, where the reconciler needs both its own flag and the global one
   (`__main__.py:225-231`).
2. `[ ! -e "$LIM/.off" ]` (the whole-arm kill) and `CC_SF_SELF != off` (the weak env form, as at `:56`).
3. SID is path-safe (same `case` as `:453`).
4. `PANE` is numeric, i.e. a kitty window id. The fleet is kitty; iTerm UUIDs stay with today's path.
5. `CLAUDE_CODE_SESSION_KIND != bg`.
6. `TP` is a file, and `$(dirname "$TP")/$SID.HANDOFF.json` is absent (the same test as `:479`).
7. `[ ! -d "$_SF_RQ_STATE/runs/by-sid/$SID.active" ]`: any driver already holds the sid.
8. Cooldown: if `self-recover/cool/$SID` exists and `find … -mmin -5` matches, skip. This costs one
   fork, and only when the file exists.
9. The per-death latch `( set -C; : > self-recover/latch/$SID.$duuid )`. This is the same O_EXCL
   idiom as `:270` and `:534`. `$duuid` comes from `_sf_enrich_once`, with `:496-497`'s fallback.
   Death is keyed per death, not per sid: re-fires of one death share a latch, and a later death of
   the same sid gets a fresh attempt.

**Spawn sketch.** bash 3.2-safe; the braces carry the hook's redirect rule (`:513-515`).

```bash
_SF_SELF_SPAWNED=""
_sf_self_recover() {
  local st="$_SF_RQ_STATE" sr mode="" duuid lrd log perl="${STOP_FAILURE_SELF_PERL:-/usr/bin/perl}"
  sr="$st/self-recover"
  [ "${CC_SF_SELF:-on}" != off ] && [ ! -e "$LIM/.off" ] && [ ! -e "$st/self-recover.off" ] || return 0
  if [ -e "$st/self-recover.on" ] && [ -e "$st/autorecover.on" ]; then mode=act
  elif [ -e "$st/self-recover.shadow" ] || [ -e "$st/self-recover.on" ]; then mode=shadow   # .on without the global consent degrades to shadow, named
  else return 0; fi
  case "$SID" in ''|'?'|*[!A-Za-z0-9._-]*) log_idl passed self-skip-bad-sid; return 0 ;; esac
  case "$PANE" in ''|*[!0-9]*) log_idl passed self-skip-not-kitty; return 0 ;; esac
  [ "${CLAUDE_CODE_SESSION_KIND:-}" != bg ] || { log_idl passed self-skip-bg; return 0; }
  [ -n "$TP" ] && [ -f "$TP" ] || { log_idl passed self-skip-no-transcript; return 0; }
  [ ! -e "$(dirname "$TP")/$SID.HANDOFF.json" ] || { log_idl passed self-skip-handed-off; return 0; }
  [ ! -d "$st/runs/by-sid/$SID.active" ] || { log_idl passed self-skip-claimed; return 0; }
  if [ -e "$sr/cool/$SID" ] && [ -n "$(find "$sr/cool/$SID" -mmin -5 2>/dev/null)" ]; then
    log_idl passed self-skip-cooldown; return 0; fi
  _sf_enrich_once
  duuid="$(_sf_slug "${_SF_EN_UUID:-}")"; [ -n "$duuid" ] || duuid="p-$(_sf_slug "$(printf '%s' "$LAST" | cut -c1-64)")"
  mkdir -p "$sr/latch" "$sr/logs" 2>/dev/null || { log_idl abstained self-dir-unwritable; return 0; }
  ( set -C; : > "$sr/latch/$SID.$duuid" ) 2>/dev/null || { log_idl passed self-latched; return 0; }
  lrd="$(_sf_lr_dir)"
  [ -n "$lrd" ] && [ -f "$lrd/lr_recon/selfrec.py" ] && [ -x "$perl" ] \
    || { rm -f "$sr/latch/$SID.$duuid"; log_idl abstained self-no-runtime; return 0; }
  log="$sr/logs/$(printf '%.8s' "$SID").$(printf '%.12s' "$duuid").log"
  # fork; the PARENT exits 0 at once (the hook never waits); the child closes every inherited fd above
  # 2 (Claude Code must not see a pipe held open by a grandchild), setsids and execs the worker.
  if { LR_STATE_DIR="$st" PYTHONPATH="$lrd" "$perl" -MPOSIX -e \
         'defined(my $p = fork) or exit 1; exit 0 if $p; POSIX::setsid(); POSIX::close($_) for 3..255; exec @ARGV or exit 127' \
         "${STOP_FAILURE_SELF_PY:-/usr/bin/python3}" -m lr_recon.selfrec --mode "$mode" \
         --sid "$SID" --pane "$PANE" --hook-ppid "$PPID" --cfg "$CFG" --account "$ACCOUNT" \
         --tp "$TP" --cwd "$CWD" --err "$ERR" --reset "${_SF_EN_RESET:-}" --rlt "${_SF_EN_RLT:-}" \
         --death-uuid "${_SF_EN_UUID:-}" --kitty-to "${KITTY_LISTEN_ON:-}" \
         </dev/null >>"$log" 2>&1; } 2>/dev/null; then
    _SF_SELF_SPAWNED="$mode"; log_idl fired "self-spawned-$mode"
  else
    rm -f "$sr/latch/$SID.$duuid" 2>/dev/null; log_idl abstained self-spawn-failed
  fi
  return 0
}
```

**The kick change in `_sf_request` (`:548`).**

```bash
if [ -e "$_SF_RQ_STATE/autorecover.on" ] && [ "${_SF_SELF_SPAWNED:-}" != act ]; then
```

Why only in act mode:
- A shadow worker takes no claim, so the poller must keep its normal cadence.
- The request itself is **still written**. It is the fallback breadcrumb, and the poller's
  `REQUEST-IN-FLIGHT` arm keeps it while the worker holds the claim
  (`lr-reset-poller.sh:1816-1822`). The poller retires it once `rq_stale_reason` sees the session
  live on its target (`:1320-1342`).

**Death-path budget.**
- The `[ -e ]` tests cost nothing.
- One `find` runs, only when a cooldown file exists.
- One perl fork costs 0.023 s [M].
- No python fork on the death path, consistent with the header's rule (`:239-241`, `:325-330`).

**Fallback if `/usr/bin/perl` is ever removed.** `-x` fails, the latch is rolled back, and the IDL
row `self-no-runtime` makes the gap visible. A python `start_new_session` spawn would cost about
0.3 s [E, gap-2 §2], so it is deliberately not the default.

### 3.2 The worker: `scripts/limit-recover/lr_recon/selfrec.py` (new)

**CLI.**

```
python3 -m lr_recon.selfrec --mode act|shadow --sid S --pane P --hook-ppid N --cfg DIR \
        --account A --tp PATH --cwd PATH --err E --reset EPOCH --rlt five_hour|seven_day \
        --death-uuid U --kitty-to SOCK
python3 -m lr_recon.selfrec --status        # live workers and the last 20 outcomes
python3 -m lr_recon.selfrec --report [--since ISO]   # shadow rows joined to the reconciler's events
```

**Process hygiene.**
- First lines: `os.chdir(HOME)`, so the worker never holds a worktree cwd.
- `signal.SIGHUP → SIG_IGN`.
- `SIGTERM → _handover()` (below).
- Record id: `rid = "self:%s:%s" % (sid[:8], slug(death_uuid)[:12])`. It matches
  `_ASSIGN_ID_RE` (`bin/claude-accounts:4344-4352`).

**Event log.** Every step appends one row to `$LR_STATE_DIR/self-recover/events.jsonl` through
`store.append_bounded` (`store.py:588`; ≤1024 B per line, `EVENT_LINE_MAX` `:34`). The row is
`{t, ev, sid, rid, mode, detail, dt_death}`, where `dt_death = now − death record timestamp`. This is
the latency measurement B6 asks for.

**Constants.** All are env-overridable and default as below. None reads load (invariant G1).

| Name | Default | Meaning and justification |
|---|---|---|
| `SELF_REST_WAIT_S` | 120 | Bound on waiting for a *stable* at-rest limited transcript. Expiry means "unknown → fall back". It is never a verdict about the session. |
| `SELF_REST_SETTLE_S` | 5 | The gap between the two at-rest reads that must agree (same size, same last uuid) |
| `SELF_RANK_TIMEOUT_S` | 30 | Bound on the cache-only `--rank`. rc 124/137 = unknown: retry once after 10 s, then fall back. Measured at 0.85 s [M]. |
| `SELF_INTAKE_MAX` | 3 | Self movers in flight per target account. It mirrors the reconciler's per-account pacer of 3 (REPORT §4 A4 risk line). |
| `SELF_BOOT_WAIT_S` | 300 | Bounded wait for a slot in the shared boot store. Slots free as boots finish, not as load falls. |
| `SELF_ATTEMPTS` / `SELF_RETRY_WINDOW_S` | 4 / 600 | lr-handoff runs per worker, for NOTMOVED-TRANSIENT only. No new attempt starts after 600 s from the worker's start. |
| backoff | `classify.backoff_s(n)` = 10/30/60/120 | The reconciler's own TRANSIENT schedule (`classify.py:17-18`) |
| `SELF_WATCH_MAX_S` | 1500 | Bound on following the watcher. It is above the watcher's own maximum of 180+600+180+180+60 = 1200 (`handoff-fire.sh:20157-20160`), so the inner bound always fires first (lesson "inner bound starves the tail"). |
| `SELF_ENGAGE_GRACE_S` | 300 | After `recycle-unverified`, how long to look for a real turn on the target |
| `SELF_COOLDOWN_S` | 300 | Per-sid hook skip after a fallback |
| `SELF_PHANTOM_TTL_S` | 1200 | `= plan.PHANTOM_TTL_S` (`plan.py:35`) |
| `LR_SEGMENT_PCT` / `SELF_SENTINEL_MAX_AGE_S` | 90 / 60 | Memory hard predicate. A stale or absent sentinel row is unknown, so proceed: the move is net-zero. |

**Steps.** Pseudocode, Python 3.9 compatible. Each `fallback(...)` or `yield_(...)` returns through
`finally: settle()`.

```python
def run(a):
    paths = T.Paths.from_env(); sr = SelfTree(paths.lr_root); t0 = time.time()
    mode = switch_mode(sr, paths)                     # S0: .off > .on(+autorecover.on) > .shadow
    if mode == "off": return ev("switch-off")
    ev("start", band=band.base_priority(os.getpid()), ppid=os.getppid())   # band.py:74; logged, never gated
    if a.mode == "act" and mode != "act": a.mode = "shadow"                  # switch removed since spawn
    ident = identity(a)                               # S1, §3.3 — (pid, lstart, cfg, pane, tty_root, shell_root)
    if not ident.ok: return fallback("identity:" + ident.why)
    if ident.nested: return fallback("nested-claude")
    if ident.shell_root == "no": return fallback("launcher-rooted")         # R/REPLACE stays the reconciler's
    if a.rlt not in ("five_hour", "seven_day"): return fallback("scope:" + (a.rlt or "none"))
    if not allowlisted(sr, a.account): return fallback("account-not-in-allowlist")
    obs = transcript.observe_transcript(a.tp)         # transcript.py:510-529
    if obs.teammate: return ev("teammate")            # the lead owns it; ARM 2 already skips it
    reset = num(a.reset)
    if reset and reset - time.time() < plan.EPS_STAY_S: return fallback("stay")  # plan.py:36; poller REQUEST-STAY owns it
    defer, why = fence.defers(paths, a.sid, "", time.time(), fence.read_waketime(), fence.proc_alive)  # S3, fence.py:183-218
    if defer or why == "lapsed": return yield_("fence:" + why)    # the reconciler owns it: today's path
    if a.mode == "shadow": return shadow(a, ident, obs)            # §7: reads only, no claim, no seat
    v = store.claim_take(paths, a.sid, T.RunClaimHolder(os.getpid(), store.proc_lstart(os.getpid()),
                         "lr-self-recover", rid), fence.proc_alive, argv_of)   # S4, store.py:371-416
    if v in ("held", "lost-race"): return yield_("claim:" + v)
    held.claim = True
    try:
        if not wait_at_rest(a.tp): return fallback("not-at-rest")          # S5
        lane = "fable" if "fable" in last_model(a.tp) else "general"
        order = rank(lane, exclude=a.account)                              # S6 (§3.5)
        if order is None: return fallback("rank-unknown")
        if not order: return fallback("no-eligible-target")
        w = plan.clamp_weight(1 + plan.subagents_written(a.tp, a.sid, death_ts(obs)), plan.kmax())   # plan.py:102,189
        seat = seats.take_first(order, w, holder)                          # S7 (§3.5)
        if seat is None: return fallback("no-seat")
        if not boot_slot(): return fallback("no-boot-slot")                # S8, admit.BootSlots shared store
        if memory_critical(): return fallback("memory")                    # S9
        if not ensure_registry(a, ident): return fallback("registry-conflict")   # S10 (§3.8)
        phantom_async(seat.acct, a.sid, rid, w)                            # S11, claude-accounts --assign, not awaited
        for n in range(1, SELF_ATTEMPTS + 1):                              # S12
            if switch_mode(sr, paths) != "act": return fallback("switch-removed")
            if n > 1 and not wait_at_rest(a.tp): return fallback("not-at-rest")
            tok = mint_token(a.sid)                                         # admit.mint_token's bash, kind=turn
            rc, err = run_handoff(argv(a, seat), env(a, seat, tok))        # NO outer timeout (§3.7)
            cls = classify_handoff(rc, err)
            if cls == "armed": return follow_watcher(a, seat)              # S13
            if cls == "transient" and time.time() - t0 < SELF_RETRY_WINDOW_S and n < SELF_ATTEMPTS:
                time.sleep(classify.backoff_s(n)); continue
            if cls == "recovered": return ev("not-limited")                 # REFUSED:not-limited: nothing owed
            if cls == "stranded": return rescue_handoff()                   # no blind retry (§3.7)
            return fallback(cls)
        return fallback("attempts-exhausted")
    finally:
        settle()                                                           # S14
```

**`settle()`** releases these only if they are still held by this pid:
- the boot slot (`BootSlots.release`, `admit.py:441-454`);
- the intake seat;
- the claim (`store.claim_release(paths, sid, rid)`, `store.py:419-424`).

On a fallback, `settle()` also:
- voids the phantom (`claude-accounts --unassign <rid>`);
- writes `cool/<sid>` (with mtime now);
- kicks the poller if `autorecover.on` exists. This is the bare `launchctl kickstart`, the same verb
  and rule as the hook at `:548-551`; never `-k`.

**`_handover()` on SIGTERM.** This applies only while an lr-handoff child is alive. It re-stamps the
claim, the seat and the boot slot to the child's `(pid, lstart)`:
- `store.claim_restamp` (`store.py:427-440`);
- the seat file's holder;
- the slot's `pid`/`lstart` files.

It then exits **without** killing the child. This is A6's "re-stamp to the live actuator" rule
applied to this lane. handoff-fire's R2 check then still sees an ancestor holder
(`handoff-fire.sh:2660-2680`, `:16302-16305`).

On SIGKILL there is no handover: the holder reads dead and any lane may steal it. That is the same
exposure as today's detached `lr-fleet --one` drivers. The per-pane recycle lock and the transplant
lock still stop a second typer.

### 3.3 Kernel identity (S1)

The hook's `$PPID` is only a **hint**. Gap-2 measured hooks running directly under claude, but
`hooks/session-register.sh:44-58` documents a `/bin/sh` shim parent on some versions. So the
authority is Claude Code's own per-pid row, the same rows `hf_exit_signal_pin` trusts
(`handoff-fire.sh:4024-4059`).

`identity(a)`:
1. Glob `~/.claude*/sessions/*.json` (seam `CC_SESSIONS_DIRS`). Keep rows with
   `sessionId == sid`, `kind == "interactive"` (rules out `-p`/sdk), and a live `pid`.
   - Exactly one must remain; otherwise return `ambiguous` or `none`.
   - If the hint pid is among them, prefer it.
2. `ucomm` of the pid is `claude.exe`, `claude` or `node`. Read `ucomm`, never `comm`: comm is argv0,
   and row 7 shows a node_modules path there (lesson "ps comm is argv0").
3. `lstart = store.proc_lstart(pid)`, which is `TZ=UTC LC_ALL=C` and normalised (`store.py:530`).
   This is the pin.
4. **Tenancy.** Walk ppid at most 16 hops. Any ancestor whose `ucomm` is claude-ish means
   `nested = True`. A nested `claude -p` inherits the parent's `KITTY_WINDOW_ID`, so its death must
   never move the pane's real tenant. This is the same rule as session-register's
   `pid_is_strict_ancestor` (`hooks/session-register.sh:66-84ff`, function at `:84`).
5. **Pane root.** Continue the walk to the first ancestor whose parent is `kitty` or `login`.
   - `tty_root` = that ancestor's tty. In row 7 it is `ttys055`, while claude itself sits on
     `ttys019`.
   - `shell_root` uses the classification of `pane_shell_root` (`handoff-fire.sh:7498-7531`): a
     `login` root is judged by its child's comm; any other root is judged by its own comm;
     shell-set means `yes`.
   - Anything unreadable is `unknown` and **proceeds**. The precheck's `shell_root:` line plus
     `--no-replace` are the backstop.
6. Pane binding. `P` is the hook's own `KITTY_WINDOW_ID`, inherited from this very claude. Step 4
   excludes a nested inheritor. handoff-fire's `hf_remote_pane_term` + `hf_remote_source_pin` then
   **independently** re-prove "P's kitty-enumerated tty is in the pinned pid's ancestry"
   (`:2827-2936`, `:2960-2995`), so the worker's binding is never the last word.
7. Defensive R1 assertion. `os.getppid() == 1`, and the pinned pid is not in the worker's own
   ancestry. A failed perl detach therefore refuses here rather than at handoff-fire's R1.

### 3.4 The self-detached origin and R1

R1 refuses a remote recycle when either the caller's `CLAUDE_CODE_SESSION_ID` equals the named
session, or the registry row's pid is an ancestor of the caller (`handoff-fire.sh:2635-2640`; called
at `:16270-16272`, `:16285-16287`, `:16296-16298`). Its premise (`:2623-2633`) is: "its own turn is in
flight, so the at-rest proof can never pass".

**Chosen: an allowlisted environment.** `selfrec.env()` builds the child environment from scratch:

```python
BASE = ("HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TZ")
env = {k: os.environ[k] for k in BASE if k in os.environ}
env["PATH"] = PLIST_PATH   # com.reso.lr-reconciler.plist ProgramArguments: "$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
env.update({
  "LR_PLACED_BY": "self", "LR_ASSIGN_ID": rid,             # lr-handoff records `placed assign` (:1619-1621)
  "LR_INPLACE_AWAIT": "0",                                  # §3.7: the worker follows the watcher itself
  "LR_WAKE_GUARD_S": "30", "CC_RECYCLE_BGWORK_ANSWER": "cancel",
  "CLAUDE_CODE_DISABLE_AGENT_VIEW": "1",
  "HF_WATCHER_RECORD": sr.work(sid + ".watcher.json"),    # handoff-fire writes it at :19993-20006
  "HF_RECYCLE_ORIGIN": "self-detached",                    # audit tag only; nothing branches on it
  "LR_STATE_DIR": paths.lr_root, "LR_RECON_ROOT": paths.root,
  "CC_TERM_KITTY_TO": a.kitty_to,                          # = the reconciler's pane_sock (act.py:85-86)
})
if tok: env["LR_ADMIT_TOKEN_PATH"] = tok
```

This is `act.actuator_env` (`act.py:50-93`) minus the record-specific keys, on a launchd-shaped base.
`CLAUDE_CODE_SESSION_ID`, `KITTY_WINDOW_ID`, `ITERM_SESSION_ID`, `CC_PANE_ID` and
`CLAUDE_CONFIG_DIR` are absent **by construction**, so:
- lr-handoff takes the DRIVER branches: `:406`, `:457` and `:983` are not reached, and `--sid`,
  `--config-dir` and `--source-pane` are explicit;
- lr-lib's self-correction is off (`lr-lib.sh:509`);
- lr-transplant's `live-self` arm (`lr-transplant.sh:1131`) is not used. It is moot anyway: in-place
  runs `--phase admit` (`lr-handoff.sh:1682`).

R1's process-truth proof still runs. The pinned claude is not an ancestor of the setsid'd worker
(§3.3 step 7), so it passes. R1's comment already names "a caller with a stripped env" as the case
its ancestry proof exists for (`:2632`).

**Rejected: an `HF_RECYCLE_ORIGIN=self-detached` bypass inside `hf_remote_is_self`** (gap 2 §7
step 6).
- It adds a new flag that **any** caller could set to skip R1's env proof.
- It needs a handoff-fire edit plus its own red proof, to buy exactly what the allowlist buys with
  zero edits.
- The allowlist cannot weaken R1: the remaining proof is the one that encodes R1's actual premise.

The tag is kept in the environment for audit only.

**Mutant test (power proof, §6 T-W6).** Build the env with `CLAUDE_CODE_SESSION_ID=<sid>` leaked
and run `handoff-fire --recycle --dry-run` in the remote form. It must exit 2 with R1's text
(`:2647`). This proves the scrub, not luck, is what passes R1.

### 3.5 Target choice and the seat ledger (S6-S8)

**S6. Eligibility and order come from the router, cache-only.**

```
claude-accounts --rank <lane> --recovery --max-wait 0 --max-age 900
```

- `--recovery` applies the survival floors in `_excluded(…, recovery=True)`
  (`bin/claude-accounts:5997-6074`): weekly headroom ≥ `RECOVERY_W_FLOOR` 0.10, projected 5h <
  `RECOVERY_S_CEIL` 0.60, the fable floor, wire rejection, auth, and `k_eff ≥ k_cap` →
  `kmax-concurrency` with phantoms applied (`:11288`).
- `--max-wait 0` forbids a sweep and never takes the lock (`get_data`, `:8237-8262`).
- It writes nothing (`--rank` "is diagnostic and deliberately silent", `:11426-11428`).

Exit codes:
- 0: stdout `acct score` lines. Drop the source account.
- 2: policy, nothing eligible → `no-eligible-target` fallback.
- 3: cache older than 900 s → `rank-unknown` fallback.
- 124/137 from our own 30 s bound → retry once, then `rank-unknown`. Our timeout is unknown, never
  a verdict.

Why the router and not gap 2's local `capped.latest_usage` reading: the router read is measured at
0.85 s [M, §1 row 3]. It applies the **exact** floors and phantoms that `--place` uses, and a second
eligibility spelling would drift (lesson "sibling auditors must share the state model"). The local
reading's only advantage, independence from the sweep, is illusory: `account-utilization.jsonl` is
written by the same sweeps.

**S7. Intake seats.** New `lr_recon/seats.py`, about 150 LOC. Lock-free on the take path.

- **Layout:** `self-recover/seats/<acct>/slot.<i>` for `i < SELF_INTAKE_MAX` (3).
- **Content:** one compact JSON line, `{sid, rid, pid, lstart, w, at}`.

```python
def take_first(order, w, holder):
    for acct in order:                                  # router order; spill to the next on full
        cap = capacity(acct)                            # cap_a − charge_a from the newest usage row ≤900 s:
                                                        #   k_work → KMAX, else k_native/k → KMAX_RESIDENT
                                                        #   (k_src/k_cap rule, claude-accounts:4160-4199); unmeasured → skip
        s = take(acct, w, cap, holder)
        if s: return s
    return None

def take(acct, w, cap, holder):
    d = seats_dir(acct)
    for i in range(SELF_INTAKE_MAX):
        p = os.path.join(d, "slot.%d" % i)
        if not (create_excl(p, holder) or (reclaim_stale(p) and create_excl(p, holder))):
            continue
        live_w = sum(h.w for h in live_slots(d))       # includes mine; read AFTER my create
        if live_w <= cap:
            return Seat(acct, p)
        unlink_if_mine(p, holder)                       # verify failed: release, try the next account
        return None
    return None

def create_excl(p, holder):   # os.open(p, O_CREAT|O_EXCL|O_WRONLY, 0o600) + one write; FileExistsError → False
def reclaim_stale(p):         # under fcntl.flock(<d>/.reclaim, LOCK_EX|LOCK_NB, retried ≤1 s):
                              #   holder unreadable and age > 10 s, OR not fence.proc_alive(pid, lstart)
                              #   → os.unlink(p) → True. The kernel drops the flock if the reclaimer dies.
```

**Correctness argument.**

1. **No over-admission.** At most `SELF_INTAKE_MAX` movers can hold a seat on one account: O_EXCL
   on a bounded index space.
2. **The weight check.** It is **take-then-verify**, so two concurrent movers that both fit alone
   but not together each see the other's file. Both release, and both spill. The ledger therefore
   never over-admits on weight; under contention it can only under-admit, which is the safe
   direction.
3. **Reclaim.** Only the rare reclaim path is serialised, by a kernel `flock` that cannot go stale.
   The claim path stays lock-free.

Seats are released at the outcome (§3.2 `settle`). The phantom row (S11, TTL 1200 s) covers the
window before the next sweep counts the session on its target.

**Herding** is bounded three ways:
- the router excludes an account once `k_eff ≥ k_cap`, phantoms included;
- `SELF_INTAKE_MAX` = 3 per target forces spill to the next ranked account;
- S8 caps the whole box.

**S8. Boot slots.**

```python
admit.BootSlots(store=os.path.join(paths.lr_root, "locks", "swap-slots")).acquire(sid)   # admit.py:336-439
```

This is the **same** store as the reconciler (`__main__.py:100-105`) and `cc-lr move`
(`lr-move-lib.sh:238-263`). Width 6 (`START`) bounds concurrent relaunches across all three lanes. If
no slot is free, the worker polls every 5 s up to `SELF_BOOT_WAIT_S`, then falls back. This is a
concurrency bound, released as boots finish; it is not a load gate.

**Weight.** `plan.clamp_weight(1 + plan.subagents_written(tp, sid, death_ts), plan.kmax())`. This is
the reconciler's wave-3 rule, unchanged: bounded at the death and clamped to KMAX−1 (`plan.py:166-202`;
gap 3 corrected A8, so leads do restart fan-out). The same `w` is charged on the phantom.

### 3.6 Admission token and `LR_PLACED_BY=self` (lr-handoff)

**Token.** `CC_ADMIT_TOKEN_KIND=turn cc_capacity_token_mint <sid>`, run through
`bash -c 'source <capacity-admit.sh>; …'`. This is the exact call in `admit.Admission.mint_token`
(`admit.py:243-262`; mint at `scripts/lib/capacity-admit.sh:810-849`).

- It is a file write, not a probe. A limited session owes a prompt, so the kind is `turn`.
- It is minted **per attempt, immediately before** lr-handoff starts. The relaunch therefore redeems
  well inside the TTL (the `1,020 s` cited at `lr-handoff.sh:322-327`).
- A failed mint is not a refusal: the launcher evaluates the gate in the pane, as at `:1607-1610`.
- lr-handoff reads it via `LR_ADMIT_TOKEN_PATH` (`:1571-1589`, "no probe, no mint").

**lr-handoff edits.** About 8 lines.

```diff
@@ lr-handoff.sh:315-321 lrh_placed
   case "${LR_PLACED_BY:-}" in
     reconciler) return 0 ;;
     cc-lr-move) [[ "${LR_PLACED_BY_MOVE:-on}" != off ]] ;;
+    self)       [[ "${LR_PLACED_BY_SELF:-on}" != off ]] ;;   # G2: lr_recon.selfrec ranked the target
     *) return 1 ;;
   esac
@@ lr-handoff.sh:1851 the launcher tail
-elif [[ "${LR_PLACED_BY:-}" == reconciler ]]; then
+elif [[ "${LR_PLACED_BY:-}" == reconciler || "${LR_PLACED_BY:-}" == self ]]; then
```

What `self` then inherits:
- the router re-check is skipped (`:1429-1434`), because S6 already read the same router;
- `CC_RECYCLE_BGWORK_ANSWER=cancel` is forced (`:1991-1993`);
- no pane mail; the mail is voluntary-only anyway (`:789-797`);
- the placed-move continue prompt: "Moved from X to Y after a usage limit; same session, full
  transcript. Continue the task you were on." (`:1852-1880`).

The submit token stays lr-handoff's own run token. `:1800` is reconciler-only, and the watcher
verifies engagement on it.

Also add a header line at `:28-37` documenting `LR_PLACED_BY=self` and its kill switch
`LR_PLACED_BY_SELF=off`.

### 3.7 Running lr-handoff, following the watcher, and classifying outcomes (S12-S13)

**argv.** `act.cmd_move` (`act.py:103-132`), with these changes:
- no `--record-id`/`--attempt`. The self lane is not a reconciler record. This also keeps fence rule
  3, "own-actuator", from ever matching (`lr-recon-fence.sh:7-20`).
- add `--no-replace`. A launcher-rooted pane holds at the precheck (`:1496-1507`) and falls back to
  the reconciler's R.

```
/bin/bash <LR>/lr-handoff.sh --sid S --config-dir CFG --cwd CWD --target T --launch --in-place \
          --source-pane P --no-replace
```

**No outer timeout on lr-handoff.** Its own bounds are its contract (lesson "never wrap in your own
timeout"). `subprocess.Popen` writes stdout and stderr to the worker log plus an in-memory tail, and
the worker waits on it.

**Why `LR_INPLACE_AWAIT=0`.** With `--await`, handoff-fire returns rc 3 ("no verdict inside the
window") over a watcher that may still be working. lr-handoff then reports **STRANDED** (exit 4,
`:2094-2147`), "converting a slow success into a reported failure" (`:2002-2007`). The reconciler sets
0 for the same reason (`act.py:65`). With 0, rc 0 means "the /exit landed and the watcher took over"
(`:2054-2062`).

**S13. Follow the watcher.**
1. Read `HF_WATCHER_RECORD` (`{pid, lstart, pane, sid}`).
2. Poll `fence.proc_alive(pid, lstart)` every 2 s, up to `SELF_WATCH_MAX_S`.
3. Find the watcher's terminal row in the tail of `~/.claude/logs/handoffs.jsonl`, joined on
   `watcher_pid` + `watcher_lstart`. Every row carries both [M, `tail -c 300000 … | grep recycle-`].

Outcomes:
- `recycle-engaged` with `engaged:true` → **success**.
- `recycle-unverified` → look for a non-error assistant turn on the target after the relaunch for
  `SELF_ENGAGE_GRACE_S` (`transcript.ok_turns_since`, `:544`).
  - If one appears → success.
  - Else file the poller's existing C14 prompt repair, `requests/<sid>.self-prompt.json`:
    `{sid, mode:"prompt", source_pane:P, requested_by:"lr-self-recover", prompt:<the placed continue text>}`,
    consumed at `lr-reset-poller.sh:1855-1880` through `cc_tui_submit`. Then kick.
- `recycle-dead`, or no row → **rescue**: release, kick the poller. Its husk lane
  (`rq_stale_reason` rc 2, `:1339`) and the reconciler's evidence rows (row 9 A-husk, row 10 B) own
  a tombstoned source.
- The watcher outlives `SELF_WATCH_MAX_S` → release the claim **without** touching the watcher. This
  relinquishes ownership; it is not a verdict.

**`classify_handoff(rc, stderr)`.** This reuses the reconciler's own parsers, so both lanes read one
stderr the same way:
- `settle._REASON` (`settle.py:61`);
- `settle._STRANDED` (`:88`);
- `classify.map_notmoved` (`classify.py:129-166`; backoff `:169`).

| lr-handoff exit | Evidence | Class | Worker action |
|---|---|---|---|
| 0 | `verdict=SWITCHED-UNPROVEN` | armed | S13 |
| 6 | reason maps to `TRANSIENT`: unreachable, wedged, `pane:resolver-unavailable`, `composer-unreadable`, `wake-guard`, unreadable | transient | backoff and retry within the window |
| 6 | `HELD:busy` / `unknown` (HOLD-COMPOSER) | not at rest | re-run S5, then retry once |
| 6 | `focused`, `draft`, `bg-work`, `subagents`, `team`, `no-shell`, `HELD:load` | hold or structural | fall back; the reconciler holds, pages, or Rs. `HELD:load` is never retried (A3 iii) |
| 6 | `REFUSED:not-limited` | nothing owed | release, done |
| 6 | `REFUSED:teammate`, `registry`, `pane:*`, `no-transcript` | not ours / changed | fall back |
| 4 | `verdict=STRANDED` or `FAILED` | rescue | no blind retry (`:2134-2145`); kick the poller |
| 2, 5, other | usage, live layer | config | fall back |

### 3.8 Registry binding (S10)

lr-handoff refuses a `--source-pane` without a registry row naming the sid (`lr-handoff.sh:505-523`),
and handoff-fire's bind refuses the same (`handoff-fire.sh:2690-2736`). 5 of 31 live sessions have no
row [M, §1 row 5]. `ensure_registry` writes `~/.claude/cc-registry/<P>.json` (seam `CC_REGISTRY_DIR`)
atomically (`store.atomic_write_json`), **only** as follows:

| Existing row | Action |
|---|---|
| absent | write `{paneUUID:P, name:<cwd-base>-<sid8>, cwd, account:<cfg basename sans dot>, pid, startedAt, session_id:sid, surface:"pane", lstart, kitty_listen_on, kitty_pid, registered_by:"lr-self-recover"}`. This is the shape of a live row [M, `jq -c . ~/.claude/cc-registry/10.json`]. |
| same sid, same pid | nothing |
| same sid, dead pid | refresh `pid`, `lstart` |
| other sid, dead pid | overwrite (stale tenant) |
| other sid, **live** pid | **refuse → `registry-conflict` fallback**. Never overwrite a live tenant. |

The row is checked, not trusted: handoff-fire's pin re-proves pid↔tty through kitty
(`:2960-2995`). Kill switch: `SELF_REGISTRY_WRITE=off`. Registry-less sessions then fall back.

### 3.9 Reconciler interplay and fencing: who owns a record

**Single rule.** The per-sid run claim `runs/by-sid/<sid>.active` is the one ownership token across
lanes:
- the reconciler takes it in `hold_claim` and `take_ownership` (`act.py:493-523`,
  `store.py:552-580`);
- the poller (`lr-reset-poller.sh:1816`);
- cc-lr and lr-fleet (`lr-lib.sh:839-882`);
- now `lr-self-recover`.

| Moment | Owner | Others |
|---|---|---|
| death → claim (≈1 s) | nobody | the hook's request exists; the reconciler has not yet passed or placed |
| the reconciler already owns `owned/<sid>` (fresh heartbeat, live procs, or lapsed) | reconciler | the worker **yields** at S3 (fence rules `fence.py:183-218`) |
| worker claim → settle | **lr-self-recover** | reconciler: `take_ownership` → `held` (no owned file, `store.py:568-569`); `hold_claim` → `held` (`__main__.py:1248-1268`); poller: `REQUEST-IN-FLIGHT`, kept (`:1816-1822`); handoff-fire's fence also defers to an owner (`:3363-3371`), and there is none |
| after success | nobody | the census sees the session live on its target → `stale … NOT_NEEDED`, and the request is claimed (`__main__.py:271-283`) or retired by the poller |
| after fallback | nobody | the reconciler and poller proceed exactly as today; the cooldown stops re-spawn for 5 min |

**The gap this closes.** Since 17:10Z (§1 row 8), records are not plan-only. Without a change, the
reconciler would still:
- run `--place` for a self-driven sid and charge a 20-min phantom on a different account
  (`plan.phantom_rows`);
- be free to fire the **non-claimed** actuators against an in-flight self move. `CLAIMED_ACTUATORS`
  (`act.py:482-489`) excludes UNCONFIRM, FOLD, ABORT, SPLIT and HEAL; row 9's UNCONFIRM
  (`phase.py:130-139`) is one of them.

**Reconciler edits.** About 45 lines.

```diff
@@ store.py:357-369 _claim_stamp — the holder names its real lane (python writer only)
-        "by": BY,
+        "by": h.owner or BY,          # reconciler holders carry owner="lr-reconciler" → byte-identical
+SELF_OWNER = "lr-self-recover"
+def self_claim_live(paths, sid, alive) -> bool:
+    h = read_claim(paths, sid)
+    return bool(h and h.owner == SELF_OWNER and h.lstart and alive(h.pid, h.lstart))
@@ plan.py:214 movers(records, snap, now, facts=None, exclude=frozenset())
+        if rec.sid in exclude: continue          # a live self move owns it: no --place, no phantom
@@ act.py:438 may_actuate(…, self_driven=frozenset())
+    if rec.sid in self_driven: return False, "self-recover"   # EVERY actuator, claimed or not
@@ __main__.py run_pass, after _census (:1699) and before _plan (:1715)
+    ctx.self_driven = {s for s, r in ctx.records.items() if r.open and store.self_claim_live(paths, s, _alive)}
+    for s in ctx.self_driven: _event_once(paths, "self-recovering", s, …)    # one row per record, not per pass
@@ __main__.py:1001  plan.movers(…, exclude=ctx.self_driven)
@@ __main__.py:1243  act.may_actuate(…, self_driven=ctx.self_driven)
```

Cost:
- one claim-dir read per open record;
- one `ps` (via `_alive`, `__main__.py:129-130`) only for a dir whose owner is `lr-self-recover`.

The startup re-stamp (`__main__.py:1792-1794`) only touches claims whose `record_id` equals the
record's, so it never touches a self claim (A6 agrees: A6 doc §9).

B3 should treat `self-recover` like `claim-held` (HARD; it pages at `W_hard` if stalled). B3's doc
already names this (B3 doc §9).

### 3.10 Other lanes

- **Poller.** Unchanged. A held claim gives `REQUEST-IN-FLIGHT`; `rq_stale_reason` retires the
  request after the move; the husk lane takes over after a rescue. A late wake past the reset is
  harmless, because the worker's stay rule (S2) hands near-reset sessions to the poller's
  `REQUEST-STAY` (`lr-reset-poller.sh:1750-1761`).
- **cc-lr recover/move, lr-fleet.** These take the claim. While a worker holds it they print
  `held-live` (`lr-lib.sh:846-847`). The operator can see the holder with `selfrec --status` and stop
  it with `kill <pid>`; SIGTERM hands over (§3.2), then the claim frees when lr-handoff exits.
- **Move lane, `lr-move-worker`.** Claim plus the shared boot-slot store; the two cannot
  double-drive.

---

## 4. Data and format changes

| Store | Change |
|---|---|
| `~/.reso/limit-recover/self-recover.on` | **new operator switch.** Empty = every account; otherwise one account name per line (an allowlist, e.g. `next3`). Act mode also needs `autorecover.on`. |
| `…/self-recover.shadow` | new: shadow mode (§7) |
| `…/self-recover.off` | new: hard off, wins over everything |
| `…/self-recover/{latch,cool,logs,seats/<acct>,work}/`, `events.jsonl`, `shadow.jsonl` | new lane tree. `events.jsonl` and `shadow.jsonl` are bounded by `store.append_bounded` with one generation of rotation. |
| `runs/by-sid/<sid>.active/holder` | a self holder writes `"by":"lr-self-recover","owner":"lr-self-recover","record_id":"self:<sid8>:<duuid12>"`. Reconciler holders are byte-identical. |
| `~/.claude/logs/account-assignments.jsonl` | rows `{t,ts,acct,src:"lr-self-recover",id:<rid>,sid,w,ttl_s:1200}` via `claude-accounts --assign … --src lr-self-recover --id <rid> --sid <sid> --w <w> --ttl-s 1200` (CLI at `:11196-11226`); `--unassign <rid>` on fallback |
| `~/.claude/cc-registry/<pane>.json` | written only per §3.8, with an extra `registered_by` field |
| `requests/<sid>.self-prompt.json` | only after `recycle-unverified` with no turn (§3.7); the existing C14 schema (`lr-reset-poller.sh:1246-1257`) |
| IDL (`stop-failure-marker`) | new dispositions `self-spawned-{act,shadow}`, `self-skip-*`, `self-latched`, `self-no-runtime`, `self-spawn-failed`, `self-dir-unwritable` |

---

## 5. Failure modes under permanent 15-40/core load

No row waits for load to fall. Every bound below is ours, and each expiry means "unknown → hand to
today's path, which retries". None is a negative verdict.

| # | Failure | Handling |
|---|---|---|
| 1 | perl absent, the latch dir unwritable, or the spawn fails | No worker. The latch is rolled back, the IDL row names it, and ARM 2's kick is **not** suppressed (`_SF_SELF_SPAWNED` stays empty). |
| 2 | Python start or import is slower at 40/core | Nothing waits on it; no deadline at spawn. At most it narrows the race with the poller and reconciler; a lost race is `yield`. |
| 3 | The worker runs at PRI < 31 (detach lost the band) | `start` logs `band`. Still no gate. Shadow reports show it before act. |
| 4 | The worker is SIGKILLed (jetsam, operator) | The claim holder reads dead and can be stolen (`lr-lib.sh:810-818`). Seats read stale and are reclaimed. The boot slot reads stale (`admit.py:364-388`). The phantom TTLs out at 1200 s. An orphaned lr-handoff continues inside its own bounds, guarded by the transplant and recycle locks. Same exposure as today's detached drivers. |
| 5 | The worker is SIGTERMed mid-move | `_handover` re-stamps the claim, seat and slot to the live lr-handoff, then exits without killing it. |
| 6 | Race with the poller or reconciler for the claim | mkdir is atomic. The loser yields, or for the poller keeps its request. Exactly one driver. |
| 7 | The reconciler owns the record before the worker starts | S3 yields. Today's path runs. |
| 8 | The session re-fires (mailbox wakes) and is never stably at rest | S5 expires at 120 s → fallback. The reconciler's 60 s quiet-window rule (`transcript.py:28`, `:442-462`) and the handoff-fire last read take over. |
| 9 | The router cache is older than 900 s (keepwarm lagging) | `--rank` exit 3 → `rank-unknown` fallback; the reconciler's placer sweeps. |
| 10 | Our 30 s bound on `--rank` fires | rc 124 → retry once after 10 s → `rank-unknown`. Not a verdict. |
| 11 | Every eligible account is full (intake or weight) | `no-seat` → fallback (the reconciler's WAIT_SLOT). |
| 12 | Herding: 9-30 deaths at once | Router exclusion, intake 3 per target, and the shared boot width 6. The excess spills, waits ≤300 s for a boot slot, or falls back. |
| 13 | Kitty slow or deaf (including PRI 4 behind a locked screen, B8) | Precheck `HELD:unreachable`/`resolver-unavailable` → TRANSIENT backoff 10/30/60 within 600 s → fallback. All lanes fail alike here; G2 is never worse. |
| 14 | Composer unreadable or a draft | TRANSIENT, or HOLD → fallback; the reconciler pages per gap 3. |
| 15 | Lead with live members, launcher-rooted pane, background work | `HELD:team`, `HELD:no-shell` (with `--no-replace`), `HELD:bg-work` → fallback. |
| 16 | The successor stage fails, so the relaunch is typed | handoff-fire's `/exit`-time load hold can say `HELD:load` under the premise; it is never retried (A3 iii) → fallback. Detection: the count of `HELD:load` in `events.jsonl`. |
| 17 | Held after confirm (unconfirm rc 0) | NOTMOVED, so a retry is safe (`lr-handoff.sh:2082-2093`). |
| 18 | STRANDED (the transplant is done, no successor) | No blind retry; kick the poller; the husk lane and reconciler rows own it. |
| 19 | Memory critical (sentinel `pct ≥ 90`) | Fallback (a §5 hard predicate). A stale or absent sentinel is unknown → proceed (net-zero move). |
| 20 | The registry has a live foreign tenant on P | `registry-conflict` → fallback; never overwritten. |
| 21 | The operator removes the switch mid-flight | Checked before each lr-handoff attempt → `switch-removed` fallback. An in-flight lr-handoff finishes. |
| 22 | The watcher overruns `SELF_WATCH_MAX_S` | Claim released; the watcher is untouched; the reconciler's evidence decides. |
| 23 | The cc-reaper `orphan-bash` class | The worker is python (§1 row 11). Its lr-handoff child has ppid = worker. The detached handoff-fire watcher is today's exposure for every lane (an unlisted bash, ≤1200 s). The current cc-reaper.log shows 0 limit-recover victims [M, `grep orphan-bash … \| grep -c __recycle` → 0], so this is not changed here. |
| 24 | The relaunch is unprompted (`recycle-unverified`, no turn) | A C14 prompt request via the poller (§3.7). C2 would later replace this with socket delivery. |

**Bounded time to first attempt** [E]: the sum of bounded terms.

hook ≤0.05 + python/identity ≤1 + fence/claim ≤0.5 + S5 ≤120 + S6 ≤(30+10+30) + S7 ≤0.1 + S8 ≤300 + token ≤0.5

That is **≤ about 8 min worst case and about 10 s typical**, independent of load average. Load can
stretch the work inside each term, but none of these terms reads load.

---

## 6. Test plan

**Runners.**
- Python: `cd scripts/limit-recover && python3 -m unittest lr_recon.tests.test_selfrec lr_recon.tests.test_seats lr_recon.tests.test_selfrec_fence`
- A bats wrapper, `tests/lr-self-recover.bats`, in the shape of `tests/lr-recon-one-driver.bats:20`.
- Run every bats suite under `/bin/bash` 3.2 too (lessons "deployment interpreter" and "bash 3.2
  parens").
- Ratchets before land (lesson "run the test ratchets"): `test-afunix-path-lint.sh`,
  `test-hermeticity-lint.sh`, `bats-assert-liveness-fix.py`, and bare `shellcheck` on each changed
  suite and on the hook.

**Red-before-fix controls.** Each of these fails on today's code and passes after.

| Id | Suite | Case | Why it is red today |
|---|---|---|---|
| T-H1 | `tests/stop-failure-self-recover.bats` (new) | `self-recover.on` + `autorecover.on` + a rate_limit payload with `KITTY_WINDOW_ID=32` and a real transcript fixture ⇒ the spawn stub (`STOP_FAILURE_SELF_PERL` = a script that appends its argv and exits 0) is called **once**, with `--mode act --sid … --pane 32 --rlt seven_day`; the hook exits 0 with empty stdout; the ARM 2 request is written; `STOP_FAILURE_LAUNCHCTL` is **not** called | there is no ARM 4 |
| T-L1 | `tests/lr-handoff-placed-self.bats` (new) | `LR_PLACED_BY=self` + a `CC_ACCOUNTS_BIN` stub whose `--rank` omits the target ⇒ the precheck prints "router check is skipped"; today it is `REFUSED — the router does not rank` rc 6 (`:1383`) | there is no `self` arm in `lrh_placed` |
| T-L2 | same | `LR_PLACED_BY=self` ⇒ the minted launcher carries the reconciler continue tail (`LRP_CONT=`) | the tail choice is reconciler-only |
| T-R1 | `lr_recon/tests/test_selfrec_fence.py` (new) | an open PRE-MOVE record + a claim holder `{owner:"lr-self-recover", pid:<live test proc>, lstart:<its lstart>}` ⇒ `plan.movers(…, exclude=…)` omits it, `may_actuate(…, "UNCONFIRM", …)` → `(False, "self-recover")`, and a stubbed `place` is never called | the reconciler places it and UNCONFIRM is unclaimed |

**Equivalence guards, each with its mutant.** Lesson "green in both arms": each guard is paired with
the mutant that proves its power.

| Id | Guard | Mutant that must turn it red |
|---|---|---|
| T-H2 | no switch file ⇒ no spawn, and ARM 2 kicks as today | drop the `self-recover.on` test |
| T-H3 | each gate: `.off`, `$LIM/.off`, `CC_SF_SELF=off`, non-numeric pane, `bg`, handed-off, claim dir present, cooldown, `.on` without `autorecover.on` ⇒ shadow | delete any one gate line |
| T-H4 | two identical payloads (same death uuid) ⇒ exactly one spawn; a new uuid ⇒ a second spawn | replace `set -C` with `[ -e ] &&` |
| T-H5 | the spawn stub exits 1 ⇒ the latch is removed, the IDL row reads `self-spawn-failed`, and the kick is **not** suppressed | set `_SF_SELF_SPAWNED` before the spawn |
| T-H6 | detach: with `STOP_FAILURE_SELF_PY` = a script that sleeps 30 s, the hook returns in under 2 s, and the sleeper's ppid is 1 with its own sid | remove `fork`/`setsid` from the perl line |
| T-H7 | shadow mode ⇒ spawn with `--mode shadow`, and the kick is **not** suppressed | suppress the kick on any spawn |
| T-L3 | `LR_PLACED_BY=reconciler` and `cc-lr-move` behave byte-identically (re-run the existing `lr-handoff-launcher-quoting.bats` and `lr-handoff-flags.bats`) | n/a (existing pins) |
| T-L4 | `LR_PLACED_BY_SELF=off` ⇒ the router check runs | remove the kill switch |
| T-R2 | a **dead** self holder, or a reconciler holder ⇒ the record is placed as today | make `self_claim_live` ignore liveness |
| T-R3 | `_claim_stamp` for a reconciler holder still writes `"by":"lr-reconciler"` (existing `test_store.py` plus one assertion) | n/a |

**Worker units.** `lr_recon/tests/test_selfrec.py` (new). Every seam is injected: the sessions dir,
the registry dir, `ps` via a fake `proc_lstart`/`alive`, the router stub, the lr-handoff stub, and
the handoffs log.

| Id | Case |
|---|---|
| T-W1 | identity: one interactive live row ⇒ ok; two rows ⇒ `ambiguous`; `kind:"print"` ⇒ refused; dead pid ⇒ refused; claude-ish ancestor ⇒ `nested`; `login`-rooted zsh ⇒ `shell_root=yes`; expect-rooted ⇒ `no`; unreadable ⇒ `unknown` proceeds |
| T-W2 | scope and stay: `rlt=""` or model-scoped ⇒ fallback; `reset − now = 600` ⇒ `stay`; `= 1000` ⇒ proceeds |
| T-W3 | fence: owned + fresh heartbeat ⇒ yield; not-owned ⇒ act; `lapsed` ⇒ yield |
| T-W4 | claim: a live foreign holder ⇒ `yield claim:held`; taken ⇒ holder `owner == "lr-self-recover"`, `record_id == rid`; **released on every exit path**, including an injected exception in S6-S12 |
| T-W5 | env: no `CLAUDE_CODE_SESSION_ID`, `KITTY_WINDOW_ID`, `ITERM_SESSION_ID`, `CC_PANE_ID` or `CLAUDE_CONFIG_DIR`; has `LR_PLACED_BY=self`, `LR_INPLACE_AWAIT=0`, `CC_TERM_KITTY_TO`, `HF_WATCHER_RECORD`, `PATH == PLIST_PATH` |
| T-W6 | **R1 power proof**: `handoff-fire.sh --recycle --dry-run --transplanted-source --source-pane P --source-session S --resume-launcher L --resume-cfg C` under `selfrec.env()` passes R1 (rc ≠ 2 on R1's text); the same with `CLAUDE_CODE_SESSION_ID=S` leaked ⇒ rc 2 with `name THIS session`. Harness: `tests/handoff-recycle-self-source.bats` setup (`:18-80`). |
| T-W7 | argv equals `act.cmd_move` minus `--record-id`/`--attempt`, plus `--no-replace` (pinned) |
| T-W8 | classification: every row of the §3.7 table, from captured stderr fixtures (the reconciler's own `settle._REASON` and `_STRANDED` shapes) |
| T-W9 | watcher follow: an engaged row joined by `(watcher_pid, watcher_lstart)` ⇒ success; unverified then a turn within the grace ⇒ success; unverified with no turn ⇒ `self-prompt.json` written with `mode:"prompt"`; dead ⇒ rescue + kick; an overrun ⇒ release without a signal |
| T-W10 | registry: each row of the §3.8 table, including "never overwrite a live other tenant" |
| T-W11 | shadow writes **only** under `self-recover/` (tree diff of a temp `LR_STATE_DIR` and `HOME`), takes no claim, mints no token, never spawns lr-handoff |
| T-W12 | `_handover`: a SIGTERM while a stub child runs ⇒ claim, seat and slot re-stamped to the child; the child is still alive after the worker exits |
| T-W13 | G1 lint: `grep -nE 'getloadavg\|vm\.loadavg\|load1\|loadavg' lr_recon/selfrec.py lr_recon/seats.py` is empty (invariant G1, REPORT §5) |
| T-W14 | our own bounds are never verdicts: an S5 expiry, a `--rank` rc 124 twice, and a boot-slot wait expiry each ⇒ `fallback` with cooldown, poller kick and claim release, and never a terminal or "impossible" row |

**Seat ledger.** `lr_recon/tests/test_seats.py` (new).

| Id | Case |
|---|---|
| T-S1 | 9 processes (`multiprocessing`, a temp dir) take on one account with `SELF_INTAKE_MAX=3`, `cap=99`, `w=1` ⇒ exactly 3 seats, over 20 repetitions |
| T-S2 | **weight power proof**: `cap=5`, 3 concurrent movers with `w=2` ⇒ at most 2 admitted (total ≤5) in every repetition. Mutant: skip the post-create verify ⇒ 3 admitted at least once ⇒ red. |
| T-S3 | stale reclaim: a slot with a dead pid ⇒ reclaimed; a live pid ⇒ not; a holder-less slot younger than 10 s ⇒ not |
| T-S4 | spill: account A full ⇒ the seat lands on B in router order; all full ⇒ `None` |
| T-S5 | release removes only our own holder; a foreign file survives |

**Integration.** This depends on B1 and needs the operator's OK, because the rig opens a kitty
window.
- Add a `self-recover` scenario to `tests/rig/lr-recon-rig.sh`. The rig's `stub-claude.py` runs
  `hooks/stop-failure-marker.sh` with a rate_limit payload when its fault spec says
  `"hook": true`, with the rig's `LR_STATE_DIR` holding `self-recover.on` and `autorecover.on`.
- Assertions, for n = 9 and n = 30 with the rig daemon running:
  - every member reaches `recycle-engaged`;
  - the reconciler logs `self-recovering`, never `spawn`, for those sids;
  - no account exceeds 3 in-flight self seats;
  - the shared slot store never exceeds 6;
  - every claim is released at the end.
- Under B1's load generator (15/25/40 per core band mix), record `dt_death` of `handoff-start` and
  `engaged` beside load1 and the worker band (lesson "verify a cure under its load").

---

## 7. Rollout, kill switches, operator steps

**Phase 0. Land.** The code is inert with no switch file: one `[ -e ]` per rate_limit death.
- Converge the normal way (land, then `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`).
- No plist change, no launchctl, no daemon restart for the hook and worker. The reconciler edits of
  §3.9 load at the next reconciler restart. Before that restart, the claim alone still prevents a
  double drive; it just wastes one `--place`.

**Phase 1. Shadow.** The operator runs:

```
touch ~/.reso/limit-recover/self-recover.shadow
```

Every rate_limit death in a kitty pane then spawns a shadow worker. It runs S0-S3, a single at-rest
read, S6 and a **simulated** S7 (against `self-recover/shadow-seats/`, so concurrency is real but
isolated). It records one row in `self-recover/shadow.jsonl`:

```
{dt_death, identity, shell_root, scope, stay, fence, rank_order, rank_s, seat, would_argv_sha, why_not}
```

It takes no claim, mints no token, writes no registry row and spawns nothing.

After at least one real wall (about 2.7/week, REPORT §1), read:

```
cd ~/.claude/scripts/limit-recover && /usr/bin/python3 -m lr_recon.selfrec --report --since 2026-10-21T00:00:00Z
```

The report joins each shadow row to the reconciler's `own`/`spawn`/`exit` and the watcher's
`recycle-engaged` for the same sid. It prints:
- "self would have spawned at +X s vs the reconciler's spawn at +Y s, engaged at +Z s";
- the target agreement with `--place`;
- the `why_not` histogram.

**Go criterion:** at least 70% of the cohort is eligible, and median X is at least 5 min earlier than
Y.

**Phase 2. Act on one account.**

```
printf 'next3\n' > ~/.reso/limit-recover/self-recover.on
```

`autorecover.on` already exists [M]. Watch `self-recover/events.jsonl` and
`python3 -m lr_recon.selfrec --status` at the next wall on that account. This is also the live test
of gap-2 §8 items 1-5 (see §10).

**Phase 3. All accounts.**

```
: > ~/.reso/limit-recover/self-recover.on
```

**Kill switches,** strongest first:

| Switch | Effect |
|---|---|
| `touch ~/.reso/limit-recover/self-recover.off` | stops new spawns at the hook; in-flight workers fall back before their next lr-handoff attempt |
| `rm -f ~/.reso/limit-recover/self-recover.on ~/.reso/limit-recover/self-recover.shadow` | same |
| `touch ~/.claude/autonomy/limited/.off` | the whole limited arm |
| `LR_PLACED_BY_SELF=off` | lr-handoff only (a test seam) |
| `SELF_REGISTRY_WRITE=off` | no registry writes |
| `kill <worker pid>` (from `--status`) | hands over to its lr-handoff, then frees |

**Operator rulings.** Asks, not blockers for building:
1. Confirm that `VOLUNTARY_ACCOUNT_SWITCH.md:40,382-390`'s "NOT a Stop-hook nudge" does not cover a
   StopFailure-triggered move of an **already capped** session that spends no model turn (gap-2 §4).
2. Accept the weight policy: the reconciler's wave-3 rule, unchanged.
3. The composer stays a hard hold. There is no HID-idle bypass; that would be B5's ruling. So gap
   2's ruling 4 is **not** needed by this design.

---

## 8. Estimated size [E]

Method: count the components and compare with existing modules of like shape (`capped.py` 161 LOC,
`band.py` 163, `act.py` 592; the hook's existing arms run 60-110 lines including their comment
blocks).

| File | LOC |
|---|---|
| `lr_recon/selfrec.py` (new) | ~560 |
| `lr_recon/seats.py` (new) | ~150 |
| `hooks/stop-failure-marker.sh` (ARM 4 + kick clause + header) | ~75 |
| `lr_recon/store.py`, `plan.py`, `act.py`, `__main__.py` | ~45 |
| `lr-handoff.sh` | ~8 |
| **Code** | **~840** |
| `test_selfrec.py` | ~380 |
| `test_seats.py` | ~150 |
| `test_selfrec_fence.py` | ~110 |
| `stop-failure-self-recover.bats` | ~220 |
| `lr-handoff-placed-self.bats` | ~110 |
| `lr-self-recover.bats` wrapper | ~40 |
| **Tests** | **~1010** |
| **Total** | **~1850** |

The rig scenario (B1) is extra, about 120 LOC.

---

## 9. Dependencies on other items

None blocks building G2.

| Item | Relation |
|---|---|
| B1-load-harness | **Soft.** Proof under 15-40/core and the n=9/30 integration (§6) need it. Unit, bats and shadow evidence do not. |
| A6-restart-safety | Independent and compatible. A6's re-stamp keeps to reconciler record ids (§3.9). G2's `_handover` uses the same "re-stamp to the live actuator" principle. |
| B3-deadline-override | Compatible. A live self claim is HARD for B3 (B3 doc §9). G2 makes the first attempt seconds after death for its population; B3 bounds the rest. |
| B2-bounded-pass | Independent. G2 needs no pass. |
| B4-cheap-place | Independent. G2 uses no `--place`; a cheaper `--rank` (apply_burn) only helps S6. |
| B6-telemetry | **Soft.** G2 writes its own bounded rows (`events.jsonl`, `dt_death`), which B6's `--rail` can read (B6 doc §9). |
| B7-now-audit | Consistent. The worker uses `time.time()` per decision, with no pass `now`. |
| B5-kitty-off-critical-path | **Soft.** G2 inherits the remote form's kitty reads. B5's stage-before-probe and census identity would raise G2's success rate, and could later let S10 pass identity instead of writing the registry. |
| C2-socket-prompt | **Soft.** It would replace §3.7's C14 prompt request with socket delivery. |
| A7-limited-cohort-ruling | Orthogonal. Both zero-human flags now exist [M]. G2 still ships behind its own switch (house pattern: one flag per actuator). |
| D1-repick-ruling | No interaction. G2 passes an explicit `--target`, so `recycle_repick` is not involved (D1 doc §6.10). |
| D2-warning-band-shedding | Complementary. D2 shrinks the population that ever dies; G2 handles the deaths. |
| B8-kitty-hygiene | **Soft.** A PRI-4 kitty behind a locked screen fails every lane, G2 included (failure row 13). |
| C1-credential-flip | Alternative path. No interaction. |

---

## 10. Risks, open questions, and what only a live event settles

1. **The band after the claude exits** [H, strongly supported]. The worker is a setsid descendant of
   a PRI-31 claude. Gap-2 measured a setsid'd child at 31 under PPID 1, and hook-spawned daemons at
   31 for days. Settled by the `start` row's `band` and one `ps -M` during phase 2.
2. **The TUI on a weekly-cap modal versus at rest and SIGTERM** [H]. Partly answered: the incident's
   reconciler moves of the **same** limited sessions used `recycle-exit-signal` 8 times without
   typing (gap-2 §2 [M]), and G2 runs the same remote tail. A modal that changes the at-rest read
   would show up as S5 fallbacks in shadow.
3. **Marginal value against a PRI-31 reconciler** (unmeasured, §1 row 9). The reconciler's death→R
   path still serialises the pass, `--place`, ownership and the token bucket (1 per 20 s, burst 6).
   G2 removes all four and survives the daemon being down. How much this saves at PRI 31 is exactly
   what phase 1's `--report` measures. If median X−Y is under 5 min, G2's value is mostly resilience,
   and the operator may stop at shadow. That is the main reason conviction is 60%, not 80%.
4. **A second actuator on one population.** Mitigated by one claim, the reconciler yielding (§3.9),
   and shadow-first. Residual: a SIGKILLed worker leaves a window where its orphaned lr-handoff and a
   stealing lane overlap. The transplant split-brain lock and the per-pane recycle lock still stop a
   second typer (failure row 4).
5. **Registry writes are a new writer to a shared store** (§3.8). They are checked downstream and can
   be switched off. If the operator prefers, set `SELF_REGISTRY_WRITE=off`; the 16% of sessions with
   no row then stay on today's path.
6. **Population edges** (gap-2 B11): idle sessions (no StopFailure), teammates, no-pane sessions
   (8/51 [M]), iTerm panes and launcher-rooted panes all stay on today's lanes by design.

---

## Appendix A. Commands run (read-only; only `/tmp/g2_*.py` and this file were written)

| Command | What it established |
|---|---|
| `git log --oneline -5`; `git rev-parse HEAD main`; `git diff --stat 28b25a119..main -- <rail paths>` | the code base; no drift on the cited files |
| `git diff c82a349ce..HEAD -- scripts/handoff-fire.sh \| grep '^@@'` | handoff-fire line shifts since gap 2 (+23/+28 after :2862/:2920) |
| `sed`/`grep -n` over `hooks/stop-failure-marker.sh`, `lr-handoff.sh`, `handoff-fire.sh`, `lr-lib.sh`, `lr-recon-fence.sh`, `lr-reset-poller.sh`, `lr_recon/{act,store,plan,fence,capped,transcript,classify,settle,admit,band,types,__main__}.py`, `bin/claude-accounts`, `bin/cc-reaper`, `scripts/lib/capacity-admit.sh`, `lib/pane-successor.sh` | every file:line cited |
| python read of `~/.claude*/sessions/*.json` + `~/.claude/cc-registry/*.json` | 31 live interactive sessions, 26 bound, 5 without a row |
| `/tmp/g2_markers.py`, `/tmp/g2_panes.py` over `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` | 51 capped sids, 43 kitty panes, 8 no pane |
| `/tmp/g2_ev.py` over `recon/events.jsonl` | no cohort since the band fix |
| `ls -la ~/.reso/limit-recover/{autorecover.on,recon.on,recon/autorecover.on}`; `ls -la ~/.claude/autonomy/limited/` | both zero-human flags exist; `.kick-on` absent |
| `ps -o pid,ppid,ucomm,tty` walk of pid 15002; `ps -Eww -o command= -p 15002` | the nested-pty ancestry; the pane env carried into hooks |
| `time /usr/bin/perl -MPOSIX -e 'exit 0'`; `sysctl -n vm.loadavg hw.ncpu` | 0.023 s at 20.7/core |
| `claude-accounts --rank general --recovery --max-wait 0 --max-age 900` | 0.848 s, cache-only, ranked list + route-meta |
| `python3 -I -c '…SourceFileLoader(bin/claude-accounts)…'` | 0.36 s import (not used by the design) |
| `tail -1 ~/.claude/logs/compressor-sentinel.jsonl` | the sentinel row shape (`pct`) |
| `tail -c 300000 ~/.claude/logs/handoffs.jsonl \| grep recycle-` | watcher rows carry `watcher_pid` and `watcher_lstart` |
| `grep orphan-bash ~/.claude/logs/cc-reaper.log \| grep -c __recycle` | 0 recycle watchers reaped in the current log |

---

## Review — efficacy-under-permanent-load

**Reviewer verdict: NEEDS-CHANGES. Adjusted conviction: 50%** (the design says 60%).

**The question.** At 15-40 runnable threads per core, with every lane at PRI 31, does G2 actually
bound recovery time? And does any new wait, bound or gate assume that load falls?

**Short answer.**
- G2's own new code reads no load. That part holds.
- But the time bound in §5 rests on four things that are false or unstated under the premise:
  1. **S13's outer bound is shorter than the watcher's own inner bounds** at every load in the band
     (R1 below).
  2. **The shared boot slot is held through the whole watcher follow**, which the reconciler never
     does (R2).
  3. **Exclusive ownership is honoured on pid liveness alone.** A stalled or sub-31 worker
     therefore holds a record that the reconciler, and B3, will not touch (R3, R4).
  4. **S6 depends on a router cache whose producer runs at PRI 20** (R6).

  Two of the cited code readings are also wrong: the failed-mint path in R5, and "no gate reads
  load" in R8.

**Method.** Read-only. Writes: `/tmp/g2rev/` (one analysis script, plus stderr captures of my two
`--rank` runs) and this section. I re-read every cited line on the efficacy path. Load during my
readings was 17.1-22.1 per core (`sysctl -n vm.loadavg` → `{ 171.44 … }` to `{ 221.40 … }`, with
`hw.ncpu` 10), and my shell ran at PRI 31 (`ps -o pri= -p $$` → `31`).

### What I confirmed

- **[M] The S6 cost is small at PRI 31.** `/usr/bin/time -p ~/.claude/bin/claude-accounts --rank
  general --recovery --max-wait 0 --max-age 900`:
  - output: `real 2.11` and `real 1.45`, rc 0;
  - route-meta: `quota_age_s=38 … k_src=panes k_cap=40 … k_eff=13`;
  - load was 17.1/core.

  That is slower than the design's 0.85 s, but far inside the 30 s bound. `--rank` writes nothing
  (`bin/claude-accounts:11425-11428`). A cache-only read never takes the lock
  (`bin/claude-accounts:8243-8259`).
- **[M] Python start and import are cheap.** `/usr/bin/python3 -B -I -c '…import lr_recon.store,
  plan, fence, transcript, classify, settle, admit, band, capped…'` → `import_s 0.662 / 0.496 /
  0.376`. A bare interpreter → `real 0.06-0.08`. So "≤1 s" holds at about 18/core.
- **[M] Live claude sessions are at 31T.** `ps -M -p 78655` → every thread `31T`. So a hook
  descendant starts at 31 while kitty is foreground (kitty 853 read `47T`).
- **`LR_INPLACE_AWAIT=0` is the right choice** (`act.py:65`, `lr-handoff.sh:2008-2011`). It avoids
  `recycle_await_verdict`, whose window is mis-sized under load (see R1).
- **The in-pane gate's load term is off on this lane.** `lr-lib.sh:517,534` (`CC_ADMIT_LOAD_TERM:-off`)
  and `lr-fire-resume.sh:905` (`LR_LOAD_TERM:-off`).
- **The precheck's typed-relaunch load hold is skipped when the successor library loads**
  (`handoff-fire.sh:13878-13879`). A `--resume-launcher` recycle is `resume` mode
  (`handoff-fire.sh:4778-4783`), and resume mode stages the successor (`:4793-4797`, `:20131`).

### Refutations and required changes

**R1. S13's bound is below the watcher's own maximum. The claim "the inner bound always fires
first" (§3.2, `SELF_WATCH_MAX_S`) is false.**

The 1200 s the design copies comes from `recycle_await_verdict`'s formula (`handoff-fire.sh:20159`).
That formula reads `${RCY_BOOT_STALE_S:-180}` and `${RCY_ENGAGE_TIMEOUT:-180}` in the *foreground*,
where neither variable is set. The detached watcher instead sets them, and several other stage
bounds, through `hf_load_scaled`. That function is base × min(4, 1 + load/core ÷ 10)
(`handoff-fire.sh:4957-4959`). It is used at:

| Line | Bound |
|---|---|
| `:12441` | engage, 180 s base |
| `:12476` | claim max, 120 s base |
| `:12510` | rails, 60 s base |
| `:12651` | boot wait, 60 s base |
| `:12652` | boot stale, 180 s base |

The post-`/exit` stages the watcher may still be in when S13 starts are:
- shell wait, 600 s (`:11634`);
- the claim loop;
- the rails;
- the typed deadline, 600 s if the stage is revoked (`:12589`);
- boot stale;
- engage.

[E] The watcher's maximum, by arithmetic on those lines:

| Load | Staged path | Revoked path |
|---|---|---|
| 0/core (×1) | 1320 s | 1920 s |
| 15/core (×2.5) | 1950 s | 2550 s |
| ≥30/core (×4) | 2760 s | 3120 s |

1500 s is under the maximum in every row except the unloaded staged path, so G2's own bound fires
first in the slow tail. When it fires, the claim, seat and slot are released while the watcher is
still working. The reconciler mostly holds off, because it sees the watcher by argv
(`evidence.py:206`; `__main__.py:855-861`). But G2 loses the outcome and its C14 repair.

The design also cites the "inner bound starves the tail" lesson for the opposite of what it does.

- **Change.** Follow the watcher by (pid, lstart) liveness with **no expiry shorter than the ×4
  sum**: derive it from the same variables (`HF_RECYCLE_SHELL_WAIT_S`, `CC_RECYCLE_CLAIM_MAX_S`,
  `CC_RECYCLE_RAILS_WAIT_S`, `CC_RECYCLE_TYPE_DEADLINE_S`, `RCY_BOOT_STALE_S`, `RCY_ENGAGE_TIMEOUT`)
  at the ×4 cap, plus slack. Pin it with a test shaped like `tests/lr-relaunch-bound.bats`.
- **Or** re-stamp the claim to the watcher's (pid, lstart), A6's rule, so ownership ends exactly
  when the watcher does.
- Correct §3.2 and §5 row 22.

**R2. The shared boot slot is held through S13. That starves the reconciler, `cc-lr move`, and G2's
own fallback.**

- The reconciler holds a slot only while a `BOOTING` actuator, lr-handoff, is alive. It releases the
  slot on the first pass after lr-handoff exits (`__main__.py:1124-1129`; `act.py:33`
  `BOOTING = ("A","A-husk","B","R")`).
- An adopted watcher is recorded as `argv_hash="adopted"` (`act.py:369`), so it never holds a slot.
- G2 releases its slot only in `settle()`, after S13 (≤1500 s) and the 300 s engage grace (§3.2,
  §3.5).
- The store's width is 6 (`admit.py:341`, `START = 6`).

So six slow self moves hold every boot slot on the box for up to about 30 min [E]. Meanwhile:
- the reconciler's `_admit` returns `boot-slots` on every pass (`__main__.py:1139-1140`);
- other self workers wait out `SELF_BOOT_WAIT_S` = 300 and fall back into a lane that is itself
  blocked on slots.

This is load-correlated, because boots and watchers stretch with load. The design's phrase
"released as boots finish" (§3.5) does not describe its own `settle()`.

- **Change.** Release the boot slot when lr-handoff exits, on every rc. That matches the reconciler.
  The intake seat may stay until the outcome.
- Add a test that the slot dir is gone while a stub watcher is still alive.

**R3. Ownership is pid liveness only. A stalled or sub-31 worker holds a record that nothing else
may touch, so invariant G fails for that record.**

`self_claim_live` (§3.9) is `alive(h.pid, h.lstart)`. When it is true:
- `movers` excludes the sid;
- `may_actuate` refuses every actuator;
- B3 classifies the record HARD and only pages (`B3-deadline-override.md:613`: "B3 sees HARD
  claim-held and pages at `W_hard` if it stalls").

The worker's bounds are all wall-clock checks inside the worker. A worker that gets no CPU cannot act
on them. Two cases:
- **Below 31.** The design's own failure row 3 says "The worker runs at PRI < 31 … Still no gate".
  The REPORT measured a 0.45 CPU-s task "never finished" in >150 s at PRI 4 (§3.1 table).
- **Kitty nap.** Whether claude sessions, and so the hook's children, are demoted while kitty is
  napped is **unmeasured** [H]. B8 records kitty napped for 713 s during the incident and 21,036 s
  overnight (`B8-kitty-hygiene.md:187-188`), but it read only kitty's own band.

Changes:
- (a) **S0 band gate.** If `band.base_priority(os.getpid()) < 31`, take no claim. Log it and hand
  back at once (kick). This is a band check, not a load check; it is invariant G4.
- (b) **A progress heartbeat.** The worker touches `self-recover/work/<sid>.hb` at each step and at
  every poll. `self_claim_live` also requires `now − mtime(hb) ≤ SELF_HB_STALE_S` (for example 120).
  Past that, the reconciler logs `self-stalled` and may steal under the existing steal path.
- (c) **State the maximum self hold** as a number (see R9). Make B3 treat the self claim as HARD
  only while its heartbeat is fresh.
- Add the matching T-R test: a live-pid holder with a stale heartbeat ⇒ the record is placed.

**R4. A `ps` timeout reads as "dead" or "no identity". That is our own bound used as a verdict, on
the new holder class.**

- `store.proc_lstart` returns `""` on its 40 s timeout (`store.py:525-546`).
- The reconciler's `_alive` is `bool(lstart) and proc_lstart(pid) == lstart` (`__main__.py:129-130`).
  So one stalled `ps` makes a live self worker read dead, and the claim becomes stealable
  (`store.py:392-395`).
- The reverse also fails. If the worker's own `proc_lstart(os.getpid())` times out at S4, the holder
  is lstart-less. The steal path then needs `lr-fleet`/`cc-lr` in the argv (`store.py:399-401`), so a
  python worker's claim is "stolen-legacy". And `self_claim_live` (which requires `h.lstart`) returns
  False, so the reconciler also stops yielding.

The REPORT records one kernel-side `ps` stall of 1,226 s (§3.3).

- **Change.** S4 refuses to claim without its own lstart (fallback `identity-unreadable`).
- `self_claim_live` maps an unreadable `ps` to "unknown → yield this pass", never to dead. This needs
  a tri-state `proc_lstart`, or a separate call that tells a timeout apart from a gone pid.

**R5. The failed-mint path is misread. It runs lr-handoff's own probe, which can PARK.**

§3.6 says "A failed mint is not a refusal: the launcher evaluates the gate in the pane, as at
`:1607-1610`". But `selfrec.env()` sets `LR_ADMIT_TOKEN_PATH` only `if tok`. With no token,
lr-handoff skips the caller-owned branch (`lr-handoff.sh:1571`) and enters
`elif command -v lr_capacity_probe_corrected` (`:1590`). It runs the probe, and on a refusal prints
`PARKED on capacity … re-run when the box clears` and returns 6 (`:1592-1597`). Lines `:1607-1610`
sit *inside* that branch, after its own probe.

The probe keeps the **active** term: CPU-active turns, ceiling ncpu × 0.8 (`capacity-admit.sh:79-81`;
`lr-lib.sh:499-538` turns only load off). Under 24/7 saturation that term is the shape of "wait for
activity to fall". `PARKED` is also not a row in the §3.7 table.

- **Change.** A failed mint means `fallback("mint-failed")` before lr-handoff runs.
- Add a `PARKED` row to the table: fall back, never retry.
- Do not pass an empty token file. That would move the fresh evaluation to after the `/exit`
  (`lr-fire-resume.sh:868`, `:905-907`), where a refusal leaves a bare shell.

**R6. S6's freshness depends on a PRI-20 producer. G2's coverage drops exactly when load starves
it.**

- **[M] The producers run at 20T.**
  - `plutil -p ~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist` → `"ProcessType" =>
    "Standard"`, `StartInterval 180`, perl `alarm 240`.
  - A live keepwarm read 20T: `ps -M -p 70900` → `20T`, at load 221.
  - accounts-local also read 20T: `ps -M -p 52396` → `20T`.
- **[M] Sweeps are slow even now.** `tail ~/.claude/logs/accounts-keepwarm.out.log` → `took_ms=17508 …
  99260`.
- **[M] Sweep gaps, 7-day proxy.** `/tmp/g2rev/gaps.py` over `account-utilization.jsonl`:
  - 1,420 sweeps;
  - gap p50 396 s, p90 519 s, p99 606 s, max 11,657 s;
  - 1.8% of wall time with a gap over 900 s.

The REPORT measured band-20 work at 7-111x slower than 31 (§3.1). When the cache passes 900 s, every
G2 death goes `rank-unknown` and falls back. That is silent, and it is not covered by T-W14, which
tests rc 124 but not rc 3.

- **Change.** Name `com.claude.accounts-keepwarm` and `com.claude.accounts-local` at
  `ProcessType Interactive` as an operator dependency, as wave 5 did for the dispatcher.
- The shadow row records the `--rank` rc, `quota_age_s`, load1 and the producer's band, so the
  dependency's failure rate under load is measured before act.
- Add rc 3 to T-W14.

**R7. The retry window is measured from worker start. Under load it allows at most one attempt.**

`SELF_RETRY_WINDOW_S` = 600 counts from t0 (§3.2, `t0 = time.time()` in `run`). Before attempt 1,
three waits can spend up to 490 s of it:
- S5, ≤120;
- S6, ≤70;
- S8, ≤300.

Those waits run longest when load is high and slots are busy. A kitty TRANSIENT then exhausts the
window after one attempt, so `SELF_ATTEMPTS = 4` is unreachable in exactly the condition retries
exist for. That is load-dependent coverage.

- **Change.** Start the window at the first lr-handoff spawn. Keep a separate hard ceiling on the
  whole hold (R9).

**R8. "No gate reads load" overstates. Load is read on the inherited path.**

- **The commit-time load hold.** `hf_recycle_load_gate` (`handoff-fire.sh:4183-4194`, called at
  `:19407-19411`, after the confirm) holds when two things are both true:
  - load/core is above `hf_recycle_load_bound`, default **24** (`:4159-4170`), which is inside the
    operator's 15-40 band;
  - no stage of ours is staged.

  The stage's refusal arms (`:4789-4827`) include "watcher has no readable start time" (a `ps`
  read, `:4805-4806`). On that path G2 meets `HELD:load` after the confirm (failure row 16).
- **Load-scaled watcher bounds.** `hf_load_scaled` (`:4957-4959`) reads load to size them (R1).
  That is not a wait, but it does read load.
- T-W13's lint covers only `selfrec.py` and `seats.py`.

- **Change.** Reword the summary and §5 to say "G2's own code reads no load; the inherited
  handoff-fire path reads it at `:4183-4194` and `:4957-4959`".
- Count `HELD:load`-after-confirm in `events.jsonl`.
- List as a dependency the follow-up that exempts the staged-refused case, or that retries the stage
  before the hold. G1 cannot be claimed for this lane until that lands.

**R9. The ≤8 min bound covers only G2's first attempt. The fallback population's bound is
unstated.**

[E] The maximum self hold before a hand-back, from §3.2's constants:

| Term | Seconds |
|---|---|
| S5 | 120 |
| S6 | 70 |
| S8 | 300 |
| retry window | 600 |
| one last lr-handoff, T_lrh | unbounded by G2; the 2026-10-18 comment at `handoff-fire.sh:13864-13866` records 306 + 284 + 649 s at PRI 20 |
| S13 | 1500 |
| engage grace | 300 |
| **Total** | **≈ 48 min + T_lrh** |

During the hold the reconciler yields, so a record that falls back reaches today's path that late.
Separately, the §6 integration assertion is inconsistent. For n = 30, "every member engaged" and "the
reconciler logs `self-recovering`, never a spawn" cannot both hold. Only 3 targets × 3 intake seats
= 9 self movers can be in flight, inside a box-wide limit of 6 boots (§3.5), so most of a 30-death
cohort must fall back to the reconciler.

- **Change.** State the composed bound: G2's maximum hold, then the reconciler's G from REPORT §5
  with `t_detect` unchanged.
- Rewrite the n = 30 assertion as:
  - ≤ 9 self seats and ≤ 6 slots;
  - every member engaged by `T_done` through either lane;
  - every fallback's reconciler `own` within `P_max` of the hand-back;
  - `t_first` per lane recorded beside load1.

**R10. The reconciler's derive side is not gated for self-driven records [H].** §3.9 gates `movers`
and `may_actuate`, but `_derive` still runs. The fixed `IN_FLIGHT_MAX_S` = 600 rule
(`__main__.py:59`, `:876-893`) applies `DETERMINISTIC`, then ESCALATED, to a relaunch gap with no
holder. Under load the gap legitimately exceeds 600 s: boot stale alone is up to 720 s (R1). Whether
a self-driven record can enter `IN-FLIGHT` depends on `confirm_len` being set (`settle.py:571-583`),
which I did not trace.

- **Change.** Add a T-R test: while a live self claim exists, the record never gets `in-flight`,
  `in-flight-expired` or `apply_failure`. If it can, skip those for `ctx.self_driven`.

**R11. A worker that crashes before `settle()` loses the kick for up to 600 s.**

The kick is suppressed whenever an act worker is spawned (§3.1). The poller's own cadence is
`StartInterval 600` ([M] `plutil -p ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist`). In the
pseudocode, S0-S3 return before the `try:`.

- **Change.** Run through a bootstrap that kicks on any uncaught exception or signal before the claim.
- Put S0-S3 inside the `try/finally`.

**R12. Polling cost in the oversubscribed PRI-31 band.**

- S13 calls `fence.proc_alive` every 2 s. That is two `ps` forks per call (`fence.py:172-180` →
  `_ps` twice, each with a 5 s bound, `:146-156`).
- Per worker that is about 1,500 forks over a 1500 s follow. Across 9-30 workers it is 9-30 forks/s.
- The REPORT measured 280-1,410 execs/s already, with 40-53% system time (§3.3).
- Note also that a 5 s `_ps` timeout reads as not-alive, which is the R4 class again.

- **Change.** Verify the lstart once, then wait on `select.kqueue` `EVFILT_PROC`/`NOTE_EXIT` for the
  watcher pid (stdlib on macOS), with a coarse lstart re-check every 60 s.
- Poll S8 at no more than one read per 5 s, as designed.

### Why the conviction drops

- The mechanism holds: no new load read, cache-only routing, the remote tail reused, and fallback
  meaning "unknown".
- But R1-R3 are not edge cases under the premise: they are the load-stretched tail.
- R3, combined with B3's HARD treatment, can turn a stalled worker into an unbounded hold. That is
  the one outcome the operator's target forbids.
- With R1-R5 and R9 applied, I would put it back at about 60%.

---

## Review — correctness-and-safety

**Reviewer verdict: NEEDS-CHANGES. Adjusted conviction: 45%** (the design says 60%).

**The question.** Could G2 strand a session, drive one session twice, lose a draft, split ownership,
break an invariant or break an existing test?

**Short answer.** The core is sound. The run claim is the right single arbiter, and every other lane
honours it. The R1 allowlist works and the remote tail is reused unchanged. But I found five defects
that give two live owners for one session, or let a lane take a session mid-move. Each is shown by a
probe or by the cited code. All are fixable inside the design. This section avoids repeating the
efficacy review above. Where it confirms one of that review's findings, it says so.

**Method.** Read-only on the system. My only writes were `/tmp/g2cs/` (two probe scripts and their
scratch stores under `/tmp`) and this section. Load during my reads was 18.7/core
(`sysctl -n vm.loadavg hw.ncpu` → `{ 187.49 197.86 183.71 }`, `10`) [M]. I re-checked about 45 of
the design's file:line cites. All were within ±3 lines, except the misreadings named below.

### What I confirmed holds

- **Every other driver takes the same claim dir, so one claim really is one owner:**
  - the reconciler takes the claim before `owned/` (`store.py:552-580`, `take_ownership`) and before
    every claimed actuator (`act.py:493-523`);
  - bash lanes use `lr_claim_take` (`lr-lib.sh:839-882`, `held-live` at `:846-847`);
  - `lr-upgrade` switch/drain uses the same `runs/by-sid` mutex (`lr-upgrade.sh:99`, `:1281-1284`);
  - the poller keeps a hook request while the claim is held (`REQUEST-IN-FLIGHT`,
    `lr-reset-poller.sh:1817-1822`).
- **R2 passes on the intended chain.** worker → lr-handoff → handoff-fire: the holder is an
  ancestor of handoff-fire (`handoff-fire.sh:2610-2621`, `:2660-2680`, `:16302-16305`).
- **The reconciler's cleanups are keyed by `record_id`, so none touches a self claim:**
  - D1.10 own-takeover (`__main__.py:1066-1073`);
  - `_release_terminal` (`:1545-1557`);
  - the startup re-stamp (`:1792-1794`).
- **The phantom is safe as designed:**
  - a sid-tagged row stops charging once the census counts that sid on its account
    (`bin/claude-accounts:4260-4263`);
  - a void row voids its id wherever it sits in the ledger (`:4285-4292`), so an async `--assign`
    that lands after a fast `--unassign` charges nothing.
- **The reconciler sees a self watcher by argv** (`evidence.py:87-93`, `:206`). Phase rows 9-11
  therefore hold off while it lives (`phase.py:123-155`).
- **Drafts.** I found no path that types over a draft:
  - the precheck holds `HELD:draft` with no `LRH_CARRY_DRAFT` (`lr-handoff.sh:1480-1496`);
  - `cc_tui_submit` holds an occupied composer (rc 3, `scripts/lib/cc-tui.sh:12`).
- **Existing pins survive:**
  - `test_store.py:147` pins `(by, owner) == (BY, BY)`, and reconciler holders keep `owner=BY`;
  - the new `movers`/`may_actuate` keyword arguments have defaults;
  - SA9 and the "not a pager" footprint pins (`tests/stop-failure-marker.bats:274-296`, `:488-520`)
    are untouched while no switch file exists, because ARM 4 returns before any `mkdir`.

### Refutations and required changes

**C1 (critical). The worker imports from the dying session's cwd.**

The perl `exec`s `python3 -m lr_recon.selfrec` in the hook's cwd, which is the session's project.
`-m` puts the cwd at `sys.path[0]`, ahead of both `PYTHONPATH` and the stdlib. So a project's
`json.py`, or a worktree's `scripts/limit-recover/lr_recon/`, is what runs, against live state.
`os.chdir(HOME)` in `selfrec` runs too late, after the imports.

- **[M] The hijack.** In `/tmp/g2rev_cwd`, holding a planted `json.py`:
  `PYTHONPATH=/tmp/g2rev_lib /usr/bin/python3 -m modz.run` → `HIJACKED json from cwd`,
  `sys.path[0]= /private/tmp/g2rev_cwd`.
- **The house rule already exists.** The reconciler plist `cd`s to the package before `-m`
  (`com.reso.lr-reconciler.plist:42`).
- **Change.**
  - In the perl child, `chdir($lrd) or exit 1` before `exec`.
  - Exec `/usr/bin/python3 -E -s -m lr_recon.selfrec`. `PYTHONPATH` is then unnecessary.
  - Add a T-H8 that runs the hook from a cwd holding a planted `json.py` and an `lr_recon/` stub,
    and checks that the worker stub records the live module path.
- ARM 3's existing `python3 -m lr_recon.facts` (`hooks/stop-failure-marker.sh:621`) has the same
  exposure. That is out of scope here, but worth a follow-up.

**C2 (critical). Two workers can share one `rid`, and `claim_take` then gives both "ours".**

- **How the `rid` collides.** `rid = "self:<sid8>:<slug(death_uuid)[:12]>"`, and `--death-uuid` is
  the raw `_SF_EN_UUID`. That is empty whenever the bounded enrich fails: its 4 s timeout, or a tail
  that misses the record (`hooks/stop-failure-marker.sh:360-370`). Meanwhile the hook's latch falls
  back to `p-<LAST>`. So two deaths of one sid with different cap text get two latches, two workers
  and the same rid `self:<sid8>:`.
- **Why "ours" is unsafe.** `claim_take` returns "ours" on a `record_id` match without checking the
  pid (`store.py:391`).
- **[M] probe (a)** (`/tmp/g2cs/claim_probe.py`) → `worker A take: taken`, then
  `worker B take (same rid, other live pid): ours`.
- **Change.**
  - Make the rid unique per worker: `self:<sid8>:<pid>:<6 hex nonce>` (it still matches
    `_ASSIGN_ID_RE`, `bin/claude-accounts:4340`).
  - Keep the death key only in the event rows.
  - Copy `_sf_request`'s `p-nokey` rule (`:496-497`) into ARM 4's latch.
  - Add a T-W4 case: two workers with the same death key ⇒ exactly one `taken`.

**C3 (critical). A self holder without an lstart is stolen while live.** This confirms efficacy R4
with a probe.

- `RunClaimHolder(os.getpid(), store.proc_lstart(os.getpid()), …)` writes `lstart:""` whenever
  that `ps` fails or passes its 40 s bound (`store.py:525-546`).
- The reconciler's `claim_take` then judges the holder by argv (`store.py:396-401`). `_own_and_charge`
  passes `lambda pid: ""` (`__main__.py:1077-1079`), and `hold_claim` passes the real argv. The
  worker's argv names neither `lr-fleet` nor `cc-lr`.
- **[M] probe (b)** → `self take with empty lstart: taken`, then
  `reconciler take over that LIVE holder: stolen-legacy`. The holder is now `owner='lr-reconciler'`.
- **Change.** As R4: S4 refuses to claim without its own lstart (fallback `identity-unreadable`).
  Apply the same rule to seat and slot files, because `fence.proc_alive` reads an empty lstart as dead
  (`fence.py:172-176`).

**C4 (critical). The SIGTERM hand-over is undone by `settle()`, and it orphans lr-handoff to the
reaper.**

- **The release is not pid-guarded.** §3.2 has `_handover` re-stamp the claim, seat and slot to
  lr-handoff and then "exit". But exiting from the handler (`sys.exit`) runs `finally: settle()`, and
  the release primitives the design names do not check the pid:
  - `store.claim_release(paths, sid, rid)` checks only `record_id` (`store.py:419-424`), so it
    deletes the claim it has just re-stamped;
  - `BootSlots.release` unlinks `pid`/`lstart` and `rmdir`s whatever `self.disk` names
    (`admit.py:442-454`).

  The claim is then free while lr-handoff is mid-transplant. The poller, cc-lr or the reconciler can
  take it, which is a double drive.
- **The orphan.** Once the worker exits, lr-handoff is a launchd-parented `bash`. `GARBAGE_WL` does
  not list `lr-handoff` (`bin/cc-reaper:737`), and the `orphan-bash` rule TERMs it at 600 s
  (`:965`). So §5 row 23's "Its lr-handoff child has ppid = worker" stops being true at exactly that
  moment. Under load, lr-handoff's own bounds exceed 600 s (efficacy R9: 306 + 284 + 649 s on record).
- **Change.**
  - Make SIGTERM mean "start no new attempt". Keep waiting on the live child, settle on its exit, then
    exit.
  - Or, if a fast exit is required: re-stamp, then `os._exit(0)`, and make every release pid-guarded.
    That means a new `store.claim_release_if(paths, sid, rid, pid)` and a seat/slot release that first
    re-reads the holder.
  - Either way, T-W12 must assert that the claim dir and slot dir still exist after the worker exits
    and the child lives.

**C5 (critical). Act mode must not start before the reconciler's yield is loaded.**

- **The contradiction.** §7 phase 0 says that before the reconciler restart "the claim alone still
  prevents a double drive". §3.9 says the opposite, and the code agrees with §3.9:
  `CLAIMED_ACTUATORS` is `A, A-husk, B, R, C, C-retry` (`act.py:482-489`). So UNCONFIRM, FOLD, ABORT,
  SPLIT, HEAL and the in-place `wake` (`act.py:226`; set up by `_wakes`, `__main__.py:408-457`) all
  run with no claim.
- **The risk.** A daemon still running pre-G2 code can therefore actuate against an in-flight self
  move.
- **Change.**
  - The reconciler writes a capability stamp at startup, for example `recon/features` containing
    `self-yield-1`.
  - The hook's act gate, and the worker before S4, require that stamp whenever `recon.on` exists.
    Otherwise they run as shadow, named `self-skip-recon-not-yielding`.
  - Add a T-R4 for the stamp.

**C6 (high). A shared boot slot is not exclusive across processes.**

- **The race.** `BootSlots._disk_take` reclaims a dead slot by unlinking `pid`/`lstart` and
  rewriting them in place (`admit.py:390-415`), with no rename and no exclusive create. Two takers that
  both judge one slot dead both "hold" it. The first one to release then deletes the other's slot
  (`:442-454`).
- **Why G2 makes it live.** The reconciler is one process, and the bash side steals by rename
  (`lr-move-lib.sh:254-255`). G2 adds N concurrent Python takers, and its hand-over leaves dead slots
  behind by design.
- **[M] The probe.** `/tmp/g2cs/bootslot_race.py`: 12 processes against 6 dead slots, 6 trials →
  `believe_held` = 8, 7, 8, 11, 7, 7, with `dup_dirs` up to `slot-6: 3`. So "the shared slot store
  never exceeds 6" (§6) is false today for concurrent Python takers.
- **Change.** Steal by `os.rename(d, d + ".dead.<pid>")`, then `mkdir`, exactly as the bash side
  does. Add a multi-process T-S6 with this probe's shape, in two arms: Python-only, and Python racing
  `lr_swap_slot_acquire`.

**C7 (high). The registry is written before it is verified.**

S10 writes `cc-registry/<P>.json` and trusts handoff-fire's later pin to catch errors. But a wrong row
is a shared-store write that outlives the refusal. Readers include lr-handoff's `SRC_PID` and argv
capture (`lr-handoff.sh:983-990`), boot-resume and `cc-find`. And `P` is a window id, which is only
unique within one kitty.

- **[M] A second kitty exists.** `ps -o pid,command -p 41475` →
  `/Users/chrisren/kitty-pr3/base/kitty/launcher/kitty --config=NONE …`.
- **[M] It has no control socket.** `ls /tmp/kitty-*` → only `/tmp/kitty-853` is a socket.

A capped claude in that instance has a `KITTY_WINDOW_ID` and an empty `KITTY_LISTEN_ON`.

**Change.**
- Gate on a non-empty `--kitty-to` that is a live socket.
- Before any write, prove `P` on that socket: enumerate it, then check that its tty equals the
  identity's `tty_root`. Use the same predicate as `hf_remote_source_pin`.
- Judge tenancy by `(pid, lstart)` from the row's own `lstart`, never by pid alone. session-register
  names pid reuse as the hazard (`hooks/session-register.sh:73-76`).
- Add the missing row "same sid, a different live pid" ⇒ `registry-conflict`.

**C8 (high). The C14 prompt repair can double-prompt.**

- **The poller does not revalidate it.** A `requested_by:"lr-self-recover"` request gets `_rq_hook=0`
  (`lr-reset-poller.sh:1616`). That skips the drain-time revalidation (`:1627`) and goes straight to
  `cc_tui_submit` (`:1857-1880`).
- **`cc_tui_submit` cannot see a turn in flight.** Its rc table has no busy refusal
  (`cc-tui.sh:9-14`), so a prompt typed while the launcher's own prompt is still in its turn is
  queued, which means a second turn.
- **`recycle-unverified` is no evidence of a missing prompt.** It is emitted when the watcher
  *could not measure* (`handoff-fire.sh:12760`, `:12899`, `:12930`).
- **The transcript is unnamed.** §3.7 does not say which transcript the worker reads. `a.tp` is the
  source copy, which the move retires.
- **A second prompter exists.** After the worker releases, the reconciler's C may also prompt the same
  session.
- **Change.** File C14 only when all of these hold:
  - the target copy is readable (`transcript.find_transcript([target_cfg], cwd, sid)`);
  - it has no user record after the relaunch carrying lr-handoff's `LR_SUBMIT_TOKEN`;
  - no open reconciler record exists for the sid.

  An unreadable target copy means unknown: release and kick, but type nothing.
- Add T-W9 cases for "launcher prompt present, turn slow" and "unreadable".

**C9 (medium). The rescue attribution is wrong. The reconciler cannot rescue a self move.**

- **Why A-husk and B fail.** Both need `settle.bundle_launcher`, which matches the MANIFEST's
  `record_id` to the record's (`settle.py:690`). A self move's MANIFEST carries `record_id:""` and
  `placed_by:"self"` (`lr-handoff.sh:1174-1183`). So for that sid, A-husk and B never find a bundle.
  They loop on `WAIT for the move's bundle` (`__main__.py:1350-1356`).
- **Who actually rescues.** No strand results, because other lanes cover it:
  - post-`/exit`: the watcher's `rcy_debt_settle` (`handoff-fire.sh:11424-11437`) and the poller's
    resume-debt sweep (`lr-reset-poller.sh:1980`);
  - pre-`/exit` husk: the poller's husk lane (`rq_stale_reason` rc 2, `:1310-1340`).
- **Change.**
  - Correct §3.7 and §5 row 18.
  - Either teach `bundle_launcher` to accept a `placed_by:"self"` MANIFEST for the same sid and
    target once no live self claim exists, or close that record with "moved by self" so it stops
    re-arming.
  - Add a T-R5 for whichever is chosen.

**C10 (medium). Two gaps in the seat ledger's weight check.**

- **A slot mid-write.** A slot that is created but not yet written must count at the maximum weight
  (KMAX−1), never 0. Otherwise two movers that each read the other mid-write both pass. T-S2's mutant
  does not cover that window; add a delayed-write arm.
- **A second spelling of capacity.** `capacity(acct)` re-derives `k_src`/`k_cap` from the usage rows.
  That is the drift §3.5 itself warns against. Add a parity test against claude-accounts' own `k_cap`
  and `k_eff` per account, or take capacity from the router.

**C11 (medium). A placement made before the self claim keeps charging.**

- **The cause.** A record that was already PLANNED when the worker claimed stays PLANNED.
  `_own_and_charge` logs `own … held` every pass (`__main__.py:1058-1083`), and `phantom_rows` keeps
  refreshing its phantom on the reconciler's target (`plan.py:474-497`). The self move charges a
  different account.
- **The effect.** In a herd, that is a double charge that can exclude accounts from the router.
- **Change.** Skip `ctx.self_driven` in `_own_and_charge` and `phantom_rows`, and void that record's
  assign id once.

**C12 (medium). The kick is lost when a worker dies early.** This confirms efficacy R11.

- **A further trigger.** The live layer is a farm of per-file symlinks
  (`ls -la ~/.claude/scripts/limit-recover/lr_recon/` → `act.py -> …/lr_recon/act.py`). A deploy that
  links `selfrec.py` but not yet `seats.py` therefore crashes every worker on import, after the hook
  has suppressed the kick.
- **Change.** Besides R11's bootstrap, the hook checks that every module file the worker imports
  exists (`-f`), and that python is executable (`-x`), before it treats a spawn as `act`.

**C13 (low). Hook and test details.**

- State whether ARM 4 sits inside the `CC_SF_REQUEST` / `.request-off` guard (`:555-560`). Today the
  sketch is ambiguous.
- Add `# shellcheck disable=SC2016` above the perl program, as the hook already does at `:361`.
  Without it, the "bare shellcheck" ratchet in §6 fails.
- Add an armed-footprint pin shaped like SA9, naming `self-recover/{latch,logs}` as the only new
  writes.
- T-H6's "returns in under 2 s" is a wall-clock assertion under 15-40/core. Assert ordering instead:
  the hook has returned while the sleeper's marker file is still absent.

**C14 (low). Bounded state and log hygiene.**

- **GC.** Garbage-collect `latch/`, `logs/`, `cool/` and `work/` on the hook's own TTL. Today nothing
  bounds them.
- **Concurrent rotation.** `store.append_bounded` rotates with an unlocked `os.replace`
  (`store.py:588-600`), which is safe for one writer only. With N workers, two rotations can overwrite
  `events.jsonl.1`. Use per-worker files or a `flock` around the rotation.
- **The lstart join.** Normalise both sides of the `watcher_lstart` join. The row and the watcher
  record keep `ps`'s double space on days 1-9 (`handoff-fire.sh:1010`, `:19994`), while `fence.lstart_norm`
  collapses it.
- **A misleading page.** With `--no-replace`, `HELD:no-shell` pages "It stays where it is"
  (`lr-handoff.sh:1418`), even though the reconciler will then R the pane. Suppress that page for
  `LR_PLACED_BY=self`.
- **Doc.** Yielding on `lapsed` means G2 does not cover a sid with a stale `owned/` file while the
  daemon is down. So "survives the daemon being down" (§10 item 3) holds only for never-owned sids.

**Also confirmed from my own reads:**
- **R1.** Re-stamping the claim to the watcher's `(pid, lstart)` is the cleaner invariant; follow it.
- **R2.** The reconciler releases its boot slot when no BOOTING process lives (`__main__.py:1124-1129`).
- **R5.** `:1607-1610` sits inside lr-handoff's own probe branch (`:1590-1611`).

### Why the conviction drops to 45%

- C1-C5 each break a guarantee the design states as already holding:
  - one owner per session (C2, C3, C4);
  - the reconciler yields (C5);
  - the code that runs is the live code (C1).
- C6 breaks the box-wide boot bound for every lane, not only G2.
- None needs a new mechanism: each fix is local and testable.
- With C1-C8 applied, plus efficacy R1-R5, I would put conviction back at about 60%.

