# Part B1 — permission auto-allow hook wiring (C10 operator-gated proposal)

**Backlog:** `cc-backlog ae0025d4bacc` (project `claude-infrastructure`, source `desk-observed`).
**Design authority:** `docs/research/desk-anti-hitl-2026-07-19.md` **Part B** (Fable research, 2026-07-19).
**Boundary (C10):** the agent *proposes* the wiring; it **never edits any `settings.json` in place** —
those files govern the agent's own permissions. The operator runs the apply step.

**Verdict in one line:** **WIRE** `ship-rail-push-allow.sh` (its activator is already built);
**KEEP INERT** `smart-bash-allowlist.sh` (documented do-not-arm decision — the repo's own doctrine,
the Part B safety thesis, and three concrete correctness defects all converge on this).

---

## 1. Frozen scope

The desk audit flagged a *latent gap*: two committed allow-hooks referenced in **zero** `settings.json`
PreToolUse configs across the 5 config dirs (`desk-anti-hitl-2026-07-19.md:30`). This item resolves that
gap by producing the operator-gated wiring proposal for **both** hooks. It does **not** build new hooks,
touch the deny-floor, or wire anything itself.

- **In scope:** the wiring recommendation + operator runbook for `ship-rail-push-allow.sh` and
  `smart-bash-allowlist.sh`.
- **Out of scope (→ backlog):** a tight feature-branch-push hook; the deny-floor gaps
  (`--force-with-lease:*`, `+`-refspec, executable-block `--dangerously-skip-permissions`,
  `desk-anti-hitl-2026-07-19.md:30`); the PermissionRequest beacon + reset-hard shape hook
  (Part B recs 2 & 5). Each is its own item.

## 2. Verified current state (re-grepped this session — not inherited)

Both hook **scripts** are symlinked into every `~/.claude*/hooks/` by `install.sh` (the
`for hook in "$REPO_DIR"/hooks/*.sh` loop, `install.sh:89-91`) — so "wired nowhere" means
**unregistered in the PreToolUse `hooks` arrays**, not absent on disk.

```sh
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  echo "$d: ship-rail=$(grep -c ship-rail-push-allow "$f") smart-bash=$(grep -c smart-bash-allowlist "$f")"
done
```

| config dir | `ship-rail-push-allow` | `smart-bash-allowlist` |
|---|---|---|
| `~/.claude` | 0 | 0 |
| `~/.claude-secondary` | 0 | 0 |
| `~/.claude-next` | 0 | 0 |
| `~/.claude-tertiary` | 0 | 0 |
| `~/.claude-quaternary` | 0 | 0 |

Premise confirmed: both inert in all 5 dirs. For reference, the Bash matcher's live `hooks` array today
is `[curl-gate.py, validate-bash.sh, git-worktree-guard.sh, keychain-guard.sh, rm-safe-allowlist.sh]` —
`rm-safe-allowlist.sh` **is** wired (it is the scoped rm hook; see §4), the two subjects of this item are not.

---

## 3. Hook 1 — `ship-rail-push-allow.sh` → **RECOMMEND WIRE**

A deterministic PreToolUse(Bash) hook that auto-allows exactly **one** shape — the non-force land push
`git push origin HEAD:<branch>` — and defers everything else (force in any form, other remote, bare push,
`-u`, compound/substitution/newline) to the existing `Bash(git push:*)` **ask**; the force-push **deny**
rules stay in force. It fixes T-P15-4 / G-P15-3: a model-issued land push
(`commands/ship.md`, the `/ship` land step) surfaces as a Bash tool call and strands the autonomous turn
on the `ask` with no human to approve. This is **Operator decision point #4** in
`docs/plans/ORCHESTRATOR_DESK_24X7_PLAN.md:162`.

**Why it clears the Part B safety bar:** allow is opt-in to one anchored shape; a non-force push cannot
rewrite trunk history (a non-fast-forward is server-rejected); kill switch
`SHIP_RAIL_PUSH_ALLOW_DISABLED=1`; hook silence/parse-error ⇒ normal prompt (fail-closed). Pinned by
`tests/ship-rail-push-allow.bats` (8/8, both directions).

**The activator already exists** (landed `9d2bf16`) — this item does not rebuild it:

| Artifact | Path |
|---|---|
| Runbook | `docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md` |
| Idempotent activator (dry-run default, `--apply`) | `docs/activation/ship-rail-push-activate.sh` |
| Hook | `hooks/ship-rail-push-allow.sh` |
| Tests | `tests/ship-rail-push-allow.bats` |

**Mechanism re-validated this session** against a scratchpad **copy** of live `~/.claude/settings.json`
(never the live file — C10): the activator's jq transform produces valid JSON, appends
`ship-rail-push-allow.sh` as an additional Bash-matcher hook (no duplicate on re-run), and leaves
everything **outside `.hooks.PreToolUse` byte-identical**. The transform is structural (locates the Bash
matcher via jq, never by line number), backs up each file (`*.bak-<ts>`), and validates before `mv`.

**Operator action (the C10 hand-step):**

```sh
./docs/activation/ship-rail-push-activate.sh          # DRY-RUN — shows the plan, writes nothing
./docs/activation/ship-rail-push-activate.sh --apply   # backs up, transforms, validates, mv
# verify:
printf '{"tool_input":{"command":"git push origin HEAD:main"}}' | ~/.claude/hooks/ship-rail-push-allow.sh
#   → permissionDecision:allow
printf '{"tool_input":{"command":"git push --force origin HEAD:main"}}' | ~/.claude/hooks/ship-rail-push-allow.sh
#   → (silent — defers to the ask + force deny)
```

Rollback: restore the printed `*.bak-<ts>` files, or set `SHIP_RAIL_PUSH_ALLOW_DISABLED=1`.

---

## 4. Hook 2 — `smart-bash-allowlist.sh` → **RECOMMEND KEEP INERT (do NOT arm)**

`smart-bash-allowlist.sh` is a **broad** allow hook: it greps the model-authored command string and
auto-allows five categories — `git commit`, `rm -rf <build-artifact>`, `sed -i <file>`,
`git push origin <feature>`, `chmod <safe-mode>`. Three independent lines of reasoning converge on
**not arming it**, and this item **closes the latent gap by recording that decision** (mirroring exactly
how the identical situation was closed for its `rm` logic — see reason A).

### A. The repo's own doctrine already decided this

`docs/L3-L4-AUTONOMY-ROADMAP.md:82-86` (rm-safe work, commit `ef7b997`):

> **Key learning:** the existing `hooks/smart-bash-allowlist.sh` already had dormant rm-allow logic but
> was registered in ZERO settings.json — **scoped a NEW rm-only hook instead of activating the broader
> one (blast radius). Allow is opt-in to a whitelist, never opt-out.**

So the precedent is explicit: when a shape is worth auto-allowing, **scope a tight hook for that one shape**
(`rm-safe-allowlist.sh`, now live-wired; `ship-rail-push-allow.sh` for the trunk land) — never arm the
broad `smart-bash-allowlist.sh`. Part B's sequencing (`desk-anti-hitl-2026-07-19.md:31`) lists **only**
`ship-rail-push-allow.sh` in the near-term arming order; `smart-bash-allowlist.sh` is deliberately absent.

### B. It is a pattern-matcher over worker-influenced content — the Part B thesis rules it out

The Part B guiding rule (`desk-anti-hitl-2026-07-19.md:4`):

> boundaries sit at **provable** safety (live state predicates, positive identity proof, fail-closed),
> **never at pattern-matching worker-influenced content. A weak boundary is strictly worse than the
> human-in-the-loop status quo.**

`smart-bash-allowlist.sh` decides purely by `grep`-ing the command string the model produced. That is the
exact "pattern-matching worker-influenced content" the design forbids as a load-bearing boundary. The tight
hooks (`ship-rail`, `rm-safe`) survive because each allows a single anchored shape with no worker-controlled
degrees of freedom that reach a dangerous target; the broad hook does not have that property.

### C. Concrete defects make a *global* arm actively unsafe (demonstrated this session)

1. **Fail-open absolute-path guards.** The "reject absolute paths outside the project" guards for `sed`
   (`hooks/smart-bash-allowlist.sh:111`) and `chmod` (`:135`) use a negative lookahead
   `(?!Users/chrisren/Development/...)` inside `grep -qE`. Negative lookahead is **not valid POSIX ERE** —
   `grep -qE` **errors** (non-zero) rather than matching, so the `if … then exit 0` reject branch is never
   taken and execution **falls through to `allow`**. Demonstrated:

   ```sh
   echo "/etc/passwd" | grep -qE '(\.\.|\*|\?|^/(?!Users/chrisren/Development))' \
     && echo "rejected" || echo "FELL THROUGH (rc=$?)"
   #  → grep: invalid syntax … / FELL THROUGH (rc=2)
   ```

   Consequence: `sed -i 's/x/y/' /etc/hosts` is **not** stopped by the outside-project guard; only the
   reso-specific `DENY_DIR` / `DENY_SENSITIVE` lists remain, and neither covers `/etc` — so an arm would
   auto-allow in-place edits to system files.

2. **Reso-hardcoded semantics.** The `sed` deny lists and the path anchors are reso paths
   (`/Users/chrisren/Development/reso-management-app`, `lib/error-logger`, `src/app/actions`, …). Wiring the
   hook into all 5 dirs applies reso's project semantics to **every** project — including
   `claude-infrastructure` itself, where those deny lists protect nothing.

3. **Last-token-only `sed` target.** `SED_TARGET` is extracted as the final whitespace token
   (`:108`), so a multi-file `sed -i 's/…/…/' safe.txt /etc/hosts` is checked only on the last token, and
   earlier targets are unvalidated.

### D. Shape-by-shape disposition — every category has a correct home that is *not* this hook

| `smart-bash` category | correct home | status |
|---|---|---|
| `git commit` | local + reflog-reversible; a scoped `commit-allow` hook only **if** a commit strand is observed | none needed now |
| `rm -rf <build-artifact>` | **`rm-safe-allowlist.sh`** (scoped, opt-in whitelist) | **LIVE-wired** |
| `git push origin HEAD:<branch>` (land) | **`ship-rail-push-allow.sh`** | activator built (§3) |
| `git push origin <feature>` (bare ref) | a scoped `feature-push-allow` hook **if** a bare-ref feature-push strand is observed | → backlog |
| `sed -i <file>` | a scoped, non-reso-hardcoded hook **if** a strand is observed | → backlog |
| `chmod <safe-mode>` | a scoped hook **if** a strand is observed | → backlog |

**Resolution:** the latent gap for `smart-bash-allowlist.sh` is **closed by this documented keep-inert
decision**, not by an arm — exactly as the rm case was closed. **No `--apply` activator is provided for
this hook by design**: shipping a turnkey apply would contradict the recommendation and hand the operator a
foot-gun. If a specific shape later proves to strand autonomous work, the doctrine-correct fix is a **new
tight hook** for that shape (fail-closed, single anchored shape, bats-pinned), not arming the broad matcher.

---

## 5. Verification (operator)

```sh
# BEFORE: prove both inert (expect ship-rail=0 smart-bash=0 in all 5 dirs)
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  echo "$d: ship-rail=$(grep -c ship-rail-push-allow "$f") smart-bash=$(grep -c smart-bash-allowlist "$f")"
done

# AFTER ship-rail --apply: ship-rail registered in every dir, smart-bash STILL 0 (must NOT be armed)
for d in ~/.claude ~/.claude-secondary ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do
  jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command]
         |index("~/.claude/hooks/ship-rail-push-allow.sh")!=null' "$d/settings.json" >/dev/null \
    && echo "ok  $d (ship-rail wired)" || echo "MISSING $d"
  jq -e '[.hooks.PreToolUse[]?|select(.matcher=="Bash").hooks[]?|.command]
         |index("~/.claude/hooks/smart-bash-allowlist.sh")==null' "$d/settings.json" >/dev/null \
    && echo "ok  $d (smart-bash correctly inert)" || echo "WARN $d smart-bash armed — review"
done
```

## 6. Follow-on backlog (not this item)

- Scope a tight `feature-push-allow.sh` **iff** a bare-ref `git push origin <feature>` strand is observed
  (not yet observed — do not build speculatively).
- Deny-floor hardening: `git push --force-with-lease:*`, `+`-refspec pushes, executable-block
  `--dangerously-skip-permissions` (`desk-anti-hitl-2026-07-19.md:30`).
- PermissionRequest beacon + reset-hard shape hook in shadow-then-arm (Part B recs 2 & 5).
- (If ever revisited) rewrite `smart-bash-allowlist.sh`'s fail-open lookahead guards before **any**
  consideration of arming — but the doctrine (§4.A/B) favors retiring it in favor of scoped hooks.
