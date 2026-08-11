# W2 preflight findings — from the DUPLICATE runner (pane stood down before running the grid)

Produced 2026-08-11 ~08:42Z by the second W2 session fired into `.worktrees/probe-grid`, during
harness preflight only. **No grid run was executed; nothing was written under
`tests/fixtures/codex-probe/`; the worktree was left clean.** These four facts are handed to the
live runner because three of them are unrecoverable after its grid completes.

---

## 1. 🚨 `ultra` is NOT in the API's reasoning-effort enum — arm C's identity is UNPROVEN

Control run (`-c model_reasoning_effort="bogusvalue"`), rc from the API:

```
400 invalid_request_error
[ReasoningEffortParam] [reasoning.effort] [invalid_enum_value] Invalid value: 'bogusvalue'.
Supported values are: 'none', 'minimal', 'low', 'medium', 'high', 'xhigh', and 'max'.
```

So the CLI passes unknown effort values **straight through to the API**, which rejects them — the
enum is enforced server-side, and `ultra` is absent from it.

**But `ultra` did not error.** `codex exec -m gpt-5.6-sol -c model_reasoning_effort="ultra"`
completed normally (`turn.completed`, 310 output / 293 reasoning tokens), and the rollout's
`turn_context` records `effort: ultra` verbatim.

Both facts are measured. They are not consistent with each other, and the gap is exactly where a
fabricated data point would hide:

- if `ultra` is a real tier the error message's enum has not caught up with, arm C is what the plan
  says it is;
- if `ultra` is silently coerced server-side (most plausibly to `xhigh`, the config default it would
  fall back to), **arm C is a duplicate of arm B** and every "C beats B" or "C ties B" reading in W3
  is an artifact.

Nothing measured so far distinguishes those. **Do not assume `ultra` = max reasoning.** The cheap
discriminator, if arm C has not finished: run one throwaway prompt at `ultra` and one at `xhigh` and
compare `reasoning_output_tokens` in `turn.completed` across several samples — a coerced `ultra`
tracks `xhigh`'s reasoning-token distribution. Also worth one run at `max`, which *is* in the enum
and is the plan's actual intent ("max reasoning"). If it cannot be discriminated, record arm C's
effort as `ultra (UNVERIFIED — not in the API enum; may be coerced)` in `index.json`, so W3 sees the
uncertainty rather than inferring a clean tier.

## 2. 🚨 Codex `--sandbox read-only` does NOT deny reads — the no-repo-access constraint is unenforced for arms B/C

From the rollout's own `turn_context`:

```json
"sandbox_policy": {"type": "read-only"},
"permission_profile": {"type": "managed",
  "file_system": {"type": "restricted",
    "entries": [{"path": {"type": "special", "value": {"kind": "root"}}, "access": "read"}]},
  "network": "restricted"}
```

`read-only` means **no writes anywhere and reads of the entire filesystem**. A Codex arm that decides
to look can `cat` the real subject file, its test suite, and its fix commit — the exact collapse W1
warned about. The brief's "do not use any tool, file, or resource other than this brief" is an
instruction, not a control, and the Claude arms are hard-denied by comparison (see 3).

There is no read-denial knob to reach for, but there is a **measurement**: run
`codex exec --json` and keep the event stream, then assert zero `exec_command` / shell items per run.
That converts an unenforceable instruction into a checkable fact, costs nothing, and is
**unrecoverable if the stream is not captured at run time**. If arms B/C are already running without
`--json`, the rollout under `~/.codex/sessions/` still holds the turn's items — harvest the shell
calls from there per run and record the count in `index.json`'s `note`.

## 3. ✅ The Claude-arm isolation recipe, measured (not asserted)

```
cd <neutral scratch dir containing only the brief>
CLAUDE_CONFIG_DIR="$HOME/.claude-quaternary" claude-latest -p \
  --model <claude-fable-5|claude-opus-5> --effort <xhigh|max> \
  --tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands \
  --no-session-persistence --output-format stream-json --verbose
```

- `--tools ""` is **hard enforcement**: the `system/init` event reports `tools: []`, and a probe
  explicitly asked to read a canary file in its cwd emitted **zero `tool_use` blocks** (it said
  "Reading the file now" and ended the turn — worth knowing, since the prose *claims* an action the
  harness never let it take).
- Asked cold what it had, the model *hallucinated* "Read, Write, Edit, Glob, Grep, Bash" from the
  generic system prompt. **A model's self-report of its own tools is not evidence** — only the
  `init` event and the absence of `tool_use` are.
- `--setting-sources ""` + a scratch cwd loads **no CLAUDE.md, no MEMORY.md, no hooks** (~7.9k
  system-prompt tokens only; model confirms no memory documents). This matters: this repo's
  `MEMORY.md` index names several corpus defect classes outright — e.g. *"Denylist = examples — `-rf`
  let 11/13 past"*, which is `cp-01`'s ground truth in one line. A Claude arm run with project memory
  loaded is voided.
- Use a **neutral scratch path** (`/private/tmp/rvw/...`). The session scratchpad's own directory
  name embeds `-Users-chrisren-Development--worktrees-probe-grid`, and cwd is in the system prompt.

## 4. A usage-policy refusal is a reachable arm outcome on this corpus

A short diagnostic prompt to `claude-fable-5` returned `stop_reason: "refusal"` —
*"restrictions on violative cyber content"* — with a 1.7s turn and 2 output tokens. `cp-01` is a
security hook about `rm -rf` denylists; a refusal on that brief is plausible for the Claude arms.

That is a **real arm result**, not a harness fault: record it verbatim as `ok:false` with the refusal
text in `note`, and do not retry it into a clean number. The acceptance criteria already say to
report `ok<36` honestly.

## 5. Quota state, for the sole runner's baseline

Codex `primary.used_percent` read **22.0** before my preflights and **22.0** after all three
(2026-08-11T08:42:32Z). My preflight spend is below the signal's granularity and does not
meaningfully contaminate the before/after deltas. Weekly bucket, resets 2026-08-17.
