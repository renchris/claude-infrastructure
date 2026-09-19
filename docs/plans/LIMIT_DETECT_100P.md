---
status: open
created: 2026-09-19
owner: session 7f533f05 (lead; research by 11569d45 wave 1 + 7f533f05 wave 2)
receipts: docs/research/lr-detect-2026-09-19/
---

# LIMIT_DETECT_100P — limit-recover DETECTION + IDENTIFICATION + SURFACING: the implementation plan

Synthesizer unit, wave 2, written 2026-09-19 ~23:15Z. Repo `claude-infrastructure` @ **`a59b53e55`** (the three
designs were written at `226b73888`; every `file:line` below was RE-READ at `a59b53e55` this unit — the only drift found:
`lr_transplanted_to` is now `lr-lib.sh:287`, `lr-fleet.sh` is 581 lines, the poller's lock-skip `exit 0` is `:185`).
Inputs: P1–P10 receipts, Da/Db/Dc designs, 8 judge verdicts, the sibling research U01–U14, and 14 read-only
measurements taken here (§ 10). Scope of this document = the DETECTION + IDENTIFICATION + SURFACING slice only.
The recovery chain is carried in § 8 as later waves, one line each, never designed.

---

## Phase 0 — Agent Team Orchestration

### Execution locus per wave

| wave | locus | why (T/L only) |
|---|---|---|
| W0 predicate SSOT | **S** (dispatched session) | — |
| W1 hook arm + registry address | **S** | — |
| W2a census core | **S** | — |
| W2b census red-proof suite | **S** | — |
| W2c reaper / faults / resolver | **S** | — |
| W3 consumers (lr-fleet, poller) | **S** | — |
| W4 predicate-copy migration | **S** | — |
| W5 statusline chip + converge | **L** (lead-inline) | ≤ 20 LOC, and the converge step's ADVANCE must be confirmed by reading `deploy-live.sh`'s own output in the landing session (`deploy-live.sh:1770`: install.sh runs only on the advance path) — a dispatched session cannot hand that receipt back more cheaply than the lead reading one line |
| W6 acceptance drill | **L** | the drill is one command (`bats tests/cc-limited-drill.bats` + `/usr/bin/time -p bin/cc-limited` ×3) whose numbers the lead compares against § 5; no code is written |

### Roster

| id | title | files (pre-grepped ranges in § 3) | output LOC target | blockedBy | model / effort |
|---|---|---|---|---|---|
| W0 | `lr_predicate.py` + shim + F1–F10 bats | `scripts/limit-recover/lr_predicate.py` (new) · `scripts/limit-recover/lr-predicate.sh` (new) · `tests/lr-predicate.bats` (new) | ≤ 260 | — | opus-5 / high |
| W1 | hook arm (alias, pane, beat, page latch, kick sentinel, TTL/CAP) + `session-register.sh` KITTY fallback | `hooks/stop-failure-marker.sh:41-42,:85-87,:89,:100,:115,:122-127` · `hooks/session-register.sh:127` · `hooks/session-beat.sh:55` · `tests/stop-failure-marker.bats` · `tests/spawn-presence.bats` · `tests/session-beat.bats` · `tests/session-registry.bats` | ≤ 190 | — | opus-5 / high |
| W2a | `bin/cc-limited` core (enumerate → resolve → state → render → exit codes) | `bin/cc-limited` (new, python3 stdlib) | ≤ 290 | W0 | opus-5 / high |
| W2b | `tests/cc-limited.bats` (15 rows + 2 CONTROLs, fixtures from real sids) | `tests/cc-limited.bats` (new) + `tests/fixtures/lr-2026-09-19/` | ≤ 240 | W2a | opus-5 / high |
| W2c | `--reaper`, `faults/` persistence + `ack`, `<query>` resolver, `--kitty` titles | `bin/cc-limited` (+), `tests/cc-limited-reaper.bats` (new) | ≤ 200 | W2a | opus-5 / high |
| W3 | lr-fleet four call sites → `lf_census`; poller §1 delegation + 3 observability lines; docs | `scripts/limit-recover/lr-fleet.sh:217,:435,:456,:496,:530,:534` · `lr-reset-poller.sh:185,:293-296,:740-795` · `scripts/gen-account-map.sh:117` · `tests/lr-fleet.bats` · `commands/recover.md:101` · `commands/limit-recover.md:441` | ≤ 200 | W2a, W2c | opus-5 / high |
| W4 | the 12 predicate copies, blast-radius order | `lr-audit.py:75-81,:210-212,:244-248` · `lr-reset-poller.sh:566,:746,:771` · `lr-lib.sh:55,:156` · `bin/cc-classify:312` · `scripts/desk-invariant.sh:156` · a lint | ≤ 150 | W0 | opus-5 / high |
| W5 | `#<pane> <sid8>` chip + converge | `statusline.sh:486` · `tests/statusline-identity.bats` | ≤ 20 | — | lead |
| W6 | acceptance drill (§ 5) | — | 0 | W1, W2b, W2c, W3 | lead |

Every brief ≤ 150 lines; every line range above is pre-grepped (§ 3 carries the exact text at each anchor); no
"investigate"; verbatim "Stop on first issue, message lead"; no visual verification inline.

### Dependency graph

```
W0 ──┬──> W2a ──┬──> W2b
     │          └──> W2c ──> W3
     └──> W4
W1 (independent)          W5 (independent, lead)          W6 after W1+W2b+W2c+W3
```

### Fire order

1. **Wave 1** (parallel, one message): W0 · W1 · W5(lead).
2. **Wave 2** (after W0's ping): W2a · W4.
3. **Wave 3** (after W2a): W2b · W2c.
4. **Wave 4** (after W2c): W3.
5. **Wave 5** (lead): converge (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` — granted at
   `.claude/CLAUDE.md:41`; then `bash scripts/deploy-parity-assert.sh` must show no `MISSING`/`COPYSTALE`) · W6 drill ·
   the § 6 operator offer.

Each dispatched wave: `handoff-fire.sh --prompt-file … --worktree <branch> --notify-back … --goal '<DoD from § 4>, proven
by the named bats command the session runs and prints; do not edit settings*.json, plists or launchd'`. The lead does
NOT `cc-await-ping` under a live `/goal` (global CLAUDE.md § Agent Teams); `session-continue.sh set` is the cross-turn lever.

### Lead's context budget + succession point

The lead holds ≥ 50 % of its window for judgment: briefs (~8 × 150 lines ≈ 12 K tokens), pings (one line each), the
parity diff and the drill numbers (§ 5, ≤ 40 lines). Succession at **67 %** fill (`feedback-recycle-at-67-percent`):
`handoff-fire.sh --recycle --prompt-file <this doc>` with § 4's per-wave DoD table as the resume point — everything a
successor needs is this file plus `git log`; nothing lives only in the lead's context.

---

## Scope (frozen)

**Scope (frozen):** one process answers "which sessions are limit-blocked right now, on which account, until when, at which
pane, and which claimed recovery produced nothing" in < 0.3 s with no screenshot; the StopFailure hook stamps pane, flips
the phantom beat, and pages once per cause; the statusline names the pane and sid; one predicate replaces twelve. Nothing
here types into a pane, drains a request, moves a session, or edits `settings*.json`/plists/launchd.

---

## 1. The measured problem (every number carries its receipt)

| defect | measurement | receipt |
|---|---|---|
| **The census is 500–1,000× too slow, and its window is longer than the fleet's own state-change interval** | `lr-fleet.sh --locate` 35.5 s wall (real 35.46 / user 18.03 / sys 18.83) over 2,591 transcripts; 43.558 s in P8, 40–86 s in U14. Scan-only 10.0 s; the rest is ~1 s/hit of python×3 + jq×37×3 + ps per hit. Prototype over markers ∪ parked ∪ registry ∪ beats ∪ the 128 KB tail of NAMED transcripts: **0.07 s cold / 0.05 s warm**; Db's probe 0.134 s (no kitty) / 0.199 s; Dc's v2 147–163 ms internal, 0.22–0.24 s wall at load 50 | lead-findings.md § Measured; P8 `( time lr-fleet.sh --locate --json )` ⇒ `43.558 total`; P8: a transplant completed 32 s before `--locate` started and its `.handed-off` rename landed INSIDE the scan |
| **Detection → first recovery action = 2 h 37 m idle across five sessions** while every one sat named on disk | e442434c 45m30s · d02d8feb 5m31s · 09e64dcb 19m52s · cb227486 44m51s · 28f07827 41m16s = **2 h 37 m**; the two the operator "discovered" by screenshot at 12:57/12:59 had a marker since 12:07 | U10-limit-detect-hooks.md § 1g (fire times from `fleet/one-20260919T17*/results.tsv`) |
| **12.5 % of panes are unidentifiable from a perfectly fresh full-line screenshot** | panes 122 and 124 both render `(3) 40% · claude-infrastructure (b80f9408e) · high`; 2 of 16 identical | U07-statusline-identity.md:313 |
| **The active-session count carries limit-dead phantoms and it is the term that refused a recovery** | Stop never fires on a limit turn ⇒ `cc-beats/<sid>.json` stays `kind:"prompt"` (12/14 of today's rate_limit sids, beat.t − marker.ts ∈ {−1 s, −5 s}); `spawn-presence.sh:319` counts `.kind=="prompt"` ⇒ ACTIVE=10; `capacity-admit.sh:782-792` refuses at `act+1 > 8`; A/B flipping 4 frozen sids to `limited` ⇒ ACTIVE=7 ⇒ ADMIT. Today's poller parked a recovery at 9 > 8 | P4 receipts (hermetic fixture + A/B over a copy of the live beat dir); `capacity-admit.sh:789` read this unit |
| The event already fires and nothing reads it | StopFailure → `stop-failure-marker.sh` on 126/128 rate_limit records, p50 0 s, p95 1 s; only misses = 2 `sdk-cli` sessions; 0 abstains in 604 fires; **zero consumers of the marker dir** | P1; lead-findings (`grep -rln stop-failure` ⇒ config-mirror-assert + growth-coverage.conf only) |
| The marker's own fields rot | `transcript_path` stale on 16/31 rows (all `.handed-off`, shortest survival 644 s); `account` wrong for 3/11 resolvable sids (27 %); `wc -l` over-counts by 63 % (31 rows = 19 sids); `cwd` decays mid-census (1→3 CWD-GONE in 20 min) | P2 R2/R3b/R4/R6 |
| The registry cannot enumerate | 3/14 of today's rate_limit sids have no row (pane-keyed, one row per pane; `session-register.sh:127` has no address without `CC_PANE_ID`/`ITERM_SESSION_ID`); 14/44 of today's sessions rowless | P5 R4/R5; **this unit: pid 41639 (the lead's expect-launched successor) carries `KITTY_WINDOW_ID=186` and NO `ITERM_SESSION_ID`/`CC_PANE_ID` — an address `:127` cannot see** |
| The Fable cap is invisible to four copies of the predicate | 19/209 rate_limit records missed by poller `:746`, `lr-lib.sh:156`, `lr-audit.py:244`, `cc-classify:312` — all the same string; `quotaLimits` absent on 35/35 Fable records | P9; P3 |
| Poller detection lag and false green | marker → PARKED mean 323 s / max 609 s; `RESUMED … pane opened` logged twice at 19:43Z while `capacity-admit refused` 2–3 s later and the panes no longer existed | P7; lead-findings |
| Both shipped instruments mislabel | `--locate`: DUPLICATE on a single process (`lr-fleet.sh:217-218` tests rc, not cardinality) ⇒ parked forever; account from the directory a copy was found in (`:210`) ⇒ next2's transcript welded to next3's pane. Proto: dropped 07e30aeb (a 2,886-byte reborn stub read as RE-ENGAGED) | P8 |

---

## 2. The winning design and the decision record

### 2.1 Winner: **Db-derive-on-read**, with grafts

Scores (judge totals): Da 14 (4.5 + 5.5 + 4) · **Db 16 (5 + 6 + 5)** · Dc 14.5 (4 + 6.5 + 4). Db wins on score and on the
SHAPE of its fatals: every Db fatal is a resolver rule or a migration line that can be fixed inside the same architecture
(§ 2.3), whereas Da's fatals are properties of having a stored state machine (re-cap wipes `claim`; bogus latch key freezes a
document wrong forever; no serialization on a shared document; a `.done` sibling deletes a live document) and Dc's are
properties of painting a second copy of the truth onto a shared per-tab surface (no clear path on recycle; a subagent's
StopFailure paints the LEAD's pane; 4–5 splits per tab). The architecture is therefore: **the census is a pure function of
stores that already exist, computed by one process at read time; the hook adds only what no store holds (pane, the beat
flip, one page per cause).**

Two digest claims corrected by the designs and confirmed here: `~/.claude-secondary` EXISTS (the `next2` row is correct); the
phantom `.claude` account is an alias-resolution bug in the hook (`accounts.json` already has `next.aliases == ["claude"]`,
measured this unit), not a missing SSOT row.

### 2.2 Grafts taken from the other two designs (each was named as a graft by ≥ 1 judge)

| graft | from | lands in |
|---|---|---|
| Stored/derived split stated as an INVARIANT: nothing rendered as CURRENT (alive, pane owner, moved, engaged, reset_in, cwd_ok) is ever stored; only claims are | Da § 4.3 | W2a header comment + `tests/cc-limited.bats` mutant control |
| `claim{actor, ts, deadline, log}` + a reaper that NAMES a claimed recovery with no live process, with its log path; `FAULT` leaves only via `ack` | Da § 8 / § 19 | W2c as a **faults DIRECTORY** (`~/.reso/limit-recover/faults/<sid>.json`, append-once, never auto-removed) — not a state store |
| `PANE-REUSED` overlay (registry `<pane>.json .session_id != sid`) — the in-place recycle case Dc's census lied on | Da § 4.3 `pane_owner` | W2a state table |
| `kind:"limited"` beat through the EXISTING writer, placed BEFORE the cap early-exit | Db § 4.3 (Da/Dc concur) | W1 |
| Alias-aware `select()` in the hook, never a fifth `accounts.json` row | Db § 4.1 | W1 |
| Liveness = exact `(pid, lstart)` under ONE `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` (31.8 ms; the full table is 4× cheaper than `-p <37 pids>` at 123.8 ms) | Db § 1.2 / P5 R1 | W2a |
| DUPLICATE by cardinality of {registry live pids} ∪ {resume leaf pids} | Db § 1.3 | W2a + lr-fleet `:217` |
| Exit 5 = INSTRUMENT UNREADABLE with EMPTY stdout, stderr names it; never an empty list at exit 0 (`lr-fleet.sh:441-447`'s own bug class) | Db § 1.4 | W2a; W3's `lf_census` propagates it |
| Slug-directed transcript probe (`<root>/projects/<slug>/<sid>.jsonl*`, 27 copies in 5.4 ms vs 121 ms full index) | Db § 3 | W2a |
| O_EXCL per-cause page latch (`( set -C; : > f )`) — `page-damp.sh:42-50` is check-then-write and returns 0 on every failure, so 30 concurrent hooks would all send | Dc § 3.5 | W1, with the judge's three corrections: `mkdir -p`, fail-OPEN on a non-EEXIST error with an IDL row, key derived from the payload alone |
| `--tsv-legacy`-style byte compatibility with `lf_locate` kept as `--slow-scan` for one release, with `tests/lr-fleet.bats` running BOTH paths and diffing | Dc § 11.1 | W3 |
| Refuse ambiguity in the resolver (exit 3, every candidate printed as `pane · sid8 · account · title`); never disambiguate by recency | Dc § 7.6 / P10 | W2c |
| Title column for free from the last `"aiTitle"` in the 128 KB tail (within 33,389 B of EOF, 30/30); one unmatched `kitten @ ls` (29 ms) only under `--kitty`, bounded 2 s | P10 | W2a / W2c |
| `#` not `⌗` (U+2317 absent from Monaco: `fc-list ':charset=2317' \| grep -c ^Monaco` ⇒ 0); left-anchored; 0 forks | P6 | W5 |

### 2.3 Db's fatals and the fix each gets

| Db fatal (judge) | fix in this plan |
|---|---|
| Copy-selection by size picks a FROZEN snapshot as "the live copy" (07e30aeb: secondary 1,157,520 B frozen 15:32 vs tertiary 5,339 B growing with 0 assistant records; `cp -p` makes size AND mtime identical) | No "live copy" concept. **Liveness comes from the registry; blocked-ness comes from the UNION of evidence over ALL copies**: blocked ⇔ no copy holds a real assistant turn with `timestamp > death.ts`. The preferred `tp` for the row is the copy under the live registry row's account root, else the marker's `transcript_path` if it exists, else the copy holding the death record. A preferred copy with 0 assistant records renders `RECOVERABLE (stub)` — surfaced, never dropped, never MOVED. No mtime, no size ordering |
| Six silent no-marker paths (`:64,:65,:66,:79,:96,:115`) ⇒ clean empty screen at exit 0 | The census reads the live IDL's last 20,000 rows for `hook=="stop-failure-marker" ∧ disposition ∈ {abstained, passed}` in its window and `wc -l` of each marker file vs `STOP_FAILURE_CAP`; any abstain or a capped file ⇒ footer line `enumerator DEGRADED: …` and **exit 6**, never 0. W1 also moves every new arm ABOVE the cap exit and raises the defaults (§ 9 D3) |
| FAULT row self-erasing at the marker TTL; no ack; no second enumerator for fable/monthly | `faults/<sid>.json` written by `--reaper --persist` (poller tick) at first sighting, never auto-removed, cleared only by `cc-limited ack <sid> --why …`; the marker TTL default rises to the seven_day window (§ 9 D3) |
| TSV fields 9/10 vocabulary broke `lr-fleet.sh:525 [ "$kind" = limit ]` | `--tsv` field 9 stays `limit\|network\|other`, field 10 stays `kinds`; the cap sub-kind (`five_hour\|seven_day\|fable\|monthly_spend\|model_scoped:<Word>`) is a JSON field only |
| Blind to non-cap blocks (`server_error__*` markers); no RESUMING / CWD-GONE / IDLE-AFTER-ERROR | Enumerate ALL `*__*.jsonl` cause files; classify via the SSOT (`server_error`+no status ⇒ network, `authentication_failed` ⇒ auth_cliff); the state table keeps RESUMING, CWD-GONE, IDLE-AFTER-ERROR with their D7/D8 semantics; the parity gate runs every `locate:`/`D7:`/`D8:` case in `tests/lr-fleet.bats:55-96,:244-350,:394` through both paths |
| `lf_locate` deletion leaves `:456` and `:530` calling a dead function ⇒ `--recover`/`--enqueue` silently empty | One `lf_census()` wrapper replaces all FOUR call sites (`:435,:456,:496,:530`); `lf_locate` stays as `--slow-scan`; `cc-limited` rc 5 propagates (never `rows=""`) |
| `$LR/../bin/cc-limited` resolves to `scripts/bin` (absent); a new bin is a LIVE_ADD until the converger links it | Path is `$LR/../../bin/cc-limited` (verified: `LR=<root>/scripts/limit-recover`, `ls -d scripts/bin` ⇒ absent); W3 lands only after Wave 5's converge is CONFIRMED; `lf_census` falls back to `--slow-scan` with a stderr line when the binary is absent |
| The hook-side `launchctl kickstart` arms the recovery chain at ~60× today's rate with autofire on | The kick line lands **default OFF** behind a file sentinel (`~/.claude/autonomy/limited/.kick-on`), flipped in the recovery wave after P7 Part C observability (§ 8) |
| Poller pages latched by grepping `poller.log` | The poller's per-(account, cap, resetsAt) page goes through `page-damp.sh` (TTL 1800 s) as the RE-SURFACE only; the FIRST page is the hook's O_EXCL latch |
| `55 ms` was arithmetic, not a measurement; token cost unmeasured | § 4 DoD requires `/usr/bin/time -p` ×3 printed by the session, and a byte count of the default screen and `--json` for today's fixture |
| Beat maps every non-rate_limit StopFailure to `failed`, un-counting a genuinely mid-retry session | The beat is written for `error == rate_limit` ONLY; `lf_phantom_actives` (`lr-fleet.sh:307`) is KEPT this wave as the second subtraction (it cannot double-count: it subtracts only `prompt` beats) |
| Beat pane provenance (`session-beat.sh:55` reads `CC_PANE_ID`/`ITERM_SESSION_ID`, never `KITTY_WINDOW_ID`) disagrees with the marker's pane | `session-beat.sh:55` and `session-register.sh:127` both gain the `KITTY_WINDOW_ID` fallback (measured present where the other two are absent, § 1); the census renders both when they disagree |

---

## 3. The edits — file:line, LOC, per wave (anchors re-read at `a59b53e55`)

### W0 — the predicate SSOT (≤ 260 LOC, no call sites)

`scripts/limit-recover/lr_predicate.py` (new, ~140): body = P3's `lr_classify.py` (107 LOC, self-tested 490/490 rate_limit
events, 0 FP on 106 non-rate_limit, `quotaLimits.resetsAt` vs prose AGREE 408 / DISAGREE 0) shaped into P9's tiers —
**T0** `type=="assistant" ∧ isApiErrorMessage` mandatory; **T1** `error=="rate_limit"` (≡ `apiErrorStatus==429`, 490/490 both
ways) ⇒ limit, `quotaLimits.rateLimitType` {five_hour, seven_day}, `resetsAt` epoch; `authentication_failed`→auth_cliff,
`server_error`+529→server_529, `server_error`+no status→network, `oauth_org_not_allowed`→org_blocked; **T2** only when T1
leaves the cap unresolved: `re.search(r"You've (?:hit|reached) your (?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit")`
— session→five_hour, weekly→seven_day, Fable→`model_scoped:Fable`, monthly spend→monthly_spend, `<Other>`→`model_scoped:<Other>`;
prose reset `resets\s+(?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*\(([^)]+)\)` parsed in the NAMED zone.
Returns `{limit, kind, cap, resets_at, resets_source∈{quotaLimits,prose,none}, recoverable_by_waiting, model, raw_error, uuid, ts, entrypoint}`;
`recoverable_by_waiting=False` for `model_scoped:*` and `monthly_spend` (no reset anywhere in the record, P3 § 6).
Entry points: `classify_record(dict)`, `classify_text(str)` (T2 only — for the marker's `last_assistant_message`), `classify_tail(bytes)`.
`scripts/limit-recover/lr-predicate.sh` (new, ~25): `classify-text "<s>"`, `classify-record` (stdin), `classify-tail <path>` — one python fork, for bash callers only.
`tests/lr-predicate.bats` (new, ~90): F1–F10 (§ 4), **F9 FIRST**.

### W1 — the hook arm + the registry address (≤ 190 LOC)

`hooks/stop-failure-marker.sh` (131 lines, `set -uo pipefail` at `:37` — every idiom below is nounset-safe and bash-3.2-safe):

| anchor (verbatim today) | edit | Δ |
|---|---|---|
| `:41 TTL_MIN="${STOP_FAILURE_TTL_MIN:-1440}"` · `:42 CAP="${STOP_FAILURE_CAP:-500}"` | defaults `10080` and `5000` (§ 9 D3); bats `:108`/`:116` pin behaviour via the env seams, not the literals | 0 |
| `:85-87` `select((.config_dir \| sub("^~"; $h) \| sub("/$"; "")) == $c)` | add `or ((.aliases // []) \| index($b) != null)` with `--arg b "$(basename "$CFG" \| sed 's/^\.//')"` — `.claude` ⇒ `claude` ⇒ `next`; `:89` basename fallback stays | +2 |
| after `:89` | `PANE="${CC_PANE_ID:-${KITTY_WINDOW_ID:-}}"; [ -n "$PANE" ] \|\| { PANE="${ITERM_SESSION_ID:-}"; PANE="${PANE##*:}"; }; case "$PANE" in *[!A-Za-z0-9._-]*) PANE="" ;; esac` — the `session-register.sh:127` idiom (`:21` "bash 3.2-safe"); NEVER `${ITERM_SESSION_ID##*:}` on a possibly-unset var (measured: `unbound variable`, exit 127 under bash 5.3) | +3 |
| `:100` GC `find … -mmin "+$TTL_MIN" -delete` | also prune `"$LIM/.paged"` with the same TTL | +1 |
| **before `:115`** (the cap early-exit) — all new arms live ABOVE it | `LIM="${STOP_FAILURE_LIMITED_DIR:-$HOME/.claude/autonomy/limited}"`; `if [ "$ERR" = rate_limit ] && [ ! -e "$LIM/.off" ]; then` **(a) beat**: resolve `session-beat.sh` beside this hook (the `:47-52` ladder), `printf '%s' "$input" \| bash "$_sf_beat" limited >/dev/null 2>&1 \|\| true` (`session-beat.sh:58` takes the kind as `$1`, `:61-66` derives `who` only for prompt, `:98-107` carries `operatorT`/`seq`, `:40/:126` hard-caps at 3 s); **(b) page, once per cause**: `mkdir -p "$LIM/.paged"`; key `$(_sf_slug "$ACCOUNT")__$(_sf_slug "$(printf '%s' "$LAST" \| cut -c1-64)")` — derived from the PAYLOAD alone, so 30 concurrent hooks compute the same key with no tail read and no race; `( set -C; : > "$_pg" ) 2>/dev/null` ⇒ send + `log_idl fired page-sent`; else `[ -e "$_pg" ]` ⇒ `log_idl passed page-latched`; else (non-EEXIST) ⇒ **send anyway** + `log_idl abstained page-latch-unwritable-sent` (fail-open, the `page-damp.sh:23-25` posture). Sink: absolute `/usr/bin/osascript -e 'display notification "<acct>: <LAST[0:80]> — run: cc-limited" with title "⛔ limited: <acct>"'`, synchronous (30 ms measured, Dc G13), through `hooks/notify.sh:26-29`'s bounded ladder when sourceable. Kill: `[ -e "$LIM/.page-off" ]`; **(c) kick, opt-in**: `[ -e "$LIM/.kick-on" ] && /bin/launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1 \|\| true` — bare, absolute, never `-k`. `fi` | +24 |
| `:122-127` jq | `--arg pane "$PANE"` and `pane:$pane` in the object (readers ignore unknown keys; the marker is consumed by nothing today) | +2 |
| `:130` | `log_idl fired "marker-…" "$(jq -cn --arg p "$PANE" '{pane:$p}')"` — `idl-log.sh:117` takes the extra object | +1 |

Kill switches are FILE sentinels (`[ -e ]`, zero cost) because an env var cannot reach a pane that is already running — the
whole population during a mass cap (judge Dc-safety MAJOR 2). Death-path cost: baseline 0.09–0.14 s (Da § 1 #3) + beat ≤ 3 s
hard cap (measured ~10 ms) + osascript 30 ms on the ONE winner ⇒ ≤ 0.25 s; no python fork, no tail read, no `oi_origin_class`
(3.17 s full-file grep on a 230 MB transcript — judge Da-safety), no `agent_assignee_argv` (0.19–0.23 s — judge Da-latency).

`hooks/session-register.sh:127` `pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"` ⇒
`pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"; pane="${pane##*:}"` (+1). Receipt: `ps eww -o command= -p 41639`
⇒ `KITTY_WINDOW_ID=186`, no `ITERM_SESSION_ID`, no `CC_PANE_ID` — the lead registered pane 186 BY HAND today. The tenancy gate
at `:203-215` (`pid_is_strict_ancestor`, measured 2026-08-08) applies unchanged, so an inherited `KITTY_WINDOW_ID` in a nested
`claude -p` is refused exactly as an inherited `CC_PANE_ID` is. Same +1 at `hooks/session-beat.sh:55`.

Tests: `tests/stop-failure-marker.bats` +~90 (§ 4 SA1–SA9 + the `:149` footprint pin gains `beats/` and `.paged/`, the `:171`
CONTROL unchanged); `tests/spawn-presence.bats` +16; `tests/session-beat.bats` +10; `tests/session-registry.bats` +12.

### W2a — `bin/cc-limited` core (≤ 290 LOC, `#!/usr/bin/python3`, stdlib, imports `lr_predicate` in-process)

Resolver, nine steps, every `open`/`stat` wrapped for `FileNotFoundError` (a transplant renames files mid-scan, measured P2):

```
0 accounts.json → name map over config_dir ∪ aliases ∪ the registry's basename spelling; roots = readlink -f dedupe (.claude-next → .claude)
1 ENUMERATE  ~/.claude/autonomy/stop-failure/*__*.jsonl (ALL causes) ∪ ~/.reso/limit-recover/parked/*.json
             skip sid=="?" (COUNT it); group by sid; MAX(ts) row wins; fires=n; accts_at_death=set; acct_death=name[basename(config_dir)] — NEVER the filename
             kind/cap = lr_predicate.classify_text(last_assistant_message) ∘ error field
2 REGISTRY   ~/.claude/cc-registry/[0-9]*.json ∩ ONE `TZ=UTC LC_ALL=C ps -eo pid=,lstart=` → live rows by sid AND by pane; acct_now
3 PANE OWNER registry/<marker.pane>.json: .session_id==sid ⇒ IN-PLACE · != ⇒ PANE-REUSED(by sid8, since startedAt) · absent ⇒ none
4 COPIES     slug-directed <root>/projects/<slug>/<sid>.jsonl* over the roots (5.4 ms/14 sids); on a slug miss ONLY, the full index (121 ms)
             evidence = UNION over copies: newest real assistant turn ts; newest api-error record (uuid, quotaLimits); per-copy assistant-record count
             preferred tp = copy under acct_now's root when a live row exists → marker.transcript_path if it exists → the copy holding the death record
5 BLOCKED    ⇔ no copy holds a real assistant turn with ts > death.ts;  resets_at = quotaLimits.resetsAt (epoch) else prose (SSOT); title = last "aiTitle" in the preferred tail
6 PROCS      |{live registry pids for sid} ∪ {lr_resume_procs leaves}|  (cardinality — lr-lib.sh:233-255's leaf filter, never its rc)
7 CLAIMS     locks/<sid>.lock {to,ts,pid} ∪ newest fleet/*/results.tsv row ∪ results/<sid>.json{rc,ts,log} ∪ requests/<sid>.json ∪ faults/<sid>.json
8 CWD        os.path.isdir(cwd) AT THIS INSTANT
9 STATE      first matching row below; group = acct_now if moved else acct_death; header key = (account, cap, resets_at)
```

State table (MECE, first match wins; the TSV column is the legacy `lf_locate` disposition it maps to for `--tsv`):

| state | predicate | `--tsv` disp | next action it names |
|---|---|---|---|
| UNADDRESSABLE | sid == `?` | (footer count) | — |
| TEAMMATE | `"agentName"` in head-8 KB of the preferred copy | TEAMMATE | lead-owned (poller `:752`) |
| RE-ENGAGED | a real assistant turn after death.ts in any copy | (settled; `--all`) | none |
| FAULT / CLAIMED-NOT-LIVE | blocked ∧ claim older than `CC_LIMITED_CLAIM_GRACE_S` (120) ∧ no live row for sid on the claimed account ∧ procs == 0 — or `faults/<sid>.json` present | NO-PANE + note | named with claimant · ts · lock/log path |
| AWAITING-ENGAGE | blocked ∧ live row ∧ acct_now ≠ acct_death | TRANSPLANTED→<acct_now> | one prompt on the successor |
| DUPLICATE | blocked ∧ procs > 1 | DUPLICATE | `--duplicates` |
| RESUMING | blocked ∧ no registry row ∧ exactly one resume leaf | RESUMING | wait (D7 `:324`) |
| IDLE-AFTER-ERROR | kind == network ∧ live row | IDLE-AFTER-ERROR | resume in place, never a transplant (`:236-243`) |
| RESET-PASSED/LIVE | blocked ∧ live ∧ resets_at ≤ now | RECOVERABLE | nudge in place (poller `:928`) |
| RECOVERABLE [(stub)] | blocked ∧ live ∧ IN-PLACE ∧ procs == 1 ∧ same account; `(stub)` when the preferred copy has 0 assistant records | RECOVERABLE | `--one` |
| PANE-REUSED | blocked ∧ pane owner ≠ sid ∧ no live row for sid | NO-PANE | spawn-at-reset; the old pane is NOT a target |
| NO-PANE | blocked ∧ no live process ∧ no claim ∧ cwd exists | NO-PANE | spawn-at-reset / `--recover` |
| CWD-GONE | as NO-PANE, cwd missing at read | CWD-GONE | recreate or drop (D8 `:394`) |
| CARCASS | only `.handed-off` copies, nothing live, no claim | (settled) | history |
| NO-TRANSCRIPT | no copy anywhere | (footer, named) | — |

Modes: default per-account grouped screen (actionable rows; settled counted) · `--all` · `--json` · `--tsv` (the 11-field
`sid cfg acct pane pid cwd tier disp kind kinds err_age` row, byte-compatible) · `--account A` · `--since 24h` (default; seven_day
rows always shown for their whole window) · `--assert-clean` · `--kitty` (W2c) · `--deep` (execs `lr-fleet --slow-scan` for the
`-p`/sdk-cli deaths no marker sees; the footer prints `(-p sessions: run --deep)` on every default screen).

Exit codes (composable — severity and work-present are NOT multiplexed): **0** rendered · **1** `--assert-clean`/`--reaper`
only: actionable rows / faults exist · **2** usage · **3** ambiguous resolver query (every candidate printed) · **4** no match ·
**5** instrument unreadable (registry dir / marker dir / accounts.json / `ps`) — stdout EMPTY, stderr names it · **6** degraded
(rows printed; footer names: kitten failed, a marker file at CAP, IDL abstains in window).

Header per (account, cap, resets_at): `next3   five_hour · resets 21:30Z (in 13m)   5 need attention · 2 faults · 3 settled`.
Row: `STATE  #PANE  SID8  ×FIRES  ERR  TITLE|cwd  ← reason`. Every timestamp from the record's own field, never mtime.

### W2b — `tests/cc-limited.bats` (≤ 240 LOC) — § 4 rows 1–15 + CONTROL C1/C2

### W2c — reaper, faults, resolver, titles (≤ 200 LOC)

`--reaper`: prints CLAIMED-NOT-LIVE rows one per line with claimant · ts · age · lock/log path; `--reaper --persist` writes
`~/.reso/limit-recover/faults/<sid>.json` `{sid, first_seen, claim:{kind, by, ts, path}, log}` on FIRST sighting only
(O_EXCL); `cc-limited ack <sid> --why "<text>"` renames it `<sid>.acked.json` (the only exit). The poller tick runs
`--reaper --persist` (W3) so the fault survives the marker TTL and a Fable/monthly row (never parked) still gets named.
Grace: `CC_LIMITED_CLAIM_GRACE_S=120` (above `handoff-fire.sh:6811-6815`'s 90 s dead-wait; a seam — § 8 moves it).
Resolver `cc-limited <query>`: exact pane id or sid prefix ⇒ 1 row; else case-insensitive substring over title then cwd; 1 hit
⇒ row; 0 ⇒ exit 4; ≥ 2 ⇒ exit 3 with `pane · sid8 · account · title` per candidate (today two panes on different accounts share
the title "limit-recover optimization", P10). `--kitty`: ONE unmatched `kitten @ ls` via the absolute binary + `--to`, bounded 2 s,
a truncated payload ⇒ titles `?` + exit 6, never a partial parse (the 10.06 s corrupt-payload case, U07 § 5).

### W3 — consumers (≤ 200 LOC)

`scripts/limit-recover/lr-fleet.sh` (581 lines): new `lf_census()` — `CC_LIMITED="${CC_LIMITED:-$LR/../../bin/cc-limited}"`;
if executable and `LF_SLOW_SCAN != 1` ⇒ `"$CC_LIMITED" --tsv`, propagating rc 5/6 (stderr line + `return 5`, so `rows` is
NEVER silently empty); else `lf_locate | lf_dedup_mirror` with one stderr line naming the fallback. Replace the four call sites
`:435` (locate; `--json` ⇒ `exec "$CC_LIMITED" --json`), `:456` (recover), `:496` (`--one`: `"$CC_LIMITED" --sid "$SID" --tsv`
first, `lf_census` only on rc 4), `:530` (enqueue). `:217-218` `if [ "$n" -gt 1 ] || lr_resume_procs "$sid"` ⇒ cardinality of
`{registry live pids} ∪ {resume leaves} | sort -u` (also fixes `--slow-scan`). `:534` echo drops `-k`. `lf_phantom_actives`
(`:307`) KEPT. `tests/lr-fleet.bats`: every `locate:` (`:55-96`), `D7:` (`:244-350`) and `D8:` (`:394`) case runs through
BOTH `lf_census` and `--slow-scan` and diffs byte-for-byte (+25).

`scripts/limit-recover/lr-reset-poller.sh` (1033 lines): `:185` `exit 0` ⇒ `log "TICK-SKIP held by pid $_hp"` first (+1); one
`log "TICK start"` after the lock (+1); `:293-296` — `[ -f "$_CC_AM" ] && source "$_CC_AM" && declare -F cc_acct_name_for_dir_basename >/dev/null 2>&1 && break`,
then `log "FATAL account map unusable"; exit 1` after the loop (+3); `scripts/gen-account-map.sh:117` `> "$OUT"` ⇒ `> "$OUT.tmp" && mv -f` (+2);
§ 1 DETECT (`:740-795`): ONE `cc-limited --json` per tick (all accounts — never per account, the judge's memoization point) ⇒
park RECOVERABLE / NO-PANE / PANE-REUSED / RESET-PASSED rows with `recoverable_by_waiting` in the `:788` record shape; TEAMMATE
⇒ `teammate-skip/<sid>` as `:752-757`; `fable`/`monthly_spend` ⇒ `log "LIMITED-NOWAIT …"`; the `find -H … -mmin` walk (`:795`)
stays as backstop for one release; `cc-limited --reaper --persist` once per tick, each row logged `CLAIMED-NOT-LIVE <sid> …`;
the re-surface page per (account, cap, resetsAt) through `page-damp.sh damp_should_send "lr-limited" "<acct>:<cap>:<epoch>:<N>"`
(TTL 1800 s) via the poller's existing `osascript` sink (`:263`, `:592` shape) — never a grep over `poller.log`.
`commands/recover.md:101` and `commands/limit-recover.md:441` point at `cc-limited --json`; `:441` drops `-k`.

### W4 — the twelve predicate copies, blast radius strictly decreasing (≤ 150 LOC)

| step | site (verbatim anchor) | change |
|---|---|---|
| 1 | `lr-audit.py:75-79 LIMIT_PREFIXES`, `:80 SERVER_529 = "API Error: Server is temporarily limiting requests"` (0/924 events), `:244-248 classify_limit_text` (`startswith`), `:210-212` prose-only reset | delegate to `lr_predicate.classify_record`; delete `SERVER_529`; `quotaLimits.resetsAt` first. The ONLY `startswith`→`search` behaviour change — lands alone |
| 2 | `lr-reset-poller.sh:746 grep -E "You've hit your (session\|weekly) limit"`, `:771 kind in ('session','weekly','fable')` (a producer that cannot emit `fable`), `:566 SPEND_RE` | `:746` ⇒ `"error":"rate_limit"` ∧ envelope via the shim; `:771` ⇒ "kind has a reset"; `:566` ⇒ shim |
| 3 | `lr-lib.sh:156 "limit" if "You've hit your" in txt else "other"` (inside `lr_last_api_error`, `:129`) and `:55` (tier) | kind via the shim. **Output stays EXACTLY four tab fields** — `hooks/net-recover-arm.sh:195 _ts="${_rec##*<TAB>}"` takes the LAST field and feeds `_turn_ended_after` (`:164`, `:175` string compare); a column append measured `_ts=[cli]` ⇒ the asyncRewake never fires (judge Da-latency FATAL 2). `tests/lr-lib.bats` gains "prints exactly 4 fields"; `tests/net-recover-arm.bats` (9 tests) must stay green. `hooks/recover-inject.sh:98-101` inherits: a Fable cap stops being "NOT a quota message" |
| 4 | `bin/cc-classify:312` (`→ :816` never-reap), `scripts/desk-invariant.sh:156 cap_stunned` | UNION the shim's verdict with the existing regex — a veto must never LOSE coverage |
| 5 | `scripts/handoff-fire.sh:9236`, `scripts/cloud-ceiling-probe.sh:212`, `scripts/lib/cloud-create.sh:174` | untouched (CLI-stdout domain) + a comment naming the SSOT; a lint refuses any NEW transcript-JSONL limit regex outside the module |
| 6 | `lr-fleet.sh:108 LIMIT_RE`, `:122 NET_RE`, `:143 lf_kinds_of` | LAST, and only if the both-paths parity diff stays empty — they are the `--slow-scan` path now (100 % recall, 209/209) |

`scripts/limit-reset-safety-gate.sh:114-121`'s "LR-blind — DECLARED" block becomes a proven row once F1 lands (its own OBLIGATION).

### W5 — statusline chip (≤ 20 LOC, lead)

`statusline.sh:486 echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"` ⇒ insert before it:
`_id_pane="${KITTY_WINDOW_ID:-}"; [ -n "$_id_pane" ] || { _id_pane="${ITERM_SESSION_ID:-}"; _id_pane="${_id_pane##*:}"; }; _id_sid8="${PAY_SID:0:8}"; ID_SEG=""; { [ -n "$_id_pane" ] || [ -n "$_id_sid8" ]; } && ID_SEG="${GRAY}#${_id_pane:-?} ${_id_sid8:-?} · ${RESET}"`
and emit `${GLYPH_PREFIX}${ID_SEG}${PCT_SEG}…` (+5). `PAY_SID` is already parsed at `:75-88` — 0 forks (P6: −0.2 ms CPU/render,
+16 cols; right-edge truncation keeps the chip at 30 cols). `tests/statusline-identity.bats` +10. NOT set: `statusLine.refreshInterval`
(1 s × 16 panes × 61 ms = one core). Converge: `~/.claude/statusline.sh` is a COPY (`ls -la` ⇒ no symlink; `install.sh:960 copy_file`)
repaired ONLY on `deploy-live.sh`'s advance path (`:1770`) — Wave 5 confirms the advance or `deploy-parity-assert.sh` reports COPYSTALE.

### LOC summary

| wave | runtime | tests | total |
|---|---|---|---|
| W0 | +165 | +90 | 255 |
| W1 | +36 | +128 | 164 |
| W2a | +290 | 0 | 290 |
| W2b | 0 | +240 | 240 |
| W2c | +120 | +70 | 190 |
| W3 | +75 / −4 | +25 (+docs 10) | 114 |
| W4 | +40 / −24 | +45 | 109 |
| W5 | +5 | +10 | 15 |
| **Σ** | **≈ +730 / −28** | **≈ +608** | ≈ 1,380 |

---

## 4. Per-wave DoD and the red-proof rows (fixtures named from real sids; 8-char prefix kept, tail zeroed)

**DoD shape for every wave:** `bats <suite>` green AND printed by the session; each new row was run once against pristine
`a59b53e55` and its RED output pasted into the suite's `# RED-PROOF` footer (`tests/spawn-presence.bats:11-15` records why);
every mutant CONTROL turns exactly its named case red; gate = `bats tests/` for the touched suites + `shellcheck` on touched
`.sh` (the ship gate runs it without `-x`, `stop-failure-marker.sh:55`).

| wave | DoD (proven by) | red-proof rows |
|---|---|---|
| **W0** | `bats tests/lr-predicate.bats` 10/10; `python3 -m lr_predicate --selftest` prints `490/490 rate_limit, 0 FP/106` over P3's `recs.dedup.json` | **F9 FIRST** skill-listing text with BOTH spellings and NO envelope ⇒ not a limit · F1 `fable-park` the verbatim 2.1.260 record (`~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/2d71c6d8-….jsonl:1252`: `quotaLimits` ABSENT, `errorDetails` present) ⇒ `cap=model_scoped:Fable, resets_at=None, recoverable_by_waiting=False` · F2 `fable-no-reap` (cc-classify answers `rate-limited` after W4) · F3 `You've hit your Sonnet limit` ⇒ `model_scoped:Sonnet` (RED even against `LIMIT_RE`) · F4 quotaLimits-only record, no prose ⇒ epoch reset · F5 ZoneInfo forced None ⇒ epoch still resolves · F6 spend packet · F7 `API Error: 529 Overloaded` ⇒ server_529, NOT limit · F8 ENOTFOUND ⇒ network · F10 `Not logged in · Please run /login` ⇒ auth_cliff |
| **W1** | `bats tests/stop-failure-marker.bats tests/spawn-presence.bats tests/session-beat.bats tests/session-registry.bats` green; `/usr/bin/time -p bash hooks/stop-failure-marker.sh < fixture` ×3 printed, each ≤ 0.30 s with the beat writer stubbed at its 3 s cap | SA1 `d02d8feb` payload, `KITTY_WINDOW_ID=112` ⇒ marker row has `"pane":"112"` · SA2 `ITERM_SESSION_ID=w0t0p0:112`, no KITTY ⇒ `"112"`; no env at all ⇒ `""`, exit 0, EMPTY stdout under `/opt/homebrew/bin/bash` (bash 5.3, the nounset case) · SA3 `CLAUDE_CONFIG_DIR=$HOME/.claude` with accounts fixture `next.aliases=["claude"]` ⇒ file `rate_limit__next.jsonl`, never `rate_limit__.claude.jsonl` (RED today: `authentication_failed__.claude.jsonl`, 5 rows) · SA4 a `rate_limit` death writes ONE beat `kind=limited`, `who=auto`, prior `operatorT` preserved; an `authentication_failed` death writes NO beat · SA5 the beat is written even when the marker file is at CAP (arm above `:115`) · SA6 30 concurrent deaths of ONE cause ⇒ exactly ONE `osascript` argv in the stub log; a second account ⇒ a second; same account with a NEW `last_assistant_message` ⇒ a third; CONTROL: a sid-keyed mutant pages 30× · SA7 `.paged/` unwritable ⇒ page STILL sent, IDL `abstained page-latch-unwritable-sent` · SA8 `.off`/`.page-off` sentinels ⇒ zero beat / zero page; `.kick-on` absent ⇒ the `launchctl` stub is NEVER invoked; present ⇒ argv `kickstart gui/<uid>/com.reso.lr-reset-poller` with NO `-k` · SA9 the `:149` footprint pin = marker + IDL + beat + `.paged/` and nothing else · spawn-presence: `kind=limited` NOT counted; `kind=zzz` NOT counted (the contract) · session-registry: `KITTY_WINDOW_ID=186` alone ⇒ row `186.json`; none of the three ⇒ no row (existing `:127-132`) |
| **W2a** | `bin/cc-limited --json` over the § 5 fixture renders the expected states; `/usr/bin/time -p bin/cc-limited` ×3 printed ≤ 0.30 s at load ≤ 20; byte counts of the default screen and `--json` printed | (rows live in W2b) |
| **W2b** | `bats tests/cc-limited.bats` 15/15 + 2 CONTROLs | 1 `07e30aeb`: marker tp → a 3-record stub (queue-operation ×2, system; 0 assistant) under tertiary; 1,157,520-byte copy with the death record under secondary; registry 147 live on tertiary ⇒ `RECOVERABLE (stub) #147`, `tp` = the tertiary copy, `copies=3` (RED: proto drops it; Db's size rule names the secondary snapshot as tp) · 2 `98f02458`: lock `{to:.claude-secondary, ts:now−1260, pid:32971}`, blocked secondary copy, no registry row, `CC_LIMITED_PS` without 32971 ⇒ FAULT/CLAIMED-NOT-LIVE naming `pid 32971` + the lock path + `21m` (RED: proto `MOVED`, `--locate` blind) · 3 same with `ts:now−60` ⇒ NOT named (grace) · 4 `65186f1f`: marker under `rate_limit__next3`; registry 121 `account:claude-secondary, startedAt 2026-09-19T20:48:39Z > death 19:58:34Z`, live; secondary copy's last record a real turn ⇒ RE-ENGAGED, grouped under next2, never queued · **C1 CONTROL** a mutant grouping by marker FILENAME turns row 4 red · 5 `09e64dcb`: rows under next4 (17:01:34, 17:11:29) AND next3 (19:53:38); registry `111.json` = `{session_id: cb29ae36…, account: claude-secondary, startedAt 2026-09-19T22:36:06Z}` (measured this unit — the pane WAS reused) ⇒ ONE row, `fires=3`, `accts=[next4,next3]`, state PANE-REUSED naming `cb29ae36 since 22:36Z`, `--tsv` disp `NO-PANE` · 6 one live registry row + one `--resume` leaf ⇒ RECOVERABLE not DUPLICATE (`lr-fleet.sh:217`) · 7 a `session_id:"?"` row ⇒ footer `1 unaddressable`, exit 0 · 8 F1 Fable text + live pane ⇒ listed, `cap=model_scoped:Fable`, `resets —`, `recoverable_by_waiting:false` · 9 NO-PANE row whose cwd is deleted between fixture and call ⇒ CWD-GONE · 10 `CC_REGISTRY_DIR` missing ⇒ exit 5, stdout EMPTY, stderr names `cc-registry` · 11 a marker file with `CAP` lines ⇒ rows printed + footer `enumerator DEGRADED: rate_limit__next4.jsonl at cap` + exit 6; an IDL row `abstained no-jq` inside the window ⇒ the same · 12 `server_error__next3.jsonl` ENOTFOUND row + live pane ⇒ IDLE-AFTER-ERROR, `--tsv` kind `network` (D7 `:244`) · 13 blocked ∧ no registry row ∧ one resume leaf ⇒ RESUMING with that pid (D7 `:324`) · 14 PARITY: every `locate:`/`D7:`/`D8:` fixture of `tests/lr-fleet.bats` through `cc-limited --tsv` equals `lf_locate \| lf_dedup_mirror` byte-for-byte · 15 `--since 24h` hides a 125 h-old five_hour row and SHOWS a 3-day-old seven_day row whose `resets_at > now` · **C2 CONTROL** a mutant that stores `alive` in a file and re-reads it turns row 1's second call red after the ps stub changes |
| **W2c** | `bats tests/cc-limited-reaper.bats` green | R1 `4bc1159f` lock `{to:.claude-secondary, ts:2026-09-19T20:59:34Z, pid:44616}` + no live process ⇒ `--reaper` one line; `--reaper --persist` creates `faults/4bc1159f-….json` once (second run: unchanged mtime); `ack --why` renames it; the marker aged past TTL ⇒ the fault STILL renders (RED: Db's derived-only FAULT vanishes) · R2 lock younger than 120 s ⇒ nothing · R3 a live registry row for the sid on the claimed account ⇒ nothing (a true claim clears itself) · R4 `--keyword limit-recover` over two panes on two accounts with one title ⇒ exit 3, both printed · R5 `--sid 07e3` ⇒ 1 row; `--sid zz` ⇒ exit 4 · R6 `--kitty` with a stub emitting a truncated payload ⇒ titles `?`, rows printed, exit 6 |
| **W3** | `bats tests/lr-fleet.bats` 33+/33+ incl. the both-paths diff; a poller dry tick (bats-fixtured, `LR_POLLER_AUTOFIRE=0`) prints `TICK start` and, on a held lock, `TICK-SKIP held by pid` | fleet: `lf_census` returns rc 5 and `--recover` prints the stderr line and exits non-zero with `census.tsv` ABSENT (never empty) when `CC_LIMITED` points at a script that exits 5 · `--enqueue` writes one request per RECOVERABLE row and its kickstart line has no `-k` (`:186` case updated) · `--one 07e30aeb` never runs the census · poller: account-map fixture with the function undefined ⇒ `FATAL account map unusable`, exit 1 (RED: today's unguarded `break`) · a `fable` row ⇒ `LIMITED-NOWAIT`, no `parked/` file · CLAIMED-NOT-LIVE ⇒ `faults/` written + `poller.log` line |
| **W4** | `bats tests/lr-predicate.bats tests/lr-lib.bats tests/net-recover-arm.bats tests/lr-fleet.bats` green; `grep -c fable scripts/limit-recover/lr-audit.py` ≥ 1; the lint passes on the tree and FAILS on a planted regex | lr-audit: the F1 record ⇒ `kind` carries a reset-less limit, parks nowhere, is LISTED (RED today: `other_api_error`) · lr-lib: `lr_last_api_error` on the F1 tail prints `limit` in field 3 and EXACTLY 4 fields; `net-recover-arm.bats` test 7 still fires · cc-classify: F2 tail ⇒ `rate-limited`; the existing regex's 190/209 still pass (UNION) |
| **W5** | `bats tests/statusline-identity.bats`; 30 renders under `getrusage` printed, CPU delta within ±3 ms of baseline (P6 method); `deploy-live.sh` output shows an ADVANCE and `deploy-parity-assert.sh` shows no COPYSTALE | chip renders `#121 65186f1f · ` left of the `%` with `KITTY_WINDOW_ID=121`; `ITERM_SESSION_ID=w0t0p0:121` alone ⇒ `#121`; neither ⇒ `#? <sid8>`; ANSI-stripped width at 30 cols still starts with the chip |

---

## 5. Acceptance — the 5-session drill (today's next3 fleet, frozen as fixtures)

Fixture `tests/fixtures/lr-2026-09-19/` = verbatim copies (uuids, timestamps, `quotaLimits` kept; bodies truncated to 3–6
records; sids keep their real 8-char prefix, tail zeroed) of: the 9 marker rows below; registry rows `111.json` (sid `cb29ae36`,
`claude-secondary`, pid 12341, startedAt 1789857366000 = 22:36:06Z), `121.json` (`65186f1f`, `claude-secondary`, pid 59379,
1789850919000 = 20:48:39Z), `147.json` (`07e30aeb`, `claude-tertiary`, pid 84167, live — the P8/Db 21:14Z state); locks for
`98f02458` (`to .claude-secondary, ts 2026-09-19T20:53:26Z, pid 32971`) and `4bc1159f` (`ts 2026-09-19T20:59:34Z, pid 44616`);
transcript tails: `07e30aeb` tertiary 3-record stub + secondary copy ending on the death record; `98f02458` secondary copy
ending on the death record; `65186f1f` secondary copy ending on a real turn at > 19:58:34Z; `09e64dcb` tertiary copy ending
on the death record; `CC_LIMITED_PS` = the four live pids with matching lstart; `LR_NOW` = 2026-09-19T21:14:00Z.

Marker rows (measured this unit, `jq` over `rate_limit__next3.jsonl` + `rate_limit__next4.jsonl`):

```
17:01:34Z 09e64dcb next4 claude-infrastructure     19:57:41Z 65186f1f next3 subagent-lifecycle-w0
17:11:29Z 09e64dcb next4 claude-infrastructure     19:57:43Z 98f02458 next3 wt-pool-2
19:52:33Z 98f02458 next3 wt-pool-2                 19:58:34Z 65186f1f next3 subagent-lifecycle-w0
19:53:38Z 09e64dcb next3 claude-infrastructure     20:00:44Z 4bc1159f next3 claude-infrastructure
                                                   20:29:28Z 07e30aeb next3 wt-cc-143039-68221
```

Expected screen (`bin/cc-limited` with the fixture seams; every number below is fixed by the fixture):

```
next3   five_hour · resets 21:30:00Z (in 16m)                         2 need attention · 2 faults · 1 settled
  RECOVERABLE (stub)   #147  07e30aeb  ×1  err 20:29:28Z  wt-cc-143039-68221      ← preferred copy 0 assistant records; death record in copy 2/3
  PANE-REUSED          #111  09e64dcb  ×3  err 19:53:38Z  claude-infrastructure   ← pane 111 held by cb29ae36 since 22:36:06Z (accts next4,next3)
  FAULT CLAIMED-NOT-LIVE     98f02458  ×2  err 19:57:43Z  wt-pool-2               ← transplant→next2 claimed 20:53:26Z by pid 32971 (locks/98f02458-….lock); no live process, 20m34s
  FAULT CLAIMED-NOT-LIVE     4bc1159f  ×1  err 20:00:44Z  claude-infrastructure   ← transplant→next2 claimed 20:59:34Z by pid 44616 (locks/4bc1159f-….lock); no live process, 14m26s
settled: 65186f1f #121 RE-ENGAGED (moved next3→next2, registry 20:48:39Z > death 19:58:34Z)
5 sessions · 9 marker rows · 0 unaddressable · enumerator ok (0 abstains; 12/5000, 36/5000) · (-p sessions: run --deep) · exit 0
```

Expected numbers: **9 rows → 5 sids**; `--assert-clean` exits **1**; `--reaper` prints **2** lines and exits 1; `--reaper --persist`
creates **2** files in `faults/` and a second run creates **0**; `--tsv` yields **4** actionable rows of **11** fields with
dispositions `RECOVERABLE NO-PANE NO-PANE NO-PANE` (the settled row absent from `--tsv`, as `lf_locate`'s tail rule drops it
today); `09e64dcb` renders ONCE with `fires=3`; `65186f1f` is grouped under **next2**, and the C1 filename-grouping mutant puts
it under next3 (RED). Wall: `/usr/bin/time -p bin/cc-limited` ×3 each ≤ **0.30 s** (shape measured 0.20–0.24 s at load 50,
judge Db-latency; 0.147–0.163 s internal, Dc G16); default screen ≤ **1,200 bytes**, `--json` ≤ **6 KB** for 5 sids (Db's
22-sid screen measured 2,504 B, judge Db-latency). Then the LIVE run: `bin/cc-limited` against the real stores at Wave 5 must
render the same five sids in states consistent with the live registry at that instant (the operator's screen), and
`cc-limited 147`, `cc-limited limit-recover` (exit 3, two candidates) and `cc-limited --reaper` are run and printed.

---

## 6. Operator-owned steps (c10) — separated, minimized

**Required for detection, identification and surfacing to work: NONE.** The hook rides its existing StopFailure registration
(all 5 config dirs, `timeout 10`, P1/Da #1); `accounts.json` needs no edit (aliases already resolve `.claude → next`);
`settings.json` is untouched; kill switches are files, not settings.

| step | when | command (operator pastes; the agent never runs these) |
|---|---|---|
| plist QueueDirectories + ThrottleInterval backstop for the request lane | ONLY in the recovery wave, after W3's three observability lines are live and `.kick-on` is being flipped | `plutil -insert QueueDirectories -json '["/Users/chrisren/.reso/limit-recover/requests"]' ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist && plutil -insert ThrottleInterval -integer 5 ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist && launchctl bootout gui/$(id -u)/com.reso.lr-reset-poller && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` — QueueDirectories, NEVER WatchPaths (`man launchd.plist:330-338`); keep `StartInterval 600`; mirror into the SSOT `scripts/limit-recover/com.reso.lr-reset-poller.plist` |

Agent-runnable but must be CONFIRMED, not assumed (Wave 5): `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` then
`bash scripts/deploy-parity-assert.sh` — the three new files (`bin/cc-limited`, `lr_predicate.py`, `lr-predicate.sh`) are
LIVE_ADDS (per-file symlink farm: `~/.claude/bin/cc-custody → <repo>/bin/cc-custody`, `~/.claude/scripts/limit-recover/lr-fleet.sh → <repo>/…`,
measured this unit) and `statusline.sh` is a COPY; W3 does not land until this prints an advance.

---

## 7. DROPPED — and why (class)

| item | why | class |
|---|---|---|
| Da's `state/<sid>.json` store, `lr-state` CLI (220 LOC), `backfill`, `.done` GC, `events[]` | five fatals intrinsic to a stored state machine: arm below the cap exit; every re-cap wipes `claim` (8/10 multi-fire sids re-cap: 12e163a9 4 uuids in 4 s); the sha latch freezes `cap=unknown` forever; no serialization on one document across 6 writers; stale `.done` deletes a live document. Its one irreplaceable idea (claim + reaper) survives as `faults/` | refuted by measurement (judges Da-correctness, Da-safety) |
| Dc's terminal mirror: `cc_limited`/`cc_sid` user_vars, per-cap tab colour, `⛔` title, `--mirror-sync`, `cc_husk` | per-TAB colour over 4–5 splits; no clear path on `/clear`-recycle (tab stays red); a subagent's StopFailure carries the LEAD's `KITTY_WINDOW_ID` and paints the lead's live pane; ~18–20 forks on the death path; every kill switch unreachable. The statusline chip + one notification + `cc-limited` answer "which panes" with none of that | refuted (judge Dc-correctness 4 fatals, Dc-safety) |
| Dc's SessionStart `cc_sid` user_var as a registry-independent index | the `KITTY_WINDOW_ID` fallback in `session-register.sh:127` closes the measured no-row class at 1 line; revisit only if registry coverage < 100 % of kitty-hosted sessions after W1 | not-yet-true (re-measure after W1) |
| Dc's burn chip (`5h 84%`) | `rate_limits` presence in the live payload on Max is UNMEASURED and the capture needs a settings edit | not-yet-true (needs an operator-owned capture) |
| `cap` computed in the hook via a python fork | the census re-classifies; a fork on the death path buys nothing | bounded scope |
| `oi_origin_class`, `agent_assignee_argv`, tier read in the hook | 3.17 s full-file grep on a 230 MB transcript; 0.19–0.23 s ancestry walk; 79 ms python — none needed for detection | refuted (judge Da-safety/latency) |
| A fifth `accounts.json` row for `~/.claude` | alias-aware `select()` is one line with zero blast radius; a new row enters `bin/claude-accounts`, `handoff-fire.sh`, `gen-account-map.sh` and the router's spend order — unmeasured | bounded scope |
| `hooks/operator-readout.sh` `◆` line from `cc-limited --json` | a census per Stop across the fleet; the notification and `cc-limited` cover the surface; add later behind a 60 s cache if wanted | bounded scope (F4) |
| Retiring `lf_phantom_actives` (`lr-fleet.sh:307`) | a stamped `limited` beat is write-once until the next prompt beat; the shim re-evaluates at every probe and cannot double-subtract; keep both for one measured week | not-yet-true |
| `kitten @ ls` on the default hot path | 10.06 s hang observed once on a corrupt payload (U07 § 5); opt-in `--kitty`, bounded 2 s | refuted |
| `session-index.db` as a title source | 0/8 of today's limited sids have a `first_prompt`; `summary` empty on all 6,682 rows | refuted (P10 R7) |
| `statusLine.refreshInterval` | 1 s × 16 panes × 61 ms/render = one core, permanently | refuted (P6) |
| Column-append on `lr_last_api_error` | breaks `net-recover-arm.sh:195` (`_ts=[cli]`) and migration 0030's guard would still register it | refuted (judge Da-latency FATAL 2) |
| WatchPaths on the poller plist | "entirely possible for modifications to be missed" — a missed limit death is a lost recovery with no retry | refuted (`man launchd.plist:330-338`) |
| Re-keying the marker file so Fable and five_hour separate | the file stays cause-keyed by design; the census reads the cap from `last_assistant_message` through the SSOT | bounded scope |
| Anything that types into a pane, drains `requests/`, ranks a target, or closes a husk | recovery chain — § 8 | out of scope (frozen) |

---

## 8. Recovery-chain findings carried as LATER waves (one line each; NOT designed here)

| later wave | finding (unit) | the dependency this plan leaves at the boundary |
|---|---|---|
| R1 capacity gate | `capacity-admit.sh:782-792` ceiling 8 + load term (U05); `lr-fire-resume.sh:322` second gate exit 9 = today's 4 PARTIALs (U03) | W1's beat takes ACTIVE 10→7 so the refusal becomes an admission — land R1 knowing the arithmetic moved |
| R2 kick + request lane | flip `.kick-on`; plist QueueDirectories/ThrottleInterval (P7 Part B); `--enqueue` writes one request per row and the drain runs ~45 s serial `--one`s inside one lock (U06 gap 2) | W3's TICK-SKIP/heartbeat/account-map guard must be live FIRST (P7 Part C) |
| R3 husk closure | `successor_pin` (`handoff-fire.sh:3435`) refuses an expect-rooted successor whose pty is a child of the pane's tty (lead-findings § Husk retirement); `cc-teardown` DEFERs a dirty/unpushed pane | `faults/<sid>.json` + `--reaper` NAME the husk; nothing here closes it |
| R4 in-place recycle transport | `lr-fire-resume` → expect → cc-close-attrib shape is non-recyclable; kitty transport library (U02, U03, U04, U08) | the census's PANE-REUSED / RESUMING states are the oracle a transport can read back |
| R5 engagement oracle | `handoff-fire.sh:6811/6815` 90 s dead-waits, `:6879` unattributed verdict (U04); poller NOT-ENGAGED `:373` | `CC_LIMITED_CLAIM_GRACE_S` (120 s) is the seam that moves when the dead-wait is shortened |
| R6 ranker / target | `claude-accounts --rank` vs lr-fleet's dry run disagree; reasons discarded at `lr-fleet.sh:301` (U13); `claude-accounts` not on PATH in an expect-launched session (lead-findings 3) | `cc-limited --json` carries `acct_now`/`acct_death`; the ranker consumes it |
| R7 write-offs | `lr-select` `MAX_PER_WT=1` LISTED write-off (U06 § 3); poller LISTED `:958-959` | rendered as FAULT with a note once R7 calls `--reaper --persist` |
| R8 ingest | `lr-audit` classifies a SETTLED run's dead slots `UNSETTLED-INFLIGHT` during ingest (lead-findings 1); ingest cost and minimal correct form (U12); subagent-slot loss has no per-slot identity (P1: 323 slot deaths, 117 parent fires) | W4 step 1 hands lr-audit the SSOT; slot identity stays with the workflow audit |
| R9 latency floor | the 40–86 s in-place chain floor (U14); today's run audit (U11) | the census removes the 35.5 s term; the rest is R2–R5 |
| R10 `session-busy.sh` LIMITED enum | a limited pane renders IDLE-DEAF (true, mis-named; `session-busy.sh:342`) | separate enum + renderer change; nothing here depends on it |
| R11 cc-classify reap decision | `bin/cc-classify:816` never-reap keyed on `:312`'s regex | W4 step 4's UNION is the prerequisite; the reap policy itself is R11's |

---

## 9. Open decisions (conviction %; ≥ 90 % items are implemented above, not asked)

| # | decision (answer-first) | conviction | options measured |
|---|---|---|---|
| D1 | The hook DOES page once per cause by default (`.page-off` to mute). It overturns the file header's "never notifies" (`:9-16`) by delivering its INTENT — one fact, one page — through an O_EXCL latch keyed on the payload | 82 % | (a) as stated; (b) page only from the poller tick (≤ 600 s late until R2, and the kick is off); (c) no page — the operator runs `cc-limited` (zero push; contradicts "without screenshotting each pane") |
| D2 | The kick lands DEFAULT OFF (`.kick-on` absent) and is flipped in R2 | 85 % | (a) as stated; (b) on now — every death kicks an autofire tick whose DETECT loop is still the 35–86 s scan until W3 lands, at load ≈ 11–50 (judge Db-safety FATAL 3); (c) never — keeps mean 323 s / max 609 s of poller blindness |
| D3 | Marker defaults: `TTL_MIN` 1440 → 10080 (the seven_day window) and `CAP` 500 → 5000, so a weekly cap outlives its marker and a burst account (36 rows/day on next4, 22/42 sessions re-fire up to 30×) does not reach the cap in two weeks; the census flags a capped file at exit 6 regardless | 76 % | (a) as stated (≤ 2.5 MB per cause file worst case); (b) keep 1440/500 and rely on `parked/` + IDL as the second enumerator (residual: a TICK-SKIP'd weekly death for 24 h has no live enumerator); (c) per-sid dedupe inside the hook (a read-modify-write on the death path — the header's own argument against it) |
| D4 | `--since 24h` is the default census window for five_hour/network rows; seven_day rows show for their whole window | 88 % | (a) as stated; (b) show everything the enumerator holds (re-imports the 125–505 h archaeology P8 scored `--locate` for) |
| D5 | `lf_locate` stays as `--slow-scan` for ONE release, then is retired if the both-paths diff has stayed empty | 72 % | (a) as stated; (b) retire in W3 (−110 LOC now; the `-p`/sdk-cli deaths lose their only census path — 0/2 emit StopFailure); (c) keep forever as `--deep` |
| D6 | The statusline chip carries BOTH pane and sid8 (`#121 65186f1f`), +16 cols | 88 % | (a) both; (b) pane only, +5 cols (a screenshot of a pane after a recycle then names a different session than the one that died) |
| D7 | Fable / monthly_spend rows are enumerated INTO the per-account group with `resets —` and the action `/model` or "operator" — never parked, never hidden | 92 % → implemented | — |
| D8 | The beat is written for `rate_limit` only, never `failed` for other StopFailure classes | 90 % → implemented | — |
| D9 | The `(account, cap, resets_at)` group key for the poller's re-surface page vs `(account, cap)` alone | 80 % | (a) with resets_at — every session capped on one account shares it to the second (all epochs % 600 == 0, P3); a second reset time in one group IS a finding and renders as two headers; (b) without — one page per account per 30 min regardless of a re-cap |

---

## 10. Receipts — commands run by this unit (all read-only)

- `git rev-parse --short HEAD` ⇒ `a59b53e55`; `git status --short` ⇒ clean.
- `cat -n hooks/stop-failure-marker.sh` (131 lines) ⇒ `:37 set -uo pipefail` · `:41-42 TTL_MIN/CAP` · `:82-89` account · `:92-94` cause key · `:96 mkdir` · `:100` GC · `:115-118` cap exit · `:122-128` line · `:130-131`.
- `grep -n … hooks/session-beat.sh` ⇒ `:40 P8_TIMEOUT` · `:55 pane=` · `:58 kind=` · `:61-66 who` · `:87-93` ancestor walk · `:98-107` operatorT/seq · `:124-128` background + wait.
- `sed -n 315,322p scripts/lib/spawn-presence.sh` ⇒ `.kind == "prompt"` select; `sed -n 780,792p scripts/lib/capacity-admit.sh` ⇒ `act_ceiling=…:-8`, `[ $(( act + 1 )) -gt "$act_ceiling" ]`; `sed -n 332,344p hooks/lib/session-busy.sh` ⇒ `[ "$kind" = "prompt" ]` at `:342`.
- `grep -n … scripts/limit-recover/lr-fleet.sh` (581 lines) ⇒ `:29 set -uo` · `:108 LIMIT_RE` · `:122 NET_RE` · `:123 BLOCK_RE` · `:143 lf_kinds_of` · `:166 lf_err_age_s` · `:183 lf_locate` · `:218 lr_resume_procs` · `:225 RESUMING` · `:232 CWD-GONE` · `:243 IDLE-AFTER-ERROR` · `:256 lf_dedup_mirror` · `:307 lf_phantom_actives` · `:435/:456/:496/:530` the four `lf_locate | lf_dedup_mirror` sites · `:525 [ "$kind" = limit ]` · `:534 kickstart -k` · `:536 nothing to enqueue`.
- `grep -n … scripts/limit-recover/lr-reset-poller.sh` (1033) ⇒ `:123 LOG=` · `:152 REQUESTS=` · `:185 exit 0 # a genuine live tick` · `:263/:592 osascript` · `:296 acct_of_cfg` · `:327 LR_ENGAGE_SETTLE_MIN` · `:373 NOT-ENGAGED` · `:566 SPEND_RE` · `:658 rm -f "$_rq"` · `:718-720/:752-754 agentName` · `:746 grep -E "You've hit your (session|weekly) limit"` · `:771 ('session','weekly','fable')` · `:788 PARKED` · `:795 find -H`.
- `grep -n … scripts/limit-recover/lr-lib.sh` (394) ⇒ `:34 lr_tier_from_transcript` · `:55 "hit your" in txt or "reached your"` · `:129 lr_last_api_error` · `:156 "limit" if "You've hit your"` · `:210 lr_registry_live_rows` · `:233 lr_resume_procs` (leaf awk `:252`) · `:287 lr_transplanted_to`.
- `grep -n … scripts/limit-recover/lr-audit.py` (2362) ⇒ `:75 LIMIT_PREFIXES` · `:80 SERVER_529` · `:81 RESET_RE` · `:210-212` · `:244-248 classify_limit_text/startswith`.
- `grep -n … hooks/net-recover-arm.sh` ⇒ `:132/:192 lr_last_api_error` · `:164 _turn_ended_after` · `:175 >= ts` · `:195 _ts="${_rec##*<TAB>}"` · `:200`; `hooks/recover-inject.sh` ⇒ `:93-94 IFS=$'\t' read -r _uuid _err _kind _ts` · `:98 [ "$_kind" = limit ]` · `:101 NOT a quota message`.
- `statusline.sh` (486) ⇒ `:75 PAY_SID=""` · `:222 GLYPH_PREFIX=""` · `:230 PCT_SEG=""` · `:486 echo -e`; `hooks/session-register.sh` (542) ⇒ `:84 pid_is_strict_ancestor` · `:127 pane=` · `:158 acct=` · `:168-172` inherited-pane comment · `:208-213` gate · `:290 mv -f`.
- `scripts/deploy-live.sh` ⇒ `:1478 link_refresh` · `:1500 MISSING: ln -sf` · `:1770 install.sh runs ONLY on the advance path`; `install.sh` ⇒ `:219 copy_file` · `:960 copy_file … statusline.sh`; `.claude/CLAUDE.md:41` grants `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`.
- `jq -c '.accounts[]|{name,config_dir,aliases}' ~/.claude/accounts.json` ⇒ `next ~/.claude-next ["claude"]`, `next4 ~/.claude-quaternary`, `next3 ~/.claude-tertiary`, `next2 ~/.claude-secondary` — no `~/.claude` row, alias present.
- `hooks/lib/idl-log.sh:112-120` (`log_idl` takes `extra`); `hooks/lib/page-damp.sh:40-52` (check-then-write, fail-open); `scripts/gen-account-map.sh:117 } > "$OUT"`; `scripts/limit-reset-safety-gate.sh:114-121` LR-blind block; `bin/cc-classify:312` regex, `:816` never-reap; `scripts/desk-invariant.sh:148/:156 cap_stunned`; `commands/recover.md:101`; `commands/limit-recover.md:441 kickstart -k`; `docs/lessons/census-matches-itself.md` exists.
- `grep -n '@test' tests/lr-fleet.bats` ⇒ locate `:55-96`, D7 `:244-350`, D8 `:375-419`, phantom `:454-468`; `tests/stop-failure-marker.bats` ⇒ `:108` cap, `:116` TTL, `:149` footprint, `:165-171` CONTROL; `tests/net-recover-arm.bats` 9 tests; `tests/spawn-presence.bats` beats fixtures at `:536-556` (kind `prompt` only).
- `ps eww -o command= -p 41639` ⇒ `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary`, `KITTY_WINDOW_ID=186`, `KITTY_LISTEN_ON=unix:/tmp/kitty-73832`, NO `ITERM_SESSION_ID`, NO `CC_PANE_ID`.
- `ls ~/.claude/autonomy/stop-failure/` ⇒ `authentication_failed__.claude.jsonl 5 rows/5 sids` · `rate_limit__next.jsonl 4/4` · `rate_limit__next3.jsonl 12/8` · `rate_limit__next4.jsonl 36/12`; the 12 next3 rows and the 9 drill rows (§ 5) via `jq -r '[.ts,.session_id[0:8],.account,(.cwd|split("/")|last)]|@tsv'`.
- Registry (39 numeric rows): `111 cb29ae36 claude-secondary 12341 1789857366000` (= 22:36:06Z) · `121 65186f1f claude-secondary 59379 1789850919000` (20:48:39Z) · `127 11569d45 claude-secondary 41980` (20:57:01Z) · `149 8843bcf3 claude-secondary 25177` (21:02:19Z) · `166 26cd14be claude-secondary 35793` (21:20:50Z) · `150 7f533f05 claude-quaternary 17221` (husk) · `186 7f533f05 claude-tertiary 41639` (22:43:41Z, hand-registered); NO row for 147, 09e64dcb, 98f02458, 4bc1159f, 07e30aeb. `date -u -r` for each epoch.
- `ls ~/.reso/limit-recover/locks/` ⇒ locks for ALL eight next3 sids; `cat` ⇒ `98f02458 {to .claude-secondary, ts 2026-09-19T20:53:26Z, pid 32971}` · `4bc1159f {…, 20:59:34Z, 44616}` · `26cd14be {…, 20:57:55Z, 20652}`. `parked/` 8 files (none of the drill sids); `results/` has `07e30aeb`, `4bc1159f` `.json`+`.log` pairs.
- `ls -la ~/.claude*/projects/*/{07e30aeb,98f02458,65186f1f}*` ⇒ `07e30aeb`: secondary 1,157,520 B (15:32), tertiary 5,339 B (16:29), `.handed-off` 1,157,520 B; `98f02458`: secondary 4,099,484 B, tertiary `.handed-off` 3,069,363 B; `65186f1f`: secondary 3,016,134 B (18:01), tertiary `.handed-off` 1,871,535 B.
- `date -u -r 1789853400` ⇒ `2026-09-19T21:30:00Z` (the next3 five_hour reset).
- `grep -c '"hook":"stop-failure-marker"' ~/.claude/autonomy/idl.jsonl` ⇒ 59 of 94,153 rows; dispositions `55 fired marker-appended · 4 fired marker-opened` (0 abstains in the live file).
- `wc -l` prototypes ⇒ `lr_classify.py 107` · `cc-limited-v2.py 130` · `census-probe.py 133` · `cc-limited-proto.py 79`; `ls ~/.claude/cc-beats/*.json | wc -l` ⇒ 3,793.
- `ls -la ~/.claude/bin/cc-custody ~/.claude/scripts/limit-recover/lr-fleet.sh ~/.claude/hooks/stop-failure-marker.sh ~/.claude/statusline.sh` ⇒ the first three are per-file symlinks into the checkout; `statusline.sh` is a real file (COPY class).
- `grep -rn -E '2 h 37|12\.5 ?%' ../lr/research/` ⇒ `U10-limit-detect-hooks.md:199 **2 h 37 m**` · `U07-statusline-identity.md:313 2 of 16 (12.5%)`.

---

## 11. Critic pass — 15 gaps, each closed as a BINDING amendment (lead, 2026-09-19 ~23:50Z)

`CRITIC.md` (`docs/research/lr-detect-2026-09-19/wave2/CRITIC.md`) found 15 gaps in the synthesis above. Each is
closed here with a decision and its conviction; **where an amendment contradicts § 3–§ 9 text, the amendment binds**
and the earlier text stays as the decision record (plan conventions: integrate, never rewrite). Briefs for W1/W2a/W2b/W2c/W3/W5
MUST carry the rows below that name their wave.

| # | gap (severity) | amendment | binds | conviction |
|---|---|---|---|---|
| 1 | Drill row 1 asserts registry row `147.json` (07e30aeb) that the plan's own § 10 denies (**fatal**) | Fixtures are never hand-asserted: W2b ships `tests/fixtures/lr-2026-09-19/capture.sh`, which copies the marker rows, registry rows, locks, beats and transcript tails FROM THE LIVE STORES at capture time, writes `CAPTURE-RECEIPT.md` (ls/jq output, UTC stamp), and the expected states in § 5 are RE-DERIVED from that capture by the state table — not quoted from a prior moment. Row 1's live truth at brief time decides: no registry row ∧ no resume leaf ∧ beat pid dead ⇒ `NO-PANE` (and `#147` moves to the `--kitty` title column); a live beat pid ⇒ `RECOVERABLE (stub)` via amendment 2. The § 5 screen is an ILLUSTRATION until the capture exists | W2b, § 5 | 92 % |
| 2 | Liveness single-sourced on the registry, whose completeness P5 REFUTED (3/14 rate_limit sids rowless; cause is pane-keyed overwrite, not address) (**fatal**) | Second liveness source, already on the read path: `~/.claude/cc-beats/<sid>.json` carries `pid` + `lstart` for every session that ever submitted a prompt (`session-beat.sh:87-93` ancestor walk; identity `(pid,lstart)`, the reaper's own pin). W2a step 2 becomes: live ⇔ `(pid,lstart)` from {registry row for sid} ∪ {beat for sid} ∪ {resume leaf} matches ONE `TZ=UTC LC_ALL=C ps -eo pid=,lstart=`. A beat-only live session renders with `#?` for the pane (the beat's `pane` field when set) and is never NO-PANE. § 7 DROPPED row 3's justification is REWRITTEN: the `KITTY_WINDOW_ID` fallback closes the *address* class only; the *overwrite* class is closed by this source, not by W1. W2b adds row 16: a sid with a beat (pid alive) and NO registry row ⇒ RECOVERABLE, and its CONTROL (beat pid dead ⇒ NO-PANE) | W2a, W2b, § 7 | 90 % |
| 3 | `parked/` records cannot feed step 1's formula (no `ts`/`config_dir`/`last_assistant_message`/`error`) (major) | W2a step 1 gains the adapter verbatim from the critic: `ts←parked_at`, `config_dir←cfg`, `error←"rate_limit"`, `cap←{session→five_hour, weekly→seven_day, fable→model_scoped:Fable}`, `resets_at←reset_at_utc`, `last_assistant_message←""`; a parked-only sid classifies by `cap`, never by text. W2b row 17: a parked-only sid (marker absent) renders with its cap and reset | W2a, W2b | 95 % |
| 4 | Mirror dedupe at the wrong depth (`~/.claude-next` is a real dir; only its `projects/` is the symlink) (major) | W2a step 0/4: dedupe on `os.path.realpath(<root>/projects)` for roots and `(st_dev, st_ino)` per candidate file; `copies=N` counts inodes. W2b row 18: a `next` session enumerated from both `.claude` and `.claude-next` ⇒ `copies=1` | W2a, W2b | 95 % |
| 5 | W1 changes the beat `capacity-admit` consumes; no DoD runs the capacity suites (major) | W1 DoD adds `bats tests/capacity-admit-active.bats tests/capacity-admit-coverage.bats` (22 + 15 tests). § 4's gate rule becomes: **touched suites ∪ every suite that reads a store the wave writes** (beats, registry, markers, faults) | W1, § 4 | 95 % |
| 6 | The IDL-abstain probe adds +0.09 s to a 0.24 s worst case against a 0.30 s bar (major) | The default footer reads marker line counts only (a `wc -l` per cause file). IDL abstains are probed by a TIME-bounded reverse read (seek back ≤ 512 KB from EOF, parse rows whose `ts` falls inside the census window, stop at the first older row) — cost printed in the W2a timing row; the full 20,000-row read moves behind `--strict`. Exit 6 semantics unchanged | W2a, § 2.3 | 88 % |
| 7 | D3 raises CAP to 5000 (≈350× the measured enumerate regime); TTL rationale half-true (file-mtime GC) (major) | D3 is amended to **TTL 10080 / CAP stays 500**. Per-sid grouping already dedupes at read; a capped file is exit 6 (unchanged). TTL rationale restated: the GC is keyed on FILE mtime (`stop-failure-marker.sh:100`), so a busy account's file never expires either way — 10080 only lets a QUIET account's weekly cap outlive its marker. W2b row 19: the census over a 500-row marker file ×3 ≤ 0.30 s | W1, W2b, § 9 D3 | 85 % |
| 8 | W1's latency DoD stubs the beat writer — the one arm it exists to gate (moderate) | The W1 timing row runs TWICE: (i) beat stubbed ⇒ ≤ 0.30 s (the hook's own budget); (ii) real `session-beat.sh` ⇒ p95 over 20 runs, measured IN W1 and recorded in the suite's `# RED-PROOF` footer as the bar for (ii); the brief states that 0.30 s belongs to (i) | W1 | 92 % |
| 9 | D5 retires `lf_locate` while `--deep` is its only implementation for the sdk-cli / no-transcript class (moderate) | D5 adopts option **(c): `lf_locate` stays permanently as `--slow-scan` (= `--deep`'s implementation)**; retirement is possible only when `--deep` has a non-`lf_locate` implementation AND the parity diff is empty. W4 step 6 (retiring `LIMIT_RE`/`NET_RE`/`lf_kinds_of`) is therefore DROPPED; they stay as the slow-scan predicate, migrated to call the SSOT shim instead (recall must stay 209/209) | W3, W4, § 9 D5 | 88 % |
| 10 | TEAMMATE decided from a transcript 21 % lack; a raw `"agentName"` substring is a 13th predicate copy (moderate) | The teammate test lives in the SSOT as `lr_predicate.is_teammate_head(bytes)` (one copy) and is applied to the head-8 KB of EVERY copy, not only the preferred one. A sid with NO copy is `NO-TRANSCRIPT` (footer, never actionable) — the poller cannot park it, so the critic's double-resume path is closed by construction. `hooks/lib/agent-identity.sh` is NOT called on the death path (0.19–0.23 s, judge Da-latency) — the hook stamps nothing. W2b row 20: `agentName` in a non-preferred copy only ⇒ TEAMMATE | W0, W2a, W2b | 85 % |
| 11 | Five of eleven sources have no failure disposition (moderate) | ONE rule in the W2a header, verbatim: **an ABSENT source is EMPTY and named in the footer; a source that EXISTS but cannot be read or parsed is exit 5 with stdout EMPTY and stderr naming it; `--reaper --persist` failing to write is exit 6 with the path named.** Applies to markers, parked, registry, beats, locks, `fleet/*/results.tsv`, `results/`, `requests/`, `faults/`, accounts.json, `ps`. W2b row 21: unreadable `locks/` ⇒ exit 5; absent `faults/` ⇒ footer note, exit 0 | W2a, W2c, W2b | 95 % |
| 12 | Which `lr_predicate` a converged `cc-limited` imports is unspecified (moderate) | `sys.path` is built from `os.path.realpath(__file__)` — the module ALWAYS matches the binary that is running (a worktree's binary imports the worktree's module; the live symlink's binary imports the live checkout's). W2b row 22 invokes `cc-limited` through a symlink and asserts `lr_predicate.__file__` is under the same checkout as `realpath(cc-limited)` | W2a, W2b | 90 % |
| 13 | Two W5 rows cannot go red (historical suite; ±3 ms band 15× the effect) (minor) | `tests/statusline-identity.bats` is a must-stay-green note, not a gate; the gate is `fork count == baseline`: a test that asserts the chip block contains no `$(`, no backtick and no `|` (P6: zero subprocesses) plus the 10 new render rows | W5, § 4 | 90 % |
| 14 | F6 pins a wire format two units call UNMEASURABLE (minor) | F6 is labelled `SYNTHETIC — modelled on lr-reset-poller.sh:566 SPEND_RE` in the suite with a falsifier comment: the first real `monthly_spend` record (grep the corpus for `"error":"rate_limit"` ∧ `monthly spend` in an envelope) re-opens F6 | W0 | 95 % |
| 15 | Wave 5's converge rewrites every install.sh COPY class (githooks, CLAUDE.md, launchd/*.plist), wider than the frozen scope states (minor) | W5 runs `bash scripts/deploy-parity-assert.sh` BEFORE the converge as well, and the lead reads the diff it names; the COPY-class blast radius is stated in the W5 brief. § 6's "operator steps: NONE" stands (the poller plist is not a launchd/ copy class — critic R) | W5, § 6 | 95 % |

Net effect on Phase 0: W2b grows by rows 16–22 (+7, ≈ +70 LOC, still ≤ 310 — split into W2b-i (rows 1–11) and W2b-ii
(rows 12–22 + CONTROLs) if the brief exceeds 150 lines); W4 loses step 6; W0 gains `is_teammate_head`; no new wave.

---

## 12. What the lead measured on ITSELF during this plan's own recovery (2026-09-19 22:30–22:50Z)

The session that wrote this plan was capped mid-wave on next4's weekly limit and recovered by `lr-handoff.sh --in-place`
onto next3. Its own recovery is a live specimen of the classes above; full receipts in
`docs/research/lr-detect-2026-09-19/wave2/lead-findings.md` § Ingest findings.

- **`lr-audit` misclassified a SETTLED run's 10 dead slots as `UNSETTLED-INFLIGHT`** because the ingest turn itself was
  mid-turn; the run's `<task-notification>` (`agents_error 10`) was already in the transcript. Carried as **R8**.
- **`--in-place` degraded to a spawn**: successor in kitty window 186 (expect-rooted, unregistered — no `ITERM_SESSION_ID`
  under expect; W1's `KITTY_WINDOW_ID` fallback is the fix, and the lead registered 186 by hand), source pane 150 left as a
  live tombstoned husk (pid 17221). `self-close --transplanted-source --successor 186` REFUSED: the successor's claude owns
  expect's pty (ttys043), not the pane's tty (ttys042), so `successor_pin` cannot see it. Carried as **R3**; the husk was
  filed as operator step `5dbca0071e85` (close window 150).
- **`claude-accounts` is not on PATH in an expect-launched session** (`~/bin` absent); `commands/limit-recover.md` § recover
  step 1's "resolve from PATH, not `~/bin`" is wrong in exactly this launch shape. Carried as **R6**.
- The poller's two `RESUMED … pane opened` lines at 19:43Z for `fff83638`/`0e2567ee` were **false greens** (capacity refused
  2–3 s later; no resume record; windows gone) — the W2c reaper's `CLAIMED-NOT-LIVE` row is what would have named them.

---

## 13. Status log

- 2026-09-19T23:5xZ · plan opened by 7f533f05 (next3, pane 186) after: wave 1 harvested from the capped sibling 11569d45
  (0 re-spend); wave 2 = 10 refutations + 3 blind designs + 9 judges + synthesis + critic (`wf_b0f2a31c-e7d`, 24/24 after
  a cross-account resume that replayed 13 cached slots); § 11 closes all 15 critic gaps. Nothing implemented yet — Wave 1
  (W0 · W1 · W5) is the next fire, per Phase 0.

## 13. Cross-reference — `LIMIT_RECOVER_100P` § 9 landed the recovery side first (2026-09-20 00:1xZ, session 11569d45)

Your wave-1 corpus was this session's research. Landed and LIVE on trunk at `1b2676f4c` (23:50Z),
before your S waves could fire: the statusline identity segment (`#<pane> <sid8>`, left-anchored —
your W5, done; `#` per your Monaco finding), `bin/cc-find` (one-session resolver: pane/sid8/tuple/kw,
`--limited`), `lr-fleet --one` registry-first, `lr_holder_count` (`5fe4c9f84`), `lr-fleet --detach` +
a named `recycle-dead` watcher arm, `claude-accounts --recovery`. In flight there: the admission
token + precheck + boot wait (the 2-attempt/3-budget husk arithmetic), then submit/engage/ingest.
Proposed split, recorded in `LIMIT_RECOVER_100P` § 9 → Reconciliation: you own detect / identify /
surface (W0–W4, W6 as written; W5 is done — verify on trunk); that plan owns the recovery chain and
narrows its W5 to actuation, dropping its census item for your `lf_census`. Your `kind:limited` beat
is yours to rule; the token path there never reads it. Re-anchor every `file:line` on trunk ≥
`1b2676f4c` before firing W1–W3.
