---
name: permission-harvest
description: >-
  Turn the accumulated record of manual permission prompts into a small set of composable prefix allow rules, and state honestly how little that can buy. Load for the weekly permission review and whenever asked to "improve the allowlist", "reduce permission prompts", "harvest permission prompts", "why am I being prompted", "consolidate the yes-don't-ask-again entries", or on `/permission-harvest`. WHAT IT DOES: runs `cc-permission-harvest` read-only over the permission beacon archive (the oracle of prompts that actually happened), relays that report VERBATIM, partitions every prompt into MECE buckets so the STRUCTURAL share (no allow rule of any form can clear it) and the HOOK_RAISED share (one of our own PreToolUse hooks asked — not a rule gap) are visible before any rule list is read, refutes every candidate rule through eleven deterministic gates, consolidates the operator's own exact acceptances into the prefixes that shadow them, reads the 8-week trend from `~/.claude/logs/permission-harvest.jsonl`, drives the structural and hook-raised clusters into hook-layer work itself, and hands the operator ONE `cc-do` step for the apply. WHAT IT NEVER DOES: run `--apply` inside a session, write any `settings*.json`, propose a rule whose head executes whatever follows it, quote a `bash-commands.log` count as a prompt count, or claim a PreToolUse hook `allow` bypasses `deny`/`ask`. NOT for auditing existing rules for deadness (that is `cc-permission-audit --prune`) and NOT for changing hook behaviour on its own.
---

## permission-harvest — prompts in, composable prefixes out, with the ceiling stated first

**Why this skill exists.** The obvious reading of "we are prompted too much, improve the allowlist"
is measurably wrong on this fleet, and acting on it has already produced nine allowlist proposals
that an adversarial verifier refuted 9 of 9 — counts inflated 2×–174×, two of them granting
arbitrary code execution (`docs/research/permission-prompts-2026-08-23.md` §3). The failure this
skill prevents is a rule list derived from the COMMAND log rather than the PROMPT oracle, handed
over without the share of prompts that no rule can ever clear. Keeping those two populations apart
is the whole discipline.

---

### 1. The loop

Every permission prompt the harness resolves is appended by `hooks/cc-permission-beacon.sh` to
`~/.claude/autonomy/permission-archive/*.jsonl` — the oracle. `bin/cc-permission-harvest` loads the
rule sets in force for each row (the fleet union plus the project-local files reachable from that
row's `cwd`, with the `auto`-mode drops removed), resolves each row's outcome by signature rather
than inference, partitions the rows into MECE buckets — structural first, then hook-raised, `ask`
and `deny` hits, and truncated payloads — decomposes what remains into leaf sub-commands (the
harness splits on `&& || ; | |& &` and newlines and requires every leaf to match a rule
independently, which is exactly why a leaf PREFIX is the composable unit the operator asked for),
greedily set-covers the leaves no rule covers into 1–3-token `Bash(<head>:*)` heads ranked by
distinct sessions, refutes each candidate through the eleven gates in §3 before it is ever
proposed, consolidates the operator's own exact "yes, don't ask again" entries into the prefixes
that shadow them, and emits a report plus a JSON proposal that only an operator-run `--apply` can
write into any settings file.

### 2. RUN — read-only, and the report is relayed VERBATIM

Run `cc-permission-harvest 30` (the argument is the window in days; `0` or absent = all history).
It writes nothing. For the machine-readable form add `--json --out ~/.claude/autonomy/permission-harvest/`,
which writes `proposal-<UTC>.json` and a `latest.json` copy. `cc-permission-harvest --check` re-runs
the whole pipeline live and prints, per proposed rule, keep or drop with the gate code and the
per-target diff — that is how you answer "why was X not proposed" without reading any code.
`--check` is the HUMAN preview and exits 0 when there IS work; `--falsify` is its inverse (exit 0
only when nothing is left to apply, settings-only, no pipeline) and is the ONLY form that may be
stored as a backlog row's `--falsifier` — see §8.

🚨 **The report is a RENDERED artifact: reproduce it in full, then add at most three lines of
interpretation.** CLAUDE.md § Communication Discipline — summarising a renderer's output into
bullets silently re-creates the second renderer the tool exists to prevent, and the dropped column
is always the one that mattered. The same rule governs `--check` output and the per-file diffs
`--apply` prints.

### 3. READ — the buckets, the gates, the blind states, and the ceiling

**Buckets are MECE and sum to `inputs.rows`.** The first two are the headline; the rule list is not.

| bucket | what it means |
|---|---|
| `structural` | ≥1 hard-gated construct — `$( )`, backticks, process substitution, subshell, `{ }`, trailing `&`, redirect to a file, heredoc, `bash -c`, >10,000 chars, multiple `cd`, `cd`+`git`. Gated BEFORE rule matching: no allow rule of any form clears it |
| `hook_raised` | joined by `session_id` and ±15 s to one of our own PreToolUse hooks' `ask` decisions. The hook asked; hooks precede rules, so a rule cannot pre-empt it |
| `ask_hit` | a leaf matched an operator `ask` rule. A deliberate prompt — leave it alone |
| `deny_hit` | a leaf matched a `deny` rule |
| `truncated` | the beacon cut the payload at `CC_PERMARCHIVE_MAXLEN`; the command text is unjudgeable, so the row is counted and never used |
| `hook_or_classifier` | every leaf IS covered by a rule in force, so the prompt came from a hook or the auto-mode classifier — never a rule gap |
| `rule_gap` | non-structural, not hook-raised, ≥1 leaf no rule covers. **The only bucket a rule can fix** |
| `gap_unrecoverable` | a rule gap whose `cwd` no longer exists (a reaped worktree), so the project-local rules in force at prompt time cannot be reconstructed. Scored against the union of all discovered local rules and excluded from `MIN_EVIDENCE` counting |

**The eleven refutation gates.** Every candidate carries every gate's verdict; a refused candidate
is reported WITH the prompts it would have cleared, so the cost of refusing it is visible.

| code | refuses when |
|---|---|
| `ACE_CLASS` | the head's verb runs whatever follows it — interpreters, shells, exec wrappers, env runners, `xargs`/`sudo`/`npx`, plus the persistence and launch verbs (`launchctl defaults crontab at osascript automator open security export set`) and `find`, whose `-exec`/`-delete` no head can pin past. The 2026-08-23 `Bash(bash:*)` / `Bash(python3:*)` refutation, made mechanical |
| `ARG_EXEC` | the verb takes an exec-bearing ARGUMENT the head's own tokens do not pin past — `git rebase -x`, `bisect run`, `filter-branch`, `submodule foreach`, `difftool --extcmd`, global `git -c`; `tar -I`, `rsync -e`, `ssh -o ProxyCommand`, `sort --compress-program`. Measured: `git rebase -x 'touch MARK' --root` executes, so `Bash(git rebase:*)` is refused while `Bash(git rebase --abort:*)` passes |
| `FLAG_HEAD` | the head's last token starts with `-`. `rm -f`, `sed -n`, `curl -sS` are the bare verb in disguise and inherit every verdict of that verb |
| `SHELL_KEYWORD` | the head is a shell keyword (`do done then fi else elif for while until if [ [[ # set export case esac function select time`). The harness's own splitter saves loop and test leaves as exact acceptances — 73 exist — and `Bash(do:*)` is nonsense that passes every other gate |
| `HOOK_OWNED` | a shipped PreToolUse hook owns that head's decision: `rm`/`rmdir` → `validate-bash.sh`'s rm guard and `rm-safe-allowlist.sh`, `curl`/`wget` → `curl-gate.py`, `git push` (and bare `git`, which reaches it) → `ship-rail-push-allow.sh`. Proposing it claims a clearance that cannot happen |
| `AUTO_MODE_DROP` | the rule is discarded by `--permission-mode auto` before matching. Inert in the mode every session on this box runs, so it would read as coverage and cover nothing |
| `ASK_DENY_COLLISION` | the head collides with any `deny`/`ask` content in the discovered union (fleet AND project). **Bidirectional** for 1-token heads and any `FLAG_HEAD` shape — `Bash(git:*)` and `Bash(rm:*)` are refused ON PURPOSE. **One-directional** only for ≥2-token heads ending in a sub-verb, where `Bash(git stash:*)` under `ask Bash(git stash drop:*)` is the legitimate carve-out and is named in the receipt |
| `REFUSED_PROMPT_COLLISION` | any leaf of any row the operator refused (Stop-resolved) or a transcript proves was rejected carries this head — structural rows included. Auto-approving inverts a recorded human decision. `abandoned` (SessionEnd; nobody answered) is a receipt flag, never a refusal |
| `MIN_EVIDENCE` | fewer than 2 rows, or 2 distinct sessions, or 2 distinct ISO weeks. **No escape clause** — `approved` is only a tiebreaker; a one-row candidate is a one-shot acceptance wearing a prefix. A consolidation cluster needs `--min-cluster` (2) exact entries under one 2-token head |
| `PATH_BOUND` | the head names a LOCATION rather than a program — any token carrying `/`, `~`, `$`, `tmp`, 7+ hex chars, or all digits. Scope-aware: a repo-relative script head (`./scripts/x.sh`) may pass only into the project file its acceptances came from, never fleet-wide |
| `TOKEN_CAP` | the head is longer than 3 tokens or carries `*`, `?`, `[` (consolidation heads: 2). Prefix form only, never a wildcard mid-rule |

**BLIND is exit 3, and it is not `proposed=0`.** The tool reports BLIND when the archive is absent,
unreadable, or only partly readable, and when the oracle is **DARK** — the beacon's own
`.archive-alive` heartbeat older than `CC_PERMHARVEST_ORACLE_MAX_AGE_S` (259200 s = 3 days), or
`rows_in_window == 0` while archive files exist. A dead beacon would otherwise render as a healthy
quiet week, forever, and every week after it.

**The honest ceiling — quote these with their date.** Measured 2026-09-08 over 3,728 archived Bash
prompts (`docs/research/permission-harvest-profile-2026-09-08.md`): STRUCTURAL **45.4 %**, RULE_GAP
46.0 % of which 1,367 of 1,368 curl-only rows were `curl-gate.py` asks (so the defensible rule gap
is ~9 %), ASK_HIT 6.0 %, TRUNCATED 2.3 %. After the §3 gates the greedy set cover clears **13–21
prompts ever — 0.35 %–0.56 % of all Bash prompts — and 0 in the last 7 days**; it terminates at 4–5
picks because nothing else reaches `MIN_EVIDENCE`, so there is no "top 20" to write. Of the 1,622 h
agents spent waiting at prompts, **65.7 % sits in the structural bucket.** The material half is
consolidation (`docs/research/permission-harvest-acceptances-2026-09-08.md`): the five fleet
`settings.json` hold 1,272 Bash allows that are ALL already `:*` prefixes with **0 exact and 0
dead**, while **975 exact acceptances live in project `settings.local.json`** (67 % path-bound), and
the ceiling at `--min-cluster 2` is **58 prefixes retiring 254 entries**. **~60 % of the exact
corpus can never be retired by any gate-passing prefix**, dominated by three clusters the report
lists as `unretirable`: `ssh -i` ×181 (`AUTO_MODE_DROP`), `perl -ne` ×82 (`ACE_CLASS`), and
`git -C <path>` ×82 (the matcher does not skip `-C`, so the head is un-normalisable). 3-token heads
rescue 2 entries in the entire corpus. **`proposed=0` is the expected steady state here, not a
failure.**

**The 8-week trend comes from `~/.claude/logs/permission-harvest.jsonl`, never from the proposal
files.** One JSON line per weekly run: `ts`, `verdict` (`proposed|nothing|blind|error`), `rc`,
`proposed`, `refused`, `rows_in_window`, `sessions_in_window`, `oracle_age_s`, `structural_share`,
`hook_raised_share`, `rule_gap`, `top_structural_kind`, `consolidation_prefixes`,
`consolidation_retires`, `proposal_path`, `sha`. Proposal files are pruned at 90 days and each one
is a snapshot of a single run; the shares over time are the finding, and only this log holds them.

### 4. DRIVE — what you do yourself, in the session

- **STRUCTURAL and HOOK_RAISED clusters are the real levers, and they are hook-category work.**
  The dominant kinds — command substitution, redirect-to-file, heredoc, `cd`+`git`, multiple `cd` —
  are authoring habits, and their remedy lives in `hooks/lib/smart-bash-allowlist.py` (which already
  decomposes and judges `$( )` contents) or in the hook that raised the ask. **Drive it or drop it.**
  A FILED row needs a named impossibility class, per CLAUDE.md § Three dispositions; "it needs more
  investigation" is a reason, not an impossibility.
- **Measured levers accrue on ONE standing row.** The condition-keyed backlog row whose
  `--condition` is `permission-harvest-structural-levers` is where a new measured lever is
  recorded — **update that row, never mint a sibling.** A second row for the same condition splits
  the evidence and neither half ever reaches a threshold. Find it by condition, not by guessing a
  title: `cc-backlog list --json | jq -r '.[] | select(.condition == "permission-harvest-structural-levers") | "\(.id)\t\(.status)"'`.
  If that prints nothing the row has been closed, and a NEW measured lever is the occasion to open
  it again with the same `--condition` — that is the one case where minting is correct.
- **Consolidation findings need nothing from you in-session.** They are carried by `--apply`, into
  the project-local file each cluster came from. Do not hand-edit those files to "help".
- **`ask_hit`, `deny_hit` and `hook_or_classifier` rows are not work.** They are the operator's own
  fence and our own hooks doing their job; naming their share is the deliverable.

### 5. HAND OVER — the ONE operator step

The weekly run files exactly one backlog row when `proposed + consolidation_prefixes > 0`. Give the
operator its id and nothing else:

▶ Run this:

`cc-do <id>`

That row's `--run` is the argument-free apply invocation (`CONFIRM=1 $HOME/.claude/bin/cc-permission-harvest --apply`):
no proposal path and no rule text ride the queue, so nothing attacker-controllable is stored, and
the tool resolves `latest.json` itself. `cc-do` prints the command, takes the operator's typed
`yes`, runs it, and marks the row `done`. Apply re-runs every gate against the LIVE files and the
LIVE archive and writes `proposed ∩ fresh`, so a tampered or decayed proposal can only SHRINK the
set. The row's `--falsifier` is `--falsify` — **never `--check`, whose exit sense is the opposite** —
which the autonomy sweep runs every 6 h: `--falsify` exits 0 only when nothing is left to apply,
which is the exit cc-premise reads as "close this row", so an applied or decayed proposal closes its
own row and a live one never does. (It was `--check` until 2026-09-09; that wiring auto-closed the
apply step within 6 h of filing it, recording `done` over an apply that never ran.) `--falsify` is
settings-only and finishes in well under cc-premise's 20 s probe bound; `--check` re-runs the whole
1,045-second pipeline and would simply time out, i.e. answer nothing.

**Why it is theirs and not yours.** Permission config IS authorization, and an agent that can widen
its own permissions does not have permissions. This is enforced at the chokepoint, not by an
env check the agent controls: `hooks/validate-bash.sh` DENIES any leaf whose argv carries a
`cc-permission-harvest` token together with `--apply`. Hooks precede rules and the classifier and
cannot be unset from inside a session. **There is no override variable, and asking for one is the
defect** — the answer is `cc-do`.

### 6. NEVER

- **Never run `--apply` in-session** (see §5) and never route around the deny arm.
- **Never edit `settings.json` / `settings.local.json` by hand**, in any config dir, for any reason.
- **Never propose a head that fails `ACE_CLASS` or `ARG_EXEC`** — including "just this once, it is
  obviously safe". `Bash(bash:*)` and `Bash(python3:*)` were both obviously safe to somebody.
- **Never quote a `bash-commands.log` count as a prompt count.** That log is a post-hook
  pass-through record of Bash calls; under auto mode almost none of them prompted. It answers
  exactly one question — what a candidate rule would NEWLY admit — and it is a receipt, never a gate.
- **Never re-add the rules the 2026-08-23 verifier refuted**, and never revive a proposal by
  re-deriving it from a different store.
- **Never relax `ASK_DENY_COLLISION` to one-directional for a 1-token or flag-shaped head.** That
  relaxation mints `Bash(rm -rf:*)` and `Bash(git:*)`; it was proposed with 85 % conviction and
  rejected on the measurement.
- **Never say a PreToolUse hook `allow` bypasses the permission system.** It does not: the harness
  re-checks `deny` and `ask` after a hook allow (docs `/permissions` line 442; `Mfr` in the binary).
  A hook exiting 2 blocks before rules are evaluated — that is the arm that beats an allow rule.

### 7. WEEKLY

`launchd/com.claude.permission-harvest.plist` runs `scripts/permission-harvest-run.sh` on
**Sunday 04:17**, with **`RunAtLoad` false**. It was `true` on the reasoning that "a read-only
reporter seeds its evidence at bootstrap"; measured 2026-09-09, the same invocation takes
**1,045 s** and reads ~8.5 GB on the live stores, so every bootstrap fired a multi-GB scan while
holding the wrapper's lock. A freshly-installed job therefore reads NEVER-RAN on the fleet board
until the first Sunday; `launchctl kickstart -k gui/$(id -u)/com.claude.permission-harvest` seeds
it sooner if you want the row now. The run itself is bounded by `CC_PERMHARVEST_MAX_S` (3600 s ⇒
exit 6 ⇒ `verdict=error`), so a hang can no longer sit on the lock. The wrapper appends one line to
`~/.claude/logs/permission-harvest.jsonl` — the fleet evidence path AND the trend store of §3 — and
prunes proposals older than 90 days. The `launchd/fleet.manifest` row declares `interval_s`
**604800**, so `cc-fleet`'s stale bound is interval × 3 = **21 days** (`0` would mean DAILY and read
a healthy weekly job as STALLED four days of every seven). BLIND exits 3, which surfaces as **S4
FAILING** on the fleet board — deliberately, with no `ok_exits` column to launder it.
`install.sh` copies and bootstraps a manifest-`run` plist at every converge, so there is **no
migration and no bespoke activation script**; `18-fleet-activate.sh` is the manifest's recovery arm.
🚨 **Every file in this loop is NEW**, so nothing is live until `scripts/deploy-live.sh` converges —
an added file has no symlink, is absent from the live tree, and every consumer guard on it is a
SILENT skip. That is the `LIVE_ADDS` rung: a land that adds files is not live until the converger
has run.

### 8. TROUBLESHOOTING

- **Exit codes.** `0` = ran (including `proposed=0`, and including a rule dropped at apply time for
  decayed evidence) · `1` = `--check` found nothing that would apply, **or** `--falsify` found
  something still outstanding (or could not tell — it fails closed); the two flags are inverses and
  only `--falsify` may be stored as a row's `--falsifier` · `2` = bad invocation (unknown flag,
  unparseable proposal) · `3` = **BLIND** (§3) · `4` = a rule failed a gate at apply time, or a
  target was refused — both named · `5` = write failure, every touched file restored from its
  `.permharvest-bak-<UTC>` · `6` = **DEADLINE**: the read-only pipeline ran past
  `CC_PERMHARVEST_MAX_S` (3600 s — ~3.4x the 1,045 s measured runtime; the bound exists to stop a
  wedged run holding the wrapper's lock, not to make the job fast) and was cut rather than emit a
  partial proposal. The weekly wrapper
  maps it to `verdict=error`, so it lands on cc-fleet S4 instead of reading as a quiet week.
- **`proposed=0` always carries its denominator** — `rows_in_window` and `oracle_age_s` on the same
  line. Read them before calling it a quiet week: 0 rows with a fresh heartbeat is a quiet week;
  0 rows with a stale one is exit 3.
- **A decayed rule is a NAMED DROP, not a failure.** Apply writes `proposed ∩ fresh`; a rule whose
  evidence aged below `MIN_EVIDENCE` between proposal and apply is printed by name at exit 0. Do
  not re-propose it by hand.
- **`settings.json` is forked across five real files** (`~/.claude`, `-next`, `-secondary`,
  `-tertiary`, `-quaternary`) with five different md5s, and the config mirror does not heal it.
  Apply writes all five, all-or-nothing with a backup each, or the change silently lands on one
  account. Project-local targets must be gitignored; a target whose realpath resolves inside a git
  worktree is refused (exit 4) unless named with `--target`.
- **Two interpreters, and the gate runs the one launchd will.** `/usr/bin/python3` is 3.9.6 and is
  what the wrapper invokes by absolute path; the interactive `python3` is 3.11.4. Code and tests
  target 3.9-compatible syntax — a 3.11-only construct passes at the desk and dies on Sunday.
- **Nothing here reads or writes `~/.claude` in tests.** Every suite fixtures the archive, the
  settings files, the corpus and the transcripts under `$BATS_TEST_TMPDIR`.
