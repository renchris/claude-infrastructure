# Adding an Nth fallback source silently un-seals every fixture that sealed N−1

**The rule.** When a subject gains a new fallback input — another environment variable in a
`${A:-${B:-${C:-}}}` chain, another config path, another default — every existing fixture that
sealed only the *previous* sources stops being hermetic at that instant. The fixture does not
change, is not touched by the diff, and keeps passing for whoever wrote it. It now answers to the
runner's ambient environment instead of to the subject, and the resulting red is a property of the
box, so it is invisible to anyone whose terminal happens not to export the new source.

**Seal every source the subject reads, not the ones it read when the fixture was written.**

## The incident (2026-09-20, claude-infrastructure)

`hooks/session-register.sh` gained a THIRD pane address:

```diff
-pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"
+pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"
```

`tests/session-registry.bats` has an over-widening control — *"a path-unsafe or empty address is
STILL refused (the widening opened no traversal)"* — which loops path-unsafe values through
`env -u ITERM_SESSION_ID CC_PANE_ID="$bad"` and asserts the registry stays empty.

On the **empty** case the chain now falls all the way through to whatever the *runner's* terminal
exports. Under kitty that is a real window id, so a row is legitimately written and the control
fails as `[->1]`. Under iTerm2 or a bare shell it passes. Before the widening the chain had nowhere
left to fall, so the same fixture was sound; the seam opened underneath it.

Measured on one box (kitty, `KITTY_WINDOW_ID=334`), one variable, both arms yielding a real TAP
plan line rather than a bats shed:

| arm | result |
|---|---|
| fixture as landed | `1..37` rc 1, `not ok 27` |
| fixture sealed (`-u KITTY_WINDOW_ID`) | `1..37` rc 0, 0 failures |

and the mechanism directly:

```
env -u ITERM_SESSION_ID KITTY_WINDOW_ID=186 CC_PANE_ID=""  -> pane=[186]
env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID  CC_PANE_ID=""  -> pane=[]
```

## Why the subject was innocent

Falling through a set-but-empty `CC_PANE_ID` is what `:-` did before the widening too; only the
number of addresses grew. Fixing the hook would have been fixing the wrong thing. **When a red
appears in a control whose subject you did not change the semantics of, ask what the subject now
READS that the fixture does not SEAL.**

## Why it is not caught

- The gate attributes by reachability, so it convicts the lander — correctly here, but it names the
  suite, never the ambient variable, and the author may not reproduce it at all.
- The branch's own **new** suite, `tests/stop-failure-marker.bats`, covering the other consumer of
  the same third address, *did* seal all three (`env -u CC_PANE_ID -u KITTY_WINDOW_ID -u
  ITERM_SESSION_ID`). Getting it right in the new fixture is no evidence at all about the edited
  one — they are written at different moments by different reflexes.

## What to do

1. When you add a fallback source to a subject, `grep` the test corpus for every fixture that
   seals any of its siblings, and seal the new one there too.
2. Seal **all** sites in the file, not just the one that is red: the rest are latent by the same
   mechanism and go red the moment a future case passes an empty or unsafe value. Here that was
   7 sites, of which 1 was red.
3. A bats run with no `1..N` plan line is a shed or a refusal, not a pass — assert the plan line
   before believing either arm of an A/B like this one.

Companions: [[hermeticity-ends-where-its-subject-spawns-a-third-tool]] (the same failure when the
subject *spawns* a program rather than reading a variable), [[fixture-shape-hides-address-bugs]],
[[a-suite-red-can-belong-to-the-box-not-the-branch]].

Landed as `7802a283d`; the widening it followed is `d2c712d07`'s branch.
