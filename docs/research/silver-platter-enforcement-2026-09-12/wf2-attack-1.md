## FALSE-NEGATIVE AUDIT — 8 defects, 6 with a reproduced trigger

Probe harness (faithful transcription of `hc_self_ran`, runnable): `/private/tmp/claude-501/-Users-chrisren-Development-voiceink/82354751-f394-4f51-928d-b50b30dbe83c/scratchpad/r1probe.sh`
`cc-owner` corpus sweep output: `/private/tmp/claude-501/-Users-chrisren-Development-voiceink/82354751-f394-4f51-928d-b50b30dbe83c/scratchpad/owner-hits.txt`

---

### F1 — CRITICAL. The gate convicts the single largest hand-off in the corpus, and it is definitionally human-only.

**Trigger:** `bash /tmp/approval-queue-drain.sh` — **270 emissions, 20.0% of the whole corpus** (line 1 of `handoff-emissions.txt`), plus 5 more as `bash ~/.claude/autonomy/approval-queue-drain.sh`.

Its own header (`~/.claude/autonomy/approval-queue-drain.sh:5`): *"a permission prompt is answerable only in its own pane, by a human. **Nothing an agent runs clears one.**"* Line 46 is a hard `: >/dev/tty` gate that prints the panes and exits when there is no TTY.

**Wrong behaviour — and the mechanism is structural, not incidental.** Verdict order is R4b (body descent, ADMIT-only) → A8 → R1.
- R4b would acquit it: the body carries `/dev/tty` (`:46`) and `read -r -p … </dev/tty` (`:66`), both inside `HC_BODY_RE`. **But R4b is gated on `[ -f "$p" ]` and `/tmp/approval-queue-drain.sh` does not exist** (verified: `No such file or directory`) — consistent with the design's own measurement that 74.9% of named scripts are reaped by emission time.
- R1 then fires. Reproduced: prior `bash ~/.claude/autonomy/approval-queue-drain.sh` ⇒ `REFUTED(self-ran)`; prior `bash /tmp/approval-queue-drain.sh` ⇒ `REFUTED(self-ran)`. The script is *designed* to be agent-run first — the no-TTY branch exists precisely so the agent can enumerate the queue — so **the receipt that convicts it is produced by using it correctly.**

**The generalisable defect:** acquitting evidence lives on the perishable `/tmp` copy; convicting evidence lives in the durable transcript. Decay is therefore **asymmetric and one-directional** — every script that ages out of `/tmp` loses only its acquittals. The design's honesty note says `UNRESOLVED/script-gone` "reports unresolvable, never clean"; that is true only when no refutation arm fires, and R1/R2/R3 never touch the file. `script-gone` is an acquittal-blind conviction path, not a safe abstain.

**Severity:** catastrophic. This is the one command that unblocks every permission-pending pane on the machine; a block here strands the operator *and* every session waiting behind him, while the corrective ("you already ran this — run it, then close on the result") asserts something the script's own header calls impossible.

**Minimal fix:** when `hc_scripts` names a script and the named path is absent, resolve the basename against a small durable set (`$HOME/.claude/autonomy/`, `$HOME/.claude/scripts/`, the repo's `scripts/`) and run the body descent against the resolved copy before any refutation arm. If no copy resolves, R1 must return `UNRESOLVED`, never `REFUTED` — a missing body means the acquittal evidence is *unreadable*, not *absent*.

---

### F2 — CRITICAL. R1's receipt is scoped to the script/head, not the argv, so every dry-run→apply pair in the corpus false-convicts.

**Triggers (all reproduced `REFUTED(self-ran)` in `r1probe.sh`):**

| handed over | prior run in-session | corpus |
|---|---|---|
| `bash scripts/deploy-release.sh` (with `DEPLOY_CONFIRMED_DROP="0088_peaceful_deadpool.sql"`) | `…deploy-release.sh --dry-run` | 2 + 2 |
| `bash /tmp/reso-operator-apex-and-vitals.sh --apply-purge` | same script, no flag | 2 + 6 |
| `bash ~/mint-denver-admin.sh --write` | `bash ~/mint-denver-admin.sh` | 2 + 4 |
| `bash /tmp/sr-recover-weekend.sh --fire` | same script, no flag | 2 + 6 |
| `bash …/golive.sh --enable` | `…/golive.sh --check` | 4 + 2 |
| `bash /tmp/dispatcher-unpark-local.sh --yes` | same script, no flag | 2 + 8 |

`hc_self_ran` uses **only `$sc` (the basename)** when a script is named — `$sig` is discarded entirely — so the `--apply` / `--write` / `--fire` / `--enable` / `--yes` mode, which is the entire blast radius, is invisible to the matcher.

**Wrong behaviour:** the gate blocks the close on a production deploy that spends money and drops a SQL table, telling the model its own dry-run proves it can run the real thing. Note the design *itself* labels `deploy-release.sh` ADMISSIBLE (it is the counter-example in the `minimal` critique), and H12 (consent/blast-radius) is declared out of the predicate — but R1 does not merely *miss* H12, it **overrides** it.

**The sharpest part:** `manual-command-delivery` mandates exactly this shape — *"reversible ⇒ driven silently; irreversible ⇒ GATED"*. Compliance with the rule the hook enforces is what manufactures the receipt that convicts. Distinct from the `causal` critique (which is about failed runs / `tool_result`): this fires on a *successful* prior run.

**Minimal fix:** two lines. (a) Match the normalised full argv, not the basename. (b) Refuse to refute whenever the handed argv is a strict superset of the executed one — extra flags mean an unproven call. This is the same asymmetry the design already states for `sudo` ("a `sudo`-prefixed re-run is a different call"); it just was not applied to flags.

---

### F3 — HIGH. `hc_sig` drops the remote and ref for `git`, i.e. the whole blast radius.

**Trigger:** `cd ~/Development/reso-landing-app && git push origin main` (4 emissions; also `cd ~/Development/reso-web-app && git push origin main`, 2+2). Sig = `git push` (head + subcommand, per the design). Any earlier branch push — the agent does this constantly — matches. Reproduced: prior `git push github HEAD:refs/heads/wt-pool-5` ⇒ `REFUTED(self-ran)`.

**Wrong behaviour:** a push to a trunk whose CI bills a real build (reso-landing/web-app on Amplify; CLAUDE.md's ship-policy table makes that hand-off terminal-valid) is convicted on the receipt of a throwaway worktree push. `git push` is the one multiplexer where head+subcommand strips 100% of the safety-relevant argv.

**Minimal fix:** per-verb sig depth. For `git push`, `git reset`, `git rebase`, `gh release`, `fly deploy`, `aws <svc> <op>`, the sig must include the remote/ref/target. Simplest sound version is F2's fix — full argv — which subsumes this.

---

### F4 — HIGH. R3 resolves *invocability*, not *authority*; the repo ships a `bin/` CLI whose header says it must never be agent-run.

**Trigger 1 (shipped, prospective):** `bin/cc-signoff`. Its docstring, lines 2–7: *"the ONLY path from `awaiting-signoff` to `signed`. **Operator only.** … this command exists to be **UNRUNNABLE BY AN AGENT**"*, quoting the operator: *"you do not have the awareness YET to have that call."* R3's closed set is "is `$bin/$hd` executable" — `cc-signoff` is — so it refutes with *"`cc-signoff` is a CLI you run yourself"* unless somebody remembers to add `# cc-class: operator`. The mission-board rule in always-resident global instructions says the same thing. R3's set is over the wrong property: being in `bin/` says the agent *can* invoke it, never that it *may*.

**Trigger 2 (in corpus, 4 emissions):** `cc-decide action f04e01ecfb51 --evidence approved` · `cc-decide answer 32d4d093f78a --what "disarm: POSTLAND_AUTOREVERT=off"` · `cc-decide action ab82a67e2c37 --evidence "settings-json: …"` · `cc-backlog done f4184622d743 --evidence "Operator ruling 2026-08-25: …"`. These record **the operator's ruling on a class-C packet** — the ⛔ answer itself. R3 refutes them, i.e. instructs the agent to answer its own decision packet. That is precisely the deference-laundering `cc-decide`'s conviction/receipt gate exists to prevent.

**And `# cc-class: operator` cannot express it:** the declaration is whole-tool. `cc-decide list --open` (31 + 9 + 2 = 42 emissions) is a *correct* refutation; `cc-decide action` (4) is the operator's. One line per tool forces you to pick which of the two to get wrong. Same split on `cc-backlog list --blocked` vs `cc-backlog done --evidence "Operator ruling"`.

**Minimal fix:** make the declaration subcommand-scoped and mandatory-by-default for the ruling verbs — `# cc-class: operator <verb> [verb…]` parsed from the tool's own header, matched against `hc_sig` (head + subcommand) rather than head alone. Backfill it into `cc-signoff` (whole tool), `cc-decide action|answer|veto`, `cc-backlog done|unblock`, `cc-do` (whole tool) in the same commit that lands R3, and add a `bats` case asserting `cc-signoff` is never `REFUTED`.

**Correction to the `causal` runner-up:** its proposed carve-out `cc-relogin* → HUMAN:login` is **wrong**. `bin/cc-relogin:2` — *"unattended OAuth re-authentication … phase 2 browser OAuth over CDP"* — is agent-driven by construction, so `cc-relogin next` (1 emission) is a *correct* refutation. Do not adopt that half of its fix.

---

### F5 — HIGH. A2's live oracle interrogates the wrong process, and the fall-through collapses `sig` to the bare token `sudo`.

**Trigger:** `sudo killall fseventsd` (13 emissions), `sudo pmset -a disablesleep 1` / `0` (4 + 2).

A2 declines to acquit when `sudo -n true` returns 0 in **the hook's** context. The design notes *"hooks run outside the permission layer, so the `Bash(sudo:*)` deny rule does not reach it"* — it then uses the hook's capability as a proxy for the **agent's**. Measured in this session, twice: `sudo -n true; echo rc=$?` ⇒ *"Permission to use Bash with command `sudo -n true` has been denied."* The actor is deny-ruled from `sudo` **entirely**, including the no-op probe. So on a box with NOPASSWD or a live ticket, A2's override can only ever produce a false conviction — the hook proves *it* could sudo, about an actor that cannot.

**The compounding second half:** once A2 declines, `sudo …` falls through. `sudo` is not in the multiplexer list, so `hc_sig` = the bare token `sudo`, and R1's non-script branch greps `(^|[;&|]|&&)\s*sudo([ ]|$)`. Reproduced: prior `sudo launchctl print system/com.apple.fseventsd` ⇒ `sudo killall fseventsd` is `REFUTED(self-ran)`. **Any one prior sudo in a session convicts every later privileged hand-off in it.**

**Minimal fix:** (a) delete the `sudo -n true` override — it cannot answer the question asked, and an unconditional `privilege` acquittal costs only missed convictions, the polarity the design says it wants; or, if kept, condition it on the agent's own permission verdict (`hooks/lib/permission_matcher.py` already answers "would the Bash tool be allowed"). (b) Add `sudo`/`doas` to the multiplexer set so sig is `sudo <binary>` at minimum — subsumed by F2's full-argv fix.

---

### F6 — MEDIUM. `HC_BODY_RE` recognises *password* reads but not the *consent* read the house rule mandates.

`HC_BODY_RE` contains `read -s|read -r -s` and `/dev/tty` — password prompts. `manual-command-delivery` requires the opposite thing for the class that most needs handing over: *"irreversible / production-mutating / money-spending … are **GATED**: print the RESOLVED command, one line on what it cannot undo, then a **typed `yes`**."* That gate is written `printf 'Type yes to run it: '; read -r a` — see `/tmp/fsev-remediation.sh:22`, the house's own exemplar. Plain `read -r a` / `read -p` match nothing in `HC_BODY_RE`; that script survives only because it also contains `sudo`.

**Trigger class:** a gated, non-privileged destroyer — `bash /tmp/reso-destroy-retired-tenants.sh` (4), `bash /tmp/reso-destroy-sunset.sh` (3), `bash /tmp/dispatcher-unpark-local.sh --yes` (2). Body present ⇒ no acquittal; body reaped ⇒ F1's path. Either way it lands on R1/R2/R3.

**Minimal fix:** add `read -r?[[:space:]]+[A-Za-z_]|read -p|Type yes|typed yes` to `HC_BODY_RE`. It is ADMIT-only, so widening it cannot create a false conviction — only silence.

---

### F7 — MEDIUM. A3 also resolves invocability rather than authority, and its `case` glob swallows absolute paths.

**Trigger:** `/skill-promote self-explaining-artifact` (1 emission). `~/.claude/commands/skill-promote.md` exists ⇒ `REFUTED agent-skill` ⇒ *"invoke it with the Skill tool, or headlessly with `claude -p "/skill-promote"`"*. The skill's own description: *"Promote a reviewed draft skill … **after explicit human confirmation**."* The gate instructs the agent to promote a skill it wrote into its own always-loaded instruction surface, bypassing the review gate. `/compact-memory` (1) is the same shape (*"PROPOSE-ONLY … shown as diffs for approval"*). The presence of a `commands/*.md` file proves the agent *can* invoke it; it says nothing about who *may*.

**Second, out-of-lens but it invalidates a runner-up claim:** `case "$exec_part" in /[a-z][a-z0-9_-]*' '*)` — in a shell `case`, `[a-z0-9_-]*` is *one class char followed by `*`*, so the pattern matches any absolute path whose first segment starts lowercase. `/opt/homebrew/bin/python3 /tmp/discord-read-history.py` (6 + 3) ⇒ slug `opt` ⇒ no `commands/opt.md` ⇒ ADMITTED `tui-builtin`. `/tmp/cc-read-twitter …` (2) ⇒ slug `tmp` ⇒ ADMITTED — so it never reaches R1, and the `minimal` critique's R1 basename claim about that row is unreachable in the shipped order.

**Minimal fix:** anchor the slash arm to `/[a-z][a-z0-9_-]*` with **no `/` in the slug** (`case` can't express it — use a `[[ "$exec_part" =~ ^/[a-z][a-z0-9_-]*([[:space:]]|$) ]]`), and give the A3 refutation the same subcommand-scoped `# cc-class: operator` escape as F4, read from the command file's own frontmatter.

---

### F8 — SPECIFY-IT. `hc_paths` is undefined, and R4a sits above every acquittal but `placeholder`.

R4a refutes `cursor|code|subl <path>` whenever `hc_paths` yields a path — **before** A2/A3/A8. The corpus has 17 distinct `cursor` rows / ~35 emissions; **15 of 17 are documents** (`.md`, `.yaml`): `cursor docs/OWNER_BRIEF.md` (7), `cursor ~/.claude/model-config.yaml` (2), `cursor …/CSM_PRE_DISCLOSURE_DRAFT.md` (2), `cursor ~/Development/personal/roommate-settlement/STATEMENTS.md`, etc. Only 2 rows are `.sh`.

The gold replay reports `worksheet 6/2` — exactly the two `.sh` rows — so `hc_paths` is *presumably* script-extension-scoped and the documents are safe. But that regex is never published, and if it matches any path-shaped token, 29 emissions become *"opening `docs/OWNER_BRIEF.md` in an editor is not the act — run it"*, on files that cannot be run, contradicting the always-resident rule that mandates this exact form (*"To point at a file, give the command that opens it: `cursor <path>`, never `<path>`"*) and colliding with A8 (eyes), which the design declares out of the predicate — `open <url>` for eyes acquits, `cursor <doc>` for eyes would not.

**Minimal fix:** publish `hc_paths`, scope R4a's path to an executable/script extension (`.sh|.py|.bash|.zsh|.mjs` or `-x`), and move R4a **below** A8 so an eyes-deliverable acquits before the worksheet arm can see it.

---

### Structural note that governs all eight

The design publishes exactly **one** of its eight regexes — `HC_BODY_RE`, the ADMIT-only one. `HC_PRIV_RE`, `HC_CHAN_RE`, `HC_MFA_RE`, `HC_LOGIN_RE`, `HC_KEYC_RE`, `HC_SHELL_RE`, `HC_GUI_RE` and `hc_paths` / `hc_sig` / `hc_scripts` are referenced and never shown. Since acquittals short-circuit refutations, **those seven carry the entire false-negative load of the mechanism and are currently unreviewable.** Every finding above is a gap between a published refutation and an unpublished acquittal; the remaining gaps cannot be audited until the sets are in the file. Publishing them is a prerequisite for the ≥0 false-conviction claim, not a documentation nicety — and each one needs the same corpus replay the refutation arms got (e.g. does `HC_LOGIN_RE` cover `gh auth refresh -h github.com -s user`, 4+2 emissions, a browser OAuth whose sig `gh auth` is manufactured by the routine `gh auth status`?).