# A fired "keep looping until dry" default is not a work item a cold worker can drive

**2026-10-15.** Backlog `df779857c4ff` — *"class-B default fired: keep looping until dry (the scope
as written)"*, DoD ref `decision:eb3dbe1e5e94` — was dispatched to a `--venue cloud` session. This
file is its verdict: **unworkable as dispatched, and it actuates no change**; close the row on this
artifact rather than re-dispatching it.

## 1 · What the row is

`scripts/autonomy-sweep.sh` (the `"$BACKLOG" add --title "class-B default fired: $ddef"` call)
mints this title from a class-B decision packet whose veto deadline passed. The title carries ONLY
the default's wording; the decision's subject (`what_plain`, `subject_project`, the session that
opened it) lives in `~/.claude/autonomy/decisions/eb3dbe1e5e94.json` on the operator's box.

## 2 · What was run (cloud VM, `CLAUDE_CODE_REMOTE=true`)

    git rev-parse --is-shallow-repository      → true; git fetch --unshallow
    git rev-list --count HEAD..origin/main     → 0   (tree IS trunk)
    git rev-parse origin/main:bin/cc-dispatch  → 03e82d02b1fc534d11df9cd4939541225bdb6829
                                                 = the brief's dispatcher blob: the dispatcher that
                                                 fired this IS trunk
    git grep df779857c4ff origin/main          → no match
    git grep eb3dbe1e5e94 origin/main          → no match
    git log --remotes --grep=df779857          → no match (all remote branches fetched)

No trunk file, commit, park or research doc names the item or its decision. The packet is the only
record of what "the scope" is, and it is not reachable from this venue.

## 3 · Why it is not workable, and why it changes nothing

1. **The default is a scope CONTINUATION, not a change.** "Keep looping until dry (the scope as
   written)" is the decision's *keep doing what you were doing* arm. Firing it alters nothing the
   original session was not already doing; there is no artifact it asks to be built. That is the
   class `bin/cc-decide` § "TWO PRODUCER-DECLARED FIELDS" names — `hold`, `disclose-only`,
   `park … and continue other work` — which `default_effect=no-change` exists to keep out of the
   dispatch queue.
2. **It reached the queue because `default_effect` fails OPEN.** The producer did not declare
   `--default-effect no-change`, so the sweep read it as `change` and filed an open row
   (`autonomy-sweep.sh`, the `if [ "$deffect" = "no-change" ]` carve-out it did not take).
3. **The loop it names belonged to another session.** "Until dry" is a stopping condition of the
   session that opened the packet. A cold worker with only the title cannot know what population
   was being looped over, so any work done here would be invented to justify a push.

## 4 · Disposition

- **Close `df779857c4ff`** on this artifact (no-change default; nothing to land).
- If the desk wants the underlying loop resumed, that is a fresh, scoped item written from the
  packet's `what_plain` on the operator box — not this row.
- Residual (not fixed here, stated): producers that open class-B packets with a continuation default
  still omit `--default-effect no-change`; each such packet will mint one more row like this one.
