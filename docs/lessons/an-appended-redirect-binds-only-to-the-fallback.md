# A harness that appends a redirect to your source block imposes a SHAPE contract on it

**Found:** 2026-09-17, landing the propose-goal polarity fix. Cost one full `ship-land` gate run
(~8 min) and a red that named a size assertion while the defect was not about size at all.

## The rule

`cmd … || fallback` is a list, and a redirect appended to a list binds to its **LAST command only**.
So when a test extracts your source block verbatim and re-runs it with ` > "$file"` appended, the
`||` idiom silently splits: the fallback's output goes to the file, and the real command's output
goes to **stdout**. Inline the block is correct; under the harness it is not.

**Any emitter whose block a test re-runs verbatim must be ONE command.** Resolve the branch before
the emit, not inside it.

## What it looked like

`tests/idl-record-size.bats` greps `scripts/autonomy-sweep.sh` for every `log_idl <disp> "$(…)"`
block, rebuilds it as a standalone script with ` > "$1"` appended, and asserts the resulting record
is under the writer's 4000-byte refusal threshold. My arm emitted:

```sh
log_idl propose-goal-arm "$(jq -nc --arg rc "${_pgw_rc:-absent}" '{…}' 2>/dev/null
  || printf '{"propose_goal_verdict":"unparsed"}')"
```

`jq` succeeded, so `printf` never ran, so the file stayed **empty** and jq's JSON went to stdout.
`$output` became two lines and the assertion died:

```
[: {"propose_goal_rc":"absent","propose_goal_verdict":"watcher-absent"}
634: integer expected
```

**The error message is the trap.** It is emitted by a *size* assertion, cites a byte count, and says
"integer expected" — three signals all pointing at the number. The number was fine (269 B after the
fix). The defect was that `$output` had a second line, and nothing in the message says so.

## The cure

```sh
case "${_pgw_rc:-absent}" in
  0) _pgw_verdict="FLIPPED-paged" ;;
  …
esac
log_idl propose-goal-arm "$(jq -nc --arg rc "${_pgw_rc:-absent}" --arg v "$_pgw_verdict" \
  '{propose_goal_rc:$rc, propose_goal_verdict:$v}')"
```

One command, no list, so the appended redirect covers all of it. 269 bytes, green.

## Two things worth carrying

**A shared ratchet can convict you for a reason its own message cannot express.** This suite exists
to bound record SIZE (an over-4096 record is not appended atomically). It has no vocabulary for
"your block has the wrong shape", so it reported the shape bug in size language. When a ratchet's
message does not fit what you changed, read the assertion's *inputs*, not its stated subject.

**The neighbouring emit has the same shape and is not convicted.** `log_idl unfired-briefs` also
ends `… || printf '{…}'`. The suite skips any emit whose extracted script exits non-zero
(`if [ "$status" -ne 0 ]; then continue; fi`), so whether the trap fires depends on whether your
command happens to succeed under the harness. **A green neighbour is not evidence your shape is
safe** — it may only be evidence that it failed earlier and got skipped.
