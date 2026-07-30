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
# ── FIRE PREDICATE ── steps>0 ∨ RUNG=📦 ∨ open-queue>0. Silent otherwise: 🔧 with no operator
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
#   deploy-lag   shared checkout ON trunk but behind its origin/main → the exact ff-sync command
#                (deploy-lag incident 2026-07-20: landed ≠ live; ordered FIRST — activations abort
#                on a stale checkout)
#   activation   pending-activation/*.sh with no .done marker → `bash <p> && touch <p>.done`
#                (CONFIRM=1-prefixed when the script gates on it — `&&` keeps a dry-run or failed
#                run from falsely marking done)
#   decisions    cc-decide store, open class-C (human-gated): run_command (board vocabulary,
#                forward-compatible with feat/board-runnable-commands) → staged_artifact_path
#                (`bash <p>`) → first-sentence prose fallback. Open class-B is NEVER itemized —
#                one summary line only when defaults auto-fire within 24h (the early-veto window).
#   backlog      cc-backlog list --blocked --json → run/run_command if present, else needs-prose.
#   queue        cc-backlog OPEN items for the cwd project (git-toplevel basename, the same
#                normalization cc-dispatch applies) → one COUNTED line, never itemized (open items
#                are the dispatcher's work, not operator steps). Header when it is the only signal,
#                footer otherwise.
#   Line marks: `▶` = run this exact command · `◆` = judgment/decision (no single command exists) ·
#   `↳` = N more of this class, and this command lists them (the class-rollup, §4 M2).
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
#
# ── SAFETY (house pattern) ── every hook path exits 0; jq/read failure → abstain; B-3 one IDL
#   {fired|abstained:<reason>} line per invocation; kill-switch CC_OPREADOUT_DISABLE=1;
#   compose-guard abstains while session-continue's 🔧 loop is armed (lib/continue-sentinel SSOT).
#
# ── MODES ── (default, stdin JSON) hook mode · `--render [--cwd <d>]` prints the block to stdout
#   with no damping/state/IDL — /wrap's pull surface and the bats harness call this; ONE renderer
#   serves push + pull so the surfaces cannot drift.
#
# Env seams (tests): CC_OPREADOUT_DISABLE · CC_OPREADOUT_MAX · CC_OPREADOUT_TTL_S ·
#   CC_OPREADOUT_NOW (epoch) · CC_OPREADOUT_STATE_DIR · CC_ACTIVATION_DIR · CC_DECISIONS_DIR ·
#   CC_BACKLOG_FILE · CC_BACKLOG_BIN · WRAP_LEDGER_BIN · WRAP_TRUNK (passes through) ·
#   CC_SHARED_CHECKOUT · CC_IDL · CC_CONTINUE_SENTINEL · CC_OPREADOUT_CLASSBUDGET · CC_DEPLOY_SCRIPT
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${CC_OPREADOUT_STATE_DIR:-$CFG/state/operator-readout}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
ACT_DIR="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
DEC_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
BLG_FILE="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
# A SEAM, and specifically so the deploy platter's own existence check (I11) is testable in BOTH
# states. Without it the suite asserts the operator's live ~/.claude/scripts/ and the verdict flips
# by machine — borrowed hermeticity, and the flip case is exactly the one the check exists for.
DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"
MAX="${CC_OPREADOUT_MAX:-6}"          # the ITEMIZED-line budget (§4 M2); rollups ride on top
TTL="${CC_OPREADOUT_TTL_S:-900}"
NOW="${CC_OPREADOUT_NOW:-$(date +%s 2>/dev/null || echo 0)}"
SID="?"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

MODE="hook"; RCWD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --render) MODE="render" ;;
    --cwd)    shift; RCWD="${1:-}" ;;
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

# ── the ONE renderer: prints the block (or nothing) for cwd=$1. Sets RUNG + TOTAL + Q_N for the
#    caller — so hook mode must invoke it via redirection in THIS shell, never `$(…)` (subshell
#    loses them).
RUNG="?"; TOTAL=0; Q_N=0
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
  local CBUDGET="${CC_OPREADOUT_CLASSBUDGET:-on}"

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
      [ "$behind" -gt 0 ] && printf 'deploy\t▶\tbash %s   [deploy: live layer %s behind origin/%s]\n' \
        "$(tildify "$dscript")" "$behind" "$sbr" >> "$steps_file"
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
  local f disp pre act_c="" act_p=""
  if [ -d "$ACT_DIR" ]; then
    for f in "$ACT_DIR"/*.sh; do
      [ -f "$f" ] || continue
      [ -f "$f.done" ] && continue
      disp="$(tildify "$f")"; pre=""
      grep -q 'CONFIRM' "$f" 2>/dev/null && pre="CONFIRM=1 "
      if [ "$CBUDGET" = off ]; then       # legacy: glob order, one stream
        act_c="${act_c}activation${TABC}▶${TABC}${pre}bash ${disp} && touch ${disp}.done   [activation]"$'\n'
      elif [ -n "$pre" ]; then
        act_c="${act_c}activation${TABC}▶${TABC}${pre}bash ${disp} && touch ${disp}.done   [activation]"$'\n'
      else
        act_p="${act_p}activation${TABC}▶${TABC}bash ${disp} && touch ${disp}.done   [activation]"$'\n'
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
      jq -r '
        select((.status // "" | if . == "" then "open" else . end) == "open"
               and (.class // "") == "C")
        | (.id // "?" | .[0:8]) as $id8
        | (.what_plain // "" | gsub("[\n\t]"; " ") | split(". ")[0]) as $s
        | ($s | if length > 110 then .[0:110] + "…" else . end) as $sent
        | (.run_command // "" | gsub("[\n\t]"; " ")) as $run
        | (.staged_artifact_path // "" | gsub("[\n\t]"; " ")) as $staged
        | (if $run != ""      then "decision\t▶\t\($run)   [decision C \($id8): \($sent | .[0:60])]"
           elif $staged != "" then "decision\t▶\tbash \($staged)   [decision C \($id8): \($sent | .[0:60])]"
           else "decision\t◆\t[decision C \($id8)] \($sent)" end) as $line
        | "\(.created // "?")\t\($line)"' "$f" 2>/dev/null
    done | sort | cut -f2- >> "$steps_file"
  fi

  # 4 · blocked backlog: operator-only `needs` steps, with the run command when the item carries one.
  local blg="${CC_BACKLOG_BIN:-}"
  if [ -z "$blg" ]; then
    for f in "$SCRIPT_DIR/../bin/cc-backlog" "$CFG/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog"; do
      [ -x "$f" ] && { blg="$f"; break; }
    done
  fi
  if [ -n "$blg" ] && [ -f "$BLG_FILE" ]; then
    "$blg" list --blocked --json 2>/dev/null | jq -r '
      .[]?
      | (.title // "" | gsub("[\n\t]"; " ") | .[0:60]) as $t
      | (.needs // "" | gsub("[\n\t]"; " ") | .[0:90]) as $n
      | (.run // .run_command // "" | gsub("[\n\t]"; " ")) as $run
      | if $run != "" then "backlog\t▶\t\($run)   [backlog \(.id // "?"): \($t)]"
        else "backlog\t◆\t[backlog \(.id // "?")] \($t) — needs: \($n)" end' 2>/dev/null >> "$steps_file"
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
    Q_N="$("$blg" list --open --json 2>/dev/null \
      | jq --arg p "$q_proj" '[ .[]? | select(.status=="open" and .project==$p) ] | length' \
          2>/dev/null || echo 0)"
    case "$Q_N" in ''|*[!0-9]*) Q_N=0 ;; esac
    [ "$Q_N" -gt 0 ] && q_line="queue: ${Q_N} open (${q_proj}) — cc-dispatch auto-drains · cc-backlog list --open --project ${q_proj}"
  fi

  # ── state line from the un-fakeable ledger (cwd repo; skipped cleanly outside a repo) ──
  local state="" wrap="" led="" branch ahead shas dirty_n gate remainder parts
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
      "🔧")
        dirty_n="$(lf DIRTY_N)"; gate="$(lf GATE)"; remainder="$(lf REMAINDER)"
        parts=""
        [ "${dirty_n:-0}" != "0" ] && parts="${dirty_n} file(s) uncommitted"
        [ "$gate" = "stale" ] && parts="${parts:+$parts · }gate stale on HEAD"
        [ "${remainder:-0}" != "0" ] && parts="${parts:+$parts · }${remainder} DoD item(s) open"
        state="🔧 in progress — ${parts:-loose ends}" ;;
      "✅") state="✅ live on trunk" ;;
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
  local total=0 cls mark text
  local c_deploy=0 c_activation=0 c_decision=0 c_backlog=0
  # PASS 1 — count per class. Fork-free: a `< file` redirect is not a fork, and this REPLACES the
  # `grep -c .` that used to compute the total, so the class budget costs one fork LESS than the
  # flat renderer it supersedes (C19: no new fork may enter render_block).
  while IFS="$TABC" read -r cls mark text; do
    [ -n "$mark" ] || continue
    total=$((total + 1))
    case "$cls" in
      deploy)     c_deploy=$((c_deploy + 1)) ;;
      activation) c_activation=$((c_activation + 1)) ;;
      decision)   c_decision=$((c_decision + 1)) ;;
      backlog)    c_backlog=$((c_backlog + 1)) ;;
    esac
  done < "$steps_file"
  TOTAL="$total"
  if [ "$total" -eq 0 ] && [ "$RUNG" != "📦" ] && [ "$Q_N" -eq 0 ]; then rm -f "$steps_file"; return 0; fi

  # ALLOCATION. Written out per class rather than looped: four classes is a fixed set, and the
  # alternatives (eval, or a `$(fn)` lookup) cost either clarity or a fork per step.
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
  if [ "$total" -gt 0 ]; then hdr="OPERATOR ▸ ${total} manual step(s)${state:+ · $state}"
  elif [ "$RUNG" = "📦" ]; then hdr="OPERATOR ▸ ${state}"
  else hdr="OPERATOR ▸ ${q_line}"; fi   # queue-only render: the queue IS the governing line
  printf '%s\n' "$hdr"

  local n=0 alloc pc=0 last_cls="" rest rcmd rtot
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
      decision)   rtot="$c_decision";   rcmd='cc-decide list --open --class C' ;;
      backlog)    rtot="$c_backlog";    rcmd='cc-backlog list --blocked' ;;
      *) return 0 ;;
    esac
    rest=$(( rtot - $2 )); [ "$rest" -gt 0 ] || return 0
    n=$((n + 1))
    printf ' %d ↳ %s   [+%s more %s]\n' "$n" "${rcmd:-cc-blockers}" "$rest" "$1"
  }

  while IFS="$TABC" read -r cls mark text; do
    [ -n "$mark" ] || continue
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
    if [ "$legacy" = 1 ] && [ "$n" -ge "$MAX" ]; then break; fi
    if [ "$pc" -lt "$alloc" ]; then
      n=$((n + 1)); pc=$((pc + 1)); shown=$((shown + 1))
      printf ' %d %s %s\n' "$n" "$mark" "$text"
    fi
  done < "$steps_file"
  [ -n "$last_cls" ] && close_class "$last_cls" "$pc"
  rm -f "$steps_file"

  # The `+N more` footer is the LEGACY path only. Under the class budget it is not merely redundant,
  # it is the defect: one aggregate number that hides which CLASSES are missing (§4 F5).
  local foot=""
  if [ "$legacy" = 1 ]; then
    over=$(( total - shown )); [ "$over" -lt 0 ] && over=0
    [ "$over" -gt 0 ] && foot="+${over} more"
  fi
  [ -n "$b_line" ] && foot="${foot:+$foot · }${b_line}"
  # queue rides the footer whenever it is not already the header (steps or 📦 govern the headline).
  if [ -n "$q_line" ] && { [ "$total" -gt 0 ] || [ "$RUNG" = "📦" ]; }; then
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
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

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
[ -n "$BLOCK" ] || abstain "nothing-to-surface"

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
