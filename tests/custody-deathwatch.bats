#!/usr/bin/env bats
# scripts/custody-deathwatch.sh — the out-of-process arm of the custody invariant.
#
# WHAT IS PINNED, and why each case exists:
#   · the three-valued oracle (ALIVE never reported · GONE reported at any age · UNKNOWN never
#     mints a death) — the false-death direction the subject's header calls the worse one;
#   · THE ORACLE-INDEPENDENT FLOOR — a stale row is reported even when BOTH oracles are blind.
#     This is the case that would have caught the measured six-day silence: cloud-return.sh
#     abstained correctly on a 401 control plane for six days and told nobody, which is the same
#     silence with better manners;
#   · detection is NOT disposition — a pass never discharges custody, at any oracle verdict;
#   · the latch — one report per peer ever, so a 155-row standing pile cannot become the
#     always-firing alarm that carries as many bits as one that never fires;
#   · the deployed-copy guard — a checkout/suite copy may never write to the operator's stores.
#
# TWO ARMS PER BUG. The subject is a NEW file, so "run it against the parent sha" would compare the
# fix to an empty path and go green for the wrong reason — a vacuous red-proof. Both regression
# cases below therefore reconstruct the REAL pre-fix line as an ANCHOR-CHECKED MUTANT: the sed is
# asserted to have changed something before the mutant is run, so a rotted anchor fails loudly
# instead of silently certifying a subject that no longer contains the bug.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO_ROOT/scripts/custody-deathwatch.sh"
  CUSTODY="$REPO_ROOT/bin/cc-custody"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_DEATHWATCH_STATE="$BATS_TEST_TMPDIR/dw"
  export CC_DEATHWATCH_DEPLOYED=1           # the guard is pinned separately, below
  export CC_DEATHWATCH_CUSTODY_BIN="$CUSTODY"

  BINS="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BINS"
  NOTIFIED="$BATS_TEST_TMPDIR/notified.log"
  FILED="$BATS_TEST_TMPDIR/filed.log"
  : > "$NOTIFIED"; : > "$FILED"

  # cc-notify stub — records <target> <msg>
  cat > "$BINS/cc-notify" <<STUB
#!/usr/bin/env bash
printf '%s\t%s\n' "\$1" "\$2" >> "$NOTIFIED"
STUB
  # cc-backlog stub — records the filed step
  cat > "$BINS/cc-backlog" <<STUB
#!/usr/bin/env bash
shift  # drop the 'needs' verb
printf '%s\n' "\$1" >> "$FILED"
STUB
  chmod +x "$BINS/cc-notify" "$BINS/cc-backlog"
  export CC_DEATHWATCH_NOTIFY_BIN="$BINS/cc-notify"
  export CC_DEATHWATCH_BACKLOG_BIN="$BINS/cc-backlog"

  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
}

# pane_oracle <ids…> — a working cc-pane whose `list` prints exactly these ids
pane_oracle() {
  { printf '#!/usr/bin/env bash\n[ "$1" = list ] || exit 0\n'
    for id in "$@"; do printf 'printf "%%s\\n" %q\n' "$id"; done
  } > "$BINS/cc-pane"
  chmod +x "$BINS/cc-pane"; export CC_DEATHWATCH_PANE_BIN="$BINS/cc-pane"
}
# blind_pane_oracle — present but FAILS. Distinct from absent: the subject must read the rc.
blind_pane_oracle() {
  printf '#!/usr/bin/env bash\nexit 7\n' > "$BINS/cc-pane"
  chmod +x "$BINS/cc-pane"; export CC_DEATHWATCH_PANE_BIN="$BINS/cc-pane"
}
blind_cloud_oracle() {
  printf '#!/usr/bin/env bash\nprintf "HTTP 401 token expired\\n" >&2\nexit 4\n' > "$BINS/cc-cloud"
  chmod +x "$BINS/cc-cloud"; export CC_DEATHWATCH_CLOUD_BIN="$BINS/cc-cloud"
}
cloud_oracle() { # <id>=<state> …
  { printf '#!/usr/bin/env bash\ncat <<JSON\n[\n'
    local first=1
    for kv in "$@"; do
      [ "$first" = 1 ] || printf ',\n'; first=0
      printf '  {"id":"%s","state":"%s"}' "${kv%%=*}" "${kv##*=}"
    done
    printf '\n]\nJSON\n'
  } > "$BINS/cc-cloud"
  chmod +x "$BINS/cc-cloud"; export CC_DEATHWATCH_CLOUD_BIN="$BINS/cc-cloud"
}

# backdate <marker> <hours> — rewrite the open row's ts so `stale` is derivable without sleeping
backdate() {
  local marker="$1" hours="$2" f
  for f in "$CC_CUSTODY_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    local tmp="$f.tmp"
    jq -c --arg m "$marker" --arg ts "$(date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ)" \
      'if .marker == $m then .ts = $ts else . end' "$f" > "$tmp" && mv "$tmp" "$f"
  done
}

# ── the invariant ────────────────────────────────────────────────────────────────────────────────

@test "a GONE peer is reported at ANY age — the abnormal-death fast path" {
  pane_oracle 100 200
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-DEAD --slug fire-killed --originator-pane 100
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone=1"* ]] || false
  # originator pane 100 IS alive ⇒ it learns directly, on the channel it already reads
  [ "$(grep -c 'M-DEAD\|fire-killed' "$NOTIFIED")" -ge 1 ]
  [ "$(grep -c '^100	' "$NOTIFIED")" -eq 1 ]
}

@test "an ALIVE peer is NEVER reported, however old the debt" {
  pane_oracle 100 555
  "$CUSTODY" open --cwd "$WT" --target 555 --marker M-LIVE --slug fire-working --originator-pane 100
  backdate M-LIVE 500
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alive=1"* ]] || false
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 0 ]
}

@test "THE ORACLE-INDEPENDENT FLOOR: both oracles blind, a STALE row is still reported" {
  # This is the six-day-silence case. Nothing can be measured about the peer; the report must
  # exist anyway, sourced from the row's own ts.
  blind_pane_oracle; blind_cloud_oracle
  "$CUSTODY" open --cwd "$WT" --target "cloud:session_X" --marker M-STALE --slug cloud-session_X
  backdate M-STALE 200
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown=1"* ]] || false
  [[ "$output" == *"gone=0"* ]] || false  # a blind oracle may never mint a death…
  [ "$(grep -c . "$FILED")" -eq 1 ]        # …but the operator is told regardless
}

@test "a blind oracle NEVER mints a death for a FRESH row" {
  blind_pane_oracle; blind_cloud_oracle
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-FRESH --slug fire-new
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown=1"* ]] || false
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 0 ]
}

@test "detection is NOT disposition — a pass never discharges custody" {
  pane_oracle 100
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-KEEP --slug fire-killed --originator-pane 100
  [ "$("$CUSTODY" count --open --cwd "$WT")" = 1 ]
  bash "$SUBJ" >/dev/null
  [ "$("$CUSTODY" count --open --cwd "$WT")" = 1 ]
  bash "$SUBJ" >/dev/null
  [ "$("$CUSTODY" count --open --cwd "$WT")" = 1 ]
}

@test "the latch reports each peer ONCE, ever" {
  pane_oracle 100
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-ONCE --slug fire-killed --originator-pane 100
  bash "$SUBJ" >/dev/null
  local first; first="$(grep -c . "$NOTIFIED")"
  [ "$first" -eq 1 ]
  run bash "$SUBJ"
  [[ "$output" == *"latched=1"* ]] || false
  [ "$(grep -c . "$NOTIFIED")" -eq 1 ]
}

@test "no reachable originator ⇒ ONE aggregated operator row, not one per peer" {
  pane_oracle 100
  local i
  for i in 1 2 3 4 5; do
    "$CUSTODY" open --cwd "$WT" --target "90$i" --marker "M-AGG$i" --slug "fire-agg$i"
  done
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone=5"* ]] || false
  [ "$(grep -c . "$FILED")" -eq 1 ]           # ONE row, not five
  [ "$(grep -c '5 dispatched peer' "$FILED")" -eq 1 ]
}

@test "an originator pane that is itself DEAD falls through to the operator row" {
  pane_oracle 100                                   # 777 is not alive
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-ORPH --slug fire-orphan --originator-pane 777
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 1 ]
}

@test "notifyBack addresses the direct notify when originatorPane is absent — the cloud lane's whole population" {
  # RED-PROOF. This pass read ONLY `originatorPane`, while scripts/wrap-ledger.sh:1020 and
  # hooks/session-continue.sh:655 both treat `notifyBack` as an equal spelling of the same
  # ownership. Measured 2026-09-10: 347 of 347 cloud custody rows opened since the 2026-08-25
  # cutover carry notifyBack and ZERO carried originatorPane — so the ENTIRE cloud lane took the
  # aggregated ADDRESS-2 path while the pane that fired it was named in the row and alive.
  pane_oracle 100 200
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-NB --slug fire-nb --notify-back 200
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$NOTIFIED")" -eq 1 ]
  grep -q '^200	' "$NOTIFIED" || false
  [ "$(grep -c . "$FILED")" -eq 0 ]            # it was DELIVERED, so nothing aggregates
}

@test "originatorPane still WINS over notifyBack when both name a live pane" {
  # EQUIVALENCE GUARD: the fallback must not reorder the incumbent. Green in both arms, so its power
  # is the mutant — swap the loop's candidate order and this dies while the arm above stays green.
  pane_oracle 100 200
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-BOTH --slug fire-both \
    --originator-pane 100 --notify-back 200
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$NOTIFIED")" -eq 1 ]
  grep -q '^100	' "$NOTIFIED" || false
}

@test "a notifyBack that is not a pane id degrades to the operator row, never a bogus notify" {
  # NEGATIVE CONTROL, and the reason the fallback needs no validator of its own. handoff-fire arms
  # notifyBack as either a bare pane ("415") or a "<worktree>-<pane>" slug ("wt-pool-2-415"); the
  # latter is not in `cc-pane list`, peer_disposition's EXACT-membership branch calls it GONE, and
  # the row falls to ADDRESS 2 — precisely the pre-change behaviour. Without this arm the fallback
  # could be shipping cc-notify calls at addresses that name nothing.
  pane_oracle 100
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-SLUG --slug fire-slug --notify-back wt-pool-2-415
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 1 ]
}

@test "the deployed-copy guard: a checkout copy is INERT and says so" {
  pane_oracle 100
  "$CUSTODY" open --cwd "$WT" --target 999 --marker M-GUARD --slug fire-killed --originator-pane 100
  CC_DEATHWATCH_DEPLOYED=0 run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not the deployed copy"* ]] || false
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 0 ]
}

@test "the store-wide read sees a shard no --cwd consumer would (the launchd '/' case)" {
  pane_oracle 100
  "$CUSTODY" open --cwd / --target "cloud:session_Y" --marker M-ROOT --slug cloud-session_Y
  backdate M-ROOT 200
  blind_cloud_oracle
  # the cwd-scoped view every OTHER consumer uses is blind to it…
  [ "$("$CUSTODY" count --open --cwd "$WT")" = 0 ]
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$FILED")" -eq 1 ]        # …this one is not
}

@test "cloud states map correctly: ALIVE stays, ABANDONED is a death, unlisted is UNKNOWN" {
  blind_pane_oracle
  cloud_oracle session_A=ALIVE session_B=ABANDONED
  "$CUSTODY" open --cwd / --target "cloud:session_A" --marker M-CA --slug cloud-session_A
  "$CUSTODY" open --cwd / --target "cloud:session_B" --marker M-CB --slug cloud-session_B
  "$CUSTODY" open --cwd / --target "cloud:session_C" --marker M-CC --slug cloud-session_C
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alive=1"* ]] || false
  [[ "$output" == *"gone=1"* ]] || false
  [[ "$output" == *"unknown=1"* ]]
}

# ── regression arms — each replays a REAL bug this subject shipped and then fixed ────────────────

@test "REGRESSION (arm 2): a marker-less row must not shift its fields into a FALSE DEATH" {
  # THE REAL BUG, measured on the live store 2026-08-23. The row loop read jq @tsv with
  # `IFS=$'\t' read -r …`. Tab is IFS WHITESPACE, so bash strips leading runs of it: the one open
  # row with a NULL marker shifted every field one position left, `target` became a cwd PATH (in no
  # pane list ⇒ GONE), and the pass judged a session that was RUNNING AT THAT MOMENT to be dead,
  # addressing its notice to "pane 0" — which was the age field.
  pane_oracle 602
  "$CUSTODY" open --cwd "$WT" --target 602 --slug fire-no-marker --originator-pane 102   # NO --marker

  # THE MUTANT MUST MODEL THE CURRENT SUBJECT, NOT A FROZEN SNAPSHOT OF IT. This reconstruction
  # hard-codes the positional field LIST, so every field the real loop gains has to be added here
  # too — the loop body it splices in is the subject's own, and a field it reads but the @tsv feed
  # never supplies is an `unbound variable` under `set -u`, i.e. a red that indicts the diff rather
  # than the reader. `notifyBack` was added 2026-09-10 for the ADDRESS-1 fallback and appears here
  # in the SAME position the subject's own @sh line uses; the regression under test — tab is IFS
  # whitespace, so a NULL leading field shifts every column left — is unchanged by the arity.
  #
  # arm 2 — the pre-fix subject, reconstructed as an ANCHOR-CHECKED mutant. The swap is an exact
  # whole-line replacement (python, not sed): the jq program carries `|`, `\(`, `"` and `//`, and a
  # sed expression escaping all four is unreadable AND silently no-ops when one escape rots — which
  # is exactly what the anchor check below exists to refuse.
  local mutant="$BATS_TEST_TMPDIR/mutant.sh"
  python3 - "$SUBJ" "$mutant" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
out, dropped, swapped_loop, swapped_feed = [], 0, 0, 0
for line in open(src):
    s = line.rstrip('\n')
    if s == 'while IFS= read -r _asn; do':
        out.append("while IFS=$'\\t' read -r marker slug target cwd opane nb age stale; do"); swapped_loop += 1; continue
    if s.startswith('  marker="" slug=') or s == '  eval "$_asn"' or s == '  [ -n "$_asn" ] || continue':
        dropped += 1; continue
    if '@sh "marker=' in s:
        out.append("""$(printf '%s' "$OPEN_JSON" | jq -r '.[] | [(.marker//""),(.slug//""),(.targetPane//""),"""
                   """(.cwd//""),(.originatorPane//""),(.notifyBack//""),((.ageHours|tostring)//"?"),((.stale|tostring))] | @tsv')""")
        swapped_feed += 1; continue
    out.append(s)
assert swapped_loop == 1 and swapped_feed == 1 and dropped == 3, (swapped_loop, swapped_feed, dropped)
open(dst, 'w').write('\n'.join(out) + '\n')
PY
  # ANCHOR CHECK — a mutant identical to the subject would make this arm vacuous
  ! diff -q "$SUBJ" "$mutant" >/dev/null || false
  [ "$(grep -c "IFS=\\\$'\\\\t' read -r marker" "$mutant")" -eq 1 ]
  # anchored on the FEED line, not on the bare token: the cloud oracle's own jq uses @tsv
  # legitimately (line ~144), so a bare '@tsv' anchor counts 2 and proves nothing about the swap.
  [ "$(grep -c 'OPEN_JSON.*@tsv' "$mutant")" -eq 1 ]
  [ "$(grep -c '@sh "marker=' "$mutant")" -eq 0 ]

  run bash "$mutant"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone=1"* ]] || false # arm 2 IS RED: the live pane is called dead

  : > "$NOTIFIED"; : > "$FILED"; rm -rf "$CC_DEATHWATCH_STATE"
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alive=1"* ]] || false # arm 1 is GREEN: pane 602 is alive and stays unreported
  [[ "$output" == *"gone=0"* ]] || false
  [ "$(grep -c . "$NOTIFIED")" -eq 0 ]
}

@test "REGRESSION (arm 2): pane liveness is EXACT, not a substring match" {
  # The first oracle used `index($0, want)`, so a dead pane 60 matched live 602/600/605 and was
  # reported ALIVE — a death this file exists to catch, silently dropped.
  pane_oracle 602 600 605
  "$CUSTODY" open --cwd "$WT" --target 60 --marker M-SUB --slug fire-substr --originator-pane 602

  local mutant="$BATS_TEST_TMPDIR/mutant2.sh"
  sed 's|awk -v want="\$tp" .{gsub(/\^\[ \\t\]+\|\[ \\t\]+\$/,"")} \$0==want {n++} END{print n+0}.|awk -v want="$tp" '"'"'index($0, want) { n++ } END { print n+0 }'"'"'|' \
      "$SUBJ" > "$mutant"
  ! diff -q "$SUBJ" "$mutant" >/dev/null || false
  [ "$(grep -c 'index(\$0, want)' "$mutant")" -eq 1 ]

  run bash "$mutant"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alive=1"* ]] || false # arm 2 IS RED: dead pane 60 passes as alive off 602
  [[ "$output" == *"gone=0"* ]] || false

  : > "$NOTIFIED"; : > "$FILED"; rm -rf "$CC_DEATHWATCH_STATE"
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone=1"* ]] || false # arm 1 is GREEN: pane 60 is correctly dead
  [ "$(grep -c . "$NOTIFIED")" -eq 1 ]
}

@test "REGRESSION: an oracle whose rows carry NO state field is BLIND, not a store of UNKNOWNs" {
  # THE REAL BUG. `cc-cloud list --json` (no --state) exits 0 with 149 KB of rows that have no
  # `state` key. The first oracle read that, mapped every row through `.state // "UNKNOWN"` and set
  # CLOUD_OK=1 — logging `cloud_oracle_ok:true` while knowing nothing. The row-level answer is the
  # same either way (UNKNOWN), so ONLY the ledger flag can tell a working sensor from a blind one,
  # and a blind sensor claiming success is how a six-day outage stays invisible.
  blind_pane_oracle
  # a stateless-but-successful oracle: exit 0, well-formed rows, no `state` key anywhere
  cat > "$BINS/cc-cloud" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
[{"id":"session_A","branch":"b1","account":"next"},{"id":"session_B","branch":"b2","account":"next"}]
JSON
STUB
  chmod +x "$BINS/cc-cloud"; export CC_DEATHWATCH_CLOUD_BIN="$BINS/cc-cloud"

  "$CUSTODY" open --cwd / --target "cloud:session_A" --marker M-NOSTATE --slug cloud-session_A
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.pass=="complete") | .cloud_oracle_ok' "$CC_DEATHWATCH_STATE/deathwatch.jsonl" | tail -1)" = "false" ]

  # and the control: the SAME shape WITH a state field must read as a working oracle
  rm -rf "$CC_DEATHWATCH_STATE"
  cloud_oracle session_A=ALIVE
  run bash "$SUBJ"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.pass=="complete") | .cloud_oracle_ok' "$CC_DEATHWATCH_STATE/deathwatch.jsonl" | tail -1)" = "true" ]
}

@test "selftest passes (the oracle truth table, independent of any store)" {
  run bash "$SUBJ" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest: PASS"* ]]
}
