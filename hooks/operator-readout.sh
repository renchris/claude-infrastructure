#!/usr/bin/env bash
# operator-readout.sh — Stop hook: the SILVER-PLATTER close renderer (operator crux 2026-07-20).
#
# THE DEFECT it closes: at turn close, operator-owned manual steps lived scattered across three
# stores (pending-activation/ · decisions/ · backlog --blocked) plus git state, surfaced only as
# model PROSE — a discipline, not a construction. A close could bury "run X" under paragraphs
# (the operator's literal complaint: steps must be silver-plattered — the exact single-line
# command, ambiguity eliminated), and a model could simply not mention them. This hook renders
# the close block BY CONSTRUCTION from disk truth — Pyramid-ordered: ONE governing state line
# (wrap-ledger rung + facts), then numbered `▶ <exact runnable command>` lines, capped, counted.
#
# ── DELIVERY ── pure-advisory {"systemMessage": …} — NEVER {decision:"block"}. This hook informs
#   the OPERATOR; it must never re-prompt the model (zero loop risk; composes with the model-facing
#   Stop arms: session-continue owns 🔧 auto-continue, completion-assert polices false-done,
#   boundary-handoff advises handoff). Bare-systemMessage-on-Stop is the proven channel
#   (session-continue.sh cap message precedent).
#
# ── FIRE PREDICATE ── steps>0 ∨ RUNG=📦 ∨ open-queue>0, where steps INCLUDES the `yours` class —
#   so a session that filed an operator step this turn renders its block even when every other
#   class is empty and the git state is otherwise ✅ (that is the whole point of `yours`: the
#   `👤` rung's line 1 says "N step(s) need you; see the OPERATOR block", and a block that did not
#   render would leave that pointing at nothing). Silent otherwise: 🔧 with no operator
#   step is the MODEL's job (auto-continue), ✅/read-only needs no block (protocol: suppress on
#   read-only). 📦 always renders — committed-but-unlanded is the invisible-risk state (parked
#   work is lost work if never surfaced). open-queue>0 (cwd project's OPEN cc-backlog items)
#   renders one counted line — operator crux 2026-07-25: a full auto-drain queue was invisible at
#   every close (only BLOCKED items rendered), reading as "sitting on todo items" in prose.
#
# ── DAMPING (boundary-handoff B-2 lesson: never quiet in the dangerous state) ── latch on
#   hash(rendered block): ANY change re-renders immediately; unchanged re-asserts only after TTL
#   (default 900s) — chatty interactive turns stay quiet, but a returning operator always finds
#   the block at the close they actually read.
#
# ── STEP SOURCES (disk truth, machine-wide; each independently fail-open) ──
#   yours        the steps THIS session filed (`cc-backlog needs "<step>" [--run …] [--session SID]`)
#                — blocked backlog items whose `.session` equals this hook's own SID. Rendered
#                FIRST and ALWAYS ITEMIZED. THE DEFECT it closes: a step the agent discovered this
#                turn ("authenticate motion-plus in /mcp") folded into the standing `◆ 180 blocked
#                backlog — your call` count and became indistinguishable from 180 items the
#                operator has been ignoring for weeks — so the `👤` rung's line 1 pointed at a
#                block that could not answer the question line 1 had just raised.
#                EXCLUSION IS STRUCTURAL: the split happens inside the ONE `cc-backlog list
#                --blocked --json` jq that already reads this stream, so an item carries exactly
#                one class and can never be both itemized here and counted in `backlog`.
#                Session UNRESOLVABLE (SID absent / "?") ⇒ `yours` is EMPTY — a missing session id
#                must never promote the standing pile.
#   deploy-lag   shared checkout ON trunk but behind its origin/main → the exact ff-sync command
#                (deploy-lag incident 2026-07-20: landed ≠ live; ordered FIRST — activations abort
#                on a stale checkout)
#   activation   pending-activation/*.sh with no .done marker → `bash <p> && touch <p>.done`
#                (CONFIRM=1-prefixed when the script gates on it — `&&` keeps a dry-run or failed
#                run from falsely marking done)
#   decisions    cc-decide store, open class-C (human-gated): run_command → staged_artifact_path
#                (`bash <p>`) → first-sentence prose fallback. Open class-B is NEVER itemized —
#                one summary line only when defaults auto-fire within 24h (the early-veto window).
#                `run_command` HAS NO PRODUCER, and is not waiting for one. It was written
#                forward-compatible with feat/board-runnable-commands, a branch that was never
#                pushed and never merged (2f25c802/a0d96fde are not ancestors of origin/main;
#                measured 2026-08-20). The LIVE runnable channel for a decision is
#                `staged_artifact_path` — 12 of 26 open packets carry it and render `▶ bash <p>`;
#                a class-C packet WITHOUT one is a value fork, which is exactly what `◆` means.
#                Do not re-file "nothing writes run_command" as a defect (backlog 0bcccfd6cd18
#                was closed as refuted on 2026-08-20): the capability arrived under a different
#                NAME on the backlog leg below, so a probe keyed on this spelling can only ever
#                convict — it cannot see its own fix land.
#   backlog      cc-backlog list --blocked --json → run/run_command if present, else needs-prose.
#                The producer is `cc-backlog needs --run` (bin/cc-backlog:2307), which rides the
#                step as `run` on the `block` record and folds at bin/cc-backlog:1058 — 60 of 160
#                blocked rows carry it today and render `▶ <cmd>`. Pinned by
#                tests/cc-backlog-needs.bats:140 (fold) + tests/operator-readout.bats:299 (render).
#   queue        cc-backlog OPEN items for the cwd project (git-toplevel basename, the same
#                normalization cc-dispatch applies) → one COUNTED line, never itemized (open items
#                are the dispatcher's work, not operator steps). Header when it is the only signal,
#                footer otherwise.
#   Line marks: `▶` = run this exact command · `◆` = judgment/decision (no single command exists) ·
#   `↳` = N more of this class, and this command lists them (the class-rollup, §4 M2).
#   `yours` reuses that SAME vocabulary rather than minting a glyph: `▶` when the item carries a
#   `.run`, `◆` when it does not. A new mark would have to be taught; these two already mean
#   exactly the right thing, and the operator's eye already reads them.
#   (`▸` is NOT available as a mark — it is the header's own glyph, `OPERATOR ▸`; caught by a test.)
#
# ── CLASS BUDGET (OPERATOR_SURFACE_V2 §4 M2) ── the render budget is allocated per CLASS, not
#   first-come, because a fixed window over a flat list STARVES WHOLE CLASSES. Measured 2026-07-29:
#   55 steps (1 deploy + 12 activation + 14 decision-C + 28 blocked-backlog) through MAX=6 put the
#   first class-C decision at position 14 and the first blocked-backlog item past 27 — 2 of 5 classes
#   unreachable at ANY queue depth, with `+49 more` as their only trace. Every active class now gets
#   a guaranteed itemized slot plus one counted `↳` rollup carrying its own listing command, so
#   truncation can shorten a class but never delete one. Bounded by construction at MAX + 4 lines.
#   Within the activation class, CONFIRM-gated (effect-bearing) scripts outrank print-only ones —
#   filename order had `18-fleet` (12 dark launchd labels) permanently below `04-page-channel`.
#   Kill switch: CC_OPREADOUT_CLASSBUDGET=off restores flat first-come + the `+N more` footer.
#   `yours` IS EXEMPT from this budget (and from the collapse below). Deliberate, and the one place
#   the volume rule yields: these are the steps from the work the operator JUST WATCHED HAPPEN, they
#   are few by construction (a session files 0-3), and they are the entire reason the `👤` rung
#   exists. Bounded anyway — above YMAX=5 the first 5 itemize and the rest become one `↳` rollup
#   carrying `cc-backlog list --blocked`, the same class-rollup pattern.
#
# ── COLLAPSE (DEFAULT since 2026-07-31 — operator directive) ── the class budget fixed STARVATION;
#   it did not fix VOLUME. Measured on the operator's own close: 204 steps → 9 numbered lines, of
#   which each activation line (`CONFIRM=1 bash <60-char path> && touch <same path>.done`) wrapped
#   to FOUR terminal rows — ~25 visual lines of grey with nothing single to paste. The close exists
#   to surface ONE decision point, so:
#     runnable (deploy + activation) → ONE `▶ cc-do` line, naming up to 3 stems then `+N`
#     judgment (decision, backlog)   → ONE `◆ <n> …` counted line each, naming up to 3 IDS then
#                                      `+N`, carrying that class's exact listing command
#   Live result: 10 lines → 5, none wrapping. Counting a class is NOT hiding it — every class stays
#   named, counted, and reachable by its own command (the I10 guarantee), the ids stay pasteable
#   (`cc-decide veto` resolves an EXACT id), and `cc-do --list` itemises everything, always.
#   A class holding exactly ONE item is still itemised: a count of 1 says strictly less than the
#   step itself and costs the same line.
#   `yours` IS NEVER COLLAPSED — see the class-budget note above. Its lines take the surrounding
#   mode's idiom (bare `▶`/`◆` under collapse, where nothing is numbered; numbered under the
#   itemised/legacy modes, where everything is) so the `^ [0-9]+ (▶|◆)` NSTEPS count downstream
#   stays consistent within each mode rather than agreeing with neither.
#   Modes: CC_OPREADOUT_CLASSBUDGET=collapse (default) · =on (per-class itemisation) · =off (legacy).
#   DEGRADATION: collapse is refused when cc-do does not resolve — a close naming a command the
#   machine lacks is worse than a long command that runs (I11).
#
# ── SAFETY (house pattern) ── every hook path exits 0; jq/read failure → abstain; B-3 one IDL
#   {fired|abstained:<reason>} line per invocation; kill-switch CC_OPREADOUT_DISABLE=1;
#   compose-guard abstains while session-continue's 🔧 loop is armed (lib/continue-sentinel SSOT).
#
# ── MODES ── (default, stdin JSON) hook mode · `--render [--cwd <d>] [--sid <id>]` prints the block
#   to stdout with no damping/state/IDL — /wrap's pull surface and the bats harness call this; ONE
#   renderer serves push + pull so the surfaces cannot drift. `--sid` is how the pull surface names
#   the session whose steps are `yours`; omitted ⇒ SID stays "?" ⇒ `yours` is empty, which is the
#   correct read for a caller that cannot name a session.
#
# Env seams (tests): CC_OPREADOUT_DISABLE · CC_OPREADOUT_MAX · CC_OPREADOUT_TTL_S ·
#   CC_OPREADOUT_NOW (epoch) · CC_OPREADOUT_STATE_DIR · CC_ACTIVATION_DIR · CC_DECISIONS_DIR ·
#   CC_BACKLOG_FILE · CC_BACKLOG_BIN · WRAP_LEDGER_BIN · WRAP_TRUNK (passes through) ·
#   CC_SHARED_CHECKOUT · CC_IDL · CC_CONTINUE_SENTINEL · CC_OPREADOUT_CLASSBUDGET · CC_DEPLOY_SCRIPT ·
#   CC_DO_BIN (unset ⇒ search · path/name ⇒ verbatim · `none` ⇒ absent, forces the I11 degradation)
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${CC_OPREADOUT_STATE_DIR:-$CFG/state/operator-readout}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
ACT_DIR="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
DEC_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
BLG_FILE="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"

# ── backlog-fold cache (scaling-bottlenecks-2026-08-09 §5 P0-3, item d1b453ddf16e) ────────────
# `cc-backlog list --json` folds the whole 2+ MB append-only JSONL through ~60 jq forks and was
# 92% of the measured 3.7 s p50 Stop-path lag — paid at EVERY turn end by EVERY session. The
# store is ONE append-only file, so (mtime,size) is an EXACT invalidator: every add/claim/done/
# needs appends and moves both, and the next read misses. No TTL, no staleness window — the key
# design the withdrawn wrap-ledger memo was re-scoped to (04-occupancy-b.md §6); it is sound
# here because ONE file carries the whole fold, unlike the ledger's multi-store fingerprint.
# Cache is box-shared by construction: the key embeds the store's identity, never the session's.
blg_list_cached() {  # $1 = cc-backlog binary · $2.. = `list` args; stdout = its output
  local bin="$1"; shift
  local dir="${CC_ORB_BLG_CACHE_DIR:-${TMPDIR:-/tmp}/cc-orb-blg-cache.$UID}"
  local key out tmp
  key="$(stat -f '%m-%z' "$BLG_FILE" 2>/dev/null || true)"
  if [ -z "$key" ]; then "$bin" list "$@" 2>/dev/null; return 0; fi   # unstattable store → live
  # (mtime,size) is exact for THIS store because it is append-only (only `compact` rewrites,
  # and compaction changes size); the path is in the key so distinct stores can never collide.
  key="$key-$BLG_FILE-$*"; key="${key//[^A-Za-z0-9._-]/_}"
  out="$dir/$key"
  if [ -s "$out" ]; then cat "$out" 2>/dev/null && return 0; fi
  mkdir -p "$dir" 2>/dev/null || { "$bin" list "$@" 2>/dev/null; return 0; }
  tmp="$(mktemp "$dir/.w.XXXXXX" 2>/dev/null)" || { "$bin" list "$@" 2>/dev/null; return 0; }
  "$bin" list "$@" 2>/dev/null > "$tmp" || true
  if [ -s "$tmp" ]; then
    mv -f "$tmp" "$out" 2>/dev/null || rm -f "$tmp"
    cat "$out" 2>/dev/null || true
  else
    rm -f "$tmp"                                    # tool produced nothing → cache nothing
  fi
  find "$dir" -type f -mmin +240 -delete 2>/dev/null || true   # bound the dir (miss path only)
}

SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
# ── escalation dead-letter stores (D3) — the standing `◆` count below. SEAMS, for the same reason
# DEPLOY_SCRIPT is one: unseamed, this leg would read the OPERATOR's live ~/.claude stores from
# inside the suite and the count would flip by machine (borrowed hermeticity). hooks/escalation-watch.sh
# is the session-facing renderer and owns the full class breakdown; this is one counted line.
ESC_ALARM_DIR="${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}"
ESC_ANNOUNCE_DIR="${CC_ANNOUNCE_ALARM_DIR:-$HOME/.claude/cc-announce-alarms}"
ESC_COMPLETION_DIR="${CC_COMPLETION_RECORDS_DIR:-$HOME/.claude/completion-push}"
ESC_PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
# The FIFTH store (SESSION_LIFECYCLE_V2 R-6): M3 close-path dead letters, written by handoff-fire's
# selfclose_mail_disposition on a TERMINAL close. Derived from the WRITER's own mailbox seam rather
# than given a seam of its own, so the two ends cannot drift — same rule the other four follow.
ESC_DEADLETTER_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/dead-letter"
ESC_SEEN_DIR="${CC_SWEEP_SEEN_DIR:-$HOME/.claude/autonomy/sweep-seen}"
# A SEAM, and specifically so the deploy platter's own existence check (I11) is testable in BOTH
# states. Without it the suite asserts the operator's live ~/.claude/scripts/ and the verdict flips
# by machine — borrowed hermeticity, and the flip case is exactly the one the check exists for.
DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"
MAX="${CC_OPREADOUT_MAX:-6}"          # the ITEMIZED-line budget (§4 M2); rollups ride on top
TTL="${CC_OPREADOUT_TTL_S:-900}"
NOW="${CC_OPREADOUT_NOW:-$(date +%s 2>/dev/null || echo 0)}"
SID="?"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# cc-do — the ONE-COMMAND driver the collapse render points at. RESOLVED, never assumed (I11 again):
# `bin/cc-*` deploys by glob in install.sh, so this hook can land BEFORE the driver reaches PATH, and
# a close that names a command which does not exist is worse than a long one that runs. Unresolvable
# ⇒ the collapse is REFUSED and the class-budget itemisation renders instead (see CBUDGET below).
# CC_DO_BIN: unset ⇒ search · a path/name ⇒ use verbatim · the literal `none` ⇒ ABSENT. The `none`
# value is the only way to exercise the degradation path from a test, because the search's first tier
# is $0's own checkout — which always holds bin/cc-do — so no amount of HOME/CFG tmpdir isolation can
# make it miss. A degradation path with no test is a degradation path that has never run.
CC_DO="${CC_DO_BIN:-}"
[ "$CC_DO" = none ] && CC_DO=""
if [ -z "$CC_DO" ] && [ "${CC_DO_BIN:-}" != none ]; then
  for _d in "$SCRIPT_DIR/../bin/cc-do" "$CFG/bin/cc-do" "$HOME/.claude/bin/cc-do"; do
    [ -x "$_d" ] && { CC_DO="cc-do"; break; }
  done
  [ -n "$CC_DO" ] || { command -v cc-do >/dev/null 2>&1 && CC_DO="cc-do"; }
fi

MODE="hook"; RCWD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --render) MODE="render" ;;
    --cwd)    shift; RCWD="${1:-}" ;;
    # the pull surface's way to name the session whose filed steps are `yours`. Hook mode overwrites
    # SID from stdin below; absent here, SID stays "?" and `yours` is empty (never the standing pile).
    --sid)    shift; SID="${1:-?}" ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) : ;;   # tolerate unknown args — a hook must never die on harness argv drift
  esac
  [ $# -gt 0 ] && shift
done

# B-3 writer = the SSOT lib hooks/lib/idl-log.sh (consolidation audit 02); see that file for the
# "jq-encode EVERY field" invariant. IDL_OFF carries this hook's extra rule: the `--render` pull
# surface (/wrap, bats, humans) must write NO telemetry — formerly `[ "$MODE" = hook ] || return 0`.
_ilib="$SCRIPT_DIR/lib/idl-log.sh"
# A BRAND-NEW hooks/lib file has no ~/.claude/hooks/lib symlink until install.sh runs — and when
# this hook executes from ~/.claude/hooks/, the CFG and $HOME tiers below resolve to that SAME
# missing path. So resolve $0's own symlink into the checkout first: the live hook IS a symlink to
# the repo, so this finds the lib on the same fast-forward that delivers this hook. Without it,
# landing would leave all five IDL hooks inert until someone remembered to re-run install.sh.
[ -f "$_ilib" ] || { _itgt="$0"; [ -L "$_itgt" ] && _itgt="$(readlink "$_itgt")"
  _ilib="$(cd "$(dirname "$_itgt")" 2>/dev/null && pwd)/lib/idl-log.sh"; }
[ -f "$_ilib" ] || _ilib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_ilib" ] || _ilib="$HOME/.claude/hooks/lib/idl-log.sh"
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ilib" 2>/dev/null; then
  # Fail LOUD but SAFE — a hook that cannot log its own disposition must not proceed silently, and
  # must never block the turn on a misconfig.
  printf 'operator-readout: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
  exit 0
fi
idl_init "$IDL" "operator-readout"
# This hook's extra rule: the `--render` pull surface (/wrap, bats, humans) writes NO telemetry.
[ "$MODE" = "hook" ] || idl_disable

# ── tiny helpers ─────────────────────────────────────────────────────────────────────────────────
tildify() { printf '%s' "${1/#$HOME/~}"; }   # display+paste-safe: the shell re-expands ~
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                 || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ''; }

# ── escalation dead-letter records that nothing has drained (D3) → ONE counted `◆` line ───────────
# UNSEEN is the sweep's own predicate, and it is NOT the one the design doc describes: the frozen
# interface calls the marker `<basename>.seen`, while scripts/autonomy-sweep.sh:89-91 actually keys
# on `sha256(FULL PATH) | cut -c1-32` with no suffix (live: 1191 markers, none suffixed). Honouring
# only the documented form would count every already-drained record, so BOTH are accepted — an extra
# recognised form can only lower the count, never inflate it.
# Hashing is BATCHED through ONE perl (Digest::SHA, core; the bin/cc-idl:38 idiom): per-record
# `shasum` forks measured 10 ms each, which at live volume is ~24 s inside a Stop hook. perl absent
# ⇒ the count is 0 and the line is simply absent — this leg is a supplement to escalation-watch.sh
# (the SessionStart guarantee), never the guarantee itself, so degrading quiet is correct here.
# NOTE: these stores are deliberately NOT in cheap_stamp() — same as the queue line, a change here
# is reported at the next render within the latch TTL, which is the staleness bound documented there.
escalation_unseen_count() {
  command -v perl >/dev/null 2>&1 || { printf 0; return 0; }
  local f n
  n="$( { for f in "$ESC_ALARM_DIR"/*.json;                 do [ -f "$f" ] && printf 'a\t%s\n' "$f"; done
          for f in "$ESC_ANNOUNCE_DIR"/announce-alarm-*.json;   do [ -f "$f" ] && printf 'a\t%s\n' "$f"; done
          for f in "$ESC_ANNOUNCE_DIR"/announce-degrade-*.json; do [ -f "$f" ] && printf 'a\t%s\n' "$f"; done
          for f in "$ESC_COMPLETION_DIR"/*.json;            do [ -f "$f" ] && printf 'c\t%s\n' "$f"; done
          for f in "$ESC_PAGES_DIR"/*.page;                 do [ -f "$f" ] && printf 'a\t%s\n' "$f"; done
          # `*.md` ONLY — the `.ran` existence evidence in this store is not a record (R4: an
          # empty store that HAS run must stay distinguishable from one that never has).
          # NO APOSTROPHE ABOVE, deliberately: this comment sits inside `$( )`, and bash 3.2 — the
          # only bash on this box — does not skip comments when scanning for the closing paren, so
          # a lone `'` there opens a quote that swallows to the next one and reds `bash -n` ~260
          # lines downstream. That is what failed this land 9 times; the retry was a copy, not a
          # chance (memory: control-must-replay-the-real-artifact / the A5 generator class).
          for f in "$ESC_DEADLETTER_DIR"/*.md;              do [ -f "$f" ] && printf 'a\t%s\n' "$f"; done
          return 0; } \
        | SEEN_DIR="$ESC_SEEN_DIR" perl -MDigest::SHA=sha256_hex -ne '
            chomp; my ($k, $p) = split /\t/, $_, 2;
            next unless defined $p && length $p;
            my $s = $ENV{SEEN_DIR};
            (my $b = $p) =~ s{.*/}{};
            next if -e "$s/" . substr(sha256_hex($p), 0, 32) || -e "$s/$b.seen";
            if ($k eq "c") {   # completion-push: only a NON-verified verdict is stuck
              open(my $fh, "<", $p) or next; local $/; my $body = <$fh>; close $fh;
              next if defined $body && $body =~ /"verdict"\s*:\s*"verified"/;
            }
            $n++;
            END { print $n + 0, "\n" }' 2>/dev/null || printf 0; )"
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# ── the ONE renderer: prints the block (or nothing) for cwd=$1. Sets RUNG + TOTAL + Q_N for the
#    caller — so hook mode must invoke it via redirection in THIS shell, never `$(…)` (subshell
#    loses them).
RUNG="?"; TOTAL=0; Q_N=0
# Write-turn oracle, three-state (0 wrote · 1 read-only · 2 cannot tell). Default 2 so the pull
# surface (`--render`, /wrap, bats), which has no transcript to read, never claims a write turn.
CERT_WROTE=2
render_block() {
  local cwd="$1"
  local steps_file; steps_file="$(mktemp "${TMPDIR:-/tmp}/opreadout.XXXXXX")" || return 0
  # steps_file: one step per line — class<TAB>mark<TAB>text; array-free (bash-3.2-safe).
  # class ∈ {deploy,activation,decision,backlog}, in that (irreversibility) order — see the CLASS
  # BUDGET block below, which is why the class is a FIELD and not just an ordering convention.
  # TABC once, not per-`read`: `IFS="$(printf '\t')" read` re-runs that substitution on EVERY
  # iteration, so hoisting it removes one fork per step rather than adding any (C19).
  local TABC; TABC="$(printf '\t')"
  # ONE switch for the WHOLE of M2 — allocation AND ordering. Bound here, before the first producer,
  # because F6's CONFIRM-first reorder happens at APPEND time: gating only the allocation left the
  # reorder live under `off`, so the switch did not restore the incumbent and A15 was unprovable.
  # Caught by A15 itself, which is the point of asserting byte-identity rather than "looks the same".
  # THREE modes now (operator directive 2026-07-31):
  #   collapse (DEFAULT) — runnable classes → ONE `cc-do` line · judgment classes → ONE counted line
  #                        each. The class budget below is right at 6 steps and unreadable at 204.
  #   on               — the per-class itemisation + rollups (§4 M2). Kill switch for collapse.
  #   off              — legacy flat first-come + `+N more` footer.
  local CBUDGET="${CC_OPREADOUT_CLASSBUDGET:-collapse}"
  # The collapse's whole output is a pointer to cc-do; without cc-do it would be a pointer to
  # nothing. Degrade to the itemisation that always runs, rather than to a lie.
  [ "$CBUDGET" = collapse ] && [ -z "$CC_DO" ] && CBUDGET=on

  # 1 · deploy-lag: shared checkout on trunk but behind its already-fetched origin/main.
  if [ -d "$SHARED" ] && git -C "$SHARED" rev-parse --git-dir >/dev/null 2>&1; then
    local sbr behind dscript
    sbr="$(git -C "$SHARED" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$sbr" = "main" ] || [ "$sbr" = "master" ]; then
      behind="$(git -C "$SHARED" rev-list --count "HEAD..origin/$sbr" 2>/dev/null || echo 0)"
      case "$behind" in ''|*[!0-9]*) behind=0 ;; esac
      # I11 — EXISTENCE-CHECK THE PLATTER. This line named ~/.claude/scripts/deploy-live.sh
      # unconditionally, and that path did not exist for the whole window in which
      # com.claude.deploy-live logged 59 `cannot execute: No such file or directory` failures; it is
      # valid today only because a symlink happened to land at 10:32 on 2026-07-29, four minutes
      # after the newest failure line. A recover command that cannot run is worse than no row: it
      # teaches the operator the board lies. Fall back to the repo copy, which is what the symlink
      # points AT, so the platter is correct in both states.
      dscript="$DEPLOY_SCRIPT"
      [ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"
      # green-stamp-gated deploy (never a raw pull — that ships whatever is on origin, verified or not)
      # Field 4 = the STEM: a short human name for this step, used by the collapse line so it can
      # say WHICH runnable steps cc-do covers without pasting three full command lines.
      #
      # ── AND RUNNABILITY-CHECKED, not merely existence-checked (DEPLOY_LANE_GROUND_UP §2.6 D5) ──
      # I11 above stops this line naming a path that does not exist. It did NOT stop it plattering a
      # command that exists and cannot succeed: for 534 consecutive refusals this row said `▶ bash
      # …/deploy-live.sh` about a lane that was structurally unable to advance. Both teach the same
      # lesson — the board lies. Ask the lane itself (`--offline`: its own T1/T2/T3 verdict, decided
      # against the already-fetched origin/main, so the probe neither hits the network nor can
      # manufacture the refusal it reports), and on a refusal downgrade the row to class `held`.
      # `held` draws no runnable slot and cc-do never executes it — the two surfaces agree because
      # they ask the same arbiter, not because they carry the same copy of its ladder.
      if [ "$behind" -gt 0 ]; then
        local dout drc
        dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
        if [ "$drc" -eq 0 ]; then
          printf 'deploy\t▶\tbash %s   [deploy: live layer %s behind origin/%s]\tdeploy-live\n' \
            "$(tildify "$dscript")" "$behind" "$sbr" >> "$steps_file"
        else
          local dwhy
          dwhy="$(printf '%s\n' "$dout" | tail -1 | tr -d '\t')"
          dwhy="${dwhy#deploy-live: }"; dwhy="${dwhy#REFUSED — }"
          [ "${#dwhy}" -gt 96 ] && dwhy="$(printf '%.93s...' "$dwhy")"
          printf 'held\t⊘\tdeploy HELD: live layer %s behind origin/%s — the lane refuses: %s\tdeploy-live\n' \
            "$behind" "$sbr" "${dwhy:-exit $drc}" >> "$steps_file"
        fi
      fi
    fi
  fi

  # 2 · activations: staged, un-run (no .done marker). CONFIRM-gated scripts get CONFIRM=1 so the
  #     emitted line is the REAL run; `&&` keeps a failed run from falsely touching .done.
  #
  #     ORDER IS A FINDING, not a style choice (§4 F6). The glob is filename order, so `18-fleet`
  #     (12 launchd labels dark) sorted BELOW `04-page-channel` and was always the one truncated
  #     away. CONFIRM-gating is the one signal already in hand at zero fork cost — the loop greps
  #     for it anyway — and it is exactly the right one: a CONFIRM-gated script does real work
  #     (cp + lint + bootstrap), a plain one prints instructions. Measured 2026-07-29: 9 of 12
  #     pending were CONFIRM-gated. Effect-bearing first.
  local f disp pre act_c="" act_p="" stem aline
  if [ -d "$ACT_DIR" ]; then
    for f in "$ACT_DIR"/*.sh; do
      [ -f "$f" ] || continue
      [ -f "$f.done" ] && continue
      disp="$(tildify "$f")"; pre=""
      stem="$(basename "$f" .sh)"
      grep -q 'CONFIRM' "$f" 2>/dev/null && pre="CONFIRM=1 "
      # THE WRAPPING CULPRIT (operator screenshot 2026-07-31): `CONFIRM=1 bash <path> && touch
      # <path>.done` names the same 60-char path TWICE and wrapped to four terminal lines per step —
      # nine of them made the close a grey wall. `cc-do <stem>` is the identical action (CONFIRM=1,
      # run, touch .done only on exit 0) in one short line. Emitted only when cc-do RESOLVES; the
      # long form still renders on a machine that lacks it, because it is the form that works there.
      if [ -n "$CC_DO" ]; then aline="cc-do ${stem}   [activation]"
      else                     aline="${pre}bash ${disp} && touch ${disp}.done   [activation]"; fi
      if [ "$CBUDGET" = off ]; then       # legacy: glob order, one stream
        act_c="${act_c}activation${TABC}▶${TABC}${aline}${TABC}${stem}"$'\n'
      elif [ -n "$pre" ]; then
        act_c="${act_c}activation${TABC}▶${TABC}${aline}${TABC}${stem}"$'\n'
      else
        act_p="${act_p}activation${TABC}▶${TABC}${aline}${TABC}${stem}"$'\n'
      fi
    done
    [ -n "$act_c$act_p" ] && printf '%s' "$act_c$act_p" >> "$steps_file"
  fi

  # 3 · open class-C decisions (human-gated), oldest first. Prefer an exact command; degrade
  #     honestly to the packet's first sentence (◆ = judgment, no single command exists).
  if [ -d "$DEC_DIR" ]; then
    for f in "$DEC_DIR"/*.json; do
      [ -e "$f" ] || continue
      # NB: jq -r renders \t in string literals as REAL tabs — line shape: created<TAB>mark<TAB>text;
      # sort on the created prefix (FIFO), then cut the prefix off. Never @tsv (it \t-escapes fields).
      # A packet that can NEVER auto-resolve is human-gated no matter what its class FIELD says.
      # `cc-decide open` refuses class-B without BOTH a default and a deadline, so a B carrying
      # neither could not have come through the front door — it is a hard block wearing the wrong
      # label, and the six legacy `shipland-esc-*` packets are exactly that. Admitting them here is
      # what puts a parked land-block on the operator's board; matching on the class FIELD alone
      # left them visible to `cc-decide list --open` yet absent from the numbered steps, which is
      # the surface the operator actually reads. Class A is deliberately NOT folded: it also lacks
      # a default/deadline, but it is a post-hoc audit trail with nothing for the operator to do.
      jq -r '
        select((.status // "" | if . == "" then "open" else . end) == "open"
               and ((.class // "") == "C"
                    or ((.class // "") == "B"
                        and (.default_if_no_veto // "") == ""
                        and (.veto_deadline // "") == "")))
        # ROUND-TRIP: `cc-decide veto|action` resolves an EXACT id ("$DECISIONS_DIR/$id.json"), with
        # no prefix matching — so the old 8-char slice printed something the operator could not paste
        # back for ANY packet (a 12-hex id truncated to 8 is "unknown id"), and collapsed every
        # `shipland-esc-*` packet to the same unusable label "shipland". Render the id whole; the
        # cap only stops a pathological id from blowing the line. This matches the backlog leg
        # below, which already prints its ids in full.
        | (.id // "?" | if length > 24 then .[0:24] else . end) as $id8
        | (.what_plain // "" | gsub("[\n\t]"; " ") | split(". ")[0]) as $s
        | ($s | if length > 110 then .[0:110] + "…" else . end) as $sent
        | (.run_command // "" | gsub("[\n\t]"; " ")) as $run
        | (.staged_artifact_path // "" | gsub("[\n\t]"; " ")) as $staged
        # the packet is EVIDENCE — label the row with the class it actually carries, never the class
        # this leg folded it in as, so the id still reconciles with `cc-decide list --all`
        | (.class // "?") as $cls
        # Field 4 = the id, so the COLLAPSE line can name the packets it counts. `cc-decide veto`
        # resolves an EXACT id, so a counted line that dropped the ids would leave the operator
        # nothing to paste — the same round-trip defect the 8-char slice caused.
        | (if $run != ""      then "decision\t▶\t\($run)   [decision \($cls) \($id8): \($sent | .[0:60])]\t\($id8)"
           elif $staged != "" then "decision\t▶\tbash \($staged)   [decision \($cls) \($id8): \($sent | .[0:60])]\t\($id8)"
           else "decision\t◆\t[decision \($cls) \($id8)] \($sent)\t\($id8)" end) as $line
        | "\(.created // "?")\t\($line)"' "$f" 2>/dev/null
    done | sort | cut -f2- >> "$steps_file"
  fi

  # 4 · blocked backlog → TWO classes off ONE read: `yours` (filed by THIS session) and `backlog`
  #     (the standing pile). Operator-only `needs` steps, with the run command when the item
  #     carries one.
  #
  #     THE EXCLUSION IS STRUCTURAL, NOT ARITHMETIC. `cc-backlog needs` files a step the agent
  #     discovered this session and stamps `.session`; those items fold into the SAME
  #     `list --blocked --json` stream as the 180-item standing pile. The obvious implementation —
  #     itemize the session's items, then subtract their count from the backlog count — is the
  #     documented way to fail this: two independent computations that must agree forever. Instead
  #     the class is decided ONCE, inside the jq that already reads this stream, so an item carries
  #     exactly one class label and the per-class counters below cannot double-count it. No second
  #     subprocess either (C19: no new fork may enter render_block).
  local blg="${CC_BACKLOG_BIN:-}"
  if [ -z "$blg" ]; then
    for f in "$SCRIPT_DIR/../bin/cc-backlog" "$CFG/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog"; do
      [ -x "$f" ] && { blg="$f"; break; }
    done
  fi
  if [ -n "$blg" ] && [ -f "$BLG_FILE" ]; then
    blg_list_cached "$blg" --blocked --json | jq -r --arg sid "$SID" '
      .[]?
      | (.title // "" | gsub("[\n\t]"; " ") | .[0:60]) as $t
      | (.needs // "" | gsub("[\n\t]"; " ") | .[0:90]) as $n
      | (.run // .run_command // "" | gsub("[\n\t]"; " ")) as $run
      | (.id // "?") as $id
      # `?` is this hook`s own unresolvable-session sentinel, and "" is a caller that passed none;
      # neither may ever match an item, or a session-less close would promote the whole standing
      # pile into `yours`.
      | (if $sid != "" and $sid != "?" and (.session // "") == $sid then "yours" else "backlog" end) as $c
      | (if $c == "yours" then "this session" else "backlog" end) as $w
      | if $run != "" then "\($c)\t▶\t\($run)   [\($w) \($id): \($t)]\t\($id)"
        else "\($c)\t◆\t[\($w) \($id)] \($t) — needs: \($n)\t\($id)" end' 2>/dev/null >> "$steps_file"
  fi

  # 5 · open-queue visibility (operator crux 2026-07-25: "we are just sitting here on todo items…
  #     not clearly surfaced"). OPEN (auto-drainable) items rendered NOWHERE — only blocked ones
  #     did — so a full queue was invisible at every close. One COUNTED line, scoped to the cwd
  #     project (git-toplevel basename — cc-dispatch's own normalization), never itemized: open
  #     items are the dispatcher's work, not operator steps. status=="open" exactly — claimed is
  #     in flight, blocked is itemized above.
  local q_proj="" q_line=""
  Q_N=0
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    q_proj="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$q_proj" ] || q_proj="$cwd"
    q_proj="$(basename "$q_proj")"
  fi
  if [ -n "$q_proj" ] && [ -n "$blg" ] && [ -f "$BLG_FILE" ]; then
    Q_N="$(blg_list_cached "$blg" --open --json \
      | jq --arg p "$q_proj" '[ .[]? | select(.status=="open" and .project==$p) ] | length' \
          2>/dev/null || echo 0)"
    case "$Q_N" in ''|*[!0-9]*) Q_N=0 ;; esac
    # NO listing command here: open items are the DISPATCHER's work, not operator steps, and this
    # token was the longest on the footer — the one that wrapped it to a second row. `board:
    # cc-blockers` (appended below) already reaches them.
    [ "$Q_N" -gt 0 ] && q_line="queue: ${Q_N} open (${q_proj}) — cc-dispatch auto-drains"
  fi

  # 6 · escalation dead-letter records nothing has drained (D3). ONE counted line, never itemized —
  #     the per-class breakdown is hooks/escalation-watch.sh's job at SessionStart; this is the
  #     standing reminder on the close surface for a session that has been open a long time.
  local esc_n; esc_n="$(escalation_unseen_count)"

  # ── state line from the un-fakeable ledger (cwd repo; skipped cleanly outside a repo) ──
  local state="" wrap="" led="" branch ahead shas dirty_n gate remainder parts custody
  RUNG="?"
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    wrap="${WRAP_LEDGER_BIN:-}"
    if [ -z "$wrap" ]; then
      for f in "$SCRIPT_DIR/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
        [ -f "$f" ] && { wrap="$f"; break; }
      done
    fi
    [ -n "$wrap" ] && led="$( cd "$cwd" 2>/dev/null && bash "$wrap" --machine 2>/dev/null || true )"
  fi
  if [ -n "$led" ]; then
    lf() { printf '%s' "$led" | grep -E "^$1=" | head -1 | cut -d= -f2-; }
    RUNG="$(lf RUNG)"; [ -n "$RUNG" ] || RUNG="?"
    branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    case "$RUNG" in
      "📦")
        ahead="$(lf AHEAD)"; shas="$(lf SHAS)"
        state="📦 parked — ${ahead} commit(s) on ${branch} unlanded (${shas:-?}) → /ship" ;;
      "🚀")
        # Face 4 of the inertness generator: landed on trunk, but the LIVE LAYER — the store
        # behaviour actually reads — is behind PAST its converge budget, or a migration carrying a
        # conclusion into settings.json / a plist / PATH has FAILED. Either way the work is landed
        # and the machine is still running the old bytes.
        #
        # It gets its own arm rather than riding the default for the reason MEMORY.md
        # new-enum-member-falls-into-fail-closed-default names: an unhandled rung leaves `state`
        # EMPTY, so the block would render a header with no state — the ledger would have computed
        # the one fact the operator needs and the renderer would have silently dropped it.
        # THREE causes, not two (2026-08-09). An added file breaches at lag 1 with the lag still
        # INSIDE the budget, so the budget wording would attach a false reason to a true rung — and
        # it is the reason that tells the operator what broke: absent, not old.
        lag="$(lf LIVE_LAG)"; migf="$(lf MIG_FAILED)"; adds="$(lf LIVE_ADDS)"
        # NOT `case "${adds:-0}"` — that defaults the EXPANSION and leaves the variable empty, so a
        # ledger with no LIVE_ADDS line fell through to `[ "" != "0" ]`, which is TRUE, and rendered
        # "— NEW file(s) absent" with a blank count over a lag the operator never got told about.
        # Caught by the no-LIVE_ADDS case below; normalise the VARIABLE, then test it.
        case "$adds" in ''|*[!0-9]*) adds=0 ;; esac
        if [ "${migf:-0}" != "0" ]; then
          state="🚀 landed, NOT live — ${migf} migration(s) FAILED; the enforcing store never took this → bash scripts/deploy-migrations.sh --status"
        elif [ "$adds" != "0" ]; then
          state="🚀 landed, NOT live — ${adds} NEW file(s) absent from the live layer; every consumer guard on them silently skips → bash scripts/deploy-live.sh"
        else
          state="🚀 landed, NOT live — the live layer is ${lag:-?} commit(s) behind and PAST its converge budget → bash scripts/deploy-live.sh"
        fi ;;
      "🔧")
        dirty_n="$(lf DIRTY_N)"; gate="$(lf GATE)"; remainder="$(lf REMAINDER)"
        # W2 CUSTODY (custody v1.1, item d29b73103189) — the one 🔧 cause that is INVISIBLE in this
        # cwd's git state. wrap-ledger ranks open custody ahead of every remaining arm and
        # short-circuits the chain, so a custody-driven 🔧 arrives here with DIRTY_N=0, GATE fresh
        # and REMAINDER=0 — every `parts` term empty — and rendered "🔧 in progress — loose ends":
        # the ledger computed the only fact the operator needed and the renderer dropped it. Same
        # shape as the 🚀 arm's own note above (MEMORY.md new-enum-member-falls-into-fail-closed-
        # default), except the fallback here is a true-but-contentless string rather than an empty
        # one, which is why it survived: nothing looked broken.
        #
        # It leads `parts` because it is the only term naming work that is not in this tree — the
        # operator's next move (await it armed / collect it / abandon it) differs in kind from
        # "commit what is dirty" — and it is the only one carrying a drivable listing command.
        #
        # This does NOT touch the FIRE PREDICATE, deliberately: a block that fired on every
        # in-flight wave is exactly the always-alarm CLOSE_INTEGRITY's "no new rung for custody"
        # decision rejected (await-with-armed-watcher is a LEGITIMATE end-of-turn). The custody
        # cause is rendered when the block renders on its own terms, never as a new reason to fire.
        custody="$(lf CUSTODY_OPEN)"; case "$custody" in ''|*[!0-9]*) custody=0 ;; esac
        parts=""
        [ "$custody" != "0" ] && parts="${custody} dispatched session(s) NOT returned"
        [ "${dirty_n:-0}" != "0" ] && parts="${parts:+$parts · }${dirty_n} file(s) uncommitted"
        [ "$gate" = "stale" ] && parts="${parts:+$parts · }gate stale on HEAD"
        [ "${remainder:-0}" != "0" ] && parts="${parts:+$parts · }${remainder} DoD item(s) open"
        state="🔧 in progress — ${parts:-loose ends}"
        [ "$custody" != "0" ] && state="${state} → cc-custody list --open --cwd ." ;;
      "✅")
        # WRITE TURN + ✅ ⇒ say SAFE TO CLOSE, in those words. "✅ live on trunk" is a fact about
        # the repo; the operator's standing question is a fact about THEM — "is there anything left
        # that needs me?" — and they had to ask it every single close because no line answered it.
        # CERT_WROTE is the three-state write-turn oracle (0 wrote · 1 read-only · 2 cannot tell);
        # only an affirmative 0 earns the stronger claim, so a `--render` pull (no transcript) and
        # an unreadable one both keep the original wording rather than over-claiming.
        if [ "${CERT_WROTE:-2}" = "0" ]; then state="✅ SAFE TO CLOSE — nothing of mine is open"
        else state="✅ live on trunk"; fi ;;
    esac
  fi

  # ── class-B early-veto summary (≤24h auto-fire window only; never itemized) ──
  local b_n=0 b_earliest="" horizon b_line=""
  horizon="$(epoch_to_iso $(( NOW + 86400 )))"
  if [ -d "$DEC_DIR" ] && [ -n "$horizon" ]; then
    b_earliest="$(
      for f in "$DEC_DIR"/*.json; do
        [ -e "$f" ] || continue
        jq -r --arg h "$horizon" '
          select((.status // "")=="open" and (.class // "")=="B"
                 and (.veto_deadline // "") != "" and .veto_deadline <= $h)
          | .veto_deadline' "$f" 2>/dev/null
      done | sort | head -1)"
    if [ -n "$b_earliest" ]; then
      b_n="$(
        for f in "$DEC_DIR"/*.json; do
          [ -e "$f" ] || continue
          jq -r --arg h "$horizon" '
            select((.status // "")=="open" and (.class // "")=="B"
                   and (.veto_deadline // "") != "" and .veto_deadline <= $h) | .id' "$f" 2>/dev/null
        done | grep -c .)"
      b_line="${b_n} class-B default(s) auto-fire ≤24h (earliest ${b_earliest}) — veto: cc-decide veto <id>"
    fi
  fi

  # ── CLASS BUDGET (§4 M2 — the row's headline mechanism) ────────────────────────────────────────
  # THE DEFECT: a fixed window over a flat, source-ordered list STARVES WHOLE CLASSES. Measured
  # 2026-07-29 on this host: 55 steps = 1 deploy + 12 activation + 14 decision-C + 28 blocked-backlog,
  # rendered through MAX=6, so a class-C decision first appeared at position 14 and a blocked backlog
  # item past 27 — i.e. **2 of 5 classes were unreachable at any queue depth**, and the queue only
  # grows. The two starved classes are precisely the ones that need a human (a genuine judgment call,
  # a blocked work item); the `+49 more` footer promised "more of what you just saw" and was the only
  # trace of them.
  #
  # THE INVERSION: an alarm that ALWAYS fires 55 times and an alarm that CANNOT fire carry the same
  # zero bits. Absence-is-loud has no term for the cost of loudness, so the budget is allocated per
  # CLASS rather than first-come: every active class gets a guaranteed itemized slot, and whatever it
  # cannot itemize becomes ONE counted rollup line carrying that class's own exact listing command.
  # Truncation can then shorten a class but can never DELETE one (I10).
  #
  # The output is bounded BY CONSTRUCTION, not by a magic number: <= MAX itemized + one rollup per
  # class = MAX + 4 lines worst case. MAX's meaning narrows from "total lines" to "itemized lines".
  # Kill switch: CC_OPREADOUT_CLASSBUDGET=off restores flat first-come + the `+N more` footer exactly.
  local total=0 cls mark text stem
  local c_deploy=0 c_activation=0 c_decision=0 c_backlog=0 c_yours=0 c_held=0
  # PASS 1 — count per class. Fork-free: a `< file` redirect is not a fork, and this REPLACES the
  # `grep -c .` that used to compute the total, so the class budget costs one fork LESS than the
  # flat renderer it supersedes (C19: no new fork may enter render_block).
  while IFS="$TABC" read -r cls mark text stem; do
    [ -n "$mark" ] || continue
    total=$((total + 1))
    case "$cls" in
      deploy)     c_deploy=$((c_deploy + 1)) ;;
      activation) c_activation=$((c_activation + 1)) ;;
      decision)   c_decision=$((c_decision + 1)) ;;
      backlog)    c_backlog=$((c_backlog + 1)) ;;
      # `yours` counts toward the TOTAL (so it can fire the block on its own) but into its own
      # counter — which is precisely what keeps it out of c_backlog and out of the allocation below.
      yours)      c_yours=$((c_yours + 1)) ;;
      # `held` follows `yours`'s shape for the same reason and one more: it is a runnable class the
      # ACTUATOR has refused, so counting it into c_deploy would let a command the lane rejects draw
      # a slot in the collapse line and be named as runnable — the exact defect §2.6 D5 closes.
      held)       c_held=$((c_held + 1)) ;;
    esac
  done < "$steps_file"
  TOTAL="$total"
  # 🚀 joins 📦 in the fire predicate. Both are "the value is not where it needs to be" states with a
  # runnable next step. A 🚀 that did not fire the block would be the whole face-4 measurement
  # computed and then not shown to anyone.
  # WHAT BOUNDS IT (restated 2026-08-09, because the old wording — "bounded BY CONSTRUCTION; it
  # cannot fire inside the converge budget" — stopped being true and would have quietly guarded a
  # false premise): the ADDED-FILE cause fires at lag 1, well inside the budget, because an added
  # file is ABSENT from the live layer rather than stale and no budget makes an absent file present.
  # The bound is now behavioural, not structural: 28.5% of trunk commits add a file, the state ends
  # the moment the live layer carries them, and CLAUDE.md has the AGENT run the converger and
  # re-read — so on a healthy box it self-clears within one close. It stands only while a converger
  # outage does, which is precisely the news this block exists to carry.
  if [ "$total" -eq 0 ] && [ "$RUNG" != "📦" ] && [ "$RUNG" != "🚀" ] && [ "$Q_N" -eq 0 ]; then rm -f "$steps_file"; return 0; fi

  # ALLOCATION. Written out per class rather than looped: four classes is a fixed set, and the
  # alternatives (eval, or a `$(fn)` lookup) cost either clarity or a fork per step.
  # `yours` is ABSENT from every line of this block on purpose — it draws no slot and therefore
  # cannot starve a standing class, and no standing class can starve it.
  local budget="$MAX" before legacy=0
  local a_deploy=0 a_activation=0 a_decision=0 a_backlog=0
  if [ "$CBUDGET" = off ]; then
    legacy=1; a_deploy="$MAX"; a_activation="$MAX"; a_decision="$MAX"; a_backlog="$MAX"
  else
    # floor: one guaranteed itemized slot per ACTIVE class, in irreversibility order
    [ "$c_deploy"     -gt 0 ] && [ "$budget" -gt 0 ] && { a_deploy=1;     budget=$((budget - 1)); }
    [ "$c_activation" -gt 0 ] && [ "$budget" -gt 0 ] && { a_activation=1; budget=$((budget - 1)); }
    [ "$c_decision"   -gt 0 ] && [ "$budget" -gt 0 ] && { a_decision=1;   budget=$((budget - 1)); }
    [ "$c_backlog"    -gt 0 ] && [ "$budget" -gt 0 ] && { a_backlog=1;    budget=$((budget - 1)); }
    # top-up: ROUND-ROBIN, one slot per class per pass, until the budget is spent or no class can
    # use another. Round-robin rather than a per-class ceiling constant, because a ceiling leaves the
    # budget UNSPENT: at a ceiling of 2 with two active classes, MAX=6 rendered only 4 lines and two
    # slots the operator had room for went to nobody. Fairness comes from the pass structure, not
    # from a second magic number. Terminates on the no-slot-taken guard.
    while [ "$budget" -gt 0 ]; do
      before="$budget"
      [ "$a_deploy"     -lt "$c_deploy" ]     && [ "$budget" -gt 0 ] && { a_deploy=$((a_deploy + 1));         budget=$((budget - 1)); }
      [ "$a_activation" -lt "$c_activation" ] && [ "$budget" -gt 0 ] && { a_activation=$((a_activation + 1)); budget=$((budget - 1)); }
      [ "$a_decision"   -lt "$c_decision" ]   && [ "$budget" -gt 0 ] && { a_decision=$((a_decision + 1));     budget=$((budget - 1)); }
      [ "$a_backlog"    -lt "$c_backlog" ]    && [ "$budget" -gt 0 ] && { a_backlog=$((a_backlog + 1));       budget=$((budget - 1)); }
      [ "$before" = "$budget" ] && break
    done
  fi

  # ── compose (Pyramid: governing line → numbered steps → counted footer) ──
  local hdr shown=0 over
  # THE GOVERNING LINE MUST CARRY AN IDEA, NOT A CATEGORY (Minto, Ch 7 p. 94 — "no intellectually
  # blank assertions": *"There are three problems" tells the kind, not the idea*; Ch 4 p. 42 "ideas,
  # not categories"). `205 manual step(s)` is exactly that blank assertion — it names the pile and
  # says nothing about it, on the one line the operator's eye is guaranteed to read. The honest
  # summary of the level below is the PARTITION: what one command clears vs what needs a human.
  # Collapse only — the itemised/legacy modes keep the historic header their tests pin.
  #
  # `yours` LEADS the partition when it is non-empty, because it is the leg that answers the
  # question the `👤` rung raises: of everything on this board, THESE came out of the work you just
  # watched. It is a real partition — c_yours, the runnable legs and the judgment legs are disjoint
  # and sum to `total` — so the line still summarises exactly the groupings printed below it.
  local _y=""
  [ "$c_yours" -gt 0 ] && _y="${c_yours} step(s) are yours"
  if [ "$total" -gt 0 ] && [ "$CBUDGET" = collapse ]; then
    local _run=$(( c_deploy + c_activation )) _jud=$(( c_decision + c_backlog )) _lead=""
    [ "$_run" -gt 0 ] && _lead="${_run} runnable now"
    [ "$_jud" -gt 0 ] && _lead="${_lead:+$_lead, }${_jud} need your call"
    # `held` is its own leg or the partition stops summing to `total` — and, with a held row as the
    # ONLY item, without this clause the fallback below would call it a "manual step", which is the
    # one thing it is not. It is nobody's action: the lane refused, and the lane will retry.
    [ "$c_held" -gt 0 ] && _lead="${_lead:+$_lead, }${c_held} held"
    # `yours`-only ⇒ the fallback must NOT fire: "2 step(s) are yours · 2 manual step(s)" restates
    # the same two items as if they were four.
    if [ -n "$_y" ]; then _lead="${_y}${_lead:+ · $_lead}"; else _lead="${_lead:-${total} manual step(s)}"; fi
    hdr="OPERATOR ▸ ${_lead}${state:+ · $state}"
    # ANSWER FIRST when the answer is "yes, close" (Minto: line 1 carries the idea, not the pile).
    # This machine standingly holds ~200 judgment items, so the default ordering renders
    # "11 runnable now, 211 need your call · ✅ SAFE TO CLOSE" — leading with a number that is NOT
    # this session's and burying the one clause the operator opened the close to find. CLAUDE.md is
    # explicit that the standing pile is not a close-gate (the 👤 rung counts only steps THIS
    # SESSION filed; the pile has its own counted ◆ line), so it is demoted here and labelled for
    # what it is. Only the certified case reorders — every other rung keeps the existing shape.
    if [ "$RUNG" = "✅" ] && [ "${CERT_WROTE:-2}" = "0" ]; then
      hdr="OPERATOR ▸ ${state} · ${_lead} (standing, not blocking this close)"
    fi
  elif [ "$total" -gt 0 ]; then hdr="OPERATOR ▸ ${_y:+$_y · }${total} manual step(s)${state:+ · $state}"
  elif [ "$RUNG" = "📦" ] || [ "$RUNG" = "🚀" ]; then hdr="OPERATOR ▸ ${state}"
  else hdr="OPERATOR ▸ ${q_line}"; fi   # queue-only render: the queue IS the governing line
  printf '%s\n' "$hdr"

  # ── YOURS — first, itemized, never collapsed, exempt from MAX ────────────────────────────────
  # Rendered BEFORE every standing class: the operator reads top-down, and these are the only rows
  # on the board whose provenance is this turn. Volume is safe by construction (a session files
  # 0-3), and above YMAX the tail becomes the standard `↳` rollup carrying its own listing command,
  # so the completeness guarantee (I10) holds here exactly as it does for every other class.
  # Numbering follows the surrounding MODE, not this class: bare under collapse (where nothing is
  # numbered), numbered under itemised/legacy (where everything is) — so `NSTEPS`
  # (`grep -cE '^ [0-9]+ (▶|◆)'`) keeps counting whatever that mode counts.
  local YMAX=5 y_shown=0 y_lines=0 y_num=""
  [ "$CBUDGET" = collapse ] || y_num=1
  if [ "$c_yours" -gt 0 ]; then
    while IFS="$TABC" read -r cls mark text stem; do
      [ "$cls" = yours ] || continue
      [ "$y_shown" -lt "$YMAX" ] || continue
      y_shown=$((y_shown + 1)); y_lines=$((y_lines + 1))
      if [ -n "$y_num" ]; then printf ' %d %s %s\n' "$y_lines" "$mark" "$text"
      else                     printf ' %s %s\n'    "$mark" "$text"; fi
    done < "$steps_file"
    if [ "$c_yours" -gt "$y_shown" ]; then
      y_lines=$((y_lines + 1))
      if [ -n "$y_num" ]; then printf ' %d ↳ cc-backlog list --blocked   [+%s more yours]\n' "$y_lines" "$(( c_yours - y_shown ))"
      else                     printf ' ↳ cc-backlog list --blocked   [+%s more yours]\n'    "$(( c_yours - y_shown ))"; fi
    fi
    shown="$y_shown"
  fi

  # ── ⊘ HELD — rendered in BOTH modes, because it lives above the collapse/itemise fork ────────────
  # A runnable step whose own actuator says it would refuse right now. Never numbered into anything
  # pasteable and never collapsed into `▶ cc-do`'s runnable count: the operator must not read it as
  # a step they can take. It is still SHOWN, because the state it reports (a stale live layer) is
  # real, and a row that silently disappears on refusal is how 534 refusals passed for normal.
  if [ "$c_held" -gt 0 ]; then
    while IFS="$TABC" read -r cls mark text stem; do
      [ "$cls" = held ] || continue
      printf ' %s %s\n' "$mark" "$text"
    done < "$steps_file"
  fi

  # ── COLLAPSE (default) ───────────────────────────────────────────────────────────────────────
  # The class budget below solved starvation; it did not solve VOLUME. Measured on the operator's
  # own close 2026-07-31: 204 steps rendered 9 numbered lines, of which the activation lines wrapped
  # to four terminal lines each — ~25 visual lines of grey with no single thing to paste. Counting a
  # class is not hiding it: every class stays NAMED, COUNTED, and reachable by its own command, which
  # is exactly the I10 guarantee, while the operator gets ONE verb.
  #   runnable (deploy + activation) → one `▶ cc-do` line naming up to 3 stems
  #   judgment (decision, backlog)   → one `◆ <n> …` counted line each, carrying its listing command
  # A class holding exactly ONE item is still itemised: one specific line costs nothing and says
  # strictly more than "1 decision". `cc-do --list` itemises everything, always.
  if [ "$CBUDGET" = collapse ]; then
    local runnable=$(( c_deploy + c_activation )) stems="" sc=0 cn=0 c2 rcmd clabel
    if [ "$runnable" -eq 1 ]; then
      while IFS="$TABC" read -r cls mark text stem; do
        case "$cls" in deploy|activation) printf ' %s %s\n' "$mark" "$text" ;; esac
      done < "$steps_file"
    elif [ "$runnable" -gt 1 ]; then
      while IFS="$TABC" read -r cls mark text stem; do
        case "$cls" in
          deploy|activation)
            sc=$((sc + 1))
            [ "$sc" -le 3 ] && [ -n "$stem" ] && stems="${stems:+$stems · }${stem}" ;;
        esac
      done < "$steps_file"
      # NAME THEM ONLY WHEN THE NAMING IS COMPLETE. Three of 174 is noise, not information, and it
      # was what pushed these lines past 130 chars — i.e. back into the wrapping this change exists
      # to kill. At <=3 the list IS the full set (round-trippable, nothing to look up); above that
      # the listing command is the honest pointer and cc-do itself enumerates.
      if [ "$runnable" -le 3 ]; then printf ' ▶ %s   [%s runnable: %s]\n' "$CC_DO" "$runnable" "$stems"
      else                           printf ' ▶ %s   [%s runnable]\n'     "$CC_DO" "$runnable"; fi
    fi
    for cls in decision backlog; do
      case "$cls" in
        decision) cn="$c_decision"; rcmd='cc-decide list --open';     clabel="decisions" ;;
        backlog)  cn="$c_backlog";  rcmd='cc-backlog list --blocked'; clabel="blocked backlog" ;;
      esac
      [ "$cn" -gt 0 ] || continue
      if [ "$cn" -eq 1 ]; then
        while IFS="$TABC" read -r c2 mark text stem; do
          [ "$c2" = "$cls" ] && printf ' %s %s\n' "$mark" "$text"
        done < "$steps_file"
      else
        # Name the ids it counts, up to 3. `cc-decide veto` / `cc-backlog` resolve an EXACT id, so a
        # bare count would leave nothing to paste — the round-trip defect the 8-char slice caused,
        # re-introduced by collapsing. Beyond 3 the listing command is the honest pointer.
        if [ "$cn" -le 3 ]; then
          stems=""
          while IFS="$TABC" read -r c2 mark text stem; do
            [ "$c2" = "$cls" ] || continue
            [ -n "$stem" ] && stems="${stems:+$stems · }${stem}"
          done < "$steps_file"
          printf ' ◆ %s %s — your call: %s   %s\n' "$cn" "$clabel" "$stems" "$rcmd"
        else
          printf ' ◆ %s %s — your call   %s\n' "$cn" "$clabel" "$rcmd"
        fi
      fi
    done
    rm -f "$steps_file"
    shown="$total"
  else

  # `n` continues the numbering the `yours` block already used, so the operator reads ONE sequence.
  local n="$y_lines" alloc pc=0 last_cls="" rest rcmd rtot
  # close_class — the COMPLETENESS guarantee. Emits at most one `▸` rollup for whatever the class
  # could not itemize, carrying the exact command that LISTS the rest. `▸` is deliberately a third
  # mark: `▶` = run this exact step · `◆` = judgment, no single command exists · `▸` = N more of
  # this class, and this command shows them. Every command here was RUN before being plattered (I5).
  # Dynamic scoping is load-bearing and safe: the `while … done < file` loop is not a subshell, so
  # `n` increments survive.
  close_class() {
    [ "$legacy" = 1 ] && return 0
    # shellcheck disable=SC2016  # $f is EMITTED, not evaluated: the loop variable must expand in the
    # OPERATOR's shell when they paste the line, which is the whole point of a platter.
    case "$1" in
      deploy)     rtot="$c_deploy";     rcmd="" ;;
      activation) rtot="$c_activation"; rcmd='for f in ~/.claude/autonomy/pending-activation/*.sh; do [ -f "$f.done" ] || echo "$f"; done' ;;
      # NOT `--class C`: this leg also admits a class-B packet that carries neither a default nor a
      # deadline (a hard block wearing the wrong label — see the decisions leg above), and a
      # `--class C` filter would hide exactly those rows from the operator who followed this
      # pointer to see "the rest". The overflow command must reproduce the rows it summarises.
      decision)   rtot="$c_decision";   rcmd='cc-decide list --open' ;;
      backlog)    rtot="$c_backlog";    rcmd='cc-backlog list --blocked' ;;
      *) return 0 ;;
    esac
    rest=$(( rtot - $2 )); [ "$rest" -gt 0 ] || return 0
    n=$((n + 1))
    printf ' %d ↳ %s   [+%s more %s]\n' "$n" "${rcmd:-cc-blockers}" "$rest" "$1"
  }

  while IFS="$TABC" read -r cls mark text stem; do
    [ -n "$mark" ] || continue
    # `yours` is already rendered above. Skipped BEFORE the last_cls transition so the remaining
    # classes stay contiguous: session-filed items interleave with standing ones in the backlog
    # stream, and letting them through here would make close_class see backlog→yours→backlog and
    # emit that class's rollup twice.
    [ "$cls" = yours ] && continue
    # `held` likewise: already rendered above the fork, and it must not open a class run here (it has
    # no allocation and close_class has no arm for it, so letting it through would emit a bare row
    # outside the budget the other classes are held to).
    [ "$cls" = held ] && continue
    if [ "$cls" != "$last_cls" ]; then
      [ -n "$last_cls" ] && close_class "$last_cls" "$pc"
      last_cls="$cls"; pc=0
    fi
    case "$cls" in
      deploy)     alloc="$a_deploy" ;;
      activation) alloc="$a_activation" ;;
      decision)   alloc="$a_decision" ;;
      backlog)    alloc="$a_backlog" ;;
      *)          alloc="$MAX" ;;
    esac
    # MAX bounds the STANDING itemisation only — `yours` is exempt, so subtract the lines it took
    # rather than letting a session's own steps eat the legacy budget for everything else.
    if [ "$legacy" = 1 ] && [ $(( n - y_lines )) -ge "$MAX" ]; then break; fi
    if [ "$pc" -lt "$alloc" ]; then
      n=$((n + 1)); pc=$((pc + 1)); shown=$((shown + 1))
      printf ' %d %s %s\n' "$n" "$mark" "$text"
    fi
  done < "$steps_file"
  [ -n "$last_cls" ] && close_class "$last_cls" "$pc"
  rm -f "$steps_file"
  fi   # ── end CBUDGET collapse / itemise branch ──

  # ── escalation records (D3) — ONE counted line, outside both mode branches so it reads the same in
  # collapse, itemised and legacy. Deliberately UNNUMBERED: `NSTEPS` counts `^ [0-9]+ (▶|◆)`, and
  # these are not operator STEPS — they are records a machine should have drained. `◆` because there
  # is no single command that clears them (ack is per-record, and acking an undelivered escalation is
  # a judgment, not a chore).
  [ "${esc_n:-0}" -gt 0 ] && printf ' ◆ %s escalation record(s) unseen — cc-escalations list\n' "$esc_n"

  # The `+N more` footer is the LEGACY path only. Under the class budget it is not merely redundant,
  # it is the defect: one aggregate number that hides which CLASSES are missing (§4 F5).
  local foot=""
  if [ "$legacy" = 1 ]; then
    over=$(( total - shown )); [ "$over" -lt 0 ] && over=0
    [ "$over" -gt 0 ] && foot="+${over} more"
  fi
  [ -n "$b_line" ] && foot="${foot:+$foot · }${b_line}"
  # queue rides the footer whenever it is not already the header (steps or 📦 govern the headline).
  if [ -n "$q_line" ] && { [ "$total" -gt 0 ] || [ "$RUNG" = "📦" ] || [ "$RUNG" = "🚀" ]; }; then
    foot="${foot:+$foot · }${q_line}"
  fi
  if [ "$total" -gt 0 ]; then
    if command -v cc-blockers >/dev/null 2>&1; then foot="${foot:+$foot · }board: cc-blockers"
    else foot="${foot:+$foot · }detail: cc-decide list --open · cc-backlog list --blocked"; fi
  fi
  [ -n "$foot" ] && printf ' ─ %s\n' "$foot"
  return 0
}

# ── render mode: the pull surface (/wrap, tests, humans). No damping, no state, no IDL. ──
if [ "$MODE" = "render" ]; then
  command -v jq >/dev/null 2>&1 || { echo "operator-readout: jq required" >&2; exit 2; }
  out="$(render_block "${RCWD:-$PWD}")"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "OPERATOR ▸ no manual steps pending."; fi
  exit 0
fi

# ── hook mode ──
input="$(cat 2>/dev/null || printf '{}')"
[ "${CC_OPREADOUT_DISABLE:-0}" = "1" ] && abstain "disabled"
command -v jq >/dev/null 2>&1 || abstain "no-jq"

SID="$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"

# ── NO OPERATOR, NO OPERATOR BLOCK (2026-08-02) ──────────────────────────────────────────────────
# Observed: a teammate pane (@preview-index-fix, spawned Agent({name,team_name})) rendered
# `OPERATOR ▸ ✅ SAFE TO CLOSE … 12 runnable now, 253 need your call` into its OWN transcript. A
# background assignee is a REAL child session and so runs this whole main-session Stop chain — but
# it has no human entrypoint at all, so every line of that block is undeliverable: nobody reads it,
# it reports the MACHINE's standing pile rather than the teammate's brief, it burns the one resource
# the brief discipline exists to protect, and "253 need your call" invites it to act on
# operator-owned items that are categorically not its work.
# Placed HERE — after the two free gates, before render_block's ~2711 ms / ~100 forks — so an
# assignee pays one `ps` and nothing else. `--render` is deliberately NOT guarded: that surface is
# the pull path (/wrap, tests, humans) and is invoked BY the operator, so it has one by definition.
_op_lib="${AGENT_IDENTITY_LIB:-$SCRIPT_DIR/lib/agent-identity.sh}"
[ -f "$_op_lib" ] || { _op_t="$0"; [ -L "$_op_t" ] && _op_t="$(readlink "$_op_t")"
  _op_lib="$(cd "$(dirname "$_op_t")" 2>/dev/null && pwd)/lib/agent-identity.sh"; }
[ -f "$_op_lib" ] || _op_lib="$CFG/hooks/lib/agent-identity.sh"
[ -f "$_op_lib" ] || _op_lib="$HOME/.claude/hooks/lib/agent-identity.sh"
if [ -f "$_op_lib" ]; then
  # shellcheck source=lib/agent-identity.sh
  # shellcheck disable=SC1091
  if . "$_op_lib" 2>/dev/null; then
    _op_aid="$(agent_is_assignee 2>/dev/null || true)"
    [ -n "$_op_aid" ] && abstain "team-assignee:${_op_aid}"
  fi
fi
# SID is parsed above, before the assignee guard, so that guard's abstain is ATTRIBUTABLE — an IDL
# row reading sid "?" cannot be traced to the session it silenced, and this is the one hook whose
# silence an operator may need to explain later.
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# ── the wrap-ledger memo's EVENT key (P0-4, scripts/wrap-ledger.sh § THE MEMO) ──
# Seven Stop-hook call sites each pay a full ~180 ms / 19-git ledger on every close, and TWO of them
# are in this file. They are one event, so they should observe one snapshot: handing the ledger this
# session's transcript is what lets it serve one. Set HERE and not in --render mode, which has no
# stdin JSON and therefore no event — /wrap's pull surface keeps computing, as it must.
# Expanded into its OWN variable: $TP itself feeds session_wrote_here_this_turn below, and this
# memo has no business changing what the write-turn oracle is handed.
_or_tp="$TP"; case "$_or_tp" in "~"*) _or_tp="$HOME${_or_tp#\~}" ;; esac
[ -n "$_or_tp" ] && export WRAP_TRANSCRIPT="$_or_tp"

# ── WRITE-TURN ORACLE (feeds both the certified governing line and the standalone certificate) ────
# Resolved ONCE, here, before render_block — two independent reads of one value is how they drift
# (this file's own kill_switch/SC_SID note, :131-134). Any failure leaves CERT_WROTE=2 (cannot tell),
# which downgrades every claim below rather than blocking anything.
if [ "${CC_CLOSE_CERT:-1}" != "0" ]; then
  _swlib="${SESSION_WRITES_LIB:-$SCRIPT_DIR/lib/session-writes.sh}"
  # A BRAND-NEW hooks/lib file has no ~/.claude/hooks/lib symlink until install.sh runs — and when
  # this hook executes from ~/.claude/hooks/, SCRIPT_DIR and both tiers below resolve to that SAME
  # missing path, so the certificate would land INERT on the live layer and nothing would say so.
  # Resolve $0's own symlink into the checkout first: the live hook IS a symlink to the repo, so
  # this finds the lib on the same fast-forward that delivers this hook. (Identical reasoning and
  # shape to hooks/completion-assert.sh:99-105 — the precedent that made this failure mode known.)
  [ -f "$_swlib" ] || { _swt="$0"; [ -L "$_swt" ] && _swt="$(readlink "$_swt")"
    _swlib="$(cd "$(dirname "$_swt")" 2>/dev/null && pwd)/lib/session-writes.sh"; }
  [ -f "$_swlib" ] || _swlib="$CFG/hooks/lib/session-writes.sh"
  [ -f "$_swlib" ] || _swlib="$HOME/.claude/hooks/lib/session-writes.sh"
  if [ -f "$_swlib" ]; then
    # shellcheck source=lib/session-writes.sh
    # shellcheck disable=SC1091
    if . "$_swlib" 2>/dev/null; then
      # TURN-scoped and CWD-scoped, both deliberately (lib § TWO SCOPES). The session-scoped
      # boolean that used to sit here answered a wider question than the one asked: after a
      # session's first edit it read rc 0 on every later Stop, so a purely conversational close
      # still certified — E0 is per-TURN, and the oracle was per-SESSION. It also certified on
      # writes that landed in another tree entirely. An older lib without this function leaves
      # CERT_WROTE=127, which matches no arm below and therefore withholds — the safe direction.
      session_wrote_here_this_turn "$TP" "$CWD"; CERT_WROTE=$?
    fi
  fi
fi

# Compose-guard: while session-continue's 🔧 loop is armed the session is mid-drive — the close
# the operator reads comes later; yield (matches boundary-handoff's guard, same sentinel SSOT).
if [ -n "$CWD" ]; then
  if [ -n "${CC_CONTINUE_SENTINEL:-}" ]; then sc="$CC_CONTINUE_SENTINEL"
  else
    sclib="$SCRIPT_DIR/lib/continue-sentinel.sh"
    [ -f "$sclib" ] || sclib="$CFG/hooks/lib/continue-sentinel.sh"
    [ -f "$sclib" ] || sclib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
    sc=""
    if [ -f "$sclib" ]; then
      # shellcheck source=lib/continue-sentinel.sh
      # shellcheck disable=SC1091
      . "$sclib" 2>/dev/null || true
      command -v continue_sentinel_for >/dev/null 2>&1 && sc="$(continue_sentinel_for "$CWD" 2>/dev/null || true)"
    fi
  fi
  { [ -n "$sc" ] && [ -f "$sc" ]; } && abstain "continue-armed"
fi

# ── PRE-RENDER CHEAP STAMP (row 13 M3 — MACHINE_CAPACITY_V2.md §8.5.3) ─────────────────────────
# The damping latch below is correct but PAID FOR AFTER THE FACT: its input is the RENDERED block,
# so the 900 s TTL suppressed OUTPUT and saved ZERO CPU. render_block costs ~2711 ms (73% of the
# 3688 ms Stop chain) — 24 command substitutions, ~100 forks, git x7 / jq x6 / cc-backlog x5, plus a
# `rev-list --count HEAD..origin/main` walk against the ONE shared checkout from EVERY session's
# EVERY Stop. At 30 sessions that is ~30x100 forks per turn-round against one contended .git, and
# the hook chain is fork-dominated (49% of its cost is scheduler queueing it causes itself), so this
# is the O(N^2) term, not a constant.
#
# The inversion: decide whether anything MOVED using only cheap reads, and render only when it did
# (or when the TTL expires and the block must re-assert). This dissolves the class
# "content-hash latch pays full cost to decide it had nothing to say".
#
# The stamp covers every input that can change the block: the activation queue, the decisions store,
# the backlog file, this cwd's commit + dirty state, and the shared checkout's trunk position. Two
# bounded `git` calls + a few `stat`s — measured ~60-100 ms vs 2711 ms.
#
# SAFETY: the stamp is only ever permitted to SUPPRESS inside the TTL the latch already enforced, so
# the worst case is a change the stamp cannot see going unreported for at most TTL — the same
# staleness bound the operator already lives with. It is NOT permitted to suppress past the TTL: an
# expired latch always re-renders. Dirty-tree state is read with a real `git status` rather than an
# `.git/index` mtime precisely so an unstaged edit cannot slip through that window.
# Kill switch: CC_READOUT_DAMP=off  → skip the cheap gate entirely (restores today's cost exactly).
cheap_stamp() {
  local cwd="${1:-}" s="" p
  for p in "$ACT_DIR" "$DEC_DIR" "$BLG_FILE"; do
    s="$s|$(stat -f '%m/%z' "$p" 2>/dev/null || printf -)"
  done
  if [ -n "$cwd" ]; then
    s="$s|$(git -C "$cwd" rev-parse HEAD 2>/dev/null || printf -)"
    s="$s|$(git -C "$cwd" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
  else
    s="$s|-|-"
  fi
  # trunk position via rev-parse (a ref READ), never rev-list (a commit WALK) — same fact, no walk.
  s="$s|$(git -C "$SHARED" rev-parse origin/main 2>/dev/null || printf -)"
  printf '%s' "$s"
}

mkdir -p "$STATE_DIR" 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "${CWD:-}" | shasum 2>/dev/null | cut -c1-16)"
LATCH="$STATE_DIR/$SKEY.last"
STAMP=""
if [ "${CC_READOUT_DAMP:-on}" != "off" ] && [ -n "$SKEY" ] && [ -f "$LATCH" ]; then
  STAMP="$(cheap_stamp "${CWD:-}" | shasum 2>/dev/null | cut -c1-16)"
  # Latch line format: "<content-hash> <ts> [<stamp>]". A 2-field line is the PRE-M3 format — treat
  # a missing stamp as "unknown", which falls through to a full render and rewrites the new format.
  # Never infer equality from an absent field.
  read -r _lh _lts _lstamp < "$LATCH" 2>/dev/null || { _lh=""; _lts=0; _lstamp=""; }
  case "$_lts" in ''|*[!0-9]*) _lts=0 ;; esac
  if [ -n "$STAMP" ] && [ -n "${_lstamp:-}" ] && [ "$_lstamp" = "$STAMP" ] \
     && [ $(( NOW - _lts )) -lt "$TTL" ]; then
    abstain "stamp-unchanged-ttl:$(( NOW - _lts ))s<${TTL}s"
  fi
fi

# Render in THIS shell (temp-file redirect, not $(…)) so render_block's RUNG/TOTAL survive.
TMPB="$(mktemp "${TMPDIR:-/tmp}/opreadout-blk.XXXXXX" 2>/dev/null)" || abstain "no-mktemp"
render_block "${CWD:-}" > "$TMPB" 2>/dev/null
BLOCK="$(cat "$TMPB" 2>/dev/null || true)"; rm -f "$TMPB"

# ── CLOSE CERTIFICATE — say "safe to close" BY CONSTRUCTION, so the operator stops asking ─────────
# THE DEFECT (operator crux 2026-08-01): this hook's fire predicate was steps>0 ∨ 📦 ∨ queue>0 and
# SILENT otherwise — "✅/read-only needs no block". But silence is not an answer; it is
# indistinguishable from "the hook didn't run", "the model forgot", and "nobody looked". So on the
# one close where everything really is finished, the only thing the operator saw was model PROSE —
# exactly the self-report they cannot audit, and exactly why they had to keep asking "are we good to
# close with no remaining tasks, loose-ends, or manual steps?" every single time. The negative gates
# around this one (completion-assert) can only ever REFUTE a false done; nothing ever AFFIRMED a
# true one. This is that affirmation, computed from the same wrap-ledger facts, never from prose.
#
# GATED ON A WRITE TURN, and that gate is what keeps it worth reading. A certificate that fired on
# every close — including the hundreds of read-only turns — would carry exactly as many bits as one
# that never fires (MEMORY.md alarm-polarity-and-attention-budget), and the protocol already says
# to suppress the readout on read-only turns (E0). lib/session-writes.sh answers "did THIS session
# write files" from the transcript, in three states; only an affirmative rc 0 certifies. rc 1
# (read-only) and rc 2 (cannot tell) both stay silent — never assert safe-to-close on an unknown.
#
# ONLY ✅ REACHES HERE. 👤/📦/queue all produce a non-empty $BLOCK above and return early with their
# own governing line, and 🔧 is deliberately uncertified: it is not safe to close, and it belongs to
# session-continue's loop. So this arm cannot contradict the block renderer — it speaks only where
# the renderer had nothing to say.
# Seams: CC_CLOSE_CERT (0 disables) · SESSION_WRITES_LIB
if [ -z "$BLOCK" ]; then
  [ "${CC_CLOSE_CERT:-1}" = "0" ] && abstain "nothing-to-surface"
  [ "$RUNG" = "✅" ] || abstain "nothing-to-surface"

  # NOT a write turn ⇒ this is exactly the pre-existing empty-block state, so it abstains with the
  # pre-existing REASON. The token is a telemetry contract (tests and cc-audit key on it); a new arm
  # that declines to fire must be byte-identical to the world before it existed, or it silently
  # rewrites the forensics of a case it did not change. Only genuinely NEW paths get new tokens.
  [ "${CERT_WROTE:-2}" = "0" ] || abstain "nothing-to-surface"

  # Re-read the ledger for the facts the line cites. render_block's copy is function-local, and
  # quoting a remembered value is precisely the self-report this arm exists to replace.
  _cwrap="${WRAP_LEDGER_BIN:-}"
  if [ -z "$_cwrap" ]; then
    for _c in "$SCRIPT_DIR/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
      [ -f "$_c" ] && { _cwrap="$_c"; break; }
    done
  fi
  [ -n "$_cwrap" ] && [ -f "$_cwrap" ] || abstain "nothing-to-surface"
  _cled="$( cd "${CWD:-}" 2>/dev/null && bash "$_cwrap" --machine 2>/dev/null || true )"
  [ -n "$_cled" ] || abstain "nothing-to-surface"
  _clf() { printf '%s' "$_cled" | grep -E "^$1=" | head -1 | cut -d= -f2-; }
  # Re-confirm the rung from THIS read: between render_block and here a sibling could have landed or
  # dirtied the tree, and a certificate is the one output that must never be stale.
  [ "$(_clf RUNG)" = "✅" ] || abstain "cert-rung-moved"
  _ctrunk="$(_clf TRUNK)"; _cdod="$(_clf DOD)"; _crem="$(_clf REMAINDER)"
  case "$_crem" in ''|*[!0-9]*) _crem=0 ;; esac

  # The DoD-absent case is reported, never smoothed over: wrap-ledger already refuses to call an
  # unverifiable scope complete, and the certificate must inherit that honesty rather than launder it.
  if [ "$_cdod" = "present" ] && [ "$_crem" -eq 0 ]; then
    _cscope="frozen-DoD remainder 0"
  else
    _cscope="scope UNVERIFIED (no durable DoD)"
  fi
  _cert="✅ SAFE TO CLOSE — nothing is left on this side.
   tree clean · landed on ${_ctrunk:-?} (nothing parked) · ${_cscope} · no manual step is yours.
   Verified from live git reads at this close, not from memory."

  log_idl fired "close-certificate" \
    "$(jq -cn --arg rung "$RUNG" --arg trunk "${_ctrunk:-?}" --arg dod "${_cdod:-?}" \
        '{rung:$rung,trunk:$trunk,dod:$dod}' 2>/dev/null || echo '{}')"
  jq -nc --arg m "$_cert" '{systemMessage:$m}' 2>/dev/null || true
  exit 0
fi

# Damping latch: change → render now; unchanged → re-assert only after TTL.
# (STATE_DIR/SKEY/LATCH are established by the pre-render stamp gate above — not recomputed here.)
HASH="$(printf '%s' "$BLOCK" | shasum 2>/dev/null | cut -c1-16)"
if [ -n "$SKEY" ] && [ -n "$HASH" ]; then
  # The stamp may not have been computed above (kill switch, or no latch file existed). Compute it
  # now so the latch we write is always usable by the NEXT turn's cheap gate — a latch missing its
  # stamp field silently disables the optimization forever after.
  [ -n "$STAMP" ] || STAMP="$(cheap_stamp "${CWD:-}" | shasum 2>/dev/null | cut -c1-16)"
  if [ -f "$LATCH" ]; then
    read -r prev_hash prev_ts _prev_stamp < "$LATCH" 2>/dev/null || { prev_hash=""; prev_ts=0; }
    case "$prev_ts" in ''|*[!0-9]*) prev_ts=0 ;; esac
    if [ "$prev_hash" = "$HASH" ] && [ $(( NOW - prev_ts )) -lt "$TTL" ]; then
      # Content unchanged, but the STAMP moved (else the cheap gate would already have abstained).
      # Persist the new stamp while KEEPING prev_ts, so (a) the next turn short-circuits cheaply
      # instead of re-rendering this same block, and (b) the TTL still measures from the last real
      # render rather than being silently extended by a no-op. Getting (b) wrong would let a
      # never-changing block suppress its own re-assert indefinitely.
      printf '%s %s %s\n' "$HASH" "$prev_ts" "$STAMP" > "$LATCH" 2>/dev/null || true
      abstain "latched-ttl:$(( NOW - prev_ts ))s<${TTL}s"
    fi
  fi
  printf '%s %s %s\n' "$HASH" "$NOW" "$STAMP" > "$LATCH" 2>/dev/null || true
fi

NSTEPS="$(printf '%s\n' "$BLOCK" | grep -cE '^ [0-9]+ (▶|◆)' 2>/dev/null)"
case "$NSTEPS" in ''|*[!0-9]*) NSTEPS=0 ;; esac
case "$TOTAL"  in ''|*[!0-9]*) TOTAL=0  ;; esac
case "$Q_N"    in ''|*[!0-9]*) Q_N=0    ;; esac
log_idl fired "steps-surfaced" \
  "$(jq -cn --arg rung "$RUNG" --argjson total "$TOTAL" --argjson shown "$NSTEPS" --argjson q "$Q_N" \
      '{rung:$rung,steps_total:$total,steps_shown:$shown,queue_open:$q}' 2>/dev/null || echo '{}')"
jq -nc --arg m "$BLOCK" '{systemMessage:$m}' 2>/dev/null || true
exit 0
