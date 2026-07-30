#!/usr/bin/env bats
# PREDICATE PARITY — ci_last_interactive_epoch (hooks/lib/cc-interactive.sh) vs ce_last_interactive_age
# (hooks/lib/context-econ.sh). There are TWO independent "WHO drove the last turn" implementations by
# design (the two legs can't share a bug), but the second is a BACKSTOP for the first: cc-classify §4.7
# gates on ci_, while the reaper's Gap-2 leg, reap-guard R-d and waiting-recycle S6 gate on ce_. When ce_
# is the WEAKER predicate, every path that backs up §4.7 holds LESS than the gate it backs up — an
# operator whose last turn was an image-only paste, or whose prompt sits past the 2 MB tail window, is
# invisible to the backstop and the pane reaps mid-conversation. The 2026-07-25 audit found exactly that
# divergence and ZERO parity tests (`git grep ci_last_interactive_epoch -- tests/` → 0 hits).
#
# These fixtures are SHARED: each is fed to both predicates and the two must agree on ADOPTED vs NOT.
# Fixture shapes mirror the live producer (fixture-shape parity, memory 2026-07-19): a real human turn is
# type:user + userType:external + isMeta:null + STRING content; an image paste is a content ARRAY with an
# image block and no tool_result; auto-drive is isMeta:true + "Stop hook feedback:".

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # HERMETICITY: both predicates are pure readers of a path argument and touch nothing under $HOME,
  # but the ratchet is structural — an unfixtured $HOME makes every result in the run untrustworthy,
  # so it is fixtured unconditionally rather than argued about per suite.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # shellcheck source=../hooks/lib/context-econ.sh
  . "$REPO/hooks/lib/context-econ.sh"
  # shellcheck source=../hooks/lib/cc-interactive.sh
  . "$REPO/hooks/lib/cc-interactive.sh"
  T="$BATS_TEST_TMPDIR"; TX="$T/tx.jsonl"
  NOW="$(date +%s)"
}

iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.123Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123Z; }

# ── shared fixtures (one producer per shape; both predicates read the SAME file) ──────────────────
mk_text()  { printf '{"parentUuid":"p","userType":"external","cwd":"/x","sessionId":"s","type":"user","isMeta":null,"message":{"role":"user","content":"%s"},"uuid":"u","timestamp":"%s"}\n' "${2:-do the thing}" "$(iso "$1")" >> "$TX"; }
mk_image() { printf '{"userType":"external","type":"user","isMeta":null,"message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]},"timestamp":"%s"}\n' "$(iso "$1")" >> "$TX"; }
mk_stop()  { printf '{"type":"user","isMeta":true,"userType":"external","message":{"role":"user","content":"Stop hook feedback:\\n[keep going]"},"timestamp":"%s"}\n' "$(iso "$1")" >> "$TX"; }
mk_tool()  { printf '{"type":"user","userType":"external","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":"ok"}]},"timestamp":"%s"}\n' "$(iso "$1")" >> "$TX"; }
mk_pad()   { local n="$1" i=0; while [ "$i" -lt "$n" ]; do printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]},"timestamp":"%s"}\n' "$(head -c 200 /dev/zero | tr '\0' 'z')" "$(iso "$NOW")" >> "$TX"; i=$((i+1)); done; }

# ── the two adoption predicates, normalized to a boolean ──────────────────────────────────────────
adopts_ce() { # 0 = this predicate SEES an operator turn
  local a; a="$(ce_last_interactive_age "$1" 2>/dev/null || true)"
  case "$a" in ''|*[!0-9]*) return 1 ;; esac
  return 0
}
adopts_ci() { ci_last_interactive_epoch "$1" >/dev/null 2>&1; }

# assert both predicates agree, and say which way
agree() { # <path> <expected: yes|no>
  local want="$2" ce=no ci=no
  adopts_ce "$1" && ce=yes
  adopts_ci "$1" && ci=yes
  [ "$ce" = "$want" ] || { echo "ce_last_interactive_age said $ce, wanted $want" >&2; return 1; }
  [ "$ci" = "$want" ] || { echo "ci_last_interactive_epoch said $ci, wanted $want" >&2; return 1; }
  return 0
}

# ── 1. an ordinary typed prompt — both adopt (the baseline both already shared) ────────────────────
@test "parity: a plain operator text prompt ⇒ BOTH predicates adopt" {
  mk_text "$(( NOW - 120 ))" "how is the build going?"
  mk_tool "$(( NOW - 5 ))"
  agree "$TX" yes
}

# ── 2. image-only paste — ⌘V of a screenshot is operator PRESENCE with no text at all ──────────────
@test "parity: an IMAGE-ONLY paste (no text block) ⇒ BOTH predicates adopt" {
  mk_image "$(( NOW - 90 ))"
  mk_tool "$(( NOW - 5 ))"
  agree "$TX" yes
}

@test "parity: image-only paste — the ce_ AGE matches the ci_ EPOCH (same turn, same clock)" {
  mk_image "$(( NOW - 300 ))"
  age="$(ce_last_interactive_age "$TX")"
  ep="$(ci_last_interactive_epoch "$TX")"
  [ -n "$age" ] && [ -n "$ep" ]
  d=$(( (NOW - ep) - age )); [ "$d" -ge -2 ] && [ "$d" -le 2 ]     # same turn ⇒ ages agree within clock jitter
}

# ── 3. the tail-eviction residual (R1) — an operator turn buried BEFORE the tail window ────────────
@test "parity: a prompt EVICTED past the tail window ⇒ BOTH predicates still adopt (whole-file fallback)" {
  mk_text "$(( NOW - 600 ))" "operator prompt buried at the head"
  mk_pad 40                                                        # >8KB of assistant traffic after it
  export CC_CE_TAIL_BYTES=512 CC_CLASSIFY_INTERACTIVE_TAIL_BYTES=512
  [ "$(wc -c < "$TX" | tr -d ' ')" -gt 512 ]                       # the fixture really does exceed the window
  agree "$TX" yes
}

@test "parity: tail-window miss on a SMALL file (nothing buried) ⇒ BOTH abstain — no false adoption" {
  mk_stop "$(( NOW - 30 ))"; mk_tool "$(( NOW - 20 ))"             # auto traffic only, file < window
  export CC_CE_TAIL_BYTES=512 CC_CLASSIFY_INTERACTIVE_TAIL_BYTES=512
  agree "$TX" no
}

# ── 4. no operator turn at all — both abstain (the guard against a hold that never releases) ───────
@test "parity: auto-drive traffic ONLY (stop-hook feedback + tool results) ⇒ NEITHER adopts" {
  mk_stop "$(( NOW - 60 ))"; mk_tool "$(( NOW - 50 ))"; mk_stop "$(( NOW - 10 ))"
  agree "$TX" no
}

@test "parity: a tool_result carried in a user record is tool traffic, never a paste ⇒ NEITHER adopts" {
  # an image INSIDE a tool_result array is a tool-returned image, not an operator ⌘V
  printf '{"type":"user","userType":"external","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":"x"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBOR"}}]},"timestamp":"%s"}\n' "$(iso "$(( NOW - 30 ))")" >> "$TX"
  agree "$TX" no
}

# ── 5. the SAFE-DIRECTION invariant: ce_ may never see LESS than ci_ ───────────────────────────────
# The parity upgrade is allowed to make ce_ hold MORE things (more operator turns counted ⇒ more DEFERs);
# it may never hold fewer than the gate it backs up. This walks every fixture shape at once.
@test "invariant: across every fixture shape, ce_ adopts wherever ci_ adopts (backstop ≥ gate)" {
  local f
  for f in text image evicted auto; do
    TX="$T/$f.jsonl"; : > "$TX"
    case "$f" in
      text)    mk_text "$(( NOW - 100 ))" "typed" ;;
      image)   mk_image "$(( NOW - 100 ))" ;;
      evicted) mk_text "$(( NOW - 100 ))" "buried"; mk_pad 40
               export CC_CE_TAIL_BYTES=512 CC_CLASSIFY_INTERACTIVE_TAIL_BYTES=512 ;;
      auto)    mk_stop "$(( NOW - 100 ))"; mk_tool "$(( NOW - 90 ))" ;;
    esac
    if adopts_ci "$TX"; then
      adopts_ce "$TX" || { echo "BACKSTOP WEAKER THAN GATE on fixture '$f': ci_ adopted, ce_ did not" >&2; return 1; }
    fi
  done
}

# ── 6. the THIRD STATE — "cannot read the answer" ≠ "nobody typed" ─────────────────────────────────
# ce_ took this split on 2026-07-25 (51521697) for its reap consumers; ci_ took it on 2026-07-29 to
# close C-SC-1, because the actuators that gate on ci_ — bin/cc-teardown's adoption belt and
# hooks/teammate-auto-shutdown.sh's TeammateIdle close — are the ones that actually KILL a pane, and a
# two-valued answer made them read an unreadable transcript as "no adoption → close". Both predicates
# must now answer THREE ways, identically, or a closer's fail-closed branch is unreachable on one leg.
#
# Verdict normalizes each predicate's (stdout, rc) pair onto the shared vocabulary:
#   adopted    = digits           (an operator turn was seen)
#   none       = "" — a FACT      (the transcript parsed; nobody typed) — the ONLY licence to close
#   unreadable = "unreadable"     (no path / unreadable / no jq / not one well-formed record)
verdict() { # <predicate-fn> <path> → adopted|none|unreadable
  local out rc=0
  out="$("$1" "$2" 2>/dev/null)" || rc=$?
  case "$out" in
    unreadable) printf unreadable ;;
    '')         if [ "$rc" = 2 ]; then printf unreadable; else printf none; fi ;;
    *[!0-9]*)   printf none ;;
    *)          printf adopted ;;
  esac
}

# each row: <fixture-builder> <expected shared verdict>. One table, both predicates, no per-leg drift.
@test "third state: both predicates agree on adopted / none / unreadable across every readability shape" {
  local shape want got_ce got_ci
  for shape in typed quiet corrupt empty missing nulls; do
    TX="$T/$shape.jsonl"; : > "$TX"
    case "$shape" in
      typed)   mk_text "$(( NOW - 60 ))" "still here"; want=adopted ;;
      # POSITIVE CONTROL for the whole split: a transcript that PARSES and holds only assistant/tool
      # traffic is the "nobody typed" FACT. If this ever answered unreadable, every closer would be
      # wedged forever and the fail-closed branches below would be indistinguishable from inert.
      quiet)   mk_tool "$(( NOW - 40 ))"; mk_pad 3; want=none ;;
      corrupt) printf 'not json at all\n\x00\x01binary garbage\n{"half":\n' > "$TX"; want=unreadable ;;
      empty)   : > "$TX"; want=unreadable ;;
      missing) TX="$T/does-not-exist.jsonl"; want=unreadable ;;
      # a file of well-formed JSON that is not one OBJECT (bare scalars) — parses per line, yields no
      # record: still "we could not read an answer", not "nobody typed".
      nulls)   printf 'null\n42\n"a string"\n' > "$TX"; want=unreadable ;;
    esac
    got_ce="$(verdict ce_last_interactive_age "$TX")"
    got_ci="$(verdict ci_last_interactive_epoch "$TX")"
    [ "$got_ce" = "$want" ] || { echo "ce_ on '$shape': got $got_ce, wanted $want" >&2; return 1; }
    [ "$got_ci" = "$want" ] || { echo "ci_ on '$shape': got $got_ci, wanted $want" >&2; return 1; }
  done
}

# The rc is the machine-readable half of the contract — a consumer branches on IT, not on the string.
@test "third state: ci_ returns rc 2 for unreadable and rc 1 for a parsed-but-quiet transcript" {
  TX="$T/quiet.jsonl"; : > "$TX"; mk_tool "$(( NOW - 30 ))"
  local rc=0; ci_last_interactive_epoch "$TX" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 1 ] || { echo "parsed-but-quiet should be rc 1 (the FACT), got rc $rc" >&2; return 1; }
  printf 'garbage\n' > "$T/bad.jsonl"
  rc=0; ci_last_interactive_epoch "$T/bad.jsonl" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "corrupt should be rc 2 (unreadable), got rc $rc" >&2; return 1; }
}

# The whole-file fallback must not be confused WITH the discriminator: a prompt buried past the tail
# window is ADOPTED (readable, found late), never "unreadable".
@test "third state: a tail-evicted prompt is ADOPTED, not unreadable (fallback beats the discriminator)" {
  TX="$T/evicted.jsonl"; : > "$TX"
  mk_text "$(( NOW - 100 ))" "buried past the window"; mk_pad 40
  export CC_CE_TAIL_BYTES=512 CC_CLASSIFY_INTERACTIVE_TAIL_BYTES=512
  [ "$(verdict ce_last_interactive_age "$TX")" = adopted ] || { echo "ce_ lost the buried prompt" >&2; return 1; }
  [ "$(verdict ci_last_interactive_epoch "$TX")" = adopted ] || { echo "ci_ lost the buried prompt" >&2; return 1; }
}
