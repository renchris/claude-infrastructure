# Part B2 — PermissionRequest beacon wiring (C10 operator-gated proposal)

**Backlog:** `cc-backlog 08d514250031` (project `claude-infrastructure`, source `desk-observed`).
**Design authority:** `docs/research/desk-anti-hitl-2026-07-19.md` **Part B, rec 2** (Fable research, 2026-07-19).
**Boundary (C10):** the agent *proposes* the wiring; it **never edits any `settings.json` in place** —
those files govern the agent's own permissions. The operator runs the apply step.

**Verdict in one line:** **WIRE** the beacon on four hook events — `write` on **`PermissionRequest`**
(catch-all), `clear` on **`PostToolUse`** (catch-all) + **`Stop`** + **`SessionEnd`**. It is a pure
**observer** (emits **no** permission decision), so it clears the Part B safety bar by construction — the
strictest boundary in the design (*"a weak boundary is strictly worse than the status quo"*) does not even
apply, because the beacon changes **no** decision. This is the opposite risk profile from the B1 auto-allow
hooks.

---

## 1. What this item builds vs. what the operator wires

| Layer | Artifact | Landed by this item? |
|---|---|---|
| The harness observer | `hooks/cc-permission-beacon.sh` (`write`/`clear`) | **yes** — in this commit |
| The out-of-session consumer | `scripts/lead-supervisor.sh` — `sweep_permission_pending` / `beacon_cmd` / `page_permpend` (a `permission_pending` IDL record + a `⛔ PERMISSION-PENDING` page) | **yes** — in this commit |
| Regression pins | `tests/cc-permission-beacon.bats` (12) + `scripts/supervisor-e2e.sh` T14–T19 (page/threshold/reap/damping), gated via `tests/lead-supervisor.bats` | **yes** — in this commit |
| The `settings.json` registration (4 events × 5 config dirs) | **this document** | **no** — operator hand-step (C10) |

The mechanism is inert until wired: the hook script ships symlinked into every `~/.claude*/hooks/` by
`install.sh:89-91` (the `for hook in "$REPO_DIR"/hooks/*.sh` loop), but **"wired nowhere" means it is
registered in no `settings.json` hook array** — nothing invokes it until §4 is applied.

## 2. Frozen scope

- **In scope:** the beacon hook, the supervisor read/page path, their tests, and this wiring proposal.
- **Out of scope (→ their own items):** the state-predicated `git reset --hard` auto-allow hook (Part B
  rec 1/5, `cc-backlog 062bdca35dd7`); the deny-floor gaps (`--force-with-lease:*`, `+`-refspec,
  executable-block `--dangerously-skip-permissions`, `desk-anti-hitl-2026-07-19.md:30`); Pushover wiring
  (rec 3). Each is its own backlog item.

## 3. Verified current state (re-grepped this session — not inherited)

**`PermissionRequest` is a real, live hook event** — this harness fires it when a tool call is gated on a
prompt. Live `~/.claude/settings.json` today wires three tool-scoped groups to `notify.sh`:

| event | matchers wired today | note |
|---|---|---|
| `PermissionRequest` | `Bash`, `AskUserQuestion`, `ExitPlanMode` → `notify.sh` | the beacon adds a **catch-all** (`matcher:""`) group — a superset, so it captures the `git reset --hard` Bash incident **and** every other hung prompt (question / plan-exit / tool-write) |
| `PostToolUse` | includes a `matcher:""` catch-all (`teammate-checkpoint.sh`) | confirms an empty matcher = all tools is a live, valid pattern |
| `Stop` / `SessionEnd` | matcher-less groups | the beacon's `clear` is added the same matcher-less way |

**There is NO `PermissionDenied` hook event in this harness.** The full live event set is `PreToolUse,
PostToolUse, SessionStart, SessionEnd, Stop, UserPromptSubmit, Notification, PermissionRequest,
TeammateIdle, WorktreeCreate, TaskCompleted, PreCompact`. The design's *"cleared by
PostToolUse/PermissionDenied/SessionEnd"* therefore substitutes **`Stop` for the non-existent
`PermissionDenied`** — and `Stop` is in fact the **stronger** universal clearer (see §5).

The payload fields the hook reads (`session_id`, `tool_name`, `tool_input`, `cwd`) are the canonical
Claude Code hook-input fields — the same ones `hooks/rm-safe-allowlist.sh:25` reads
(`.tool_input.command`). `tool_name` is guaranteed present (the live matchers select on it); the hook
degrades gracefully if `tool_input`/`cwd` are ever absent (`// {}`, `// ""`), so the worst case is a page
that names the tool without its argument — still actionable. **On first arm, tail `CC_PERMPEND_DIR` once
to confirm the live `tool_input` shape** (§6).

## 4. The wiring (C10 hand-step)

Four registrations. The `write` mode fires on the prompt; the three `clear`s fire on every resolution path.

```jsonc
// PermissionRequest — a NEW catch-all group (append; does NOT touch the existing Bash/question/plan groups)
{ "matcher": "", "hooks": [ { "type": "command", "command": "~/.claude/hooks/cc-permission-beacon.sh write", "timeout": 5 } ] }
// PostToolUse — a NEW catch-all group (the FAST clear on the grant path)
{ "matcher": "", "hooks": [ { "type": "command", "command": "~/.claude/hooks/cc-permission-beacon.sh clear", "timeout": 5 } ] }
// Stop — matcher-less (the UNIVERSAL clearer: fires after grant OR deny)
{ "hooks": [ { "type": "command", "command": "~/.claude/hooks/cc-permission-beacon.sh clear", "timeout": 5 } ] }
// SessionEnd — matcher-less (the backstop for a session that ends without a Stop)
{ "hooks": [ { "type": "command", "command": "~/.claude/hooks/cc-permission-beacon.sh clear", "timeout": 5 } ] }
```

**Idempotent apply — validated this session against a scratchpad *copy* of live `~/.claude/settings.json`
(never the live file — C10):** the transform is additive (appends new groups, mutates none), a re-run is a
byte-for-byte no-op, the result is valid JSON, and **everything outside `.hooks` is byte-identical**.

```sh
BEACON_JQ='
($write) as $w | ($clear) as $c |
.hooks = (.hooks // {})
| .hooks.PermissionRequest = ((.hooks.PermissionRequest // [])
    + (if ([.hooks.PermissionRequest[]?.hooks[]?.command] | index($w)) == null
       then [{"matcher":"","hooks":[{"type":"command","command":$w,"timeout":5}]}] else [] end))
| .hooks.PostToolUse = ((.hooks.PostToolUse // [])
    + (if ([.hooks.PostToolUse[]?.hooks[]?.command] | index($c)) == null
       then [{"matcher":"","hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
| .hooks.Stop = ((.hooks.Stop // [])
    + (if ([.hooks.Stop[]?.hooks[]?.command] | index($c)) == null
       then [{"hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
| .hooks.SessionEnd = ((.hooks.SessionEnd // [])
    + (if ([.hooks.SessionEnd[]?.hooks[]?.command] | index($c)) == null
       then [{"hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
'
W='~/.claude/hooks/cc-permission-beacon.sh write'
C='~/.claude/hooks/cc-permission-beacon.sh clear'
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"; [ -f "$f" ] || continue
  cp -p "$f" "$f.bak-$(date -u +%Y%m%dT%H%M%SZ)"                       # backup FIRST
  tmp="$f.tmp.$$"
  if jq --arg write "$W" --arg clear "$C" "$BEACON_JQ" "$f" > "$tmp" && jq -e . "$tmp" >/dev/null; then
    mv "$tmp" "$f"; echo "wired: $f"
  else
    rm -f "$tmp"; echo "SKIP (transform did not validate): $f"        # fail-closed: leave the file intact
  fi
done
```

(`install.sh` also re-runs this class of wiring on install — but the beacon is currently added by NO
installer step, so the operator runs the block above once; a later `install.sh` change could fold it in.)

## 5. Why the clears are complete — no stale page, no leaked beacon

A permission prompt is **always mid-turn**: the turn cannot `Stop` until the human answers. So every
resolution path is covered:

| Path | What clears the beacon | Latency |
|---|---|---|
| **Grant** | the granted tool runs → its **`PostToolUse`** fires (catch-all) | immediate — narrows the pending window to the true wait |
| **Deny** | the tool does not run, but the turn continues; the **next** tool's catch-all `PostToolUse`, else the turn's **`Stop`**, clears it | seconds |
| **Turn end (either)** | **`Stop`** — the universal clearer | end of turn |
| **Session close without a Stop** | **`SessionEnd`** | on close |
| **Hard-kill (kill-9 / OOM, no Stop, no SessionEnd)** | the supervisor **reaps** the beacon when its owning session's pid is provably dead, or past a long orphan horizon (`sweep_permission_pending`, REAP-1 / REAP-2) | ≤ one sweep / horizon |

**The catch-all `PostToolUse` clear is load-bearing, not redundant with `Stop`:** on a granted prompt in a
long autonomous turn, `Stop`-only would leave the beacon aged past the 120 s notice threshold → a **false**
`PERMISSION-PENDING` page for work that was already approved. Clearing on the granted tool's `PostToolUse`
eliminates that window. Its per-tool cost is a single `rm -f` of a usually-absent file (the hook exits in
ms).

The supervisor page uses a **separate `.permpend.notified` namespace** so `assess()`'s per-sweep
`clear_page` (a prompt-blocked session has stale telemetry) can never clobber it, and **damps to one notify
per pending episode** keyed by the beacon `ts` (a re-prompt is a new episode). Thresholds:
`CC_PERMPEND_NOTICE_S=120` (auto-approved tools clear in ms ⇒ no false page), `CC_PERMPEND_HORIZON_S=86400`.

## 6. Verification (operator)

```sh
# BEFORE — prove inert (expect 0 in every dir)
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  echo "$d: $(grep -c cc-permission-beacon.sh "$d/settings.json" 2>/dev/null)"
done

# AFTER — write on PermissionRequest, clear on PostToolUse + Stop + SessionEnd (expect 4 registrations/dir)
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq -r '"'"$d"': write@PermReq=" +
    ([.hooks.PermissionRequest[]?.hooks[]?.command|select(test("cc-permission-beacon.sh write"))]|length|tostring) +
    " clear@{Post,Stop,End}=" +
    ([.hooks.PostToolUse[]?.hooks[]?.command,  .hooks.Stop[]?.hooks[]?.command, .hooks.SessionEnd[]?.hooks[]?.command
      |select(test("cc-permission-beacon.sh clear"))]|length|tostring)' "$f"
done

# LIVE SMOKE — the hook round-trips a beacon, and confirms the PermissionRequest payload shape:
export CC_PERMPEND_DIR=/tmp/cc-permission-pending
printf '{"session_id":"smoke-1","tool_name":"Bash","tool_input":{"command":"git reset --hard origin/main"},"cwd":"/w"}' \
  | ~/.claude/hooks/cc-permission-beacon.sh write
cat "$CC_PERMPEND_DIR/smoke-1.json"     # → {"ts":...,"tool_name":"Bash","tool_input":{"command":"git reset --hard origin/main"},"cwd":"/w"}
printf '{"session_id":"smoke-1"}' | ~/.claude/hooks/cc-permission-beacon.sh clear
[ -f "$CC_PERMPEND_DIR/smoke-1.json" ] && echo "LEAK" || echo "cleared ✓"
# then, on first real arm, once: `ls /tmp/cc-permission-pending` after a genuine prompt — confirm the
# harness populates tool_input/cwd on a real PermissionRequest (the one field-shape we cannot unit-test).
```

## 7. Rollback

Restore the printed `*.bak-<ts>` files, or set the kill switch `CC_PERMISSION_BEACON_DISABLED=1` (the hook
no-ops in both modes) and/or `CC_PERMPEND_NOTICE_S` very high (the supervisor stops paging). The observer
emits no decision, so disarming it only removes visibility — it can never have widened any permission.

## 8. Safety recap (Part B thesis)

The beacon is the **safe half** of Part B: unlike an auto-allow hook, it makes **no** decision, so there is
no boundary to be *"strictly worse than the status quo."* Its payload is **harness-authored** (`session_id`
/ `tool_name` / `tool_input` / `cwd` arrive from the harness on the hook's stdin, not from
worker-influenced content) ⇒ **unspoofable**; a worker cannot forge a `PERMISSION-PENDING` page or suppress
one. Fail-open + fail-quiet: any parse/IO error exits 0 with no decision and no partial file, so the hook
can never block or alter a prompt. **The desk still never presses "1"** — this turns a silent 133-minute
hang into a precise, command-attached, minutes-latency escalation, and leaves the approve/deny call exactly
where it was: with a human or a live session.
