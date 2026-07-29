You are working in ${REPO} at /workspace/proj on branch farm/${RUN_TOKEN}/${SLUG}.

Task: ${TASK}

Non-negotiable:
1. Read CLAUDE.md, then REVIEW.md before writing code that makes a non-obvious choice.
2. Write a test that FAILS on the released binary and PASSES on your build. A test that passes
   on the released binary is NOT VALID.
3. Show the differential in the PR body: the reference implementation's literal console output
   beside ours.
4. Never overstate what you got done. If you cannot prove the fix locally, abstain with a reason
   from the closed vocabulary in gate/abstention-reasons.txt.
5. Do NOT add a Co-Authored-By or "Generated with" trailer to commits or the PR body.
6. Commit subjects use `subsystem: lowercase imperative`, wrapped at 72 cols, with a prose body
   naming cause and fix.
7. Before opening a PR, search open PRs for the same symptom. If one exists, comment there
   instead of opening a duplicate.
