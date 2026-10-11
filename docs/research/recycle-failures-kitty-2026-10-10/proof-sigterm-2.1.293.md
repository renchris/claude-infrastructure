# Proof: SIGTERM at rest is a safe exit actuator (fix 10 gate), Claude Code 2.1.293, 2026-10-11

**Verdict: PASS on all four conditions the report's fix 10 names.** Run from the build session in
scratch kitty tabs it created and closed itself (windows 239 and 240); no other pane was touched.

## Setup

- A fresh tab ran `zsh -l -i -c 'claude --model sonnet "<nonce> … run sleep 1800 in the background, reply OK"'`,
  so the real launcher wrapped claude in `bin/cc-close-attrib` (binary `~/.claude-293`).
- The session reached rest (last assistant record `end_turn`, then `stop_hook_summary`, `turn_duration`)
  with one background shell running (`zsh -c … sleep 1800`, a child of the claude pid).
- A successor was staged for the pane's tty with `lib/pane-successor.sh` `cc_pane_successor_stage`: a
  one-line `.cmd` that writes `/tmp/sigterm-proof/successor-ran`, and a meta whose watcher was a live
  `sleep 300`.
- Teardown markers were written in `bin/cc-teardown write_teardown_marker`'s shape (sid key and pid
  key, `mode:"recycle"`).
- The claude pid was pinned by `ps -o lstart=` and sent one `kill -TERM`.

## Results (window 240, session 844993db, claude pid 74838, tty ttys046)

| Condition | Observed |
|---|---|
| Process exits | gone within ~1 s; close-record `exit_code:143`, `signal:"15"` |
| Transcript intact | 62 → 67 records, every line parses (`jq -c .`) — the shutdown appended, nothing truncated |
| Background shell stops | the `zsh -c … sleep 1800` child was gone 3 s later |
| Staged successor claimed and run | `ttys046.cmd` renamed to `ttys046.claimed.74325`; close-record `successor_claim` names it; the successor wrote `SUCCESSOR-RAN tty=/dev/ttys046 at 2026-10-11T04:40:37Z` |
| Not classified as a crash | `hooks/lead-crash-watchdog.sh --classify <sid> <pid> <epoch>` ⇒ `RECYCLE deliberate-teardown` |

The pane printed CC's own "Resume this session with: claude --resume …" banner, then the successor
ran in the same tty: the signal path is the same `shutdown()` as `/exit`, as the binary scan predicted.

## The first run's miss was the harness, and it is a contract worth knowing

Window 239 gave the same four results except that the successor was **not** claimed. Tracing
`cc_pane_successor_take` showed why: the meta's `watcher_lstart` was written in local time
(`Sat 10 Oct 23:38:21 2026`), while the lib compares against `TZ=UTC LC_ALL=C ps -o lstart=`
(`Sun Oct 11 04:38:21 2026`). The take correctly refused (fails safe). A producer must write the
lstart in that UTC/C form, which `handoff-fire.sh`'s own stager does.

## Consumers on the signal path

- `bin/cc-close-attrib` claims on any exit code (`_cca_take_successor || true`), so 143 is fine.
- `bin/reso-resume-one` closes the pane on rc 0 only when no recycle is pending
  (`rr_close_on_clean_exit`, `cc_pane_recycle_pending`), and then claims the stage; a 143 skips the
  close arm entirely.
- `scripts/limit-recover/lr-fire-resume.sh` claims whenever stdin is a tty, whatever the rc.
