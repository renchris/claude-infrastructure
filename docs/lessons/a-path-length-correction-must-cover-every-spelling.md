# A path-length correction must cover every spelling the subject emits

_Filed 2026-09-21 from the post-land RED on `tests/cc-limited.bats` row 15, cc-backlog
`9c3766f5be0a`. The always-loaded rules file carries the hook and links here._

## The rule

A budget asserted over output that embeds a *test-harness* path is a measurement of the harness
until the inflation is subtracted, and a subtraction is only as complete as the set of SPELLINGS
it enumerates. One spelling that escapes the correction leaves the whole assertion a function of
how deep `BATS_TEST_TMPDIR` happens to sit — which is what the correction existed to remove, so
the comment above it now reads as a guarantee that is not in force. Enumerate the spellings from
the SUBJECT's own transform, not from the one you can see; then assert the invariance rather than
trust it.

## The incident

`tests/cc-limited.bats` row 15 — *"the shape of the answer: exit codes, TSV arity, and the two
size budgets"* — asserts `cc-limited --json` fits a 6,144 B budget. The fixture root is a bats
tmpdir far longer than a production path and it appears inside every stored path, so the row
already corrected for it:

```bash
raw="$(cc --json | wc -c | tr -d ' ')"
occ="$(cc --json | grep -o "$W" | wc -l | tr -d ' ')"
adj=$(( raw - occ * ${#W} + occ * 15 ))     # re-price each root at "/Users/chrisren"
```

Its own comment states the intent exactly: *"Left raw, this assertion would measure the harness
rather than the tool."*

It measured the harness anyway. The JSON's `tp` field names a Claude Code **project directory**,
whose basename is the session cwd with every non-alphanumeric character mapped to `-`
(`bin/cc-limited:440` `slug_of`, and the fixture's own `build.sh:69`). So the fixture root is in
the payload in **two** spellings — the literal path and its transliteration — and `grep -o "$W"`
sees only the first. Four `tp` values each carried one uncounted copy: `4 × |W|` of inflation
subtracted from nothing.

Measured on the unchanged fixture and the unchanged subject, varying only `TMPDIR`:

| `|W|` | `--json` raw | old `adj` | new `adj` |
|---|---|---|---|
| 31 | 6,168 B | 5,880 | **5,816** |
| 139 | 8,544 B | 6,336 | **5,816** |
| 169 | 9,204 B | 6,432 | **5,816** |

The same census, the same bytes, on one side of the 6,144 bar and then the other.

## Why it read GREEN by hand and RED after a land

The breach needs `|W| ≥ ~97`. A hand-run `bats tests/cc-limited.bats` on macOS gets
`|W| ≈ 78` — `/var/folders/xx/<~30>/T` + `/bats-run-XXXXXX` + `/test/NN` + `/fix` — and squeaks
under. But `postland-verify` hands the corpus a **nested private TMPDIR**
(`scripts/postland-verify.sh:260`, `mktemp -d "$TMPBASE/postland-run.XXXXXX"`), adding ~21 chars
and pushing it past the edge. So the row is red exactly and only in the context that reports it,
and every attempt to reproduce it by hand comes back green. That file's own header already names
the class one paragraph earlier — *"what must hold is that the adjudicator's TMPDIR is as LONG as
the measurement's (see the 104-byte incident)"* — which is the same defect read from the other
end.

Note also what the cited sha carries: `6a0a05f8c` touches `lr-handoff.sh`, `lr-predicate-lint.sh`
and `tests/lr-predicate.bats`, none of which this suite reads. The attribution is whole-tree
reachability, not causation (see *Reachable ≠ caused*), and the defect predates it.

## The method that would have caught it, and now does

1. **Take the transform from the subject.** The fix's first draft used `tr '/.' '--'` — a
   reasonable guess from looking at one slug — and read `socc=0` on a tmpdir containing `_`.
   `slug_of` is `re.sub(r"[^A-Za-z0-9]", "-", cwd)`; quote it, do not infer it.
2. **Assert the invariance with a spelling-stable token.** The run tmpdir's own random component
   (`bats-run-XXXXXX`) is alphanumerics and dashes, every one of which `slug_of` maps to itself,
   so it reads identically in *any* spelling of a path that contains it. Strip the spellings you
   corrected for; if the token survives, a spelling you did not enumerate is still inflating the
   measurement. That guard has power rather than being an equivalence guard: strip one spelling
   instead of two and it fails.
3. **Run the row at two harness depths.** A correction that claims path-independence is a claim
   that can be executed. `TMPDIR=/tmp` beside a deliberately deep `TMPDIR` costs two runs and is
   the only evidence that the number is a property of the tool.
4. **State why an UNcorrected budget is safe.** Row 15's 1,200 B screen bar carries no correction
   because the default screen renders basenames. That is now asserted, not assumed — the day a
   row starts printing a stored path, the bar silently becomes a measurement of tmpdir depth.

## What was run

- `bats --filter '^15 ' tests/cc-limited.bats` at `|W|` = 31, 139, 169 — old form: green, red,
  red; new form: green, green, green, with `adj` printed as 5,816 in all three.
- Full suite, plan line `1..24` read not inferred: 23/24. Row 21 (`chmod 000` → expect exit 5) is
  red on this cloud VM **and on pristine trunk here**, both arms run, because the VM is uid 0 and
  `chmod 000` cannot deny root. Environment, not branch, and out of this item's frozen scope.
- Mutant: `for spelling in (sys.argv[2],)` — the leak guard fails, so it is not decorative.
- `bats-testname-eval-lint`, `bats-kill-guard-lint`, `alarm-polarity-lint`: clean.
  `bash32-parse-lint`: NON-VERDICT on this box (`/bin/bash` is 5). The added heredoc is therefore
  kept at statement level rather than inside a `$( … )`, per *bash 3.2 counts parens inside a
  heredoc it never runs*.
