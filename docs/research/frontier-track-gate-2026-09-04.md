# The frontier tier was gated on a deleted launcher — in FOUR places the filing did not name

**Backlog row:** `9ce3c6350e2f` — *"reso docs still gate the frontier tier on the deleted
claude-next eval track (project-pass.md, CONTEXT_EXHAUSTION_GUARDRAILS.md)"*
**Venue:** cloud VM, dispatched 2026-09-04. **Branch:** `claude/fire-20260904T193754Z-36841-1`.
**Disposition:** premise SPLIT — half refuted-as-located, half confirmed-and-widened. Cure landed
for the reachable half; the reso half parked (`docs/parks/9ce3c6350e2f.md`).

---

## 1. The premise, checked before acting

The row asserts one defect in two named files. Checked against `origin/main`, at
`HEAD..origin/main == 0` (this tree IS trunk) and after `git fetch --unshallow` — the checkout
arrived shallow at depth 50, so every ancestry read below would otherwise have answered from
inside that horizon.

**Neither cited name exists in this repository, in the working tree or anywhere in history:**

```
git ls-tree -r --name-only origin/main | grep -iE 'project-pass|CONTEXT_EXHAUSTION'   → no match
git log --all --name-only | grep -iE 'project-pass|CONTEXT_EXHAUSTION'                → no match
```

They were located by their *referrers*, both of which give the same absolute answer:

| Referrer | What it says |
|---|---|
| `templates/model-classification.json:28-29` | `Development/reso-management-app/.claude/commands/project-pass.md`, `Development/reso-management-app/docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md` — both under `review` |
| `skills/model-upgrade/SKILL.md:184` | same two paths, annotated *"(reso — a SECOND repo with its own gate and land cycle; scope that deliberately)"* |

**So the row's `repo:` field and the row's `title:` disagree.** It is filed against
`claude-infrastructure`, and dispatched into a checkout of `claude-infrastructure`, but every file
it names lives in `reso-management-app`. That is not a typo in the filing — it is the row's whole
difficulty, and it is why two prior claims (`claims: 2`) came back with nothing.

**The reso half is unverifiable and unfixable from this venue**, and this is a hard limit, not a
preference: there is no reso checkout on this VM (`find / -maxdepth 6 -name reso-management-app`
→ empty; `~/Development` does not exist), and GitHub access is scoped to
`renchris/claude-infrastructure` alone. Whether those two files *still* carry the conjunct is a
claim this session **cannot** settle in either direction, and it is recorded here as open rather
than guessed.

## 2. The half that IS in this repo — and the row did not know it was here

The generator behind the row is real, current, and had **four live carriers in
`claude-infrastructure` itself**. The sibling cure `436f3435` (*"docs(frontier): name the SSOT key,
not the model — two gates no reader could satisfy"*, 2026-09-03) fixed exactly two files —
`commands/research.md` and `agents/deep-research.md` — and stopped there:

```
$ git merge-base --is-ancestor 436f3435 origin/main && echo ancestor
ancestor
$ git show --stat 436f3435
 agents/deep-research.md | 2 +-
 commands/research.md    | 4 +++-
```

The four it did not reach, in severity order:

1. **`skills/frontier-run/SKILL.md:19-21`** — the worst, because it is not prose but a **hard gate**
   inside a list headed *"Gate (hard, in order — stop at the first failure)"*. Step 2 read
   *"Require the eval track … On the stable track: report and stop."* Consolidation v2 deleted that
   track, so step 2 was an unsatisfiable conjunct in front of every `/frontier-run`: read literally,
   the skill stops before it ever spawns, permanently, and reports the tier as unavailable.
2. **`skills/research-subagents/SKILL.md:559-568`** — a live routing instruction (*"While `active:
   true` AND the session is on the eval track, route the adversarial/judge/depth-coordination slots
   to Fable 5"*) carrying **the same triple of dead conjuncts `436f3435` cut out of
   `commands/research.md`**: a usage window `2026-06-09 → 2026-06-23` that died two windows before
   it was read (`frontier_access.permanent: true` since 2026-07-20), the deleted track, and an
   "after the window" fallback branch that can no longer be entered.
3. **`skills/agent-teams/SKILL.md:246-251`** — *"That holds (if ever) ONLY on the claude-next eval
   track — NOT universally."* Gates the `model: "fable"` subagent override on the deleted name.
4. **`model-config.yaml:467`** — *"**STILL BINDING** (unchanged by permanence): Fable exists ONLY on
   the claude-next eval track."* The strongest form of the rot: a header that explicitly asserts
   currency, **17 lines above the `tracks:` key that already records the deletion**
   (`:484` — *"⚠️ STALE LABEL … consolidation v2 deleted the `claude-next` launcher"*). One file
   contradicting itself within one screen, with the false half marked STILL BINDING.

## 3. What decided the cure: the enforcer never asked

The shipped gate is `hooks/frontier-spawn-gate.sh`, and it reads **`active` and `end` only**:

```
:42  active="$(… grep -m1 '  active:' …)"
:43  end="$(… grep -m1 '  end:' …)"
:47  if [ "$active" = "true" ] && [ -n "$end" ] && [ ! "$today" \> "$end" ]; then
```

`frontier_access.tracks` has **no code consumer anywhere** — a sweep of `hooks/ scripts/ bin/`
returns only unrelated English uses of the word "tracks". So the track condition was doc-only
staleness on all four carriers: the machine had already stopped enforcing it, and only the
instructions still told agents it applied.

**The cure is therefore not "delete the gate" but "restate the gate as the thing that is actually
checkable":** a **binary version** (`CC ≥ 2.1.170`, i.e. not the deliberately-pinned legacy
`claude-previous`/`cc-previous` 2.1.114 path; the live launcher `claude` is on 2.1.260), which a
session can interrogate — never a launcher name, which no longer resolves. Each of the four edits
also records what the line used to say and why it rotted, per the principle `436f3435` established:
*a doc that restates a perishable fact has no path to learn the fact changed.*

## 4. Verification

- `model-config.yaml` still parses; `frontier_access` and `versions.frontier_latest`
  (`claude-fable-5-1`) unchanged in value — the diff is **comment-only** there
  (`git diff -U0 model-config.yaml` minus comment lines is empty).
- Targeted gate: the 30 `tests/*.bats` suites matching
  `frontier_access|frontier-run|research-subagents|claude-next eval|model-config` →
  **337 ok**, failures confined to `tests/accounts-board.bats`.
- Those failures are **not this diff's**: the suite fails **17** on the clean tree
  (`git stash`) and **17** with the diff applied — identical. It is environment-dependent
  (no live `~/.claude` / accounts store exists on a cloud VM).
- `scripts/claude-lint-models.sh --all` is **unrunnable in this venue**, not skipped:
  `ERROR: missing /root/.claude/model-config.yaml` — it reads the live `~/.claude` layer, which
  does not exist off-box.
- Full `bats tests/` (573 suites, the repo's `FULL` gate scope) is the desk lander's to run.

## 5. Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` → `98ab38f51f7ac82a043e522d3a9601ff9f460528`, against
the brief's stated composing blob `646b8a652e71dd5e5e506dffe23725437accea6b`. **DIFFERENT — the
dispatcher that fired this session is BEHIND trunk.** That is a convergence fact about the deploy
layer (landed is not live), not a defect in anything read above; no finding here depends on the
dispatcher's version.

## 6. What remains, and who owns it

The reso half. It needs a venue with a `reso-management-app` checkout — a desk session cwd'd into
that repo, which has its own gate and land cycle. The step is mechanical once there: read
`.claude/commands/project-pass.md` and `docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md`, and if
either still gates the frontier tier on `claude-next`, apply the §3 cure — restate the condition as
the CC binary version, name `versions.frontier_latest` and `frontier_access` rather than a model id
or a date, and note that `frontier_access.tracks` is a stale label with no consumer. If neither file
carries it, the row is cured and the premise was simply stale.
