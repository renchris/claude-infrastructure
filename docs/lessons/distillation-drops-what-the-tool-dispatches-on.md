# A distillation reproduces the path your example took; what it drops is the dispatch table

**The rule.** When you port a tool's behavior into a prompt, a skill, or a reimplementation, the
thing you silently omit is whatever the tool **dispatches on** — a `switch`, a style/mode/profile
table, a strategy registry. You read the code path your one example exercised, distilled that
faithfully, and never saw the other branches, because nothing in a working trace points at the
branches it did not take. **Before claiming a distillation covers the tool, count the branches of
every dispatch it performs, and check which branch is the tool's own DEFAULT.**

## The incident (2026-09-17, claude-infrastructure)

Distilling Grok-Wiki's wiki generator into `skills/repo-wiki/SKILL.md`. The extraction was careful:
`src/prompts/{prelude,structure,page}.ts` read out of the unminified bundle, the exploration script,
the page-count policy, the decomposition rules, the page shape, the diagram harness — all carried
verbatim. The skill then stated its own gaps in a summary line:

> What genuinely does not carry over is state, not intelligence: the `~/.rlm-wiki` store, per-page
> concurrency, and the multi-repo namespace.

Every clause of that is true and the sentence as a whole is false. The operator asked the one
question that tests it — *"so are you saying it doesn't fully encapsulate the original run?"* — and
the re-audit found the generator dispatches on **15 named styles** through `wikiStyleGuidance`,
**12,635 chars of prompt in that one function**. The skill carried **one**.

Worse than the count: **the one it carried was not the tool's default.** Grok-Wiki's CLI defaults to
`first-30` (onboarding — what this is, where to start, read order, glossary). The skill's implicit
lens was `technical` (developer reference). So the distillation and the tool, handed the same repo
with no flags, would produce *different artifacts* — and the distillation's own summary line said
the only losses were a filesystem path and a concurrency setting.

A style in that generator is not a tone setting; it changes what the structure pass goes looking
for. `debugging-atlas` builds a table of contents out of symptoms, probes and root-cause paths;
`worth-stealing` opens by naming reusable moves and ends every page with `## What To Reuse`;
`hidden-quirks` hunts specifically what the README does not show. Fifteen different questions asked
of one repo.

## Why the wrong self-assessment was so comfortable

"State, not intelligence" is a flattering frame that survives exactly as long as nobody enumerates.
It sorts the known gaps into a harmless bin — store, concurrency, namespace are all plumbing — and
the sorting *feels* like an audit while never asking whether the bin is complete. The three gaps in
it were the three the extraction had happened to notice. **A gap list assembled from what you
noticed is a list of your attention, not of the difference.**

The measurement that refutes it costs one command:

```bash
python3 - "$BUNDLE" <<'PY'
import sys,re
b=open(sys.argv[1],encoding='utf-8',errors='replace').read()
st=b.find('function wikiStyleGuidance'); seg=b[st:b.find('\nfunction ',st+10)]
print(len(seg), re.findall(r'case "([a-z0-9-]+)":',seg))
PY
```

## How to check, generally

1. **Grep the subject for its dispatch points** — `switch`, `case`, a `styles`/`modes`/`profiles`
   map, a registry, an enum the code branches on. Each is a fan-out your trace never showed you.
2. **Find the default.** A distillation that omits the default branch differs from the tool on the
   *no-flags* invocation, which is the invocation almost everyone uses.
3. **State the residual by name, not by category.** "State, not intelligence" is a category; "15
   styles, 1 carried, and not the default" is a fact someone can act on.
4. **Say what you left out on purpose and why.** Scope is legitimate; silence about it is not. Here
   `ask` stays out because repo Q&A is the host's native competence — that is an argument, and an
   argument is auditable in a way an omission is not.

## Companions

- `spec-named-mechanism-may-be-prose-only.md` — a cited mechanism can exist only in prose; grep the
  identifiers against the tree. Same family: believing a description over an enumeration.
- `zero-claim-must-name-its-excluded-strata.md` — a clean count that hides a stratum reads as
  all-done. This is its constructive twin: name the strata your coverage claim excludes.
- `closure-measured.md` — a "there is no fourth option" closure is a claim about its premises.
