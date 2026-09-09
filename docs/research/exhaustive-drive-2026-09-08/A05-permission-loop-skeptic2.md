# A05 — Permission loop: SKEPTIC pass 2

**Wave:** exhaustive-drive 2026-09-08 · **Axis under review:** A05-permission-loop · **Mode:** read-only, refute by default.
A first skeptic pass (`A05-permission-loop-skeptic.md`, 17:36) already exists; this pass re-derives its load-bearing refutations
independently (it agrees on every one) and adds the one measurement neither the axis nor pass 1 ran: **what `decide()` itself
would clear if R1+R2+R4 were built.** Every number here is **measured** in this pass unless marked *inferred*. Scratch:
`<scratchpad>/sk-*.{jsonl,txt}` (perm30 rebuilt at cutoff 2026-08-09T23:4xZ: 3,050 rows / 2,971 Bash + 79 AskUserQuestion).
`timeout` is not on PATH in the Bash tool's zsh; every long command below ran under `/opt/homebrew/bin/gtimeout`.

## Verdict in one paragraph

The axis's **cost** instruments reproduce (1,175.9 h / 3,050 prompts; 23 sids / 84.4 h / 49 episodes in the IDL) and its four
parser defects are real at the cited functions. Its **value** arithmetic does not survive: the "~260 blocked hours recoverable
from R1–R4" counts the hours of every command that *contains* a fixable segment, but `decide()` (`smart-bash-allowlist.py:1006`)
allows a command only when **every** segment clears, and the mktemp-scratch compounds that carry those hours have other failing
segments (git 89, bash 81, rm 69, printf 43, cp 43, tar 30 …). Monkey-patching `allowed_segment` to grant a *generous* R1+R2+R4
and re-running the live `decide()` over all 2,905 Bash prompts gains **2 commands and 12.9 h** (from 157 allow / 3.5 h to
159 / 16.4 h) — about **1%** of the 1,040 h, not 25%. Three recommendations are refuted outright (R3 — `Bash(rm -rf /*)` is a
wildcard deny the axis never read; R7 — the `is_error` text is the same category-free string; R4 — only 44% of the
`rm -rf "$VAR"` family is mktemp-assigned in-command, and even those do not clear). The axis's framing of the pre-gate as
"unreachable by any allow rule" is default-mode semantics: in auto mode the classifier overrides the substitution gate
(matcher-truth §3, measured), so the 43.7% is not why hours are lost; the slow stratum (>300 s, 439 Bash rows) is **69.2%**
pre-gated and was **batch-approved by the operator** (10/11 of today's 6–8 h blocks, SIG-MATCH, 12:57–12:58Z). The
silent-in-the-dangerous-state defect is the one pass 1 named: the escalation ladder landed today and is not running
(**0** `permission_pending_escalate` in 5,155 records; **114/114** `.permpend.notified` markers carry a bare ts, the pre-ladder format,
the newest written 23:28Z).

## 1. Re-measurements of the axis's key numbers

| # | claim | axis | rechecked (command → result) | holds |
|---|---|---|---|---|
| 1 | 30-d prompts / blocked hours | 3,046 / 1,172.5 h | `jq -c 'select(.ts>=now-30d)' → 3,050`; `jq -r .waited_s \| awk` → **1,175.9 h** | yes |
| 2 | tool_sig attribution | 50/56 = 89% | same jq → **64 MATCH / 12 MISMATCH = 84%** (n=76, subsample grew) | yes, weaker |
| 3 | IDL sessions blocked today | 22 sids / 83.8 h | `grep permission_pending idl.jsonl` → 5,155 rows; per-sid max age → **23 sids / 84.4 h / 49 (sid,since) episodes**; top 11 at 5.77–7.86 h | yes |
| 4 | escalation "one page every 9 s" | 5,117 records | 5,155 `permission_pending` records are the per-30 s-sweep telemetry (`page_permpend` :553 writes `idl` on **every** sweep); pages are damped per episode (`send_page … "permpend:$sid:$ts"`, :571); `grep -c permpend idl.jsonl` → 367 page-related lines; `permission_pending_escalate` → **0** | **refuted as framed** |
| 5 | pre-gate share | 1,270/2,905 = 43.7% | axis's `pregate2.py` on my perm30 → **1,273/2,905 = 43.8%**; on the slow (>300 s) stratum → **304/439 = 69.2%** | yes; the slow number is the one that matters |
| 6 | live decider clears 5.4% | 157/2,905, 3.5 h | `replay.py` → **157 / 2,905, 3.5 h, 7 slow**; ALLOW rows by date: 154 of 157 on or before 08-28, 3 after — a measure of history, not headroom | yes, mis-framed |
| 7 | verbs by hours | rm 428 h, git 345 h, bash 177 h | `replay2.py` on slow rows → rm 431.0 h / git 346.3 h / bash 178.3 h / curl 117.9 h / python3 103.2 h | yes |
| 8 | D1–D4 probes | as stated | live module: `git -C … log` → defer "segment not on the allowlist"; `T=$(mktemp -d); …` → "inside a substitution: … mktemp -d"; `rm -rf "$T"` → defer; `rm -rf /tmp/x` → "behind the operator's own gate: rm -rf /". `verb()` :359, `load_fence()` :384 (`pat[:-2] if pat.endswith(":*") else pat`), `crosses_fence()` :411 (`startswith`) | yes |
| 9 | recoverable hours from R1–R4 | ~260 h (25%) | monkey-patched `decide()` (below) → **+2 cmds, +12.9 h (1.2%)**; per-segment: fully recoverable **7 cmds / 13.3 h**, partial 214 cmds / 195.8 h | **refuted** |
| 10 | R4 premise "every `rm -rf "$VAR"` is mktemp-assigned in the same command" | asserted | regex over 399 `rm -rf "$VAR"` prompts → **174 (44%)** carry `VAR=$(mktemp…)`; hours 196.2 mktemp vs 167.0 other; `$WT` 0/8, `$NEW` 0/7, `$D` 19/43 | **refuted** |
| 11 | prompt rate doubled | 9.91 → 17.85 /1k | per-day join of bash-commands.log × archive: pre 08-09..19 10.69 (842/78,774 — axis 781 used the 30-d cut) · post 08-21..09-06 **16.99** · post minus 08-21 + 08-24 **11.08** · 08-29..09-08 **7.34** | **refuted** — two days (08-21 inert hook, `a7ec1b5fb` 2026-08-21T02:21-07:00; 08-24 611-prompt burst) |
| 12 | AskUserQuestion prompts | 117 | `jq -r .tool_name \| sort \| uniq -c` → **79**, 20.9 h | no |
| 13 | fast bucket clusters at 02:00/04:00 LA | 170 @04, 108 @02 | `TZ=America/Los_Angeles jq localtime` → 170 @**02**, 108 @**00**, 396 @17, 319 @20; slow flat 13–28/h | qualitatively yes; hours mislabelled by +2 h (machine TZ is −05:00) |
| 14 | auto-mode drop list | 7/339 ×5 | `drop.py` rerun → identical 7 reasons ×5 | yes |
| 15 | `--prune` classifier-denied | row 27 | ledger now 30 rows: 25 "Blocked by classifier", 3 stage-2 error (Bash), 1 stage-2 (Edit), 1 "Classifier unavailable"; the `--prune` row present at 21:52:57Z | yes |
| 16 | cc-permission-audit unscheduled | 0 plists | repo grep: 11 md + 1 hook comment + 5 bats, 0 plists; `~/Library/LaunchAgents` → 0 | yes |
| 17 | `permissions.deny` holds `Bash(rm -rf /)` | cited | `jq .permissions.deny` → also **`Bash(rm -rf /*)`**, `rm -fr /`, `rm -rf ~`, `rm -rf $HOME`, `rm -rf .git` | axis read one of two rm rules |

### The decisive simulation (row 9)

```
spec=importlib.util.spec_from_file_location("sba", ".../hooks/lib/smart-bash-allowlist.py"); m=…
orig=m.allowed_segment
def patched(seg, sole=False):
    r=orig(seg, sole=sole);  if r: return r
    if re.match(r'^mktemp\b', s): return "SIM-R2"                     # GENEROUS: any mktemp form
    if rm -rf "$VAR" and VAR=$(mktemp appears anywhere in cmd: return "SIM-R4"   # GENEROUS: any assignment
    if git -C <path> <rest>: return orig("git "+rest, sole=sole)      # R1
m.allowed_segment=patched ; re-run m.decide(cmd) over the 2,905 Bash prompts
→ BASE allow=157 (3.5 h) · SIM allow=159 (16.4 h) · gained 2 cmds, 12.9 h
  (the 12.9 h is one `git -C … reflog | grep` command blocked 774 min on 09-06)
```

This uses the actuator as the arbiter (memory `make-the-actuator-the-arbiter`) rather than re-implementing its predicate. The
per-segment cross-check agrees: of 2,748 deferred commands, **7** have every failing segment inside {R1,R2,R4}; **214**
(195.8 h) have a fixable segment *and* another that still fails; 133 (87.0 h) cannot be decomposed at all.

## 2. Per-recommendation verdicts

**R1 — skip `git -C <path>` before the subcommand read (axis 93%).** Mechanism confirmed (`verb()` :359 returns `git`;
`allowed_segment` reads `parts[1]` = `-C`). Hours refuted: 78 prompts contain `git -C`; the subcommand mix is worktree 22
(`worktree add` mutates), show 18, rev-list 13, rev-parse 12, **archive 10 / 30.9 h, init 6 / 22.6 h, add 5 / 22.8 h** (all
mutating), log 8, status 7. Through `decide()` the fix gains **2 commands / 12.9 h**. Also (pass 1's caveat, confirmed by code):
`crosses_fence("git -C x push")` is `None` today because the fence tests `startswith("git push")` — the normalisation must run
before the fence test or R1 fixes the allow path and leaves the fence blind. Correct hygiene, ~1% value. **Not refuted as a
defect; refuted as a lever. 75%.** Errs toward allow, bounded to read-only subcommands. S.

**R2 — add `mktemp` to the read-only set (91%).** Mechanism confirmed. Value refuted: 5 commands / 0.3 h clear fully. `READ_ONLY`
(:624) is a bare verb set; `mktemp /etc/x.XXXX` and `mktemp -p <dir>` create caller-named files, so it must be an arg-guarded
branch (`mktemp`, `mktemp -d`, `mktemp -t X`, `mktemp -d -t X` only). **Not refuted as hygiene; refuted as a lever. 65%.** S.

**R3 — split `load_fence()` into prefix and exact (88%). REFUTED.** `~/.claude/settings.json` deny holds `Bash(rm -rf /*)`
beside `Bash(rm -rf /)`. Per matcher-truth `OTo`/`tCs` (:58–66) an unescaped `*` not at `:*` is a **wildcard**, matched by
`ffe` as `^rm -rf /.*$` against each sub-command — so the harness itself denies `rm -rf /tmp/x`; the decider today reaches the
harness's verdict for the wrong reason, and R3 as written would allow a segment the operator's deny list refuses. A faithful fix
is a **three-way** split (prefix / wildcard / exact) and its measured benefit here is zero. Whether a hook `allow` even outranks a
deny rule is contested inside the house (matcher-truth :383–386 "does NOT bypass rules … `Mfr` re-checks"; decider header :39–41
and `smart-bash-allowlist.sh:54–58` "BYPASSES … completely"), and the live experiment is empty: **0** single-command
`rm -rf /tmp/…` submissions in `bash-commands.log` since 08-26 (`grep 'rm -rf /tmp'` → 10 lines, all compound), and the two
archive "rm -rf /tmp" prompts are heredoc-embedded compounds. **20%.**

**R4 — resolve `VAR=$(mktemp -d)` for `rm -rf "$VAR"` (79%). REFUTED on its premise and its value.** 174/399 (44%) of the
`rm -rf "$VAR"` prompts carry a mktemp assignment in the same command (196 of 363 h); `$WT` 0/8 (14.0 h), `$NEW` 0/7 (9.6 h),
`$D` 19/43 are worktree/probe paths. And the mktemp-assigned commands are multi-segment scratch scripts: through `decide()` the
generous R4 clears nothing on its own. Highest-exposure item (a wrong resolution allows `rm -rf` on a non-scratch path) for ~0
measured hours. **20%.** M.

**R5 — persist a proposals file on the supervisor tick (84%).** The tick exists (pid 31716, `--daemon`, plist). But the daemon
does not pick up landed changes: the ladder commit `10348ff6a` (authored 14:45Z, on origin/main and in the shared-checkout HEAD)
is not what pid 31716 runs — daemon start 15:17Z, checkout content changed later, **0** `permission_pending_escalate`, 114/114
markers bare-ts including one at 23:28Z. A new producer inside that daemon inherits the same non-convergence
(memory `registration-precondition-must-assert-version-not-executability`). Second problem: the proposals it would rank are the
compound/pre-gate shapes where the simulation shows a decider widening clears ~1%, so the file would rank work worth ~13 h.
**50%.** Errs toward allow-widenings landing without an operator read (the A08 2026-08-20 lesson). M.

**R6 — do not add `Bash(prefix:*)` rules (90%).** Conclusion holds; the stated reason is wrong. "Unreachable by any allow rule"
is **default-mode** semantics; matcher-truth §3 measured `echo $(/bin/date +%s)` → ALLOW in auto (classifier overrides the
substitution gate), and this fleet runs `defaultMode: auto`. The real reasons: the slow stratum is 69.2% pre-gated and not
rule-shaped; 63 redirect-only-to-`/dev/null` + 229 cwd-relative redirects (pass 1) are reachable by working-dir rules anyway;
today's 11 long blocks were `git checkout --`, `git add`, `git reset --hard`, mktemp compounds. **85%.** Errs toward inert.

**R7 — feed the classifier's prose to `permission-denied.sh` (76%). REFUTED.** The `tool_result` for the axis's own denial
(`toolu_01Vq199QAnwSMeLcBKns7Zha`, `LC_ALL=C grep -a -o 'denied by the Claude Code auto mode classifier.{0,160}'` on the
subagent transcript) reads *"… Reason: Blocked by classifier. If you have other tasks that don't depend on this action, continue
working on those …"*. No category, no prose to harvest on 2.1.260. **10%.**

**R8 — arm `model-permission-decider.py` in shadow (71%).** Premise refuted: it is not "the only lever that reaches the 43.7%" —
the auto-mode classifier already reaches that stratum and disposes of ~84% of prompts in <10 s (rows 5, 13). What blocks for
hours is what the classifier escalates or cannot approve (`classifierApprovable:false`: `&`, protected paths, `rm` at a critical
path, content-scoped ask rules) — and whether a hook `allow` beats those is the unmeasured precedence question above. Shadow mode
is harmless and would answer the approvability question offline, which is its only defensible purpose. **50%.** M.

**R9 — make the producer's read path callable (87%).** Denial confirmed; module import ran. The rename half is a spelling fix
(memory `denylist-enumerates-spellings-not-the-class`: the classifier keys on the action class — a script that walks every
`~/.claude*/settings.json` — not on the flag). The in-process import is the durable form. **80% for the import, 35% for the
rename.** S. Errs toward a callable read path; the `CONFIRM=1` write path is unchanged either way.

## 3. What the axis missed

1. **The escalation ladder is landed, not live** — `permission_pending_escalate` 0 in 5,155 records; 11 sessions sat 5.8–7.9 h with
   one notice each. Pass 1 found this; confirmed here with the later IDL. The fix is a daemon restart and a version assertion on
   the plist's registration, not anything in the axis's list.
2. **Hours-of-commands-containing-a-shape is not hours-recoverable.** The decider is conjunctive over segments; the axis's ~260 h
   headline never asked what else fails in those commands. Measured: 12.9 h.
3. **Auto-mode semantics.** The pre-gate table is default-mode; the classifier overrides the substitution gate in auto (measured
   2026-08-20). The axis's own "84% disposed in seconds" is the same fact and contradicts its "unreachable by any allow rule".
4. **What ended the long blocks:** batch approval 12:57–12:58Z, 10/11 SIG-MATCH — the operator approved them. A loop should start
   from *approved slow prompts*, not from prompt counts or verb hours.
5. **`Bash(rm -rf /*)` wildcard deny** governs the whole rm family analysis (D2/D4, R3/R4).
6. **Hook-`allow` vs deny-rule precedence** is asserted both ways by house documents and measured by neither on 2.1.260; every
   allow-widening's fail direction depends on it. Sample for an empirical read from the bash log: 0.
7. **Prompt-rate doubling is two days**, one of them the hook's own inert day (`a7ec1b5fb`).
8. **170 Bash prompts (5.7%) were cleared by WebSearch**, 45 by Read, 40 by ToolSearch — the model routed around the prompt; a lower
   bound on denials the archive records as resolutions.
9. `78b76e1a8311` is "discharged by §3b" in prose only; the store still reads `open`. `7d5d083cb7b0`, `8365f6c8b37e`,
   `c0e7b1128788` read `blocked`, as stated.
10. Hour-of-day labels are off by +2 h (the box runs −05:00, not Los Angeles); the shape of the argument survives.

## Commands (population in brackets)

- `cat ~/.claude/autonomy/permission-archive/*.jsonl > sk-permarch.jsonl` [3,852]; `jq -c 'select(.ts>=now-30d)'` → sk-perm30 [3,050]
- `jq -r .waited_s sk-perm30.jsonl | awk '{s+=$1}END{print s/3600,NR}'` → 1175.9 h
- `grep 'permission_pending"' ~/.claude/autonomy/idl.jsonl | jq -r '[.sid,.since,.age_s]|@tsv' | awk` → 23 sids / 84.4 h / 49 episodes [5,155]
- `grep -c permission_pending_escalate idl.jsonl` → 0; `for f in pages/*.permpend.notified; do awk '{print NF}'; done | sort | uniq -c` → 114 × 1
- `python3 pregate2.py sk-perm30.jsonl` → 1,273/2,905; on `jq 'select(.waited_s>300)'` → 304/439
- `python3 replay.py` / `replay2.py` / `replay3.py … git|rm` (axis's own scripts) — figures in §1 rows 6–7
- monkey-patched `decide()` simulation — §1 row 9 (inline python, reproduced in full above)
- `rm -rf "$VAR"` × `VAR=$(mktemp` regex over 2,971 Bash rows → 174/399
- `(gzcat bash-commands.log.*.gz; cat bash-commands.log) | grep -o '^\[2026-..-..' | sort | uniq -c` × `jq -r '.ts|strftime("%F")' sk-permarch.jsonl | sort | uniq -c` → per-day rate table; window sums via awk
- `TZ=America/Los_Angeles jq -r 'select(.waited_s<10)|(.ts|localtime|strftime("%H"))' | sort | uniq -c`
- `jq -r '.permissions.deny[]' ~/.claude/settings.json | grep rm` → 9 rm rules incl. `Bash(rm -rf /*)`
- `LC_ALL=C grep -a -o 'denied by the Claude Code auto mode classifier.{0,160}' …/wf_928fd862-9aa/agent-aa4d8ac75d3d33bea.jsonl`
- `jq -r '[.tool,.reason]|@tsv' ~/.claude/logs/permission-denied.jsonl | sort | uniq -c` [30]
- `git log -1 --date=iso-strict 10348ff6a` → 2026-09-08T09:45:42-05:00; `git merge-base --is-ancestor 10348ff6a HEAD` → yes; `ps -o lstart= -p 31716` → 10:17:09
- `cc-backlog list --json | jq '.[]|select(.id==…)'` → 78b76e1a8311 open; 7d5d083cb7b0 / 8365f6c8b37e / c0e7b1128788 blocked
