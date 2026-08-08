#!/usr/bin/env bats
# cc-authstore-probe — HERMETIC verdict tests + the real-artifact control.
#
# The fixtures are VERBATIM excerpts of the 2.1.220 bundle (the composite credential store, the
# keychain writer, the constant table), not hand-written approximations — a control that replays a
# paraphrase passes vacuously (memory: control-must-replay-the-real-artifact). Each mutant flips
# exactly ONE thing away from that excerpt, so a green run means the probe discriminates on the
# mechanism and not on the fixture's general shape.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROBE="$REPO/scripts/cc-authstore-probe.sh"
  GATE="$REPO/scripts/cc-upgrade-gate.sh"
  CHECK14="$REPO/lib/cc-upgrade-gate/check14_authstore.sh"

  # The real-artifact control needs the installed 2.1.220 bundle, so resolve its path from the
  # AMBIENT home FIRST — then fixture $HOME, so nothing else in this suite (notably check14's
  # `$HOME/.claude/scripts/…` probe fallback) can reach live state. Read-only either way: no test
  # here writes outside $BATS_TEST_TMPDIR.
  REAL_BIN="$HOME/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  export REPO PROBE GATE CHECK14 REAL_BIN
}

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────
# The keychain writer + the constant table, verbatim from 2.1.220. `_QT_`/`_ARGV_` are placeholders
# so one test can prove the constants are EXTRACTED and not echoed back from the probe's baseline.
_writer() {
  local qt="${1:-2000}" argv="${2:-4032}"
  cat <<EOF
var _Qt=$qt,Lcg=$argv,Mcg=44,Ncg=36,Q5i,YJn;
EOF
  cat <<'EOF'
Q5i={name:"keychain",async update(e){iG();try{let t=oG(j1e),r=_q(),n=Ie(e),o=Buffer.from(n,"utf-8").toString("hex"),i=`add-generic-password -U -a "${r}" -s "${t}" -X "${o}"
`,s;if(i.length<=Lcg)s=await ax("security",["-i"],{input:i,stdio:["pipe","pipe","pipe"],reject:!1,timeout:_Qt});else w(`Keychain payload (${n.length}B JSON) exceeds security -i stdin limit; using argv`,{level:"warn"}),s=await ax("security",["add-generic-password","-U","-a",r,"-s",t,"-X",o],{stdio:["ignore","pipe","pipe"],reject:!1,timeout:_Qt});if(s.exitCode!==0)return{success:!1,transient:s.timedOut};return NI.cache={data:e,cachedAt:Date.now()},{success:!0}}catch(t){return{success:!1}}}};
EOF
}

# the plaintext store + the composite, verbatim. The composite's transient arm is what STATUS-QUO is.
_plaintext_store() { printf '%s\n' 'XJn={name:"plaintext",read(){let{storagePath:e}=JJn();try{return Ut(Jt().readFileSync(e,{encoding:"utf8"}))}catch{return null}}};'; }

_composite_with_skip() {
  cat <<'EOF'
function bFc(e,t){let r={name:`${e.name}-with-${t.name}-fallback`,async update(n){let o=await e.readAsync(),i=await e.update(n);if(i.success){if(o===null)await t.delete();return be("secure_storage_credentials_write"),i}if(i.transient)return Ne("secure_storage_credentials_write","primary_transient_skip_fallback"),i;let s=await t.update(n);if(s.success){if(o!==null)await e.delete();return Ne("secure_storage_credentials_write","plaintext_fallback_used"),{success:!0,warning:s.warning}}return pe("secure_storage_credentials_write","primary_and_fallback_failed"),{success:!1}}};return r}
EOF
}

# the ONE-THING mutant: the transient early-return is deleted, so a failed write reaches the fallback.
_composite_without_skip() {
  cat <<'EOF'
function bFc(e,t){let r={name:`${e.name}-with-${t.name}-fallback`,async update(n){let o=await e.readAsync(),i=await e.update(n);if(i.success){if(o===null)await t.delete();return be("secure_storage_credentials_write"),i}let s=await t.update(n);if(s.success){if(o!==null)await e.delete();return Ne("secure_storage_credentials_write","plaintext_fallback_used"),{success:!0,warning:s.warning}}return pe("secure_storage_credentials_write","primary_and_fallback_failed"),{success:!1}}};return r}
EOF
}

# the other ONE-THING mutant: no plaintext tier at all — the keychain write is the only path.
_composite_no_fallback() {
  cat <<'EOF'
function bFc(e){let r={name:`${e.name}-only`,async update(n){let i=await e.update(n);if(i.success)return be("secure_storage_credentials_write"),i;if(i.transient)return Ne("secure_storage_credentials_write","primary_transient_skip_fallback"),i;return pe("secure_storage_credentials_write","primary_write_failed"),{success:!1}}};return r}
EOF
}

_fixture() {   # _fixture <path> <statusquo|fixed|worse> [qt] [argv]
  local path="$1" kind="$2" qt="${3:-2000}" argv="${4:-4032}"
  { _writer "$qt" "$argv"
    case "$kind" in
      statusquo) _plaintext_store; _composite_with_skip ;;
      fixed)     _plaintext_store; _composite_without_skip ;;
      worse)     _composite_no_fallback ;;
    esac
  } >"$path"
}

_verdict_of() { python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])'; }

# ── the four verdicts ───────────────────────────────────────────────────────────────────────────

@test "STATUS-QUO: the 2.1.220 shape (transient skips the fallback) → exit 1" {
  F="$BATS_TEST_TMPDIR/statusquo.bin"; _fixture "$F" statusquo
  run bash "$PROBE" "$F"
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | _verdict_of)" = "STATUS-QUO" ]
}

@test "FIXED: deleting ONLY the transient early-return flips the verdict → exit 0" {
  F="$BATS_TEST_TMPDIR/fixed.bin"; _fixture "$F" fixed
  run bash "$PROBE" "$F"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | _verdict_of)" = "FIXED" ]
}

@test "WORSE: keychain writer present but the plaintext tier removed → exit 2, outranks STATUS-QUO" {
  F="$BATS_TEST_TMPDIR/worse.bin"; _fixture "$F" worse
  run bash "$PROBE" "$F"
  [ "$status" -eq 2 ]
  [ "$(printf '%s' "$output" | _verdict_of)" = "WORSE" ]
  # the fixture deliberately still carries the transient-skip slug: WORSE must win over STATUS-QUO
  grep -q 'primary_transient_skip_fallback' "$F"
}

@test "UNREADABLE: no anchors at all → exit 3 (fail-closed, not a silent pass)" {
  F="$BATS_TEST_TMPDIR/opaque.bin"; head -c 4096 /dev/urandom >"$F"
  run bash "$PROBE" "$F"
  [ "$status" -eq 3 ]
  [ "$(printf '%s' "$output" | _verdict_of)" = "UNREADABLE" ]
}

@test "UNREADABLE: empty file and missing file both fail closed, never PASS" {
  : >"$BATS_TEST_TMPDIR/empty.bin"
  run bash "$PROBE" "$BATS_TEST_TMPDIR/empty.bin"
  [ "$status" -eq 3 ]
  run bash "$PROBE" "$BATS_TEST_TMPDIR/does-not-exist.bin"
  [ "$status" -eq 3 ]
}

# ── the constants are EXTRACTED, not echoed ─────────────────────────────────────────────────────

@test "write timeout + argv threshold are read off the candidate, not the baseline" {
  F="$BATS_TEST_TMPDIR/moved.bin"; _fixture "$F" statusquo 9000 8000
  run bash "$PROBE" "$F"
  [ "$status" -eq 1 ]
  printf '%s' "$output" >"$BATS_TEST_TMPDIR/out.json"
  run python3 -c '
import json,sys
a=json.load(open(sys.argv[1]))["axes"]
sys.exit(0 if (a["write_timeout_ms"]==9000 and a["argv_threshold_chars"]==8000
               and a["transient_keyed_on_timeout"] is True) else 1)' "$BATS_TEST_TMPDIR/out.json"
  [ "$status" -eq 0 ]
}

# ── the real-artifact control ───────────────────────────────────────────────────────────────────

@test "real 2.1.220 binary reproduces the filed measurement (2000 ms / 4032 chars / STATUS-QUO)" {
  [ -f "$REAL_BIN" ] || skip "2.1.220 bundle not on this box: $REAL_BIN"
  run bash "$PROBE" "$REAL_BIN"
  [ "$status" -eq 1 ]
  printf '%s' "$output" >"$BATS_TEST_TMPDIR/real.json"
  run python3 -c '
import json,sys
r=json.load(open(sys.argv[1])); a=r["axes"]
sys.exit(0 if (r["verdict"]=="STATUS-QUO" and r["version"]=="2.1.220"
               and a["write_timeout_ms"]==2000 and a["argv_threshold_chars"]==4032
               and a["keychain_writer"]=="present" and a["plaintext_fallback"]=="present"
               and a["transient_keyed_on_timeout"] is True) else 1)' "$BATS_TEST_TMPDIR/real.json"
  [ "$status" -eq 0 ]
}

# ── gate wiring: the check is discovered and maps verdicts to the right gate status ─────────────

@test "gate #14: STATUS-QUO → SKIP (never drags an upgrade red)" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$CHECK14" "$TMPC/"
  F="$BATS_TEST_TMPDIR/gate-statusquo.bin"; _fixture "$F" statusquo
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next"
  JSON="$BATS_TEST_TMPDIR/gate1.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" CC_AUTHSTORE_PROBE="$3" bash "$4" "$5" claude-opus-5 next >"$6" 2>/dev/null' \
      _ "$H" "$TMPC" "$PROBE" "$GATE" "$F" "$JSON"
  [ "$status" -eq 0 ]
  grep -q '"verdict": "GREEN"' "$JSON"
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); c=next(x for x in r["checks"] if x["check"]==14); sys.exit(0 if c["status"]=="SKIP" else 1)' "$JSON"
  [ "$status" -eq 0 ]
}

@test "gate #14: WORSE → FAIL, verdict RED, exit 1 (the check CAN park an upgrade)" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$CHECK14" "$TMPC/"
  F="$BATS_TEST_TMPDIR/gate-worse.bin"; _fixture "$F" worse
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next"
  JSON="$BATS_TEST_TMPDIR/gate2.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" CC_AUTHSTORE_PROBE="$3" bash "$4" "$5" claude-opus-5 next >"$6" 2>/dev/null' \
      _ "$H" "$TMPC" "$PROBE" "$GATE" "$F" "$JSON"
  [ "$status" -eq 1 ]
  grep -q '"verdict": "RED"' "$JSON"
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); c=next(x for x in r["checks"] if x["check"]==14); sys.exit(0 if c["status"]=="FAIL" else 1)' "$JSON"
  [ "$status" -eq 0 ]
}

@test "gate #14: FIXED → PASS and names the backlog item to close" {
  TMPC="$BATS_TEST_TMPDIR/checks"; mkdir -p "$TMPC"
  cp "$CHECK14" "$TMPC/"
  F="$BATS_TEST_TMPDIR/gate-fixed.bin"; _fixture "$F" fixed
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude-next"
  JSON="$BATS_TEST_TMPDIR/gate3.json"

  run bash -c 'HOME="$1" CC_UPGRADE_GATE_CHECKS="$2" CC_AUTHSTORE_PROBE="$3" bash "$4" "$5" claude-opus-5 next >"$6" 2>/dev/null' \
      _ "$H" "$TMPC" "$PROBE" "$GATE" "$F" "$JSON"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); c=next(x for x in r["checks"] if x["check"]==14); sys.exit(0 if (c["status"]=="PASS" and "4adbeab56aa7" in c["detail"]) else 1)' "$JSON"
  [ "$status" -eq 0 ]
}
