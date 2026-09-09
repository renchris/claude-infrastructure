# D5 · Who owns an orphaned class-C decision packet? (packet `0f354fc4d693`)

READ-ONLY measurement, 2026-09-09. Store: `~/.claude/autonomy/decisions/` (198 packets).
Repo read: `/Users/chrisren/Development/.worktrees/exhaustive-drive`.

## The three measurements that decide it

**M1 — option (b) has an EMPTY field population.** Across **all 98 class-C packets ever
written** (any status), `veto_deadline` is set on **0** and `default_if_no_veto` on **0**.
All **67** `expired-actioned` packets are **class B**, and **67/67** of those carry both
fields. Age-out is a class-B mechanism that has never once touched a class-C packet, and
there is no default on any open packet for it to fire.

```
jq -s '[.[]|select(.class=="C")]|{n:length,veto:([.[]|select((.veto_deadline//"")!="")]|length),dflt:([.[]|select((.default_if_no_veto//"")!="")]|length)}' ~/.claude/autonomy/decisions/*.json
# => {"n":98,"veto":0,"dflt":0}
jq -s '[.[]|select(.class=="B" and .status=="expired-actioned")]|{n:length,veto:([.[]|select((.veto_deadline//"")!="")]|length)}' ~/.claude/autonomy/decisions/*.json
# => {"n":67,"veto":67}
```

**M2 — option (a)'s render half is ALREADY BUILT and firing.** `hooks/operator-readout.sh`
reads `DEC_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"` (line 203) and its
decisions leg (lines 585-635) selects `status=="open" and class=="C"` **with no session
join at all** — plus class-B packets carrying neither a default nor a deadline. Every one of
the 31 open class-C packets **already renders today** as a `◆` row in the OPERATOR block
(collapsed to one counted line under the default `CC_OPREADOUT_CLASSBUDGET=collapse`).
The orphan is not invisible to the operator. It is invisible only to the **⛔ rung**.

**M3 — option (a)'s re-attach arms yield ~0 and one of them re-arms a permanent ⛔.**
`session_pane_uuid` is set on **1 of 31** packets (`b1614375d051`, pane `314`) and that pane
is dead ⇒ pane-arm yield **0 today**. The project arm reaches 16 of 31, **10 of them
`claude-infrastructure`** — so joining ⛔ on project makes every close in this repo render
⛔ over a stranger's question, permanently. `scripts/wrap-ledger.sh` lines 46-48 designed
against exactly that: *"this machine standingly carries ~21 open decisions, and a top-priority
rung counting those would fire at every close forever"* (the alarm-polarity lesson).

## What each option changes in code (one line each)

| Option | The code change | Verdict |
|---|---|---|
| (a) re-attach | `scripts/wrap-ledger.sh:935` — widen `select((.session_sid//"")==$sid)` to also match `session_pane_uuid` ∈ live panes, else `subject_project` == this repo | **REFUTED** — pane arm reaches 1 packet (dead pane); project arm re-arms a permanent ⛔ in this repo (10 packets) |
| (a) render | `hooks/operator-readout.sh:585-635` — nothing; the leg has no session filter already | **NO-OP — already shipped** |
| (b) age-out | `cc-decide` sweep on `veto_deadline`/`default_if_no_veto` | **IMPOSSIBLE** — 0/98 class-C packets carry either field |
| (T) third | close refuted packets with `cc-decide veto <id>`; leave `wrap-ledger.sh:935` untouched; add the packet's age to the existing `◆` row (`operator-readout.sh:619`, which already reads `.created` for its sort key) | **DOMINATES** |

## Per-packet table (31 open class-C, oldest first)

`age` = days since `created`. `author` = authoring session alive now (registry pid + `ps`,
TZ-pinned). `pane` = `session_pane_uuid`. `cv`/`rc` = conviction / receipt present.
`opts` = options count. `PREMISE` = is the question still true, checked against disk.

| id | age d | project | author | pane | cv | rc | opts | PREMISE | what (80c) / evidence |
|---|---|---|---|---|---|---|---|---|---|
| `f91a9701ed21` | 52 | - | dead | - | no | no | 0 | **TRUE** | Pushover credentials: every page and alarm is currently silent to an away human <br/>*no PUSHOVER_TOKEN/CC_PAGE_TO in ~/.zshrc or settings*.json; no keychain entry* |
| `adec28939635` | 52 | - | dead | - | no | no | 0 | **DEAD?** | Ship-rail permission posture: the git-push ask plus a classifier deny on compoun<br/>*settings now carries a `Bash(git push:*)` rule (allow/deny bucket unverified)* |
| `409693600c90` | 52 | - | dead | - | no | no | 0 | **TRUE** | Reboot posture: today any reboot halts the whole desk until console login (FileV<br/>*/Library/LaunchDaemons has 0 claude units; ~/Library/LaunchAgents has 29* |
| `a3b5aadfb217` | 51 | - | no-sid | - | no | no | 0 | **DEAD** | GO LIVE — end the keystroke-injection page-spam. Both fixes are landed + gate-gr<br/>*all 4 cited shas (1ddba46 9c0d42a 6b39463 f53348a) are ancestors of origin/main; deploy-now.sh exists and deploy-live.sh is the standing converger* |
| `7b406352c6f3` | 51 | - | no-sid | - | no | no | 4 | **DEAD** | SevenRooms bridge go-live: pick the channel. TWO of the three blockers in the ea<br/>*c9a807dfdf84 (today, live session) says verbatim "an earlier packet said no… three of that reasoning's four clauses are now false on disk"* |
| `2b9d23a05157` | 51 | - | no-sid | - | no | no | 0 | **DEAD** | Run the read-only SevenRooms navigation + introspection mapper against your auth<br/>*no mapping/ dir; bridge built through to go-live — mapper obsoleted by progress* |
| `739906feadbe` | 50 | - | no-sid | - | no | no | 0 | **?** | OPTIONAL last-mile to a zero-FAIL preflight on real infra: stand up the two revi<br/>*external infra stand-up; not checkable from disk* |
| `9d97a3c272a2` | 44 | - | no-sid | - | no | no | 0 | **TRUE** | Focus-ring authority for /admin: CONSTRAINTS.md:38 (2px sky outline, frozen+gene<br/>*src/lib/focus-ring.ts still `_focusVisible: { insetRing: '1px' }`* |
| `264154f10d1a` | 39 | - | no-sid | - | no | no | 0 | **TRUE** | Opus 5 over-delegates where prior models under-delegated: does 'NEVER cap resear<br/>*reso CLAUDE.md:513 still "NEVER cap research-subagent parallelism"; infra CLAUDE.md:245 still "No parallelism cap … Default N=12"* |
| `1e325f3f5711` | 30 | reso-management-app | no-sid | - | no | no | 2 | **TRUE** | May the Turso Platform API client be upgraded from version 1.9.2 to 2.0.5? The a<br/>*reso package.json still `"@tursodatabase/api": "^1.9.2"`* |
| `7d4a230457c5` | 28 | reso-management-app | no-sid | - | no | no | 2 | **?** | Should the /admin/platform console be able to mint a tenant's first-admin invite<br/>*reso product judgment* |
| `5bccddb2bb52` | 18 | reso-management-app | no-sid | - | no | no | 2 | **?** | Should a tenant's first-admin invitation be able to pin the person's username (y<br/>*reso product judgment* |
| `ef79469fbb12` | 17 | reso-management-app | no-sid | - | no | no | 3 | **?** | Every tenant the provisioning saga creates gets a credential-less admin user at <br/>*reso product/security judgment* |
| `f75ea0199b6e` | 14 | - | dead | - | no | no | 0 | **?** | The production web app runs with a never-rotated AdministratorAccess AWS key fro<br/>*needs AWS credential — `aws` not on PATH; agent structurally cannot check* |
| `55cb0a27028e` | 14 | reso | dead | - | no | no | 3 | **?** | Two production tenant databases hold more than one venue (key-database: heist + <br/>*production tenant data; needs console* |
| `ff24ce1f7808` | 13 | claude-infrastructure | dead | - | no | no | 3 | **?** | The standing backlog dispatcher only fires work into Claude Cloud, and Cloud is <br/>*no backlog-dispatch*.sh in scripts/ under that name; unverified* |
| `287e3d99c14e` | 5 | reso-management-app | dead | - | no | no | 2 | **?** | The marketing walkthrough shows the venue name on screen for eight continuous mi<br/>*marketing/product judgment* |
| `b1614375d051` | 3 | reso-management-app | dead | 314 | no | no | 2 | **?** | May the guest-check-in app move its login-and-permission database reads inside t<br/>*reso architecture judgment* |
| `8977a4fa4dd1` | 3 | - | dead | - | no | no | 0 | **?** | Should we spend about 6.40 dollars a month to keep one machine always running in<br/>*spend judgment ($6.40/mo)* |
| `1151a8035d08` | 3 | reso-management-app | dead | - | no | no | 3 | **?** | The Oregon key tenant will report DEGRADED on every deploy forever, and it is ha<br/>*tenant-state judgment* |
| `0aa3febf3143` | 3 | - | dead | - | no | no | 0 | **?** | Should the app ship a new client data-store version now? It re-keys every door d<br/>*reso product judgment* |
| `bed4ce4ec791` | 1 | - | dead | - | no | no | 3 | **?** | Five working sessions are frozen waiting for someone to approve ordinary setup c<br/>*permission-prompt policy (sibling of b6b6879b8650/f6e4c09d07e3/ba1a148a0e2f)* |
| `4194644aea26` | 1 | claude-infrastructure | dead | - | no | no | 2 | **?** | May the unattended deploy job restart a background daemon by itself when that da<br/>*infra policy judgment* |
| `shipland-esc-c661813` | ? | - | no-sid | - | no | no | 3 | **TRUE** | ship-land refused to auto-land branch 'feat/autonomy-100': the landing range '64<br/>*feat/autonomy-100 is 14 commits ahead of origin/main, head 2026-07-19 — genuinely unlanded* |
| `f7f296389c6e` | 0 | claude-infrastructure | ALIVE | - | 70 | yes | 2 | **TRUE** | Ratify the C10 rescope split: env-var and hook-registration migrations land auto<br/>*live wave* |
| `f6e4c09d07e3` | 0 | claude-infrastructure | dead | - | 70 | yes | 2 | **?** | May the standing desk session answer a worker's permission prompt on its behalf,<br/>*permission-prompt policy* |
| `c9a807dfdf84` | 0 | sevenrooms-bridge | ALIVE | - | 75 | yes | 2 | **TRUE** | Should the SevenRooms guest bridge go live on the manager-guestlist channel now?<br/>*live wave; supersedes 7b406352c6f3* |
| `ba1a148a0e2f` | 0 | claude-infrastructure | dead | - | 75 | yes | 3 | **?** | May an agent write into scratch locations without asking each time? Right now th<br/>*permission-prompt policy* |
| `b6b6879b8650` | 0 | - | dead | - | 70 | yes | 2 | **?** | When a FIRED, unattended session hits one of our own PreToolUse 'ask' verdicts (<br/>*permission-prompt policy* |
| `1df4081249d2` | 0 | claude-infrastructure | ALIVE | - | 60 | yes | 2 | **TRUE** | Who answers a permission prompt while you are asleep? Measured 1,040-1,176 sessi<br/>*live wave* |
| `0f354fc4d693` | 0 | claude-infrastructure | ALIVE | - | 65 | yes | 2 | **TRUE** | Who owns an orphaned class-C decision packet? 28-29 packets are open (median 13 <br/>*this packet* |

## Counts

| Count | n | Command |
|---|---|---|
| open class-C packets | **31** (33 twenty minutes earlier — 2 were actioned mid-research) | `jq -s '[.[]\|select(.class=="C" and .status=="open")]\|length' ~/.claude/autonomy/decisions/*.json` |
| …whose author session is ALIVE | **4** — from **2** distinct sessions (`b418b97a`×3, `2878d5d2`×1) | registry pid × `ps` join, above |
| …author dead | 16 | |
| …no `session_sid` at all | 11 | `jq -sr '.[]\|select(.class=="C" and .status=="open" and (.session_sid//"")=="")\|.id'` |
| would age-out fire a sane default | **0** | `…select((.default_if_no_veto//"")!="")\|length` ⇒ 0 |
| have nowhere to re-attach (no live pane, no project) | **13** (31 − 16 with project − 2 project-less-but-live) | `…select((.subject_project//"")=="" and (.session_pane_uuid//"")=="")` |
| already rendered in the OPERATOR block today | **31 of 31** | `hooks/operator-readout.sh:587-635` — no session filter |
| dead-premise, refuted on disk | **4 of 10 checked** (~40% of the pre-August cohort) | see PREMISE column |
| premise verified STILL TRUE | 10 | |
| premise needs a credential/console/value judgment the agent cannot reach | 17 | |

## Why a THIRD option dominates

Option (a) asks *where to re-attach an orphan*; option (b) asks *when to retire it*. Both
assume the orphan's problem is **attachment**. It is not — M2 shows every orphan is already
on the operator's board. The measured problem is that **the pile never shrinks**, because
nothing ever asks whether a packet's question is still a question. Four of ten checked are
already answered by the machine's own later state, and one of those (`7b406352c6f3`) is
refuted **verbatim by its own successor packet filed beside it** (`c9a807dfdf84`, today):
*"an earlier packet said no … three of that reasoning's four clauses are now false on disk."*
Both sit `open` in the same directory.

**T1 · Close what is refuted.** `cc-decide veto <id>` on `a3b5aadfb217` (all 4 cited shas are
ancestors of `origin/main`), `7b406352c6f3` (superseded verbatim), `2b9d23a05157` (bridge
built past it), and `adec28939635` pending a bucket check. Two tiers of authority:
**T1a** — a packet whose successor already re-asked the question needs **no** operator
authority to close (the question was re-put; closing the stale copy is bookkeeping).
**T1b** — a packet refuted by disk that nobody re-asked is the narrow residue.

**T2 · Do not touch `wrap-ledger.sh:935`.** The `session_sid` join is correct: the ⛔ rung is
*"a decision **I** am holding"*, not *"a decision exists"*. Project-joining it would fire ⛔ at
every close in this repo forever — the polarity defect the file's own header names.

**T3 · Add age to the `◆` row.** `operator-readout.sh` already reads `.created` (it is the
sort key at line 634). Rendering `[decision C <id> · 52d]` is a one-field change to an
existing jq and turns an undifferentiated pile into a drainable one — a 52-day packet and a
2-hour packet currently look identical on the board.

**T4 · Age-out: none.** No field to read (M1), and for a human-gated value fork a silent
default is the wrong instrument — that is what class B is for.

## Adversarial pass — what I checked because it would break the recommendation

- *"Is the store static?"* **No.** `60bf1044b72e` and `7b3793f8aed4` went `open`→`actioned`
  during this research. Any count here is a 2026-09-09 snapshot, not a standing figure.
- *"Is `cc-decide list --open --class C --json` the same population as the files?"* **Yes —
  RESOLVED, 31 ids, byte-identical id sets.** This nearly became a false finding: `cc-decide`
  is not on the *subagent shell's* PATH (`command not found`, exit 127), and the first attempt
  also died on a missing `timeout`, so the CLI arm twice returned empty. An empty CLI would
  have meant `wrap-ledger.sh:923` counts 0 for everyone and the ⛔ rung could never fire at
  all — a completely different decision. Run against the real binary
  (`bin/cc-decide`, or `~/.claude/bin/cc-decide`) the population matches the file read
  exactly. A tool's refusal bounds the tool, not the world.
- *"Does the aliveness test convict a live session?"* Cross-checked 7 sids two ways
  (registry pid + `ps`, and transcript mtime < 45 min). Both ALIVE sids are transcript-hot;
  `c7543d28`'s pid 30272 is gone despite a registry entry, so registry presence alone is not
  liveness.
- *"Is `adec28939635` really dead?"* Only partly established: a `Bash(git push:*)` rule
  exists in settings, but I read a grep of quoted patterns, not the allow-vs-deny bucket.
  Marked `DEAD?`, not `DEAD`.
- *"Is `shipland-esc-c661813` dead because its base sha landed?"* No — the base sha is an
  ancestor of `origin/main`, but `feat/autonomy-100` is still **14 commits ahead**, head
  dated 2026-07-19. Premise TRUE. It is a stranded-branch item in the wrong store.
