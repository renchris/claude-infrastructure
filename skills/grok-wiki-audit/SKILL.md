---
name: grok-wiki-audit
description: "Our recipe for a multi-shard defect sweep of a repo with grok-wiki ask: preflight checks (a broken claude stub, the codex config override), shard design, and verifying each finding against the pre-fix artifact before fixing it."
---

# Grok-Wiki as a defect sweep

The vendor skills (`grok-wiki-cli`, `grok-wiki-custom`) cover generation and Ask syntax. This
covers the one use that has paid for itself here: pointing `ask --mode deep` at a whole repo, in
shards, to find defects nobody was looking for. First round (2026-08-10): **five shards, 12 real
defects fixed and landed, 1 retracted.** Record: `docs/research/grok-wiki-audit-2026-08-10/`.

## Preflight — two facts, each of which silently ruins a run

**1. A broken `claude` stub on PATH makes every agent undetectable.** grok-wiki's detector spawns
every candidate unconditionally, so one `EACCES` throws the whole scan — and the error names no
agent, so it reads as "nothing installed", including `codex`. The `fnm_multishells` PATH entry
holds a non-executable 500-byte postinstall-failed npm shim. Strip it:

```bash
env PATH="$(echo "$PATH"|tr : '\n'|grep -v fnm_multishells|paste -sd: -)" grok-wiki agents --rescan
```

**2. The agent inherits its own config, not your flags.** `--reasoning high` produces no error and
changes nothing — `~/.codex/config.toml` wins. The first two shards of the first round silently ran
at `gpt-5.5`/`medium`. Read the config, and **update the CLI before reading its model list** (a
stale `models_cache.json` was simultaneously unreadable by the old client and hiding three
`gpt-5.6` models).

```bash
grep -E 'model|effort' ~/.codex/config.toml
```

## The sweep

Shard by SUBSYSTEM, one question file per shard, each shard reading the whole repo as context.
Under-scoping is what produces false findings: two of the first shard's six were artifacts of a
too-narrow shard.

```bash
env PATH="$(echo "$PATH"|tr : '\n'|grep -v fnm_multishells|paste -sd: -)" \
  grok-wiki ask /Users/chrisren/Development/claude-infrastructure \
  "$(cat /tmp/gw-q-<shard>.txt)" --agent codex --reasoning high --mode deep
```

Shards that worked: `hooks` · `scripts` (+bin) · `skills` · `launchd` · `tests`.

**The output is in `/tmp` and nowhere else.** Copy each shard's verbatim answer into
`docs/research/<sweep>/shard-<name>.md` as the FIRST action after it returns — the first round's
originals were one reboot from gone.

## Then do not trust it

A raw finding's base rate of being real is **well under 100%**. Three of the first round's were
wrong: two from shard scope, one (`session-index-sweep.sh`) survived filing and was disproved only
on follow-up, where the original repro proved `rc=0 with no DB` and could not distinguish "failed to
bootstrap" from "nothing to do".

So every finding gets both of these before a fix lands:

1. **Adjudicate against the real pre-fix artifact.** `git show origin/main:<file>` into a scratch
   path, run it on the failing input, observe the OLD behaviour, then the new. Run the pre-fix copy
   where `$REPO` still resolves inside the checkout — a copy run from `/tmp` exits early at an
   unrelated guard and acquits the bug.
2. **Fix the chokepoint, not the subject.** `settings.json` invoked `curl-gate-scope.sh`, which
   exited before `curl-gate.py` ever ran; fixing only the python would have turned the new suite
   green while production stayed exactly as broken.

File unverified leads as backlog rows with the verify-first instruction attached, never as fixes.

## If the app is gone, the behavior is not

The engine is not a service and not weights — it is prompts, in an unminified bundle:
`/Applications/Grok-Wiki.app/Contents/Resources/server/rlm-wiki.js` (13.6 MB, readable). It carries
**40 distinct `You are …` system-prompt openers (the census below), 28 `build*Prompt`
builders, and 5 `src/prompts/*.ts` modules**
(`prelude` · `structure` · `page` · `chat` · `ask-history`). The pipeline is a structure prompt
(table of contents) → a per-page prompt carrying that page's file list → repair loops (mermaid,
empty-diff, format-tune), each returning inside one `<ANSWER>...</ANSWER>` block.

```bash
grep -o "You are [A-Za-z -]\{10,90\}" /Applications/Grok-Wiki.app/Contents/Resources/server/rlm-wiki.js | sort -u
```

Read that way, a style is a prompt and nothing else, so any of it can be lifted into a skill or run
natively. What does NOT come across is state, not intelligence: per-page file selection,
concurrency, the `~/.rlm-wiki` store, and the sidecar that drives your local agent.
