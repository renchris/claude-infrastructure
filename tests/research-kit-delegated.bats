#!/usr/bin/env bats
# research-kit-delegated — the standing delegated acceptance (REPORT.md §14, ruled 2026-10-16): the
# operator signs `cc-signoff research:<slug|*>/delegate` once, and an agent's `gate.sh accept` accepts a
# phase when its machine criteria hold (scripts/research-kit/lib/gate_accept.py). Contracts:
#   - the delegation and its revoke are operator signatures (claude ancestor refused, exit 3) in their
#     own log, each with a hash; an edited one is void;
#   - accept writes nothing without a delegation in force, refuses third reads, vetoes and the
#     delegation itself by name, and refuses (exit 1, nothing written) while any criterion is false;
#     each criterion case below fails ALONE, so a case refused by another guard reads red;
#   - an acceptance is a distinct record in delegated.jsonl, never in signoff.jsonl, and every reader
#     honours it exactly where it honours the operator's signature: requires (cert), row 1, the sweep's
#     spare and the passing run's close (frame), built-signed, close and render (implementation),
#     round cap, Stage 9 adoption, profile switch, decision extension, reopen;
#   - a revoke voids acceptances dated after it AND any line appended after it in the program's own
#     log (an acceptance's `at` is self-reported), keeps earlier ones, and a per-program revoke under
#     `*` ends only that program; renders say "accepted by delegation (not read by the operator)".
# Lead review of 58620fce6 (decision afc1; /tmp/tm2-review-224/FINDINGS-to-224.md), each case red on
# 58620fce6 for its finding: M1 frame `unsigned-base`/`never-signed` (no base pin: ACCEPTED); M2
# `acceptance-edited` and the frame's STALE on an acceptance.json edit (never verified); M3 the line
# copied below the revoke (read VALID by its `at`); M4 the contract page's profile line ("your
# signature"); m1 implementation `research-certificate`; m2 `frame-1.2`; m3 the reopen hidden by a
# touched certificate; m4 the quoted revoke line; m5 the unregistered per-program revoke; m6 the
# linked delegations log; m7 the delegated reopen and profile wording; m8 the race (ACCEPTED, exit 0).
# RED-proof (2026-10-16): on f6b1fbff2 every case fails: `gate.sh accept` is an invalid choice (argparse
# exit 2, no case's message) and cc-signoff refuses research:*/delegate as no research row.
# Per-site mutants (each on a scratch copy, each turned the named case red): research_records without
# the delegated merge (cert, frame, implementation, purchases, revoke); acceptance_verdict without the
# in_force check (revoke) or without the criteria check (the reader); each of the 4 cert, 4 frame and
# 4 implementation criteria forced true (its criterion case); the `already` check removed (cert, a
# second line written); delegated_line returning None (cert render); close_delta_rows' delegated
# wording reverted (frame); profile_switch_terms' cap reading `verdict(r)` again (purchases).

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh" CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  mkdir -p "$W"
  REC="$("$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W")"
  echo "$REC" > "$BATS_FILE_TMPDIR/records-path"
  # a real, passing gate run: CERT-v1 on disk, registry certified, and no certificate signature
  "$BATS_TEST_DIRNAME/../scripts/research-kit/gate.sh" run --program demo --consent-sealed-read > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "CERT-v1"
  ART="$W/artifact"
  mkdir -p "$ART"
  git -C "$ART" init -q
  git -C "$ART" config user.email t@example.com
  git -C "$ART" config user.name t
  echo one > "$ART/a.txt"
  git -C "$ART" add a.txt
  git -C "$ART" commit -qm built
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  I="$REPO/scripts/research-kit/intake.py"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key" CC_RESEARCH_OWNER="lead"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh" CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  ART="$(cd "$W/artifact" && pwd -P)"
  ACC="$CC_RESEARCH_HOME/demo/delegated.jsonl"
  SIG="$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

SIGNER() { "$REPO/tests/fixtures/research-kit/fixture_signer.py" "$@"; }
delegate() { SIGNER "research:${1:-*}/delegate" --because "zero human in loop" > /dev/null; }
acc() { "$G" accept --program demo "$@"; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
state() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])"; }
setstate() {
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_REGISTRY'; d=json.load(open(p)); d['programs'][0]['state']='$1'; json.dump(d, open(p, 'w'))"
}
jedit() { /usr/bin/python3 -c "import json; p='$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"; }
# ledit <jsonl> <python over r>: rewrite every line of a log
ledit() {
  /usr/bin/python3 -c "import json; p='$1'; rows=[json.loads(l) for l in open(p) if l.strip()]
for r in rows: $2
open(p, 'w').write(''.join(json.dumps(r, sort_keys=True) + '\n' for r in rows))"
}
# py <code>: the readers, with the libraries importable
py() {
  /usr/bin/python3 -c "import sys; sys.path[:0] = ['$REPO/scripts/research-kit/lib', '$REPO/scripts/research-kit', '$REPO/scripts/lib']
import operator_sign as o, kit
$1"
}
# fails: the criteria a refused accept printed as FAIL, sorted, space-joined
fails() { printf '%s\n' "$output" | sed -n 's/^  FAIL \([^:]*\):.*/\1/p' | sort | tr '\n' ' ' | sed 's/ $//'; }
kr_st() { /usr/bin/python3 -c "
import json; s = {}
for l in open('$REC/known_rows.jsonl'):
    if l.strip(): r = json.loads(l); s.setdefault(r['id'], {}).update(r)
print(s['$1'].get('status'))"; }

# ── the delegation ─────────────────────────────────────────────────────────────────────────────

@test "the delegate signoff: --because required, a claude ancestor refused, a misspelt program refused; a clean one is a hashed operator signature" {
  run SIGNER 'research:*/delegate'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *'delegate needs --because'* ]] || { echo "$output"; false; }
  ln -s /bin/bash "$BATS_TEST_TMPDIR/claude-fake-shell"
  # `; exit $?` keeps the fake shell alive as the CLI's parent (a lone -c command is exec'd in place)
  run "$BATS_TEST_TMPDIR/claude-fake-shell" -c "'$REPO/bin/cc-signoff' 'research:*/delegate' --because x; exit \$?"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"descended from a claude process"* ]] || { echo "$output"; false; }
  run SIGNER research:nosuch/delegate --because x
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"nosuch is not a registered program"* ]] || { echo "$output"; false; }
  run SIGNER 'research:*/revoke-delegation'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"nothing to revoke"* ]] || { echo "$output"; false; }
  [ "$(lines "$CC_RESEARCH_HOME/delegations.jsonl")" = 0 ]
  run SIGNER 'research:*/delegate' --because "zero human in loop"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"is in force for every program"* ]] || { echo "$output"; false; }
  # the revoke line it prints is quoted: unquoted, zsh globs research:*/… to "no matches found"
  [[ "$output" == *"cc-signoff 'research:*/revoke-delegation'"* ]] || { echo "$output"; false; }
  [ "$(lines "$CC_RESEARCH_HOME/delegations.jsonl")" = 1 ]
  run py 'd = o.delegation_records()[0]; print(d["_verdict"], d["provenance"]["chain"][0], d["id"] == d["sha256"][:12], o.delegation_for("demo")["id"] == d["id"])'
  [ "$output" = "valid fixture-signer True True" ] || { echo "$output"; false; }
  # a per-program revoke needs no registry entry: under `*` it ends that one program, registered or not
  run SIGNER research:nosuch/revoke-delegation
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py 'print(o.delegation_for("nosuch"), o.delegation_for("demo") is not None)'
  [ "$output" = "None True" ] || { echo "$output"; false; }
  # the fixture signer resolves every file it may write: a delegations log linked into the live store
  # is refused before cc-signoff runs (the row is one cc-signoff would refuse anyway, so a broken guard
  # fails this test without writing anything)
  live="$(/usr/bin/python3 -c "import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)")/.claude/autonomy/research"
  mkdir -p "$BATS_TEST_TMPDIR/linked"
  ln -s "$live/delegations.jsonl" "$BATS_TEST_TMPDIR/linked/delegations.jsonl"
  CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/linked" run SIGNER 'research:*/delegate'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"resolves into the live research store"* ]] || { echo "$output"; false; }
  [ "$(lines "$CC_RESEARCH_HOME/delegations.jsonl")" = 2 ]
  # one edited byte of what was signed voids it: the hash no longer matches, so nothing is in force
  ledit "$CC_RESEARCH_HOME/delegations.jsonl" 'r["because"] = "anything at all"'
  run py 'print(o.delegation_records()[0]["_verdict"], o.delegation_for("demo"))'
  [ "$output" = "void None" ] || { echo "$output"; false; }
}

@test "accept refuses with no delegation in force, and third reads, vetoes and the delegation itself by name, writing nothing" {
  run acc --action cert
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"no delegation is in force for demo"*"cc-signoff research:demo/delegate"* ]] || { echo "$output"; false; }
  delegate
  for c in 'third-read/v3.regex-missed'$'\t''sealed held-out stratum' 'veto/DR-1'$'\t''a veto overrules' \
           'delegate'$'\t''grant of authority' 'revoke-delegation'$'\t''the operator'"'"'s to end' \
           'extra-round'$'\t''needs --because' 'frame/x'$'\t''frame takes no target' \
           'profile'$'\t''profile names its target' 'adopt/stage8'$'\t''adopt/stage8 is not adoptable' \
           'sign'$'\t''not an action'; do
    run acc --action "${c%%$'\t'*}"
    [ "$status" -eq 2 ] || { echo "case ${c%%$'\t'*}: $output"; false; }
    [[ "$output" == *"${c#*$'\t'}"* ]] || { echo "case ${c%%$'\t'*}: $output"; false; }
  done
  [ "$(lines "$ACC")" = 0 ]
}

# ── cert ───────────────────────────────────────────────────────────────────────────────────────

@test "cert: accepted on its criteria into its own log; requires admits the wave as on a signature; render and the .md say the operator did not read it" {
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"CERT-v1 is not signed by the operator"*"nor accepted by delegation"* ]] || { echo "$output"; false; }
  delegate
  sig_before="$(lines "$SIG")"
  run acc --action cert
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "ACCEPTED research:demo/cert under delegation "*": accepted by delegation (not read by the operator)"* ]] || { echo "$output"; false; }
  [ "$(lines "$ACC")" = 1 ] || false
  [ "$(lines "$SIG")" = "$sig_before" ] || false
  run py 'import json; r = json.loads(open(o.acceptance_log("demo")).read())
print(r["kind"], sorted(r["pins"]), [c["name"] for c in r["criteria"]], r["delegation"]["id"] == o.delegation_for("demo")["id"])'
  [ "$output" = "delegated ['cert/CERT-v1.json'] ['state', 'newest-certificate', 'rows-pass', 'no-reopen'] True" ] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "CLEAR demo wave B1: CERT-v1"* ]] || { echo "$output"; false; }
  run "$G" render --program demo
  [[ "${lines[1]}" == "Accepted by delegation (not read by the operator): certificate CERT-v1 20"*"Z" ]] || { echo "$output"; false; }
  [[ "$(tail -1 "$REC/cert/CERT-v1.md")" == "Accepted by delegation (not read by the operator) "*"criteria state, newest-certificate, rows-pass, no-reopen held." ]] || { tail -2 "$REC/cert/CERT-v1.md"; false; }
  # accepting again writes nothing
  run acc --action cert
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "ALREADY research:demo/cert: accepted by delegation"* ]] || { echo "$output"; false; }
  [ "$(lines "$ACC")" = 1 ]
}

@test "cert: each criterion refuses alone when false, exit 1, nothing written" {
  for c in state newest-certificate rows-pass no-reopen; do
    rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
    delegate
    case "$c" in
      state) setstate registered; want="state" ;;
      newest-certificate) mv "$REC/cert/CERT-v1.json" "$BATS_TEST_TMPDIR/"; want="newest-certificate rows-pass" ;;
      rows-pass) jedit "$REC/cert/CERT-v1.json" 'd["rows"]["3"] = "FAIL"'; want="rows-pass" ;;
      # the reopen still counts after the certificate's file is touched to the future: the clock is
      # the certificate's own `issued`, not an mtime a re-checkout moves
      no-reopen) SIGNER research:demo/reopen --because "the operator reopened it" > /dev/null
                 touch -t 209901010000 "$REC/cert/CERT-v1.json"; want="no-reopen" ;;
    esac
    run acc --action cert
    [ "$status" -eq 1 ] || { echo "case $c: $output"; false; }
    [ "$(fails)" = "$want" ] || { echo "case $c: $output"; false; }
    [[ "$output" == "NOT ACCEPTED research:demo/cert"* ]] || { echo "case $c: $output"; false; }
    [ "$(lines "$ACC")" = 0 ] || { echo "case $c wrote"; false; }
  done
}

@test "the reader: an acceptance missing a criterion or naming no delegation is void; one whose certificate changed is stale; none of them admits a wave" {
  delegate; acc --action cert > /dev/null
  cp "$ACC" "$BATS_TEST_TMPDIR/acc"
  ledit "$ACC" 'r["criteria"] = r["criteria"][:3]'
  run py 'r = o.research_records("demo", "cert")[0]; print(r["_verdict"], r["_why"])'
  [ "$output" = "void its record does not show criteria no-reopen holding" ] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  cp "$BATS_TEST_TMPDIR/acc" "$ACC"
  ledit "$ACC" 'r["delegation"]["sha256"] = "0" * 64'
  run py 'r = o.research_records("demo", "cert")[0]; print(r["_verdict"], r["_why"])'
  [ "$output" = "void it names no delegation on record" ] || { echo "$output"; false; }
  cp "$BATS_TEST_TMPDIR/acc" "$ACC"
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # a veto or third read written in the acceptance shape is never one: the sweep and heldout read none
  cp "$BATS_TEST_TMPDIR/acc" "$BATS_TEST_TMPDIR/veto"; cp "$BATS_TEST_TMPDIR/acc" "$BATS_TEST_TMPDIR/read"
  ledit "$BATS_TEST_TMPDIR/veto" 'r["action"] = "veto"; r["target"] = "DR-1"'
  ledit "$BATS_TEST_TMPDIR/read" 'r["action"] = "third-read"; r["target"] = "v3.regex-missed"'
  cat "$BATS_TEST_TMPDIR/veto" "$BATS_TEST_TMPDIR/read" >> "$ACC"
  run py 'r = o.research_records("demo", "veto")[0]; print(r["_verdict"], r["_why"].split(":")[0], o.latest_valid("demo", "veto", "DR-1"))
r = o.research_records("demo", "third-read")[0]; print(r["_verdict"], r["_why"].split(":")[0])
import heldout; print(heldout.third_read_signatures("demo"))'
  [ "$output" = "$(printf 'void veto is never delegable None\nvoid third-read is never delegable\n{}')" ] || { echo "$output"; false; }
  cp "$BATS_TEST_TMPDIR/acc" "$ACC"
  printf ' ' >> "$REC/cert/CERT-v1.json"
  run py 'r = o.research_records("demo", "cert")[0]; print(r["_verdict"], r["_why"])'
  [ "$output" = "stale a pinned artifact changed after it" ] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "revoke: the verb refuses after it and an acceptance dated after it is void, an earlier one stands; a per-program revoke under * ends only that program" {
  delegate; acc --action cert > /dev/null
  run SIGNER research:demo/revoke-delegation
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"acceptances dated after this are void"* ]] || { echo "$output"; false; }
  run acc --action cert --check
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"no delegation is in force for demo"* ]] || { echo "$output"; false; }
  run py 'print(o.delegation_for("demo"), o.delegation_for("other") is not None)'
  [ "$output" = "None True" ] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "the acceptance made before the revoke no longer stands: $output"; false; }
  # the revoke also landed in demo's own log, so a line appended after it is void whatever time it
  # claims: here the earlier acceptance, copied below the revoke with its earlier `at` unchanged
  head -1 "$ACC" > "$BATS_TEST_TMPDIR/orig"
  grep -q '"kind": "revoke-marker"' "$ACC"
  cat "$BATS_TEST_TMPDIR/orig" >> "$ACC"
  run py 'r = o.research_records("demo", "cert"); print(r[0]["_verdict"], r[1]["_verdict"], r[1]["_why"].split(":")[0])'
  [[ "$output" == "valid void revoke "*" of its delegation "*" precedes it in the log" ]] || { echo "$output"; false; }
  head -2 "$ACC" > "$BATS_TEST_TMPDIR/two" && cp "$BATS_TEST_TMPDIR/two" "$ACC"
  # a revoke landing between the verb's delegation check and its write: the record it wrote reads
  # void, so the verb says VOID, exits 1, and nothing follows from it
  run py 'import gate; d = [x for x in o.delegation_records() if x["action"] == "delegate"][0]
o.delegation_for = lambda slug, at=None: d
sys.exit(gate.main(["accept", "--program", "demo", "--action", "reopen", "--because", "race"]))'
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == "VOID research:demo/reopen: written, but every reader reads it void"* ]] || { echo "$output"; false; }
  run py 'import gate; print(gate.reopened(gate.make_ctx("demo")))'
  [ "$output" = False ] || { echo "$output"; false; }
  head -2 "$ACC" > "$BATS_TEST_TMPDIR/two" && cp "$BATS_TEST_TMPDIR/two" "$ACC"
  # an acceptance dated after the revoke (hand-written: the verb refuses) is void, so it covers nothing
  ledit "$ACC" 'r["at"] = r["at"] + 3600; r["at_iso"] = "after the revoke"'
  run py 'r = o.research_records("demo", "cert")[0]; print(r["_verdict"], r["_why"])'
  [[ "$output" == "void its delegation "*" was not in force for demo at after the revoke (revoked before it, or given after it)" ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  # a newer delegation is in force again; the void record stays void, the verb accepts afresh
  delegate demo
  run acc --action cert
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "ACCEPTED research:demo/cert"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── frame ──────────────────────────────────────────────────────────────────────────────────────

# held_delta: KR-1 held after the fixture's frame signature (2026-09-30T00:00Z), its re-sign overdue,
# and a delta that carries it applied; frame.json is then v2 and its signature stale.
held_delta() {
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"descope","blocks_waves":["B2"],"ts":"2026-09-30T01:00:00Z"}\n' \
    >> "$REC/known_rows.jsonl"
  printf '%s' '{"program":"demo","base_version":1,"known_rows":["KR-1"],"why":"KR-1: the predicate undercounted trials","acceptance":[{"op":"replace","id":"AM-1","fields":{"predicate":"loses 0 writes in 2000 trials"}}]}' \
    > "$BATS_TEST_TMPDIR/delta.json"
  "$I" delta-apply --program demo --file "$BATS_TEST_TMPDIR/delta.json" > /dev/null
}

@test "frame: a delta carrying a held row is accepted; row 1, the sweep's spare and the passing run's close honour it as a re-sign" {
  held_delta; delegate
  run acc --action frame
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "ACCEPTED research:demo/frame under delegation "* ]] || { echo "$output"; false; }
  [[ "$output" == *"FD-1 wrote frame v2"* ]] || { echo "$output"; false; }
  # it pins the acceptance rows as well as the frame: an edit to either makes it STALE
  cp "$REC/acceptance.json" "$BATS_TEST_TMPDIR/acceptance.json"
  jedit "$REC/acceptance.json" 'd["rows"][0]["check_cmd"] = "true"'
  run py 'r = o.research_records("demo", "frame")[-1]; print(sorted(r["pins"]), r["_verdict"])'
  [ "$output" = "['acceptance.json', 'frame.json'] stale" ] || { echo "$output"; false; }
  cp "$BATS_TEST_TMPDIR/acceptance.json" "$REC/acceptance.json"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(kr_st KR-1)" = open ] || { cat "$REC/known_rows.jsonl"; false; }
  git -C "$REC" add -A && git -C "$REC" commit -qm "FD-1, accepted"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"frame pin "*" accepted by delegation (not read by the operator) 20"* ]] || { echo "$output"; false; }
  [[ "$output" == *"closed known row KR-1 (frame-delta cycle: frame accepted by delegation (not read by the operator) "*" carries KR-1, certificate re-issued as CERT-v2)"* ]] || { echo "$output"; false; }
  [ "$(kr_st KR-1)" = closed ]
  run "$G" render --program demo
  [[ "${lines[1]}" == "Accepted by delegation (not read by the operator): frame 20"*"Z" ]] || { echo "$output"; false; }
}

@test "frame: each criterion refuses alone when false, exit 1, nothing written" {
  for c in no-delta changed-after unsigned-base never-signed acceptance-edited legacy-delta row-closed lint annotation; do
    rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
    delegate
    case "$c" in
      no-delta) want="acceptance-unchanged base-is-signed known-rows-open newest-change-is-delta" ;;
      # the frame changed unsigned BEFORE the delta: the delta's base is not the frame last signed
      unsigned-base) "$I" set --program demo --escape-cost-days 9 > /dev/null; held_delta; want="base-is-signed" ;;
      never-signed) held_delta; : > "$SIG"; want="base-is-signed" ;;
      # the rows the frame's checks run, edited after the delta (a check_cmd that can no longer fail)
      acceptance-edited) held_delta; jedit "$REC/acceptance.json" 'd["rows"][0]["check_cmd"] = "true"'; want="acceptance-unchanged" ;;
      changed-after) held_delta; "$I" set --program demo --escape-cost-days 9 > /dev/null; want="newest-change-is-delta" ;;
      legacy-delta) held_delta; ledit "$REC/frame-deltas.jsonl" 'r.pop("frame_sha256")'; want="newest-change-is-delta" ;;
      row-closed) held_delta; printf '{"id":"KR-1","status":"closed","closed_by":"default"}\n' >> "$REC/known_rows.jsonl"; want="known-rows-open" ;;
      lint) held_delta; printf '{"id":"CR-1","status":"open","origin":"operator"}\n' >> "$REC/changes.jsonl"; want="lint" ;;
      annotation) held_delta; printf '{"id":"DR-1","annotation":"DA-1","question":"retry policy, restated"}\n' >> "$REC/decisions.jsonl"; want="annotations-pinned lint" ;;
    esac
    run acc --action frame
    [ "$status" -eq 1 ] || { echo "case $c: $output"; false; }
    [ "$(fails)" = "$want" ] || { echo "case $c: $output"; false; }
    [ "$(lines "$ACC")" = 0 ] || { echo "case $c wrote"; false; }
  done
}

# ── implementation ─────────────────────────────────────────────────────────────────────────────

# built_certified: under the delegation, the certificate and Stage 9's adoption accepted, the artifact
# frozen, and a built certificate with rows 20-25 PASS on the frozen snapshot; registry build-certified.
built_certified() {
  delegate
  acc --action cert > /dev/null
  acc --action adopt/stage9 --because "Stage 9 under the delegation" > /dev/null
  "$G" built-freeze --program demo --artifact "$ART" --wave W1 > /dev/null
  sha="$(/usr/bin/python3 -c "import json; print(json.load(open('$REC/built/freeze.json'))['snapshot_sha'])")"
  printf '{"cert":"BUILT-CERT-v1","program":"demo","version":1,"issued":"%s","snapshot_sha":"%s","rows":{"20":"PASS","21":"PASS","22":"PASS","23":"PASS","24":"PASS","25":"PASS"}}\n' \
    "$CC_NOW" "$sha" > "$REC/built/BUILT-CERT-v1.json"
  printf 'Built: demo built certificate version 1\n' > "$REC/built/BUILT-CERT-v1.md"
  setstate build-certified
}

@test "implementation: each criterion refuses alone; then the acceptance moves the registry, close admits it and render says it" {
  built_certified
  cp "$REC/built/BUILT-CERT-v1.json" "$BATS_TEST_TMPDIR/bc.json"
  cp "$SIG" "$BATS_TEST_TMPDIR/sig"
  for c in state newest-built-certificate rows-pass freeze-snapshot research-certificate; do
    cp "$BATS_TEST_TMPDIR/bc.json" "$REC/built/BUILT-CERT-v1.json"; setstate build-certified
    case "$c" in
      state) setstate build-certifying ;;
      newest-built-certificate) jedit "$REC/built/BUILT-CERT-v1.json" 'd["program"] = "other"' ;;
      rows-pass) jedit "$REC/built/BUILT-CERT-v1.json" 'd["rows"]["22"] = "FAIL"' ;;
      freeze-snapshot) jedit "$REC/built/BUILT-CERT-v1.json" 'd["snapshot_sha"] = "0" * 40' ;;
      # row 20 re-read at the acceptance: a reopen after the research certificate refuses it
      research-certificate) SIGNER research:demo/reopen --because "the operator reopened it" > /dev/null ;;
    esac
    run acc --action implementation
    [ "$status" -eq 1 ] || { echo "case $c: $output"; false; }
    [ "$(fails)" = "$c" ] || { echo "case $c: $output"; false; }
  done
  cp "$BATS_TEST_TMPDIR/bc.json" "$REC/built/BUILT-CERT-v1.json"; setstate build-certified
  cp "$BATS_TEST_TMPDIR/sig" "$SIG"
  run "$G" close --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"carries no operator signature or delegated acceptance"* ]] || { echo "$output"; false; }
  run acc --action implementation
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"IMPLEMENTATION-SIGNED demo: BUILT-CERT-v1 accepted by delegation (not read by the operator) 20"*"registry -> implementation-signed"* ]] || { echo "$output"; false; }
  [ "$(state)" = implementation-signed ]
  grep -q '^Accepted by delegation (not read by the operator) ' "$REC/built/BUILT-CERT-v1.md"
  run "$G" render --program demo
  [[ "${lines[${#lines[@]}-1]}" == "Built: certified $CC_NOW (BUILT-CERT-v1) · implementation accepted by delegation (not read by the operator) 20"*"Z" ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1 --after-signoff
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$G" close --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(state)" = closed ] || { echo "$output"; false; }
}

# ── the purchases ──────────────────────────────────────────────────────────────────────────────

@test "purchases: extra-round, adopt, extend-decision, profile and reopen accept on the kit's own conditions and caps, and their readers honour each" {
  delegate
  # extra round set: only while certifying; once per program; the round cap reads it
  run acc --action extra-round --because "the bound is still wide"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = state ] || { echo "$output"; false; }
  setstate certifying
  run py 'import round; print(round.extra_round_granted("demo"))'
  [ "$output" = False ]
  acc --action extra-round --because "the bound is still wide" > /dev/null
  run py 'import round; print(round.extra_round_granted("demo"))'
  [ "$output" = True ] || { echo "$output"; false; }
  run acc --action extra-round --because "again"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = once-per-program ] || { echo "$output"; false; }
  # profile switch: profile_switch_terms decides (narrower, between rounds, once); kit.profile_switch reads it
  run acc --action profile/lite --because "narrow the remaining rounds"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"FAIL switch-terms: \"lite is not narrower than lite"* ]] || { echo "$output"; false; }
  jedit "$REC/frame.json" 'd["profile"] = "standard"'
  acc --action profile/lite --because "narrow the remaining rounds" > /dev/null
  run py 'print(kit.profile_switch("demo")["to"], kit.profile_switch("demo")["from"])'
  [ "$output" = "lite standard" ] || { echo "$output"; false; }
  # the contract page's profile line says the switch was accepted by delegation, never "your signature"
  run py 'import json, intake
fr = json.load(open(str(kit.records_dir("demo") / "frame.json")))
f = dict(found=1, desk_n95=1, r_max=6, rounds_counted=3, inputs=3, found_raw=1, n_hat=1, false_material_share=0,
         false_material_source="fixture", desk_mean=0.1, invisible_mean=0.1, invisible_bound95=1, p_any=0.1)
print(intake.measured_profile_lines("demo", fr, kit.profile(fr["profile"]), f, 14.0, 28.0)[0])'
  [[ "$output" == "## Profile: lite from round 4 (standard through round 3; switch accepted by delegation (not read by the operator) 20"*"Z)" ]] || { echo "$output"; false; }
  run acc --action profile/lite --because "again"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"one profile switch per program is already accepted by delegation (not read by the operator)"* ]] || { echo "$output"; false; }
  # Stage 9 adoption: a pre-1.2 frame, once; stage9_applies reads it
  run py 'print(kit.stage9_applies("demo", {}))'
  [ "$output" = False ]
  acc --action adopt/stage9 --because "Stage 9 under the delegation" > /dev/null
  run py 'print(kit.stage9_applies("demo", {}))'
  [ "$output" = True ] || { echo "$output"; false; }
  run acc --action adopt/stage9 --because again
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = once-per-program ] || { echo "$output"; false; }
  # decision extension: only where the menu offers one (a 1.2 frame, research can still raise it),
  # once per decision
  run acc --action extend-decision/DR-1 --because "more probes"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = "frame-1.2 research-can-raise-it" ] || { echo "$output"; false; }
  jedit "$REC/frame.json" 'd["method_version"] = "1.2"'
  printf '%s\n' '{"id":"DR-2","question":"cache size","status":"open","options":[{"label":"a"},{"label":"b"}],"tally":{"premises":["PR-9"]},"timebox_days":1,"research_started":"2026-10-01T00:00:00Z"}' >> "$REC/decisions.jsonl"
  acc --action extend-decision/DR-2 --because "more probes" > /dev/null
  run py 'import blockers; print(blockers.extensions("demo", "DR-2"))'
  [ "$output" = 1 ] || { echo "$output"; false; }
  run acc --action extend-decision/DR-2 --because again
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = once-per-decision ] || { echo "$output"; false; }
  # reopen: after a certificate, once per certificate; `gate.sh run` honours it
  setstate certified
  acc --action reopen --because "a premise moved" > /dev/null
  run acc --action reopen --because again
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(fails)" = not-reopened ] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [[ "$output" == *"a reopen accepted by delegation (not read by the operator) is recorded after the newest certificate"* ]] || { echo "$output"; false; }
  run "$G" run --program demo
  [[ "$output" == *"REOPENED demo by a reopen accepted by delegation (not read by the operator); registry -> registered"* ]] || { echo "$output"; false; }
  [ "$(state)" = registered ]
  # none of the purchases went to the operator's log
  [ ! -e "$SIG" ] || ! grep -qE '"action": "(extra-round|profile|adopt|extend-decision|reopen)"' "$SIG"
}
