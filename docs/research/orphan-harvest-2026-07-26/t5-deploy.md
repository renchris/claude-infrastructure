# t5-deploy  (session 64132f93-23bf-4946-b44a-d0c367d45dea)

Harvested 2026-07-26 from disk after lead a3f68174 self-closed leaving this teammate orphaned.
Last assistant turn: 2026-07-25T23:24:54.537Z
Total records: 227

---


## turn @ 2026-07-25T23:21:26.106Z

T5 complete — commit `bee5c53` on `tm/gr-t5` (not pushed).

**Delivered (all 5 mission items, +344 LOC: 125 script / 186 bats / 33 edits — under the 400 cap):**

1. **NEW `scripts/deploy-live.sh`** — green-stamp-gated live-layer advance. Fetches `origin main` (fail ⇒ loud exit 1), walks `rev-list origin/main -n 200` newest-first, and fast-forwards only to the newest commit whose **tree** carries a `stamps/<tree>.json` with `"verdict":"green"` (python3 parse, `grep -E` fallback), then runs `install.sh` and reports un-stamped commits remaining above. Refuses on: no green in window (+ epoch-headed page `deploy-blocked-<tip12>.page`), target behind HEAD (roll-back), absent stamps dir (unless `--bootstrap`). `--force` and `--dry-run` per spec. `set -uo pipefail`, bash-3.2-safe, shellcheck clean, fail-closed.
2. **`hooks/operator-readout.sh:113`** — nag now emits `bash ~/.claude/scripts/deploy-live.sh`, annotation shape intact. This forced a one-line update to the pre-existing assertion in `tests/operator-readout.bats:147` (it grepped the raw pull string) — otherwise the suite goes red.
3. **`scripts/nightly-regression.sh`** — new `postland_inertness` check (step 5): RED when the stamps dir exists but the newest >2h-old trunk commit is unstamped; green-abstains when the net isn't adopted. Seams `CC_NIGHTLY_POSTLAND_DIR` / `_AGE`; selftest pinned hermetic.
4. **`scripts/rotate-autonomy-logs.sh`** — DEFAULT_TARGETS += `postland/flakes.jsonl`, `postland/runner.log`.
5. **NEW `tests/deploy-live.bats`** — 14 tests, all green (12 deploy-live + the 2 nightly inertness cases).

**Verified this turn:** `bats tests/deploy-live.bats` 14/14 · `bats tests/operator-readout.bats tests/rotate-autonomy-logs.bats` 29/29 · `nightly-regression.sh --selftest` GREEN 10/0 · `bash -n` + `shellcheck` clean on all four touched scripts.

**Two flags for the lead:** (a) adoption chicken-and-egg — the nag targets `~/.claude/scripts/deploy-live.sh`, which only exists after an `install.sh` run containing this commit, so the first deploy must go the old way or via `--bootstrap`; (b) `deploy-live.sh` only *reads* stamps and never invokes `$POSTLAND_BIN` — it assumes the stamp-writer emits tree-keyed `stamps/<tree-sha>.json` with `"verdict":"green"`; that contract should be confirmed against the postland-verify teammate.

## turn @ 2026-07-25T23:21:59.581Z

Small addendum — detail-carrying pages. Implementing:

## turn @ 2026-07-25T23:24:54.537Z

Addendum complete — branch `tm/gr-t5` is back to **one atomic commit `8b8039a`** (fixup + `GIT_EDITOR=true git rebase --autosquash`, non-interactive; not pushed).

**What changed (+26 lines, all in `scripts/nightly-regression.sh` + 1 test assertion):**

- **`run_check()` now captures instead of discarding** — signature and console output byte-identical; only `>/dev/null 2>&1` → `>"$out" 2>&1`, where `$out` is a per-check file under a trap-cleaned `mktemp -d` RUNDIR (falls back to `/dev/null` if mktemp fails, so a full disk can't break the check). Green path unchanged: nothing new printed, nothing new written.
- **RED page now carries WHY** — after the existing epoch/summary/see-LOG lines it appends, per failing check, `--- <name> ---` plus `{ grep -E '^not ok' || tail -15 } | tail -15` of that check's output. A bats RED names the actual failing tests; a plutil RED carries the parse error.
- **Made `postland_inertness` speak before failing** — it was a silent function, so its page body would have been empty (the very failure mode flagged, reintroduced). It now prints `postland net INERT: trunk <sha12> (tree <tree12>), settled >Ns ago, has NO stamp under <stamps>`.
- **Blind-checked the new path** — selftest gains `red-bats: page quotes the FAILING detail, not just the name`; bats test 13 asserts `postland net INERT` appears in the page body. Both fail if capture silently regresses to `/dev/null`.
- Fixed a leak I'd introduced: selftest's own EXIT trap was overriding the RUNDIR trap; it now cleans both.

**Verified post-squash:** `bats tests/deploy-live.bats tests/operator-readout.bats` exit 0 (15 tests) · `bats tests/rotate-autonomy-logs.bats` exit 0 · `nightly-regression.sh --selftest` GREEN 11/0 (was 10) · `bash -n` + `shellcheck` clean · working tree clean.
