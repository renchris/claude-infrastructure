# Custody debt lifecycle at sha 47c3317eb

Two ways of reading a line number appear below. Numbers I read directly are cited plainly. Where a comment's cited line does not hold, I say so in the last section.

## 1. Recording

### Where the store lives and what one file is
- The store is `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`). It is append-only jsonl with one file per originator cwd, `<cwd-key>.jsonl` (`bin/cc-custody:12-13`, `:179`).
- The key comes from `_fired_cwd_key` (`hooks/lib/origin-identity.sh:68-77`). It runs `cd "$d" && pwd -P` to resolve symlinks, so `/tmp` and `/private/tmp` give one key. It then takes the first 32 hex characters of the sha256 of that resolved path.
- `_files_for` rebuilds the same path for a `--cwd` read (`bin/cc-custody:130-134`). With no cwd it globs every `*.jsonl` (`:136`).

### Row fields
- `_row` (`bin/cc-custody:93-104`) always writes `ts`, `kind` (open, return or abandon) and `cwd`.
- It adds `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why` and `provenance` only when non-empty.
- `open` passes `why` as `""` (`:179`), so open rows never carry `why`.
- `provenance` is open-only (`:16-17`, `:159-161`). Its values are `proven` or `unproven-rc<N>`.
- `return` and `abandon` rows copy `cwd`, `targetPane`, `marker` and `slug` from the matched open row. They take `originatorPane` from `--originator-pane` and `why` from `--why`. They never carry `notifyBack` or `provenance` (`:223-227`).

### How the open set is computed (`_OPEN_JQ`, `bin/cc-custody:108-112`)
- **Join key:** `m:<marker>` when `.marker` is non-empty. Otherwise `s:<slug>|<targetPane>`.
- **Marker missing:** the row falls back to the slug + targetPane key. If those are also empty the key is `"s:|"`.
- **Which row wins:** rows are grouped by key and sorted by `.ts`, and the last one is kept. Only rows with `kind == "open"` survive.
- **Ties:** `ts` has one-second resolution (`:85`). jq's `sort_by` is stable, so on equal timestamps the later line in the stream should win. This is my inference; I did not test it.
- **Age:** `ageHours` and `stale` (age >= `CC_CUSTODY_TTL_HOURS`, default 24) are added afterwards (`:118-122`, `:66`). An unparseable `ts` gives `ageHours` null and `stale` false.
- **Bare `count --open`:** it skips the age step, so stale rows still count (`:256-263`).

### The precise condition that opens a row
`scripts/handoff-fire.sh:13219`:
```
[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody
```
- `NB_ARMED_TARGET` is set only where the back-channel trailer is actually appended (`:10726-10728`). The fire is then `_hf_custody open` (`:13220-13223`).
- The old `WANT_SELF_RETIRE` restriction was lifted (`:13200-13209`).
- Fires with `ENGAGE_VERIFY=0` (recycle or dry run) never reach this code, by design (`:13211-13217`, `:13235`).

### Which directory the row is keyed on
- It is keyed on `--cwd "$PWD"` (`:13220`), which is the firing session's cwd.
- The header comment says so directly: "keyed on the FIRING cwd, not the target worktree" (`:13196`).
- `--target` is the spawned pane (`:13220`).

### Engagement outcomes for custody (`engage_rc_consequence`, `scripts/handoff-fire.sh:3547-3597`)

| rc | Meaning | Opens custody? | Opens goal? | Line |
|---|---|---|---|---|
| 0 | Engaged | yes | yes | `:3550` |
| 1 | Never ingested | **yes** (provenance `unproven-rc1`) | **no** | `:3574`, `:3580` |
| 2 | Pane parked on a shell | no | no | `:3583` |
| 4 | Wedged on a modal | yes | yes | `:3589` |
| 5 | Cannot tell | yes | yes | `:3592` |
| other | Undocumented | yes, fails open, with a warning | not stated at `:3594-3595` | `:3593-3595` |

- **Provenance:** any non-zero rc records `unproven-rc$rc` (`:13191-13192`, `:13218`). A non-zero rc also prints a stderr notice that the debt was opened anyway (`:13227`).
- **Custody and /goal differ.** The same table governs both, but rc 1 splits them: rc 1 opens custody and does not arm the goal. That is because a goal pasted before the brief was ingested would be a wrong first instruction (`:3575-3580`). The goal arm is `engage_rc_consequence "$rc" goal` (`:13232`).

### Every producer that opens rows
1. **`scripts/handoff-fire.sh:13220`**, the local fire. It runs through the `_hf_custody` wrapper (`:4147-4158`), which is best-effort and swallows errors.
2. **`bin/cc-offload:747`** (cloud `up`). It passes `--marker "$sid"`, `--slug "cloud-$sid"`, and the notify-back and originator-pane when known (`:747-749`). It notes on failure (`:750`).
3. **`bin/cc-dispatch:931`**, the declared cloud leg. It uses `--target cloud:$sid --marker $sid --slug cloud-$sid`, with `--notify-back` when known, and no originator pane.
4. **`bin/cc-dispatch:903-904`**, the legacy CLI adoption leg. It is the same shape but without `--notify-back`.

The header names only handoff-fire (`bin/cc-custody:22`). The cc-offload and cc-dispatch openers are not named there.

## 2. Discharging

The verbs are `return` and `abandon`, both routed through `bin/cc-custody:182-234`.

**How a discharge matches.**
- The token matches either `.marker` or `.slug` (`:216`).
- It searches only open rows, in `_files_for "$CWD"`. That means one file if `--cwd` is given, otherwise every file (`:214-221`).
- With no match it prints "nothing discharged" to stderr and exits 0 (`:229-233`).
- Matching only open rows makes a repeat discharge a no-op.

**Every discharge site:**
1. **Self-close, `scripts/handoff-fire.sh:8707`.**
   - It runs `return "$_sc_cmk" --why "$SC_LEDGER_STAMP"`.
   - The key is the MARKER, read from the fired-peer stamp (`:8657`).
   - It is store-wide, with no `--cwd`.
   - The condition is that the marker is non-empty.
   - The marker is the only key it holds. The header says self-close holds the marker, which is globally unique, so it can run from any cwd (`bin/cc-custody:25-28`).
2. **Ping receipt, `hooks/mailbox-drain.sh:565-580`.**
   - It runs `return "$_slug" --cwd "$_cust_cwd"`.
   - The key is the SLUG. That is the only custody field the peer is told to echo, in `HANDOFF-PING <slug>:` (`:534-536`, `handoff-fire.sh:13209`).
   - It is scoped to the hook payload's cwd, falling back to `$PWD` (`:563-566`).
   - The scope is deliberate because slugs can collide across originators (`:541-546`).
   - Conditions:
     - `CC_DRAIN_CUSTODY_RETURN != 0`.
     - The body contains `HANDOFF-PING`.
     - The slug matches the regex at `:585-587`.
     - At most 8 slugs are processed.
3. **`scripts/cloud-return.sh:977-979`.**
   - It runs `return "$custody"` by marker.
   - The condition is that the marker is non-empty and the land is verified (`landed_ok -eq 0`). Otherwise it leaves the row open (`:977-984`).
4. **`scripts/cloud-return.sh:536-537`.**
   - It runs `abandon "$custody" --why "cloud session superseded — item $item already done"`.
   - The condition is `item_is_done` (`:533`).
5. **`scripts/cloud-retire-terminal.sh:204-207` (`settle_custody`).**
   - The verdict `landed` runs `return "$marker"`. Any other verdict runs `abandon "$marker" --why …`.
   - The condition is that the declaration has a marker.
   - Both are keyed by marker and store-wide.
6. **Bulk, `abandon --stale --why` (`bin/cc-custody:186-210`).**
   - It has no token and requires `--why`.
   - For each file in scope it appends an `abandon` row for every open row whose `stale` is true.
   - It is store-wide unless `--cwd` is given.
   - It prints the count of rows discharged.
7. **Manual `return` and `abandon <token>`.** These are the human or agent verbs the messages point at (`hooks/completion-assert.sh:719`, `scripts/wrap-ledger.sh:2009`).

**Automatic expiry or deletion: none.**
- The header says "Nothing here deletes, nothing here rewrites" (`bin/cc-custody:47-49`, `:271`).
- I found no other writer in the paths I read. `scripts/growth-coverage.conf:211` says an open debt must never be reaped.

**Does the deathwatch discharge anything? No.**
- `scripts/custody-deathwatch.sh:44` says "It NEVER discharges a debt". `:66` and `:73` repeat it.
- The only custody call is `list --open --json`, store-wide (`:282`).
- Its `cc-custody return` and `abandon` strings appear only inside notification text (`:353`, `:388`).

## 3. Consuming

### Close-ledger rung (`scripts/wrap-ledger.sh`)
- `count_open_custody` (`:1048-1085`) runs `list --open --cwd "$PWD" --json` and splits the rows into mine and unknown.
  - The count is taken at `:1998`, in `count_open_custody` followed by `if [ "$CUSTODY_OPEN" -gt 0 ]`, inside the ✅-eligible `else` branch.
  - This comes after ⛔ (`:1965-1968`), dirty (`:1969-1970`), DoD remainder (`:1971-1972`) and unlanded 📦 (`:1973-1975`) have already decided the rung.
  - So on those turns custody is never counted. It reports `CUSTODY_SRC=skip` (`:1047`, `:1990-1996`).
  - When it is counted and non-zero, it outranks every remaining arm, including no-trunk, and sets the rung to 🔧 (`:1999-2010`).
- The attribution logic, in `jq` (`:1069-1075`):
  - `known` means the row has `originatorPane` or `notifyBack`.
  - `mine` means one of:
    - `originatorPane == pane`.
    - `notifyBack == pane`.
    - `notifyBack` ends with `"-" + pane`.
  - `CUSTODY_MINE` counts rows that are known and mine. `CUSTODY_UNK` counts rows that are not known.
  - Rows that are known but not mine are counted in neither field, and so are dropped.
  - `CUSTODY_OPEN` is the sum of `MINE` and `UNK`, and `CUSTODY_SRC` is `pane` (`:1076`).
- The pane is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the last `:` stripped (`:1064-1065`).
- With no pane id or no jq, it falls back to `count --open --cwd "$PWD"`. All rows are then `UNK`, and `CUSTODY_SRC=cwd` (`:1080-1084`).
- Errors give 0 and `CUSTODY_SRC=error` (`:1081-1083`).
- The count is emitted as `CUSTODY_OPEN`, `CUSTODY_SRC`, `CUSTODY_MINE` and `CUSTODY_UNK` (`:2202-2207`).
- If `SRC=pane` and `MINE` is 0, the wording hedges: the store "cannot say whose" (`:2006-2007`). Otherwise it uses the ordinary wording (`:2008-2010`).
- The operator-facing display strings are at `:2317-2326`.
- The count is also passed to the busy probe: `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"` (`:2143`).

### Done-claim gate (`hooks/completion-assert.sh:718-719`)
- The count line is `CUSTODY="$(lfield CUSTODY_OPEN)"`, a non-numeric value becoming 0.
- It reads the ledger output and never re-derives the count (`:715-717`).
- If `CUSTODY -gt 0` it sets `contra=1` and adds a fact. That fact says an armed `cc-await-ping` is a valid state but "done" is not.
- Because the ledger skips the count on the earlier rungs, the gate sees custody only on ✅-eligible turns.

### Stop/wake floor (`hooks/session-continue.sh`)
- It uses the same attribution jq (`:757-763`), fed by `list --open --cwd "$cwd" --json`.
  - The pane is `_opane`, set at `:425`.
  - The fallback is `count --open --cwd "$cwd"` (`:770-772`).
  - Both give `cust = cust_mine + cust_unk`.
- The line that reads the count is `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`).
  - It re-fires the floor on any idle where custody is open, not only the first idle.
- The message has two spellings: "YOU fired" when `cust_mine` is above 0, otherwise a hedged "cannot say whose" (`:876-883`).

### Operator readout (`hooks/operator-readout.sh:915`)
- The count line is `custody="$(lf CUSTODY_OPEN)"`.
- It appends `N dispatched session(s) NOT returned` to the 🔧 state (`:930`), and the hint `→ cc-custody list --open --cwd .` (`:940`).
- The comment says custody does not change the fire predicate (`:910-914`).

### Other consumers
- **Busy probe** (`hooks/lib/session-busy.sh:302`): `case "${CC_BUSY_CUSTODY_OPEN:-0}" … arms="$arms custody"`.
- **Deathwatch** (`scripts/custody-deathwatch.sh:282`): `list --open --json`, store-wide. It notifies and never discharges.
- **`commands/are-we-done.md:22-23`**: `cc-custody list --open --fresh` and `count --open --stale`. These are readouts only.
- **Discharge lookups**: the internal open-set match in `return` and `abandon` (`bin/cc-custody:216`).

## Citations that do not hold at this sha

| Where it is cited | What it says | What I found |
|---|---|---|
| `hooks/mailbox-drain.sh:522-528` | `handoff-fire.sh:8936` defers a restriction to the ping-receipt discharger | Line 8936 is `RCY_TRANSPLANT_CAUSE=…`, unrelated |
| `hooks/mailbox-drain.sh` | `:7100` is the `HANDOFF-PING <slug>` recipe | Line 7100 is a recycle comment. The recipe is at `handoff-fire.sh:197` |
| `hooks/mailbox-drain.sh` | `:7087` is `basename` of the prompt file | Line 7087 is an unrelated dialog-case comment. `basename` is at `handoff-fire.sh:10720-10721` |
| `hooks/mailbox-drain.sh:522` | `bin/cc-custody`'s header names this hook as a `return` producer | It does, at `bin/cc-custody:23-24`. That part holds |
| `scripts/wrap-ledger.sh:1062` | the pane key is the same expression `session-continue.sh:302` captures | `hooks/session-continue.sh:302` is `else echo "inactive"; fi`. The pane is `_opane`, set at `:425` |
| `scripts/wrap-ledger.sh:1016` | `bin/cc-custody:35-38` is POLARITY | POLARITY is at `:36-39`, so off by one. Line 35 is the tail of CONSUMERS |
| `hooks/session-continue.sh` | `_opane` is "captured at :197" | `:197` is a different comment. `_opane` is set at `:425` |
| `scripts/handoff-fire.sh:3558` | `fire_cleanup` "KEPT" text is at `:9064` | Line 9064 is an unrelated comment. The text is at `:10942` |
| `scripts/handoff-fire.sh:8705` | `bin/cc-custody:212-227` is the `--why` on `return` | Roughly holds. The `--why` handling is at `bin/cc-custody:211-228` |
| `scripts/cloud-retire-terminal.sh:180-181` | cc-custody "refuses a second discharge" | It does not refuse. It exits 0 with "nothing discharged" on stderr (`bin/cc-custody:229-233`). The effect is a no-op, so the row's first discharge stays final, which is the comment's point |
