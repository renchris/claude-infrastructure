# PERMISSION_HARVEST is finished in fact and open only in its frontmatter — 2026-09-11

**Row:** cc-backlog `3e77c8eb182f`, *"advance PERMISSION_HARVEST — the recurring loop from manual
permission prompts to composable allow rules"*, project `claude-infrastructure`.
**Plan:** `docs/plans/PERMISSION_HARVEST.md`. **Verdict: DONE — no code was owed.** The deliverable
of this row is the status field, not a diff against the feature.

Measured off-box on a cloud VM (Linux) against `origin/main`, unshallowed first
(`git rev-parse --is-shallow-repository` printed `true`; `git fetch --unshallow` → 4,704 commits, so
every ancestry read below is outside the depth-50 horizon that makes a landed cure read as
never-landed).

---

## 1. Why the row kept coming back — the title names the PLAN, not the work

The row was minted from the plan's H1 by `cc-discover`'s C2 critic, whose whole claim is *"this plan
still holds work to advance"*. Two independent signals kept that claim alive, and **neither is
evidence about the work**:

- **`plan-phase-scan.sh` reports 17 of 18 sections PENDING.** Its status detection (header, lines
  13–18) marks a section DONE only when the HEADING contains the literal word `DONE` or a 7+ hex
  commit hash. No heading in this plan carries either, so every section reads PENDING **whatever its
  real state** — the scan is silent on completion here, not negative about it.
- **The frontmatter reads `status: in-progress`.** `find-plan.sh` `plan_status()` accepts the closed
  set `open | in-progress | complete | superseded`, and `--list-open` excludes only
  `complete|superseded` (`scripts/find-plan.sh:53,108`). `in-progress` therefore keeps the plan in
  the open list forever, and the stored falsifier's clause (a) — which retracts on terminal
  frontmatter — can never fire.

Measured before any change:

```
$ bash scripts/find-plan.sh --status docs/plans/PERMISSION_HARVEST.md
in-progress                                                        (rc 0)
$ bash scripts/plan-phase-scan.sh docs/plans/PERMISSION_HARVEST.md --falsify
                                                                   (silent, rc 1 = "still holds work")
```

rc 1 is the safe direction and never a confirmation: a probe can only ever REFUTE. So the premise had
to be checked against trunk by content, which is what §2 does.

This is the repo's own recorded class — *a work item that reappears after being closed is evidence
about the CLOSING MECHANISM, not about the work* — one polarity over: here the terminal value was
never written at all, so the plan never even reached the `unknown` fail-open default.

## 2. Every file-map deliverable is on trunk, verified by content

`git cat-file -e origin/main:<path>` for each row of the plan's §7 File map:

| Unit | Path | State on `origin/main` |
|---|---|---|
| C1 | `hooks/lib/permission_matcher.py` | present, 1,820 lines |
| C1 | `tests/permission-matcher.bats` | present, 726 lines |
| C1 | `bin/cc-permission-audit` (refactored to import) | present, 432 lines |
| C2 | `bin/cc-permission-harvest` | present, 2,414 lines |
| C3 | `scripts/permission-harvest-run.sh` | present, 368 lines |
| C3 | `launchd/com.claude.permission-harvest.plist` | present, 86 lines |
| C3 | `launchd/fleet.manifest` row | present, `:395`, `interval_s 604800`, owner `6` |
| C3 | `hooks/validate-bash.sh` `--apply` deny arm | present, `:1328–1378` |
| C3 | `hooks/validate-bash.sh` decision log | present, `:129` (`validate-bash-decisions.jsonl`) |
| C3 | `hooks/cc-permission-beacon.sh` `MAXLEN` 3500→12000 | present, `:62` (`ARCH_MAXLEN` default 12000) |
| C3 | `tests/permission-harvest-wiring.bats` | present, 509 lines |
| C3 | `tests/validate-bash-permharvest.bats` | present, 341 lines |
| C4 | `skills/permission-harvest/SKILL.md` | present, 231 lines |
| C4 | cross-link in `docs/research/permission-prompts-2026-08-23.md` | present, `:194–203` |
| C4 | matcher-doc DO #8 cross-link | present, `:615–616` |
| C4 | `hooks/smart-bash-allowlist.sh:26-29` header correction | present (the "BYPASSES" claim is corrected in place, dated 2026-09-08) |
| C5 | `tests/cc-permission-harvest.bats` | present, 880 lines |
| C5 | `tests/cc-permission-harvest-apply.bats` | present, 573 lines |
| C5 | `tests/fixtures/permission-harvest/**` | present, 11 files |

The two file-map rows marked *DROPPED* in the plan — migration `0022` and activation `44` — are a
**recorded, reasoned deviation, not a gap**: §5 drops them because `install.sh:1051-1122` already
copies and `bootstrap`s a new manifest-`run` plist at every converge, so a c10 migration would file
an operator step for a bootstrap that has already happened and could never transition to applied.

Landing history, all three asserted ancestors of `origin/main` with
`git merge-base --is-ancestor <sha> origin/main`:

- `7a73a511` — the plan and the two measurements that rewrote it
- `63734f03` — the weekly loop (the implementation)
- `a8837a8c` — §12, the hook-layer ceiling priced

## 3. The shipped code is green, and the two reds are this VM, not the tree

`bats` is absent here; bats-core 1.14.0 was cloned to the scratchpad and the five suites run against
trunk's code. Plan lines are asserted present on every one — an absence of `not ok` is not a pass.

| Suite | plan | ok | not ok | rc |
|---|---|---|---|---|
| `tests/permission-matcher.bats` | `1..49` | 49 | 0 | 0 |
| `tests/cc-permission-harvest.bats` | `1..61` | 61 | 0 | 0 |
| `tests/cc-permission-harvest-apply.bats` | `1..29` | 29 | 0 | 0 |
| `tests/permission-harvest-wiring.bats` | `1..24` | 22 | **2** | 1 |
| `tests/validate-bash-permharvest.bats` | `1..39` | 39 | 0 | 0 |

**200 of 202 pass.** Both reds are macOS-only binaries absent on this Linux VM, and neither touches
the subject:

- **#15** (`proposal files older than 90 days are pruned`) — `tests/permission-harvest-wiring.bats:292`
  calls BSD `touch -t "$(date -v-1d …)"`. GNU date has no `-v`: `date: invalid option -- 'v'` →
  `touch: invalid date format ''`. The harness died on its own fixture; the prune under test never ran.
- **#17** (`plist: plutil -lint clean, weekly calendar, …`) — `run /usr/bin/plutil -lint` exits **127**,
  command not found. bats itself flags it: `BW01: … exited with code 127, indicating 'Command not found'`.

**#17's assertions were re-derived platform-independently** rather than assumed. Parsing the plist
with Python `plistlib` after stripping XML comments reproduces every content claim the test makes,
and all match §5 of the plan exactly:

```
Label                 = com.claude.permission-harvest
RunAtLoad             = False
StartCalendarInterval = {'Weekday': 0, 'Hour': 4, 'Minute': 17}
ProgramArguments      = ['/bin/bash', '-c', 'exec "$HOME/.claude/scripts/permission-harvest-run.sh"']
StandardOutPath       = /Users/chrisren/.claude/logs/permission-harvest.out.log
StandardErrorPath     = /Users/chrisren/.claude/logs/permission-harvest.err.log
ProcessType present?  False   |   Nice present?  False
```

`python3 -m py_compile` is clean on `hooks/lib/permission_matcher.py`, `bin/cc-permission-harvest`
and `bin/cc-permission-audit`.

### 3a. One incidental finding, pre-existing and repo-wide — NOT this plan's and NOT fixed here

The un-stripped plist fails a **strict** XML parse: `not well-formed (invalid token): line 11,
column 12`. The cause is generic — XML forbids `--` inside a comment, and line 11 of the comment
block reads ``denies `--apply` from inside a session at the chokepoint``. macOS `plutil` uses
CoreFoundation's lenient parser and accepts it, which is why the suite is green on the operator's box.

Scoped before reporting it, because a finding's population decides whether it is a defect or a
convention: **9 of the repo's 26 `launchd/*.plist` files fail the same strict parse** —
`com.chrisren.cc-reaper`, `com.claude.auth-timeseries`, `com.claude.browser-spin-guard`,
`com.claude.deploy-live`, `com.claude.devserver-gc`, `com.claude.discovery`, `com.claude.dispatcher`,
`com.claude.power-policy-verify`, `com.claude.teammate-reap-alarm`, and this one. So it is a
standing property of how this repo writes plist comments, load-bearing on nothing (launchd reads
through the same CF parser `plutil` does), and predates PERMISSION_HARVEST. Recorded here so the
next reader who runs a strict parser does not file it as a regression of this feature; **fixing it is
a separate, repo-wide change and deliberately out of this row's frozen scope.**

## 4. The plan's own last open question was closed on 2026-09-10

§12 (`a8837a8c`) prices §3.5's "hook-layer levers" and **refutes** the premise: of 1,752 structural
rows the hook layer's ceiling is 444 (25.3 %), whose first three greedy picks (`rm` → `git` → `curl`,
181 rows) are all already owned by existing guards; excluding them leaves 33 rows = 1.9 % of
structural. It closes child row `5a629c6465d1`. Both layers now agree that `proposed=0` is the
correct steady state — **≤0.6 % from allow rules, ≤1.9 % from hook levers** — which is §10's
recommendation strengthened, not contradicted. Nothing in §§1–12 names an outstanding unit.

## 5. What was changed, and the consumer read-back

One field, plus a §13 recording this verification in the plan itself:

```
-status: in-progress
+status: complete
```

Written and then **read back through the consumer that dispatches on it**, which is the whole point —
a value written into a state field is worth nothing until the reader that defaults has been asked:

| Probe | before | after |
|---|---|---|
| `find-plan.sh --status <plan>` | `in-progress` (rc 0) | `complete` (rc 0) |
| `plan-phase-scan.sh <plan> --falsify` | silent, **rc 1** ("still holds work") | `FALSIFIED`, **rc 0** |

rc 0 with the affirmative token `FALSIFIED` is the only load-bearing answer under the falsifier
contract (`bin/cc-premise` `run_falsifier`; `scripts/autonomy-sweep.sh:1162-1176` — probe exit 0 ⇒
row CLOSED). Clause (a) of `--falsify` is what fires, and it is checked FIRST by design so that a
stored probe stays a strict superset of the derived arm it shadows.

Section headings were deliberately **not** rewritten to carry `DONE`. Clause (a) is sufficient and
fires first; churning 18 headings to satisfy clause (b) as well would rewrite the document's
structure to restate a fact its frontmatter now carries.

## 6. Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `e61bcbfc657a44a20b03d7d52ab3e921fd138242`, **EQUAL** to
the blob that composed this brief. The dispatcher that fired this row IS trunk, so nothing here is
confounded by a behind-trunk dispatcher — landed and live coincide for the dispatch path.

## 7. How to re-measure this verdict

The criterion, not the number — the number perishes:

```sh
bash scripts/find-plan.sh --status docs/plans/PERMISSION_HARVEST.md      # expect: complete
bash scripts/plan-phase-scan.sh docs/plans/PERMISSION_HARVEST.md --falsify  # expect: FALSIFIED, rc 0
bats tests/permission-matcher.bats tests/cc-permission-harvest.bats \
     tests/cc-permission-harvest-apply.bats tests/permission-harvest-wiring.bats \
     tests/validate-bash-permharvest.bats                                # expect: 202/202 on macOS
```

On macOS all 202 are expected green; on Linux expect exactly the two named in §3 to fail, for the
two named reasons, and treat any THIRD red as a real regression.
