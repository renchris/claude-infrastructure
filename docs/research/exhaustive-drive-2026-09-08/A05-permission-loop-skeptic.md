# A05 — Permission loop: SKEPTIC pass

**Wave:** exhaustive-drive 2026-09-08 · **Axis under review:** A05-permission-loop · **Mode:** read-only, refute by default.
Every number below is **measured** in this pass unless marked *inferred*. Scratch: `<scratchpad>/a05skep/` (perm30.jsonl rebuilt at
cutoff 2026-08-09T22:12Z, 3,053 rows / 460 sessions / 2,974 Bash + 79 AskUserQuestion — the axis's 3,046 / 455 / 2,905 was ~30 min earlier;
its "117 AskUserQuestion" does not reproduce: `jq -r .tool_name | sort | uniq -c` → 79).

## Verdict in one paragraph

The **cost** half of the report survives and is if anything understated; the **mechanism** half has three load-bearing errors.
(1) The "2026-08-20 fix doubled the prompt rate" is an artefact of two days: 08-21, when the rewritten hook was **inert** for a full day
(commit `a7ec1b5fb`: "the live layer ran an inert hook … deferred EVERY command"), and 08-24, one session's 611-prompt scraping burst.
With those two days out the post-fix rate is 11.08/1k against 9.72 pre-fix, and the **last 11 days run at 7.66/1k — below pre-fix**.
(2) R3 (split `load_fence` so `Bash(rm -rf /)` stops fencing `rm -rf /tmp/x`) is refuted by the operator's own deny list: it also holds
`Bash(rm -rf /*)`, which the harness parses as a **wildcard** (`^rm -rf /.*$`, matcher-truth §parser) and which fences every absolute-path
`rm -rf` on the box. The decider today reaches the harness's verdict for the wrong reason; R3 as written would make it reach the *wrong*
verdict for the right reason and auto-allow what the harness denies. (3) R7's premise — "the classifier's prose exists on the `is_error`
channel" — is false on 2.1.260: the denied `--prune` call's `tool_result` reads *"Reason: Blocked by classifier."*, the same category-free
string the hook already logs. What the axis **missed** is the one silent-in-the-dangerous-state defect in its own domain: the escalation
ladder it cites at `lead-supervisor.sh:571` produced **0** `permission_pending_escalate` records today while 11 sessions sat 5.7–7.8 h each
(all 23 notice markers written today carry a bare ts and no rung), because the running daemon (pid 31716, started 15:17Z) predates the file
content that carries the ladder (mtime 19:03Z). Landed on trunk, not live.

## 1. Re-measurements of the axis's key numbers

| claim | axis | rechecked | holds |
|---|---|---|---|
| 30-d prompts / hours | 3,046 / 1,172.5 h | 3,053 / 1,175.4 h (`jq -r .waited_s … awk`) | yes |
| sessions blocked today (IDL) | 22 sids / 83.8 h, per-sid max | 23 sids / 84.4 h per-sid max; **43 episodes / 93.1 h** per-(sid,since) max — the axis's per-sid max undercounts multi-episode sids | yes, understated |
| were they really idle? | asserted | transcript entries inside each episode window (`jq … select($t>since+60 and $t<since+max-60)`): **0 assistant/user entries in all 43 episodes**; only `attachment`/`queue-operation` (peer mail) in 5 | yes — genuinely blocked |
| what ended the 11 long blocks | not asked | archive rows `waited_s>10000` on 09-08: all 11 resolved 12:57–12:58Z, **10/11 `SIG-MATCH`** (the prompted invocation ran) — one batch approval after 6–8 h | new fact |
| waited_s attribution | 50/56 = 89% | 53+10 rows carry `tool_sig`; not re-derived (sub-sample too small to move anything) | *inferred* |
| pre-gate share | 1,270/2,905 = 43.7% | 1,276/2,911 = 43.8% via the axis's own `pregate2.py` — **but** redirect-only commands split: 63 to `/dev/null` (exempt per matcher-truth §"Output redirection") + 229 to cwd-relative files (checked as a working-dir write, not hard-gated) + 24 heredoc-only (heredoc is in **no** hard-gate list in the source doc). Defensible floor ≈ **960/2,911 = 33%** | overstated |
| live decider clearance | 157 ALLOW / 5.4% | 157/2,911 reproduced — **154 of the 157 fall on or before 08-28; 3 after**. The population is prompts that occurred *despite* the live hook, so 5.4% measures history, not headroom; the current decider is already at its ceiling on the current corpus | mis-framed |
| prompt rate pre/post | 9.91 → 17.85 /1k | 9.72 → 16.99 raw; **11.08 excluding 08-21 (inert hook) + 08-24 (burst); 7.66 over 08-29..09-08** | refuted |
| auto-mode drop list | 7/339 per file, 35 fleet | `drop.py` rerun: 5 × 7 identical reasons | yes |
| `--prune` classifier-denied | row 27 @21:52:57Z | present; ledger now 30 rows (25 "Blocked by classifier", 3 stage-2 error, 1 Edit, 1 "Classifier unavailable") | yes |
| D1–D4 probes | as stated | reproduced on the live module: `git -C … log` → defer "segment not on the allowlist"; `mktemp -d` → defer; `rm -rf "$T"` → defer; `rm -rf /tmp/x` → "behind the operator's own gate: rm -rf /". `verb()` is `^([A-Za-z0-9_.\-/]+)` and `allowed_segment` takes `sub = parts[1]` (:906) — `-C` really is read as the subcommand | yes |
| cc-permission-audit refs | 7 docs + 1 hook, 0 plists | 9 docs + 1 hook + 5 bats, 0 plists, 0 LaunchAgents; bash-log invocations 119 (axis: ~40) | yes in substance |
| hook wall time (5 s timeout) | not measured | live shim, load avg **175**: 0.09–0.10 s × 5 — timeouts are not why prompts leak | new |
| escalation "one every 9 s" | 5,117 IDL records | 5,136 — but that is `idl permission_pending`, written on **every 30 s sweep per blocked session** (`SWEEP=30`, ~11 concurrent). Pages are fingerprint-damped; 23 `.permpend.notified` markers today = 23 notices. The "alarm that cannot be read" is a ledger cadence, not an alarm | refuted as framed |
| `AskUserQuestion` price (open q.) | unpriced | 79 prompts, **20.9 h** | new |

## 2. Per-recommendation verdicts

**R1 — skip `git -C <path>` in `verb()`/subcommand read (93%).** Mechanism confirmed at `allowed_segment` (`sub = parts[1]`). Not refuted.
Fail direction: allow, bounded to `GIT_READ ∩ GIT_SUBCOMMAND_READ_ONLY` guards. One caveat the axis did not state: today `git -C x push` does
**not** cross the fence either (`crosses_fence` tests `startswith("git push")`), so the normalisation must run *before* the fence test, or R1
will fix the allow path and leave the fence path blind. Adjusted 90%.

**R2 — add `mktemp` to the read-only set (91%).** `READ_ONLY` is a bare **verb set**; adding the verb admits `mktemp /etc/x.XXXX` and
`mktemp -p <anywhere>`, which create files at caller-named paths. The axis's "mutates nothing a caller names" is true only for the bare/`-d`/`-t`
forms. Not refuted, but must be an arg-guarded branch, not a set entry. Adjusted 80%. Fail direction: allow.

**R3 — split `load_fence()` into prefix and exact (88%). REFUTED.** `~/.claude/settings.json` deny holds both `Bash(rm -rf /)` (exact) **and**
`Bash(rm -rf /*)`. Per matcher-truth `OTo`/`ALs`: a rule with an unescaped `*` not at `:*` is a wildcard, matched as `^rm -rf /.*$` on each
sub-command. So the harness itself denies `rm -rf /tmp/x`; R3 would have the decider **allow** a segment the operator's deny list refuses —
and a PreToolUse `allow` "bypasses the permission system completely" (decider header, measured 2.1.220). The promised ~/tmp recovery does not
exist without an operator decision to retarget `Bash(rm -rf /*)`. Implementing the three-way split (prefix/wildcard/exact) faithfully is still
correct hygiene, but its measured benefit here is zero. 25%.

**R4 — resolve `VAR=$(mktemp -d)` for `rm -rf "$VAR"` (79%).** Numbers not re-derived (the ~180 h family is plausible from the archive
shapes). Highest exposure item; the axis's gate is right. Note the same `Bash(rm -rf /*)` wildcard applies: a resolved `/private/tmp/...`
target is still under the harness's deny — the only reason `rm-safe-allowlist.sh` gets away with allowing it standing alone is that a hook
`allow` outranks a deny rule, which nobody has measured against deny rules specifically. Adjusted 60%, blocked on that measurement.

**R5 — persist a proposals file on the supervisor tick (84%).** The supervisor is a real 30 s daemon (plist + pid 31716) so the tick exists.
But this pass shows the ladder that *already* lives in that file is not running (§3). Putting a new producer into a daemon that does not
pick up its own landed changes builds on the same non-convergence. Also memory `sweep-hosted-actuator-cannot-exceed-its-tick`: a
2,911-row replay costs 13 s in-process; fine, but bats-per-widening is the real gate and is not schedulable from a tick. Adjusted 60%.

**R6 — do NOT add `Bash(prefix:*)` rules (90%).** The two ceilings are real but smaller than stated (33% not 43.7%; 2.1% drop list).
The conclusion still holds on the hour-weighted residual: the 11 long blocks today were `git checkout --`, `git add`, `git reset --hard`,
`rm -rf` scratch, `$(mktemp -d)` compounds — none rule-shaped. Not refuted; 85%. Fail direction: inert.

**R7 — feed the classifier prose to `permission-denied.sh` (76%). REFUTED.** Measured on the very denial the axis cites: the subagent
transcript's `tool_result` for `toolu_01Vq199QAnwSMeLcBKns7Zha` is `is_error:true` with text *"Permission for this action was denied by the
Claude Code auto mode classifier. Reason: Blocked by classifier. …"* — no soft-deny category anywhere. There is no prose to harvest on 2.1.260. 10%.

**R8 — arm `model-permission-decider.py` in shadow (71%).** Shadow errs to zero effect, so not harmful; but the axis's own precondition
(does hook `ask` reach the human under auto on 2.1.260) is unmeasured, and the R3/R4 finding adds a second: does hook `allow` outrank a
**deny** rule (the 2.1.220 measurement was against the working-dir write guard). Two unmeasured preconditions ⇒ 55%.

**R9 — make the producer's read path callable (87%).** Denial confirmed (row at 21:52:57Z); plain report form ran. Not refuted; 85%. Fail
direction: read path callable, write path unchanged — but note the classifier keys on argv shape, so a renamed flag is a spelling fix
(memory `denylist-enumerates-spellings-not-the-class`); the module import is the durable form.

## 3. What the axis missed

1. **The escalation ladder is not live.** `permission_pending_escalate` IDL records today: **0**. All 23 `~/.claude/autonomy/pages/*.permpend.notified`
   written today hold a bare ts (0 of 23 carry a rung field). The ladder landed as `10348ff6a` (on origin/main, in the shared checkout HEAD),
   the daemon started 15:17Z, the file's content changed at 19:03Z; bash does not re-read parsed functions. Eleven sessions sat 5.7–7.8 h
   with exactly one notice each and no escalation. This is the silent-in-the-dangerous-state defect this wave exists to find, in the axis's own
   citation (`lead-supervisor.sh:571`). Fix is a daemon restart (`launchctl kickstart -k`), then re-check the IDL for `_escalate`.
2. **Approval, not denial, is what ended the long blocks** — 10/11 `SIG-MATCH` in one batch at 12:57Z. The cost is operator-absence latency
   on commands the operator then approved. The loop the goal asks for ("move prompts to the allowlist") should start from *these 11 rows*
   (they are the hours), not from prompt counts; the axis ranked by hours per verb but never looked at what the operator actually approved.
3. **`Bash(rm -rf /*)` is a wildcard deny** covering every absolute `rm -rf`; the whole rm family analysis (D2/D4, R3/R4) is downstream of an
   operator rule the axis did not read.
4. **Hook-`allow` vs deny-rule precedence is unmeasured.** The decider header measured `allow` against the working-dir guard on 2.1.220.
   `rm-safe-allowlist.sh` allowing `/tmp` targets under a `Bash(rm -rf /*)` deny is the live experiment; nobody has read its outcome.
5. **The 08-21 inert-hook day** (`a7ec1b5fb`) sits inside the axis's "post-fix" window and is the single largest contributor to the doubling.
6. **347/2,974 Bash prompts (11.7%) were cleared by a non-Bash tool** (`cleared_tool` ∈ WebSearch 170, Read 45, …) — the model routed around
   the prompt. A lower bound on denials/route-arounds the axis's "approved 50 / denied 10" from `cc-permission-audit` cannot see.
7. Redirect-target class matters for the pre-gate claim (63 `/dev/null`-only, 229 cwd-relative-only, 65 h) — reachable by rules/working-dir.
8. IDL record cadence was reported as alarm volume (memory `alarm-polarity-and-attention-budget` is about *pages*, and pages were 23).

## Commands (population in brackets)

- `cat ~/.claude/autonomy/permission-archive/*.jsonl | jq -c --argjson c $(( $(date +%s)-30*86400 )) 'select(.ts>=$c)'` → perm30.jsonl [3,053]
- `jq -r '[.sid,.since,.age_s]|@tsv' pp.jsonl | awk …` per-(sid,since) max → 43 episodes / 93.1 h [IDL 5,136 records]
- `tx2.sh`: per-episode `jq 'select(($t>since+60) and ($t<since+max-60))|.type'` over the four transcript roots [43 episodes]
- `jq 'select(.waited_s>10000 and .ts>=1788825600)'` → 11 rows, resolved 12:57–12:58Z, 10 SIG-MATCH
- `python3 redir.py` (redirect target classes) · `python3 replay.py` (decide() over 2,911; ALLOW by date) · `python3 probe.py` (D1–D4 + source)
- `join calls.txt prompts.txt | awk` windows: pre 762/78,400; post 2,084/122,635; post−{08-21,08-24} 1,103/99,580; 08-29..09-08 489/63,803
- `jq -r '.permissions | .deny[]|select(startswith("Bash"))' ~/.claude/settings.json` → `Bash(rm -rf /*)` present
- `grep toolu_01Vq199QAnwSMeLcBKns7Zha …/subagents/workflows/wf_928fd862-9aa/agent-aa4d8ac75d3d33bea.jsonl | jq '.message.content[]|select(.type=="tool_result")'`
- `grep -c permission_pending_escalate ~/.claude/autonomy/idl.jsonl` → 0 · `find pages -name '*.permpend.notified' -newermt 2026-09-08 | xargs awk 'NF>=2'` → 0/23
- `ps -axo pid,lstart,command | grep lead-supervisor` → pid 31716 started 10:17 CDT; `stat` shared-checkout file mtime 14:03 CDT
- shim timing: `printf "$P" | ~/.claude/hooks/smart-bash-allowlist.sh` ×5 at load 175 → 0.09–0.10 s
