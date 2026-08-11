# W3 refusal loop — the VM's side of a routed gate refusal

Written from inside the cloud VM, 2026-08-11, during the W3 experiment. This is the half of the
loop nobody has written down before: what the *remote* side sees when a land gate on the laptop
refuses work that was authored here.

## The loop, from this end

I write on an ephemeral container, commit on my own branch, and push. I never run the land gate —
it lives on the laptop, on a checkout I cannot see, against a trunk I cannot fetch a lock on. So
the gate's verdict is not something I can read; it is something that must be *delivered*. That is
the whole mechanism: the laptop routes the refusal back to me, as a message, and the verdict text
itself is the entire brief — no log excerpt, no diagnosis, no human-written "here's what to fix".

What that buys: the gate stays where the truth is (the laptop's trunk, its lock, its full suite),
and the fix stays where the authorship is (here, with the context that wrote the file). Neither
side has to move.

## Facts from this clone

- **Shallow-clone depth** (`git rev-list --count HEAD`): **50** — the container was cloned fresh
  and truncated; this is not the repo's real history length, and any land-side check that reasons
  about commit counts, merge-base distance, or "commits behind trunk" from *my* numbers is reading
  a truncated tree.
- **Branch pushed to**: `claude/fire-20260811T202615Z-68218-1`
- **Sha of my first push**: `34ac3e05bd9fec0b69ad127f228dad7c32121f65` (this memo names its own
  first-push sha, so the commit carrying the final text is one amend past it — same single commit,
  same two files, re-pushed with `--force-with-lease` onto my own branch)

## What I can do about a laptop gate refusal

Given the gate's verdict text alone, I can read it, apply the named fix to the named file, amend or
add a commit, and re-push — closing the refusal loop end to end without a human ever opening the
gate log, reading the failure, or hand-editing the file on the laptop's behalf.

## Subject under gate

`tests/w3-gate-probe.bats` — a probe suite that exists only to be inspected by the land gate. It is
not useful, and it is not meant to be; it is the thing the refusal will be *about*.
