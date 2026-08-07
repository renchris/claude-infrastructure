#!/usr/bin/env bash
# pane-spawn-log.sh — ONE durable row per pane-spawn, naming the CALLER that issued it.
#
# ── THE DEFECT, MEASURED ───────────────────────────────────────────────────────────────────────
# 2026-08-07, item `191d4d056c98` (CONCURRENCY_PROGRAM.md §S4.1): nine sessions came up in ONE
# worktree from ONE composed prompt. Forensics could reconstruct that much — all nine first user
# messages are byte-identical at 2281 chars and carry a SINGLE `HANDOFF-ENGAGE-27022-…` marker,
# and only two `handoff-prompt-nb-XXXXXX` files exist in the window — but it could not name what
# issued the eight extra launch+run pairs. `cc-dispatch`, `lead-supervisor.sh`, `waiting-recycle`
# and repeated `handoff-fire` were each independently FALSIFIED. Two hypotheses survived with
# nothing measured separating them:
#
#     (a) an UNLOGGED CALLER — some path that spawns a pane without entering handoff-fire
#     (b) an UNDOCUMENTED DETACHED CHILD — something re-parented that spawns after its parent exits
#
# ── WHY THE EXISTING LOGS COULD NOT DECIDE IT ──────────────────────────────────────────────────
# `~/.claude/logs/handoffs.jsonl` and the dispatcher IDL both count *fires that entered
# handoff-fire's front door*. A spawn that goes around that door is not under-reported by them —
# it is INVISIBLE to them, and an invisible event is indistinguishable from one that never
# happened (the absence-alarm shape: memory `alarm-polarity-and-attention-budget`). So the storm
# left the two hypotheses exactly where it found them.
#
# ── THE INFERENCE THIS FILE EXISTS TO MAKE VALID ───────────────────────────────────────────────
# With EVERY in-tree spawn site instrumented, one new inference becomes sound:
#
#     a pane that exists with NO row here was spawned by something OUTSIDE this tree.
#
# That is the whole point, and it is why coverage is not optional: a single uninstrumented site
# turns the inference from "outside the tree" into "outside the tree, or that one site" — which is
# the ambiguity being closed. `scripts/pane-spawn-coverage-lint.sh` fails the gate when a new
# spawn primitive lands without a call to this function, so the census cannot decay silently
# (memory `enforcement-must-live-at-the-chokepoint` — a census in a doc is detection, a lint in
# the always-run phase is a gate).
#
# ── WHY pid + ppid ARE NOT ENOUGH ON THEIR OWN, AND WHAT CARRIES THE ANSWER ─────────────────────
# The item asks for the caller's pid and ppid, and they are here — but a pid read months later
# names nothing: it has been recycled, and the process is gone. Three fields carry the identity
# instead, each answering a different half of the question:
#
#   caller    THIS script's own name, from `$0`. Exact, free, no `ps` involved.
#   chain     the inherited script-name chain (`cc-dispatch>handoff-fire.sh>it2-kitty`), relayed
#             through CC_SPAWN_CHAIN in the environment. A nested spawn therefore names every
#             in-tree script above it BY NAME, which pid numbers cannot do post-hoc. This is what
#             discriminates hypothesis (a): a chain whose head is an unexpected script names the
#             unlogged caller outright.
#   ancestry  the `pid:comm` chain walked from `$$` upward. This is what discriminates hypothesis
#             (b): a detached child shows a broken chain — re-parented to pid 1, or an ancestry
#             whose top is `launchd` where `chain` claims an interactive origin.
#
# ── COST DISCIPLINE ────────────────────────────────────────────────────────────────────────────
# The ancestry walk is ONE `ps` fork, not one per level: `ps -Ao pid=,ppid=,comm=` is read once and
# walked in awk. `comm` deliberately, never `args` — argv on this box carries whole agent briefs,
# and a table-wide `args=` read is both enormous and the exact instrument that has lied before
# (memory `pgrep-f-matches-agent-briefs` — `pgrep -f X` counted 50 sessions that merely MENTIONED
# X where the truth was 1). A spawn happens on the order of once per session, so one fork is free;
# a per-level walk would not be (memory `fork-cost-proxies-and-mid-session-siblings`).
#
# ── FAIL-OPEN, ALWAYS 0 ────────────────────────────────────────────────────────────────────────
# Same contract as `mark_fired_peer`: a SPAWN must never die on its own bookkeeping. Every path
# returns 0, and a caller under `set -e` is safe. CC_SPAWN_LOG=0 disables it outright (R8).
# The add-on must fail no wider than itself (memory `addon-failure-exceeds-its-blast-radius`), so
# nothing here defaults a variable off `$HOME` under `set -u` and nothing here removes a file.

# CC_SPAWN_LOG_FILE — UNSET ⇒ the default path. SET, including set to EMPTY ⇒ honored verbatim, so
# `CC_SPAWN_LOG_FILE=` genuinely turns the writer off at the source (the house seam pattern:
# `${VAR:-}` cannot tell unset from set-empty, and a seam that cannot turn a thing off is not one).
_cc_spawn_log_file() {
  if [ -n "${CC_SPAWN_LOG_FILE+set}" ]; then printf '%s' "$CC_SPAWN_LOG_FILE"; return 0; fi
  printf '%s' "${HOME:-}/.claude/logs/pane-spawns.jsonl"
}

# One ps, walked in awk. Emits "pid:comm>ppid:comm>…" up to CC_SPAWN_ANCESTRY_MAX levels.
# A walk that cannot start (no ps, empty table) yields "" — ABSENT, never a fabricated single
# node, so "unmeasured" stays distinguishable from "the chain really is one deep" (R9).
_cc_spawn_ancestry() { # $1=start pid → echoes the chain, or nothing
  local start="${1:-$$}" max="${CC_SPAWN_ANCESTRY_MAX:-8}"
  ps -Ao pid=,ppid=,comm= 2>/dev/null | awk -v start="$start" -v max="$max" '
    { pid=$1; ppid=$2; c=$3; sub(/.*\//, "", c); P[pid]=ppid; C[pid]=c }
    END {
      out=""; cur=start
      for (i = 0; i < max && cur != "" && cur != "0"; i++) {
        if (!(cur in C)) { out = out (out == "" ? "" : ">") cur ":?"; break }
        out = out (out == "" ? "" : ">") cur ":" C[cur]
        if (cur == "1") break
        cur = P[cur]
      }
      print out
    }' 2>/dev/null || true
}

# JSON-safe fallback for a box without jq. Strips the two characters that can break a JSON string
# (`"` and `\`), strips control characters, and truncates — so a degraded row is still parseable
# rather than corrupting every downstream `jq -s` read of the whole file.
_cc_spawn_scrub() { # $1=value → echoes a bounded, JSON-safe scalar
  printf '%s' "${1:-}" | tr -d '"\\\000-\037' | cut -c1-200 | tr -d '\n'
}

# cc_log_pane_spawn — the one writer. Call it at the site that ISSUES the launch, not at a wrapper
# above it: one row per real surface creation is the contract, and a row per layer would make
# "how many panes were spawned" a count nobody can take.
#
# $1 surface   split | bg-tab | tab | os-window | window | detach — what was created
# $2 backend   kitty | iterm2 | wezterm | ghostty | tmux — which terminal made it
# $3 pane      the new pane/window id when the caller already knows it, else "" (ABSENT, not "?" —
#              many launch primitives only learn the id from their own stdout, and a site that
#              logs BEFORE the launch cannot honestly claim one)
# $4 cwd       the directory the new surface starts in, else "" — this is the DURABLE key that
#              joins a row to a fired-peer stamp (see mark_fired_peer's cwd index)
# $5 detail    free text, bounded — the launch's distinguishing argument (location, --match, title)
cc_log_pane_spawn() { # → always 0
  [ "${CC_SPAWN_LOG:-1}" != 0 ] || return 0
  local log; log="$(_cc_spawn_log_file)"
  [ -n "$log" ] || return 0
  local dir; dir="$(dirname "$log" 2>/dev/null)" || return 0
  mkdir -p "$dir" 2>/dev/null || return 0

  local surface="${1:-unknown}" backend="${2:-unknown}" pane="${3:-}" cwd="${4:-}" detail="${5:-}"
  local self ppid_comm chain ancestry ts
  # CC_SPAWN_CALLER exists for the CLI mode below: when this file is EXECUTED rather than sourced,
  # `$0` is the library and would name every row after the logger instead of after the spawner.
  self="${CC_SPAWN_CALLER:-$(basename -- "${0:-?}" 2>/dev/null || printf '?')}"
  ppid_comm="$(ps -o comm= -p "$PPID" 2>/dev/null || true)"; ppid_comm="${ppid_comm##*/}"
  ancestry="$(_cc_spawn_ancestry "$$")"
  chain="${CC_SPAWN_CHAIN:-$self}"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

  if command -v jq >/dev/null 2>&1; then
    local line
    line=$(jq -cn \
      --arg ts "$ts" --arg sf "$surface" --arg be "$backend" --arg pn "$pane" \
      --arg cw "$cwd" --arg dt "$detail" --arg ca "$self" --arg ch "$chain" \
      --arg an "$ancestry" --arg pc "$ppid_comm" --arg mk "${FIRE_MARKER:-}" \
      --arg it "${CC_SPAWN_ITEM:-}" \
      --argjson pid "$$" --argjson ppid "$PPID" \
      '{ts:$ts, surface:$sf, backend:$be, caller:$ca, pid:$pid, ppid:$ppid}
       + {ppid_comm: (if $pc == "" then null else $pc end)}
       + {chain:$ch}
       + {ancestry: (if $an == "" then null else $an end)}
       + {pane:     (if $pn == "" then null else $pn end)}
       + {cwd:      (if $cw == "" then null else $cw end)}
       + {marker:   (if $mk == "" then null else $mk end)}
       + {item:     (if $it == "" then null else $it end)}
       + {detail:   (if $dt == "" then null else $dt end)}' 2>/dev/null) || line=""
    [ -n "$line" ] && { printf '%s\n' "$line" >> "$log" 2>/dev/null || true; return 0; }
  fi
  # DEGRADED ROW — and it SAYS SO. A jq-less box still has to leave evidence, because the whole
  # inference above turns on "no row ⇒ not from this tree"; a silent no-op here would manufacture
  # exactly the false conviction this file exists to prevent. `degraded:true` keeps a consumer from
  # reading a scrubbed field as a faithful one.
  printf '{"ts":"%s","surface":"%s","backend":"%s","caller":"%s","pid":%s,"ppid":%s,"ppid_comm":"%s","chain":"%s","ancestry":"%s","pane":"%s","cwd":"%s","detail":"%s","degraded":true}\n' \
    "$(_cc_spawn_scrub "$ts")" "$(_cc_spawn_scrub "$surface")" "$(_cc_spawn_scrub "$backend")" \
    "$(_cc_spawn_scrub "$self")" "$$" "$PPID" "$(_cc_spawn_scrub "$ppid_comm")" \
    "$(_cc_spawn_scrub "$chain")" "$(_cc_spawn_scrub "$ancestry")" "$(_cc_spawn_scrub "$pane")" \
    "$(_cc_spawn_scrub "$cwd")" "$(_cc_spawn_scrub "$detail")" \
    >> "$log" 2>/dev/null || true
  return 0
}

# ── HOW CALL SITES FIND THIS FILE (inlined at each site, deliberately not a helper here) ───────
# A resolver that lives INSIDE the library cannot bootstrap the library, so every site inlines the
# same loop. The ORDER is the load-bearing part:
#
#   1. the CALLING script's symlink-resolved sibling — ~/.claude/{bin,scripts,hooks}/* are per-file
#      symlinks into the checkout, so this reaches the repo's own scripts/lib/ and the logger goes
#      live the moment the file does
#   2. $CLAUDE_CONFIG_DIR/scripts/lib/…      3. ${HOME:-}/.claude/scripts/lib/…
#
# A $CLAUDE_CONFIG_DIR-FIRST order would find nothing until the next deploy re-globs — the
# deployed-layer-bootstrap-circle, verified live in 64a7d1fa. And `${HOME:-}`, never bare `$HOME`:
# bash expands the ENTIRE for-list before the loop body runs, so under `set -u` a bare $HOME aborts
# the whole calling script even when candidate 1 resolves. That is not hypothetical — it shipped
# here for one revision and killed `kitty-split-launch.sh --self-retire` outright, which is the
# add-on failing wider than itself (memory `addon-failure-exceeds-its-blast-radius`).

# ── THE CHAIN RELAY, PUSHED AT SOURCE TIME AND NOT AT WRITE TIME ───────────────────────────────
# A script that sources this library joins the chain even if it never writes a row itself, and that
# is the case that matters rather than an edge: handoff-fire's DEFAULT surface (split) does not
# launch anything directly — it shells out to `it2-kitty session split`, which owns the primitive
# and writes the row. Pushing the name only when a row is written would leave that row's chain
# reading `it2-kitty` alone, i.e. the single most common spawn on this box would be the one whose
# origin the log cannot name — the exact blindness this file exists to remove.
#
# Idempotent per process: `set -u`-safe, and a double `source` in one shell cannot double-append.
# The sentinel is the resolved chain itself, so a re-source after a legitimate `exec` into another
# instrumented script still appends (different $0), while a repeat source of the same file does not.
#
# ⚠ THE CHAIN DOES NOT CROSS A PANE BOUNDARY, and that is a property to rely on rather than a gap.
# `kitty @ launch` and iTerm2's AppleScript both spawn the new surface from the TERMINAL's process
# and environment, not the caller's — nothing here is passed through `--env` — so a fired pane
# starts with CC_SPAWN_CHAIN unset and builds its own. A chain is therefore "who, inside ONE
# invocation, delegated down to the primitive", never "every ancestor pane back to boot". The
# opposite assumption is a live trap elsewhere in this repo: a var a launcher DOES `--env` into a
# pane is inherited by every descendant, so its non-emptiness proves nothing about provenance
# (memory `second-transport-makes-an-e2e-ambient`). Bounded anyway — a loop that re-sources cannot
# grow the field without limit, and a truncated head reads `…>` so a consumer can see it was cut.
_cc_spawn_chain_push() { # $1=name to append
  local n="${1:-?}" c max="${CC_SPAWN_CHAIN_MAX:-8}" trimmed=0
  if [ -z "${CC_SPAWN_CHAIN_SELF+set}" ] || [ "${CC_SPAWN_CHAIN_SELF:-}" != "$n" ]; then
    c="${CC_SPAWN_CHAIN:+$CC_SPAWN_CHAIN>}$n"
    c="${c#…>}"   # drop any previous truncation marker before re-counting
    # Keep the LAST $max segments: the ones nearest the primitive are what name who issued it,
    # which is the question this field answers.
    while [ "$(printf '%s\n' "$c" | tr '>' '\n' | wc -l | tr -d ' ')" -gt "$max" ]; do
      c="${c#*>}"; trimmed=1
    done
    [ "$trimmed" = 1 ] && c="…>$c"
    CC_SPAWN_CHAIN="$c"
    CC_SPAWN_CHAIN_SELF="$n"
    export CC_SPAWN_CHAIN CC_SPAWN_CHAIN_SELF
  fi
}

# ── CLI MODE — for a spawn site that is not a bash script ──────────────────────────────────────
#     pane-spawn-log.sh log <surface> <backend> <pane> <cwd> [detail]
# bin/kitty-pane-menu is python3 and creates a real OS window (`detach-window` with no
# --target-tab), so it needs a row for the same reason every bash site does: coverage is what makes
# "no row ⇒ not from this tree" a sound inference, and a python exemption would silently reintroduce
# the ambiguity. The caller exports CC_SPAWN_CALLER so the row is attributed to IT, not to this file.
#
# The `return`-vs-`exit` guard: `${BASH_SOURCE[0]}` equals `$0` only when this file is EXECUTED, so a
# `source` never falls into the dispatch. Sourced ⇒ push the caller's name and stop here.
if [ "${BASH_SOURCE[0]:-}" != "${0:-}" ]; then
  _cc_spawn_chain_push "${CC_SPAWN_CALLER:-${0##*/}}"
  # Reachable ONLY when sourced — the branch this guard selects — and shellcheck analyses the file
  # as a script, so it cannot see the `source` caller. (The explanation goes ABOVE the directive:
  # a shellcheck directive comment must be ONE line, and a wrapped second line parses as a second,
  # malformed directive that turns two info findings into two errors.)
  # shellcheck disable=SC2317
  return 0 2>/dev/null || :
else
  _cc_spawn_chain_push "${CC_SPAWN_CALLER:-${0##*/}}"
  case "${1:-}" in
    log) shift; cc_log_pane_spawn "$@"; exit 0 ;;
    "")  printf 'usage: pane-spawn-log.sh log <surface> <backend> <pane> <cwd> [detail]\n' >&2; exit 64 ;;
    *)   printf 'pane-spawn-log.sh: unknown verb %s\n' "${1:-}" >&2; exit 64 ;;
  esac
fi
