#!/bin/bash
# gate-manifest.sh — the C1..C10 pre-signed ruling-class manifest (gate-batching axis c: P1/P2/P4/P7).
#
# The operator PRE-SIGNS a set of in-class ruling CLASSES at wave START (formalizing the operator's
# own "RATIFY ALL 7"). An in-class ruling then auto-ratifies + carries an auditable auto-stamp trailer;
# an out-of-class ruling STOP-ASKs. This is the P1 registry + P2 wave manifest + P4 auto-stamp + P7
# per-wave expiry. Its sibling gate-classify.sh (P3) routes a boundary to A|B|C on the SURFACE; this is
# the G-manifest gate (class ∈ current NON-EXPIRED manifest). They COMPOSE — surface says "is this a
# ceiling", manifest says "is this class pre-signed this wave". cc-bind is the per-RULING content half.
#
# ── THE ASYMMETRY (load-bearing; any doubt fails CLOSED, never silently open) ──────────────────────
#   {C1-C5, C7}  PRE-SIGNABLE — the normal in-class ratification set.
#   {C6 money-path, C8 next-wave-go}  CONDITIONAL — out-of-class BY DEFAULT; signable ONLY with a
#                                     deliberate --allow-conditional (a false auto-ratify here is costly).
#   {C9 /ship, C10 self-modification/persistence}  PERMANENT EXCLUSION — never sign-able, never
#                                     stamp-able. C10 is harness-enforced (a peer-agent ruling is not
#                                     user intent, invariant 6); C9 is /ship, retro-reviewed by the
#                                     `/ship` backstop grep (P6). Never demotable, even with a flag.
#
#   gate-manifest.sh classes                                 print the C1..C10 registry
#   gate-manifest.sh sign --wave <id> --classes C1,C3,C7 [--expiry <ISO|+Nh|+Nd>] [--allow-conditional] [--by who]
#   gate-manifest.sh check <class> [--wave <id>]             G-manifest gate: 0 in-class · 1 out/expired/none (fail-closed)
#   gate-manifest.sh stamp <class> [--wave <id>]             P4: print `Ratified-By: ...` trailer if in-class, else refuse
#   gate-manifest.sh current [--wave <id>]                   print the active (newest non-expired) manifest
#   gate-manifest.sh backstop [<git-range>]                  P6: surface auto-stamped ratifications in a range for EARLY-VETO (non-blocking)
#   gate-manifest.sh selftest                                RED-on-out-of-class + GREEN-on-in-class, throwaway dir, no side effects
#
# Env (tests): CC_GATE_MANIFEST_DIR · CC_IDL (audit trail) · CC_NOW (ISO override for expiry compare).
# Exit: check/stamp → 0 in-class · 1 out-of-class OR indeterminate (fail-closed) · 2 usage/refusal.
#       sign → 0 written · 2 refused/usage (LOUD).  BSD+GNU portable; ISO-8601-Z compares lexically.
set -uo pipefail
export LC_ALL=C   # byte-deterministic string compares (ISO-Z lexi == chrono) + greps

MANIFEST_DIR="${CC_GATE_MANIFEST_DIR:-$HOME/.claude/autonomy/gate-manifest}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
die2()  { echo "gate-manifest: ⛔ $*" >&2; exit 2; }               # usage / policy refusal (LOUD)

command -v jq >/dev/null 2>&1 || { echo "gate-manifest: jq required" >&2; exit 2; }

# ── P1 registry — the C1..C10 signability map + human-legible names (this IS the registry) ──────────
class_signability() { # <Cn> → presignable|conditional|excluded|unknown
  case "$1" in
    C1|C2|C3|C4|C5|C7) echo presignable ;;
    C6|C8)             echo conditional ;;
    C9|C10)            echo excluded ;;
    *)                 echo unknown ;;
  esac
}
class_name() { # <Cn> → one-line human description
  case "$1" in
    C1)  echo "wave-exit ratification (in-class dispositions at a wave boundary)" ;;
    C2)  echo "in-class verify-wave fix (security/data-integrity on served surfaces, now)" ;;
    C3)  echo "reversible refactor / cleanup (net-positive, reversible with a tag)" ;;
    C4)  echo "additive test / doc / observability (no served-surface behavior change)" ;;
    C5)  echo "in-tree dependency / config change (non-escalation surface)" ;;
    C6)  echo "money-path — payment/spend/raise-the-cap commitment (out-of-class by default)" ;;
    C7)  echo "land verified net-positive work (autonomous-at-green ship of the verified diff)" ;;
    C8)  echo "next-wave go — cut/spawn the next wave (couples wave-plan; out-of-class by default)" ;;
    C9)  echo "/ship to origin — the push/land act; permanent exclusion + retro backstop" ;;
    C10) echo "self-modification / persistence — settings/hooks/launchd/plist/PATH/creds; HUMAN-ONLY" ;;
    *)   echo "unknown class" ;;
  esac
}

normalize_class() { # <token> → canonical Cn on stdout, or return 1 (unknown shape)
  local c; c="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')"
  case "$c" in C[1-9]|C10) printf '%s' "$c" ;; *) return 1 ;; esac
}

# ── clock (CC_NOW overrides for deterministic tests; all timestamps are ISO-8601-Z) ─────────────────
now_iso()   { if [ -n "${CC_NOW:-}" ]; then printf '%s' "$CC_NOW"; else date -u +%Y-%m-%dT%H:%M:%SZ; fi; }
iso_to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null; }
iso_from_epoch() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }
now_epoch() { if [ -n "${CC_NOW:-}" ]; then iso_to_epoch "$CC_NOW"; else date -u +%s; fi; }

expand_expiry() { # <ISO|+Nh|+Nd|+Nm> → ISO-8601-Z on stdout, or return 1
  local e="$1" n unit secs base
  case "$e" in
    +[0-9]*[hdm])
      unit="${e##*[0-9]}"; n="${e%"$unit"}"; n="${n#+}"
      case "$unit" in h) secs=$((n*3600)) ;; d) secs=$((n*86400)) ;; m) secs=$((n*60)) ;; esac
      base="$(now_epoch)"; [ -n "$base" ] || return 1
      iso_from_epoch "$((base+secs))" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
      printf '%s' "$e" ;;
    *) return 1 ;;
  esac
}

log_idl() { # <verb> <ref> <status>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"gate-manifest","verb":"%s","ref":"%s","status":"%s"}\n' \
    "$(now_iso)" "$1" "$2" "$3" >> "$IDL" 2>/dev/null || true
}

# ── manifest resolution + activeness (P7 expiry: now >= expiry ⇒ stale ⇒ all out-of-class) ──────────
manifest_active() { # <file> → 0 if it exists AND now < expiry
  local f="$1" exp now
  [ -f "$f" ] || return 1
  exp="$(jq -r '.expiry // empty' "$f" 2>/dev/null)"; [ -n "$exp" ] || return 1
  now="$(now_iso)"
  [[ "$now" < "$exp" ]]
}
class_in_manifest() { # <file> <Cn> → 0 if listed
  jq -e --arg c "$2" '.classes | index($c) != null' "$1" >/dev/null 2>&1
}
newest_active_manifest() { # → path on stdout, or return 1
  local best="" best_ts="" f ts
  [ -d "$MANIFEST_DIR" ] || return 1
  for f in "$MANIFEST_DIR"/*.json; do
    [ -f "$f" ] || continue
    manifest_active "$f" || continue
    ts="$(jq -r '.signed_at // empty' "$f" 2>/dev/null)"
    if [ -z "$best" ] || [[ "$ts" > "$best_ts" ]]; then best="$f"; best_ts="$ts"; fi
  done
  [ -n "$best" ] || return 1
  printf '%s' "$best"
}

# REASON + MANIFEST_FILE are set by resolve_in_class for the caller (check/stamp/current).
REASON=""; MANIFEST_FILE=""
resolve_in_class() { # <Cn> <wave|''> → 0 in-class (sets MANIFEST_FILE) · 1 out/expired/none (sets REASON) · 2 bad class
  local class="$1" wave="$2" sig f
  sig="$(class_signability "$class")"
  case "$sig" in
    unknown)  REASON="unknown class '$class' (valid: C1..C10)"; return 2 ;;
    excluded) REASON="$class is a PERMANENT exclusion — never pre-signable (human-only). $(class_name "$class")"; return 1 ;;
  esac
  if [ -n "$wave" ]; then
    f="$MANIFEST_DIR/$wave.json"
    [ -f "$f" ]           || { REASON="no manifest for wave '$wave' — $class is out-of-class (fail-closed)"; return 1; }
    manifest_active "$f"  || { REASON="wave '$wave' manifest is EXPIRED/stale — all classes out-of-class (P7)"; return 1; }
  else
    f="$(newest_active_manifest)" || { REASON="no active (non-expired) manifest — $class is out-of-class ⇒ STOP-ASK (operator must pre-sign it)"; return 1; }
  fi
  if class_in_manifest "$f" "$class"; then MANIFEST_FILE="$f"; return 0; fi
  REASON="$class not pre-signed in wave '$(basename "$f" .json)' — out-of-class ⇒ STOP-ASK (fail-closed)"
  return 1
}

# ── subcommands ─────────────────────────────────────────────────────────────────────────────────────
cmd_classes() {
  local c
  echo "C#   signability   ruling class"
  for c in C1 C2 C3 C4 C5 C6 C7 C8 C9 C10; do
    printf '%-4s %-13s %s\n' "$c" "$(class_signability "$c")" "$(class_name "$c")"
  done
}

cmd_sign() {
  local WAVE="" CSV="" EXPIRY="+24h" ALLOW_COND=0 BY="operator"
  while [ $# -gt 0 ]; do
    case "$1" in
      --wave)              WAVE="${2:-}"; shift 2 || shift ;;
      --wave=*)            WAVE="${1#--wave=}"; shift ;;
      --classes)           CSV="${2:-}"; shift 2 || shift ;;
      --classes=*)         CSV="${1#--classes=}"; shift ;;
      --expiry)            EXPIRY="${2:-}"; shift 2 || shift ;;
      --expiry=*)          EXPIRY="${1#--expiry=}"; shift ;;
      --by)                BY="${2:-}"; shift 2 || shift ;;
      --by=*)              BY="${1#--by=}"; shift ;;
      --allow-conditional) ALLOW_COND=1; shift ;;
      *) die2 "sign: unknown arg '$1'" ;;
    esac
  done
  [ -n "$WAVE" ] || die2 "sign: --wave <id> required"
  [ -n "$CSV" ]  || die2 "sign: --classes C1,C3,... required"

  local expiry_iso; expiry_iso="$(expand_expiry "$EXPIRY")" || die2 "sign: bad --expiry '$EXPIRY' (use an ISO-8601-Z stamp or +Nh/+Nd/+Nm)"

  local IN=() COND=() raw c sig
  local oldIFS="$IFS"; IFS=','; set -f
  # shellcheck disable=SC2086
  set -- $CSV
  IFS="$oldIFS"; set +f
  for raw in "$@"; do
    [ -n "$raw" ] || continue
    c="$(normalize_class "$raw")" || die2 "sign: unknown class '$raw' (valid: C1..C10)"
    sig="$(class_signability "$c")"
    case "$sig" in
      presignable) IN+=("$c") ;;
      conditional)
        [ "$ALLOW_COND" = 1 ] || die2 "sign: $c is CONDITIONAL (out-of-class by default) — pass --allow-conditional to deliberately pre-sign it. $(class_name "$c")"
        IN+=("$c"); COND+=("$c") ;;
      excluded) die2 "sign: $c is a PERMANENT exclusion — never pre-signable (human-only, harness-enforced). Refusing. $(class_name "$c")" ;;
      *) die2 "sign: unknown class '$raw'" ;;
    esac
  done
  [ "${#IN[@]}" -gt 0 ] || die2 "sign: no valid classes in '$CSV'"

  mkdir -p "$MANIFEST_DIR" 2>/dev/null || die2 "sign: cannot create $MANIFEST_DIR"
  local classes_json conditional_json
  classes_json="$(printf '%s\n' "${IN[@]}" | jq -R . | jq -s 'unique')"
  if [ "${#COND[@]}" -gt 0 ]; then
    conditional_json="$(printf '%s\n' "${COND[@]}" | jq -R . | jq -s 'unique')"
  else
    conditional_json='[]'
  fi
  jq -n --arg wave "$WAVE" --arg signed "$(now_iso)" --arg by "$BY" --arg expiry "$expiry_iso" \
        --argjson classes "$classes_json" --argjson conditional "$conditional_json" \
    '{wave:$wave, signed_at:$signed, by:$by, expiry:$expiry, classes:$classes, conditional:$conditional}' \
    > "$MANIFEST_DIR/$WAVE.json" || die2 "sign: failed to write manifest"

  log_idl sign "$WAVE" "signed:$(printf '%s,' "${IN[@]}")"
  echo "✓ signed wave '$WAVE': $(IFS=,; echo "${IN[*]}")  (expiry $expiry_iso, by $BY)"
  [ "${#COND[@]}" -gt 0 ] && echo "  ⚠ conditional (deliberate): $(IFS=,; echo "${COND[*]}")" >&2
  return 0
}

parse_class_wave() { # "$@" → sets P_CLASS, P_WAVE
  P_CLASS=""; P_WAVE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --wave)   P_WAVE="${2:-}"; shift 2 || shift ;;
      --wave=*) P_WAVE="${1#--wave=}"; shift ;;
      -*)       die2 "unknown option '$1'" ;;
      *)        if [ -z "$P_CLASS" ]; then P_CLASS="$1"; else die2 "unexpected arg '$1'"; fi; shift ;;
    esac
  done
}

cmd_check() {
  parse_class_wave "$@"
  [ -n "$P_CLASS" ] || die2 "check: a class (C1..C10) is required"
  local class; class="$(normalize_class "$P_CLASS")" || die2 "check: unknown class '$P_CLASS' (valid: C1..C10)"
  resolve_in_class "$class" "$P_WAVE"; local rc=$?
  if [ "$rc" -eq 0 ]; then
    log_idl check "$class" "in-class:$(basename "$MANIFEST_FILE" .json)"
    echo "✓ $class in-class (wave $(basename "$MANIFEST_FILE" .json)) — auto-ratify + stamp" >&2
    return 0
  fi
  log_idl check "$class" "out-of-class"
  echo "⛔ $REASON" >&2
  return 1
}

cmd_stamp() {
  parse_class_wave "$@"
  [ -n "$P_CLASS" ] || die2 "stamp: a class (C1..C10) is required"
  local class; class="$(normalize_class "$P_CLASS")" || die2 "stamp: unknown class '$P_CLASS' (valid: C1..C10)"
  resolve_in_class "$class" "$P_WAVE"; local rc=$?
  if [ "$rc" -ne 0 ]; then
    log_idl stamp "$class" "refused"
    echo "⛔ stamp REFUSED — $REASON. An out-of-class ruling is never auto-stamped; STOP-ASK the operator." >&2
    return 1
  fi
  local wave expiry
  wave="$(basename "$MANIFEST_FILE" .json)"
  expiry="$(jq -r '.expiry' "$MANIFEST_FILE" 2>/dev/null)"
  # P4 auto-stamp trailer. The literal "pre-signed class" substring is the P6 /ship-backstop grep key.
  printf 'Ratified-By: operator (pre-signed class %s, manifest %s@%s)\n' "$class" "$wave" "$expiry"
  log_idl stamp "$class" "stamped:$wave"
  return 0
}

cmd_current() {
  parse_class_wave "$@"
  local f
  if [ -n "$P_WAVE" ]; then
    f="$MANIFEST_DIR/$P_WAVE.json"
    { [ -f "$f" ] && manifest_active "$f"; } || { echo "⛔ no active manifest for wave '$P_WAVE'" >&2; return 1; }
  else
    f="$(newest_active_manifest)" || { echo "⛔ no active (non-expired) manifest — nothing is pre-signed" >&2; return 1; }
  fi
  jq -r '"wave:      \(.wave)\nsigned_at: \(.signed_at) by \(.by)\nexpiry:    \(.expiry)\nclasses:   \(.classes | join(", "))\nconditional: \(.conditional | join(", "))"' "$f"
  return 0
}

cmd_backstop() {
  # P6 /ship backstop: surface every auto-stamped in-class ratification in <range> so the operator
  # can EARLY-VETO one that was signed out-of-class. NON-BLOCKING by contract — a review surface,
  # NEVER a gate (ZERO-HITL: former STOP-ASKs become async early-veto queues, not fences). Always 0.
  # The grep key `pre-signed class C<n>` is exactly what cmd_stamp writes into the trailer — kept in
  # THIS one file so the stamp side (P4) and the retro-review side (P6) can never drift apart. The
  # trailing `C[0-9]` pins it to the auto-stamp TRAILER (every class C1..C10 has a digit after "class
  # C") so a commit that merely mentions the phrase in prose is NOT surfaced as a ratification.
  local range="${1:-}"
  command -v git >/dev/null 2>&1        || return 0
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  if [ -z "$range" ]; then
    local up; up="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" || return 0
    [ -n "$up" ] || return 0
    range="$up..HEAD"
  fi
  local hits
  hits="$(git log --grep='pre-signed class C[0-9]' --format='  %h %s  [%an]' "$range" 2>/dev/null)" || return 0
  if [ -n "$hits" ]; then
    { echo "── P6 gate-batching backstop — auto-ratified (pre-signed class) rulings in ${range}:"
      echo "$hits"
      echo "   ↑ EARLY-VETO now if any auto-ratification was out-of-class (surfacing only — never blocks the land)."
    } >&2
    log_idl backstop "$range" "surfaced"
  fi
  return 0
}

cmd_selftest() {
  local tmp; tmp="$(mktemp -d 2>/dev/null)" || { echo "selftest: mktemp failed" >&2; return 1; }
  local self="$SELF" rc=0
  (
    export CC_GATE_MANIFEST_DIR="$tmp/gm" CC_IDL="$tmp/idl.jsonl" CC_NOW="2026-07-19T12:00:00Z"
    set -e
    bash "$self" sign --wave WT --classes C1,C3,C7 --expiry "2026-07-19T13:00:00Z" >/dev/null
    bash "$self" check --wave WT C1 2>/dev/null                                             # in-class → 0
    ! bash "$self" check --wave WT C2 2>/dev/null                                           # out-of-class → 1
    ! bash "$self" check --wave WT C10 2>/dev/null                                          # excluded → 1
    ! bash "$self" sign --wave WX --classes C10 --expiry "2026-07-19T13:00:00Z" 2>/dev/null # refuse C10 → 2
    ! bash "$self" sign --wave WX --classes C6  --expiry "2026-07-19T13:00:00Z" 2>/dev/null # refuse C6 sans flag → 2
    bash "$self" stamp --wave WT C1 2>/dev/null | grep -qF 'pre-signed class'               # in-class trailer + grep key
    ! bash "$self" stamp --wave WT C2 >/dev/null 2>&1                                       # out-of-class → 1
    # expired manifest ⇒ out-of-class (P7)
    bash "$self" sign --wave WE --classes C1 --expiry "2026-07-19T11:00:00Z" >/dev/null
    ! bash "$self" check --wave WE C1 2>/dev/null
  ) || rc=1
  rm -rf "$tmp" 2>/dev/null || true
  if [ "$rc" -eq 0 ]; then echo "✓ gate-manifest selftest: RED-on-out-of-class + GREEN-on-in-class + P6 grep-key all hold"; else echo "✗ gate-manifest selftest FAILED" >&2; fi
  return "$rc"
}

SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

main() {
  [ $# -gt 0 ] || { usage; exit 2; }
  local verb="$1"; shift
  case "$verb" in
    -h|--help|help) usage; exit 0 ;;
    classes)  cmd_classes ;;
    sign)     cmd_sign "$@" ;;
    check)    cmd_check "$@" ;;
    stamp)    cmd_stamp "$@" ;;
    current)  cmd_current "$@" ;;
    backstop) cmd_backstop "$@" ;;
    selftest) cmd_selftest ;;
    *) die2 "unknown verb '$verb' — try: classes | sign | check | stamp | current | backstop | selftest (-h for help)" ;;
  esac
}

main "$@"
