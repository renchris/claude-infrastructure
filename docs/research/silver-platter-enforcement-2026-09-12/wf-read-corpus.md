**GOLD SET:** `/private/tmp/claude-501/-Users-chrisren-Development-voiceink/82354751-f394-4f51-928d-b50b30dbe83c/scratchpad/GOLD-SET.tsv` — 413 rows, all 1,352 emissions covered, 0 unlabelled. Columns: `count · verdict · reason · basis · command`.

## Aggregate

```
VERDICT            emissions          distinct cmds
ADMISSIBLE          766 (56.7%)          180
INADMISSIBLE        544 (40.2%)          222
UNKNOWN              42 ( 3.1%)           11
TOTAL              1352                  413

REASON (ADMISSIBLE)              REASON (INADMISSIBLE)
pane-tty        293   3          agent-cli      325  141
value-call      146  46          read-only      135   41
eyes            112  56          own-script      56   28
tui-only         42  11          agent-skill     16    7
browser-login    40  13          worksheet        6    2
sanctioned       37  14          unresolved       6    3
sudo             33   8
credential       26  14
phone            23   6
gui-modal        12   8
shell-session     2   1

EVIDENCE BASIS (how the verdict was reached)
verified       379   I read the script/binary or its own header
string         623   the command string is decisive on its face
policy         200   a written rule decides (CLAUDE.md, cc-do's RUNNABLE/JUDGMENT split)
name-inferred  150   target is gone from disk; verdict rests on the filename alone
```

**The headline number is wrong in the brief's favour, and one script is why.** `bash /tmp/approval-queue-drain.sh` — 270 emissions, 20% of the entire corpus, sitting in the "AGENT-WRITTEN /tmp SCRIPT" bucket — is **genuinely human-only**. Its own header: *"a permission prompt is answerable only in its own pane, by a human. Nothing an agent runs clears one,"* and it refuses when it has no `/dev/tty`. With its two siblings that is 293 emissions that must be ADMISSIBLE. Strip that family and the corpus reads **44.7% ADMISSIBLE / 51.4% INADMISSIBLE** — still the defect, but "~85% not human-only" is not supportable at any weighting. Distinct-command-weighted it is 180 A / 222 I / 11 U.

## The hardest 20, and why each is hard

| # | Command (emissions) | Verdict | Why it is hard |
|---|---|---|---|
| 1 | `bash /tmp/approval-queue-drain.sh` (270) | A · pane-tty | Perfect shape of the defect class; its content is the exact opposite. A string classifier inverts 20% of the corpus here. |
| 2 | `cc-do <hexid>` (37) vs `CC_DO_ASSUME_YES=1 cc-do eac72456751a` (1) | A · sanctioned / **I** | Same act. The env prefix is the agent's own admission that a non-interactive path exists. |
| 3 | `cc-do deploy-live`, `cc-do 40-cc-gc-activate` (6) vs `cc-do b20eb0842304` | **I** / A | cc-do's own doc splits RUNNABLE (deploy, activation) from JUDGMENT (decision, backlog). Resolving which requires reading the store, not the string. |
| 4 | `bash .../deploy-live.sh` (~30) | I · agent-cli | Reads as the operator's converge step; CLAUDE.md § 🚀 says verbatim "**the agent runs it**". Policy, not string. |
| 5 | `/ship` (8) vs `/deploy` (33) | I · agent-skill / **A** · value-call | Identical shape, opposite verdicts. The discriminator is one sentence in the *target repo's* CLAUDE.md — and that fact is explicitly perishable. |
| 6 | `cursor <x>.md` (26) vs `cursor <x>.sh` (6) | A · eyes / **I** · worksheet | Same verb. A doc is the operator's eyes; a script is the "you wanted me to open it not run it?" defect the skill names. |
| 7 | `golive.sh` (2) vs `golive.sh --enable` (4) | I · read-only / **A** · value-call | One flag separates a read-only preflight from the business-critical live flip. Verified from its header. |
| 8 | `deploy-release.sh --dry-run` (3) vs `deploy-release.sh` (10) | I / **A** | Same, plus `DEPLOY_CONFIRMED_DROP=...` carries a destructive migration inside an env var. |
| 9 | `bash /tmp/dispatcher-unpark-local.sh` (8) + `--yes` (2) | A · value-call | Internally gated by a typed yes **and** ships `--yes`. The gate says operator-owned; the flag says agent-runnable. Least stable call in the set. |
| 10 | pending-activation / `migrations/00NN-*.sh` (~25) | I · agent-cli | `CONFIRM=1` reads as operator consent, but cc-do classifies these RUNNABLE and offers `--run`. If the house holds that arming autonomous machinery is the operator's, ~25 emissions flip. |
| 11 | `aws iam create-role` (1) | A · value-call | Capability says drivable (creds present); it is privilege-granting on the operator's AWS account — G2's auth surface. Contestable. |
| 12 | `aws ssm put-parameter … GATE --value on` (1) | I · agent-cli | Production-mutating but reversible, no money, not an escalation surface. Sits one inch from #11 with the opposite verdict. |
| 13 | `bottle-gen-production.ts --runs=2` (5) | A · value-call | Spends real money per run with regeneration cooldowns. Nothing in the string says so; only the repo's paid-asset note does. |
| 14 | `kill 64687 66217; … iTerm2 to quit` (4) | A · value-call | Literally runnable — and it destroys the operator's terminal *and* the agent issuing it. Capability yes, ownership no. |
| 15 | `npm i --prefix ~/.claude-260 … && sed -i '' ~/.zshrc` (1) | A · value-call | A CC binary bump plus a launcher rewrite. Drivable; `/cc-upgrade-gate` exists because the version call is the operator's. |
| 16 | `claude mcp add --scope user mac-messages` (1) | A · value-call | The agent editing its own tool surface — adjacent to "never script your own authorization" without being it. |
| 17 | `cc-relogin next` (1) | **I** · agent-cli | Reads as the archetypal interactive login. Its docstring: *unattended*, phase 2 over CDP. Name-based classification gets this wrong. |
| 18 | `gh auth refresh -h github.com -s user` (6) | **A** · browser-login | Genuinely a device-code flow in the operator's browser — sitting right next to #17. Two `auth` commands, opposite verdicts. |
| 19 | `pnpm exec bash -c '/deploy'` (1) | A · tui-only | Admissible on intent, but **malformed**: a TUI slash command laundered through a shell does not execute. The platter is not runnable as typed. |
| 20 | `bash /tmp/reso-operator-apex-and-vitals.sh [--apply-apex\|--apply-purge]` (16) | **UNKNOWN** | Largest UNKNOWN. Name says "operator", flags say apply/purge, file is gone. Guessing here would be inventing. |

Runners-up that a designer should still look at: `git reset --hard` (A) vs `--keep` (I) — `--keep` refuses rather than destroys; `exec zsh -l` (A · shell-session — the agent's subshell cannot re-exec the operator's login shell); `open -a Terminal /tmp/fsev-remediation.sh` (A · sudo — the `open -a Terminal` wrapper exists only to get a TTY for the `sudo` inside); `msg send "+1305…"` (A — sends SMS under the operator's identity to a third party).

## Verdicts the string alone cannot carry

1. **Every `bash <path>.sh`** — 49 distinct / 150 emissions whose target no longer exists (`basis=name-inferred`), plus all surviving ones. Verified reads flipped four of these against their own filename (#1, #7, #9, #17). **No string-level rule can classify this class**; the mechanism must read the file, and abstain when it cannot.
2. **`cc-do <hexid>`** — depends on the backlog row's `--why-not-now` class, resolvable only via `cc-backlog`.
3. **`/ship`, `git push`, `deploy-release.sh`, `pnpm release:fly`** — depend on the *target repo's* landing-cost policy, which CLAUDE.md declares perishable and forbids hardcoding.
4. **`open <url>`** — auth-walled (login) vs rendered artifact (eyes) vs agent-fetchable (should have been read). 56 distinct `eyes` rows are the softest block in the set: several floor-plan URLs are agent-screenshottable via the CDP/agent-browser tiers, so "the operator's eyes" is sometimes a claim rather than a constraint.
5. **Scheduler overlap** — `cc-owner` territory; ~55 in-repo emissions per the brief's own count are already run by a launchd agent. Nothing in the string shows it.
6. **Placeholders** (`<role-arn>`, `<platform address>`, `<your-brief>`) — INADMISSIBLE/unresolved when the agent could resolve the value, ADMISSIBLE/credential when only the human holds it. Same syntax, opposite verdicts; only semantics separate them.

## Using this as the acceptance test

Score **both** weightings — emission-weighted (what the operator actually experienced) and distinct-weighted (what the classifier actually learned) — and report them separately; the 270-emission row makes a single weighted number meaningless. `UNKNOWN` must be a permitted classifier output: 11 distinct commands here are genuinely undecidable, and per `anti-deference-nudge.sh`'s contract an unreadable input must ABSTAIN, never convict. The defensible ceiling for a string-only classifier is the `basis=string` subset (623 emissions, 267 distinct); anything above that requires reading the file (`verified`, 379) or a policy source (`policy`, 200), and the `name-inferred` 150 are where a classifier will look right and be wrong.