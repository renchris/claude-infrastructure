# A test double's output is indistinguishable from real output in a shared store

**2026-09-21.** Six mock-produced JSONL files accumulated in `~/.claude/autonomy` in a single
afternoon — from hand repros run against a local mock gateway. Same filename shape as a real run,
same row schema, same timestamp ordering, same directory. Two separate consumers read them:

- The anchor picker took the newest non-empty rank run. That was a **5-row mock**, newer by name
  than the real 140-row run, whose every row named a fixture file absent from disk. All five failed
  the resolution test and the tool refused with *"no weak-incumbent anchors"* — **a true sentence
  about the file it chose and a false one about the machine**, which held 22 good anchors one file
  down. That cost a debugging detour.
- `cc-jev status` reported *"8 verdict(s)"* over a mock pass.

## The rule

**When a tool can be pointed at a test double, the ROW must record which one it was pointed at —
written at the moment of the call, from the fact that settles it: the URL, socket or endpoint the
call actually went to.** Not the filename, not the directory, not a flag the caller might forget.

```sh
jev_is_mock() { case "${CC_JEV_BASE_URL:-}" in *127.0.0.1*|*localhost*|*'[::1]'*) return 0;; *) return 1;; esac; }
```

Consumers then refuse mock rows explicitly. **Do not rely on a downstream sanity check to filter
them**: the resolution test here (`[ -f "$MEM/$f" ]`) looked like it would, and a mock row naming a
file that *happens* to exist passes it silently. Provenance needs its own check because it is a
different question from validity.

## Why the obvious fix is the wrong one

The first thing I reached for was sorting them out by eye — *do these filenames look like
`alpha.md`?* That worked once, on six files, and it is a **judgment applied by hand to a store that
grows**. The second run of it found four more. Any rule whose enforcement is "someone notices"
fails at exactly the moment the store is large enough to matter.

## The companion half: what to do about rows that predate the marker

Mark them **UNKNOWN, never assumed real.** A run without provenance cannot say what it was, and a
consumer that guesses will guess in the "it's fine" direction — the one that costs the operator the
work. `cc-jev status` says `completeness UNKNOWN (run predates the plan stamp)` rather than
dividing by an invented denominator, and the batch refuses to resume an unstamped run at all:
*cannot prove it was the same experiment* is not *it was*.

## The generalisation

This is not about mocks specifically. It is about any tool with a **dev/prod, staging/live, or
dry-run/real switch that writes to a shared location**. The switch is ephemeral — an env var, a
flag, a `--dry-run` someone typed once — and the artifact is durable. If the artifact does not
carry which side of the switch produced it, then every later reader is doing archaeology, and the
archaeology is wrong in the direction of treating rehearsal as fact.

## Companions

- [[a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool]] — the inverse leak: the
  fixture's *reach* escaping into the machine. This one is the fixture's *output* escaping into
  production.
- [[ranker-surfaced-row-may-already-hold-the-right-state]] — a queue pointing at a dead row is
  often the consumer ignoring a field. Here the field did not exist yet.
- `scripts/jev/promote-memory.sh`, `bin/cc-jev`, `scripts/jev/jev-batch.sh` — the three consumers,
  and `hooks/lib/jev.sh::jev_is_mock` the one definition.
