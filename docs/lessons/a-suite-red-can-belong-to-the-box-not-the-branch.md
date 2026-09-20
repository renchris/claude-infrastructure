# A suite red can belong to the BOX, not the branch — and the store may already name it

**2026-09-20 · claude-infrastructure · found while landing cc-backlog `7f2e2244f715`**

## The shape

`tests/anti-deference-nudge.bats` went RED on trunk with **no code change on either side**.
Eight failures, every one of them a `silent on ...` case. A/B against pristine `origin/main`
reproduced all eight identically, so it was never any lander's diff.

The suite tests the LEXICAL deference tells, but never pinned the SEMANTIC (Jev) arm. That arm's
four preconditions (`hooks/lib/jev.sh:118-121`) are read from the **ambient machine**: `CC_JEV != 0`,
a key from env *or* `agent-secrets`, `scripts/jev/evaluate.mjs`, and `node_modules/ai`. Three were
already true; `node_modules/ai` was installed at 22:15 and completed the conjunction. So the suite
passed or failed on **what happened to be installed**, and it flipped fleet-wide — it sits in the
direct own-set of any diff touching `hooks/anti-deference-nudge.sh`, so every such land was refused
on a red that belonged to the box.

## The part I got wrong, which is the instructive half

I concluded the arm was FIRING on the no-tell path — which *is* the suite's "silent" population, so
the story fit perfectly. It was false, and a perfect fit is exactly when to measure instead.

Measured on a no-tell fixture: **stdout is 0 bytes**, exit 0, and the hook's own IDL line reads
`disposition=abstained reason=no-tell`. The arm never fires; the hook is correct throughout. What
fails `[ -z "$output" ]` is the arm's node child writing

```
egress allowlist active (proxy 127.0.0.1:NNNNN; N rule(s)) — non-allowlisted hosts refused
```

to **STDERR**, which bats `run` MERGES into `$output`. The hook said nothing and was convicted of
speaking. That pass-through is deliberate (`jev.sh:142-144`), citing the repo's own
`suppressed-stderr-turns-a-failed-command-into-a-zero` lesson — so suppressing it in the lib is
precisely what that lesson forbids. The over-broad assertion is in the TEST.

## Rules

1. **A suite whose subject shells out inherits every precondition of that child as a hidden input.**
   Before blaming a diff for a red, enumerate what the subject *executes* and ask which of its
   preconditions are ambient. A conjunction that is 3/4 true is one `npm install` from flipping.
2. **`bats run` merges stderr into `$output`, so `[ -z "$output" ]` asserts more than silence** — it
   asserts the whole process tree is silent on both streams. When the channel under test is stdout,
   say so: `run --separate-stderr`, or redirect in the helper.
3. **A conclusion that explains the failing set *too* neatly deserves one measurement before it
   ships.** Split the streams and read the subject's own disposition record; both were one command
   away and both refuted me.
4. **Grep the backlog for the symptom BEFORE diagnosing it.** Row `7eb22985f778` already carried the
   correct diagnosis and warned that three sessions had lost turns to it. I landed the right fix with
   the wrong reason attached, then had to land a correction. The store is an instrument; read it
   first.
5. **A per-suite `setup()` pin is not a global kill switch.** The objection "CC_JEV=0 trades 8 reds
   for 2" was true of a GLOBAL `CC_JEV=0` and false of a `setup()`-scoped one, which cannot reach the
   arm's own suites — they set their own env. Check the SCOPE of a remedy before inheriting the
   objection to it.

## Evidence

- Landed: `e6100e316` (the original item), `69564f432` (the pin), plus the correction commit.
- A/B: 8 not-ok on trunk's own file and on mine, identical test names.
- Red-proof: 8 not-ok → 49/49 ok, same box, minutes apart; `jev-anti-deference-arm` +
  `jev-evaluate` 27/27 green beside the pin.
