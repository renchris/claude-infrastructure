#!/usr/bin/env bash
# cloud-bundle-probe.sh — WHY DOES A CLOUD CREATE FAIL FROM THIS REPO?
#
#   scripts/cloud-bundle-probe.sh --measure [--cwd DIR]...        FREE. Spends nothing.
#   scripts/cloud-bundle-probe.sh --ab --account <a> --rounds N --confirm
#   scripts/cloud-bundle-probe.sh --report
#
# ── WHAT THIS EXISTS TO SETTLE ────────────────────────────────────────────────────────────────
# CONCURRENCY_PROGRAM.md §S5.2 filed a SUSPICION: a cloud create from a git worktree hit
# `Bundle upload failed: Socket is closed after 3 attempts` on 3 of 3 ramps, while the same
# account from the main checkout created 2 of 2. The proposed mechanism was "a bundle upload
# walking a `.git` that is an 86-byte gitdir pointer rather than a directory", and the proposed
# remedy was that `handoff-fire.sh --cloud` must fire from the main checkout.
#
# That suspicion is testable WITHOUT spending a single create, because the bundle the CLI uploads
# is built by plain `git bundle create` — so we can build the identical artifact locally and
# measure it. `--measure` does exactly that, which is why it is the default and why it is free.
#
# ── THE CLI's ACTUAL ALGORITHM, read out of the 2.1.220 binary ────────────────────────────────
# The create path only bundles when it cannot use a GitHub source. When it does bundle:
#
#   sizeBytes = (git count-objects -v → size-pack) * 1024        # NOT the working tree
#   maxBytes  = 104857600 (100 MiB)                              # flag tengu_ccr_bundle_max_bytes
#   skipAll   = sizeBytes > maxBytes
#   skipHead  = sizeBytes > 3*maxBytes
#   tooLarge  = skipHead && (sizeBytes > 100*maxBytes || inPack > 5_000_000)
#   tier 1 `git bundle create <tmp> --all`   (unless skipAll)  → accept if file <= maxBytes
#   tier 2 `git bundle create <tmp> HEAD`    (unless skipHead) → accept if file <= maxBytes
#   tier 3 squashed root commit-tree bundle                    → accept if file <= maxBytes
#
# The upload that follows retries 3 times; its failure surfaces as
# `Bundle upload failed: <err>` and, when a GitHub remote WAS detected, the CLI appends
# ". Please setup GitHub on https://claude.ai/code". So that GitHub sentence is NOT evidence of a
# broken account link — it is appended to a TRANSPORT failure too, which is exactly how §S5.2
# came to read a 95 MiB upload timeout as a linking regression.
#
# ── THE LOAD-BEARING PROPERTY, and why cwd cannot be the discriminator ────────────────────────
# `size-pack` is a property of the OBJECT STORE, and a linked worktree SHARES the main checkout's
# object store (its `.git` file points at `<main>/.git/worktrees/<name>`, whose `objects` is the
# common dir). So the tier decision and the bundle contents are the same from either cwd, and any
# difference is confined to which commit HEAD names plus whatever `git stash create` captures.
# `--measure` reports both cwds' numbers side by side so this is read off a measurement rather
# than argued.
#
# ── THE --ab ARM, and why it needs a SIZE control rather than only a cwd control ──────────────
# A cwd A/B alone cannot separate "worktrees are cursed" from "a 95 MiB upload is marginal", and
# §S5.2's 3-of-3 vs 2-of-2 is exactly the sample size at which a coin looks like a cause. So --ab
# interleaves THREE arms against one account: `wt` (worktree), `main` (main checkout), and `small`
# — a throwaway one-commit repo whose bundle is kilobytes. `small` is the POSITIVE CONTROL: if
# creates succeed there and fail from the two big-repo arms at comparable rates, bundle SIZE is
# the cause and cwd is exonerated. If `small` fails just as often, the cause is neither and the
# instrument says so instead of publishing a cwd verdict it did not earn.
# Arms are interleaved, never run in blocks, so a transient network window cannot land entirely
# on one arm and manufacture a difference.
#
# COST: --measure spends NOTHING. --ab spends one real create per attempt on a real account and
# leaves real cloud sessions behind, so --confirm is mandatory and --rounds has no default.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
LEDGER="${CLOUD_BUNDLE_LEDGER:-$HOME/.claude/autonomy/cloud/bundle-probe.jsonl}"
MAX_BYTES=104857600            # XO_ in the 2.1.220 binary; the flag override is server-side
RUN_ID="${CLOUD_BUNDLE_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"

mkdir -p "$(dirname "$LEDGER")"

die() { echo "cloud-bundle-probe: $*" >&2; exit 2; }
have() { command -v "$1" >/dev/null 2>&1; }
have jq || die "jq is required"

emit() { printf '%s\n' "$1" | jq -c --arg r "$RUN_ID" '. + {run:$r}' >> "$LEDGER"; }

# ── FREE ARM ─────────────────────────────────────────────────────────────────────────────────
# Replicates the CLI's tier decision and then BUILDS the tier-2 artifact, because the decision is
# arithmetic we can get wrong and the file size is not.
measure_one() { # $1 = dir
  local d="$1" gitkind toplevel common sp inpack sizeb predicted bundle bytes dirty
  [ -d "$d" ] || { echo "  SKIP $d — no such directory"; return 0; }
  if ! git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  SKIP $d — not a git repository"; return 0
  fi

  if [ -f "$d/.git" ]; then gitkind="file ($(wc -c < "$d/.git" | tr -d ' ') B gitdir pointer)"
  elif [ -d "$d/.git" ]; then gitkind="directory"
  else gitkind="unknown"; fi

  toplevel="$(git -C "$d" rev-parse --show-toplevel)"
  common="$(git -C "$d" rev-parse --git-common-dir)"
  # count-objects reads the OBJECT STORE, which a worktree shares with its main checkout — the
  # single fact that decides this whole question.
  sp="$(git -C "$d" count-objects -v 2>/dev/null | awk -F': *' '/^size-pack:/{print $2}')"
  inpack="$(git -C "$d" count-objects -v 2>/dev/null | awk -F': *' '/^in-pack:/{print $2}')"
  sizeb=$(( ${sp:-0} * 1024 ))
  dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

  # Mirror the binary's tier arithmetic exactly.
  local skipall=0 skiphead=0 toolarge=0
  [ "$sizeb" -gt "$MAX_BYTES" ] && skipall=1
  [ "$sizeb" -gt $(( 3 * MAX_BYTES )) ] && skiphead=1
  if [ "$skiphead" = 1 ] && { [ "$sizeb" -gt $(( 100 * MAX_BYTES )) ] || [ "${inpack:-0}" -gt 5000000 ]; }; then toolarge=1; fi
  if [ "$skipall" = 0 ]; then predicted="all"; elif [ "$skiphead" = 0 ]; then predicted="head"
  elif [ "$toolarge" = 1 ]; then predicted="too_large"; else predicted="squashed"; fi

  # Build the artifact the CLI would upload at the predicted tier. `git bundle create` writes a
  # file and touches no ref, so this is safe to run against a checkout another session is using.
  bundle="$(mktemp -t ccbundle).bundle"
  case "$predicted" in
    all)  git -C "$d" bundle create "$bundle" --all >/dev/null 2>&1 || true ;;
    head) git -C "$d" bundle create "$bundle" HEAD  >/dev/null 2>&1 || true ;;
    *)    : ;;   # squashed/too_large would need refs written into a SHARED ref store — not here
  esac
  bytes="$( [ -f "$bundle" ] && wc -c < "$bundle" | tr -d ' ' || echo 0 )"
  rm -f "$bundle"

  printf '  %-52s %s\n' "cwd" "$d"
  printf '    %-22s %s\n' ".git" "$gitkind"
  printf '    %-22s %s\n' "toplevel" "$toplevel"
  printf '    %-22s %s\n' "git-common-dir" "$common"
  printf '    %-22s %s KB (%s bytes)\n' "size-pack" "${sp:-?}" "$sizeb"
  printf '    %-22s %s\n' "in-pack" "${inpack:-?}"
  printf '    %-22s %s file(s)  (CLI adds refs/seed/stash when non-zero)\n' "uncommitted" "$dirty"
  printf '    %-22s %s\n' "predicted tier" "$predicted"
  if [ "$bytes" -gt 0 ]; then
    printf '    %-22s %s bytes (%s MiB) — %s%% of the %s MiB cap\n' "MEASURED bundle" "$bytes" \
      "$(awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1048576}')" \
      "$(awk -v b="$bytes" -v m="$MAX_BYTES" 'BEGIN{printf "%.0f", 100*b/m}')" \
      "$(awk -v m="$MAX_BYTES" 'BEGIN{printf "%.0f", m/1048576}')"
  else
    printf '    %-22s not built (tier %s writes refs into a shared store)\n' "MEASURED bundle" "$predicted"
  fi
  echo
  emit "$(jq -n --arg k measure --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cwd "$d" \
    --arg gitkind "$gitkind" --arg tier "$predicted" \
    --argjson sp "${sp:-0}" --argjson inpack "${inpack:-0}" --argjson sizeb "$sizeb" \
    --argjson bytes "$bytes" --argjson dirty "${dirty:-0}" \
    '{kind:$k,ts:$ts,cwd:$cwd,git:$gitkind,size_pack_bytes:$sizeb,in_pack:$inpack,predicted_tier:$tier,bundle_bytes:$bytes,uncommitted:$dirty}')"
}

cmd_measure() {
  local dirs=("$@")
  if [ "${#dirs[@]}" -eq 0 ]; then
    dirs=("$PWD")
    # The comparison is the point, so offer the main checkout automatically when we are in a
    # linked worktree — otherwise the default invocation answers only half the question.
    local cdir; cdir="$(git -C "$PWD" rev-parse --git-common-dir 2>/dev/null || true)"
    case "$cdir" in
      /*) local main; main="$(dirname "$cdir")"; [ "$main" != "$PWD" ] && dirs+=("$main") ;;
    esac
  fi
  echo "cloud-bundle-probe --measure   (free; cap = $MAX_BYTES bytes)   ledger=$LEDGER"
  echo
  local d; for d in "${dirs[@]}"; do measure_one "$d"; done
  echo "Read it this way: equal size-pack across cwds ⇒ ONE object store ⇒ cwd cannot change the"
  echo "bundle, so a cwd-correlated failure is coincidence unless some OTHER mechanism is named."
}

cmd_report() {
  [ -f "$LEDGER" ] || die "no ledger at $LEDGER — nothing probed yet"
  jq -r 'select(.kind=="measure") | "measure \(.ts) tier=\(.predicted_tier) bundle=\(.bundle_bytes) cwd=\(.cwd)"' "$LEDGER"
  jq -r 'select(.kind=="ab") | "ab      \(.ts) arm=\(.arm) outcome=\(.outcome) acct=\(.account) cwd=\(.cwd)"' "$LEDGER"
  echo
  echo "── per-arm tally ──"
  jq -r 'select(.kind=="ab") | "\(.arm) \(.outcome)"' "$LEDGER" | sort | uniq -c | sort -k2
}

# ── CREATE A/B ARM ───────────────────────────────────────────────────────────────────────────
# THE CREATE NO LONGER LIVES HERE. It was factored out to scripts/lib/cloud-create.sh — the pty
# allocator, the normaliser, the classifier, the id extraction and the retry — so the fire path
# (`handoff-fire.sh --cloud`, CLOUD_OBSERVABILITY.md §10.4) could use THIS implementation rather
# than become a fourth copy. `fire_one` below is now an adapter over that library, and its
# behaviour here is unchanged in the two ways this instrument depends on:
#
#   * normalisation still maps BOTH cursor-FORWARD (CSI n C) and cursor-horizontal-ABSOLUTE
#     (CSI n G) to a space. That was this file's own hard-won finding — the ceiling probe's
#     post-mortem named C alone, and handling C alone left the exact symptom the fix was written to
#     remove (`Error:[8GBundle[15Gupload[22G…` fusing into one unmatchable word). The library
#     carries it, plus a wider CSI parameter class so a private-mode sequence INSIDE a phrase
#     cannot break the match either.
#   * a bare `session_…` no longer counts as a create. This file's classify accepted it, which is
#     harmless where all we do is tally but wrong for a caller that then declares the id.
#
# 🚨 THE SINGLE-ATTEMPT CALL IS LOAD-BEARING HERE. The library also exposes `cc_cloud_create`, a
# bounded retry over the transient class — and this instrument must NOT use it. The number this
# probe exists to produce is the PER-ATTEMPT success rate (§S5.3: roughly 50-75%); wrapping the
# attempt in a retry would make every round report the success of up to N attempts under the name
# of one, inflating the rate and erasing the very marginality it measured. `create_once` is the
# measurement; the retry is a consumer's policy built on top of it.
_CC_BP_LIB="$ROOT/scripts/lib/cloud-create.sh"
[ -f "$_CC_BP_LIB" ] || die "missing $_CC_BP_LIB (the create implementation)"
# shellcheck source=scripts/lib/cloud-create.sh
. "$_CC_BP_LIB"
export CC_CLOUD_CREATE_BIN="${CLOUD_BUNDLE_CLAUDE_BIN:-$CC_CLOUD_CREATE_BIN}"
export CC_CLOUD_CREATE_TIMEOUT_S="${CLOUD_BUNDLE_TIMEOUT_S:-300}"

fire_one() { # $1=cfgdir $2=cwd $3=label -> "<outcome>\t<session id>\t<first 300 chars>"
  cc_cloud_create_once "$1" "$2" "$3"
}

cmd_ab() {
  local acct="" rounds="" confirm=0 arms="wt,main"
  while [ $# -gt 0 ]; do
    case "$1" in
      --account) acct="${2:-}"; shift 2 ;;
      --rounds)  rounds="${2:-}"; shift 2 ;;
      --arms)    arms="${2:-}"; shift 2 ;;
      --confirm) confirm=1; shift ;;
      *) die "unknown --ab arg: $1" ;;
    esac
  done
  [ -n "$acct" ]   || die "--account is required"
  [ -n "$rounds" ] || die "--rounds has no default — every round spends 3 real creates"
  [ "$confirm" = 1 ] || die "refusing without --confirm: each attempt spends real quota and leaves a live cloud session"

  local cfg; cfg="$(python3 -c "
import json,os,sys
c=json.load(open(os.path.expanduser('~/.claude/accounts.json')))
a=c['accounts'] if isinstance(c,dict) else c
m={x['name']:x['config_dir'] for x in a}
print(os.path.expanduser(m.get(sys.argv[1],'')))" "$acct")"
  [ -n "$cfg" ] && [ -d "$cfg" ] || die "no config_dir for account '$acct'"

  # ── the `small` arm is OPT-IN, and the reason is a methodology constraint, not laziness ──
  # `small` is the size POSITIVE CONTROL: a one-commit repo whose bundle is kilobytes instead of
  # 95 MiB. Measured 2026-08-09, a freshly-created directory stops on Claude Code's folder-trust
  # prompt ("Is this a project you created or one you trust?") and never reaches the create — so
  # it costs no quota, but it also yields no datum. The two ways past it both DISQUALIFY it as a
  # control: `--dangerously-skip-permissions` makes the arm differ from `wt`/`main` in something
  # other than bundle size, and pre-seeding `hasTrustDialogAccepted` means a read-modify-write of
  # an account `.claude.json` that a live session may be writing concurrently.
  # So: run `--arms wt,main,small` ONLY after trusting the control directory once interactively
  # in the target account. Absent that, the A/B compares two arms of EQUAL size, which is exactly
  # what the filed cwd claim needs and is the default.
  local small=""
  case ",$arms," in *,small,*)
    # Identity is passed TRANSIENTLY via `git -c`, never written with `git config`: ~100 linked
    # worktrees share one .git/config here, and a `git config` whose -C target is a bare variable
    # is a no-op the moment that variable is empty — which lands the write in the CURRENT repo and
    # re-authors its commits. The transient form cannot persist at all, so it cannot leak.
    small="${CLOUD_BUNDLE_SMALL_DIR:-$(mktemp -d -t ccsmall)/repo}"
    if [ ! -d "$small/.git" ]; then
      mkdir -p "$small"
      ( cd "${small:?control repo path required}" && git init -q . \
        && echo "cloud-bundle-probe positive control" > README.md && git add README.md \
        && git -c user.email=probe@example.invalid -c user.name=probe commit -qm "control" ) \
        || die "could not build the small-repo control"
    fi
    ;;
  esac

  local wt="$PWD" main; main="$(dirname "$(git -C "$PWD" rev-parse --git-common-dir)")"
  case "$main" in .) main="$PWD" ;; esac

  echo "cloud-bundle-probe --ab  account=$acct rounds=$rounds arms=$arms  run=$RUN_ID"
  printf '  arm wt    = %s\n  arm main  = %s\n' "$wt" "$main"
  [ -n "$small" ] && printf '  arm small = %s\n' "$small"
  echo

  local r arm d outcome msg line rest sid
  for r in $(seq 1 "$rounds"); do
    # Interleaved, never blocked: a transient network window must not land entirely on one arm.
    for arm in ${arms//,/ }; do
      case "$arm" in
        wt) d="$wt" ;; main) d="$main" ;;
        small) d="$small"; [ -n "$small" ] || die "arm 'small' requested but no control repo" ;;
        *) die "unknown arm: $arm" ;;
      esac
      line="$(fire_one "$cfg" "$d" "cloud-bundle-probe $arm r$r: print the repository name, then stop. Do not modify any files.")"
      outcome="${line%%$'\t'*}"; rest="${line#*$'\t'}"; sid="${rest%%$'\t'*}"; msg="${rest#*$'\t'}"
      printf '  r%s %-6s %-16s %s %s\n' "$r" "$arm" "$outcome" "$sid" "$(printf '%s' "$msg" | cut -c1-90)"
      # The session id goes in the ledger. This probe's own closing line tells the operator to
      # DECLARE every created session — which was unactionable while the id lived only in a
      # truncated msg field, and an undeclared session is both unobservable and reaper-invisible.
      emit "$(jq -n --arg k ab --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg arm "$arm" \
        --arg cwd "$d" --arg acct "$acct" --arg o "$outcome" --arg m "$msg" --arg sid "$sid" \
        '{kind:$k,ts:$ts,arm:$arm,cwd:$cwd,account:$acct,outcome:$o,session:$sid,msg:$m}')"
    done
  done
  case ",$arms," in *,small,*) [ -n "${CLOUD_BUNDLE_SMALL_DIR:-}" ] || rm -rf "$(dirname "$small")" ;; esac
  echo; echo "── tally ──"; cmd_report | sed -n '/per-arm tally/,$p'
  echo
  echo "DECLARE every created session (cc-cloud declare --id … --branch …) — an undeclared one is"
  echo "unobservable AND the 600s reaper archives it."
}

usage() { sed -n '2,12p' "$SELF"; }

case "${1:-}" in
  --measure|"") shift || true; cmd_measure "$@" ;;
  --report)     cmd_report ;;
  --ab)         shift; cmd_ab "$@" ;;
  -h|--help)    usage ;;
  *)            usage; exit 2 ;;
esac
