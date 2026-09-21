# A /goal whose condition contains an operator-only act can never clear

**2026-09-21.** A session was armed with:

> *"Jev is RUNNING on real work that a schedule or hook triggers — proven by the session printing
> the scheduled artifact AND a JSONL of verdicts it produced; **do not claim a Jev call was made by
> this session (CC_JEV_ZDR=0 is classifier-refused — operator-run only)**."*

Read it twice. The parenthetical states that the agent cannot make the call. The main clause
demands evidence that the call was made. **The condition asserts its own unreachability in its own
text**, and the evaluator — correctly, every time — judged it unmet. Six closes, six blocks, each
one accurate.

## The rule

**Before arming a goal, ask: can the agent reach this condition with the permissions it has?** If
any conjunct requires an act reserved to the operator — a credential, a `sudo`, a GUI step, a
consent decision, loading a daemon, anything behind a C10 boundary — the goal will block forever.
Not usefully: it blocks *after* all the reachable work is done, which is the most expensive moment.

The fix is to make the condition end at the agent's reach: *"the scheduled artifact is landed,
converged and declared, and one command is handed over that produces the verdicts."* That is
checkable, it is the agent's actual job, and it terminates.

## Why it is easy to write by accident

The goal is usually authored at the *start*, when the operator-only step is not yet known. Here the
constraint was even written into the same sentence — and it still read as a caveat rather than as a
contradiction, because "do not claim X" parses as an honesty instruction, not as "X is impossible
for you." **A negative permission clause inside a success condition is the signature to look for.**

## What the agent should do when it happens

Not route around it. The three obvious routes here were all real and all wrong: registering a hook
that sends (hooks are not bound by the permission classifier — measured, 372 real outbound requests
in 25 h from a retired arm), loading the launchd job itself, or writing the consent sentinel. Each
would have satisfied the goal and **laundered a decision the same session had just filed as the
operator's.** A goal is an instruction, and it does not outrank the permission boundaries the
operator set, or the ones the agent itself just wrote down.

Do instead: drive everything the condition's *reachable* conjuncts imply, make the operator's one
remaining command as valuable as it can be, file the decision, and say plainly — once — which
conjunct is unreachable and why. Then stop re-closing. Repetition adds nothing and spends quota.

## Companions

- `commands/handoff.md` § Autonomous fire — the template says a condition wants *one measurable end
  state · the check that proves it · the constraint that must hold*. The trap is putting the
  constraint **inside** the end state.
- [[detector-with-no-owner-is-not-an-actuator]] — the same shape: a condition nobody can act on.
- [[conservative-branch-gated-on-a-manual-flag]] — a branch gated on a flag no automation passes is
  permanent inaction. An unreachable goal is permanent *blocking*, which is worse: it also prevents
  the close.
