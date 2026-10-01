# C2 addendum: three restart findings from the lead (pane 4), verified live 2026-10-01 14:00-14:20

Relayed by the W2 lead from a peer message of the restart lead. These bind any restore design.

1. **`kitty @ send-text` lands as a paste in Claude Code.** Its trailing `\r` becomes a newline inside
   the composer, not a submit; 31 recovery prompts sat unsent. A restore must send the text, then a
   separate `kitten @ send-key enter`. The auto-mode classifier refuses an agent doing that into other
   sessions (category "Remote Shell Writes"), so the submit step needs the operator or a sanctioned
   launcher arm. Design implication: deliver the recovery nudge **at launch** (an initial prompt passed
   to `claude --resume <sid> "<prompt>"` by the launcher, or a SessionStart hook that injects it as
   context) rather than by typing into a live pane afterwards.
2. **Layout preference changed: each window is ONE ROW of panes, not a 2x2 grid.**
   `kitten @ set-enabled-layouts --match id:<tab> horizontal splits stack` then `goto-layout horizontal`
   gives equal full-height columns. Rotating a split tree on a window on another Desktop is
   unverifiable, because screenshots there show the last drawn frame.
3. **A per-window screenshot works offscreen:** CGWindowListCopyWindowInfo for the window ids (Swift),
   then `screencapture -x -o -l<id>`. Treat it as a possibly stale frame for windows on other
   Desktops; `kitten @ get-text` is live.
