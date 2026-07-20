# Deploying `pyramid-principle-full` without a 1M-token run

**Date:** 2026-07-20 · **Trigger:** a Fable ultracode session ran the skill inside a Dynamic
Workflow and spent 1M+ tokens over 1hr+, against an expectation of ~a dozen minutes.
**Verdict:** the skill is fine; the *deployment* inverted its economics. Fix = an execution contract
carried in `SKILL.md` itself, because the skill is what loads into the orchestrator's context.

**Evidence discipline.** Two findings are **measured** from artifacts still on disk (the unbounded
input body; the uncapped rework loop). One commonly-assumed cause — a per-session agent fan-out — is
**inferred only**: the originating transcript has aged out and no retained workflow runs this skill.
The sections below label which is which, and §5 states plainly what could not be verified. An
earlier draft of this document asserted the fan-out as an observed cause; that was an overclaim and
is corrected here.

---

## 1. The run under investigation

| Fact | Value | Evidence |
|---|---|---|
| Run | doc_classifier root README via the full Minto workflow | commit `9c43d191`, 2026-07-10 01:51 ("gate + critique passed") |
| Mode | C — Communication (message already clear; job = rigorous document) | worklog `README.pyramid-worklog.md:8` |
| **Declared input body** | `IMPLEMENTATION_PLAN.md` + `docs/research/00-34` + `docs/specs/B00-B23`+`C00` + `docs/briefs/` (16) + prototype docs | worklog:9 |
| **Measured size of that body** | 126 files · 530,919 words · 4.11 MB → **~740K tokens** | `wc` over the four trees |
| **Governing subset mode C needs** | plan + binding spec = 2 files · 65,217 words → **~91K tokens** | `wc` |
| **Oversize ratio** | **8.1×** | derived |
| Output | README 14,238 w + worklog 19,897 w ≈ 48K tokens | `wc` |
| Worklog | 950 lines / 131 KB | `wc` |
| Session 10 share of worklog | **444 / 950 lines = 47%** | `awk` per-section count |
| Session 10 closure | "**PASS after 6 in-critique repairs**" | worklog:507 |
| Pyramid shape | governing thought + 5 Key Line points + 3–5 children each ≈ **6 groupings** | worklog:41–60 |

Estimates marked "~tokens" use `words × 1.4` (markdown with tables/code runs above the 1.33 prose
ratio). File and line counts are measured.

---

## 2. Diagnosis — three compounding causes

### Cause 1 (dominant): the input body was never bounded

Session 0 of the skill says *"Identify: the **input body**, the reader(s), the medium…"*. It says
identify. It never says **bound**. So this run declared the entire 126-file design corpus as its
input — ~740K tokens — for a mode-C job whose message was already adjudicated and carried by two
governing documents (~91K tokens).

That single decision sets the floor for everything downstream. Every later stage that re-grounds
itself in "the input body" is now pricing against 740K tokens instead of 91K. **A 1M-token run
against a self-declared 740K-token input is not a wildly wasteful workflow — it is a workflow fed
an 8× oversized input.** No orchestration cleverness recovers from this; the fix has to land at
Session 0.

Mode C and mode R need only the documents that *govern* the message, never the whole corpus that
produced it. Modes P and T legitimately need more — but still need a stated bound.

### Risk 2 — fanning out along the sessions (INFERRED, *not* observed in this run)

> **Evidence status — read this before relying on the section below.** The originating session's
> transcript is **gone**. Every transcript that references `README.pyramid-worklog` post-dates the
> `9c43d191` commit; the earliest is 07-10 18:04, the commit was 07-10 01:51. A sweep of every
> retained workflow run (`~/.claude/projects/*/*/subagents/workflows/*/`) found **no workflow whose
> agents execute this skill** — the single hit is a 2026-06-22 run on Sonnet 4.6 / Opus 4.8 that
> merely mentions "Pyramid Principle" and pre-dates the skill's creation. So **I cannot show that
> this run was structured as a per-session fan-out.** What follows is a first-principles argument
> for why that decomposition is wrong, which stands on the skill's own text regardless of what this
> particular run did. It justifies rule 2 as *prevention*. It is not a diagnosis of the 1M+ spend.
>
> Two nearby measurements, for calibration rather than attribution: the doc_classifier session
> closest to the commit window spent **1.49M fresh tokens over 42 min on Opus 4.8** with exactly one
> `Workflow` call — and that call was for an unrelated reso decision. Separately, three 2026-07-11
> `claude-fable-5` workflows in the doc_classifier project spent **26.4M / 10.7M / 10.2M fresh
> tokens** across **111 / 35 / 46 agents**; the 111-agent run's 68-minute window matches the "1hr+"
> recollection closely, but its agents are running a *documentation audit* (one agent per claim,
> adversarial-verify shape), **not** this skill.

The skill presents **10 numbered sessions**. An ultracode orchestrator's default decomposition
heuristic maps numbered lists onto workflow phases — one agent per session. That is the single
worst decomposition available here, and it is worth being precise about why:

- The sessions are a **strictly sequential chain**. `SKILL.md` is explicit: *"Sessions run strictly
  in sequence… A session may begin only when the previous session's exit checklist is fully checked
  and its artifact is appended to the worklog."* So per-session fan-out buys **zero** parallelism —
  the hard-stop protocol serialises the agents anyway.
- Yet it pays **full** fan-out cost. Every agent cold-starts and must re-receive the pyramid, the
  worklog (which grew to 131 KB / ~33K tokens by the end), and — absent Cause 1's fix — the input.
- The worklog re-read is quadratic: session *N* reads the artifacts of sessions 1…*N*−1. Over ten
  sessions against a worklog ending at 33K tokens, that is on the order of 150K tokens of pure
  re-reading that an inline run pays **once**, as cache.

The genuinely parallel axes in this methodology are *not* the sessions. They are (a) **corpus
slices** during Session 3's extraction, and (b) **independent audit lenses** in Sessions 8 and 10.

### Cause 3: the rework loop has no cap

Session 10 mandates *"Iterate until a full pass is clean."* This run closed "PASS after **6**
in-critique repairs," and Session 10 alone produced **47% of the entire worklog**. Each repair
round re-reads the artifact and re-runs dependent gates.

Under ultracode's standing posture — *"lean toward orchestrating with workflows and adversarially
verifying your findings"*, plus the loop-until-dry pattern — an uncapped "iterate until clean"
becomes a multi-round panel where each round spawns verifiers over a 20K-token artifact. Nothing in
the skill bounds it.

---

## 3. The counter-intuitive finding: inline beats fan-out on *both* axes

The instinct is that a workflow makes a long job faster. For this skill it does neither:

**On cost.** The lead holds the pyramid in one warm context. Every session after 3 is then a cache
hit plus its own thinking (~10K) and artifact (~2K). Fanning out re-transmits that state *cold*
into every agent, and each returns a fraction of what it consumed. Order-of-magnitude shape for the
S4–S10 audits on a typical pyramid (estimate, not measurement):

| Deployment | Shape | Effective cost |
|---|---|---|
| Inline | ~30K resident context, 7 sessions × (cache-read + ~12K new) | **~105K** |
| Per-session fan-out | ~18 agents × (~8K prompt + ~10K thinking + ~1.5K out), no shared cache | **~350K** |

**On wall-clock.** The critical path is the **sequential spine** — S0 → S3 → S4 → S9. The audits
(S5–S8, S10) are leaves hanging off it. Parallelising leaves shaves minutes from a path the spine
dominates. The Jul-10 run did not take ~68 minutes because its audits ran serially; it took that
long because every stage was pricing against a 740K-token corpus.

So the rule inverts the ultracode default: **inline by default, fan out at two named boundaries
only.**

---

## 4. The execution contract

Landed in `SKILL.md` (§ *Execution contract*) so it loads with the skill. Summary:

1. **Bound the input at Session 0 and state its token cost.** ≤30K → Tier A. 30–150K → Tier B.
   \>150K → **stop**, scope to governing documents or justify the full read in the worklog.
2. **Run the spine inline.** S0–S4 and S9 in one context. Never one agent per session.
3. **Fan out at exactly two boundaries.** S3 corpus extraction (one agent per slice, each returning
   ≤2K tokens of *candidate ideas + citations* — never prose); S10 critique panel (one agent per
   lens over the frozen artifact, **cap 4**). Never fan out S4–S8.
4. **Cap the rework loop at 2 rounds.** A third round means the defect is structural — fix it in the
   owning session once, re-run only the touched gates, log the residual in the variance log.
5. **Suspend the ultracode posture.** The exit checklists and Session 8's gates *are* the
   verification. Adding refuter panels verifies the verifier — the largest single source of runaway
   cost here.

**Budget heuristic:** a correctly-bounded run costs ~1× the input body plus ~60–120K tokens of
thinking, landing in 10–15 minutes. Trending past **2× the input body** means Cause 1 or Cause 2 is
live — stop and re-read the contract.

The two sanctioned fans are implemented runnable at `~/.claude/workflows/pyramid-fans.mjs`
(versioned at `pyramid-principle-full/workflows/pyramid-fans.mjs`) — `args.phase="extract"` with
`args.slices`, or `args.phase="critique"` with `args.artifact`. Two design points carry the
contract into the script's shape:

- **Slice-readers return candidates, not structure.** Each returns `{idea, citation, kind}` under a
  schema and is told explicitly not to summarise its slice or propose an ordering — grouping needs
  every candidate at once, so that judgment cannot leave the lead. This is also what keeps the
  return small (≤2K tokens) against a slice that may be 50K.
- **Critique lenses return defects with an owning session, not rewrites** — matching the rework
  loop, where repairs are applied in the session that owns the defect (3/5/6/7), not patched into
  the artifact by the finder.

Both fans use `parallel()` rather than `pipeline()`. That is one of the genuine barrier cases: the
lead cannot group candidates until it holds all of them, and cannot write the variance log until all
lenses have reported.

**Making the contract auditable.** Rules 1 and 4 are mechanically checkable, so they are checked:
`pyramid-principle-full/scripts/pyramid-worklog-lint.sh` is fail-closed (exit 1 on violation, 2 on
usage/unreadable) and asserts Session 0 recorded a bounded input with a token estimate and a tier,
and that the rework loop stayed within 2 rounds; it warns when the Session 3 pyramid carries no
citations — the condition that forces later sessions back into the corpus. It was proven on a
**discriminator pair** rather than one direction: the Jul-10 doc_classifier worklog fails both rules
and exits 1, a compliant fixture exits 0. Without the contract, a non-compliant run was visible only
as a large bill after the fact.

Rules 2, 3 and 5 are not mechanically checkable from the worklog — they are properties of the
orchestration, not of the artifact. They rely on the contract loading with the skill, which is why
it lives in `SKILL.md` rather than in this document.

---

## 5. Replay — would the contract have caught this run?

Checked against the Jul-10 run's own recorded numbers:

| Rule | What it tests | Jul-10 run | Fires? |
|---|---|---|---|
| 1 — bound the input | declared body > 150K tokens | ~740K declared (**measured**) | **yes**, at Session 0, before any cost |
| 2 — inline spine | one agent per session | **unverifiable** — transcript aged out | can't say |
| 3 — fan-out boundaries | fans outside S3/S10 | **unverifiable** — same | can't say |
| 4 — rework cap | > 2 repair rounds | **6 rounds**, 47% of the worklog (**measured**) | **yes**, at round 3 |
| Budget | run > 2× input body | declared body alone is ~8× the governing subset | **yes**, early |

Rule 1 is the one that carries the result: it fires at Session 0, before a single token of analysis
is spent, and alone re-scopes the run from ~740K tokens of declared input to ~91K. Rule 4 fires
later and caps the tail. **Rules 2, 3 and 5 are prevention, not repair** — they are justified by the
first-principles argument about sequential chains, not by anything observed in this run.

### What could not be verified

Stated plainly, so nobody later mistakes inference for measurement:

- **The orchestration shape of the 1M+ run.** The originating transcript has aged out of retention.
  No retained workflow anywhere on disk executes this skill.
- **The token split of that run** (output vs cache-read vs fresh). Same cause. Note that "1M+" is
  ambiguous without that split: in the nearby runs measured for calibration, `cache_read` exceeds
  fresh spend by roughly 5–6×, so a headline token figure can describe very different real costs.
- **Whether the run was on Fable 5.** The session nearest the commit window ran on Opus 4.8. The
  Fable-5 workflows found in that project were doing a documentation audit, not this skill.

None of this weakens the contract. Rules 1 and 4 answer measured defects; rules 2, 3 and 5 are
cheap, sound as design guidance, and cost nothing when they turn out to be unnecessary. But the
honest summary is: **the dominant measured cause is the unbounded input, and the orchestration story
is a hypothesis.**

---

## 6. The generalizable lesson

The trap is not specific to Minto. **A skill that presents itself as N numbered sequential steps
invites an orchestrator to map those steps onto N agents** — and when the steps are a hard-stop
chain over shared state, that mapping is strictly dominated: zero parallelism gained, full fan-out
cost paid, plus quadratic re-reading of the growing shared artifact.

The diagnostic question before fanning out any staged skill: **is the critical path the stages, or
the state they share?** If the stages must serialise anyway, the only useful fan-out axes are
(a) map-reduce over an input too big for one context, and (b) genuinely independent lenses over a
frozen artifact. Everything else belongs inline, where shared state stays cache-warm.

---

## 7. Residual notes

- The skill lives in two places that must stay in sync: the versioned source at
  `~/Development/pyramid-principle-full/skills/pyramid-principle-full/` (GitHub:
  `renchris/pyramid-principle-full`) and the live copy at
  `~/.claude/skills/pyramid-principle-full/` (a real directory, **not** a symlink). They were
  byte-identical before this change; both were updated.
- `evolve-fixtures/pyramid-principle/cases/` in claude-infrastructure holds 4 fixture cases for the
  *compressed* sibling skill. They are 17–25 lines each — useful for Tier-A smoke tests, too small
  to exercise the bounding rule.
