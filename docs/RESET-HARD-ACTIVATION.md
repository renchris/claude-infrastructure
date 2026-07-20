# reset-hard-shadow-allow — ACTIVATION runbook (C10: human-only)

The build is **complete, tested, and landed**: `hooks/reset-hard-shadow-allow.sh` is a
state-predicated PreToolUse(Bash) hook that auto-allows the ONE reflog-reversible reset shape
(`git reset --hard origin/main` / `git reset --hard @{u}`) — but ships in **SHADOW mode** and turns
on auto-allow only after a deliberate, operator-gated arm. `tests/reset-hard-shadow-allow.bats`
(15 tests, all green) pins both directions. What remains is **activation**, which is **C10
(human-only)**: an agent must never edit the settings that govern its own permissions. The agent
built + tested + wrote this runbook + `docs/activation/reset-hard-activate.sh`; **the operator runs
it.** The agent NEVER edits any `settings.json` in place and NEVER arms.

Binding design: `docs/research/desk-anti-hitl-2026-07-19.md` **Part B** (adversarial-safety, the
`git reset --hard` incident class). cc-backlog: `062bdca35dd7`.

## What it fixes

`Bash(git reset --hard:*)` sits in the **`ask`** array of the settings.json files
(`~/.claude/settings.json:407`) — a deliberate operator judgment point, everywhere. 24/7 autonomous
work **strands** on it: incident 731f0968 hung **133 min** because *nothing can answer a prompt*.
The design verdict (§B, BINDING) is that **the desk must never learn to press "1"** —
keystroke-approval is fundamentally unsafe (screen-spoof, TOCTOU, and the "Yes, don't ask again"
ratchet that writes a *permanent* silent allowlist entry). Bounded loss (latency) beats unbounded
loss (a rewritten trunk). The provably-safe alternative is a **same-process hook that checks live
state atomically with the decision** — a keystroke never can.

## Safety model (why this is safe to auto-allow — once armed)

Allow is **opt-in to one provably-reversible shape**; **three conjuncts, all required**, evaluated
in the **same process** as the decision (atomic — no TOCTOU window a keystroke has):

1. **SHAPE** — the anchored single command `git reset --hard <T>`, `T ∈ {origin/main, @{u}}`, and
   nothing else: no compound / substitution / redirection / newline (the ship-rail metachar guard),
   no extra flag, no leading `-C` / env-prefix, no other target. The anchor is an **all-positive
   allowlist** match — never a negated lookahead (a `grep -qE '(?!…)'` guard is invalid ERE on
   macOS/BSD → errors → **fails open**; memory
   `reference-grep-lookahead-fails-open-and-tight-allow-hook-doctrine`).
2. **CLEAN TREE** — `git status --porcelain` empty at decision time ⇒ the reset discards **no**
   uncommitted work; it only moves the branch ref, which the reflog fully reverses.
3. **SANCTIONED WORKTREE** — cwd is a **linked** git worktree (`absolute-git-dir` under
   `.git/worktrees/`), never the primary shared checkout (a `reset --hard` there can disrupt a
   concurrent session sharing the index) and never a non-repo dir.

**Fail-closed**: any parse error / git failure / uncertainty ⇒ the hook is **silent** ⇒ the normal
`ask:407` prompt fires. The hook can only ever ADD an allow to a provably-safe case; it never denies
and never widens. Kill switch: `RESET_HARD_ALLOW_DISABLED=1` (defers everything, incl. shadow logs).

## What gets activated

| Primitive | File | Activation act | Blast radius |
|---|---|---|---|
| the hook script | `hooks/reset-hard-shadow-allow.sh` | symlink into `~/.claude/hooks/` | one file, reversible |
| registration | 5× `settings.json` | append to the PreToolUse **Bash** matcher's `hooks` array | +1 array element/file; `ask` rule untouched |

## Sequencing — SHADOW first, ARM after a clean soak (Part B §B.5)

Each step is independently reversible.

### Step 1 — wire in SHADOW (starts the soak; does NOT auto-allow anything)

```sh
# DRY-RUN first — shows exactly which files would change, validates the jq transform, writes nothing:
./docs/activation/reset-hard-activate.sh

# APPLY — backs up every file (*.bak-<ts>), transforms via jq to a temp, validates JSON, then mv:
./docs/activation/reset-hard-activate.sh --apply
```

The script is **idempotent** (re-runs report "already registered", never double-insert) and
**structural** (locates the Bash matcher via jq, never by line number — settings byte-sizes differ
per account). Once wired, the hook **logs** a would-allow for each qualifying reset but emits **no
decision** — the `ask:407` prompt still fires, so every real reset is still human/desk-approved.
This is the observation phase.

### Step 2 — review the soak

```sh
~/.claude/hooks/reset-hard-shadow-allow.sh status
jq -c 'select(.decision=="would-allow")' ~/.claude/logs/reset-hard-allow-shadow.jsonl
```

A **clean soak** = every logged would-allow is a legitimate reflog-reversible reset (expected cwd,
expected target `origin/main`/`@{u}`, a worktree you meant to include) and **nothing surprises you**.

### Step 3 — ARM (turns auto-allow on; deliberately gated)

```sh
~/.claude/hooks/reset-hard-shadow-allow.sh arm --confirm   # a bare `arm` REFUSES (prints the checklist)
```

Now the proven shape auto-allows (no prompt) whenever the tree is clean in a linked worktree; every
other reset still prompts. Revert anytime:

```sh
~/.claude/hooks/reset-hard-shadow-allow.sh shadow          # back to log-only
# or, without unwiring:  export RESET_HARD_ALLOW_DISABLED=1
```

## Verify after wiring (still SHADOW)

```sh
# valid shape on a clean LINKED worktree → SILENT (shadow: no decision) but a would-allow is logged:
printf '{"tool_input":{"command":"git reset --hard origin/main"},"cwd":"'"$PWD"'"}' \
  | ~/.claude/hooks/reset-hard-shadow-allow.sh            # → (no output); check `status` for the log

# unsafe/other shape → SILENT (defers to the ask prompt):
printf '{"tool_input":{"command":"git reset --hard HEAD~3"},"cwd":"'"$PWD"'"}' \
  | ~/.claude/hooks/reset-hard-shadow-allow.sh            # → (no output)

# full regression:
bats tests/reset-hard-shadow-allow.bats                   # 15 tests, all pass

# registered in every settings.json:
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command]|index("~/.claude/hooks/reset-hard-shadow-allow.sh")!=null' "$d/settings.json" >/dev/null && echo "ok $d" || echo "MISSING $d"
done
```

## Rollback

The apply run prints exact `mv` commands to restore each `*.bak-<ts>`. Nothing destructive: the hook
script stays on trunk; removing the registration (or restoring the backup) fully reverts. To disable
without unwiring: `RESET_HARD_ALLOW_DISABLED=1`. To stop auto-allow but keep the soak log:
`reset-hard-shadow-allow.sh shadow`.

## Note on the hook event (`PreToolUse`, not a distinct `PermissionRequest` event)

Part B §B.1 refers to "PermissionRequest decision hooks". In the running binary (stable 2.1.114) the
**proven, live-wired** mechanism for a harness-authored permission decision is a **`PreToolUse`**
hook emitting `hookSpecificOutput.permissionDecision:"allow"` — exactly what the already-live
`rm-safe-allowlist.sh` (`settings.json:444`) and `ship-rail-push-allow.sh` do, and what §B.1 tells
us to "extend". This hook uses that same proven mechanism. If a future CC version exposes a distinct
`PermissionRequest` event that fires only when the ask would show (narrower than every-Bash-call),
the decision logic here ports verbatim — only the matcher/event name in the wiring changes.

## Follow-on (optional)

`docs/activation/wiring-all.sh` bundles the activation scripts. This hook is deliberately kept as a
**standalone** activate so starting the soak is an explicit operator choice; add it to the bundle
only if you want it wired alongside the rest by default (still shadow — arming stays separate).
