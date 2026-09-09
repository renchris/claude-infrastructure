# The rotor's 118s, and the "unexplained" verdict flip that blocked the fix

*2026-09-08 · cc-backlog `99dbf659930c` · subject `bin/cc-memory-rotate` · DoD ref `a72bfd477`*

## The answer

**The speedups never changed the rotor's verdict. The measurement harness did.**
`cc-memory-rotate` resolves `../hooks/lib/memory-index-measure.sh` **relative to its own path**.
A patched copy run as a flat scratchpad file has no sibling `hooks/`, so the lib does not load,
`OVERHEAD` stays 0, and `LIMIT` / `ROTATE_AT` / `TARGET` are each **1346 bytes lower** than the
shipped rotor's on this index. That is a different breach decision and a different target — i.e.
a different program — and it is invisible in every diff the blocking note checked, because it
changes neither the hub set nor the cited set.

That is exactly the shape the row recorded: *"changed the verdict from `exhausted eligible=0` to
`moved=34` on a forced breach, unexplained by hub or cited set diffs"*, with the prior session's
own artifacts showing hub 91-vs-95 (the 4 extras — `CLAUDE.md`, `MEMORY.md`,
`DAEMON_FLEET_V2.md`, `MACHINE_CAPACITY_V2.md` — are not index entries and can never match) and
cited 26-vs-26. Both sets were equal. The thresholds were not.

It also explains the second, stranger observation — *"an instrumented copy of the same patched
file returned 41 rather than 34"*. Instrumenting meant copying the file somewhere else, and
**where the file sits is an input to it.**

## The reproduction, with an unmodified rotor on both sides

Trunk `bin/cc-memory-rotate`, byte-identical, run twice on `cp -Rp` copies of the same index,
differing only in where the executable was placed:

| placement | thresholds | forced-breach outcome |
|---|---|---|
| `<root>/bin/` beside `<root>/hooks/lib/` | `limit=26346 rotate_at=24846 target=22346` | moved nothing |
| a flat scratchpad copy | `limit=25000 rotate_at=23500 target=21000` | 9 index lines demoted, 5 at stage 2 |

So a "control" built by copying the rotor to `/tmp` is not a control. **The precondition is an
equality, asserted:** both arms must print the same `loader-vs-disk overhead … thresholds shifted
to …` line before any verdict from the pair counts. This is the same class of harness defect the
subject's own header already documents for `cp -R` restamping topic mtimes (`young=26 hub=0`
against a live `young=11 hub=15`) — one more input to this program that a copy silently changes.

## The SECOND harness confounder, found the same way

Fixing the placement bug did not make the matrix green. `breach-noage` — the only case where a
rotation actually *moves* lines — still diverged: both arms moved 56, both `stage2=31`, but the
SETS differed and `live=` read 51 against 56.

**The rotor writes its demotion pointers into `.claude/rules/*.md`, and that file is INSIDE the
citation corpus `build_cited_set` scans.** So two arms sharing one project directory is a
feedback loop: arm 1 rotates, appends a pointer naming each demoted topic file, and arm 2 then
reads those pointers as citations, ranks those entries 2 instead of 1, and demotes a different
set. Every name in the delta was one arm 1 had just written a pointer for.

Two consequences, and the second is why this is in the record rather than only in a fix:

* **A/B arms need their own project directory**, copied from a pristine template — the same
  discipline as `cp -Rp` for the memory dir, for the same reason: an input this program mutates.
* Until that was fixed the harness was writing into the **real** repo's tracked
  `.claude/rules/agent-operating-lessons.md` — 101 lines across four routed blocks, all naming
  fixture paths under `/private/tmp/.../scratchpad/fx/co/`. Restored by truncating at the first
  block, verified against `origin/main` (the result differs by exactly the 3 lines the 3-commits-
  behind shared checkout has not got). No real memory was ever moved: every routed marker names a
  fixture index, never the live one.

The generalisable shape, and it is the one that made both confounders invisible: **this program's
inputs include its own executable path and its own previous output.** A control for it is not "a
copy of the file and a copy of the data" — it is a copy of *everything it reads*, in the *shape*
it reads them from.

## What the scans cost, measured

`/usr/bin/grep` (BSD 2.6.0), this repo's executable corpus, 556 files:

| | |
|---|---|
| `grep -rlF -f` — **1** pattern | 0.16 s |
| `grep -rlF -f` — **163** patterns | 45.0 s |
| `grep -rhoF -f` — 163 patterns (`-o`, the shipped form) | 49.5 s |
| `grep -rhoE -f` — the same 163 as ONE alternation | 28.6 s |
| `cat` of the whole corpus | 0.06 s |
| the anchored `awk` pass | **0.63 s** |

**BSD `grep -F -f` is linear in pattern count, not Aho-Corasick.** 163× the patterns cost 274× the
time. `-o` is not the cost and neither is I/O, and a single `-E` alternation is not the cure —
BSD's ERE engine walks it the same way. The comment on `build_cited_set` asserting Aho-Corasick
was a belief about the tool that nobody had measured; it justified the scan that cost 35–50 s of
a 115 s run.

The hub scan paid the same bill in forks: one `grep` per topic file per candidate, 429 × 18 =
**5.08 s per candidate**, 91 s of the run. Batching it to one `grep` per candidate is 0.023 s —
but at breach pressure stage 2 re-judges the whole type-kept pool and the candidate count rises
from 18 to ~122, so even the batched form costs seconds inside a 3 s hook budget. Both scans are
now one anchored `awk` pass over the corpus for the whole name set.

## The equivalence proof

Three independent instruments, because the blocked question was precisely "is this the same
predicate", and the predicate decides which memories are protected from demotion.

1. **Differential fuzz** — `scripts/memory-rotate-scan-equiv.sh`. Runs the new engine against the
   `grep -lF` it replaces over randomized corpora built to hit what a real index cannot: a name
   that is a strict substring of another, many name lengths ending at one `.md`, self-overlapping
   wikilink anchors (`[[a]]]`), regex metacharacters, empty files, no trailing newline, NUL bytes.
   The engine is `eval`'d out of the subject rather than re-typed. `verdict=equivalent`.
2. **Whole-program matrix** — trunk vs patched, `cp -Rp` fixtures of the live 163-entry index,
   comparing stdout, the full `--verbose` per-entry keep/move trace, and the resulting file tree,
   across dry-run/write × breach/no-breach × project-dir/none × deep breach.
3. **Suite** — `tests/cc-memory-rotate.bats`, with five new cases pinning the substring semantics
   the fast rewrites get wrong, and a mutation control that restores the pre-fix `grep` scan and
   requires it to eat a cited rule.

## The one deliberate divergence, and its direction

`grep -o` prints `Binary file <path> matches` **instead of** the matches the moment it sees a NUL
anywhere in a file. So `build_cited_set` both fed that sentence into `CITED_LIST` as though it
were a topic filename, and lost every real citation in that file — including ones on lines
*before* the NUL. `awk` is not immune (macOS `awk` truncates a record at its first NUL), but it
reads the lines that precede it. The new scan therefore finds a **superset** of the citations, and
a citation found is a memory **protected** from demotion — the safe direction for a change to this
predicate. On this repo's corpus the real-name sets are identical (9 = 9); the only delta was one
bogus `Binary file …` token from a `__pycache__/*.pyc`, which no topic filename can equal.

## The residue, and the cache whose obvious spelling was worse than the problem

Fixing the scans left 4.7 s — still over `memory-nudge`'s 3 s bound, so that hook went on reporting
`verdict=deferred`. An ablation put the whole remainder in two reads that look free and are not,
because each is a **fork per candidate** and macOS `fork`+`exec` is ~5 ms: the frontmatter `type:`
probe (~2.6 s) and `fmtime` (~2.2 s — called twice per candidate, once in `protect_reason` and
again in the selection loop). One bulk `stat` over the whole directory is 0.066 s against 0.81 s
for 163 individual ones.

🚨 **The obvious cache made it six times worse.** bash 3.2 has no associative arrays, so the
natural shape is a `name<TAB>value` string probed with `${table#*"$NL$name$TAB"}` — which is what
`HUB_TABLE` does safely, because it holds only the handful of names with any inbound link at all.
Over a table of *every* entry it is **quadratic**: bash matches a leading `*` by retrying at every
prefix length. Measured, that spelling took the same index from 4.7 s to **28.9 s**, with 22.9 s
burned inside the shell. The entries already carry an ordinal — `protect_reason` takes it as `$1`
and stage 2 replays the recorded one — so both tables became plain indexed arrays, filled in
ordinal order and read in O(1) with no fork at all.

That buys **one new way to be wrong, and no fixture in the suite could see it**: every entry in
them parses, while an UNPARSEABLE line contributes an *empty field* to the entry list, so a table
built by dropping blanks shifts every later entry by one and reads another memory's stamp and age.
Building the mutation control for it took two corrections worth recording — the shift moves the
MTIME too, so a directive that merely stops being the oldest is not demoted; and the value a shift
steals must itself be non-protective, or the mutant keeps the directive for a different reason and
the control passes vacuously.

## Result

**118 s → 2.9 s**, measured under a load average of 69–93 with an interleaved three-round A/B (the
scans-only commit measured 5.0 s against the same load). Byte-identical stdout, stderr and tree
throughout. The rotor now fits inside `memory-nudge`'s 3 s budget as well as
`memory-index-drain`'s 8 s one, so an in-hook rotation of a breached index **completes** instead of
reporting `deferred` — which is what the parent fix (`a72bfd477`) explicitly left undone.

Equivalence composes rather than being re-derived: the scans commit is byte-equivalent to trunk
over 8 matrix cases, and the ordinal-cache commit is proved against *it* over 9 (both arms fast, so
that matrix runs in minutes instead of an hour), including `--drain-oversized` and two cases that
really rotate.
