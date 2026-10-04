# Auto mode and the sanctioned commit + land line: allow rules decide it, the classifier never should

*2026-10-03 · Claude Code 2.1.284 (`~/.claude-284`, the `~/.zshrc:502` launcher pin) · operator step: migration `0054` · probe: `scripts/automode-land-probe.sh`*

## Verdict

**An allow rule is the right lever, it is sufficient, and three rules close the incident.** Under `--permission-mode auto`, a Bash call whose every subcommand matches an allow rule is allowed before any classifier runs, server-side classifier included. That is measured, not inferred: with a classifier fixture that blocks every land and every commit, the incident line was denied without the rules and ran with them, under the operator's live settings and hooks.

The incident line (reso, 2026-10-03) was:

    git add scripts/data/bottle-image-manifest.json && git commit -m "chore(bottles): record operator ranks" && fnm exec --using=22 bash scripts/ship-land.sh

Only `git add` had a rule. `git commit` and the fnm-wrapped land script had none, and one uncovered subcommand sends the whole line to the classifier. The classifier then applied the operator's custom "Modify Shared Resources" rule, whose wording ("shared artifacts not created in the current context") covers a data file that a local review server wrote. The shipped 2.1.284 wording would not have matched it.

Migration `0054` adds exactly these three rules to the one shared `~/.claude/settings.json`:

| rule | covers |
|---|---|
| `Bash(git commit -m:*)` | the house commit form |
| `Bash(bash scripts/ship-land.sh:*)` | the land script run through `bash` |
| `Bash(fnm exec --using=22 bash scripts/ship-land.sh:*)` | reso's Node-pinned form, as the incident ran it |

Already live and unchanged: `Bash(git add:*)` and `Bash(scripts/ship-land.sh:*)`, which is the form both repos' `/ship` documents.

**What stays gated (measured):**
- a hand `git push` to trunk: the `ask` rule `Bash(git push:*)` outranks any allow rule *and* any hook `allow`;
- force-push: the `deny` rules;
- `git commit … --no-verify` / `-n` and commits in the shared checkout: `validate-bash.sh`, because hooks run before rules;
- every `/deploy` and `fly deploy` path: no rule touches them, and `fly deploy` is an `ask`.

**The limit:** the rules reach the land line only when it runs alone. In the last 30 days, 49 classifier denials touched `ship-land` or `git commit`, and only 3 to 7 of them had a shape a rule can reach. The rest put the line behind `cd`, a log redirect, `| tail`, `&`, a heredoc or a multi-line script, and all of those go to the classifier no matter what rules exist. `.claude/commands/ship.md` §4 now says to run the line alone.

## Q1. Does an allow rule pre-empt the classifier, and are these commands on the drop list?

**Yes, it pre-empts, and none of the three is dropped.**

**Code (2.1.284).** In `ZWo` (offset 187500194), the static evaluation runs first. `if(_e.behavior==="allow")` returns before any classifier code; the classifier path is reached only from `_e.behavior==="ask"`.

The one way a static allow is re-routed is the server-side hold (offset 187534334). When the server classifier runs in arbiter mode, an allow is rewritten to `ask` with the reason "Auto mode held this command for the server-side classifier to review". `HWo` (offset 187491922) limits that hold to allows whose reason is the sandbox auto-allow or the read-only allowlist. A `type:"rule"` allow returns `undefined` there and is never held.

**Drop list (2.1.284, offset 181582905), unchanged from the 2026-09-09 audit:**
- `python python3 python2 node deno tsx ruby perl php lua npx bunx "npm run" "yarn run" "pnpm run" "bun run" bash sh ssh zsh fish eval exec env xargs sudo`
- the net list: `curl wget kubectl aws gcloud gsutil`

`Ldn` (offset 181583531) drops a rule only when it is `<cmd>`, `<cmd>:*`, `<cmd>*` or `<cmd> *`, or `<cmd> -…*` with a flag tail. So:
- `bash scripts/ship-land.sh:*` survives, because its tail is a path, not a flag;
- `git` and `fnm` are not on the list at all;
- `autoMode.classifyAllShell` (`dGr`, offset 178450334) would suspend every shell allow rule, and no settings source sets it.

**Probe:** see the table below. Arm I-rules-bare ran `bash scripts/ship-land.sh` under a fixture that blocks every ship-land run, which proves the `bash …` rule survived the drop.

## Q2. How are compound lines matched?

Every subcommand must resolve to `allow` independently. Then the line is allowed with `type:"subcommandResults"` (`k$o`, offset 187273196). One `ask` makes the whole line an `ask`, and in auto mode an `ask` goes to the classifier with the full line and the transcript.

Two consequences, both measured:
1. **The incident shape.** Two uncovered parts out of three meant the classifier judged the whole line (arm L-base-incident).
2. **A read-only part re-routes a rule-covered line.** If any subcommand was allowed by the read-only list rather than a rule, `HWo` finds `readOnly` inside the `subcommandResults` and the server-side classifier holds the line. Arm I-rules-rochain (`git status --short && bash scripts/ship-land.sh`) was denied even though the land part matched a rule. This is why the land line must run alone; `| tail` and a `cd … &&` prefix belong to the same class.

Structural gates (`$( )`, heredoc, a file redirect, `&`, a subshell, more than one `cd`, `cd`+`git`) make the line an `ask` before rule matching, as documented in `permission-matcher-truth-2026-08-20.md` §2.

## Q3. Is `autoMode` config a better lever?

**No. It is a weaker one, kept for what rules cannot reach.**

`autoMode.{allow,soft_deny,hard_deny,environment}` exists and is read only from user, flag and policy settings. Sources are concatenated in `ak()` (offset 178449292). A project or local `autoMode` is ignored with a warning, so reso's own settings could never carry it. A non-empty list replaces the shipped defaults unless it contains the literal `"$defaults"` (`xNt`, offset 180991704).

It is weaker than an allow rule for three reasons:
- it is prose that a model applies, so it is probabilistic and re-judged on every call;
- the transcript can still tip a soft rule;
- 18 denials in the last 30 days, as recent as 2026-10-02, cite "Auto-Mode Bypass", which is a shipped rule absent from the operator's list. So the rules a verdict applies are not always the user's list. UNVERIFIED which classifier issued them; the server-side one is the likely candidate.

An allow rule is deterministic, takes zero classifier calls, and is checked by `cc-permission-audit`. `autoMode.allow` text remains the only lever for the structural forms above, and is not proposed here.

**Two observations about the operator's custom `soft_deny`.** It has 35 entries and no `"$defaults"`, deliberately: `$defaults` was measured and ruled NO in `c10-staged-residuals-2026-10.md`.
- **"Git Push to Default Branch"** blocks pushing to main and says to push a feature branch instead. That contradicts the global ship policy, and 2.1.284 ships the opposite rule as an *allow*: "Git Push Destination: pushing to any branch … the default branch included". Its measured cost is zero: none of the 596 classifier denials in 30 days cites it. Recorded, not filed.
- **"Modify Shared Resources"** in the custom wording covers any file not created in the current context. The shipped wording covers shared infrastructure. The custom text is what fired in the incident. With the 0054 rules the clean land line never reaches it.

## Q4. The narrowest rule set

The three rules in the Verdict, user-level, because the existing `Bash(scripts/ship-land.sh:*)` is user-level too.

**Global `/ship` in repos without a land script.** Its commit step is now covered. Its push, `git push origin HEAD:<trunk>`, is "a push to main by hand" to the harness and stays gated by design; covering it would need the `ask` rule narrowed, which the brief rules out. A repo that should land unattended carries a `scripts/ship-land.sh`, as claude-infrastructure, reso and reso-qa-runner already do.

**Not proposed:**
- `Bash(git commit:*)`: it would add `-a`, which stages every tracked change, against the explicit-paths rule;
- `-F -` heredoc commits: structural, so a rule cannot reach them;
- env-prefixed forms such as `LAND_LANE=v1 scripts/ship-land.sh`: a non-allowlisted env prefix never matches a rule.

**Residual risk, stated:**
- the land-script rules trust whatever file sits at `scripts/ship-land.sh` in the cwd, exactly as the existing rule does;
- the commit + land chain now runs with no classifier review at all, which is the operator's ruling;
- the commit content is still reviewed by the pre-commit hooks and by the land script's own gate and escalation scan.

`cc-permission-harvest`'s gates would refuse all three rules (ACE_CLASS on `bash …`, PATH_BOUND, TOKEN_CAP), which is why they ship as a hand-reviewed c10 migration and not through `--apply`.

## The push hook does nothing while the `ask` rule stands

`hooks/ship-rail-push-allow.sh` (T-P15-4) was built on the premise that a hook `allow` overrides a settings `ask`. On 2.1.284 it does not. In arms I-hook-landpush2 and L-landpush, `--include-hook-events` shows the hook firing and returning `allow` for `git push origin HEAD:main`. The call was still refused with `decision_reason_type=rule`.

This matches the docs and the permission-harvest skill ("never say a PreToolUse hook allow bypasses the permission system"). Its header now carries a dated CORRECTED note. Whether to retire the hook or narrow the `ask` rule is not decided here.

## Probe arms (all 2.1.284, `--permission-mode auto --model opus`, every `init` line read `permissionMode: auto`)

Fixture: `autoMode.hard_deny` += "block any run of a script ending in ship-land.sh, and every git commit". Verdicts come from git side effects in a scratch repo with a local bare remote, not from the model's narration.

| arm | settings | command | result |
|---|---|---|---|
| I-ctrl-incident | isolated; `git add`, `scripts/ship-land.sh` rules + fixture | incident line | **denied**, server-side classifier; nothing committed |
| I-rules-incident | isolated; + the 3 rules + fixture | incident line | **ran**: committed, stub ran, remote advanced |
| I-rules-bare | isolated; rules + fixture | `bash scripts/ship-land.sh` | **ran** (survives the drop) |
| I-rules-rochain | isolated; rules + fixture | `git status --short && bash scripts/ship-land.sh` | **denied**, server-side hold |
| I-rules-negpush | isolated; rules + `ask git push` | `git push origin main` | denied (`ask`) |
| I-rules-negforce | isolated; rules + `deny --force` | `git push --force origin HEAD:main` | denied (`deny`) |
| I-hook-landpush2 | isolated; `ask git push` + ship-rail hook | `git push origin HEAD:main` | hook said allow; **denied** by the rule |
| L-base-incident | live settings + hooks + fixture | incident line | **denied**, classifier: the incident, reproduced |
| L-new-incident | live + the 3 rules (inline) + fixture | incident line | **ran**: committed, stub ran, remote advanced |
| L-new-noverify | live + the 3 rules | `git commit -m "probe" --no-verify` | denied by `validate-bash.sh` |
| L-landpush | live + the 3 rules | `git push origin HEAD:main` | live hook said allow; **denied** by the rule |

The tracked probe produced two verdicts:
- before apply: POS FAIL (classifier), NEG-PUSH gated;
- `--with-rules` rehearsal: `verdict=PASS`, all three arms.

Its judge is pinned by `tests/automode-land-probe.bats`. Two mutants (drop the hook-deny channel; drop the remote-advanced check) each turn exactly their intended test red.

## Census (30 days, transcripts in all five config dirs)

- 17,014 transcript files; 596 unique Bash classifier denials linked to their command.
- 49 of those touched `ship-land` or `git commit`. Only 3 had every segment covered by the 0054 rules plus the live list, and 1 more had an uncovered segment.
- 5 were `cd`-prefixed. The other 40 were structural: a file redirect, `&`, a heredoc, `$( )` or newlines. Up to 4 of those 40 may be quoted parentheses in commit messages that the regex over-read, so the reachable share is 3 to 7 of 49.

Method: every `*.jsonl` modified in the last 30 days under the five `projects/` dirs. A classifier denial is a `tool_result` containing "auto mode classifier", joined to its Bash `tool_use` by id. A segment is covered when it equals or prefix-matches a live `Bash(…:*)` rule or one of the three new ones. The structural test is a regex over the raw text, not the harness's tree-sitter parser, after exempting `N>&M` and `>/dev/null`.

## Operator step

`bash ~/Development/claude-infrastructure/migrations/0054-automode-land-allow.sh --confirm settings.json --probe`

It backs up and edits the one shared `settings.json`, verifies by content, and then runs the probe: three headless sessions, about $1 of quota. It exits 0 only if the land line runs on the rules while the hand push and the `--no-verify` commit stay gated. Rollback is the printed `cp -p` line.

## Reproduce

    bash scripts/automode-land-probe.sh               # live settings as they are
    bash scripts/automode-land-probe.sh --with-rules  # rehearsal with the 0054 rules passed inline
    bash migrations/0054-automode-land-allow.sh --verify
