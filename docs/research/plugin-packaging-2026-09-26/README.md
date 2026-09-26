# Packaging claude-infrastructure as Claude plugins — should we, and what?

Scope (frozen): investigate whether and what to package from claude-infrastructure, whole or in
modules, as a Claude plugin; prompted by the 2026-09-25 plugin-directory launch
(https://x.com/ClaudeDevs/status/2103577007938228300, https://claude.com/blog/build-plugins-for-claude).
Research only: nothing was built, submitted or installed.

## Answer

1. **Do not package the repo as a whole, and do not move our own `~/.claude` deploy onto
   plugins.** (conviction 95%) The directory cannot take it: the GitHub archive is 151.9 MiB
   against a 50 MiB cap, even for a subfolder submission, and there is no LICENSE (02). The hooks are
   one coupled, order-dependent system: 49 of 96 read transcripts, 47 call `cc-*` tools and 16
   source `hooks/lib`, none of which a plugin carries (05, 10). For self-consumption, an in-place
   local marketplace gives the same live-edit loop as today and renames every skill and agent
   (`infra:…`). A cached marketplace gives atomic versioned activation, but only for the
   prompt-and-hook half, and mixes versions with the 122 `cc-*` tools and 348 scripts, which must
   stay symlinked (08).

2. **If we publish anything, publish a small carve-out from a NEW repo, not from this one.**
   (conviction 75%. The residual is the operator's appetite to maintain a public product, not a
   missing fact.) A new repo is what makes the 50 MiB, LICENSE, symlink, 512-file and 256 KiB
   review gates passable (01, 02). It also stops ~6 hook commits a day on this trunk from
   auto-updating onto strangers' machines unreviewed (10, "the update channel").

3. **Before any of that, this public repo already exposes material that is not ours to publish.**
   This finding is independent of the plugin question. See "Live exposure" below.

## The carve-out, ranked (only where nothing comparable exists: 09)

| # | Plugin | Contents | Surfaces | Work to ship | Why it earns a slot |
|---|---|---|---|---|---|
| 1 | `x-reader` | `read-twitter` skill + `cc-read-twitter` moved to `scripts/` (a top-level `bin/` makes claude.ai and Cowork refuse the whole plugin: 01, 07) | Claude Code, Cowork; chat needs a hosted MCP | ~1 h: path rewrite to `${CLAUDE_PLUGIN_ROOT}`, README | Keyless, both-direction thread walk with an outage ladder; nothing >50★ does this (09) |
| 2 | `command-handoff` | `manual-command-delivery` skill | all three | ~20 min: strip zsh/cursor/reso references (04) | No comparable skill found anywhere (09) |
| 3 | `video-motion` | `video-understanding` + `motion-probe.py` | Claude Code, Cowork | ~30 min + declare opencv/numpy (07) | Ingestion is solved upstream; slit-scan/optical-flow/easing-fit probes are not (09) |
| 4 | `explainer-gates` | `self-explaining-artifact` + `probe.mjs` (vendor out of a private repo) | Claude Code, Cowork | ~30 min | Generators exist; measured word/contrast/frame gates do not (09) |
| 5 | `bats-test-audit` | `test-audit` | all three | ~20 min + OpenClaw MIT notice | Narrow gap: bats-specific pruning (09) |
| 6 | `close-integrity` (later) | a git-only ledger + session-continue core + anti-deference-nudge, rebuilt slim | Claude Code only | a new build, not an extraction: `completion-assert` alone depends on the 2,587-line `wrap-ledger.sh` (05) | Stop gates today only check "a test ran"; none blocks on unlanded work or on unfinished items in the frozen scope (09) |

**Skip:** bash guard and write-backup (dcg 6.1k★, cc-safety-net, built-in `/rewind`);
research fan-out (first-party deep-research); codex-security (first-party claude-security);
permission-harvest (`/fewer-permission-prompts`); plan-conventions and beautiful-mermaid
(covered); `/review` (bundled `/code-review`) (09, 06).
**Cannot ship:** visual-direction (paid ui.sh corpus); grok-wiki-* and repo-wiki (unlicensed
upstream text); kpmg-deck (KPMG brand book quoted page by page); agent-browser (the vendor serves
its own version-matched copy) (03, 04).

Constraints on the carve-out, all measured in 01:
- `${CLAUDE_PLUGIN_ROOT}` changes on every update, so durable state goes in `${CLAUDE_PLUGIN_DATA}`.
  Neither is exported to the Bash tool, so skills must spell the path in text that is substituted
  at load.
- claude.ai skill uploads accept six frontmatter keys. Five of our skills use others
  (`argument-hint`, `when_to_use`, `shell`, `disable-model-invocation`, `arguments`); whether plugin
  uploads enforce the same rule is unverified.
- `claude plugin validate` on 2.1.280 passes plugins that claude.ai and Cowork will refuse
  (top-level `bin/`, dropped `settings` keys), so local validation is not a cross-surface check.
- Installs are per config dir, so each of the 4 accounts installs separately.
- Fork drift: the carve-out becomes the source of truth for the units it takes. A one-way export
  from here would re-create exactly the "tracked copy of upstream silently diverges" class that
  `skills/LOCAL_ONLY.md` already rules out.

## Live exposure in this public repo (not a plugin question)

Verified this session against `origin/main` @ `7dd2e1035`:
- `vendor/uidotsh/` — 196 tracked files of paid ui.sh content. Its own `README.md:20` reads
  "Licensed content, mirrored for the account holder's own local use."
- Personal email addresses and account identifiers: `accounts.json` (7 addresses, under a comment
  reading "Emails are fine: this repo is private", `accounts.json:3`),
  `hooks/enforce-email-formatting.py:353-366`, `skills/account-relogin/SKILL.md:128`,
  `skills/outbound-drafting/SKILL.md:41,229-238` (with a vendor order number and a phone
  fragment), `skills/resume-sessions/REFERENCE.md:22-28`, `skills/outlook-cleanup/rules/rescue.yaml`.
- Third-party text redistributed without a licence: `skills/grok-wiki-cli` (an unlicensed
  upstream), `skills/kpmg-deck/references/brand-kit.md` (KPMG guidelines, page by page).
- No `LICENSE` at the root (`gh repo view` → `licenseInfo: null`).

Untracking these files going forward does not remove them from public git history. The two real
remedies are making the repo private (reversible, one setting) or rewriting history and
force-pushing (destructive). Both are the operator's call.

## Incidental defects found (in-repo, not plugin-specific)

- Three agent definitions point at `~/.claude/rules/research-subagents.md`, which exists nowhere (06).
- `agents/research-decomposition-critic.md`: its description is invalid YAML. 2.1.114 drops the
  frontmatter; 2.1.280 accepts it (06).
- `commands/read-twitter.md` and `commands/resume-sessions.md` are shadowed by same-named skills
  (dead). `copy-plan`'s and `read-twitter`'s error-handling steps can never run, because their `!`
  helpers exit non-zero (06).
- `hooks/check-edit-boundary.sh` reads `~/.claude/edit-boundary.json`, which nothing writes (05).
- session-continue → completion-assert rely on Stop-hook ordering that the docs say runs in
  parallel (05).
- 12 repo hooks are registered in no live settings file; 2 live-registered hooks have no repo
  source (05).

## Evidence

| File | Axis |
|---|---|
| `01-spec.md` | component model, per-surface support, env vars, validate behaviour |
| `02-policy.md` | directory review, security scan, size limits, directory vs self-hosted |
| `03-skills-a.md`, `04-skills-b.md` | per-skill shippability tiers with file:line coupling |
| `05-hooks.md` | hook census, dependency closure, 9 candidate bundles |
| `06-commands-agents.md` | commands and agents, `validate --strict` results |
| `07-bin-mcp.md` | bin/ CLIs, MCP authorship (none authored here), MCP-wrap option |
| `08-deploy-model.md` | symlink farm vs plugin marketplace for our own deploy |
| `09-prior-art.md` | overlap with official and community plugins; the six real gaps |
| `10-hostile.md` | adversarial verdict; the update-channel risk |

Personal email addresses, an order number and a phone fragment were redacted from these copies.
