#!/usr/bin/env bats
# accounts-width-sweep — both /accounts surfaces fit every pane from 40 to 200 columns, and the
# ladder they are drawn from keeps every value whole down to 7 cells.
#
# Operator, 2026-10-18 21:13, with a screenshot of a ~55-column pane: "correct and improve layout
# for all small screen widths — it breaks when small". The desk clause broke mid-sentence, the grid
# headers split, every account row wrapped its last cells onto a second line. Two surfaces draw
# this table into a pane, and both are swept here at the same widths:
#
#   · the /accounts chat readout — `claude-accounts --readout` leaves a pane-fitted copy that
#     hooks/relay-verbatim.sh draws as a PostToolUse systemMessage (`--pane --cols N` prints it);
#   · the SessionStart board — hooks/accounts-board.sh draws a file the keepwarm producer wrote,
#     choosing among the producer's narrow variants by the pane's width (`CC_PANE_COLS` seam).
#
# THE BUDGET, measured (docs/research/board-render-2026-09-22.md, findings 6-7): a hook
# systemMessage gets pane − 5 cells per row (a 5-column continuation indent), and line 1 alone also
# carries the harness's `⎿ <Event>:<source> says: ` prefix (~31 columns for SessionStart). The
# check below measures DISPLAY CELLS with SGR stripped, re-implemented here rather than imported
# from the subject — a check that calls the subject's own measure agrees with it by construction.
#
# The one allowance: a single token wider than the pane (a path or a command the hook names) is
# never split, because a broken command no longer pastes. The check accepts such a line only when
# it is ONE token after its indent; any line a word wrap could have shortened is a breach.

WIDTHS="17 20 22 25 27 30 35 40 50 55 60 70 76 80 100 120 160 200"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOOK="$REPO/hooks/accounts-board.sh"
  export RELAY="$REPO/hooks/relay-verbatim.sh"
  export CA_BIN="$REPO/bin/claude-accounts"
  export D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"
  export CC_ACCOUNTS_BOARD="$D/board.txt"
  export CC_PANE_DIR="$D/pane"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mk_cfg
}

# Fixture config and rows: the same shape tests/accounts-board.bats uses (a 61-character account
# name, so truncation is load-bearing; a stale `*` reading; a 100% 5h row the wire rejected).
mk_cfg() {
  python3 - "$D/acct.json" "$D/cache.json" "$REPO/accounts.json" <<'PY'
import json, sys
out, cache, real = sys.argv[1:4]
r = json.load(open(real))
acct = lambda n, l, x: {"name": n, "config_dir": f"/tmp/ca-sweep-nonexistent-{x}", "launcher": l,
                        "email": f"{x}@example.com", "mailbox": f"{x}@example.com", "dia_profile": x}
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [acct("next-quaternary-extremely-long-account-name-for-width-testing", "claude4", "a"),
               acct("next2", "claude2", "b"), acct("next3", "claude3", "c"),
               acct("next", "claude", "d")],
}, open(out, "w"))
PY
}

FIXTURE='
_t = lambda m: (datetime.now(timezone.utc) + timedelta(minutes=m, seconds=30)).isoformat()  # +30 s: a ladder built across a minute boundary keeps every countdown
    rows = [
  {"acct": "next-quaternary-extremely-long-account-name-for-width-testing",
   "auth": "ok", "launcher": "claude4", "k": 12,
   "session_pct": 88.0, "weekly_pct": 46.0, "fable_pct": 18.0,
   "session_reset_h": 1.2, "weekly_reset_h": 100.4, "login_expires_h": 447.0,
   "session_reset_at": _t(72), "weekly_reset_at": "2126-01-05T00:00:00+00:00",
   "login_expires_at": "2126-02-01T00:00:00+00:00", "stale_quota": True},
  {"acct": "next2", "auth": "ok", "launcher": "claude2", "k": 1,
   "session_pct": 82.0, "weekly_pct": 48.0, "fable_pct": 21.0,
   "session_reset_h": 2.5, "weekly_reset_h": 83.5, "login_expires_h": 636.0,
   "session_reset_at": _t(150), "weekly_reset_at": "2126-01-04T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00"},
  {"acct": "next3", "auth": "ok", "launcher": "claude3", "k": 0,
   "session_pct": 100.0, "weekly_pct": 40.0, "fable_pct": 10.0,
   "session_reset_h": 0.75, "weekly_reset_h": 60.0, "login_expires_h": 50.0,
   "session_reset_at": _t(45), "weekly_reset_at": "2126-01-03T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00",
   "wire": {"5h_util": 1.02, "5h_status": "rejected", "7d_util": 0.4, "7d_status": "allowed",
            "status": "rejected", "http": 429}},
  {"acct": "next", "auth": "ok", "launcher": "claude", "k": 2,
   "session_pct": 0.0, "weekly_pct": 22.0, "fable_pct": 0.0,
   "session_reset_h": 3.6, "weekly_reset_h": 145.0, "login_expires_h": 671.0,
   "session_reset_at": _t(218), "weekly_reset_at": "2126-01-07T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00"},
]
    wj, cached, prev = {}, True, None'

ca() {  # <args…> → claude-accounts run over the fixture rows (source patch at the documented anchor)
  python3 - "$CA_BIN" "$@" <<PY
import subprocess, sys
src = open(sys.argv[1]).read()
anchor = "rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)"
new = src.replace(anchor, '''$FIXTURE'''.strip())
assert new != src, "source patch did not apply — the anchor moved (see the note at that line)"
p = subprocess.run([sys.executable, "-c", new] + sys.argv[2:], capture_output=True, text=True)
sys.stderr.write(p.stderr)
sys.stdout.write(p.stdout)
sys.exit(p.returncode)
PY
}

# <pane cols> <line-1 prefix cells> < message → exit 1 and one BREACH line per row that the
# terminal would wrap. Line 1 is charged the prefix; every row is charged the 5-column gutter.
fits() {
  python3 -c '
import re, sys, unicodedata
cols, prefix = int(sys.argv[1]), int(sys.argv[2])
sgr = re.compile("\x1b\\[[0-9;]*m")
def cells(s):
    return sum(0 if unicodedata.combining(c) or c in "‍︎️" else
               2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
bad = 0
for i, l in enumerate(sys.stdin.read().split("\n"), 1):
    p = sgr.sub("", l)
    budget = cols - 5 - (prefix - 5 if i == 1 else 0)
    if cells(p) > budget and len(p.split()) > 1:
        bad += 1
        print(f"BREACH pane={cols} line {i}: {cells(p)} cells > {budget}: {p!r}")
sys.exit(1 if bad else 0)' "$@"
}

@test "1 /accounts pane readout: no row wraps at any pane width 40..200" {
  local w out fail=0
  for w in $WIDTHS; do
    out="$(ca --readout --pane --cols "$w" --no-agents --max-wait 0 2>"$D/err")" \
      || { echo "pane=$w: --pane failed: $(cat "$D/err")"; fail=1; continue; }
    [ -n "$out" ] || { echo "pane=$w: empty render"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 5 || fail=1
  done
  [ "$fail" -eq 0 ]
}

@test "2 /accounts pane readout keeps the answer at 40 columns: desk pick and every account" {
  run ca --readout --pane --cols 40 --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *desk* ]] || { echo "desk line lost at 40: $output"; false; }
  local a
  for a in next2 next3 next; do
    [[ "$output" == *"$a"* ]] || { echo "account $a dropped at 40: $output"; false; }
  done
}

@test "3 /accounts as drawn by the relay hook: the drawn message fits at every width" {
  local w out fail=0
  export CLAUDE_CODE_SESSION_ID="sweep-sid"
  for w in $WIDTHS; do
    CC_PANE_COLS="$w" ca --readout --no-agents --max-wait 0 >/dev/null 2>"$D/err" \
      || { echo "pane=$w: readout failed: $(cat "$D/err")"; fail=1; continue; }
    out="$(jq -nc --arg c "claude-accounts --readout" \
            '{tool_name:"Bash", tool_input:{command:$c}, tool_response:{stdout:"x"},
              session_id:"sweep-sid", hook_event_name:"PostToolUse"}' \
           | "$RELAY" | jq -r '.systemMessage // empty')"
    [ -n "$out" ] || { echo "pane=$w: the relay hook drew nothing"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 27 || fail=1     # `⎿ PostToolUse:Bash says: `
  done
  [ "$fail" -eq 0 ]
}

board_at() {  # <pane cols> → the SessionStart systemMessage for that pane
  printf '{"source":"startup","hook_event_name":"SessionStart"}' \
    | CC_PANE_COLS="$1" "$HOOK" | jq -r '.systemMessage // empty'
}
# The dated stamp line (accounts-board.bats #30 owns it). Only the byte-identity check drops it: the
# fit checks need it in place, since it is what shares line 1 with the harness prefix.
unstamp() { sed -E '1{/^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) [A-Z][a-z]{2} [0-9]{1,2} · /d;}'; }

@test "4 SessionStart board: no row wraps at any pane width 40..200" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$CC_ACCOUNTS_BOARD" ] || { echo "producer wrote no board"; false; }
  local w out fail=0
  for w in $WIDTHS; do
    out="$(board_at "$w")"
    [ -n "$out" ] || { echo "pane=$w: the hook drew nothing"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 31 || fail=1
    [[ "$out" == *next3* ]] || { echo "pane=$w: an account row was lost: $out"; fail=1; }
  done
  [ "$fail" -eq 0 ]
}

@test "5 SessionStart board: a STALE board's warning lines fit too, at every width" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f t
  t=$(( $(date +%s) - 900 ))
  for f in "$CC_ACCOUNTS_BOARD" "$CC_ACCOUNTS_BOARD".w*; do
    [ -e "$f" ] && touch -t "$(date -r "$t" +%Y%m%d%H%M.%S)" "$f" || false
  done
  # launchctl stubbed: the warning names the producer's state, and the real job is not ours to read
  mkdir -p "$D/bin"; printf '#!/bin/sh\nexit 1\n' > "$D/bin/launchctl"; chmod +x "$D/bin/launchctl"
  local w out fail=0
  for w in $WIDTHS; do
    out="$(PATH="$D/bin:$PATH" board_at "$w")"
    [[ "$out" == *STALE* ]] || { echo "pane=$w: not on the stale path: $out"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 31 || fail=1
  done
  [ "$fail" -eq 0 ]
}

@test "6 SessionStart board: byte-identical to the 76-column board wherever that board fits" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local want w
  want="$(cat "$CC_ACCOUNTS_BOARD")"
  for w in 81 100 120 160 200; do
    [ "$(board_at "$w" | unstamp)" = "$want" ] || { echo "pane=$w: board changed where it fit"; false; }
  done
  # and an unknown width (no tty anywhere up the tree, no override) keeps the old board too
  [ "$(printf '{"source":"startup"}' | CC_PANE_COLS=x "$HOOK" | jq -r .systemMessage | unstamp)" = "$want" ]
}

# Operator, 2026-10-19, with a screenshot: "The weekly reset header is not aligned with the
# respective column". The weekly bar has no header, and its empty header cell was appended
# UNPADDED, so every header right of the bar sat a bar's width (4 or 8 cells) left of its column.
# Fitting is not alignment: case 1 stayed green through it. Here every right-aligned header must
# end exactly where each account row has a cell ending — a non-space at its last column and a space
# (or the end of the row) right after it.
@test "7 /accounts pane readout: every right-aligned header ends on its column's right edge" {
  local w fail=0
  for w in $WIDTHS; do
    CC_BOARD_COLOR=off ca --readout --pane --cols "$w" --no-agents --max-wait 0 > "$D/grid" 2>"$D/err" \
      || { echo "pane=$w: --pane failed: $(cat "$D/err")"; fail=1; continue; }
    python3 - "$w" "$D/grid" <<'PY' || fail=1
import re, sys
w, lines = sys.argv[1], open(sys.argv[2]).read().split("\n")
hi = next((i for i, l in enumerate(lines) if re.search(r"\baccount\b", l)), None)
if hi is None:          # the stacked form (two rows per account) carries no header row
    sys.exit(0)
head = lines[hi]
rows = []
for l in lines[hi + 1:]:        # the grid runs from the header to the first blank line
    if not l.strip():
        break
    rows.append(l)
bad = 0
for m in re.finditer(r"\b(live|used|resets|fable)\b", head):
    e = m.end()
    for r in rows:
        # the cell a header names must END at the header's edge: a percent under used/fable, a
        # countdown under resets, a count under live. Edge-matching alone is fooled whenever the
        # shift lands inside another cell ("5d 11h") or on the bar's own edge.
        want = {"used": r"\d+%\*?", "fable": r"\d+%\*?|—", "live": r"\d+|\?",
                "resets": r"\d+d \d+h|\d+h \d+m|\d+[dhm]|99d\+|—"}[m.group()]
        ok = len(r) >= e and (len(r) == e or r[e] == " ") \
            and re.search(r"(?:^|\s)(?:" + want + r")$", r[:e]) is not None \
            and not (m.group() == "resets" and re.match(r" \d+[hms]\b", r[e:]))  # nor cut mid-countdown
        if not ok:
            bad += 1
            print(f"MISALIGNED pane={w}: header {m.group()!r} ends at {e}, row {r!r}")
sys.exit(1 if bad else 0)
PY
  done
  [ "$fail" -eq 0 ]
}

# THE RESIZE CASE (2026-10-19). Tests 1-3 fit the readout to the width it is DRAWN at; the
# operator then narrowed a pane drawn at ~157 columns to ~35 and the static copy re-wrapped into
# soup. mods/accounts-readout re-draws from the ladder `--readout` leaves (`<sid>.ladder.json`)
# at every width change; the pty proof is docs/research/accounts-responsive-mod-2026-10-19/.

@test "8 ladder: the layout picked for each pane width is the one --pane draws for it, and it fits" {
  run ca --readout --ladder --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" > "$D/ladder.json"
  local w out fail=0
  for w in $WIDTHS; do
    out="$(jq -r --argjson c "$w" '.budget.cells[$c - .budget.from] as $b
             | [.variants[] | select(.cells <= $b)] | last | .lines | join("\n")' "$D/ladder.json")"
    # HH:MM masked: the wide layouts print reset clock times, and the two renders may straddle
    # a minute (measured: pane=200 differed only in its clock times).
    [ "$(printf '%s' "$out" | sed -E 's/[0-9]{1,2}:[0-9]{2}/HH:MM/g')" = \
      "$(ca --readout --pane --cols "$w" --no-agents --max-wait 0 | sed -E 's/[0-9]{1,2}:[0-9]{2}/HH:MM/g')" ] \
      || { echo "pane=$w: the ladder's pick differs from --pane"; fail=1; }
    printf '%s' "$out" | fits "$w" 5 || fail=1
  done
  # deduplicated: no two neighbouring variants lay out the same
  [ "$(jq '[.variants | range(1; length) as $i | select(.[$i].lines == .[$i - 1].lines)] | length' \
        "$D/ladder.json")" -eq 0 ] || { echo "duplicate variants"; fail=1; }
  [ "$fail" -eq 0 ]
}

@test "9 --readout leaves the ladder beside the pane file, for the session that ran it" {
  export CLAUDE_CODE_SESSION_ID="sweep-sid"
  CC_PANE_COLS=160 ca --readout --no-agents --max-wait 0 >/dev/null
  [ -s "$CC_PANE_DIR/sweep-sid.ladder.json" ] || { ls -la "$CC_PANE_DIR"; false; }
  [ "$(jq -r '.v, (.variants | length > 1), (.written_ms > 0)' "$CC_PANE_DIR/sweep-sid.ladder.json" \
       | tr '\n' ' ')" = "1 true true " ]
  # the FULL family only (2026-10-22): the transcript draws nothing else, and the dense family cost
  # every /accounts call ~40% more CPU for no reader
  [ "$(jq '[.variants[] | select(.dense)] | length' "$CC_PANE_DIR/sweep-sid.ladder.json")" -eq 0 ]
}

@test "10 relay hook: the mod's stamp for THIS call silences the static copy; any other keeps it" {
  export CLAUDE_CODE_SESSION_ID="sweep-sid"
  relay() {  # <tool_use_id> → the relay hook's JSON for a just-run readout
    CC_PANE_COLS=160 ca --readout --no-agents --max-wait 0 >/dev/null
    jq -nc --arg u "$1" '{tool_name:"Bash", tool_input:{command:"claude-accounts --readout"},
            tool_response:{stdout:"x"}, tool_use_id:$u, session_id:"sweep-sid",
            hook_event_name:"PostToolUse"}' | "$RELAY"
  }
  mkdir -p "$CC_PANE_DIR"; printf 'toolu_A' > "$CC_PANE_DIR/sweep-sid.mod"
  run relay toolu_A
  [ "$(printf '%s' "$output" | jq -r '.systemMessage // "none"')" = none ] || { echo "$output"; false; }
  [[ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)" == *"accounts-readout mod"* ]] || false
  [ ! -e "$CC_PANE_DIR/sweep-sid.txt" ]                 # the static copy is consumed, never drawn later
  run relay toolu_B                                      # a stamp from another call: static copy drawn
  [ -n "$(printf '%s' "$output" | jq -r '.systemMessage // empty')" ] || { echo "$output"; false; }
  rm -f "$CC_PANE_DIR/sweep-sid.mod"
  run relay toolu_C                                      # no mod at all: unchanged
  [ -n "$(printf '%s' "$output" | jq -r '.systemMessage // empty')" ] || { echo "$output"; false; }
}

# THE NARROW FLOOR (2026-10-22). Operator screenshot of a ~27-column band: every reset countdown cut
# to an ellipsis by the band's truncate-end, the weekly bars and the prose cut too. The ladder now
# reaches 8 cells (a 13-column pane's band; Claude Code hands a 12-16-column pane's band 7-11 cells,
# measured, docs/research/accounts-narrow-2026-10-22/) and carries two families: the full layouts and
# the DENSE ones the band draws when the full one would not fit its height (`"dense": true`, first).
#
# LADDER_CHECK reads a ladder the way a person reads the pane, independently of the renderer: for
# every cell width the band can be handed (pickFit, within each family) and every pane width the
# transcript readout can be drawn into (pickVariant, the full family), each account's name and its
# 5h used, 5h reset, weekly used and weekly reset must be recoverable WHOLE and IN ORDER after the
# name (a name continued after a `-` or a `↩` is rejoined; a countdown is compared without its
# space, `1h 11m` = `1h11m`; side-by-side cards are read one card at a time). The expected values
# are the widest grid's, read by its own header columns: a narrow layout may move a value, never
# drop, cut or change it. Also, in every variant: no row past the width, no `…` anywhere (no name
# behind an ellipsis in any pane layout), no ` · ` at a row edge, no row ending in `→` or holding a
# bare `→`. Args: <ladder.json> <comma-separated names> <floor cells>.
#
# And in every variant, read off its own rows (round 2, 2026-10-22): no row wider than the
# variant's cells (a short name's grid overflowed by 3, a 10-cell card's `used resets` by 1); no
# lane label without its mark in the lanes block (`general` alone in prose grey under the desk
# reason); under 12 cells no row of prose at a 2-cell indent and no drain line; no `↩` cut that
# spreads into the next part of a name (`y-extreme↩` / `ly-long-`) or cuts a `-`-bounded piece
# that fit where it starts (`quaternar↩` at 12 cells); and no `desk·gen·fable` (general cut short
# while all three lanes agree; `all lanes` says it whole).
#
# RED-proof (2026-10-22, against 10c2eab2b's renderer): 11 fails "no dense family" and "floor is 12,
# not 8" and the grid's `next-quater…` ellipsis; 12 fails with no dense family; 13 fails at 12-27
# cells (`Pi` / `Codex backend`, the dot deleted); 14 fails on `→` alone on a row, and on `← you`
# missing from the lanes block of 46 full variants (12-58 cells). Round 2, against the first
# round's working tree: the row-level rules above fail 11 and 14 (`y-extreme↩` at 10-12 cells),
# 12 (`desk·gen·fable`, a lone `general`), and 16 on every fixture it adds.
#
# Round 7 (2026-10-22): every dense layout says what its numbers are, in one vocabulary, `used` and
# `reset`, within its account rows (the column form's reset rows had no label and its legend said only
# `used`; the floor said `resets`), unless it is a `terse` sibling, which ships only where it saves a
# row on its labelled layout (the mod draws it only where that one does not fit the band's height);
# a row that leads with `-` continues the name above it (`quaternary` / `-extremely`); and a word a
# row holds is never cut (`quaternar↩` / `y-` at 10 cells). RED-proof against round 6's tree: 11, 12
# and 16 fail on `used`/`reset` (15-21 and 7-14 cells) and 11 on `quaternar↩` at 10.
# shellcheck disable=SC2016  # Python source: its `$` is a regex anchor, never a shell expansion
LADDER_CHECK='
import json, re, sys, unicodedata
L = json.load(open(sys.argv[1]))
names, floor = sys.argv[2].split(","), int(sys.argv[3])
sgr = re.compile("\x1b\\[[0-9;]*m")
def cells(s):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in ("W", "F")
               else 1 for c in sgr.sub("", s))
def plain(v):
    return [sgr.sub("", x).replace(" ", " ") for x in v["lines"]]
normal = [v for v in L["variants"] if not v.get("dense")]
dense = [v for v in L["variants"] if v.get("dense") and not v.get("terse")]
terse = [v for v in L["variants"] if v.get("terse")]
bad = []
if not dense or [v for v in L["variants"][:len(dense) + len(terse)] if not v.get("terse")] != dense:
    bad.append("no dense family ahead of the full one")
for i, v in enumerate(L["variants"]):       # a terse sibling saves rows on its labelled one
    if not v.get("terse"):
        continue
    sib = [x for x in L["variants"][:i] if x.get("dense") and not x.get("terse")]
    if not sib or sib[-1]["cells"] > v["cells"] or len(v["lines"]) >= len(sib[-1]["lines"]):
        bad.append("terse %s: saves no row on its labelled layout" % v["cells"])
for fam in (normal, dense):
    cs = [v["cells"] for v in fam]
    if cs != sorted(set(cs)):
        bad.append(f"a family is not narrowest first: {cs[:6]}")
if normal[0]["cells"] != floor or L["budget"]["from"] != floor:
    bad.append("floor is %s, not %s" % (normal[0]["cells"], floor))
def cellview(s):
    """One character per CELL (a wide one gains a NUL), so header offsets index values."""
    return "".join(c + ("\0" if unicodedata.east_asian_width(c) in ("W", "F") else "") for c in s)
wide = [cellview(x) for x in plain(normal[-1])]
hi = next(i for i, l in enumerate(wide) if re.search(r"\b(account|acct)\s+live\b", l))
ends = [m.end() for m in re.finditer(r"\b(used|resets)\b", wide[hi])][:4]
want = {}
for l in wide[hi + 1:]:
    if not l.strip():
        break
    t = l[3:].replace("\0", "").split()
    # a name the grid clipped (`next-quater…`, before 2026-10-22) still keys its values; the
    # ellipsis itself is a finding below
    n = next((x for x in names if t and (t[0] == x or t[0].endswith("…")
                                          and x.startswith(t[0][:-1]))), None)
    if n:
        want[n] = [re.findall(r"(\S+(?: \d+[hm])?)$", l[:e])[0].replace(" ", "") for e in ends]
assert set(want) == set(names), want
PCT = re.compile(r"^(≥?\d+%\*?|—)$")
CD = re.compile(r"^(\d+d\d+h|\d+h\d+m|\d+[dhm]|<1m|99d\+|—)$")
MARKS = ("➤ᵍ", "➤ᶠ", "➤")
def by_card(rows):
    """Side-by-side cards (names on one row, then 5h and wk rows): one card column at a time."""
    out, i = [], 0
    while i < len(rows):
        x = rows[i]
        hits = [(m.start(), m.group()) for m in re.finditer(r"\S+", x) if m.group() in names]
        if len(hits) > 1 and i + 2 < len(rows) and rows[i + 1].startswith("5h") \
                and rows[i + 2].startswith("wk"):
            st = []
            for s, _n in hits:
                pre = x[:s].rstrip()
                mk = next((k for k in MARKS if pre.endswith(k)), "")
                st.append(len(pre) - len(mk) if mk else s)
            for j, (_s, n) in enumerate(hits):
                b = st[j + 1] if j + 1 < len(st) else None
                out += [n] + [r[:2] + " " + r[st[j]:b] for r in rows[i + 1:i + 3]]
            i += 3
            continue
        out.append(x)
        i += 1
    return out
def by_column(rows):
    """The column form (each limit a column, its percent over its reset): one limit at a time."""
    out, i = [], 0
    while i < len(rows):
        t = rows[i].split()
        u = rows[i + 1].split() if i + 1 < len(rows) else []
        u = u[1:] if u[:1] == ["reset"] else u          # the reset row, labelled (2026-10-22)
        if len(t) >= 2 and PCT.match(t[-1]) and PCT.match(t[-2]) and len(u) == 2 \
                and all(CD.match(y) for y in u):
            out.append(" ".join(t[:-2] + [t[-2], u[0], t[-1], u[1]]))
            i += 2
            continue
        out.append(rows[i])
        i += 1
    return out
def whole(rows):
    """{name: True} for every name followed, before the next name, by its four values in order."""
    t = "\n".join(by_column(by_card(rows)))
    t = re.sub(r"↩\n\s*", "", t)
    t = re.sub(r"-\n\s*", "-", t)
    t = re.sub(r"(?<=[^\s-])\n\s*-(?=[^\W\d_])", "-", t)     # `quaternary` / `-extremely`
    t = re.sub(r"\b(\d+[dh]) (\d+[hm])\b", r"\1\2", t)
    toks = t.split()
    occ = [(k, x) for k, x in enumerate(toks) if x in names]
    ok = set()
    for a, (k, n) in enumerate(occ):
        seg = toks[k + 1:occ[a + 1][0] if a + 1 < len(occ) else len(toks)]
        seg = [x for j, x in enumerate(seg)
               if not (x in ("5h", "wk") and j + 1 < len(seg) and PCT.match(seg[j + 1]))]
        if [x for x in seg if PCT.match(x) or CD.match(x)][:4] == want[n]:
            ok.add(n)
    return ok
def picks():
    for fam, tag in ((normal, "band"), (dense, "dense")):
        for c in (range(floor, 61) if fam else ()):
            v = [x for x in fam if x["width"] <= c] or fam[:1]
            yield tag, c, v[-1], c
    for v in terse:
        yield "terse", v["cells"], v, v["cells"]
    b = L["budget"]
    for cols in range(floor + L["gutter"], 66):
        bud = b["cells"][max(0, min(len(b["cells"]) - 1, cols - b["from"]))]
        v = [x for x in normal if x["cells"] <= bud] or normal[:1]
        yield "tx", cols, v[-1], cols - L["gutter"]
for tag, w, v, room in picks():
    pl, errs = plain(v), []
    grid = any(re.search(r"\b(account|acct)\s+(live|used)\b", x) for x in pl)
    for x in pl:
        s = x.strip()
        if cells(x) > room and len(x.split()) > 1:
            errs.append(f"over: {x!r}")
        if s == "·" or x.rstrip().endswith(" ·") or (x.startswith(" ") and s.startswith("· ")):
            errs.append(f"separator at a row edge: {x!r}")
        if s == "→" or x.rstrip().endswith("→"):
            errs.append(f"arrow alone or at a row end: {x!r}")
    if not grid:
        miss = set(names) - whole(pl)
        if miss:
            errs.append(f"not whole and in order after the name: {sorted(miss)}")
    if errs:
        bad.append("%s %s (variant %s): %s" % (tag, w, v["cells"], errs[:3]))
for v in L["variants"]:
    if any("…" in x for x in plain(v)):
        bad.append("ellipsis in variant %s%s" % (v["cells"], " dense" if v.get("dense") else ""))
LANE = re.compile(r"^\s*(desk|general|gen|fable)(·|\s|$)")
DRAIN = ("Not enough recent readings", "Unused at weekly reset", "Give heavy work",
         "No weekly quota goes unused")
VALUE = re.compile(r"^(≥?\d+%\*?|—|\d+d\d+h|\d+h\d+m|\d+[dhm]|<1m|99d\+|5h|wk|used|resets?)$")
for v in L["variants"]:
    tag = "%s%s" % (v["cells"], " dense" if v.get("dense") else "")
    pl, errs, lanes = plain(v), [], []
    for x in pl:                    # the lanes block: every row before the legend or a blank one
        if not x.strip() or re.match(r"^\s*(used|5-hour)\b", x):
            break
        lanes.append(x)
    for j, x in enumerate(lanes):
        if LANE.match(x) and not (j and lanes[j - 1].rstrip().endswith("·")):
            errs.append(f"a lane label without its mark: {x!r}")
    n = v["cells"]
    for j, x in enumerate(pl):
        if cells(x) > n and len(x.split()) > 1:
            errs.append(f"wider than its {n} cells: {x!r}")
        if n < 12 and x.strip() and not VALUE.match(x.split()[0]) \
                and len(x) - len(x.lstrip()) >= 2:
            errs.append(f"a floor row indented 2: {x!r}")
        if x.rstrip().endswith("↩") and j + 1 < len(pl) and pl[j + 1].split():
            a, b = x.rstrip()[:-1].split()[-1], pl[j + 1].split()[0]
            if re.match(r"^[^\W\d_]+-[^\W\d_]", b):
                errs.append(f"a cut spreads into the next part: {a}↩ / {b}")
            hi, lo = b.find("-"), a.rfind("-") + 1
            start = len(x.rstrip()) - 1 - len(a) + lo
            if hi >= 0 and cells(a[lo:] + b[:hi + 1]) <= v["cells"] - start:
                errs.append(f"cut a piece its row holds: {a}↩{b}")
            # the word alone, without its hyphen: a row holds it whole at the margin (G, 2026-10-22:
            # `quaternar↩` / `y-` at 10 cells, where `quaternary` / `-extremely` fits), beside the
            # arrow it is bound to where it has one (`→ next3@example.com` is 19 cells, not 17)
            elif not (j and pl[j - 1].rstrip().endswith("↩")) and cells(a[lo:] + (b[:hi] if hi > 0 else b)) \
                    + (2 if x.rstrip()[:-1].split()[-2:-1] == ["→"] else 0) <= v["cells"]:
                errs.append(f"cut a word a row holds: {a}↩{b}")
    flat = re.sub(r"↩ ", "", " ".join(x.strip() for x in pl))       # a wrapped phrase, rejoined
    if not v.get("dense") and n < 12 and any(d in flat for d in DRAIN):
        errs.append("the drain line under 12 cells")
    if v.get("dense") and not v.get("terse"):
        acct = [x.split() for x in pl[:v.get("values", len(pl))]]
        need = {"used", "reset"} - {t for x in acct for t in x}
        if need:
            errs.append(f"says not which number is used and which the reset: {sorted(need)}")
        # a reset row of the column form with no label of its own needs the `reset` key row
        if any(len(x) == 2 and all(CD.match(t) and not PCT.match(t) for t in x) for x in acct) \
                and ["reset"] not in acct:
            errs.append("an unlabelled reset row and no `reset` key")
    if any("desk·gen·fable" in x for x in pl):
        errs.append("`desk·gen·fable`: general cut short while all lanes agree")
    if errs:
        bad.append("variant %s: %s" % (tag, errs[:3]))
print("\n".join(bad[:12]))
sys.exit(1 if bad else 0)'

LONG="next-quaternary-extremely-long-account-name-for-width-testing"

cfg_as() {  # <out> <name>… → $D/acct.json with its accounts renamed in order, its own cache file
  python3 - "$D/acct.json" "$@" <<'PY'
import json, sys
src, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
c = json.load(open(src))
for a, n in zip(c["accounts"], names):
    a["name"] = n
c["cache_file"] = out + ".cache.json"
json.dump(c, open(out, "w"))
PY
}

@test "11 ladder 7..60: every account's 5h and weekly use and resets survive whole, nothing cut" {
  run ca --readout --ladder --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" > "$D/ladder.json"
  run python3 -c "$LADDER_CHECK" "$D/ladder.json" "$LONG,next2,next3,next" 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# THE DENSE FAMILY'S HEIGHT (2026-10-22). The band gets about half the pane's rows (10 on a 30-row
# pane, 17 on 45), and a tree of exactly that many shows whole (measured; a taller one loses its last
# row to the `↓ N more` cue). On the live fleet's shape (four short names, no alerts, no `←`, as the
# band draws it) the dense variant must fit 9 rows from 22 cells (a 30-row pane under a one-row stale
# head), 10 from 15 (the column form, 2026-10-22: it was 16 there, and the desk's own pick, last in
# config order, was the account cut), 14 from 12, and never be taller than the full variant.
#
# Also, in every dense variant: the PICKS lead the accounts (the desk pick's name first, so a band
# cut short cuts an unpicked account); side-by-side cards sit under ONE `used reset` legend (at 22-28
# cells `0% 4h46m` said neither whether the percent was used or left nor that the time was a reset;
# one per card read `used reset used reset`, which the one-row table means otherwise one column
# wider); and no read clock while the quota is fresh (the band states its own age; test 15 has the
# old one). The caps hold for the layout a band that tall draws: where the labelled column form spends
# a row on its `reset` key (15-16 cells), on its terse sibling (round 7, 2026-10-22). RED-proof: with
# the cards' legend once per card, 24-28 cells fail; with no terse sibling, 15-16 cells fail the cap.
LIVE_FIXTURE='
_t = lambda m: (datetime.now(timezone.utc) + timedelta(minutes=m, seconds=30)).isoformat()  # +30 s: a ladder built across a minute boundary keeps every countdown
    rows = [
  {"acct": "next", "auth": "ok", "launcher": "claude", "k": 5, "session_pct": 0.0,
   "weekly_pct": 2.0, "fable_pct": 0.0, "session_reset_h": 4.7, "weekly_reset_h": 68.6,
   "fable_reset_h": 68.6, "login_expires_h": 685.0, "session_reset_at": _t(283),
   "weekly_reset_at": _t(4116), "fable_reset_at": _t(4116), "login_expires_at": _t(41100)},
  {"acct": "next4", "auth": "ok", "launcher": "claude4", "k": 6, "session_pct": 1.0,
   "weekly_pct": 44.0, "fable_pct": 0.0, "session_reset_h": 3.7, "weekly_reset_h": 73.6,
   "fable_reset_h": 73.6, "login_expires_h": 273.0, "session_reset_at": _t(223),
   "weekly_reset_at": _t(4416), "fable_reset_at": _t(4416), "login_expires_at": _t(16400)},
  {"acct": "next3", "auth": "ok", "launcher": "claude3", "k": 2, "session_pct": 15.0,
   "weekly_pct": 11.0, "fable_pct": 0.0, "session_reset_h": 1.25, "weekly_reset_h": 124.6,
   "fable_reset_h": 124.6, "login_expires_h": 690.0, "session_reset_at": _t(75),
   "weekly_reset_at": _t(7476), "fable_reset_at": _t(7476), "login_expires_at": _t(41400)},
  {"acct": "next2", "auth": "ok", "launcher": "claude2", "k": 9, "session_pct": 16.0,
   "weekly_pct": 37.0, "fable_pct": 0.0, "session_reset_h": 3.6, "weekly_reset_h": 51.6,
   "fable_reset_h": 51.6, "login_expires_h": 220.0, "session_reset_at": _t(216),
   "weekly_reset_at": _t(3096), "fable_reset_at": _t(3096), "login_expires_at": _t(13200)},
]
    wj, cached, prev = {"active": True, "permanent": True, "end": "2099-12-31"}, True, None'

live_ladder() {  # <quota age s> → $D/ladder.json, the live fleet's shape (desk pick: next2, last)
  cfg_as "$D/acct-live.json" next4 next2 next3 next
  printf '{"ts": %s}' "$(( $(date +%s) - $1 ))" > "$D/acct-live.json.cache.json"
  CLAUDE_ACCOUNTS_JSON="$D/acct-live.json" FIXTURE="$LIVE_FIXTURE" \
    ca --readout --ladder --no-agents --max-wait 0 > "$D/ladder.json"
}

@test "12 dense family: the live fleet's shape fits 9 rows from 22 cells, 10 from 15, picks first" {
  live_ladder 75 || { cat "$D/ladder.json"; false; }
  run python3 -c "$LADDER_CHECK" "$D/ladder.json" "next,next4,next3,next2" 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 - "$D/ladder.json" <<'PY'
import json, re, sys
L = json.load(open(sys.argv[1]))
sgr = re.compile("\x1b\\[[0-9;]*m")
names = ["next", "next4", "next3", "next2"]
def fit(dense, c):
    fam = [v for v in L["variants"] if bool(v.get("dense")) == dense and not v.get("terse")]
    return ([v for v in fam if v["width"] <= c] or fam[:1])[-1]
def short(d, c):
    """The fewest rows a band c cells wide can draw for d's width: d, or a terse sibling of it."""
    t = [v for v in L["variants"] if v.get("terse") and d["cells"] <= v["cells"] and v["width"] <= c]
    return min([len(d["lines"])] + [len(v["lines"]) for v in t])
bad = []
for c in range(7, 61):
    d, n = fit(True, c), fit(False, c)
    cap = 9 if c >= 22 else 10 if c >= 15 else 14 if c >= 12 else len(n["lines"])
    if short(d, c) > cap or len(d["lines"]) > len(n["lines"]):
        bad.append(f"{c} cells: dense {len(d['lines'])} rows, {short(d, c)} at its tersest "
                   f"(cap {cap}, full {len(n['lines'])})")
for v in (x for x in L["variants"] if x.get("dense")):
    pl = [sgr.sub("", x).replace("\u00a0", " ") for x in v["lines"]]
    body = [x for x in pl if not re.search(r"→|➤ use|\buse\b", x)]
    seen = [t for x in body for t in x.split() if t in names]
    if not seen or seen[0] != "next2":
        bad.append(f"dense {v['cells']}: accounts open with {seen[:1]}, not the desk pick next2")
    cards = [i for i, x in enumerate(pl) if len([t for t in x.split() if t in names]) > 1
             and i + 1 < len(pl) and pl[i + 1].startswith("5h")]
    legend = [x for x in pl[:cards[0]] if "used" in x and "reset" in x] if cards else []
    if cards and not legend:
        bad.append(f"dense {v['cells']}: side-by-side cards with no used/reset legend")
    if legend and len(re.findall(r"\bused\b", legend[0])) != 1:
        bad.append(f"dense {v['cells']}: the cards' legend is not one `used reset`: {legend[0]!r}")
    if any(re.search(r"\bread\b", x) for x in pl):
        bad.append(f"dense {v['cells']}: a read clock on a fresh quota")
print("\n".join(bad[:12]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# THE READ CLOCK IS NEWS ONLY WHEN IT IS OLD (2026-10-22). The band states its own age from 5
# minutes (its stale head), so the dense variant drops the clock row for a quota read just before
# the board was written; one already 400 s old when written keeps it, the band cannot see that age.
# The full family keeps its clock at every age.
@test "15 dense family: the read clock rides only a quota already stale when the board was written" {
  live_ladder 400 || { cat "$D/ladder.json"; false; }
  run python3 - "$D/ladder.json" <<'PY'
import json, re, sys
L = json.load(open(sys.argv[1]))
sgr = re.compile("\x1b\\[[0-9;]*m")
bad = [f"{'dense' if v.get('dense') else 'full'} {v['cells']}: no read clock"
       for v in L["variants"]
       if not any(re.search(r"\bread\b.*\d{1,2}:\d\d|^\s*\d{1,2}:\d\d [AP]M$", sgr.sub("", x).replace("\u00a0", " "))
                  for x in v["lines"])]
print("\n".join(bad[:8]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# A DOT INSIDE A BOLD LABEL IS PART OF A NAME (2026-10-22). providers.json labels two backends
# `Pi · Codex backend` and `Pi · Claude backend`; the pane wrap treated the dot as a separator and
# deleted it at a row break, so the transcript read `Pi` / `Codex backend`, two agents.
@test "13 provider brief: a bold label's dot survives every row break, 8..60 cells" {
  run python3 - "$CA_BIN" <<'PY'
import importlib.machinery, importlib.util, re, sys
loader = importlib.machinery.SourceFileLoader("ca", sys.argv[1])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
sys.argv = [sys.argv[1]]
loader.exec_module(ca)
ready = {"routable": True, "auth_state": "ok", "installed": True, "bills_outside_plan": False}
lines = ca.render_providers_brief([dict(ready, label="Pi · Codex backend"),
                                   dict(ready, label="Pi · Claude backend")])
assert "Pi · Codex backend" in lines[0], lines
bad = []
for w in range(8, 61):
    rows = [ca._SGR_RE.sub("", x).replace(" ", " ") for ln in lines
            for x in ca._pane_prose(ln, w, cont="  ")]
    flat = re.sub(r"↩ ", "", " ".join(r.strip() for r in rows))
    if "Pi · Codex backend" not in flat or "Pi · Claude backend" not in flat:
        bad.append(f"{w}: {rows}")
print("\n".join(bad[:4]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# A LONG PICK WITH NO HYPHEN, AND IT IS THIS SESSION'S ACCOUNT (2026-10-22). The lanes printed
# `➤ desk` / `→` / the name (an arrow alone on its row), and `← you` vanished at 41-66 cells. Every
# full and every labelled dense variant must say `← you` (round 7: the dense `←` was bare at 7-23
# cells, nothing on the band saying whose; RED against round 6's tree), a terse one at least `←`, and
# the pick must follow its arrow whole.
@test "14 ladder: a 40-character pick with no hyphen keeps its arrow, its name and ← you" {
  local nohy=nextquaternaryextremelylongaccountnamexx
  cfg_as "$D/acct-nohy.json" "$LONG" "$nohy" next3 next
  # this session's account is next2's config dir (mark_self), renamed to the long name
  CLAUDE_ACCOUNTS_JSON="$D/acct-nohy.json" CLAUDE_CONFIG_DIR=/tmp/ca-sweep-nonexistent-b \
    FIXTURE="${FIXTURE//\"next2\"/\"$nohy\"}" run ca --readout --ladder --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" > "$D/ladder.json"
  run python3 -c "$LADDER_CHECK" "$D/ladder.json" "$LONG,$nohy,next3,next" 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 - "$D/ladder.json" "$nohy" <<'PY'
import json, re, sys
L, pick = json.load(open(sys.argv[1])), sys.argv[2]
sgr = re.compile("\x1b\\[[0-9;]*m")
bad = []
for v in L["variants"]:
    flat = " ".join(sgr.sub("", x).replace(" ", " ").strip() for x in v["lines"])
    flat = re.sub(r"↩ ", "", flat)
    tag = f"{v['cells']}{' dense' if v.get('dense') else ''}"
    # a dense layout names its picks in its lane rows (`lanes`, 2026-10-22), where a pick may also
    # follow its mark alone (the terse sibling's `➤ next2 ➤ᵍ next`, `➤ next2` under 11 cells);
    # only there, since anywhere else `➤ name` is the table's own account mark
    lw = len(v.get("lanes") or [])
    head = re.sub(r"↩ ", "", " ".join(sgr.sub("", x).replace(" ", " ").strip()
                                      for x in v["lines"][:lw])) if lw else flat
    if not re.search(r"(→|➤ use" + (r"|➤[ᵍᶠ]*" if lw else "") + r") " + pick + r"\b", head):
        bad.append(f"{tag}: the pick does not follow its arrow whole")
    # a full variant says it in its lanes block (the rows before the first blank one), where the
    # desk pick is named; a dense one on its desk row wherever `← you` fits beside the pick (it
    # rode nowhere but the table's `←` once, 2026-10-22), and on its table row always
    pl = [sgr.sub("", x).replace("\u00a0", " ") for x in v["lines"]]
    lanes = " ".join(pl[:pl.index("")] if "" in pl else pl)
    desk = next((x for x in pl if re.search(r"(→|➤ use) " + pick + r"\b", x)), None)
    if v.get("dense") and desk and "← you" not in desk and len(desk.rstrip()) + 6 <= v["cells"]:
        bad.append(f"{tag}: `← you` left off the desk row where it fits: {desk!r}")
    # E (2026-10-22): no bare `←` that nothing on the band explains: every labelled layout says
    # `← you` (the lanes or the name); only a terse sibling may keep the bare mark
    if ("←" not in flat) if v.get("terse") else ("← you" not in flat) if v.get("dense") \
            else ("← you" not in lanes):
        bad.append(f"{tag}: no ← you for this session's account")
print("\n".join(bad[:8]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# THE FIXTURE ZOO (round 2, 2026-10-22): the live shape with one thing each that no fixture above
# carries, every one a defect a reviewer found by hand. Each ladder goes through LADDER_CHECK.
#   login   a logged-out account's auth note ends in an e-mail after `→` (it printed `→` alone)
#   allout  every account logged out: `—` values (a 10-cell card's `used resets` was 11 wide) and
#           the `· Skipped by the general router` footnote (its `·` sat alone on a row at 8 cells)
#   short   1-cell names (the grid's `acct` floor overflowed every row by 3 cells)
#   wide    a CJK name, 2 cells a character (`↩` alone on a row, grid rows past the pane)
#   maxed   `≥99%` over `12d12h` (the floor card was 9 cells wide at 8)
#   starred the widest values the renderer prints, `≥99%*` and `100%*` (5 cells: `5h ≥99%*` made
#           both 7-cell variants 8 wide, 2026-10-22), beside `—` (logged out) and a `?` live count
@test "16 ladder 7..60 over the fixture zoo: login, all logged out, short, wide, maxed, starred" {
  local kind names edit fail=0
  local cjk="アカウント一二三四五六"
  for kind in login allout short wide maxed starred; do
    names="next,next4,next3,next2"
    case "$kind" in
      login)  cfg_as "$D/acct-z.json" next4 next2 next3 next
              edit='    rows[2].update(auth="logged-out", email="next3@example.com", dia_profile="P3")
    rows[1].update(login_expires_h=10.0, login_expires_at=_t(600), email="next4@example.com",
                   dia_profile="P4")' ;;
      allout) cfg_as "$D/acct-z.json" next4 next2 next3 next
              edit='    for r in rows: r.update(auth="logged-out", session_pct=None, weekly_pct=None, session_reset_at=None, weekly_reset_at=None, fable_reset_at=None, session_reset_h=None, weekly_reset_h=None, fable_reset_h=None)' ;;
      short)  cfg_as "$D/acct-z.json" b d c a; names="a,b,c,d"
              edit='    for r in rows: r["acct"] = {"next": "a", "next4": "b", "next3": "c", "next2": "d"}[r["acct"]]' ;;
      wide)   cfg_as "$D/acct-z.json" "$cjk" next2 next3 next; names="next,$cjk,next3,next2"
              edit="    rows[1][\"acct\"] = \"$cjk\"" ;;
      maxed)  cfg_as "$D/acct-z.json" next4 next2 next3 next
              edit='    rows[0].update(session_pct=100.0, weekly_pct=100.0, session_reset_at=_t(0.1), weekly_reset_at=_t(18000), fable_reset_at=_t(18000))
    rows[3].update(session_pct=99.0, weekly_pct=99.0, session_reset_at=_t(744), weekly_reset_at=_t(0.1), fable_reset_at=_t(0.1))' ;;
      starred) cfg_as "$D/acct-z.json" next4 next2 next3 next
              edit='    rows[0].update(session_pct=100.0, weekly_pct=100.0, stale_quota=True)
    rows[1].update(session_pct=100.0, stale_quota=True, wire={"5h_util": 1.0, "5h_status": "rejected", "7d_util": 0.44, "7d_status": "allowed", "status": "rejected", "http": 429})
    rows[2].update(auth="logged-out", session_pct=None, weekly_pct=None, session_reset_at=None, weekly_reset_at=None, fable_reset_at=None, session_reset_h=None, weekly_reset_h=None, fable_reset_h=None)
    rows[3].update(k=None)' ;;
    esac
    printf '{"ts": %s}' "$(( $(date +%s) - 75 ))" > "$D/acct-z.json.cache.json"
    CLAUDE_ACCOUNTS_JSON="$D/acct-z.json" FIXTURE="$LIVE_FIXTURE
$edit" ca --readout --ladder --no-agents --max-wait 0 > "$D/z.json" 2>"$D/err" \
      || { echo "$kind: ladder failed: $(cat "$D/err")"; fail=1; continue; }
    python3 -c "$LADDER_CHECK" "$D/z.json" "$names" 7 > "$D/out" 2>&1 \
      || { echo "$kind:"; cat "$D/out"; fail=1; }
    if [ "$kind" = starred ]; then     # the case is vacuous unless the widest values are drawn
      local t
      for t in '≥99%*' '100%*'; do
        jq -r '.variants[] | select(.cells == 7) | .lines[]' "$D/z.json" | grep -qF -- "$t" \
          || { echo "starred: no $t in a 7-cell variant"; fail=1; }
      done
    fi
  done
  [ "$fail" -eq 0 ]
}

# A WIDER PANE NEVER SHOWS LESS (round 2, 2026-10-22). The grid's name column was as wide as the
# longest name whenever the six required columns fit beside it, so the 61-character name inline at
# 93-125 cells cost the bar, live, fable, login and both clocks that the 66-92-cell layout (the name
# on rows of its own) still had. Every optional column a grid variant shows, every wider one shows.
@test "17 the grid's optional columns only ever join as the pane widens, long names included" {
  local nohy=nextquaternaryextremelylongaccountnamexx fail=0
  run ca --readout --ladder --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" > "$D/long.json"
  cfg_as "$D/acct-nohy.json" "$LONG" "$nohy" next3 next
  CLAUDE_ACCOUNTS_JSON="$D/acct-nohy.json" FIXTURE="${FIXTURE//\"next2\"/\"$nohy\"}" \
    ca --readout --ladder --no-agents --max-wait 0 > "$D/nohy.json" || false
  for f in long nohy; do
    python3 - "$D/$f.json" <<'PY' || { echo "($f)"; fail=1; }
import json, re, sys
L = json.load(open(sys.argv[1]))
sgr = re.compile("\x1b\\[[0-9;]*m")
full = [v for v in L["variants"] if not v.get("dense")]
seen, bad = set(), []
for c in range(35, 126):
    v = [x for x in full if x["cells"] <= c][-1]
    pl = [sgr.sub("", x) for x in v["lines"]]
    hi = next((i for i, x in enumerate(pl) if re.search(r"\b(account|acct)\s+(live|used)\b", x)), None)
    if hi is None:
        continue
    rows = []
    for x in pl[hi + 1:]:
        if not x.strip():
            break
        rows.append(x)
    have = {k for k in ("live", "fable", "login") if re.search(r"\b%s\b" % k, pl[hi])}
    if any(re.search("[▁▂▃▄▅▆▇█]", x) for x in rows):
        have.add("bar")
    clocks = max(len(re.findall(r"\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b", x)) for x in rows)
    have |= {f"clock{i}" for i in range(clocks)}
    if seen - have:
        bad.append(f"{c} cells (variant {v['cells']}) lost {sorted(seen - have)}")
    seen |= have
    if any("…" in x for x in pl):
        bad.append(f"{c} cells: an ellipsis")
print("\n".join(bad[:8]))
sys.exit(1 if bad else 0)
PY
  done
  [ "$fail" -eq 0 ]
}

# THE WRAP ITSELF (round 2, 2026-10-22), on the strings that broke it, at every width it lays out:
# a word a row holds is never cut (`Anthropic's` at 12 cells printed `Anthropic↩` / `'s server`; a
# name's part that fits, `quaternary` at 10, breaks before its `-` rather than mid-letter);
# a cut never spreads into the next part of a name (`y-extreme↩` / `ly-long-`); an arrow never
# ends a row or stands alone (`→` alone when the word after it was a row's width less 1-2 cells);
# a footnote's `·` never stands alone; a wide name's pieces stay inside their row.
@test "18 pane wrap: words a row holds stay whole, cuts stay in their piece, arrows keep their word" {
  run python3 - "$CA_BIN" <<'PY'
import importlib.machinery, importlib.util, re, sys
loader = importlib.machinery.SourceFileLoader("ca", sys.argv[1])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
sys.argv = [sys.argv[1]]
loader.exec_module(ca)
P = lambda rows: [ca._SGR_RE.sub("", r).replace(" ", " ") for r in rows]
LONG = "next-quaternary-extremely-long-account-name-for-width-testing"
note = ("✖ `next3` is **out of 5-hour quota**, confirmed by Anthropic's server (102% used); "
        "resets in 44m")
bad = []
for W in range(7, 41):
    for N in range(1, 45):
        rows = P(ca._pane_prose("➤ general → **" + "x" * N + "**", W, cont="  "))
        if any(r.strip() == "→" or r.rstrip().endswith("→") or ca._disp_w(r) > W for r in rows):
            bad.append(f"arrow W={W} N={N}: {rows}")
            break
for W in range(12, 41):
    rows = P(ca._pane_prose(note, W, cont="  "))
    if any("↩" in r for r in rows):
        bad.append(f"a word its row holds was cut at {W}: {rows}")
for W in range(7, 41):
    for rows in (P(ca._pane_prose(f"▲ `{LONG}` — 5h at 88%", W, cont="  ")),
                 ca._name_chunks(LONG, W)):
        if any(ca._disp_w(r) > W for r in rows):
            bad.append(f"past the row at {W}: {rows}")
        for a, b in zip(rows, rows[1:]):
            if a.endswith("↩") and re.match(r"^\s*[a-z]+-[a-z]", b):
                bad.append(f"a cut spread into the next part at {W}: {a!r} / {b!r}")
        # every part of the name a row holds is whole on one row (round 7, 2026-10-22: at 10 cells
        # `quaternar↩` / `y-`, where `quaternary` / `-extremely` fits; RED against round 6)
        whole = {t for r in rows for t in re.split(r"[\s`]+|-", r.replace("▲", " ")) if t}
        cut = [p for p in LONG.split("-") if ca._disp_w(p) <= W and p not in whole]
        if cut:
            bad.append(f"{cut} cut at {W} though the row holds them: {rows}")
    foot = P(ca._pane_prose("· Skipped by the general router: next (weekly room under the floor)",
                            W, cont="  "))
    if any(r.strip() == "·" for r in foot):
        bad.append(f"a footnote's dot alone at {W}: {foot}")
for W in range(4, 30):
    ch = ca._name_chunks("アカウント一二三四五六", W)
    if any(ca._disp_w(x) > W for x in ch) or "↩" in ch:
        bad.append(f"wide name at {W}: {ch}")
print("\n".join(bad[:8]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# SPLIT LANES ON THE BAND (2026-10-22). The operator's board at 11:14 had desk and fable on next2
# and general on next. The labelled lanes then take 2-4 rows at 15-21 cells (`➤ desk·fable` / `→
# next2` / `➤ᵍ general` / `→ next`), and a 10-row band (a 30-row pane at 20-26 columns) lost next3
# under its cue; the live fixture of test 12 has every lane on next2, one row, so it never saw it.
# The terse sibling now says the picks on ONE row, each group as its mark and pick (`➤ next2 ➤ᵍ
# next`), so the fewest rows a band 15-21 cells wide can draw is 10; the labelled lanes keep their
# words for a band tall enough. Every dense variant ships `lanes`, its lane rows' cells, which the
# band uses to set its stale tag beside one. The fixture is the real board's 11:14 numbers
# (/tmp/narrow-fix3/rev3-reader/real-band.json) with session counts that split the lanes as they
# were split then. RED-proof: before the compact lanes, 15-21 cells drew 11-13 rows and no terse
# sibling named both picks on one row.
SPLIT_FIXTURE='
_t = lambda m: (datetime.now(timezone.utc) + timedelta(minutes=m, seconds=30)).isoformat()  # +30 s: a ladder built across a minute boundary keeps every countdown
    rows = [
  {"acct": "next", "auth": "ok", "launcher": "claude", "k": 0, "session_pct": 11.0,
   "weekly_pct": 8.0, "fable_pct": 0.0, "session_reset_h": 0.92, "weekly_reset_h": 59.0,
   "fable_reset_h": 59.0, "login_expires_h": 685.0, "session_reset_at": _t(55),
   "weekly_reset_at": _t(3540), "fable_reset_at": _t(3540), "login_expires_at": _t(41100)},
  {"acct": "next4", "auth": "ok", "launcher": "claude4", "k": 2, "session_pct": 0.0,
   "weekly_pct": 45.0, "fable_pct": 0.0, "session_reset_h": 4.92, "weekly_reset_h": 64.0,
   "fable_reset_h": 64.0, "login_expires_h": 273.0, "session_reset_at": _t(295),
   "weekly_reset_at": _t(3840), "fable_reset_at": _t(3840), "login_expires_at": _t(16400)},
  {"acct": "next3", "auth": "ok", "launcher": "claude3", "k": 1, "session_pct": 0.0,
   "weekly_pct": 11.0, "fable_pct": 0.0, "session_reset_h": 4.58, "weekly_reset_h": 115.0,
   "fable_reset_h": 115.0, "login_expires_h": 690.0, "session_reset_at": _t(275),
   "weekly_reset_at": _t(6900), "fable_reset_at": _t(6900), "login_expires_at": _t(41400)},
  {"acct": "next2", "auth": "ok", "launcher": "claude2", "k": 4, "session_pct": 2.0,
   "weekly_pct": 51.0, "fable_pct": 0.0, "session_reset_h": 4.75, "weekly_reset_h": 42.0,
   "fable_reset_h": 42.0, "login_expires_h": 220.0, "session_reset_at": _t(285),
   "weekly_reset_at": _t(2520), "fable_reset_at": _t(2520), "login_expires_at": _t(13200)},
]
    wj, cached, prev = {"active": True, "permanent": True, "end": "2099-12-31"}, True, None'

@test "19 split lanes: the terse sibling names both picks on one row, so 15-21 cells fit a 10-row band" {
  cfg_as "$D/acct-split.json" next4 next2 next3 next
  printf '{"ts": %s}' "$(( $(date +%s) - 75 ))" > "$D/acct-split.json.cache.json"
  CLAUDE_ACCOUNTS_JSON="$D/acct-split.json" FIXTURE="$SPLIT_FIXTURE" \
    ca --readout --ladder --no-agents --max-wait 0 > "$D/ladder.json" || { cat "$D/ladder.json"; false; }
  run python3 -c "$LADDER_CHECK" "$D/ladder.json" "next,next4,next3,next2" 7
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 - "$D/ladder.json" <<'PY'
import json, re, sys, unicodedata
L = json.load(open(sys.argv[1]))
sgr = re.compile("\x1b\\[[0-9;]*m")
plain = lambda s: sgr.sub("", s).replace(" ", " ")
cells = lambda s: sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in plain(s))
lab = [v for v in L["variants"] if v.get("dense") and not v.get("terse")]
ter = [v for v in L["variants"] if v.get("terse")]
bad = []
top = plain(lab[-1]["lines"][0])
if "desk·fable → next2" not in top or "general → next" not in top:
    bad.append(f"the lanes do not split as on the real board: {top!r}")
for c in range(15, 22):
    d = [v for v in lab if v["width"] <= c][-1]
    t = [v for v in ter if d["cells"] <= v["cells"] and v["width"] <= c]
    least = min([len(d["lines"])] + [len(v["lines"]) for v in t])
    if least > 10:
        bad.append(f"{c} cells: {least} rows at the fewest (labelled {len(d['lines'])}), over a 10-row band")
    if not any(plain(v["lines"][0]) == "➤ next2 ➤ᵍ next" and v.get("lanes") == [15] for v in t):
        bad.append(f"{c} cells: no terse sibling says `➤ next2 ➤ᵍ next` on one lane row: "
                   f"{[plain(v['lines'][0]) for v in t]}")
    words = " ".join(plain(x) for x in d["lines"][:len(d.get("lanes") or [])])
    if "desk·fable" not in words or "general" not in words:
        bad.append(f"{c} cells: the labelled lanes lost their words: {words!r}")
for v in L["variants"]:
    lw = v.get("lanes")
    if not v.get("dense"):
        if lw is not None:
            bad.append(f"full {v['cells']}: ships `lanes`")
        continue
    if not lw or lw != [cells(x) for x in v["lines"][:len(lw)]]:
        bad.append(f"dense {v['cells']}: `lanes` {lw} is not its lane rows' cells")
    elif not plain(v["lines"][len(lw)]).lstrip().startswith(("used", "5-hour")):
        bad.append(f"dense {v['cells']}: the row after the lanes is no legend: {plain(v['lines'][len(lw)])!r}")
print("\n".join(bad[:12]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# THE FLOOR'S LANES (2026-10-22). Under 11 cells (12-15 columns) the agreeing lanes fell to three
# rows, `➤ all` / `lanes` / `→ next2`, and the desk pick's own weekly reset went under a 30-row
# pane's cue (probe3, `fin-live-rows30/band-08-15.png`). `➤ next2` holds them on one row down to
# the 7-cell floor, so all four of the desk pick's values sit in the band's first 9 rows.
# RED-proof: before, 7-10 cells had three lane rows and `2d3h` on row 10 or later.
@test "20 dense floor: agreeing lanes take one row at 7-11 cells; the desk pick's values clear a 10-row band's cue" {
  live_ladder 75 || { cat "$D/ladder.json"; false; }
  run python3 - "$D/ladder.json" <<'PY'
import json, re, sys
L = json.load(open(sys.argv[1]))
sgr = re.compile("\x1b\\[[0-9;]*m")
lab = [v for v in L["variants"] if v.get("dense") and not v.get("terse")]
bad = []
for c in range(7, 12):
    d = [v for v in lab if v["width"] <= c][-1]
    pl = [sgr.sub("", x).replace(" ", " ") for x in d["lines"]]
    want = "➤ use next2" if c >= 11 else "➤ next2"
    if pl[0] != want or d.get("lanes") != [len(want)]:
        bad.append(f"{c} cells: lanes {pl[:3]} ({d.get('lanes')}), not one row {want!r}")
    i = pl.index("next2") if "next2" in pl else 99
    seen = [t for x in pl[i + 1:9] for t in x.split()]
    vals = [t for t in seen if re.fullmatch(r"16%|37%|\d+h\d+m|2d3h", t)]
    if i >= 9 or len(vals) < 4:
        bad.append(f"{c} cells: the desk pick's values in the first 9 rows: {vals} (name at row {i})")
print("\n".join(bad[:12]))
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
