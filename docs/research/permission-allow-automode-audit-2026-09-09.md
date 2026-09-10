# The 339 `permissions.allow` entries, audited against the auto-mode drop list

*2026-09-09 · closes cc-backlog `78b76e1a8311` (condition `allow-entries-never-audited-against-automode-drop`, filed 2026-08-21) · instrument `bin/cc-permission-audit --prune`, built for this row by `bd9ce93f3`*

## Verdict

**7 of the 339 allow entries in `~/.claude/settings.json` are inert under `--permission-mode auto`, 0 are redundant, and the inertness currently costs zero prompts.** All three numbers are measured, and the predicate that produces the first was verified against the binary this box actually runs rather than trusted from its source doc.

Report only. Deleting a dropped entry is a real semantic change the moment a session leaves auto mode, and applying any allowlist edit is operator-owned (three independent arms refuse an agent-side one). Nothing was written.

## Axis 1 — the auto-mode drop list: 7 of 339

```
/Users/chrisren/.claude/settings.json  (7 of 339 inert in auto mode)
  · Bash(bunx:*)              [`bunx` in bare/`:*` form — on auto mode's dangerous-command list]
  · Bash(env:*)               [`env` in bare/`:*` form — on auto mode's dangerous-command list]
  · Bash(node --version:*)    [`node` with a flag tail (`--version:*`) — auto mode drops the flag form]
  · Bash(node -e:*)           [`node` with a flag tail (`-e:*`) — auto mode drops the flag form]
  · Bash(python --version:*)  [`python` with a flag tail (`--version:*`) — auto mode drops the flag form]
  · Bash(python3 --version:*) [`python3` with a flag tail (`--version:*`) — auto mode drops the flag form]
  · Bash(python3:*)           [`python3` in bare/`:*` form — on auto mode's dangerous-command list]
```

The four sibling config dirs carry the identical 7 (`.claude-next` 339, `.claude-secondary` / `-tertiary` / `-quaternary` 338 each) — the same file, mirrored.

## Axis 2 — redundancy: 0 of 339

`~/.claude/settings.json` appears in **no** file block of the redundancy section. None of its 339 entries is a duplicate or shadowed by a broader sibling. Fleet-wide the picture is different — 388 provably-dead entries of 12,505 approved patterns (3.1%) across 195 discovered settings files, almost all of it worktree `.claude/settings.json` copies repeating four git entries already shadowed by `Bash(git:*)`.

## The predicate was verified against the LIVE binary, not its source doc

`auto_mode_dropped()` is transcribed from a decompile of **CC 2.1.220** and `bin/cc-permission-audit:388-392` flags it as the one load-bearing claim resting on non-probe sources that "can go stale in a way the redundancy predicate cannot". Sessions on this box no longer run 2.1.220 — `~/.zshrc:496` pins `~/.claude-260`. So the staleness risk was live and unmeasured.

Measured, by reading the three tables out of `~/.claude-260/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`:

| audit constant | live 2.1.260 symbol | result |
|---|---|---|
| `DROP_CMDS` (26) | `Swn = [...hwt, "zsh","fish","eval","exec","env","xargs","sudo"]` | **EQUAL** |
| `DROP_NET` (6) | `yGt = ["curl","wget","kubectl","aws","gcloud","gsutil"]` | **EQUAL** |
| `KUBECTL_VERBS` (18) | `Bl.kubectl` | **EQUAL**, both directions |

The 2.1.220 transcription still holds on 2.1.260. The 7-entry verdict above rests on a table read out of the binary that will decide it.

### One version-scoped over-report, recorded because it will matter on a rollback

On the two binaries under `~/.claude-versions/` (2.1.113 and 2.1.114, the pinned-stable lane) the net list is the empty spread — `sf7=[...k4_,"zsh",…,"sudo",...[]]` with **no** `["curl","wget","kubectl","aws","gcloud","gsutil"]` literal anywhere in the image. On those builds a `curl`/`wget`/`kubectl` allow rule is **not** dropped, so the audit's net arm over-reports there. Blast radius today: 10 rows across the whole 195-file scope, **none of them in `~/.claude/settings.json`**, whose 7 all come from the `DROP_CMDS` half. Not fixed here — the arm is correct for the binary in use, and a version-conditional predicate would need a version input the tool does not have. It becomes wrong only if the launcher is rolled back to the 2.1.11x lane.

## The inertness costs nothing measurable

Over the beacon archive's full range — **3,942 resolved prompts across 748 sessions, 2026-07-31 → 2026-09-09** — not one of the 15 ranked blocking command heads is a `python3`, `node`, `env` or `bunx` invocation. The 7 dropped entries are dead weight that reads as coverage, not a source of prompts.

What *does* block is `curl`: 721 `curl -sS` + 322 `curl -sL` + 293 `curl -s` = **1,336 of the observed prompts, the top three heads by a wide margin.** These are **not** a dropped-rule problem and cannot be fixed by adding one — `~/.claude/settings.json` has zero `curl` allow entries, and `curl` is on the live `yGt` net list, so any allow rule written for it would be discarded by auto mode before matching. That is the classifier prompting, and the drop list is what makes the distinction legible: an allow-list addition here would be inert by construction.

## Reproduce

    bin/cc-permission-audit --prune     # both axes, writes nothing
    bin/cc-permission-audit             # the observed-prompt half

Read the second one's rc, not a filtered pipe: `--prune` emits 1,251 lines and piping it through `head` truncates the AUTO-MODE section at a SIGPIPE that looks exactly like a crash.
