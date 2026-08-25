---
name: resume-sessions
description: >
  Recover and autonomously resume all Claude Code sessions across the 4 accounts (next/next2/next3/next4)
  after a crash or reboot, and un-stick sessions that stalled after /compact. Finds the open sessions,
  recreates reaped worktrees (in whatever repo owns them), answers the blocking "resume from summary"
  prompt autonomously by taking the FULL session rather than the summary, clears terminal
  escape-sequence gibberish, re-engages each session with a continue-prompt (via the reliable it2 keystroke
  API, not osascript write text), and keeps them working with a keepalive watcher. Also gives a live
  cross-account quota view + optimal work routing. Use when: the machine crashed/rebooted with sessions
  open; sessions look "stuck" after resume→/compact (empty input box or ^[[<35;… / ^[[?27 gibberish);
  the user says "recover my sessions", "resume the crashed sessions", "restart my Claude sessions",
  "un-stick the sessions", "view usage across accounts", or invokes /resume-sessions.
---

# Resume Sessions — crash recovery + autonomous restart (100th-percentile runbook)

The tools live in `~/.reso/bin/` (`reso-resume-one`, `reso-keepalive`, `reso-quota`) — `reso-resume-one`
is a symlink to the tracked, gated, tested `bin/reso-resume-one` in claude-infrastructure; its two
neighbours are still untracked, which is the state that let this one rot. Deep rationale,
every gotcha, and the exact API details are in **`REFERENCE.md`** (read it if a step misbehaves).
**The load-bearing rule: send keystrokes to a running Claude TUI with `it2 session send`, NEVER
`osascript … write text` (it drops submits and mangles long text as pastes).**

Account → config dir: `next`→`.claude-next` · `next2`→`.claude-secondary` · `next3`→`.claude-tertiary` ·
`next4`→`.claude-quaternary`. `.claude` and `.claude-next` are the SAME account (mirror).

---

## Phase 1 — Anchor the crash & find the open sessions

1. **Reboot time** = crash anchor: `sysctl -n kern.boottime`. Sessions "open at crash" = transcripts last
   written just before that boot.
2. **Enumerate resumable sessions** across all 4 stores
   (`~/.claude{,-next,-secondary,-tertiary,-quaternary}/projects/<enc-cwd>/<sid>.jsonl`). Rules:
   - Skip `wf_*` dirs (workflow internals) and `agent-*.jsonl` (subagents) — not resumable sessions.
   - **Dedup the `.claude`↔`.claude-next` mirror**: a session in BOTH = one `next` session.
   - **Rank by the transcript's INTERNAL max timestamp, NOT file mtime** — a bulk mirror/backup touch
     gives many files an identical mtime that is NOT real activity.
   - Account = `next` if in `.claude-next`; else `next2/next3/next4` by store.
   - Use `python3` to read each jsonl's last real timestamp + `cwd` + `gitBranch` + summary/first-user.
     (A ready scanner pattern is in `REFERENCE.md § scan`.)
3. Present a tiered inventory (hot = mid-task recently; warm = idle/blocked; stale = days-old/done) with,
   per session: account, session-id, worktree/branch, one-line "what it was doing", last-activity.

## Phase 1b — CONSOLIDATE: one session per worktree (MANDATORY, not judgment)

🚨 **Enumerating is not selecting.** "Resume everything resumable" was the emergent default here and
it cost 39 live sessions / 8.8 GB RSS / zero free RAM on 2026-07-21 — **14 sessions for one project**,
batch-spawned in ~2 seconds. A project with a long transcript history resurrects proportionally many
sessions unless something says stop. **You are not the ceiling. The helper is.**

Do NOT hand-pick from the Phase 1 inventory. Run the shared selector — the same one
`lr-reset-poller.sh` and `boot-resume.sh` consult, so all three paths obey one policy:

```
~/.claude/scripts/limit-recover/lr-select.py --scan --allow-missing-cwd
#   stdout: TSV winners  acct <TAB> sid <TAB> worktree <TAB> branch   → feeds Phase 2 verbatim
#   stderr: the triage table                                          → show this to the user
```

`--allow-missing-cwd` is required here **because Phase 2 can recreate a reaped worktree from its
branch** (that is what `reso-resume-one`'s `git worktree add` is for). Without it those sessions are
filtered before Phase 2 ever sees them — the callers that *cannot* recreate a worktree omit the flag.
The TSV's 4th column is the branch, which is exactly `reso-resume-one`'s optional 4th argument.

> **That contract was only true for one repo until 2026-08-10.** `reso-resume-one` hardcoded
> `REPO=$HOME/Development/reso-management-app`, so a reaped worktree belonging to any other
> repository died at `worktree <wt> missing` — *after* `--allow-missing-cwd` had admitted it
> specifically on the promise that Phase 2 could rebuild it. The repo is now derived from the
> reaped worktree's own owner (the `.git/worktrees/<n>/gitdir` back-reference the owning repo keeps
> after the directory is deleted), so the flag now means what this paragraph says for every repo.
> Ambiguous cases **refuse** rather than guess — pass `--repo <path>` to name the owner outright.

- Resumes **one session per worktree** — the one that holds the most real state — and **lists** the
  rest. Total ceiling 4 per run. Both are flags (`--max-per-worktree`, `--max-total`), so exceeding
  them is explicit and visible, never a silent default.
- Winner = last **internal** transcript timestamp, then turn count, then sid. Never file mtime (a bulk
  mirror touch gives many transcripts the same mtime, which is not activity).
- Uncommitted work marks a group **HOT** in the triage table; it does not pick the winner — every
  session in a worktree sees the identical dirty tree, so it cannot discriminate between them.
- Teammate sessions, already-running sessions, and `agent-*`/`wf_*` internals are filtered out.

**Show the triage table (stderr) to the user before firing** — it is what makes 14-for-one visible
*before* it consumes 2.76 GB. A listed session is not lost: its transcript is intact and it can be
resumed explicitly by sid. If the user genuinely wants more than one per worktree, pass the flag; do
not work around the helper.

## Phase 2 — Recover each chosen session (autonomous, never blocks)

**Only the Phase 1b winners.** One invocation per winner:

```
~/.reso/bin/reso-resume-one <account> <worktree-path> <session-id> [branch]
```

`reso-resume-one` (idempotent) does all of: **recreate the worktree from `<branch>` if its dir was
reaped** (`git worktree add` in whatever repo owns it; branches survive worktree deletion — verify with
`git show-ref`), **reset mouse reporting** (stops crashed-session escape-seq garbage), **auto-answer the
large-session resume dialog** via `expect` — selecting **option 2, "Resume full session as-is"**, never
option 1 (**timeout 240s** because big sessions take >60s to reach the prompt — a short timeout leaves
them stuck), then hand off to a live session.

**It picks the FULL session, not the summary** (changed 2026-08-10; it answered with a bare CR before,
which takes option 1). Option 1 runs `/compact` on the transcript, and per REFERENCE.md §5 that drops
the session-scoped `/goal` Stop-hook — so the cheaper answer is exactly why recovered sessions came
back idle. A crash recovery is meant to return the session, not a précis of it. The trigger is the
five-character token `as-is`, because the previous 19-character literal `Resume from summary` breaks
across rows on a narrow pane and then never matches at all — three transplants sat on an unanswered
menu for 20+ minutes that way. Re-check the option list on any CC bump: **option 3 is "Don't ask me
again"**, a persistent per-account preference change.

The tool lives in the repo at `bin/reso-resume-one`, with `~/.reso/bin/reso-resume-one` a symlink to
it (`install.sh`), so the deployed copy cannot drift from the gated one. It was untracked until
2026-08-10, which is how its binary path, its model id and its effort all went stale unnoticed.

For the Fable session use account `fable4` (etc.) to keep it on `claude-fable-5` — and **pass
`--effort <tier>` to keep the reasoning tier too**. The account alone only fixes the model: until
2026-08-10 every fable arm re-pinned `effort=high`, so a Fable-5-at-**max** session came back at
high while its statusline still read "Fable 5". Omit the flag and prior behaviour is unchanged
(`high`). Same flag, same values and same reason as `lr-handoff.sh --effort` (`0c00b814`).

**Layout** (default = window per account, split panes; ask if unsure): create an iTerm2 window per
account with `create window` then `split vertically/horizontally with default profile`, and run the
`reso-resume-one` command in each pane. NEVER reuse the current window's `current session` for the first
pane — that's YOUR tab (off-by-one); always create a fresh window. Protect your own session by
`${ITERM_SESSION_ID##*:}` before any bulk pane-close (`~/.claude/bin/it2 session close -f -s <id>` is the
modal-free close, but it does NOT reap the process — `kill` surviving `claude … --resume` PIDs too).

**Layout on kitty — split panes anchored to the CALLING pane, never "wherever kitty is focused".**
A bare `kitty @ launch --location=vsplit` places the new pane relative to kitty's INSTANCE-WIDE
active tab (whichever tab was focused most recently, across every OS window) — not the tab
containing the pane that issued the command. Measured 2026-08-05: three crash-recovery resumes,
launched from a Bash tool call whose own pane was the intended anchor, landed in an unrelated OS
window instead, twice over (once from misidentifying the caller's own window id, once from
trusting kitty's active-tab default at all) — each needed a manual `kitty @ detach-window
--target-tab` to relocate. **Use `bin/kitty-split-launch.sh` instead of a raw `kitty @ launch`** —
it anchors the split to `$KITTY_WINDOW_ID` (the calling pane) by default via
`--match "window_id:<anchor>" --next-to "id:<anchor>"` (the same pattern `bin/it2-kitty` already
uses for Agent Teams teammate panes, which is why that path never hit this bug), and accepts
`--anchor <window-id>` to direct a resume at a DIFFERENT pane/window on request — "direct them to
other windows as needed" is the explicit override, not a restriction the default creates. Chain
further splits by passing the previous call's printed window id as the next `--anchor`, which is
how several resumed sessions stack into one column beside you. To relocate an ALREADY-RUNNING
pane after the fact (not at launch time), `kitty @ detach-window --match id:<id> --target-tab
id:<any-window-in-target-tab>` moves it live without killing the process — or right-click
(cmd+right) the pane for the same menu, point-and-click (`bin/kitty-pane-menu`, config/kitty.conf
§6c — iTerm2-parity "Move Session to…").
Verify your OWN window id from `$KITTY_WINDOW_ID` directly — do NOT infer "which pane is me" from
`kitty @ ls`'s `is_focused` flag, which tracks kitty's UI focus and can point at an unrelated pane
someone last clicked, not the pane actually running your shell (this is exactly the
misidentification bug above).

## Phase 3 — Un-stick after /compact (the #1 symptom)

Resume-from-summary runs `/compact`, then leaves each session **idle** (empty box, or `^[[<35;…M` /
`^[[?27;3;1R` gibberish) because it **drops the session's `/goal` Stop-hook**, so nothing auto-continues.

1. **Clear the gibberish** (per pane, windows ≠ yours): send Escape + Ctrl-U (chars 27, 21). For a
   stubborn multiline block, send Ctrl-C (char 3). Verify the input tail no longer contains `[<35;` /
   `[?27` / `[I[`.
2. 🚨 **CLASSIFY FIRST — re-engage ONLY the sessions the crash INTERRUPTED. A session that was
   already idle before the crash must be restored and LEFT ALONE.** Run the classifier on the
   winners and nudge only the `INTERRUPTED` rows:

   ```
   python3 ~/.claude/scripts/limit-recover/lr-select.py --scan --allow-missing-cwd \
     | ~/Development/claude-infrastructure/bin/cc-resume-classify.py --explain
   ```

   It appends a 5th column — `INTERRUPTED` / `AT-REST` / `UNKNOWN` — and `--explain` prints the
   evidence plus each at-rest session's own last words, which is what makes a wrong call visible
   before it costs anything. **`UNKNOWN` is treated as `AT-REST`.**

   **Why this is a rule** (operator ruling 2026-08-24). A recovery nudged all ten resumed sessions
   with "continue autonomously". Five had not been interrupted at all — they had stopped at a
   deliberate pause point, and the nudge sent them off doing work nobody had signed off. Their own
   closing words: *"…which is yours to authorise"* · *"still up for your feel check"* · *"Nothing
   open on my side. What would you like to work on?"* Operator: *"often already idle sessions are
   stopped at a good pausepoint waiting on a decision that needs more thought."*

   **The rule is `mid-turn AND alive-at-crash`, and both halves are load-bearing** — on the measured
   batch each one alone gets a real row wrong, in opposite directions. `wt-pool-6` finished its turn
   3.0 min before the crash, so the CLOCK alone convicts it (it was parked, awaiting a look).
   `wt-pool-8` was mid-turn but had been so for 2.8 DAYS, so the TAIL alone convicts it (it died
   days earlier; this crash interrupted nothing). Rationale, the fail-safe polarity, and a
   `--selftest` whose cases fail if either signal is dropped are in the script's header.

   ⚠️ **Phase 4's keepalive re-nudges on a timer, so it must be scoped the same way** — pass only
   the INTERRUPTED worktrees in `CC_KEEPALIVE_MARKERS`, or it re-pokes every parked session every
   240 s forever, which is the same defect on a loop.

3. **Re-engage the INTERRUPTED ones** with a continue-prompt via the reliable keystroke API — for
   each idle pane (skip any at an approval prompt: content has "Tab to amend"/"ctrl+e to explain";
   skip working panes: "esc to interrupt"):
   ```
   it2 session send -s <session-id> "<continue directive>"
   it2 session send -s <session-id> $'\r'     # Ink Enter = CR; send twice (belt-and-suspenders)
   ```
   Directive template: *"Continue autonomously with your goal: do your next task, commit it, and keep
   going. Stop only when genuinely done or blocked on auth/destructive-migration/undecidable."*
4. **Verify it took**: fresh `git log -1` commits in the worktrees are the ground-truth proof of work
   (the TUI "working" flag is a fast-moving snapshot). Expect bursty task→commit→pause.

## Phase 4 — Perpetual autonomy (keep them going)

Because the Stop-hook is gone, sessions pause between tasks. Start the keepalive watcher, which
re-nudges ONLY idle panes — it leaves working ones alone, skips decision-prompts, and skips a pane
that is legitimately awaiting its own armed watcher. 🚨 **Scope `CC_KEEPALIVE_MARKERS` to the
INTERRUPTED worktrees from Phase 3 only** — the watcher cannot tell a parked session from a stalled
one, so an unscoped marker list re-pokes every deliberately-parked session on a 240 s timer:

```
CC_KEEPALIVE_MARKERS="wt-a wt-b" nohup ~/.reso/bin/reso-keepalive 240 >>~/.reso/keepalive.out 2>&1 & disown
```

Interval 240s. Log: `~/.reso/keepalive.log`. **Stop: `pkill -f reso-keepalive`.**

**It re-discovers its targets every cycle by WORKTREE MARKER** — there is no ids file to capture or
re-capture, and a static id list goes stale the moment a session recycles. `CC_KEEPALIVE_MARKERS` is
a space-separated list; unset falls back to the built-in default, and an explicitly EMPTY value
exits rather than looping blind. *(This section used to prescribe `osascript … >
/tmp/reso-keepalive-ids.txt`. That interface has not existed since marker-rediscovery landed in
410f920c — the doc was describing a script that no longer read an ids file.)*

**BOTH TERMINALS, since 2026-08-17 (backlog a94c9e5722f7 · 71c2c19d6c63).** The watcher was
iTerm2-only, so on a **kitty** fleet this whole phase was INERT — measured 2026-08-10 after resuming
4 sessions onto next2/next4 in kitty, where 3 settled idle-at-prompt with nothing to re-nudge them,
which made this skill's own success criterion ("keepalive covering it", Phase 6) unreachable on the
terminal we actually run. It now drives kitty through `bin/it2-kitty`, the sanctioned adapter, and
matches markers against each kitty window's **cwd** (durable) rather than its scrollback (a sampling
surface — a long-running pane scrolls its worktree name off and silently stops matching).

The kitty arm is inert *by design* when the watcher itself is not running in a kitty pane and
`CC_TERM_KITTY_TO` is unset — driving panes in a window nobody is looking at is the failure the skip
predicates exist to prevent. When that happens it **says so once in the log** rather than reporting
nothing; an arm that is inert AND silent is exactly the defect this row filed.

Three skip predicates, declared once and applied to both terminals — override any of them with
`CC_KEEPALIVE_BUSY` / `CC_KEEPALIVE_PROMPT` / `CC_KEEPALIVE_AWAIT` if Claude Code rewords a footer:

| predicate | why the nudge is withheld |
|---|---|
| a turn is running (`esc to interrupt`) | never interrupt work in flight |
| a decision/approval prompt is on screen | a blind auto-typer that answers a permission dialog is worse than an idle pane |
| the pane is awaiting **its own armed watcher** (`N monitor(s) still running`) | "Awaiting ARMED is the legitimate non-close state" — nudging it interrupts a correct wait and can duplicate a wave collection. **Silence is not evidence of a stall** |

## Phase 5 — Cross-account quota view + routing (quality-of-life)

```
claude-accounts               # live table: auth state, k, 5h-session, weekly-ALL, weekly-Fable, resets, credits
claude-accounts --route general   # optimal account for the next general/Opus work-unit
claude-accounts --route fable     # optimal account for Fable work (window read live from model-config.yaml)
claude-accounts --json | --rank general|fable    # machine-readable rows / ranked list for wave spread
```

(`reso-quota` is now a compat shim to this — promoted 2026-07-10 into
claude-infrastructure/bin with the stale-JUL7 fix; entrypoint: `/accounts`.) Reads all 4
accounts live (tokens from Keychain `Claude Code-credentials-<sha256(dir)[:8]>`, acct
`chrisren`; heals a stale idle account via headless `claude auth login` — never a raw
refresh-and-discard, which risks rotation logout). The router is adversarially-verified
(use-it-or-lose-it × Fable-sub-cap coupling × 5h-cutoff safety × per-account concurrency
spread × the SSOT Fable window `frontier_access.end`). When routing says "none", the reasons
print on stderr (exhausted vs window vs excluded) — wait or spread manually. Logged-out
accounts show their email + Dia profile; re-auth via the `account-relogin` skill.
**Operator quota policy: maximize exhaustion of weekly-general AND weekly-Fable across all 4
before their resets (unused = destroyed); the Fable window end is the SSOT
`~/.claude/model-config.yaml frontier_access.end` — never a remembered date.**

## Success criteria
Every **winner**: worktree exists · resumed past the summary prompt · input box clean · re-engaged
(fresh commit or a running turn) · keepalive covering it. Report the tiered inventory + which are
working / at-a-prompt (needs the user) / idle-by-design.

**And the consolidation invariant: no worktree has more than one session resumed by this recovery,
and every session NOT resumed was listed with its reason.** A recovery that fired more than it
reported, or reported fewer candidates than it found, is a failed recovery even if every pane is
alive — that is exactly how the 2026-07-21 incident read as success while the machine ran out of RAM.
