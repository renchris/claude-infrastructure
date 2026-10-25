# SYNTHESIS: mid-turn account move, the final design (2026-10-25)

Synthesizer of the judge-panel study. Read in full: D-brief, P-probes (P1-P11; P9 RESULTED
03:58-04:00 CDT, P-probes:162-176: an account's own refresh revokes its previous access token at once), A1-A4
(A5 was never written), S05, S06, S07, S12 §1-4, S14, G1, G2-securestorage, G2-keychain-acl,
G2-bootstrap, G2-org, G3, G4, I1, I2, the S08 rating section, `.claude/rules/*.md`, and the panel
results with every adversarial verdict. Read-only, except for this file. I launched no Claude Code,
touched no pane, read no keychain secret, and made no git write.

Labels: **[M]** measured (command or probe named), **[C]** cited (note and section or offset),
**[E]** estimated (method named), **[I]** inference from source, with a falsifier given where it
carries load. Byte offsets are into `/tmp/mtam/cc293-src.js` (CC 2.1.293).

**Review status (2026-10-25):** the completeness review of this file did not finish: a safety classifier
stopped the run while it was reading, so no gaps were assessed. Do not read that run as a pass. The
operator decides whether and how to rerun it. No design text changed as a result of that run.

**New source reads in this pass** (`timeout 60 python3 -I` byte windows) [M]:
- `y$` @4661639: for a store whose `refreshToken` is null, the 401 handler takes the
  `!h?.refreshToken` branch and returns `false`. `recovered_from_keychain` is reachable only when
  the store holds a refresh token. `Khe` @12387081 still rebuilds the client after any 401 (`Dnn`
  @12385357) and retries with whatever the store holds. It gives up after `wur=2` attempts
  (@12384871) on an unchanged token.
- `_Dn` @4661369: the "401 unrecovered, exit" timer applies only to remote children (`Il()`), so a
  local session is never killed by it.
- `wA` @4658281 stats `uw()/.credentials.json` on every check. When `CLAUDE_SECURESTORAGE_CONFIG_DIR`
  changes in-process to a lane that has a file, the next check sees a new mtime, and `ox()` clears
  both the memo and the 30 s keychain cache. A lane bind with a file leg is therefore adopted at the
  next client build.
- `session.measure` carries `["context","rateLimits","cost","changed"]` (@5051563).
- In the JS source, `cch` is the literal string `cch=00000;` (@5434119).

**Patch-pass source reads** (`timeout 60 python3 -I` byte windows) [M]:
- The 401 throw site is @12388522: `if(mn()?.accessToken===Ze){if(oSe()!==null||!KN(M)&&++Te>=wur)throw
  … "api_request_oauth_refresh_exhausted"}`. With `wur=2` (@12384871), the second 401 on an unchanged
  token ends the request. The retry backoff is `LF` @3751360 (`me=500` base, proportional jitter 0.25).
- `FF()` @3737710 names the keychain item `Claude Code-credentials-<sha256(CLAUDE_SECURESTORAGE_CONFIG_DIR)[:8]>`
  when the variable is set. Set to a home dir's exact path, it names that home's own item (M31).
- `Pl` @4668663 runs `ox()` and re-reads the store before it takes `<uw()>/.oauth_refresh.lock`, and
  again under the lock. A refresh therefore uses the grant of the store the session points at now, not
  a cached one.
- The store reads the keychain first and the file only when the keychain returns null (S14 §2,
  `M(primary,fallback)` @3743527).
- `session.measure.rateLimits` entries are `kue` @11504180: `{kind, percentUsed, resetsAt}`, with
  `resetsAt` = the server's `resets_at`. The push gate `xn()` @26019398 compares only `percentUsed`
  per kind with a 1 pp threshold. It ignores `resetsAt`. A "turn" push carries the current
  `rateLimits` whenever anything changed (`$n` @26019818).
- 2.1.310 (`~/.cursor/extensions/anthropic.claude-code-2.1.310-darwin-arm64/resources/native-binary/claude`):
  the change-check is `sA` @219228917. It calls `VRe(){return J()?null:DL()}` (@218478357) before the
  `.credentials.json` stat and takes the `ku` path on null. The anchors move, and the semantics may
  move too (§10 W0, check18).

---

## 1. Verdict

**Winner: A4, the identity-clean hybrid.** Each session gets its own credential lane (M6). The lane
holds an access-only mirror of one account's token, and a move is one journaled, content-verified
write to that lane. Identity is re-aligned later, at a restart the session was going to have anyway
("re-home"). **P10 adds a retrofit path:** the already-loaded `accounts-readout` mod re-points a
running session at its lane with `$.env.set`, with no restart.

**Grafts:**

| from | graft | why |
|---|---|---|
| A1 | **Keychain-primary lane with a synced 0600 file leg.** The broker pre-creates the lane keychain item. | A client-side `mutate` (an MCP token save) then takes `update`, not the delete-on-migrate branch @3743013 (S14 §6b). The file's mtime bump makes adoption immediate (`wA`→`ox()`). The file also serves the token when `security` stalls under load. |
| A1 | **Broker-enforced lane hygiene:** `O_NOFOLLOW\|O_EXCL`, `lstat` refuses symlinks, owner check, 0600 files, 0700 dir outside the `~/.claude` symlink farm | The live plaintext reader follows symlinks (`readFileSync` @3750135; the v5 `O_NOFOLLOW` path is inert) |
| A3 | **Prove death before any relaunch** (re-home, restart-now). Checks are single-pid: `kill -0` plus `KERN_PROC_PID` lstart, plus no `--resume <sid>` argv holder on 2 passes ≥1 s apart. | Closes P8 and the late-append fork (S04 §3). Corrected per the verifier: a full-table census is not required. |
| A3 | **R8 as a fleet rule:** each account's grant lives in exactly one store, and no mover copies a refresh token | G1 §5 |
| A3 | **Restart lane kept**, with degrade-to-incumbent as the kill switch. M2 (kill, then resume with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`) runs only on an explicit operator order, for sessions the retrofit cannot reach. | Policy-lowest lever (S08 M1). The never-ending-turn cohort exists (S06: 4 of 20 sampled sessions have no `end_turn` at all). |
| A3 | **Timing-honest verdict fields:** `order_ts`, `t_c`, `first_post_commit_request_ts` | R4 |
| A4 | **Three-key, time-aware attribution:** home / billing(t) / identity, with `unknown` as a first-class value. `ledger.jsonl` is the single source. | I1: about 68 config-dir-keyed files |
| A4 | **R16:** every process that sets `CLAUDE_CONFIG_DIR` for a child also sets or unsets the lane variable | heal uses `env = os.environ.copy()` (`bin/claude-accounts:1975`, inside `heal()` at :1936) |
| A4 | `cc-lane revert --all` emergency rollback: one write per lane, zero restarts | §8 |
| A2 | **First-hand strand sensor, without a proxy.** The mod's `session.measure.rateLimits` reports the billed org's utilization after every main turn. | Replaces A2's header sniffer. No bearer is intermediated. |
| A5 | **A policy gate before any zero-restart credential mover goes live:** ask Anthropic in writing, and treat 2026-11-12 as a mandatory re-review | §11 Q1 |

**Why the panel total does not decide this.** The totals were A3 26, A4 25, A1 21.5, A2 20.5,
A5 10. A3 won the policy and build-risk lenses. A4 won the robustness and operator-outcome lenses.
Four facts settle the choice:

1. **The DoD is frozen**, and A3 misses three of its four clauses by construction (lost turn, killed
   background work, effect in seconds rather than one call). A3 says so itself (A3 §0).
2. **Six of A3's load-bearing claims were refuted or contested** (§1.1): tool boundaries are not
   seconds away, the fork guard missed the bg daemon, the comparative identity claim fails,
   invalid_grant is not structurally impossible, the census is not a hard prerequisite, and the
   ship-land premise was wrong.
3. **P10 was measured after the architectures were written.** It removes A4's operator weakness: all
   36 live sessions are un-laned, yet 40 of 42 interactive processes already load the mod
   (P-probes:129-132). It also removes A4's riskiest component, Arm T, which the verifier refuted:
   it would discard rotated grants and log out `next`.
4. **A3's strengths survive as grafts.** The restart path stays as the explicit fallback and the
   rollback target. Its policy position becomes a gate (Q1), not the architecture.

**Conviction: 70%** that this is the right design to build. Probes P-R1, P-L1 and P-F1 (§10 W0) are
the falsifiers. The policy question is separate: it is an operator value call (Q1, class C).
**Patch pass:** P9 has resulted, and a refresh revokes every copy at once (§3.7). The lane *form* is
therefore open: per-session copy (as built here, gated on P-L5), pointer (M31) or per-account shared
copy (M32). P-L5, P-L6 and P-F1 decide it (§2). The 70% applies to the architecture (lane plus
retrofit plus re-home). It is not a claim that per-session copies survive P9.

### 1.1 Every refuted or contested claim, and what this design does with it

| # | claim (source) | panel finding | disposition here |
|---|---|---|---|
| 1 | A3: kill at a `PostToolBatch` boundary, "seconds away" | REFUTED. Time-weighted mean wait to the next boundary is 421 s; 93% of tool time is in calls over 120 s; tool p90 311 s (verifier [M], n=1520). Moving a busy session without waiting comes from M2 itself, which works at any instant (P7, +18 s). | **Removed.** `PostToolBatch` is not used. The operator-explicit restart (M2) fires at once. |
| 2 | A3: "meets 0 forks; misses the other 3 structurally" | REFUTED. The source-dir bg daemon can re-claim a job minutes later (`lr-upgrade.sh:1407-1421`, F4 pane 405: "claimed-spare … 4 minutes later"). | **Fixed.** Re-home and restart-now refuse a sid that has a live `<home>/jobs/<short>/state.json` or daemon-roster entry (R1, FM58). |
| 3 | A3: "no zero-restart mechanism re-syncs account_uuid" | REFUTED. In-process bootstrap restamps happen on a model change (`aan` @18400845), on `/login`, and on `_ut` slot misses (G4 M3/M4, G2-bootstrap). | **Fixed.** Identity is modeled as a value in {home, billing}, never stored as exact (§3.8). None of these triggers is used on purpose (R18). |
| 4 | A3: no credential write, so "invalid_grant is structurally impossible" | REFUTED. `Pl` rotates on the server before it writes the keychain, so killing a process mid-refresh can lose the rotated grant. | **Fixed.** restart-now first takes the source's `<uw()>/.oauth_refresh.lock` (bounded 10 s), so the kill never lands inside a refresh [I]. Falsifier: a `claude-accounts-lastgood-rejected.json` entry after a restart-now. Laned sessions never refresh. |
| 5 | A3: the ps-free census is a hard prerequisite | REFUTED. It improves availability; it is not a safety gate. 56/4820 passes were degraded (1.2%) and the longest blind streak was 15 passes (S07 §5). | **Fixed.** Swaps need only single-pid checks (§3.4). A degraded census makes a row abstain (row-local, R5). |
| 6 | A3: ship-land is non-idempotent, so a wait is forced | REFUTED. `ship-land.sh` traps TERM, `rollback_clean` runs `git rebase --abort`, and an attested land exits 0 (verifier, `ship-land.sh:1516-1560, 5943-5946`). | **Fixed.** restart-now does not refuse ship-land. Its cost is re-gating time. A SIGKILL backstop can leave a rebase in progress, and the next run then refuses until it is aborted (FM59). |
| 7 | A4: a lane write moves billing at the next call | HOLDS for the file-only form (P4/P5/P6). CONTESTED for the keychain-primary form, which was never probed. | **Guarded.** P-L1 is the falsifier and gates `on`. "Next call" means the next *client build*, with the exceptions in FM24-26. |
| 8 | A4: no in-process path short of /login restamps account_uuid | REFUTED (same as 3) | Fixed (same as 3) |
| 9 | A4: mismatch lasts 17 h median, 47 h p90 | REFUTED as too low. It counts restarts that lanes remove. Recomputed: median 19-20 h, p90 68-115 h (two verifiers [M], launch.log). | **Fixed.** §3.8 quotes the range [E] and calls it lower-side. The duration accrues from the ledger (§12). |
| 10 | A4: the lane covers the whole process tree | HOLDS at spawn time. CONTESTED: GC by the creator's pid would orphan `--bg` jobs and pane teammates that hold the lane *path* in `providerEnv`. | **Fixed.** GC is refcounted over bind and beat records and job `state.json` (FM50). The mirror refreshes every referenced lane. |
| 11 | A4: access-only copies never refresh | HOLDS for lanes (`Pl` returns `no_refresh_token` before any lock or POST, S14 §7). REFUTED for Arm T (rewriting `next`'s live home item). | **Arm T removed** (§7). |
| 12 | A1: `claude-accounts --local-refresh` is the single refresher | REFUTED. `local_refresh` "Never calls heal" (`bin/claude-accounts:8231`), and heal runs only when the account has zero live sessions (:1936-1975). | **Replaced** by R21 (refresh ownership, §3.7). |
| 13 | A1: after a 429, `Khe` rebuilds onto the new bearer | REFUTED. The rebuild gate `Dnn` @12385357 covers 401/403 and auth errors only. 429 retries reuse the old client (G3 §1). | **Removed.** A capped turn ends, and recovery is swap plus wake (§3.5). |
| 14 | A1: `expiresAt:null` in the lane | unmeasured. P4-P6 copied the real `expiresAt` (`/tmp/mtam/probe/tok.py:13-23`). | **Replaced** by the real `expiresAt` (the measured form). |
| 15 | A2: a safe lane copy "has no source" without setup-tokens | contradicted by P4-P6 (an inference-only copy of the live access token works) | moot (A2 not chosen) |
| 16 | A4: a body rewrite "breaks the cch hash" | contradicted. `cch=00000;` is a literal in the JS source (@5434119); native substitution was not traced. | **Fixed.** A body rewrite is rejected on policy grounds (S08 "misrepresent the client"), not because of cch (R18). |
| 17 | D-brief "Retry loop": the 401 handler adopts a changed token | REFINED [M]. For refreshToken-null lanes, `y$` returns false. `Khe` still rebuilds and retries, so a re-mirrored token is adopted only if it lands within `wur=2` same-token attempts. | §3.7 makes steady-state refreshes broker-driven, so the mirror is written right after the refresh (FM46). **P9 RESULTED (patch pass):** the old token is revoked at once, so the window is ≈1.5-2.5 s [E]. Per-session copy lanes have no structural answer yet (§3.7, FM19/FM46). M31/M32 are evaluated in §2. |
| 18 | I2: "No retrofit: plugins load only at session start" | REFUTED by P10. A module re-load fires `session.start` again, at the next turn end. | §3.9 |

---

## 2. Every mechanism M1-M32

S08 policy ratings: M1-class restart Low (75% not a breach), store rewrite Low-Moderate (60%), proxy
Moderate-High (45% clear violation, 70% citable).

| # | mechanism | mid-turn? | forks? | what it loses | policy exposure | measured by | verdict |
|---|---|---|---|---|---|---|---|
| M1 | Incumbent: wait for idle, `/exit`, `--resume` on the target dir | no | no with rails (13 FAILED historically, S05 §3) | waits indefinitely: 5/149 busy rows moved (3.4%, S06 §1b); cache rewrite of 273K-479K tokens; 58-129 s outage | Low 75% | S05, S06 | **Keep** as the path for un-laned idle sessions and as the carrier for re-home |
| M2 | Kill mid-turn, `--resume` on the target with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` | yes, any instant (P7 +18 s) | no, with prove-death and the bg-daemon guard | the turn is re-driven; bg Bash, Monitor and workflows die (P7, S04 §2); cold cache; boot latency | Low 75% | P7, S04 | **Keep, operator-explicit only** (`cc-lr move --restart-now`, Q3), for sessions the retrofit cannot reach |
| M3 | Esc at a boundary, `/exit`, resume, type "continue" | yes, lossy | no | Esc never auto-continues (S04 §1) | Low | S04 | Reject |
| M4 | Hook-triggered boundary (`PostToolBatch`) | trigger only | — | mean wait 421 s (verifier [M]); "the boundary buys little safety" (S10 §3) | — | S10, verifier | Reject as a move trigger (§1.1 #1) |
| M5 | Rewrite the home account's keychain item (incl. A4 "Arm T") | yes | no | moves every session on the dir; a null-refresh write over a live item discards rotated grants, so `jhr` logs out every `next` session (verifier) | Low-Mod 60% | S01, G1 §5, verifier | **Reject** |
| M6 | Per-session lane (`CLAUDE_SECURESTORAGE_CONFIG_DIR`) plus an access-only mirror swap | **yes** | **no** (same process) | nothing in-process; identity mismatch until re-home; one prefix re-create (6.2-8.4K tokens in probes) and one 404 replay of about 225 ms | Low-Mod 60% | P4, P5, P6 (file-only form) | **Adopt (core)**. The keychain-primary form needs P-L1. |
| M7 | Localhost proxy, bearer injection | yes | no | single point of failure for ~36 sessions; P2 degradation; threads and RC off | Mod-High 45-70%; S09 #529 ban | P3, P1, P2 | Reject |
| M8 | Same as M7 over `ANTHROPIC_UNIX_SOCKET` | likely | no | M7 losses plus the no-auth/thirdParty flip (S03 (1)) | Mod-High | S03 | Reject |
| M9 | `HTTPS_PROXY` with TLS interception | in principle | no | MITM, CA trust | Mod-High+ | — | Reject |
| M10 | apiKeyHelper | — | — | bills API, not Max | n/a | S05 G4 | Reject |
| M11 | `CLAUDE_CODE_OAUTH_TOKEN` at launch | no | — | pinned (`Pfs` keeps it on 401) | Low-Mod | S01, @4661639 | Reject |
| M12 | FD token | no | — | cached once | — | S05 G7 | Reject |
| M13 | setup-token | yes as a credential | no | reduced scopes; operator ruling a90e1ac2597e | Low-Mod | S13 | Reject |
| M14a | Mod `$.env.set('CLAUDE_CODE_OAUTH_TOKEN')` | yes [I] | no | the token sits in `process.env` and reaches every later child; `Pfs` pins it on 401; the token must pass through mod memory | Low-Mod | I2 (source) | Reject |
| M14b = **M23** | Mod `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR')` at `session.start` on hot-reload (the retrofit) | at the next turn end (P10: edit at t+3.0 s, reload about t+29 s) | no | nothing; it cannot reach a session that never ends a turn | Low-Mod 60% | **P10** (lane→lane, throwaway). Home-keychain→lane is unprobed (P-R1). | **Adopt** (rollout, §3.9) |
| M15 | `/login` in the session | idle only | no | needs a browser; rewrites the whole dir; inside a laned pane it writes the grant into the **lane** | Low | S04, G2 §a | Reject as a mover; guarded (FM49) |
| M16 | Built-in gateway | — | — | enterprise/API billing | n/a | S11 | Reject |
| M17 | bg respawn or attach | — | no | the supervisor pins its own config dir | — | S12 §4 | Reject. bg jobs follow lanes through `providerEnv` instead. |
| M18 | SDK `getOAuthToken` | — | — | SDK-hosted only | — | S01 | N/A |
| M19 | `CLAUDE_CODE_OAUTH_401_WAIT_MS` | — | — | polls env/FD only | — | S01, @4660424 | Reject |
| M20 | New pane, new session on the target | — | — | not a move | — | brief | N/A. New launches are laned at birth. |
| M21 | `--fork-session` / `/background` | — | **yes** | forks by definition | — | S12 §5 | Reject |
| M22 | SIGSTOP the source, resume on the target, kill the source | yes | fork window | M2 losses | Low | P8 | Reject |
| M24 | Mod `$.env.set` of the lane variable from `tool.call`/`turn.step` (mid-turn bind or unbind) | yes [I] (`EIo` @11552107 writes `process.env`; `uw()` reads it per call; `wA` sees the new path) | no | none | Low-Mod | **unprobed: P-F1** | **Adopt, narrowly:** late binds and the fail-safe unbind (§3.11) |
| M25 | Settings `env` live rebind (G2 §b) | yes | no | rebinds **every** session, since all settings.json symlink to one file; cannot unset | — | G2 §b | Reject |
| M26 | Ordered `oauthAccount` rewrite plus slot deletion (G2-bootstrap R1) | identity only | no | per dir; write-once suppression; poisoning | raises the profile | G2-bootstrap | Reject (R18) |
| M27 | Model-change bootstrap restamp (`aan`) | identity only | no | changes the model | — | G4 M3 | N/A. Incidental occurrences are accepted (§3.8). |
| M28 | Pass-through observer proxy (A2 D4) | — | no | threads and RC off (P2) | Low | P2 | Probes only (P-L4) |
| M29 | **Re-home at a natural restart** (A4) | no | no, with the R1 barrier | nothing extra (billing-neutral, warm cache) | Low 75% | P-L4 (unprobed) | **Adopt** (identity plane) |
| M30 | Transparent 429 failover at a proxy (A2 §5) | yes | no | requires M7 | Mod-High | S03 (4) | Reject. Replaced by the pre-wall drain (§3.5). |
| **M31** | **Pointer lane.** The module sets `CLAUDE_SECURESTORAGE_CONFIG_DIR` to the billing account's home config dir, spelled exactly as that home's sessions resolve `we()` (e.g. `/Users/chrisren/.claude-quaternary`). `FF()` @3737710 then names that dir's own item, so the session shares the one grant with native sessions, along with their `<uw()>/.oauth_refresh.lock` (`Pl` @4668663) and `y$` keychain recovery (@4661639). A move is the module's `$.env.set` re-point at `turn.step`. | yes, at `turn.step` [I]: P11 measured per-request routing from `turn.step`, but with copy lanes and in `-p` | no | No copies, so no mirror, heal guard or lane token files. That dissolves Q2 and Q4 and FM46/47/49/70. P9 does not apply, because the session is a native reader of B and recovers from a sibling's refresh like one. Costs: adoption is bounded by the 30 s host-keyed cache (`PK()` @3738325, `cPt=30000`). The four home dirs have no `.credentials.json` (tertiary's is stale, FM21), so `wA` takes the `Jf` path and does not clear the cache, and the change can land **later than 1 API call**: ≤30 s [I]. Identity mismatch as M6. A `/login` inside a pointer-laned pane re-logs **B's** home item. | Low-Mod 60% [I: same class as M6; no token leaves the official client's own stores] | P11 (copy-lane routing); pointer form unprobed (P-probes:148-152) | **Candidate, not adopted.** Decided by P-F1 (now decisive) and P-L6 (below). |
| **M32** | **Per-account shared copy lane.** One access-only copy per account, `~/.reso/lanes/acct-<acct>/`. Every session billed to that account points at it. A move is a re-point between lane dirs, through the same `$.env.set` at `turn.step`. | yes [I] | no | A refresh fans out to **1** write per account (one `security` plus one rename), not one per session. The two dirs' file mtimes differ, so `wA`→`ox()` adopts at the next request with no 30 s cache bound (@4658281). It still needs the mirror, the heal guard (R21) and Q2 token files, and P9 still applies to that one write. | Low-Mod 60% | P4/P5 (file swap), P11 (route by `turn.step`); shared form unprobed | **Candidate, not adopted.** Decided by P-F1 and P-L5 (1-lane form). |

**M31/M32 falsifiers (added after P9 resulted).** P-probes:155-156 named pointer lanes as the
consequence of P9. These rows are the evaluation §2 lacked. Per-session copy lanes (M6 as built)
stay the adopted core until W0 decides. The rule is: M6 keeps its place only on a P-L5 PASS (§3.7).
Otherwise M31, if P-F1 and P-L6 pass, or else M32, if P-F1 and the 1-lane P-L5 pass.
- **M31 is falsified by** any of:
  - P-F1 FAIL: a mid-turn `$.env.set` from `turn.step` does not change the store the next request reads.
  - P-L6 FAIL. P-L6 is a W0 probe in which a throwaway with a hermetic `CLAUDE_CONFIG_DIR` is
    pointer-laned at a real home, then re-pointed. It runs only while both accounts' tokens have
    ≥30 min of life, so `Pl` returns `not_needed` and the client never writes the item [I, @4668663].
    It fails on any of:
    - adoption later than 30 s after the re-point;
    - A's `rt_fp` appearing in B's item, or any `claude-accounts-lastgood-rejected.json` entry;
    - home A's `.claude.json` `oauthAccount` changing after the pointer session's requests or refresh.
      Whether the post-refresh save also profile-writes into `CLAUDE_CONFIG_DIR` is unread.
- **M31's heal gate must count readers by bind beat.** A pointer-bound session counts as a home
  reader of the account its beat names, not of its `CLAUDE_CONFIG_DIR`. Otherwise `claude-accounts`
  heal would see zero readers and refresh outside CC's lock while pointer readers also refresh, which
  leads to invalid_grant (FM18).
- **M32 is falsified by** any of:
  - P-F1 FAIL;
  - the 1-lane P-L5 showing home-refresh → lane-rewritten later than the measured 401 tolerance;
  - two re-points that land on lane files with equal `mtimeMs`, so `wA` sees no change [I]. The
    broker must stamp a distinct mtime on every lane write.

---

## 3. Architecture

### 3.1 Components (paths are under the repo root; runtime state under `~/.reso/lanes/`, 0700)

| component | path | role |
|---|---|---|
| ps-free census | `scripts/limit-recover/lr_recon/proctable.py` (new), `bin/cc-proctable` (new CLI) | S07 §6 verbatim, plus `proc_lstart(pid)` (`KERN_PROC_PID`) and `env_keys(pid,{CLAUDE_CONFIG_DIR,CLAUDE_SECURESTORAGE_CONFIG_DIR})`, which extracts only those two keys |
| lane store | `scripts/limit-recover/lr_lane/store.py` | lock `<lane>/.storage-write.lock` (mkdir, stale 15 s, hold under 5 s, the CC contract per G2-keychain); read-modify-write of only `claudeAiOauth`; `security -i` on stdin with `-a chrisren`, never argv; atomic rename of the file leg; fingerprint read-back |
| ledger | `.../lr_lane/ledger.py` → `~/.reso/lanes/ledger.jsonl` (append-only, fsync) | `{t, lane, sid, pid, lstart, home, billing, prev_billing, cause, move_id, state: prepared/committed/proved/unproven/aborted/reverted/rehomed, fp}` |
| bind table | `.../lr_lane/bind.py` → `~/.reso/lanes/bind/<sid>.json` (order), `<lane>/bind.ack`, `~/.reso/lanes/beat/<sid>.json` | which process reads which lane. **Authoritative over the exec-time env**, because `KERN_PROCARGS2` shows the env the process started with, not later `$.env.set` changes [I] (FM57). |
| mirror | `.../lr_lane/mirror.py` | wakes on kqueue `login.keychain-db`; reads mdat of the 4 home items (attributes only); on a change, does one `-w` read and re-mirrors every lane that references that account; polls at 1 s inside each account's `[expiresAt−6 min, +1 min]` window |
| heal guard | `.../lr_lane/heal_guard.py` | R21: an account with zero home readers gets `claude-accounts --heal-for-lanes <acct>` 15 min before expiry, then a synchronous re-mirror |
| GC | `.../lr_lane/gc.py` | refcounted (§3.4 end) |
| proof | `.../lr_lane/proof.py` | AC1-AC4 verdicts: `SWAPPED` / `SWAP-UNPROVEN` / `SWAP-REVERTED`. `proved` requires the account-specific `resetsAt` witness (R4). |
| broker | `.../lr_lane/broker.py`, launchd `launchd/staged/com.reso.lane-broker.plist` (KeepAlive, WatchPaths `~/.reso/lanes/requests`, ThrottleInterval 2), run as `python3 -I -m lr_lane.broker` | the single writer of lane content; writes heartbeat `~/.reso/lanes/broker.beat` every 10 s. Python, not bash, because `cc-reaper` TERMs launchd-parented bash older than 600 s (rules: "Detached bash is reaped at 10 min"). |
| re-home | `.../lr_lane/rehome.py` | `resolve(sid) → (cfg, lane_env, transplant_needed)` for every relauncher; cold transplant via `lr-transplant.sh --cold` |
| certification | `.../lr_lane/cert.py` → `~/.reso/lanes/cert/<ccver>.json`; `lib/cc-upgrade-gate/check18_lanes.sh` | R14: anchors (located by regex) plus W0 probe verdicts for each CC version, produced for any `--binary <path>`, including an upgrade candidate before the pin moves |
| CLI | `bin/cc-lane` | `arm`, `bind`, `swap --sid S --to B`, `revert [--all]`, `unbind --all`, `promote --lane L`, `status [--fleet] [--json]`, `verify [--rt-null]`, `gc`, `report --mismatch` |
| launcher | `lib/cc-lane.sh` (new), `lib/claude-launcher.zsh` | `cc_lane_env <cfg> [<sid>]`: arm a lane and export the variable at launch; no-op under `CC_LANE=off` |
| binding module | `mods/accounts-readout/hooks/lane-bind.ts` (new) plus a 2-line registration in `register.tsx` | binds on a broker order (at `session.start` on reload, or at `tool.call`/`turn.step`); writes the beat; does the fail-safe unbind (stale beat, or `refresh_path=none`, §3.11); is the `session.measure` sensor. It writes the measure file on **every** push, not only when `changed` contains `rateLimits`, because `xn()` @26019398 ignores `resetsAt` and moves under 1 pp. Inert by default (R20). |
| attribution | `scripts/lib/billing.py`, `lib/billing.sh`, `bin/cc-billing` (new) | `billing_of(sid,t)`, `home_of(sid)`, `identity_of(sid)` ∈ {home, billing, unknown}, `sessions_billed_to(acct)`, `mismatched()` |
| consumers | I1 BILLING-class rows (§10 W5a-W8) | switch from the config dir to `billing_of` |

### 3.2 Data flow

```
operator / rebalance (lr-shed sink arm) / lr_recon (limited rows)
   │ intent {sid, to, origin}
   ▼
~/.reso/lanes/requests/<id>.json ──launchd WatchPaths──▶ lane-broker (single flight per lane)
   │ admit (intent, router fail-closed, (pid,lstart) claim, lane bound+acked, not lane-owned,
   │        B token ≥10 min life) ─▶ ledger.prepared (fsync)
   │ read B home item (-a chrisren -w, in memory only) ─▶ lock lane ─▶ keychain -U (stdin)
   │ ─▶ read-back fp ─▶ rename file leg ─▶ read-back fp ─▶ unlock ─▶ ledger.committed(t_c, fp_B)
   ▼
running claude (same pid): next EN() → j7→Pl→wA: lane file mtime changed → ox() → mn()=B
   │ request billed to B (in-flight request finishes on A, G3 §3); first B call: 404 thread replay
   ▼
mod lane-bind.ts: EVERY session.measure push → ~/.reso/lanes/measure/<sid>.json (the witness)
proof.py: fp(lane)=fp_B ∧ post-t_c request in transcript ∧ 1 holder ∧ linear
          ∧ measure record after t_c with seven_day.resetsAt == B's ≠ A's (tie-break five_hour) ─▶ ledger.proved
          (else SWAP-UNPROVEN)
billing.py view: billing(S)=B from t_c; home(S)=A; identity(S)∈{A,B}  →  every BILLING consumer
   │
natural boundary (process gone, proven dead) → rehome.resolve → cfg=dir(B), lane(B)
   → launch --resume under dir(B) → bootstrap stamps B → ledger.rehomed (mismatch closed)

side loops: mirror (home item mdat change → re-mirror referencing lanes) · heal guard (R21) ·
GC (refcount) · broker.beat ← mod fail-safe reads it before every request
```

### 3.3 The lane store contract

- **Location:** `~/.reso/lanes/<lane-id>/`. Mode 0700, owned by `$USER`, outside the symlink farm.
  The keychain item is `Claude Code-credentials-<sha256(lane path)[:8]>` with account `chrisren` (S14 §1).
- **Contents:** a whole blob `{claudeAiOauth:{accessToken, expiresAt (real), refreshToken:null,
  scopes, subscriptionType, rateLimitTier}, mcpOAuth:{access-only mirror, Q8}}`.
  - Never `refreshToken:""`, which means logged out (S14 §7).
  - Never `refreshTokenExpiresAt`.
  - This is the measured form (`tok.py:13-23`).
- **Two legs:**
  - the keychain item (primary, pre-created at arm time, so a client `mutate` takes the `update`
    branch, A1 §4);
  - `.credentials.json` (0600, the same blob), which carries the mtime signal and serves as the
    fallback when `security` times out.
  - The beacon-only variant (`{}` file) is **not** shipped. A keychain stall would serve `{}`, and the
    session would read as logged out, not as a 401 [I]. It is decision Q2(b) and needs P-L1 first.
- **Write order:** lock → keychain write → read back the keychain fingerprint → rename the file leg →
  read back the file fingerprint → unlock. The keychain must hold the new blob *before* the mtime
  changes [I, S14 §5]. A keychain write that times out goes to read-back, not to the file leg:
  - read-back shows the new fp: continue;
  - read-back shows the old fp: `aborted`;
  - read-back is unreadable: the lane is `unknown`. Retry, page after 3 tries, never commit (R3).
- **Refusals:**
  - the `security -i` command would exceed 4,032 chars, which would force CC's argv path and expose
    the hex in `ps` (G2-keychain): abort loudly;
  - the lane blob carries a non-null `refreshToken` (`lane-owned`, FM49);
  - the lane path or its file is a symlink, or is not owned by `$USER` (FM68).
- **P9 consequence (RESULTED):** every lane is a revocable copy. When its account refreshes, the
  copy's access token is revoked at once. The write order above then runs **once per lane per
  refresh**, not once per move, and has to finish within the 401 tolerance (§3.7). The shared form
  (M32) or the pointer form (M31, no copy at all) is the structural alternative (§2).

### 3.4 Move protocol (order → billing change)

Preconditions: S is bound to lane L (ack plus beat `lane_env==L`), and L mirrors A = billing(S).

| step | actor | action | bound | typical |
|---|---|---|---|---|
| 0 | caller | `cc-lr move --sid S --to B` (or rebalance or reconciler) writes the request | — | <50 ms [E] |
| 1 | launchd | WatchPaths kick | 2 s throttle | 1-2 s [C 100p REPORT C6] |
| 2 | broker | **Admission, all before the point of no return (R6):** intent valid (R11); router fail-closed: B not walled or `unknown`; (pid, lstart) claim (R7); the lane's bound pid alive by `kill -0` and `KERN_PROC_PID` lstart (single-pid, never blocked by a blind `ps`); ack present; L not lane-owned; B's home token has ≥10 min of life (else wait for the refresh or heal); cooldown (§3.6). Duplicate-holder detection is the census's job and is advisory for swaps, since a swap starts no process. | 5 s | <0.5 s [E] |
| 3 | broker | `ledger.prepared` with fsync | — | <10 ms |
| 4 | broker | Read B's home item, build the access-only blob | `security` 2 s × 2 | 50-300 ms [E] |
| 5 | broker | §3.3 write order under `<L>/.storage-write.lock` | 5 s | 0.1-2 s [E] |
| 6 | broker | `ledger.committed{t_c, fp_B}`; `claude-accounts --assign B --unassign A --src lane` | — | <0.2 s |
| 7 | session | The next client build (main-loop step, subagent, classifier, compact, G3 §2) runs `wA`, sees the new mtime, runs `ox()` and reads B. An in-flight stream finishes on A (G3 §3). | **≤1 API call** | wall time = rest of the current tool call: p50 2-3 s, p90 311-477 s ([C] S06 §3, verifier) |
| 8 | server/CC | The first B request returns 404 `thread_not_found`; the client replays it as `create`; one prefix re-create | — | ≈225 ms [M P5] |
| 9 | proof.py | AC1-AC4. `proved`, or `SWAP-UNPROVEN` at 600 s (loud, not reverted, R19) | 600 s | seconds after step 7 |

**Order to commit:** about 2-5 s of mover time [E]. In API-call units, the change is always the
first request built after `t_c`. Exceptions: the `cache_touch` keepalive (≤240 s, `jLn` @9777402);
a `Khe` call in 429/5xx backoff (that one call); a request that joins an in-flight `j7` check (FM26).
**Revert** is the same write with `to=home(S)`.

**Refcounted GC:** lane L is removed (keychain item deleted, dir removed, ledger closed) only when
all of the following hold on 2 passes ≥60 s apart:
- no live (pid, lstart) has a bind ack or beat for L;
- no live process has L in its exec env (`env_keys`);
- no `<cfg>/jobs/*/state.json` `providerEnv` names L (S12 §1, G2 §b);
- no ledger row is open on L.

### 3.5 Limit-wall recovery

1. **Pre-wall drain (preferred).**
   - Inputs: the sensor (`~/.reso/lanes/measure/<sid>.json` from `session.measure.rateLimits`, which
     reflects the billed org once the first response after a swap lands, G3 §4); the statusline
     `rl5/rl7`; `claude-accounts --readout`.
   - The shed controller, not lr_recon, projects each account's 5 h and 7 d landing. lr_recon is
     excluded because `facts.py:12-13` says "usage % is never a limit signal".
   - Armed sessions on an account projected to wall within its horizon are swapped to accounts with
     headroom. A busy session moves in place, so the wall is never hit.
   - **Ownership and gates (patch pass).** Until this pass the drain was an automatic new mechanism
     with no wave, no switch and no AC. W8 is the C2/C3 rebalance and W7b the reactive rebill.
     `LR_REBAL_LANE` covers rebalance only. The existing `lr-shed.py` is shadow-only pending packet
     `76a584cc935b` and sheds idle sessions only (`lr-shed.py:3-6`).
     - It is now built in **W8** (`lr-shed.py`, a drain arm that picks only from armed rows).
     - Its own switch is `LR_LANE_DRAIN` with file twin `~/.reso/lanes/drain.off`, **default off**
       (§8).
     - **AC16** covers it.
     - It is ruled on separately as **Q10**. It is automatic and pre-emptive, so it is *not* the
       "limit recovery" that Q7(b) allows.
2. **Reactive (the wall was hit).**
   - A capped turn **ends**. 429 retries do not adopt a new bearer (§1.1 #13), so recovery always
     owes one turn.
   - lr_recon sees the `rate_limit` tail and attributes it to `billing_of(sid, t_err)`. This closes
     I1's critical row at `__main__.py:306-358`.
   - As the single actuator for limited rows (R7), it requests swap → B through the broker.
   - On `committed` it mails the sid. The pre-armed asyncRewake watchers (`hooks/mailbox-wake-arm.sh`,
     `hooks/net-recover-arm.sh`; proof doc `docs/research/api-error-rewake-proof-2026-09.md`, cited
     by A4) honour exit 2 after an api-error turn, and the synthesized turn bills to B.
   - A `/goal` in `usage_limit_waiting` resumes on any message (A4 [M I] @18097318).
   - With no watcher, the row goes to `hold:no-wake` and the incumbent typed nudge is used.
3. **Latency:** one detection pass + 2-5 s swap + wake [E], against a median of 81 min today
   (S05 §3, n=19). AC13 measures it at the first real wall. A4's P-L3 needs an account induced to
   cap, so it is not in W0.
4. **Un-laned sessions** keep the incumbent reconciler relaunch, unchanged.

### 3.6 Strand-aware rebalance

This is the 100p REPORT §4 design (C1-C3, C8, C9), **which is not built yet**: no `--rebal-band` and
no `lr_burn.py` exist in the tree [M `git grep`]. It is built here with a lane actuator.

- C1: `claude-accounts --rebal-band --json` gives sink, donor and corrected strand, attributed by
  billing.
- C2: `lr_burn.py` gives per-session pp/h by billing.
- C3: the sink arm in `lr-shed.py` actuates `cc-lane swap`.
- **Holds that vanish for armed rows:** mid-turn, background-job, subagents, goal-live, draft,
  focused, slots (S05 §2, class V).
- **Holds that stay:** un-armed (wait for re-home or the restart lane), duplicate/bg-split (R1),
  limited (owned by the reconciler, R7), intent and router (R11), team (the lane moves as a unit,
  priced on summed burn, R13).
- **Cost gate:** each move re-creates the conversation prefix once on the new org (P3/P5, "the same
  order as a resume"). A row moves only if `b_wk × min(sink_h,96) ≥ 10 × cost_pp` (100p C3).
  Cooldown is 6 h per session.
- **Stop rules:** moved burn ≤0.8 × capacity; sink 7 d landing ≤97%; 5 h landing ≤80%; overshoot
  breaker; no move-back after a reset.
- No filler sessions (R12). The donor arm sits behind its own switch, after one clean sink window.
- **Automatic** rebalance is gated by Q7. Operator orders and limit recovery are not.
  "Limit recovery" here means the **reactive** path after a wall (§3.5.2). The automatic pre-wall
  drain (§3.5.1) is gated by Q10 and `LR_LANE_DRAIN`, not by Q7(b).

### 3.7 Refresh ownership and the mirror (R21)

- Lanes never refresh. Each account's grant has exactly one holder: its home item.
- **A refresh path must always exist**, and there are exactly two:
  - (a) ≥1 **home reader**: an un-laned process with `CLAUDE_CONFIG_DIR=<home>`. CC refreshes the
    item itself in the 5-min window (`JP`, S14 §5). The mirror follows that refresh within a 1 s poll.
  - (b) zero home readers: the heal guard runs `claude-accounts --heal-for-lanes <acct>` 15 min before
    `expiresAt`. That is the existing official-binary refresh (`claude auth login` with
    `CLAUDE_CODE_OAUTH_REFRESH_TOKEN`, `bin/claude-accounts:24-31`), run under
    `/tmp/claude-accounts-heal-<acct>.lock` and a marker `~/.reso/lanes/heal-in-flight-<acct>`. The
    broker re-mirrors **synchronously** after it returns.
- **The heal gate counts home readers as:** live claude processes with `CLAUDE_CONFIG_DIR=<home>`,
  minus those with a current bind ack and a beat showing `lane_env≠null`.
  - An unreadable census, bind table or beat **refuses** the heal (`k_live=None` semantics,
    `bin/claude-accounts:1940-1965`).
  - I1 §2 asked for "exclude processes whose env carries the lane"; that alone is blind to
    retrofitted sessions (FM57).
- **Admission invariant: every account has a refresh path** (patch pass). The broker refuses to
  `arm` or `bind` a session that is its account's **last home reader** unless `LR_LANE_HEAL` is on
  **and** the ledger shows a successful `--heal-for-lanes` for that account. Without this, R2
  `cc-lane arm --all-live` plus W9's `CC_LANE` on would leave every account with zero home readers
  while heal defaults off (§8). Nothing would then refresh any account, and every lane would expire
  within ≤8 h (G1 §2 expiries 03:51-07:01 CDT). "Excluded as a target" only stops new moves.
  - The broker writes `<L>/state.json.refresh_path` ∈ {`home-reader`, `heal`, `none`} for the
    lane's billing account on every pass. The module acts on `none` (§3.11).
- **R16:** heal, `cc-relogin` and every claude-spawning helper **unset** `CLAUDE_SECURESTORAGE_CONFIG_DIR`
  explicitly. A claude-accounts run inherited from a laned pane would otherwise write the rotated
  grant into the lane (FM48).
- **Revoke-on-refresh (P9, RESULTED 03:58-04:00 CDT, P-probes:162-176):**
  - **Measured:** an account's own refresh revokes **every** copy of its previous access token at
    once. In the log, the old token returned `OAuth token revoked` 8 s after the refresh and again
    2 min later, and the new token returned OK.
  - **The 401 tolerance of a null-refresh lane is ≈1.5-2.5 s [E].** It is computed from source: the
    first 401, then one `LF` backoff (500 ms ±25%, `me=500` @3751360), then one same-token retry. The
    throw `api_request_oauth_refresh_exhausted` fires once `++Te>=wur` (`wur=2`, throw @12388522).
    `y$` returns false for null-refresh stores (@4661639), so no keychain recovery helps. That
    **turn is lost**, which fails the DoD's "0 lost turns" and AC3.
  - **Why the current mirror does not meet it.** The mirror (a kqueue wake plus a 1 s poll) and the
    steady-state heal ("synchronous re-mirror a few seconds later [E]") must rewrite **every** lane of
    the account. next4 alone has 19 live sessions (S06 §4). Each lane is keychain-primary, so each
    rewrite is a `security` write budgeted at 2 s × 2 (R10) under load 300-900, plus the heal path's
    `claude auth login` subprocess (90 s budget). So each refresh, about every 8 h per account [M:
    28,773 s lifetime, P9], can fail the turn of every laned session that sends a request inside that
    window [I].
  - **Arm-all makes it worse before any move.** Today's home readers recover from a sibling's refresh
    through the `y$` keychain path. R2/R3 "billing-neutral" arm-all turns them into copy readers that
    the same refresh revokes (§3.9).
  - **Structural status: none yet for per-session copy lanes** (FM19/FM46). The candidates are M31
    (pointer lanes: no copy, and P9 does not apply) and M32 (one shared copy per account: 1 write per
    refresh). §2 gives the falsifiers.
  - **If per-session copy lanes are kept:** W0 adds **P-L5**. It measures home-item refresh → last
    lane rewritten for a 19-lane account at load ≥600, against the measured 401 tolerance. The refresh
    is simulated by rewriting a throwaway home item for a `/tmp` dir, never a real home item, and the
    lanes are throwaway items. R2 arm-all and `LR_LANE_MOVE` are gated on a
    P-L5 PASS (§3.9, §8).
  - **Fan-out order — fix not applied as written.** The fix said to write the file legs (renames)
    before the per-lane `security` writes. The store reads the keychain first and the file only on
    null (S14 §2, @3743527), so a file-first rename would make `ox()` re-read the old, revoked keychain
    token. A keychain write that then times out would leave file=new and keychain=old indefinitely.
    The §3.3 order stays. To shorten the fan-out, batch all lanes' `add-generic-password -U` lines
    into **one** `security -i` process [I] (the 4,032-char limit is per line), then do the renames.
  - P-L2 still measures 401s per lane in rollout.

### 3.8 Identity handling

- **Keys:**
  - `home(S)`: the config dir the process runs under. It changes only at launch or re-home.
  - `billing(S,t)`: from the ledger, cross-checked against the lane fp.
  - `identity(S)` ∈ {home, billing, unknown}.
- **Why identity is a set and not one value.** `metadata.user_id.account_uuid = iL()||Mn()` (`KWe`
  @8876312). It starts at home and stays there across a swap (P6). An incidental bootstrap (a model
  change, `aan` @18400845) can restamp it to billing. A later `kn()`, such as on a 401, nulls `iL()`
  and it falls back to home `Mn()` (G4, verifier). It is not observable on disk without an observer
  proxy, so the design never asserts an exact value.
- Every BILLING consumer reads `billing_of`. STORE and KEYCHAIN consumers keep `home`, tagged
  `# acct:home` (I1 §0). Nothing defaults `unknown` to home (R5).
- **Re-home** happens at natural boundaries:
  - B1: operator `--resume` (Q5).
  - B2: reconciler or crash revival.
  - B3: reboot mass resume (every ~5 d, A4 [M E]).
  - B4: upgrade respawn.
  - B5: `/handoff` recycle.
  - B6: idle ≥30 min, cold-only (Q6).
  - **Never B7 (`--bg` jobs):** a cross-supervisor relaunch makes two writers (S12 §3).
- **Re-home preconditions** (fail-closed):
  - source proven dead (R1);
  - no live `jobs/<short>/state.json` or daemon-roster entry for the sid in the source dir (the
    bg-daemon re-claim guard, FM58);
  - no open claim;
  - transcript sha-verified after the cold transplant;
  - the source is retired only on confirm (S05 §1.6).
- **At launch on `dir(billing)`** the startup bootstrap stamps the bearer's account (`ot()`
  @18239236). If the prefetch is suppressed (`Oqe()` with an own-org slot), `account_uuid` comes from
  the target dir's own `oauthAccount`. That is also the billing account, so both routes agree
  (verifier). P-L4 certifies this per CC version.
- **Mismatch window** (move → next re-home) [E, launch.log renewal residual, 680 rows]: A4 measured
  median 17.4 h and p90 47.1 h. Recomputed without the restarts lanes remove: median 19-20 h, p90
  68-115 h (two verifiers). **Treat it as lower-side.** Live accrual: `cc-lane report --mismatch`
  over `committed → rehomed`.
- **Not done (R18):** body rewrite, proxy, forged 401, external `oauthAccount` or slot rewrites
  (M26), forced re-home right after a swap (that is M2 with its losses).

### 3.9 Rollout for already-running sessions (P10 retrofit)

| stage | act | effect on live sessions |
|---|---|---|
| R0 | Land W1-W8 with every switch at its default (§8). Converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. The live mod is `~/.claude/mods/accounts-readout → ~/Development/claude-infrastructure/mods/accounts-readout` [M `readlink`], so converging changes the loaded files. | Every session that loaded the mod (40/42 [M P-probes:129]) reloads `lane-bind.ts` at its next turn end. **Inert:** no bind order, so no env change. Beat files appear with `lane_env:null` (AC5a). |
| R1 | Operator rules on Q1/Q2 **and Q4**, runs migration W9 (broker loaded), `touch` removes `bind.off`. The refresh-path admission invariant (§3.7) is live from the first arm. | none yet |
| R2 | `cc-lane arm --all-live`: for each live sid, a lane seeded with an access-only mirror of **home(S)**'s token, plus a bind order. **Billing-neutral.** **Gated on a P-L5 PASS** (patch pass). Arm-all turns home readers, which recover from a sibling's refresh through `y$`, into copy readers that the refresh revokes (P9, §3.7). The broker skips an account's last home reader unless heal is on and has succeeded for that account. | none until binding; after binding, exposure to P9 on every refresh |
| R3 | The module binds when it sees an order: at `tool.call`/`turn.step` (needs P-F1). If P-F1 fails, it binds at the next reload: land a version bump of the mod, which re-fires `session.start` at each turn end (P10). It calls `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', L)`, then writes the ack and the beat. The next `wA` sees the lane file and adopts it (@4658281). | the session reads the lane holding the same account: no billing change |
| R4 | `LR_LANE_MOVE=on` (`rm move.off`). **Gated on** a P-L5 PASS (or a W0 switch to M31/M32, §2) and on `cert/<installed VERSION>.json` = PASS (AC17). | busy sessions move within 1 API call |

**Coverage of the 01:55 cohort** [C S06 §2-3]:
- Retrofittable at their next `end_turn`: 216 `2b3becea`, 271 `502bd860` (5 end_turns in 305
  records), 274 `7396b781`, 301 `88fc8283`, 309 `06457213`, 303 `cf477fab`.
- **Not reachable:** 217 `15f652bd` and 194 `2a707a01` have **zero** `end_turn` records in their
  whole transcripts. They move only at their first turn end, at a natural restart (re-home arms them),
  or on an explicit `--restart-now` order (M2, Q3).
- Sessions without the mod (2/42) arm at their next launch.

**Before R3 is enabled:** P-R1 must pass. P10 measured lane→lane only; home-keychain→lane is
inferred from `wA` and `ox()`.

### 3.10 ps-free census (S07 design)

- `proctable.read_table`:
  - one `sysctl KERN_PROC_ALL` (3.3 ms for 2,167 rows at load 624) for pid, ppid, zombie, lstart and
    tdev, **including** the root-owned `login` pane roots;
  - a `/dev` `st_rdev` tty map (0.7 ms);
  - `ArgsReader` over `KERN_PROCARGS2`, claude-family first (9 ms for 93 processes), with
    `ARGS_CALL_S=0.5`, `ARGS_BUDGET_S=3.0`, `STUCK_MAX=2`;
  - ps-identical `strvis` rendering.
- **Fail-closed:** an unread claude-family args value marks `degraded:ps-args <pid>`, and only that row
  abstains. It is never rendered `(comm)`, which would undercount holders. `claude_count` is by
  `comm`.
- **Modes:** `LR_RECON_PSFREE=off|shadow|on` plus `recon/ps-free.off`. Shadow writes
  `recon/shadow/ps-free.jsonl` (field mismatch counts and token-list hashes, never argv or env text).
  It switches to `on` after N=500 passes with 0 ppid/zombie/lstart/tty mismatches and 0 claude-family
  token mismatches. 24 args mismatches are still unexplained (S07 §4).
- **Additions here:**
  - `proc_lstart(pid)` for every prove-death and admission check;
  - `env_keys` extracting two keys only, never logged, because the env block can hold secrets;
  - per-call duration logging, because `KERN_PROCARGS2` under a real stall is unmeasured (S07 §7).
- **Consumers:** lr_recon `observe.read_ps`, re-home preconditions, GC, the heal gate (it replaces the
  `ps` that made heal "UNMEASURABLE"), and `cc-proctable --holders/--alive` for shell callers.
- **Status:** an availability improvement. Safety comes from abstaining (§1.1 #5).

### 3.11 Broker death and the fail-safe unbind

- **Broker death:** live sessions keep reading their lanes, and new moves stop. Lanes go stale only
  when a home token refreshes, so the fuse is ≥5 min after the next refresh, about 8 h per account.
  launchd KeepAlive respawns the broker. **P9 RESULTED:** a copy is revoked **at** the home refresh,
  not 5 min later. The home refreshes inside `JP` (the last 5 min), and the fail-safe acts at <10 min
  of life, so the unbind has to come first. The guard runs before every request, so a session idle
  through that band still unbinds before its next request. Only a request (or `Khe` retry chain)
  already in flight across the refresh instant is exposed (FM19) [I].
- **The module guards each request** (`turn.step`). It stats `~/.reso/lanes/broker.beat` and reads
  `<L>/state.json` (`expires_at`, non-secret). If the beat is stale >120 s **and** the lane token
  expires within 10 min:
  - it calls `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', undefined)` (`EIo` deletes the key);
  - the session falls back to its home item, which holds the refresh token. It adopts within 30 s,
    because the keychain cache is keyed by host (G2 §b). Tertiary's stale file makes it immediate;
  - it writes beat `unbound-failsafe` and pages.
- **Second trigger: no refresher (patch pass).** The module does the same unbind when
  `<L>/state.json.refresh_path` is `none` **and** the lane token has <10 min of life, even with a
  fresh beat. Before this pass the fail-safe fired only on a stale beat, never when the broker was
  alive but no refresher existed (heal off, zero home readers), and AC11 only paged. The beat records
  the cause as `unbound-failsafe:no-refresher`.
- **Hysteresis:** the module never re-binds by itself. Only a newer broker order re-binds it.
- **Heal coordination:** the unbind defers while `heal-in-flight-<acct>` exists, so it cannot race a
  heal.
- If the broker is dead and billing ≠ home, the unbind reverts billing to home. That is loud, and
  correct over a lane that is about to fail.

---

## 4. Invariants R1-R22

- **R1, one writer per sid at every instant.** Moves start no process. Every relaunch (re-home,
  restart-now) first proves source death: `kill -0` fails, or `KERN_PROC_PID` lstart differs, **and**
  no `--resume <sid>` argv holder appears on 2 passes ≥1 s apart. It also needs no live bg-daemon job
  or roster entry for the sid in the source dir. `duplicate`/`bg-split` rows hold. (S05 §5.1;
  `lr-upgrade.sh:1407-1421`.)
- **R2, no in-flight work destroyed.** The swap path has no `/exit`, kill or keystroke code. The only
  lossy path is operator-explicit `--restart-now`.
- **R3, content-verified.** A ledger `committed` exists only after fingerprint read-back of both
  legs. Re-home transplants are sha-verified, and the source is retired only on confirm. A verdict
  that "it moved" from a write's return code alone is forbidden.
- **R4, verdicts come from disk and process facts and can be re-derived.** "Billed to B" means lane
  fp plus a post-commit request in the transcript, with measure/statusline as corroboration. It is
  never prose. **Patch pass:** lane fp plus a post-commit request prove only that the broker wrote
  B's token and the session kept working. They do not prove which org was billed. `proved` therefore
  also needs an **account-specific witness**: a `~/.reso/lanes/measure/<sid>.json` record written
  after t_c whose `seven_day.resetsAt` (tie-break `five_hour.resetsAt`) equals B's reset instant from
  `claude-accounts --json` and differs from A's. Each `rateLimits` entry carries the server's
  `resets_at` (`kue` @11504180), and each account's resets are its own. With no such record, the
  verdict is `SWAP-UNPROVEN`. That includes a null `resets_at`, which the endpoint returns right after
  a weekly reset (`bin/claude-accounts:3605-3614`), and an A/B tie on both windows.
- **R5, absence is loud.** `unknown` attribution, a missing ack or beat, a stale broker beat,
  `SWAP-UNPROVEN`, `degraded:ps-args`, `hold:no-wake`, `unbound-failsafe` and `lane-owned` each page
  once **to a read channel** (operator mail and readout). launchd stderr is not a read channel (rules:
  "Loud into a dead log"). None defaults to home.
- **R6, refuse before the point of no return.** All admission happens before `ledger.prepared`
  (fsync). A committed swap is reversible by the same write.
- **R7, one actuator per session.**
  - The broker is the sole writer of lane content: single flight per lane, (pid, lstart) claim.
  - The module is the sole writer of the process's lane binding, and acts only on a broker order or
    the fail-safe condition.
  - lr_recon owns limited rows and requests swaps through the broker.
- **R8, credential safety.**
  - One grant per account, in its home item.
  - Lanes are access-only. CC's `.storage-write.lock` is honored.
  - `security` always gets `-a chrisren` (a second `136fa815` item has acct=unknown, G2-keychain)
    and always uses stdin `-i`.
  - Fingerprints only (sha256[:16]). No token is printed or logged.
- **R9, one time-aware attribution source.** `ledger.jsonl` → `billing.py`.
- **R10, bounded external calls under load 300-900.**
  - `security`: 2 s × 2.
  - broker request: 30 s budget.
  - proctable: 0.5 s per call and 3 s per pass.
  - heal: 90 s.
  - The swap path makes no `/bin/ps` and no kitty socket calls.
- **R11, operator authority.** Intent is re-read at admission. The router fails closed. Env plus file
  kill switches exist. Settings change only via numbered migrations. Nothing is typed into a session
  the system does not own: the wake rides the session's own pre-armed watcher.
- **R12, no filler sessions.** The design launches nothing. Heal is a token refresh. There is no
  token-keeper session (A2 D6 rejected).
- **R13, teams move as a unit.** In-process teammates share `process.env`. Pane teammates and `--bg`
  jobs spawned after binding inherit the lane path (`H()` @36021704, `pHt` @16378899). The
  shared-lane guard exempts inherited children (by ppid chain or job state).
- **R14, fail closed on binary drift.** `cc-lane arm/bind` refuses a CC version that has no
  `cert/<ver>.json` PASS. Anchors: `uw` @3737607, `wA` @4658281, `y$` @4661639, `Khe` @12387081,
  `KWe` @8876312, `EN` @8641537, `EIo` @11552107, plus the W0 probes. On refusal the module stays
  inert. **Patch pass:** these offsets are 2.1.293-only, and W0 used to produce only
  `cert/2.1.293.json`. Decision packet `5a7554481183` has already ruled a `/cc-upgrade` to the newest
  gate-passing release ≥2.1.301 after 2026-10-22T14:34Z
  (`docs/research/startup-hooks-2026-10-18/W6-cc-2.1.294-2.1.304-audit.md:3-5`). The 2.1.306, 2.1.308
  and 2.1.310 binaries are on disk, and 2.1.310 renames the change-check (`sA`) and adds the `VRe()`
  gate. So W0 is binary-parametric: `run.py --all --binary <path>` locates anchors by regex over
  function shape, not by byte offset. `lib/cc-upgrade-gate/check18_lanes.sh` writes
  `cert/<ver>.json` for the candidate before the pin moves. Without a cert, the upgrade leaves every
  new launch and re-home un-laned: fail-closed, but dark. AC17 pages on it.
- **R15, lanes are mirrors, never sources.** A lane holding a non-null `refreshToken` is frozen as
  `lane-owned` (FM49).
- **R16, every child-spawning setter of `CLAUDE_CONFIG_DIR` also sets or unsets the lane variable
  explicitly.** A repo test greps for violations.
- **R17, a move never causes a restart.** Restarts come only from natural boundaries or an explicit
  `--restart-now`.
- **R18, identity is never re-aligned by** body rewrite, proxy, forged 401, or external
  `oauthAccount`/slot writes.
- **R19, a non-verdict is not red.** `SWAP-UNPROVEN`, `degraded` and `unknown` are distinct from
  `FAILED`. They page, are never auto-reverted, and are never counted as failures. Conversely, no
  fail-safe default may render as the healthy state (rules: "Fail-safe mimics healthy").
- **R20, the module is inert by default.** It binds only on an order for its own `$.session.id()`
  whose lane `state.json` is `ready`. Any exception means no env change (catch → `next(e)`, the
  existing mod's pattern).
- **R21, refresh ownership is total** (§3.7). The heal gate refuses on unknown. Every account keeps
  a refresh path as an admission invariant: no arm or bind of an account's last home reader without
  heal on and a ledger heal success. `state.json.refresh_path` drives the `none` fail-safe (§3.11).
- **R22, one source of liveness for lanes.** Bind ack plus beat plus (pid, lstart). The exec-time env
  alone never proves binding.

---

## 5. Measured constants

| constant | value | source |
|---|---|---|
| inter-turn gap p10 / p50 / p90 | 0.0 / 6.3 / 1573 s (n=268) | [M] S06 §3 |
| mid-turn share of wall time (20 sessions, 3 h) | 0.668; 11/20 ≥0.998 | [M] S06 §3 |
| sessions with zero `end_turn` in the whole transcript | 4 of 20 (15f652bd, 2a707a01, ba56f290, 28a7b735) | [M] S06 §3 |
| automated turn restarts | 258/268 (96%) | [M] S06 §3 |
| tool-exec p50 / p90 / max | 3 / 477 / 5528 s (n=1237); 2.0 / 311 / 5528 s (n=1520) | [M] S06 §3; verifier |
| mean wait to the next tool boundary at a random instant | 421 s; 93% of tool time is in calls >120 s | [M] verifier, sum(d²)/2sum(d) |
| busy/goal move rate, incumbent | 5/149 (3.4%) | [M] S06 §1b |
| incumbent actuate→proof p50 / p90 / max | 207 / 823 / 1396 s (n=47) | [C] S05 §3 |
| incumbent cache write on the first post-move turn | 273,235-479,138 tokens | [C] S05 §3 |
| recovery latency, detection → ENGAGED | median 81 min (n=19) | [C] S05 §3 |
| live sessions by registry (07:16Z) | next 6, next2 2, next3 9, next4 19 (36); 40 claude processes | [M] S06 §4 |
| processes loading the accounts-readout mod | 40 of 42 interactive | [M] P-probes:129-132 |
| mod reload latency | edit t+3.0 s → reload at turn end ≈t+29 s | [M] P10 |
| lane swap adoption | call 2, ≈4.5 s after the rewrite | [M] P4 |
| cross-org first-call cost | one 404 ≈225 ms; prefix re-create 6.2-8.4K tokens (probe) | [M] P3, P5 |
| P2 degradation behind a non-first-party URL | 89,031 vs 49,164 request bytes | [M] P2 |
| dead local hop | retried 11-12× | [M] P1 |
| keychain read cache `cPt` | 30,000 ms per host | [C] S14 @3738141 |
| keychain read failure back-off `fyo` | 1,000 ms | [C] S14 |
| `security` timeout / `-i` length limit | 2,000 ms / 4,032 chars, then argv | [C] G2-keychain, S14 §2 |
| `.storage-write.lock` | mkdir; stale 15,000 ms; 10 retries 100-1000 ms | [C] G2-keychain @3741539 |
| expiry window `JP` | 300,000 ms | [C] S14 §5 |
| `cache_touch` client cache `jLn` | 240,000 ms | [C] G3 @9777402 |
| 401 same-token retry bound `wur` | 2; the throw `api_request_oauth_refresh_exhausted` fires at `++Te>=wur` | [M] @12384871, throw @12388522 |
| **P9: refresh revokes the previous access token** | **RESULTED: yes, at once.** Old token `revoked` 8 s and 2 min after the refresh; new token OK | [M] P-probes:162-170 (03:58-04:00 CDT) |
| access-token lifetime after a refresh | 28,773 s (≈8 h) | [M] P9 log |
| 401 retry backoff `LF` | base 500 ms (`me=500`), proportional jitter ±25% | [M] @3751360 |
| 401 tolerance of a null-refresh lane | ≈1.5-2.5 s from the first 401 to the lost request | [E] one `LF` backoff plus two request round trips at load |
| `session.measure.rateLimits` entry | `{kind, percentUsed, resetsAt}`; push gate ignores `resetsAt`, threshold 1 pp | [M] `kue` @11504180, `xn` @26019398 |
| 401 zombie-exit (`AUTH_FAIL_EXIT_MS`) | 600,000 ms, remote children only | [M] @4661369 |
| `.claude.json` watch interval | 1,000 ms | [C] G4 @4544408 |
| census `KERN_PROC_ALL` | 3.3 ms, 2,167 rows, load 624 | [M] S07 §4 |
| claude-family args read | 8.8 ms / 93 processes; all same-uid 0.40-0.63 s | [M] S07 §4 |
| `/bin/ps` worst case | 42 s timeouts; 97 ps-degraded abstains; 15 blind passes (22:43-22:56 CDT 10-24) | [M] S07 §5 |
| ps-degraded share | 56/4,820 passes (1.2%); 84 had a timeout | [M] S07 §5 |
| `security dump-keychain` under load 742 | timed out at 55 s | [M] G2-keychain |
| access-token expiry (sample) | next 03:51, next2 07:01, next3 04:02, next4 06:38 CDT 10-25 | [M] G1 §2 |
| **refresh-token cliffs** | next 11-19, **next2 10-31**, next3 11-19, **next4 11-02** | [M] G1 §2 |
| orgs | four distinct personal `claude_max` orgs: next 260ebc56, next2 fb09ef51, next3 1a71eca0, next4 c570be13 | [M] G2-org |
| keychain items | 35 `Claude Code-credentials*`; ACL trusts `/usr/bin/security` | [M] G2-keychain |
| launch.log | 680 rows, 2026-09-29 → 10-25; mass resumes about every 5 d | [M] A4 B, E |
| mismatch window [E] | median 17.4-20 h; p90 47-115 h (lower-side) | A4 D; verifiers |
| policy | M1 75%; M3/M6 60%; M2/M7 45%/70% | [C] S08 §4 |

---

## 6. Failure-mode table: every observed mode and its structural answer

FM1-FM42 carry over from A4 §14 with the answers below, re-pointed where this design differs.

| # | observed mode (source) | structural answer |
|---|---|---|
| 1 | Busy sessions never move: 149 rows → 5 MOVED; 56/56, 57/57, 67/67 mid-turn snapshots (S06) | An armed row has no wait. The swap is adopted at the next call. |
| 2 | `/exit` kills the in-flight turn (handoff-fire:20757) | The swap path has no `/exit` (R17) |
| 3 | Forks: 13 FAILED, bg SPLIT-BRAIN, P8 | Same process for swaps. R1 barrier for relaunches. |
| 4 | STRANDED (12) | No relaunch on a move. A re-home strand is retried on the target. The source is retired only on confirm. |
| 5 | Husks, half-moved, stale tombstones | Moves never transplant. Re-home transplants cold (source dead). |
| 6 | Subagents killed; `killed_inflight` unaudited | Subagents share the process and the lane (G3 row 2) |
| 7 | bg jobs die (P7) | Same process. `--bg` jobs keep the lane path through `providerEnv`. |
| 8 | `/goal` dies or is held (45 `hold:goal-live`) | The goal stays in-process. The wake resumes `usage_limit_waiting`. |
| 9 | Team killed on lead exit | No exit. The lane moves as a unit (R13). |
| 10 | Drafts merged, pasted text lost | No keystrokes |
| 11 | Cache rewrite 273K-479K per move | One prefix re-create per move, priced into the cost gate with a 6 h cooldown. Re-home is cache-neutral. |
| 12 | Outage 58-129 s per move | None. Mover time is 2-5 s [E]. |
| 13 | Lane overhead (slot-wait, HELD:load, kitty, focus) | None of those stages exist on `act=swap` |
| 14 | Recovery median 81 min | Pre-wall drain (W8, `LR_LANE_DRAIN`, Q10, AC16); reactive swap plus wake (§3.5) |
| 15 | Owes a turn after a cap | Wake through the pre-armed watcher; `hold:no-wake` falls back to the nudge |
| 16 | `ps` blind for 15 passes | proctable; row-local abstain |
| 17 | `KERN_PROCARGS2` may stall | Bounded thread. Swaps need only single-pid checks (§3.4). |
| 18 | Refresh rotation and the `invalid_grant` erase | Access-only lanes; one grant holder (R8, R15) |
| 19 | Old access token revoked on refresh (P9, **RESULTED**: revoked at once, P-probes:162-176) | **No structural answer yet** for per-session copy lanes. The listed answer (broker-driven refresh plus synchronous re-mirror; the 1 s poll in the window; `Khe` rebuild, `wur=2`) has to rewrite every lane of the account within ≈1.5-2.5 s [E]. With 19 lanes on next4 at 2 s × 2 per `security` write, it cannot be shown to do so (§3.7). Candidates: M31 pointer lanes (no copy) and M32 shared copy (1 write). Gate: P-L5. |
| 20 | Account with no home reader → lanes expire | R21 heal guard |
| 21 | Tertiary's stale `.credentials.json` pins the memo | Lane dirs are separate. The fail-safe unbind to tertiary is immediate (mtime differs). Renaming the file is operator housekeeping (§12). |
| 22 | Client `mutate` on a file-only store deletes the file (@3743013) | Keychain-primary lane, pre-created at arm |
| 23 | `security` timeout under load (55 s observed for a dump) | The file leg holds the same blob, and CC falls back to the file. The broker aborts before the point of no return. Rules: "Launch hang = keychain". |
| 24 | An in-flight request finishes on the old bearer (G3 §3) | Accepted: it is "the 1 call" |
| 25 | 429/5xx backoff inside one `Khe` reuses the old client | Accepted: one call. A cap ends the turn (§3.5). |
| 26 | `cache_touch` keeps an old client ≤240 s; a request that joined an in-flight `j7` | Accepted: a keepalive is not a generation |
| 27 | 404 `thread_not_found` on the first call to a new org | The client's thread layer replays it (`Hhe` @12372944) |
| 28 | Identity mismatch (P6, G4) | Re-home (§3.8). Identity is modeled as a set. |
| 29 | Usage meter keyed on the old uuid | Cosmetic. Controllers read the ledger. The statusline shows `home→billing`. |
| 30 | Bridge/RC captured-token helpers | Residual until re-home (G3 row 5e) |
| 31 | MCP OAuth tokens live in the same blob | Mirror `mcpOAuth` access-only from home (Q8) |
| 32 | `/login` in a laned pane writes the grant into the lane | See FM49 |
| 33 | `/logout` in a laned pane deletes the lane item | `unknown` plus a page. Never re-armed silently. |
| 34 | Nested `claude` or heal inherits the lane | R16 |
| 35 | Two sessions on one lane | Launchers always call `cc_lane_env`. The shared-lane guard exempts inherited children (R13). |
| 36 | Settings `env` live rebind | Forbidden (M25) |
| 37 | Dispatch identity lost on transplanted panes | Moves keep pane, pid and registry row. Re-home reuses the launcher's re-registration (rules: "Transplant loses dispatch identity"). |
| 38 | Duplicate/orphan keychain items (G1 §1) | Lanes are named by the sha256 of a `~/.reso/lanes` path. `-a chrisren` always. |
| 39 | exit-readback / composer / bg-work-dialog holds | Not reachable on the swap path |
| 40 | Router refusal | Admission refusal before `prepared` |
| 41 | P1 dead local hop | No local hop (M6) |
| 42 | P2 degradation | Not applicable (first-party host) |
| 43 | The retrofit cannot reach a session that never ends a turn (S06: 4/20) | Wait for its first turn end or a natural restart (re-home arms it), or an explicit `--restart-now` (Q3) |
| 44 | Binding to an empty or unready lane would log the session out | The module binds only if `<L>/state.json.ready` is true and its fp equals the fp the order names. The broker writes `ready` after content-verified seeding (R20). |
| 45 | Broker dead and the lane token expiring | KeepAlive; the module's fail-safe unbind before expiry (§3.11); `cc-lane status` min-life page (AC11) |
| 46 | 401 on a lane: `y$` returns false for a null refresh token (@4661639) | `Khe` rebuilds and retries; the mirror must land within `wur=2`; refresh made synchronous with the re-mirror (§3.7). **No structural answer yet** (P9 RESULTED): one `LF` backoff of 500 ms ±25% and then the turn is lost (@12388522). Gated by P-L5; dissolved by M31. |
| 47 | Refresher gap once every session of an account is laned | R21, plus the admission invariant: no arm or bind of an account's last home reader without heal on and a ledger heal success; the `refresh_path=none` fail-safe unbind (§3.7, §3.11) |
| 48 | Heal's `os.environ.copy()` inherits the lane variable | R16 unset in heal and `cc-relogin` |
| 49 | Operator `/login` inside a laned pane near the login cliffs (next2 10-31, next4 11-02): the new grant lands in the lane | `lane-owned` detection at every mirror pass: freeze the lane, page, and offer `cc-lane promote --lane L`, which writes the lane's grant into the home item under both `.storage-write` locks and the home `.oauth_refresh.lock`, then makes the lane access-only. The runbook says re-login through `cc-relogin`, which scrubs the lane variable. |
| 50 | GC removes a lane that a `--bg` job or pane teammate still uses (verifier) | Refcounted GC (§3.4); the mirror serves every referenced lane |
| 51 | Shared-lane guard fires on legitimate children | Exemption by ppid chain or job state (R13) |
| 52 | Keychain write timed out but landed | Read-back fp decides: commit, abort, or `unknown` (§3.3) |
| 53 | `security` argv fallback exposes the hex in `ps` (>4,032 chars) | The broker never uses argv; abort loudly; minimal blob |
| 54 | Second `136fa815` item with acct=unknown | `-a chrisren` (R8) |
| 55 | The mirror's kqueue fires on the broker's own lane writes | It reacts only to a home-item mdat change (attribute read, no `-w`) |
| 56 | Any landing on the mod reloads ~40 sessions at once | The module is inert by default, wrapped in try/catch, and has the `bind.off` kill file. W4 gates on `claude plugin validate` plus the mod test suite. |
| 57 | Census cannot see a retrofit binding (`KERN_PROCARGS2` shows the exec-time env) [I] | Bind ack plus beat are authoritative (R22) |
| 58 | bg-daemon re-claims a job minutes after a stop (`lr-upgrade.sh:1407-1421`) | Re-home and restart-now refuse while a jobs/roster entry is live (R1) |
| 59 | `--restart-now` kills a running ship-land | `ship-land` traps TERM → `rollback_clean` → `git rebase --abort`. A SIGKILL backstop may leave a rebase, and the next run refuses until it is aborted. The cost is re-gate time; nothing is applied twice (verifier). |
| 60 | A tool-boundary trigger waits minutes | Not used (§1.1 #1) |
| 61 | Identity flips A↔B in one process (`kn()` → `Mn()`) | Identity is modeled as a set; re-home ends it |
| 62 | Mismatch window longer than estimated | B6 idle re-home (Q6); accrual from the ledger |
| 63 | Restart-now kill lands inside a refresh POST→keychain-write window | Take the source's `.oauth_refresh.lock` first (bounded 10 s) [I] |
| 64 | A CC upgrade turns on storageV5 (`probeCredentials`) or moves anchors | R14 certification per version. A refused arm leaves stock behavior. The ruled ≥2.1.301 upgrade (packet `5a7554481183`) is pending, and 2.1.310 already moves the change-check (`sA`, `VRe`). So `check18_lanes.sh` certifies the candidate before the pin moves, and AC17 pages when the installed version has no cert. |
| 65 | After an unbind, the keychain cache serves the lane blob ≤30 s | Accepted: the token is still valid by the fail-safe's 10 min margin |
| 66 | Symlinked lane path | Broker hygiene (A1, §3.3) |
| 67 | `session.measure` shape differs from the inference | Sensor is corroboration only, never a gate (AC1). P-S1 checks it. **Superseded in the patch pass:** the shape is now read (`kue` @11504180), and the `resetsAt` match is the `proved` gate (R4, AC1). A shape or semantics drift therefore yields `SWAP-UNPROVEN`, never a false `SWAPPED`. |
| 68 | `cc-reaper` kills a launchd-parented bash older than 600 s | The broker is python |
| 69 | "Engaged" taken for "running" after a re-home | AC6 witnesses (pid, lstart) on 2 reads ≥5 s apart |
| 70 | Two lanes on one account plus that account's own refresh | P-L2 counts 401s per lane |
| 71 | Rollback reverts the module but live env bindings persist (a reload does not unset env) | Rollback order is unbind-all, confirm beats, then revert code (§8) |
| 72 | Server treats the cross-org bearer/metadata mismatch as abuse | Unknowable from source. Policy gate Q1. Re-home bounds it. Ban-signal watch (§12). |

---

## 7. Rejected alternatives

| alternative | reason |
|---|---|
| **A3 Restart, Perfected, as the primary mover** | Misses 3 of 4 DoD clauses by construction. Its tool-boundary timing, fork guard, identity, credential and census premises were refuted (§1.1 #1-6). It is kept as the explicit `--restart-now` fallback. |
| **A2 Network router (M7)** | A correlated single point of failure for ~36 sessions with no true fail-open (A2 §11). P2 degradation; threads and RC off. Moderate-High policy exposure and the one public ban (S09 #529). |
| A2 transparent 429 failover | Needs M7. Replaced by the pre-wall drain. |
| A2 token-keeper session (D6) | Close to the filler veto (R12). Replaced by heal-for-lanes. |
| A1 drain-only rollout | Superseded by the P10 retrofit |
| A1 "local-refresh is the refresher" | False (§1.1 #12) |
| A1 `expiresAt:null` | Unmeasured; the measured form uses the real expiry |
| A1 M5 whole-dir fallback at a cap | Moves siblings; refresh collision |
| **A4 Arm T** (access-only park of `next`'s live home item) | Discards rotated grants for six live `next` sessions, leading to invalid_grant and logout (verifier). Moves idle siblings. Superseded by P10. |
| A4 D1(b) beacon-only lane | Unprobed. A keychain stall would read as logged out. Q2(b) only after P-L1. |
| A4 "body rewrite breaks cch" (reason) | Wrong reason (§1.1 #16). The body rewrite stays rejected on policy grounds. |
| A5 (not delivered) | No architecture. Its policy gate is grafted (Q1). |
| File-only lane (P4 shape) | A client `mutate` deletes the file (@3743013) |
| M14a: env token through the mod | The token propagates into every child's env; `Pfs` pins it |
| Observer proxy in production | Turns off threads and RC (P2). Probe-only. |
| G2-bootstrap R1 ordered identity re-sync | Per-dir, poisoning, write-once suppression; R18 |
| Forced re-home right after a swap | That is M2, with its losses |
| setup-tokens | Ruling a90e1ac2597e; reduced scopes |
| Settings `env` rebind | Every session at once; cannot unset |
| `PostToolBatch`/`UserPromptSubmit` trigger | Minutes of waiting; S10 §3 |

---

## 8. Kill switches and rollback

| switch (env; file twin read on every pass or event) | default | effect |
|---|---|---|
| `CC_LANE` (`~/.reso/lanes/arm.off`) | **off** until W9 | Launchers arm no lane, so new launches behave stock. Live lanes keep working. |
| `LR_LANE_BIND` (`~/.reso/lanes/bind.off`) | **off** (file present) until W9 | The module binds nothing. The file is the real switch for live sessions, since their env is fixed. |
| `LR_LANE_MOVE` (`move.off`) | **off** until Q1, a P-L5 PASS (or a W0 switch to M31/M32) and AC17 | The broker refuses swaps. `cc-lr move` uses the incumbent restart path. |
| `LR_LANE_MIRROR` | on whenever the broker runs | Debug only. Lanes 401 at expiry when it is off. |
| `LR_LANE_HEAL` (`heal.off`) | off until Q4 | No heal-for-lanes. An account with zero home readers is excluded as a target. **Patch pass:** exclusion stops only new moves. While heal is off, the broker also refuses to arm or bind an account's last home reader, so every account keeps a home reader (§3.7). Lanes whose `refresh_path` is `none` unbind before expiry (§3.11). |
| `LR_LANE_DRAIN` (`~/.reso/lanes/drain.off`) | **off** until Q10 | Pre-wall drain (§3.5.1, W8). Off means no automatic pre-emptive move. Operator orders and reactive recovery are unaffected. |
| `LR_LANE_FAILSAFE` (`failsafe.off`) | **on** | Module fail-safe unbind |
| `LR_REHOME` (`rehome.off`) | off until P-L4 PASS | Relaunchers keep the home dir |
| `LR_REHOME_IDLE` | off until Q6 | B6 |
| `LR_LANE_WAKE` | on with MOVE | Off means the incumbent nudge |
| `LR_REBAL_LANE` / `LR_REBAL_DONOR` | off / off | Rebalance uses the incumbent; donor arm off |
| `LR_MOVE_RESTART_NOW` | off; must be passed per invocation as well | M2 path |
| `LR_RECON_PSFREE` (`recon/ps-free.off`) | **shadow** | S07 |
| `CC_BILLING` | on (falls back to home when no ledger row exists) | Off means `billing_of == home`, today's behavior |
| `LR_LANE_CERT_REQUIRED` | on | Refuse to arm or bind on an uncertified CC. The cert is read for the **installed** version (AC17). |

**Rollback, in order:**
1. `cc-lane revert --all`: every lane's billing becomes home, one write each, no restart.
2. `touch ~/.reso/lanes/unbind-all`: the module unsets the variable at each session's next request.
   Wait until every beat reads `lane_env:null` (AC5b).
3. `touch arm.off bind.off move.off`.
4. Only then revert the code lands. A module reload does **not** unset an env value already set
   (FM71).
5. `cc-lane gc` removes the lane items.

Each switch fails toward the incumbent or stock client, never toward an unproven state (R6, R11).

---

## 9. Acceptance criteria (disk-truth reads)

| AC | claim | read | pass |
|---|---|---|---|
| AC1 | billing changed within 1 API call | `~/.reso/lanes/ledger.jsonl` row (t_order, t_c, fp_B); `cc-lane verify --sid S` gives fp(lane keychain) = fp(lane file) = fp_B = B's `at_fp` in `~/.claude/logs/claude-accounts-lastgood.local-state.json`; the transcript `<sid>.jsonl` from t_order; corroboration (not a gate): `~/.reso/lanes/measure/<sid>.json` 7 d ≈ B's `claude-accounts --readout` when A and B differ by >5 pp. **Billing witness (gate, patch pass):** a `~/.reso/lanes/measure/<sid>.json` record with mtime > t_c whose `seven_day.resetsAt` (tie-break `five_hour.resetsAt`) equals B's weekly (5 h) reset from `claude-accounts --json` and differs from A's | fps equal; **≤1** request built in [t_order, t_c]; ≥1 assistant record whose parent ts > t_c; **and** the post-t_c `resetsAt` equals B's and differs from A's. That is a disk read of which org was billed. Otherwise the verdict is `SWAP-UNPROVEN`. |
| AC2 | 0 forks | `<sid>.jsonl` non-sidechain records since t_order: every uuid has ≤1 child; `cc-proctable --holders <sid>` at every pass t_order → +600 s | 0 multi-child parents; holders == 1 |
| AC3 | 0 lost turns | same transcript window | no `[Request interrupted`; no unmatched `tool_use` older than its timeout; no new api-error tail except a real limit |
| AC4 | 0 killed background tasks | `cc-proctable --alive <pid> <lstart>` before and after; `<task-notification>` statuses; `<home>/jobs/*/state.json` inFlight | identical; no killed/stopped notification; unchanged |
| AC5a | module inert after R0 | `~/.reso/lanes/beat/*.json` | every beat `lane_env:null` while `bind.off` exists |
| AC5b | retrofit coverage | `cc-lane status --fleet --json` | bound ≥90% of live sids that ended ≥1 turn since R3; unbound sids listed by reason |
| AC6 | re-home | the first process of the sid after the boundary: `cc-proctable --env-keys <pid>` `CLAUDE_CONFIG_DIR` = dir(billing at exit); lane fp = same account; `ledger.rehomed` with sha match; registry `account` = billing; same (pid, lstart) on 2 reads ≥5 s apart | all true |
| AC7 | credential safety | local-state `items[].rt_fp` (one per account) against every lane blob (`cc-lane verify --rt-null`); `~/.claude/logs/claude-accounts-lastgood-rejected.json`; `security dump-keychain` attributes for lane items | 1 holder per grant; every lane `refreshToken==null`; rejected == `{}`; lane items have acct = chrisren |
| AC8 | census | `~/.reso/limit-recover/recon/shadow/ps-free.jsonl`; `recon/events.jsonl` | ≥500 passes with 0 ppid/zombie/lstart/tty and 0 claude-family token mismatches; after `on`, 0 table-wide ps-degraded abstains |
| AC9 | attribution | `cc-billing mismatched` vs `cc-lane verify --all`; `claude-accounts --json` per-account `k` vs a count by billing; `tests/attribution-keys.bats` | equal sets; equal counts; ratchet green |
| AC10 | busy-move rate | 7 d of armed `wait:*`/goal-class rows (`~/.reso/limit-recover/move/*/plan.json` + ledger) | ≥99% `SWAPPED` (vs 3.4%), where `SWAPPED` counts only rows that passed the AC1 `resetsAt` witness. `SWAP-UNPROVEN` is reported beside it, never folded in. |
| AC11 | refresh ownership | `cc-lane status --json`: `.accounts[].home_readers`, `.accounts[].heal_scheduled_at`, `.lanes[].expires_in_s` at each pass; `<L>/state.json.refresh_path`; broker refusal log | every account has home_readers ≥1 or a heal scheduled ≥15 min before expiry; min lane life ≥10 min, else paged; no lane with `refresh_path=none` outlives its last 10 min bound (it unbinds, §3.11); 0 arms or binds of a last home reader while heal is off or unhealed |
| AC12 | fail-safe | **Never boot out the fleet broker.** The broker and `broker.beat` serve the whole fleet, so a bootout canary would stop moves, mirror and heal for every lane for hours, and every account whose lanes reach the 10 min window would then unbind at once. Two forms instead: (a) a per-lane fault flag, `<L>/state.json.test_beat_stale=true`, that the module honours **only** for a sid named in a test order; (b) the same check in W0 against a throwaway broker root under `/tmp`. Read that session's beat. | `unbound-failsafe` before lane expiry; no api-error tail; every other lane's beat unchanged |
| AC13 | limit recovery | lr_recon record: detection ts → ledger `committed` → first assistant record after the wake | ≤ one pass + 5 s to commit; the wake turn bills to B (AC1 reads) |
| AC14 | certification | `~/.reso/lanes/cert/2.1.293.json` (and `cert/<ver>.json` for each version `check18` runs) | P-R1, P-L1, P-F1, P-L4, P-S1 all PASS (P-L2 recorded). P-L5 PASS if per-session copy lanes are kept; P-L6 PASS if M31 is chosen. P-S1 also asserts that `resetsAt` follows the billed org. |
| AC15 | restart-now | the target transcript tail; ledger `restart-now` row; `claude-accounts-lastgood-rejected.json` | `pL` result plus a continued turn; source proven dead before launch; rejected == `{}` |
| AC16 | pre-wall drain (W8) | 7 d of `lr-shed` drain shadow log: per account, the projected 5 h/7 d landing at each tick vs the actual landing; picks; ledger | the projected-vs-actual error is logged per account; every pick is an **armed** row; 0 move-backs to an account after its reset; the overshoot breaker trips on fixtures; 0 moves while `drain.off` exists |
| AC17 | installed version certified | the installed version, taken from the launcher's resolved binary path (a path read; nothing executed), then `~/.reso/lanes/cert/<installed VERSION>.json` | PASS. When the installed version has no cert, page once to the read channel ("lanes dark: CC <ver> uncertified") and keep `LR_LANE_MOVE` off |

---

## 10. Implementation waves

**Phase 0 header.**
- **Execution locus:** S for every wave, meaning one dispatched `/handoff` session per wave in its own
  worktree, landing only via the project-local `/ship` and never with a wrapping timeout. The
  exception is W9, locus **O**: the operator runs the numbered migration.
- W0 runs throwaway hermetic sessions under `/tmp`, reads live account items **read-only**, and may
  create throwaway keychain items for throwaway dirs only.
  - P-L6 points a throwaway at a real home store. It stays read-only only because it runs while both
    tokens have ≥30 min of life (`Pl` → `not_needed`) [I]. The probe refuses to start otherwise, and
    it needs the operator's go in the W0 brief.
  - `check18_lanes.sh` is auto-discovered (`scripts/cc-upgrade-gate.sh:87` globs `check*.sh`), so no
    driver edit is needed.
- **Lead context budget:** the lead holds this file's §10-§11 plus each wave's return JSON. That is
  ≤80K tokens. A wave brief is ≤8K tokens and points here by section.
- **Converge** after each land: `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`. Never
  `--force`.
- The 4 limit-recover defect fixes landed (bfe8025ff on origin/main), so `lr-fleet.sh`,
  `lr-reset-poller.sh` and the `lr_recon` files are free.
- **Ownership** came from I1, then `ls`/`wc -l` [M]. No file appears in two waves.
- **LOC** [E]: sized from the I1 per-row change scope and the 100p REPORT component estimates. The
  figure includes tests.
- Gate commands follow the land gate:
  - bats via `cc-bats <file>`, asserting the `1..N` plan line (rules: "Gate refusal ≠ gate result");
  - python via `cd scripts/limit-recover && python3 -I -m unittest discover -s <dir> -p '<glob>'`,
    asserting the "Ran N tests" line;
  - shellcheck bare on changed shell files.

| wave | goal | exclusive files | deps | gates | acceptance read | kill switch | est LOC |
|---|---|---|---|---|---|---|---|
| **W0** | Certification probes: P-R1 (retrofit from a home keychain store to a keychain-primary lane via mod reload), P-L1 (keychain-primary swap, plus a `security` stall shim under load ≥600), P-F1 (mid-turn `$.env.set` bind/unbind from `tool.call` **and `turn.step`**; `$.fs` read of `~/.reso`; now decisive for M31/M32), P-L4 (re-home: `account_uuid` = B on call 1, observer proxy), P-S1 (`session.measure.rateLimits` shape, and that `resetsAt` follows the billed org), P-L2 (two lanes on one account plus that account's refresh: 401 count), **P-L5** (if per-session copy lanes are kept: simulated home-item refresh → last lane rewritten, 19 throwaway lanes, load ≥600, against the 401 tolerance; also the 1-lane M32 form), **P-L6** (M31 pointer lane, §2: adoption ≤30 s after a re-point, no cross-account `rt_fp`, home `.claude.json` unchanged; runs only while both tokens have ≥30 min of life). The fail-safe canary (AC12 b) runs here against a throwaway broker root under `/tmp`. **Binary-parametric:** anchors are located by regex, never byte offset. | new: `tests/probes/lane/{README.md,lib.py,run.py,anchors.py,p_r1_retrofit.py,p_l1_keychain_primary.py,p_f1_midturn_env.py,p_l4_rehome_identity.py,p_s1_measure.py,p_l2_two_lanes.py,p_l5_fanout.py,p_l6_pointer.py}`; new `lib/cc-upgrade-gate/check18_lanes.sh` (runs the suite against the candidate binary and writes `~/.reso/lanes/cert/<ver>.json` before the pin moves); new `tests/cc-upgrade-gate-check18.bats` | none | `python3 -I tests/probes/lane/run.py --all --binary <path>` (prints PASS/FAIL with fingerprints only); `cc-bats tests/cc-upgrade-gate-check18.bats`; shellcheck `lib/cc-upgrade-gate/check18_lanes.sh` | `~/.reso/lanes/cert/<ver>.json` for 2.1.293 and for the upgrade candidate; AC17 | n/a (`LR_LANE_CERT_REQUIRED` consumes it) | 1,050 |
| **W1** | ps-free census (S07 §6) in shadow | new `scripts/limit-recover/lr_recon/proctable.py`, new `bin/cc-proctable`; `lr_recon/observe.py`, `lr_recon/store.py`, `lr_recon/fence.py`; new `lr_recon/tests/test_proctable.py`, `lr_recon/tests/test_observe_psfree.py`; `lr_recon/tests/test_observe.py`, `lr_recon/tests/test_session_row_reuse.py`, `lr_recon/tests/test_pane_bind_env.py` (they pin `observe.py` semantics) | none | unittest `-p 'test_proctable.py'`, `-p 'test_observe*.py'`, `-p 'test_session_row_reuse.py'`, `-p 'test_pane_bind_env.py'`; shellcheck `bin/cc-proctable` | AC8 | `LR_RECON_PSFREE` / `ps-free.off` (default shadow) | 900 |
| **W2** | Three-key attribution API and ledger schema reader | new `scripts/lib/billing.py`, `lib/billing.sh`, `bin/cc-billing`, `tests/billing-attribution.bats`, `tests/attribution-keys.bats`, `tests/fixtures/attribution-keys.baseline` | none | `cc-bats tests/billing-attribution.bats tests/attribution-keys.bats` | `cc-billing --sid <s> --json` returns `{home, billing:home, identity:home}` with no ledger | `CC_BILLING` | 650 |
| **W3** | Lane store, ledger, bind table, mirror, heal guard, GC, proof, cert, broker, CLI (inert) | new `scripts/limit-recover/lr_lane/{__init__,store,ledger,bind,mirror,heal_guard,gc,proof,cert,broker}.py`, `lr_lane/tests/test_{store,ledger,bind,mirror,heal_guard,gc,proof,cert,broker}.py` plus `lr_lane/tests/fake_security.py` (a fake `security` shim; never the real keychain), `bin/cc-lane`, `launchd/staged/com.reso.lane-broker.plist`, `migrations/0079-lane-broker-stage.sh` (stages only) | W1, W2 | unittest `-s lr_lane/tests`; shellcheck `bin/cc-lane migrations/0079-*.sh`; the plist run under `/bin/bash` 3.2 (rules: "Deployment interpreter") | `cc-lane status --json` on fixtures; `cc-lane arm --dry-run --sid X` | `LR_LANE_MOVE`, `LR_LANE_MIRROR`, `LR_LANE_HEAL` (all off); broker not loaded | 2,400 |
| **W4** | Launch-time arming, binding module, beat, fail-safe, `session.measure` sensor | new `lib/cc-lane.sh`; `lib/claude-launcher.zsh`; new `mods/accounts-readout/hooks/lane-bind.ts`; `mods/accounts-readout/hooks/register.tsx` (registration only); new `mods/accounts-readout/tests/lane-bind.test.ts`; new `tests/claude-launcher-lane.bats`; `tests/claude-launcher-router.bats` | W3 | `claude plugin validate mods/accounts-readout`; `claude plugin test mods/accounts-readout`; `cc-bats tests/claude-launcher-lane.bats tests/claude-launcher-router.bats` | AC5a after converge | `CC_LANE`, `bind.off`, `failsafe.off` | 750 |
| **W5a** | claude-accounts and relogin: billing/store census split, lane-aware heal gate, `--heal-for-lanes`, R16 unset, `--assign` by billing, C1 `--rebal-band` | `bin/claude-accounts`, `bin/cc-relogin`, `scripts/relogin-desharing-activate.sh`, `bin/cc-config-slot`; `tests/claude-accounts.bats`, `tests/account-fact-derivation.bats`, `tests/cc-relogin.bats`, `tests/claude-accounts-kwork-live-bound.bats`, `tests/claude-accounts-place.bats`, `tests/claude-accounts-stranded.bats`, `tests/claude-accounts-fleet-pace.bats` (they pin the census this wave splits); new `tests/claude-accounts-lanes.bats`, `tests/claude-accounts-rebal-band.bats` | W2, W3 | `cc-bats` on the nine files; shellcheck `bin/cc-relogin scripts/relogin-desharing-activate.sh bin/cc-config-slot` | AC7, AC11 (with W3) | `LR_LANE_HEAL`, `CC_BILLING` | 1,250 |
| **W5b** | Hooks, statusline and readouts on billing (I1 §7-9 display/billing rows) | `hooks/stop-failure-marker.sh`, `hooks/session-register.sh` (adds `lane`; `account` stays home), `hooks/lead-crash-watchdog.sh`, `hooks/operator-readout.sh`, `bin/cc-reconcile`, `statusline.sh` (`home→billing`, `rl5/rl7`), `bin/cc-context`, `bin/cc-board`, `bin/cc-value`, `bin/cc-queue`, `bin/cc-sessions`, `bin/cc-limited`, `bin/cc-token-ledger`, `bin/cc-quota-price`; `tests/stop-failure-marker.bats`, `tests/cc-reconcile.bats`; new `tests/billing-consumers.bats` | W2 | `cc-bats` on the three files; shellcheck on the changed shell | AC9 (display half) | `CC_BILLING` | 800 |
| **W5c** | Three things: the limit-recover shell billing rows; the recycle launcher writer setting the lane; the `--restart-now` actuator. The actuator takes the source's `.oauth_refresh.lock` (bounded 10 s), SIGTERMs at once with a 5 s SIGKILL backstop, proves death via `cc-proctable`, applies the bg-daemon guard, and relaunches in the pane with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`. It replaces the typed `/exit` and the idle wait only on this path. | `scripts/limit-recover/lr-fleet.sh`, `scripts/limit-recover/lr-reset-poller.sh`, `scripts/limit-recover/lr-handoff.sh`, `scripts/handoff-fire.sh`, **`scripts/limit-recover/lr-lib.sh`** (a billing-aware `lr_successor_state` @1155-1200: moved = `billing_acct(sid) != source`; plus a new `lr_billing_acct` helper over `lib/billing.sh`. I1 §4 lists `lr_pid_cfg` @1111-1127 and `lr_successor_state` as BILLING proxies that answer "not moved" after a re-bill. Their callers are lr-fleet.sh:1785-1806, lr-reset-poller.sh:1510/2791-2812, lr-handoff.sh:706, handoff-fire.sh:14422 and W7a's bin/cc-lr:433-439, so the shared judge is patched once, here); `tests/handoff-recycle-repick.bats`, `tests/lr-reset-poller.bats`, `tests/lr-lib.bats`, `tests/lr-fleet.bats` (changed in bfe8025ff), `tests/handoff-recycle-same-account.bats`, `tests/handoff-recycle-cross-account-engage.bats`; new `tests/lr-billing-shell.bats`, `tests/lr-restart-now.bats` | W1, W2, W4 | `cc-bats` on the eight files; shellcheck (including `lr-lib.sh`) | a wall fact on a re-billed sid lands on billing, not the store (fixture); `lr_successor_state` answers "moved" for a re-billed sid in the same store (fixture); AC15 on a throwaway pane | `CC_BILLING`, `LR_REHOME`, `LR_MOVE_RESTART_NOW` | 1,200 |
| **W6** | Re-home at natural boundaries, cold transplant, prove-death, bg-daemon guard | new `scripts/limit-recover/lr_lane/rehome.py`, new `lr_lane/tests/test_rehome.py`; `scripts/limit-recover/lr-fire-resume.sh`, `bin/reso-resume-one`, `scripts/boot-resume-launch.sh`, `scripts/boot-resume.sh`, `bin/kitty-split-launch.sh`, `scripts/limit-recover/lr-transplant.sh` (`--cold`); new `tests/rehome.bats` | W1, W3, W4 | unittest `-p 'test_rehome.py'`; `cc-bats tests/rehome.bats`; shellcheck | AC6 | `LR_REHOME`, `LR_REHOME_IDLE` | 1,000 |
| **W7a** | Move-lane front door (`act=swap` for armed rows); verdict P2′ (lane fp = target) and P3′ (one live transcript in any store); billing census columns; the operator-only `--restart-now` flag, passed through to W5c's actuator | `bin/cc-lr`, `scripts/limit-recover/lr-move-worker.sh`, `lr-move-lib.sh`, `lr-move-batch.sh`, `lr-upgrade.sh`; `tests/lr-move-plan.bats`, `tests/rig-move-lane.bats`, `tests/lr-switch-driver.bats`, `tests/cc-lr-front.bats`; new `tests/lr-move-swap.bats`. (`tests/lr-lib.bats` is in W5c, which owns `lr-lib.sh`. One owner per file; W7a already depends on W5c.) | W1, W2, W3, W5c | `cc-bats` on the five files plus `tests/lr-lib.bats` read-only as a regression check; shellcheck | AC1-AC4, AC10, AC15 | `LR_LANE_MOVE`, `LR_MOVE_RESTART_NOW` | 800 |
| **W7b** | Reconciler: `billing_acct` join, limit facts by billing, `rebill` actuator (swap plus wake), settle by ledger. **`billing_join.py` decorates each `SessionObs` after `observe()` returns** (at the `observe.observe(` call, `__main__.py:2748`; `billing_acct` is a new field in `types.py`, default `None` = unknown). **W7b never edits `observe.py`**, which is exclusive to W1. This re-points I1 §10's "lands at observe.py:956-970". | `scripts/limit-recover/lr_recon/{act,facts,census,plan,settle,__main__,types,evidence,report}.py`, new `lr_recon/billing_join.py`; `lr_recon/tests/test_census.py`, `test_main.py`; new `test_billing_join.py`, `test_rebill_act.py` | W1, W2, W3 | unittest `-s lr_recon/tests` | AC13 | `LR_LANE_MOVE`, `LR_LANE_WAKE` | 1,200 |
| **W8** | Strand-aware rebalance: C2 burn meter and C3 sink arm with lane actuator; donor arm behind its own switch. **Plus the pre-wall drain (§3.5.1)** as a separate `lr-shed.py` arm: it projects each account's 5 h/7 d landing, picks only armed rows, never moves back after a reset, has an overshoot breaker, and runs shadow-only until Q10 | `scripts/limit-recover/lr-shed.py`, new `scripts/limit-recover/lr_burn.py`, `tests/lr-shed.bats`, new `tests/lr-burn.bats` (drives `python3 -I lr_burn.py` on fixture transcripts), new `tests/lr-shed-drain.bats` | W5a, W7a | `cc-bats tests/lr-shed.bats tests/lr-burn.bats tests/lr-shed-drain.bats` | a shadow tick on fixtures logs the right sink and picks; overshoot trips the breaker; AC16 | `LR_REBAL_LANE`, `LR_REBAL_DONOR`, `LR_LANE_DRAIN` (`drain.off`, default off) | 1,150 |
| **W9** | Activation (after Q1, Q2, **Q4** and a W0 PASS, including P-L5 or the M31/M32 switch, and AC17 for the installed version): load the broker, set defaults, runbook | new `migrations/0080-lane-activate.sh`, new `docs/runbooks/lane-move.md` | all + operator | shellcheck; `bash -n` under `/bin/bash` 3.2 | AC5b, AC11, AC12 (per-lane fault flag; never a fleet-broker bootout), AC17 | all of §8 | 150 |

**Order:**
1. W0, W1 and W2 in parallel.
2. W3.
3. W4, W5a, W5b and W7b in parallel.
4. W5c and W6.
5. W7a.
6. W8.
7. W9.

W4 lands inert, so it reloads across the fleet with zero functional change (FM56). Total about
12.7K LOC [E] before the patch pass. The patch pass adds W0 +250 (P-L5, P-L6, check18), W5c +150
(lr-lib.sh) and W8 +250 (drain), about 13.4K LOC [E, same sizing method]. W7b runs in step 3, after
W1 has landed `observe.py`; it decorates `SessionObs` and never edits that file.

---

## 11. Operator decisions this design cannot settle at >90% conviction

| # | question (plain English) | conviction | options → outcome | recommendation | class |
|---|---|---|---|---|---|
| Q1 | Should the fleet move a live session to another of your accounts by switching the access token it reads, with no restart? Anthropic's terms do not clearly allow it, and the server can see that the session still names the old account. | 55% | (a) Build everything but keep it off. Ask Anthropic support in writing first, and switch it on after a yes or your explicit go. Outcome: zero exposure while you wait; busy sessions keep moving at today's 3.4% rate. (b) Switch it on now for your own four accounts, with a mandatory re-review before 2026-11-12. Outcome: busy sessions move within one API call; S08 puts this at 60% not-a-breach today. (c) Never. Outcome: lowest exposure (75%); moved sessions keep losing turns and background jobs, and busy ones mostly do not move. | (a), then decide | C |
| Q2 | Your 2026-09-08 ruling says no token files are ever created. Each switched session needs a private file, readable only by you, that holds a short-lived access token (no refresh token, expires within about 8 h, deleted when the session ends). It is the fallback when the keychain stalls under load. Allow it? | 65% | (a) Allow access-token-only lane files. Outcome: robust under load; this is the tested form. (b) Keychain only, with an empty marker file. Outcome: no token on disk, but untested, and a keychain stall could make a session believe it is logged out; it ships only after a load probe passes. (c) Neither. Outcome: switching cannot ship. | (a) | C |
| Q3 | A few sessions never finish a turn (4 of 20 sampled), so the no-restart switch cannot reach them. When you order one of them moved, should the mover restart it mid-turn? | 70% | (a) Wait. Outcome: no loss; it moves at its first turn end or next restart, which may take hours. (b) Restart it, but only on your explicit order for that session. Outcome: it moves within minutes; its background jobs die and its turn re-runs; a running /ship cleans itself up and must re-gate. | (a) by default; (b) available on your order | B |
| Q4 | Once every session on an account is switched, nobody refreshes that account's token. Should the lane service refresh it with the official claude binary, the same refresh claude-accounts already uses when an account has no live sessions? | 80% | (a) Yes. Outcome: switched sessions keep working indefinitely. (b) No. Outcome: the system never switches the last un-switched session of an account, so every account keeps at least one session that refreshes it. If an account still loses its last refreshing session (for example, that session exits), each switched session on it detaches from its switch about 10 min before the token expires and goes back to its own account's login. Nothing moves it to another account. That return is reported to you. | (a) | B |
| Q5 | When you resume a moved session by hand, should it come back under its new account's folder automatically? | 75% | (a) Automatic, with a one-line notice. Outcome: the account mismatch ends at that restart. (b) Print a suggestion only. Outcome: the mismatch continues until another restart. | (a) | B |
| Q6 | Should moved sessions that sit idle for 30 min or more also be relaunched under their new account, to end the mismatch sooner? | 75% | (a) Yes, idle-only. Outcome: shorter mismatch, no cache cost. (b) Natural restarts only. Outcome: mismatch median about 17-20 h, p90 47-115 h. | (a) | B |
| Q7 | Should the system move sessions on its own to spend weekly quota before it resets unused, or only when you order it and at limit walls? | 60% | (a) Automatic. Outcome: uses quota that would otherwise expire; this looks most like "using several accounts to stretch limits" under the 2026-11-12 policy text. (b) Your orders plus limit recovery only. Outcome: lower exposure; some quota expires unused. "Limit recovery" means moving a session **after** it has hit a limit; moving sessions **before** a limit is Q10. (c) Automatic only after the 2026-11-12 re-review. | (b) now, (c) later | C |
| Q10 | Before an account hits its 5-hour or weekly limit, should the system move its switched sessions to another of your accounts on its own, so they never hit the limit? This is separate from Q7: Q7(b) covers your orders and moves after a limit is hit, not this. | 55% | (a) Yes, automatically. Outcome: busy sessions rarely stop at a limit; this is the pattern closest to the 2026-11-12 text about using several accounts to "circumvent product guardrails". (b) Log what it would do for 7 days and move nothing, then decide. Outcome: no exposure; you see how often it would act and how accurate its forecasts are (AC16). (c) Never. Outcome: sessions hit the limit and are moved afterwards by limit recovery, each losing one turn to the wake. | (b), then decide with Q7 at the 2026-11-12 re-review | C |
| Q8 | Inside a switched session, should MCP sign-ins be copied from the home account (access part only), or left out? | 65% | (a) Copy. Outcome: OAuth MCP servers keep working; their refresh stays with the home account. (b) Leave out. Outcome: those servers ask you to sign in again in each switched session. | (a) | B |
| Q9 | Close the open decision packet `745e0fdc78e6` ("wait for the next wall" credential flip) once the probes pass? | 80% | (a) Close it as superseded after a W0 PASS. Outcome: one open packet fewer. (b) Keep it open. | (a) | B |

---

## 12. Residual risks and accruing measurements

| risk / measurement | why it stays open | where it is read |
|---|---|---|
| **P9: does a refresh revoke the previous access token?** | **RESULTED (03:58-04:00 CDT, P-probes:162-176): yes, at once.** It is no longer accruing. What stays open is whether per-session copy lanes can re-copy within the ≈1.5-2.5 s tolerance [E] for a 19-lane account under load. FM19/FM46 have no structural answer yet. | `/tmp/mtam/probe/revoke-watch.log`; W0 P-L5 (fan-out), P-L6 (M31), P-L2; R2 arm-all and `LR_LANE_MOVE` gated on P-L5 PASS |
| Refresh fan-out loses turns (per-session copy lanes) | Each account refresh (≈8 h) revokes every lane copy at once. The rewrite is one `security` write per lane, at 2 s × 2 under load. | P-L5 result; P-L2 401 counts; AC3 api-error tails clustered within 10 s after a home-item mdat change |
| Server-side meaning of the cross-org bearer/metadata mismatch | Unknowable from source (G4 open question 1; G2-org: four separate orgs) | Q1 policy gate; ban-signal watch: any 401/403 with an account-level error, or an account notice, pages and triggers `cc-lane revert --all` (runbook W9) |
| Policy drift on 2026-11-12 (AUP "circumvent product guardrails", "proxy … consumer subscriptions") | Text not yet in force | Mandatory re-review entry in the W9 runbook, dated 2026-11-11 |
| Mismatch window longer than estimated | The estimate is lower-side (§3.8) | `cc-lane report --mismatch` (ledger `committed→rehomed`), weekly |
| Retrofit unreachable for never-ending turns | Structural to reload-at-turn-end (P10) | `cc-lane status --fleet` "unbound: no end_turn since R3" |
| Keychain-primary form and home→lane retrofit unprobed | P4-P6 and P10 used file-only lanes | W0 P-L1, P-R1; `cert/2.1.293.json` |
| Mid-turn `$.env.set` from `tool.call` unprobed | Inferred from `EIo` and `uw()` | W0 P-F1 |
| `KERN_PROCARGS2` under a real stall | Unmeasured (S07 §7) | `recon/shadow/ps-free.jsonl` per-call durations |
| `security` latency at load 600-900 | One 55 s dump observed (G2-keychain) | Broker log of per-call duration; aborted-before-PONR count |
| CC upgrade (storageV5 turned on, anchors moved) | Release-controlled | R14 cert per version; arm refused until re-certified |
| **The ruled ≥2.1.301 upgrade** (packet `5a7554481183`, via `/cc-upgrade` after 2026-10-22T14:34Z) | Pending, and it could land during implementation. 2.1.310 already renames the change-check (`sA` @219228917) and adds the `VRe()` gate. A pin move without a cert leaves every new launch and re-home un-laned: fail-closed, but dark. | The upgrade **must pass `check18_lanes.sh`** (`cert/<ver>.json` = PASS) before `LR_LANE_MOVE` stays on; AC17 pages otherwise |
| Login cliffs: next2 2026-10-31, next4 2026-11-02 | A `/login` inside a laned pane makes the lane the grant holder (FM49) | Runbook: re-login with `cc-relogin`; `cc-lane verify --rt-null` pages on `lane-owned` |
| Lane item sprawl (about 40 keychain items) | GC failure leaves short-lived access tokens until expiry | `cc-lane gc --dry-run` count vs live sids |
| `session.measure` shape | Inferred from I2 and @5051563. Shape read in the patch pass: `kue` @11504180. | W0 P-S1 (shape, and that `resetsAt` follows the billed org). The sensor is now the `proved` gate through `resetsAt` (R4); a miss yields `SWAP-UNPROVEN`. |
| Tertiary's stale `.credentials.json` (an Oct 11 grant) | Pins the tertiary memo; a dead fallback if the keychain ever reads null (S14 side finding) | Operator housekeeping: rename it (G1 §3: it shares no live refresh token) |
| Bridge/RC captured-token helpers | They keep the old token until re-home (G3 row 5e) | Re-home closes it; no gate |
| Mod hot-reload blast radius | Any mod landing reloads about 40 sessions | W4 gates; `bind.off`; AC5a after every converge that touches `mods/` |
