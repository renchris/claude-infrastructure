<!-- arm C = claude-opus-5-5 @xhigh · brief T1-custody · settle run 1 (wf_e43f474d-ad0) · raw worker output, verbatim -->

# Custody debt lifecycle (snapshot `47c3317eb`)

## 1. Recording

### Store and physical file
- **Directory.** The store lives at `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`).
- **One file per originator cwd.** Each cwd gets one append-only file, `$CUSTODY_DIR/<key>.jsonl`. `open` appends to it (`bin/cc-custody:177-179`) and the scoped readers resolve it the same way (`bin/cc-custody:133-134`).
- **How the key is derived.** The key comes from `_fired_cwd_key` (`hooks/lib/origin-identity.sh:68-77`):
  - It resolves the directory with `cd "$d" && pwd -P` (`:74`).
  - It takes the first 32 hex characters of the SHA-256 of that physical path (`:76`).
  - It returns nothing if the directory does not resolve (`:73-75`). In that case `open` dies with "cwd does not resolve" (`bin/cc-custody:177`), and a `--cwd`-scoped read finds no file (`bin/cc-custody:133`).
  - Consequence: once a cwd is deleted, its rows are invisible to every `--cwd` consumer. Only store-wide readers can still see them.
- **Append-only.** Every write is `>>` (`bin/cc-custody:179,199,227`).

### Row fields
`_row` (`bin/cc-custody:93-104`) always writes `ts`, `kind` and `cwd`. It writes `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why` and `provenance` only when they are non-empty (`:97-103`).
- `ts` is UTC with one-second resolution. It can be empty, because of `|| true` (`:85`).
- `open` passes an empty `why` and a real `provenance` (`:179`).
- `return` and `abandon` pass no provenance. They copy `cwd`, `targetPane`, `marker` and `slug` from the matched open row (`:223-227`, bulk `:195-199`).

### How the open set is computed
`_OPEN_JQ` (`bin/cc-custody:108-112`) derives it at read time:
- **Join key.** The key is `"m:"+marker` when a marker is present. When the marker is missing or empty, it falls back to `"s:"+slug+"|"+targetPane` (`:110`).
- **Which row wins.** Rows are grouped by key and sorted by `ts`, and the **last** row wins. Only `kind=="open"` survives (`:111`).
  - Ties inside one second are left to jq's sort order. I did not verify from this repo that jq's sort is stable.
  - An empty `ts` sorts first, so an empty-ts `return` would lose to its own `open`.
- **Age fields.** Age is added after the fold (`:118-122`). `stale` means `ageHours >= TTL`, with a default TTL of 24 (`:66-67`). A `ts` that will not parse counts as not stale (`:119-121`).
- **Scope.** With `--cwd` the read covers one file. Without it, it covers every `*.jsonl` (`:130-139`), concatenated before the fold (`:240,260,263`).
- **Header claim that does not hold.** The header says "a crashed writer can never corrupt an existing verdict" (`:19-20`). A torn line would not rewrite any verdict, but `[ inputs ]` aborts on the first unparseable line (by reading the code; I did not run it), and each reader then fails differently:
  - `list` becomes `'[]'`, which reads as zero open (`:240`).
  - `count` dies with "store unreadable" (`:263`).
  - `return`/`abandon` matches nothing and still exits 0 (`:216-217,232`).

### When a fire opens a row (`scripts/handoff-fire.sh`)
The exact condition is `[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody` (`:13219`).
- **Back-channel.** `NB_ARMED_TARGET=$BACK_SID` and `NB_SLUG=basename(prompt minus extension)` are set only inside `if [ -n "$NOTIFY_BACK" ]`, where the trailer is actually appended (`:10720-10728`). A headless fire with no pane blanks `NOTIFY_BACK` (`:10713-10717`), so it opens no row.
- **Engagement verification.** The consequence function runs only under `if [ "$ENGAGE_VERIFY" = 1 ]` (`:13245`). `ENGAGE_VERIFY` starts at 0 (`:509`). The comment says it is 0 only for `--recycle` or a dry run (`:13212-13214`); I did not check the assignment. `FIRE_MARKER` is minted only when `ENGAGE_VERIFY=1` (`:10781-10786`).
- **Which directory the row is keyed on.** It is `--cwd "$PWD"` (`:13220`): the **firing** cwd, not the peer's worktree (`:13199`). A grep for lines beginning with `cd ` in the file found none.
- **Row contents.** `--target $SPAWNED_PANE --marker $FIRE_MARKER --slug $NB_SLUG --notify-back $NB_ARMED_TARGET --originator-pane $FIRING_SID --provenance proven|unproven-rc<N>` (`:13196-13197,13220-13223`).
- **Misleading message.** `_hf_custody` swallows every failure (`:4156`). Even so, on a non-zero rc it prints "custody debt OPENED anyway" without checking (`:13227`), so that message can report a row that was never written.

### What each engagement outcome does
`verify_engagement` returns 0, 1, 2, 4 or 5 (`:3416`); 3 is deliberately unused (`:3406-3409`). The table is `engage_rc_consequence` (`:3547-3597`):

| rc | Meaning | Custody row | /goal arm | Call site |
|---|---|---|---|---|
| 0 | engaged | open (`:3550`) | arm (`:3550`) | `:13273` |
| 1 | never ingested | **open** (`:3574`) | **not armed** (`:3580`) | `:13365` |
| 2 | pane parked | no (`:3583`) | no (`:3583`) | `:13289` |
| 4 | wedged on a startup dialog | open (`:3589`) | arm (`:3589`) | `:13301` |
| 5 | cannot tell | open (`:3592`) | arm (`:3592`) | `:13323` |
| anything else | undocumented code | open, with a stderr warning (`:3593-3596`) | arm | — |

The goal arm does **not** follow the same rule. It differs at rc 1, and it does not require `NB_ARMED_TARGET` (`:13232-13236`).

**Stale citation.** `:3520` says custody sits at `:10715` and the goal at `:10723`. Those lines are now notify-back setup. The actual arms are at `:13219` and `:13232`.

### Every producer that opens rows
1. **`scripts/handoff-fire.sh:13220`**, described above.
2. **`bin/cc-offload:747-750`** opens `--cwd "$PWD" --target "cloud:$sid" --marker "$sid" --slug "cloud-$sid"`, plus notify-back and originator pane (from `CC_PANE_ID`, then `ITERM_SESSION_ID`, `:745`). It is gated only on the binary being found (`:732`), not on a notify-back.
3. **`bin/cc-dispatch:903-906`** covers the legacy leg: no notify-back and no originator pane.
4. **`bin/cc-dispatch:931-933`** runs after `cc-cloud declare --custody "$sid"` (`:922-926`). Its notify-back comes from the desk role file (`:921`).
5. **Manual CLI:** `cc-custody open` (`bin/cc-custody:175-181`).

The deathwatch header says cloud fires run with cwd `/` (`scripts/custody-deathwatch.sh:12-14`). The self-close repair at `handoff-fire.sh:8390-8396` writes a fired-peer **stamp**, not a custody row.

## 2. Discharging
`_hf_custody` is called only at `handoff-fire.sh:8707` and `:13220`. The only files that call the verbs are the ones listed below.

1. **handoff-fire self-close** (`handoff-fire.sh:8657,8707`)
   - **Verb and key:** `return` on the marker read from the peer's own stamp, `$FIRED_DIR/$SC_SID.json`.
   - **Scope:** store-wide, since `_hf_custody` passes no `--cwd` (`:4147-4157`).
   - **Why only the marker:** the marker is the only token on the stamp. The stamp writer takes it from `FIRE_MARKER` (`:4535`).
   - **Conditions:** the stamp exists with a marker, and every earlier gate passed, including the terminal ledger refusal, which exits 8 *before* the discharge (`:8676-8702`).
   - **Limit for rc 1/4/5 rows:** at fire time the stamp is written only on rc 0 and only if `WANT_SELF_RETIRE=1` (`:13268-13270`). Rows opened on rc 1, 4 or 5 can reach this path only through the absent-stamp repair (`:8390-8396`).
   - **Dry-run defect (by reading):** `SC_DRY` is checked only at `:8709`, after the `return` at `:8707` (its only references are `:7967`, `:7985`, `:8709`). So `self-close --dry-run` appears to append a real discharge.
   - **Header claims that do not hold:** `bin/cc-custody:22-23` and `scripts/custody-deathwatch.sh:28-29` say the return comes "from sc_announce_before_retire". That function is called separately at `:8652-8653`. The citation to `bin/cc-custody:212-227` at `:8705` does hold.
2. **mailbox-drain** (`hooks/mailbox-drain.sh:558-587`)
   - **Verb and key:** `return <slug>`, scoped with `--cwd` to the payload's `.cwd`, falling back to `$PWD` (`:566-567`).
   - **Why only the slug:** it is the only field echoed to the peer in `HANDOFF-PING <slug>:`. A store-wide slug discharge could drop another cwd's row (`:543-547`, `bin/cc-custody:26-32`).
   - **Conditions:** `CC_DRAIN_CUSTODY_RETURN≠0`, the body contains `HANDOFF-PING`, and the binary is found (`:558-563`). Slugs must match the regex, are deduplicated, and are capped at 8 (`:583-585`).
   - **Which row a slug hits:** the matcher accepts `.marker==$t or .slug==$t` and takes `first` in key-sorted order (`bin/cc-custody:216`). Two open rows with the same slug in one cwd lose one row per ping, and marker order decides which one, not which peer pinged.
   - **Stale citation:** `:545` points at `(:7087)` for the basename; the real line is `handoff-fire.sh:10721`.
3. **cloud-return, verified land** (`scripts/cloud-return.sh:977-983`)
   - `return "$custody"`, keyed on the marker from the declaration (the `sid`), store-wide.
   - Only when `landed_ok -eq 0`; otherwise the row is left open (`:982`).
4. **cloud-return, item already done** (`scripts/cloud-return.sh:533-537`)
   - `abandon`, same key, store-wide, when `item_is_done`.
5. **cloud-retire-terminal** (`scripts/cloud-retire-terminal.sh:200-209`, called at `:294`)
   - `return` on verdict `landed`, otherwise `abandon --why`. Keyed on the marker, store-wide.
   - Only after a successful `cc-cloud retire`, and not in dry-run (`:285-289`).
6. **Manual CLI:** `cc-custody return|abandon <marker-or-slug> [--cwd]` (`bin/cc-custody:182-234`). It is store-wide unless `--cwd` is given. If nothing matches it prints to stderr and exits 0 (`:230-232`).
7. **Bulk stale abandon:** `abandon --stale --why` (`bin/cc-custody:186-209`). It discharges only stale rows (`:194`), requires `--why` (`:187`), and is scoped only if `--cwd` is passed (`:206`). **No code invokes it** (repo grep: no hits).

**Nothing expires or deletes rows automatically.** The header rules out a TTL (`bin/cc-custody:45-49`), the usage text says "nothing ever expires" (`:271`), every write is `>>`, and a grep for `rm`/`-delete` on the custody directory returned nothing.

**The deathwatch/reaper discharges nothing.**
- Its header says so: "NEVER discharges a debt" (`scripts/custody-deathwatch.sh:44,66,73`).
- Its only `cc-custody` call is `list --open --json` (`:282`).
- Its only outputs are a `cc-notify` message (`:353`), a `cc-backlog needs` row (`:388-390`), and its own ledger (`:238`).

## 3. Consuming

1. **The close-ledger rung** (`scripts/wrap-ledger.sh`, `count_open_custody` at `:1047-1085`)
   - **Lines that read the count:**
     - `j="$(_bounded … "$bin" list --open --cwd "$PWD" --json …)"` (`:1063`)
     - fallback: `n="$(_bounded … "$bin" count --open --cwd "$PWD" …)"` (`:1081`)
   - **Whose pane counts as "yours":** the pane is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the last `:` stripped (`:1061`).
   - **Attribution** (`:1064-1070`):
     - A row is **known** if `originatorPane` or `notifyBack` is non-empty.
     - A row is **mine** if `originatorPane==pane`, `notifyBack==pane`, or `notifyBack` ends with `"-"+pane`.
     - `CUSTODY_MINE` = known and mine. `CUSTODY_UNK` = not known.
     - `CUSTODY_OPEN` = MINE + UNK (`:1076`). Rows that are known but belong to another pane are dropped entirely.
   - **Other sources:** no pane, no jq, or empty JSON falls back to `SRC=cwd` with UNK=n (`:1084`). Otherwise `SRC=error` or `SRC=none`, and the count is 0.
   - **Stale citation:** `:1058` cites `hooks/session-continue.sh:302`, which is an `echo "ARMED…"` line. The real capture is at `:420,425`.
   - **Where in the ladder the count is taken:** only in the ✅-eligible `else` (`:1997`), after ⛔ (`:1970-1976`), dirty tree (`:1977`), DoD remainder (`:1979`) and 📦 unlanded (`:1981-1987`).
   - **What that implies:**
     - On those earlier-decided turns, `CUSTODY_OPEN` stays 0 with `SRC=skip` (`:1047`). The `--full` view prints "not counted (a worse rung governs)" (`:2328`).
     - When counted and above 0, custody gives 🔧 and outranks no-trunk, 🚀 and 👤 (`:1998-2010`).
     - It is emitted as `CUSTODY_OPEN/SRC/MINE/UNK` (`:2202-2208`).
2. **Busy arms.** wrap-ledger passes `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"` (`scripts/wrap-ledger.sh:2143`). `hooks/lib/session-busy.sh:302` then adds a `custody` arm.
3. **Done-claim gate** (`hooks/completion-assert.sh:718-719`)
   - Reads `CUSTODY="$(lfield CUSTODY_OPEN)"` from the ledger's `--machine` output (`:296-300,302`). Above 0 it sets `contra=1` and a fact about unreturned sessions.
   - It inherits the rung's skip, so it can only fire on turns that are ✅-eligible on the git facts.
4. **Stop/wake floor** (`hooks/session-continue.sh`, `wake_floor` at `:603`)
   - Reads the store itself, with the same attribution jq, through `list --open --cwd "$cwd" --json`, falling back to `count` (`:737-773`). It is independent of the rung ladder.
   - `cwd` comes from the payload, else `$PWD` (`:310`). The raw pane is `_opane` (`:420,425`).
   - Gate: `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`). When it fires, it blocks the stop with a "yours" or "cannot say whose" message (`:878-887`).
5. **Operator readout** (`hooks/operator-readout.sh`)
   - `custody="$(lf CUSTODY_OPEN)"` (`:915`), read inside the 🔧 rendering from `wrap-ledger --machine` (`:822-829`).
   - Adds "N dispatched session(s) NOT returned" (`:929`), and `→ cc-custody list --open --cwd .` when no teammates are resident (`:939-940`).
6. **`/wrap --full` "Dispatched:" row** (`scripts/wrap-ledger.sh:2313-2330`).
7. **custody-deathwatch.** Reads store-wide `OPEN_JSON="$("$CUSTODY_BIN" list --open --json …)"` (`scripts/custody-deathwatch.sh:282`) and only notifies or files a backlog row. It runs from `scripts/autonomy-sweep.sh:1894-1923`.

The consumers list in the cc-custody header (`bin/cc-custody:33-35`) omits the deathwatch and session-busy. The producers line (`:22-24`) omits cc-offload and cc-dispatch.