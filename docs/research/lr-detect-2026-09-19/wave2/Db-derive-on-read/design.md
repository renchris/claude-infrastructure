# Db — DERIVE-ON-READ: `cc-limited`, one process, no new state

Blind designer Db · wave2 · 2026-09-19T21:20Z · repo claude-infrastructure @ 226b73888 (read-only) ·
probe + receipts beside this file (`census-probe.py`, § 15).

## 0. Anchor, verdict, and two measured corrections

**Anchor (committed):** the census is a PURE FUNCTION of stores that already exist —
`~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` ∪ `~/.reso/limit-recover/parked/` ∪
`~/.claude/cc-registry/` ∪ `~/.claude/cc-beats/` ∪ the 128 KB tail of each NAMED transcript ∪
`~/.reso/limit-recover/{locks,results,fleet}` — computed by ONE process, `bin/cc-limited`, in
< 0.2 s, and consumed unchanged by `lr-fleet --locate`, the poller, `/recover`, `/limit-recover`
and the operator. The StopFailure hook gains no second store: it adds two FIELDS to the record it
already writes (pane, cap), writes ONE beat through the EXISTING writer (`kind:"limited"`), and
kicks the EXISTING daemon. Nothing new is GC'd, locked, schema'd, or migrated.

**Why this anchor wins on the operator's four axes.** Latency: every input is a small file or a
tail; measured end-to-end 0.134 s without kitty, 0.199 s with, against 35.5–86 s for the shipped
census (§ 3). Clean code: one resolver (~260 LOC) replaces `lf_locate` (lr-fleet.sh:183-254,
three python forks per hit), the poller's detect loop (lr-reset-poller.sh:740-795, one lr-audit
subprocess per candidate) and the prototype. Token cost: the operator reads one grouped screen,
never a pane. Fault visibility: a claimed recovery with no live process is a QUERY over claims
that already exist on disk (locks, results.tsv) — § 9 — so it is named without anyone having to
remember to write a "pending" file.

**Correction 1 (measured, contradicts a digest evidence line).** `~/.claude-secondary` EXISTS:
`ls -ld ~/.claude-secondary` ⇒ `drwxr-xr-x@ … Sep 19 16:13`, and `readlink -f
~/.claude-secondary/projects` ⇒ itself; a 1,157,520-byte live transcript sits under it
(07e30aeb, § 2). The `next2 -> ~/.claude-secondary` accounts.json row is correct. The only mirror
is `~/.claude-next/projects -> /Users/chrisren/.claude/projects` (measured, same command).
**Correction 2 (design consequence).** The phantom `.claude` account is NOT fixed by adding a
`~/.claude` row to accounts.json. `accounts.json` already carries the concept — its `_port_index`
note defines `aliases` as "extra config-dir basenames that resolve to this account" and
`next.aliases == ["claude"]`; `lib/account-map.generated.sh:44-47` already maps `claude ⇒ next`.
The defect is that `hooks/stop-failure-marker.sh:85-87` matches `.config_dir` ONLY. A fifth
`accounts[]` row would enter every consumer the file's `_what` header names (`bin/claude-accounts`,
`handoff-fire.sh`, `gen-account-map.sh`, the router's spend-priority order) — unmeasured blast
radius — whereas an alias-aware `select()` in the hook is one line with none (§ 4.1).

## 1. The census contract — `bin/cc-limited`

### 1.1 Inputs (every one exists today; none is created by this design)

| store | file:line of its writer | what the census takes from it | read cost |
|---|---|---|---|
| `~/.claude/accounts.json` | install.sh symlink | `config_dir`/`aliases` ⇒ account NAME (both spellings normalise here) | 0.1 ms |
| `~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl` | hooks/stop-failure-marker.sh:122-128 | ENUMERATOR: sid, ts, config_dir, cwd, transcript_path (snapshot), last_assistant_message; after § 4: `pane`, `cap` | 0.7 ms / 31 rows |
| `~/.reso/limit-recover/parked/<sid>.json` | lr-reset-poller.sh:788 | second enumerator (outlives the marker's 24 h TTL): sid, acct, kind, reset_at_utc | 1.0 ms / 7 |
| `~/.claude/cc-registry/[0-9]*.json` | hooks/session-register.sh:282-290 | RESOLVER sid ⇒ pane, pid, lstart, account-now, cwd | 1.4 ms / 31 |
| one `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` | — | liveness = (pid,lstart) match, never `kill -0` alone | 30.8 ms |
| `~/.claude/cc-beats/<sid>.json` (candidates only) | hooks/session-beat.sh:111-117 | `kind`, `t`, `pid`, `lstart` — after § 5 a `limited` beat is the freshest death evidence | ~0.1 ms/sid |
| transcript copies, slug-directed | Claude Code | last non-`No response requested.` assistant record ⇒ blocked?, `error`, `quotaLimits.{resetsAt,rateLimitType}`; last `"aiTitle"` | 5.4 ms probe + ~1 ms/tail |
| `~/.reso/limit-recover/locks/<sid>.lock` | lr-transplant.sh | `{from,to,ts,pid,host}` — a CLAIM | 0.2 ms |
| `~/.reso/limit-recover/fleet/*/results.tsv`, `results/<sid>.json`, `requests/<sid>.json` | lr-fleet.sh:412 (`lf_row`), lr-reset-poller.sh:658-660 | claims + their logs (§ 9) | ~1 ms |
| one unmatched `kitten @ ls` (optional, `--kitty`, 3 s bound) | kitty | pane ⇒ title corroborator; a corrupt payload ⇒ column `?`, never a failure | 65 ms |

Not inputs, by measurement: `session-index.db` (0/8 titles), the whole-fleet transcript scan
(the entire 43.6 s; available only under `--deep`), `lsof` (0 rows), `locks/` as a liveness
surface (it is a claim, § 9).

### 1.2 The resolver — nine steps, in order, each a pure read

```
0  accounts.json → base2name: {".claude-secondary":"next2", …, ".claude":"next" (alias), "claude-secondary":"next2" (registry spelling)}
1  markers: for each rate_limit__*.jsonl row: skip sid=="?" (COUNT it); group by sid; keep MAX(ts) row;
   fires += 1; acct_death = base2name[basename(config_dir)]  — NEVER the filename;
   cap = lr_predicate.classify_text(last_assistant_message).kind
2  parked/*.json: setdefault(sid) — adds sids whose marker aged out (seven_day caps); carries reset_at_utc
3  registry ∩ ps: rows where ps[pid].lstart == row.lstart (exact string, both TZ=UTC LC_ALL=C);
   index by session_id → [rows]; acct_now = base2name[row.account]
4  transcript: probe <root>/projects/<slug>/<sid>.jsonl* for the 4 REAL roots (slug = basename of
   dirname(marker.transcript_path); it is the cwd slug and is stable across accounts) — 5.4 ms for
   14 sids; on a miss ONLY, fall back to the full index (121 ms). Order copies (.handed-off last,
   size desc); the LIVE copy = first .jsonl with ≥1 assistant record in its 128 KB tail.
   0 assistant records in every .jsonl ⇒ UNKNOWN-STUB (its own state, never RE-ENGAGED)
5  tail: last assistant record (skip "No response requested."): blocked ⇔ isApiErrorMessage ∧ error=="rate_limit";
   resets_at = quotaLimits.resetsAt (epoch) else prose (lr_predicate); title = last "aiTitle" in the tail
6  liveness: live = step-3 rows for sid; procs = |live pids ∪ lr_resume_procs leaves| (cardinality, never rc)
7  claims: lock.to (≠ live copy's cfg ⇒ claim), results/<sid>.json{rc,ts,log}, newest results.tsv row for sid
8  cwd: os.path.isdir(cwd) AT THIS INSTANT (it decays under the worktree reaper mid-census — measured 1→3 CWD-GONE in 20 min)
9  state = the FIRST matching row of the table in § 1.3; group by acct_now when the session moved, else acct_death
```

Every `open()`/`stat()` is wrapped for `FileNotFoundError` (a transplant renames files mid-scan;
measured). No mtime is ever read for ordering (header rewrites move mtime 44 min past the last real
record); the record's own `timestamp` is the clock.

### 1.3 The state enum (MECE; first row that matches wins)

| state | predicate | the ONE next action it names |
|---|---|---|
| `UNADDRESSABLE` | marker sid == `?` | counted in the footer; never dropped |
| `TEAMMATE` | `"agentName"` in head-8 KB of the live copy | lead-owned (poller :752 rule); listed, never queued |
| `UNKNOWN-STUB` | live .jsonl exists, 0 assistant records, no full copy | name it — a reborn stub with nothing behind it |
| `RE-ENGAGED` | last assistant record is a real turn | settled (`--all` shows it) |
| `CLAIMED-NOT-LIVE` | blocked ∧ a claim (lock / RECOVERED row / result) older than `CC_LIMITED_CLAIM_GRACE_S`=120 ∧ no live row for sid on the claimed account | § 9 — NAMED with claimant + log path |
| `AWAITING-ENGAGE` | blocked ∧ live row ∧ acct_now ≠ acct_death (death record copied forward by the transplant) | one prompt on the successor, not a recovery |
| `DUPLICATE` | blocked ∧ procs > 1 | `--duplicates` |
| `RESET-PASSED/LIVE` | blocked ∧ live ∧ resets_at ≤ now | nudge in place (poller :928) |
| `RECOVERABLE` | blocked ∧ live ∧ single process ∧ same account | in-place recovery (`--one`) |
| `NO-PANE` | blocked ∧ no live process ∧ no claim ∧ cwd exists | spawn-at-reset (poller) or `--recover` |
| `CWD-GONE` | as NO-PANE, cwd missing at resolve time | human: recreate the tree or drop |
| `CARCASS` | only `.handed-off` copies, nothing live, no claim | history |
| `NO-TRANSCRIPT` | no copy at all | named; came from a marker whose transcript never existed on this box |

Cap sub-kind rides on every row: `five_hour` · `seven_day` · `fable` · `monthly_spend` ·
`model_scoped:<Word>` (§ 6). `fable`/`monthly_spend` render `resets —` and carry
`recoverable_by_waiting:false`; their next action is `/model` and the operator respectively.

### 1.4 Modes, columns, exit codes

```
cc-limited                       per-account grouped view (default: actionable rows; settled counted)
cc-limited --all                 + settled rows (RE-ENGAGED, CARCASS)
cc-limited --json | --tsv        machine forms; --tsv is the 11-field lf_locate row, byte-compatible
cc-limited --account next3       one account
cc-limited --pane 147 | 147      resolve by pane id (exact)
cc-limited --sid 07e3 | 07e30aeb resolve by sid prefix
cc-limited --keyword bottle      case-insensitive substring over title, then cwd
cc-limited --reaper              only CLAIMED-NOT-LIVE rows (§ 9), one line each, for the poller tick
cc-limited --assert-clean        exit 1 iff any actionable row exists (a gate primitive)
cc-limited --deep                ADD the single-pass transcript scan (0.15 s, U14 A4) for -p/sdk deaths that emit no StopFailure
cc-limited --no-kitty | --since 24h | --claim-grace 120
```

Columns (human): `STATE  #PANE  SID8  CAP  RESETS  ERR  ×FIRES  TITLE  [← reason]`. JSON adds
`pid, lstart, acct_death, acct_now, lock_to, tp, copies, claim{kind,ts,by,log}, cwd, tier`.

| exit | meaning | stdout |
|---|---|---|
| 0 | census rendered (resolver modes: exactly one hit) | the rows |
| 1 | `--assert-clean` only: actionable rows exist | the rows |
| 2 | usage | — |
| 3 | AMBIGUOUS — `--pane/--sid/--keyword` matched ≥ 2 | every candidate as `pane · sid8 · account · title`; never disambiguated by recency |
| 4 | NO-MATCH for a resolver query | what was searched |
| 5 | INSTRUMENT UNREADABLE — registry dir / marker dir missing, `ps` failed, accounts.json unparseable | EMPTY; stderr names the instrument. A census may never print an empty list at exit 0 over a broken read (lr-fleet.sh:441-447 documents exactly that bug) |

Ambiguity is real today: two live panes on DIFFERENT accounts are both titled
"limit-recover optimization" (P10); `cc-limited --keyword limit-recover` exits 3 and prints both.

## 2. Today's fleet, rendered (probe output 2026-09-19T21:14Z, `census-probe.py`, 0.199 s)

```
$ cc-limited
next3   five_hour · resets 21:30Z (in 13m)                      5 need attention · 3 settled
  RECOVERABLE       #111  09e64dcb  err 19:53Z  ×3  API key export silver platter
  RECOVERABLE       #147  07e30aeb  err 20:29Z  ×1  Bottle image review for Studio60 menu
  CLAIMED-NOT-LIVE  #—    98f02458  err 19:57Z  ×2  W1b floor-plan first frame soft nav
                          ← transplant to next2 claimed 20:53:26Z by pid 32971 (locks/98f02458.lock); no live process on next2 after 21m
  CLAIMED-NOT-LIVE  #—    4bc1159f  err 20:00Z  ×1  reso-management-app worktree sync strategy   ← lock→next2, no live process
  CLAIMED-NOT-LIVE  #—    26cd14be  err 20:04Z  ×1  Kitty Terminal split pane auto-even on move  ← lock→next2, no live process
next4   five_hour · reset PASSED 19:40Z (1h36m ago)               2 need attention · 4 settled
  CWD-GONE          #—    fff83638  err 19:28Z  ×1  (untitled) wt-cc-142546-79030   ← worktree reaped; spawn impossible
  CWD-GONE          #—    0e2567ee  err 19:28Z  ×1  (untitled) wt-cc-142549-10206   ← worktree reaped; spawn impossible
settled: 7 RE-ENGAGED — 65186f1f #121 (next3→next2), 11569d45 #127, 8843bcf3 #149, e442434c, d02d8feb, cb227486, 28f07827
14 sessions · 26 marker rows (+7 parked) · 0 unaddressable · 0 teammate · stages ms {markers 0.7, parked 1.0, registry+ps 33.7, resolve 13.5, kitty 65}
```

What this screen fixes against the two shipped instruments, row by row: `07e30aeb` is
RECOVERABLE at #147 — the prototype dropped it (its marker `transcript_path` points at a 2,886-byte
reborn stub with 0 assistant records; step 4 picked the 1,157,520-byte live copy under
`.claude-secondary` and step 5 read the death record there). `98f02458/4bc1159f/26cd14be` are the
three "claimed recovery, no live process" rows the operator asked to have NAMED: each has a
`locks/<sid>.lock` with `to=.claude-secondary`, a blocked successor transcript there, and NO
registry row on any account — the prototype printed them as `MOVED` (handled) and `--locate` cannot
see the claim at all. `65186f1f` is a working session on next2 that a filename-grouped census
would queue for recovery (marker under `rate_limit__next3`, registry account `claude-secondary`,
pid alive, last record a real turn) — it is RE-ENGAGED and grouped under next2. `09e64dcb` is
RECOVERABLE, not DUPLICATE: one live registry row (pane 111) and one resume leaf, cardinality 1
(lr-fleet.sh:217 reports DUPLICATE on the mere rc of `lr_resume_procs`). The nine 125–505 h
archaeology rows `--locate` renders are absent by construction: the marker window is 24 h and
`parked/` is event-keyed.

## 3. Latency budget per stage (measured on the live box, load ≈ 11, this unit)

| stage | measured | receipt | budget |
|---|---|---|---|
| python3 start | ~8 ms | U14 § 3.1 (0.09 s of a 0.242 s parse was interpreter start; `time` of the probe = 0.074 s total incl. start) | 10 ms |
| accounts.json | 0.1 ms | `census-probe.py` stage_ms `accounts` | 1 ms |
| markers (31 rows, 3 files) | 0.7 ms | stage `markers`; standalone `marker rows=31 read=0.3ms` | 5 ms |
| parked (7) | 1.0 ms | stage `parked` | 2 ms |
| registry read (31) + one `ps` | 1.4 + 30.8 ms | `registry rows=31 read=1.4ms ps=30.8ms live(pid+lstart)=13` | 40 ms |
| transcript resolution, slug-directed | **5.4 ms** (14 sids × 4 roots ⇒ 27 copies) | `slug-directed probe: 14 sids x4 roots -> 27 copies in 5.4ms` vs full index `2223 paths in 143.4ms`/`120.9ms` vs per-sid wildcard `907.9ms` | 10 ms; 130 ms on a slug miss |
| 128 KB tails + last-record parse (14) | 13.5 ms | stage `resolve` 134.4 − `transcript-index` 120.9 | 20 ms |
| locks/results/claims | < 1 ms | 47 lock files, 7 result pairs | 2 ms |
| kitty `ls` (optional) | 65 ms | stage `kitty-ls` 199.3 − 134.4; P10 measured 29 ms idle | 100 ms; hard-bounded 3 s |
| **total, no kitty** | **≈ 55 ms** (probe measured 134 ms WITH the full index instead of the slug probe) | | **< 200 ms** |
| **total, with kitty** | **≈ 120 ms** (probe measured 199 ms) | | < 300 ms |

Against the shipped path: `lr-fleet.sh --locate` 35.5 s (lead), 40.3/64.5/86.1 s (U14 A1-A2),
43.6 s (P8). The 43.6 s window is LONGER than the fleet's own state-change interval (a transplant
completed 32 s before a `--locate` started and its rename landed inside the scan — P8), so `--locate`
rows are not a snapshot of one instant; a 55 ms window effectively is.

## 4. The event arm — `hooks/stop-failure-marker.sh` (four edits, +14 LOC, no new file)

The hook is registered on `StopFailure` in all five config dirs (U10 § 1c), fires at p50 0 s / p95
1 s after the death record (P1: 126/128), re-fires per limited turn (undeduped by design), and is a
SYMLINK at `~/.claude/hooks/stop-failure-marker.sh → <repo>/hooks/stop-failure-marker.sh`
(`readlink`, this unit) — live on land, no converge step. Its unused budget is ~9.7 s of a 10 s
timeout (U10 § 2a: 0.19–0.25 s measured). Every path still exits 0 with empty stdout.

### 4.1 Account resolution becomes alias-aware (replace :85-87)

```bash
ACCOUNT="$(jq -r --arg h "$HOME" --arg c "$CFG" --arg b "$(basename "$CFG" | sed 's/^\.//')" '
  .accounts[]? | select( ((.config_dir | sub("^~"; $h) | sub("/$"; "")) == $c)
                      or ((.aliases // []) | index($b) != null) ) | .name' "$ACCOUNTS" 2>/dev/null | head -1 || true)"
```
Effect: a death under `~/.claude` writes `account:"next"` into `rate_limit__next.jsonl` instead of
opening `rate_limit__.claude.jsonl` (today's `authentication_failed__.claude.jsonl` shows the
phantom file class: 5 rows, `account:".claude"`). The `:89` basename fallback stays for a dir the
SSOT truly does not know.

### 4.2 The pane, from inherited env — 0 forks (insert after :89)

```bash
PANE="${CC_PANE_ID:-${KITTY_WINDOW_ID:-}}"
[ -n "$PANE" ] || { PANE="${ITERM_SESSION_ID:-}"; PANE="${PANE##*:}"; }
case "$PANE" in *[!A-Za-z0-9._-]*) PANE="" ;; esac
```
`KITTY_WINDOW_ID` and `ITERM_SESSION_ID=w0t0p0:<id>` are in the CC process env (U10 § 2c, `ps eww -p 52095`)
and inherited by hooks (U07 § 3b, verified from a hook's own Bash). The registry keys on the same
integer (`hooks/session-register.sh:127`). Then `:122-127` gain `--arg pane "$PANE" --arg cap "$CAP"`
and `pane:$pane, cap:$cap` in the object. `CAP` is `lr-predicate.sh classify-text "$LAST"` (§ 6) —
ONE python fork inside the hook's 9.7 s slack, or, if the fork is unwelcome on the death path,
omitted and left to the census (the census re-classifies anyway; the field is a convenience for
`jq`-only readers). Readers ignore unknown keys: the marker line is consumed by nothing today
(`grep -rln 'stop-failure' scripts bin hooks` ⇒ only `hooks/config-mirror-assert.sh` and
`scripts/growth-coverage.conf`, neither a recovery reader).

### 4.3 The beat — ARM 2, through the existing writer (insert after 4.2, BEFORE the cap early-exit at :115)

```bash
if [ "${CC_SF_BEAT:-on}" != off ]; then
  _sf_beat="$_sfscd/session-beat.sh"
  [ -f "$_sf_beat" ] || _sf_beat="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session-beat.sh"
  [ -f "$_sf_beat" ] || _sf_beat="$HOME/.claude/hooks/session-beat.sh"
  case "$ERR" in rate_limit) _sf_kind=limited ;; *) _sf_kind=failed ;; esac
  if [ -f "$_sf_beat" ]; then printf '%s' "$input" | bash "$_sf_beat" "$_sf_kind" >/dev/null 2>&1 || true; fi
fi
```
Same ladder shape as `:47-56`. `session-beat.sh:124` takes the kind as `$1`; `:62` skips the `who`
derivation for any non-`prompt` kind (so the beat is `who:auto` and can never forge operator
presence); `:98-108` carry `operatorT` and `seq` forward; the writer's own 3 s hard timeout
(`:40`, `:126`) bounds the cost. Placement BEFORE `:115` matters: a capped marker (≥ 500 lines)
still must flip the beat, or a runaway cause would resurrect the phantom exactly when the fleet is
most loaded.

### 4.4 Wake the daemon — ARM 3 (append after :128)

```bash
if [ "$ERR" = rate_limit ] && [ "${CC_SF_KICK:-on}" != off ]; then
  /bin/launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true
fi
```
Absolute path (the daemon's default PATH is `/usr/bin:/bin:/usr/sbin:/sbin`, P7), bare `kickstart`
NEVER `-k` (`-k` kills a tick mid-recovery; lr-fleet.sh:534 prints the wrong flag today), no plist
edit, no permission rule. Converts mean 323 s / max 609 s of blindness (P7) into the daemon's
10 s `ThrottleInterval` floor. A kick of an already-loaded job is not `load`/`unload`/autofire, so
it stays outside the operator-owned activation surface. `log_idl fired "marker-appended" '{"pane":"'"$PANE"'","kick":1}'`
— `hooks/lib/idl-log.sh:117` takes a third extra-JSON argument, so the IDL row (an existing
append-only store) also carries the pane for free.

### 4.5 What the hook must NOT do
Not write a request file (that is the recovery chain; a request written here would be executed by
`lr-reset-poller.sh:657` through the same capacity gate that parked at 9 > 8 today), not rank a
target, not page (`tests/stop-failure-marker.bats:149` pins its whole write footprint — the beat
dir is added to that pin), not emit on stdout.

## 5. The beat / `cc_sp_active` phantom — fixed by § 4.3 with ZERO consumer edits

Stop never fires on a limit turn (U10 § 1a, 5/5), so `~/.claude/cc-beats/<sid>.json` freezes at the
limit turn's own opening `kind:"prompt"` beat (P4: 12 of 14 of today's rate_limit sessions, beat.t −
marker.ts ∈ {−1 s, −5 s}). `scripts/lib/spawn-presence.sh:319` counts `select(.kind == "prompt" …)`
— any other kind is NOT counted — and `scripts/lib/capacity-admit.sh:782-789` refuses when
`act + 1 > 8`. P4's A/B over a copy of the live beat dir: baseline ACTIVE=10 ⇒ REFUSE; the 4 frozen
sids flipped to `limited` ⇒ ACTIVE=7 ⇒ ADMIT — the exact term that parked a recovery at 9 > 8.

Consumer census (P4, 13 readers): kind-agnostic readers (`hooks/lib/cc-beat.sh:41-82`,
`cc-reaper`, `cc-teardown`, `teammate-auto-shutdown`, `cc-inbox-guard`, `measure-terminations.py`)
read only `.t/.operatorT/.pid/.lstart`; the three kind-testing readers all test `== "prompt"`
(`spawn-presence.sh:319`, `hooks/lib/session-busy.sh:335,342`, `bin/cc-await-ping:570`), so an
unknown kind degrades to "not busy / not a new turn" — the safe direction. The enum was already
extensible (`docs/plans/SESSION_REGISTRY_V2.md:231` declares `start|prompt|stop|end`; `start`/`end`
have never been written over 3,779 files). Residual, named not designed: `session_busy_live` renders
a limited session `IDLE-DEAF` — true, mis-named; a `LIMITED` state in its enum and renderers is a
separate change.

The census reads the beat as the freshest evidence of the death (`kind:"limited"`, `t`, and the
writer's own `(pid,lstart)` — `session-beat.sh:85-93` walks to the claude ancestor), which is the
liveness handle for the 21.4 % of rate_limit sessions with NO registry row (P5). Two bats rows pin
the contract, not the literal (§ 11): `kind=limited is NOT counted mid-turn`, `kind=zzz is NOT
counted mid-turn`.

## 6. The shared limit predicate — ONE module, and the migration of the copies

### 6.1 The module: `scripts/limit-recover/lr_predicate.py` (+ `lr-predicate.sh` shim)
Body = P3's `lr_classify.py` (written, self-tested: 490/490 rate_limit events classified, 0 false
positives on 106 non-rate_limit; `quotaLimits.resetsAt` vs prose AGREE 408 / DISAGREE 0), shaped
into P9's three tiers, one vocabulary, importable in-process by `cc-limited` (no fork) and callable
from bash through the shim (one fork, only on paths that already fork python):

```
T0 envelope   type=="assistant" ∧ isApiErrorMessage            MANDATORY, never relaxed (LR-o: the skill listing quotes the strings)
T1 membership error=="rate_limit" ⇔ apiErrorStatus==429 (490/490 both ways) ⇒ limit=True; kind from quotaLimits.rateLimitType
              {five_hour, seven_day}; resets_at = quotaLimits.resetsAt (epoch, authoritative); other errors map:
              authentication_failed→auth_cliff · server_error+529→server_529 · server_error+no status→network · oauth_org_not_allowed→org_blocked
T2 text       ONLY when T1 leaves kind unresolved: re.search(r"You've (?:hit|reached) your (?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit")
              session→five_hour · weekly→seven_day · Fable→fable · monthly spend→monthly_spend · <Other>→model_scoped:<Other>
              prose reset parsed in the NAMED timezone; resets_at None for fable/monthly_spend/model_scoped ⇒ recoverable_by_waiting=False
returns       {limit, kind, membership, resets_at, resets_source∈{quotaLimits,prose,none}, model, raw_error, recoverable_by_waiting}
```
`classify_text(last_assistant_message)` (T2 only, for the hook's `cap` field and the marker's
`last_assistant_message`) and `classify_record(dict)` (T0-T2) are the two entry points.

### 6.2 The copies (P9: 16 sites; the four decision-bearing ones disagree) and the order they migrate

| step | site | today | change | blast radius |
|---|---|---|---|---|
| 1 | new module + `tests/lr-predicate.bats` (F1-F10) | — | land alone, no call sites | 0 |
| 2 | `bin/cc-limited` | — | imports it (the first consumer; nothing else changes) | 0 |
| 3 | `scripts/limit-recover/lr-audit.py:75-79` LIMIT_PREFIXES, `:80` SERVER_529 (matches 0/924 events), `:244` classify_limit_text (`startswith`) | Fable ⇒ `other_api_error` ⇒ never parked (LR-blind at `scripts/limit-reset-safety-gate.sh:114-121` is STALE: the shape has been captured 19 times) | delegate to `classify_record`; delete SERVER_529 | the only `startswith→search` behaviour change; goes alone |
| 4 | `scripts/limit-recover/lr-reset-poller.sh:746` pre-filter `You've hit your (session\|weekly) limit`, `:771` allowlist `('session','weekly','fable')` (`fable` is a branch its producer cannot emit — `grep -c fable lr-audit.py` ⇒ 0) | 10.4 % blind | `:746` ⇒ `grep '"error":"rate_limit"' ∧ envelope`; `:771` ⇒ "kind has a reset" (fable rows are SURFACED by the census, not parked) | poller only |
| 5 | `scripts/limit-recover/lr-lib.sh:156` (`"limit" if "You've hit your"`) vs `:55` (`hit your`/`reached your`) — one file, two predicates, split on Fable | `hooks/recover-inject.sh:98-101` tells the operator a Fable cap is "NOT a quota message" | `:156` delegates via the shim; recover-inject inherits | recover-inject |
| 6 | `scripts/limit-recover/lr-fleet.sh:108` LIMIT_RE, `:122` NET_RE, `:143` lf_kinds_of | already 100 % recall (209/209) | retired with `lf_locate` (§ 10.1); `--tsv` must be byte-identical on `tests/lr-fleet.bats` fixtures | parity-gated |
| 7 | veto sites `bin/cc-classify:312`, `scripts/desk-invariant.sh:148-156` | 0 false positives, 19 misses | UNION the module's verdict with the existing regex — a veto must never lose coverage | 0 |
| 8 | CLI-stdout copies `scripts/handoff-fire.sh:9236`, `scripts/cloud-ceiling-probe.sh:212`, `scripts/lib/cloud-create.sh:174` | different domain (stdout, not JSONL) | comment naming the SSOT; a lint refusing any NEW transcript-JSONL limit regex outside the module | 0 |

### 6.3 Red-proof fixtures (verbatim strings from the corpus, receipts in P3/P9)
F1 fable-park: `"You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."`, error `rate_limit`, 429, quotaLimits ABSENT, version 2.1.260 ⇒ kind=fable, listed, resets — (RED today on lr-audit:244, poller:746). F2 fable-no-reap: cc-classify must answer `rate-limited` (highest consequence). F3 next-model: `"You've hit your Sonnet limit"` ⇒ `model_scoped:Sonnet` (RED even on lr-fleet's widened LIMIT_RE — proves the open scope group). F4 structural-reset: quotaLimits-only record, no prose ⇒ resets_at from epoch (RED: RESET_RE finds nothing ⇒ `:773` `continue`). F5 no-zoneinfo: ZoneInfo forced None, reset still resolves via epoch. F6 spend-packet, F7 529-not-limit (`API Error: 529 Overloaded…`), F8 network-not-limit (ENOTFOUND, same envelope) — regression guards. F9 skill-listing: BOTH spellings present with NO envelope ⇒ not a limit — the suite's FIRST assertion, the only test that can catch a T0 regression. F10 auth-cliff: `Not logged in · Please run /login` ⇒ auth_cliff, never a limit.

## 7. Statusline identity — an IDENTIFICATION primitive, never a detection one

Render `#<pane> <sid8>` LEFT-anchored so it survives the 30-column panes (5 of 16 live panes are
30 cols; U07 § 2b). Insert at `statusline.sh:486`, between `GLYPH_PREFIX` and `PCT_SEG`:

```bash
_id_pane="${KITTY_WINDOW_ID:-}"; [ -n "$_id_pane" ] || { _id_pane="${ITERM_SESSION_ID:-}"; _id_pane="${_id_pane##*:}"; }
_id_sid8="${PAY_SID:0:8}"            # PAY_SID already extracted by the single jq pass at :77-86
ID_SEG=""; if [ -n "$_id_pane" ] || [ -n "$_id_sid8" ]; then ID_SEG="#${_id_pane:-?} ${_id_sid8:-?} · "; fi
echo -e "${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}${OUTPUT}${RESET}"
```
Zero forks (P6: −0.2 ms/render CPU, inside noise; U07: +1.2 ms wall, +14 cols). Glyph `#` (U+0023,
Monaco-covered), NOT `⌗` (U+2317, `fc-list ':charset=2317' | grep -c ^Monaco` ⇒ 0 — the same
downsample class as the five reverts recorded at `tests/statusline-identity.bats:25-30`). Result at
30 cols: `(3) #124 26cd14be 40% · cla` — pane and sid8 both legible; the binary truncates right
(`<Text wrap="truncate">`, P6). Do NOT set `statusLine.refreshInterval` to 1 (61 ms CPU × 16
panes ≈ one saturated core); 10–30 s only if a freshness tick is ever wanted. Do NOT read
`rate_limits` as a limit flag: it vanishes from the payload once `resets_at` passes, and 13 of 26 of
today's limited sessions had no telemetry row at all. Free companion (0 forks, rides the telemetry
`jq` at `:149-156`): `pane`, `session_name`, `rate_limits.five_hour.{used_percentage,resets_at}` into
`/tmp/cc-telemetry/<sid>.json` — useful to the ranker, NOT an input to this census.

Converge is the cost: `~/.claude/statusline.sh` is a COPY (`readlink -f` ⇒ itself; install.sh:219-232
`copy_file`, `:960`), repaired ONLY by `install.sh`, which `scripts/deploy-live.sh:1310-1333` cannot
run on the steady state and runs only on the ADVANCE path (`:1770`). § 12 gives the step.

## 8. Push / notification — the beat, the kick, and ONE line per (account, reset)

Derive-on-read means no daemon of its own. Push = (a) § 4.3's beat — the fleet's presence spine
flips to `limited` within 1 s of the death, which `cc-board`/`cc-await-ping` readers see as "not
mid-turn" immediately; (b) § 4.4's kick — the poller tick runs within ~10 s instead of ≤ 600 s; (c)
inside that tick, ONE operator-facing notification per (account, resetsAt), through the surface the
poller already owns (`lr-reset-poller.sh:1028` `osascript display notification`), rendered FROM the
census:

```
lr-reset-poller: next3 — 5 sessions capped (five_hour, resets 21:30Z in 13m): #111 #147 live, 3 claimed-not-live. cc-limited
```
The latch is DERIVED, not stored: the tick greps its own `poller.log` for a `LIMITED next3
reset=2026-09-19T21:30:00Z` line already present (the log is append-only and per-tick); same key ⇒
no second notification. No `.notified` file is added (the poller's existing `parked/<sid>.notified`
stays for its own arm). `hooks/push-critical.sh` stays inert (`:21` exits without PUSHOVER_TOKEN,
measured) — nothing here depends on it. Paging discipline holds: N deaths of one cause ⇒ one line,
because the key is (account, resetsAt), the server-side 10-minute boundary every session on one
account shares (P3: 408/408).

## 9. Fault visibility — `CLAIMED-NOT-LIVE`, a query over claims that already exist

The operator's rule: a claimed resume/recovery that produced nothing must be NAMED with sid + pane
+ log path, never silently abandoned. Under this anchor the claims are already on disk:

| claim | writer | fields |
|---|---|---|
| `~/.reso/limit-recover/locks/<sid>.lock` | lr-transplant.sh | `{sid, from, to, ts, pid, host}` — measured: `98f02458 … to=/Users/chrisren/.claude-secondary ts=2026-09-19T20:53:26Z pid=32971` |
| `~/.reso/limit-recover/fleet/<run>/results.tsv` | lr-fleet.sh:412 `lf_row` | `sid pane→ pane← acct→ acct← mech/verdict note ts` — measured: `8843bcf3 149 149 next3 next2 recycle-in-place/RECOVERED - 2026-09-19T21:02:30Z` |
| `~/.reso/limit-recover/results/<sid>.json` + `.log` | lr-reset-poller.sh:658-660 | `{sid, rc, ts, log, requested_by}` |
| `~/.reso/limit-recover/requests/<sid>.json` | lr-fleet.sh:514-534 `--enqueue` / (recovery chain) | `{sid, target, source_pane, requested_by, ts}` — an UNDRAINED request older than 2 ticks is also a named fault |

The rule, evaluated at every census: for a blocked sid with a claim whose `ts` is older than
`CC_LIMITED_CLAIM_GRACE_S` (default 120 s — above the 90 s dead-wait at `handoff-fire.sh:6811-6815`
so a relaunch in flight is not falsely named), if NO registry row for the sid is live (pid,lstart)
on the claimed account AND no beat of kind `prompt|stop` on the sid is younger than the claim ⇒
`CLAIMED-NOT-LIVE`, rendered as
`← <mechanism> to <acct> claimed <ts> by <pid|requested_by> (<lock|results.tsv|results.json path>); no live process after <age>`.
A `PARTIAL` results row (`rc=4`, "tombstoned husk") is named until a later RECOVERED row or a live
row supersedes it. Today that names 98f02458 (21 min), 4bc1159f and 26cd14be — three of the eight
next3 deaths, invisible to both shipped instruments. `cc-limited --reaper` prints only these rows,
one per line, and the poller tick logs them as `CLAIMED-NOT-LIVE <sid> …` (§ 10.2) so the
`poller.log` carries the fault even when nobody runs the census. Cross-check that the query is
sound: the same rule reads 8843bcf3 (RECOVERED 21:02:30Z, live row #149 on next2, last record a
real turn) as RE-ENGAGED — a true claim clears itself with no bookkeeping.

## 10. Consumers — one census, four readers

### 10.1 `lr-fleet.sh`
`locate)` at `:434-435` becomes `exec /usr/bin/python3 "$LR/../bin/cc-limited" --tsv ${JSON:+--json}`;
`lf_locate` (`:183-254`), `lf_kinds_of` (`:143`), `lf_err_age_s` (`:166`), `lf_dedup_mirror`
(`:256`), `LIMIT_RE/NET_RE/BLOCK_RE` (`:108-123`) are deleted (−~110 LOC). The 11-field TSV
contract (`sid cfg acct pane pid cwd tier disp kind kinds err_age`) is kept byte-identical for the
`recover)` loop at `:456-470` and for `tests/lr-fleet.bats` — the parity test in § 11 is the gate.
`--one SID` (`:488-504`) stops running the full census first (`:496`): it calls `cc-limited --sid
SID --tsv` (≈ 55 ms) and falls back to `--deep` only on exit 4. `:217`'s DUPLICATE boolean is
retired with `lf_locate`; the census's cardinality rule replaces it. `:534` prints bare `kickstart`.
`--enqueue` (`:514`) reads the same rows and gains nothing else.

### 10.2 `lr-reset-poller.sh`
§ 1 DETECT (`:740-795`: `find -H … -mmin -2880` + text grep + one `lr-audit` subprocess per
candidate + `cwd_of`) becomes one call: `cc-limited --json --account "$acct"`; rows with
`recoverable_by_waiting ∧ state ∈ {RECOVERABLE, NO-PANE, RESET-PASSED/LIVE}` are parked exactly as
`:788` does today (same record shape, same event-keyed REPARK rule `:775-785`); `TEAMMATE` rows
write `teammate-skip/<sid>` as `:752-757` does; `fable`/`monthly_spend` rows are logged
`LIMITED-NOWAIT` (never parked — the `:771` allowlist's dead `fable` branch retires). Three
observability lines land in the same edit (P7's Part C, prerequisites of any faster trigger):
`:185` logs `TICK-SKIP held by pid $_hp` before `exit 0`; a `TICK <n> census=<ms> parked=<k>
claimed-not-live=<m>` heartbeat per tick; `:293-296` gates its `break` on `declare -F
cc_acct_name_for_dir_basename` and hard-fails with `FATAL account map unusable` (the
`poller.launchd.err` `command not found` class — mtime Sep 15, since fixed, but the guard is what
keeps it fixed). § 2 RESUME (`:870-1031`) is untouched — the recovery chain is out of scope.

### 10.3 `/recover` and `/limit-recover`
`commands/recover.md:101` ("Read KIND per unit from `lr-fleet.sh --locate`") and
`commands/limit-recover.md:404-410` (fleet `--locate`) point at `cc-limited --json`; the state enum
in § 1.3 replaces the disposition prose. `hooks/recover-inject.sh:98-101` inherits the SSOT through
`lr-lib.sh:156` and stops calling a Fable cap "NOT a quota message".

### 10.4 The operator
`cc-limited` (the screen in § 2) · `cc-limited 147` · `cc-limited bottle` · `cc-limited --reaper`.
No screenshot, no pane visit, no `cc-sessions` (30–41 s, no sid column — U07 § 0).

## 11. Tests — bats red-proofs, fixtures named from real sids (zeroed tails, per tests/lr-fleet.bats:17-27)

Hermetic seams already exist and are reused unchanged: `STOP_FAILURE_MARKER_DIR`, `STOP_FAILURE_IDL`,
`STOP_FAILURE_ACCOUNTS` (stop-failure-marker.bats:26-33), `CC_REGISTRY_DIR`, `LR_STATE_DIR`,
`LR_CONFIG_DIRS` (lr-fleet.bats:10-16), `CC_BEAT_DIR`/`CC_BEAT_NOW` (session-beat/spawn-presence).
`cc-limited` adds `CC_LIMITED_PS` (a file standing in for `ps -eo pid=,lstart=`) so liveness is
fixtured, never read from the real table — the lesson lr-fleet.bats:17-24 records (a fixture sid
that was live on the box turned RECOVERABLE into DUPLICATE). Every fixture sid keeps its real 8-char
prefix with a zeroed tail.

### 11.1 `tests/cc-limited.bats` (new, 13 tests, ~200 LOC)
| # | fixture | asserts | RED against |
|---|---|---|---|
| 1 | `07e30aeb-…-0000`: marker tp → 2,886-byte stub (3 non-assistant records) under next3; full blocked copy under next2; registry row #147 live on next3 | RECOVERABLE #147, tp = the full copy | prototype (`RE-ENGAGED`, dropped) |
| 2 | `98f02458-…-0000`: lock `{to:next2, ts:now−1260}`; blocked successor under next2; no registry row | CLAIMED-NOT-LIVE, reason names `pid 32971`, the lock path, `21m` | prototype (`MOVED`), `--locate` (blind) |
| 3 | same as 2 with `ts:now−60` | NOT named (inside CLAIM_GRACE 120 s) — a relaunch in flight is not a fault | a reaper with no grace |
| 4 | `65186f1f-…-0000`: marker under `rate_limit__next3`; registry row account `claude-secondary`, live; live copy's last record a real turn | RE-ENGAGED, grouped under next2, never queued | filename grouping (CONTROL below) |
| 5 | `09e64dcb-…-0000`: one live registry row + one `--resume` leaf in `CC_LIMITED_PS` | RECOVERABLE, not DUPLICATE | lr-fleet.sh:217 |
| 6 | four marker rows, one sid, ts ascending | one row, `fires=4`, `err` from the MAX(ts) row | `wc -l` censuses |
| 7 | a marker row with `session_id:"?"` | footer `1 unaddressable`, exit 0, row absent from groups | silent drop |
| 8 | F1 Fable text, quotaLimits absent, live pane | listed, `cap=fable`, `resets —`, `recoverable_by_waiting:false` | poller:746, lr-audit:244 |
| 9 | `config_dir:"/Users/x/.claude"` with accounts.json `next.aliases=["claude"]` | account `next`, no fifth group | hook :85-87 today |
| 10 | `--keyword limit-recover` over two live panes on two accounts with the same title | exit 3, both candidates printed `pane · sid8 · account · title` | any recency tie-break |
| 11 | NO-PANE row whose cwd is deleted between fixture and call | CWD-GONE (resolved at read time) | marker-time cwd |
| 12 | `CC_REGISTRY_DIR` pointed at a missing dir | exit 5, stdout EMPTY, stderr names `cc-registry` | an empty list at exit 0 (lr-fleet.sh:441-447 class) |
| 13 | PARITY: the six `locate:` fixtures of tests/lr-fleet.bats:55-96 run through `cc-limited --tsv` | byte-identical 11-field rows to `lf_locate \| lf_dedup_mirror` at the parent commit | any drift in the legacy contract |
| C | CONTROL (stop-failure-marker.bats:171 pattern): a mutant that groups by marker FILENAME | test 4 must go RED | proves test 4 can fail |

### 11.2 `tests/stop-failure-marker.bats` (+5, ~45 LOC)
`pane field from KITTY_WINDOW_ID` (env `KITTY_WINDOW_ID=112` ⇒ `"pane":"112"`) · `ITERM tail fallback`
(`ITERM_SESSION_ID=w0t0p0:112`, no KITTY ⇒ `"112"`) · `a rate_limit death writes ONE beat kind=limited
through session-beat.sh` (CC_BEAT_DIR fixtured; `.who=="auto"`, a prior `operatorT` preserved) ·
`the daemon kick is invoked bare, by absolute path, under PATH=/usr/bin:/bin` (the binary path is a
seam, `CC_SF_LAUNCHCTL`, defaulting to `/bin/launchctl`; the test stubs it and asserts argv
`kickstart gui/<uid>/com.reso.lr-reset-poller` with NO `-k`) · `CC_SF_BEAT=off CC_SF_KICK=off ⇒
marker unchanged, zero beat, zero kick`. Test :149's write-footprint pin gains the beat dir.

### 11.3 `tests/spawn-presence.bats` (+2), `tests/session-beat.bats` (+1), `tests/statusline-identity.bats` (+1), `tests/lr-predicate.bats` (new, F1-F10)
`kind=limited is NOT counted mid-turn` and `kind=zzz is NOT counted mid-turn` (the CONTRACT: unknown
⇒ not counted) · `the limited write preserves operatorT and sets who=auto` · `#<pane> <sid8> is
left-anchored and survives a 30-col truncation` (layer 2 at :53-76) · F1-F10 from § 6.3, F9 first.

## 12. Deploy / converge / operator-owned steps

| artefact | class | goes live by | receipt |
|---|---|---|---|
| `hooks/stop-failure-marker.sh`, `hooks/session-beat.sh` | symlink | on land — `~/.claude/hooks/*` resolve into the checkout (`readlink`, this unit) | live layer = per-file symlinks (deploy-live.sh:1310-1333) |
| `bin/cc-limited`, `scripts/limit-recover/lr_predicate.py`, `lr-predicate.sh`, `lr-fleet.sh`, `lr-reset-poller.sh`, `lr-audit.py`, `lr-lib.sh` | symlink | on land (`~/.claude/scripts/limit-recover/lr-fleet.sh → checkout`, measured) | same |
| `statusline.sh` | COPY | the granted degraded-tier deploy-live run (`CC_DEPLOY_MAX_LAG_COMMITS=0`, .claude/CLAUDE.md:35-47 per P6) in the landing session, then CONFIRM an advance ran — install.sh runs only on the advance path (deploy-live.sh:1770); otherwise `deploy-parity-assert.sh` reports COPYSTALE and nothing automatic clears it | install.sh:219-232, :960 |
| `~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` | operator c10, OPTIONAL backstop | insert `QueueDirectories = [~/.reso/limit-recover/requests]` and `ThrottleInterval = 5` with plutil, then boot the job out and back in (the exact four commands are P7's Part B); never WatchPaths (`man launchd.plist:330-338`), keep StartInterval 600 | P7 |
| `~/.claude/settings.json` | untouched | the hook is already registered on StopFailure in all 5 dirs | U10 § 1c |
| `~/.claude/accounts.json` | untouched | aliases already carry `.claude → next` | § 0 correction 2 |

Landing order (each step independently landable, blast radius non-increasing): (1) module + bats;
(2) `bin/cc-limited` + bats — no consumer changes, the operator can run it beside `--locate` for a
day; (3) hook arm (§ 4) — detection latency drops to ~1 s + kick; (4) `lr-fleet --locate` delegates,
parity test green; (5) poller § 1 delegates + the three observability lines; (6) lr-audit / lr-lib /
veto unions; (7) statusline chip + install converge; (8) optional plist c10.

## 13. Files touched — file:line and LOC (every line above was READ this unit)

| file | lines touched | Δ LOC |
|---|---|---|
| `bin/cc-limited` (NEW, `#!/usr/bin/python3`, stdlib only, imports lr_predicate) | — | +260 |
| `scripts/limit-recover/lr_predicate.py` (NEW; body from wave2/P3-quotalimits/lr_classify.py 107 LOC + tiers + open scope group) | — | +140 |
| `scripts/limit-recover/lr-predicate.sh` (NEW shim: `classify-text`, `classify-record`, `classify-tail`) | — | +25 |
| `hooks/stop-failure-marker.sh` | :85-87 (alias-aware select) · after :89 (PANE) · before :115 (beat) · :122-127 (pane, cap fields) · after :128 (kick, IDL extra) | +14 |
| `hooks/session-beat.sh` | none (`:124` already takes the kind; `:62` already skips `who` for non-prompt) | 0 (+2 comment) |
| `scripts/lib/spawn-presence.sh` | none (`:319` already excludes non-prompt) | 0 |
| `scripts/limit-recover/lr-fleet.sh` | :108-123 · :143-182 · :183-254 · :256-262 deleted; :434-435 exec; :496-504 `--one` inversion; :534 bare kickstart | −110 / +18 |
| `scripts/limit-recover/lr-reset-poller.sh` | :185 (+1 log) · :293-296 (+3 guard) · :740-795 detect loop → census call (−45 / +22) · :771 · tick heartbeat (+2) · LIMITED notify arm (+12) · CLAIMED-NOT-LIVE log (+4) | −45 / +44 |
| `scripts/limit-recover/lr-audit.py` | :75-79, :80, :244 delegate | −10 / +6 |
| `scripts/limit-recover/lr-lib.sh` | :156 delegate via shim | −1 / +3 |
| `statusline.sh` | :486 (ID_SEG) | +4 |
| `bin/cc-classify:312`, `scripts/desk-invariant.sh:148-156` | union with the shim's verdict | +2 / +2 |
| `commands/recover.md:101`, `commands/limit-recover.md:404-410` | point at `cc-limited --json`, state enum | +8 |
| `tests/cc-limited.bats` (NEW) · `tests/lr-predicate.bats` (NEW) · `tests/stop-failure-marker.bats` · `tests/spawn-presence.bats` · `tests/session-beat.bats` · `tests/statusline-identity.bats` | § 11 | +200 · +120 · +45 · +20 · +12 · +10 |
| **net** | | **≈ +770 / −166; runtime code ≈ +330 net** |

## 14. The anchor's trade-offs, honestly, and what stays UNMEASURABLE

**What derive-on-read buys.** No schema, no GC, no lock, no write race, no migration: every fixture
is a directory of files that already exist in production shapes, and every bug is reproducible by
copying a store. Decay is handled by construction — `transcript_path` (stale on 16/31 rows, all
`.handed-off`), `cwd` (1→3 CWD-GONE in 20 min), `account` (flips under a constant sid within 4 min)
are re-read at every call, so the census can never be wrong for longer than one read.

**What it costs, and the cover for each.**
1. *A read cost on every query* (~55–200 ms). Fine for a CLI, a 600 s daemon tick, `/recover`; NOT
   for a 1 s statusline tick — § 7 forbids that route anyway.
2. *The marker is a 24 h rolling window* (`stop-failure-marker.sh:100`, TTL 1440 min, mtime-keyed,
   whole-file delete). A `seven_day` cap outlives its marker. Cover: the second enumerator is
   `parked/` (event-keyed, retired only by the poller's own arms) — a seven_day row is parked within
   one tick of its death and stays until reset; retrospective questions go to the IDL
   (`gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz`), which is history, not detection. Residual: a
   seven_day death whose poller tick was skipped on the lock (§ 10.2's TICK-SKIP line is what makes
   that visible) for 24 h has no live enumerator — named, not solved; an event-state design closes it
   at the price of a store.
3. *Headless `claude -p` / sdk-cli deaths emit no StopFailure* (0/2, P1). No marker, no beat, no
   registry row (`session-register.sh:127-132` returns on no address). Cover: `--deep` (the U14 A4
   single-pass scan, 0.15 s) and the fire-side ledger; the default view prints `(-p sessions: run
   --deep)` in its footer so the gap is visible on every screen.
4. *Successor location is INFERRED* (lock.to ∧ live copy's cfg ∧ registry.account), not recorded by
   the transplant as a session-state fact. The inference is pinned by tests 1-5 and its failure
   class has its own state (UNKNOWN-STUB). An event-state design records it; this one derives it.
5. *Pane provenance rides env inheritance.* Under tmux the inherited `ITERM_SESSION_ID` is the
   server's (session-beat.sh:49-50); under launchd there is none. Cover: the registry join is the
   authority when present; disagreement renders both (`#112(reg)/#111(marker)`); absence ⇒ NO-PANE.
6. *The claim grace is a constant* (120 s). Too low names an in-flight relaunch; too high hides a
   husk for longer. The 90 s dead-wait at handoff-fire.sh:6811-6815 is the measured floor; the
   value is a seam (`--claim-grace`) and the recovery wave will move it when it kills the dead-wait.

**UNMEASURABLE in this unit (read-only, no hook may be run against live stores):** the hook's
end-to-end cost with all three arms (components: 0.19–0.25 s today, beat writer ≤ 3 s by hard
timeout, the kick unmeasured but a single IPC to launchd); whether `StopFailure` fires inside an
Agent-Teams assignee on a cap (0 instances in the corpus; SF-e in U10 is the fixture that must
establish it); whether a kicked tick reaches the census call under the overlap lock within the 10 s
ThrottleInterval when a tick is already running (launchd coalesces; the TICK-SKIP log line is what
will answer it); the true "cold" census time (no cache purge permitted; 0.199 s is first-run-of-session
with the full index, a lower bound on the gap to 35.5 s).

## 15. Receipts — commands run by this unit (all read-only; outputs quoted above)

- `git rev-parse --short HEAD` (claude-infrastructure) ⇒ `226b73888`; `git status --short` ⇒ clean.
- `cat -n hooks/stop-failure-marker.sh` (131 lines): fields :70-75, abstain :79, account :82-89, cause key :92-94, GC :100, FIRST :105-111, cap :115-118, line :122-128, IDL :130.
- `sed -n 1,140p hooks/session-beat.sh`: pane :55, kind :58, who gate :62, walk :85-93, carry :98-108, write :111-117, entry :124, timeout :40/:126.
- `sed -n 285,335p scripts/lib/spawn-presence.sh` ⇒ `:319 select(.kind == "prompt" …)`; `sed -n 778,795p scripts/lib/capacity-admit.sh` ⇒ `:782 act_ceiling=…:-8`, `:789 [ $(( act + 1 )) -gt "$act_ceiling" ]`.
- `sed -n 328,346p hooks/lib/session-busy.sh` ⇒ `:335 kind=…`, `:342 [ "$kind" = "prompt" ]`.
- `grep -n` anchors: lr-lib.sh :20/:34/:55/:129/:156/:210/:233/:262 · lr-reset-poller.sh :123/:152/:185/:281/:293-296/:646/:746/:752/:771/:788/:795/:896/:1028 · lr-fleet.sh :108/:122/:143/:183/:210/:216/:217/:256/:434/:456/:488/:496/:514/:534 · lr-audit.py :75/:80/:81/:209/:244 · session-register.sh :127/:158/:282/:290 · statusline.sh :77-86/:486 · idl-log.sh :64/:117 · account-map.generated.sh :44-47 · cc-classify :312 · desk-invariant.sh :148 · limit-reset-safety-gate.sh :114-121 · recover-inject.sh :98-101 · agent-identity.sh :33 · origin-identity.sh :237 · install.sh :219-232/:960 · deploy-live.sh :1310-1333/:1770.
- `cat ~/.claude/accounts.json` ⇒ no `~/.claude` row; `next.aliases == ["claude"]`; `_port_index` note defines aliases.
- `ls -ld ~/.claude ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary` ⇒ all five directories exist; `readlink -f <dir>/projects` ⇒ only `.claude-next` resolves elsewhere (`/Users/chrisren/.claude/projects`).
- Marker inventory: `rate_limit__next3.jsonl 12 rows / 8 sids`, `rate_limit__next4.jsonl 14 rows / 7 sids`, `authentication_failed__.claude.jsonl 5 rows / 5 sids` (the phantom account); parked/ 7 files, all next3, reset `2026-09-19T21:30:00Z`; registry 36 files (31 numeric rows); beats 3,782 files; locks 47.
- Timings: `registry rows=31 read=1.4ms ps=30.8ms live(pid+lstart)=13` · `transcript glob 4 real roots: 2223 paths in 143.4ms` · `marker rows=31 read=0.3ms` · `jq -rs … cc-beats/*.json` ⇒ 1723 prompt beats, `real 0.09` · `slug-directed probe: 14 sids x4 roots -> 27 copies in 5.4ms; per-sid wildcard-dir glob -> 27 copies in 907.9ms` · prototype `elapsed 0.040s`, `0.074 total` · `census-probe.py` `stage_ms {"accounts":0.1,"markers":0.7,"parked":1.0,"registry+ps":33.7,"transcript-index":120.9,"resolve":134.4,"kitty-ls":199.3}` (cumulative).
- `ls -la ~/.claude*/projects/*/07e30aeb*` ⇒ `.claude-secondary/…/07e30aeb….jsonl 1157520` · `.claude-tertiary/…/07e30aeb….jsonl 2886` · `….jsonl.handed-off 1157520` · `….HANDOFF.json 341`.
- `cat ~/.reso/limit-recover/locks/98f02458-….lock` ⇒ `{"sid":…,"from":"/Users/chrisren/.claude-tertiary","to":"/Users/chrisren/.claude-secondary","ts":"2026-09-19T20:53:26Z","pid":32971,"host":"Chriss-MacBook-Pro-3"}`; newest `fleet/one-20260919T210124Z/results.tsv` ⇒ `8843bcf3… 149 149 next3 next2 recycle-in-place/RECOVERED - 2026-09-19T21:02:30Z`; `requests/` empty; `results/` 7 pairs.
- `grep -rln 'stop-failure' scripts bin hooks` (minus the hook itself) ⇒ `scripts/growth-coverage.conf`, `hooks/config-mirror-assert.sh` — no recovery reader of the markers.
- `readlink ~/.claude/hooks/stop-failure-marker.sh` / `session-beat.sh` / `~/.claude/scripts/limit-recover/lr-fleet.sh` ⇒ all resolve into `/Users/chrisren/Development/claude-infrastructure/…` (symlink class); U07 § 1 `readlink -f ~/.claude/statusline.sh` ⇒ itself (copy class).
- `grep -n PUSHOVER_TOKEN hooks/push-critical.sh` ⇒ `:21 [ -z "${PUSHOVER_TOKEN:-}" ] && exit 0` (inert).
- Test inventories: `@test` counts lr-fleet 33 · spawn-presence 33 · session-beat 14 · lr-lib 19 · statusline-identity 23 · stop-failure-marker 15 (CONTROL pattern at :165-171).
- `kitten @ --to unix:/tmp/kitty-73832 ls | jq '[…windows[]]|length'` ⇒ 19 windows (one unmatched call).
