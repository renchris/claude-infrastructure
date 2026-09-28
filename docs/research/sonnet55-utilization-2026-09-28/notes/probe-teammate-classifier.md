# Probe: teammate-classifier (Sonnet 5.5 as a teammate, gate #7 attribution, auto mode, classifier_model)

Run 2026-09-28 on 2.1.284 (`/Users/chrisren/.claude-284/node_modules/.bin/claude`), account next4 (`~/.claude-quaternary`).
Scratch: `/tmp/s55/probe-teammate-classifier/`. Repo paths are relative to `/Users/chrisren/Development/claude-infrastructure`
(read-only). Spend: **$1.45 list** (MEASURED, sum of `modelUsage[].costUSD` over the 7 probe JSONs).

**Instrument failure, recorded:** the first P1 pair used `CLAUDE_CONFIG_DIR=~/.claude-next4`. That dir exists but is **not logged
in** ("Not logged in · Please run /login", is_error=true). next4 is `~/.claude-quaternary`. The outputs are kept in
`failed-next4-dir/` and every result below comes from the re-run.

## Q1: can a Sonnet 5.5 teammate be spawned under our hooks?

**Policy: no.** In practice it does get through when the hook times out.

Hook logic (`hooks/agent-teams-enforce.sh:534-565`):
- The gate fires only when `TEAMMATE_ID` (`name` or `team_name`) AND `model` are both set.
- The allowlist is `yq .auto_mode_allowlist.non_firstParty_max[]` from `$HOME/.claude/model-config.yaml`, which is a symlink to the repo file (MEASURED `ls -la`). The list is `claude-opus-4-8, claude-opus-5, claude-opus-5-5, claude-fable-5, claude-fable-5-1`, and it has no Sonnet.
- A full id must match an entry exactly. A bare alias passes only if some entry is `claude-<alias>-*`.

MEASURED by running the hook directly: modern `{name, model}` shape with session_id/cwd/transcript_path, and
CC_ADMIT/WCLAIM/LINEAGE gates off with IDL and state redirected to scratch.

| tool_input | decision |
|---|---|
| name + `sonnet` | **deny** ("not on the Max-plan auto-mode allowlist") |
| name + `claude-sonnet-5-5` | **deny** |
| name + `claude-sonnet-5-5[1m]`, `claude-sonnet-5`, `claude-sonnet-4-6` | **deny** |
| name + `opus`, name + `claude-opus-5-5`, name + no model | allow (+ skill pointer) |
| no name + `sonnet` / `claude-sonnet-5-5` | allowed silently (exit 0, no output). The allowlist does not apply to in-process subagents. |

This refutes cc284-workflows.md:32 ("The alias still passes that check"). cc284-teams.md:24 and census.md:86 are right.

**The full id never reaches the hook.** The 2.1.284 Agent tool schema is `model: z(["sonnet","opus","haiku","fable"]).optional()`,
and 2.1.280 has the same enum (MEASURED, python regex over `/tmp/s55/cc28{0,4}.strings`). Live P2 (`model:'claude-sonnet-5-5'`) got
`InputValidationError ... invalid_value ... values [sonnet,opus,haiku,fable]`. p2.debug.log:305 shows `Agent tool input error`,
and no PreToolUse line follows it. The only way to spawn a Sonnet 5.5 teammate through Agent is `model:'sonnet'`.

**The deny fails open on timeout (MEASURED, live P2b).** Setup: an Opus 5.5 lead in auto mode, full user hooks, `Agent({name:'tm-p2b', model:'sonnet'})`.
- p2b.debug.log:306: `Hook PreToolUse:Agent [~/.claude/hooks/agent-teams-enforce.sh] timed out after 5000ms` → `cancelled`.
- The transcript carries `hook_cancelled PreToolUse:Agent`, and the teammate spawned anyway.
- The teammate ran on **claude-sonnet-5-5**: 3 assistant rows in `subagents/agent-a7fd61b703b0118d0.jsonl`, and modelUsage shows claude-sonnet-5-5 at 175 output tokens.
- It wrote `p2b/marker.txt`.

Hook latency: 5 serial runs with every gate live and state/IDL redirected took **2.10–2.95 s** each and returned deny (MEASURED, `time` around `bash hook < in.json`). The timeout in `~/.claude-quaternary/settings.json` is `"timeout": 5`. So headroom is under 2x, and P2b ran alongside two other probes.

Fleet scale, 7 days, 4 accounts: PreToolUse:Agent `hook_cancelled` attachments were 2.1.280: 96, 2.1.260: 14, 2.1.284: 10. `hook_success` attachments were 255, 128 and 2 (MEASURED, python scan of `projects/*/*.jsonl` + `subagents/*.jsonl`). The per-call cancel rate is ESTIMATED at roughly 25-30% on 280, on the assumption of one attachment of each kind per call. Every cancel is a spawn on which the allowlist, brief cap, spawn budget and lineage cap were not enforced.

Untested bypass: an agent definition whose frontmatter pins a Sonnet model, spawned with `name` and no `model`. The hook sees `MODEL` empty and allows the call (read from the code, not probed).

## Q2: gate #7 on Sonnet 5.5: which process ran which model?

`lib/cc-upgrade-gate/check07_teams.sh:17-18` hardcodes the teammate as **`model opus`**, whatever `$GATE_MODEL` is. The check then
asserts only that modelUsage contains `$GATE_MODEL`, and the lead alone satisfies that. So on a Sonnet run, #7 can never test a Sonnet teammate.

Attribution, MEASURED from the gate's own transcripts on account next (`~/.claude-next/projects/-Users-chrisren-Development-claude-infrastructure/`):
- Session `36c79bfd-…` (Sonnet gate, 2.1.284). The **lead** has 4 assistant rows, all `claude-sonnet-5-5`, and it issued `Agent{name:"gate-probe-1", team_name:"gate-probe", model:"opus"}`. The enforce hook ran with `hook_success`, not cancelled.
- **Teammate** `subagents/agent-a90cfeabee5d03f90.jsonl`: meta `{spawnDepth:1, requestNonInteractive:true, model:"opus"}`, with 3 assistant rows, all `claude-opus-5-5`. It ran `echo TEAMMATE_OK` and then SubagentHandback.
- Both run in **one `claude -p` process**. In print mode a named Agent call becomes an in-process subagent under the lead's `subagents/` dir, not a pane or CLI session. This rests on the transcript path and meta; the OS pid was not measured.
- So gate-sonnet55.json #7's `claude-sonnet-5-5` (414 out) is the lead and `claude-opus-5-5` (161 out) is the teammate.
- #7 also never exercises the pane-teammate path (a separate CLI with `--model/--permission-mode` on argv), and its `echo` is read-only, so it never makes the classifier decide anything.

## Q3: does Sonnet 5.5 hold auto mode as a teammate on 2.1.284?

**Yes on every surface probed.** Each result is from a single trial.

| probe | setup | result (MEASURED) |
|---|---|---|
| P1 (proxy for a pane teammate: main loop = Sonnet 5.5) | `-p --model claude-sonnet-5-5 --permission-mode auto`, user settings on | debug: `verifyAutoModeGateAccess: enabledState=enabled … model=claude-sonnet-5-5 modelSupported=true … canEnterAuto=true`. Auto mode stripped the user allow rule `Bash(python3:*)` ("Ignoring dangerous permission … bypasses classifier"). The non-read-only `python3 -c open(...).write` **ran**, permission_denials=[], and the assistant row carries `serverClassifierRequest`. |
| P1neg (control) | same, `--permission-mode default` | Ran too, because the `Bash(python3:*)` allow rule is honored outside auto. **The control does not discriminate**, so it was replaced by P1neg2. |
| P1neg2 (clean control) | default mode, `--setting-sources project,local` (no user allow rules) | **denied**: `permission_denials=[Bash python3 …]`, "This command requires approval", no marker |
| P3b (in-process Sonnet 5.5 teammate, no user hooks) | Opus 5.5 lead `--permission-mode auto --setting-sources project,local`, `Agent({name:'tm-p3b', model:'sonnet'})` | The teammate ran **claude-sonnet-5-5** (3 rows). Its Bash write **ran** under auto with 3 `serverClassifierRequest` rows, and the marker was written. The lead is `claude-opus-5-5`. |
| P2b (same, full hooks) | as above with user settings | same outcome: sonnet-5-5 teammate, write approved, marker written (see Q1: the hook was cancelled) |

Why this holds, from the binary: the 284 client gate is `Q9e(model)`. It returns false only for models at or below `claude-opus-4-6` in its ordering list, or, off firstParty, for `opus-4-6`, `sonnet-4-6` or `haiku`. It keeps no Max-plan allowlist (MEASURED, cc284.strings @14993994). On firstParty, `claude-sonnet-5-5` is therefore supported. The "STRICTER non_firstParty_max" list in the SSOT is our own policy, not a client check.

**Recommendation:** the evidence supports appending `claude-sonnet-5-5` to `non_firstParty_max`. It is the same class of evidence that admitted fable-5-1 and opus-5-5: a mechanical auto-mode tool turn with no denials. Conviction ~80%. What is not covered:
- a real **pane** teammate (interactive, it2-kitty) was not spawned. P1 is its proxy for the auto-mode gate;
- there was n=1 per arm;
- the approving classifier was server-side, so its behaviour on harder commands is untested.

## Q4: `classifier_model: claude-sonnet-4-6`: who reads it, and is it still meaningful on 2.1.284?

**Readers:** none. `git grep classifier_model` hits only `model-config.yaml:808`, and `roles.classifier` (:1005) is read by nothing
under bin/ scripts/ hooks/ lib/ tests/ (MEASURED). census.md:13 says the same. It is a descriptive mirror and nothing depends on it.

**It is stale on both 2.1.280 and 2.1.284.** Client-side selection is the same function in both builds (284 `QDe`, 280 `eRe`; MEASURED cc28{0,4}.strings):
1. First, the server config `tengu_auto_mode_config.modelByMainModel` / `.model` wins if set. In the cached GrowthBook payload both are **null** on next and next4 (MEASURED, `.claude.json cachedGrowthBookFeatures`).
2. Next, unless the probe has been demoted, it uses the "external default" `Hx(mainModel)`. This returns nothing when the main model is `claude-sonnet-4-6`, `claude-sonnet-4-5` or `haiku-*`. Otherwise it returns `ANTHROPIC_DEFAULT_SONNET_MODEL`, or the catalog key **`sonnet5` = `claude-sonnet-5`**. The debug string is "Got error trying Sonnet 5 as auto mode classifier".
3. Last, it falls back to the main loop model (Fable mains fall back to the default Opus).

So on the client path an Opus 5.5 or Sonnet 5.5 session is classified by **claude-sonnet-5**. `claude-sonnet-4-6` is never chosen. It appears in this function only as an *exclusion*.

**The client path is usually not what runs.** Auto-mode sessions in the last 6 h whose transcripts carry `serverClassifierRequest`: 2.1.284 39 of 43, 2.1.280 25 of 92 (MEASURED, python scan across 4 accounts). A session with no such row may simply have had no classifier-gated call. All P1/P2b/P3b approvals were server-side. On that path Anthropic picks the classifier model and the client cannot see it. This refutes cc284-workflows.md:62 and cc284-hooks.md:59,67 ("we run the local classifier path").

The line should be rewritten as "client-path default = catalog sonnet5 (claude-sonnet-5); server path = opaque". It should be marked non-load-bearing, or deleted.

## Artifacts
- Probe scripts, JSONs and debug logs: `/tmp/s55/probe-teammate-classifier/{run1,run_p2,run_p3,run_p2b,run_p3b,run_p1neg2}.sh`, `{p1,p1neg,p1neg2,p2,p3,p2b,p3b}.{json,debug.log}`
- Hook timing: `/tmp/s55/probe-teammate-classifier/timing/`
- Transcripts: `~/.claude-quaternary/projects/-private-tmp-s55-probe-teammate-classifier-{p1,p2b,p3b}/`; gate #7: `~/.claude-next/projects/-Users-chrisren-Development-claude-infrastructure/36c79bfd-7241-4fcf-a42f-ae80c26089cc{.jsonl,/subagents/}`

## Skeptic

Reviewed 2026-09-28 by re-reading every cited artifact. I re-ran two checks: the hook, directly (free), and one API probe (P1clean, $0.0327 list, MEASURED from `p1clean.json total_cost_usd`). Scratch: `/tmp/s55/probe-skeptic-tc/` (`run_hook.sh`, `run_p1clean.sh`, `p1clean.{json,debug.log}`) and the scans `/tmp/s55/probe-skeptic-tc-scan{,2,3}.py`. Every probe debug log shows `cc_version=2.1.284`, so the build is the one claimed.

**Upheld**
- **Spend $1.45.** Recomputed $1.4543 by summing `modelUsage[].costUSD` over the 7 JSONs (MEASURED). The next4-dir failure is real: `failed-next4-dir/p1.json` has is_error=true, "Not logged in", and $0.
- **Q1 hook table.** Reproduced exactly (MEASURED, `run_hook.sh`, gates off, IDL/state redirected):
  - `name` with any of `sonnet`, `claude-sonnet-5-5`, `claude-sonnet-5-5[1m]`, `claude-sonnet-5` or `claude-sonnet-4-6` → deny;
  - `name` with `opus`, `claude-opus-5-5` or no model → allow;
  - no `name` with `sonnet` or `claude-sonnet-5-5` → exit 0 and no output.
- **The full id never reaches the hook.** The enum is `["sonnet","opus","haiku","fable"]` at cc284.strings @26876713 and cc280.strings @25473981 (MEASURED). The P2 transcript row 34 is an InputValidationError, and no PreToolUse hook produced output for that call.
- **The deny fails open on timeout.**
  - The P2b debug log line 306 and the transcript `hook_cancelled` attachment (`timedOut:true`, 5072 ms) both check out. The Agent call was dispatched 4 ms later with `permissionDecisionMs=2`.
  - I extended this to the fleet and the live pin: all 120 PreToolUse:Agent `hook_cancelled` calls in 7 days (2.1.280: 96, 2.1.260: 14, 2.1.284: 10) got a non-error tool_result, and 118 of them carry spawn text (MEASURED, `probe-skeptic-tc-scan3.py`).
- **Latency with under 2x headroom.**
  - The original 2.10–2.95 s figures are saved in no artifact. Only `out*.json` and IDL timestamps at 1 s resolution survive, and those timestamps are 2–3 s apart, which is consistent.
  - My re-run of 5 serial calls with gates live and state redirected took 3.56, 1.87, 2.10, 1.92 and 1.95 s (range 1.87–3.56 s), all deny (MEASURED, python wall clock around `bash hook < in.json`).
  - `"timeout": 5` is set for this hook in all 5 settings.json files: `~/.claude` and the 4 accounts (MEASURED).
  - A live call in gate session 36c79bfd took 3012 ms (MEASURED, `hook_success.durationMs`).
- **Fleet attachment counts.** 96/14/10 cancelled and 255/128/2 success reproduce exactly (MEASURED, `probe-skeptic-tc-scan2.py`).
- **Q2: check07 hardcodes `model opus`.** Confirmed at `check07_teams.sh:17`.
- **Q2 attribution.**
  - The lead's 4 rows are all `claude-sonnet-5-5`, and their usage sums to exactly 414 output tokens (MEASURED).
  - The teammate's 3 rows are all `claude-opus-5-5`, with meta `model:"opus"`.
  - One mismatch: the teammate transcript usage sums to 52 tokens against 161 in modelUsage. P2b and P3b show the same gap (45 vs 175) even though the count of sonnet dispatches equals the row count (3). So this is transcript under-recording of the subagent's usage, not a third actor (inference).
- **Q2: the echo never exercises the classifier.** This is stronger than stated. The teammate's `echo` was approved by a user PreToolUse:Bash hook ("echo: read-only, no redirect"), so no classifier path ran at all.
- **Q3 P1 (pane proxy).** Upheld, now with a clean control.
  - The original P1 had user settings and hooks on, while its "clean control" P1neg2 had them off. P1neg2 was therefore not paired with P1.
  - **P1clean** changes only the mode: Sonnet 5.5 main loop, `--permission-mode auto --setting-sources project,local`, 0 hooks in the registry. Result: `modelSupported=true canEnterAuto=true`, permission suggestions and then dispatch after 1527 ms, marker `P1CLEAN` written, denials `[]` (MEASURED).
  - P1clean vs P1neg2 is now a discriminating pair.
- **Q3 P3b and P2b.** Upheld. P3b has 0 hooks, the teammate ran `claude-sonnet-5-5`, and the marker was written.
- **Server-side approval.** No `claude-sonnet-5` dispatch appears in the p1, p2b, p3b or p1clean debug logs, and no `claude-sonnet-5` appears in modelUsage (MEASURED, grep). The client classifier did not run. That the server approved the call is an inference.
- **Q4 readers: none.** Confirmed (MEASURED, `git grep classifier_model`, and no `roles.classifier` reader under bin/, scripts/, hooks/, lib/ or tests/).
- **Q4 client selection.** `QDe`/`eRe` → `rUr`/`p_r` → `Hx`/`PF` with the sonnet-4-6/4-5/haiku exclusion checks out, and the catalog maps `"claude-sonnet-5":"sonnet5"`. `tengu_auto_mode_config.model` and `.modelByMainModel` are absent on all 4 accounts, not only next and next4 (MEASURED).
- **Labelled inferences** (the frontmatter bypass and "one process") are correctly labelled.

**Refuted or unsupported**
- **Evidential weight of `serverClassifierRequest`.** The field is on every assistant row in auto mode, including text-only "DONE" rows (P1, P3b, P1clean), and is absent in default mode. It marks that a server classification was *requested*, not that a decision was made. So "3 `serverClassifierRequest` rows" in P3b means 3 assistant rows, not 3 approvals. The decisive evidence is the marker contrast with P1neg2.
- **Q9e wording.** "At or below `claude-opus-4-6`" is wrong. `$n()` returns true for `claude-3-*` or for models strictly *before* `claude-opus-4-6` in the ordering list, so opus-4-6 passes on firstParty. The conclusion that sonnet-5-5 is supported is unaffected, and the debug line measures it directly.
- **Per-call cancel rate "~25-30%".** Overstated. 2.1.280 had 470 Agent tool_use calls in the window (MEASURED, scan2), so the cancels are **20.4% of all calls**. The 27.4% figure holds only for calls that produced an enforce attachment. Report 20–27%.
- **"The client path is usually not what runs."** True on 2.1.284 (74 of 78 auto sessions in 6 h), false on the live pin by session count.
  - On 2.1.280, 31 of 98 auto sessions carry the field. 64 of the 89 sessions with at least one tool_use have **zero** rows with it (MEASURED, `probe-skeptic-tc-scan.py`, run about 15:17). One example is a 2.1.280 sdk-cli auto session with 3 Bash calls and no field.
  - The hedge "may simply have had no classifier-gated call" is refuted, because the field is written per request, not per decision. When it is absent, the binary's `xSt`/`Npt` returns `server_not_requested`.
  - By assistant rows, 4340 of 4942 (88%) on 280 do carry the field, so the large sessions are on the server path.
  - Net effect: the refutation of cc284-workflows.md:62 and cc284-hooks.md:59,67 is too broad. For most 2.1.280 auto sessions the client path, which picks `claude-sonnet-5`, is live. That makes the stale `classifier_model` line more worth fixing, not less.
- **Recommendation to append `claude-sonnet-5-5`: unsupported as scoped.**
  - Because of the enum, the hook only ever sees the alias `sonnet`. An entry of `claude-sonnet-5-5` satisfies `claude-sonnet-*`, so it admits `model:'sonnet'` on **every** build.
  - On the live pin 2.1.280, and on 2.1.260 which is still in the fleet, `sonnet` resolves to `claude-sonnet-5` (cc280.strings @17525637). That is a model no probe here exercised.
  - Before appending, gate the entry on build ≥ 2.1.284, or add a 2.1.280 `sonnet`-teammate auto probe.
