#!/bin/bash
# T9 Q1 INSTRUMENT — a plain SYNCHRONOUS Stop hook. Its only job is to answer one question:
# does the harness run Stop hooks at all when the turn it is ending died with an API ERROR?
# It logs at START, never at exit (W0's rule: an exit-time log cannot tell "never started"
# from "started then reaped").
echo "$(date -u +%H:%M:%S) SYNC-STOP-FIRED pid=$$ arm=${T9_ARM:-unset}" >> "/private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-4236edc78a72/23a9a12e-c3c9-4672-b8a8-92e6831618e7/scratchpad/t9probe/stop.log"
cat >/dev/null 2>&1
exit 0
