# Slot D: the composer junk in the resurrected pane (pid 57630)

Junk as reported: `^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c`, kitty's replies to XTVERSION (`CSI > q`),
the kitty keyboard flags query (`CSI ? u`) and DA1 (`CSI c`).

## Verdict

The junk is **tty-driver echo painted onto the screen**. It is not text that reached Claude Code's
composer as input. `bin/reso-resume-one` leaves the pane tty cooked, with `echo` and `echoctl` on, for
the whole pre-`interact` phase of its expect program. During that phase Claude Code's boot probe
queries the terminal. Kitty's replies land on the pane tty's input queue, and the line discipline
echoes each control byte as caret text (`ESC` shows as `^[`). The input bytes themselves are then
removed by the existing `lr-reply-drain`. The paint stays on screen, though: Ink diffs its frames and
believes those cells still hold what it drew.

The same defect was found and fixed on 2026-09-24, but only in `scripts/limit-recover/lr-fire-resume.sh`
(commit 2b1cdfcc8, "NO ECHO BEFORE interact"). Nobody ported it to `bin/reso-resume-one`. The parity
test only diffs the drain span, so the gap stayed invisible.

## Launch chain (measured: `ps -o pid,ppid,tty,command`, read-only, 2026-10-16 evening)

```
57630 57513 ttys027  .../.claude-293/node_modules/.bin/claude --permission-mode auto --model claude-opus-5-5 --effort high ...
57513 57490 ttys027  bash /Users/chrisren/.claude/bin/cc-close-attrib /Users/chrisren/.claude-293/.../claude ...
57490 56454 ttys023  expect -c \012  set timeout 240 ...
56454 56080 ttys023  bash /Users/chrisren/.reso/bin/reso-resume-one next2 /Users/chrisren/Development/.worktrees/wt-pool-5 5423f92a-...
56080 56073 ttys023  -zsh -ic 'env' 'CC_ADMIT_DONE=1' '/Users/chrisren/.reso/bin/reso-resume-one' 'next2' ... || exec zsh -i
56073 44163 ttys023  /usr/bin/login -f -l -p chrisren /Applications/kitty.app/Contents/MacOS/kitten run-shell --shell /bin/zsh -ic ...
44163     1 ??       /Applications/kitty.app/Contents/MacOS/kitty
```

- The kitty pane tty is **ttys023**. Claude runs on expect's own pty, **ttys027**. The tty name was
  reused and has nothing to do with old pane 217. Claude writes its probe to ttys027. Expect relays
  that output to ttys023 (log_user). Kitty answers on ttys023's input, which only expect's stdin
  reads.
- `~/.reso/bin/reso-resume-one` is a symlink to `/Users/chrisren/Development/claude-infrastructure/bin/reso-resume-one`
  (`ls -la`). `diff -q` against that checkout prints IDENT. Its `lr-reply-drain` span is the same as
  this worktree's (measured: the sed span diff prints SAME_DRAIN). The live code therefore has the drain.
- pane-spawns.jsonl:4964: `{"ts":"2026-10-16T23:26:23Z","surface":"os-window","backend":"kitty","caller":"boot-resume-launch.sh",...,"chain":"lr-reset-poller.sh>boot-resume-launch.sh",...,"detail":"boot-resume-launch resume sid:5423f92a-..."}`
- recon/launch.log:385-387: `1792193180 ... cc-resume-debt taken pid=45752`, `... boot-resume-launch inherited pid=53834`,
  `1792193184 ... reso-resume-one taken pid=56454` (pid 56454 matches the ps row above).
- The kitty arm builds the argv `zsh -ic "$CMD || exec zsh -i"` at scripts/boot-resume-launch.sh:248.
  Kitty itself adds `login -f ... kitten run-shell` (seen in ps; it is not in the repo).

## Who emits the queries: Claude Code's boot probe

- Measured with python mmap over `~/.claude-293/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`
  (2.1.293). The bundle's string table holds `XTVERSION: terminal identified as "`,
  `XTVERSION: no reply (terminal ignored query)`, `CSI ? u flags=`, `no reply to CSI ? u`,
  `probe: DECRPM 2026 status=` and `no XTVERSION reply`, next to `Terminal capabilities:`. That is a
  startup probe asking exactly XTVERSION and `CSI ? u`. Kitty replies with the triple
  XTVERSION/`?5u`/DA1, and DA1 is the usual end-of-batch sentinel. The bundle is Bun bytecode, so I
  read the strings, not the call site.
- Ruled out:
  - p10k instant prompt returns under `zsh -c`. `~/.cache/p10k-instant-prompt-chrisren.zsh:2`:
    `! (( ${+__p9k_instant_prompt_disabled} || ZSH_SUBSHELL || ${+ZSH_SCRIPT} || ${+ZSH_EXECUTION_STRING} )) || return 0`.
  - `~/.zshenv`, `~/.zprofile` and `~/.zshrc` contain no `\e[c`, `>q`, `?u` or `/dev/tty` writes (bounded grep).
  - bin/reso-resume-one and bin/cc-close-attrib emit no query. The only escapes in cc-close-attrib
    are a stderr strip at :238 and a coloured notice at :501. Grep for `\e[c`, `\033[c`, `>q`, `?u`
    and `run-shell` in reso-resume-one, cc-close-attrib and boot-resume-launch.sh finds nothing.
- UNVERIFIED: whether `kitten run-shell` itself sends a query. It is low relevance either way. Any
  reply that arrives while expect is still pre-`interact` is echoed the same way, and the fix covers
  the whole span from spawn to drain.

## Why it shows as caret text (the mechanism)

1. Measured with `script -q /dev/null stty -a`: a fresh macOS pty defaults to `icanon`, `echo` and `echoctl`.
   `zsh -c` never starts zle, and bash reso-resume-one never changes the mode, so ttys023 is still
   cooked and echoing when expect starts.
2. bin/reso-resume-one:798 starts `expect -c`, and :830 spawns claude. The first `expect {}` block
   (:857-907) can run for up to `set timeout 240` (:799) and never reads stdin. In the whole program
   `stty` appears only in the WINCH trap (:853-855) and inside `lr_drain_user` (:945, :947, :959,
   which go raw, read, and restore). **Nothing turns echo off before spawn.**
3. Kitty's replies arrive on ttys023 while it is cooked and echoing. The line discipline echoes them
   at receipt (receipt, not read), and echoctl renders ESC as `^[`. That gives exactly
   `^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c`. The cursor is at Ink's input row, so the paint lands on
   the composer row.
4. At :963 `lr_drain_user` reads the queued bytes in raw mode and `lr_reply_filter` (:928-940) drops
   all three reports: the DCS regsub at :930 and the private-prefix CSI regsub at :935. They never
   reach claude. The paint stays, because the drain only cleans **input**.
5. The 2.1.293 composer would not render an ESC byte as the two characters `^[`. Caret notation is
   the tty-echo signature. This is inference: I could not read pane 220's screen or composer state
   (that would need `kitty @ get-text`, which the brief forbids).

Natural control: the earlier in-place relaunch of the same sid in pane 217 went through
lr-fire-resume.sh. That launcher has the no-echo guard, and launch.log:384 records
`1792193091 ... lr-fire-resume taken pid=78755`. Its run recorded a clean composer. events.jsonl in the
upgrade run dir:
`{"ts":"2026-10-16T23:25:00Z",...,"state":"READY-QUIET","stage":"ready","detail":"READY never matched; the composer reads EMPTY after 8s quiet and there is no prompt to type",...}`.
The launcher without the guard produced the junk. The one with it did not. This is suggestive, not
proof, because the boot timing differs.

## The existing guards and why they did not fire

| guard | where | why it did not stop this |
|---|---|---|
| lr-reply-drain (input filter) | bin/reso-resume-one:915-962, identical span in lr-fire-resume.sh; added b9a8b4b8a 2026-09-23 | It did its job, as far as I can tell: the bytes were not forwarded. It works on the input queue only, and the echo was painted at receipt, before the drain ran. |
| NO ECHO BEFORE interact | scripts/limit-recover/lr-fire-resume.sh:1043-1046 (bash save), :1066-1076 (`stty -echo` before spawn), :1649 (restore before drain), :1654 (bash restore); commit 2b1cdfcc8 2026-09-24 | **Only ever applied to lr-fire-resume.sh.** bin/reso-resume-one has no counterpart (grep for `stty`, `-echo`, `lr_tty_orig` finds only the drain and WINCH lines above). The commit message names this exact string: "painted across the composer as ^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c". |
| drain parity test | tests/lr-fire-resume-reply-drain.bats:33 (`span()` = only the `>>> lr-reply-drain` ... `<<< lr-reply-drain` lines), :87-103 | It diffs only the drain span. The echo guard sits outside the markers, so dropping it from one launcher stays green. |
| no-echo red-proof | tests/lr-fire-resume-submit.bats:637-655 | It runs against lr-fire-resume.sh only. No reso-resume-one test samples the pty mode (tests/reso-resume-one.bats has only a stub `stty raw -echo` at :123). |
| composer-intent `terminal-reply` class | scripts/lib/composer-intent.sh:27, :69-71 (regex `^(_G[A-Za-z]=\|P>\\\|\|...\|\[\?[0-9]...)`) | It matches the **input-path** form (`P>|...`, `[?62;52;c`) and misses the **echo** form, which starts with a literal `^[`. Measured by sourcing the lib and calling `composer_unintended_class`: `^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c => DRAFT(rc=1)`; `P>|kitty(0.48.2) => terminal-reply`. |

## Does the junk block anything?

- **Inside Claude Code: probably not.** The drain dropped the bytes (point 4), so CC's composer state
  is most likely empty. A prompt typed into pane 220 should not fuse with the junk at the CC level.
  UNVERIFIED: I cannot read pid 57630's composer. The teammate transcript ends with
  `2026-10-16T23:25:40.740Z attachment deferred_tools_record`, and no later record exists (measured by
  parsing the tail of the transcript jsonl), so nothing with the junk was ever submitted.
- **For every screen-reading gate: yes, it blocks.** `cc_tui_composer` and `cc_tui_composer_text`
  (scripts/lib/cc-tui.sh:158-185) read the kitty screen with `get-text` (:146, :242). The painted row
  reads as composer content, and `composer_unintended_class` calls it a DRAFT (measured above). Every
  composer gate that refuses to type into a draft would refuse this pane: `cc_tui_submit` (:567),
  `handoff-fire --probe-recycle-preconditions`, and recycle/upgrade typing. The commit message of
  2b1cdfcc8 records the same paint having "broke the composer border parse, so lr_screen read
  UNKNOWN and the submit wait ran to its deadline". `cc_tui_clear` (:278) cannot clear it either: CC
  thinks the composer is empty, so Ctrl-U changes nothing and nothing is repainted. That function's
  rc 1 is "could not clear". The lr-upgrade switch carries `cc_tui_composer_text` output forward
  (cc-tui.sh:171-173 comment), so it could copy the junk into a successor composer as a "draft".
  UNVERIFIED for pane 220, because no gate has run against it.
- It also misleads the operator, who sees what looks like a garbage draft.
- Side effect, inferred: CC's probe never gets its replies (they are dropped on the outer tty), so CC
  logs "no XTVERSION reply" and falls back to defaults. This is harmless and the same as on the
  lr-fire-resume path.

## Clean fix

1. **Port the no-echo guard to bin/reso-resume-one**, shaped like lr-fire-resume.sh:
   - In the expect program, before `spawn` (:830), save `stty -g` and run `stty -echo` (keep icanon,
     so the drain's raw-mode snapshot and restore stay unchanged).
   - Immediately before `set lr_keep [lr_drain_user]` (:963), restore the original state.
   - In bash, save `stty -g` before `expect -c` (:798) when `[ -t 0 ]`. Restore it right after
     `rr_rc=$?` (:975), before any `exit` and before `exec "${SHELL:-/bin/zsh}" -l -i` (:1078), so the
     fall-through shell never inherits `-echo`.
   - Watch the trap the file names at :810: the program is a single-quoted bash string, so a Tcl
     comment must contain no apostrophe.
2. **Make drift impossible, not just less likely.** Put the echo-off and restore lines in a second
   marked span (for example `>>> lr-tty-quiet` / `<<< lr-tty-quiet`), identical in both launchers.
   Extend tests/lr-fire-resume-reply-drain.bats to diff it and to assert order: quiet before spawn,
   restore immediately before the drain call. Port the "-echo 1 s in" red-proof
   (tests/lr-fire-resume-submit.bats:637) to reso-resume-one through its `CC_RR_NO_INTERACT` harness
   path (reso-resume-one:910-914). Better still: move both procs into one sourced Tcl file under
   scripts/lib that each expect program `source`s, with fail-open if it is missing. The two
   near-duplicate expect programs are the root reason a fix landed in only one of them.
3. **Belt (optional).** Teach `composer_unintended_class` the ECHOCTL form: content that starts with a
   literal `^[` followed by one of `P`, `[`, `]` or `_`, classed as `terminal-reply`. A screen-reading
   gate then calls painted replies junk, not a draft. Its repair must be a **repaint**, not Ctrl-U,
   because the composer is already empty. A SIGWINCH-driven redraw is one option (the WINCH trap at
   :852-856 forwards size changes). UNVERIFIED: which keystroke forces a full Ink repaint in 2.1.293.
4. For pane 220 now: nothing was done (read-only brief). The paint goes once Ink fully redraws (a
   resize or similar). The pane's real problem is that it is a resurrected retired teammate, which
   belongs to other slots.

## UNVERIFIED (could not check under the brief's rules)

- What pane 220's screen and composer actually hold. Reading them needs `kitty @ get-text`, which is
  forbidden. The paint-only conclusion rests on the caret signature plus the code path.
- Whether expect for pid 57630 got past the first `expect {}` block to the drain and `interact`. ps
  shows expect alive. Checking ttys023's mode (`stty -a -f`) would mean opening a live pane tty, so I
  skipped it.
- That BSD/XNU moves pending canonical input into the readable queue when ICANON is cleared. This is
  from memory. The drain's executed bats arm (tests/lr-fire-resume-reply-drain.bats:104) shows queued
  reports are dropped, but it does not use a cooked-mode partial line on a real pty.
- Whether `kitten run-shell` emits any terminal query.
