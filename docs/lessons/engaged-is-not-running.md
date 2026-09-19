# A fresh assistant turn proves the account, not the session's survival

**2026-09-19, limit-recover fleet wave.** Six limit-blocked sessions were transplanted from two
weekly-dead accounts onto `next3` and relaunched. Each transcript then carried a fresh
**non-error assistant turn** — the exact engagement proof `lr-handoff`/`lr-fleet` themselves use.
I reported "6 resumed". Twelve minutes later **no claude process younger than 20 minutes existed
on the box**: every one had executed its `/limit-recover ingest` turn and exited.

## The rule

A fresh non-error assistant turn is evidence about the **account** (quota is clear) and the
**transplant** (the moved transcript is loadable and addressable). It is *not* evidence that a
session **persists**. The two claims have different witnesses:

| claim | witness |
|---|---|
| the account is usable / the transplant is sound | a non-error assistant record after the last api-error |
| the session is RUNNING and pick-up-able | a live process, and a pane that still exists |

Never let the first stand in for the second. A transcript is written by a turn, and a turn can be
the last thing a process ever does.

## Why the sessions died, and the fix

`lr-fire-resume.sh` drives an interactive TUI through `expect`. Launched detached — `nohup bash
lr-launch-*.sh` from a tool call, or `kitty @ launch` with the bare script — it has no pane to live
in: it submits the prompt, completes the turn, and exits. The transcript looks perfect.

The cure is a pane that outlives the script, with the capacity retry INSIDE it, because the
admission budget re-arms between launches and a refusal would otherwise close the window:

```bash
kitty @ launch --type=os-window --hold --title "recover-<sid8>" \
  /bin/bash -c "for i in 1 2 3 4 5 6; do /bin/bash <lr-launch-script> && break; sleep 5; done"
```

Verified: windows 181-186, six live `expect` TUIs, six transcripts advancing, and a
younger-than-10-minutes claude count that went 0 → 14.

## The companion failure: four faulty instruments in one session

Every wrong turn here was a bad instrument believed over the subject, which is
[[corrected-instrument-can-lie-again]] four times in one sitting:

1. A function-extraction probe missing `hf_bounded` → rc 127 → "kitty branch is dead in the daemon".
   Wrong; the branch is fine.
2. The same probe missing `hf_bounded_s` → same false negative a second time, *after* the first fix.
   One dead dependency found is not the last one.
3. `lsof -t <transcript>` → "no holder, the session is dead". The control refutes it: my own
   definitely-live session also shows no holder, because Claude Code does not hold the file open.
4. A `ps | awk` census whose wrapper argv carried all six sids → it matched itself and reported a
   holder for every session (the `census-matches-itself` shape, via the *caller's* command line
   rather than awk's own).

**Rule: before a null indicts the subject, run the positive control.** For a liveness question the
control is cheap and always available — ask the instrument about something you KNOW is alive (your
own session, your own pid). If it answers "dead", the instrument is the finding.
