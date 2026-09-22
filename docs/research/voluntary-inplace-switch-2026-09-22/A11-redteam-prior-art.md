# A11 — red team: prior art for a voluntary in-place account switch

**VERDICT: ALREADY EXISTS — shipped, tested and live. Do not build it; drive the residuals.**

The verb is `scripts/handoff-fire.sh --recycle`, whose `recycle_repick()` re-picks the account
of a HEALTHY session in place. BOTH halves the proposal describes are landed: the
exclusion half (2026-08-10) and the pressure-short-of-exclusion half (backlog `2dc6906b6e0b`).

| Artifact | Where | What it does / decided | State |
|---|---|---|---|
| `recycle_repick()` | `scripts/handoff-fire.sh:9436-9560` ("W2-A: recycle account re-pick (ACCOUNT_ROUTING_V2 §14)") | On `--recycle` with `ACCOUNT=auto`, calls `claude-accounts --rank general`, and if the incumbent is excluded OR under scored pressure, swaps launcher + config dir and charges `--assign <new> --src recycle-repick`. Fail-soft in every direction; kill switch `CC_RECYCLE_REPICK=on/off` | **LIVE** — `~/.claude/scripts/handoff-fire.sh` is a symlink to the checkout |
| Call site | `handoff-fire.sh:9734-9748` | `_repick="$(recycle_repick "$ACCOUNT")"; [ -n "$_repick" ] && ACCOUNT="$_repick"` — inside the `auto` arm only | LIVE |
| `--account` flag | `handoff-fire.sh:8847`, header `:147` | Answers (c): `--account` **already composes with `--recycle`** ("Account defaults to THIS session's (CLAUDE_CONFIG_DIR-derived); --account/--launcher/--model/--effort compose"). An explicit `--account` is never second-guessed — it IS the manual in-place override, today, as a flag | LIVE |
| `docs/plans/ACCOUNT_ROUTING_V2.md` §14 / §14.1 | lines 825-946 | Design record. §14.1 marked **DONE (2026-08-10)**; motive is this proposal's exactly: 36 sessions piled on next3 at 100% while three accounts sat idle | LIVE |
| `tests/handoff-recycle-repick.bats` | repo | `1..17` (1 re-picks · 8 must-not · 4 fail-soft) | LIVE |
| Pressure half | `handoff-fire.sh:~9522-9560`, §14's "SECOND HALF … backlog `2dc6906b6e0b`" | Uses the router's own M7 `score_general` magnitude rather than inventing a second opinion | LIVE |
| `bin/cc-lr` LIMITED-only gate | `bin/cc-lr:178-266`, `a91f10e8b` | The limit-recover rails admit QUOTA limits only and refuse a healthy session — **this is a different rail** and is not the blocker for a voluntary move | LIVE, not applicable |
| Backlog `3d9943ec9e87` | `~/.claude/autonomy/backlog.jsonl`, linked `master-operator-gated` | Answers (d): the one open operator call nearby is `bin/cc-limited`'s **census/admission** contract (LIMIT_DETECT_100P, lead died) — it gates limit DETECTION, not recycle re-pick. **Nothing blocks this** | OPEN, non-blocking |
| Graveyard sweep | `git log --all --diff-filter=A`; `git branch -a` | No stranded branch carries a rival switch verb. Nearest neighbours are `64f536e76` (`--recovery` lane), `1a354bb5e` ("in-place is the default; --spawn is the opt-out") — both limit-recovery, both landed | — |

**Residuals, already named in §14.1 (the only honest build targets):** R14A-2 a Fable pane is
never re-picked (`case $MODEL in claude-fable-5*) return 0`), needs the `--route fable` lane;
R14A-3 `pre_fire_account_sweep` is still skipped for recycles, so a re-pick can land on an
account the sweep would have flagged.

**Sharpest negative:** the proposal's "reuse the transplant + pane-recycle machinery" is
already the implementation, and its premise that only a LIMITED session can move is false —
the LIMITED gate lives in `cc-lr`, a rail this path never enters.
