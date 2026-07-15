# Never-let-completion-go-silent (comms) — ACTIVATION runbook (C10: human-only)

The comms-safety build is **complete, RED-proven, and landed**; `scripts/comms-safety-gate.sh` is GREEN
(`5 met · 0 failed · 0 NOT BUILT` — *"completion cannot go silent"*). F1–F5 are **standalone tools + a lint
+ a doc**. What remains is **activation — wiring the live exit/ship recipes to CALL them — which is C10
(human-only).** The agent built + tested + wrote this runbook + `/tmp/comms-safety-activate.sh`; **the
operator runs it.** The agent NEVER edits `scripts/handoff-fire.sh`, `bin/cc-wait`, or
`scripts/lead-reconciler.sh` in place — that build-vs-activation split is what keeps the C10 line.

## What the pieces do

- **F1 `bin/cc-announce`** `<role|name|uuid> "<msg>"` — the VERIFIED-or-LOUD announce primitive. Trusts only
  cc-notify's `submit VERIFIED`; retries once; on mailbox-only / stranded / unresolvable → a LOUD alarm
  record (`~/.claude/cc-announce-alarms/`, `CC_ANNOUNCE_ALARM_DIR`) + non-zero. Resolves a **role** via
  `~/.claude/cc-roles/<role>` (`CC_ROLES_DIR`) → a target, else passes the token to cc-notify.
- **F3 `scripts/payload-lint.sh`** `<payload>` — a successor-fire payload missing the back-channel block
  (a cc-notify line + the desk FULL uuid) → RED; a terminal-announce via SendMessage → RED.
- **F4 `scripts/exit-deadline.sh`** `resolve [--default s] [--exit s]` — the effective wait/sweep deadline:
  **900s during an exit sequence** (`CC_EXIT_SEQUENCE` truthy OR the flag file
  `~/.claude/exit-sequence.flag`, `CC_EXIT_SEQUENCE_FLAG`), the default otherwise.
- **F5 `scripts/completion-push.sh`** `fire --event <desc>` — a program-terminal completion → an OPERATOR
  push via cc-announce; a record is captured BEFORE the push (`~/.claude/completion-push/`); a non-verified
  push exits non-zero (LOUD).

## Activation (run `/tmp/comms-safety-activate.sh`, opened in Cursor)

1. **Deployed verification** — `scripts/comms-safety-gate.sh` is GREEN and each `--selftest` fires.
2. **Role map (YOU write it).** Bind the roles the recipes name to live targets:
   ```sh
   mkdir -p ~/.claude/cc-roles
   printf '%s\n' '<DESK-PANE-UUID>'  > ~/.claude/cc-roles/desk          # the orchestrator desk
   printf '%s\n' '<OPERATOR-TARGET>' > ~/.claude/cc-roles/operator      # what reaches YOU (a pane uuid, or the desk if it relays)
   printf '%s\n' '<DESK-PANE-UUID>'  > ~/.claude/cc-roles/orchestrator
   ```
   Recipes then say `cc-announce desk "…"` — a role, never a rotting uuid. Rebind here when a pane recycles.
3. **Wire F5 into the exit recipe (YOU edit it — the agent never does).** In `scripts/handoff-fire.sh`, in
   the `self-close --terminal` path (end-of-line; nothing continues → today the operator is NOT pushed),
   immediately before the close chain, call:
   ```sh
   "<REPO>/scripts/completion-push.sh" fire --event "program-terminal: <what completed>" --detail "<final state>"
   ```
   completion-push pushes the operator via cc-announce (VERIFIED-or-LOUD) and records it — the terminal
   event is never silent. (The `--successor` path already announces into the survivor via cc-notify; leave it.)
4. **Wire F4 into the wait/sweep deadlines (YOU edit them).** Touch the exit-sequence flag at exit-start and
   remove it at exit-end, so the tightening is scoped:
   ```sh
   : > ~/.claude/exit-sequence.flag                 # at the START of a self-close / ship sequence
   #   … cc-wait / lead-reconciler read their deadline from:  scripts/exit-deadline.sh resolve
   rm -f ~/.claude/exit-sequence.flag               # at the END
   ```
   In `bin/cc-wait` / `scripts/lead-reconciler.sh`, replace the hard-coded `3600` deadline/sweep default with
   `"$(<REPO>/scripts/exit-deadline.sh resolve)"` (each may pass its own `--default/--exit` pair).
5. **Wire F3 into fire-payload generation (YOU edit it).** Before firing a successor payload, lint it:
   ```sh
   "<REPO>/scripts/payload-lint.sh" "$PAYLOAD_FILE" || { echo "payload missing the back-channel block — fix before firing"; exit 1; }
   ```

## Verify after activation

```
scripts/comms-safety-gate.sh                       # 5 met · 0 failed · 0 NOT BUILT
cc-announce <desk-role> "activation smoke"          # prints 'submit VERIFIED' to a live desk pane
scripts/completion-push.sh fire --event "smoke"     # a push record in ~/.claude/completion-push/, VERIFIED
CC_EXIT_SEQUENCE=1 scripts/exit-deadline.sh resolve # 900 (else 3600)
```

## Rollback

Remove the inserted `completion-push` / `exit-deadline` / `payload-lint` calls and the role-map files.
Nothing else changed; the tools on trunk are untouched. No data migration, nothing destructive.
