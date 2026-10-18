---
status: in-progress
---

# LIMIT_RECOVER_SELF_INPLACE — a session moves itself, in place, with no external help

Scope (frozen): a live session can move ITSELF to another account in place (same pane, same session uuid, full transcript) with no operator step and no external terminal, both (a) when it invokes the move from its own turn and (b) when an originating peer session requests it; root causes found by a research Dynamic Workflow; a plan written at docs/plans/LIMIT_RECOVER_SELF_INPLACE.md (Phase 0 per plan-conventions); implemented with tests; landed and LIVE in the enforcing store per this repo's ship policy; proven by a real in-place self-move of a live session.

Goal (operator, 2026-10-17): proven by printing, after the move, the same session id running under the new config dir, plus the landed sha on origin/main; do not weaken any safety gate.

Hard constraints: no safety gate weakened (at-rest checks, single-copy fences, claim locks — fix the self path, never delete a guard); reso-management-app touched only by the one proof move of session 43e6eb4b; quota-heavy actions bounded, throwaway sessions first; operator panes moved only when idle with nothing in flight.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave**
  | wave | what | locus | why |
  |---|---|---|---|
  | W0 research | reproduce + trace each failure to file:line | Dynamic Workflow (workflow-lean, read-only, adversarial verify) | read-only fan-out of ~6 same-shaped units |
  | W1 implement | self-path fixes across handoff-fire.sh / cc-lr / lr-handoff | T (named teammates, one per disjoint file) or L | decided after W0; the files are disjoint per root cause, combined output small |
  | W2 land + converge | /ship, deploy-live degraded tier | L | lead-only by policy (standing-land) |
  | W3 proof | throwaway self-move, peer-requested move, then 43e6eb4b | L | needs live panes the lead watches |
- **Task size per unit:** 40–150K output tokens, 3–6 files per teammate.
- **Lead context budget:** hold ≥50% for deciding; **succession point:** after W2 lands (recycle before W3 if over ~60%).
- Worktree: lead on `lr-self-inplace`; teammates in their own worktrees, merged by rebase + ff.

## Evidence (session 43e6eb4b, pane 8, next4 → next, 2026-10-17/18)

1. Peer-sent `handoff-fire.sh --recycle --transplanted-source --source-pane 8 --source-session 43e6eb4b …` run from the session's OWN Bash tool: transplant copied + confirmed, then `recycle ABORTED before /exit (held: busy): transcript not at rest (rc 1 …)`, unconfirm rc 0. A background cc-await-ping watcher was also running.
2. Retry: `--recycle REFUSED: --transplanted-source, but session 43e6eb4b has NO transplant tombstone` — the abort's unconfirm removed it; the peer's retry line was not re-runnable.
3. `cc-lr switch --target next --dry-run` → "a real run would QUEUE"; real run → "REFUSED — the reconciler is live and it has no switch lane … Use: cc-lr move". Dry and real disagree.
4. `cc-lr move --sid <self> --to next` (own Bash AND operator `!`) → `hold:self`.
5. Separate terminal, `cc-lr move --pane 8 --to next --until-idle 900` → `hold:in-flight — another actuator holds its claim (pid 51575)`; 51575 was the worker of the settled batch 20261018T000816Z-next4-next-49288 (result NOTMOVED: HELD:unreachable, lr-handoff rc 6). Leftovers: locks/43e6eb4b….aborted-20261018T004143Z, ….unconfirmed-20261018T004117Z.
6. `cc-lr move` holds a session with a background job, while the WAKE FLOOR stop hook demands every idle session run a background cc-await-ping watcher ⇒ an idle healthy session is unmovable by construction.

## Lead's first trace (pre-W0, to be verified by W0)

- E1: `scripts/handoff-fire.sh:15344` — any `--source-pane/--source-session` selects the REMOTE form (`RCY_REMOTE=1`) even when the named pane IS the caller's own; the remote form's last read (`hf_recycle_last_read`, ~:3489) then re-proves at-rest on the caller's own transcript, which is mid-turn by construction. The self form deliberately reads the composer only (comment at :3486-3488).
- E3: `bin/cc-lr` cmd_switch (~:1873) returns the dry run BEFORE `cl_recon_queue` applies its switch-lane refusal (:253-258).
- E3/E4 loop: `cc-lr move` holds self (`bin/cc-lr:1229`) and points at `cc-lr switch` (:1629), which refuses while the reconciler is live and points at `cc-lr move`.

## W0 — Research (Dynamic Workflow)

_Pending — results integrated here._
