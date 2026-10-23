# shellcheck shell=bash
# watchdog-registration.sh — the one reading of lead-crash-watchdog's `registered` line.
#
# hooks/lead-crash-watchdog.sh writes, at every SessionStart:
#   [YYYY-mm-dd HH:MM:SS] registered session=<sid> pid=<pid> tty=<tty|none> pane=<id|none>[ teammate=<agent-id>]
# The trailing ` teammate=<agent-id>` arrived in b6bf10c0c (2026-09-30), and the readers that anchor
# on `pane=N` at the END of the line never followed: bin/cc-pane-close (identity, moved_live) and
# bin/cc-husk-sweep (watchdog_sid, lineage_of) read every Agent-Teams member's registration as
# absent, so pane 144 was refused "no session registration" on every tick for hours
# (docs/research/husk-panes-2026-10-22/round2-2026-10-23/, RC2). A reader pipes the log through
# wd_reg_norm and keeps its end-of-line anchor; lineage_of's Python reads the file itself and carries
# the same optional group in its regex (`(\s+teammate=\S+)?`), pinned by tests/cc-husk-sweep.bats.
#
# Sourced, side-effect-free, bash 3.2 safe (launchd runs the drainer under /bin/bash).

# stdin → stdout, each line with its optional trailing ` teammate=<id>` (and trailing blanks) removed.
wd_reg_norm() { sed -E 's/ teammate=[^ ]*[[:space:]]*$//'; }
