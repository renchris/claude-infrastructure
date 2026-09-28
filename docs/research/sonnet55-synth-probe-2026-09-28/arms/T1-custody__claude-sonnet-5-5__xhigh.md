# Custody debt lifecycle (repo snapshot 47c3317eb)

**Summary.** A debt is one append-only JSONL row per originator cwd. Nothing in the repo expires or deletes a row. Rows are discharged by appending a `return` or `abandon` row. Every consumer reads the fold of that file. The deathwatch never discharges anything.

## 1. RECORDING

### Store and file
- The store is `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`).
- One physical file corresponds to one originator cwd: `$CUSTODY_DIR/<key>.jsonl`. `open` appends with `>>` (`bin/cc-custody:177,179`).
- The filename is `_fired_cwd_key "$CWD"`:
  - It resolves the path with `cd "$d" && pwd -P`, so `/tmp` and `/private/tmp` collapse to one key (`hooks/lib/origin-identity.sh:74`).
  - It takes the first 32 hex characters of the sha256 of that path (`hooks/lib/origin-identity.sh:76`).
- If the cwd does not resolve, `open` dies with "cwd does not resolve" (`bin/cc-custody:177`).
- Cwd-scoped reads use that one file. Reads with no `--cwd` glob every `*.jsonl` (`bin/cc-custody:130-139`).

### Row fields
- `_row` always writes `ts`, `kind` and `cwd`. It writes `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why` and `provenance` only when non-empty (`bin/cc-custody:93-103`).
- `kind` is `open`, `return` or `abandon` (`bin/cc-custody:93`).
- `provenance` is `proven` or `unproven-rc<N>`. It is written on open only (`bin/cc-custody:89-92`, `bin/cc-custody:179`).
- `open` never writes `why` (`bin/cc-custody:179` passes `""`).
- `ageHours` and `stale` are not stored. They are derived at read time (`bin/cc-custody:118-122`).
- A discharge row copies `cwd`, `targetPane`, `marker` and `slug` from the matched open row. `why` comes from `--why`. `originatorPane` is the caller's `--originator-pane`, not the matched row's value (`bin/cc-custody:222-227`).

### How the open set is computed
`_OPEN_JQ` is at `bin/cc-custody:108-112`.
- **Join key:** `"m:"+marker` when `.marker` is non-empty (`bin/cc-custody:110`).
- **Marker missing or empty:** the key falls back to `"s:"+slug+"|"+targetPane`, with a missing slug or target treated as `""` (`bin/cc-custody:110`).
- **Which row wins:** `group_by(.k) | map(sort_by(.ts) | last) | select(.kind=="open")` (`bin/cc-custody:111`). The latest `ts` wins, and only a surviving `open` row is in the set.
- **Ties:** `ts` has one-second resolution (`_now`, `bin/cc-custody:85`). On a tie the later file line should win, because jq's `sort_by` is stable. That is jq behaviour I did not verify in the repo.
- **Cross-cwd collisions:** the key carries no cwd. Store-wide reads concatenate all files (`bin/cc-custody:240,260`), so marker-less rows with the same `slug|target` in different cwds would merge.

### When a fire opens a row
The predicate is `[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody` (`scripts/handoff-fire.sh:13219`), inside `engage_apply_consequences` (`scripts/handoff-fire.sh:13195`).
- **`NB_ARMED_TARGET`** is set to `$BACK_SID` only inside `if [ -n "$NOTIFY_BACK" ]` (`scripts/handoff-fire.sh:10720,10728`). A headless default blanks `NOTIFY_BACK` (`scripts/handoff-fire.sh:10716`).
- **Recycle and dry runs** never reach this code. `ENGAGE_VERIFY=1` only when `RECYCLE=0` and `DRY=0` (`scripts/handoff-fire.sh:10662`; rationale at `scripts/handoff-fire.sh:13213-13218`).
- **The old self-retire condition is gone** (`scripts/handoff-fire.sh:13203-13212`).
- **Keyed directory:** `--cwd "$PWD"` (`scripts/handoff-fire.sh:13220`). That is the firing session's cwd, not the target worktree (comment at `scripts/handoff-fire.sh:13198-13201`). I found no line-initial `cd` in `handoff-fire.sh`.
- **Row contents:**
  - `--target "$SPAWNED_PANE"` (`scripts/handoff-fire.sh:13220`)
  - marker `${FIRE_MARKER:-}` (assigned at `scripts/handoff-fire.sh:10785`)
  - slug `NB_SLUG`, the prompt-file basename (`scripts/handoff-fire.sh:10721`)
  - `--notify-back "$NB_ARMED_TARGET"`
  - `--originator-pane "${FIRING_SID:-}"` (`FIRING_SID` is assigned at `scripts/handoff-fire.sh:11279`)
  - `--provenance`, which is `proven` when rc is 0 and `unproven-rc$rc` otherwise (`scripts/handoff-fire.sh:13196-13197`)
- **Empty marker:** `FIRE_MARKER` is passed as `${FIRE_MARKER:-}`, so it can be empty. The row is then marker-less and uses the slug fallback key.

### Engagement outcomes (`engage_rc_consequence`, `scripts/handoff-fire.sh:3547-3595`)

| rc | Meaning | Custody row | /goal arm |
|---|---|---|---|
| 0 | engaged | yes (`:3550`) | yes (`:3550`) |
| 1 | never ingested | **yes** (`:3574`) | **no** (`:3580`) |
| 2 | pane parked | **no** (`:3583`) | no (`:3583`) |
| 4 | wedged | yes (`:3589`) | yes (`:3589`) |
| 5 | cannot tell | yes (`:3592`) | yes (`:3592`) |
| other | undocumented | fails open with a stderr warning (`:3593-3595`) | fails open (`:3593-3595`) |

- rc 2 is the only non-success outcome that opens no debt.
- The /goal arm does not follow the same rule. It differs on rc 1, where the goal is fail-closed because it would land before the brief (comment at `scripts/handoff-fire.sh:3575-3579`).
- The goal call is `if engage_rc_consequence "$rc" goal; then arm_goal … else goal_unreachable` (`scripts/handoff-fire.sh:13232-13233`; I read the `else` branch but did not anchor its line).
- The callers pass rc 0, 2, 4, 5 and 1 (`scripts/handoff-fire.sh:13273,13289,13301,13323,13365`).
- On a non-zero rc that still opens a debt, stderr says "custody debt OPENED anyway" (`scripts/handoff-fire.sh:13227`).

### Every producer
A regex scan of `bin`, `scripts`, `hooks`, `lib`, `tools` and `autonomy` found four `open` call sites in three files.
1. `scripts/handoff-fire.sh:13220` is the local peer fire.
2. `bin/cc-offload:747` is the cloud API lane.
   - It uses `--target cloud:$sid`, `--marker "$sid"` and `--slug cloud-$sid`.
   - It passes `--notify-back` from `UP_NOTIFY_BACK`.
   - It passes `--originator-pane` from `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`, with `##*:` stripped (`bin/cc-offload:746-750`).
3. `bin/cc-dispatch:904` is the legacy-CLI cloud leg. It passes no notify-back and no originator pane.
4. `bin/cc-dispatch:932` is the declared cloud path. It passes `--notify-back` only if `~/.claude/cc-roles/desk` exists, and no originator pane.

`cc-cloud declare --custody` only stores the marker on the declaration (`bin/cc-cloud:311,988`). It does not call `cc-custody`.

Rows from sites 3 and 4 fail the wrap-ledger and wake-floor `known` test (`originatorPane` or `notifyBack` non-empty) unless `notifyBack` is present. Without it they count as "unattributable".

## 2. DISCHARGING

The verbs are `return` and `abandon`, and both append a row. `abandon` requires `--why` (`bin/cc-custody:212`).

### How a single-token discharge works
- It matches `.marker == $t or .slug == $t` over the open set and takes `first // empty` (`bin/cc-custody:216`).
- It iterates `_files_for "$CWD"` and breaks at the first file that matches (`bin/cc-custody:214-220`).
- With no match it prints "no OPEN row matches" to stderr and exits 0 (`bin/cc-custody:232`).

### Discharge sites

| # | Site | Verb and key | Scope | Condition |
|---|---|---|---|---|
| 1 | `scripts/handoff-fire.sh:8707` (self-close) | `return`, marker read from the peer's own fired stamp (`:8657`) | store-wide (no `--cwd`), so it can run from any cwd | The marker is non-empty. It sits after the terminal ledger refusal (`:8669-8673`), so a refused close does not discharge. |
| 2 | `hooks/mailbox-drain.sh:579` | `return`, slug parsed from `HANDOFF-PING <slug>:` (`:585`; deduped and capped at 8, `:586`) | `--cwd "$_cust_cwd"` (`:567-568`) | The `CC_DRAIN_CUSTODY_RETURN` kill switch is not 0 and the mail body contains `HANDOFF-PING` (`:558`). It is counted as discharged only when stderr is empty. |
| 3 | `scripts/cloud-return.sh:979` | `return "$custody"` | store-wide | `landed_ok -eq 0` (`:978`); otherwise the row is "left OPEN" (`:973-981`). |
| 4 | `scripts/cloud-return.sh:537` | `abandon "$custody" --why "cloud session superseded…"` | store-wide | `item_is_done "$item"` (`:534`) and the custody field is non-empty (`:536`). |
| 5 | `scripts/cloud-retire-terminal.sh:204-207` (`settle_custody`) | `return` when the verdict is `landed`; otherwise `abandon --why "cloud declaration retired: <verdict>…"`. Marker from the declaration's `custody` field (`:201`) | store-wide | The marker is non-empty and the binary is resolved. |
| 6 | `bin/cc-custody:186-209` (`abandon --stale --why`) | Bulk. It uses each row's own marker, slug and target (`:197-199`), so no join token is needed. | `_files_for "$CWD"` (`:206`): one file with `--cwd`, else store-wide | `--why` is given (`:187`) and the row's derived `stale` is true (`:194`). Stale means age ≥ `CC_CUSTODY_TTL_HOURS`, default 24 (`:66`, `:118-122`). |

Why each site uses the key it does (`bin/cc-custody:25-32`; `hooks/mailbox-drain.sh:532-548`):
- Sites 1, 3, 4 and 5 hold the marker, which is globally unique. That is why they can discharge store-wide from any cwd.
- The drain sees only the slug, because the marker is never sent to the peer. Two originators can collide on a slug, so the drain must be cwd-scoped. A store-wide slug discharge could silently drop another cwd's debt.
- Cost of that scoping: an originator that recycled into a new worktree keys a new cwd, and its old rows stay open.

**Details on the sites:**
- **Site 1 (self-close)** discharges on `--successor` and `--recycle` closes too. The refusal is terminal-only (comment `scripts/handoff-fire.sh:8675-8677`).
- **Site 1 (dry run)** puts the discharge at `:8707`, before the `SC_DRY` branch at `:8709`. I did not check for an earlier dry-run exit.
- **Site 2 (drain)** discharges on receipt of the ping, not on collecting the work. The note says "reported, not yet collected" (`hooks/mailbox-drain.sh:591-592`).
- **Site 2 (drain, one match)** discharges one row per slug per ping, because the match takes `first`.
- **Site 5** takes the abandon path on any non-`landed` verdict. Its comment lists `gone`, `conflict` and `superseded` (`scripts/cloud-retire-terminal.sh:182-190`).
- **Site 6 (bulk)** has no automated caller. My scan found only prose mentions of the verbs, in message strings. The same holds for manual `return` and `abandon`, which the messages tell the operator to run (`scripts/wrap-ledger.sh:2009`, `hooks/completion-assert.sh:719`).

### Nothing expires or deletes a row automatically
- The header says "NOT expiry … Nothing here deletes, nothing here rewrites" (`bin/cc-custody:45-52`).
- The usage text says "nothing ever expires" (`bin/cc-custody:268-271`).
- Every write is a `>>` append (`bin/cc-custody:179,199,227`).
- Bare `count --open` counts stale rows (`bin/cc-custody:263`).
- `scripts/growth-coverage.conf:211` exempts the custody directory from reaping: "an OPEN debt must never be reaped".
- What does happen automatically is verdict-driven discharge by sites 3–5, which is not age-based.
- A row with a missing or unparseable `ts` gets `ageHours` null and is never stale (`bin/cc-custody:59`, `:118-122`).

### Does the deathwatch discharge anything? No.
- The script says "It NEVER discharges a debt" (`scripts/custody-deathwatch.sh:44`), "cannot discharge custody" (`:66`) and "NEVER discharge" (`:73`).
- In code, `CUSTODY_BIN` appears only at `:138` (resolve), `:277` (existence check) and `:282` (`list --open --json`, store-wide).
- It only notifies. Its messages tell people to run `return` or `abandon` (`scripts/custody-deathwatch.sh:353,388`).
- It is driven from `scripts/autonomy-sweep.sh:1914`.
- Its report condition is oracle says GONE **or** the row is stale (`scripts/custody-deathwatch.sh:53-60`).
- `hooks/lead-crash-watchdog.sh` mentions custody only in a comment (`:218`). A scan of non-comment lines there found no `cc-custody` call.

## 3. CONSUMING

### 3a. wrap-ledger: the close-ledger rung
- The reading function is `count_open_custody` (`scripts/wrap-ledger.sh:1048-1085`). It is called at `scripts/wrap-ledger.sh:1997`, then `if [ "$CUSTODY_OPEN" -gt 0 ]` at `:1998`.
- **Where in the ladder.** The ladder is:
  - ⛔ at `:1972`
  - dirty 🔧 at `:1979`
  - DoD-remainder 🔧 at `:1981`
  - 📦 at `:1983`
  - an `else` arm that is "✅-eligible on the git facts" (`:1990-1993`)

  Custody is counted only in that last arm, and it outranks the no-trunk 🔧 (`:1999-2001`; the no-trunk rung is at `:2052`).
- **Consequence for earlier turns.** The count is not paid for on turns already decided by ⛔, 🔧 or 📦. The initial state is `CUSTODY_OPEN=0; CUSTODY_SRC="skip"` (`:1047`, comment `:1991-1994`).
  - On those turns the emitted `CUSTODY_OPEN=0` (`:2202`) means "not counted", not "none open".
  - That includes the completion-assert and operator-readout fields.
- **The count.**
  - The raw pane key is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with `##*:` stripped (`:1061`).
  - With a pane and jq it runs `list --open --cwd "$PWD" --json`, bounded to 5 s (`:1063`).
  - The jq test defines `known` as `originatorPane` or `notifyBack` non-empty (`:1066`).
  - `mine` is true when any of these hold (`:1067-1069`):
    - `originatorPane == pane`
    - `notifyBack == pane`
    - `notifyBack` ends in `-<pane>`
  - `CUSTODY_MINE` counts rows that are `known` and `mine`.
  - `CUSTODY_UNK` counts rows that are not `known`.
  - Rows that are `known` but not `mine` are dropped (`:1070`).
  - `CUSTODY_OPEN = MINE + UNK` and `SRC=pane` (`:1076`).
- **Fallbacks.**
  - Without a pane or jq it runs `count --open --cwd "$PWD"` (`:1081`), giving `SRC=cwd`, `MINE=0` and `UNK=n` (`:1084`).
  - An unreadable store gives `OPEN=0` and `SRC=error` (`:1082-1083`).
  - A missing binary gives `SRC=none` (`:1057`).
- **Rung text.** `SRC=pane` with `MINE==0` gives 🔧 "cannot say whose" (`:2006-2007`). Otherwise it gives 🔧 "have NOT returned" (`:2009`).
- **Emitted fields.** `CUSTODY_OPEN`, `CUSTODY_SRC`, `CUSTODY_MINE` and `CUSTODY_UNK` are emitted at `:2202-2208`.

### 3b. Other consumers

| Consumer | Line that reads the count | What it does |
|---|---|---|
| completion-assert (done-claim gate) | `hooks/completion-assert.sh:718` `CUSTODY="$(lfield CUSTODY_OPEN)"` | `[ "$CUSTODY" -gt 0 ] && { contra=1; … }` (`:719`). It consumes the ledger field and does not re-derive it (`:716`). It reads only `CUSTODY_OPEN`. |
| session-continue wake floor (Stop hook) | `hooks/session-continue.sh:744` `list --open --cwd "$cwd" --json`, or `:762` `count --open` | Runs the same `known`/`mine` jq (`:748-754`), then `cust=$((cust_mine+cust_unk))` (`:758`). The floor fires on `[ "$cnt" -eq 0 ] \|\| [ "$pend" -gt 0 ] \|\| [ "$cust" -gt 0 ] \|\| return 0` (`:805`), so open custody re-fires it even after an earlier decline. Wording splits mine and unknown (`:878-884`). |
| operator-readout | `hooks/operator-readout.sh:915` `custody="$(lf CUSTODY_OPEN)"` | Adds "N dispatched session(s) NOT returned" to the 🔧 state (`:929`) and a `cc-custody list` hint (`:939-940`). It never changes the fire predicate (`:911-914`). |
| session-busy | `hooks/lib/session-busy.sh:302` `case "${CC_BUSY_CUSTODY_OPEN:-0}" …` | Adds a `custody` arm to the busy list. wrap-ledger feeds it `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"` (`scripts/wrap-ledger.sh:2143`). |
| custody-deathwatch | `scripts/custody-deathwatch.sh:282` `list --open --json` | The only store-wide, cwd-unscoped reader (`:39-41`). It sees the `/` shard that cloud fires from the launchd dispatcher write to (`:11-15`). |

`hooks/lib/why-tier.sh:205-212` is guidance text only and reads nothing. I found no other code consumers. Non-comment `custody` lines in `cc-teardown`, `cc-pane`, `cc-backlog`, `lr-transplant`, `compressor-sentinel`, `ship-land`, `cloud-reconcile` and `cloud-return-lane` returned nothing.

## 4. Citation audit (comments checked against the file they point at)

| Claim | Where | Verdict |
|---|---|---|
| Custody debt at `:10715`, /goal arm at `:10723` | `scripts/handoff-fire.sh:3520` | **Does not hold.** Those lines are the notify-back default and the `NB_SLUG` comment. The sites are `:13220` and `:13232`. |
| fire_cleanup "worktree … KEPT" at `:9064` | `scripts/handoff-fire.sh:3557` | **Does not hold.** `:9064` is an unrelated freshness-gate comment. The message is at `:10942`. |
| `bin/cc-custody:212-227` for `--why` on `return` | `scripts/handoff-fire.sh:8705` | **Holds.** `:212` is the `--why` guard and `:227` is the row write. |
| handoff-fire `:8936` defers to a "ping-receipt discharger" | `hooks/mailbox-drain.sh:523` | **Does not hold.** `:8936` is the `--transplanted-source` argument parser, and the quoted phrase is not in `handoff-fire.sh`. |
| slug at `:7087`, ping recipe at `:7100` | `hooks/mailbox-drain.sh:533-541` | **Unchecked.** The slug is derived at `:10721` today. |
| `$_opane` "captured at :197" | `hooks/session-continue.sh:724` | **Does not hold.** It is captured at `:420-425`. |
| Raw pane key at `session-continue.sh:302` | `scripts/wrap-ledger.sh:1058` | **Does not hold.** `:302` is `else echo "inactive"; fi`. |
| Attribution rule at `session-continue.sh:608-612` | `scripts/wrap-ledger.sh:1018` | **Does not hold.** `:608-612` are local declarations. The rule is at `:713-730` and `:748-754`. |
| POLARITY at `cc-custody:35-38` | `scripts/wrap-ledger.sh:1016` | **Roughly holds.** POLARITY starts at `:36` and runs past `:38`. |
| "cc-custody refuses a second discharge" | `scripts/cloud-retire-terminal.sh:180` | **Loosely worded.** It is an rc-0 no-op with a stderr line (`bin/cc-custody:232`). |
| Producers are handoff-fire and mailbox-drain | `bin/cc-custody:22-24` | **Incomplete.** The drain only discharges, and `cc-offload` and `cc-dispatch` also open rows. |
| Header says handoff-fire returns "from sc_announce_before_retire" | `bin/cc-custody:22-24` | **Not confirmed.** The return call is `scripts/handoff-fire.sh:8707`, after the announce call at `:8652-8653`. I did not read the function body. |

## 5. Not verified
- `sc_announce_before_retire` body.
- What the `ship-land.sh:4685` TTL comment refers to.
- Whether `FIRE_MARKER` at `scripts/handoff-fire.sh:10785` is set on every path.
- `cloud-return.sh` ping text.
- I hit the tool budget while cross-checking. One consequence is that cloud rows use slug `cloud-$sid` (`bin/cc-dispatch:932`), while the drain header says cloud pings look like `cloud/<id>` (`hooks/mailbox-drain.sh:533-534`). That suggests cloud rows are never discharged by the drain and only by marker through `cloud-return`. It is an inference I did not confirm.
