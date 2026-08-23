# What a Stop-hook `systemMessage` ACTUALLY renders as — measured, not assumed

**Date:** 2026-08-22 · **Binary:** 2.1.220 (`~/.claude-220/node_modules/.bin/claude`, the live one) ·
**Probe:** `docs/research/tui-systemmessage-render-2026-08-22.py` · **Status:** measured; the result
is load-bearing for `hooks/operator-readout.sh`'s `✎` row

## Why this had to be measured rather than reasoned

The operator asked for the missing-value row to carry "syntax colour highlighting so I can see it
and not gloss over it along with all the blocks of white text." This repo has been wrong about
exactly this kind of claim before, and expensively: a ` ```bash ` fence was **mandated for every
plattered command, shipped, and hook-enforced for a whole session** — then disproved by one
screenshot, because a fence gets *syntax* highlighting and a bare command name has no syntax to
colour, so it rendered plain white, *less* visible than the prose around it. The recorded lesson is
`CLAUDE.md`'s: **a rendering claim is only true of the renderer you measured.**

So: measure this renderer.

## Method

`hooks/operator-readout.sh` reaches the operator as `{"systemMessage": …}` on Stop. That channel is
**TUI-only and silently dropped under `claude -p`** (`final-response-shaping-2026-08-08.md` §2a,
positive-controlled), so a headless probe measures nothing. The instrument therefore has to be a
**real TUI in a pty**, with the raw bytes it writes to the terminal captured and inspected.

1. A throwaway project `/tmp/ansi-render-probe/` with `.claude/settings.json` registering the SAME
   hook on `SessionStart` and `Stop`. Launched with `--setting-sources project`, so the operator's
   own global hooks do not fire alongside and contaminate the capture (that contamination
   invalidated the first run of the 2026-08-08 probe and is worth repeating as a trap).
2. The hook emits ONE systemMessage carrying three sentinels:
   * `ZZANSIZZ` wrapped in `\u001b[33m` … `\u001b[0m` — does an ESC we emit survive?
   * `` `ZZCODEZZ` `` in markdown backticks — is the block markdown-rendered?
   * `ZZPLAINZZ` bare — the positive control (did it render at all?).
   `\u001b` is the only *legal* way to put an ESC in a JSON string, and it is exactly what
   `jq -n --arg` emits for a real ESC byte — i.e. the realistic channel, not a contrived one
   (`operator-readout.sh:1300` is a `jq -nc --arg m "$BLOCK" '{systemMessage:$m}'`).
3. `pty.fork()`, drive one cheap turn so `Stop` fires, capture every byte, then grep the raw buffer.

**The trap that cost run 1:** the keystrokes went to the folder-**trust dialog**, so no turn ran and
`Stop` never fired — only the `SessionStart` line rendered. A single count of the sentinel would have
been read as success. Run 2 dismisses the dialog first, and the two occurrences are then
distinguishable by their prefix (`SessionStart:startup says:` vs `Stop says:`).

## Observed — raw pty bytes, run 2

```
⎿  Stop says: PROBE \x1b[33mZZANSIZZ\x1b[32G\x1b[39mand\x1b[36G`ZZCODEZZ`\x1b[47Gand\x1b[51GZZPLAINZZ\x1b[61GEND
```
(preceded by `\x1b[38;2;153;153;153m` — the grey the whole block is drawn in)

| Question | Answer | Evidence in the bytes above |
|---|---|---|
| Does the Stop `systemMessage` render at all? | **Yes**, as `⎿ Stop says: …` | the sentinel appears, prefixed |
| What colour is the block? | **Grey `#999`** (`SGR 38;2;153;153;153`) | the wrapper before `Stop says:` — this **is** the "block of white text" the operator glosses over |
| Does an ESC we emit survive? | **YES, verbatim** | `\x1b[33m` arrives intact, immediately before `ZZANSIZZ` |
| What happens to our reset? | **Normalised by Ink to `\x1b[39m`** (default fg) | our `\u001b[0m` is not echoed as-is |
| Is markdown rendered? | **NO** | backticks arrive as literal `` ` `` characters, no styling |
| Is the text escaped/stripped anywhere? | **No** | zero occurrences of literal `\u001b` or `^[` in the capture |
| Anything else worth knowing? | Ink emits **cursor-forward (`\x1b[NG`)** instead of runs of spaces | `\x1b[32G` between fields — so any assertion over TUI output must strip ANSI first |

## What follows from it

1. **ANSI is the colour lever in this block, and it works.** `✎`'s `SUPPLY <token>` clause is drawn
   in `\033[1;38;2;255;193;7m` — the TUI's own warning amber, lifted from its own `⚠ Transcript
   saving is off` line in the same capture, so it is native to the renderer and provably supported
   by the emulator that draws it. Closed with `\033[22;39m`, **not** `\033[0m`: this line renders
   *inside* the TUI's styled block, `0m` would reset attributes the renderer set around us, and
   `39m` is what Ink rewrites our reset to anyway.
2. **The "inline code renders blue" rule buys nothing here.** That rule (CLAUDE.md § ONE COMMAND) is
   about the MODEL's prose, which the TUI markdown-renders. This block is not markdown-rendered, so
   backticks in a hook line are just backticks. Anyone reaching for them here is applying a true
   rule to the wrong renderer — the same mistake as the fence.
3. **Colour costs nothing in paste-safety, and it is scoped so the question cannot arise.** SGR
   sequences are attributes, not screen-buffer characters, so they are not part of a drag-selection
   (unlike a blockquote's `│`, which the operator has actually pasted and corrupted a command with).
   *That last clause is an argument from how terminals work, **not** something this probe measured* —
   so the implementation does not rest on it: `▶` runnable lines are left **byte-identical**, colour
   or no colour, pinned by `tests/operator-readout.bats` ("▶ rows stay byte-identical"). Only the
   deliberately-unpasteable `✎` row is coloured.
4. **Push and pull differ on colour, deliberately.** Hook mode's destination is the TUI (measured
   above). `--render`'s destination is usually the MODEL (`/wrap` captures it), where escape bytes
   are noise it would relay as prose — so `auto` colours in hook mode and in `--render` only at a
   tty. `NO_COLOR` wins over both. Pinned in both directions by tests.

## Re-run it

```bash
python3 docs/research/tui-systemmessage-render-2026-08-22.py ~/.claude-quaternary
```

It provisions `/tmp/ansi-render-probe/` itself, spends one cheap Haiku turn, writes the raw capture
to `/tmp/ansi-render-probe/pty.out`, and prints per-sentinel RENDERED/ABSENT with byte context. Read
the **context lines**, not just the counts: a count of 1 is the run-1 failure (SessionStart only)
wearing the shape of a pass. Pass a config dir that is logged in; `--setting-sources project` keeps
your global hooks out of it.
