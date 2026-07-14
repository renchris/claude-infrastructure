#!/bin/bash
# pane-id-lint — catch TRUNCATED pane UUIDs in the docs corpus before they reach a brief.
#
# WHY THIS IS A GREP AND NOT A RULE IN A TEMPLATE (2026-07-14, audit §3g):
# A successor's mandated first action — announcing its own pane so the orchestrator can
# re-address the role — HARD-FAILED (cc-notify exit 3) because the brief carried an 8-char
# prefix (`99261468`) instead of the full uuid. `cc-notify` resolves only {registered name |
# FULL uuid}, and the name registry is empty until P8 lands, so two gaps composed to break the
# one send a succession cannot lose.
#
# The truncation did NOT originate in the brief. It entered at DOC-AUTHORING time — the
# orchestrator wrote "orchestrator pane 99261468" into the plan/proposal, and every downstream
# brief faithfully copied it. THE CORPUS IS THE COPY-SOURCE. A prose rule in a template cannot
# fix that: the author already knew the full uuid and truncated it anyway, for readability.
# So the rule is mechanical, per this repo's own law — prose rules get violated; greps don't.
#
# THE RULE (two shapes, because the two failure modes want opposite things):
#   * An OPERATIONAL address (a send target) -> a ROLE token, e.g. `<orchestrator>`, resolved at
#     SEND-TIME. Panes are epoch-specific: any uuid written into a doc is stale the moment its
#     session recycles.
#   * A HISTORICAL reference (a status-log fact) -> the FULL uuid, marked as a past fact.
#     Full-but-stale degrades GRACEFULLY (cc-notify -> loud "unreachable" + mailbox fallback,
#     recoverable). Truncated hard-fails exit 3 — unresolvable, and it cannot even be mailboxed.
#     A stale full uuid is strictly safer than a truncated one.
#
# Flags an 8-hex token with no lowercase (a truncated UPPERCASE pane uuid — session/transcript
# ids are lowercase, a different namespace, and are NOT flagged) that is not followed by `-`,
# on a line that is talking about addressing. Intentional counter-examples (docs that QUOTE the
# bad form to teach it) opt out with a `pane-id-lint:allow` marker on the line.
#
# Exit: 0 = clean · 1 = violations found
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="${1:-$ROOT/docs}"

# NOTE: deliberately NO keyword filter. A first cut only flagged lines that themselves said
# "pane"/"orchestrator"/etc., and it MISSED 4 real violations whose context word sat on the
# PREVIOUS line — a detector with false negatives is the D9 bug in miniature. Scanning every
# bare token costs nothing: across the whole corpus this matches exactly two distinct tokens and
# zero dates/counts, so the precision was never worth the blind spot.
viol=0
while IFS= read -r hit; do
  case "$hit" in *pane-id-lint:allow*) continue ;; esac
  printf '  %s\n' "$hit"
  viol=$((viol + 1))
done < <(
  grep -rnE '(^|[^-0-9A-Za-z])[0-9A-F]{8}([^-0-9A-Za-z]|$)' "$SCAN" 2>/dev/null \
    | grep -vE '[0-9A-F]{8}-' || true
)

if [ "$viol" -gt 0 ]; then
  echo "pane-id-lint: ⛔ $viol TRUNCATED pane id(s) above — each is a landmine for the next successor."
  echo "  Fix: an operational address -> a ROLE token (<orchestrator>, resolved at send-time);"
  echo "       a historical reference -> the FULL uuid, marked as a past fact, not a send target."
  echo "  Intentional counter-example? add  pane-id-lint:allow  to that line."
  exit 1
fi
echo "pane-id-lint: clean — no truncated pane ids in $SCAN"
