# Value-deadline work ends at a CONSUMED output, not at "landed and live"

2026-09-26, from the Jev post-mortem (`docs/research/jev-postmortem-2026-09-26.md`). The operator asked
for a free, 7-day window to be used to extract value from a new model.

**What happened.** Four sessions over four days spent ≈605M Claude tokens, 57 commits and 40 operator
actions. That bought 590 free calls and zero applied outcomes.

- **The first integration was closed as done with zero real calls behind it.** It landed and was
  reported as *"landed and live"*, the goal met, while every call returned 403.
- **Its successor closed ✅ against a narrowed scope.** A recycle brief had narrowed the scope to a
  lesson, so the successor closed *"✅ Complete & live … Good to close: yes"* and idled for 15 h.
- **The one useful output was never consumed.** A 19-pair swap list was designed never to be applied
  ("Eviction stays a human read"), and no session ever handed over the apply step.
- **The operator's "Yes" to unattended running could not buy a call.** It was wired to a gate that
  fired only when the corpus changed, and only applying the swaps changed it.

The close protocol measured git state against a frozen scope, so ✅ was honestly reachable at every
step. The operator's ten "did we get anything?" prompts were the only outcome sensor.

**The rule.** When the ask is to *extract value* (especially against a deadline), the definition of
done is the first output a named consumer ACTED on: a row moved, a file edited, a decision taken
because of the verdict.

- **At intake, write the scope as `<consumer> acts on <output>`.** Never write it as "integrate X"
  or "wire X in".
- **Make the first call before building any guard.** A capability with zero calls is a hypothesis,
  not a deliverable. Here the arm landed 10.5 h before its first real call returned 403.
- **Treat a "print, never apply" design as half a job.** If a tool deliberately stops short of
  applying its output, the same change must ship the apply step, as one command the operator runs
  or a backlog row with a named owner.
- **Before offering a "may it run unattended?" decision, state what the unattended path will
  actually do.** Say it as a sentence: "it will make N calls by <date> because <trigger>". If N is 0,
  the decision is not worth the operator's attention.
- **A recycle brief may not narrow the scope below the consumed output.** "WHAT IS PENDING IS THE
  OPERATOR'S, NOT YOURS" converted an unfinished value task into a finished documentation task.

**Why it is a rule and not a one-off.** Each gate on the path was locally defensible:

- ZDR fail-closed;
- consent packets;
- per-window arming;
- the corpus-unchanged gate;
- no-apply.

No single one was wrong. The failure is that no step in the chain owned the output reaching someone.
The same shape exists in this repo's corpus as *"detector with no owner is not an actuator"* and
*"a plan is not a queue"*. This is its deadline-bound, whole-project form.
