# W2 red team — where RETIRE fails (read-only, 2026-09-10)

Q(i): with `CC_FIRE_CLOUD` unset, cloud-planned items DO fire locally and safely (`bin/cc-dispatch:2759-2762`, journalled, claim label read from the actuator) — **but only after** the already-declared gate at `:2103-2127` has removed every `venuePlan=cloud` item that holds an unlanded declaration. That gate has "no TTL to expire and no marker to sweep" (`:2078-2080`). Q(iv): no other repo depends on the lane — 0 files in reso / doc_classifier / sevenrooms-bridge, 0 `claude/*` heads on their remotes.

## (i) Concrete failure modes

| what breaks | depends on | evidence | sev | mitigation memo must name |
|---|---|---|---|---|
| **6 open/claimed rows never fire again in EITHER lane**: `1f6208064577`, `badb132df232`, `c18e7ea9e6b1`, `9f8a985115a9`, `64c150ba2a8e`, `1dd6fbb6766c` | the retire/return pass writing `.retired`/`.returned` | 14 of 692 `.decl` lack both markers (`ls ~/.claude/autonomy/cloud`); `cloud_pending_scan` `cc-dispatch:719-734`; drop at `:2119-2123` precedes the local fallback | **HIGH** | settle the 14 declarations (retire/return) or `cc-backlog venue`→local BEFORE flipping the opt-in |
| cc-venue keeps relabelling rows `cloud` every 6 h; no cloud-off input | sweep | `autonomy-sweep.sh:1311-1328` `run --apply`; `bin/cc-venue:84-85` env seams (none for venue) | LOW | disable the venue pass or add a local-only switch |
| retire is not agent-executable: opt-in lives in two plist argv (`export CC_FIRE_CLOUD=on`); 4 cloud sessions fired TODAY (12:31Z–20:00Z) | operator | `plutil … com.chrisren.autonomy-sweep` and `com.claude.dispatcher`; plist edits are staged migrations (`migrations/0010`, `0016`) | MED | a migration removing the export from both plists |
| blocked `2a65b9bf722d` (`live-cloud-worker`) can only be unblocked by the cloud oracle; if `bin/cc-cloud`/store are deleted "block STANDS" forever | `cc-reaper sweep --reap` → `cc-backlog reap` | `bin/cc-backlog:6679-6681`, `bin/cc-reaper:2618`; oracle is `git ls-remote` + local store, no control plane (`bin/cc-cloud:476-500`) | LOW | keep `bin/cc-cloud` + `~/.claude/autonomy/cloud` read-only, or `cc-backlog unblock` by hand |
| 133 open cloud custody debts (of 138 open), all cwd `/`, stay open forever; deathwatch reports each once at TTL | custody-deathwatch | custody store census; `custody-deathwatch.sh:44` never discharges, `:224-229` latch | LOW | `cc-custody abandon` the 133 with a why after harvest |
| `is-offbox` liveness consumers convict cloud ids as dead if the store is deleted | cc-spawn-verify:243, cc-board:120, team-orphan-reaper:89 | 0 of 40 teams cloud-led today → inert | LOW | keep the store |

## (ii) Factual errors demonstrated

- §6 RETIRE: *"the 27 blocked and 5 open rows about the lane become moot."* Reproduced over LEAD-notes' own field regex (title/needs/evidence/source/condition ~ cloud|off-box|cc-cloud): `blocked=31 open=4`, and the 4 open are `badb132df232` (CV pipeline), `1f6208064577` (desk router), `64c150ba2a8e`, `c18e7ea9e6b1` — work **held by** the lane, matched only because their hold text names cloud. Retirement strands them; it does not moot them.
- §3.3 *"25 of 25 land invocations since 09-08 terminate exit:143"*: `~/.claude/land.log` since 09-08 on `claude/*` = 25×143, 10×42, 1×-1 (36 rows). True only if STALE-GATE rounds are not counted as invocations; say so.
- Not the memo but load-bearing: `cc-dispatch:3193` claims the live dispatcher runs `CC_DISPATCH_VENUE_ONLY=cloud`; the plist argv carries no such var.

Reproduced clean: 430 refs, 131 `Cloud-session:` commits (all re-authored as the operator), one post-09-08 landing (`140c2889b`).

## (iii) Verdict

**Yes.** The unnamed, unmitigated failure is the dispatcher's already-declared gate (`cc-dispatch:2103-2127`): it runs before the local fallback and has no TTL, so stopping the retire pass permanently holds six open/claimed rows — the rows the memo calls "moot" — out of both lanes. Sequence the retire: settle the 14 declarations and stop cc-venue relabelling first, then remove the plist opt-in.
