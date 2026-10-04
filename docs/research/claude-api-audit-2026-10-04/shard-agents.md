# Prompt audit — shard "agents" (agents/*.md, 5 subagent definitions)

## Assumptions (Step 0)

- **Scope:** `agents/deep-research.md`, `agents/deep-research-sonnet.md`, `agents/frontier-derivation.md`,
  `agents/research-decomposition-critic.md`, `agents/workflow-lean.md` (frontmatter + bodies, HTML comments included).
  Not read: settings/hooks/credentials. Cross-shard conflicts are flagged, not edited.
- **Target models:** each file is audited against the model it pins: `opus` alias = Claude Opus 5.5
  (`deep-research`, `frontier-derivation`; the lead may pass `fable` = Fable 5.1), `sonnet` alias =
  Claude Sonnet 5.5 (`deep-research-sonnet`, `research-decomposition-critic`), unpinned `workflow-lean` = the
  caller's model (Opus 5.5).
- **Cost frame:** quota, not dollars (Max subscriptions). The per-spawn first-turn prefix is the dominant
  lever for these files, since `deep-research` is the most-spawned agent (302 spawns in the omitClaudeMd census).
- Hunks were checked to apply cleanly, all 17 together, to a scratch copy (`/tmp/capi-audit/applied/agents/`).
  `agents-omit-claudemd.bats` and `research-zero-allowed-prompts.bats` assertions were re-checked by hand on the
  patched copy: contract markers and "zero is a valid answer" lines are present, and descriptions are unchanged.
  The bats runner itself deferred (machine load), so **no bats verdict exists**.

## Summary

Highest-impact items:

1. **`deep-research-sonnet` has to deliver its report through a Bash heredoc (agents-01/02).** It has no Write
   tool, so the prompt says "create it with one Bash heredoc". That is the failure `edec03003` (2026-08-26)
   measured and fixed only for `deep-research`: 2 of 15 agents died mid-heredoc. The heredoc instruction was
   added on 2026-09-22 to describe the gap instead of closing it. Fix: add Write and Edit, and adopt
   deep-research's delivery and never-overwrite wording.
2. **`deep-research` and `deep-research-sonnet` load the 11.2k-token skill listing on every spawn (agents-01/03).**
   They carry the `Skill` tool. The repo measured that "no `Skill` in an agent's tools ⇒ no skill listing"
   (token-efficiency-2026-09-23/BASELINE.md:45, 11.2k tokens by count_tokens), and that agents call Skill in
   only 0.2–0.8% of contexts (commit 8febac125). Dropping it is the largest remaining per-spawn prefix cut
   after omitClaudeMd.
3. **The return contract contradicts the operating contract in both deep-research agents (agents-04/05).**
   The 2026-09-22 operating contract says "Only the file is delivered; return a short pointer". The 2026-07-25
   Return Contract still sizes the *return* at 3-15K, and treats file delivery as a conditional ("If lead's wave
   is N > 25 … OUTPUT_TO"). The skill now makes field-7 file delivery mandatory on every brief, so the newer rule
   wins. Fix: apply the sizing to the file, and make the manifest the return.

Counts: Group 1: 5 (agents-07, 08, 09, 10, 17) · Group 2: 8 (agents-02, 04, 05, 06, 11, 12, 13, 14, plus the
15 comment correction) · Group 3: not applicable (no tool descriptions authored here) · Group 4: 3 (agents-01, 03, 16).

## Findings (highest confidence first)

| ID | Location | Pattern | Why obsolete | Conf. | Action |
|---|---|---|---|---|---|
| agents-01 | deep-research-sonnet.md:8 | G4 tools list; G2 sibling fix not carried | No Write tool, so delivery runs through a heredoc, the failure measured in edec03003. `Skill` loads an 11.2k-token listing per spawn. | High | rewrite tools line (+Write, Edit, −Skill) |
| agents-02 | deep-research-sonnet.md:113-117 | G2 volatile/contradicted; fragile op | Depends on 01. The heredoc and `>>` instructions become wrong once Write and Edit exist; use deep-research's wording. | High | rewrite |
| agents-04 | deep-research.md:233-248 | G2 in-file contradiction | Operating contract (2026-09-22) = file plus pointer. Return Contract (2026-07-25) = 3-15K return, with file delivery only at N>25. The skill's field 7 is mandatory on every brief. | High | rewrite (sizing → file, return → manifest) |
| agents-05 | deep-research-sonnet.md:137-144 | G2 in-file contradiction | Same conflict, and "return <3K" can never be false for a pointer return. | High | rewrite |
| agents-06 | deep-research.md:177 | G2 in-file contradiction | "past 800K context" sits beside "Hard ceiling 500K" (line 92); a leftover from the retired 500-800K prescription. | High | rewrite |
| agents-13 | research-decomposition-critic.md:29 | G2 path that no longer resolves | `research-subagents.md` names no file. 351d910e8 fixed the six `~/.claude/rules/research-subagents.md` refs and missed this bare one; line 22 of the same file has the right path. | High | rewrite |
| agents-03 | deep-research.md:7 | G4 tools / cost | `Skill` loads an 11.2k-token listing on every spawn of the most-spawned agent; Skill-call rate in agents is 0.2-0.8%. Skill docs stay reachable by Read (the body already cites SKILL.md paths). | Med-High | rewrite tools line (−Skill) |
| agents-12 | deep-research-sonnet.md:35-50 | G2 contradiction; 1d fossil | The table says "synthesis-and-citation → Sonnet (you)", but the same file's measured standing says Sonnet *loses* synthesis 5-0-1. The agent acts on the table ("routing error … stop"), even though the file calls it "kept for its history". In a probe-certified Workflow a self-declared misroute wastes the slot. | Med | rewrite (routing is the lead's; keep the multi-hop flag) |
| agents-11 | deep-research-sonnet.md:13-19 | 1d / G2 history + version pins | The pre-5.5 $/insight rationale (MALBO, "Opus 4 lead + Sonnet 4 workers", "2.1.284") is contradicted by lines 21-34. | Med | rewrite |
| agents-07 | deep-research.md:107-110 | 1d migration-relative phrasing | "The previous 500-800K prescription…" is a diff against a prompt the model never saw. | Med | rewrite |
| agents-08 | deep-research.md:275-278 | 1a "do not stop early" + 1f numeric floor | The 3K floor pushes padding and contradicts the file's own "zero is a valid answer" stance. The under-exploration guard survives at lines 102-105. | Med | rewrite |
| agents-09 | deep-research.md:134-145 | G2 history narrative | About 12 lines of archaeology on every spawn; the rule and its Why (runaway bound, do not "fix") stay. History is kept via a commit pointer (f21ad9d4a). | Med | rewrite to pointer |
| agents-10 | deep-research.md:167-171 | G2 volatile; text the reader cannot use | Self-described as "not callable from inside a subagent"; `--teammate-mode tmux` concerns teammates. | Med | remove |
| agents-14 | frontier-derivation.md:9 | G2 volatile figure | "~2×" contradicts the repo's "roughly 2-5x … re-measure before quoting" (CLAUDE.global.slim.md:134), and is false when the lead does not pass fable. | Med | rewrite |
| agents-15 | frontier-derivation.md:85-90 (comment) | G2 stale fact | "Silently falls back to Opus 4.8" no longer holds: on Fable 5.1/Opus 5.5/Sonnet 5.5, `reasoning_extraction` declines are not retried on a fallback. Correction appended, history kept. | Med | add CORRECTED line |
| agents-16 | deep-research.md:4 | G4 effort config | Unpinned, so it inherits the lead's rung (xhigh/max leads → xhigh/max workers). opus55_research=high (model-config.yaml:1379, DRACO +1.7 for ~2.5× at xhigh). Frontmatter effort is honoured on the Agent path (probe-effort-binding case c). Precedence against a Workflow per-call effort is unmeasured. | Med | needs-measurement |
| agents-17 | deep-research.md:86-90 | 1d retired-model evidence | The 400K ceiling and 150-250K target rest on Sonnet 3.5 / Opus 4.6 curves; model-config.yaml:197 lists Opus 5.5's long-context curve as unknown. | Low | needs-measurement (hunk restates honestly) |

## Flags (no edit proposed)

- **Cross-shard conflict:** `skills/research-subagents/SKILL.md:958-962` ("Recursion Regression", 2026-06-19)
  says hierarchical fan-out is available and preferred on 2.1.183. `agents/deep-research.md:112-171` (2026-09-08)
  says recursion is off by our own `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`. The agent text is newer and
  correct. The skill shard should rewrite its section. The skill also still carries "fill 3K" and "N > 25"
  return-sizing text that matches agents-04/08.
- `deep-research.md:7` lists `Agent`, which the depth-1 cap makes unusable. It is harmless, since the harness
  withholds the tool, and it is the re-enable path, so it is kept.
- The Brief-Drift block (deep-research.md:28-82) uses heavy pressure ("non-negotiable", "Do NOT proceed").
  It is kept because it is backed by a measured incident (12 of 13 workers complied with a drifted brief) and
  guards a real scope constraint.
- The long-commands paragraph is repeated in 4 files. That is working redundancy: each agent loads alone.
- `research-decomposition-critic` description "~$0.05 cost" is a dollar figure in a quota-only fleet. Low value;
  the description is length-pinned by bats case 3.
- `workflow-lean.md`: clean.

## Verification owed (Step 7)

- 01/03: one deep-research spawn before and after; read the first-request token count (`cc-token-ledger`).
  Expect about −11k. Also confirm no brief in the corpus depends on the Skill tool (grep subagent transcripts for
  `"name":"Skill"`).
- 16: probe Workflow `agent({agentType:'deep-research', effort:'xhigh'})` against `effort: high` frontmatter,
  and read the request's effort. Pin only if a per-call effort still wins; otherwise the adversarial xhigh slot
  is lost.
