# The venue classifier reads a POINTER for `plan-open` rows — and the obvious fix starves the tap

**2026-08-29, a cloud VM fired on backlog `70f0001c657b`** (*"advance BACKLOG_DRAIN_24_7 — SSOT plan:
drain cc-backlog to zero, and keep it there"*, project `claude-infrastructure`, dodRef
`docs/plans/BACKLOG_DRAIN_24_7.md`).

The repo was right this time — unlike the `venue-foreign-repo-*` family, whose rows named a project
the VM could not clone. The **work** is what is unhostable: every remaining section of that plan is
ledger operations on `~/.claude/autonomy/backlog.jsonl`, stranded-branch recovery across worktrees
that exist on one disk, `launchctl` policy, and a self-recycling local drain chain. None of it is
reachable from a VM, and `bin/cc-cloud`'s own header says the first one never can be.

This file records two things. The first is the mechanism, which is new: **for a `plan-open` item the
classified span is a pointer, not a specification.** The second is a REFUTATION of the fix that
mechanism obviously implies, measured before it was written — the reason this session landed no code.

---

## 1 · The measurement: the item fires nothing, its subject fires everything

`bin/cc-eligible` classifies `SPAN_FIELDS = ("title", "dodRef", "condition", "source")`. For an item
minted by cc-discover's C2 critic those four fields hold a title, a path and the word `plan-open` —
the plan's H1 and a pointer to it. The plan's remaining work is not in the span at all.

Run against a fixtured store carrying this row verbatim (`CC_BACKLOG_FILE` at a temp JSONL,
`CC_ELIGIBLE_REPO` at this checkout):

```
$ cc-eligible why 70f0001c657b --json
  "verdict": "eligible",
  "description": "repo-only work — no local-only state named",
  "tokens": [],
$ cc-eligible check 70f0001c657b   →  verdict=eligible   rc=0
```

Now classify the same plan's **not-DONE sections** (10 of 12, level > 1, via
`scripts/plan-phase-scan.sh`) through the identical `classify_all()`:

| class | tokens that fired |
|---|---|
| `ineligible-offbox-lane` | off-box · cloud-lane · cc-cloud · cc-offload · cloud-session · venue |
| `ineligible-spawn-rail` | handoff-fire · spawn-rail |
| `ineligible-box` | launchd · plist · daemon · pane · terminal · iterm2 · kitty · tmux · hook · quota · account · keychain |
| `ineligible-visual` | screenshot · browser · dev-server · visual · render · pixel · banner · ui |
| `ineligible-branch-banking` | worktree · unpushed · unlanded · stranded · local-branch · wt-slug |
| `ineligible-github` | gh-cli · github |

**All six refusal classes, `off-box-lane` among them.** `OFFBOX_LANE`'s own docstring states the rule
it was built for — *"A SESSION THIS LANE CREATED CANNOT VERIFY A CHANGE TO THE LANE"* — and the row
it admitted is the plan that **builds that lane**. The classifier did not fail its own rule; it never
saw the text the rule is about.

This is `assertion-span-must-equal-its-subject`, the memory `SPAN_FIELDS` is annotated with, one
level up: the span is correct for an item that *describes* work and empty for an item that *points
at* it.

---

## 2 · The refutation: widening the span to the plan body starves the tap completely

The implied fix — classify the plan's remaining sections instead of the pointer — was measured over
every open plan in `docs/plans/` (45 of 76, frontmatter status not complete/superseded) before being
written. Three candidate spans, same `classify_all()`, same corpus:

| span | flips to INELIGIBLE | catches `BACKLOG_DRAIN_24_7`? |
|---|---|---|
| remaining sections, **full body** | **45 / 45 — 100%** | yes |
| remaining section **headings only** | 30 / 45 — 67% | **no** |
| headings **+ the `Scope (frozen)` line** | 34 / 45 — 76% | yes |

**The full-body span refuses every plan-open row in the corpus.** That is the exact cost
`bin/cc-eligible`'s header warns against in as many words — *"a word added because it 'sounds local'
costs the cloud tap a whole class of real work, and the tap is the entire point"* — arrived at not by
adding a word but by widening the span until any word suffices. Over a 2.3 MB document some refusal
spelling appears almost surely; a single `render` in 2.3 MB carries no signal.

Headings-only has a defensible false-positive profile and a fired list that reads correct
(`TERMINAL_AGNOSTIC_L3_L4` → pane/iterm2/kitty, `DAEMON_FLEET_V2` → launchd/plist,
`README_HERO_BANNER` → css/render/pixel/banner) — **and it misses the row that exposed the defect**,
because this plan's remaining headings are structural scaffolding (*"§3 Reconciliation worklist"*,
*"§4 Pipeline architecture"*) that spells nothing local.

Headings + `Scope (frozen)` catches it (`off-box` comes from the frozen scope line itself) at 76%.
But only **53%** of open plans carry a `Scope (frozen)` line at all, so the arm is silent on half the
corpus — and inspecting its 11 survivors refutes the framing rather than endorsing it:
`GUARDRAIL_HOOKS_V2`, `MASTER_ENFORCING_STORE` and `MASTER_FLEET_FOOTPRINT` are plainly box work that
the **spelling list** does not reach, at any span. The residue is not a span problem, and a fourth
span would not find it.

**What the three rows actually say together:** the `plan-open` class in this repo is very nearly all
local — 34 of 45 measured, with several of the 11 survivors misclassified in the same direction. That
is a statement about the CLASS, and the honest repair is a class-level venue rule for `plan-open`
rows, not a better span. It costs the tap the genuinely-eligible remainder, so it is a value call
with a measured price, which makes it the operator's and not this session's.

---

## 3 · Why this session landed no code, and the refusal is the rule working

Two independent guards in the lane's own source refuse a fix from here, and both are load-bearing:

1. **`OFFBOX_LANE`, quoted above.** `bin/cc-eligible` is the admission predicate for the cloud tap. A
   session this lane created cannot verify a change to the lane: if the change is wrong, the failure
   is that rows stop being admitted, or are admitted into a VM that cannot see them — and both are
   invisible from inside the session the lane produced. Observer and subject are the same object.
2. **The shallow guard.** This clone is grafted at 50 commits; `cc-eligible why` reports
   `"history": {"state": "shallow", "depth": 50}`, and by design the PRODUCER fails closed there —
   `cc-venue` will not write a cloud label without a certification a shallow clone may not issue.

This is the same refusal `BACKLOG_DRAIN_24_7` §4's *A-lane routing 2026-08-18* entry made for the
spawn rail, for the same reason, and it is recorded here rather than acted on for the same reason.

The measurement above is the deliverable; the fix is a local session's.

---

## 4 · Reproducing the numbers

The probe is three calls and no fixture beyond a temp JSONL. `classify_all()` is imported by exec'ing
`bin/cc-eligible` up to `def main(` — it is pure (no I/O, no ledger, no git), which is what makes it
safe to call directly:

```python
import json, subprocess, sys, glob, re
src = open("bin/cc-eligible").read()
mod = type(sys)("cce"); mod.__dict__["__name__"] = "cce"
exec(compile(src.split("def main(")[0], "cc-eligible", "exec"), mod.__dict__)

def remaining(plan):                       # not-DONE sections, level > 1
    doc = json.loads(subprocess.run(["scripts/plan-phase-scan.sh", plan],
                                    capture_output=True, text=True).stdout)
    L = open(plan, encoding="utf-8", errors="replace").read().splitlines()
    out = []
    for s in doc["sections"]:
        if s.get("level", 1) > 1 and s.get("status") != "DONE":
            out.append(s.get("title", ""))
            out += L[max(0, int(s["start_line"]) - 1):min(len(L), int(s["end_line"]))]
    return out

# span A: full body   span B: [t for t in ... if is a title]   span C: B + the Scope(frozen) lines
print(mod.classify_all("\n".join(remaining("docs/plans/BACKLOG_DRAIN_24_7.md"))))
```

Corpus openness is read the same way `find-plan.sh`'s `plan_status()` reads it — YAML frontmatter
`status:`, excluding `complete`/`completed`/`superseded` — so the denominator matches the population
cc-discover's C2 critic actually mints from. Elapsed: 11.4 s full-body, 5.2 s headings, over 45
plans.

**Declared blind spot, and it is the important one:** this corpus is `claude-infrastructure`'s
`docs/plans/` only — 45 plans. The live store's `plan-open` rows span other projects whose plans this
VM cannot read, and the header's own rule is to measure over the live ELIGIBLE bucket, which needs
`~/.claude/autonomy/backlog.jsonl` and is unreachable here. Re-run the three spans locally against
the real bucket before acting on the class-level rule in §2.
