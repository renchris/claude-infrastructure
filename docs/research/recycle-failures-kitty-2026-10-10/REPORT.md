# Why in-place self-recycle failed four times on one kitty pane (panes 44 and 134, 2026-10-09 → 10-11)

Status: DRAFT — slot verdicts pending.

## Evidence timeline (established by the lead before the fan-out)

Live-layer sha per failure, from the shared checkout's reflog (`~/.claude/scripts/*` symlink into it; local time is UTC-5):

| # | When (UTC) | Pane | Live sha | Recorded outcome |
|---|---|---|---|---|
| F1 | 10-09 04:55-05:03 | 44 | `bc471e0b6` | /exit landed, shell confirmed at 30 s, spell-correction disarm failed ×2, relaunch write failed ×2 → `recycle-dead`; alarm `push=refused-rc3` |
| F2 | 10-11 00:25 | 134 | `e667558fc` | successor staged → `recycle-held-exit-readback`: `/exit read back as '<unreadable>'` |
| F3 | 10-11 01:20-01:24 | 134 | `1b2b93357` (handoff-fire.sh ≡ `e667558fc`) | `recycle-deferred-turn` → `recycle-turn-ended` (+16 s) → `recycle-held-unreachable` (180 s) |
| F4 | 10-11 02:20-02:23 | 134 | `b68fa8a25` (includes `0584f0720`, live 01:48Z) | `recycle-held-draft ... over '/exit'` |

All four are the same Claude Code session, `6defb493-e229-4318-b0ab-86e7167c39e3` (account dir `~/.claude-next`), resumed from pane 44 into pane 134.

Facts that frame the analysis:

- **Remediation already landed for F1's class.** The `recycle-keystrokeless` program (`docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md`; `c54a3c0bd`, `f4b297310`, `3578b0e19`, landed 10-09 13:34-14:38Z) was built after F1; its fixtures include F1's own relaunch cmdfile and alarm (`tests/fixtures/recycle-keystrokeless/`). F2 shows the new path running (`recycle-successor-staged`).
- **The F2 read-back bug was found and fixed on another pane the same evening.** `0584f0720` ("the slash-command menu above a narrow box is not a dialog — /exit reads back in pane 168", 38 columns) went live at 01:48Z, after F2 and F3, before F4. Pane 134 is 37 columns wide (`kitty @ ls`, read 2026-10-11).
- **F2's hold message was false.** At `e667558fc`, `hf_exit_readback` sends DELs only when the read-back ends in `/exit`, so an `<unreadable>` read sent none, but `recycle_fire_commit` printed a hard-coded "five DELs sent to take our /exit back out" (`git show e667558fc:scripts/handoff-fire.sh`, line 17368). `0584f0720` replaced it with `HF_EXIT_RB_UNDO` and added a residue receipt (`composer_residue_record "$id" "/exit"`) for the unreadable case.
- **No residue receipt exists for pane 134** (`~/.claude/logs/composer-residue/` has no `134`), consistent with F2 predating the receipt.
- **Pane 134's composer reads empty now** (`it2 session read -s 134`, read-only), so no live `/exit` hazard remains in it.
- **F1's attempt telemetry does not exist**: `recycle-type-attempt` rows start with `f4b297310`, after F1.
