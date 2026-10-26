# Lane certification probes (wave W0)

Certifies, per Claude Code binary, the client behaviour the zero-restart account move rests on
(`docs/research/midturn-account-move-2026-10-25/REPORT.md` §4, §12 W0). Gate:

```
python3 -I tests/probes/lane/run.py --all [--binary <path>]
```

It writes `~/.reso/lanes/cert/<version>.json` (`LANE_CERT_DIR` overrides the directory), prints one line per
probe, and exits 0 only when every gating probe passes (`CERTIFIED`). `lib/cc-upgrade-gate/check18_lanes.sh`
runs it against each upgrade candidate. `--anchors-only` runs just the binary scan.

| probe | what it proves | gating |
|---|---|---|
| anchors | the mechanisms are still in the binary, found by regex (never byte offsets): store dir read per call from `CLAUDE_SECURESTORAGE_CONFIG_DIR`, the refresh lock, the keychain read cache (its interval is recorded), the thread-404 replay, the mod ops `env.set` / `turn.step` / `session.measure`, 401 store recovery | yes |
| P-P1 | **pointer lane**: a throwaway pointed at account A's real store is re-pointed mid-turn to B's store by a `turn.step` hook reading a route file; billing moves within the keychain-cache bound, no flap back, the turn completes, the transcript stays linear, the expiry guard (6 min / refresh lock) held, no keychain item or credential file appears, and A's and B's items see only ordinary refreshes. Decides operator decision `be5c5e83800f` | yes |
| P-S1 | `session.measure.rateLimits` shape, and every measure matches the org that billed the call before it | yes |
| P-R1 | retrofit: a running interactive session (private tmux server) is re-pointed by rewriting its mod mid-turn; `session.start` re-fires at the turn end and the next turn bills B | yes |
| P-L4 | re-home: the transcript cold-transplanted into a dir carrying B's identity record and resumed on B's store sends B's `account_uuid` on call 1 (observer proxy) and recalls the conversation | yes |
| P-L2 | two pointer lanes on one account: 401s and failed turns; `LANE_PL2_MAX_WAIT_S` makes it wait for and span that account's refresh | recorded |
| P-L1 | copy-lane keychain form: SKIP when P-P1 passes; otherwise BLOCKED, because it needs a copied token | — |

## Safety rules the harness enforces

- Throwaway sessions only, each config dir made fresh with `mkdtemp` under `/tmp` (never deleted and
  recreated: a removal prompt in an unattended session waits forever). No live session is pointed at a lane.
- No token is copied, written or printed. Keychain items are read for metadata only (expiry, modification
  date, sha256[:10] fingerprints) and the secret is dropped inside `lib.kc_state`; every artifact is scanned
  for the `sk-ant-` prefix and overwritten if one appears, which fails the probe.
- No slash command is ever typed. The TUI probe types plain prompts into its own tmux server only.
- Spend: haiku, roughly 2-3 cents for `--all`.

## Known form deviations (stated in each probe's docstring)

- P-R1 starts from A's store reached through the lane variable, not from an unset variable over A's own
  config dir: that start needs a credentialed throwaway config dir, which is either a copied token (ruled
  out) or a live account dir (its settings would run the fleet's hooks in the throwaway). The anchor
  `lane_var_read_per_call` certifies that both starts take the same branch.
- Print mode (`-p`) never reloads a mod, so P-R1 needs the interactive TUI.
