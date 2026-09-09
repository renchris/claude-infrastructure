# Permission-harvest profile — what prefix allow rules can ACTUALLY clear, measured on the oracle

**Date:** 2026-09-08 · **Unit:** A1 (archive ceiling) of `docs/plans/PERMISSION_HARVEST.md` Phase 0 wave A ·
**Oracle:** `~/.claude/autonomy/permission-archive/*.jsonl`, every row with `tool_name == "Bash"` —
**3,728 rows** at run time (the archive is live-appended; the plan's 3,719 was the count when it was written,
and the figure moved by 7 rows during this session's runs), 690 sessions, 2026-07-31 → 2026-09-08 17:xx.

**Answer up front.** Of 3,728 archived Bash prompts, **1,714 (46.0%)** have at least one leaf no rule in force
covers — the necessary condition for a rule fix. But **1,368 of those (36.7% of ALL Bash prompts, 79.8% of the
gap bucket) are curl-only gaps that were raised by `hooks/curl-gate.py`** — measured by joining each row to the
curl-gate audit log (1,367/1,368 have a curl-gate `ask` in the same session within 15 s) — and no gate-passing
`Bash(curl…:*)` exists (every form is `AUTO_MODE_DROP` or `PATH_BOUND`). After the plan's own §3.2 gates, the
greedy set cover clears **21 prompts with 5 rules under per-cwd collision scope, 13 prompts with 4 rules under
fleet-wide collision scope, and 0 prompts in the last 7 days.** The honest ceiling of a top-10 / top-20
gate-passing rule set is therefore **13–21 archived prompts = 0.35%–0.56% of all Bash prompts**, and the set
cover terminates before 10 picks — there is no 20th rule to pick.

---

## 1. Method

Profiler: `/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/52e35019-17e8-40f6-a54f-3a04de70d2e6/scratchpad/a1/profile.py`
(throwaway; writes `report.json` + `rows.jsonl` beside itself). One pass over every Bash row:

| Step | Implementation | Fidelity |
|---|---|---|
| (a) classify | `_classify` **imported verbatim** from `bin/cc-permission-audit` via `importlib.machinery.SourceFileLoader` (extensionless file; `spec_from_file_location` returns no loader for it). `sys.argv` is neutralised around the import because the module parses argv at load. | faithful |
| (b) structural triage | hand-rolled quote-aware scanner over the command (single quotes literal; `$(`/backticks also counted inside double quotes): `$( )` (not `$((`), backticks, `<( )`/`>( )`, `( )` subshell vs `name()` function def, `{ …}` group at command position, background `&` (not `&&`, `>&`, `<&`, `&>`, `|&`), redirection `>`/`>>`/`N>`/`&>`/`>|` to any target other than `/dev/null` (fd dups `2>&1`, `>&2` exempt), heredoc `(?<!<)<<(?!<)` (body stripped via `smart-bash-allowlist.strip_heredocs` before scanning), `bash|sh|zsh|dash|ksh` leaf carrying a `-c`-bearing flag, length > 10,000, > 1 `cd` leaf, `cd`+`git` leaves (a `cd` back to the row's own cwd exempt), unbalanced quotes. Also recorded, NOT in the matcher doc: `function_def` (94) and `case_statement` (50) — tree-sitter nodes `MT` does not recurse into; counted structural conservatively, **UNVERIFIED** against the binary. | approximate — no tree-sitter |
| (c) leaves | own `qsplit` (quote-aware split on `&& \|\| ; ;; \| \|& &` and newlines — `smart-bash-allowlist.split_segments` minus its INDIRECTION pre-check, which refused on `<(` INSIDE quotes, e.g. a python regex `<(script\|style)`); keywords `if then else elif fi for while until do done ! { } esac in` peeled; `for VAR in LIST` / `case X in` / `pat)` / `;;` yield no leaf; bare assignments (`_ONLY_ASSIGNMENTS`) yield no leaf. Normalisation as `iae`: comment lines dropped, leading `VAR=val` stripped ONLY for the doc's env allowlist (the doc says "38-name" and lists **39** names — measured), wrappers `timeout time nice stdbuf nohup command builtin noglob` stripped with heuristic argument skipping, first token unquoted, whitespace collapsed for prefix/wildcard matching but **preserved for exact matching** (probe C#11). | faithful on the doc's probe table; wrapper-arg skipping heuristic |
| (d) rules | UNION of the 5 fleet `settings.json` + every `.claude/settings.json` / `.claude/settings.local.json` walking up from `row.cwd` to `~/Development`, deduped on (behaviour, kind, content). Match: exact `===`; prefix ws-normalised, space boundary, `xargs <prefix>`; wildcard glob→regex with `/**/` and the `' *'`-single-star optional tail; deny→ask→allow with strip-all-env for deny/ask. | faithful; **fidelity self-test 19/19** on the matcher doc's probe rows (double-space exact DENY, `LS -la`, `FOO=1`, `LC_ALL=C`, `timeout 5`, comment, `git status *` ↔ bare `git status`, `xargs grep` vs `xargs -n1 grep`, `2>/dev/null`) |
| (e)–(g) cover | candidate heads at 1/2/3 tokens of each uncovered normalised leaf; greedy pick = (rows fully cleared, uncovered leaves covered, Σ`waited_s`); a row clears when ALL its uncovered leaves are covered by rules-in-force ∪ picks. Gates applied at pick time: `ACE`, `AUTO_DROP` (`auto_mode_dropped` imported verbatim), `PATH_BOUND`, `ASK_DENY_COLLISION`, `TOKEN_CAP`, `REFUSED_PROMPT_COLLISION`, `MIN_EVIDENCE` (<2 rows or <2 sessions unless ≥1 approved), plus `VALUE_FLAG_TAIL` (plan §3.1 step 5: `git -C` is never a head) and `READONLY_BUILTIN`. `DANGER_WIDENING` not run (needs the corpus log — out of A1 scope). | as specified |

**Two honest limits of the rules-in-force reconstruction.** (1) **1,523 of 3,728 rows (40.9%) have a `cwd` that no
longer exists on disk** (reaped worktrees), so their project-local rules at prompt time are unrecoverable; they
match only the fleet + `~/Development/.claude/settings.local.json` (WebFetch/Read rules only). (2) Local rules are
read as they are NOW — a "yes, don't ask again" exact rule written by the very prompt being profiled makes that
row read as covered today (F19); measured effect is tiny: 3 of the 13 HOOK_OR_CLASSIFIER rows are covered by a
local exact rule.

---

## 2. Tables

### (a) Classification — signature-proven, never inferred

| class | rows | % | note |
|---|---|---|---|
| approved | 62 | 1.7% | `tool_sig`/`cleared_tool_sig` exist on rows from 2026-09-08 only (64 rows carry a signature) |
| refused | 23 | 0.6% | `resolved_by ∈ {Stop, SessionEnd}` |
| collateral | 379 | 10.2% | cleared by a provably different tool |
| unknown | 3,264 | 87.6% | same tool name, no id/signature — a gap in the RECORD |

Every candidate's approved/refused/unknown split below is dominated by `unknown` for this reason; the signature
mechanism has one day of history.

### (b)/(e) Buckets

| bucket | rows | % of 3,728 | Σ waited (h) | meaning |
|---|---|---|---|---|
| STRUCTURAL | 1,692 | 45.4% | 1,066.4 | ≥1 hard-gated construct; no rule of any form clears it |
| RULE_GAP | 1,714 | 46.0% | 259.8 | non-structural, ≥1 leaf no rule covers (necessary condition for a rule fix — see §2(f) for why most are not) |
| ASK_HIT | 224 | 6.0% | 163.6 | a leaf matched an operator `ask` rule — `git push:*` 171, `git reset --hard:*` 32, `git restore:*` 22, `git stash drop:*` 1. Deliberate prompts |
| TRUNCATED | 84 | 2.3% | 126.4 | beacon truncated the payload (>3,500 B); command text unjudgeable |
| HOOK_OR_CLASSIFIER | 13 | 0.3% | 6.4 | every leaf covered by a rule in force → the prompt came from a hook or the classifier |
| DENY_HIT | 1 | 0.0% | 0.0 | `Bash(rm -rf /*)` |

Total agent wall-clock at prompts: **1,622.6 h**; 65.7% of it sits in the STRUCTURAL bucket.

By window: last 30 d (2,968 rows, 434 sessions) — STRUCTURAL 1,089 · RULE_GAP 1,642 · ASK_HIT 164 · TRUNCATED 65 ·
HOC 7 · DENY 1. Last 7 d (476 rows, 134 sessions) — **STRUCTURAL 289 (60.7%)** · RULE_GAP 97 (20.4%) · ASK_HIT 48 ·
TRUNCATED 39 · HOC 2 · DENY 1.

### (h) Structural histogram — kinds per row (a row may carry several; 753 rows carry exactly one)

| kind | rows | sole-kind rows | top-10 verbs inside these rows |
|---|---|---|---|
| command_substitution | 1,007 | 388 | echo 3035 · git 1676 · cd 832 · rm 793 · grep 549 · mkdir 432 · tail 421 · printf 412 · head 377 · bash 348 |
| redirect_file | 769 | 135 | echo 2156 · git 1113 · rm 681 · cd 630 · mkdir 493 · printf 416 · cat 362 · bash 344 · grep 322 · head 258 |
| heredoc | 431 | 109 | echo 747 · git 541 · cat 313 · cd 302 · rm 260 · mkdir 202 · python3 188 · tail 160 · bash 134 · grep 118 |
| cd_git_compound | 307 | 44 | git 1069 · echo 899 · cd 469 · rm 277 · mkdir 154 · tail 147 · grep 143 · head 119 · printf 92 · export 85 |
| multi_cd | 239 | 43 | echo 664 · cd 534 · git 464 · rm 263 · mkdir 178 · grep 128 · head 125 · tail 119 · ls 63 · cat 61 |
| subshell | 148 | 8 | echo 480 · git 277 · rm 168 · mkdir 124 · cd 116 · printf 97 · grep 82 · head 70 · tail 69 · bash 68 |
| command_group | 127 | 0 | echo 528 · git 243 · rm 151 · printf 115 · cd 110 · cp 80 · mkdir 78 · grep 76 · bash 65 · [ 54 |
| function_def (UNVERIFIED gate) | 94 | 0 | echo 362 · git 162 · rm 120 · printf 97 · cd 71 · mkdir 71 · cp 71 · bash 55 · grep 53 · run_mutant 44 |
| truncated_payload | 84 | — | — |
| background `&` | 57 | 0 | echo 166 · rm 53 · sleep 51 · cd 40 · git 27 · grep 24 · kill 24 · mkdir 22 · cat 18 · [ 17 |
| bash_c | 56 | 20 | echo 115 · bash 85 · rm 36 · mkdir 31 · cd 24 · cat 17 · printf 17 · export 17 · git 14 |
| case_statement (UNVERIFIED gate) | 50 | 0 | echo 112 · git 54 · rm 42 · cd 37 · grep 34 · mkdir 29 · printf 25 · cat 22 |
| process_substitution | 22 | 2 | echo 89 · grep 25 · rm 23 · cd 20 · cp 17 · mkdir 16 · diff 14 · git 13 |
| unbalanced | 20 | 4 | echo 63 · git 31 · rm 26 · grep 23 · printf 17 · cd 15 · mkdir 14 |
| backtick | 3 | 0 | echo 7 · mkdir 3 · cp 3 · tail 3 |
| too_long (>10,000) | 0 | — | longest non-truncated command is 2,989 chars |

Kinds per structural row: 1→753 · 2→495 · 3→270 · 4→118 · 5→36 · 6→16 · 7→3 · 8→1. The 7-day mix is the same
shape (command_substitution 189 · redirect_file 136 · heredoc 79 · cd_git 45 · multi_cd 34). The dominant
verbs (`echo`, `git`, `cd`, `rm`, `mkdir`) are authoring habits — scratch-path preambles, `echo "=== step ==="`
banners, `cd <wt> && git …` — i.e. `smart-bash-allowlist.py` / hook-layer levers, not rule levers.

**Built-in read-only share of uncovered leaves (RULE_GAP):** 6 of 2,452 uncovered leaves (0.2%) have a head in
the docs' read-only set (`ls cat echo pwd head tail grep find wc which diff stat du cd` + read-only git); 33
(1.3%) under the wider probe-B-observed set (+ `date uname hostname id true false printf sleep whoami test [ [[`).
**0 rows** have all-read-only uncovered leaves (1 under the wider set). So the read-only auto-allow is not what
generated the gap bucket — the classifier and the hooks are (next table).

### (i) Distribution

| metric | value |
|---|---|
| simple rows (≤1 leaf, no structural kind) | 882 (24.2% of the 3,644 judgeable) |
| compound rows | 2,762 (75.8%) |
| multi-line rows | 1,681 (46.1%) |
| leaves per row | median 5 · mean 7.16 · p90 17 · max 66 |
| uncovered leaves per RULE_GAP row | 1→1,342 · 2→202 · 3→73 · 4→50 · 5→19 · ≥6→28 |
| RULE_GAP rows whose uncovered leaves share ONE verb | 1,432 of 1,714 |
| refused rows | **23** total — STRUCTURAL 17 · RULE_GAP 3 · ASK_HIT 2 · HOC 1 (`resolved_by` SessionEnd 16, Stop 7) |
| approved rows by bucket | STRUCTURAL 47 · TRUNCATED 11 · ASK_HIT 2 · HOC 2 · **RULE_GAP 0** |

The 3 refused RULE_GAP rows are all curl (`curl -s … http://gn.localhost:…`) — under the plan's
`REFUSED_PROMPT_COLLISION` gate they refuse `curl` heads independently of `AUTO_DROP`.

### (f) Candidate heads — greedy set cover, all rows, UNRESTRICTED (flags shown, nothing refused)

Uncovered-leaf verbs in RULE_GAP: `curl` 1,672 · `rm` 187 · `sort` 74 · `cp` 69 · `mkdir` 53 · `set` 47 · `sed` 45 ·
`export` 27 · `git` 26 · `.` 22 · `sleep` 13 · … Two-token: `curl -sS` 749 · `curl -sL` 447 · `curl -s` 406 ·
`rm -rf` 154 · `sort -u` 58 · `mkdir -p` 41 · `curl -sSL` 38 · `cp -R` 28 · `rm -f` 21.

| # | head (rule = `Bash(<head>:*)`) | rows cleared | appr/ref/unk/coll | sessions | Σ waited s | cum rows | flags |
|---|---|---|---|---|---|---|---|
| 1 | `curl` | 1,368 | 0/2/1151/215 | 60 | 346,160 | 1,368 | AUTO_DROP (and REFUSED_PROMPT_COLLISION ×2) |
| 2 | `sort` | 51 | 0/0/41/10 | 12 | 20,807 | 1,419 | — (clears rows only after #1) |
| 3 | `rm` | 45 | 0/0/44/1 | 33 | 71,668 | 1,464 | ASK_DENY_COLLISION |
| 4 | `sed` | 34 | 0/0/30/4 | 10 | 26,099 | 1,498 | ASK_DENY_COLLISION (`sed -i*/.env*` deny) |
| 5 | `git` | 11 | 0/0/11/0 | 10 | 46,852 | 1,509 | ASK_DENY_COLLISION |
| 6 | `export` | 10 | 0/0/9/1 | 6 | 56,180 | 1,519 | — (PATH manipulation; ACE-adjacent, see §3) |
| 7 | `open` | 9 | 0/0/9/0 | 2 | 897 | 1,528 | — |
| 8 | `sleep` | 8 | 0/0/7/1 | 3 | 208 | 1,536 | — |
| 9 | `cp` | 7 | 0/0/6/1 | 7 | 258 | 1,543 | — |
| 10 | `mkdir` | 11 | 0/0/10/1 | 10 | 142,116 | 1,554 | — |
| 11 | `gh` | 8 | 0/1/7/0 | 5 | 69,058 | 1,562 | ASK_DENY_COLLISION (`gh pr create` deny), REFUSED ×1 |
| 12 | `pdftotext` | 7 | 0/0/7/0 | 1 | 404 | 1,569 | — (1 session) |
| 13 | `bash` | 6 | 0/0/6/0 | 6 | 3,250 | 1,575 | ACE, AUTO_DROP |
| 14 | `tar` | 6 | 0/0/6/0 | 5 | 163 | 1,581 | — |
| 15 | `printf` | 5 | 0/0/4/1 | 3 | 82 | 1,586 | — |
| 16 | `sips` | 5 | 0/0/5/0 | 1 | 20 | 1,591 | — (1 session) |
| 17 | `cc-backlog` | 5 | 0/0/5/0 | 5 | 2,015 | 1,596 | — |
| 18 | `set` | 4 | 0/0/4/0 | 4 | 312 | 1,600 | — |
| 19 | `.` | 20 | 0/0/17/3 | 1 | 70 | 1,620 | ACE (`. ./.env.local`, 1 session) |
| 20 | `sqlite3` | 4 | 0/0/3/1 | 4 | 56 | 1,624 | — |
| 21 | `pkill` | 4 | 0/0/4/0 | 4 | 22,561 | 1,628 | — |
| 22 | `node` | 4 | 0/0/4/0 | 4 | 1,017 | 1,632 | ACE, AUTO_DROP |
| 23 | `ln` | 3 | 0/0/3/0 | 2 | 13 | 1,635 | — |
| 24 | `[` | 4 | 0/0/4/0 | 3 | 1,528 | 1,639 | TOKEN_CAP |
| 25 | `du` | 3 | 0/0/3/0 | 3 | 3,099 | 1,642 | READONLY_BUILTIN |
| 26 | `awk` | 3 | 0/0/3/0 | 3 | 20 | 1,645 | ACE |
| 27 | `egrep` | 3 | 0/0/3/0 | 1 | 10 | 1,648 | — |
| 28 | `chmod` | 2 | 0/0/2/0 | 2 | 14,043 | 1,650 | ASK_DENY_COLLISION |
| 29 | `/Users/chrisren/.claude/bin/cc-bats` | 3 | 0/0/3/0 | 3 | 1,139 | 1,653 | PATH_BOUND |
| 30 | `npx` | 2 | 0/0/2/0 | 2 | 29 | 1,655 | ACE, AUTO_DROP, ASK_DENY_COLLISION |
| 31 | `RIG_DEV_LOG=$S/dev.log` | 2 | 0/0/2/0 | 1 | 155 | 1,657 | PATH_BOUND (non-allowlisted env prefix) |
| 32 | `npm` | 2 | 0/0/2/0 | 1 | 15 | 1,659 | — |
| 33 | `soffice` | 2 | 0/0/1/1 | 1 | 8 | 1,661 | — |
| 34 | *(empty head — a leaf that is only a quoted string)* | 2 | 0/0/1/1 | 2 | 6 | 1,663 | — |
| 35 | `launchctl` | 2 | 0/0/2/0 | 2 | 27,894 | 1,665 | — |
| 36 | `/Applications/Blender.app/Contents/MacOS/Blender` | 2 | 0/0/2/0 | 1 | 63 | 1,667 | PATH_BOUND |
| 37 | `CC_FIRED_DIR="$SB/fired"` | 1 | 0/0/1/0 | 1 | 28,879 | 1,668 | PATH_BOUND |
| 38 | `$B` | 1 | 0/0/1/0 | 1 | 91 | 1,669 | PATH_BOUND |
| 39 | `$FF` | 1 | 0/0/1/0 | 1 | 5 | 1,670 | PATH_BOUND |
| 40 | `magick` | 2 | 0/0/2/0 | 1 | 60 | 1,672 | — |

Unrestricted, 40 picks clear 1,672 of 1,714 gap rows (cum10 = 1,554, cum20 = 1,624) — **but 1,368 of them ride on
`Bash(curl:*)`**, which is dropped in auto mode (the mode every session runs) and, per the audit-log join, would
not have pre-empted the hook that raised the prompt anyway. The 1-token heads listed pass or fail on their own
merits; every 2-/3-token curl head (`curl -sS`, `curl -sL`, `curl -s`, `curl -sSL`, `curl -sG`, `curl -sI`) is
`AUTO_DROP` (flag tail) and every `curl https://…` head is `PATH_BOUND`.

### (f) cont. — GATE-PASSING set cover (ACE · AUTO_DROP · PATH_BOUND · ASK_DENY_COLLISION · TOKEN_CAP · VALUE_FLAG_TAIL · REFUSED_PROMPT_COLLISION · MIN_EVIDENCE · READONLY_BUILTIN)

Collision scope A = deny/ask rules reachable from each row's cwd (55 distinct contents). Scope B = every
deny/ask rule in every discovered settings file (61 — adds `finance-ai-web-app`'s `ask: Bash(rm -r:*)`,
`Bash(rm -rf:*)`, `Bash(mv:*)`), which is the scope a FLEET apply target should honour.

| # | head | rows | unk/coll | sessions | Σ waited s | cum (scope A) | scope B |
|---|---|---|---|---|---|---|---|
| 1 | `rm -r` | 7 | 7/0 | 4 | 6,063 | 7 | **refused** (collides with `ask Bash(rm -r:*)`) |
| 2 | `export` | 3 | 3/0 | 2 | 21,522 | 10 | 3 |
| 3 | `rm -f` | 5 | 5/0 | 5 | 31,857 | 15 | 7 (4 rows) |
| 4 | `cc-backlog` | 4 | 4/0 | 4 | 237 | 19 | 11 |
| 5 | `launchctl` | 2 | 2/0 | 2 | 27,894 | 21 | 13 |
| — | *cover terminates: no remaining candidate passes MIN_EVIDENCE* | | | | | **21** | **13** |

Approved (signature-proven) rows cleared: **0** in either scope. `REFUSED_PROMPT_COLLISION` refused nothing here
(the 3 refused gap rows are curl). Note `rm -r`/`rm -f` are also `hooks/validate-bash.sh` territory — the rm
guard emits `permissionDecision: ask`, which an allow rule does not pre-empt (READ: matcher doc §3 precedence;
INFERRED for the `ask` verdict specifically, only exit-2 was documented) — so their 12 rows are an upper bound.

### (g) Windows

| window | Bash rows | RULE_GAP | curl-only gap | unrestricted top-1 | gated (A) rules → rows | gated (B) rules → rows |
|---|---|---|---|---|---|---|
| all (2026-07-31 →) | 3,728 | 1,714 | 1,368 | `curl` 1,368 | 5 → 21 (0.56%) | 4 → 13 (0.35%) |
| last 30 d | 2,968 | 1,642 | 1,368 | `curl` 1,368 | 4 → 11 (`export` 3, `rm -f` 3, `rm -r` 3, `launchctl` 2) | 3 → 8 |
| last 7 d | 476 | 97 | 60 | `curl` 60 (12 sessions, 242,364 s waited) | **0 → 0** | **0 → 0** |

Last-7-day unrestricted picks after `curl`: `rm` 5 (ASK_DENY), `sort` 5, `mkdir` 2, `export` 2, `printf` 2,
`git` 2 (ASK_DENY), then singletons — nothing reaches `MIN_EVIDENCE` once curl and the collision heads are out.
All 1,368 curl-only rows fall inside the 30-day window; only 240 predate the 2026-08-23 curl-gate fix
(`6bf610045`/`d8b517b28`), so the post-fix residual (`ask` on credential-carrying requests, non-public hosts,
`gn.localhost` dev servers) is what the archive now records — 60 in the last week.

### The curl join — MEASURED, not inferred

`~/.reso/curl-audit.jsonl` (5,566 rows) holds every curl-gate decision with `session_id` and an ISO `ts`. For the
1,368 curl-only RULE_GAP rows: **1,367 have a curl-gate `ask` in the same session within ±15 s of the prompt's
`ts`; 1 has no audit row in range; 0 have only allow/deny.** The gap bucket's dominant member was produced by a
PreToolUse hook, and hooks sit above allow rules in the precedence chain.

---

## 3. What this means for the harvester

1. **The ceiling is 13–21 archived prompts, 0.35%–0.56% of all Bash prompts, and 0 in the last 7 days.** A
   top-10 gate-passing rule set does not exist — the greedy cover terminates at 4 (fleet-wide collision scope) or 5
   (per-cwd scope) rules because nothing else reaches 2 rows × 2 sessions. A "top-20" is the same set. Of the
   1,622 h agents spent waiting at Bash prompts, these rules recover at most ~24 h (Σ waited of the cleared rows),
   and that assumes the prompt was raised by the rule gap rather than by the classifier.
2. **What the gap bucket actually is:** 79.8% curl (hook-raised, measured); 10.1% `rm` (173 rows; hook-guarded and
   `ask`/`deny`-colliding); the rest is a long tail of 1–5-row heads dominated by one-session bursts (`pdftotext`,
   `sips`, `.`, `open`, `soffice`, `magick`). `sort` looks large (51) only because it co-occurs with curl and clears
   nothing on its own. The harvester's gates as designed in §3.2 refute exactly the right things — `curl` by
   `AUTO_MODE_DROP`/`REFUSED_PROMPT_COLLISION`, `rm` by `ASK_DENY_COLLISION`, `bash`/`node`/`npx`/`.`/`awk` by
   `ACE_CLASS`, path-ful heads by `PATH_BOUND` — and what survives is small because the operator's rules were
   already right, not because the matcher is stingy.
3. **Collision scope must be fleet-wide.** Under per-cwd scope `Bash(rm -r:*)` is the top gate-passing proposal (7
   rows); `finance-ai-web-app/.claude/settings.local.json` carries `ask Bash(rm -r:*)`, so a fleet-level allow is
   dead in that project and inverts a recorded operator decision. Apply targets the 5 fleet files → the gate must
   read every discovered deny/ask, not the prompt's own cwd chain.
4. **`export` should be treated as ACE-adjacent.** `Bash(export:*)` is the #1 fleet-wide survivor (3 rows), but 19
   of its 27 uncovered leaves are `export PATH=…` (12× `"$HOME/.claude/bin:$PATH"`, 7× an Application Support path) — a rule that approves PATH rewrites
   approves whatever resolves next. Recommend adding `export` (and `set`, `source`, `.`) to the ACE list.
5. **Structural is 45% of all prompts and 66% of waited time, and it is stable week over week** (60.7% of the last
   7 days). `command_substitution` (1,007 rows), `redirect_file` (769), `heredoc` (431), `cd_git_compound` (307),
   `multi_cd` (239) are the levers, and they are authoring-habit / hook-layer levers: `smart-bash-allowlist.py`
   already judges `$( )` contents (its docstring cites 543/1,747 blocking commands on exactly this), and a
   `cd <wt> && git …` habit is a brief-template fix. The harvester should report these as its headline, per plan
   §3.1 step 3 — the report's first line is "45% of prompts cannot be cleared by any rule", not a rule list.
6. **The `unknown` classification dominates (87.6%)** because signatures began 2026-09-08. `MIN_EVIDENCE`'s
   "unless ≥1 approved" escape clears nothing today (0 approved rows in RULE_GAP); a week of signatures will change
   that, and the harvester should print the approved/unknown split so the reader sees when proof arrives.
7. **The consolidation half (plan §3.1 step 8) is the part of the loop with real material.** 6,927 Bash allow
   entries across the 143 settings files discovered under `~/.claude*` and `~/Development`, 51 exact entries in `claude-infrastructure/.claude/settings.local.json`
   alone, 277 in reso's; none of that shows up in the archive because an exact acceptance never re-prompts. The
   archive measures the FUTURE prompt reduction of a prefix (≈0); the exact-entry clusters measure the
   simplification — that is where "refactor individual acceptances into composable patterns" has a denominator.

**Recommendation for wave B/C:** keep the harvester's honest `proposed=0` path as the expected outcome on this
fleet, make the STRUCTURAL breakdown and the curl-gate attribution its primary output, gate collisions
fleet-wide, add `export`/`set`/`source` to ACE, and size the recurring job's value on consolidation, not on
prompt reduction — the archive says prompt reduction from allow rules is ≤0.6% and trending to 0.
