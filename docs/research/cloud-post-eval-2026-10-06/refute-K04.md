# Refutation pass: K04 "Route a merge conflict back to its VM as a rebase follow-up"

Written 2026-10-06. Repo read-only at `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (HEAD `593a21fc3`).
Live store read-only at `~/.claude/autonomy/cloud/`. Nothing was sent, fired, dispatched or changed.
The only write outside this file: git objects from `merge-tree` went to `/tmp/cloud-blog-eval/scratch/k04-objs` (isolated `GIT_OBJECT_DIRECTORY`), not into the repo.

## Verdict

| field | value |
|---|---|
| proposed | trial, conviction 50, effort M |
| survives? | **No (refuted)** |
| corrected | **skip** as a built mechanism, conviction **65** |
| residual | 35% that a zero-code hand probe on the next doc-only conflict is worth one follow-up |

The external feature is real and our transport for it works. The row fails on three things it rests on: where the change would go, why the branches conflicted, and how many conflicted sessions a rebase could turn into landed rows.

## 1. The four key questions

| question | answer | evidence |
|---|---|---|
| Do the cited file:lines say what the row claims today? | Text yes; live path no | section 2 |
| Does the external source say what the row claims? | Yes, with three limits | section 3 |
| Is the pain point open as of the newest dated source? | Yes; last conflict 2026-10-02, no cure landed since | section 4 |
| Would it move landed rows per unit of quota? | At most 1 to 2 rows per 15 days; otherwise it replaces a refire with a cheaper message | sections 5, 6 |

## 2. Citations checked against the code

| row claim | status | what the code says |
|---|---|---|
| Conflict is terminal, "no artifact, no wake, no latch" | Holds | `scripts/cloud-return.sh:637-660`; the phrase is at `:645` and in the ledger note at `:660` |
| Router sends it `local-only`, "the VM's shallow clone cannot see" trunk | Text holds; the arm is dead | `scripts/cloud-refusal-route.sh:236` |
| Transport exists | Holds | `bin/cc-notify:737-739` runs `claude -p "$MSG" --strict-mcp-config --cloud "$CLOUD_ID" --output-format json` |
| 3 of 3 gate refusals routed on 10-01 later returned | Holds | section 7 |
| 120 `land-conflict` rows over 4 sessions since 09-22 | Holds | measured, section 5 |

Three facts the row does not carry:

- **`:236` has had no input since the precheck landed.** Measured: `grep -l "hit a conflict" ~/.claude/autonomy/cloud/*.land-refused` gives 44 artifacts all-time, 0 with `at=` on or after 2026-09-07. The 3b' precheck (`cloud-return.sh:652-663`, commit `7d72371ca`, 2026-09-07) intercepts a conflict before the lander is asked, so the lander's "hit a conflict" text is never written.
- **The router cannot see a merge-tree conflict.** Its population is `*.land-refused` files only (`cloud-refusal-route.sh:616-628`), and the precheck files none by design. The four sessions behind the 120 rows have no `.land-refused` and no `.refusal-route` file (measured: `ls ~/.claude/autonomy/cloud/<id>.*` shows `.decl .retired .seen .sends` only). A "new arm in `cloud-refusal-route.sh`" has nothing to key on.
- **An existing guard would swallow it anyway.** `stale_resolved` ARM 2 (`cloud-refusal-route.sh:393-402`) calls a refusal stale when every path of the VM's set exists on trunk. That is true of any branch that only modifies existing files, which is the class that conflicts. Measured instance: `session_01A1uFXp8UhVcmE7TxPhsLgD.refusal-route` records `arm=stale` at 2026-09-23T12:13:23Z over three pre-existing paths for an rc 6 refusal, while the branch was unlanded; it was retired `conflict` 66 minutes later.

So the real change site is `cloud-return.sh` section 3b' plus a new per-head latch. That reverses a stated design decision in a path that has no state today. The file family has two measured runaways on record in its own comments: 150 `routed-originator` rows in two days (`cloud-refusal-route.sh:326-330`) and 980 `land-refused` rows over 45 sessions (`cloud-return.sh:605-609`).

Minor: the router's VM send is `cc-offload say` (`cloud-refusal-route.sh:314`), which wraps `cc-notify --cloud` (`bin/cc-offload:24`). "Through cc-notify" is one hop off.

## 3. External source

- Post, "Common questions" (`/tmp/cloud-blog-eval/.c1-post.txt:286`): "The sessions don't know about each other. Merge one branch, then send the next session a follow-up such as `claude -p "rebase on main and fix any conflicts" --cloud <session-id>`." Also `:168`: "Claude doesn't get notified about merge conflicts with the base branch, so ask it to rebase."
- Docs (`doc-claude-code-on-the-web.md:170-196`): the CLI "queues the message into the session and exits without waiting for a reply". JSON result is `{ok, session_id, url}`.
- Limits: an archived session refuses new messages (`:413`); `--cloud` needs an Anthropic account, not Bedrock or Vertex (`:184`); "Cloud sessions stop after a period of inactivity and the session's VM is reclaimed", and the documented recovery is reopening from claude.ai/code (`:415-422`). Whether a CLI follow-up revives a reclaimed environment is not documented.
- Binary: `/opt/homebrew/bin/claude --help` (2.1.291, run here) lists `--cloud [description|session_id|url]`. The 2.1.284 help was captured by a reader at `help-284.txt:70`; I did not re-run that build.
- Force-push: the proxy "rejects branch deletions and pushes of anything other than a branch" and "doesn't limit which branches a push can update" (`doc-cloud-environments.md:242`). Our own evidence that a VM can rewrite its branch: the 09-28 VM-authored verdict says "the branch was reset to `origin/main` and carries only this verdict" (`docs/research/truememory-adoption-cloud-verdict-2026-09-28.md:45-49`).

The feature behaves as claimed. The refutation is not here.

## 4. Is the pain point open?

Yes.

- Last `verdict=conflict` retire: `session_01K8vfFi3Xn1TwM3dHtutoHU`, declared 2026-10-02T11:02Z.
- Six fires since then, none conflicted (measured: `.retired` files for declarations after 10-02T12:00Z).
- No commit touches conflict handling: `cloud-refusal-route.sh` last changed 2026-09-07 (`7d72371ca`), `cloud-retire-terminal.sh` 2026-09-10 (`30530bc14`), `cloud-return.sh` 2026-09-30 for an unrelated lint (`04188cf27`). `git log --since=2026-10-02 | grep -i "cloud|conflict|owner guard"` returns nothing relevant.
- The brief carries no rebase rail: `grep -in rebase bin/cc-dispatch bin/cc-offload scripts/lib/cloud-create.sh` gives two hits, both comments (`bin/cc-dispatch:3265`, `:3320`).

## 5. What the conflicts were (the finding that decides this)

Population, measured: sessions declared in the last 15 days with `.retired verdict=conflict` = 5, of 30 declarations (the reader counted 31; boundary). `superseded` = 4.

Ledger, measured with `jq 'select(.outcome=="land-conflict" and .ts>="2026-09-22")' return.jsonl`: 120 rows, 4 sessions (26, 25, 35, 34). The 120 is one precheck per tick for about 5.5 hours per session, because the path has no latch. It is 4 events, not 120.

Push times are from `git reflog show origin/main --date=iso-strict` in `/Users/chrisren/Development/claude-infrastructure`. Conflicting files are from `git merge-tree --write-tree --name-only` in the isolated object directory.

| session (item) | fired | VM last commit | first `land-conflict` row | trunk push that collided | conflicting files | class |
|---|---|---|---|---|---|---|
| `01NLbyun` (`4f8c73bbdb35`) | 09-22 21:22Z | 21:32:12Z | 21:51Z (+29 min) | `0ee1b0e36` at 21:34:16Z, 2 min after the VM's commit | `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md` only | shared plan doc; code clean |
| `01AG5GAe` (`ac7bdd4b2f9d`) | 09-22 21:24Z | 21:29:44Z | 21:41Z (+17 min) | same push, 4.5 min after | same doc only; also conflicts with its sibling on that doc | shared plan doc; code clean |
| `01A1uFXp` (`ac7bdd4b2f9d`, refire) | 09-23 06:48Z | n/a | none (35 `land-deferred` over 4.7 h, then `land-refused` rc 6) | sibling refire `01RfAyCB` returned 13:19:56Z | not measured | gate-red, then lost to sibling |
| `01AMUiV1` (`eb41b669e5e6`) | 09-28 08:12:33Z | 08:32:17Z | 08:47Z (+35 min) | `c9b085699` at 08:13:51Z, 78 s after the fire | 7 files incl. `bin/cc-memory-search`, `CLAUDE.global.md` | desk landed the same feature (F48) |
| `01K8vfFi` (`71a4aa9fdc55`) | 10-02 11:02Z | 11:14:37Z | 11:38Z (+36 min) | `ad5ef734e` at 11:25:23Z, 11 min after | `tests/cc-backlog-needs.bats` | desk landed the same fix |

Readings:

- **No conflict in the ledger came from aging.** All four appeared at the first precheck, 12 to 24 minutes after the VM's last commit. The row's "riskiest assumption" names "the 10-05 land price-out that let the branch age". There is no conflict on 10-05: the priced-out session of that date, `session_01Be1LHu1mx4ozNCUpArEPiT`, ended `verdict=landed`. The one priced-out session that ended `conflict` is `01A1uFXp` on 09-23, and its refusal was rc 6, not a rebase conflict.
- **Two of five are duplicates of desk work.** The 09-28 VM said so itself: replaying its commits "at best would land a second implementation of each. So the branch was reset" (`truememory-adoption-cloud-verdict-2026-09-28.md:45-49`). The 10-02 item closed with `b3e2e3627`, "post-land RED already cured by b80c2517 on trunk". A rebase lands nothing new here; the correct resolution is discard.
- **Two of five are one shared plan doc.** The code in both branches merges clean against the colliding trunk commit. The two siblings then conflict with each other on the same doc, so the second rebased head conflicts again once the first lands, and the proposal retires it at that point.
- **The conflicts track concurrent desk activity on the same item, not independent trunk churn.** Trunk ran at a mean of 95 first-parent commits per day over 09-22 to 10-06 (measured, `git log --first-parent`; range 12 to 231), yet every colliding push was the desk working the same item or its plan doc within 11 minutes of the VM.

## 6. Yield

- Landed rows: at most 2 of 5 conflicted sessions per 15 days could add non-duplicate content (the 09-22 pair). Point estimate 1, because the second sibling re-conflicts (estimate, from the merge-tree result above and the proposal's own retire rule).
- Race for that one: follow-up to `returned` took 41, 62 and 78 minutes on 10-01 and 58 minutes on 09-23 (measured: first `routed=="vm"` `at` in `<id>.refusal-route` against the `returned` row in `return.jsonl`). The next trunk commit on the pair's three files was `210e5affc`, committer time 90 minutes after the colliding push (measured, `git log --reverse`). The window is about as long as the round trip.
- Quota: every conflicted item was refired, 5 refires in total (measured from `.decl item=`: `ac7bdd4b2f9d` 3 fires, the other three 2 each). Two of those refires only produced an "already cured" verdict doc. K04 could replace up to 5 refires with follow-ups. At the reader's 0.143 weekly-pp per fire (`C1-quota-pool.md:21-24` via `candidates.md` section 3, not re-measured) that is at most 0.72 weekly-pp per 15 days gross (estimate, 5 x 0.143), before the follow-up's own cost, which nobody has measured.
- Latency: retire happens 6.1 h after declare (measured on all four: `retired_at - declared_at` = 21,801 to 22,078 s; `CC_RETIRE_MIN_AGE_H` default 6, `cloud-retire-terminal.sh:84`). K04 would close up to 5 rows per 15 days about 5 hours sooner. Supply is 1 open row (`candidates.md` section 0, reader figure), so latency does not bind.
- Sample: about 2 fires per day and 0 conflicts in the last 6 fires. A trial needs weeks to see three events.

## 7. What supports the row (kept, because it is true)

- Follow-ups reach our API-created sessions and the work returns: 4 of 4 routed sessions since 09-23 returned, including one routed 335 minutes after declare (`session_01RfAyCB3YfvWS1kN4CaXH9q`).
- The VM is alive when the conflict is found: first conflict row at +17 to +36 minutes, retire at +6.1 h.
- The "shallow clone cannot see trunk" reason is stale. In all four ledger cases the VM's merge-base was trunk's head at fire time; trunk moved afterwards.
- A VM can rewrite its own branch (09-28 reset).

These make the mechanism feasible. They do not make it valuable.

## 8. Alternatives considered

| alternative | covers | ruled in or out |
|---|---|---|
| Brief line "fetch and rebase before the final push" | 1 of 4 ledger conflicts: only 09-28 had the colliding push before the VM's last commit | Out as a substitute for K04; trunk moved 2 to 11 minutes after the VM's last commit in the other three |
| Dispatch guard "a desk session owns this row" (F48, open; `a3-failure-ledger.md:132`; the 09-28 verdict asks for it at `:60-64`) | 2 of 5, and it saves the first fire, which K04 never can | Preferred for that class; not built |
| Keep VMs out of shared plan docs (brief rule), or `merge=union` as already used at `.gitattributes:34,70,71` | 2 of 5, zero quota, zero round trip | Preferred for that class; untested. `merge=union` on a doc with frontmatter can duplicate lines, so the brief rule is the safer form |
| Zero-code hand probe: on the next conflict whose merge-tree names only doc paths, hand-send one `cc-offload say <id> "..."` (described, not run) | Tests the one untested link: VM-side resolution plus the return lane accepting a rewritten head | The only part of K04 worth doing now |

## 9. Adversarial pass on this refutation

- "Five of 30 fires dying is the lane's largest loss; any recovery deserves a trial." The loss is real. Two of the five were dead at fire time (duplicates), and K04 is recovery-only, as `candidates.md` section 2 says itself.
- "The transport is proven 4 of 4." Those were gate-reds on files the VM wrote, where the fix is local to its own diff. A conflict's right answer depends on the other side's intent, and in 2 of 5 it was discard.
- "n = 5." Yes. The row's 50 rests on the same five. At higher volume, random-drift conflicts could dominate; the lifetime F39 figure (296 of 567) comes from a regime with a 207 h median land lag (`a3-failure-ledger.md:118`, reader figure), where the VM's environment has long expired and our longest measured idle follow-up is 5.6 h.
- "The brief-level rebase would do the same job cheaper." Checked and rejected above (1 of 4). That cuts in K04's favour and is why the residual is 35% and not lower.

## 10. Not verified

- The cost of one follow-up turn in quota terms.
- Whether a CLI follow-up revives a reclaimed environment.
- Whether VM-side conflict resolution is correct on a real doc conflict (never attempted on this lane).
- Which path set `01A1uFXp` conflicted on at retire time.
- The 2.1.284 binary's help (reader capture only); the 0.143 pp per fire figure; the 31-fire denominator.

## 11. Corrections to the row

1. Change site: not `cloud-refusal-route.sh`. A merge-tree conflict files no artifact and the router reads only artifacts; `:236` has had 0 inputs since 2026-09-07; `stale_resolved` would swallow a modify-only branch. The site is `cloud-return.sh` 3b' plus a new per-head latch.
2. Cause: "the 10-05 land price-out that let the branch age" is wrong on the date and the mechanism. No ledger conflict aged; the 10-05 priced-out session landed.
3. Pain size: 120 rows are 4 events; the implied "trim 4 to 5 conflict sessions per 31 fires" (`candidates.md` section 3) is an upper bound of 2 and a point estimate of 1.
4. Transport hop: `cc-offload say`, which wraps `cc-notify --cloud`.
