# The off-box partition's reds are mostly REAL — T1H is blocked by the tree, not by machine coupling

**Row:** backlog `8fd1919f7769` — *"T1H can never fire: the OFF-BOX hermetic partition is genuinely
RED … Triage per suite: machine-coupled (belongs in offbox-excluded.manifest) vs genuinely broken
(fix it)."* Filed 2026-08-26 against fold `{red:12, nonverdict:1}` on run 32945312244.

**The finding, stated first:** of the nine suites red in the newest fold, **five are red on this desk
too**, under the producer's own runner and therefore its own environment axes. They are not
machine-coupled. Landing every plausible exclusion would take the fold from 9 red to 5 red and the
`verdict` job would still be skipped — so the exclusion list was never the thing standing between
this repo and an off-box green. The row's implicit model (*a red partition is a mis-classified
partition*) is wrong, and it is worth naming because it is the model that made the list the remedy.

## The instrument

Two measurements per suite, because one off-box red cannot distinguish the classes.

1. **Off-box**, four consecutive scheduled folds: `33883119356` · `33921137472` · `33931675582` ·
   `33944444105` (2026-09-04T14:20Z → 2026-09-05T04:24Z; 537–541 suites each). Four samples, so a
   flake is separable from a deterministic red.
2. **On this box**, `scripts/offbox-run.sh suites <paths>` — the SAME classifier, bound and fold CI
   runs, with empty `$HOME`, `env -i`, `LC_ALL=C`, `TERM=dumb`. `scripts/offbox-admission-lint.sh`'s
   header states the limit exactly: it reproduces the **environment** axes and not the **machine**
   axes (no iTerm2, no loaded launchd agents, a different scheduler band, a different brew prefix,
   GNU rather than BSD userland). So *red off-box + green here* isolates a machine axis, and
   *red in both* rules one out.

## The table

| suite | off-box | this box | verdict |
|---|---|---|---|
| `tests/typed-send-lint.bats` | red 4/4 (notok=3) | **red, 15 ok / 3 notok, 21s** | GENUINELY BROKEN |
| `tests/validate-bash-differential.bats` | red 4/4 (notok=6) | **red, 1 ok / 6 notok, 62s** | GENUINELY BROKEN |
| `tests/goal-inert-watch.bats` | red 4/4 (notok=1) | **red, 27 ok / 1 notok, 4s** | GENUINELY BROKEN |
| `tests/bash-audit-attrib.bats` | red 3/4 (notok=3) | **red, 5 ok / 3 notok, 0s** | GENUINELY BROKEN |
| `tests/deploy-link-parity.bats` | red 1/4 (notok=2) | **red, 64 ok / 2 notok, 22s** | GENUINELY BROKEN |
| `tests/cc-resume-field-order.bats` | red 4/4 (notok=1) | green 4/4, 1s | machine-coupled → excluded |
| `tests/pipefail-sigpipe-lint.bats` | red 4/4 (notok=1) | green 27/27, 101s | machine-coupled → excluded |
| `tests/capacity-alarm.bats` | red 4/4 (notok=4) | **CUT** at 300s (28 ok / 0 notok) | class placement → excluded |
| `tests/cc-reaper.bats` | non-verdict 4/4 | — | harness-coupled → excluded |
| `tests/live-session-registry-atomic.bats` | red 2/4 (notok=1) | green 15/15, 8s | FLAKY — deliberately NOT excluded |

The four exclusions and their measurements are in `scripts/offbox-excluded.manifest` under
*FIFTH SEEDING*; the reasoning for each, including why `capacity-alarm`'s local leg ABSTAINS (a cut
is not a green) and why `live-session-registry-atomic` is left out, is at its own line there.

## What each surviving red actually says

- **`typed-send-lint`** — its own `--selftest` fails: *"the embedded allowlist is stale — the real
  tree is not clean"*, and it names two live sites, `scripts/handoff-fire.sh:5681` (`hf_bounded
  "$IT2" session send -s "$RSID" "/exit"`) and `bin/cc-husk-sweep:161` (`type_line()`). This is the
  lint working, on the tree, at its own call site.
- **`validate-bash-differential`** — 6 of 7 cases, including *"the majority verdict is DIVERGENT —
  the row's remedy does not clear its own gate"* and the coverage/drift arms. A pinned-pattern
  inventory has drifted from the hook it pins.
- **`goal-inert-watch`** — mutation M2 (*dropping the sentinel test makes the hook fire on a HEALTHY
  goal*) no longer reddens: the mutant passes, so that arm of the suite is now vacuous.
- **`bash-audit-attrib`** — `log-bash` records no exit code from `.tool_response` (cases 1, 3, 4 all
  fail on `grep -q 'Exit: N'`), while case 2's exit-0 path passes. An attribution sensor that only
  ever reports success.
- **`deploy-link-parity`** — an `install.sh` deploy class is in neither the forward-walk set nor the
  NOT-PER-FILE declaration, and case 43's control (which asserts the coverage arm can FIRE) is off by
  the same unclaimed rows.

## Why the on-box corpus never showed these

Row `782607797fc5` — the ON-BOX producer (T1) is killed from outside ~67% of the time. That is the
same reason this row's own framing survived nine days: with T1 starved and T1H structurally silent,
five real reds sat on trunk with no producer able to say so. Fixing them is what unblocks T1H;
nothing in the exclusion list will.
