#!/bin/bash
# lr-predicate.sh — the bash face of lr_predicate.py. ONE python fork, for bash callers only.
#
# `bin/cc-limited` imports the module IN-PROCESS and must never come through here: the whole point
# of the census being one process is that it does not pay a fork per hit (the shipped --locate pays
# python x3 + jq x37 per hit and takes 35.5 s over the fleet). This file exists for the callers that
# are shell and will stay shell — lr-reset-poller.sh, lr-lib.sh, lr-fleet.sh's --slow-scan path.
#
# Every subcommand prints ONE line of compact JSON on stdout and nothing else, so a caller can pipe
# it to jq or read one field with a second fork. Exit 0 means "a verdict was computed", including
# the verdict `{"limit":false,"kind":null,...}` — which is the honest answer for an ordinary
# assistant turn. A non-zero exit means the PREDICATE could not run, never "not a limit": those two
# must stay distinguishable, because one says retry and the other says proceed.
set -uo pipefail

_LRP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LRP_PY="${LR_PREDICATE_PY:-$_LRP_DIR/lr_predicate.py}"
# Resolved from BASH_SOURCE, not from $0: through the ~/.claude per-file symlink farm $0's dirname
# is ~/.claude/scripts/limit-recover, and a sibling that has no symlink yet is simply absent there.
# BASH_SOURCE gives the path this file was READ from, which is the one its sibling sits beside.

_lrp_usage() {
  cat >&2 <<'EOF'
usage: lr-predicate.sh <subcommand>
  classify-text "<text>" [error] [apiErrorStatus] [timestamp]
        T2 ALONE. For a caller that ALREADY established the envelope — in practice a reader of
        hooks/stop-failure-marker.sh's rows, which key on the structured `error` field and store
        `last_assistant_message`. Pass that row's `error` back in as argument 2 and this is a full
        classification. Omit it and MEMBERSHIP is decided by the text, which is the read the
        envelope gate exists to forbid. Never point this at a raw transcript record.
  classify-record
        One transcript JSONL record on stdin. The full three-tier classification.
  classify-tail <path>
        The last LR_TAIL_BYTES (default 131072) of a transcript, classified on its LAST assistant
        record. 6 of 77 capped sessions span two cap classes; the first record is not the answer.
EOF
}

_lrp_run() { # stdin -> the module, $@ -> the python argv
  /usr/bin/python3 -c '
import json, sys, os
sys.path.insert(0, os.environ["LRP_DIR"])
import lr_predicate as P
mode = sys.argv[1]
if mode == "classify-text":
    text = sys.argv[2]
    err = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "" else None
    sta = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != "" else None
    ts  = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "" else None
    out = P.classify_text(text, error=err, api_error_status=sta, ts=ts)
elif mode == "classify-record":
    raw = sys.stdin.read()
    try:
        rec = json.loads(raw)
    except ValueError as exc:
        sys.stderr.write("lr-predicate: stdin is not one JSON record: %s\n" % exc)
        sys.exit(3)
    out = P.classify_record(rec)
elif mode == "classify-tail":
    out = P.classify_tail(sys.stdin.buffer.read())
else:
    sys.stderr.write("lr-predicate: unknown subcommand %r\n" % mode)
    sys.exit(2)
print(json.dumps(out, separators=(",", ":"), sort_keys=True))
' "$@"
}

_lrp_main() {
  local sub="${1:-}"
  [ -f "$_LRP_PY" ] || {
    # The module is what this file IS. Absent, it cannot answer, and saying "not a limit" here
    # would silently un-park every capped session in the fleet.
    printf 'lr-predicate: module not found at %s\n' "$_LRP_PY" >&2
    return 4
  }
  LRP_DIR="$(dirname "$_LRP_PY")"; export LRP_DIR
  case "$sub" in
    classify-text)
      [ "$#" -ge 2 ] || { _lrp_usage; return 2; }
      shift
      _lrp_run classify-text "$1" "${2:-}" "${3:-}" "${4:-}" </dev/null
      ;;
    classify-record)
      _lrp_run classify-record
      ;;
    classify-tail)
      [ "$#" -ge 2 ] || { _lrp_usage; return 2; }
      [ -f "$2" ] || { printf 'lr-predicate: no such transcript: %s\n' "$2" >&2; return 4; }
      tail -c "${LR_TAIL_BYTES:-131072}" "$2" | _lrp_run classify-tail
      ;;
    -h|--help|help) _lrp_usage; return 0 ;;
    *) _lrp_usage; return 2 ;;
  esac
}

# Sourceable as well as executable: a caller that already pays for a bash process should not fork
# another one just to reach _lrp_main.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  _lrp_main "$@"
fi
