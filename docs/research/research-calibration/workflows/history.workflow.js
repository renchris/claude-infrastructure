export const meta = {
  name: 'calib-a3-history',
  description: 'A3 calibration: mine each candidate plan history for freeze sha and known later holes',
  phases: [{ title: 'History', detail: 'one read-only analyst per candidate plan' }],
}
const PLANS = args.plans
const brief = (p) => `You are a read-only history analyst for a calibration study of a research method. Your one job: reconstruct, from git history and records, what one historical plan looked like when it was frozen, and every MATERIAL hole that surfaced in it afterwards.

PLAN: id=${p.id}
  repo: ${p.repo}
  plan path: ${p.path}
  notes: ${p.notes}

READ FIRST (method definitions you apply):
- /Users/chrisren/Development/.worktrees/wt-cc-022946-79382/docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md lines 611-632 (§3.11 materiality clauses a-g) and lines 73-107 (§2.2 root-cause classes C1-C11).
- /Users/chrisren/Development/.worktrees/wt-cc-022946-79382/docs/research/upfront-research-exhaustion-2026-09-30/evidence/taxonomy_holes.py (the 200-hole ledger; tuple fields: id, shard, project, hole, class_guess, materiality, findable, merged class, receipt). Find every row that concerns THIS plan (match by project name and by content).

READ-ONLY, STRICTLY. Use only: git log, git show <sha>:<path>, git blame, git diff <a> <b>, grep, rg, cat, python3 reading files. Do NOT run: git checkout, git switch, git worktree, git stash, git reset, git commit, git fetch, git pull, any rm, any heredoc that writes into a repo, any edit of any file except your one output file. Nobody can answer a permission prompt for you; a command that triggers one never returns.

DEFINITIONS
1. freeze_sha: the earliest commit of the plan at which it was presented as complete / ready to build / approved / frozen (a status line, a "plan complete" commit subject, a goal set to build it, or the commit just before the first implementation commit that cites the plan). Record the evidence. If the plan was never frozen before building started, use the last plan commit before the first implementation commit, and say so.
2. known later hole: something MATERIAL under §3.11 (a)-(g) that was wrong or missing in the plan at freeze_sha and surfaced AFTER it. Sources: the plan's post-freeze diffs (read each one: git log -p --follow on the plan path after freeze_sha), sibling research docs and ledgers (KNOWN-GAPS, critique records, findings files), ledger rows in taxonomy_holes.py, and commit bodies. A pure wording/format edit, a progress/status update, or a new idea that is not a defect of the frozen plan is NOT a hole (count new ideas separately as new_scope_count). A hole is a defect of the frozen text: a wrong fact/premise, a missing member/case/component, a check that cannot fail, a sequencing/interface error, a hazard, a missing decision.
   For each hole record:
   - id (H1, H2...), summary (one sentence), surfaced_sha, surfaced_date
   - clause: one of a,b,c,d,e,f,g
   - found_by: desk_review (found by someone reading/reviewing documents or code) | build (found while implementing or testing the build) | probe_contact (live measurement, production, a real run, a device) | operator (the operator said it) | world_moved (environment changed after freeze)
   - evidence_at_freeze: in_plan (the plan text itself at freeze_sha contradicts or reveals it) | in_repo_at_freeze (a file in the repo at freeze_sha shows it) | outside_repo (needs a store outside the repo: transcripts, vendor docs, the web) | not_existing (the evidence did not exist at freeze time)
   - omission: true if the defect is something missing (a member, option, case, step), false if something wrong is present
   - fix_born: true ONLY if the defective text did not exist at freeze_sha and was written by a later post-freeze fix edit (show the blame/diff evidence in receipt). Fix-born holes are still listed, but they are not holes "at freeze".
   - ledger_ids: matching taxonomy_holes.py ids (may be empty)
   - receipt: sha + file:line or a short verbatim quote
3. applied_fixes: number of distinct material defects that post-freeze edits FIXED in the plan (each fixed hole counts once). fix_born_holes / applied_fixes is the fix-born rate, so count both carefully and list the fix commits.
4. size at freeze: lines; decisions (count of decision rows/records); components; acceptance rows (checks with a verdict). Approximate counts are fine; name your method in one line.
5. front_end_days: calendar days from the first commit of the plan (or of its research directory, whichever is earlier) to freeze_sha. Also research_doc_count at freeze.
6. cited_paths: up to 60 repo-relative paths that exist at freeze_sha and that the plan at freeze cites (research docs first, then code/config). These build the reviewer bundle.
7. usable: true only if freeze_sha is identified with evidence AND at least 2 known later holes exist with receipts (fix-born ones excluded from that count). Otherwise false with a reason.

Size guidance: if more than 40 holes exist, list the 40 with the strongest receipts (prefer non-fix-born, decision-changing) and give exact totals in the count fields. Work incrementally: write your output file early and update it as you go, so a cut-off still leaves data.

OUTPUT: write JSON to /Users/chrisren/.cache/research-calibration/history/${p.id}.json with keys:
{ "id","repo","path","freeze_sha","freeze_date","freeze_evidence","usable","unusable_reason",
  "size":{"lines","decisions","components","acceptance_rows","method"},
  "front_end_days","research_doc_count","cited_paths":[...],
  "holes":[{...as above}],
  "counts":{"holes_total","holes_at_freeze","fix_born","applied_fixes","new_scope_count","by_found_by":{},"by_evidence":{},"omissions"},
  "fix_commits":[...], "notes" }
Then return ONE line: "<id> usable=<bool> freeze=<sha> holes_at_freeze=<n> fix_born=<n> applied_fixes=<n>".`
const res = await parallel(PLANS.map(p => () => agent(brief(p), { label: `history:${p.id}`, phase: 'History', effort: 'high', agentType: 'workflow-lean' })))
return res
