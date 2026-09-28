# audit.md — should the Claude Code binary advance? (phases P2, P3, P8)

Paper evidence for a CC **binary** move: what Anthropic *said* changed, judged against how we work.
It never stands in for the gate (gate.md): the audit tells you what changed, the gate tells you
what broke. Run both, audit first.

Related memories: `hardened-version-management`, `feedback-detect-cc-runtime-not-claude-version`,
`version-identity-is-the-running-process-not-the-launcher`,
`resident-policy-must-not-restate-perishable-facts`.

🚨 **This file names NO version as current, deliberately.** It once pinned two versions by number
(historical: "eval 2.1.183 / stable 2.1.114") while the fleet had moved 37 releases on. A runbook
that restates a perishable fact has no path to learn it changed. Read every number live; dated
facts live only in holds.md.

## The two lanes

| Lane | Launchers | Binary | Governed by |
|---|---|---|---|
| **fleet** | `claude`, `cc` and the account/effort variants | the `_bin=` pin inside `~/.zshrc` `claude()`; read it with `cc-claude-bin --explain` | the activation script's `_bin` edit (gate.md § GREEN), nothing else |
| **legacy** | `claude-prev`, `cc-prev` (+ `claude-prev2/3/4`) | `claude-latest` → `~/.claude-versions/current`, a symlink to a version dir (`readlink ~/.claude-versions/current`) | MANIFEST default-deny (§ MANIFEST below) |

Every consumer that needs "the claude binary" goes through `bin/cc-claude-bin`; keying.md § Pins
has the ratchet that keeps it that way.

## Step 0 — detect the REAL running runtime (never `claude --version`)

`claude` is a shell function, so `claude --version` reports whatever the CURRENT `~/.zshrc` pin
resolves to, not what this session is running. A pane started before a repoint keeps its old
`claude()` body and its old binary. In order of authority:

- **`ps -o command= -p $PPID`** — the running process's own argv, carrying the real
  `~/.claude-<NNN>/node_modules/.bin/claude` path. The only reading that cannot lie, because it
  interrogates the process rather than a name that resolves elsewhere.
- `echo $CLAUDE_CODE_EXECPATH` → `.../.claude-<NNN>/...`
- `echo $AI_AGENT` → `claude-code_2-1-XXX_agent`

Fleet-wide: `ps -axo pid=,command= | awk '$2 ~ /\.claude-[0-9]+\//'` lists every live session's
binary (the census model.md Case A step 0b needs before any flip).

## Step 1 — establish the target (do NOT trust the `stable` dist-tag)

```bash
npm view @anthropic-ai/claude-code dist-tags time --json   # stable / latest / next + publish times
cc-claude-bin --explain                                 # fleet lane pin
readlink ~/.claude-versions/current                         # legacy lane
```

**The npm `stable` dist-tag is not a reliability signal and not a route to a new model** — one
copy of this trap, here. It has pointed into a self-destructing-daemon regression window, trailed
`latest` by several releases, and lacked a newly released model id that only `latest` carried
(each measured, historical). Check the tag you are actually about to install; judge from the
CHANGELOG + churn, never the tag.

## Step 1b — discharge the standing HOLD → holds.md § 1

**Slice floor:** read the CHANGELOG from the version we ACTUALLY RUN (Step 0), never from
`latest` minus a few. A fix for a held-open issue can land in any release in the gap, and skipping
the early ones is how a discharged blocker gets missed.

## Step 2 — fetch + slice the CHANGELOG gap

```bash
curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md -o /tmp/cc-changelog.md
grep -n "^## 2\.1\." /tmp/cc-changelog.md | head -40   # locate the gap: our-version → target
```

Read every version between the running version and the target.

## Step 3 — fan out the assessment (Dynamic Workflow, 3 axes + adversary)

Four read-only slots, `agentType: 'workflow-lean'`, each with a self-contained brief naming the
changelog slice and the config paths it reads (research-subagents skill § Workflow slot table for
the model/effort pins). Each rates every change BLOCKER / CAUTION / IMPROVEMENT / NEUTRAL:

1. **Agent Teams / effort / worktree** — implicit-team spawn, TeammateIdle reap, it2/tmux pane
   backend, per-member effort, worktree isolation, depth-cap/fork.
2. **Background subagents / Dynamic Workflows / model+cost defaults** — background-by-default
   subagents, workflow `agent()`/schema behaviour, daemon reliability + regression WINDOWS, Explore
   model/cost, default-model and alias flips vs reso's pins.
3. **Hooks / permission modes / auto-mode / launchers** — matcher semantics, SessionStart
   streaming/idle-reap, Stop/Notification, auto-mode destructive-cmd blocks + transcript-tamper
   rules, default-permission-mode flip, AskUserQuestion.
4. **Adversary** (web-enabled): sweep `github.com/anthropics/claude-code/issues` for OPEN
   regressions in the target band that the changelog omits; default to flagging risk; a sharp
   ≤450-token verdict.

Every axis also walks holds.md § 2 (the standing reso landmines).

## Step 4 — churn signal (the load-bearing judgment)

A version that FIXES a daemon/hook regression means that subsystem was recently broken. **Set the
safe floor at the LAST fix in a regression cluster, not the first version that looks clean**
(historical: a daemon self-kill shipped in 2.1.196 and was fixed across 199–203, so the floor was
the last fix, 2.1.203, not the `stable` tag's 2.1.197 — historical). A version with <1 week of
field exposure is a moving target regardless of changelog.

🚨 **Measure that week as AGE SINCE PUBLISH, never as tenure on the `latest` tag.** Measured over
the package's whole npm history (historical, 2026-08-20): almost no version has ever held `latest`
for ≥7 days, because releases ship about every 1.5 days. A criterion phrased "≥1 week as npm
`latest`" is therefore **unsatisfiable** — it clears only on a shipping pause, so an audit gated
on it returns HOLD forever without that being an evidence-based verdict (backlog `b69b1d957cec`).
Age since publish keeps accruing after a version stops being `latest`, which is what soak means.

```bash
npm view @anthropic-ai/claude-code time --json | jq -r --arg v "$TARGET" '.[$v]'   # publish date
# tenure-as-latest, only ever as a CONTRAST — never as the gate:
npm view @anthropic-ai/claude-code time --json | jq -r '
  to_entries | map(select(.key|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
  | map(.value |= sub("\\.[0-9]+Z$";"Z")) | sort_by(.value) | . as $v
  | [range(0;length-1) | {ver:$v[.].key,
      days: ((($v[.+1].value|fromdateiso8601)-($v[.].value|fromdateiso8601))/86400*100|round/100)}]
  | sort_by(-.days) | .[0:5][] | "\(.ver)\t\(.days) d"'
```

(`fromdate` throws on npm's millisecond timestamps — strip the fractional seconds first, as above.)

The operator mandate (gate.md) may override a failed age bar: the bar is a PROXY for field
evidence, and a GREEN gate is the evidence itself. Record the override in the MANIFEST note and
the activation script's header.

**Sizing the jump honestly.** Registration (cc-model-registered) is ONE axis. Hooks, Stop-hook
semantics, auto mode, the effort ladder, spawn depth, permissions, settings-schema keys and MCP are
all unmeasured by it; the gate measures them. The dangerous shape is a settings key or hook field
that is silently *dropped* rather than loudly rejected. Precedent (historical): 2.1.219 changed
the nested-subagent spawn-depth default to 3, re-opening GH #68619 (a 4M-token/5-min runaway) on
this spawn-heavy box — carry `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` across every bump.

**What the gate does NOT cover, so the audit must:** the AskUserQuestion idle-timeout in launcher
profiles (a default change stops auto-continue), and re-pricing fan-outs when the Explore model
default moves (research-subagents skill). Everything else the old pre-flight list asked by hand —
a teammate lifecycle smoke, `--permission-mode auto` non-blocking, explicit `model:` on teammate
spawns — is gate checks #3, #7, #10 and #11 now; do not redo them by hand.

## P3 — install the candidate without burning the bridge

```bash
npm install --prefix ~/.claude-<NNN> @anthropic-ai/claude-code@<ver>
```

A new prefix exists and the **old prefix is untouched** — it is the rollback. Nothing to undo.
Then `cc-model-registered <id> --bin ~/.claude-<NNN>/node_modules/.bin/claude` for any model
id this run needs.

## Verdict + MANIFEST governance (the auto-install trap)

Two guards, and both must stay intact:

- **CC's built-in self-updater is off**: `DISABLE_AUTOUPDATER=1` is exported by every launcher
  (grep `~/.zshrc` and `~/bin/claude-latest` for it; do not trust a recalled name — an earlier
  audit miscalled it `DISABLE_AUTOREPATCH`, which does not exist).
- **The legacy lane's bump is default-deny**: `claude-latest` reads `MANIFEST.jsonl` and
  auto-installs a newer version ONLY if its `status` is `stable` or `candidate`; `skip` or no entry
  ⟹ refused. So on the legacy lane a `candidate` entry TRIGGERS the advance — that is the trap.

The MANIFEST `status` governs ONLY that legacy lane. **The fleet lane does not read it**; the fleet
pin moves only through the activation script's `_bin` edit. So a row can say `skip` while the
fleet advances past it — say which in the note.

- **To HOLD** (and for every version the legacy lane must not take): `status:"skip"`. Put the
  conditional-advance playbook in the `notes`.
- **To ADVANCE the legacy lane**: `status:"candidate"` only when actually ready to install there,
  after a GREEN gate. `stable` only after soak.
- Entry shape (append after the last line via Edit, never overwrite):
  `{"version":"X","status":"skip|candidate|stable","date_added":"<ISO>","notes":"<why + citations + REVISIT when: … + [[memory-link]]>"}`.
  A band audit writes one row per version; the last row carries the `REVISIT` trigger holds.md reads.

## Rollback

Put the launcher's `_bin` back to the prior `~/.claude-<NNN>` and revert the keying diff
**together** (model.md, keying.md). What does NOT come back with it: any
`claude-bump-models --apply` sweep already run (re-run it `--from-to <new> <old>`), and anything a
session wrote while running the new binary.

🚨 **A CC-version rollback silently drops capabilities that live in the binary, not in our
config.** Canonical instance (historical): rolling 2.1.170 → 2.1.114 dropped the long-horizon
harness — the autonomous-loop preamble, the "check your last paragraph before ending the turn"
early-stop instruction, and the `SendUserMessage` verbatim tool all lived in the newer binary. The
CLASS is permanent and matters more with one fleet lane, because a rollback moves the whole fleet.
A model-only change (model.md Case C) keeps the binary pin and is unaffected. After any rollback,
re-verify that autonomous `/loop`, `/frontier-run` and `/schedule` still self-terminate and report
correctly, and re-run the gate on the rolled-back build rather than assuming it behaves as
remembered.

## P8 — record

1. MANIFEST rows (above), one per assessed version.
2. The run ledger row (router § Ledger) with the verdict and evidence paths.
3. A `claude-code-<range>-*.md` memory + MEMORY.md index line only for what generalises (the
   anti-capture list applies: no transient failures, no this-machine facts).

## Output

A briefing: (1) one-line VERDICT (hold vs target, per lane), (2) blockers + mitigations, (3)
cautions to re-verify, (4) net improvements, (5) the recommended action + the MANIFEST rows. Never
move the fleet lane on an audit alone: the gate decides.
