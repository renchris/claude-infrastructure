#!/usr/bin/env bash
# osa.sh — osa_bounded: run osascript under a wall-clock bound. Source, don't execute.
#
# WHY THIS EXISTS. An `osascript` call is an AppleEvent into another application, and an AppleEvent
# has no timeout of its own: if the target app (iTerm2, Dia, System Events, NotificationCenter) is
# wedged, blocked on its own modal, or merely paging under load, the call does not fail — it waits,
# for as long as the app takes, which on the machine-wide iTerm2/AppleEvent wedge of 2026-07-26 meant
# forever. Every caller in this repo treats its osascript as best-effort (`|| true`, `2>/dev/null`),
# so a CUT costs at most one notification, one window activation, one clipboard copy. A HANG costs
# the whole hook, launchd job, or crash handler that made the call. The asymmetry is the argument.
#
# CONTRACT
#   osa_bounded osascript -e '…'      → runs bounded; exit status is the command's, or timeout(1)'s
#                                       124 when the bound was reached.
#   CC_OSA_TIMEOUT_S    seconds (default 10)
#   CC_OSA_TIMEOUT_BIN  explicit timeout binary. SET-BUT-EMPTY means UNBOUNDED, honored verbatim:
#                       `${VAR+set}` is used rather than `${VAR:-}` precisely so that
#                       `CC_OSA_TIMEOUT_BIN= some-script` can genuinely turn the bound OFF. A seam
#                       that cannot turn a thing off is not a seam — and a test that cannot run the
#                       unbounded path cannot prove the bounded one differs from it.
#
# DEGRADATION. No timeout(1) anywhere ⇒ run UNBOUNDED rather than lose the call. hooks and launchd
# jobs run without Homebrew on PATH, which is where coreutils installs both `timeout` and `gtimeout`,
# so the absolute paths are probed as well as PATH. Failing closed here would silently delete every
# notification on any machine without coreutils — a worse default than the hang this bounds, because
# it is permanent rather than occasional.
#
# This mirrors the local helper in hooks/lead-crash-watchdog.sh (LCW_OSA_TIMEOUT_S / lcw_osa), which
# keeps its own copy on purpose: it is a SessionStart hook that must not depend on a lib file being
# deployed before it can spawn a watchdog.

CC_OSA_TIMEOUT_S="${CC_OSA_TIMEOUT_S:-10}"

if [ -n "${CC_OSA_TIMEOUT_BIN+set}" ]; then
  # Set — including set to EMPTY — is honored verbatim. Empty ⇒ unbounded.
  CC_OSA_TB="${CC_OSA_TIMEOUT_BIN}"
else
  CC_OSA_TB=""
  for _cc_osa_c in "$(command -v timeout 2>/dev/null || true)" \
                   "$(command -v gtimeout 2>/dev/null || true)" \
                   /usr/bin/timeout /opt/homebrew/bin/timeout /usr/local/bin/timeout \
                   /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_cc_osa_c" ] && [ -x "$_cc_osa_c" ] && { CC_OSA_TB="$_cc_osa_c"; break; }
  done
  unset _cc_osa_c
fi

# -k 3: if the AppleEvent ignores SIGTERM (a wedged app's event loop often does), follow with SIGKILL
# 3s later, so the bound is a bound rather than a request.
osa_bounded() {
  if [ -z "$CC_OSA_TB" ] || [ ! -x "$CC_OSA_TB" ]; then "$@"; return $?; fi
  "$CC_OSA_TB" -k 3 "$CC_OSA_TIMEOUT_S" "$@"
}
