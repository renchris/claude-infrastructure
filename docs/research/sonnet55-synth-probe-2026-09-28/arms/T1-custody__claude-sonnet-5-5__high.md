# Custody debt lifecycle at sha 47c3317eb

Every `path:line` below comes from a line I read. Anything I inferred rather than read is marked.

## 1. Recording

### Store and file

- **Location.** The store is `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:13`, `:65`).
- **One file per originator cwd.** The file is `<cwd-key>.jsonl` (`bin/cc-custody:13`, `:179`).
- **Filename derivation.** The key is `_fired_cwd_key`. It resolves the cwd with `cd … && pwd -P`, takes the SHA-256 of the resolved path, and keeps the first 32 hex characters (`hooks/lib/origin-identity.sh:68-77`).
  - `/tmp` and `/private/tmp` therefore map to the same file (`origin-identity.sh:71-74`).
  - A cwd that does not resolve gives an empty key, and `open` dies with "cwd does not resolve" (`bin/cc-custody:177`).
- **Append-only.** Rows are only ever added with `>>` (`bin/cc-custody:179`, `:199`, `:227`). Nothing in the file rewrites or deletes.

### Row fields

`_row` (`bin/cc-custody:93-104`) always writes `ts`, `kind` (open, return or abandon) and `cwd`. It adds the rest only when non-empty:

- `originatorPane`
- `targetPane`
- `marker`
- `slug`
- `notifyBack`
- `why`
- `provenance`

Details on which rows carry what:

- `open` requires `--cwd` and `--target` (`:176`). It always passes `why=""`, so open rows never carry `why` (`:179`).
- `provenance` is written by `open` only. The return/abandon rows are built without a provenance argument (`:223-228`).

### Computing the open set

The jq program is `_OPEN_JQ` (`bin/cc-custody:108-112`):

- **Join key.** `k` is `"m:"+marker` when the marker is non-empty (`:110`).
- **Marker missing.** `k` becomes `"s:"+slug+"|"+targetPane`, with a missing slug or targetPane read as `""` (`:110`). If both are absent too, the key is the bare `"s:|"`. That is my inference from the expression, not something I read stated.
- **Winner per key.** Rows are grouped by `k`, sorted by `ts`, and the last one is taken (`:111`). Only survivors with `kind=="open"` remain.
- **Ties.** `ts` has one-second resolution (`:85`). A same-second open and return therefore tie, and the outcome depends on jq's sort stability. I did not verify that.
- **Discharge rows keep the key.** A discharge row copies `marker`, `slug` and `targetPane` from the matched open row (`:223-227`), so it lands on the same key.
- **Age fields (annotation only).** `ageHours` and `stale` (age ≥ `CC_CUSTODY_TTL_HOURS`, default 24) are added by `_AGE_JQ` (`:118-122`, `:66`). An unparseable `ts` gives null age and `stale=false` (`:119-121`).
- **`count --open`.** The bare form does not apply the age filter, so stale rows still count (`:256-257`, `:263`).

### The condition that opens a row (handoff-fire)

The condition is `handoff-fire.sh:13219`:

```
[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody
```

- **`NB_ARMED_TARGET`** is set to `BACK_SID` only inside `if [ -n "$NOTIFY_BACK" ]`, where the back-channel trailer is appended (`:10720`, `:10728`). The comment at `:13208-13211` says the same: it is non-empty iff the trailer was written.
- **`SPAWNED_PANE`** must be set.
- **Engagement outcome.** The rc must license custody in the table below.
- **`--recycle` and dry runs.** They never reach this code. The comment at `:13213-13218` says `ENGAGE_VERIFY` is 0 iff `RECYCLE` or `DRY`.
- **Nesting not fully checked.** The callers of `engage_apply_consequences` are at `:13273-13365`, after `if [ "$ENGAGE_VERIFY" = 1 ]` at `:13239`. I did not read every line between them to confirm the nesting.

### Which directory the row is keyed on

- **Firing cwd.** The row is keyed on the firing session's cwd, not the target worktree: `--cwd "$PWD"` (`handoff-fire.sh:13220`). The comment says "keyed on the FIRING cwd, not the target worktree" (`:13199-13200`).
- **Target pane.** The target is recorded as `--target "$SPAWNED_PANE"`.
- **Not checked.** I did not verify that nothing `cd`s before `:13220`.

### Engagement outcomes and the consequence table

`engage_rc_consequence` (`handoff-fire.sh:3547-3597`):

| rc | Meaning | Opens custody? | Arms /goal? |
|---|---|---|---|
| 0 | Engaged | yes (`:3550`) | yes (`:3550`) |
| 1 | Never ingested | **yes** (`:3574`) | **no** (`:3580`) |
| 2 | Pane parked on a shell | no (`:3583`) | no (`:3583`) |
| 4 | Wedged on a modal | yes (`:3589`) | yes (`:3589`) |
| 5 | Cannot tell | yes (`:3592`) | yes (`:3592`) |
| anything else | Undocumented | yes, with a stderr warning (`:3593-3595`) | yes (`:3593-3595`) |

- **Provenance.** It is `proven` for rc 0 and `unproven-rc<N>` otherwise (`:13196-13197`).
- **Non-zero rc message.** A non-zero rc prints "custody debt OPENED anyway" to stderr (`:13227`).
- **Same rule for /goal?** Almost, but not identically. Both go through the same table (`:13219`, `:13232`), and they diverge only on rc 1, where custody opens and the goal does not.
  - The goal arm is not gated by `NB_ARMED_TARGET`.
  - The goal arm calls `arm_goal` if licensed, else `goal_unreachable` (`:13232-13236`).
  - The rc 1 rationale is `:3553-3580`.

### Every producer

1. **`scripts/handoff-fire.sh:13220`**, via `_hf_custody` (`:4147-4157`). It is best-effort and swallows failures.
2. **`bin/cc-offload:747`** (cloud). It uses `--cwd "$PWD"`, target `cloud:$sid`, marker `$sid` and slug `cloud-$sid`.
   - `--notify-back` is added only if `UP_NOTIFY_BACK` is set.
   - `--originator-pane` comes from `CC_PANE_ID`, else `ITERM_SESSION_ID`, with `##*:` stripped (`:744-748`).
   - It is not gated on notify-back.
3. **`bin/cc-dispatch:904`** (adopt path). It has marker `$sid` and slug `cloud-$sid`, and no notify-back or originator-pane.
4. **`bin/cc-dispatch:932`** (declare path). Same shape, but `--notify-back` comes from the desk role file (`:931-933`).

**Header gap.** The `cc-custody` header names only `handoff-fire` as the opener (`bin/cc-custody:22-24`). Producers 2–4 are missing from it. I searched `bin hooks scripts lib autonomy tools commands skills agents` and found no other openers.

## 2. Discharging

Every discharge is an appended `return` or `abandon` row.

| # | Site | Verb | Key | Scope | Precondition |
|---|---|---|---|---|---|
| A | `scripts/handoff-fire.sh:8707` (self-close) | `return … --why "$SC_LEDGER_STAMP"` | marker, read from the peer's own stamp (`:8657`) | store-wide (no `--cwd`) | `_sc_cmk` non-empty. Reached only after the terminal-refusal `exit 8` (`:8676-8701`), so a refused close discharges nothing (`:8668-8672`). |
| B | `hooks/mailbox-drain.sh:579` | `return "$_slug" --cwd "$_cust_cwd"` | slug, parsed from `HANDOFF-PING <slug>:` (`:585`) | this cwd only | `CC_DRAIN_CUSTODY_RETURN != 0` and the body contains `HANDOFF-PING` (`:558`). Slugs are deduped and capped at 8 (`:586`). The cwd is the hook payload's `.cwd`, else `$PWD` (`:567-568`). |
| C | `scripts/cloud-return.sh:979` | `return "$custody"` | marker, from the declaration (`:514`) | store-wide | `landed_ok -eq 0`. Otherwise "left … OPEN" (`:977-982`). |
| D | `scripts/cloud-return.sh:537` | `abandon --why "cloud session superseded — item … already done"` | marker | store-wide | `custody` and `CUSTODY_BIN` non-empty (`:536`), inside the superseded-item branch (`:531`). I did not read that branch's test. |
| E | `scripts/cloud-retire-terminal.sh:204-207` (`settle_custody`) | `return` if the verdict is `landed`, else `abandon --why` | marker from the declaration's `custody` field (`:202`) | store-wide | marker and `CUSTODY_BIN` non-empty. I did not read its callers. |
| F | manual, `cc-custody return\|abandon <token> [--cwd]` (`bin/cc-custody:182-234`) | either | marker or slug (`:216`) | store-wide unless `--cwd` (`:136`) | `abandon` needs `--why` (`:212`). |
| G | bulk, `abandon --stale --why` (`bin/cc-custody:186-210`) | `abandon` per row | none; rows are selected by age | `--cwd` file only, else all files (`:206`, `:136`) | `--why` is required (`:187`). Only rows with `.stale == true` are discharged (`:194`), meaning age ≥ TTL (`:121`). Prints the count (`:208`). |

### Why each site uses the key it uses

- **Marker sites (A, C, D, E).** They hold the marker. It is unique per fire, so they can discharge store-wide from any cwd (`bin/cc-custody:25-28`).
- **Slug site (B).** The slug is the only field echoed to the peer, as `HANDOFF-PING <slug>:` (`mailbox-drain.sh:532-536`).
  - A slug is a prompt-file basename (`handoff-fire.sh:10721`), so two originators can collide on one.
  - The drain therefore scopes to its own cwd (`mailbox-drain.sh:543-547`). The ping's recipient is the originator by construction (`:538-540`).
  - The accepted cost is that an originator recycled into a new worktree leaves its old rows open (`:548-550`).
- **One row per slug call (inference).** The token match takes `first` (`bin/cc-custody:216`). One slug call therefore discharges at most one open row. If two open rows in one cwd share a slug, one ping clears one.
- **B's "discharged" verdict is inferred.** It is read off empty stderr (`mailbox-drain.sh:576-579`).
- **Idempotent.** An unmatched token prints "no OPEN row matches" to stderr and returns rc 0 (`bin/cc-custody:232`).
- **G has no automated caller.** In the search above, the only `abandon --stale` occurrences are the usage text (`:268`) and the header. Nothing calls it.

### Automatic expiry or deletion

None. The header says "Nothing here deletes, nothing here rewrites" (`bin/cc-custody:47-49`) and "nothing ever expires" (`:271`). The TTL only annotates and selects (`:50-58`). The code confirms it: the only writes are the three `>>` appends listed above.

### Does the deathwatch or reaper discharge anything?

**No.**

- Its header says "It NEVER discharges a debt, never closes a row, never kills a process" (`scripts/custody-deathwatch.sh:47`).
- The code agrees. `CUSTODY_BIN` appears only at `:138` (resolve), `:277` (existence check) and `:282` (`list --open --json`, store-wide, no `--cwd`).
- `return` and `abandon` appear in its messages as advice to the reader (`:353`, `:388`).
- Its report condition is oracle GONE or row stale (header, around `:58`).
- `bin/cc-teardown` and `hooks/lead-crash-watchdog.sh` mention custody only in comments (`bin/cc-teardown:275`, `lead-crash-watchdog.sh:218`, `:1050`). They do not call `cc-custody`.

## 3. Consuming

### 3a. Close-ledger rung (`scripts/wrap-ledger.sh`)

**Reading the count.** `count_open_custody` (`:1048-1085`) does two things:

- With a pane id and `jq`, it runs `list --open --cwd "$PWD" --json` (`:1063`). It then sets `CUSTODY_OPEN=$(( CUSTODY_MINE + CUSTODY_UNK ))` with source `pane` (`:1076`).
- Otherwise it falls back to `count --open --cwd "$PWD"` (`:1081`). That sets `CUSTODY_MINE=0`, `CUSTODY_UNK=n` and source `cwd` (`:1084`).

**Where the count is taken.** The ladder runs in this order:

1. ⛔ if blocked (`:1972`).
2. 🔧 if dirty (`:1979`).
3. 🔧 if DoD remainder (`:1981`).
4. 📦 if unlanded (`:1983`).
5. Only in the final `else` (`:1990`) is `count_open_custody` called (`:1997`).
6. If `CUSTODY_OPEN -gt 0` (`:1998`), the rung is 🔧 (`:2007`, `:2009`). This ranks ahead of the operator-step, live-layer, filed, resident-member and no-trunk arms (`:1999-2001`, `:2012-2017`).

**What that implies.**

- On a turn already decided ⛔, 🔧-dirty, 🔧-remainder or 📦, custody is never counted (`:1991-1994`). `CUSTODY_OPEN` stays at its initial 0 with `CUSTODY_SRC="skip"` (`:1047`).
- The readout says "not counted (a worse rung governs)" (`:2328`).
- Downstream consumers that read the emitted `CUSTODY_OPEN` (`:2202`) see 0 on those turns.

**Attribution split.** The jq at `:1065-1071` defines two predicates:

- `known` means `originatorPane` or `notifyBack` is non-empty (`:1066`).
- `mine` means `originatorPane == $p`, or `notifyBack == $p`, or `notifyBack` ends with `"-"+$p` (`:1067-1069`).

The counts and their fields:

- `CUSTODY_MINE` counts `known and mine`. `CUSTODY_UNK` counts `not known`.
- Known-but-not-mine rows are dropped (`:1070`).
- The fields are emitted at `:2207-2208`.

Which spellings count as "yours":

- The pane is `CC_PANE_ID`, else `ITERM_SESSION_ID`, with `##*:` stripped (`:1061`).
- `notifyBack` is either the bare pane ("386") or `<worktree>-<pane>` ("wt-pool-2-415"). The `-` anchor stops pane 15 claiming pane 415's row (`:1037-1039`).

The rung message depends on the split:

- If source is `pane` and `CUSTODY_MINE -eq 0`, the message is hedged, uses `CUSTODY_UNK`, and does not assert originatorship (`:2006-2007`).
- Otherwise it uses the plain "have NOT returned" text with `CUSTODY_OPEN` (`:2009`).

The rendered `Dispatched:` line is at `:2313-2330`.

### 3b. Done-claim gate (`hooks/completion-assert.sh`)

- **Reading the count:** `CUSTODY="$(lfield CUSTODY_OPEN)"` (`:718`).
- **What it does:** `[ "$CUSTODY" -gt 0 ] && { contra=1; … }` (`:719`), so an open count contradicts a done-claim.
- **What it does not do:** it consumes the ledger's count and does not re-derive it (`:716`).
- **Consequence:** it sees 0 on turns where wrap-ledger skipped the count (see 3a).
- **Not read:** `lfield`'s implementation.

### 3c. Stop/wake floor (`hooks/session-continue.sh`)

- **Reading the count:** it re-derives the count itself rather than reading the ledger field.
  - `_cj="$("$_cb" list --open --cwd "$cwd" --json …)"` (`:744`).
  - It uses the same `known`/`mine` jq as wrap-ledger (`:748-754`), then `cust=$(( cust_mine + cust_unk ))` (`:758`).
  - The no-pane fallback is `count --open --cwd "$cwd"` (`:762`).
- **Pane key:** the raw `_opane` (`:425`).
- **Gate:** `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`). So the floor also fires for owned or unattributable open custody.
- **Messages:** "YOU fired" for `cust_mine` (`:878-880`), and hedged text for `cust_unk` alone (`:881-882`).
- **Telemetry:** the counts are logged at `:890-891`.
- **"No armed watcher" not confirmed.** The `cc-custody` header describes the floor as "idle + open custody + no armed watcher ⇒ arm the watcher" (`bin/cc-custody:34-35`). I did not read the armed-watcher test in the code.

### 3d. Operator readouts

- **`hooks/operator-readout.sh:915`:** `custody="$(lf CUSTODY_OPEN)"`.
  - It is used only inside the 🔧 arm (`:896`).
  - It adds "N dispatched session(s) NOT returned" to the state (`:929`) and "→ cc-custody list --open --cwd ." (`:939-940`).
  - It reads the unattributed sum, not MINE/UNK.
  - It does not change the fire predicate (`:911-914`).
- **wrap-ledger's own `Dispatched:` line** (`scripts/wrap-ledger.sh:2313-2330`).

### 3e. Others

- **Busy predicate.** `wrap-ledger.sh:2143` injects `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"`. `hooks/lib/session-busy.sh:302` reads it with `case "${CC_BUSY_CUSTODY_OPEN:-0}" in … *) arms="$arms custody"`.
  - This is computed after the ladder (`wrap-ledger.sh:2127`).
  - `wrap-ledger.sh:1012` says there are "three" consumers of `CUSTODY_OPEN`. This is a fourth.
- **Deathwatch.** `scripts/custody-deathwatch.sh:282` reads `list --open --json` store-wide. It is the only consumer that drops the cwd scope (`:39-41`).
- **Mailbox drain.** It discharges but does not read the count.
- **Documentation only.** `hooks/lib/why-tier.sh:203-213` is text about the custody debt. `scripts/ship-land.sh:4685` mentions the TTL in a comment only.

## Citations that do not hold

| Claim | Where | Actual |
|---|---|---|
| POLARITY at `cc-custody:35-38` | `wrap-ledger.sh:1016` | POLARITY is at `bin/cc-custody:36-39`. Off by one. |
| "session-continue.sh:608-612" applies the rule | `wrap-ledger.sh:1018` | Lines 606-613 are unrelated (`local mbxd sf …`). The rule is at `session-continue.sh:726-730`. |
| Raw pane key captured at "session-continue.sh:302" | `wrap-ledger.sh:1058` | `:302` is unrelated. The capture is `session-continue.sh:420`, `:425`. |
| Raw pane key captured at ":197" | `session-continue.sh:724` | `:197` is an unrelated comment. The capture is `:425`. |
| "custody debt (:10715) and /goal arm (:10723)" | `handoff-fire.sh:3520` | Now `:13219` and `:13232`. Stale. |
| `handoff-fire.sh:8936` "defers a restriction to 'custody v1.1 adds the ping-receipt discharger'" | `mailbox-drain.sh:523` | `:8936` is option parsing. That phrase appears nowhere in `handoff-fire.sh`. The restriction was lifted at `:13203-13211`. |
| Slug basename at ":7087", `HANDOFF-PING <slug>` armed at ":7100" | `mailbox-drain.sh:534`, `:545` | Both lines are unrelated comments. The slug is set at `handoff-fire.sh:10721`. |
| "cc-custody refuses a second discharge" | `cloud-retire-terminal.sh:180` | It does not refuse. It prints "no OPEN row matches" and returns rc 0 (`bin/cc-custody:232`). The effect is a no-op. |
| `--why` handled at "cc-custody:212-227" | `handoff-fire.sh:8705` | Roughly right. The flag is parsed at `:158`, checked at `:212`, and written at `:227`. |
| Producer list is `handoff-fire` plus `mailbox-drain` | `bin/cc-custody:22-24` | Incomplete. `cc-offload` and `cc-dispatch` also open rows. `cloud-return` and `cloud-retire-terminal` also discharge. |
| Consumer list | `bin/cc-custody:33-35` | Omits the deathwatch and `session-busy`. |
