#!/bin/bash
# quota-kind.sh — the ONE answer to "which claude-accounts quota meter does a spawn of THIS MODEL
# draw on?", shared by bin/cc-route and scripts/handoff-fire.sh.
#
#   quota_kind_for_model <model-id>   → prints `fable` or `general`
#
# Why one helper: cc-route used to pick the meter by SLOT (lead → general, judgment-dense → fable)
# while handoff-fire keyed it on the MODEL. The two agree only while roles.lead_default is an Opus id;
# point the SSOT's lead_default at a Fable id and cc-route ranked a Fable spawn on the general meter,
# routing it onto an account whose Fable sub-cap was already spent. The meter follows the model that
# actually runs, so the model is the only key.
#
# PREFIX match, never an exact id: every Fable 5.x id (claude-fable-5, claude-fable-5-1, …) draws on
# the Fable sub-cap, and an exact list would silently un-match the next point release (the same
# reason handoff-fire.sh's recycle guard uses the prefix).
quota_kind_for_model() { # <model-id>
  case "${1:-}" in
    claude-fable-5*) echo fable ;;
    *)               echo general ;;
  esac
}
