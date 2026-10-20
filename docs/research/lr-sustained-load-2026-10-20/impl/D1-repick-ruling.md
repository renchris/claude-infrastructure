# D1: should a recycle leave an account the router holds for new work? Decision packet and implementation design

Item D1-repick-ruling, from `REPORT.md` §4(d) D1 and §6. Written 2026-10-20 around 17:30-18:00Z,
read-only, against `28b25a119` (this worktree's HEAD, which is also main's tip). Load at the time
of writing was `sysctl -n vm.loadavg` => `{ 177.26 196.29 203.17 }` on 10 cores, about 18/core
(measured 17:52:48Z).

**Labels.** *Measured* means read from a named file or produced by a named command. *Estimated*
means derived, and the method is named. *Hypothesis* means not verified.

**Verdict: OPERATOR.** The change is small and an agent can build it end to end (§6), but the
question is the routing-policy judgment that the code's own comment reserves
(`scripts/handoff-fire.sh:15993-15998`), so it needs a ruling first. **Recommendation: yes,
honour the held verdict, with the router-declared mode `on`. Conviction 85%.**

---

## 1. The question

> When a session recycles (exit and relaunch in the same pane, with fresh context), and the router
> holds the pane's current account **for new work**, should the relaunch move to the router's
> open line 1? Put the other way: may a recycled session keep landing on an account the router
> reserves?

Scope, from the code:

- **In scope.** Ordinary recycles that take the `auto` account arm: `/handoff`, the
  boundary-handoff hook, the waiting-recycle deterministic recycle, and lead succession. The
  re-pick is called only there (`scripts/handoff-fire.sh:16437-16452`).
- **Out of scope.**
  - Resume and transplant recycles. The lr-handoff, lr-fleet, move-lane and `--same-account`
    forms all carry `--resume-launcher`, which takes the explicit arm at `:16432-16436`, and the
    pair is enforced at `:15420-15421`.
  - An explicit `--account` or `--launcher`.
  - Frontier (Fable) recycles, which return early at `:16022`.
- **Two sub-questions.**
  - Q1: may a recycle **leave** a held account? Today it may not, unless the account is excluded
    or outscored 4x.
  - Q2: may a re-pick **land** on a held account? Today it does only when every routable account
    is held, because line 1 comes from the partitioned ranking. This packet keeps Q2 as it is,
    and adds one rule: a move made *because* the incumbent is held never lands on another held
    account.

## 2. How the code decides today

| Placement path | Rule for a thin account (< `DISPATCH_W_FLOOR` 0.10 weekly headroom) | Code |
|---|---|---|
| New fire (`--account auto`) | **Held**, so demoted below every open account. It is still picked when it is the only routable one | `bin/claude-accounts:6851-6882` (`_dispatch_partition`), `:6920-6928` (`ranked`) |
| Recovery placement (`--place`, `--recovery`) | **Excluded** below `RECOVERY_W_FLOOR` 0.10 | `bin/claude-accounts:6545` (`recovery_floors` in `cmd_place`), `accounts.json:68` |
| **Recycle** (`recycle_repick`) | **Stays**, unless the account is excluded, or line 1 beats it by `repick_ratio` (4x) | `scripts/handoff-fire.sh:16058-16131` |

So the recycle is the one automatic path that keeps putting sessions onto a thin, held account.

The held verdict comes from `dispatch_floor_row` (`bin/claude-accounts:6770-6827`):

- A thin account is open (`lifted`, or `lifted-first`) only when its forecast-dead quota covers
  another fire.
- Every other thin verdict is a hold: `flat`, `level-stale`, `hold-credits`, `pace-unknown`,
  `pace-stale`, `on-pace` and `claimed`.
- The router already publishes each thin row's verdict on `route-meta` as
  `dispatch_floor=<acct>:<token>:<spare>`. That token is at `bin/claude-accounts:11519-11525`; it
  was added in `aa98726b1`, 2026-10-09 (measured: `git log -S`).

The §14 comment explains why v1 did not re-pick on pressure short of exclusion: "a routing-POLICY
judgment and belongs with M7's scoring terms, where it can be scored against headroom, not here
where the only input is a boolean" (`:15995-15998`). That condition has since been met. The held
verdict is now the router's own judgment, scored against headroom, pace and claims inside
`claude-accounts` (the floor landed 2026-09-27 in `5eb65d95d`, the strand rescue 2026-10-09 in
`aa98726b1`). The floor's own commit message says:

> "The one change covers handoff-fire's head -1, **recycle_repick**, --route general, and
> cc-wave-plan."

That is true of where a re-pick **lands** (line 1). It is false of whether it **leaves**, which is
the hole this item addresses (measured: `git show 5eb65d95d`).

## 3. Measurements

| # | Finding | How |
|---|---|---|
| M1 | **5 of 40** named-account recycles in the ledger window (2026-10-18T07:05Z to 10-20) relaunched onto an account at weekly ≥90%. All 5 were next3, between 10-19 19:45Z and 10-20 02:22Z: pane 7 at 92%, pane 63 at 93%, pane 38 at 93%, pane 55 at 95% and pane 24 at 100%. Axis 10's own reads are 92/93/94/96/100 | Measured: `python3 -I /tmp/d1/join.py ~/.claude/logs/account-utilization.jsonl ~/.claude/logs/handoffs.jsonl`, which joins each `recycle-intent` row to the preceding ledger row for its account. The window is limited by the 1000-row trim (`window_starts_at 2026-10-18T07:05:13Z`) |
| M2 | **3 of the 9 sessions at the next3 wall** got there through a recycle in the wall's last 4.1 h: 7aae55e1 (pane 38), e80b61f4 (pane 55) and ceff45c5 (pane 24). They engaged on another account 86, 94 and 103 min after the cohort opened at 02:31:55Z, about 284 session-minutes in all | Measured (axis 10 §2.2), engaged times from `REPORT.md` §2.1; the minutes are my arithmetic |
| M3 | **Red control, today's code.** The 2026-10-19T18:36:54Z ranking (`next 0.000185 > next2 0.000105 > next4 0.000045 > next3 0.000166`), with next3 held, run through the extracted `recycle_repick next3` under `/bin/bash` 3.2. Result: stdout empty; stderr `♻ recycle stays on next3 — routable, and next (0.000185) does not beat its 0.000166 by the router's 4x threshold`; no `--assign`; no row on disk | Measured: `/tmp/d1/ctl/block.sh` (marker extraction, as the suite does) with the stub `/tmp/d1/ctl/stub.sh` |
| M4 | **Every thin window walls.** Since the ledger began (2026-08-10), 41 weekly windows have closed. 33 reached ≥90% and 27 of those walled (100%). **Since 08-29, 25 of 25** windows that reached 90% walled. From ≥90% to the wall: min 1.5 h, p25 2.6 h, **median 11.3 h**, p75 20.1 h, max 71.3 h | Measured: `python3 -I /tmp/d1/windows.py ~/.claude/logs/account-utilization.jsonl`. Weekly ≥90% is a proxy for "thin"; the router's rule uses `weekly_headroom`, which includes the wire figure |
| M5 | **The cross-account recycle mechanism works.** All 4 re-picks in the window engaged on the new account: pane 362 (next to next3) `recycle-engaged` at 183 s, pane 246 (next to next3) at 103 s, pane 397 (next4 to next3) at 197 s, pane 5 (next4 to next) at 269 s, each "a real assistant turn within 0s" | Measured: `handoffs.jsonl` rows per pane after each `recycle-repick` row |
| M6 | **The router read inside a recycle sometimes sweeps.** keepwarm runs every 180 s against a 90 s cache TTL (`plutil -p ~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist`; `accounts.json:23`). Its sweeps take **p50 24.6 s, p90 75.4 s, max 149 s** (335 swept, 65 served). A recycle's `--rank` that finds a 91-600 s cache with the lock free sweeps itself (`bin/claude-accounts:8300-8318`), so it hits the 25 s `perl alarm` (`handoff-fire.sh:16039`) about half the time | Measured: `tail -400 ~/.claude/logs/accounts-keepwarm.out.log`, parsed for `took_ms` |
| M7 | A cache-served `--rank general` from a priority-31 shell takes 2.10-8.09 s at about 22/core (p90 about 8.1 s), and about 14.6 s scaled to 40/core | Measured by wave 5 and quoted from the `134000efe` commit message. The 40/core figure is that commit's estimate |
| M8 | `dispatch_held`, `repick_held` and `REPICK_HELD` appear nowhere in the code, tests or SSOT | Measured: `grep -c -E 'dispatch_held\|repick_held\|REPICK_HELD'` over `bin/claude-accounts`, `scripts/handoff-fire.sh`, `accounts.json` and both suites gave 0 each |
| M9 | Cached rows carry no derived dispatch keys (`thin_demoted`, `dispatch_floor`). Current levels: next 57, next4 15, next3 0, next2 79 | Measured: python read of `/tmp/claude-accounts-cache.json` at 17:4xZ |
| M10 | The pace and claims behind the held verdict are recomputed on every call, after the cache read (`apply_assignments`, `apply_burn` at `bin/claude-accounts:11285-11289`). A stale cache therefore ages only the weekly **level** | Measured: code read |

**Estimates built on these.**

- **Recycles that today get no router answer: about 15-20%.** Method: the cache is older than
  90 s for about half of each 180 s keepwarm cycle. The lock is free for about 65 s of each
  cycle, so a recycle's call sweeps on about 36% of calls, and about half of those sweeps exceed
  25 s. Unmeasured, because a "stays" outcome is never written to disk (axis 10 open question 4).
- **Wall sessions avoided: about 3-4 per wall, so about 8-10 fewer recoveries a week.** Method:
  M1's rate is 5 recycles in the 8.6 h that next3 spent thin, and 3 of the 5 were still alive at
  the wall. Scaled by M4's median of 11.3 h thin per wall and the fleet's ~2.7 walls a week
  (axis 10 §1). This rests on one incident (n=1), so the range is wide.
- **Strand cost: near zero.** Method: 25 of 25 thin windows since 08-29 walled (M4). And an
  account the forecast says will strand is `lifted`, not held (`:6816-6827`), so D1 never moves a
  recycle off it.

## 4. Options

| Option | What it does | Measured or estimated consequence |
|---|---|---|
| **A. Status quo** | Leave only when excluded or outscored 4x | Recycles keep landing on thin accounts during their median 11.3 h run to the wall (M1, M4). In this incident 3 of the 9 at the wall came this way (M2). The 2026-09-27 floor's stated intent, to cover `recycle_repick`, stays unmet on the leave side |
| **B. Honour the held set (recommended)** | When the router lists the incumbent in `dispatch_held` and line 1 is not in it, move to line 1 | Estimated 3-4 fewer wall sessions per wall. It adds no relaunch: the recycle is already happening (it is "a passenger, never a trigger", `VOLUNTARY_ACCOUNT_SWITCH.md:334`). It adds no router call: it reuses the call made today (`:16039`). Strand cost near zero (M4) |
| C. Honour only quota-evidenced holds (`on-pace`, `claimed`, `flat`); stay on the data-quality holds (`pace-unknown`, `pace-stale`, `level-stale`) | As B, but with a narrower trigger | Under permanent load the ledger goes stale when sweeps stall (M6), which is exactly when `pace-stale` appears. C keeps sessions on a thin account at those moments, while every new fire already treats it as held. The consumer would also have to own the router's token vocabulary. Not recommended |
| D. Like B, but the target must be `roomy` (never a `lifted-first` thin account) | A narrower target | Skipping line 1 makes handoff-fire author routing policy, which the §14 design refuses (`:16086-16093`). A `lifted-first` target is forecast to strand by at least one fire's need, and `--assign` charges its claim, so the gain is small. Kept as an operator alternative |
| E. Put the held flag on `--rank` stdout | A router contract change | `--rank` stdout is the `acct score` contract that cc-wave-plan and handoff-fire parse by shape (`bin/claude-accounts:11455-11456`). Route-meta already carries the facts. Rejected |
| F. B, but ship in `shadow` mode first | Record "would move" rows for N days, then flip the mode | Costs the avoided wall sessions for N days (estimated ~8-10 recoveries a week). The mechanism is already proven by M5. Available through the same switch without a code change, so offered as a mode, not as the default |

## 5. Recommendation

**Adopt B.** Make the mode a router declaration, `repick_held=on`, read by `recycle_repick`. Keep
Q2's rule. Record every decision, including "stays", on disk.

Why:

1. **A recycle is new work.** The successor is a fresh session that starts from disk
   (`docs/plans/ACCOUNT_ROUTING_V2.md:836-838`). The router's rule for new work is the held
   verdict.
2. **Both other automatic paths already refuse thin accounts** (§2).
3. **The original objection is now answered inside the router** (§2), and both the threshold and
   the set are read from it, as with `repick_ratio`. The consumer reads them; it does not decide
   them.
4. **It keeps the operator's "exhaust the week" ruling** (`bin/claude-accounts:3890-3891`, ruling
   of 2026-10-17). A held account is by definition on pace to use its week, and every thin window
   since 08-29 walled (M4). If moving recycles off ever leaves spare quota, the strand rescue
   lifts that account. A lifted account is not held, so the recycles stay on it and new fires
   come back to it. The router self-corrects toward exhaustion.
5. **It consistently applies the 2026-09-22 ruling's own logic**: "Putting more onto next3 cannot
   fill it faster … it can only bring next3's wall forward"
   (`docs/research/routing-policy-ruling-2026-09-22.md:20-29`). No routing constant changes.

**Conviction 85%.** What would move it:

- **Down:** a thin window that does not wall under today's routing (none since 08-29); or the
  operator ruling that desk recycles must follow the desk lane (sub-question 5).
- **Up:** the first live thin window with D1 on shows no recycle-placed session at the wall.

---

## 6. Implementation design (for the recommendation)

### 6.1 Files and functions

| File | Function or site | Change |
|---|---|---|
| `bin/claude-accounts` | new `REPICK_HELD_DEFAULT`, `REPICK_HELD_MODES`, `repick_held_mode(R)`, placed after `repick_ratio` (`:3842-3866`) | The mode, declared by the router |
| `bin/claude-accounts` | route-meta print (`:11457-11531`) | Append `dispatch_held=<a,b>|-` and `repick_held=<mode>` **after** the `dispatch_floor=` token, same lanes (general and fable, not `--recovery`) |
| `scripts/handoff-fire.sh` | `recycle_repick()` (`:16004-16186`) | Cache-first router read; parse the two tokens before `errf` is removed; the pressure block stops returning early; a third arm, `held`; a `recycle-repick-stay` row on every stay where the router was asked; `basis` and `held_token` on the re-pick row |
| `scripts/handoff-fire.sh` | §14 header comment (`:15984-16003`) | Document the third arm and the ruling |
| `accounts.json` | router block | `"REPICK_HELD": "<ruled mode>"` and a `_repick_held` note recording the ruling (optional; the code default carries it) |
| `tests/handoff-recycle-repick.bats` | new D1 section; test 30's last line | §6.6 |
| `tests/account-recovery-lane.bats` | setup unset list (`:44-49`); new route-meta cases | §6.6 |
| `tests/recycle-repick-held-contract.bats` (new) | producer-to-consumer contract | §6.6 |
| `docs/plans/ACCOUNT_ROUTING_V2.md` | §14 | A §14.3 record of the held arm |

### 6.2 Router diff sketch (`bin/claude-accounts`)

```python
# after repick_ratio() (:3866)
# ── D1 (ruling <packet-id>, 2026-10-2x): a recycle LEAVES an account held for new work ──────────
# The dispatch floor (dispatch_floor_row/_dispatch_partition) decides which thin accounts are HELD
# for new work; every fire obeys it and --recovery EXCLUDES a thin account outright. A recycle is
# a fresh session from disk — new work — and was the one path that kept landing on a held account
# (3 of 9 at the 2026-10-20 next3 wall). The SET and the SWITCH ride route-meta, for
# repick_ratio's reason: the consumer reads them and does not get a vote.
REPICK_HELD_DEFAULT = "on"                 # the ruled mode; "shadow" records, never moves
REPICK_HELD_MODES = ("on", "shadow", "off")


def repick_held_switch_path():
    return os.path.join(HOME, ".claude", "state", "repick-held")


def repick_held_mode(R):
    """on|shadow|off — whether handoff-fire's recycle_repick moves a pane off a HELD incumbent.
    First PRESENT, non-empty source wins: env CC_ROUTE_REPICK_HELD > the operator switch file
    (~/.claude/state/repick-held: one word, fleet-wide at the next recycle, keyed on $HOME and never
    on CLAUDE_CONFIG_DIR so no routing decision can step around it) > SSOT router.REPICK_HELD >
    REPICK_HELD_DEFAULT. A present value outside the three reads 'off': this term AUTHORISES moving
    a pane, so its safe failure direction is off (repick_ratio's docstring)."""
    try:
        with open(repick_held_switch_path()) as f:
            switch = f.read(64)
    except OSError:
        switch = None
    for raw in (os.environ.get("CC_ROUTE_REPICK_HELD"), switch, (R or {}).get("REPICK_HELD")):
        if raw is None or not str(raw).strip():
            continue
        v = str(raw).strip().lower()
        return v if v in REPICK_HELD_MODES else "off"
    return REPICK_HELD_DEFAULT
```

```python
# route-meta (:11457 ff.), computed beside `w = cand[0][1]`:
held = (",".join(r["acct"] for _s, r in cand if r.get("thin_demoted"))
        if dispatch_w_floor(cfg["router"]) > 0 else "")
# …and appended AFTER the existing dispatch_floor list item (so the pinned adjacency
# " repick_ratio=4 dispatch_floor=…" at tests/account-recovery-lane.bats:910 survives):
+ ([f"dispatch_held={held or '-'}", f"repick_held={repick_held_mode(cfg.get('router'))}"]
   if kind in ("general", "fable") and not recovery else [])
```

The tokens contain no spaces or glob characters, because cc-route word-splits this line
(`bin/cc-route:166`; comment at `bin/claude-accounts:11517-11518`). `thin_demoted` is the
partition's own flag, cleared and re-stamped on each call (`:6864-6881`). The floor guard covers
the early return at `:6860`, where the flags are not cleared.

### 6.3 Consumer diff sketch (`scripts/handoff-fire.sh`, `recycle_repick`)

```diff
@@ :16005 locals
-  local cur="$1" bin="${CC_ACCOUNTS_BIN:-claude-accounts}" errf out new reason exline rc=0
+  local cur="$1" bin="${CC_ACCOUNTS_BIN:-claude-accounts}" errf out new reason exline rc=0 t0=$SECONDS
+  # A stay is recorded too (D1; axis-10 open question 4): a "stays" written only to a pane that is
+  # about to exit is unrecoverable. Nested, and its closing brace is INDENTED: the suite extracts this
+  # function from its marker to the first column-0 `}`. NEVER name the class `recycle-held-*` —
+  # lr-move-worker.sh:460, lr-handoff.sh:1303 and lr-fleet.sh:1393 read that prefix as a HELD verdict.
+  _rp_stay() { # $1 why · $2 best · $3 rank rc · $4 ranked · $5 exline · $6 rr · $7 held mode · $8 held token
+    [ "${DRY:-0}" = 0 ] && [ "${CC_FIRE_REFUSAL_LOG:-1}" != 0 ] && command -v jq >/dev/null 2>&1 \
+      && mkdir -p "$HOME/.claude/logs" 2>/dev/null || return 0
+    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg f "$cur" --arg why "$1" --arg b "$2" \
+           --arg rc "$3" --arg rk "$4" --arg ex "$5" --arg rr "$6" --arg hm "$7" --arg ht "$8" \
+           --arg s "$((SECONDS - t0))" --arg p "${SID:-}" \
+      '{ts:$ts, class:"recycle-repick-stay", gate:"recycle", from:$f, why:$why,
+        best:(if $b == "" then null else $b end), rank_rc:($rc|tonumber? // null), rank_s:($s|tonumber),
+        ranked:(if $rk == "" then null else $rk end), excluded:(if $ex == "" then null else $ex end),
+        repick_ratio:(if $rr == "" then null else $rr end), repick_held:(if $hm == "" then null else $hm end),
+        held_token:(if $ht == "" then null else $ht end), target_pane:(if $p == "" then null else $p end)}' \
+      >> "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null || true
+  }
@@ :16038-16043 the router read
+  # CACHE-FIRST. --max-age 600 serves the shared cache up to the router's own grace (cache_grace_s)
+  # instead of sweeping: keepwarm refreshes it every 180 s, and a sweep measured p50 24.6 s / p90
+  # 75.4 s at 15-20/core, so a recycle that had to sweep lost to the 25 s alarm about half the time.
+  # The held verdict's pace and claims are recomputed per call (claude-accounts:11285-11289); only
+  # the weekly level can be up to 10 min old. --max-wait 20: a clean exit 3 inside the alarm on the
+  # no-cache path. Our alarm firing is UNKNOWN, never a verdict about the account.
   if command -v perl >/dev/null 2>&1; then
-    out="$(perl -e 'alarm 25; exec @ARGV' "$bin" --rank general 2>"$errf")" || rc=$?
+    out="$(perl -e 'alarm 25; exec @ARGV' "$bin" --max-age 600 --max-wait 20 --rank general 2>"$errf")" || rc=$?
   else
-    out="$("$bin" --rank general 2>"$errf")" || rc=$?
+    out="$("$bin" --max-age 600 --max-wait 20 --rank general 2>"$errf")" || rc=$?
   fi
-  if [ "$rc" != 0 ] || [ -z "$out" ] || [ "$out" = none ]; then rm -f "$errf"; return 0; fi
+  if [ "$rc" != 0 ] || [ -z "$out" ] || [ "$out" = none ]; then
+    rm -f "$errf"; _rp_stay rank-unanswered "" "$rc" "" "" "" "" ""; return 0
+  fi
@@ after `ranked=` (:16057), BEFORE the new==cur check, while $errf still exists
+  local rh_raw dh_raw df_raw cur_tok
+  rh_raw="$(sed -n 's/.*[[:space:]]repick_held=\([a-z]*\).*/\1/p' "$errf" | sed -n '1p')"
+  dh_raw="$(sed -n 's/.*[[:space:]]dispatch_held=\([^[:space:]]*\).*/\1/p' "$errf" | sed -n '1p')"
+  df_raw="$(sed -n 's/.*[[:space:]]dispatch_floor=\([^[:space:]]*\).*/\1/p' "$errf" | sed -n '1p')"
+  # display only — the DECISION reads dispatch_held membership, never this vocabulary
+  cur_tok="$(awk -v a="$cur" 'BEGIN { RS = ","; FS = ":" } $1 == a { print $2; exit }' <<<"$df_raw")"
   if [ "$new" = "$cur" ]; then
     echo "♻ recycle stays on $cur — the router's own top pick (ranked: ${ranked:-?})" >&2
-    rm -f "$errf"; return 0
+    rm -f "$errf"; _rp_stay top-pick "" 0 "$ranked" "" "" "$rh_raw" "$cur_tok"; return 0
   fi
@@ :16100-16131 pressure, then the new third arm
-  local rr="$rr_raw" cur_s="" best_s="" why
-  if [ -z "$reason" ]; then
-    case "$rr" in ''|*[!0-9.]*) return 0 ;; esac
-    … [ -n "$cur_s" ] && [ -n "$best_s" ] || return 0
-    awk … || { echo "♻ recycle stays on $cur — routable, and …"; return 0; }
-    echo "⚠ recycle re-pick on PRESSURE: …" >&2; why="…"
-  else
-    why="$cur is NOT routable ($reason)"
-  fi
+  local rr="$rr_raw" cur_s="" best_s="" why="" basis="" stay=""
+  if [ -n "$reason" ]; then
+    basis=excluded; why="$cur is NOT routable ($reason)"
+  else
+    cur_s="$(awk -v a="$cur" '$1==a {print $2; exit}' <<<"$out")"
+    best_s="$(awk 'NR==1 {print $2}' <<<"$out")"
+    case "$rr" in
+      ''|*[!0-9.]*) stay=pressure-off ;;
+      *) if [ -z "$cur_s" ] || [ -z "$best_s" ]; then stay=incumbent-unscored
+         elif awk -v c="$cur_s" -v b="$best_s" -v r="$rr" '
+                BEGIN { if (c + 0 <= 0) { exit (b + 0 > 0) ? 0 : 1 }
+                        exit ((b + 0) / (c + 0) >= r + 0) ? 0 : 1 }'; then
+           basis=pressure
+           echo "⚠ recycle re-pick on PRESSURE: $cur scores $cur_s against $new at $best_s (router threshold ${rr}x) — moving this pane" >&2
+           why="$cur is routable but outscored: $cur_s against $new's $best_s, at or over the router's ${rr}x threshold"
+         else stay=below-threshold; fi ;;
+    esac
+    # ── D1, the THIRD arm: the router HOLDS the incumbent for new work and line 1 is open ──────
+    # Only when pressure did not move the pane, so every basis:"held" row is a move the first two
+    # arms would not have made. Membership is comma-fenced and exact: `next` is a prefix of
+    # next2/3/4. A held-basis move never lands on a held account (Q2): held-everywhere stays.
+    if [ -z "$basis" ]; then
+      case ",${dh_raw}," in
+        *",$cur,"*)
+          case ",${dh_raw}," in
+            *",$new,"*) stay=held-everywhere ;;
+            *) case "$rh_raw" in
+                 on)     basis=held
+                         why="$cur is held for new work by the router's dispatch floor (${cur_tok:-held}); $new is open to it" ;;
+                 shadow) stay=held-shadow ;;
+                 *)      stay=held-mode-off ;;   # off, absent (older router), or anything else
+               esac ;;
+          esac ;;
+      esac
+    fi
+    if [ -z "$basis" ]; then
+      case "$stay" in
+        below-threshold) echo "♻ recycle stays on $cur — routable, and $new ($best_s) does not beat its $cur_s by the router's ${rr}x threshold (ranked: ${ranked:-?})" >&2 ;;
+        held-shadow)     echo "♻ recycle stays on $cur — held for new work (${cur_tok:-held}); SHADOW: would have moved to $new (repick_held=shadow; ranked: ${ranked:-?})" >&2 ;;
+        held-everywhere) echo "♻ recycle stays on $cur — held for new work, and so is every routable account (ranked: ${ranked:-?})" >&2 ;;
+      esac
+      _rp_stay "$stay" "$new" 0 "$ranked" "$exline" "$rr" "$rh_raw" "$cur_tok"
+      return 0
+    fi
+  fi
@@ :16176-16182 the re-pick row (fields appended LAST, row shape otherwise unchanged)
-           --arg b "$([ -n "$reason" ] && echo excluded || echo pressure)" --arg w "$why" \
+           --arg b "$basis" --arg w "$why" --arg hm "$rh_raw" --arg ht "$cur_tok" \
 …
+        repick_held:(if $hm == "" then null else $hm end), held_token:(if $ht == "" then null else $ht end),
```

Also:

- The DECLINED branch (`:16136-16141`) gains `_rp_stay declined-unmapped "$new" 0 …` before its
  `return 0`.
- The announcement (`:16169`) keeps the substring `CC_RECYCLE_REPICK=off`, which test 2 pins, and
  adds `held arm: repick_held=off (~/.claude/state/repick-held)`.

**Constraints the implementer must keep, each with its reason:**

- **No column-0 `}` before `recycle_repick`'s own.** The extraction is
  `sed -n '/^# ---- W2-A…/,/^}$/p'` (`tests/handoff-recycle-repick.bats:36`).
- **No numeric `>=`/`-ge` literal in the block.** Test 25's lint (`:386`) refuses one.
- **Here-strings, never `printf | awk … exit`.** This avoids SIGPIPE under pipefail
  (`:16105-16108`).
- **Valid under bash 3.2.** No `${x,,}`, and no `case` inside `$( )`.
- **Shellcheck-clean when run bare.** The land gate runs it that way.

### 6.4 Data and format changes

| Surface | Before | After |
|---|---|---|
| `route-meta:` (stderr of `--rank`/`--route`, general and fable lanes, not `--recovery`) | `… repick_ratio=4 dispatch_floor=…` | `… repick_ratio=4 dispatch_floor=… dispatch_held=<a,b>\|- repick_held=on\|shadow\|off` |
| `handoffs.jsonl` `recycle-repick` row | `basis` is `excluded` or `pressure` | `basis` adds `held`; new trailing fields `repick_held` and `held_token` |
| `handoffs.jsonl` new class `recycle-repick-stay` | none | One row per stay where the router was asked. `why` is one of `rank-unanswered`, `top-pick`, `pressure-off`, `incumbent-unscored`, `below-threshold`, `held-everywhere`, `held-shadow`, `held-mode-off` or `declined-unmapped`; plus `rank_rc`, `rank_s`, `best`, `ranked`, `excluded`, `repick_ratio`, `repick_held`, `held_token`. Volume about 17 a day (estimated from M1: 40 in about 2.4 days) against about 417 rows a day today (1000 rows in the trim window), so the trim reaches about 4% sooner |
| SSOT `accounts.json` router block | none | Optional `"REPICK_HELD": "on"` and a `_repick_held` note. A string, outside `ROUTER_OPTIONAL_RANGES` (numeric only, `bin/claude-accounts:437-456`), so it needs no validator |
| Operator switch file | none | `~/.claude/state/repick-held`, one word: `on`, `shadow` or `off`. `~/.claude/state` is a real directory, not a symlink into the checkout (measured: `ls -ld`) |

`recycle-repick-stay` delivers B6's "write the stays decision to disk" sub-item.

### 6.5 Failure modes under permanent 15-40/core load

| # | Failure | Handling | Load-dependent? |
|---|---|---|---|
| F1 | `--rank` is slower than the 25 s alarm (exit 142) | Pane keeps its launcher (today's byte-identical relaunch). A `rank-unanswered rank_rc=142` row means "unknown". No wait is added. The next chance is the pane's next recycle | The cache-first read makes it rare: 2.1-8.1 s at about 22/core, about 14.6 s at 40/core (M7). A sweep is no longer on this path (M6) |
| F2 | keepwarm wedged, cache older than 600 s | `--max-wait 20` tries the lock and serves the grace cache, or sweeps under a 20 s timer and exits 3 (`bin/claude-accounts:8267-8275`, `:8181-8202`). Logged `rank_rc=3` | Bounded at 20 s, then 25 s |
| F3 | Older router, or `CC_ROUTE_RECORD_INPUTS=off`, so no tokens | `repick_held` absent counts as off, and an empty `dispatch_held` means no member. Behaviour equals today's; the stay row says `held-mode-off` or `below-threshold` | No |
| F4 | A served cache up to 600 s old | Only the weekly level is stale; pace and claims are recomputed per call (M10). The level reaches the wall a median 11.3 h after thin (M4), so 10 min is negligible. The router's own doc: a stale pick is now-excluded in 0.8% of pairs at ≤10 min (`bin/claude-accounts:171-173`) | No |
| F5 | Several recycles off one held account pile onto line 1 | `--assign … --src recycle-repick` charges a phantom on each move (existing, `:16161-16163`), and apply_assignments sees it on the next call | No |
| F6 | Line 1 is `lifted-first` (thin, but forecast to strand) | Honoured, as for a fire, and its claim is charged. If it later turns held, that pane's next recycle moves again. D1 never moves a session onto a held account, so it cannot ping-pong | No |
| F7 | Data-quality holds (`pace-stale` etc.) when the ledger goes stale under load | Treated as held, as every new fire treats them. The target is open. The strand risk on a thin account is about 0 (M4) | Indirectly; the direction is safe |
| F8 | The switch file holds garbage or cannot be read | Garbage counts as `off` (the authorising term fails off); an unreadable file is skipped as absent | No |
| F9 | The stay row is mistaken for a HELD verdict by the lr lanes | The class is `recycle-repick-stay`, never `recycle-held-*` (consumers at `lr-move-worker.sh:460`, `lr-handoff.sh:1303`, `lr-fleet.sh:1393`). Static test D1-14 | No |
| F10 | The successor fails on the new account (trust dialog, MCP modal, auth) | Existing re-pick plumbing: `pre_trust` under the new config dir (`:20355-20357`); the engagement scan works across accounts. M5: 4 of 4 engaged | No |
| F11 | The held verdict flaps (`lifted` ↔ `claimed`) | D1 acts only at a recycle that is already happening. It adds no relaunch, so flapping cannot multiply relaunches | No |
| F12 | A desk recycle moves account | Announced by the RE-PICK line, and the same as today's exclusion and pressure re-picks. Desk-lane parity is sub-question 5 | No |
| F13 | Disk-row or `--assign` write fails | Advisory (`|| true`), as today | No |

**Invariant G1 holds.** Nothing in this decision reads the load average. Load can only stretch
the router read, which is bounded at 20 s by `--max-wait`, then at 25 s by the alarm, and which
falls back to today's behaviour.

### 6.6 Test plan

**Red controls, red before the fix.** Write these first and run them against pristine `main`.

| ID | Suite | Case | Red on main because |
|---|---|---|---|
| D1-1 | `handoff-recycle-repick.bats` | The 2026-10-19 next3 recycle. Fixture: the M3 ranking with `dispatch_floor=next3:on-pace:1.2 dispatch_held=next3 repick_held=on`. Expect stdout `next`, `--assign next --src recycle-repick`, stderr `held for new work`, and a row with `basis=held`, `held_token=on-pace` | Measured M3: today it stays |
| D1-2 | same | Shadow: `repick_held=shadow` gives empty stdout, no `--assign`, and a stay row `why=held-shadow best=next` | No stay row exists today |
| D1-10 | same | Test 30's last line `[ ! -e …handoffs.jsonl ]` becomes "a `recycle-repick-stay` row with `why=below-threshold`" | That assertion encodes the defect: "stays" was never on disk (axis-10 Q4). This edit is the cure, and it is named here so nobody reads it as weakening a test (lesson "DoD can demand what the cure removed") |
| D1-11 | same | `ROUTE_RC=3` stays, with a row `why=rank-unanswered rank_rc=3` | No row today |
| D1-12 | same | The stub log shows `--max-age 600` and `--max-wait 20` | Flags absent today |
| R-1 | `account-recovery-lane.bats` | `seed_snapshot "next2:100"` (next2 `claimed`): `rank_meta general` contains `dispatch_floor=next2:claimed:6.0 dispatch_held=next2 repick_held=on`. The existing pin `" repick_ratio=4 dispatch_floor="` (`:910`) still holds; the fable lane has both tokens; `--recovery` has neither | Tokens absent (M8) |
| R-2 | same (python `$LOAD`) | Precedence: env, then switch file, then SSOT, then default. Garbage reads `off`; an empty value is absent; the switch file sits under the fixture `$HOME` | Function absent |
| C-1 | `recycle-repick-held-contract.bats` (new) | Producer to consumer. The extracted `recycle_repick next2` runs against the **real** router (`CC_ACCOUNTS_BIN` = a wrapper that `exec`s `python3 $CA_BIN`, with `CC_ACCOUNTS_BIN_EXPLICIT=1`) on `seed_snapshot "next2:100"`. Expect `next4`, and the fixture `CC_ASSIGN_LOG` gains `next4 src=recycle-repick` | Tokens absent. This case also catches a token-name drift between the two files, which the stub suites cannot |

**Equivalence guards.** These are green on both arms. For each, the mutant it kills is named,
because only a mutant's death shows the guard has power (lesson "Green in both arms").

| ID | Case | Mutant it kills |
|---|---|---|
| D1-3 | `repick_held=off` stays, with a `held-mode-off` row | M-a: ignore the mode |
| D1-4 | No `repick_held` token stays | M-b: default `on` when the token is absent |
| D1-5 | `dispatch_held=next3,next,next2,next4` stays `held-everywhere` | M-c: drop the "line 1 is not held" check |
| D1-6 | `dispatch_held=-` stays `below-threshold`, with today's message | M-a |
| D1-7 | Prefix: `dispatch_held=next3`, incumbent `next`, line 1 `next2`: stays | M-d: substring membership |
| D1-8 | Incumbent held **and** outscored ≥4x moves with `basis=pressure` | M-e: test held before pressure (attribution) |
| D1-9 | Incumbent excluded and held moves with `basis=excluded` | M-f: held before exclusion |
| D1-13 | Static: the block's code (comments stripped) contains none of `on-pace\|claimed\|pace-unknown\|pace-stale\|level-stale\|hold-credits`. Written as `[ "$(… \| grep -cE …)" = 0 ]`, never a mid-test `! grep` (lesson "negated assertion dead unless final") | M-g: decide on the vocabulary instead of the router's set |
| D1-14 | Static: no `class:"recycle-held-` in the block | F9 |
| D1-15 | A held move in a dry run prints the move, charges nothing and records nothing | M-h: the dry-run gate dropped from `_rp_stay` |
| R-3 | `CC_ROUTE_DISPATCH_W_FLOOR=off`, with a cached row carrying a stray `thin_demoted:true`, gives `dispatch_held=-` | M-i: drop the floor guard |
| R-4 | No placement (next2 `lifted-first`) gives `dispatch_held=-` | M-j: `held` from `dispatch_floor` presence |

**How to run.**

- Every pre-existing case in both suites must still pass (30 in `handoff-recycle-repick.bats`
  today; measured 30/30 ok at `28b25a119`, §8).
- Run the D1 cases a second time with the block under `/bin/bash` 3.2, by parameterising
  `run_repick` on `RP_BASH`. Reason: lesson "Deployment interpreter ≠ yours". M3 already ran
  under 3.2.
- Run each mutant against the full section; record which test killed it.
- Assert the plan line `1..N` before reading a filtered result.

**Load.** D1 adds no load-dependent gate, so no B1 harness arm is needed. After deployment, the
`rank_s` and `rank_rc` columns of the new rows **are** the measurement of how often D1 is
reachable at 30-40/core. Join them on `ts` to the load ledger, so each reading stands beside its
load (lesson "Verify a cure under its load").

### 6.7 Rollout, verification and kill switch

1. The operator rules (§7).
2. Implement on an agent worktree branch and land it through the project `/ship`, under this
   repo's standing-land authorization. Set `REPICK_HELD_DEFAULT` (and the optional SSOT key) to
   the ruled mode.
3. Converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, under the
   standing-converge tier. Both files are per-file symlinks, so the next recycle and the next
   router call use the new code. No daemon reload is needed.
4. Check the declaration with a cache-only read, which never sweeps:
   `claude-accounts --max-wait 0 --rank general 2>&1 >/dev/null | grep -o 'dispatch_held=[^ ]* repick_held=[^ ]*'`
5. Watch:
   `jq -c 'select(.class=="recycle-repick" or .class=="recycle-repick-stay") | {ts,from,to,best,basis,why,rank_rc,rank_s,held_token}' ~/.claude/logs/handoffs.jsonl | tail -20`
6. **Success criterion: the next thin window.** next2 read 79% at 17:4xZ (M9), with its reset
   10-24 11:00Z. Inside that window, no `recycle-intent` row may land on an account that was in
   `dispatch_held`, except under a stay row whose `why` is `held-everywhere`, `rank-unanswered` or
   `held-mode-off`. At the wall, count the resident sessions whose last relaunch was a recycle
   after the account went thin. The target is 0.

**Kill switches, from fastest to narrowest:**

- Fleet-wide and immediate (the next recycle reads it): `printf 'off\n' > ~/.claude/state/repick-held`
- Shadow: `printf 'shadow\n' > ~/.claude/state/repick-held`
- Back to the SSOT and code default: `rm -f ~/.claude/state/repick-held`
- One process only: `CC_ROUTE_REPICK_HELD=off`
- Every re-pick, per process (existing): `CC_RECYCLE_REPICK=off`
- Durable: the SSOT `"REPICK_HELD": "off"`, through a land

### 6.8 Operator steps

The only operator step is the ruling, given as answers to the asks below. Nothing needs a
launchctl, a credential or a kitty restart. The switch-file commands in §6.7 are optional
overrides.

### 6.9 Estimated LOC (estimated, by component)

| Component | Lines |
|---|---|
| `bin/claude-accounts` | about 45 |
| `scripts/handoff-fire.sh` | about 110 changed or added, including comments |
| `handoff-recycle-repick.bats` | about 200 |
| `account-recovery-lane.bats` | about 60 |
| New contract suite | about 70 |
| `accounts.json` | 2 |
| `ACCOUNT_ROUTING_V2.md` | about 30 |
| **Total** | **about 520** (about 155 of it code) |

### 6.10 Dependencies on the other items

- **None blocking.**
- **B6-telemetry.** D1 implements B6's "stays row" sub-item, in the same function. B6 should drop
  that sub-item, or land after D1, to avoid a conflicting edit of `recycle_repick`. If B6 adds a
  `load1` field to these rows, it must be telemetry only (invariant G1).
- **D2-warning-band-shedding.** Should take its "held" input from this item's `dispatch_held`
  token rather than re-derive one. That way the recycle path and the shed controller cannot
  disagree about which accounts are reserved. D1 does not depend on D2.
- **B4-cheap-place.** Unrelated to `--rank`'s cost. `apply_burn`'s 19.3 MB re-parse, noted under
  B4, is what dominates M7; making it cheaper would only widen D1's margin under the 25 s alarm.
- **G2-self-recovery.** If G2 relaunches through `handoff-fire --recycle` with an explicit
  account, D1 does not touch it. If it ever uses the `auto` arm, D1 applies, which is the right
  rule there too.
- **No interaction** with B1, A6, B3, B2, B7, B5, C2, A7, B8 or C1.

### 6.11 Residual risks

- **Desk recycles follow the general lane**, not the desk lane, exactly as today's re-picks do
  (sub-question 5).
- **Fable recycles never re-pick.** A held Fable account keeps its recycles. Widening that needs
  the fable lane (`:16012-16015`).
- **The benefit figure rests on one incident** (n=1). The success criterion in §6.7 measures it.
- **A switch file is a new kind of router input.** That is why the operator is asked to approve
  it (ask 4).

---

## 7. Operator asks

1. **Ruling:** should a recycle re-pick leave an account the router lists in `dispatch_held` when
   line 1 is open? Recommended: **yes** (option B).
2. **Initial mode:** `on` (recommended) or `shadow` for N days. Shadow costs an estimated ~8-10
   avoided recoveries a week, and the cross-account mechanism is already proven 4 of 4 (M5).
3. **Target rule:** the router's line 1 whenever it is not held, including a `lifted-first`
   account (recommended), or roomy-only (option D).
4. **Approve the switch file** `~/.claude/state/repick-held` as the immediate fleet-wide kill, in
   addition to env and SSOT. If not approved, the kill is the SSOT through a land.
5. **Desk recycles:** confirm that they follow the general lane in D1, as today's exclusion and
   pressure re-picks do (recommended). Desk-lane parity would be a separate DEC-1-scope item.

## 8. Notes and deviations

- **All reads were read-only.** I typed into no pane, signalled no process, ran no launchctl and
  ran no `cc-lr` verb.
- **I did not run the live router** (`claude-accounts --rank`). Its write sites include a log
  append (`bin/claude-accounts:297-303`), so I relied on the logged rankings instead.
- **Scratch files all live under `/tmp/d1/`:** `join.py`, `windows.py`, `ctl/`, and a sandbox
  with symlinks to this worktree's `scripts/` and `bin/`.
- **Deviation:** one run of `tests/handoff-recycle-repick.bats` (30/30 ok, measured, at
  `28b25a119`, with `TMPDIR=/tmp/d1/tmp`) went through the `cc-bats` chokepoint, even though I
  invoked the Homebrew binary by path. `cc-bats` wrote a transient admission slot,
  `~/.claude/state/bats-roots.d/5247` (`started=2026-10-20T17:46:05Z cwd=/tmp/d1`). Its pid is
  dead, and `cc-bats`'s `roots_live()` reaps dead entries itself (`bin/cc-bats:602-609`), so I
  did not remove it. No further bats run was made. The red control M3 was run with plain
  `/bin/bash` and wrote only under `/tmp/d1/ctl`.

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20 ~18:00-18:25Z, against `28b25a119`. Read-only on the system. Every
run below used a fixture `$HOME` and fixture router files under `/tmp/d1rev/`; no bats run (cc-bats
writes a slot under `~/.claude/state`), no live router call, no pane touched. **Verdict:
NEEDS-CHANGES.** The consumer sketch is mechanically sound. But the trigger set, the time bound,
the staleness handling and the success criterion each have a defect that can strand quota or that
contradicts a stated guarantee.

### R.1 What was checked and holds

- **Citations.** Every file:line in §1-§6 was spot-read and matches, except one (R.3 item 10).
  This includes `handoff-fire.sh:15993-15998, 16004-16186, 16022, 16039, 16136-16141, 16161-16163,
  16432-16452, 15420-15421, 20355-20357`, `claude-accounts:171-173, 437-456, 3842-3866,
  3890-3891, 6770-6827, 6851-6882, 6860, 6920-6928, 8181-8202, 8267-8318, 11285-11289,
  11455-11531`, `account-recovery-lane.bats:44-49, 910` and `handoff-recycle-repick.bats:36, 386`.
- **The §6.3 sketch, applied literally to an extracted copy, works under bash 3.2 and 5.3.** I
  applied it to `/tmp/d1rev/blk/block-d1.sh` and ran it with `set -euo pipefail`. Under
  `/bin/bash` 3.2.57 and Homebrew bash 5.3.15, cases D1-1/2/3/4/5/7/11/15 and excluded+held give
  the outputs §6.6 expects (measured: `bash /tmp/d1rev/blk/cases.sh /bin/bash …`).
  - stdout stays clean.
  - The only `^}$` is the function's own.
  - `shellcheck -s bash` gives rc 0 with no findings.
  - The test-25 lint regex finds no `>= <digit>`.
- **M3 reproduced.** Today's block with the 18:36:54Z ranking and cur=next3 gives `♻ recycle stays
  on next3 — … does not beat its 0.000166 by the router's 4x threshold` and only `--rank general`
  in the stub log (measured).
- **The suite stub tolerates the new leading flags.** It tests `$1 = --assign`
  (`handoff-recycle-repick.bats:53`), and `called '--rank general'` is a `grep -F` substring.
- **The route-meta pins survive appending after `dispatch_floor=`.** Checked `:910, :913, :916`
  and `:947` (`' dispatch_floor=-( |$)'`). cc-route ignores unknown keys (`bin/cc-route:92-98`).
- **The router side is right.** `held` from `thin_demoted` on the `--rank` candidates gives
  `held=next2` for `seed_snapshot next2:100` and `held=-` with no placement, in both lanes
  (measured: `python3 /tmp/d1rev/held.py` on the replicated fixture).
- **No consumer misreads `recycle-repick-stay`.**
  - lr-handoff:1303, lr-fleet:1393 and lr-move-worker:460 use `startswith("recycle-held-")`.
  - settle.py:489 slices `class[13:]`, which gives `k-stay`, not a `RCY_HELD_SUB` key, and it
    also requires `.attempt`.
  - No production code matches `recycle-repick` outside handoff-fire (measured: `grep -rn` over
    bin/scripts/hooks).
  - Only `handoff-recycle-repick.bats` drives `recycle_repick` with `CC_ACCOUNTS_BIN_EXPLICIT=1`,
    so no other suite gains stay rows.
- **B6 defers the stays row to D1** (`B6-telemetry.md:816-817`). G2 does not touch the re-pick
  (`G2-self-recovery.md:993`).
- **The ledger counts are right.** 4 `recycle-repick` rows (all `basis=pressure`) and 40
  named-account `recycle-intent` rows (measured: `jq` over `~/.claude/logs/handoffs.jsonl`).

### R.2 Defects found (each refutes a specific claim in the packet)

**D-1. Strand mechanism: `claimed` is forecast to strand, D1 evicts its residents, and D1's own
move creates it.** Severity high. This refutes §3 "Strand cost: near zero … an account the
forecast says will strand is `lifted`, not held", §5.4 "the router self-corrects", and F6.

- **`claimed` means forecast to strand.** It is `spare >= need` (forecast-dead quota covers a
  fire) but `spare < need × (1 + k_placed)` (`claude-accounts:6814-6827`).
- **Any `--assign` creates a claim.** `k_placed` counts every source over
  `DISPATCH_CLAIM_TTL_MIN` = 300 min (`:4549-4556`), so `--assign … --src recycle-repick` places
  a 5-hour claim.
- **Measured on the replicated fixture (4 accounts, no placements, `/tmp/d1rev/run3.sh`):**
  - before: `dispatch_floor=next2:lifted-first:6.0`;
  - then one `--assign next2 --src recycle-repick` gives `assign rc=0`;
  - after: `dispatch_floor=next2:claimed:6.0`, and the order is `next4 next next3 next2`.
- **The loop under D1** (consequence by code read):
  1. A held-basis move from A lands on a promoted `lifted-first` account B, which is line 1 by
     design whenever the strand rescue fires. An ordinary fire onto B does the same.
  2. B turns `claimed` and enters `dispatch_held`.
  3. For up to 300 min, every resident session on B that recycles is moved off B, while B is
     forecast to leave ≥ need pp unused.
- **It is sticky.** spare uses `max(ewma, flat 24h pace)` (`:6820`), so removing burn shows up
  late. The claims hold for 5 h.
- **The design's own C-1 fixture is this case.** next2 is `claimed:6.0`, quiet at 94% with 13.2 h
  left, and C-1 asserts that the pane leaves it.
- **`flat` has the same problem.** With `CC_ROUTE_DISPATCH_STRAND=off` there is no forecast and
  every thin account is held, so the strand rescue's kill switch silently turns D1 into "leave
  every thin account". That is the 2026-10-09 failure (next2 stranding ~5pp under the flat floor)
  in the leave direction.
- **This breaks the operator ruling** "exhaust the week" (`claude-accounts:3890-3891`).

**D-2. Data-quality holds turn an unknown into a move, against the binding premise.** Severity
medium.

- F7 concedes that `pace-stale` appears "when sweeps stall (M6)", which is load-induced.
- The binding premise says an unknown is "unknown, retry, never a negative verdict".
- Moving a pane off an account because its pace reading is stale acts on the unknown as a
  negative verdict.
- For a recycle, "retry" is today's stay, with the decision re-taken at the next recycle.
- G1 ("nothing reads load") is literally true, but load reaches the decision through this input.

**D-3. The "bounded at 20 s, then at 25 s by the alarm" guarantee (§6.5 G1, F1-F2) is false on the
sweep path.** Severity medium.

- `--max-wait 20` arms `_arm_sweep_bound`. That does `setitimer(ITIMER_REAL, …)`, and its disarm
  does `setitimer(ITIMER_REAL, 0)` (`claude-accounts:8197-8202`). That is the same timer perl's
  `alarm 25` set before `exec`.
- `_arm_hold_ceiling` was already skipped because that alarm was pending (`:8228-8229`).
- **Measured:** `perl -e 'alarm 3; exec @ARGV' python3 -c '…setitimer(1.0); setitimer(0);
  sleep(5)…'` gives `survived past the 3 s perl alarm`, rc 0, 5.49 s wall.
- So after a won sweep that finishes inside 20 s, the remaining work runs under no timer at all:
  `apply_assignments`, `apply_burn` (the 19.3 MB parse), and scoring. That is about 14.6 s at
  40/core (M7's estimate), so about 35 s.
- Today's call (no `--max-wait`) keeps the perl alarm for its whole life.

**D-4. `--max-age 600` serves a cache that predates the incumbent's own reset.** Severity medium.

- The router refuses such a cache only for a `--src` account (`claude-accounts:7019-7044, 7072,
  11259-11273`). W6 resolution 11 built that for "moving work OFF" a source, which is what a
  recycle re-pick does.
- **Measured** (`/tmp/d1rev/run4.sh`, cache 300 s old, next2's 5h window rolled 60 s ago):
  - without `--src`, the cache is served (`next4 0.000463`);
  - with `--src next2`, the cache is refused (`… predates next2's session reset … refused`,
    `none`, rc 3).
- **The change widens staleness for all three arms, not only the held one.** The exclusion arm
  (`5h-cutoff`, `kmax-concurrency`) and the pressure arm move from a 90 s TTL to 600 s. F4 argues
  only the held verdict's staleness. `weekly_reset_h` is also as-of-sweep on a cache read
  (`:8373-8377`), so M10's "only the weekly level" is incomplete.

**D-5. The success criterion (§6.7.6) measures only the benefit side, and would flag correct
stays.**

- **No strand metric.** M4 (25/25 thin windows walled) was measured under status-quo routing,
  where recycles stayed. D1 changes the input M4 rests on, and the plan never measures the strand
  side again (lesson "Size refuted ≠ decision flipped").
- **Correct stays read as failures.**
  - A `top-pick` stay on a held incumbent is the "every routable account is held" case: the
    partition puts held last, `:6876-6882`. Prototype: `why=top-pick held_token=on-pace`.
  - A `declined-unmapped` stay is also legitimate.
  - The exception list covers neither.
- **`recycle-intent` is written before the holds.** It is emitted at `:19526`; the load hold is
  at `:19410` and the last-read hold at `:19401`. So it records an intended account, not a
  landing.

**D-6. A recycle held after the pre-pass leaves a 5-hour claim with no session behind it.**

- `--assign` runs inside `recycle_repick`, in the pre-pass at `:16445`. That is before
  `recycle_fire`'s last-read and load holds (`hf_recycle_hold`, `:3809`), and nothing voids it.
- `--unassign <id>` exists (`claude-accounts:4417-4424`).
- **This exists today, but D1 makes it bite.** Today's pressure targets are high-score accounts.
  D1's targets include `lifted-first` accounts, where one claim flips the verdict (D-1).
- **Frequency.** 27 `recycle-held-load` rows, all on 2026-10-18 (measured). Present-day frequency
  is unmeasured.

### R.3 Required changes

1. **Make the leave trigger a router-declared set that excludes `claimed` and `flat`.**
   - Keep `dispatch_held=` as the dispatch fact; D2 can use it.
   - Add a second route-meta token, e.g. `repick_leave=<accts>|-`. Compute it in
     `claude-accounts` from a router constant, e.g. `REPICK_LEAVE_VERDICTS = ("on-pace",
     "hold-credits")`, so the consumer still owns no vocabulary.
   - Have `recycle_repick` test membership in that token.
   - Correct the §3 strand bullet, §5.4 and F6.
   - Add guard **D1-16:** a `claimed` incumbent with an open line 1 stays, with a row
     `why=held-not-leave`. Its mutant is "leave on any `thin_demoted`".
   - Add router case **R-5:** `seed_snapshot next2:100` gives `dispatch_held=next2` but
     `repick_leave=-`.
2. **Treat data-quality holds as unknown.** For `pace-stale`, `pace-unknown` and `level-stale`,
   the pane stays, with a stay row `why=held-unknown`, per the binding premise. If the
   recommendation keeps moving on them, it must say so explicitly as an operator ask that
   overrides the premise for this case. F7 must stop calling the direction "safe".
3. **Bound the router call for real.**
   - Use `--max-wait 0 --max-age 600`: cache-only, never takes the lock, never sweeps, and arms no
     itimer, so perl's `alarm 25` stays intact.
   - With keepwarm every 180 s, a >600 s cache means keepwarm is down, and the recycle should not
     become the sweeper.
   - Otherwise, restate G1/F1/F2 as "≤20 s sweep + unbounded post-sweep compute (est. ~15 s at
     40/core)".
   - Update D1-12 to match.
4. **Pass `--src "$cur"` after the lane:** `--rank general --src "$cur"`. The kind is read
   positionally (`:11410-11411`), so `--src` must not sit between `--rank` and `general`.
   - Add a red case: a cache that predates cur's reset gives `rank-unanswered rank_rc=3`.
   - Extend F4 to the exclusion and pressure arms and to `weekly_reset_h`, citing the router's own
     0.8% (`:171-173`) for the target side.
5. **Rewrite the §6.7 success criterion.**
   - (a) Add a **strand-side stop rule.** For every thin window with D1 on, record the account's
     weekly % at reset. If any window ends with more than `DISPATCH_STRAND_PP` (4pp) unused while
     D1 moved recycles off it, flip the switch to `off` and reopen the ruling.
   - (b) Judge landings from the successor's account (`recycle-engaged`), not from
     `recycle-intent`.
   - (c) Either class a `top-pick` on an incumbent in the held set as `held-everywhere`, or add
     `top-pick` and `declined-unmapped` to the exception list.
   - Given D-1/D-2, reconsider `shadow` as the initial mode until (a) has one thin window of data.
     This is an operator call.
6. **Void the charge when a re-picked recycle is held.** Two options:
   - Give the assign an id (`--assign "$new" --src recycle-repick --id rp:<SID>:<epoch>`) and
     `--unassign` it in `hf_recycle_hold` when `ACCOUNT` came from a re-pick.
   - At minimum, join `recycle-repick` to `recycle-held-*` by `target_pane` and report the rate
     before turning it on.
7. **C-1 fixture.**
   - The new contract suite's `CA_CFG` must declare all four accounts.
     `account-recovery-lane.bats:83-86` declares only `next3`, so the real router refuses the
     charge. Measured: `--assign next4` gives `--assign requires an account name (next3; got
     'next4')`, rc 64, and nothing reaches `CC_ASSIGN_LOG`.
   - After change 1, seed the incumbent `on-pace` (a utilization series burning about 0.5 pp/h at
     94% with 13.2 h left), not `claimed`.
   - C-1 stays red before the fix: 0.000463/0.000307 = 1.51x < 4x (measured,
     `/tmp/d1rev/run1.sh`).
8. **Kill-switch precedence.** Env outranks the switch file, so `printf off > ~/.claude/state/
   repick-held` is not "fleet-wide" for a process that exports `CC_ROUTE_REPICK_HELD=on`. Either
   make the most restrictive present value win (off < shadow < on), or rank the file above env.
   R-2 must pin whichever is chosen.
9. **Keep today's decision trace when the held arm does not move.**
   - In the prototype, `repick_held=off` with a held incumbent overwrites `stay=below-threshold`
     with `held-mode-off` and drops today's "does not beat … 4x" stderr line (measured, case
     D1-3). So F3's "behaviour equals today's" is false on stderr and in the row.
   - Keep the pressure reason in its own field (e.g. `pressure=below-threshold`).
   - Add `rank_s` and `rank_rc` to the `recycle-repick` row too, or the reachability measurement
     in §6.6 sees only stays.
   - Label router rc 2 (`none`, nothing routable by policy) `rank-none`, not `rank-unanswered`.
10. **Citations and labels.**
    - The unquoted word-split is `bin/cc-route:92` (`for kv in $ROUTE_META`), not `:166`.
    - M3 and D1-1 are a **constructed** scenario: the logged 18:36:54Z recycle was next4 → next
      (`handoffs.jsonl`), so "the 2026-10-19 next3 recycle" should not be implied.
    - M1/M2 use weekly ≥90% as the proxy for thin. Whether next3 was *held* or *lifted* in that
      window is unverified, because `route.jsonl` carries no `dispatch_floor` (measured: `grep -c
      'dispatch_floor=' ~/.claude/route/route.jsonl` gives 0). The "3-4 avoided" estimate
      therefore assumes next3 was `on-pace`. That is plausible, since it walled 6.8 h after 92%,
      but it is a hypothesis.

### R.4 Conviction after review

**55% for the design as written. About 80% with changes 1-5** (estimated).

- The core rule, leaving an account whose own pace walls it (`on-pace`), is coherent and still
  catches the next3 incident (hypothesis: next3 was `on-pace`).
- Three things block it as written:
  - the trigger set includes `claimed`, which is a forecast-strand verdict that D1's own `--assign`
    creates;
  - it acts on load-induced unknowns;
  - its time bound and staleness claims do not hold.

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 18:00-18:20Z, against `28b25a119`. Load during the review was
`sysctl -n vm.loadavg` => `{ 210.50 230.67 223.13 }` at 18:05:33Z, falling to `{ 118.91 82.67
125.40 }` at 18:19:34Z. The lens: does D1 actually work at 15-40/core with every lane at PRI 31,
and does any new wait, bound or gate assume that load falls? Labels are as in this file:
*measured* names the command, *estimated* names the method, and *hypothesis* means unverified.

**Verdict: NEEDS-CHANGES. Adjusted conviction: 70%** (down from 85%).

- The core still holds. The decision reads no load. It fails soft to today's relaunch, and the
  cache-first read makes the router call cheaper than today's.
- Five changes are required (C1-C3 and C5 below are the ones that matter most):
  - The read as written loses its own hard bound on one path (C1).
  - It widens a pre-reset staleness window that the router already has a refusal for (C2).
  - Its efficacy above about 22/core is unmeasured, yet the plan says no load measurement is
    needed (C3).
  - Its success criterion passes even if every router read times out (C5).

### R0. What I verified and found true

- **The citations hold.** I checked them against the code at HEAD. The pieces checked:
  - `recycle_repick` is at `handoff-fire.sh:16004-16186`: the alarm at `:16039`, the early return
    at `:16043`, the pressure block at `:16100-16131`, DECLINED at `:16136-16141`, `--assign` at
    `:16161-16163` and the row at `:16174-16184`.
  - Its only call site is the `auto` arm (`:16437-16452`); the resume arm is at `:16432-16436`.
  - Router functions: `dispatch_floor_row` at `bin/claude-accounts:6770-6827`;
    `_dispatch_partition` at `:6851-6882`, with its early return at `:6860`; `ranked` at
    `:6920-6928`; `repick_ratio` at `:3842-3866`.
  - The route-meta `dispatch_floor=` token at `:11519-11525`, `get_data` at `:11285-11289`, the
    `--max-age` doc at `:171-173`, and `cache_grace_s` 600 at `accounts.json:26`.
  - The `recycle-held-` prefix readers at `lr-move-worker.sh:460`, `lr-handoff.sh:1303` and
    `lr-fleet.sh:1393`.
  - Minor drift: the adjacency pin is at `tests/account-recovery-lane.bats:909`, not `:910`.
- **The recycle path runs at PRI 31, nice 0.** The re-pick runs inside the session's own process
  tree: the PostToolUse hook `waiting-recycle.sh:1528` calls handoff-fire synchronously, and
  `/handoff` runs through the Bash tool. Nothing on these paths lowers priority:
  `grep -nE '\b(taskpolicy|nice -n|renice)\b'` over `hooks/waiting-recycle.sh`,
  `hooks/boundary-handoff.sh`, `scripts/handoff-fire.sh` and `bin/claude-accounts` gave no hits.
  Measured: `ps -axo pri,nice,comm` gave 27 `.bin/claude` and 6 `claude.exe` processes at 31/0.
  The only nice-5 claude processes are Claude Code's own `bg-pty-host` and `bg-spare` children.
  So M7's "priority-31 shell" matches the condition the re-pick runs in.
- **M1 reproduces.** `python3 -I /tmp/d1/join.py …` => `recycles with named account: 40  at
  weekly>=90%: 5`.
- **next3 really was held (`on-pace`) for all five recycles.**
  - The ledger shows next3 at 92% (19:35Z) rising to 100% (02:17Z) with its weekly reset at
    10-20 12:00Z. That is about 1.2 pp/h with 16 h left against 8 pp of headroom, so spare is 0
    and the verdict is `on-pace` (estimated with the `:6816-6818` formula).
  - Ledger command: a python read of `account-utilization.jsonl`, filtered to `acct=next3`.
  - The 18:36:54Z `recycle-repick` row ranks next3 last on a higher score than next4, which is
    the partition's demotion.
  - So D1 would have fired on all five, **provided the router answered**.
- **The five recycles all happened in the measured load regime.** `convoy-gauge.jsonl` load1
  nearest each `recycle-intent` (a python join, ±120 s) gives 15.1, 8.8, 10.0, 11.4 and
  21.8/core. So the incident that motivates D1 sits at or below M7's 22/core. It says nothing
  about 30-40/core.
- **The cache-first read is much cheaper than a sweep.** Measured with a write-denying sandbox
  (`sandbox-exec -f /tmp/rv-d1/ro.sb` denies every file write outside `/tmp/rv-d1`, so the
  router could append to nothing):
  - `claude-accounts --max-age 600 --max-wait 0 --rank general` => wall 9.81 s on the first
    call, then 0.70-0.77 s (5 calls) at load1 40-44, `cached=1 quota_age_s=128-132`.
  - Under `/usr/bin/time -p` => `user 0.54-0.58 sys 0.04` per call.
  - Today's sweep path, recomputed: `tail -400 accounts-keepwarm.out.log`, swept rows =>
    n 335, p50 27.4 s, p90 78.7 s, p99 125.7 s, max 149.2 s. 176 of 335 exceed 25 s.

### R1. Findings that refute or weaken the design

**R1.1 `--max-wait 20` removes the outer 25 s alarm on the won-sweep path, so the bound claimed
in F2 and G1 is false.**

- On macOS, perl's `alarm` and Python's `setitimer(ITIMER_REAL)` are the same per-process timer,
  and it survives `exec`. The two router functions interact with it like this:
  - `_arm_hold_ceiling` (`bin/claude-accounts:8205-8233`) skips itself because a timer is
    already pending.
  - `_arm_sweep_bound` (`:8181-8202`) then replaces the timer with `T0+20`. Its disarm calls
    `setitimer(ITIMER_REAL, 0)`, which leaves no timer at all.
  - Everything after a sweep that finishes inside its budget therefore runs with no alarm:
    `cache_commit`, then `mark_self`, `apply_assignments`, `apply_burn`, the ranking and the
    print.
- Measured with the router's real functions (module loaded under the sandbox, perl
  `alarm 4` outside):
  - `outer alarm left after import: 2.55`
  - `after router disarm: (0.0, 0.0)`
  - `SURVIVED 6s past the outer perl alarm 4`, rc=0
- Without `--max-wait`, `_arm_sweep_bound` is a no-op (`deadline is None`), so today's call keeps
  perl's 25 s as a hard bound throughout.
- The path is reached only when the cache is over 600 s old and the lock is free (keepwarm has
  failed for two or more ticks), so it is rare. But the flag adds no protection in exchange:
  - Its one benefit is a clean rc 3 instead of rc 142.
  - It cuts a won sweep's budget from about 25 s to about 18 s after Python start-up. At the
    measured sweep p50 of 27.4 s, nearly every such sweep is killed anyway, after spending four
    usage fetches and CPU on a loaded box.

**R1.2 A 600 s grace read without `--src "$cur"` can move a pane off an account whose window
just rolled.**

- `_cache_predates_reset` (`:7019-7044`) refuses a cache taken before a **source** account's 5h
  or weekly reset. It exists because of the 2026-09-30 incident, in which "a pre-reset cache
  moved a cohort OFF its source 5 s after the source had already rolled".
- `--rank … --src <acct>` enables the refusal (`:11262-11273`), and `--rank` reads it for
  nothing else.
- D1 makes 600 s the normal staleness for every recycle read; today's normal is the 90 s TTL.
  So for up to 10 minutes after the incumbent's own reset, the read can still show it as:
  - `5h-cutoff` or `weekly-exhausted`, which the existing exclusion arm acts on;
  - `on-pace` at 99%, which the new held arm acts on.
- In both cases the pane moves off an account that is now fresh: the wrong direction.
- F4 ("only the weekly level is stale … 10 min is negligible") ignores the one event at which
  the level jumps by about 100 pp.

**R1.3 Efficacy at 30-40/core is unmeasured, and the plan rules a measurement out.**

- §6.6 says "D1 adds no load-dependent gate, so no B1 harness arm is needed." That is right
  about the gate and wrong about efficacy. D1 acts only if a router call of about 0.6 s CPU
  (measured above) finishes inside a fixed 25 s alarm, on a box that is loaded permanently by
  design.
- The evidence for that is thin:
  - M7 is n=5 at 22/core (`git show -s 134000efe`: 6.33 4.74 8.09 2.10 3.37 s).
  - The 14.6 s figure at 40/core is a linear extrapolation of the p90 of five samples.
- Two other readings disagree with it:
  - **Measured.** keepwarm's own cache-served ticks run at PRI 31 under ProcessType Standard.
    They are heavier, because each renders 9 readouts and calls `apply_burn` twice
    (`_board_variants`, `:8015-8028`; `BOARD_LADDER` has 8 widths, `:8012`). Over the last 400
    ticks (about 20 h), the served-cache ones gave `n 65 min 962 p25 4424 p50 11973 p90 64323
    max 141784` ms (`tail -400 … | grep served-cache`). The all-history figure is p50 1.8 s and
    p99 79 s (n 4871). So cached router work on this box has a long tail at today's loads, which
    five samples cannot show.
  - **Estimated** (fair-share model: CPU × runnable per core). 0.6 s × 40 = 24 s, right at the
    alarm. The scheduler gives short-lived processes better than fair share (M7's wall/CPU ratio
    was 3.5-13.5 at 22/core), so this is a ceiling, not a forecast.
- **Hypothesis:** at 30-40/core a material share of D1's reads return rc 142, so D1 does least
  exactly when the wall cohorts are largest.

**R1.4 "The next chance is the pane's next recycle" (F1) usually comes after the wall.**

- Measured: per-pane gaps between consecutive ordinary (named-account) `recycle-intent` rows in
  `handoffs.jsonl` were n 9 gaps over 8 panes: min 2.87 h, p25 9.45 h, **p50 16.28 h**, p75
  17.44 h, max 30.56 h. The 2.4-day window censors longer gaps; 22 of the 30 panes recycled only
  once in it.
- M4's median from 90% to the wall is 11.3 h.
- So a timed-out D1 decision is, in effect, final for that thin window. The pane goes back onto
  the held account and is usually still there at the wall.
- That is in tension with REPORT §5 G2, "our timeout is never a verdict … retried at a different
  moment". D1 is not on the recovery rail, so G2 does not strictly bind it. But the design should
  either give the decision a second chance or have the operator accept explicitly that it gets
  none.

**R1.5 The success criterion (§6.7 step 6) passes trivially under load.**

- `rank-unanswered` is a permitted exception. So with every D1 read timing out, no
  `recycle-intent` would "violate" the first clause.
- In §6.3 the `rank-unanswered` row also lumps three different outcomes under one `why`:
  - rc 2: the router answered, by policy, that nothing is routable;
  - rc 3: data unavailable;
  - rc 142: our own alarm.
- The timeout share, the one number that measures D1 under load, is therefore polluted.

**R1.6 Minor.**

- **§6.7 step 4's check reads with the default 90 s TTL.** `claude-accounts --max-wait 0 --rank
  general` exits 3 whenever the cache is older than 90 s, which by M6's model is about half of
  each 180 s keepwarm cycle. It needs `--max-age 600` to check the declaration reliably.
- **The move path's `--assign` call has no bound.** It is a second Python start with no alarm
  (`:16161-16163`); only its ledger lock is bounded, at 5 s (`append_assignments`). Importing the
  router module alone took 1.45 s at about 12/core (measured: the perl-alarm remainder 4 → 2.55
  above). D1 runs this call on more recycles than today.
- **D1 is not a term of REPORT §5's G bound.** Its benefit is a smaller wall cohort (estimated 3
  of 9 at the 10-20 wall, n=1). It leaves attempt latency for the sessions that do wall
  unchanged, and the design should say so in §6.5.

### R2. Required changes

- **C1.** In §6.3, replace `--max-wait 20` with `--max-wait 0`. Dropping `--max-wait` entirely
  is also acceptable.
  - `--max-wait 0` is cache-only: an immediate rc 3 when no cache of 600 s or less exists, no
    lock wait and no doomed sweep on a loaded box (`:8241-8259`). It also sets
    `want_heal=False`, so a `--no-heal` cache from cc-relogin with an errored row is still
    served, where today's call would sweep.
  - Fix F2 and the G1 paragraph to state the true bound: perl's 25 s, which is untouched once no
    `_arm_sweep_bound` runs.
  - D1-12 pins the final argv.
  - Alternative: fix `_arm_sweep_bound`'s disarm so it restores the inherited timer's remainder,
    with a router test. That would also protect any future perl-wrapped `--max-wait N` caller.
- **C2.** Add `--src "$cur"` to the read.
  - Red case (contract suite C-1 style): a seeded cache whose incumbent `session_reset_at` or
    `weekly_reset_at` falls between the cache `ts` and now. Expect no move, no `--assign`, and a
    stay row `rank_rc=3`.
  - Note in F4 that the reset boundary is the one event at which a 10-minute-old level is wrong
    by about 100 pp.
- **C3.** Replace "no B1 harness arm is needed" with a measurement taken before the operator
  rules on the mode.
  - Take n≥30 timed runs of the exact final argv from a PRI-31, nice-0 shell at load1 ≥300.
    Use the B1 harness, or the write-denying sandbox read used here.
  - Report p50, p90 and p99 against the 25 s alarm.
  - If p99 is at or above about 20 s, C4(b) becomes mandatory.
- **C4.** Specify what happens on a timeout. Pick one and write it into §6.3 and §6.5 F1:
  - (a) A new operator ask 6: "a recycle whose router read times out stays for the rest of the
    thin window". Quote R1.4's 16.3 h against 11.3 h.
  - (b) A G1-clean second chance, on rc 142 only, with no load read. Either:
    - one retry under a longer alarm (45 s, the wave-5 pattern of `134000efe`). Worst-case pane
      hold 70 s, within the 600 s default command-hook timeout on PostToolUse
      (https://code.claude.com/docs/en/hooks); `waiting-recycle.sh` sets none, as read from
      `~/.claude/settings.json`;
    - or a last-good `--rank general` answer (stdout plus route-meta) of 600 s or less, which
      keepwarm already has the rows to publish each tick, with the same `--src` reset refusal
      applied.
- **C5.** Fix the stay-row taxonomy and the success criterion.
  - Split rc 2 into `nothing-routable` (a policy answer). Keep `rank-unanswered` for rc 142 and
    rc 3, and record the router call's own duration as `rank_s`, not the function's.
  - D1-11 grows to rc 142, 3 and 2.
  - §6.7 step 6 gains a quantitative clause: among recycles whose incumbent was held, the
    `rank-unanswered` share, binned by load1/core from a ts join to `convoy-gauge.jsonl`, stays
    at or below a stated X% (suggested 10%) at 30-40/core. Above it, C4(b) is triggered.
  - State in §6.5 that D1 is not a term of the G bound.
- **C6 (minor).** §6.7 step 4 reads `claude-accounts --max-age 600 --max-wait 0 --rank general`.
- **C7 (recommended).** Put the `--assign` charge under the same perl alarm, or detach it. It is
  advisory by its own comment.

### R3. What would move my conviction

- **Up to about 85%:**
  - C3's n≥30 run at 30-40/core shows p99 well under 25 s;
  - C1 and C2 land;
  - C4 is chosen explicitly.
- **Down below 60%:**
  - C3 shows p90 at or above 20 s at 30-40/core, with no C4(b);
  - or the first live thin window shows `rank-unanswered` as the dominant stay reason among held
    incumbents.

### R4. Reviewer's own runs (read-only)

- No pane input, no signals, no launchctl, no `cc-lr` verbs and no live router run outside the
  write-denying sandbox.
- All scratch files are under `/tmp/rv-d1/`: `ro.sb` and the `out.N`/`err.N` captures.
- The only file edited is this one, by appending this section.
