# A4: identity-clean hybrid. Zero-restart billing move (M6 lane) + deferred re-home at natural restart boundaries

Architect slot A4-identity-clean-hybrid, 2026-10-25. Read-only except this file. No Claude Code launched, no pane
touched, no keychain secret read, no settings.json edit, no git write. Labels: **[M]** measured (command named),
**[C]** cited from a note (file + section/offset), **[E]** estimated (method named), **[I]** inference.

---

## 0. Answer first

1. **Mechanism.** Every session is launched with its own credential lane (`CLAUDE_SECURESTORAGE_CONFIG_DIR=<lane>`, M6),
   holding an access-only mirror (refreshToken null) of its billing account's token. A move is one journaled write to that lane.
   The client adopts the new bearer at its next client build, which is the next API call of the turn: P4, P5, P6 measured;
   G3 §2 confirms that every inference path runs `j7→Pl→wA` before each request. Nothing exits, so there are 0 forks, 0 lost turns,
   0 killed background tasks, and the change takes effect within 1 API call.
2. **Identity.** The lane cannot move `metadata.user_id.account_uuid`, `oauthAccount`, or the transcript store (P6, G4, G2 §c).
   The hybrid **re-homes** the session at the next restart it was going to have anyway (recycle, crash or reconciler revival,
   reboot mass resume, upgrade respawn, operator `/exit` then resume). At that restart it is relaunched on the config dir of its
   *current billing* account, with a fresh lane on that same account. Bearer, body identity and store then agree again. The
   re-home adds no restart. Billing has not changed, so the prompt cache stays warm.
3. **The same boundary arms the lane.** M6 and M7 both need a launch-time env var, so a session started without a lane cannot be
   moved without a restart (S05 §4.4, G2 §b). The natural boundary that re-homes a session also arms it. One restart the session
   would have had anyway pays for both.
4. **M6, not M7.** The lane is client-native. It moves inference and every side endpoint that reads `mn()`: usage, policy limits,
   bridge (G3 §2 rows 5a-5f). It has no proxy single point of failure and no P2 degradation. Its S08 exposure is Low-Moderate
   (60%), against Moderate-High (45-70%) for M7. M7's mismatch is permanent: G4 M5 says "body account_uuid is permanently the launch
   account" unless the body is rewritten, which breaks `cch` (S03 (2)). The re-home cannot fix M7's mismatch. It can fix M6's.
5. **How long a session stays in mismatch** (move → next natural restart):
   - **[E]** median ≈ **17 h**, p90 ≈ **47 h**, mean ≈ **22 h**. This is the renewal-theory residual of the measured
     inter-restart gaps.
   - **[M]** Live process ages (age and residual life are equidistributed in a stationary renewal): p50 2.7 h, p90 25 h,
     max 83 h. Excluding processes that tonight's move lane itself restarted: p50 ≈ 6 h, p90 ≈ 29 h.
   - The always-busy cohort (15f652bd, 2b3becea, 7396b781, 502bd860, 2a707a01) is 5.7-25 h old. Their restarts come only from a
     crash, a reboot or the operator. Reboot-scale mass resumes happened 5 times in 24 days.

   Mismatch is therefore the *normal* state of a moved session for most of a day. So billing, not config dir, must be the
   first-class attribution key (§9).
6. **Tonight's un-armed fleet** (all ~36 live sessions predate lanes) cannot be moved zero-restart by M6. §7.4 gives a transitional
   whole-dir arm, Arm T: an access-only park of `next`'s home item. It is the only zero-restart lever for un-armed sessions, and the
   operator must rule on it (D2).

---

## 1. Inputs used

D-brief (all), P-probes P1-P9, G1, G2, G3, G4, S03 §(1)-(2), S05 §1-5, S06 §1-4, S07 §1-6, S08 §4, S12 §1-6, S14 §1-7,
`docs/research/account-rotation-100p-2026-10-24/REPORT.md` §4 (the rebalance arm C1-C9), `lib/claude-launcher.zsh`,
`bin/claude-accounts:1936-1990` (heal), `hooks/session-register.sh:223`, `hooks/mailbox-wake-arm.sh` and
`hooks/net-recover-arm.sh` headers, and `/tmp/mtam/cc293-src.js` (offsets below). I1/I2 notes are absent from the directory
(`ls notes/`, [M]), so M14 stays unverified.

New measurements in this slot (all read-only, `timeout ≤60`):

| # | Command | Result |
|---|---|---|
| A | `python3 -I -c …` join of `/tmp/mtam/S06/ps-once.txt` (07:16:16Z) with `~/.claude/cc-registry/*.json` (pid + lstart, UTC→CDT) | 33 live rows. Process age h: p10 0.38, p25 0.61, **p50 2.73**, p75 6.91, **p90 25.1**, max 83.1, mean 9.6. 13 rows <1 h (12 of them restarted by tonight's move batches A/C) |
| B | `python3 -I -c …` over `~/.reso/limit-recover/recon/launch.log` (680 rows, 09-29 → 10-25) | Launcher-driven (re)starts: boot-resume-launch 274, lr-fire-resume 199, reso-resume-one 106, recon-R/A/B/C spawn 62, cc-resume-debt 10, cc-lr 8, poller 8, lr-upgrade 1. 253 sids, 149 with ≥2 starts |
| C | same, per-sid gaps ≥ 1 h (drops retry clusters) | n=135; p25 5.4 h, **p50 14.6 h**, p75 38.8 h, **p90 52.9 h**, max 121.8 h; mean 24.1 h |
| D | renewal residual from C: E[X²]/2E[X], and quantiles of (1−F(t))/E[X] | **mean residual 22.0 h; median 17.4 h; p90 47.1 h** [E: stationary renewal; it ignores operator-typed restarts, so it is an upper-side estimate] |
| E | boot-resume clusters (>1 h apart) in launch.log | mass resumes 10-01 (160), 10-02 (20), 10-05 (16), 10-18 (49), 10-21 (30). Machine-scale restarts about every 5 days |
| F | `grep -n` `hooks/session-register.sh:223` | registry `account` = `basename(CLAUDE_CONFIG_DIR)`, so the fleet's account stamp is the **home** dir |
| G | `bin/claude-accounts:1936-1990` | `heal()` refreshes via `claude auth login` with `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`, only when the account has **zero** live sessions; env is `os.environ.copy()` with `CLAUDE_CONFIG_DIR` set (the lane var is **not** scrubbed; see hazard H-16) |
| H | cc293 @12383907 (`xnn`) | the only server-driven identity restamp: header `x-cc-atis-current` ≠ cached pin → `refreshBootstrapData` → `ot()`. It is gated on flag `tengu_expressive_whistle` (default **false**), main querySource only, ≥300 s min interval. Not an external lever |
| I | cc293 @18097318 | `/goal` pause strings: `usage_limit_waiting: "continues automatically when it resets"`, `rate_limited: "send a message to retry"`. A wake message resumes a paused goal |
| J | `git grep -l` config-dir patterns in bin/scripts/hooks/lib (excluding md/tests) | 253 code files mention a config dir; the axis-08 count of files that key the *account* on it is 68 (`08-zero-restart.md:471`) |

---

## 2. Mechanism

### 2.1 The lane (billing plane)

- At launch every session gets `CLAUDE_SECURESTORAGE_CONFIG_DIR=$HOME/.reso/lanes/<lane-id>` (dir 0700).
  `uw()` and `FF()` read it on every call with no memo (G2 §a, @3737607). The lane therefore governs:
  - the keychain item `Claude Code-credentials-<sha256(lane)[:8]>`;
  - `<lane>/.credentials.json`;
  - the `wA` mtime probe (@4658522);
  - every lock (`.storage-write`, `.oauth_refresh`, `mcp-refresh-*`).
- The lane binds the whole local process tree:
  - in-process subagents and teammates (shared `process.env`);
  - pane teammates (`H()` forwards the var even when empty, @36021704);
  - `--bg` jobs (`GWe`/`providerEnv` snapshot, @9569145, @16378899);
  - MCP and Bash children (`as()` strips it only under `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`) (G2 §b).
- `CLAUDE_CONFIG_DIR` is unchanged. Transcripts, `sessions/`, `.claude.json` and the bg supervisor stay with the home dir
  (S14 §1, S12 §1).
- **Lane contents: an access-only mirror.**
  - `claudeAiOauth` = {accessToken and expiresAt of the billing account's *current* token, `refreshToken: null` (never `""`,
    S14 §7.2), scopes, subscriptionType, rateLimitTier}.
  - The billing account's home keychain item stays the **only** holder of its refresh token. A lane therefore never refreshes:
    `Pl` returns `not_needed`/`no_refresh_token` before any lock or POST (S14 §7). It can never trigger `invalid_grant`/`jhr`
    on any store (G1 §5(c)).
  - This is the same token, not a setup-token, so its scopes are the real ones (`user:profile`, `user:inference`, …). Usage,
    profile and policy calls keep working (contrast S13 and ruling a90e1ac2597e).
- **Swap = one journaled write:**
  1. Under the lane's `.storage-write.lock`, rewrite `claudeAiOauth` in the lane's keychain item.
  2. Atomically replace `<lane>/.credentials.json` (see D1 for its content). The `wA` stat then sees a new mtime and runs
     `ox()` (memo + 30 s keychain cache cleared) on the next `Pl` (S14 §5-6).
  3. The next `EN()` client build copies the new token (G3 §1). P4 measured adoption at call 2, ≈4.5 s after the rewrite.

### 2.2 Re-home (identity plane)

- **Where `account_uuid` comes from.** `metadata.user_id.account_uuid = iL()?.accountUuid || Mn()?.accountUuid` is computed on
  every request build (`KWe` @8876312).
  - `iL()` is stamped only by a bootstrap fetch (`ot()` @18239236).
  - `Mn()` is `<CLAUDE_CONFIG_DIR>/.claude.json` `oauthAccount`.
  - Nothing on a credential-adopt path restamps either one (G4 table). P6 measured the stale value on every post-swap call.
- **What re-homing does.** At the session's next natural restart, the relauncher resolves `dir(billing(S))`. It cold-transplants
  the transcript there (the source is provably dead at a boundary) and launches `--resume <sid>` with
  `CLAUDE_CONFIG_DIR=dir(billing)` and a fresh lane on the same account.
  - The bootstrap at startup stamps the billing account (G4 @18239236).
  - `Mn()` reads the billing dir's `oauthAccount`.
  - Bearer, `account_uuid`, `oauthAccount`, transcript store, `sessions/` registry and bg supervisor now all name one account.
- **Re-home is billing-neutral.** The session was already drawing from that account, so the conversation prefix is warm in that
  org's cache (P3/P5 cache rows). The resume pays no cache rewrite beyond any TTL lapse the restart itself causes.

### 2.3 Why the hybrid, rather than either half alone

- **Lane only** leaves the mismatch for the session's whole life (G4 M1, P6). It also leaves the transcript in the home store
  forever, so the ~68 config-dir consumers drift further every time the session moves.
- **Re-home only** is the incumbent M1. It waits for a restart, and busy sessions never get one (S06: 0 of 7 busy/goal rows moved
  tonight).
- **The hybrid** puts the latency-critical half (billing) on a zero-restart write. The identity half waits for a boundary that
  already exists, where it costs nothing.

---

## 3. M6 or M7? M6

| Axis | M6 lane | M7 proxy | Source |
|---|---|---|---|
| Mid-turn, ≤1 API call | yes (P4, P5, P6) | yes (P3) | P-probes |
| Needs launch-time env | yes (`CLAUDE_SECURESTORAGE_CONFIG_DIR`) | yes (`ANTHROPIC_BASE_URL`) | S05 §4.4, S03 (1) |
| Side endpoints (usage, policy_limits, bridge, GrowthBook) | follow the shared `mn()` cache, so they move too | bypass the proxy and stay on the old account (S03 (d)) | G3 §2 rows 5a-5f |
| Feature degradation | none (first-party host) | tool search and account identity off unless `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL=1` (internal); `Of()` features (threads, RC) off regardless | P2, S03 |
| Body/bearer identity | mismatch until re-home, then **closed** | mismatch **permanent**; fixing it means rewriting the body, which breaks the `cch` hash | G4 M5, S03 (2) |
| SPOF | none (per-session store; broker down = no new moves, live sessions unaffected) | every inference request transits one local process; a dead hop is retried 11-12× and then fails (P1) | P1 |
| Policy (S08 §4) | Low-Moderate, 60% "not a breach" | Moderate-High, 45% clear violation today, 70% citable | S08 |
| Refresh hazard | none (access-only mirror) | none (the proxy injects; client store untouched) | S14 §7 |
| Prior-art incident | none found | TeamClaude #529 ban 54 min after adding a pooled account (S09) | brief |

M7 wins only on "no client store write". The identity-clean philosophy needs a mismatch that a restart can close, and M7's cannot
close without a body rewrite. **M6.**

---

## 4. Components (by path)

### 4.1 New files

| Path | Role |
|---|---|
| `bin/cc-lane` | CLI: `arm`, `swap --sid S --to B`, `revert [--all]`, `status`, `verify`, `gc`, `park/unpark` (Arm T). Thin wrapper over `lr_lane` |
| `scripts/limit-recover/lr_lane/store.py` | Lane store I/O: CC-compatible proper-lockfile on `<lane>/.storage-write.lock` (mkdir lock, stale 15 s, S14 §2); read-modify-write of the lane blob that replaces only `claudeAiOauth` (and the `mcpOAuth` mirror, D4); `security -i add-generic-password -U` write; atomic mirror/beacon rename; `fingerprint()` = sha256[:16], never the token |
| `scripts/limit-recover/lr_lane/ledger.py` | Append-only `~/.reso/lanes/ledger.jsonl` (write-ahead) plus the materialized `~/.reso/lanes/<lane>/state.json`. Row: `{t, lane, sids[], pid, lstart, home, billing, prev_billing, cause, move_id, state: prepared/committed/proved/aborted/reverted, fp}` |
| `scripts/limit-recover/lr_lane/broker.py` | Single-flight daemon (launchd KeepAlive). Drains `~/.reso/lanes/requests/`. Its **mirror refresher** watches `~/Library/Keychains/login.keychain-db` mtime via kqueue, re-fingerprints the 4 home items, and re-mirrors every lane whose billing account's token changed. Its **expiry guard** schedules `claude-accounts` heal for an account with zero home holders 15 min before its token expires |
| `scripts/limit-recover/lr_lane/proof.py` | Disk-truth move verdict (§11 AC1-AC5) |
| `scripts/limit-recover/lr_lane/rehome.py` | `resolve(sid) → (cfg_dir, lane_env, transplant_needed)` for every relauncher; cold transplant through `lr-transplant.sh --cold` after `proctable` proves zero holders |
| `lib/cc-lane.sh` | Shell helper for every launcher: `cc_lane_env <cfg> [<sid>]` exports `CLAUDE_SECURESTORAGE_CONFIG_DIR` after `cc-lane arm`. It is a no-op under `CC_LANE=off` |
| `scripts/lib/billing.py`, `lib/billing.sh`, `bin/cc-billing` | The one attribution API (§9): `billing_of(sid|pid, t=None)`, `home_of(sid)`, `sessions_billed_to(acct)`, `mismatched()` |
| `hooks/lane-bind.sh` | `SessionStart` (sync, fast): reads its own `CLAUDE_SECURESTORAGE_CONFIG_DIR` and the stdin `session_id`, and appends the binding `{lane, sid, pid, lstart}` to `<lane>/bind.jsonl`. Re-fires on /clear and resume, so one lane can bind successive sids |
| `scripts/limit-recover/lr_recon/proctable.py` | The S07 ps-free census (§10), plus `env_keys(pid, {CLAUDE_CONFIG_DIR, CLAUDE_SECURESTORAGE_CONFIG_DIR})` from the KERN_PROCARGS2 env block. Only those two keys are extracted, and nothing is kept or logged |
| `launchd/staged/com.reso.lane-broker.plist` | Broker job (KeepAlive; WatchPaths `~/.reso/lanes/requests`, ThrottleInterval 2), with a pending-activation script |
| `migrations/00NN-lane-bind-hook.sh` | Numbered migration that the operator runs to register `hooks/lane-bind.sh` (agents never edit settings.json) |

### 4.2 Changed files

| Path | Change |
|---|---|
| `lib/claude-launcher.zsh` | Every route (routed, pinned, `claude1..4`, `--resume`) calls `cc_lane_env "$CLAUDE_CONFIG_DIR"` before `_claude_pinned`. On `--resume <sid>`/`-r <sid>`, `rehome.resolve` may swap the config dir and cold-transplant first (D5). `-c/--continue` is never re-homed (the sid is unknowable before launch) |
| `scripts/limit-recover/lr-fire-resume.sh`, `bin/reso-resume-one`, `scripts/boot-resume-launch.sh`, `scripts/boot-resume.sh`, `scripts/handoff-fire.sh` (launcher writer `recycle_fire_armed`), `bin/kitty-split-launch.sh` | Source `lib/cc-lane.sh`. The resume config dir becomes `rehome.resolve(sid).cfg`, not the registry account. Each **sets** the lane explicitly and never inherits one (H-15) |
| `bin/cc-lr` (`cl_move_rows` :1284-1454, `cmd_move` :1599) | New disposition `armed` → act `swap` (no wait). `unarmed` → `wait:boundary` (re-home/arm at next restart) or `hold:unarmed`. Busy kinds (`mid-turn`, `subagents-in-flight`, `background-job`, `goal-live`, `teammate`, `draft`, `self`) no longer gate an armed row |
| `scripts/limit-recover/lr-move-worker.sh` | For `act=swap`: W2/W2d/W3/kernel/pre-actuate stages are skipped. W5 = `cc-lane swap`; W6 = `proof.py`. The restart path stays only for `--restart` (operator-explicit) |
| `scripts/limit-recover/lr-move-lib.sh` (`lr_move_verdict` :121-225) | P2 becomes P2′ (lane fingerprint = target account's fp). P3 becomes P3′ (exactly one live transcript, in any store). P5 is unchanged. New verdict vocabulary: `SWAPPED`, `SWAP-UNPROVEN`, `SWAP-REVERTED` |
| `scripts/limit-recover/lr-upgrade.sh` (`lru_switch_census` :1053-1182) | Census columns gain `lane`, `billing`, `home`. `cfg` comes from proctable env keys, not argv guesses |
| `scripts/limit-recover/lr_recon/observe.py` (:161-202) | `read_ps` → `proctable.read_table` (S07 §6 fallback order). Lane/env keys feed `bind` |
| `scripts/limit-recover/lr_recon/facts.py`, `act.py`, `settle.py` | A `rate_limit` tail is attributed to `billing_of(sid, t_err)`, not the config dir. For an armed limited session the actuator is `swap + wake` (§7.2), not relaunch. The relaunch path calls `rehome.resolve` |
| `scripts/limit-recover/lr-shed.py`, `scripts/limit-recover/lr_burn.py` (C2/C3 of the 100p REPORT) | Burn and strand are attributed by billing. The sink/donor arm actuates `cc-lane swap` for armed rows (§7.3) |
| `bin/claude-accounts` | `--assign/--unassign` on a swap. `heal()` and every child-`claude` spawn scrub `CLAUDE_SECURESTORAGE_CONFIG_DIR` (H-16). A local pass marks a parked item `parked` instead of healing or flagging it. Per-account `sessions_billed` comes from `billing.py` |
| `bin/cc-relogin`, `scripts/relogin-desharing-activate.sh` | Scrub the lane var. Refuse any `~/.reso/lanes/*` path |
| `hooks/session-register.sh` (:223) | Registry row gains `lane`. `account` keeps meaning **home**, and a `billing` field is added at write time from `billing.sh` |
| `statusline.sh` | Shows `home→billing` when they differ. Records `rl5/rl7` (C9) for AC5 |
| `scripts/limit-recover/lr-transplant.sh` | `--cold`: the source holder is proven absent by proctable (pid/lstart and argv `--resume <sid>`), and the copy runs without a source exit. Custody, lock and tombstone semantics are kept (R1, R3) |

---

## 5. Data flow

```
 operator / rebalance arm / reconciler
        │  move intent {sid|lane, to, origin, intent_ok}
        ▼
 ~/.reso/lanes/requests/<id>.json ──launchd WatchPaths──▶ lane-broker (single flight)
        │ admission: intent ✓, router fail-closed ✓, claim(pid,lstart) ✓, armed ✓ (proctable env key)
        │ ledger.prepared ──▶ read B home item (fp only logged) ──▶ lock lane ──▶ write lane item ──▶ rename beacon
        │ ledger.committed(t_c, fp_B)
        ▼
 running claude (same pid): next EN() → j7→Pl→wA sees new mtime → ox() → mn() = B → request billed B
        │ transcript appends assistant record (requestId) after t_c
        ▼
 proof.py: fp(lane)==fp_B ∧ first post-t_c request present ∧ 1 holder ∧ linear transcript ──▶ ledger.proved
        │
        ▼
 billing.py view: billing(sid)=B from t_c; home(sid)=A until re-home
        │
 natural boundary (process gone; proctable proves 0 holders)
        ▼
 relauncher → rehome.resolve(sid): cfg=dir(B), cold transplant A→B store, new lane mirror(B)
        │ launch --resume sid under dir(B) + lane ──▶ bootstrap stamps B; .claude.json(B) ──▶ identity aligned
        ▼
 ledger.rehomed ; registry account=B ; mismatch closed
```

Side flows:
- **Mirror refresher.** Keychain DB mtime changes → re-fingerprint the 4 home items → each lane whose billing fp went stale is
  re-mirrored (same write as a swap; cause `refresh-mirror`).
- **GC.** A lane whose bound (pid, lstart) is gone on 2 consecutive proctable passes gets its keychain item deleted and its dir
  removed, and its ledger row is closed.

---

## 6. Move protocol (order → billing change), with timings

Timings are **[E]**, built from: S07 (in-process census 3.3 ms; claude-family args 9 ms); the 100p REPORT C6(a) (WatchPaths kick
1-2 s); S14 §2 (keychain `security` subprocess, 2 s timeout); P4 (adoption at the next call); S06 §3 (tool-exec p50 3 s,
p90 477 s).

| Step | Actor | What | Bound | Typical |
|---|---|---|---|---|
| 0 | caller | `cc-lr move --sid S --to B` (or rebal/recon) writes intent + request file | — | <50 ms |
| 1 | launchd | WatchPaths kicks the broker | 2 s throttle | 1-2 s |
| 2 | broker | Admission: intent valid (R11); router `--rank general` from cache, fail-closed (R11); per-session claim keyed (pid, lstart) (R7); proctable: exactly 1 holder of S (R1), process env carries a lane, lane bound to S (`bind.jsonl`); B not `walled`/`unknown`; cooldown (§7.3) | 5 s | <0.5 s |
| 3 | broker | `ledger.prepared` (fsync) **before any write** (R6) | — | <10 ms |
| 4 | broker | Read B's home item (one `security find-generic-password -w`, held in memory only); build the access-only blob; refuse if B's token expires in <10 min (wait for refresh or heal, D9) | 2 s timeout ×2 | 50-300 ms |
| 5 | broker | Take `<lane>/.storage-write.lock` (proper-lockfile, CC's own order; S14 §2). Read the lane blob; **refuse** if it carries a non-null refreshToken (`lane-owned`, H-12). Replace `claudeAiOauth` and keep other keys. `security -i add-generic-password -U`. Atomically rename the mirror/beacon (D1). Unlock | 5 s | 0.1-2 s |
| 6 | broker | `ledger.committed {t_c = beacon mtime, fp_B}`; `claude-accounts --assign B --unassign A --src lane` | — | <0.2 s |
| 7 | session | The in-flight request, if any, finishes on A (G3 §3). The **next** client build (tool-loop step, subagent, classifier, compact) runs `wA` and sends B's bearer | ≤1 API call | wall = remaining tool time: p50 3 s, p90 477 s [C S06 §3] |
| 8 | proof.py | Polls the transcript tail with the 400-line reader `lru_at_rest` uses, and proctable. `proved` when AC1-AC4 hold | 600 s, then `SWAP-UNPROVEN` (loud, not reverted) | seconds after step 7 |

**Order → billing change: ≈2-5 s of mover time [E]**, then the session's next request. In API-call units the change is always
the first request built after `t_c`, which is what the DoD requires.

**Two narrow exceptions (residual, §14):**
- **cache_touch keepalive.** It caches its client for ≤240 s (`jLn` @9777402, G3 4b), so it can POST one keepalive on A's bearer.
  That is not a generation.
- **A Khe call sitting in 429/5xx backoff.** It reuses its client until that call ends (G3 §1). It is one call by definition.

**Revert** is the same write with `to = home(S)`. It is idempotent, and `cc-lane revert --all` is the emergency path (§12).

---

## 7. Flows

### 7.1 Arming and re-home at natural boundaries

| Boundary | Today's relauncher | Change |
|---|---|---|
| B1 operator `/exit`, then `claude --resume <sid>` | `claude()` router passes `--resume` through to `_claude_pinned` | `rehome.resolve(sid)`: dir(billing). Cold transplant if the store differs, arm lane (D5) |
| B2 reconciler revival / crash revival (recon-A/B/R/C, reso-resume-one, cc-resume-debt) | lr_recon `act.py` → `lr-fire-resume.sh` | resume cfg = `rehome.resolve` |
| B3 reboot mass resume (`boot-resume-launch`, 274 starts in 26 d [M B]) | `scripts/boot-resume-launch.sh` | the same. Every live session re-homes at once, so a reboot closes every mismatch |
| B4 upgrade respawn (`lr-upgrade`) | lr-upgrade queue | the same |
| B5 `/handoff` recycle (`handoff-fire --recycle`) | handoff-fire launcher | the launcher writes `CLAUDE_CONFIG_DIR=dir(billing)` + lane |
| B6 idle-park (optional, D3) | the incumbent move lane, used only for armed + mismatched sessions at rest ≥ 30 min (`--cold-only`) | it re-homes billing-neutrally. The incumbent's 8/8 MOVED record on idle rows since 10-19 [C S05 §3] applies. This boundary exists because some sessions do idle (S06: tonight's idle rows moved 8/8) |
| B7 `--bg` supervisor respawn/revival | supervisor forces its own `CLAUDE_CONFIG_DIR` (S12 §6) | **no re-home** (it would create two writers across supervisors, S12 §3). Billing still follows the lane via `providerEnv` (G2 §b). The identity mismatch persists until an operator moves the job |

Re-home preconditions, all fail-closed:
- proctable: zero live holders of the sid, measured as a pid/lstart match plus argv `--resume <sid>`, on 2 passes ≥1 s apart (R1, R5);
- no open move claim on the sid;
- billing(S) ≠ home(S), otherwise there is nothing to re-home and the session is simply armed;
- transcript sha-verified after the copy (R3);
- the target store differs physically (`lr-transplant.sh:138-142` refuses the next/`~/.claude` shared store; that case needs no copy).

Re-home writes `ledger.rehomed` and the registry row then carries `account = billing`. If the launch fails, the existing
STRANDED/revival machinery retries **on the target**. The source copy is retired only on confirm, so an abort leaves the
session resumable from the source.

### 7.2 Limit recovery

1. **Pre-wall (preferred).** The rebalance controller (the shed tick, not lr_recon, because `facts.py:12-13` "usage % is never a
   limit signal" stays true; D7) watches each account's 5 h and 7 d landing (`--rebal-band`). An account projected to wall within
   its horizon has its highest-burn armed sessions swapped to accounts with headroom. Busy sessions move in place, so the wall is
   never hit.
2. **Reactive.**
   1. lr_recon sees a `rate_limit` tail (existing detection).
   2. It attributes the wall to `billing_of(sid, t_err)`. This fixes C1's "X un-capped" defect (S05 R9).
   3. Being the single actuator (R7), it requests `swap → B` (router pick).
   4. After `committed` it **wakes** the session by sending mail to the sid. The `mailbox-wake-arm.sh` / `net-recover-arm.sh`
      watchers are `asyncRewake` hooks armed *before* the death; an api-error turn runs no Stop hook, but a pre-armed watcher's exit 2
      is honoured afterwards (`hooks/net-recover-arm.sh` header, proof `docs/research/api-error-rewake-proof-2026-09.md`). The
      synthesized turn goes out on B.
   5. A `/goal` paused in `usage_limit_waiting` resumes on any message ([M I]).

   **No pane typing, no `/exit`.** If no watcher is armed (`<sid>` beat shows none), the row is `hold:no-wake`, and the incumbent
   typed nudge stays the fallback (S05 "owes a turn").
3. **Recovery latency target:** detection pass + 2-5 s swap + wake. Today the median is 81 min (S05 §3, n=19).

### 7.3 Strand-aware rebalance (the 100p REPORT's C1-C9 with a lane actuator)

- **Unchanged:** C1 `--rebal-band` (sink, donor, corrected strand), C2 `lr_burn.py` (attribution switched to billing), C6 event
  scheduling, C8 readout.
- **C3 sink arm, revised holds.**
  - These holds vanish for armed rows (they existed only because of exit+relaunch; S05 §2 class V): mid-turn, background-job,
    subagents, goal-live, drafts, focused/operator panes, `--slots`.
  - These stay:
    - `unarmed` → wait for a boundary;
    - `duplicate` / `bg-split` (R1);
    - limited / being-recovered (the reconciler owns it, R7);
    - intent and router (R11);
    - team: a lead's lane is shared by its pane teammates (G2 §b, `H()`), so the planner moves **the lane**, i.e. the whole team,
      and prices the team's summed burn (R13).
  - **Per-move cost gate.** Each move re-creates the conversation prefix once on the new org (P3/P5). Historically that cost
    273K-479K cache-write tokens, a median of 0.109 pp (S05 §3). A row moves only if `v = b_wk × min(sink_h, 96) ≥ 10 × cost_pp`,
    with a 6 h per-session cooldown (kept from C3).
  - **Donor arm** (deferred in the 100p REPORT): now cheap, because a move is a write. It can ship with the sink arm, behind its own
    switch.
- **Stop rules are kept:** moved burn ≤ 0.8 × capacity, sink 7 d landing ≤ 97%, 5 h landing ≤ 80%, overshoot breaker
  (`strand_audit`). No move-back after reset.
- **Re-home interplay.** The rebalance never restarts anything. Mismatches it creates are closed at B1-B6 by §7.1.

### 7.4 Arm T: transitional whole-dir move for un-armed sessions (tonight's case; D2)

All 36 live sessions predate lanes. The only zero-restart lever for them is the home item itself (M5). Done access-only, it avoids
C1's rotation hazard:

1. Copy `next`'s home blob (with its refresh token) into a parking keychain item `reso-lane-park-next` (`security -U`; not a file).
   Its grant now lives in exactly one item, the park (R8).
2. Overwrite `next`'s home item `claudeAiOauth` with next4's **access-only** mirror. `~/.claude-next` has no `.credentials.json`
   (S14 §5, G1 §3), so the running `next` sessions run `Jf` on every `Pl` and adopt within ≤30 s of the PK cache, at their next
   request (S14 §6a).
3. While parked:
   - claude-accounts marks `next` `parked` (no heal, no relogin page);
   - the mirror refresher keeps the access-only copy current;
   - the router excludes `next` as a target.
4. Unpark when `billing.sessions_billed_to(park)` is empty, i.e. every parked session re-homed at a boundary, or on operator
   command:
   1. lock;
   2. write the parked blob back;
   3. delete the park item;
   4. `ledger.unparked`.

   The parked refresh token was never used, so it is still valid unless past `refreshTokenExpiresAt`: `next`'s is 11-19
   (G1 §2) [C].

Limits:
- It moves **every** session on that dir, including idle ones.
- Do not apply it to `~/.claude-tertiary` while its stale `.credentials.json` exists: that file pins the memo, so a keychain-only
  change is not adopted until a 401 or expiry (S14 §5, G1 §3). Rename the file first, as an operator action.
- The identity mismatch is the same as with lanes.

---

## 8. Measured mismatch exposure (philosophy requirement)

| Population | Mismatch duration after a move (= time to next natural restart) | Basis |
|---|---|---|
| Fleet, renewal estimate | median 17.4 h, p90 47.1 h, mean 22.0 h | [E] residual of the launch.log gap distribution (n=135 gaps ≥1 h) [M C-D]. It omits operator-typed restarts, so the true value is somewhat shorter |
| Fleet, live ages 07:16Z | p50 2.7 h, p90 25 h, max 83 h (all 33). Excluding the 12 processes tonight's move lane restarted: p50 ≈ 6 h, p90 ≈ 29 h | [M A]. In a stationary renewal, age ≡ residual in distribution |
| Always-busy cohort | 5.7-25.1 h old now (15f652bd 5.7, 2b3becea 6.9, 7396b781 10.0, 502bd860 10.9, 2a707a01 25.1). None idles (S06 §3), so B6 never fires; B2-B4 only | [M A] |
| Upper bound | the reboot cadence: mass resumes on 10-01, 10-02, 10-05, 10-18 and 10-21 (≈5 d mean) | [M E] |
| `--bg` daemon sessions | until operator action (B7) | S12 §6 |

Fleet share in mismatch at steady state ≈ min(1, λ_move × 22 h) [E: Little's law]. With the rebalance's 6 h cooldown and a sink
open, a frequently moved session spends most of its life mismatched.

Consequences:
- (a) Attribution must key on billing (§9).
- (b) Client-side UI derived from `Mn().accountUuid` is wrong during the window. The usage meter shows B's numbers under A's
  uuid, and the cache may be discarded (S03 §3, "g7n resets on uuid mismatch"). This is cosmetic.
- (c) Server-visible metadata shows A's uuid on B's bearer, which S08 §4 M3 says "raises the detection profile". The re-home bounds
  the window. It cannot remove it.

---

## 9. Attribution model for the ~68 config-dir-keyed files

### 9.1 Three accounts per session, one source of truth

| Name | Definition | Changes when | Read from |
|---|---|---|---|
| **home(S)** | the account whose config dir the process runs under (`CLAUDE_CONFIG_DIR`) | launch / re-home only | proctable env key, or the registry `account` (session-register.sh:223) |
| **billing(S, t)** | the account whose token is in S's lane at time t | every committed swap or mirror | `ledger.jsonl` (time-aware), cross-checked against the lane item fp |
| **identity(S)** | the `metadata.account_uuid` the client sends | = home(S), always (P6, G4) | derived; never stored separately |

**mismatch(S)** ⇔ billing ≠ home. "Unknown" is a value (R5): the ledger and the lane fp disagree, the lane is unreadable, or the
process carries no lane. Every consumer must branch on it. Nothing may default it to home.

### 9.2 Which consumers key on which

| Class (example paths) | Key on | Why |
|---|---|---|
| Quota and limit attribution: router `--route/--assign` (`bin/claude-accounts`), lr_recon `facts.py` limit owner, shed/rebal (`lr-shed.py`, `lr_burn.py`), strand forecasts, usage sweep, statusline account badge, `cc-lr` census "on-target", move verdict | **billing** | quota is consumed by the bearer (P3, P4, P5: billed org follows the bearer) |
| Credential lifecycle: heal gate (`claude-accounts:1936`), cc-relogin, refresh-ownership, keychain-item ↔ dir map (`keychain_service(config_dir)`, `claude-accounts:518-521`) | **home** | the refresh-token holder is the home item. Lanes never refresh |
| Storage: transcript paths, `sessions/`, `projects/`, cc-registry pane binding, bg supervisor, `jobs/`, hooks resolving `$CLAUDE_CONFIG_DIR/...`, lr-transplant | **home** | CC itself keys these on `CLAUDE_CONFIG_DIR` (S12 §1, S14 §1) |
| Policy and identity views: "which account is this session signed in as" (statusline name, cc-board), the bridge/RC owner | **identity (= home)**, shown as `home→billing` | it is what the server sees in metadata |
| Audit and casualty ledgers (moves, recon records) | both, time-stamped | R9: "billed to A from t" |

Migration rule for the ~68 files:
- Every read of `basename($CLAUDE_CONFIG_DIR)` or the registry `account` that feeds the **billing** class moves to
  `billing.sh`/`billing.py`.
- Reads in the home and storage classes stay as they are, and gain a comment tag `# acct:home`.
- A repo test (`tests/attribution-keys.bats`) greps for untagged config-dir→account derivations, so new code must choose a key.

---

## 10. ps-free census (S07) folded in

`lr_recon/proctable.py` per S07 §6:
- one `sysctl KERN_PROC_ALL` (3.3 ms / 2,167 rows at load 624 [C S07 §4]) for pid, ppid, zombie, lstart and tdev;
- a `/dev` rdev map for tty;
- a bounded `ArgsReader` thread for KERN_PROCARGS2, claude-family first (9 ms / 93 rows), with deadline 0.5 s, budget 3 s per pass
  and STUCK_MAX 2;
- strvis rendering identical to ps.

Additions for this design:
- `env_keys(pid, keys)`: the same KERN_PROCARGS2 buffer's env block, extracting **only** `CLAUDE_CONFIG_DIR` and
  `CLAUDE_SECURESTORAGE_CONFIG_DIR`. Nothing else from the block is kept, compared or logged, because the block can hold secrets
  (S07 §6 "Also replace").
- Consumers:
  - broker admission (armed? one holder?);
  - re-home precondition (zero holders);
  - lane GC (bound pid gone twice);
  - the arming audit (`unarmed` count by home);
  - heal's `gate_census` (it replaces the `ps` that made heal "UNMEASURABLE");
  - the move-lane census `lr-upgrade.sh` (the 100p REPORT's deferred "ps-free move-lane census").
- Fail-closed: an unread args or env for a claude-family row marks `degraded:ps-args <pid>`. That row is **unknown**: no swap, no
  re-home, no GC. The rest of the table proceeds. The abstain shrinks from table-wide to row-local (S07 §6).
- Modes: `LR_RECON_PSFREE=off|shadow|on` + `recon/ps-free.off`. Shadow parity runs N passes before `on` (S07 §6).

---

## 11. Acceptance criteria (disk-truth reads only)

| AC | Read | Pass |
|---|---|---|
| AC1 billing changed within 1 call | `ledger.jsonl` row (t_order, t_c, fp_B); `stat -f %m <lane>/.credentials.json` = t_c; `cc-lane verify` → fp(lane item) = fp_B = claude-accounts local-state fp for B; transcript: requests built between t_order and t_c (records whose parent user/tool_result ts lies in [t_order, t_c]) | fp match; **≤1** such request; ≥1 assistant record whose parent ts > t_c (a request built after commit) |
| AC2 0 forks | transcript `<sid>.jsonl` from t_order: every `uuid` has ≤1 child among non-sidechain records; proctable: exactly 1 holder of sid at every pass t_order → t_order+600 s | 0 multi-child parents; holders == 1 |
| AC3 0 lost turns | from t_order to t_order+600 s: no `[Request interrupted` record, no unmatched `tool_use` older than its tool's own timeout, no new api-error tail other than a later real limit | all zero |
| AC4 0 killed bg tasks | proctable (pid, lstart) of the holder identical before and after; no `<task-notification>` with status killed/stopped after t_order; `<cfg>/jobs/*/state.json` inFlight unchanged | identical / zero |
| AC5 corroboration (not gate) | `/tmp/cc-telemetry` statusline row `rl7` (C9) after t_c ≈ B's 7 d % (`claude-accounts --readout`), not A's, when they differ by >5 pp; account-utilization feed: B's 7 d slope rises | consistent, or logged `uncorroborated` |
| AC6 re-home | the first process of sid after a boundary: proctable env `CLAUDE_CONFIG_DIR` = dir(billing at exit); lane fp = same account; `ledger.rehomed` with transcript sha match; registry `account` = billing | all true. Mismatch closed |
| AC7 credential safety | for each account: refresh-token fp present in exactly 1 keychain item (claude-accounts local-state + every lane blob `refreshToken==null` checked by `cc-lane verify --rt-null`); `claude-accounts-lastgood-rejected.json` = `{}` | 1 holder each; no rejections |
| AC8 census | `recon/shadow/ps-free.jsonl` N passes, 0 ppid/zombie/lstart/tty mismatch, 0 claude-family token mismatch; `events.jsonl` 0 `ps degraded` abstains after `on` | zero |
| AC9 attribution | `cc-billing mismatched` agrees with `cc-lane verify` on every live sid; the router's per-account charge = count by billing | equal |
| AC10 busy-move rate | over 7 d: armed `wait:*`-class rows (mid-turn / bg / subagents / goal) → `SWAPPED` | ≥ 99% (vs 3.4% today, S06 §1b) |

---

## 12. Kill switches

| Env (file twin, read every pass) | Effect |
|---|---|
| `CC_LANE=off` (`~/.reso/lanes/arm.off`) | Launchers set no lane: stock behaviour for new launches. Live lanes keep working |
| `LR_LANE_MOVE=off` (`~/.reso/lanes/move.off`) | The broker refuses new swaps. `cc-lr move` falls back to the incumbent restart path for every row |
| `LR_LANE_MIRROR=off` | Mirror refresher stops (debug only; lanes then 401 at their token's expiry) |
| `LR_REHOME=off` (`~/.reso/lanes/rehome.off`) | Relaunchers use the session's current home dir (status quo). Lanes are still armed |
| `LR_REHOME_IDLE=off` | Disables B6 only |
| `LR_LANE_PARK=off` | Forbids Arm T. `cc-lane unpark --all` restores parked items |
| `LR_LANE_WAKE=off` | No mailbox wake after a limit swap. The incumbent nudge is used |
| `LR_REBAL_LANE=off` | The rebalance arm uses the incumbent move lane |
| `LR_RECON_PSFREE=off|shadow|on` (`recon/ps-free.off`) | S07 census mode |
| Emergency | `cc-lane revert --all`: every lane's billing := home, one write each, zero restart. Then `CC_LANE=off` |

Every switch fails toward the incumbent or the stock client, never toward an unproven state (R6, R11).

---

## 13. Invariants (carried from S05 §5, plus new)

| # | Invariant | Enforcement here |
|---|---|---|
| R1 | One writer per sid at every instant | Moves never start a process. Re-home only after proctable proves 0 holders on 2 passes. `duplicate`/`bg-split` hold. No cross-supervisor bg re-home (B7) |
| R2 | No in-flight work destroyed | A move touches no process. The re-home rides a restart that happened anyway and adds no kill |
| R3 | No silent truncation; continuity verified | Moves: same file, same process (AC2). Re-home: cold-transplant sha verify, retire on confirm (`lr-transplant` custody) |
| R4 | Verdicts from disk/process facts | AC1-AC9. "Billed to B" = lane fp + post-commit request, never prose; P2 redefined as P2′ |
| R5 | Absence is loud | `unknown` attribution, `SWAP-UNPROVEN`, `degraded:ps-args`, `hold:no-wake` each page once. None defaults to home |
| R6 | Refuse before the point of no return | All admission before `ledger.prepared`. The write is reversible by the same write (revert) |
| R7 | One actuator per session | (pid, lstart) claim. lr_recon owns limited rows. The broker is single-flight per lane |
| R8 | Credential safety | Lanes are access-only (`refreshToken:null`). A grant lives in exactly one item (home or park). CC's `.storage-write` lock is honoured. No token is printed. Every spawner scrubs the lane var (R16) |
| R9 | One time-aware attribution source | `ledger.jsonl` + `billing.py` (§9) |
| R10 | Bounded calls under load | Every `security` call ≤2 s ×2. Proctable deadlines. Broker request budget 30 s, then `aborted` |
| R11 | Operator authority | Intent re-read at admission. Router fail-closed. Env + file kill switches. Settings only via numbered migrations |
| R12 | No filler sessions | The design launches nothing. The heal (D9) is a token refresh, not a session |
| R13 | Teams never orphaned; teammates follow the lead | A lane is shared by in-process and pane teammates (G2 §b), so the team moves as a unit |
| R14 | Fail closed on binary drift | `cc-lane arm` refuses on an uncertified CC version. The certified set lists the anchors this design rests on (`uw` @3737607, `wA` @4658522, `KWe` @8876312, `EN` @8641537) plus a recorded probe (§16 P-L1) per version |
| R15 (new) | Lanes are mirrors, never sources | No lane holds a refresh token. A lane blob with `refreshToken≠null` is `lane-owned` and frozen (H-12) |
| R16 (new) | Every process that sets `CLAUDE_CONFIG_DIR` for a child also sets or unsets the lane explicitly | `lib/cc-lane.sh`; claude-accounts heal; cc-relogin; tests grep for `CLAUDE_CONFIG_DIR=` without `cc_lane_env`/`unset CLAUDE_SECURESTORAGE_CONFIG_DIR` |
| R17 (new) | A move never causes a restart; only natural boundaries restart | The `act=swap` path has no `/exit` code. The restart path is reachable only by `--restart` (operator) |
| R18 (new) | Identity re-alignment never by body rewrite, proxy or forged 401 | §15 rejected list |

---

## 14. Failure-mode table (every observed mode → structural answer)

| # | Observed mode (source) | Structural answer |
|---|---|---|
| 1 | Busy sessions never move: 149 wait/goal rows → 5 MOVED; 56/56, 57/57, 67/67, 151/151 mid-turn snapshots (S06 §1-2, S05 §3) | Armed rows have no wait: a write, adopted at the next call (P4-P6) |
| 2 | `/exit` kills the in-flight turn, no output persisted (S05 §2.1, handoff-fire:20757) | No `/exit` on the move path (R17) |
| 3 | Forks: 13 FAILED "two live copies", bg-daemon SPLIT-BRAIN (S05 §3); P8 two writers branch | Move: same process. Re-home: 0-holder proof (R1). No cross-supervisor bg re-home (B7) |
| 4 | STRANDED (12), watcher died, F1 strand (S05 §3) | Move cannot strand (no relaunch). A re-home strand is retried on target by the existing revival; source retired only on confirm |
| 5 | Husks / half-moved / stale tombstones (S05 §3) | Moves never transplant. Re-home transplant is cold (source dead), so there is no exit race to cancel |
| 6 | Subagents killed; `killed_inflight` unaudited (S05 §3) | Subagents share the lane and the process (G3 row 2), so nothing is killed |
| 7 | Background jobs die on restart (P7); ship-land killed | Same process. `--bg` jobs bind the same lane via `providerEnv` (G2 §b) |
| 8 | `/goal` dies or is held (S05 §3, 45 hold:goal-live) | The goal stays in-process across the swap. A wake resumes `usage_limit_waiting` ([M I]) |
| 9 | Team kills on lead exit (S05 §3) | No exit. The team shares the lane and moves as a unit (R13) |
| 10 | Drafts merged or destroyed; pasted text lost (S05 §3) | No keystrokes are typed |
| 11 | Cache rewrite 273K-479K tokens per warm move (S05 §3) | One prefix re-creation per move (P3/P5), priced into the rebalance gate with a 6 h cooldown. The re-home is cache-neutral (§2.2) |
| 12 | Outage 58-129 s per move; actuate→proof p50 207 s (S05 §3) | No outage; mover time ≈2-5 s [E] |
| 13 | Lane overhead: slot-wait, HELD:load, capacity, kitty unreachable/wedged, no-shell, focus (S06 §1a) | None of these stages exist on `act=swap` (no boot, no kitty RPC) |
| 14 | Recovery latency median 81 min (S05 §3) | Swap + mailbox wake (§7.2). Pre-wall drain avoids the wall |
| 15 | `became-limited` / owes a turn (S05 §2.2) | Reconciler swap + asyncRewake wake. `hold:no-wake` falls back to the incumbent nudge |
| 16 | ps blind for 15 passes (S07 §5) | Proctable in-process census. Row-local abstain |
| 17 | KERN_PROCARGS2 may stall (S07 §3, §7) | Bounded thread, deadline, STUCK_MAX. An unread claude row is `unknown` (no act) |
| 18 | Refresh rotation + `invalid_grant` erase; copies self-destruct (S14 §7, G1 §5, S05 G8) | Access-only mirrors. One refresh holder per grant (R8, R15) |
| 19 | Old access token possibly revoked on refresh (P9 accruing; claude-swap #381) | The mirror refresher re-mirrors on keychain-db change (≈1 s [E]). The client's 401 path re-reads the store and retries (`Khe` @12388136, `y$` @4661628). Cost ≤ one 401 + retry per source refresh |
| 20 | Billing account has no home sessions, so nobody refreshes its token → lanes expire | Expiry guard runs claude-accounts heal (zero-live gate already exists, `claude-accounts:1936`) 15 min before expiry (D9) |
| 21 | Tertiary's stale `.credentials.json` pins the memo (S14 §5, G1 §3) | The lane dir is separate, so it does not matter for lanes. Arm T refuses tertiary until the file is renamed (operator) |
| 22 | CC `mutate` on a file-only store migrates to keychain and deletes the file, silencing later file swaps (S14 §6b) | The broker creates the lane keychain item at arm, so `update` never takes the "no item before" delete branch. The swap writes both legs |
| 23 | Keychain `security` read timeout (2 s) under load 600-900 → composite falls to file | D1(a): the file leg holds the same mirror, so a failed keychain read still yields the right token. D1(b): a beacon `{}` yields no token → 401 → re-read → retry |
| 24 | In-flight request finishes on the old bearer (G3 §3) | Accepted. It is "the 1 call" of the DoD |
| 25 | 429/5xx backoff inside one `Khe` reuses the old client (G3 §1) | Same as 24. A long usage-limit wait ends the turn on the main thread, and the reactive flow handles it |
| 26 | cache_touch keepalive keeps an old client ≤240 s (G3 4b) | Accepted: one keepalive POST on the old org, no generation. It also keeps A's cache warm in case of revert |
| 27 | P5 404 `thread_not_found` on the first call to a new org | Handled by the client's thread layer (`Hhe` @12372944); one ≈225 ms re-send (P5) |
| 28 | P6 / G4 identity mismatch | Re-home at a natural boundary (§2.2). Window measured in §8 |
| 29 | Usage meter / rate-limit state `Iu` keyed on the old uuid (S03 §3, G3 §4) | Cosmetic until re-home. The statusline shows `home→billing`. Controllers read billing from the ledger, never from the client UI |
| 30 | Remote Control bridge / session-ingress helpers that captured a token (G3 row 5e) | Residual. A bridge 401 runs `y$` (re-read). Captured-token helpers keep the old token for their lifetime. Re-home re-registers. Listed in §15 residuals |
| 31 | MCP OAuth tokens live in the same blob; a fresh lane has none (G2 §b) | D4: mirror `mcpOAuth` access-only from home. MCP refresh stays with the home item |
| 32 | `/login` inside a lane session writes a refreshable grant into the lane (`uw()` → lane) | `lane-owned` detection at every swap read: the lane is frozen, a page is sent, and the lane becomes the grant's sole holder (still one holder) |
| 33 | `/logout` in a lane session deletes the lane item | Broker sees the item missing → `unknown` + page. It never re-arms silently (the operator logged out on purpose) |
| 34 | Nested `claude` or heal spawned from a tool inherits the lane and writes the wrong item (H-16; heal uses `os.environ.copy()`) | R16 scrub. Test |
| 35 | New session launched from inside a session inherits the parent's lane (two sessions, one lane) | Launchers always `cc_lane_env` explicitly (R16). `bind.jsonl` shows >1 unrelated sid → `shared-lane` hold + page |
| 36 | Settings `env` live rebind changes `CLAUDE_SECURESTORAGE_CONFIG_DIR` in **every** session (G2 §b; all settings.json symlink to one file) | Forbidden. Settings are never edited by agents. `cc-lane verify` alarms if any process's lane env ≠ its arm record |
| 37 | Dispatch identity lost on transplanted panes (S05 §3) | Moves keep the pane, pid and registry row. The re-home relauncher reuses the incumbent's registry rebind |
| 38 | Duplicate `136fa815`/unknown item and 27 orphan probe items (G1 §1) | Lane items are named by `sha256(lane)` with lane under `~/.reso/lanes/`, so no collision. GC deletes lane items. Orphan cleanup is a separate operator task |
| 39 | `HELD:exit-readback`, `composer-unreadable`, `bg-work-dialog` modal (S05 §2) | Not reachable: no exit and no composer read on the swap path |
| 40 | Router refusal / target-unverified (S06 13 rows) | Kept as an admission refusal before `prepared` (R6) |
| 41 | P1: a dead local hop is retried 11-12× then fails | No local hop (M6). Broker death stops only new moves |
| 42 | P2: degradation behind a non-first-party base URL | Not applicable (M6 keeps api.anthropic.com) |

---

## 15. Rejected alternatives

| Alternative | Why rejected |
|---|---|
| M7 proxy (as primary) | §3: mismatch permanent, SPOF, P2 degradation, side endpoints stay on the old account, and S08 Moderate-High |
| M7 + body rewrite of `metadata.user_id` | Breaks the `cch` body hash (S03 (2)) and "misrepresents the client" (S08 M2) |
| Forced immediate re-home (restart right after the swap) | That is M2/M22, with the P7/S04 losses. It violates the DoD (killed bg jobs; lost turn) |
| Lane-only, never re-home | The mismatch is unbounded (G4 M1). Transcripts drift from billing. The attribution debt grows with every move |
| Re-home-only (M1 incumbent) | 3.4% busy-move rate (S06) |
| In-process identity re-sync via a per-session `CLAUDE_CONFIG_DIR` clone + external `oauthAccount` write + a provoked 401 to force `kn()` (G4 M2) | It needs a deliberately failing request (it reads as token abuse). A per-session config dir breaks the bg supervisor, `sessions/` liveness and every home-keyed consumer (S12 §3). `iL()` still wins until `kn()` |
| Trigger a bootstrap refresh externally (G4 M3) | The triggers are a model change, an SDK `set_model`, or the server ATIS pin (flag off by default, [M H]). None can be driven from outside without typing into the pane |
| `CLAUDE_CODE_ACCOUNT_UUID` | Honoured only with `CLAUDE_CODE_REMOTE` (G2 §c) |
| M5 home-item rewrite as the general mechanism | Whole-dir granularity, and the C1 graveyard (S05 §4, 14% conviction). Kept only as the access-only, transitional Arm T |
| Settings `env` live rebind of the lane (G2 §b) | One value for every session on every account. `Object.assign` cannot unset. Agents never edit settings.json |
| M10 apiKeyHelper, M16 gateway | API/enterprise billing (S05 G4, S11) |
| M11 env token, M12 FD token, M19 401-wait poll | Pinned at launch, or poll sources that cannot change externally (S01, S14 §7) |
| M13 setup-tokens | Ruling a90e1ac2597e. Reduced scopes (S13) |
| M14 plugin `env.set` | Unverified (I2 absent). Even if it works, a plugin hook gets only a hook-time trigger (S10) |
| M15 `/login` | Idle + browser; rewrites the whole dir (S04) |
| M17 bg respawn, M21 fork-and-retire | Supervisor pins its config dir; `/background` forks (S12 §5-6) |
| M3/M4 hook-timed Esc/exit | Lossy (S04). A hook only triggers (S10) |
| Waiting on turn-end events (100p C5) | Still a wait, and 11/20 sessions are ≥99.8% mid-turn (S06 §3). Kept only for un-armed rows awaiting a boundary |

---

## 16. Residual risks

1. **Server-side meaning of the mismatch is unknown** (G4 open Q1). If the server validates `account_uuid` against the bearer, every
   moved session's requests could be flagged during the 17 h [E] median window. P3-P6 all succeeded, so it is at least not rejected
   today. Policy exposure stays Low-Moderate at 60% (S08 M3) and may worsen after 2026-11-12 (AUP "circumvent product guardrails").
2. **Keychain+beacon variant (D1 b) is unprobed.** P4 measured the file-store variant only. Probe P-L1 is required before `on`:
   throwaway hermetic session, lane keychain item + `{}` beacon, swap mid-turn, measure adoption call index under load ≥600.
3. **P9 outcome.** If refresh revokes old access tokens instantly, each source refresh costs one 401 + retry per lane session on
   that account. If `Khe`'s bounded retries outrun the mirror (≈1 s [E]), one request errors and the turn may end. The reactive
   limit/api-error wake covers it.
4. **Bridge / Remote Control and captured-token helpers** stay on the old account until re-home (G3 row 5e).
5. **`--bg` daemon sessions** never re-home automatically (B7).
6. **Version drift.** Every anchor above is in 2.1.293. R14 refuses `arm` on an uncertified binary, so the design degrades to the
   incumbent on upgrade until re-certified.
7. **Lane item sprawl.** One keychain item per live process (~40). GC is census-driven, and a GC failure leaves short-lived access
   tokens in orphan items until they expire (≤ token life).
8. **Arm T moves idle sessions too**, and depends on the operator renaming the tertiary file before it can be applied there.
9. **Cosmetic UI drift** during mismatch (usage meter under the wrong uuid).

---

## 17. Operator decisions (each below 90% conviction)

| # | Question | Options | Recommendation | Conviction |
|---|---|---|---|---|
| D1 | Lane store form vs ruling a90e1ac2597e ("No token files are ever created") | (a) keychain item + a 0600 `.credentials.json` mirror holding the same access-only blob, deleted at GC (P4-measured, robust when `security` times out under load); (b) keychain item + `{}` beacon file (no token on disk; unprobed; a keychain timeout costs one 401+retry); (c) file only (P4 exact; mutate-migration hazard H-22) | (a), with an explicit ruling that access-only mirrors with ≤token-life lifetime are outside a90e1ac2597e. If refused, ship (b) after probe P-L1 | 60% |
| D2 | Tonight: move un-armed sessions zero-restart via Arm T (access-only park of `next`'s home item onto next4) | (a) Arm T now for `next`; (b) incumbent lane, which waits (0 of 7 busy moved tonight); (c) do nothing, ~14 pp strand on next4 (100p REPORT §2) | (a) for `next` only (no stale file; whole-dir matches the "every active session" order). Unpark on the first of: all parked sessions re-homed, or next4 reset at 08:59:59Z | 65% |
| D3 | Shorten the mismatch window with B6 idle-park re-homes? | (a) natural boundaries only (B1-B5); (b) + B6 idle-park ≥30 min at rest, cold-only; (c) + scheduled forced re-home (rejected) | (b). It is billing- and cache-neutral, and uses the proven idle path | 75% |
| D4 | MCP OAuth in lanes | (a) mirror `mcpOAuth` access-only from the home item, re-mirrored on change; (b) copy intact including refresh (MCP rotation conflicts); (c) none (re-auth prompts) | (a) | 65% |
| D5 | Operator-typed `claude --resume <sid>`: re-home automatically? | (a) automatic, launcher-intercepted cold transplant; (b) print the suggestion only; (c) never | (a), with a one-line `◆ re-homed next→next4` notice | 75% |
| D6 | Accept the policy exposure of M6 at all (S08: 60% not a breach today; Nov-12 AUP ambiguity) | (a) proceed, own accounts only, re-home bounding the mismatch; (b) proceed until 2026-11-12, then re-review; (c) stay on the restart incumbent | (b) | 60% |
| D7 | Where a pre-wall drain lives | (a) rebalance/shed controller (usage % allowed there); (b) lr_recon (would break `facts.py:12-13`) | (a) | 80% |
| D8 | Close decision packet `745e0fdc78e6` (C1 flip "wait for the next wall") as superseded | (a) close, superseded by A4; (b) keep open until the P-L1 probe passes | (b), then close | 80% |
| D9 | Allow the broker's expiry guard to invoke the existing zero-live-session heal for an account that only lanes bill to | (a) yes (existing gate, refresh by the official binary); (b) no: lanes on such an account expire and their sessions get moved off it | (a) | 80% |
| D10 | Ship the donor arm together with the sink arm (now zero-restart) | (a) together behind `LR_REBAL_DONOR`; (b) sink first, donor after one clean sink window (100p REPORT order) | (b) | 70% |

---

## 18. Probes still required before `on` (none run here)

- **P-L1.** D1(b) keychain+beacon adoption under load. Also the adoption call index with `security` slowed (ulimit or a stall
  shim).
- **P-L2.** Two lanes billing the same account concurrently, plus the source's own refresh: count 401s per lane (folds in P9).
- **P-L3.** Wake after a reactive limit swap: a throwaway session pre-armed with the asyncRewake watcher, induced limit (a
  next-of-cap account), swap, mail. The synthesized turn must bill to B.
- **P-L4.** Re-home: cold transplant + launch on dir(B) + lane(B). Expect `metadata.account_uuid` = B on call 1 (bootstrap
  stamp), using the probe proxy as an observer only, as in P4.
