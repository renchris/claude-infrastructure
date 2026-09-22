# A retry budget must count ACTIONS TAKEN, never OPPORTUNITIES EXAMINED

**2026-09-22 · `scripts/limit-recover/lr-fire-resume.sh` · two sessions transplanted correctly and
left task-less**

## The shape

A retry loop had one budget and spent it in the wrong place:

```tcl
if {$verb eq "none" && !$recr && $t >= [expr {$poll - 1}]} {
  set recr 1                      ;# <- latched BEFORE the branch
  set sv [lr_screen]
  if {$sv eq "DRAFT-MINE"}      { ...send the retry... }
  elseif {$sv eq "EMPTY" || $sv eq "UNKNOWN"} { ...NOT MEASURED: send nothing... }
  else                          { ...break... }
}
```

The `EMPTY || UNKNOWN` arm is *correct*: those two readings are not negatives (an empty composer is
what a successful submit leaves behind, and UNKNOWN means no pane was read), so neither licenses a
keystroke. The lesson is not about that arm. It is that **the arm which correctly declines to act is
the one that disarmed the recovery**, because `set recr 1` had already been executed. One
unreadable sample permanently retired the only self-heal in the loop, and the remaining 150 s of
deadline polled a transcript that could never change.

## Why it is invisible

Every individual decision reads right, and the log even says so — `SUBMIT-UNMEASURED … not a
negative; polling the transcript` is an honest, well-worded note. Nothing reports that the budget
was consumed, because consuming a budget is not an event anybody emits. The failure surfaces only
as the *absence* of a later retry that no one is watching for.

It is also timing-shaped, which hides it from every test run on a settled fixture: the one sample
was taken at t = 29 s into a TUI that takes ~30 s to paint. Re-running the same oracle against the
same pane minutes later returned `DRAFT-MINE` — the evidence that licensed the retry existed, just
not at the single instant the code looked.

## The rule

Separate the two quantities and give each its own variable:

- **the SEND budget** — incremented only where a keystroke is actually emitted;
- **the LOOK schedule** — a `nextlook` timestamp that every branch, including the
  not-measured one, pushes forward.

A NOT-MEASURED reading must reschedule the observation, never retire it. Concretely: `incr recr`
belongs *inside* the arm that sends, and the arms that abstain set `nextlook` instead.

## The companion defect in the same incident

Two independent faults were needed to strand the sessions, and the second is worth its own line:
the settle gaps around the prompt inject had been cut from 2/1/1 s to 0.3/0.2/0.2 s by a commit
whose own comment named the hazard they existed for — keeping the text and the CR from coalescing
into one paste the TUI reads as a single keystroke. A trailing CR inside a paste is a literal
NEWLINE, not a submit.

**A fixed sleep cannot fix that**, because the quantity it must outlast is a TUI event loop under a
boot it does not control. Wait for the EVIDENCE instead — poll until the composer affirmatively
shows the draft, which proves the TUI consumed the text as its own event and that any CR after it
is a separate keystroke.

## The instrument that settled it

An empty Claude Code composer renders **exactly one body row** (`❯ `) between the two border runs.
Both stranded panes rendered the wrapped prompt **plus a trailing blank row** — the CR sitting in
the composer as text. Counting rendered rows separated "the CR was swallowed" from "the CR became a
newline", which no log distinguished.

## Re-derive

```bash
# the row-count instrument, against any live pane id
~/.claude/bin/it2 session read -s <pane> -n 24 | nl -ba | tail -12
# the run's own verdict
jq -r '[.ts,.state,.detail]|@tsv' ~/.reso/limit-recover/*/bundle-*/events.jsonl | grep -i submit
```

Companions: [[predicate-refusal-is-not-a-negative]] (why the abstaining arm is right),
[[empty-vs-no-surface]] (why EMPTY and UNKNOWN are different answers),
[[a-cure-is-verified-only-under-the-load-that-caused-it]] (why a settled fixture cannot see this).
