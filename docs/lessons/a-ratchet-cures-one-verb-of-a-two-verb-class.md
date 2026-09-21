# A ratchet cures one VERB of a two-verb class, and its green is then read as class-wide safety

**2026-09-21, item 8dc9ff906d4b.** A post-land RED took down four tests in
`tests/handoff-remote-pane-term.bats` and was green in every hand-check. The cause was a class this
repo had already found, already explained in two files, and already built a whole-tree ratchet for —
and the ratchet was green throughout, correctly.

## The mechanism

Darwin caps `sun_path` at 104 bytes, and the cap applies to **the string handed to the syscall**, not
to where the file ends up. That is a property of the *address*, so it binds `connect(2)` exactly as
it binds `bind(2)`.

`scripts/handoff-fire.sh`'s `kitty_socket_accepting` connected by absolute path. Under a session
`$TMPDIR` that path is comfortably short; beneath postland-verify's corpus TMPDIR
(`$TMPDIR/postland-run.XXXXXX`) it measured **107 bytes** against the cap, and `connect()` raised
`AF_UNIX path too long` — over a socket that was listening, reachable, and connected fine from its
own directory by basename. The function's fail-closed `except` then spent that exception as a clean
"not accepting", so the classifier reported `no-socket` over a socket it had never reached, and the
`timeout` sub-state the function exists to name became **unreachable inside the one gate that judges
this tree**.

## Why every existing defence was green

- **The fixture was not the victim.** `mksock` and `mklistener` already `chdir` + bind the basename —
  cured on 2026-08-06 by item e1d43f93da19, after the absolute-bind form took a whole sibling suite
  down inside postland. So the only absolute-capable address left in play was the **subject's**.
- **`scripts/test-afunix-path-lint.sh` was green, and truthfully so.** It is a genuine whole-tree
  ratchet for this exact cap, it carries a *"KNOWN LIMIT, stated rather than hidden"* block, and it
  even warns "do not read a green here as 'no oversized socket path anywhere'". But it scans
  **`bind(` only, in `tests/` only** — two axes, and the incident sat outside both.

That is the whole lesson. The class had been identified, explained, and enforced; the enforcement's
*scope* was the uncovered part, and scope is invisible precisely because the tool reports clean.

## The rule

When you cure a resource-limit class with a ratchet, **the ratchet's scope is itself a claim, and it
has two axes that fail independently**:

1. **The VERB.** Most limits on an address, handle, or name are symmetric across a verb pair —
   `bind`/`connect`, `open`/`create`, `listen`/`accept`, read-side/write-side. A lint written from an
   incident encodes the verb *that incident used*. Ask: what is the mirror verb, and who calls it?
2. **The POPULATION.** A lint born from a fixture bug scans fixtures. But the party that performs the
   mirror verb is usually the **subject**, which by construction does not live under `tests/`.

Polarity is what makes this expensive rather than merely untidy. Production values are short
(`/tmp/kitty-<pid>`; the only other AF_UNIX connect in this tree resolves to 57 bytes off `$HOME`),
so the defect is green on every box, in every hand-check, and under the re-run command the gate
itself prints — and red **only** inside the gate whose verdict everyone waits on.

## Method notes that cost time here

- **Do not diagnose a post-land RED from the failing test's name.** The row cited one test; the TAP
  showed **four**, all sharing one fixture helper. The shared helper was the signal, not the title.
- **Reproduce by moving the environment variable, not by reading.** Re-running under
  `TMPDIR=$(mktemp -d "${TMPDIR%/}/postland-run.XXXXXX")` reproduced all four failures exactly and
  took one command. A positive control then separated *cause* from *correlation*: the identical
  socket, absolute connect vs `chdir`+basename connect, one fails and one succeeds.
- **`rc=75` from `bats` is cc-bats SHEDDING, not a red.** An empty TAP with no plan line is a
  non-verdict. The land gate is admission-exempt (`CC_BATS_MAX_ROOTS=0`); a hand re-run is not.

## What was deliberately NOT done, and why it is recorded rather than enforced

The lint's scan was **not** widened to production connects. The population is zero (one site, cured
by `7a8e2d85ee8b`), the value is prospective, and that lint **blocks a land for every session on the
box** — a real cost against a speculative benefit. The missing axis was written into the lint's own
stated-limits block instead (`8ef17272f`), so the next reader inherits the finding without the next
lander inheriting the risk. **A second production site is the signal to widen.**

## Companions

- `docs/lessons/a-gate-s-surface-is-not-its-traffic.md` — a gate's coverage proves reachability on the
  surface it names, never that the work still crosses it. This is its sibling on a different axis:
  the surface is right and the *verb* is wrong.
- `docs/lessons/a-generator-fix-needs-its-population-enumerated-and-the-incident.md` — enumerate the
  population before calling a generator fixed.
- memory: `enforcement-must-live-at-the-chokepoint`, `unfixtured-sensor-executes-the-deployed-subject`.
