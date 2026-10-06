# R7: what the suites pin about wall wording and precision, plus the 06:01:45Z control

Worktree `sessionstart-readout` @ `b87e6da64`. Read-only: no tracked file was edited. Scratch artefacts are all under `/tmp/ssr-research/` (`r7-*`).

## 0. Bottom line

- **Every assertion on wall wording or precision lives in `tests/claude-accounts-wire-truth.bats`**, in tests W-6, W-9 and the second W-10, plus one `_wire_note` pin in `tests/claude-accounts-freshness.bats` F-7. `claude-accounts-core.bats` and `accounts-board.bats` pin no wall wording and no tenths (grep receipts in §1.3).
- **Five assertions pin the defect itself** and must be edited, not loosened: `wire-truth.bats:206` ("says 99.0% used"), `:207` ("still accepts work"), `:209` ("| 99.0% |"), `:341` (" 99.6%" in the board row) and `:357-358` (`pct_text(99.6, False) == "99.6%"`).
- **The ruling pins must stay as they are**: the bar sliver `:339` and `:354`, solid only when refused `:338` `:355` `:347`, half height when unconfirmed `:344` `:356`, "100%" only on a refusal `:341b` `:344` `:347`, and the orange/red/gray mapping `:359-360`.
- **Measured: the drafted control W-11 fails on HEAD with 10 of its 15 checks and passes on a minimal sketch fix.** Two mutants (a full bar, red instead of orange) each kill it (§4).
- **Measured: in the 4138 recorded wire values, no value has more than 2 decimals.** The `0.996` in the W-10 fixture (`:336`) is a value the server has never sent. That three-decimal fixture is what lets `pct_text` print a meaningful-looking `99.6%`.

## 1. Assertions touching wall wording or precision

Renderer map (all in `bin/claude-accounts`):
- `board_eff` at :6326 floors the wire value to a tenth and caps it at 99.9.
- `pct_text` at :6360 prints `f"{v:.1f}%"` when `exhausted is False and v>=99`.
- `pct_rgb` is at :6369.
- `board_bar` at :6391 keeps the last cell open below 100.
- `_bpct` at :6431 is the narrow percent cell; `pctc` at :6566-6579 is the wide percent cell.
- The wall note at :6738-6753 is shared by both surfaces.
- `_wire_note` is at :6098 and `_plain_status` at :6109.

### 1.1 `tests/claude-accounts-wire-truth.bats` (11 tests, plan `1..11`, measured `cc-bats tests/claude-accounts-wire-truth.bats`)

| file:line | test | asserted string / predicate | renderer path | verdict for the fix |
|---|---|---|---|---|
| :104 | W-1 | `abs(weekly_headroom(r) - 0.01) < 1e-9` (wire 0.99) | `weekly_headroom` :1358 (routing, not text) | keep; changes only if R6 changes routing |
| :105-108 | W-1 | `_excluded is None`, `score_general` reason None, interactive None | router | keep (routing, out of R7 scope) |
| :146, :161-166 | W-3/W-4 | no probe below `WIRE_NEAR_WALL`; `wire_wanted` gate; `CC_ACCOUNTS_WIRE=off` kill switch | `wire_wanted` :1338 | keep (hard constraint: wire reads gated) |
| **:206** | W-6 | `"is **not out of weekly quota**" in allowed and "says 99.0% used" in allowed` | wide `render_readout` → note :6745-6750 → `pct_text(*board_eff)` | **EDIT**: "99.0%" is the defect; keep or replace the lead phrase |
| **:207** | W-6 | `"still accepts work" in allowed` | note :6748 | **EDIT**: present tense without age/load is defect 2 |
| **:209** | W-6 | `"\| 99.0% \|" in row` (wide table weekly cell) | `pctc` :6572-6574 → `pct_text` | **EDIT** to the bound (e.g. `"\| ≥99% \|"`) |
| :212 | W-6 | `"is **out of weekly quota**, confirmed by Anthropic" in rejected` | note :6742 | keep |
| :214 | W-6 | `"shows 100% weekly, **not confirmed**"` and `"rounds up"` | note :6751 | keep |
| :216 | W-6 | no `ʷ`; **no word `wire`** except `--wire` | whole readout | keep. **Constrains new wording**: "wire read 79 s ago" would fail; say "server read" |
| :217 | W-6 | `allowed != rejected != blind` | whole readout | keep |
| :241 | W-9 | no `ʷ`, no `"rate-limit headers"` | wide readout | keep (constrains wording) |
| :242 | W-9 | `"not out of weekly quota" in marked` | note :6746 | keep, or edit together with :350 if the lead phrase changes |
| :244 | W-9 | away from the wall: no `ʷ`, `"weekly quota"`, `"not confirmed"` | note gating | keep. Age/load text must not leak to rows away from the wall |
| :278 | W-8 | series row has `wire_7d_util == 0.99`, `wire_7d_status == "allowed_warning"` | `record_utilization` :5486 | keep; the control's replay depends on this flat shape |
| :338 | W-10 (board) | refused: `"▆▆▆▆▆▆▆▆"` and `"100%"` | `board_bar(100,True)`, `pct_text` | **keep: ruling** |
| :339 | W-10 (board) | allowed 0.996: `"▆▆▆▆▆▆▆▁"` ("a spendable bar must not read full") | `board_bar` :6416-6417 | **keep: ruling** (no full red bar for a spendable last 1%) |
| **:341** | W-10 (board) | `" 99.6%" in row and "100%" not in row` | `_bpct` → `pct_text` | **EDIT** the first half to the bound; keep `"100%" not in row` (ruling) |
| :344-345 | W-10 (board) | unconfirmed: `"▄▄▄▄▄▄▄▄"`, `"≥99%"`, no `"100%"` | `board_bar(100,None)`, `pct_text(100,None)` | keep: ruling. Already pins `≥99%`, for the gray state |
| :347 | W-10 (board) | refused row: no `▄`, `" 100%"` | bar + cell | keep |
| :349 | W-10 (board) | `"next3 is out of weekly quota, confirmed by Anthropic"` | note | keep |
| :350 | W-10 (board) | `"next3 is not out of weekly quota"` | note | keep, or edit together with :242 |
| :352 | W-10 (board) | no `ʷ` / `"rate-limit headers"` | narrow | keep |
| :354-356 | W-10 (board) | `board_bar(94.0)=="▆▆▆▆▆▆▆▁"`, `board_bar(100,True)` solid, `board_bar(100)` half | `board_bar` | **keep: ruling** |
| **:357-358** | W-10 (board) | `(pct_text(100,True), pct_text(99.6,False), pct_text(100,None)) == ("100%","99.6%","≥99%")` | `pct_text` | **EDIT the middle element** (tenths at the wall) |
| :359-360 | W-10 (board) | `pct_rgb(100,True)==RED`, `pct_rgb(99.6,False)==NEAR_WALL_RGB`, `pct_rgb(100,None)==GRAY` | `pct_rgb` :6369 | **keep: ruling** (orange near wall) |

`NEAR_WALL` / `WIRE_NEAR_WALL` appear only at :146, :155, :159 (the gate) and `NEAR_WALL_RGB` only at :359. No test asserts a `.1f` format string directly; tenths are pinned only through the literals `99.0%` (:206, :209) and `99.6%` (:341, :358).

### 1.2 `tests/claude-accounts-freshness.bats` (7 tests)

| file:line | test | asserted | renderer | verdict |
|---|---|---|---|---|
| :285-286 | F-7 | board contains `"server reads 5-hour 1% (accepting work), weekly 0% (accepting work)"` | `_wire_note` :6098 (`{w[k]*100:.0f}%`) + `_plain_status` :6109 | Untouched by a `pct_text`/note-only fix. **Breaks if the fix extends the bound/age wording to `_wire_note`** (the throttled-substitute path, which would print the incident row as "weekly 99% (accepting work, near the limit)", a point value in the present tense, same defect class; R6 territory) |
| :287-288 | F-7 | board row: `"100%" not in row and " 0%" in row` | `_bpct` | keep |

### 1.3 `claude-accounts-core.bats` (95 tests) and `accounts-board.bats` (33 tests): no wall-wording pins

- **Measured, by grep:** `grep -n -E '99\.0%|99\.6%|still accepts|of the week left|≥99%|NEAR_WALL|board_eff|pct_text|pct_rgb|board_bar|not out of|accepting work'` returns no hit in either file. Across `tests/`, `bin/`, `hooks/` and `commands/`, the only test file hit is `wire-truth.bats`.
- **Core pins next to this area, all to keep:**
  - `:163` asserts `score_general(row(weekly_pct=100))` gives `"weekly-exhausted"` (no wire, routing).
  - `:2058` and `:2065-2069` pin `pace_line` wording: `"⚠ WALL"` absent mid-week, and `"1.08× burn"` with `"⚠ WALL trajectory"` in the last day. That matters only if the fix moves the burn ratio into the wall note: reuse `pace_line`'s figure, do not re-derive it.
- **`accounts-board.bats`:**
  - The hook tests (1-14) treat the board as opaque text and so cover no wall wording.
  - Test 15 / `WIDTH_CHECK` (:383-390) caps each line at 76 cells, but its `NARROW_FIXTURE` (:342-356) has no account at the wall. **So no test width-checks a wall note today.** The control adds that check.
  - Test 17 pins `"11%*"`.

## 2. How these suites feed a row into the renderer

| mechanism | where | what it gives | limits for this control |
|---|---|---|---|
| `setup()` hermetic config: scratch `accounts.json` with every endpoint at `http://127.0.0.1:9/never`, `cache_file` in `BATS_TEST_TMPDIR`, one account `next3` | wire-truth :21-59; freshness :14-; core :16- | `cfg`, `CACHE`, plus env `CLAUDE_ACCOUNTS_JSON`, `CLAUDE_ACCOUNTS_LASTGOOD`, `CC_UTIL_LOG`, `CC_ASSIGN_LOG`, `CC_ROUTE_RECORDS_DIR`, `CC_FIRE_CAPACITY_GATE=off`, `CC_FIRE_HEADROOM_GATE=off`, `HOME` → tmp | none |
| `$LOAD` prelude: imports `bin/claude-accounts` as module `ca` via `SourceFileLoader`, redirects `ca.LOG_PATH`/`LASTGOOD_PATH` | wire-truth :61-89; freshness :55-; core :75- | direct calls to `ca.readout_lines` / `ca.render_readout` / `ca.board_eff` / `ca.pct_text` | none |
| `probe(lim, wire)`: stubs `concurrency`, `read_creds`, `fetch_usage`, `fetch_wire_limits` (records CALLS), returns `ca.collect(cfg, no_heal=True)[0]` | wire-truth :77-88; freshness :72-83 (`probe(status, lim, wire)`) | a real `collect()`-shaped row | **pins `concurrency` → `{"next3": 0}` (k=0), and `limits()` carries `resets_at: None`**, so it cannot express k=11 or the 5 h 58 m countdown. The control builds the row directly instead |
| `row(**kw)` dict builder + `READOUT` (`rd()`, `acctrow()`) on the wide renderer | core :89, :1304-1319 | synthetic rows for the router and the wide table | wide only |
| cache JSON fixture + CLI (`--route`) | core :720-730 | end-to-end through `get_data` | no wire field |
| `NARROW_FIXTURE` source patch at the anchor `rows, wj, cached, prev = get_data(...)`, run by `render_narrow --readout --narrow` | board :342-370 | end-to-end narrow CLI | it is a source-text anchor (rules: "Control anchors on source text") |
| `CC_ACCOUNTS_BOARD` file + `mk_board` / `age_board` | board :31-50 | hook-only tests | the board is opaque text |
| `CC_BOARD_COLOR=off` | wire-truth :325 | SGR-free text | needed to match plain strings |
| `_quota_age_s(cfg)` reads the cache JSON's own `ts` field, never an mtime | bin :2687-2696 | a deterministic "read age" | the control writes `{"ts": now-79}` to `cfg["cache_file"]` |

**Read-age source (reasoned).** On the normal sweep path a wire read carries no timestamp of its own:
- `wire_at` is set only in `apply_wire_substitute` (bin :1961);
- the `read_at`/`at` reader at :5056 reads fields that no writer sets on the normal path.

So today the only age available is the sweep age, which comes from `_quota_age_s` through the cache `ts`. In `readout_lines` it is computed only inside `if narrow:` (:6582), so the wide path and the note must compute it themselves. The control fixes the cache `ts` and does not set `wire_at`, so either source the fix chooses reads 79 s.

## 3. The control test (drafted; lands as `W-11` in `tests/claude-accounts-wire-truth.bats`, after :364)

- The fixture row is the **verbatim** line 44578 of `~/.claude/logs/account-utilization.jsonl`. It was extracted with `grep '"ts":"2026-10-06T06:01:45.738874+00:00","acct":"next3"'` into `/tmp/ssr-research/r7-incident-row.json`, sha256 `531ea536…446c`.
- The row contains no apostrophe, so it is safe inside the single-quoted `-c` body (rules: "Stub quoting fails open"; this draft hit that trap once on a comment, and the result was a `bats-gather-tests` syntax error).
- Full file: `/tmp/ssr-research/r7-control-fragment.bats`.

```bash
# ---- W-11: CONTROL — the 2026-10-06 incident, replayed from the series verbatim ---------------
# 06:01:45Z the sweep recorded next3 at endpoint 100 / wire 0.99 allowed_warning with 11 live
# sessions; the board printed "99.0%" and "still accepts work (about 1% of the week left, roughly
# 5% of one 5-hour window)"; 79 s later a session on next3 got "You've hit your weekly limit".
# The wire arrives as TWO decimals, so it supports "99% or more", never a tenth, and the headroom
# it implies is an upper bound that can be zero. A snapshot is not a present tense: the sentence
# must carry the read's age and the load on the account. FAILS PRE-FIX on every check below
# except the bar/colour ones, which pin the 2026-10-01/03 rulings this fix must not revert.

@test "W-11: CONTROL replay of the 06:01:45Z next3 row: a bound not a tenth, no headroom figure, age and load in the note" {
  run env CC_BOARD_COLOR=off python3 -c "$LOAD"'
import re, time
from datetime import datetime, timezone, timedelta
# VERBATIM, ~/.claude/logs/account-utilization.jsonl, the next3 row at ts 2026-10-06T06:01:45.
REC = json.loads(r"""{"ts":"2026-10-06T06:01:45.738874+00:00","acct":"next3","k":11,"k_work":4,"k_src":"work","session_pct":7,"weekly_pct":100,"fable_pct":3,"session_reset_at":"2026-10-06T07:50:00.443077+00:00","weekly_reset_at":"2026-10-06T12:00:00.443099+00:00","wire_5h_util":0.06,"wire_7d_util":0.99,"wire_5h_status":"allowed","wire_7d_status":"allowed_warning","credits_on":false,"credits_used":0.0,"auth":"ok","stale":false}""")
AGE_S = 79                      # read -> rejection gap measured in the incident
P = datetime.fromisoformat
# The series row is flat; the renderer takes the collect() shape. Rebuild it the way
# record_utilization flattened it (wire_* -> wire{}), and rebase every absolute stamp so the read
# is AGE_S old NOW while each countdown stays what it was at 06:01:45Z.
shift = (datetime.now(timezone.utc) - timedelta(seconds=AGE_S)) - P(REC["ts"])
r = {k: REC[k] for k in ("acct", "k", "k_work", "session_pct", "weekly_pct", "fable_pct",
                         "credits_on", "credits_used", "auth")}
r.update(session_reset_at=(P(REC["session_reset_at"]) + shift).isoformat(),
         weekly_reset_at=(P(REC["weekly_reset_at"]) + shift).isoformat(),
         session_reset_h=(P(REC["session_reset_at"]) - P(REC["ts"])).total_seconds() / 3600,
         weekly_reset_h=(P(REC["weekly_reset_at"]) - P(REC["ts"])).total_seconds() / 3600,
         wire={w: REC["wire_" + w] for w in ("5h_util", "7d_util", "5h_status", "7d_status")})
# The sweep age the board states comes from the cache ts field (_quota_age_s), never an mtime.
json.dump({"ts": time.time() - AGE_S, "rows": []}, open(cfg["cache_file"], "w"))
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
v, ex = ca.board_eff(r, "weekly_pct")
assert ex is False, "the replay must land in the nearly-out state, not refused/unconfirmed: %r" % ((v, ex),)
bad = []
for narrow in (True, False):
    surf = "board" if narrow else "readout"
    out = "\n".join(ca.readout_lines([r], cfg, WIN_OPEN, True, narrow=narrow))
    lines = out.splitlines()
    ri = next(i for i, l in enumerate(lines) if "next3" in l and ("▆" in l or "▄" in l or l.startswith("|")))
    row = lines[ri]
    # the note: first later line naming next3 and the week, plus its indented continuation lines
    ni = next(i for i in range(ri + 1, len(lines)) if "next3" in lines[i] and "week" in lines[i])
    nl, j = [lines[ni]], ni + 1
    while j < len(lines) and lines[j].startswith("   ") and narrow:
        nl.append(lines[j]); j += 1
    note = " ".join(" ".join(nl).split())
    # (1) precision: a two-decimal read never prints a tenth, anywhere on either surface
    if re.search(r"\b99\.\d%", out): bad.append((surf, "tenth printed", re.findall(r"\b99\.\d%", out)))
    # (2) the cell is a bound, and only a server-confirmed refusal may print 100%
    if not re.search(r"(≥ ?99%|99%\+)", row): bad.append((surf, "cell is not a bound", row))
    if "100%" in row: bad.append((surf, "100% on a spendable row", row))
    # (3) no headroom figure derived from the two-decimal reading
    if re.search(r"\d+% of (the week|one 5-hour window)", note):
        bad.append((surf, "headroom figure in note", note))
    # (4) the read carries its age (79 s) and the load on the account (11 live sessions)
    # 79..89 s: tolerates a loaded box between the cache write and the render (int-truncated age)
    if not re.search(r"\b(79|8\d) ?s(ec(ond)?s?)?\b|\b1 ?m(in(ute)?)?\b", note):
        bad.append((surf, "no read age", note))
    if not re.search(r"\b11\b[^.;]{0,20}session", note): bad.append((surf, "no live-session count", note))
    # (5) RULINGS 2026-10-01/03 (must hold before AND after): inline, sliver open, not red, not half-height
    if narrow and ("▆▆▆▆▆▆▆▁" not in row or "▄" in row):
        bad.append((surf, "bar: spendable last cell must stay open and not read unconfirmed", row))
    # (6) the longer note still fits the 76-cell board budget (suite test 15 never renders a wall note)
    import unicodedata
    cells = lambda s: sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
    if narrow and any(cells(l) > 76 for l in lines):
        bad.append((surf, "line over 76 cells", [l for l in lines if cells(l) > 76]))
if ca.pct_rgb(v, ex) != ca.NEAR_WALL_RGB: bad.append(("colour", "near-wall orange lost", ca.pct_rgb(v, ex)))
for b in bad: print("FAIL", b)
assert not bad, "%d checks failed" % len(bad)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
```

Design choices:
- **The row is built directly rather than through `probe()`.** `probe` hard-codes `concurrency → 0` and reset stamps of `None` (wire-truth :73-80), so it cannot carry k=11 or the 5.97 h countdown the incident board showed (`5h 58m`, measured in the replay).
- **Stamps are rebased, the clock is not frozen.** `readout_lines` calls `datetime.now()` (header) and absolute-stamp helpers. Shifting every stamp by `now − AGE_S − ts` keeps the relative facts identical with no monkeypatching.
- **Failures are collected, not raised one at a time.** A pre-fix run then prints every failing check, which is the red receipt.
- **The bound regex accepts `≥99%` or `99%+`**, and the age regex accepts 79-89 s or "1 min", so the control fixes what the cell and note must mean, not one exact sentence. The note locator expects a note line after the table row that names `next3` and "week"; if the fix moves age and load inline and drops the note, retarget it.

## 4. Proof that it fails pre-fix and passes post-fix (measured)

Both arms were run as a copy of `wire-truth.bats` with W-11 appended (`/tmp/ssr-research/r7-{head,sketch}/tests/wt-plus-control.bats`). The setup there derives `REPO` from the test file's directory, so each scratch tree carries its own `bin/claude-accounts`; `git show HEAD:bin/claude-accounts` gives the HEAD copy.

| arm | renderer | result (`cc-bats r7-*/tests/wt-plus-control.bats`) |
|---|---|---|
| HEAD | `git show HEAD:bin/claude-accounts` | plan `1..12`; tests 1-11 ok; **`not ok 12 W-11`, `AssertionError: 10 checks failed`**. Failing checks, on both surfaces: tenth printed `['99.0%','99.0%']`; cell not a bound (`➤  next3  11  6%  99.0% ▆▆▆▆▆▆▆▁  3%  5h 58m  —`); headroom figure in the note; no read age; no live-session count. Checks (5), (6) and colour pass, as designed |
| sketch fix (`/tmp/ssr-research/r7-sketch/make-sketch.py`: `pct_text` gives `≥99%` when `exhausted is False and v>=99`; note gives "Anthropic's server read ≥99% used 79s ago and was still accepting work then, with 11 live sessions on it; the reading is too coarse to say how much is left") | patched copy | **`ok 12 W-11`** |
| mutant: `board_bar` cap removed (full bar at 99) | sketch + mutation | `not ok`: `FAIL ('board', 'bar: spendable last cell must stay open…', '… ≥99% ▆▆▆▆▆▆▆▆ …')` |
| mutant: `pct_rgb` near-wall gives `RED` | sketch + mutation | `not ok`: `FAIL ('colour', 'near-wall orange lost', (224, 90, 90))` |
| mutant: `NARROW_W = 200` (the note is no longer wrapped to the board budget) | sketch + mutation | `1 checks failed`: `FAIL ('board', 'line over 76 cells', …)` |

**Which runs were under bats and which were not:**
- HEAD and sketch were run under `cc-bats` with checks (1) to (5).
- Check (6) and the widened age regex were added afterwards. By then `cc-bats` refused at load ~90 (`uptime`: `load averages: 94.94`; `cc-bats: REFUSED … nothing ran`).
- So the **final fragment** was verified by running the same python body outside bats with the identical `setup()` environment (`/tmp/ssr-research/r7-direct.sh <arm>`):
  - HEAD: `AssertionError: 10 checks failed`, the same 10 failures as above.
  - Sketch: `OK`.
  - Each of the three mutants: `1 checks failed`.
- It still needs one admitted `cc-bats` run before landing.

Checks (5), (6) and the colour check pass in both arms, so on their own they are equivalence guards. Their power comes only from the three mutant deaths (rules: "Green in both arms").

What the replay rendered on HEAD (measured with `/tmp/ssr-research/r7-probe.sh`, `CC_BOARD_COLOR=off`):

```
CLAUDE MAX · Tue 01:19 · cached 79s
➤  next3           11     6%  99.0% ▆▆▆▆▆▆▆▁     3%  5h 58m   —
next3 is not out of weekly quota: the meter shows 100%, but Anthropic's
   server says 99.0% used and still accepts work (about 1% of the week left,
   roughly 5% of one 5-hour window)
➤ desk (bare claude) → next3
```

This is byte-for-byte the incident sentence. The same render also shows that **the desk still routes bare `claude` to next3** (input for R6), and the wide table prints `| 99.0% |` with the same note.

**Gate procedure for the implementer (the order is the proof):**
1. Add W-11 to `tests/claude-accounts-wire-truth.bats` first and commit nothing yet.
2. Run `cc-bats -f W-11 tests/claude-accounts-wire-truth.bats` against the unmodified `bin/claude-accounts`: expect `not ok 1` with 10 `FAIL` lines.
3. Apply the fix, then run the full gate.

The `wire-truth` plan becomes `1..12`. The four-suite gate's `@test` count goes from 146 to **147** (estimated from `grep -c '^@test'`: 33+7+11+95).

Two cautions from the rules:
- `cc-bats` **refuses** under load (`REFUSED … nothing ran`, measured twice during this research). That is a deferral, not a result; retry it, and never read it as green.
- Count `ok` + `not ok` against N before trusting a filtered run.

## 5. Existing pins the sketch fix broke (measured, same sketch run)

| test | failing assert | why | edit |
|---|---|---|---|
| W-6 | :206 `"says 99.0% used"` (masks :207 and :209, which fail by the same output: `"still accepts work"` absent, cell `\| ≥99% \|`) | defect pin | assert the bound (`"≥99%"`), the age and the load. Drop `"99.0%"` and replace `"still accepts work"` with a past-tense, dated form |
| W-9 | :242 `"not out of weekly quota"` | **only because the sketch changed the lead to "nearly out of"**, which was a sketch choice | keeping "not out of weekly quota" leaves :242 and :350 green, and these are the only lead-phrase pins |
| W-10 board | :341 `" 99.6%" in row` (and :358 fails by code: `pct_text(99.6, False)` now gives `≥99%`) | defect pin, and its fixture value 0.996 is one the server never sends | change the fixture to 0.99 (the measured value) and assert `"≥99%"`; keep `"100%" not in row`, :339, :354-356, :359-360 |

## 6. Ruling conflicts and design decisions for the lead

- **Text-only distinguishability (decision needed).** If the wire-allowed state prints `≥99%`, its cell text becomes identical to the endpoint-only "not confirmed" state, which :344 already pins as `≥99%`. The code comment at bin :6355-6356 claims "The text carries it without colour too", and that claim would no longer hold for the cell.
  - What survives: with colour off the states still differ inline by the **bar** (`▆▆▆▆▆▆▆▁` against `▄▄▄▄▄▄▄▄`, pinned at :339 and :344) and by the sentence. So the 2026-10-03 "inline" ruling holds through the bar.
  - Alternative: `99%+` for the server-allowed state. It keeps the texts distinct, but both strings mean "≥99", and a distinction that needs a key is what the operator rejected with `ʷ` (W-9 :224-226).
  - Recommendation (reasoned): use the same `≥99%`, update the :6355 comment, and keep the bar as the colour-off distinguisher.
- **Do not loosen** `:339`, `:354`, `:355-356`, `:341` "100%" not in row, `:344`, `:347` or `:359-360`. Each encodes the 2026-10-01/03 rulings: three states inline, no full red bar for a spendable last 1%, and only a server refusal prints "100%". W-11 check (5) re-pins the bar and colour on the real row.
- **Wording constraints from existing pins.** The new note must not contain the word `wire` (:216), `ʷ` or `rate-limit headers` (:241, :352), and must not appear away from the wall (:244).
- **Out of R7 scope but touched by the same row.** W-1 (:104-108) pins that wire 0.99 is *routable* with headroom 0.01, and the replay shows the desk picking next3. If R6 changes routing for this state, W-1 is the pin to edit, not the wording tests.

## Blockers / caveats

- No blocker. `cc-bats` refused repeatedly under load: 2 roots plus 1-min load ≥ 2.0/core, peaking at load ~95. The final fragment's bats run is still owed (§4).
- No test exercises the throttled-substitute path (`_wire_note`) at 0.99. If R6 extends the fix there, F-7 :285 is its only pin, and a second control (a substitute row at 0.99) would be needed.
