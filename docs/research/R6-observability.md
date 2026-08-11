# R6 — why `◆ routed → next3` never reached the operator, and the 100th-percentile fix

Research, read-only. Every behavioural claim below names the command that produced it; every code
claim names file:line.

---

## 1. VERDICT — it printed, and the TUI erased it 1.4 s later

**The line is emitted. `[[ -t 2 ]]` holds. Then Claude Code enters the alternate screen buffer and
clears it, and the normal buffer — where the line lives — stays hidden for the entire session.**

Measured, not reasoned:

```
# /tmp/r6-launch220.sh: print -u2 "◆◆R6MARKER◆◆"; exec ~/.claude-220/node_modules/.bin/claude
# driven under a real pty (python pty.fork), cwd = the trusted worktree
```

| probe | result |
|---|---|
| `[[ -t 2 ]]` at the moment of the print, under a pty | **YES** (`stderr_is_tty=YES` in the capture) |
| marker byte offset in the pty stream | 0–10 (first thing on the wire) |
| `ESC[?1049h` (enter alt screen) emitted by claude 2.1.220 | **1×**, at byte 104 |
| `ESC[2J` (erase display) immediately after | **1×** |
| wall-clock gap marker → alt-screen switch | **1.42 s** (python pty timing run) |
| `ESC[?1049l` (restore) on a clean `/exit` | **1×** — the line reappears only *after the session ends* |

So the announcement is visible for ~1.4 s during CC's startup, is then swapped out of view with the
rest of the shell scrollback, and cannot be scrolled back to *during* the session (kitty's scrollback
in alt-screen shows the alt buffer). The operator would have had to be looking at that pane during a
1.4 s window, and could never recover it afterwards. This is a **structural** loss, not a missed glance.

### 1a. A repo doc's inference about this is REFUTED by measurement

`docs/research/cc-startup-modals-2026-08-04.md:82` concludes, from reading `ds()`/`IZi()` in the
binary, that *"`tui:"default"` also keeps every pane **out of the alternate screen** — … which
preserves `kitty @ get-text` pane-text tooling."* All four homes were set to `tui:"default"` on that
basis (`.claude`, `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`; `.claude-next` is
`"fullscreen"`).

Measured on 2.1.220, same box, trusted cwd:

| config dir | `tui` | `ESC[?1049h` |
|---|---|---|
| `~/.claude-tertiary` | `default` | **1** |
| `~/.claude-next` | `fullscreen` | **1** |
| `~/.claude-tertiary` + `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` | `default` | **0** |
| `~/.claude-tertiary` + `CLAUDE_CODE_NO_FLICKER=false` | `default` | **0** |

`tui` does **not** control alt-screen at 2.1.220. The two env levers do (they are the `IZi()` clause
quoted at that doc's line 79). `~/.zshrc:284` exports `CLAUDE_CODE_NO_FLICKER=1` for every
interactive shell, i.e. the fleet is currently on the alt-screen path everywhere. Anything that
depends on "panes are out of the alternate screen" (pane-text tooling on the close path) should be
re-verified.

### 1b. Even surviving, the line answers the wrong question

`lib/claude-launcher.zsh:113` prints `_CC_ROUTE_NOTE`, set at `:80` to `"routed → $acct"`. That is
*which*, never *why*, and never *versus what*. The operator's stated belief — "I'm on the account
`/accounts` recommends" — is not contradicted by the string `routed → next3`; you would have to
already know that `/accounts`' recommendation and the launcher's are different computations. They are
— see §3.

---

## 2. What is recoverable in-session today

| surface | shows | model tokens | always visible? | evidence |
|---|---|---|---|---|
| **statusline** `(3)` | the account, as a bare ordinal | **0** | **YES, every render** | `~/.claude/statusline.sh:226-334`; live render: `(3) wt-pool-1 (aa6e49de5)  cc-130528-83028 · high · 42%` |
| **`/status`** | `Email: ren.chris+claude@outlook.com`, login method, org | **0** (TUI-local) | on demand, operator types it | pty capture of `/status` on 2.1.220 |
| CC welcome banner | model, effort, "Claude Max" — **not** the account | 0 | first frame only | same capture |
| `claude-which` alias | `Config: $CLAUDE_CONFIG_DIR` | costs a tool call if the model runs it | no | `~/.zshrc:236` |
| `$CLAUDE_CONFIG_DIR` | the dir | tool call | no | env |
| `claude-accounts --json` `is_self` | the row, marked | tool call + a sweep | no | `bin/claude-accounts:1919-1938` |
| `~/.claude/logs/account-assignments.jsonl` | *that* the launcher picked an account (`src:"claude-launcher"`, 9 rows) | tool call | no | `bin/claude-accounts:1252` |

**So the operator DID have an always-visible account indicator — `(3)` — and it was not enough.**
Two reasons, both fixable and neither cosmetic:

1. `(3)` is an **ordinal with no label**. It requires holding the `.claude-tertiary → 3 → next3 →
   ren.chris+claude@outlook.com` chain in your head (`~/.claude/accounts.json`). It says nothing you
   can act on without that map.
2. Nothing anywhere says **why**. The assignment ledger records `{acct, src, ts}` only — no lane, no
   score, no runner-up. `bin/claude-accounts:1252`. So "why am I on 3?" is unanswerable after the
   fact, by anyone, including the model.

Note `score_interactive`'s own docstring already predicted this failure shape
(`bin/claude-accounts:1499-1501`): a wrong pick reads *"as an ordinary limit hit, with nothing
anywhere pointing at routing as the cause."*

---

## 3. `/accounts`' blind spot — and it can name the OPPOSITE account

Bare `claude` routes with `--route interactive` (`lib/claude-launcher.zsh:60`). `/accounts` renders
**only** the `general` and `fable` picks:

- `render_readout` (`bin/claude-accounts:2197`) computes `rank_g`/`rank_f` at `:2202-2206` and marks
  the table row `➤` / `➤ᶠ` from `pick_g`/`pick_f` at `:2237-2242`. No interactive rank exists.
- `render_table` (`:2382`, the coloured CLI renderer) does the same: `rank_g, rank_f` at `:2409-2410`,
  `mark = "➤" if r["acct"] == pick_general` at `:2432`, and the footer prints exactly two
  `route_line`s — `general` at `:2630` and `fable` at `:2632` (`route_line` def at `:2608`).

These are **different objectives over the same eligibility**, by design and by docstring:
`score_general` is `headroom / T**2`, deadline-dominant (`:1476` ff.); `score_interactive`
(`:1492`) carries **no 1/T term at all** and maximises runway — *"the opposite shape"* (`:1497-1501`).
The interactive lane additionally **never yields the login-cliff term** (`:1604`), so it can abstain
where general routes.

Demonstrated numerically (module loaded via the /Users/chrisren/.claude/bin/cc-bats `LOAD` idiom, real `load_cfg()`):

```
## two healthy accounts: "far" = weekly 10% but resets in 150 h; "soon" = weekly 60%, resets in 3 h
general     -> [('soon', 0.064000), ('far', 0.000040)]
interactive -> [('far',  0.847059), ('soon', 0.376471)]
```

**A complete inversion.** `/accounts` would have printed `➤ general → soon` while bare `claude`
launched onto `far`. Today all three lanes happen to return `next` (three accounts are
`poll throttled`), so the divergence is invisible right now — which is exactly why it survives.

### The precise change

1. **`render_readout` (`:2197`)** — add `rank_i, ire = ranked(rows, cfg, win, "interactive")` beside
   the existing two at `:2202-2206`; derive `pick_i`. In the name cell at `:2239` add a third mark
   (e.g. `➤ⁱ`) when `acct == pick_i and pick_i != pick_g`, following the existing `➤ᶠ` de-dup rule.
   Add an `interactive` line to the markdown footer with the same shape as the two route lines.
   The `why` string should be the interactive lane's own terms — absolute weekly headroom + projected
   5 h headroom — not general's `↻ reset` clause, or the footer will contradict the score.
2. **`render_table` (`:2382`)** — same three-line addition (`rank_i` at `:2409-2410`; `mark` at
   `:2432` must handle two possible marks without breaking column alignment, which the existing
   comment at `:2427-2431` warns is width-critical); then
   `print("  " + route_line("interact", rank_i, ire, interactive_why))` after `:2632`.
   `route_line`'s `f"{label:<7}"` at `:2609` is 7 wide — `"interactive"` overflows it; use a
   ≤7-char label or widen all three together (the footer shares the table's 82-col budget, `:2617`).
3. **Order matters for the operator's read**: the interactive line is the one that answers "what will
   bare `claude` do", so it should be FIRST, not appended after fable.

### Tests that pin the current output — must be updated in the same commit

- `tests/claude-accounts-core.bats:394` *"render_table: the routed row is marked IN the table, not
  only in the footer"* — asserts **exactly one** row carries `➤` (`assert len(picked) == 1`), that it
  is the general winner, that `"➤ general → win" in plain`, and that **both rows keep equal length**
  (`len(tbl[0]) == len(tbl[1])`). A second mark on a different row breaks assertion 1 directly; a
  wider mark breaks the alignment assertion.
- `tests/claude-accounts-core.bats:417` *"a /login instruction always names the mailbox"* — greps
  `"is the pick"` lines; the cliff-warning loop at `bin/claude-accounts:2645` iterates
  `(rank_g, rank_f)` and must gain `rank_i`, or an interactive-only pick with a dying login is
  warned about nowhere.
- `--json`: `route_reasons` / rank consumers (`commands/accounts.md:84,122`) document general/fable
  only; adding a lane without adding it to `--json` re-creates the same asymmetry one layer down.

---

## 4. Ranked fixes for in-session account visibility

**Rank 1 — label the statusline marker. `(3)` → `(3 next3)`.**
- *Mechanism*: `~/.claude/statusline.sh:243-266` already resolves `$CFG` (transcript-path prefix,
  `$CLAUDE_CONFIG_DIR` fallback) and maps it to `NIDX` through a literal `case`. Add the account name
  to the same `case` arms — **zero new forks** on a per-render hot path.
- *Cost*: **0 model tokens**; measured render time unchanged at **60–110 ms** (5 runs, `/usr/bin/time`
  on a fixture payload) — the account is derived from a variable already computed.
- *Visibility*: **always**, and left-anchored so a narrow pane's ellipsis cannot eat it (`:228-230`).
- *Tests*: `tests/statusline-identity.bats:418` and `:441` are **differential, with no glyph literal**
  (`marker_of()` = everything before the cwd name), so a longer marker still passes provided two
  instances differ and stable renders none. Layer 1 (tests 1–9) is frozen against historical blobs and
  cannot go red (`:20-46`).
- *Risk*: 4–6 extra columns on every pane's status line. Mitigate by dropping the redundant ordinal
  (`(next3)`) rather than carrying both.

**Rank 2 — record the WHY, so it is answerable at any later moment.**
- *Mechanism*: the launcher already forks `--assign` (`lib/claude-launcher.zsh:85`). Extend the ledger
  row (`bin/claude-accounts:1252`, `log_assignment` writer) with `kind`, `score`, `runner_up`,
  `excluded` — everything `--route` already computes and currently throws away into
  `2>/dev/null` at `:60`. Then `claude-accounts --why [--session]` reads it back.
- *Cost*: one tool call when asked; 0 otherwise. Ledger already prunes at 400 lines (`:1249`).
- *Risk*: none to the launch path (the write is already backgrounded and detached, `:85`).

**Rank 3 — make the note survive its own printing.**
Three sub-options, best first:
- *3a. kitty tab title.* `kitty @ set-tab-title "next3 · <cwd>"` before exec. Alt-screen does **not**
  touch the title, and kitty treats an explicitly-set tab title as fixed, ignoring later app OSC-0
  writes — CC does set one (`ESC]0;✳ Claude Code` observed in the capture), so this must be measured
  before shipping. Always-visible, 0 tokens.
- *3b. Print it AFTER startup instead of before*: unavailable — nothing in the launcher runs after
  `exec`.
- *3c. `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`* (measured: kills `?1049h`). **Do not** reach for this
  just to save one line — it changes the renderer for every session and would need its own
  scrollback/perf verdict. It is listed because it is the only lever that makes *any* pre-exec stderr
  durable.

**Rank 4 — fix `/accounts` (§3).** Does not answer "which am I on" (it answers "which *should* I be
on"), but it removes the belief that produced the confusion. Pair it with Rank 1.

**Rejected: a SessionStart hook injecting the account into context.** `additionalContext` is model-
visible, i.e. it spends tokens on every session forever to state a fact the statusline can carry for
free — and per `~/.claude/CLAUDE.md` § Session Close, `systemMessage` is the only Stop/hook field that
does not extend a turn, and it cannot reach the model. Wrong surface.

---

## 5. Prior art

- **No prior decision to announce, or to keep quiet, the routed account.** `git log -S"_CC_ROUTE_NOTE"
  -- lib/claude-launcher.zsh` → a single commit, `9759d28d9` *"claude1 pins account 1, bare claude
  routes — landed inert, operator-activated"*. `grep -rn "routed →|◆ routed|ROUTE_NOTE" docs/` → **no
  hits**. Nothing has been tried and rejected here.
- The launcher's comment at `:120-122` states the design intent explicitly — *"an inert router and a
  router that legitimately chose the pinned account are indistinguishable in silence, which is how a
  dark feature survives for weeks"* — i.e. the note was written for the FALLBACK case (debugging the
  router), and the success case inherited it. That explains why nobody checked whether it survives.
- Alt-screen prior art: `docs/research/cc-startup-modals-2026-08-04.md:79-82` (the `IZi()`/`ds()`
  source read) — its **conclusion is refuted by measurement**, see §1a.
- Statusline marker design history: five redesigns recorded at `tests/statusline-identity.bats:29-34`.
  Every one was about *legibility of the ordinal*; **none** asked whether an ordinal is the right
  content. That is the gap Rank 1 closes.

---

## 6. Blockers / uncertainties

- **kitty tab-title persistence against CC's OSC-0 write is UNTESTED** (Rank 3a). It needs a live
  kitty window; a subagent cannot claim it from documentation.
- The `/accounts` divergence is **currently masked** — all three lanes return `next` today because
  three accounts are `poll throttled ↻ (cached usage)`. Any test of the fix must use synthetic rows
  (as §3 does), never the live fleet.
- `tui:"default"` was applied fleet-wide partly *for* the alt-screen property that §1a refutes. I did
  not chase what else depends on that assumption; `kitty @ get-text` close-path tooling is the named
  consumer and should be re-verified independently.
