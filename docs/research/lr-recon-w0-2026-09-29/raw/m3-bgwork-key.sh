#!/bin/bash
# emulate pane_bgwork_key's decision on a captured screen: dialog? then KEEP index
# shellcheck source=/dev/null  # the repo root is a runtime argument
. "$1/hooks/lib/pane-modal.sh"
f="$2"
if pane_bgwork_dialog < "$f"; then d=yes; else d=no; fi
k="$(pane_bgwork_choice < "$f")"; rc=$?
echo "screen=$(basename "$f") dialog=$d choice_rc=$rc key=${k:-<none>} KEEP_LABEL='$CC_MODAL_BGWORK_KEEP'"
