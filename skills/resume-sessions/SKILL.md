---
name: resume-sessions
description: >
  Recover and autonomously resume all Claude Code sessions across the 4 accounts (next/next2/next3/next4)
  after a crash or reboot, and un-stick sessions that stalled after /compact. Finds the open sessions,
  recreates reaped worktrees, resumes WITHOUT the blocking "resume from summary" prompt, clears terminal
  escape-sequence gibberish, re-engages each session with a continue-prompt (via the reliable it2 keystroke
  API, not osascript write text), and keeps them working with a keepalive watcher. Also gives a live
  cross-account quota view + optimal work routing. Use when: the machine crashed/rebooted with sessions
  open; sessions look "stuck" after resume→/compact (empty input box or ^[[<35;… / ^[[?27 gibberish);
  the user says "recover my sessions", "resume the crashed sessions", "restart my Claude sessions",
  "un-stick the sessions", "view usage across accounts", or invokes /resume-sessions.
---

# Resume Sessions — crash recovery + autonomous restart (100th-percentile runbook)

The tools live in `~/.reso/bin/` (`reso-resume-one`, `reso-keepalive`, `reso-quota`). Deep rationale,
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
~/.claude/scripts/limit-recover/lr-select.py --scan            # stdout: TSV winners, stderr: triage
```

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
reaped** (`git worktree add`; branches survive worktree deletion — verify with `git show-ref`), **reset
mouse reporting** (stops crashed-session escape-seq garbage), **auto-answer the large-session "Resume
from summary" prompt** via `expect` (picks summary = quota-cheap; **timeout 240s** because big sessions
take >60s to reach the prompt — a short timeout leaves them stuck), then hand off to a live session.
For the Fable session use account `fable4` (etc.) to keep it on `claude-fable-5`.

**Layout** (default = window per account, split panes; ask if unsure): create an iTerm2 window per
account with `create window` then `split vertically/horizontally with default profile`, and run the
`reso-resume-one` command in each pane. NEVER reuse the current window's `current session` for the first
pane — that's YOUR tab (off-by-one); always create a fresh window. Protect your own session by
`${ITERM_SESSION_ID##*:}` before any bulk pane-close (`~/.claude/bin/it2 session close -f -s <id>` is the
modal-free close, but it does NOT reap the process — `kill` surviving `claude … --resume` PIDs too).

## Phase 3 — Un-stick after /compact (the #1 symptom)

Resume-from-summary runs `/compact`, then leaves each session **idle** (empty box, or `^[[<35;…M` /
`^[[?27;3;1R` gibberish) because it **drops the session's `/goal` Stop-hook**, so nothing auto-continues.

1. **Clear the gibberish** (per pane, windows ≠ yours): send Escape + Ctrl-U (chars 27, 21). For a
   stubborn multiline block, send Ctrl-C (char 3). Verify the input tail no longer contains `[<35;` /
   `[?27` / `[I[`.
2. **Re-engage each** with a continue-prompt via the reliable keystroke API — for each idle pane
   (skip any at an approval prompt: content has "Tab to amend"/"ctrl+e to explain"; skip working panes:
   "esc to interrupt"):
   ```
   it2 session send -s <session-id> "<continue directive>"
   it2 session send -s <session-id> $'\r'     # Ink Enter = CR; send twice (belt-and-suspenders)
   ```
   Directive template: *"Continue autonomously with your goal: do your next task, commit it, and keep
   going. Stop only when genuinely done or blocked on auth/destructive-migration/undecidable."*
3. **Verify it took**: fresh `git log -1` commits in the worktrees are the ground-truth proof of work
   (the TUI "working" flag is a fast-moving snapshot). Expect bursty task→commit→pause.

## Phase 4 — Perpetual autonomy (keep them going)

Because the Stop-hook is gone, sessions pause between tasks. Start the keepalive watcher, which
re-nudges ONLY idle panes (leaves working ones alone; skips decision-prompts):

```
osascript … > /tmp/reso-keepalive-ids.txt   # capture the pane session-ids (skip your own)
nohup ~/.reso/bin/reso-keepalive 240 >>~/.reso/keepalive.out 2>&1 & disown
```

Interval 240s. Log: `~/.reso/keepalive.log`. **Stop: `pkill -f reso-keepalive`.** (Re-capture the ids
file if you rebuild the pane layout.)

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
