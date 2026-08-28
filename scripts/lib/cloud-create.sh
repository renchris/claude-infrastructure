#!/usr/bin/env bash
# cloud-create.sh — THE cloud-create implementation. Sourced, never executed.
#
#   cc_cloud_normalise            stdin → stdout      strip the pty's terminal control, keep the WORDS
#   cc_cloud_classify             stdin → one token   created|refused-{bundle,quota,harness,other}
#   cc_cloud_session_id           stdin → session_…   "" when the output names no session
#   cc_cloud_create_once  cfg cwd prompt  → "<outcome>\t<id>\t<msg>"
#   cc_cloud_create       cfg cwd prompt  → same, with a BOUNDED retry over the transient class
#
# ── WHY THIS FILE EXISTS RATHER THAN A FOURTH COPY ────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §10.4 graded G5 ✅ on the parts that were built and discovered the fire
# path issues no create at all: `handoff-fire.sh` parses `--cloud`, gates it default-off and prices
# it against account headroom, then never invokes one. The three real creates in the tree all live
# in probes — `cloud-bundle-probe.sh:fire_one`, `cloud-ceiling-probe.sh`, `cloud-websetup-drive.sh`
# — so the fire path's create had to come from somewhere, and §10.4 says explicitly: factor it out
# of a probe "rather than written a fourth time". This is that factoring. `fire_one` is the parent:
# it is the smallest correct create and it already carries the two things a naive one gets wrong.
#
# ── THE TWO THINGS A NAIVE CREATE GETS WRONG ──────────────────────────────────────────────────
# 1. THE PTY IS NOT OPTIONAL. `claude --cloud` refuses its own capture: "Error: --cloud requires an
#    interactive terminal." And the usual macOS allocator does not survive an agent tool call —
#    `script -q /dev/null` calls tcgetattr on ITS OWN stdin and dies "Operation not supported on
#    socket" from anything without a controlling terminal (cron, launchd, a hook, a fired session).
#    Both refusals are in the ceiling-probe ledger, rows 1/2/5. scripts/lib/pty-run.py is the
#    allocator that needs nothing of the caller's stdin.
# 2. THE NORMALISER DECIDES WHETHER A REFUSAL IS READABLE AT ALL — see below.
#
# ── `refused-other` WAS NEVER MEASURING AN UNKNOWN REFUSAL. IT WAS MEASURING THE NORMALISER. ───
# A TUI does not emit runs of spaces; it emits cursor motion — CSI n C (forward) and CSI n G
# (horizontal ABSOLUTE). Delete those as decoration and the words fuse. Every classifier pattern
# downstream contains a space ("Bundle upload failed", "weekly limit reached", "interactive
# terminal"), so a refusal rendered that way matches NOTHING and is filed as `refused-other` — the
# instrument reporting a non-verdict in the one direction that looks like honest abstention.
#
# This is not a hypothesis. Measured 2026-08-09 over the two probe ledgers on this box:
#
#   ~/.claude/autonomy/cloud/ceiling-probe.jsonl   9 of 9 `refused-other` rows have an identifiable
#                                                  cause and NONE is unknown: 6 are real bundle
#                                                  refusals (3 fused, 1 raw `[8GBundle[15Gupload`,
#                                                  2 spaced) and 3 are rig faults (2 "requires an
#                                                  interactive terminal", 1 "script: tcgetattr").
#   ~/.claude/autonomy/cloud/bundle-probe.jsonl    1 of 1 `refused-other` is a real bundle refusal
#                                                  (`Error:Bundleuploadfailed:Socketisclosed…`),
#                                                  beside 2 `refused-bundle` rows carrying the SAME
#                                                  refusal with its spaces intact.
#
# So the bucket that exists to say "we could not tell" contained, in every measured instance, a
# refusal the rig could have told.
#
# ⚠️ THE PRODUCER IS `pty-run.py:strip_ansi`, NOT the probes' own normalise() — measured, because
# the obvious attribution is wrong and would have sent the fix to the wrong file.
# `cloud-bundle-probe.sh:normalise()` already maps BOTH C and G to a space (its own header records
# that "handling C alone left the exact symptom the fix was written to remove"), so its ledger's
# fused row predates that fix rather than demonstrating it. Replaying the real CSI-G artifact
# through `strip_ansi` verbatim reproduces the ledger byte-shape exactly:
#     Error:\x1b[8GBundle\x1b[15Gupload…  →  'Error:Bundleuploadfailed:Socketis closed'
# fused where the sequence was G and spaced where it was C — which is precisely the
# `Error:Bundleuploadfailed:…Pleasesetup  GitHubon` shape in the ceiling ledger. `strip_ansi`
# converts `CSI n C` to spaces and lets `CSI n G` fall through to its generic CSI delete, one line
# below a comment lecturing about this exact failure. That is fixed at the source in the same
# change as this file; this library never sets PTY_RUN_STRIP_ANSI and normalises the raw bytes
# itself, so it does not depend on that fix having landed.
#
# ── WHAT THIS ADDS OVER `fire_one`, each demonstrated by a control in tests/cloud-create-lib.bats ─
#   * THE ECMA-48 CSI GRAMMAR — parameter bytes 0x30-0x3F, intermediate 0x20-0x2F, one final
#     0x40-0x7E — against fire_one's hand-written [0-9;?]*. The narrow class omits the private-mode
#     introducers < = > ?, so such a sequence is not matched, the later control sweep eats its bare
#     ESC, and its parameters survive as literal text — cosmetic at the head of a line (the
#     `78[<u[>1u[>4;2m` prefix on almost every bundle-probe msg), NOT cosmetic inside a phrase the
#     classifier greps: `Bundle\x1b[>4m\x1b[<u upload failed` reads `refused-other` under the
#     narrow class and `refused-bundle` under this one.
#   * A bare `session_…` no longer counts as a create. fire_one's classify accepts
#     `*"Created cloud session"*|*"session_"*`, so a refusal that merely QUOTES an id — a resume
#     hint, a "session_… not found" — classifies as `created`. Harmless in a probe that only
#     tallies; on the fire path it declares a session that does not exist. Only the CLI's own
#     success banner is a create now.
#   * Id extraction, and `created-unidentified` when it fails (below).
#   * The bounded retry (below).
#
# Two properties the sweep ORDER depends on: OSC strings are consumed WHOLE before the generic CSI
# sweep (or the introducer goes first and the payload "11;?" survives as text), and the C/G→space
# rule runs before the generic sweep can delete them.
#
# ── THE RETRY RULE: ONLY THE CLASS MEASURED TRANSIENT ─────────────────────────────────────────
# CONCURRENCY_PROGRAM.md §S5.3 measured cloud create at roughly 50-75% success per attempt and
# reached a session on attempt 2 of 4 twice over, and it named the mechanism: the CLI bundles ~95
# MiB against a 100 MiB cap and the upload retries 3 times internally — marginal by construction,
# and failing by round rather than by cwd. That makes `refused-bundle` the transient class.
#
# Nothing else is retried, and each exclusion is a rule rather than a guess:
#   refused-quota    a shared account limit. Retrying inside one fire cannot clear it and spends
#                    the next attempt against the same wall.
#   refused-harness  OUR rig is broken (no binary, no pty, an unknown option). Retrying a fault in
#                    the instrument produces the same fault, more expensively.
#   refused-other    genuinely unclassified. Measured above: with this normaliser the bucket had no
#                    true members, so a member now is a NEW refusal shape — the one case where
#                    spending quota on a repeat is least defensible and reporting it is worth most.
# Retrying an unknown refusal is how quota gets spent on a permanent condition.
#
# ── created-unidentified: THE OUTCOME THAT MUST NOT FOLD ──────────────────────────────────────
# A create can succeed while the id extraction fails. Folding that into `created` hands the caller
# an empty id to declare; folding it into a refusal reports "no session" while one is running. It
# is neither, so it is its own outcome and it is LOUD: a live cloud session that was never declared
# is unobservable by construction (§1) AND the 600 s orphan reaper cannot see it either, which is
# the precise failure this whole document is organised against — quota burning where nothing local
# can attribute, judge or reap it.
#
# bash 3.2-safe (no declare -A, no mapfile). No `set -e` dependence: sourced into callers that vary.

# Guard against double-sourcing (handoff-fire.sh and a probe may both reach this in one process).
[ -n "${CC_CLOUD_CREATE_LIB:-}" ] && return 0
CC_CLOUD_CREATE_LIB=1

# The claude binary that has --cloud. 2.1.114 does NOT; 2.1.220 does. Overridable per caller so a
# test can point at a stub and a probe can pin a track.
: "${CC_CLOUD_CREATE_BIN:=$HOME/.claude-220/node_modules/.bin/claude}"
: "${CC_CLOUD_CREATE_TIMEOUT_S:=300}"
: "${CC_CLOUD_CREATE_ATTEMPTS:=3}"
: "${CC_CLOUD_CREATE_BACKOFF_S:=5}"

# Resolve pty-run.py relative to THIS file, not to $0 or $PWD: the library is sourced from
# handoff-fire.sh (scripts/), from probes (scripts/), and from bats (tests/), and only
# BASH_SOURCE[0] is the same answer in all three.
cc_cloud_lib_dir() { local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || return 1; printf '%s' "$d"; }
: "${CC_CLOUD_PTY_RUN:=$(cc_cloud_lib_dir)/pty-run.py}"

cc_cloud_normalise() {
  python3 -c '
import sys, re
d = sys.stdin.buffer.read().decode("utf-8", "replace")
# OSC … BEL|ST consumed WHOLE, before anything can eat its introducer.
d = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", d)
# CURSOR MOTION IS WHITESPACE. Forward (C) and horizontal-absolute (G) both become a space, or the
# words fuse and every spaced classifier pattern stops matching. This is the whole reason
# refused-other was over-populated in both probe ledgers.
d = re.sub(r"\x1b\[[0-9;]*[CG]", " ", d)
# Every other CSI, by the ECMA-48 grammar rather than an enumerated guess: parameter bytes
# 0x30-0x3F (which is what brings in the private-mode introducers < = > ?), then intermediate
# bytes 0x20-0x2F, then exactly one final byte 0x40-0x7E. Spelling the ranges is both wider and
# stricter than a hand-written character class, and it is what stops a sequence losing its ESC to
# the control sweep below and leaving its parameters behind as literal text.
d = re.sub(r"\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]", "", d)
d = re.sub(r"\x1b[()][A-Za-z0-9]", "", d)          # charset select
d = re.sub(r"\x1b[78=><NOPcM]", "", d)             # single-char escapes
d = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", d)  # stray controls, incl. any bare ESC
d = d.replace("\r\n", "\n").replace("\r", "\n")
sys.stdout.write(re.sub(r"[ \t]+", " ", d))'
}

cc_cloud_classify() { # stdin = NORMALISED output → one token on stdout
  local t; t="$(cat)"
  case "$t" in
    *"Created cloud session"*) echo created; return ;;
  esac
  # A fault in OUR OWN rig is classified FIRST and separately, so it is never published as a
  # property of the fleet (the `refused-harness` lesson, cloud-ceiling-probe.sh).
  if printf '%s' "$t" | grep -qiE 'interactive terminal|tcgetattr|Operation not supported on socket|pty-run:|unknown option|no claude binary|cannot exec'; then
    echo refused-harness; return
  fi
  if printf '%s' "$t" | grep -qiE 'Bundle upload failed|Repo is too large'; then echo refused-bundle; return; fi
  if printf '%s' "$t" | grep -qiE 'limit|quota|rate.?limit|exceeded'; then echo refused-quota; return; fi
  # A bare `session_…` with no "Created cloud session" banner reaches here rather than `created`.
  # cloud-bundle-probe.sh's classify accepted `*"session_"*` as a create, which also matches a
  # refusal that happens to quote an id (a resume hint, a "session_… not found"). The banner is the
  # CLI's own success line; the id is not evidence of anything on its own.
  echo refused-other
}

cc_cloud_session_id() { # stdin = NORMALISED output → session id, or "" (rc 1)
  # Anchored on the two places the CLI PRINTS the id as a machine handle — the view URL and the
  # teleport line — before falling back to a bare token. A create banner's TITLE is free text the
  # caller chose, so an unanchored first-match could return an id out of the prompt's own words.
  python3 -c '
import sys, re
d = sys.stdin.read()
for pat in (r"claude\.ai/code/(session_[A-Za-z0-9]+)",
            r"--teleport\s+(session_[A-Za-z0-9]+)",
            r"\b(session_[A-Za-z0-9]{16,})\b"):
    m = re.search(pat, d)
    if m:
        sys.stdout.write(m.group(1)); sys.exit(0)
sys.exit(1)'
}

cc_cloud_create_once() { # $1=cfgdir $2=cwd $3=prompt → "<outcome>\t<id>\t<msg>"
  local cfg="$1" dir="$2" prompt="$3" out norm outcome id
  if [ ! -x "$CC_CLOUD_CREATE_BIN" ]; then
    printf 'refused-harness\t\tno claude binary at %s' "$CC_CLOUD_CREATE_BIN"; return 0
  fi
  if [ ! -f "$CC_CLOUD_PTY_RUN" ]; then
    printf 'refused-harness\t\tno pty allocator at %s' "$CC_CLOUD_PTY_RUN"; return 0
  fi
  # `|| true` is deliberate and bounded: the CLI exits non-zero on every refusal, and the OUTPUT is
  # the verdict, not the status. Swallowing the status here is safe only because classify() reads
  # the text — never because a failure is being ignored.
  out="$(cd "$dir" 2>/dev/null && PTY_RUN_TIMEOUT_S="$CC_CLOUD_CREATE_TIMEOUT_S" \
         CLAUDE_CONFIG_DIR="$cfg" python3 "$CC_CLOUD_PTY_RUN" "$CC_CLOUD_CREATE_BIN" \
         --cloud "$prompt" 2>&1 || true)"
  norm="$(printf '%s' "$out" | cc_cloud_normalise)"
  outcome="$(printf '%s' "$norm" | cc_cloud_classify)"
  id=""
  if [ "$outcome" = created ]; then
    id="$(printf '%s' "$norm" | cc_cloud_session_id)" || id=""
    # A live session we cannot name is strictly worse than no session: unobservable AND unreapable.
    [ -n "$id" ] || outcome=created-unidentified
  fi
  printf '%s\t%s\t%s' "$outcome" "$id" "$(printf '%s' "$norm" | tr -d '\n' | cut -c1-300)"
}

cc_cloud_create() { # $1=cfgdir $2=cwd $3=prompt → "<outcome>\t<id>\t<msg>"; bounded retry
  local cfg="$1" dir="$2" prompt="$3" line outcome n=1
  while :; do
    line="$(cc_cloud_create_once "$cfg" "$dir" "$prompt")"
    outcome="${line%%$'\t'*}"
    [ "$outcome" = refused-bundle ] || break          # only the measured-transient class repeats
    [ "$n" -lt "$CC_CLOUD_CREATE_ATTEMPTS" ] || break
    printf 'cloud-create: attempt %s/%s hit %s — retrying in %ss (§S5.3: ~50-75%% per attempt)\n' \
      "$n" "$CC_CLOUD_CREATE_ATTEMPTS" "$outcome" "$CC_CLOUD_CREATE_BACKOFF_S" >&2
    sleep "$CC_CLOUD_CREATE_BACKOFF_S"
    n=$((n + 1))
  done
  printf '%s' "$line"
}

# The branch a fired cloud session is DECLARED against, and it must be assigned rather than guessed.
#
# Measured 2026-08-09: `git ls-remote --heads origin 'claude/*'` returns ZERO rows — no cloud
# session has ever pushed — and the one prior fire-shaped declaration on this box names
# `claude/fire-20260809T101645Z-78351`, a branch with no producer anywhere in the tree. It was a
# guess. A declaration against a branch the session will never push to reads C1 NOT-STARTED
# forever, which is §10.2c's hazard with the sign flipped: a confident verdict computed from
# evidence that has nothing to do with the session.
#
# So the firing side NAMES the branch and the payload instructs the push (see
# cc_cloud_brief_trailer below). That also settles §10.2c's own hazard in the other direction: the
# name is unique per fire, so — unlike `--branch main`, where trunk's background traffic reads as a
# heartbeat forever — nothing but this session can advance it. O2 becomes a real signal.
cc_cloud_branch_name() { printf 'claude/fire-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$"; }

# ── THE BRIEF TRAILER — the executable form of CLOUD_OBSERVABILITY.md §4.1's absence contract ────
#
# §4.1 is the load-bearing paragraph of the whole observability design: "a declared cloud session
# that has pushed nothing is indistinguishable from one that never started, one that died at boot,
# and one that was refused entitlement… It can only be resolved by CONTRACT: the fire declares a
# branch and a boot budget, and the session's brief REQUIRES ITS FIRST ACT TO BE PUSHING THAT
# BRANCH — an empty commit is enough." §4.3's C1 arm and §8 step 2 both cite it by name.
#
# 🚨 IT WAS PROSE ONLY, ON BOTH LEGS, AND THAT MADE C1 UNREADABLE (backlog 0c8b39b67665).
# What the two fire paths actually shipped before this function existed:
#
#   CLI  (handoff-fire.sh)  a trailer titled "HOW TO RETURN YOUR WORK" — `switch -c` then push,
#                           with "push whatever you have BEFORE YOU FINISH". A push at the END.
#   API  (cc-offload up --via api, the shipping path)  the brief VERBATIM. No trailer at all, so
#                           the branch cc-offload declares was never even named to the session.
#
# A return-channel push and a boot beacon are not the same instruction, and only the second one
# discriminates. Under "push before you finish", a session twenty minutes into a three-hour brief
# has pushed nothing FOR THE CORRECT REASON, and it reads byte-identically to a session that never
# booted: both are `ls-remote` rc=0 with empty stdout, past `declared_at + boot_s`, i.e. C1
# NOT-STARTED. So C1 could not mean "never booted" — it meant "no ref", which is seven worlds at
# once (§4.4), one of which is healthy. An alarm that fires on a healthy population is the
# alarm-polarity defect this document is organised against, and the actuation is real: §12's
# `cc-offload gc` retires on it and a re-fire spends quota against a session that is still working.
#
# The beacon is what buys the discrimination, and it is cheap in exactly the way §4.1 says: ONE
# empty commit in the first minute. After it, absence of the ref past the boot budget can only be
# never-booted / died-at-boot / refused-entitlement — every one of them actionable — and presence
# of the ref hands §4.3 its C4/C5 arms (sha unchanged vs advanced) instead of nothing at all.
#
# ONE COMPOSER, TWO LEGS. It lives here beside `cc_cloud_branch_name` because the branch name and
# the instruction that makes that name observable are one fact: a leg that assigns the branch and
# does not carry this trailer is declaring against a ref nothing will ever push (the §10.2c hazard
# with the sign flipped, which is what this file's header already refuses to let happen twice).
#
# $2 (the session id) is OPTIONAL because the CLI leg does not have one yet: on that leg the id is
# a return value of the create, and the payload must be composed before the create is issued
# (§8.1). The beacon subject falls back to the branch, which is unique per fire either way.
cc_cloud_brief_trailer() { # $1 = declared branch  [$2 = session id] → the trailer on stdout
  local br="$1" tag="${2:-}"
  [ -n "$br" ] || return 2
  [ -n "$tag" ] || tag="$br"
  cat <<TRAILER

── FIRST ACT — PUSH THE BOOT BEACON, BEFORE YOU DO ANYTHING ELSE ───────────────────────────────
You are running off-box, on an Anthropic-managed VM. Nothing on the operator's machine can see
your filesystem, your processes or your terminal. The single fact their instruments CAN observe
about you is whether this branch exists on the remote:

    $br

Create it and push it NOW, before you start the work above. An EMPTY commit is enough, and is
exactly what is wanted:

    git switch -c $br
    git commit --allow-empty -m "boot beacon: $tag"
    git push -u origin HEAD

This is not bookkeeping, and it is not optional. Until that ref appears, "no such branch" is
indistinguishable from "never started", "died at boot" and "refused entitlement" — so past the
boot budget the local instrument (cc-cloud) reads you as NOT-STARTED, and a session that reads as
NOT-STARTED gets retired and re-fired while it is still working. One empty commit in your first
minute is the whole of what makes your silence afterwards mean something. If git refuses it for
want of an identity, set one and retry rather than skipping it.

── HOW TO RETURN YOUR WORK ─────────────────────────────────────────────────────────────────────
That same branch is your only channel home: you cannot run this repo's /ship, and nothing here
reaches the operator's box. Commit onto it and push as often as you like — and at minimum once
more before you finish, even if the work is incomplete. A push anywhere else is invisible and
your work will strand; an unpushed cloud session leaves no trace of any kind. A local reconciler
(scripts/cloud-reconcile.sh) discovers the branch and hands it to the sanctioned local lander.
TRAILER
}
