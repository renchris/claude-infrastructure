#!/usr/bin/env bash
# cloud-refusal-route.sh — THE REFUSAL LOOP for a cloud fire (CLOUD_BACKLOG_PIPELINE.md W3,
# §2 gap row 4, §5 clause 6).
#
#   scripts/cloud-refusal-route.sh --sweep [--dry-run]        every refusal artifact, one pass
#   scripts/cloud-refusal-route.sh --id <session-id> [--dry-run]
#   scripts/cloud-refusal-route.sh --classify <artifact-file> [--paths a,b]   pure verdict, no send
#   scripts/cloud-refusal-route.sh --chain <session-id>        the evidence chain, human-readable
#
# WHY THIS EXISTS. §2 row 4, in the words of the session that paid for it: *"the memo's land was
# refused by one lint; nothing told the VM. Diagnosed and hand-sent."* A cloud VM cannot see this
# box's land gate, cannot read `~/.claude/autonomy/cloud/<id>.land-refused`, and has no route home
# except the git remote it cloned from. So a gate refusal was a DEAD END that a human had to walk:
# read the log, work out which lint, compose the fix, hand-send it. W2 built the artifact and the
# wake; this closes the circuit — the gate's OWN verdict text reaches the session that produced the
# commits, over `cc-offload say`, and the VM amends and re-pushes with nobody reading anything.
#
# ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
# It does not detect the refusal (cloud-return.sh does, and writes the artifact), does not land or
# re-land (cloud-reconcile → desk-land → ship-land own that, and cloud-return's next pass fires the
# retry the moment the VM's new push goes quiet), and does not fork a second refusal store or a
# second wake rail — it consumes W2's marker and sends over W2's transports. The ONE piece of state
# it owns is its own routing history, and that is a separate file for a reason given below.
#
# ═══ THE FOUR RULES, each one a defect this repo has already paid for ═══════════════════════════
#
# 1. 🚨 A LAND CUT BY A BOUND IS NOT A REFUSAL, AND THAT DISTINCTION IS LOAD-BEARING (d079576e).
#    A refusal is a claim ABOUT THE BRANCH — actionable, routable, and the VM can clear it. A cut
#    is a claim about the MACHINE: `verdict=killed signal=SIGTERM … it did not fail a gate and
#    nothing was proven about the tree`. Routing a cut to the VM asks it to fix code that is not
#    broken, and the VM — being agreeable — will change something. cloud-return abstains before
#    filing one, so post-d079576e no cut should reach here at all; this arm exists because ONE
#    pre-fix artifact is on this box right now (rc=143), and because "should not happen" is not a
#    guard. A cut is recorded, never routed, and consumes no cycle.
#
# 2. 🚨 THE IDENTITY-GATE REFUSAL IS BY DESIGN AND MUST NOT ENTER THE LOOP (CLOUD_OBSERVABILITY
#    §13.4-13.5). The VM authors as `noreply@anthropic.com`; this repo's identity gate refuses such
#    a range ON PURPOSE, and the landing path already answers it — cloud-reconcile re-authors
#    between the fetch and the land. So a refusal that names the identity wall is not news the VM
#    can act on: it cannot change who authored its commits, and asking it to would be asking it to
#    defeat a gate that is working. It routes to the ORIGINATOR (the re-author itself failed, which
#    is a fact about THIS box's git identity) and never to the VM.
#    ⚠️ The matcher keys on the REFUSAL spellings — `could not be re-authored`, `authored by someone
#    GitHub cannot attribute`, `git-identity` — never on the word "unattributable", which appears in
#    cloud-reconcile's SUCCESS line ("2 of them were unattributable"). A matcher that fired on the
#    success line would classify every healthy cloud land as an identity refusal.
#
# 3. 🚨 FIXABLE-BY-VM IS DECIDED BY WHETHER THE GATE NAMED THE VM'S OWN FILES — and the search runs
#    in that direction on purpose. The naive form (scrape paths out of the verdict, ask if they look
#    fixable) reads `scripts/desk-land.sh` out of the lander's own preamble and convicts a file
#    nobody touched. So instead: derive the VM's OWN path set from ITS OWN COMMITS (cc-cloud
#    fill-paths, W2's derivation — never "the most recent session", never a guess) and ask whether
#    the gate's output NAMES one of them.
#    ⚠️ MEASURED, not assumed: a lint may name a file by BASENAME. `test-hermeticity-lint` reports
#    `LEAK  w3-gate-probe.bats: …` for a suite whose repo path is `tests/w3-gate-probe.bats`, so a
#    full-path-only match reads NOT-NAMED over a red that names the file perfectly. Both spellings
#    are searched and the ledger records WHICH matched, so a basename-only hit stays auditable.
#
# 4. 🚨 THE DEFAULT DIRECTION IS THE ORIGINATOR, NEVER THE VM (memory: gate-default-decides-failure-
#    direction). When nothing establishes that the VM can clear the refusal — the red names no file
#    of its, the path set could not be derived, the cause is machine-side — the message goes to the
#    human's inbox, not off-box. The asymmetry is real: a wrong VM route spends quota, hands a
#    confident-sounding brief to a machine that cannot act on it, and is only discovered by
#    exhausting the bound; a wrong originator route costs one ping. So uncertainty routes home.
#
# ── WHY THE CYCLE COUNTER IS A SEPARATE FILE, WHICH LOOKS LIKE THE SECOND STORE IT IS NOT ────────
# cloud-return writes `<id>.land-refused` with `>` — every new refusal REPLACES it. A cycle counter
# living inside that marker would therefore be reset by the very event it is there to bound, and the
# loop would run forever while reading `cycle 1` every time (memory: counter-resets-at-the-boundary-
# the-runaway-crosses — a cap whose key the runaway re-creates is decorative). `<id>.refusal-route`
# is append-only routing HISTORY, not a second opinion about whether a land was refused: the refusal
# facts are still read out of W2's marker and nowhere else.
#
# ── THE BOUND, AND WHAT HAPPENS AT ITS END ──────────────────────────────────────────────────────
# CC_REFUSAL_MAX_CYCLES (default 2) VM routes per session, ever. On exhaustion the originator is
# woken with the chain — every cycle, its arm, its verdict head — and `--chain <id>` prints it in
# full. It never loops silently and it never gives up silently: the terminal state is a human being
# told, with the evidence, which is the state this whole rail exists to reach WITHOUT one.
#
# EXITS: 0 the pass completed (per-artifact outcomes on stdout and in the ledger) · 2 usage ·
#   3 a precondition is missing (no jq, no cc-cloud) · 4 the lock is held by a live pass.
#   A per-artifact failure is REPORTED, never fatal to the pass.
#
# 🚨 THIS SCRIPT SPENDS QUOTA (`cc-offload say`). Its caller in scripts/autonomy-sweep.sh carries
# the same deployed-copy guard cloud-return does, for the same reason: tests/autonomy-sweep.bats
# runs the real sweep once per test and postland-verify runs that suite from a throwaway worktree.
#
# Env seams (the suite overrides all of them; nothing here touches the real fleet under test):
#   CC_CLOUD_STATE · CC_REFUSAL_MAX_CYCLES · CC_REFUSAL_PAYLOAD_MAX · CC_REFUSAL_CLOUD_BIN ·
#   CC_REFUSAL_OFFLOAD_BIN · CC_REFUSAL_NOTIFY_BIN · CC_REFUSAL_GIT_BIN · CC_REFUSAL_NOW ·
#   CC_REFUSAL_LEDGER
#
# bash 3.2-safe.
set -uo pipefail

SELF="$0"; while [ -L "$SELF" ]; do _t="$(readlink "$SELF")"; case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac; done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"

STATE="${CC_CLOUD_STATE:-$HOME/.claude/autonomy/cloud}"
MAX_CYCLES="${CC_REFUSAL_MAX_CYCLES:-2}"
PAYLOAD_MAX="${CC_REFUSAL_PAYLOAD_MAX:-1600}"
GIT_BIN="${CC_REFUSAL_GIT_BIN:-git}"
LEDGER="${CC_REFUSAL_LEDGER:-$STATE/refusal-route.jsonl}"

resolve() { # <override> <name> <fallback-path…>
  local ov="$1" name="$2"; shift 2
  [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }
  local c
  for c in "$@" "$(command -v "$name" 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 0
}
CLOUD_BIN="$(resolve "${CC_REFUSAL_CLOUD_BIN:-}" cc-cloud "$ROOT/bin/cc-cloud" "$HOME/.claude/bin/cc-cloud")"
OFFLOAD_BIN="$(resolve "${CC_REFUSAL_OFFLOAD_BIN:-}" cc-offload "$ROOT/bin/cc-offload" "$HOME/.claude/bin/cc-offload")"
NOTIFY_BIN="$(resolve "${CC_REFUSAL_NOTIFY_BIN:-}" cc-notify "$ROOT/bin/cc-notify" "$HOME/.claude/bin/cc-notify")"

MODE="" ONE="" FILE="" FORCED_PATHS="" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sweep) MODE=sweep; shift ;;
    --id) MODE=one; ONE="${2:-}"; shift 2 ;;
    --id=*) MODE=one; ONE="${1#--id=}"; shift ;;
    --classify) MODE=classify; FILE="${2:-}"; shift 2 ;;
    --chain) MODE=chain; ONE="${2:-}"; shift 2 ;;
    --paths) FORCED_PATHS="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,40p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "cloud-refusal-route: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "cloud-refusal-route: pass --sweep, --id <session-id>, --classify <file> or --chain <session-id>" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "cloud-refusal-route: jq required" >&2; exit 3; }

now() { if [ -n "${CC_REFUSAL_NOW:-}" ]; then printf '%s' "$CC_REFUSAL_NOW"; else date +%s; fi; }
say() { printf '%s\n' "$*"; }
warn() { printf '%s\n' "cloud-refusal-route: $*" >&2; }

ledger() { # <id> <outcome> <detail-json-object>
  mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || return 0
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$1" --arg out "$2" --argjson d "$3" \
    '{ts:$ts, id:$id, outcome:$out} + $d' >>"$LEDGER" 2>/dev/null || true
}

# ── the artifact reader ──────────────────────────────────────────────────────────────────────────
# W2's format is a KV header, a bare `--`, then the land's whole combined output. Read with sed
# rather than sourcing it: the body is arbitrary gate text, quotes and backticks included.
A_ID="" A_BRANCH="" A_RC="" A_AT="" A_BODY="" A_KEY=""
read_artifact() { # <file> → 0 ok · 1 unreadable
  local f="$1"
  [ -f "$f" ] || return 1
  A_ID="$(sed -n 's/^id=//p' "$f" | head -1)"
  A_BRANCH="$(sed -n 's/^branch=//p' "$f" | head -1)"
  A_RC="$(sed -n 's/^rc=//p' "$f" | head -1)"
  A_AT="$(sed -n 's/^at=//p' "$f" | head -1)"
  A_BODY="$(sed -n '/^--$/,$p' "$f" | sed '1d')"
  case "$A_RC" in ''|*[!0-9-]*) A_RC="?" ;; esac
  case "$A_AT" in ''|*[!0-9]*) A_AT="0" ;; esac
  # The dedupe key. `at` alone is not enough — two refusals inside one second would collapse into
  # one, and the second would never be routed. cksum over the body is POSIX and in /usr/bin, so the
  # key survives on a box where md5/shasum spellings differ (memory: the find|sort|cksum lesson).
  A_KEY="$A_AT:$A_RC:$(printf '%s' "$A_BODY" | cksum 2>/dev/null | awk '{print $1}')"
  [ -n "$A_ID" ] || return 1
  return 0
}

# ── the VM's own path set ────────────────────────────────────────────────────────────────────────
# From ITS OWN COMMITS, via the tool that already owns that derivation (W2's `fill-paths`, which
# excludes deletions and reads the local ref the lander fetched). The declaration's `paths=` is
# preferred when already written, because after a successful land that is the authoritative record
# and the range is empty by then. A derivation that fails leaves the set EMPTY, which is honest and
# routes the refusal home under rule 4 rather than guessing.
VM_PATHS=""
derive_paths() { # <id>
  local id="$1"
  VM_PATHS=""
  if [ -n "$FORCED_PATHS" ]; then VM_PATHS="$FORCED_PATHS"; return 0; fi
  VM_PATHS="$(sed -n 's/^paths=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"
  [ -n "$VM_PATHS" ] && return 0
  [ -n "$CLOUD_BIN" ] || return 0
  VM_PATHS="$("$CLOUD_BIN" fill-paths --id "$id" --print 2>/dev/null | head -1)"
  return 0
}

# ── classification ───────────────────────────────────────────────────────────────────────────────
# Precedence is the order of the rules in the header, and it is not arbitrary: a cut that also
# happens to name a file must NOT be routed to the VM, and an identity refusal that also names one
# must not either. The strongest disqualifier wins.
ARM="" ARM_WHY="" ARM_MATCH=""
classify() { # <body> <rc> <vm-paths-csv> → sets ARM ∈ cut|by-design|local-only|vm
  local body="$1" rc="$2" paths="$3"
  ARM="" ARM_WHY="" ARM_MATCH=""

  # 1. THE CUT — a non-verdict. Both sides corroborate: the bound's own exit codes (timeout's 124,
  #    SIGKILL's 137, SIGTERM's 143) and ship-land's killed token, either of which is enough.
  case "$rc" in 124|137|143) ARM="cut"; ARM_WHY="the land was killed from outside (exit $rc) — a bound reached the process; nothing was proven about the branch" ;; esac
  if [ -z "$ARM" ]; then
    case "$body" in
      *"verdict=killed"*) ARM="cut"; ARM_WHY="ship-land reported verdict=killed — it did not fail a gate and nothing was proven about the tree" ;;
      *"GATE-KILLED"*)    ARM="cut"; ARM_WHY="the gate died without earning a verdict (GATE-KILLED) — a claim about the machine, not about the tree" ;;
    esac
  fi

  # 2. THE IDENTITY WALL — by design, and the re-authoring land owns it.
  if [ -z "$ARM" ]; then
    case "$body" in
      *"could not be re-authored"*|*"authored by someone GitHub cannot attribute"*|*"git-identity"*)
        ARM="by-design"
        ARM_WHY="the identity gate — the VM authors as noreply@anthropic.com and this repo refuses that range ON PURPOSE; the re-authoring land is what answers it, so the VM has nothing to fix" ;;
    esac
  fi

  # 3. MACHINE-SIDE CAUSES — nothing off-box can clear any of these.
  if [ -z "$ARM" ]; then
    case "$body" in
      *"non-fast-forward"*)              ARM="local-only"; ARM_WHY="the push lost a race with a sibling land (non-fast-forward) — the lander's own retry clears it, not the VM" ;;
      *"CONTENT-VERIFY FAILED"*)         ARM="local-only"; ARM_WHY="post-push content-verify failed on this box — a concurrent rebase-land dropped content; recovery is local" ;;
      *"ALREADY IN FLIGHT"*)             ARM="local-only"; ARM_WHY="another land holds this worktree's in-flight marker — contention on this box" ;;
      *"hit a conflict"*)                ARM="local-only"; ARM_WHY="the rebase onto the trunk conflicted — resolving it needs the trunk the VM's shallow clone cannot see" ;;
      *"REFUSING to land from the shared checkout"*) ARM="local-only"; ARM_WHY="the lander refused the checkout it was pointed at — a local wiring fault" ;;
      *"working tree has uncommitted changes"*)      ARM="local-only"; ARM_WHY="the landing worktree is dirty on this box" ;;
    esac
  fi

  # 4. DOES THE GATE NAME A FILE THE VM WROTE? Searched in that direction (rule 3), full path first
  #    so the ledger can tell a precise hit from a basename one.
  if [ -z "$ARM" ] && [ -n "$paths" ]; then
    local rest p base
    rest="$paths"
    while [ -n "$rest" ]; do
      case "$rest" in *,*) p="${rest%%,*}"; rest="${rest#*,}" ;; *) p="$rest"; rest="" ;; esac
      [ -n "$p" ] || continue
      case "$body" in *"$p"*) ARM="vm"; ARM_MATCH="path:$p"; break ;; esac
      base="${p##*/}"
      [ -n "$base" ] || continue
      case "$body" in *"$base"*) ARM="vm"; ARM_MATCH="basename:$base"; break ;; esac
    done
    [ "$ARM" = vm ] && ARM_WHY="the gate's verdict names a file this session's own commits wrote ($ARM_MATCH) — the VM can see it, edit it and push again"
  fi

  # 5. THE DEFAULT DIRECTION — home, never off-box (rule 4).
  if [ -z "$ARM" ]; then
    ARM="local-only"
    if [ -z "$paths" ]; then
      ARM_WHY="no path set could be derived for this session, so nothing establishes the VM can clear this refusal — uncertainty routes home, never off-box"
    else
      ARM_WHY="the verdict names none of this session's own files (${paths}), so this is not the VM's to fix — a red it did not cause, or a file its clone cannot see"
    fi
  fi
  return 0
}

# ── the payload: the gate's OWN verdict lines, bounded, and the cut NAMED ────────────────────────
# From the first failure marker to the end of the body, contiguous — not a grep of matching lines,
# because a lint's remedy wraps onto continuation lines that carry no marker of their own and a
# filtered payload would deliver the diagnosis without the fix. A bound that trims silently would
# be the same defect one layer down, so the truncation is written into the value.
verdict_lines() { # <body> → the payload text on stdout
  local body="$1" cut="" n
  cut="$(printf '%s\n' "$body" | awk '/✗|⛔|RED|LEAK|FAILED|REFUS/{found=1} found{print}')"
  [ -n "$cut" ] || cut="$(printf '%s\n' "$body" | tail -20)"
  n="${#cut}"
  if [ "$n" -gt "$PAYLOAD_MAX" ]; then
    printf '%s\n[… truncated: %s of %s characters of the gate output are shown]\n' \
      "$(printf '%s' "$cut" | cut -c1-"$PAYLOAD_MAX")" "$PAYLOAD_MAX" "$n"
  else
    printf '%s\n' "$cut"
  fi
}

# ── routing history ──────────────────────────────────────────────────────────────────────────────
route_file() { printf '%s' "$STATE/$1.refusal-route"; }
already_routed() { # <id> <key> → 0 yes
  local f; f="$(route_file "$1")"
  [ -f "$f" ] || return 1
  jq -e --arg k "$2" 'select(.key == $k)' "$f" >/dev/null 2>&1
}
vm_cycles() { # <id> → count on stdout
  local f; f="$(route_file "$1")"
  [ -f "$f" ] || { printf '0'; return 0; }
  jq -s '[.[] | select(.routed == "vm")] | length' "$f" 2>/dev/null || printf '0'
}
record_route() { # <id> <key> <arm> <routed> <detail-json>
  local f; f="$(route_file "$1")"
  mkdir -p "$STATE" 2>/dev/null || return 0
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg at "$(now)" --arg k "$2" \
    --arg arm "$3" --arg r "$4" --argjson d "$5" \
    '{ts:$ts, at:($at|tonumber), key:$k, arm:$arm, routed:$r} + $d' >>"$f" 2>/dev/null || true
}

# ── the sends ────────────────────────────────────────────────────────────────────────────────────
SEND_DETAIL=""
send_vm() { # <id> <message> → 0 queued · 1 not
  local id="$1" msg="$2" out rc
  SEND_DETAIL=""
  [ -n "$OFFLOAD_BIN" ] || { SEND_DETAIL="cc-offload not found on this box"; return 1; }
  out="$("$OFFLOAD_BIN" say "$id" "$msg" 2>&1)"; rc=$?
  SEND_DETAIL="$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
  [ "$rc" -eq 0 ] || return 1
  return 0
}
send_home() { # <notify-back> <message> → 0 sent · 1 not · 3 no target
  local target="$1" msg="$2" out rc
  SEND_DETAIL=""
  [ -n "$target" ] || { SEND_DETAIL="the declaration names no notify-back target — nothing to wake"; return 3; }
  [ -n "$NOTIFY_BIN" ] || { SEND_DETAIL="cc-notify not found on this box"; return 1; }
  out="$("$NOTIFY_BIN" "$target" "$msg" 2>&1)"; rc=$?
  SEND_DETAIL="$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"
  [ "$rc" -eq 0 ] || return 1
  return 0
}

# ── has the branch since landed? ─────────────────────────────────────────────────────────────────
# A refusal whose work is now on trunk is STALE, and routing it would hand the VM a job that is
# already done. BY CONTENT, never by ancestry: the land RE-AUTHORS, so the branch ref is not an
# ancestor of the trunk after a perfect land and `merge-base --is-ancestor` reads NOT-LANDED over
# one (the §1 rule this whole subsystem is organised around).
stale_resolved() { # <id> <paths-csv> → 0 all present on trunk
  local id="$1" paths="$2" repo trunk rest p
  [ -n "$paths" ] || return 1
  repo="$(sed -n 's/^repo=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"
  trunk="$(sed -n 's/^trunk=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"; [ -n "$trunk" ] || trunk="origin/main"
  [ -n "$repo" ] && [ -d "$repo" ] || return 1
  rest="$paths"
  while [ -n "$rest" ]; do
    case "$rest" in *,*) p="${rest%%,*}"; rest="${rest#*,}" ;; *) p="$rest"; rest="" ;; esac
    [ -n "$p" ] || continue
    [ -n "$("$GIT_BIN" -C "$repo" ls-tree "$trunk" -- "$p" 2>/dev/null)" ] || return 1
  done
  return 0
}

# ── attribution ──────────────────────────────────────────────────────────────────────────────────
# The artifact is KEYED on the session id, so attribution is structural rather than inferred — there
# is no "most recent session" anywhere in this file. What is still worth checking is AGREEMENT: the
# branch the refusal names must be the branch the declaration declared. A disagreement means the
# artifact and the declaration are describing different work, and a send composed from one and
# addressed by the other would reach the wrong VM. That is worse than not routing at all.
attrib_check() { # <id> <artifact-branch> → 0 agree · 1 refuse
  local id="$1" abranch="$2" dbranch
  [ -f "$STATE/$id.decl" ] || { ARM_WHY="no declaration for $id — the causing session cannot be identified, so nothing is sent"; return 1; }
  dbranch="$(sed -n 's/^branch=//p' "$STATE/$id.decl" | head -1)"
  [ -n "$abranch" ] || return 0
  [ "$abranch" = "$dbranch" ] && return 0
  ARM_WHY="the refusal names branch '$abranch' but the declaration for $id declares '$dbranch' — they describe different work, so nothing is sent"
  return 1
}

# ── the evidence chain ───────────────────────────────────────────────────────────────────────────
print_chain() { # <id>
  local id="$1" f m
  f="$(route_file "$id")"; m="$STATE/$id.land-refused"
  say "REFUSAL CHAIN — $id"
  say "  declaration : $STATE/$id.decl"
  if [ -f "$STATE/$id.decl" ]; then
    sed -n 's/^\(branch\|account\|repo\|paths\|notify_back\|custody\)=/    \1=/p' "$STATE/$id.decl"
  else say "    (absent)"; fi
  say "  marker      : $m"
  if [ -f "$m" ]; then
    sed -n '1,/^--$/p' "$m" | sed 's/^/    /'
    say "    --- the gate's verdict (first 12 lines of the recorded output) ---"
    sed -n '/^--$/,$p' "$m" | sed '1d' | head -12 | sed 's/^/    /'
  else say "    (no refusal recorded)"; fi
  say "  routes      : $f"
  if [ -f "$f" ]; then
    jq -r '"    · " + .ts + "  arm=" + .arm + "  routed=" + .routed + "  " + ((.why // "")|.[0:150])' "$f" 2>/dev/null
  else say "    (none)"; fi
  say "  sends       : $STATE/$id.sends"
  if [ -f "$STATE/$id.sends" ]; then
    jq -r '"    · " + .ts + "  " + (.msg|.[0:160]|gsub("\n";" "))' "$STATE/$id.sends" 2>/dev/null
  else say "    (none)"; fi
}

# ── one artifact ─────────────────────────────────────────────────────────────────────────────────
handle() { # <session-id>
  local id="$1" art nb url payload msg rc cycles
  art="$STATE/$id.land-refused"
  read_artifact "$art" || { say "· $id — no refusal artifact"; return 0; }

  if already_routed "$id" "$A_KEY"; then
    say "· $id — this refusal is already handled (key $A_KEY); waiting on the VM, not re-sending"
    return 0
  fi

  nb="$(sed -n 's/^notify_back=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"
  url="$(sed -n 's/^url=//p' "$STATE/$id.decl" 2>/dev/null | head -1)"

  if ! attrib_check "$id" "$A_BRANCH"; then
    say "✗ $id — REFUSING TO ROUTE: $ARM_WHY"
    record_route "$id" "$A_KEY" misattributed none "$(jq -cn --arg w "$ARM_WHY" '{why:$w}')"
    ledger "$id" misattributed "$(jq -cn --arg w "$ARM_WHY" '{why:$w}')"
    return 0
  fi

  derive_paths "$id"

  if stale_resolved "$id" "$VM_PATHS"; then
    say "· $id — the refusal is STALE: every declared path is content-present on the trunk, so this work has since landed. Nothing routed."
    record_route "$id" "$A_KEY" stale none "$(jq -cn --arg p "$VM_PATHS" '{paths:$p}')"
    ledger "$id" stale "$(jq -cn --arg p "$VM_PATHS" '{paths:$p}')"
    return 0
  fi

  classify "$A_BODY" "$A_RC" "$VM_PATHS"
  say "→ $id — refusal rc=$A_RC on $A_BRANCH · arm=$ARM"
  say "    why: $ARM_WHY"

  case "$ARM" in
    cut)
      say "    NOT ROUTED — a cut is a non-verdict; the next land pass resumes it. No cycle consumed."
      record_route "$id" "$A_KEY" cut none "$(jq -cn --arg w "$ARM_WHY" '{why:$w}')"
      ledger "$id" cut "$(jq -cn --arg w "$ARM_WHY" --arg b "$A_BRANCH" '{why:$w, branch:$b}')"
      return 0 ;;
  esac

  payload="$(verdict_lines "$A_BODY")"
  cycles="$(vm_cycles "$id")"

  if [ "$ARM" = vm ] && [ "$cycles" -ge "$MAX_CYCLES" ]; then
    # EXHAUSTED. The loop ends here, loudly, with the whole chain — never silently and never with
    # another send. Two failed cycles means the verdict is not one the VM can act on, whatever the
    # classifier thought, and a third would be the same evidence spent again.
    msg="HANDOFF-PING cloud/$id: REFUSAL LOOP EXHAUSTED after $cycles routed cycle(s) on $A_BRANCH — the VM amended and the gate refused again. This one needs you. Chain: $ROOT/scripts/cloud-refusal-route.sh --chain $id · marker: $art · session: $url"
    rc=0; send_home "$nb" "$msg" || rc=$?
    case "$rc" in
      0) say "    EXHAUSTED after $cycles cycle(s) — surfaced to $nb ($SEND_DETAIL)" ;;
      3) say "    EXHAUSTED after $cycles cycle(s) — $SEND_DETAIL" ;;
      *) say "    EXHAUSTED after $cycles cycle(s) — NOT DELIVERED to $nb ($SEND_DETAIL)" ;;
    esac
    print_chain "$id" | sed 's/^/    /'
    record_route "$id" "$A_KEY" exhausted originator "$(jq -cn --arg w "$SEND_DETAIL" --arg c "$cycles" '{why:"the per-session cycle bound is spent", cycles:($c|tonumber), send:$w}')"
    ledger "$id" exhausted "$(jq -cn --arg c "$cycles" --arg w "$SEND_DETAIL" '{cycles:($c|tonumber), send:$w}')"
    return 0
  fi

  if [ "$DRY" = 1 ]; then
    say "    Dry run: would route to $([ "$ARM" = vm ] && echo "the VM ($id)" || echo "the originator (${nb:-none})"). Payload:"
    printf '%s\n' "$payload" | sed 's/^/      | /'
    ledger "$id" dry-run "$(jq -cn --arg a "$ARM" '{arm:$a}')"
    return 0
  fi

  case "$ARM" in
    vm)
      msg="LAND REFUSED — the laptop's land gate refused your branch $A_BRANCH. Nobody read this log for you: what follows is the gate's OWN verdict, verbatim and bounded.

$payload

Do exactly what that verdict says to the file it names, commit the fix (amend or a new commit), and push to $A_BRANCH again. The laptop re-lands automatically once your push goes quiet — you do not need to ask it to. Do not open a PR and do not touch any other file. This is refusal cycle $((cycles + 1)) of $MAX_CYCLES; after that the loop stops and a human is woken instead."
      rc=0; send_vm "$id" "$msg" || rc=$?
      if [ "$rc" -eq 0 ]; then
        say "    ROUTED TO THE VM — queued to $id (cycle $((cycles + 1))/$MAX_CYCLES). $SEND_DETAIL"
        record_route "$id" "$A_KEY" "$ARM" vm "$(jq -cn --arg w "$ARM_WHY" --arg m "$ARM_MATCH" --arg s "$SEND_DETAIL" --arg c "$((cycles + 1))" '{why:$w, match:$m, send:$s, cycle:($c|tonumber)}')"
        ledger "$id" routed-vm "$(jq -cn --arg b "$A_BRANCH" --arg m "$ARM_MATCH" --arg c "$((cycles + 1))" --arg s "$SEND_DETAIL" '{branch:$b, match:$m, cycle:($c|tonumber), send:$s}')"
      else
        # NOT LATCHED. A send that did not go must be retried by the next pass, or the VM waits
        # forever on a message nobody delivered — the same reason cloud-return leaves an unwoken
        # originator unlatched.
        say "    ✗ THE SEND FAILED — not recorded, so the next pass retries it. $SEND_DETAIL"
        ledger "$id" send-failed "$(jq -cn --arg s "$SEND_DETAIL" '{send:$s}')"
      fi ;;
    by-design|local-only)
      msg="HANDOFF-PING cloud/$id: LAND REFUSED (rc=$A_RC) on $A_BRANCH and it is NOT the VM's to fix — $ARM_WHY. Nothing was sent off-box. Chain: $ROOT/scripts/cloud-refusal-route.sh --chain $id · marker: $art · session: $url"
      rc=0; send_home "$nb" "$msg" || rc=$?
      case "$rc" in
        0) say "    ROUTED HOME — $nb woken ($SEND_DETAIL)" ;;
        3) say "    NOT ROUTED — $SEND_DETAIL" ;;
        *) say "    ✗ NOT DELIVERED to $nb ($SEND_DETAIL)" ;;
      esac
      if [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; then
        record_route "$id" "$A_KEY" "$ARM" originator "$(jq -cn --arg w "$ARM_WHY" --arg s "$SEND_DETAIL" '{why:$w, send:$s}')"
      else
        say "    (not recorded — the next pass retries the wake)"
      fi
      ledger "$id" "routed-originator" "$(jq -cn --arg a "$ARM" --arg b "$A_BRANCH" --arg s "$SEND_DETAIL" '{arm:$a, branch:$b, send:$s}')" ;;
  esac
  return 0
}

# ── modes that touch nothing ─────────────────────────────────────────────────────────────────────
if [ "$MODE" = classify ]; then
  read_artifact "$FILE" || { warn "unreadable refusal artifact: $FILE"; exit 2; }
  if [ -n "$FORCED_PATHS" ]; then VM_PATHS="$FORCED_PATHS"; else derive_paths "$A_ID"; fi
  classify "$A_BODY" "$A_RC" "$VM_PATHS"
  say "arm=$ARM"
  say "id=$A_ID"
  say "branch=$A_BRANCH"
  say "rc=$A_RC"
  say "paths=${VM_PATHS:-<none derived>}"
  say "match=${ARM_MATCH:-<none>}"
  say "why=$ARM_WHY"
  exit 0
fi
if [ "$MODE" = chain ]; then
  [ -n "$ONE" ] || { warn "--chain needs a session id"; exit 2; }
  print_chain "$ONE"
  exit 0
fi

# ── the pass ─────────────────────────────────────────────────────────────────────────────────────
# Single-flight for the same reason cloud-return is: this one SENDS, and two overlapping passes
# would double-send the same verdict to the same VM and burn a cycle of a bound that exists to be
# spent on real evidence.
LOCK="$STATE/.refusal-route.lock"
lock_acquire() {
  mkdir -p "$STATE" 2>/dev/null || return 1
  if mkdir "$LOCK" 2>/dev/null; then printf '%s\n' "$$" >"$LOCK/pid" 2>/dev/null; return 0; fi
  local age start
  start="$(cat "$LOCK/at" 2>/dev/null)"; case "$start" in ''|*[!0-9]*) start=0 ;; esac
  age=$(( $(now) - start ))
  if [ "$start" -gt 0 ] && [ "$age" -lt 900 ]; then return 1; fi
  warn "reaping a lock held for ${age}s — a previous pass did not release it"
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || return 1
  return 0
}
# shellcheck disable=SC2329
#   Invoked from the EXIT/INT/TERM trap below, which shellcheck cannot see — it is not dead.
lock_release() { rm -rf "$LOCK" 2>/dev/null || true; }

lock_acquire || { warn "another pass holds the lock — skipping (this is single-flight by design)"; exit 4; }
printf '%s\n' "$(now)" >"$LOCK/at" 2>/dev/null
trap 'lock_release' EXIT INT TERM

if [ "$MODE" = one ]; then
  [ -n "$ONE" ] || { warn "--id needs a session id"; exit 2; }
  handle "$ONE"
  exit 0
fi

# The population is the ARTIFACTS — one refusal, one file, written by W2's return path and by
# nothing else. A disk read, no network: a box with no refusals must cost nothing to sweep.
N=0
for F in "$STATE"/*.land-refused; do
  [ -f "$F" ] || continue
  B="${F##*/}"
  N=$((N + 1))
  handle "${B%.land-refused}"
done
if [ "$N" -eq 0 ]; then say "(no refusal artifacts — nothing to route)"; fi
say "cloud-refusal-route: $N refusal artifact(s) examined."
exit 0
