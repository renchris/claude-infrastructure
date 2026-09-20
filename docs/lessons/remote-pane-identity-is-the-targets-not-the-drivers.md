# A terminal-identity verdict walked from the DRIVER's ancestry is the wrong subject for a REMOTE pane

**2026-09-20, limit-recover in-place recovery (LIMIT_RECOVER_100P § 10).** `handoff-fire.sh`'s remote recycle
form — "recycle pane P, which is not mine" — pinned its terminal verdict by running `bin/cc-in-kitty` on the
**driver's own process ancestry** (`pin_term_verdict_for_watcher`, `:1686`). That walk is the right instrument for
"which terminal am I in": it was built after inherited `KITTY_*` env made genuine iTerm2 panes look like kitty
(2026-08-05), and its DEFINITIVE-no is correct there. It is the wrong instrument for "which terminal owns pane P".
Any driver reparented away from kitty — a `nohup … &` whose Bash tool call has already returned, W1's `detach`
(`start_new_session`), the launchd poller (no kitty ancestor by construction) — walks to launchd without meeting
kitty, is judged "not kitty", gets `CC_TERM=iterm2` exported, and then asks iTerm2 about a kitty window id: empty,
"pane resolved to no tty", refused. Reproduced from an attached session: `cc-in-kitty` rc 0; rc 1 from a grandchild
whose parent exited first, with `KITTY_WINDOW_ID=198` and `KITTY_PID=73832` intact in its env.

**Population.** 0 of 9 detached- or daemon-driven in-place recoveries on record had ever passed this gate
(2026-09-10 ×3, 09-14 ×2, 09-19 ×4), each leaving a tombstoned husk until a later precheck moved the read before the
transplant — after which the fleet path refused every time instead. The only success was a foreground run from an
attached session. The tool's own "husk" census could not see the result either, because its predicate asked about
the SESSION ("did its last turn die at a limit?") while the operator was asking about the PANE ("can it do work?").

**The rule.** When an actuator acts on a pane it does not own, every identity question is about the TARGET: resolve
the pane's terminal by enumerating the pane (an integer id a live kitty socket lists ⇒ kitty; a UUID ⇒ iTerm2), and
keep the ancestry walk for self-operations only. Corollaries that fell out of the same incident:

- A resolver that collapses "cannot tell" into "absent" turns a transient into a terminal verdict. `as_tty`
  discards `as_tty_classified`'s rc 3; the remote pin read the empty string as "no tty". Three codes, never two.
- A liveness pin that compares ttys by EQUALITY is blind to a successor on an `expect`-nested pty; the sibling
  predicate one function away already walked ancestry. Two gates over one population must share the state model.
- A census keyed on a transcript's last word cannot see a live pane whose session moved on. Enumerate the panes
  (registry × live pid) and give the moved-but-still-open case its own state; "not blocked" and "recoverable" are
  not the only two answers.
- Before firing a detached or daemon driver at a path that types into a pane, run the path's read-only probe FROM
  that driver's process shape (setsid'd, orphaned, launchd) — a probe run from the attached session proves nothing
  about the shape the daemon will have.

Receipts: `docs/research/lr100p-2026-09-19/inplace-default-2026-09-20.md` (R3–R6). Fix: LIMIT_RECOVER_100P § 10 W8.
