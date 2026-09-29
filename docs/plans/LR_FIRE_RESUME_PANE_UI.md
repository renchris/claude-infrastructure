---
status: complete
---

# LR_FIRE_RESUME_PANE_UI — the pane cc-lr relaunches leave broken

Scope (frozen): the three defects below are fixed, each covered by a bats test that fails on the
pre-fix code, landed via the project /ship, and converged live.

Scope (grown): +the same byte-transparent relay in `bin/reso-resume-one` (the boot-resume launcher
runs the same Tcl 8.5 expect relay, so every emoji in a boot-resumed pane was mangled the same way;
its patterns are all ASCII, so the fix there is the two-channel block and the drain call site).

## Result — DONE 2026-09-29

Landed on main as `e98cccb1c` (this plan), `9cbe10795` (probe window) and `c692c4035` (tty status
to the run log and inbox, byte-transparent relay in both launchers); converged live, with the live
blobs identical to trunk. `tests/lr-fire-resume-pane-ui.bats` has 7 cases, and 5 of them fail on the
pre-fix tree. The land shed its smoke at load 210, so the suite was re-run on the landed tree:
`1..7`, 0 failures. Also green before the land: `lr-fire-resume-submit`, `lr-submit-cr-landing`,
`lr-fire-resume-reply-drain`, `-close-attrib`, `-direct-invocation`, `-model-ssot`,
`lr-resume-answer-width`, `reso-resume-one`, `cc-tui`, `handoff-recycle-expect-probe`,
`lr-handoff-launcher-quoting`, `cc-lr`, `cc-lr-front`.

**Learnings.** A tail bound sized in bytes breaks as soon as one record outgrows it: bound the
window by the question it answers (reach back to `t0`), not by a size. A mojibake that spares BMP
characters and mangles only astral ones points at a UCS-2 runtime (Tcl 8.5), not at a locale.

Reported 2026-09-28 ~19:16-19:24 CDT with three screenshots of panes relaunched by `cc-lr upgrade`
(runs `ddd154a9-20260929T001507Z`, `46bc0436-20260929T001856Z`, `e0487c53-20260929T002302Z`). The
relaunches worked: each session resumed, received its prompt and answered it. The pane was broken.

## Phase 0 — execution locus

- **Wave 1 (all three fixes): L, lead-inline.** Defects 1 and 3 both edit the one `expect -c '…'`
  program in `scripts/limit-recover/lr-fire-resume.sh`, a single-quoted block where one stray
  apostrophe or unbalanced brace breaks the whole file, so it needs one owner. Defect 2 is about 60
  lines in `lr-submit-probe.sh`. The combined diff is too small to pay back a teammate's brief and merge.
- **Lead context budget:** a single session; recycle at about 60% if the land or the converge stalls.
- **Hands-off files** (pane 930, `feat/close-resume-custody`): `lr-upgrade.sh`, `handoff-fire.sh`,
  `lr-reset-poller.sh`, `boot-resume-launch.sh`, `hooks/operator-readout.sh`, `bin/cc-resume-debt`.
  None of the three fixes needs them.

## Defect 1 — TTY overprint

`lr-fire-resume.sh` is an expect wrapper that owns the pane tty while Claude Code's TUI paints on it.
Its ~15 `send_user` status lines wrote raw text over the TUI. That text landed inside the composer
box, wrapped mid-word, and stayed on screen after redraws. `cc-tui.bats` already carries a
consumer-side workaround for exactly this torn frame: one Ctrl-L, then a re-read.

**Rule:** after `spawn`, nothing writes to the pane tty except the session itself.
- Every status line becomes `lr_say`, which appends to `$LR_RUN_DIR/lr-fire-resume.log`, or to
  `~/.reso/limit-recover/fire-resume/<sid>.log` on a by-hand run with no run dir.
- A verdict that needs a human (CR withheld over a menu, READY never seen, selector unconfirmed,
  NOT SUBMITTED) also goes to the session's inbox via `cc-notify <sid>`. It is run in the
  background with all three standard streams on `/dev/null`, so it cannot paint either.
- Errors before the spawn (argument validation, tombstone, gate, binary resolution) stay on stderr:
  at that point the pane is a plain shell.

## Defect 2 — false "✗ NOT SUBMITTED"

**Root cause, measured:** the probe reads a fixed 400 KB tail, and on 2.1.284 the prompt's own
user record is buried under more than that within half a second of landing. Run ddd154a9: the
record is at 00:16:05.219Z; at 00:16:05.737Z Claude Code appends an `instructions` attachment of
**335,382 bytes** and a `prompt_snapshot` of **67,329 bytes**, then a second snapshot of 67,413
bytes at 00:16:10. After the record there are 490,982 bytes: 549,998 for run 46bc0436 and 567,616
for run e0487c53. Against the real transcripts, all three runs read `none` at the default window and
`submitted <ts>` with the window unbounded. The token, the config dir and the record shape were
all correct. The other candidates in the brief were ruled out: the token in the prompt is
byte-identical to `LR_SUBMIT_TOKEN`, the transcript sits in the account the relaunch used, and the
record is an ordinary `type:"user"` with string content.

**Fix:** the window grows until it reaches back past `t0`: it widens ×4 until the oldest timestamped
record parsed is at or before `t0`, or the whole file has been read. The question stays
tail-scoped, as the probe's header requires. The stopping rule makes the tail a sufficient window
rather than a guess.

## Defect 3 — mojibake (`ð¬ peer mail`)

**Root cause, measured: not the locale.** The producer of the line is
`hooks/mailbox-drain.sh:741` (its `systemMessage`), and its bytes are correct. The corruption
happens in the relay: `/usr/bin/expect` is 5.45 on Tcl 8.5.9, which cannot represent a 4-byte
UTF-8 sequence (TCL_UTF_MAX=3). It decodes each byte of 📬 (`f0 9f 93 ac`) as its own Latin-1
character and re-encodes them, so `ð` + `U+009F` + `U+0093` + `¬` reaches the terminal. BMP
characters survive, which is why `◀` in the same line rendered correctly. Measured identically under
a UTF-8 locale, under `LC_ALL=C` and under `env -i` (all report `encoding system` = `utf-8` on this
box). So every astral emoji the TUI paints (🔧 📦 🚀 👤 📬 …) was mangled for the whole life of a
session resumed this way, through both the pre-`interact` relay and `interact` itself.

**Fix, at the relay:** the spawn channel and `$user_spawn_id` are set to `-encoding binary`, so
bytes pass through untouched in both directions (measured byte-exact through a real pty). Anything
compared against or sent into that byte stream is converted to the same view with `encoding
convertto [encoding system]`: the LR_RE_* patterns, the typed prompt, and the drained keystrokes.
The system encoding is the one Tcl decoded them with, so the conversion restores the original bytes.

**Residual, stated rather than hidden:** a prompt that itself contains a 4-byte character is
still corrupted, because Tcl 8.5 has already mangled it while reading `env(LR_PROMPT)`. The
behaviour there is unchanged from before, and every prompt the fleet types today is ASCII.
