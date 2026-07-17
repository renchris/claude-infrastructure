#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && ok || bad` reporter idiom is
#                              intentional — ok()/bad() end in printf (return 0), never falling to `|| C`.
# kimi-frontend-ab.sh — the burn-in A/B the tokenomics verdict requires BEFORE relying on Kimi K3
# for the frontend-design gap: "a small frontend-design A/B so the operator can confirm Kimi K3 >
# Fable 5 on THEIR tasks before relying on it — cheap, metered, real."
#
# METHOD (fair · cheap · real):
#   * FAIR  — both arms get the IDENTICAL brief and produce the same artifact (one self-contained
#             index.html, inline CSS, zero deps), so the only variable is the MODEL's design taste.
#   * CHEAP — one single-shot headless (`claude -p`) generation per arm. The Kimi arm is ~pennies of
#             metered spend (~$3/$15 per MTok; a page is a few K tokens); the Fable arm rides the plan.
#   * REAL  — the outputs are actual renderable pages you open side-by-side and score BLIND.
#
#   Arm A = Fable 5   via  claude-fable      (the incumbent this must beat)
#   Arm B = Kimi K3   via  claude-kimi       (the metered challenger; needs a wired key)
#
# USAGE:
#   kimi-frontend-ab.sh new [--brief-file F | --brief-text "..."]   Scaffold a run dir + rubric +
#                                                                   the two exact commands. (Default.)
#   kimi-frontend-ab.sh run <run-dir>                               Execute BOTH arms via `claude -p`
#                                                                   (checks the Kimi key; warns metered).
#   kimi-frontend-ab.sh rubric                                      Print the blind scoring rubric.
#   kimi-frontend-ab.sh selftest                                    Internal RED-proof checks.
#
# Run root: $KIMI_BURNIN_DIR (default $HOME/.config/kimi/burnin) — outside the repo and the Max mirror.
# Effort: Arm A rides claude-fable's default (high); Arm B rides claude-kimi's default (max). Both are
#   each model's sensible frontend default; override the printed commands if you want strict parity.

set -euo pipefail

BURNIN_DIR="${KIMI_BURNIN_DIR:-$HOME/.config/kimi/burnin}"
FABLE_LAUNCHER="${KIMI_AB_FABLE:-claude-fable}"
KIMI_LAUNCHER="${KIMI_AB_KIMI:-claude-kimi}"

_default_brief() {
  cat <<'EOF'
# Frontend-design brief (A/B burn-in)

Build a COMPLETE, self-contained `index.html` (all CSS inline in a <style> tag; NO external fonts,
frameworks, images, or JS libraries — a single file that renders offline) for:

**A SaaS pricing section** with three tiers — "Starter", "Pro" (highlighted as the recommended
plan), and "Enterprise". Each card shows a name, price, a short tagline, a 4–5 item feature list,
and a call-to-action button. Include a section heading and a monthly/annual toggle (visual only).

Design bar (this is a DESIGN-TASTE test — the reason for the A/B):
- Confident visual hierarchy; the "Pro" tier is clearly the hero without shouting.
- Deliberate spacing rhythm and alignment; nothing cramped or arbitrary.
- A restrained, cohesive color system with accessible contrast (WCAG AA).
- Responsive: graceful from 360px mobile to a wide desktop.
- Small, tasteful detail (hover states, a subtle accent) — no gradients-for-the-sake-of-it.

Output ONLY the full HTML document, ready to save as index.html and open in a browser.
EOF
}

_rubric() {
  cat <<'EOF'
# Blind scoring rubric — score EACH arm's rendered index.html, 1–5 per dimension, BEFORE you look
# at which arm is which. (Tip: have a second person, or a judge model, map A/B → labels.)
#
#   dimension                              A (___/5)   B (___/5)
#   ------------------------------------   ---------   ---------
#   visual hierarchy (Pro reads as hero)   [     ]     [     ]
#   spacing & alignment rhythm             [     ]     [     ]
#   color system & AA contrast             [     ]     [     ]
#   responsive 360px → wide                [     ]     [     ]
#   tasteful detail (hover/accent)         [     ]     [     ]
#   code cleanliness (semantic, no cruft)  [     ]     [     ]
#   "would I ship this?" (gut)             [     ]     [     ]
#   ------------------------------------   ---------   ---------
#   TOTAL                                  [  /35]     [  /35]
#
# VERDICT: Arm B (Kimi K3) must beat Arm A (Fable 5) by a clear margin (≥3 pts total, AND win
# "would I ship this?") to justify routing the frontend gap to metered Kimi. A tie or narrow win =
# stay on Fable for design; keep Kimi as the outage/limit hedge only. Record the outcome in memory
# (project-tokenomics-plan-swap-verdict) so the decision is durable.
EOF
}

_prompt_text() {  # the single-shot instruction wrapped around a brief file
  local brief="$1"
  printf 'Read this brief and produce the deliverable exactly as specified. Brief:\n\n'
  cat "$brief"
}

_cmd_new() {
  local brief_file="" brief_text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --brief-file) brief_file="${2:?--brief-file needs a path}"; shift 2 ;;
      --brief-text) brief_text="${2:?--brief-text needs a string}"; shift 2 ;;
      *) echo "unknown arg: $1" >&2; return 2 ;;
    esac
  done
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local run="$BURNIN_DIR/ab-$stamp"
  mkdir -p "$run/A-fable" "$run/B-kimi"
  if [ -n "$brief_file" ]; then cp "$brief_file" "$run/brief.md"
  elif [ -n "$brief_text" ]; then printf '%s\n' "$brief_text" > "$run/brief.md"
  else _default_brief > "$run/brief.md"; fi
  _rubric > "$run/SCORECARD.md"

  local pt; pt="$(_prompt_text "$run/brief.md")"
  # RUN.md carries the two EXACT commands (headless single-shot, output captured per arm).
  {
    echo "# A/B burn-in run — $stamp"
    echo
    echo "Brief: brief.md   ·   Scorecard: SCORECARD.md"
    echo
    echo "## Arm A — Fable 5 (incumbent)"
    echo '```bash'
    echo "cd '$run/A-fable' && $FABLE_LAUNCHER -p \"\$(cat '$run/brief.md')\" > index.html"
    echo '```'
    echo
    echo "## Arm B — Kimi K3 (metered challenger — your \$; ~pennies for one page)"
    echo '```bash'
    echo "cd '$run/B-kimi' && $KIMI_LAUNCHER -p \"\$(cat '$run/brief.md')\" > index.html"
    echo '```'
    echo
    echo "Then open both index.html side-by-side and fill SCORECARD.md BLIND. Or run:"
    echo "    $(basename "$0") run '$run'"
  } > "$run/RUN.md"

  echo "$run"
  echo "scaffolded ✓  — brief.md · SCORECARD.md · RUN.md · A-fable/ · B-kimi/" >&2
  echo "next: run both arms (see RUN.md) or '$(basename "$0") run $run'" >&2
  # silence the unused-var linter for the illustrative prompt text
  : "$pt"
}

_cmd_run() {
  local run="${1:?usage: run <run-dir>}"
  [ -f "$run/brief.md" ] || { echo "✗ no brief.md in $run — scaffold with 'new' first." >&2; return 1; }
  command -v "$FABLE_LAUNCHER" >/dev/null 2>&1 || { echo "✗ $FABLE_LAUNCHER not on PATH." >&2; return 1; }
  command -v "$KIMI_LAUNCHER"  >/dev/null 2>&1 || { echo "✗ $KIMI_LAUNCHER not on PATH." >&2; return 1; }
  # the Kimi arm needs a wired key (real metered spend) — verify + warn before spending.
  if ! "$KIMI_LAUNCHER" status 2>/dev/null | grep -q 'WIRED'; then
    echo "✗ Kimi key not wired — run '$KIMI_LAUNCHER set-key' first (Arm B would fail)." >&2; return 1
  fi
  echo "⚠️  Arm B (Kimi) is METERED — this spends your key (~pennies for one page). Ctrl-C to abort." >&2
  local prompt; prompt="$(cat "$run/brief.md")"
  echo "→ Arm A (Fable 5)…" >&2
  ( cd "$run/A-fable" && "$FABLE_LAUNCHER" -p "$prompt" > index.html ) && echo "  A-fable/index.html ✓" >&2
  echo "→ Arm B (Kimi K3, metered)…" >&2
  ( cd "$run/B-kimi"  && "$KIMI_LAUNCHER"  -p "$prompt" > index.html ) && echo "  B-kimi/index.html ✓"  >&2
  echo "done — open both index.html side-by-side and fill $run/SCORECARD.md BLIND." >&2
}

_cmd_selftest() {
  local fails=0 n=0
  ok()  { n=$((n+1)); printf '  ok %d - %s\n' "$n" "$1"; }
  bad() { n=$((n+1)); fails=$((fails+1)); printf '  NOT ok %d - %s\n' "$n" "$1"; }
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  export KIMI_BURNIN_DIR="$tmp/burnin"

  # ST-a: `new` scaffolds the full run dir with both arms + rubric + commands.
  local run; run="$(_cmd_new 2>/dev/null)"
  [ -d "$run/A-fable" ] && [ -d "$run/B-kimi" ] && ok "new scaffolds both arm dirs" || bad "arm dirs missing"
  [ -f "$run/brief.md" ] && [ -f "$run/SCORECARD.md" ] && [ -f "$run/RUN.md" ] && ok "brief + scorecard + run notes written" || bad "scaffold files missing"

  # ST-b: FAIRNESS — the SAME brief drives both arms (identical prompt, only the model differs).
  grep -Fq "$run/brief.md" "$run/RUN.md" && ok "both arms read the one shared brief (fair)" || bad "brief not shared across arms"

  # ST-c: the two commands invoke the RIGHT launchers (Fable incumbent vs Kimi challenger).
  grep -q "$FABLE_LAUNCHER -p" "$run/RUN.md" && ok "Arm A uses the Fable launcher" || bad "Arm A launcher wrong"
  grep -q "$KIMI_LAUNCHER -p"  "$run/RUN.md" && ok "Arm B uses the Kimi launcher"  || bad "Arm B launcher wrong"

  # ST-d: the scorecard is a genuine decision instrument (dimensions + a beat-margin verdict).
  grep -q 'visual hierarchy' "$run/SCORECARD.md" && grep -q 'would I ship' "$run/SCORECARD.md" && ok "scorecard has design dimensions" || bad "scorecard dimensions missing"
  grep -q 'beat Arm A' "$run/SCORECARD.md" && ok "scorecard states the beat-margin verdict rule" || bad "verdict rule missing"

  # ST-e: a custom brief is honored (operator's OWN task, per the verdict's 'THEIR tasks').
  local run2; run2="$(_cmd_new --brief-text 'my own component' 2>/dev/null)"
  grep -Fq 'my own component' "$run2/brief.md" && ok "custom --brief-text honored" || bad "custom brief ignored"

  # ST-f: run refuses cleanly when the Kimi key is not wired (no accidental spend / half-run).
  local out; out="$(KIMI_AB_KIMI=/bin/false _cmd_run "$run" 2>&1 || true)"
  # /bin/false lacks 'status'→'WIRED'; run must refuse before spending
  printf '%s' "$out" | grep -qiE 'not on PATH|not wired' && ok "run refuses without a wired key (no blind spend)" || bad "run did not guard the metered arm"

  printf '%s\n' "selftest: $((n - fails))/$n checks passed"
  [ "$fails" -eq 0 ]
}

case "${1:-new}" in
  new)      shift 2>/dev/null || true; _cmd_new "$@" ;;
  run)      shift; _cmd_run "$@" ;;
  rubric)   _rubric ;;
  selftest) _cmd_selftest ;;
  help|--help|-h) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "unknown command: $1 (try: new | run | rubric | selftest | help)" >&2; exit 2 ;;
esac
