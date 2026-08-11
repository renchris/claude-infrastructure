# W2 run conditions — how these outputs were produced

**Produced:** 2026-08-11 · **Plan:** `docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md` § W2
**Contents:** `<brief_id>__<arm>.md` = one arm's verbatim output for one brief · `index.json` = one
record per run.

W2's job was to **produce outputs, not to judge them**. Nothing here is scored, ranked, or compared;
the runner deliberately did not read the outputs it collected, because a runner that peeks becomes an
unblinded judge. Everything below is about the *conditions*, which W3 needs in order to read the
outputs correctly.

## The arms

| Arm | Model | Effort | Provider | Role |
|---|---|---|---|---|
| A | `claude-fable-5` | `xhigh` | anthropic | incumbent — what `roles.research_adversarial` holds today |
| B | `gpt-5.6-sol` | `xhigh` | openai-codex | candidate at the pinned Codex default |
| C | `gpt-5.6-sol` | `ultra` (**unverified — see below**) | openai-codex | candidate at max reasoning |
| D | `claude-opus-5` | `max` | anthropic | cost anchor — the fallback when the frontier window is off |

**Arm A's effort was read from disk, not chosen.** `model-config.yaml` sets
`roles.research_adversarial: claude-fable-5`, and `effort_defaults.verify_judge: xhigh` names this
exact slot — *"the workflow_judge / eval_judge / research_adversarial slots use xhigh whether on
Fable (in-window) or Opus-fallback (window shut)"*. Arm D's `max` is the plan's own specification.

## Isolation — what is proven, and what is only measured

The corpus pins sibling mechanisms inert on the assumption that an arm sees the brief and nothing
else. That assumption is enforced differently per vendor, and the difference matters:

**Claude arms (A, D) — hard-denied.** Run as `claude -p --tools "" --setting-sources ""
--strict-mcp-config --no-session-persistence`, cwd = a scratch directory containing only `brief.md`.

- `--tools ""` removes the tools rather than forbidding them. Control probe: a model explicitly
  asked to `Read` the real `manifest.json` emitted a *fabricated* tool-call block and *invented* file
  contents (`"name": "codex-probe"`, `"version": "0.1.0"` — the real manifest is a 9-record list of
  brief metadata). There was no tool to call. **A model's self-report about its own tools is not
  evidence in either direction** — it also hallucinated having `Read, Edit, Write, Glob, Grep` when
  asked cold.
- Every arm-A/arm-D record carries `num_turns` in its note. `num_turns=1` means one model turn and
  therefore zero tool round-trips — the mechanical control, per run.
- `--setting-sources ""` plus a scratch cwd loads **no `CLAUDE.md`, no `MEMORY.md`, no hooks**
  (verified by diagnostic: `NONE` for both). This is load-bearing rather than tidy: this repo's own
  `MEMORY.md` index states cp-01's ground truth in a single line (*"Denylist = examples — `-rf` let
  11/13 past…"*). A Claude arm run with project memory loaded would be void.

**Codex arms (B, C) — NOT denied; measured instead.** `codex exec -s read-only` denies *writes*
everywhere and permits *reads of the entire filesystem* (`permission_profile.file_system:
{restricted, root:read}`). So the brief's "use no resource other than this brief" is an instruction,
not a control, and a Codex arm that chose to look could have read the subject file, its test suite
and its fix commit.

The substitute is a per-run measurement harvested from each run's own persisted rollout under
`~/.codex/sessions/`: `tool_calls_observed` counts `exec_command` / `function_call` /
`local_shell_call` / `apply_patch` / search items, and `isolation_verified` is `true` only when that
count is zero.

**Result: all 18 Codex runs made zero tool calls** (`isolation_verified: true`, 18/18) — only
reasoning and message items appear in any rollout. No Codex arm read anything. Note what this is:
evidence that none of them *did*, not a guarantee that none of them *could*. It is a weaker
guarantee than the Claude arms have, and W3 should treat it as such.

The Anthropic-side equivalent is `num_turns=1` in every arm-A/arm-D note (18/18) — one model turn,
therefore zero tool round-trips.

## Arm C's identity — RESOLVED by measurement: `ultra` is not a silent alias of `xhigh`

`ultra` is **absent from the API's reasoning-effort enum**. A deliberately bogus value returns
`400 invalid_request_error … Supported values are: 'none', 'minimal', 'low', 'medium', 'high',
'xhigh', and 'max'`. Yet `ultra` completes without error, and the rollout's `turn_context` records
`effort: ultra` verbatim — which proves the value was **passed**, never that it was **honoured**.

If `ultra` is silently coerced (most plausibly to `xhigh`, the config default), **arm C is a
duplicate of arm B**, and any "C beats B" or "C ties B" reading in W3 is an artifact of the same
config run twice. That is precisely the landmine class this corpus exists to catch: a flag accepted,
ignored, and reported back as if honoured.

The discriminator was a **paired reasoning-token comparison against arm B on the same brief**,
across all 9 briefs — a coerced `ultra` would track `xhigh`'s distribution. It does not:

| | cp-01 | cp-02 | cp-03 | cp-04 | cp-05 | cp-06 | cp-07 | cp-08 | cp-09 |
|---|---|---|---|---|---|---|---|---|---|
| B `xhigh` | 17,692 | 20,840 | 17,610 | 22,777 | 19,682 | 24,862 | 12,694 | 30,560 | 27,100 |
| C `ultra` | 57,422 | 41,812 | 14,502 | 47,555 | 33,668 | 60,086 | 22,790 | 11,912 | 50,978 |

**C > B on 7 of 9 briefs, 1.76× in sum** (`arm_c_identity_evidence` in every arm-C record).
Supporting wall-clock signal on cp-01: arm B 12 min, arm C 24 min. So arm C is a genuinely distinct
configuration and W3 may compare it against B as two different tiers — **the "C is a duplicate of B"
artifact is ruled out.**

What remains open is narrower, and W3 should not overclaim past it: `ultra` is still absent from the
documented enum, so **its relation to the enum's `max` is unestablished**. Arm C is "more reasoning
than `xhigh`", measured — not "the maximum the model offers", which was the plan's stated intent.
The two briefs where C < B (cp-03, cp-08) are unexplained and left as-is.

*(Credit: this and the Codex-sandbox finding were raised by a second W2 session that ran preflight
checks and stood down without running the grid — `/private/tmp/rvw/W2-preflight-findings.md`.)*

## Consumption

`codex_used_percent_before` / `_after` come from `rate_limits.primary.used_percent` in the newest
rollout, read immediately before and after each Codex run. **It is the only consumption signal
either vendor exposes** — neither reports tokens or dollars — so W3's cost comparison is
**DIRECTIONAL only**. Its granularity is coarse: whole percentage points against a weekly bucket, so
a single run usually moves it by 0 and only the cumulative drift is legible. Baseline at grid start
was **22.0%** (weekly bucket, resets 2026-08-17). Per-run token counts harvested from the rollouts
(`input_tokens`, `output_tokens`, `reasoning_output_tokens`) are a finer-grained substitute for the
Codex arms and have no Anthropic-side equivalent here.

## Known limitations — read these before drawing conclusions

0. **Completion: 36/36 runs, all `ok:true`.** No arm was dropped, substituted, or missing from any
   brief. Codex weekly `used_percent` moved **22.0 → 27.0** across the 18 Codex runs.

1. **Two records are RECONSTRUCTED, and say so in their `note`** (`cp-01__C`, `cp-02__C`). The orchestrating shell process
   was killed three times mid-grid by something on this machine that was never identified (its own
   grandchild `codex exec` survived each time and kept working). Where a run's output reached disk
   but its record did not, the record was rebuilt from disk truth — rollout filename for
   `started_at`, output-file mtime for `ended_at` — and the **output itself is the untouched file the
   run wrote**. No output in this directory was edited, regenerated, or summarised. Affected records
   carry `SALVAGED` or `RECONSTRUCTED` in `note`; their timestamps are approximate, their content is
   not.
2. **The scratch path names the repo.** Each run's cwd was
   `…/-Users-chrisren-Development--worktrees-probe-grid/…/grid/<brief>__<arm>/`, and cwd appears in
   the Claude system prompt. That leaks the *repository name and the arm label* — never any defect,
   ground truth, or corpus content. It was left unchanged mid-grid deliberately: cp-01 had already
   run under it, and splitting the corpus into two different conditions is a worse confound than one
   weak, uniform hint.
3. **Corpus bias, inherited from W1.** Briefs are drawn from defects a Claude-family model already
   missed once. The plan states this tilt (§ Known risks 2); the verdict must state it too.
4. **`ok:false` runs are real data, not gaps.** A refusal or an error is a genuine result about an
   arm in this slot and is recorded verbatim rather than retried into a clean number. Per the plan, a
   failing run is retried at most once; record fragments were snapshotted before each retry so a
   retry cannot erase the first attempt.
