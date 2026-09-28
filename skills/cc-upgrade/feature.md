# feature.md — adopting a harness feature (phase P5b)

For a Claude Code release that ships something we might use (Dynamic Workflows, a concurrency
knob, `omitClaudeMd`, per-turn effort, time budgets, a new built-in command). The question is not
"is it in the changelog" but "what does the binary actually do, and does it pay here". Worked
example: `docs/research/opus55-feature-adoption-2026-09-22/README.md` — copy its method, never its
numbers.

## 1. Lever list

From the CHANGELOG slice (audit.md Step 2) and the release notes, list each candidate lever with
the surface it would change (settings `env`, agent frontmatter, Workflow `agent()` opts, a hook,
a launcher flag) and the cost it targets (wall-clock, quota, context, correctness).

## 2. Read the binary, not the paraphrase

The changelog paraphrases; the binary is ground truth. The main npm package is a small wrapper
stub; the real CLI is a per-platform Bun single-executable (`claude.exe`, ~220 MB) shipped as an
`optionalDependencies` package (`@anthropic-ai/claude-code-<platform>`, version-matched). The
installed one is `readlink -f` of the path `bin/cc-claude-bin` prints (or of a candidate's
`~/.claude-<NNN>/node_modules/.bin/claude`). Search it with Python `mmap` + `find`, which answers
in under a second; `strings | grep` over the whole file takes minutes, and a plain `grep` is blind.

```bash
python3 - "$(readlink -f ~/.claude-<NNN>/node_modules/.bin/claude)" CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT <<'PY'
import mmap, sys
with open(sys.argv[1], 'rb') as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
    i = m.find(sys.argv[2].encode())
    while i != -1:
        print(m[max(0, i - 300):i + 300].decode('utf-8', 'replace').replace('\n', ' ')); print('---')
        i = m.find(sys.argv[2].encode(), i + 1)
PY
```

Read the resolver, the default, the parser's bounds, and who reads the value (per session, per
run, per agent). Record the extracted code in the run dir.

**A built-in command's hidden prompt** (e.g. `/checkup`, alias of `doctor`) extracts the same way,
or read-only into `/tmp` from the platform package without touching any install:

```bash
cd /tmp && npm pack @anthropic-ai/claude-code-darwin-arm64   # the platform pkg for THIS arch
tar xzf anthropic-ai-claude-code-darwin-arm64-*.tgz
bin=$(find package -name claude.exe -o -name 'claude' -type f | head -1)
strings -n 8 "$bin" > /tmp/cc-bin-strings.txt                # one-off; slow but complete
grep -nE 'doctor|checkup|Check [0-9]|DISABLE_DOCTOR_COMMAND' /tmp/cc-bin-strings.txt
```

A naive grep catches noise (the binary also embeds the Workflow tool's own prompt), so anchor on
the command's unique markers; pick the platform package for your arch (`-darwin-arm64`,
`-darwin-x64`, `-linux-x64`, `-linux-arm64`, `-win32-x64`). Governance: `doctor`/`checkup` is
killable via `DISABLE_DOCTOR_COMMAND` — set it if its auto-fixes (disabling rarely-fired but
deliberate skills, moving always-loaded CLAUDE.md rules, turning off load-bearing slow hooks) would
fight a deliberate config. Its version-currency check no-ops under `DISABLE_AUTOUPDATER=1`.

## 3. A/B one lever at a time

- Build both arms from the same definition, differing only in the lever (e.g. `<name>-base` and
  `<name>-omit` agents), and read the artifact the lever should move (first-turn context tokens,
  `effort=` per request in stream-json, wall-clock per wave).
- Add a sentinel or positive control that proves the lever took effect in each arm.
- Judge quality blind when the lever trades speed or tokens for output (a faster arm that drops
  completeness fails "faster at ≥ equal quality").
- Say what one sample cannot tell, and what re-probe would move the verdict.
- A probe that needs a subagent spawn can be refused by the capacity gate on a loaded box; record
  it as unmeasured, never as a pass.

## 4. Adopt or drop, with a conviction number

Per lever: **Adopt / Do not adopt / Stopped** and a conviction %. Below 90%, name the probe still
owed. A lever whose actuator would write an operator-owned file (settings, allowlists) is
**Stopped** and handed to the operator, never built.

## 5. Wire it

- A process-environment knob goes in settings `env`, which is a `c10` migration
  (`migrations/README.md`): staged for the operator, never self-run.
- Agent frontmatter and repo files: an ordinary commit, with a bats test pinning the adopted value.
- **Every adopted feature gets its own gate probe** before activation
  (`lib/cc-upgrade-gate/checkNN_<feature>.sh`, gate.md), so the next binary move re-proves it.
