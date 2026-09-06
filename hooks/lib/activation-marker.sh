# shellcheck shell=bash
# activation-marker.sh — the ONE predicate for "does this activation still need the operator?"
#
# THE DEFECT THIS FIXES (measured 2026-09-04, docs/research/activation-queue-audit-2026-09-04.md).
# `.done` was carrying two facts that have come apart:
#     (a) did the SCRIPT RUN            — what the marker is documented to mean
#     (b) is the WIRING COMPLETE        — what every consumer actually asks it
# An eleven-agent audit checked all eleven pending activations against live disk. TEN were already
# in effect — labels loaded, plists byte-identical to their SSOT, jobs at 696–3,261 runs — and were
# pending only because nobody touched a marker. So the queue reported ten phantom items, and worse,
# `cc-do` listed all ten as RUNNABLE. Two of them cause real harm if run: 36-start-latency-router
# re-creates the 2026-08-11 incident that killed every fire on the box, and 38-accounts-board's
# vehicle deletes the config-dir symlinks. The queue was not merely noisy; it was pointing at those.
#
# Neither available answer was right. Touching `.done` records a false provenance — the script did
# not run, and a future reader needs to be able to tell. Leaving it keeps the hazard live.
#
# SO: a THIRD state, `.superseded`, meaning "the effect this script installs is already in place;
# it does not need running, and it was never run." That is not a new idea in this file's world —
# activation-watch.sh:38-40 already ships `<name>.local` for the LIVE-ONLY class, described there as
# mirroring the `.done` convention. This mirrors it too.
#
# ONE PREDICATE, NOT SIX COPIES. Before this, `[ -f "$f.done" ]` was open-coded at six call sites
# across bin/cc-do, hooks/activation-watch.sh and hooks/operator-readout.sh. Six copies of a rule
# drift; the next state added would have to find all six again, and a missed one reads as "still
# pending" in exactly one surface — the silent-disagreement class this repo has been bitten by
# before (two auditors over one population disagreeing because only one modelled a by-design state).
#
# Consumers source this and call `activation_settled <script-path>`.

# activation_settled <path-to-activation-script>
#   rc 0 → settled: the operator has nothing to do for it (ran, or superseded, or declared local)
#   rc 1 → still owed
# `.local` is included deliberately: activation-watch.sh already treats it as an intentional
# exemption, and a file the operator has declared un-committable is not work they owe either.
activation_settled() {
  local f="${1:?activation_settled: need a script path}"
  [ -f "$f.done" ] || [ -f "$f.superseded" ] || [ -f "$f.local" ]
}

# activation_marker_kind <path-to-activation-script>
#   Prints which marker settled it — done | superseded | local | none. For rendering, never for
#   control flow: a caller that branches on the STRING re-creates the six-copies problem this file
#   exists to delete. Branch on activation_settled; print this.
activation_marker_kind() {
  local f="${1:?activation_marker_kind: need a script path}"
  if   [ -f "$f.done" ];       then printf 'done\n'
  elif [ -f "$f.superseded" ]; then printf 'superseded\n'
  elif [ -f "$f.local" ];      then printf 'local\n'
  else                              printf 'none\n'
  fi
}
