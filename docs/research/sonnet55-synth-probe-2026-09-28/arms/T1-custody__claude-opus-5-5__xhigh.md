# Custody debt lifecycle at `47c3317eb`

## 1. Recording

### Where the store lives and what one file is
- **Directory:** `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`). The header describes the same path (`bin/cc-custody:12-13`).
- **One file = one originator cwd:** `<key>.jsonl` (`bin/cc-custody:134`, `:179`). The file is append-only. Every write uses `>>` (`bin/cc-custody:179`, `:199`, `:227`).
- **How the filename is derived:** the key comes from `_fired_cwd_key` in `hooks/lib/origin-identity.sh` (`bin/cc-custody:14`, `:76-83`).
  - It resolves the directory with `cd "$d" && pwd -P`. This collapses `/tmp` and `/private/tmp` and follows symlinks (`hooks/lib/origin-identity.sh:71-75`).
  - It then takes the first 32 hex characters of `shasum -a 256` of that physical path (`hooks/lib/origin-identity.sh:76`).
  - If the directory can't be entered, the key is empty. An `open` then dies with "cwd does not resolve" (`bin/cc-custody:177`). A read returns no files and counts `0` (`bin/cc-custody:133`, `:255`).
- **Reading:** a read with `--cwd` reads exactly that one file. A read without `--cwd` reads every `*.jsonl` in the store (`bin/cc-custody:130-139`).

### Row fields
`_row` always writes `ts`, `kind` and `cwd`. The other fields are written only when non-empty: `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` (`bin/cc-custody:93-104`).
- `ts` is UTC with one-second resolution (`bin/cc-custody:85`).
- `kind` is `open`, `return` or `abandon` (`bin/cc-custody:16`).
- `provenance` is set only on `open` rows (`bin/cc-custody:17`, `:87-92`). Discharge rows pass an empty notifyBack and no provenance (`bin/cc-custody:199`, `:227`).
- `open` requires `--cwd` and `--target` (`bin/cc-custody:176`), so every open row has a `targetPane`.

### How the open set is computed at read time (`_OPEN_JQ`, `bin/cc-custody:108-112`)
- **Join key:** `"m:"+marker` when `marker` is present and non-empty. Otherwise it falls back to `"s:"+slug+"|"+targetPane` (`bin/cc-custody:110`).
  - If `slug` is also missing, the key becomes `"s:|<targetPane>"`. Two marker-less, slug-less fires at the same pane then share one key.
- **Which row wins:** rows are grouped by key, each group is sorted by `ts`, and the last row wins. The key is open only if that winning row has `kind=="open"` (`bin/cc-custody:111`). So the latest verdict per key wins.
  - Because `ts` is per-second, two rows in the same second break the tie by stream order. That relies on jq's `sort_by` being stable, which the file doesn't state (my inference).
- **Keys stay consistent across verdicts.** A discharge row copies the matched open row's `cwd`, `targetPane`, `marker` and `slug` (`bin/cc-custody:223-227`; bulk: `:195-199`). The verdict therefore lands on the same key as the open row, in the same file (`>> "$matched_file"`, `:227`).
- **Merging across files:** `count` and `list` concatenate all selected files into one stream before running the jq program (`bin/cc-custody:240`, `:260`, `:263`). `return`/`abandon` compute the open set one file at a time (`bin/cc-custody:216-217`).
- **Age:** age is added afterwards. `ageHours` comes from `ts`, and `stale = ageHours >= TTL`, with a default TTL of 24 h (`bin/cc-custody:66-67`, `:118-122`). A `ts` that won't parse gives `ageHours: null` and `stale: false` (`bin/cc-custody:59-60`, `:121`).

### The condition that opens a row (local fire, `scripts/handoff-fire.sh`)
All five engagement verdicts go through one function, `engage_apply_consequences` (`scripts/handoff-fire.sh:13195`). It is called for rc 0, 2, 4, 5 and 1 at `:13273`, `:13289`, `:13301`, `:13323` and `:13365`. The guard is:

```
if [ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody; then
```
(`scripts/handoff-fire.sh:13219`)

- **`NB_ARMED_TARGET`** is set to `$BACK_SID` only inside `if [ -n "$NOTIFY_BACK" ]` (`scripts/handoff-fire.sh:10720`, `:10728`). That happens where the back-channel trailer is actually appended (`:10722-10727`). A headless fire with no pane blanks `NOTIFY_BACK` first (`:10716-10717`).
- **The self-retire requirement was removed** (`scripts/handoff-fire.sh:13203-13211`).
- **Recycle and dry-run fires never reach this code** (`ENGAGE_VERIFY=0`), according to the comment at `:13213-13218`.
- **Row contents:** `open --cwd "$PWD" --target "$SPAWNED_PANE" --marker "${FIRE_MARKER:-}" --slug "${NB_SLUG:-}" --notify-back "$NB_ARMED_TARGET" --originator-pane "${FIRING_SID:-}" --provenance "$prov"` (`scripts/handoff-fire.sh:13220-13223`).
  - `FIRE_MARKER` is `HANDOFF-ENGAGE-$$-<epoch>-<RANDOM>` (`:10785`).
  - `NB_SLUG` is the prompt file's basename without its extension (`:10721`).
  - `prov` is `proven` for rc 0 and `unproven-rc<N>` otherwise (`:13196-13197`).
- **The row is keyed on the firing session's `$PWD`, not the peer's worktree** (comment `:13198-13200`). The peer's `LAUNCH_DIR` goes only into the fired-peer stamp (`:13269`).
- **Failures never stop the fire.** `_hf_custody` discards output and errors, and is a no-op when the binary is missing (`scripts/handoff-fire.sh:4147-4156`).

### How each engagement outcome decides custody and the goal
`verify_engagement` returns 0, 1, 2, 4 or 5 (`scripts/handoff-fire.sh:3416`). The `engage_rc_consequence` table (`:3547-3597`) then decides both custody and the /goal arm (goal: `:13232-13233`):

| rc | meaning | custody | /goal | line |
|---|---|---|---|---|
| 0 | engaged | open (`proven`) | arm | `:3550` |
| 1 | never ingested | **open** (`unproven-rc1`) | **do not arm** | `:3574`, `:3580` |
| 2 | pane parked (launcher never ran) | no | no | `:3583` |
| 4 | wedged on a dialog, session alive | open | arm | `:3589` |
| 5 | cannot tell | open | arm | `:3592` |
| other | undocumented | open, with a stderr warning | arm | `:3593-3595` |

- When custody opens on a non-zero rc, the fire prints "custody debt OPENED anyway" (`:13227`).
- The same table governs /goal, but the two diverge at rc 1: custody opens (`:3574`) while the goal stays fail-closed (`:3575-3580`).
- On a non-zero rc the goal arm is tagged `engagement-<prov>` (`:13233`).

### Every producer that opens rows
| Producer | Line | cwd | target | marker / slug | notifyBack / originatorPane | Condition |
|---|---|---|---|---|---|---|
| `handoff-fire.sh` (local fire) | `:13220` | `$PWD` of the firer | spawned pane | `FIRE_MARKER` / `NB_SLUG` | both | guard at `:13219` above |
| `bin/cc-offload` (cloud fire) | `:747-749` | `$PWD` | `cloud:$sid` | `$sid` / `cloud-$sid` | `UP_NOTIFY_BACK` if set; `op_pane` from `CC_PANE_ID`/`ITERM_SESSION_ID` (`:746`) | only that a binary resolved (`:732`), after the declare succeeded (`:725-726`). **No notify-back requirement.** |
| `bin/cc-dispatch`, legacy CLI-leg adopt | `:903-905` | `$PWD` | `cloud:$sid` | `$sid` / `cloud-$sid` | none | the declared-session grep at `:896` |
| `bin/cc-dispatch`, declared path | `:931-933` | `$PWD` | `cloud:$sid` | `$sid` / `cloud-$sid` | notifyBack = contents of `~/.claude/cc-roles/desk` if present (`:922`); no originatorPane | after `cc-cloud declare … --custody "$sid"` succeeds (`:923-929`) |
| Manual `cc-custody open` | `bin/cc-custody:266` | any | any | any | any | — (the desk once "hand-opened 529's row", `scripts/handoff-fire.sh:3528`) |

The file header names only handoff-fire as a producer of `open` rows (`bin/cc-custody:22-24`). It omits cc-offload and cc-dispatch.

## 2. Discharging

A discharge always goes through the same `return`/`abandon` code path in `bin/cc-custody`:
- A leading flag is treated as a malformed call, not a token (`:146-149`). A token is required, and `abandon` requires `--why` (`:211-212`).
- The first open row where `.marker == $t or .slug == $t` is chosen, from the first file that has one (`:214-221`).
- A matching verdict row is appended (`:223-228`).
- If nothing matches, it prints "no OPEN row matches" to stderr and exits 0 (`:230-233`).

So a second discharge of an already-discharged token writes nothing. `scripts/cloud-retire-terminal.sh:180` calls this "refuses". In practice it is a silent rc-0 no-op.

Because `open` is keyed on the originator's cwd, a caller outside that cwd can only find the row by searching the whole store. That is safe only with the marker, which is unique per fire. The slug isn't safe store-wide because two originators can pick the same slug (`bin/cc-custody:25-32`).

| # | Site | Verb | Key | Scope | Condition before discharge |
|---|---|---|---|---|---|
| D1 | `scripts/handoff-fire.sh:8707` (peer `self-close`) | `return … --why "$SC_LEDGER_STAMP"` | **marker**, read from the peer's own stamp: `jq -r '.marker'` on `$FIRED_DIR/$SC_SID.json` (`:8657`) | **store-wide** (no `--cwd`) | the stamp has a marker (`:8656`, `:8707`), and the terminal ledger refusal did not fire. That refusal exits 8 *before* the discharge (`:8668-8672`, `:8676-8700`, "nothing was discharged" `:8688`). Runs after `sc_announce_before_retire` (`:8652`). |
| D2 | `hooks/mailbox-drain.sh:579` (ping receipt at the originator) | `return "$_slug" --cwd "$_cust_cwd"` | **slug**. It is the only custody field the ping carries; the marker is never sent (`:532-536`) | **cwd-scoped**: the hook payload's `.cwd`, else `$PWD` (`:567-568`) | kill switch `CC_DRAIN_CUSTODY_RETURN≠0` and the body contains `HANDOFF-PING` (`:558`). Slugs are parsed with `HANDOFF-PING <slug>:`, deduplicated, capped at 8 (`:584-586`). A discharge is counted only when stderr is empty (`:576-581`). |
| D3 | `scripts/cloud-return.sh:979` | `return "$custody"` | **marker**, from the declaration's `.custody` field (`:514`), which cc-dispatch sets to `$sid` (`bin/cc-dispatch:923`) | store-wide | `landed_ok -eq 0`, i.e. a verified land (`:978`). Otherwise it leaves the row open (`:981-982`). |
| D4 | `scripts/cloud-return.sh:537` | `abandon "$custody" --why "cloud session superseded — item $item already done"` | marker | store-wide | `item_is_done "$item"` (`:534`) |
| D5 | `scripts/cloud-retire-terminal.sh:206-207` (`settle_custody`) | `return` if the verdict is `landed`; otherwise `abandon --why "cloud declaration retired: <verdict> [detail]"` (`:202`) | marker, from the declaration's `custody` field (`:201`) | store-wide | the marker and binary exist (`:204`), not a dry run (`:286-289`), and `cc-cloud retire` succeeded (`:291-294`) |
| D6 | `bin/cc-custody:186-210` (bulk) | `abandon --stale --why …` with no token | copies each row's own key (`:195-199`) | cwd-scoped if `--cwd` is given, otherwise store-wide (`:206`) | `--why` is required (`:187`), and the row's `stale == true` (`:194`). Prints the number discharged (`:208`). |
| D7 | Manual `cc-custody return|abandon <token>` | either | marker or slug | store-wide, or `--cwd` | the remedy text the consumers print (`scripts/wrap-ledger.sh:2007`, `:2009`; `hooks/completion-assert.sh:719`; `scripts/handoff-fire.sh:13227`) |

**No code calls the bulk path.** None of the call sites I found invokes `abandon --stale`. The header says the choice is "a human/agent decision that age makes cheap — never an automatic one" (`bin/cc-custody:57-58`).

**Nothing expires or deletes a row automatically.**
- The header rejects a TTL: "Nothing here deletes, nothing here rewrites" (`bin/cc-custody:45-49`). The usage text ends with "nothing ever expires" (`:271`).
- `count --open` still counts stale rows (`:256-257`, `:263`).
- The growth config lists the store with "an OPEN debt must never be reaped, and discharged ones have no horizon either" (`scripts/growth-coverage.conf:211`).

**The deathwatch/reaper discharges nothing.**
- Its only call into the ledger is `list --open --json` (`scripts/custody-deathwatch.sh:282`). A grep for `CUSTODY_BIN"` finds only `:277` and `:282`.
- Its header says "It NEVER discharges a debt, never closes a row" (`:41`) and "uncertain about anything → NEVER discharge" (`:66`).
- It only *tells* the originator to run `return`/`abandon` (`:353`, `:388`).

**The ping drain can never discharge a cloud row (my inference).**
- Cloud pings read `HANDOFF-PING cloud/$id:` (`scripts/cloud-return.sh:844`, `:1001`), and the drain's slug pattern accepts `/` (`hooks/mailbox-drain.sh:585`).
- Cloud rows use the slug `cloud-$sid` and the marker `$sid` (`bin/cc-offload:747-748`; `bin/cc-dispatch:904-905`, `:932-933`).
- The token `cloud/<id>` matches neither under `.marker == $t or .slug == $t` (`bin/cc-custody:216`). The call is also scoped to the receiver's cwd, which isn't where these rows are stored.
- In practice this doesn't matter: D3 discharges by marker (`:979`) before the ping is sent (`:1001`).

## 3. Consuming

### C1. Close-ledger rung, `scripts/wrap-ledger.sh` `count_open_custody` (`:1048-1085`)

**Where in the ladder the count is taken.** The ladder runs:
1. Default ✅ (`:1962`)
2. ⛔ (`:1971-1978`)
3. Dirty 🔧 (`:1979-1980`)
4. DoD-remainder 🔧 (`:1981-1982`)
5. Unlanded 📦 (`:1983-1989`)
6. Only in the final `else` is `count_open_custody` called (`:1990-1997`).

On ⛔, dirty, remainder or 📦 turns, the count is never taken. `CUSTODY_OPEN` stays `0`, `CUSTODY_SRC` stays `skip`, and the split fields stay `0` (`:1047`). Those values are what gets emitted (`:2202-2208`).

What that means for turns whose rung is decided earlier:
- Every downstream consumer of the emitted field (C2, C4, C5) sees 0 open custody on those turns, even when rows are open.
- On the ✅-eligible path, a custody count above 0 outranks every remaining arm, including no-trunk (`:1998-2001`), and forces 🔧 (`:2007`, `:2009`).

**The line that reads the count:**
```
&& j="$(_bounded "${WRAP_CUSTODY_TIMEOUT_S:-5}" "$bin" list --open --cwd "$PWD" --json 2>/dev/null)" \
```
(`:1063`). The fallback is `n="$(… "$bin" count --open --cwd "$PWD" …)"` (`:1081`).

**How attribution splits the count** (`:1065-1076`):
- `known` = the row has a non-empty `originatorPane` or `notifyBack`.
- `mine` = `originatorPane == $p`, or `notifyBack == $p`, or `notifyBack` ends with `"-" + $p`.
- `CUSTODY_MINE` = known and mine. `CUSTODY_UNK` = not known.
- `CUSTODY_OPEN = MINE + UNK` with `SRC=pane`. Rows owned by another pane are dropped (`:1019`).
- The `"-"` anchor stops pane 15 from claiming the row of `wt-pool-2-415` (`:1036-1038`).
- `$p` is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the last `:` stripped (`:1061`).

**Fallbacks:**
- No pane, no jq, or empty JSON: raw `count` with `MINE=0`, `UNK=n`, `SRC=cwd` (`:1079-1084`).
- No binary: `SRC=none` (`:1057`).
- Non-numeric result or failure: `SRC=error`, count 0 (`:1082-1083`).

**Readouts:**
- `SRC=pane && MINE=0`: the hedged 🔧 message ("store cannot say whose", `:2006-2007`).
- Otherwise: 🔧 "have NOT returned" (`:2009`).
- The close display lists the pane, cwd and none cases (`:2313-2326`).

### C2. Done-claim gate, `hooks/completion-assert.sh`
```
CUSTODY="$(lfield CUSTODY_OPEN)"; case "$CUSTODY" in ''|*[!0-9]*) CUSTODY=0 ;; esac
```
(`:718`)

- `lfield` greps the wrap-ledger output (`:302`).
- A count above 0 sets `contra=1` and adds a "have NOT returned" fact (`:719`).
- It deliberately reuses the ledger's number rather than recomputing it (`:715-717`). That means it inherits C1's `skip`=0 on non-✅-eligible turns.

### C3. Stop/wake floor, `hooks/session-continue.sh`
The floor does its own attributed read, with the same jq as C1:
```
&& _cj="$("$_cb" list --open --cwd "$cwd" --json 2>/dev/null)" && [ -n "$_cj" ]; then
```
(`:744`). Attribution is at `:748-758`. The fallback is `cust_unk="$("$_cb" count --open --cwd "$cwd" …)"` (`:762`).

- An armed watcher turns the floor off: `if mailbox_wake_armed "$_ouid"; then rm -f "$sf"; return 0; fi` (`:614`).
- The floor fires when `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ]` (`:805`).
- The message has a "YOU fired" form and a hedged form (`:879-882`).
- It is independent of the rung ladder.

### C4. Operator readout, `hooks/operator-readout.sh`
```
custody="$(lf CUSTODY_OPEN)"; case "$custody" in ''|*[!0-9]*) custody=0 ;; esac
```
(`:915`)

- This read happens only inside the `"🔧")` arm (`:896`).
- It adds "N dispatched session(s) NOT returned" to the readout (`:929`) and points to `cc-custody list --open --cwd .` (`:939-940`).
- `lf` greps the ledger output (`:829`).

### C5. Idle-arm classifier, `hooks/lib/session-busy.sh`
```
case "${CC_BUSY_CUSTODY_OPEN:-0}" in ''|0|*[!0-9]*) : ;; *) arms="$arms custody" ;; esac
```
(`:302`)

The value is passed in by wrap-ledger, `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"` (`scripts/wrap-ledger.sh:2143`), after the ladder has run.

### C6. Deathwatch, `scripts/custody-deathwatch.sh`
```
OPEN_JSON="$("$CUSTODY_BIN" list --open --json 2>/dev/null)" || OPEN_JSON=""
```
(`:282`)

- It is store-wide on purpose, and it is the only consumer without cwd scoping (`:39-41`, `:280-281`).
- It reports a row when the pane oracle says GONE or the row is stale (`:59`), once per marker (`:67-68`).
- It notifies the originator's pane directly, or falls back to one aggregated backlog row (`:75-79`).

### C7. Operator CLI, `cc-custody list`
`list --open` renders age, STALE/fresh and provenance, with `prov?` when absent (`bin/cc-custody:240`, `:246-248`).

`hooks/lib/why-tier.sh:204-212` is help text only and reads nothing.

**A corrupt line reads as zero (my inference).** A single unparseable line in a store file makes the whole-stream `[ inputs ]` fail:
- `list` then prints `[]` (`bin/cc-custody:240`), so C1 and C3 report 0 with `SRC=pane` (`scripts/wrap-ledger.sh:1076`). C6 sees nothing.
- `count` instead exits 3 ("store unreadable", `bin/cc-custody:263`), and wrap-ledger records `SRC=error` (`scripts/wrap-ledger.sh:1082`).

## 4. Header comments and cited line numbers that don't match the code

**Line references that point at the wrong place:**
- `scripts/handoff-fire.sh:3558` cites `:9064` for "worktree … KEPT — the pane is live". Line 9064 is about worktree freshness (`:9058-9068`). The text is actually at `:10942`.
- `hooks/mailbox-drain.sh:523` cites `scripts/handoff-fire.sh:8936` as deferring a "custody v1.1" restriction. Line 8936 is `RCY_TRANSPLANT_CAUSE=…`, and the phrase no longer appears anywhere in `handoff-fire.sh`.
  - `hooks/mailbox-drain.sh:534` cites `:7100` for the ping recipe. Line 7100 is a recycle comment; the recipe is at `:197`.
  - `hooks/mailbox-drain.sh:545` cites `:7087` for the slug `basename`. Line 7087 is the dialog comment; the `basename` is at `:10721`.
- `scripts/wrap-ledger.sh:1016-1018` has three bad references:
  - `bin/cc-custody:35-38` for POLARITY: the block is actually `:36-39`.
  - `:44-46` for the "not expiry" rule: it is actually `:45-49`.
  - `hooks/session-continue.sh:608-612`: those lines are wake-floor setup. The quoted "counts … HEDGES" text is at `:729`.
- `scripts/wrap-ledger.sh:1058` cites `hooks/session-continue.sh:302` as the pane-key capture. Line 302 is `else echo "inactive"; fi`; the floor's pane variable is set at `:425`.

**Line reference that roughly holds:**
- `scripts/handoff-fire.sh:8705` cites `bin/cc-custody:212-227` for `--why` on `return`. The verdict row that writes `$WHY` spans `:223-228`.

**Header statements that are wrong or out of date:**
- `bin/cc-custody:23` and `scripts/custody-deathwatch.sh:29-30` say the local return happens *from* `sc_announce_before_retire`. That function (`scripts/handoff-fire.sh:4344`) makes no custody call. The only `_hf_custody` calls are at `:8707` and `:13220`, and the return is at `:8707`, after the announce at `:8652`.
- The header lists of producers and consumers are incomplete:
  - `bin/cc-custody:22-24` leaves out the opens in cc-offload and cc-dispatch, and the discharges in cloud-return and cloud-retire-terminal.
  - `bin/cc-custody:33-35` leaves out session-busy and the deathwatch.
  - `scripts/wrap-ledger.sh:1000-1001` and `scripts/handoff-fire.sh:4145-4146` still describe self-close as the only discharge.
