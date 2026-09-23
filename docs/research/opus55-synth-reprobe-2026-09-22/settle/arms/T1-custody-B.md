<!-- arm B = claude-opus-5-5 @high · brief T1-custody · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# Custody debt lifecycle (repo @ 47c3317eb)

## 1. Recording

### The store and the file
- **Store directory:** `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`).
- **One file per originator cwd:** `$CUSTODY_DIR/<key>.jsonl`, append-only (`bin/cc-custody:179`).
- **How the filename key is made:** `_fired_cwd_key` in `hooks/lib/origin-identity.sh:68-78`.
  - It resolves the cwd physically with `cd "$d" && pwd -P` (`:74`). This stops `/tmp` and `/private/tmp` from producing two keys (`:71-73`).
  - It then takes the first 32 hex characters of the path's `shasum -a 256` (`:76`).
  - If the cwd does not resolve, there is no key, and `open` dies with "cwd does not resolve" (`bin/cc-custody:177`).
  - The handoff-fire passthrough swallows that failure (`scripts/handoff-fire.sh:4154-4156`).

### Row fields
Built by `_row` (`bin/cc-custody:93-104`).
- **Always present:** `ts` (UTC, whole seconds, `:85`), `kind` (open, return or abandon), `cwd`.
- **Written only when non-empty:** `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` (`:97-103`).
- `open` always passes an empty `why` (`:179`).
- Discharge rows never write `notifyBack` or `provenance`. They copy `cwd`, `targetPane`, `marker` and `slug` from the matched open row (`:195-199`, `:223-227`).

### How the open set is computed at read time
`_OPEN_JQ` (`bin/cc-custody:108-112`):
- **Join key:** `"m:"+marker` when `marker` is non-empty (`:110`).
- **When `marker` is missing or empty:** the key falls back to `"s:"+slug+"|"+targetPane` (`:110`). A row with neither marker nor slug keys as `s:|<targetPane>`.
- **Which row wins:** rows are grouped by key, and the row with the latest `ts` wins (`group_by(.k) | map(sort_by(.ts) | last)`). Only groups whose winner has `kind=="open"` survive (`:111`).
- **Ties:** `ts` has one-second resolution (`:85`). When two rows share a second, the order they were fed in decides. That relies on jq's `sort_by` being stable, which is a jq property rather than something this repo's code states.
- **Input streams:** `list` and `count` fold the concatenation of every file in scope (`cat $files`, `:240`, `:263`). `return` and `abandon` fold one file at a time (`:216`).
- **Age annotation:** `_AGE_JQ` adds `ageHours` and `stale = ageHours >= TTL` (default 24) (`:66`, `:118-121`). An unparseable `ts` gives `ageHours: null` and `stale: false` (`:119-121`).

### When `handoff-fire.sh` opens a row
The exact condition (`scripts/handoff-fire.sh:13219`):
```
[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody
```
- **`NB_ARMED_TARGET`** is set to `$BACK_SID` only where the back-channel trailer is actually appended to the brief (`:10722-10728`).
- **Gated on `ENGAGE_VERIFY=1`.** This code runs inside `engage_apply_consequences`, which is only reached when `ENGAGE_VERIFY=1`. That variable defaults to 0 (`:509`) and becomes 1 only when `RECYCLE=0` and `DRY=0` (`:10662`). So `--recycle` fires and dry runs never open a row (the rationale is at `:13213-13218`).
- **Keyed on the firing session's cwd, not the peer's worktree:** `--cwd "$PWD"` (`:13220`). The comment at `:13199-13200` says the same.
- **Other fields on the row:**
  - `--target "$SPAWNED_PANE"`
  - `--marker "${FIRE_MARKER:-}"`, which may be empty, in which case the slug/target key applies
  - `--slug "${NB_SLUG:-}"`, where `NB_SLUG` is the prompt file's basename without its extension (`:10721`)
  - `--notify-back "$NB_ARMED_TARGET"`
  - `--originator-pane "${FIRING_SID:-}"`, set at `:11279` and `:12189`
  - `--provenance`: `proven` on rc 0, otherwise `unproven-rc<code>` (`:13196-13197`, `:13220-13223`)
- **Stderr note:** a non-zero code prints "custody debt OPENED anyway" (`:13227`).

### What each engagement outcome does
`engage_apply_consequences` is called with its own internal codes, which are not the same numbers as `ENGAGE_RC`:

| Outcome (call site) | Internal code | Opens custody? | Arms /goal? |
|---|---|---|---|
| engaged (`:13273`) | 0 | yes (`:3550`) | yes |
| never-engaged, when `ENGAGE_RC=2` (`:13364-13365`) | 1 | **yes**, with provenance `unproven-rc1` (`:3574`) | **no** (`:3580`) |
| pane-parked (`:13289`) | 2 | no (`:3583`) | no |
| pane-wedged (`:13301`) | 4 | yes (`:3589`) | yes |
| engagement-unproven / cannot tell (`:13323`) | 5 | yes (`:3592`) | yes |
| any code not in the table | — | yes, fails open with a stderr warning (`:3593-3595`) | yes |

The /goal arm uses the same table (`:3230` calls `engage_rc_consequence "$rc" goal`). It diverges from custody on exactly one code, never-engaged, because pasting a goal before the brief has been ingested would be a wrong first instruction (`:3575-3580`).

### Every producer of `open` rows
1. **`scripts/handoff-fire.sh:13220`** (above).
2. **`bin/cc-offload:747-750`** (cloud fires):
   - `--cwd "$PWD"`, `--target "cloud:$sid"`, `--marker "$sid"`, `--slug "cloud-$sid"`
   - `--notify-back` only if `UP_NOTIFY_BACK` is set
   - `--originator-pane` from `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}##*:` (`:746`)
   - It opens at the fire, not at the return (`:728-731`).
3. **`bin/cc-dispatch:903-905`** (the legacy adopted cloud leg): marker and slug as in cc-offload, but **no `--notify-back` and no `--originator-pane`**. These rows can never be attributed to a pane.
4. **`bin/cc-dispatch:931-933`** (declared cloud fire): `--notify-back` is read from `~/.claude/cc-roles/desk` (`:922`); there is no originator pane.

**Header claims that do not hold:**
- The header at `bin/cc-custody:22-24` names only `handoff-fire.sh` as an opener.
- Its premise "notify-back armed ⇒ a return is owed" is false for producer 3, which opens with no notify-back at all.

## 2. Discharging

The `return`/`abandon` token matches **either** field: `select(.marker == $t or .slug == $t)` against the open set, taking the first match (`bin/cc-custody:216`).
- It walks the files in scope and stops at the first file that matches (`:214-221`).
- Without `--cwd` the scope is every `*.jsonl` in the store (`:136`). With `--cwd` it is only that cwd's file (`:132-134`).
- The discharge row is appended to the matched file (`:223-227`).
- No match prints "no OPEN row matches" to stderr and exits 0 (`:229-233`).

**Discharge sites, exhaustively:**

1. **`handoff-fire.sh self-close`** (`scripts/handoff-fire.sh:8707`)
   - Call: `_hf_custody return "$_sc_cmk" --why "$SC_LEDGER_STAMP"`.
   - **Key:** the marker, read from the peer's own fired-peer stamp (`:8657`). `mark_fired_peer` wrote it from `FIRE_MARKER` (`:4535`). The peer can only use the marker because that stamp is the only custody field it holds.
   - **Scope:** store-wide (no `--cwd`), which is safe because the marker is unique.
   - **Conditions:**
     - The marker must be non-empty.
     - The discharge comes after every gate that can abort the close. The W3-B1 terminal refusal exits 8 *before* it (`:8674-8700`), deliberately, so a refused close never discharges (`:8669-8673`).
     - A stamp missing at close time can be repaired from the brief contract, which lets this path discharge (`:8390-8396`).
   - **Defect:** `SC_DRY` is read only at `:7985` and `:8709`. The discharge at `:8707` comes before the dry-run branch, so `self-close --dry-run` appears to append a real `return`.
   - **Citation that does not hold:** `bin/cc-custody:22-23` and `scripts/custody-deathwatch.sh:36-37` say the discharge happens inside `sc_announce_before_retire`. It is a separate step after that call (`:8652-8653` vs `:8707`).

2. **`hooks/mailbox-drain.sh` ping receipt** (`:558-587`)
   - Call: `return "$_slug" --cwd "$_cust_cwd"`.
   - **Key:** the slug parsed from `HANDOFF-PING <slug>:` (`:584`). The slug is the only custody field the ping carries; the marker is never sent to the peer (`:532-536`).
   - **Scope:** the cwd, taken from the hook JSON's `.cwd` with `$PWD` as fallback (`:567-568`). It is cwd-scoped because slugs can collide across originators (`:542-549`).
   - **Conditions:**
     - Kill switch `CC_DRAIN_CUSTODY_RETURN` must not be 0.
     - The message body must contain `HANDOFF-PING`.
     - Slugs are de-duplicated and capped at 8 (`:584-586`).
     - Success is read as "stderr was empty" (`:578`).
   - **It cannot discharge cloud rows**, although `:533-534` says cloud-return "mirrors that shape":
     - Cloud pings say `HANDOFF-PING cloud/$id:` (`scripts/cloud-return.sh:844`, `:1001`).
     - Cloud rows carry slug `cloud-$sid` and marker `$sid` (`bin/cc-offload:747-748`, `bin/cc-dispatch:904`, `:932`).
     - So the token `cloud/<id>` matches neither field.

3. **`scripts/cloud-return.sh` superseded arm** (`:536-538`)
   - Call: `abandon "$custody" --why "cloud session superseded — …"`.
   - **Key:** the declaration's `.custody` field, which is the marker (`:514`). Store-wide.
   - **Condition:** `item_is_done "$item"`.

4. **`scripts/cloud-return.sh` step 9** (`:977-983`)
   - Call: `return "$custody"`. Store-wide, by marker.
   - **Condition:** `landed_ok -eq 0`, a content-verified land. Otherwise the row is left open (`:973-975`, `:984`).

5. **`scripts/cloud-retire-terminal.sh` `settle_custody`** (`:200-209`)
   - **Key:** the marker from the declaration (`field … custody`). Store-wide.
   - Verdict `landed` calls `return`. Any other verdict (gone, superseded, conflict) calls `abandon --why "cloud declaration retired: <verdict> …"`.
   - **Condition:** both the marker and the binary are present.

6. **Bulk `cc-custody abandon --stale --why …`** (`bin/cc-custody:186-209`)
   - Appends one `abandon` row per stale open row. Scope is `--cwd`, or store-wide if none is given. `--why` is required.
   - **No script calls it.** It exists only for manual use. The only `--stale` reader is `count --open --stale` in `commands/are-we-done.md:23`.

7. **Manual `cc-custody return|abandon <token>`** by an agent or the operator. The readouts prompt for it (`hooks/lib/why-tier.sh:210-212`, `scripts/wrap-ledger.sh:2009`, `hooks/completion-assert.sh:719`).

**Nothing expires or deletes a row automatically.**
- The store is append-only; age only classifies rows (`bin/cc-custody:45-58`), and the usage text ends "nothing ever expires" (`:271`).
- `scripts/growth-coverage.conf:211` exempts `autonomy/custody` from reaping.

**The deathwatch/reaper does not discharge anything.**
- `scripts/custody-deathwatch.sh` calls the binary only at `:277` (a presence check) and `:282` (`list --open --json`).
- Its header states "It NEVER discharges a debt" (`:42`) and "can only ever ADD a notification" (`:62`).
- It is launched from `scripts/autonomy-sweep.sh:1914`.

## 3. Consuming

### `scripts/wrap-ledger.sh` — the close-ledger rung
- **The count is read by** `count_open_custody` (`:1048-1085`).
- **When the count is taken:** only at `:1997`, inside the ✅-eligible `else` branch. That branch comes after ⛔ `BLOCKED` (`:1968`), dirty tree (`:1976`), DoD remainder (`:1978`) and unlanded commits (`:1980`).
- **What that implies:** on any ⛔, 🔧 or 📦 turn the custody count is never computed. It stays at its initial `CUSTODY_OPEN=0; CUSTODY_SRC="skip"` (`:1047`), and every downstream consumer sees 0 on those turns.
- **Effect on the rung:** open custody greater than 0 gives 🔧, ranked ahead of no-trunk, live-layer and operator-step checks (`:1998-2010`).
- **Attribution:**
  - "Your" identity is the raw pane `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}##*:` (`:1062`).
  - A row is **mine** when `originatorPane == pane`, or `notifyBack == pane`, or `notifyBack` ends with `"-"+pane` (`:1066-1069`).
  - A row is **unk** when it carries neither field (`:1066`, `:1070`).
  - A row naming a *different* pane is dropped.
  - `CUSTODY_OPEN = MINE + UNK`, with `SRC=pane` (`:1076`).
  - With no pane, no jq, or unreadable JSON, it falls back to `count --open --cwd "$PWD"`: all rows count as `UNK`, with `SRC=cwd` (`:1081-1084`).
- **Emitted fields:** `CUSTODY_OPEN`, `CUSTODY_SRC`, `CUSTODY_MINE`, `CUSTODY_UNK` (`:2202-2208`). The `--full` line renders them at `:2313-2327`.
- **Also exported** to `hooks/lib/session-busy.sh` as `CC_BUSY_CUSTODY_OPEN` (`:2143`), where `sb_idle_arms` adds an arm named "custody": `case "${CC_BUSY_CUSTODY_OPEN:-0}" in ''|0|*[!0-9]*) : ;; *) arms="$arms custody"` (`hooks/lib/session-busy.sh:302`).

### `hooks/completion-assert.sh` — the done-claim gate
- Reads `CUSTODY="$(lfield CUSTODY_OPEN)"` (`:718`).
- If it is greater than 0 it sets `contra=1`, so a done-claim is contradicted (`:719`).
- Because the value comes from wrap-ledger, it can only be non-zero on ✅-eligible turns, which `:717` acknowledges.

### `hooks/session-continue.sh` — the Stop/wake floor
- It **recomputes the count itself** rather than reading the ledger (`:731-765`):
  - `list --open --cwd "$cwd" --json`, with the same mine/unk jq as wrap-ledger (`:744-758`).
  - The pane identity is `$_opane`, the raw pane captured at `:420`/`:425`.
  - Fallback: `count --open --cwd "$cwd"` (`:762`).
- **Fire condition:** `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`).
- **It does not reach the custody read when:**
  - a watcher is already armed (`mailbox_wake_armed` → return, `:614`), or
  - a /goal is live *and* mail is pending (`:697-702`).
- **Messages:** separate wording for mine vs unattributable rows (`:878-882`); logged as `cust_mine`/`cust_unk` (`:890-891`).

### `hooks/operator-readout.sh` — operator-facing readout
- Reads `custody="$(lf CUSTODY_OPEN)"` (`:915`).
- In the 🔧 arm it renders "N dispatched session(s) NOT returned" (`:931`) and points to `→ cc-custody list --open --cwd .` (`:939-940`).

### Others
- **`scripts/custody-deathwatch.sh:282`** — `OPEN_JSON="$("$CUSTODY_BIN" list --open --json …)"`. This is store-wide on purpose, so it sees the `/`-cwd cloud file (`:39-41`). It notifies or files a backlog row; it never discharges.
- **`commands/are-we-done.md:22-23`** — `cc-custody list --open --fresh` and `cc-custody count --open --stale`. Neither passes `--cwd`, so both are store-wide, unlike every hook consumer.
- **`hooks/lib/why-tier.sh:204-212`** — explanatory prose only; it does not read the store.

## Citations checked against the code

| Citation | Claim | Verdict |
|---|---|---|
| `bin/cc-custody:22-24`, `:33-35` | producer and consumer lists | Incomplete: missing cc-offload, cc-dispatch, cloud-return, cloud-retire-terminal, deathwatch, session-busy and are-we-done. |
| `bin/cc-custody:22-23` and `scripts/custody-deathwatch.sh:36-37` | discharge happens "from sc_announce_before_retire" | Does not hold (see §2 item 1). |
| `scripts/handoff-fire.sh:3557` | `:9064` holds the "KEPT — the pane is live" message | Stale: the message is at `:10942`. |
| `scripts/handoff-fire.sh:3520` | `:10715`/`:10723` are the custody and goal sites | Stale: they are now at `:13220`/`:13230`. |
| `hooks/mailbox-drain.sh:523` | `handoff-fire.sh:8936` | Stale: that line is `--transplant-cause` argument parsing. |
| `hooks/mailbox-drain.sh:533` | `:7100` arms the ping | Stale: the ping recipe is at `:10734`. |
| `hooks/mailbox-drain.sh:544` | `:7087` is the slug basename | Stale: it is at `:10721`. |
| `scripts/wrap-ledger.sh:1016` | `cc-custody:35-38` (POLARITY) | Off by one: POLARITY is at `:36-39`. The `:44-46` citation roughly holds. |
| `scripts/wrap-ledger.sh:1018` | `session-continue.sh:608-612` holds the hedge rule | Does not hold: those lines are wake-floor setup. The rule is at `:725-729`. |
| `scripts/wrap-ledger.sh:1059` | `session-continue.sh:302` captures the pane | Does not hold: line 302 is `else echo "inactive"; fi`. The capture is at `:420`/`:425`. |
| `hooks/session-continue.sh:724` | `$_opane` is captured at `:197` | Does not hold: it is at `:425`. |
| `scripts/cloud-retire-terminal.sh:180` | cc-custody "refuses a second discharge" | Effect holds, mechanism does not: there is no refusal. An unmatched token is a stderr note with rc 0 (`bin/cc-custody:229-233`). |
| `scripts/handoff-fire.sh:8705` | `cc-custody:212-227` | Holds. |
| `scripts/handoff-fire.sh:13213` | `ENGAGE_VERIFY=0` iff RECYCLE or DRY | Holds (`:509`, `:10662`). |
| `hooks/completion-assert.sh:717` | the count is computed on the ✅-eligible path | Holds (`scripts/wrap-ledger.sh:1997`). |
| `scripts/custody-deathwatch.sh:10-11` | how cc-offload resolves the originator pane | Holds (`bin/cc-offload:746`). |