# A2 — Which Claude Code cloud mechanisms the cc-backlog cloud lane uses today (code read)

- Subject: `/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` at HEAD `593a21fc3` (2026-10-06).
- Read-only. No session fired, no routine created, no row claimed, no credential read, no daemon touched.
- Every `file:line` below is at that HEAD. Dates are the date of the cited source, not of this read.
- Number labels: **measured** = I ran the named command today (2026-10-06); **documented** = stated by a
  dated repo source I read but did not re-measure; **inferred** = my reasoning from the cited lines.
- Deployed == read: `git -C ~/Development/claude-infrastructure rev-parse HEAD` = `593a21fc3` = this
  worktree HEAD = `origin/main`; `~/.claude/bin/cc-dispatch` and `~/.claude/scripts/cloud-return-lane.sh`
  are symlinks into that checkout (measured: `rev-parse`, `ls -la`). The code described here is the code running.

---

## 0 · Headline

The lane does **not** use `claude --cloud "<task>"`, `--remote`, routines, RemoteTrigger, teleport, a
SessionStart hook, a setup script or `.mcp.json`. It creates sessions with a **hand-rolled HTTP client
against endpoints recovered from the 2.1.220 binary** (`POST api.anthropic.com/v1/sessions`, beta
`ccr-byoc-2025-07-29`, the account's OAuth token read from the macOS keychain), delivers the brief with
`claude -p "<brief>" --cloud <session_id> --output-format json`, observes by **`git ls-remote` polling
plus `GET /v1/code/sessions/<id>`**, and lands by fetching the `claude/fire-*` branch, **re-authoring every
commit** and pushing through the local `ship-land` gate. Everything a cloud environment could be
configured to do (setup script, env vars, network level, hooks) is done instead by **prose in the brief**.

The lane is live today: both launchd jobs loaded with `CC_FIRE_CLOUD=on`, ~2 fires/day, a cloud-authored
commit landed on trunk at 2026-10-06T16:43Z (§5, §6).

---

## 1 · How a cloud session is started

### 1.1 The path that runs (dispatcher-driven)

| step | invocation (quoted) | where |
|---|---|---|
| 1. dispatcher selects the cloud actuator | `local -a up_args=(up --via api --task "$cloud_pf" --account "$acct" --item "$id")` then `"$offload_bin" "${up_args[@]}"` | `bin/cc-dispatch:3432-3435` |
| 2. `cc-offload up` defaults to the API lane | `via="${CC_OFFLOAD_VIA:-api}"` → `cmd_up_api` | `bin/cc-offload:524`, `:600-601` |
| 3. create | `python3 "$api" --account "$account" --branch "$br" --repo "$repo_slug" --title "cc-offload: $(basename "$pf")"` | `bin/cc-offload:710-711` |
| 3a. environment resolve | `GET /v1/environment_providers`, pick first `kind == "anthropic_cloud"`; else `POST /v1/environment_providers/cloud/create` | `scripts/cloud-create-api.py:317-322`, `:347-367` |
| 3b. session create | `POST /v1/sessions`, header `anthropic-beta: ccr-byoc-2025-07-29`, body `{title, events: [], session_context: {sources:[{type:"git_repository",url,revision:"main"}], outcomes:[{type:"git_repository",git_info:{type:"github",repo,branches:[branch]}}], reuse_outcome_branches:true}, environment_id}` | `scripts/cloud-create-api.py:408-433`, `:644`, `:656`; constants `:106-108` |
| 3c. acceptance read-back | `GET /v1/code/sessions/<id>` must show `environment_kind == "anthropic_cloud"` AND `len(config.sources) == 1`, else exit 5 | `scripts/cloud-create-api.py:371-388`, `:671-681` |
| 4. declare locally (before brief) | `cc-cloud declare --id $sid --branch $br --account … --repo … --url https://claude.ai/code/$sid --custody $sid --item …` | `bin/cc-offload:722-729` |
| 5. deliver the brief | `"$CLOUD_CLAUDE" -p "$MSG" --strict-mcp-config --cloud "$CLOUD_ID" --output-format json … </dev/null` (via `cc-notify --cloud`) | `bin/cc-offload:765-766` → `bin/cc-notify:737-739` |

- Branch name is minted by the firing side: `claude/fire-$(date -u +%Y%m%dT%H%M%SZ)-$$-$i` (`bin/cc-offload:700`).
- `events: []` is deliberate: create and brief are separate so a failed acceptance costs no brief
  (`scripts/cloud-create-api.py:415-419`).
- No `--model`, no `--effort`, no `--environment` is passed on the create (`bin/cc-offload:710-711`;
  `--model` default `None`, omitted from the body, `cloud-create-api.py:426-427`, `:526`). **Inferred:** the
  VM runs whatever model/effort the platform defaults to; the pipeline does not choose it.
- Credentials: OAuth access token from the account's own keychain item
  (`security find-generic-password -s <service> -a <acct> -w` → `claudeAiOauth.accessToken`), org uuid
  from `<config_dir>/.claude.json` (`cloud-create-api.py:198-256`). Headers `:259-272`
  (`anthropic-version: 2023-06-01`, `x-organization-uuid`). No API key, no token refresh.

### 1.2 Why the API lane exists (the code's own measured reasons)

| create variant | got | lost | source (date) |
|---|---|---|---|
| `claude --cloud "<prompt>"` (CLI, needs a pty) | a real VM | `sources: []` — the VM git proxy refuses to inject a push credential: `access denied by the git proxy: … is not in this session's authorized repository set` (403) | `cloud-create-api.py:11-26` (2026-08-10) |
| `POST /v1/code/sessions` with `bridge:{}` | `sources: 1` | `environment_kind: bridge` — executes on a connected client (this box); sat `working / disconnected / 0 output tokens` 35+ min | `cloud-create-api.py:47-54` (2026-08-10) |
| `POST /v1/sessions` + `environment_id` (current) | both | — | `cloud-create-api.py:56-71`; `bin/cc-offload:662-679` |

- The request shapes were "recovered from the 2.1.220 binary" (`cloud-create-api.py:34-45`, `:56-66`) —
  i.e. undocumented client internals (`teleportToRemote`, `createCodeSession`, `zMt`), not a public API
  contract. **Inferred:** any server-side change to these shapes breaks the lane with a 400; the code's
  only guard is surfacing the HTTP body (`:284-305`).
- Bundle path cost when the CLI lane was used: ~95 MiB bundle vs a 100 MiB cap, ~50-75% success per
  attempt, hence a 3-attempt retry on `refused-bundle` only (`scripts/lib/cloud-create.sh:84-98`, `:130-132`, `:228-241`).

### 1.3 The deprecated CLI lane (still in tree, reachable with `--via cli`)

- `python3 "$CC_CLOUD_PTY_RUN" "$CC_CLOUD_CREATE_BIN" --cloud "$prompt"` under a custom pty allocator,
  because `claude --cloud` "requires an interactive terminal" and `script -q /dev/null` dies without a
  controlling tty (`scripts/lib/cloud-create.sh:20-25`, `:214-216`; 2026-08-09).
- Output is scraped: success = the literal `Created cloud session` banner (`:165-167`); id from
  `claude.ai/code/(session_…)` or the `--teleport session_…` line (`:187-201`).
- Called from `scripts/handoff-fire.sh:14153` behind `CC_FIRE_CLOUD=on` (`:577`, `:12547`).
- `bin/cc-dispatch:2828-2836` calls it "the DEPRECATED CLI create: it bundle-retries, DELIVERS NO BRIEF …".
- Stale header: `bin/cc-offload:22` still says `up → handoff-fire.sh --cloud`; the default is `api` (`:524`).

### 1.4 Mechanisms NOT used (negative results, all measured by grep today)

| mechanism | evidence of absence |
|---|---|
| `CLAUDE_CODE_REMOTE` (hook/env keying) | `grep -rn CLAUDE_CODE_REMOTE bin/ scripts/ hooks/ .claude/ skills/ tests/` → 0 hits; only 7 hits under `docs/research/` (binary-reading notes) |
| `RemoteTrigger` | 0 hits in `bin/ scripts/ hooks/ .claude/ skills/ tests/` |
| routines / `/fire` | 1 hit, a comment: "routines `/fire` → mint a per-routine bearer token" listed as needing a web-only operator action (`bin/cc-cloud:83-86`, 2026-08-07). No caller. |
| `claude --remote` | 0 hits as a Claude flag (all `--remote` hits are `cc-cloud declare --remote <git-remote>` or Chrome `--remote-debugging-port`) |
| `--teleport` | never invoked; appears only as an id-extraction regex (`scripts/lib/cloud-create.sh:195`) and in an argv allowlist (`scripts/handoff-fire.sh:5365`) |
| `--environment <id>` CLI flag | 0 hits outside `cloud-create-api.py` (its own argparse flag, `:533-537`) |
| PR-based return (`gh pr`, draft PR, auto-fix) | 0 callers; `gh pr list --head` is a design-note observable (O5, `bin/cc-cloud:75`) and a preflight print (`:1368-1371`) |
| session transcript / events / usage read | 0 hits for `/events`, `transcript`, `external_metadata` in `scripts/cloud-*.{py,sh}`, `bin/cc-offload` (the plan says usage is readable at `external_metadata.usage`, `docs/plans/CLOUD_BACKLOG_PIPELINE.md:122`, 2026-08-11 — no code reads it) |
| browser automation to start a session | none; a browser is only the operator escalation (`cc-offload open <id>`, `bin/cc-offload:11`, `:917`) |

---

## 2 · How the environment is configured

**Short answer: it is not. The only environment config in code is the fallback body used when an account
has no cloud environment at all.**

| surface | state in code | where |
|---|---|---|
| environment object | reuse the FIRST `anthropic_cloud` env the account lists; create one only if none | `cloud-create-api.py:347-367` |
| setup script | `"init_script": None` (fallback body only) | `cloud-create-api.py:336` |
| env vars | `"environment": {}` (fallback body only) | `cloud-create-api.py:337` |
| network level | `"network_config": {"allowed_hosts": [], "allow_default_hosts": True}`, description `Default - trusted network access` (fallback body only) | `cloud-create-api.py:332-342` |
| languages | python 3.11, node 20 (fallback body only) | `cloud-create-api.py:338-341` |
| SessionStart hook keyed on `CLAUDE_CODE_REMOTE` | none (0 grep hits) | — |
| project `.claude/settings.json` | has `disabledMcpjsonServers` + a `permissions.allow` list; **no `hooks` key** | `.claude/settings.json:4-55` |
| `.mcp.json` | does not exist in the repo (`ls .mcp.json` → No such file); settings comment confirms "ships no .mcp.json today" | `.claude/settings.json:3` |
| what the VM does get from the repo | `.claude/CLAUDE.md` (project memory), `.claude/rules/*.md`, `.claude/commands/ship.md` (`git ls-files .claude/`) | — |
| the operator's fleet hooks | live in `~/.claude/settings.json`, which does not exist in the VM | `.claude/settings.json:2`; `docs/plans/CLOUD_BACKLOG_PIPELINE.md:113-116` |

- The repo explicitly declined a SessionStart hook: "A SessionStart hook would mean editing
  .claude/settings.json, which the dispatch rails forbid in place. It is a venue-provisioning step"
  (`scripts/cloud-venue-provision.sh:8-12`, quoting `BACKLOG_DRAIN_24_7.md` 2026-08-29 addendum).
- The substitute is a **script the worker must be told to run**: `scripts/cloud-venue-provision.sh`
  installs shellcheck ≥0.11 and bats 1.13 (Ubuntu's apt gives 0.9.0 / 1.10.0, which red or silently
  un-gate this repo's land gate) and unshallows (`:18-47`, `:49-66`, `:76-104`, `:577-594`, `:685`).
  **It has no caller**: `grep -rn cloud-venue-provision bin/ scripts/ hooks/ skills/ .claude/` → one hit,
  a comment (`bin/cc-dispatch:3156-3158`: "nothing in that VM runs the provisioner").
- So per-session provisioning is carried in the brief text (§4) and re-paid by every session.
- **Inferred:** because the environment is per-account (resolved with that account's token/org,
  `cloud-create-api.py:639-640`), any setup-script/env/network change must be made once per account, and
  the code's "first anthropic_cloud env wins" rule (`:352-354`) is arbitrary if an account ever has two.
- Unknown from code: what the reused environments actually contain today (see Gaps).

GitHub-side prerequisites the code grades but cannot create:

- Claude GitHub App on the repo — "UNGRADEABLE FROM HERE" (gh holds an OAuth token; installation API
  needs an App JWT) (`bin/cc-offload:40-45`, `:347-365`; 2026-08-10).
- Per-account CLI↔GitHub link via `/web-setup`, which is TUI-only, so it is driven by typing into a
  kitty pane (`scripts/cloud-websetup-drive.sh:2-15`; permission carve-out `.claude/settings.json:6`, `:10-14`).

---

## 3 · How a running session is observed, collected, and landed

### 3.1 Observation channels

| channel | what it reads | where | notes |
|---|---|---|---|
| O1/O2 remote ref exists / advances | `git ls-remote --heads <remote> <branch>`, sha delta vs `<id>.seen` sidecar | `bin/cc-cloud:68-70`, `:95-99` | "the only heartbeat there is"; rc≠0 ⇒ UNKNOWN, never a verdict |
| boot ping | first act = push the declared branch | `scripts/lib/cloud-create.sh:280-305` (prepended by `bin/cc-offload:765`); `bin/cc-dispatch:3205-3208` | two conflicting texts — see §7 |
| control plane | `GET /v1/code/sessions/<id>` → `worker_status`, `status_bucket`, `post_turn_summary{status_category,status_detail,needs_action}`, `requires_action_details_list` | `cloud-create-api.py:563-611` (`--verify`) | read by `scripts/cloud-return.sh:359-378` (uses `worker_status` only), `scripts/cloud-inbox.py` (`need_input`/`review_ready`, `:107`), `cc-cloud poll` → `<id>.cp` (`bin/cc-cloud:1151-1158`) |
| `Claude-Session:` commit trailer (O3) | version-gated probe | `bin/cc-cloud:708-719` | marked "not yet wired" (`:712`) |
| PR state (O5) | `gh pr list --head` | `bin/cc-cloud:75` | design note only, no caller |
| lane liveness | gap since newest `claude/fire-*` ref, ceiling 24 h | `scripts/cloud-lane-liveness.sh:21-43`, `:95-100` | rides the return-lane tick (`scripts/cloud-return-lane.sh:143-182`) |

- State function over those: `UNKNOWN / NOT-STARTED / BOOTING / LANDED / STALLED / ALIVE / ABANDONED`
  (`bin/cc-cloud:102-120`); budgets boot 900 s, stall 3600 s, life 21600 s (`:229-231`).
- "There is no cloud→here push … the return arm is `git ls-remote` polling" (`bin/cc-offload:47-50`).
- Completion is a 3-fact conjunction because `worker_status: idle` / `review_ready` reads identically
  for a session finished 14 h ago and one fired 4 min ago: (1) pushed, (2) control plane says not
  running, (3) pushed sha quiet ≥ `CC_RETURN_QUIET_S` = 180 s (`scripts/cloud-return.sh:27-42`, `:89`; 2026-08-11).
- Here→cloud steering: `cc-offload say` → `cc-notify --cloud` → `claude -p … --cloud <id>`; the answer
  `{ok:true}` is "QUEUED, never delivered", `--receipt` exits 7 (`bin/cc-offload:34-36`, `:819-838`;
  `bin/cc-notify:111-135`).
- Land-gate refusals are routed back to the VM the same way, max 2 cycles per session
  (`scripts/cloud-refusal-route.sh:10-16`, `:74-78`).
- A session's question (`need_input`) is read and turned into a backlog row for the operator; nothing
  from the VM is ever executed (`scripts/cloud-inbox.py:31-39`; `scripts/cloud-answer.py:28-49`).

### 3.2 How work lands on trunk

```
launchd com.chrisren.autonomy-sweep (300 s)
  └─ scripts/autonomy-sweep.sh:749-768   spawns, detached (perl setsid):
     scripts/cloud-return-lane.sh        single-flight lane tick
       0 OBSERVE  cloud-lane-liveness.sh                        (:143-182)
       1 RETURN   cloud-return.sh --sweep --limit 25, bound 5400 s (:185-218)
            handle(): 0 item already done? → superseded        (cloud-return.sh:523-541)
                      1 pushed?  2 worker running?  3 quiet?    (:545-603)
                      4 CONFIRM=1 cloud-reconcile.sh --land <branch>   (:756)
                           fetch → reauthor_branch (git commit-tree, trailers) (cloud-reconcile.sh:626-720)
                           → SHIP_LAND_SESSION_BRANCH_RE=… desk-land.sh → ship-land.sh (:831)
                      5 fill paths  6 verify BY CONTENT  7 goal (:851-877)
                      8 cc-backlog done | block (from a landed docs/parks/<id>.md) (:878-968)
                      9 discharge custody  10 wake originator via cc-notify (:978-1025)
       2 RETIRE   cloud-retire-terminal.sh  (gone | landed | superseded | conflict) (:221-270)
       3 ANSWER   cloud-answer.py           (:273-309)
       4 RESCUE   cloud-reconcile.sh --rescue-docs  (:312-337)
```

- No PR, no merge button: the desk fetches the branch and pushes a rebased, re-authored range to `main`
  itself through the same gate local work uses (`scripts/cloud-reconcile.sh:21-25`).
- Land verification is by content (`git ls-tree <trunk> -- <path>`), never by sha, because the land
  re-authors (`docs/plans/CLOUD_BACKLOG_PIPELINE.md:59-61`; `bin/cc-cloud:73-74`).
- The backlog row is closed by the desk, never by the VM (`bin/cc-dispatch:3235`).
- Cost of the land unit (documented): `land.log` total p50 246 s · p90 680 s · max 14,783 s over 2,329
  rows (`scripts/cloud-return.sh:185-186`, ~2026-09-03); 700-3,900 s per cloud land under contention
  (`scripts/cloud-return-lane.sh:14-16`, 2026-09-06). The 2026-09-10 campaign located the cost in
  whole-tree ratchets over trunk, not in anything a VM could pre-run
  (`docs/research/cloud-lane-redesign-2026-09-10.md:309-312`, `:392-405`).

### 3.3 Admission gates in front of a fire

| gate | value / rule | where |
|---|---|---|
| box opt-in | `CC_FIRE_CLOUD=on` or the row fires locally | `bin/cc-dispatch:2842-2848` |
| venue label | row must carry `venuePlan=cloud`, written by `bin/cc-venue` from a positive certification | `bin/cc-dispatch:2824-2827`; `bin/cc-venue:1-60` |
| eligibility | `cc-backlog claim --venue cloud` runs `bin/cc-eligible`; rc 3 ⇒ `verdict=cloud-ineligible` (a skip) | `bin/cc-dispatch:2852-2854`, `:2943-2945`; `bin/cc-backlog:3658-3716` |
| trunk refresh before the gate | `refresh_trunk` | `bin/cc-dispatch:2873-2875` |
| off-box concurrency | `CLOUD_CEILING=6` ("a POLICY default, not a measurement") | `bin/cc-dispatch:441-446` |
| off-box pile | `CLOUD_PENDING_MAX=50` unlanded declarations ⇒ refuse ALL cloud fires | `bin/cc-dispatch:455`, `:2158-2174` |
| already-declared | an item holding an unlanded declaration is not re-fired | `bin/cc-dispatch:2190-2198`; scan `:778-793` |
| foreign repo | item project ≠ attached repo, or its text names another project ⇒ refuse | `bin/cc-offload:408-450`, `:477-520` |

---

## 4 · Workarounds for cloud limitations (each with its explaining comment)

| # | limitation | workaround | where (date of the comment's measurement) |
|---|---|---|---|
| 1 | Clone is shallow, depth 50; `merge-base --is-ancestor` exits 1 for both "no" and "cannot see that far" | brief orders `git rev-parse --is-shallow-repository` then `git fetch --unshallow` before any trunk read; `cc-eligible` refuses items citing a sha outside a 50-commit horizon (`CLOUD_DEPTH = 50`) | `bin/cc-dispatch:3145-3169`, `:3210` ("50 → 3,915" re-measured); `bin/cc-eligible:56-74`, `:759` (2026-08-11, 2026-09-01) |
| 2 | No `~/.claude` in the VM: `cc-backlog`, `cc-notify`, `/ship` are no-ops (return 3, write nothing) | cloud-specific brief tail: "Do NOT run cc-backlog done"; park via `bash scripts/cloud-park.sh <id> --needs …` which writes `docs/parks/<id>.md` to the branch; desk turns the landed file into `cc-backlog block` | `bin/cc-dispatch:3220-3237`; `scripts/cloud-park.sh:7-21`; `scripts/cloud-return.sh:878-968` (2026-08-29) |
| 3 | No inbound channel; "no ref" conflates never-booted / died / refused / working | boot-ping contract as the first act | `scripts/lib/cloud-create.sh:258-305`; `bin/cc-dispatch:3185-3208` (2026-09-02) |
| 4 | Push credential scope: git proxy injects a credential only for repos in the session's `sources`; App install is necessary but not sufficient | API create with explicit `sources` + `outcomes.git_info.branches=[branch]`; acceptance pair enforced | `cloud-create-api.py:11-32`, `:391-405`, `:671-681` (2026-08-10) |
| 5 | Exactly ONE repo per session, permanently | foreign-repo gate (label-foreign / subject-foreign) | `bin/cc-offload:408-450` (2026-08-20); "seven dispatches over six items … each unworkable ON ARRIVAL" |
| 6 | VM commits as `Claude <noreply@anthropic.com>`; repo `pre-push` identity gate refuses it | `reauthor_branch`: replay with `git commit-tree` as the operator, provenance in `Cloud-session:` / `Original-commit:` / `Original-branch:` trailers; not `Co-authored-by` (commit-msg hook blocks it) | `scripts/cloud-reconcile.sh:78-94`, `:526-528`, `:626-720` (2026-08-11) |
| 7 | `claude/*` branch name fails `ship-land`'s session-branch regex | one-invocation override `^(claude\|feat\|fix\|…)/.+` | `scripts/cloud-reconcile.sh:27-35`, `:138`, `:831` |
| 8 | A cloud VM must clone from the remote; local-only branches invisible | `cc-cloud preflight` refuses an unpushed branch | `bin/cc-cloud:1297-1355` (2026-08-07: 286 local branches without upstream) |
| 9 | Desk paths (`git -C /Users/…`) do not exist at `/home/user/…` | drop the `-C` prefix for cloud briefs | `bin/cc-dispatch:3173-3184` |
| 10 | VM lacks shellcheck/bats at the versions the land gate needs | `scripts/cloud-venue-provision.sh` (no caller) | `scripts/cloud-venue-provision.sh:18-104` (2026-08-29) |
| 11 | Every local liveness oracle (`ps`, `kill -0`, registry) reads an off-box session as dead | declaration store `~/.claude/autonomy/cloud/<id>.decl` + `cc-cloud is-offbox` | `bin/cc-cloud:43-65` |
| 12 | `idle` does not mean finished | quiet-window conjunction | `scripts/cloud-return.sh:27-42` |
| 13 | A finished session that asks a question pushes nothing and read NOT-STARTED (222 of 262 sessions were `need_input`) | `cloud-inbox.py` reader + `<id>.cp` sidecar + `cloud-answer.py` | `scripts/cloud-inbox.py:4-29`; `cloud-create-api.py:571-577` (2026-08-27) |
| 14 | VM cannot self-admit: a shallow clone certifies everything reachable | `cc-venue` writes a cloud label only from a full-clone certification | `bin/cc-eligible:76-84`; `bin/cc-venue` header |
| 15 | No `gh` off-box (as coded) | `ineligible-github` class refuses rows naming PRs / `gh` | `bin/cc-eligible:304-324`, `:454` — **contradicted by a newer source, §7** |
| 16 | Visual/browser/dev-server, launchd, panes, keychain do not exist off-box | spelling denylist classes `ineligible-box`, `ineligible-visual`, `ineligible-spawn-rail`, `ineligible-offbox-lane`, `ineligible-branch-banking` | `bin/cc-eligible:135-150`, `:326-335`, `:444-448` |
| 17 | `--cloud` create needs a pty; TUI output uses cursor motion that fuses words | `pty-run.py` + ECMA-48 normaliser (CLI lane only) | `scripts/lib/cloud-create.sh:20-62`, `:140-161` (2026-08-09) |
| 18 | Hidden/absent flag across versions | binary resolved from the launcher pin via `bin/cc-claude-bin`; refusal detected from the real call's `unknown option` | `bin/cc-offload:85-98`; `bin/cc-notify:743-757`; `scripts/lib/cloud-create.sh:114-128` |
| 19 | Re-fire loop (82% of declarations were re-fires of 51 items; `done` lags the land by median 2.33 d) | already-declared gate + pile cap + `cloud-retire-terminal.sh` | `bin/cc-dispatch:447-455`, `:2132-2198`; `docs/research/cloud-dispatch-delivery-2026-09-09.md` |
| 20 | Stale local branch / dead lander from a prior attempt | `fetch_branch` self-heal, sandbox reapers | `scripts/cloud-reconcile.sh:343-476` |

---

## 5 · launchd jobs that drive the lane, and whether they are declared enabled

| job | declared (`launchd/fleet.manifest`) | repo plist | live (measured 2026-10-06) | role in the cloud lane |
|---|---|---|---|---|
| `com.claude.dispatcher` | `run`, interval **900** (`:133`) | `StartInterval` **300**, `RunAtLoad false`, `ProcessType Background`, argv `export CC_FIRE_CLOUD=on; exec "$HOME/.claude/bin/cc-dispatch" --once` (`launchd/com.claude.dispatcher.plist:115-131`) | loaded, pid 71356; live `StartInterval=300`; live argv identical to the repo plist | FIRE: picks rows, claims `--venue cloud`, calls `cc-offload up --via api` |
| `com.chrisren.autonomy-sweep` | `run`, interval 300, evidence `~/.claude/autonomy/autonomy-sweep.heartbeat` (`:416`) | `StartInterval 300`, argv `export CC_FIRE_CLOUD=on; … taskpolicy -c utility ~/.claude/scripts/autonomy-sweep.sh` (`launchd/com.chrisren.autonomy-sweep.plist:24-26`) | loaded, pid 34546; live argv identical | RETURN: spawns `cloud-return-lane.sh` detached (`scripts/autonomy-sweep.sh:749-768`); also `cloud-refusal-route.sh --sweep` (`:816-823`), `branch-prune-landed.sh` (`:857-890`), `cc-venue run --apply` relabel (`:1425-1443`) |

- Measured with `launchctl list | grep`, `plutil -extract StartInterval raw`, `plutil -extract ProgramArguments.2 raw`.
- Manifest/plist disagreement: the manifest declares the dispatcher at 900 s; the plist (repo and live)
  is 300 s, and the plist comment says "Was 900s" (`launchd/com.claude.dispatcher.plist:87-90`).
  **Inferred:** `cc-fleet`'s staleness bound for this job is computed from a stale cadence.
- No cloud-specific launchd job exists; "§1.6's constraint holds: no new launchd job"
  (`scripts/cloud-lane-liveness.sh:52-53`). No cron entry is declared in the repo for the lane.
- `CC_DISPATCH_VENUE_ONLY=cloud` was removed 2026-09-07; both venues are admitted
  (`launchd/com.claude.dispatcher.plist:48-51`).
- The return lane is not a daemon: it lives only as a child of the sweep tick, single-flight by a
  mkdir lock with TTL `5400+900+5400+120` s (`scripts/cloud-return-lane.sh:78-80`, `:113-140`).
- `cc-reaper` whitelists argv naming `cloud-return` (`bin/cc-reaper:718`, `:892-896`).

---

## 6 · Live state of the lane (context for "is this worth improving")

| reading | value | command (2026-10-06) |
|---|---|---|
| declarations in store | 757 `.decl`, 757 `.retired`, 121 `.returned`, 98 `.land-refused`, 5 `.cp` | `ls ~/.claude/autonomy/cloud \| sed -E 's/.*\.//' \| sort \| uniq -c` |
| pending (unretired, unreturned) | 0 (every declaration carries `.retired`) | same |
| fires 2026-09-22 … 10-06 | 31 over 15 days ≈ 2.1/day (max 6 on 09-23, 2 today) | fold of `declared_at=` over `*.decl` |
| return outcomes since 2026-09-22 | 19 `returned` · 10 `land-refused` · 120 `land-conflict` · 55 `nothing-to-land` · 4 `superseded` · 11 `abstain` (8 "state UNKNOWN", 3 "control plane unreadable") | `jq` over `~/.claude/autonomy/cloud/return.jsonl` |
| trunk commits carrying `Cloud-session:`, commit dates 2026-09-22 … 10-06 | 68 (per day: 4, 11, 3, 2, 35, 8, 1, 2, 2 on 09-22/23/25/26/30, 10-01/02/04/06); the 35 on 09-30 coincide with the day the doc-rescue pass landed its `docs(cloud): … rescued from claude/fire-…` commits | `git log --since=2026-09-15 --format='%ad %(trailers:key=Cloud-session,valueonly)' --date=short origin/main \| awk 'NF>1{print $1}' \| sort \| uniq -c` |
| newest cloud land | `593a21fc3` — fired 16:41:59Z (branch name), VM commit 16:43:44Z, `returned` 17:29:23Z ≈ 47 min fire→landed (one sample) | `git log -1`, `tail -1 return.jsonl` |
| what the 5 newest cloud lands were | 2 `park(...)` files, 3 verdict/close docs — no code change | `git log -6 --grep=Cloud-session origin/main` |

- Documented lifetime figures (2026-09-22 audit, not re-derived): 727 declarations over 182 items, 116
  distinct rows landed, 1.4 landed rows/day over the prior 14 days, session yield ~16-20%, 74.9% of
  declarations were re-fires (`docs/research/backlog-drain-audit-2026-09-22/a2-cloud-lane.md:9-36`, `:66-72`).
- Documented economics (2026-09-10): cloud draws the same Max quota as local (p = 6.5e-06); ≈0.81×
  local token cost at small task size; machine capacity did not bind the local dispatcher (0 refusals
  over 297 fire attempts) (`docs/research/cloud-lane-redesign-2026-09-10.md:15-20`;
  `docs/plans/CLOUD_BACKLOG_PIPELINE.md:136-153`).
- Open operator decision `663522aa67b1` "retire, repair, or redesign the 24/7 cloud backlog lane",
  recommendation RETIRE at 70% (`cloud-lane-redesign-2026-09-10.md:361-372`); still OPEN as of the
  2026-09-22 audit (`backlog-drain-audit-2026-09-22/a6-design-record.md:96`, `:306`). The lane kept firing after it.

---

## 7 · Where sources disagree (newest dated source first)

| topic | older claim | newer evidence | status |
|---|---|---|---|
| Is `--cloud` a visible flag? | "present and HIDDEN on 2.1.215/219/220, so `claude --help` … is structurally incapable of seeing it" (`bin/cc-cloud:76-80`, 2026-08-07); "do NOT infer support from --help (it is blind to hidden flags)" (`bin/cc-offload:303`) | **Measured today on 2.1.284**: `~/.claude-284/node_modules/.bin/claude --help` lists `--cloud [description\|session_id\|url]  Create a cloud session with the given description, or attach to an existing one by session ID or claude.ai/code URL`, plus `--environment <environment_id>  Create a new cloud session that runs on the given self-hosted environment (ccpool_...)` and `--teleport [session]`. No `--remote` flag (only `--remote-control`). | code comments stale; behaviour of `--cloud "<desc>"` at 2.1.284 (pty requirement, bundle vs git source) NOT re-measured — it would create a session |
| "A cloud session cannot be FIRED programmatically from this box today" | `bin/cc-cloud:82-86` (2026-08-07) | the API lane fires programmatically since 2026-08-10/11 (`bin/cc-offload:662-679`) | comment stale inside the same repo |
| `gh` in the VM | "No `gh` CLI. GitHub reaches the VM only through MCP tools scoped to one repository" (`bin/cc-eligible:305-306`, `:454`; `CLOUD_BACKLOG_PIPELINE.md:107-108`, 2026-08-10) | "`gh` in the VM — already true — docs: 'Utilities: git, gh, jq, yq…', `gh` reads `GH_TOKEN` automatically; `bin/cc-eligible:456`'s 'no gh CLI off-box' is false" (`cloud-lane-redesign-2026-09-10.md:70`) | code still carries the class at HEAD (`bin/cc-eligible:454`); not corrected |
| Classifier accuracy | spelling denylist is the admission rule | "62.5% false-negative over its refusals (35 of 56) … `ineligible-box` is 54% of the flow and 20 of its 27 sampled rows are split-reachable" (`cloud-lane-redesign-2026-09-10.md:58-63`) | no later source shows a correction |
| Full-depth clone | "fails off-box because the VM's clone is grafted at 50 commits" (`bin/cc-eligible:58-62`, 2026-08-11) | unshallow works inside a real VM: "Checkout arrived shallow at depth 50 and was unshallowed first" (`cloud-lane-redesign-2026-09-10.md:71`); the brief now orders it (`bin/cc-dispatch:3210`) | `cc-eligible` still refuses on `CLOUD_DEPTH = 50` (`:759`) while the brief unshallows — the two rails disagree |
| Boot ping form | "an empty commit is enough" → `git commit --allow-empty -m 'chore: cloud session boot'` (`scripts/lib/cloud-create.sh:261`, `:290-292`), prepended to EVERY API-lane payload (`bin/cc-offload:765`) | "A BARE REF CREATION, NOT AN EMPTY COMMIT … Do NOT make an empty commit" (`bin/cc-dispatch:3199-3207`, 2026-09-02) | **both texts reach the same worker** in a dispatcher-driven fire, and they also name different branches (`git switch -c claude/fire-…` vs `git push -u origin HEAD`). Measured consequence: 1 empty `chore: cloud session boot` commit is on trunk (`25d8a193e`, 2026-09-22, `git log --grep='cloud session boot' origin/main \| wc -l` = 1) |
| Dispatcher cadence | manifest 900 s (`launchd/fleet.manifest:133`) | plist + live 300 s | manifest stale |
| Dispatcher is cloud-only | "MIGRATED TO CLOUD-ONLY 2026-08-11" | "UN-PARKED 2026-09-07" (`launchd/com.claude.dispatcher.plist:48-51`); routing last 2 d of the 09-22 audit: 45 local / 9 cloud (`a6-design-record.md:52`) | current: both venues |
| Plan status | `docs/plans/CLOUD_BACKLOG_PIPELINE.md` frontmatter `status: complete` | "REFUTED by an open operator decision" (`a6-design-record.md:96`, 2026-09-22) | open |
| `cc-offload up` delegate | header: `up → handoff-fire.sh --cloud` (`bin/cc-offload:22`, `:390-391`) | default `via=api` (`:524`) | header stale |

---

## 8 · Adversarial pass (what could make the above wrong)

- **"The code I read is not the code that runs."** Checked: shared checkout HEAD = worktree HEAD =
  `origin/main` = `593a21fc3`; live plist argv byte-matches the repo plists; the newest trunk commit is
  itself a cloud land from today. Holds.
- **"The lane is dead and this is archaeology."** Refuted by §6: 2 declarations and 2 cloud lands dated
  2026-10-06.
- **"Maybe a SessionStart hook or setup script exists in the cloud environment itself, configured in the
  web UI."** Cannot be excluded from code. The code never sets one and reuses whatever environment the
  account has (`cloud-create-api.py:352-354`). Named as a gap, with the read-only command.
- **"The API lane's undocumented endpoints are a fragility claim without evidence of breakage."**
  Correct — no breakage is recorded after 2026-08-11; the claim is inferred risk, bounded by the fact
  that 3 of 11 `abstain` rows since 09-22 read "control plane unreadable" and that on 2026-09-10 "six of
  eleven read 401" (`scripts/cloud-answer.py:69`). Those are token/auth reads, not shape changes.
- **"`--cloud` being visible in `--help` at 2.1.284 means the CLI lane now attaches the repo and the API
  lane is obsolete."** Not established. Only the help text was measured. Whether `--cloud "<desc>"` now
  produces `sources: 1` instead of a bundle, and whether it still demands a tty, needs one live create.
- **"Surviving `claude/fire-*` refs undercount fires."** True (the pruner deletes landed refs), which is
  why §6 counts declarations, not refs.
- **"The 47-minute fire→land sample is representative."** It is one sample of a park-file land; the
  documented land cost distribution is bimodal with a long tail (§3.2).
- **Latent defect found while checking version handling (measured by replaying the `case` pattern):**
  `cc-offload setup` R1 passes `2.1.2[2-9]*|2.[2-9]*|[3-9].*` (`bin/cc-offload:300-305`). `2.1.284`
  passes; `2.1.300` falls to `FAIL "… has no --cloud verb"`. It grades `setup` only, not `up`.

---

## 9 · Gaps (could not determine)

1. What the reused cloud environments contain per account (setup script, env vars, network level, name,
   count). Read-only command, not run because it reads a keychain credential and calls the account's
   control plane: `python3 scripts/cloud-create-api.py --account <name> --list-environments --json`.
2. Behaviour of `claude --cloud "<desc>"` on 2.1.284: tty requirement, bundle vs attached git source,
   whether it honours a branch/outcome, whether `-p` + `--cloud <desc>` creates headlessly. Requires a
   live create (out of scope).
3. Which model and effort a cloud worker actually runs with (the create omits both).
4. Whether the VM image at session start now has `gh` + a usable `GH_TOKEN`, and whether the clone is
   still depth 50 — newest in-repo evidence is 2026-09-10 / 2026-09-01.
5. Whether decision `663522aa67b1` has been ruled since 2026-09-22 (`cc-decide list --open` not run;
   the store is outside the repo).
6. Per-session token usage for recent cloud sessions (no code reads `external_metadata.usage`).
7. Whether the two conflicting boot-ping texts cause more than the one observed empty commit (e.g.
   sessions pushing to a branch other than the declared one); not measured.
8. Live liveness-sensor verdict (`scripts/cloud-lane-liveness.sh --assert`) — not run (it performs a
   network `ls-remote`); its 2026-09-22 VOID state was fixed in code on 2026-09-30 (`:69-93`).
