# Why the startup readout hides, folds and vanishes (Claude Code 2.1.293), 2026-10-23

**Answer.** There are two blocks on screen, not one. The odd behavior almost all belongs to the
lower block, and that block is ours. Only the `[-]` button is Claude Code's.

- **Top block** (`⎿ SessionStart:startup says: ⏰ … startup-health fold stale …`). This is our
  SessionStart dispatcher's `systemMessage`. Claude Code draws it as an ordinary transcript row:
  it has no fold, it arrives on every start, and nothing deletes it. In fullscreen it can scroll
  out of view.
- **Lower block** (`➤ desk (bare claude) → next2 … [-]`, the quota table, `Quota read live at`).
  This is our mod `mods/accounts-readout`, drawing into Claude Code's plugin panel above the
  prompt. Claude Code adds the `[-]` collapse button to that panel. Our mod deletes the board at
  the first prompt sent 20 s or more after the board appeared. That is the "Band until 1st
  prompt" design the operator chose on 2026-10-21.

| # | Symptom | Cause | Whose | Conviction |
|---|---|---|---|---|
| 1 | Not always shown | The quota board now exists only in the lower panel, which lasts until the first prompt and is never drawn in resumed sessions started without the mod. Delivery never fails. | Ours | 80% |
| 2 | Looks expandable | Claude Code's plugin-panel frame: the `[-]` button, a collapsed hint line, and an internal scroll when the board is tall. Our board is drawn inside it. | Claude Code (frame), ours (content) | 97% |
| 3 | Gone after the first prompt | Our mod clears the board on purpose. The top row stays but scrolls off in fullscreen after a long reply. | Ours, by design | 96% |
| 4 | Comes back on "minimize" | Most likely the `[-]` collapse followed by an expand, which only works before the clearing prompt. Less likely, a pane tall enough to show the whole transcript brings back a top row that had scrolled off. | Claude Code mechanism, our lifetime | 55% / 25% |

Upgrading Claude Code changes none of this. The 2.1.294–2.1.309 changelog has no entry touching
hook-message rendering or the plugin-panel collapse (MEASURED, `/tmp/ssr-tui/cl-293-309.md`).

Offsets below are byte offsets into
`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (2.1.293). Probe artifacts
live under `/tmp/ssr-*`.

## Symptom 1: the readout does not always show (ours, 80%)

**Delivery is not the cause (refuted, about 97%).**
- 72 h dispatcher ledger (`~/.claude/logs/session-start-dispatch.jsonl`): 309 of 309 runs
  printed. The smallest message was 46 chars, there were 0 cancellations and 1 run took 9 s or
  more. MEASURED.
- 303 of 303 real starts have the dispatcher's `hook_system_message` in their transcript.
  MEASURED (`/tmp/ssr-drop-census/census.py`).
- The path where the hook prints nothing (`hooks/accounts-board.sh:396`, `[ -n "$band_msg" ] ||
  exit 0`) fired 0 times. It cannot fire while the deadline banner and the stale-fold line are
  present. It is latent, not current.

**What varies is the lower board.**
- **Lifetime.** Since 2026-10-22T06:02Z, 128 of 128 real startups handed the grid to the panel.
  46 of them lost it at a first prompt sent 20 s or more later. Before the grace fix `842db6f67`
  (2026-10-23T05:37Z), fired panes lost it 0.08–3.3 s after it appeared
  (`mods/accounts-readout/hooks/register.tsx:28-35`: 72 of 85 band-era starts and 41 of 41
  handoff fires). MEASURED (`/tmp/ssr-skeptic2/census2.py`).
- **No mod.** Only the zsh launcher adds `--plugin-dir` (`lib/claude-launcher.zsh:201-215`).
  The `expect` resume wrappers (`bin/reso-resume-one`, `scripts/limit-recover/lr-fire-resume.sh`)
  start the binary without it. Live census: 9 of 19 interactive 2.1.293 sessions lack the mod,
  and all 9 are expect-wrapper resumes. One of them also lacks `CLAUDE_CODE_NO_FLICKER`, so it
  runs the classic renderer. MEASURED (`ps -E`).
  - Those sessions show the grid as static text in the top block instead
    (`hooks/accounts-board.sh` band header: "No stamp … every byte below is today's").
  - On resume that row is appended at the end of the transcript. In 16 of 42 resumes it landed
    after the first prompt. MEASURED (`/tmp/ssr-drop-census/order.py`).
- **Handshake fallback.** The grid falls back to static text in the top block when any of these
  hold: the request stamp is older than 30 s, the ladder and board mtimes are more than 60 s
  apart, the board is hard-stale or empty, or the snapshot cp/mv fails
  (`hooks/accounts-board.sh:372-391`). MEASURED in code. It is rare: 121 of 121 band-era
  startups in the ledger handed off.
- **Sticky collapse.** One `[-]` click keeps every later panel collapsed for the rest of the
  process.
  - `bVt=We(Gs(),reset)` at 190871027, and `function We(t,e){return t}` at 183931168 throws the
    reset away. MEASURED.
  - That this survives `/clear` is INFERRED (no `/clear` was run).
  - Collapse does not carry across sessions: no key exists in any `.claude.json`. MEASURED.
- **The operator's own screenshot** (`/tmp/ssr-skeptic2/op-image-1.jpeg`, from transcript
  `0197e503`). MEASURED.
  - The left pane (`ea696cbf`) had its first prompt 288.4 s after start, so it shows no board.
  - The right pane (`0197e503`), before its first prompt, shows the board with `[-]`.

## Symptom 2: the expandable element (Claude Code frame, our content, 97%)

- **The button.** `[-]` is Claude Code's `CollapseHandle`. `var Xte=…e(JM,{label:"[-]",
  onAction:h.onCollapse})` at 214911175 is the only UI `[-]` in the binary. MEASURED.
- **The collapsed state.** Collapsing shows `CollapsedHint`:
  `▸ plugin panel hidden · ${shortcut} or click to show` (about 214911390). MEASURED.
- **The shortcut.** The default binding is `"ctrl+x ctrl+a":"abovePrompt:toggle"` (189898497),
  described as "hide/show plugin panel". MEASURED.
- **When it appears.** The button shows only while a plugin, not the engine, draws in the panel:
  `!ao&&Ro&&e(Xte,…)` and `Ro=…tn.type!=="engine"` in `AbovePromptSite` (about 214924783).
  MEASURED.
- **What is inside is ours.** `register.tsx:175-176` (`ui.render` `AbovePrompt` → `drawBand`)
  draws the content, and `bin/claude-accounts` writes the text (`:11477`, `:9241`, `:6072`,
  `:10869`). Our code contains no `[-]`. MEASURED.
- **Internal scroll.** The panel is capped at about half the pane. Taller content scrolls inside
  it behind a `↓ N more` cue, which also feels expandable. MEASURED (binary `maxHeight` and
  `overflowY:"hidden"`;
  `docs/research/accounts-board-band-2026-10-21/captures/out-band/1-start-50.txt` row 54).
- **Behavior measured in a pty.** A click collapses the panel, and the hint or the shortcut
  expands it again (`/tmp/ssr-live-probe/run-band-flicker-toggle` t1–t4). MEASURED.
- **The top row cannot fold.** It renders as `case"hook_system_message"` →
  `[hookName," says: ",content]` (213470571), inside a dim, wrapped Text with no truncation or
  toggle state. A regex search for any hook-row collapse string found 0 hits. MEASURED.

## Symptom 3: gone after the first prompt (ours, by design, 96%)

**The lower board is deleted by our mod.**
- The `prompt.submit` handler at `register.tsx:164-173` sets the board to null once
  `now - raisedMs` is at least `CC_BOARD_BAND_GRACE_S` (default 20, `:149`).
- After that, `ui.render` falls through to Claude Code's default panel.
- The hook had already taken the grid out of the top block (`hooks/accounts-board.sh:393-399`),
  so no copy remains.
- The design record is `docs/research/accounts-board-band-2026-10-21/README.md:3-10`.

**The causal A/B.** Two arms ran with the same timing, a first prompt about 28 s after the
board appeared. MEASURED (`/tmp/ssr-skeptic2/run-ko-{default,grace}`).
- With grace 20, the board was gone 1.5 s after Enter.
- With grace 9999, it survived the prompt, the reply, a collapse and expand, and a resize.

**The operator's panes match.** Their first prompts came 36.8 s and 288.4 s after start, both
past the grace window. Both had handed the grid to the panel: each snapshot was consumed, and
the ledger message was 448 chars with no grid. MEASURED.

**The top row is never removed, but it scrolls.**
- The only `transcript.cut()` calls are `/clear` (214807421) and resume/fork (214813177).
  None of the 16 `hook_system_message` sites runs on submit. MEASURED.
- In pty runs the row stayed through the prompt, the reply, resizes and ctrl+o, in both
  renderers (`/tmp/ssr-live-probe/run-flicker`, `run-plain`). MEASURED.
- The fleet runs fullscreen. `~/.zshrc:290` exports `CLAUDE_CODE_NO_FLICKER=1`, and that check
  runs before the `"tui":"default"` setting is read (191470951). MEASURED.
- On submit, fullscreen jumps to the bottom (`onUserRowLanded` → `repin("ownSubmitLanded")` →
  `scrollToBottom`, 215777131). After a reply taller than the pane, the row sits above the
  viewport. MEASURED (`/tmp/ssr-skeptic1/probe/run-scrolloff`, `/tmp/ssr-skeptic2/probe2.py`).
- Mouse-wheel scrolling brings the row back. kitty's own scrollback cannot reach it, because the
  session is on the alternate screen.

**The `1 new message (click) ↓` pill** is fullscreen's jump-to-bottom button. It shows only when
the view is not at the bottom (213613595, 213624218). It means the left pane had been scrolled
up. It does not point to a hidden message. MEASURED that the pill appears on wheel-up; INFERRED
that the wheel was the input used.

## Symptom 4: comes back on "minimize" (55% / 25%; depends on what "minimize" means)

- **(a) The `[-]` button itself (55%).** Clicking `[-]` collapses the panel to
  `▸ plugin panel hidden`, and clicking the hint or pressing ctrl+x ctrl+a brings it back.
  - This only works while the mod still holds the board: before the clearing prompt, or after a
    first prompt sent inside the grace window. MEASURED (`run-band-flicker-toggle` t1–t4,
    `run-ko-grace` c1/c2).
  - ctrl+o twice also hides the panel and then restores it. MEASURED (`run-band-flicker-grace`
    e1/e2).
  - That this is what the operator means by "minimize" is INFERRED.
- **(b) A taller pane (25%).** For example, kitty ⌘⇧Z `toggle_layout stack`
  (`~/.config/kitty/kitty.conf:315`). It brings back a top row that had scrolled off, but only
  when the new height fits the whole transcript. MEASURED, and the two runs are consistent:
  - After a 70-line reply, 120x24 → 120x110 restored the row, and shrinking back hid it again
    (skeptic 1).
  - After a 90-line reply, 120x40 → 200x60 did not restore it (skeptic 2).
- **Refuted.** MEASURED.
  - Focus out and in (what a minimize and restore sends; mode 1004 is on), a same-size SIGWINCH
    and a width-only resize never moved the view.
  - A cleared board never returns from a resize, the shortcut or ctrl+o (t5–t8, c3/c4). The
    toggle returns early when no plugin content is drawn (`if(!Ro)return!1`).
  - Only a geometry change can restore anything, so a true OS minimize and restore at the same
    size should restore nothing. INFERRED.

## Other findings

- **The large blank gap** is the fullscreen layout: the transcript starts at the top and the
  panel is pinned just above the prompt (row 27). In the classic renderer the panel sits
  directly under the message (row 6). MEASURED (`run-band-flicker` against `run-band-plain`).
- **The top block says the same thing every start** because two of our folds are stuck.
  - The startup-health fleet fold has been stale since 10-21 15:09 (`fleet.stamp`). The likely
    cause is the 30 s timeout at `bin/claude-accounts:12468-12472`. INFERRED.
  - The deadline-banner latch has not been written since 10-19 (`banner-latch` mtime), so the
    banner shows on every start instead of once a day. MEASURED.
- **Resume behavior.**
  - SessionStart rows are appended at the end and are not de-duplicated per resume. MEASURED
    (22296442).
  - Correction to an earlier finding: the resume de-dup `EEe` (193413217) can drop the whole
    batch, `systemMessage` included, when nothing de-dup-keyed is new. It is latent and was not
    observed.
- **The `›` in the report** is `➤` on screen (`bin/claude-accounts:11476`). It is a transcription
  difference, not a different element.
- **The 2026-10-19 research README** labels its probe "normal (non-fullscreen) screen". That is
  probably wrong, because the probe inherited `NO_FLICKER=1`. INFERRED.
- **Unexplained, minor.**
  - 3 resumes on 2026-10-21 around 20:08Z ran the dispatcher but left no batch in their
    transcripts.
  - 2 band-era resumes kept the static grid despite a mod stamp.
  - Neither one leaves a readout missing.

## Fix options, ranked

No upstream change is needed. Claude Code behaves as built: hook rows are plain transcript rows,
the plugin-panel `[-]` cannot be hidden per mod, and the collapse state is per process.

1. **Decide how long the board lives (ours; the operator's call).** Choices:
   - keep "until 1st prompt" (no change);
   - keep it until the operator clicks `[-]`, by deleting the clear at `register.tsx:164-173` so
     Claude Code's collapse becomes the dismiss control;
   - keep it for N prompts or N minutes.

   Cost: about 10 lines in the mod plus a pty regression run (`/tmp/ssr-live-probe/probe.py`
   with `PROBE_BAND=1`). It reverses the 2026-10-21 ruling. A no-code trial: launch one pane
   with `CC_BOARD_BAND_GRACE_S=9999`, which was measured to keep the board.
2. **Explain the absence instead of leaving it silent (ours).** When the grid goes to the panel,
   add one line to the top block (`hooks/accounts-board.sh:393-399`), e.g. "accounts board shown
   above the prompt until your first message · `claude-accounts --readout` to redraw". Cost: a
   few lines plus one bats case. It does not reverse the ruling.
3. **Give resumed sessions the mod (ours).** Add the launcher's per-mod `--plugin-dir`
   (`lib/claude-launcher.zsh:201-215`) to `bin/reso-resume-one` and
   `scripts/limit-recover/lr-fire-resume.sh`. Cost: two small script edits plus a test. 9 of 19
   live sessions currently get the static grid, at the end of the transcript.
4. **Unstick the two repeating folds (ours).** Fix the fleet fold (stale since 10-21) and the
   deadline-banner latch (stuck since 10-19). Cost: one investigation each. This removes noise
   but does not affect visibility.
5. **Log the mod's own events (ours).** Write raised, cleared (with the reason) and collapsed to
   a jsonl store, so "did the operator see the board" becomes measurable. Cost: small.
6. **Documentation (ours).**
   - In the mod header and the `accounts-board.sh` band section, state that `[-]`,
     `▸ plugin panel hidden` and ctrl+x ctrl+a are Claude Code chrome, and that collapse is
     process-wide.
   - Correct the 2026-10-19 README label.

   Cost: docs only.
7. **Shared settings (operator-owned).** The `"tui":"default"` in `~/.claude/settings.json` does
   nothing because `NO_FLICKER=1` overrides it. Remove it, or set it to `"fullscreen"` so a
   launch without the zsh environment matches the fleet. Cost: one line in `settings.json`, which
   is the operator's file to edit.
8. **Upstream (optional, low value).** Ask Claude Code for a per-mod collapse state instead of
   one per process, or for a way to pin a hook message. Cost: an issue, with no timeline.

## Open questions for the operator

- What does "minimizing" mean here: clicking `[-]`, ctrl+x ctrl+a, kitty ⌘⇧Z zoom, or a macOS
  window minimize? The answer settles symptom 4.
- In symptom 3, which block disappears? The lower board (our mod clears it), or the top `says:`
  row (which only scrolls)?

## Fix status (2026-10-23, landed 64f907abe)

Options 3 and 4 are done. Option 1 stays open as operator decision `9ee7197568c1`; options 2, 5
and 6 were not attempted.

- **Option 3, resumed sessions load the mod.** `lib/cc-mod-argv.sh` builds the `--plugin-dir`
  argv for all three start paths: the launcher, `bin/reso-resume-one` and
  `scripts/limit-recover/lr-fire-resume.sh`. It also supplies `CLAUDE_CODE_NO_FLICKER`, which the
  launcher's shell gets from `~/.zshrc`. There is one bats case per wrapper, and both went red on
  the pre-fix files.
- **Option 4a, the fleet fold.** CORRECTION to "Other findings": the 30 s bound was the instrument,
  not the cause.
  - `sh_settle` tested `flushed` with `tail | grep -q`. Every caller runs under pipefail, so the
    pipeline read 141 (3 of 3 runs on a 1.2 MB transcript), and no proof could go unproven.
  - `fold_dir` caches only a dir that has no `proof.*` file, so no dir cached. Each tick re-folded
    ~419 dirs and was SIGKILLed at 30 s, leaving 1,353 orphaned `.fold-rows.<pid>` files.
  - After the fix, the first fold ran in 27.9 s and the second in 4.2 s (390 of 420 dirs cached).
    `fleet.stamp` went from 2026-10-21 15:09 to 2026-10-23 17:47.
- **Option 4b, the banner latch.**
  - `fit()` re-flows the banner to the pane width. Once `a3c8f40f5` moved the latch write behind
    proof of delivery, the banner's one-line needle could never match the delivered text. Result:
    381 open `proof.dl-banner` files and 0 settled.
  - `sh_delivered` now collapses whitespace on both sides of the match.
  - The backlog was drained oldest-first, so the latch now reads today's value
    (`2026-10-23 cc70579ca7b42ef2`, written 17:47).
