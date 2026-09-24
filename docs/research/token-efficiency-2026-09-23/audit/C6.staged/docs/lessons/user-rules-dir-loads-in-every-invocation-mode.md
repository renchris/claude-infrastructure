# `~/.claude/rules/*.md` loads in every invocation mode — and a sentinel inside an HTML comment is invisible

_Relocated VERBATIM from `~/.claude/rules/agent-operating-lessons.md` (live-only, untracked, user-level: it loaded in every repo) — the file was removed from the always-loaded tier by the 2026-09-23 token-efficiency pass (`docs/research/token-efficiency-2026-09-23/audit/C6.rules-essay.md`). Nothing was shortened. The one finding added below the rule is new._

**The rule, stated once:** when a negative disagrees with a positive, do not reach for a story that reconciles them (a version fix, a scope limit); re-run both arms, on the original binary too, and let the weaker instrument lose. Invocation mode (interactive vs `claude -p`) is a variable. A probe's negative arm must prove the token is visible to the model, not only present on disk: the loader strips HTML comments from memory files, so a sentinel inside `<!-- -->` can never be found.

## Finding added 2026-09-23: why the original `RULES=NO` probe could never pass

Measured with the `/context` method on Claude Code 2.1.280: a `CLAUDE.md` holding 2,897 bytes that are entirely one HTML comment produced no memory row, while the same text without the comment markers read 1.1k tokens. This file's sentinel `RULESLOAD-OK-A7F3` sat inside an HTML comment, so the documented probe returned `NONE` on every binary. The 2026-09-09 positive probe used a fresh file with its token in body text.

## Where the reso lessons live

reso's agent-operating lessons load from reso's own `.claude/rules/agent-operating-lessons.md` in reso sessions. For cross-repo reach, symlink that file into another repo's `.claude/rules/` (a symlinked project rule loads). The `docs/plans/MEMORY_ARCHITECTURE_SPLIT.md` pointer below is dead: reso deleted that file in ece6ed407.

## The file, verbatim (6,334 bytes, as of 2026-09-23)

# THIS DIRECTORY LOADS EVERYWHERE — interactively AND in `claude -p`, on 2.1.114 AND 2.1.266

<!-- load-check sentinel: RULESLOAD-OK-A7F3 — do not remove. -->

🚨 **CORRECTED 2026-09-03. The headline below said "`~/.claude/rules/*.md` is NOT read by Claude
Code on this machine", full stop. That is HALF TRUE, and the false half is the half that matters:
this file IS loaded, verbatim and sentinel-included, into INTERACTIVE sessions.**

The evidence is this file itself. In an interactive session on 2.1.233 the harness injects it under
the header `Contents of /Users/chrisren/.claude/rules/agent-operating-lessons.md (user's private
global instructions for all projects)` — the product's own words for "this is loaded". No probe is
needed; the surface announces itself. Re-run of the documented probe the same day still returned
`NONE`, so **both arms are real and the variable is the invocation mode, not the surface**:

| invocation | `~/.claude/rules/*.md` |
| --- | --- |
| **interactive session** (TUI / launcher) | **LOADS** — this file, in context, right now |
| `claude -p` headless | **LOADS TOO** — measured on BOTH 2.1.114 and 2.1.266; see below |

🚨 **SECOND CORRECTION, 2026-09-09: the headless arm is FIXED, and the row above has been
updated rather than left to mislead.** On the live binary (2.1.266) the documented probe
returns the sentinel: a fresh `~/.claude/rules/00-zz-probe.md` holding
`MISSIONCARRIER-PROBE-K4X9`, read back by
`claude -p 'Reply with ONLY these tokens if they appear in your instructions … else NONE.'`,
answered `MISSIONCARRIER-PROBE-K4X9` — while the paired never-written token came back absent,
so the instrument can still say no. Reproduced independently four times the same day (three
subagents plus the lead, one under `CLAUDE_CONFIG_DIR=~/.claude-quaternary`).

**Why this matters more than a doc fix:** the false row said the one surface measured at 100%
session reach was dead for crons, dispatched fires and every `-p` run. Anything built on it
would have been written off unbuilt. It is the carrier for `~/.claude/rules/00-mission-board.md`
(the customer deal board, `cc-mission render`), which therefore DOES reach headless sessions.

⚠️ **AND MY OWN FIRST CORRECTION WAS ALSO TOO NARROW — worth keeping as the sharper lesson.**
I initially wrote "fixed as of 2.1.266", assuming a version fix explained the disagreement. Then
an end-to-end check ran on **2.1.114** — the *pinned stable*, and one of the two versions the
original table names as NOT loading — and it read `~/.claude/rules/00-mission-board.md` out of its
instruction context and quoted the top row back verbatim. So the recorded negative **does not
reproduce on the very binary it was recorded against**, and "a later version fixed it" is NOT the
explanation. Something about the original probe was wrong (most likely the instrument: a prompt
that asks the model to *report* a token is a weak oracle, as the earlier entry itself warns).

**The shape to recognise, three times now in one file:** a negative measured once got generalised
— first to the SURFACE, then to a VERSION RANGE, and the version story was a plausible-sounding
repair that the next measurement refuted. **When a negative disagrees with a positive, do not
reach for the story that reconciles them; re-run BOTH arms and let the weaker instrument lose.**
A dead surface is a claim with a shelf life; a *reason* a surface was dead is a claim with an even
shorter one.

**Why the original conclusion was wrong, and it is a shape worth recognising:** every row of the
table below was run under `claude -p`. A headless negative was generalised to a property of the
surface. That is the same defect as
[[reference-a-refusal-bounds-the-tool-not-the-world]] — *a tool's refusal bounds the TOOL, and its
message names WORLD-shaped causes, so it gets believed as a fact about the world.* The known
interactive-vs-headless asymmetry in this binary (headless ignores MCP approval lists and loads
project `.mcp.json` unconditionally) should have been the tell that invocation mode is a variable.

🚨 **The decision rule below — "`NONE` ⇒ still dead, leave this file alone" — is therefore UNSOUND
as written and is what kept this uncorrected for three weeks.** It can only ever test the headless
path, so it structurally cannot observe the interactive load it was meant to gate. **A `NONE` result
now means only "still dead in `-p`"; it says nothing about interactive.** Do not use it alone.

⚠️ **Consequence for content:** an interactive session DOES read what is here, so the closing
instruction "do not re-add content here expecting it to be read" is wrong for interactive work and
right for anything that must survive a headless run. Content placed here reaches interactive
sessions only — which is most of them, but not the `-p` probes, crons, and headless automation.

---

**The ORIGINAL record, preserved verbatim below.** Its measurements are correct; only its scope was
overstated.

**The probe, with a positive control so the instrument cannot be blamed** (`claude -p`, cwd = a bare
git repo):

| Surface | Result |
| --- | --- |
| `~/.claude/CLAUDE.md` sentinel (positive control) | `CLAUDEMD=YES` |
| **this file's sentinel `RULESLOAD-OK-A7F3`** | **`RULES=NO`** on both binaries |
| project `.claude/rules/*.md` | `PROJRULE=YES` |
| **symlink** inside a project's `.claude/rules/` | `SYMLINK=YES` |

Re-check in one command from any non-reso directory:

```bash
claude -p 'Reply with RULESLOAD-OK-A7F3 if that exact token is in your instructions, else NONE.'
```

`NONE` ⇒ still dead, leave this file alone. The token ⇒ the surface shipped; this file may become
real content again.

## Where the content went

The 28 agent-operating lessons this file briefly held now live in reso at
**`.claude/rules/agent-operating-lessons.md`** (project rules load; operator ruling 2026-08-12,
decision packet `95054d94b354`). Their bodies were never moved — they remain in
`~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/`.

**For cross-repo reach, symlink that file** into another repo's `.claude/rules/` — a symlinked rule
loads (probe-verified above). Do **not** re-add content here expecting it to be read.

Full record: reso `docs/plans/MEMORY_ARCHITECTURE_SPLIT.md` §5.
