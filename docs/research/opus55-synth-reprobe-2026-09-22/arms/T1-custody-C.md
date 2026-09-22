<!-- arm C = claude-opus-5-5 @xhigh · brief T1-custody · raw worker output, verbatim -->

# Custody debt lifecycle (snapshot `47c3317eb`)

## Summary

- A debt is an append-only JSONL row. Each originator cwd has its own file, and the file name is a hash of the physically resolved cwd (`bin/cc-custody:12-13`, `:65`, `:130-134`; `hooks/lib/origin-identity.sh:68-77`).
- Rows are opened at fire time from `engage_apply_consequences` in `scripts/handoff-fire.sh:13219-13223`.
- Rows are discharged by three automated paths: self-close by marker (`scripts/handoff-fire.sh:8657`, `:8707`), the mailbox drain by slug (`hooks/mailbox-drain.sh:579`) and cloud-return by marker (`scripts/cloud-return.sh:979`). They can also be discharged by hand with the `return`/`abandon` verbs, including a bulk `abandon --stale` (`bin/cc-custody:182-234`).
- Consumers: the `wrap-ledger` rung, `completion-assert`, the `session-continue` wake floor, `operator-readout`, and the busy probe inside `wrap-ledger`.
- Five defects surfaced; they are listed in §4. Several comment and header line citations are stale; see §5.

---

## 1. Recording

### 1.1 Store and physical file
- **Store directory:** `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (`bin/cc-custody:65`; also stated in the header at `:12-13`).
- **One file per originator cwd:** `<cwd-key>.jsonl` (`bin/cc-custody:133-134`, `:177-179`).
- **How the key is made:** `_fired_cwd_key` resolves the directory with `cd "$d" && pwd -P`, SHA-256s the path string, and keeps the first 32 hex characters (`hooks/lib/origin-identity.sh:68-77`).
  - This is the same key the fired-peer by-cwd index uses (`hooks/lib/origin-identity.sh:79-85`; `bin/cc-custody:14-15`).
  - If the cwd does not resolve, the key is empty (`hooks/lib/origin-identity.sh:74-75`) and `open` dies with "cwd does not resolve" (`bin/cc-custody:177`).
  - The fire path cannot see that failure: `_hf_custody` swallows all output and the exit code (`scripts/handoff-fire.sh:4155`). It is also a silent no-op when the binary is missing (`:4152-4154`).

### 1.2 Row schema
`_row` always writes `ts`, `kind` and `cwd`. The other fields are written only when non-empty: `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` (`bin/cc-custody:93-104`).
- `kind` is `open`, `return` or `abandon` (`bin/cc-custody:16`).
- `ts` is ISO UTC with 1-second resolution (`bin/cc-custody:85`).
- `provenance` appears on open rows only (`bin/cc-custody:17`, `:87-92`, `:179`).
- Return and abandon rows copy `cwd`, `targetPane`, `marker` and `slug` from the matched open row. They take `originatorPane` from the caller's `--originator-pane` and set `why` from `--why` (`bin/cc-custody:223-227`).

### 1.3 How the open set is computed at read time (`_OPEN_JQ`, `bin/cc-custody:108-112`)
- **Join key:**
  - `"m:"+marker` when `marker` is non-empty.
  - Otherwise `"s:"+slug+"|"+targetPane`, with `//""` defaults (`bin/cc-custody:110`).
  - So a row without a marker falls back to slug plus target pane.
  - A row with neither marker nor slug keys as `s:|<pane>`. No `return`/`abandon <token>` can ever match it, because matching is `.marker == $t or .slug == $t` (`bin/cc-custody:216`). Only the bulk stale abandon can discharge it (`bin/cc-custody:183-210`).
- **Which row wins:** `group_by(.k) | map(sort_by(.ts) | last) | map(select(.kind == "open"))` (`bin/cc-custody:111`). The row with the latest `ts` decides, and only a row whose latest verdict is `open` survives.
  - With 1-second `ts`, ties are broken by jq's stable sort, so the later line in the concatenated input wins. Writes are always `>>` appends (`bin/cc-custody:179`, `:199`, `:227`). This tie-break is jq behaviour; the file does not state it.
- **Input:** `list` and `count` `cat` the selected files. With `--cwd` that is one file; without it, every `*.jsonl` in the store (`bin/cc-custody:130-137`, `:240`, `:260`, `:263`).
- **Age (display only):** `ageHours` comes from the row's own `ts`, and `stale` means age ≥ `CC_CUSTODY_TTL_HOURS` (default 24). An unparseable `ts` gives `null`, which is treated as not stale (`bin/cc-custody:66-67`, `:118-122`, `:59-60`). A bare `count --open` ignores age and counts stale rows (`bin/cc-custody:256-257`, `:263`).

### 1.4 The fire-time open (the only `open` call in `handoff-fire.sh` that I found)
- **Exact condition:**
  ```
  if [ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody; then
  ```
  (`scripts/handoff-fire.sh:13219`)
- **Arguments passed:**
  - `--cwd "$PWD"` — the handoff-fire process's cwd, which is the firing session's cwd, not the target worktree. The comment says so explicitly: "keyed on the FIRING cwd, not the target worktree" (`:13198-13200`).
  - `--target "$SPAWNED_PANE" --marker "${FIRE_MARKER:-}" --slug "${NB_SLUG:-}" --notify-back "$NB_ARMED_TARGET" --originator-pane "${FIRING_SID:-}" --provenance "$prov"` (`:13220-13223`).
  - `prov` is `proven` when rc = 0 and `unproven-rc<N>` otherwise (`:13196-13197`).
- **Earlier restriction removed:** a self-retire restriction used to apply and has been lifted (`:13203-13211`).
- **Only the cold-fire branch can reach this.** Dry runs go to `:12787`, `--recycle` goes to `recycle_fire` (`:12915-12964`), and the cold fire runs `spawn` and then the `ENGAGE_VERIFY` block (`:12965-13239`). This matches the comment's disproof that dry-run and recycle fires never open custody (`:13213-13218`).
- **Not verified:** where `NB_ARMED_TARGET` and `ENGAGE_VERIFY` are assigned. The comment says `NB_ARMED_TARGET` is non-empty exactly when the back-channel trailer was written (`:13207-13209`). `--notify-back` without a value becomes `__self__`, and `--no-notify-back` opts out (`:8948-8949`).

**`verify_engagement` outcomes and their consequences.** The codes are 0, 1, 2, 4 and 5 (`scripts/handoff-fire.sh:3380-3393`, `:3416`). The table that decides both consequences is `engage_rc_consequence` (`:3547-3597`), and the fire-side call sites are listed per row:

| rc | Meaning | Custody row opened? | `/goal` armed? | Call site; process exit |
|---|---|---|---|---|
| 0 | Engaged | Yes (`:3550`) | Yes (`:3550`) | `:13273`; continues to "→ fired" |
| 1 | Never engaged within the window | **Yes**, provenance `unproven-rc1` (`:3574`) | **No** (`:3580`) | `:13365`; `exit 1` |
| 2 | Pane parked; launcher never ran | No (`:3583`) | No (`:3583`) | `:13289`; `exit 1` |
| 4 | Wedged on a dialog | Yes (`:3589`) | Yes (`:3589`) | `:13301`; `exit 1` |
| 5 | Cannot tell (the one non-verdict) | Yes (`:3592`) | Yes (`:3592`) | `:13323`; `exit 6` |
| other | Undocumented code | Yes, with a warning (`:3593-3595`) | Yes, with a warning | — |

- The goal arm uses the same table, **but row 1 splits**: custody opens and the goal does not (`:3575-3580`). A refused goal goes to `goal_unreachable` (`:13232-13236`).
- On any non-zero rc the fire prints "custody debt OPENED anyway" to stderr (`:13227`). The row is written before the process exits (`:13289-13290`, `:13301-13302`, `:13323-13324`, `:13365-13366`).
- The fired-peer stamp that self-close later reads (`mark_fired_peer`) is written only on rc 0 and only when `WANT_SELF_RETIRE=1` (`:13268-13270`).

### 1.5 Every producer that opens rows
1. **`handoff-fire.sh` cold fire:** `engage_apply_consequences` (`scripts/handoff-fire.sh:13219-13223`), through `_hf_custody` (`:4147-4157`).
2. **Manual `cc-custody open`:** requires `--cwd` and `--target` (`bin/cc-custody:175-181`). It is used in practice: "The desk hand-opened 529's row" (`scripts/handoff-fire.sh:3527-3528`).
3. **Cloud-fire producer (code not read).**
   - `wrap-ledger` reports 117 rows with neither `originatorPane` nor `notifyBack`, all from "cc-offload cloud fires", with the producer cut over on 2026-08-25 (`scripts/wrap-ledger.sh:1021-1030`).
   - `cloud-return` treats a custody token as part of a cloud declaration (`scripts/cloud-return.sh:8-10`, `:45-46`, `:977-979`).
   - `bin/cc-custody`'s own PRODUCERS list (`:22-24`) does not mention an opener for cloud fires.

---

## 2. Discharging

| # | Site | Verb and key | Scope | Condition before it fires |
|---|---|---|---|---|
| D1 | `handoff-fire.sh self-close` | `_hf_custody return "$_sc_cmk" --why "$SC_LEDGER_STAMP"` (`scripts/handoff-fire.sh:8707`). The marker comes from the peer's own stamp: `jq -r '.marker // ""' "$FIRED_DIR/$SC_SID.json"` (`:8657`). | Store-wide: no `--cwd`, so every file is searched (`bin/cc-custody:130-137`, `:214-221`). | The stamp carries a marker, and every earlier gate passed: origin/stale/spent/absent (`:8306-8452`), live teammates (`:8472-8485`), subagents (`:8492`), successor (`:8498-8563`), dirty tree (`:8578-8597`), and the `--terminal` ledger refusal (`:8676-8702`). **It also fires on `--successor` closes.** |
| D2 | `mailbox-drain.sh` ping receipt | `"$_cust_bin" return "$_slug" --cwd "$_cust_cwd"` (`hooks/mailbox-drain.sh:579`). The slug is taken from `HANDOFF-PING <slug>:` (`:584-586`); up to 8 per drain, deduplicated. | Scoped to one cwd: the payload `.cwd`, or `$PWD` as fallback (`:567-568`). | `CC_DRAIN_CUSTODY_RETURN` is not 0, the body contains `HANDOFF-PING`, and the binary is found (`:558-569`). Success is judged by empty stderr (`:576-579`). |
| D3 | `cloud-return.sh` step 9 | `"$CUSTODY_BIN" return "$custody"` (`scripts/cloud-return.sh:979`) | Store-wide (no `--cwd`) | `custody` and the binary are present, and `landed_ok -eq 0`, i.e. the land was content-verified (`:977-978`). On a refused or unverified land the row stays OPEN (`:843`, `:982`). |
| D4 | Manual `return` / `abandon <token>` | Token matches `marker` **or** `slug`; the `first` open match is used, in the first file where one exists (`bin/cc-custody:214-221`). `abandon` requires `--why` (`:212`). | `--cwd` gives one file; without it, store-wide. | Nothing matching gives "no OPEN row matches" on stderr and rc 0 (`:229-233`). The operator-facing prompts suggest this verb without a `--cwd` (`scripts/wrap-ledger.sh:2009`; `hooks/completion-assert.sh:719`). |
| D5 | Bulk `abandon --stale --why` | One abandon row per open row with `stale == true` (`bin/cc-custody:183-210`) | `--cwd` or store-wide | `--why` is required (`:187`). Invoked only by hand; I found no caller in the code I read. |

**Why each path uses the key it does.**
- Self-close and cloud-return hold the globally unique marker, so they can safely run store-wide (`bin/cc-custody:26-27`).
- The drain only ever sees the slug, because the marker is never echoed to the peer. Two originators can share a slug, so the drain restricts itself to its own cwd (`bin/cc-custody:28-32`; `hooks/mailbox-drain.sh:532-550`).

**Does anything expire or delete rows automatically? No.**
- The header says "nothing ever expires" and rejects expiry as a design (`bin/cc-custody:271`, `:45-49`, `:57-58`).
- Every write is an append (`:179`, `:199`, `:227`).
- The limit: in the files I read, nothing deletes store files. I could not search the whole repo.

**Deathwatch / reaper: no evidence that it discharges anything. This is not confirmed from its own code.**
- The drain header says a peer "closed by the operator, by a reaper, or by a crash left its originator's row OPEN FOREVER" (`hooks/mailbox-drain.sh:524-529`).
- Self-close hands the killed-peer case to "L1 death-watch" and says nothing about custody there (`scripts/handoff-fire.sh:8645-8648`).
- `cc-reaper` reaps based on the fired-peer stamp (`:4104-4118`, `:4495-4499`), so a reaped peer never reaches the discharge at `:8707`.
- I did not read `bin/cc-reaper` or the death-watch scripts.

---

## 3. Consuming

**C1. `scripts/wrap-ledger.sh` rung computation (`count_open_custody`, `:1047-1085`)**
- **Reads:**
  - `:1063`: `&& j="$(_bounded "${WRAP_CUSTODY_TIMEOUT_S:-5}" "$bin" list --open --cwd "$PWD" --json 2>/dev/null)" \`
  - Fallback at `:1081`: `n="$(_bounded "${WRAP_CUSTODY_TIMEOUT_S:-5}" "$bin" count --open --cwd "$PWD" 2>/dev/null)" \`
- **Where in the ladder:** it is called **only** in the ✅-eligible `else` branch (`:1990-1997`). That branch is reached only after ⛔ (`:1971-1978`), a dirty tree (`:1979`), a DoD remainder (`:1981`) and unlanded commits (`:1983-1989`) have all been ruled out.
- **What that implies:** on any turn whose rung was already decided, the fields stay at their defaults, `CUSTODY_OPEN=0 CUSTODY_SRC="skip"` (`:1047`), and are emitted that way (`:2202-2208`).
- **When custody is open:** it decides 🔧 ahead of residents, filed rows, unconvicted rows, close floor, no-trunk, 🚀 and 👤 (`:1998-2011`, `:2118`). That makes `✅ SAFE TO CLOSE` unreachable over open custody.
- **Attribution:**
  - The reader's pane is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}`, cut after the last `:` (`:1061`).
  - A row is "mine" when `originatorPane == pane`, or `notifyBack == pane`, or `notifyBack` ends with `"-"+pane` (`:1066-1069`).
  - `CUSTODY_MINE` counts rows that are known and mine. `CUSTODY_UNK` counts rows with neither field. Known rows that are not mine ("theirs") are **dropped** (`:1070`, `:1019`).
  - `CUSTODY_OPEN = MINE + UNK`, with `SRC=pane` (`:1076`).
  - With no pane identity or no jq, the count falls back to a plain cwd count with `SRC=cwd` (`:1079-1084`). The other states are `none` (`:1057`) and `error` (`:1082-1083`).
- **Readout:** the "cannot say whose" message is used when `SRC=pane` and `MINE=0` (`:2006-2007`); otherwise the standard message (`:2009`).

**C2. `hooks/completion-assert.sh` done-claim gate**
- **Reads:** `:718`: `CUSTODY="$(lfield CUSTODY_OPEN)"; case "$CUSTODY" in ''|*[!0-9]*) CUSTODY=0 ;; esac`
- **Effect:** when positive, it sets `contra=1` with the collect/return/abandon remedy (`:719`).
- It consumes the ledger's value rather than computing its own (`:715-717`). It can therefore be muted by the double-block yield (`:849-870`).

**C3. `hooks/session-continue.sh` wake floor (its own attributed count; independent of the ledger)**
- **Reads:**
  - `:744`: `&& _cj="$("$_cb" list --open --cwd "$cwd" --json 2>/dev/null)" && [ -n "$_cj" ]; then`
  - It applies the same "mine" test as C1 to `$_opane` (`:748-758`).
  - Fallback at `:762`: `cust_unk="$("$_cb" count --open --cwd "$cwd" 2>/dev/null || echo 0)"`
- **Gate:** `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (`:805`).
- **Not rung-gated.** It still stands down in these cases: a watcher is already armed (`:614`), headless (`:656-664`), live goal plus pending mail (`:697-703`), teammate/teardown (`:776-798`). It is bounded to 2 attempts with a 600 s TTL (`:807-808`).

**C4. `hooks/operator-readout.sh` (operator-facing)**
- **Reads:** `:915`: `custody="$(lf CUSTODY_OPEN)"; case "$custody" in ''|*[!0-9]*) custody=0 ;; esac`
- **Only inside the 🔧 arm** (`:896`). It renders "N dispatched session(s) NOT returned" (`:929`) and the action `→ cc-custody list --open --cwd .`, unless residents take the action slot (`:937-940`).
- It ignores `CUSTODY_MINE`/`CUSTODY_UNK`.

**C5. `wrap-ledger` own renderers**
- The `/wrap --full` custody row uses `CUSTODY_MINE`/`CUSTODY_UNK` (`scripts/wrap-ledger.sh:2313-2319`).
- The machine fields are emitted at `:2202-2208`.

**C6. Busy probe (a consumer not in the `cc-custody` header)**
- **Reads:** `:2143`: `_wl_sbo="$(CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}" \`, which passes the count to `session_busy_live` after the ladder (`:2127-2128`). I did not read what the lib does with it.

**C7. Retirement ledger stamp**
- `hf_ledger_stamp` reads the ledger's `RUNG` (`scripts/handoff-fire.sh:4225-4252`). That rung can be 🔧 because of custody (`:4277-4278`), and the stamp text becomes D1's `--why` (`:8666`, `:8707`).
- The `--terminal` refusal looks only at UNLANDED and REMAINDER, never at custody (`:4294-4317`).

---

## 4. Defects found (from the code)

1. **Self-close discharges the debt even when no close happens.**
   - The `return` at `scripts/handoff-fire.sh:8707` runs before the `SC_DRY` exit (`:8709-8736`), so `self-close --dry-run` appends a real return row.
   - It also runs before the mail-disposition check (M3), which can abort the close with `exit 6` (`:8748-8755`).
   - This contradicts the block's own rule: "a close that does not happen must not discharge the originator's debt" (`:8668-8672`).
2. **The done-claim gate cannot see custody after an earlier rung decided.**
   - When the ledger's rung is 🔧-dirty, 🔧-remainder, 📦 or ⛔, custody is never counted (`scripts/wrap-ledger.sh:1979-1997`, `:1047`).
   - If `completion-assert` then clears that term as not this session's (`hooks/completion-assert.sh:646`, `:679-687`), its custody term reads 0 (`:718`). The done-claim passes over open custody.
   - For the same reason, `operator-readout` shows no custody on those rungs (`hooks/operator-readout.sh:896`, `:915`).
3. **The drain's slug match is loose.**
   - Any `HANDOFF-PING <slug>:` discharges the row, including progress or failure pings (`hooks/mailbox-drain.sh:558`, `:585`).
   - When several open rows in one cwd share a slug, `return` takes the `first` open row (`bin/cc-custody:216`). The open set is grouped by key, so "first" follows marker sort order (`:110-111`), not which peer actually pinged.
4. **Probably discharges cloud debt that cloud-return deliberately keeps open.**
   - Cloud-return's failure pings use the form `HANDOFF-PING cloud/$id: LAND REFUSED…` (`scripts/cloud-return.sh:844`) and `…LANDED-UNVERIFIED…` (`:1001`).
   - The drain's pattern accepts `/` in a slug (`hooks/mailbox-drain.sh:570-573`, `:585`).
   - If cloud rows carry `cloud/<id>` as their slug or marker, which `hooks/mailbox-drain.sh:533-535` implies (the cloud opener's code was not read), the drain discharges exactly the debt cloud-return leaves open (`scripts/cloud-return.sh:843`, `:982`).
5. **Attribution drops rows that are not "mine" instead of keeping them.**
   - Rows that are known but do not match the reader are excluded (`scripts/wrap-ledger.sh:1070`; `hooks/session-continue.sh:753`).
   - If the writer's `FIRING_SID` (`scripts/handoff-fire.sh:13222`) is spelled differently from the reader's pane key (`scripts/wrap-ledger.sh:1061`), a genuinely owned debt disappears from the count. The `notifyBack` checks are the only backstop.

---

## 5. Citation audit

| Claim | Cited location | Holds? |
|---|---|---|
| `bin/cc-custody:22-23`: handoff-fire "`return`s from sc_announce_before_retire" | — | **No.** The function body (`scripts/handoff-fire.sh:4344-4469`) makes no custody call. The return is at `:8707`, after the announce call at `:8652-8653`. |
| `scripts/handoff-fire.sh:12729`: "self-close twin (:4104)" | `:4104` | **No.** `:4104` is the header of the fired-peer marker block. |
| `scripts/handoff-fire.sh:4411`: call site's comment at ":5598-5610" | `:5598-5610` | **No.** Those lines are the tail of `hf_alarm` and the start of `check_goal_length`. The real call site is `:8625-8653`. |
| `scripts/handoff-fire.sh:3557-3558`: fire_cleanup "KEPT" at ":9064" | `:9064` | **No.** `:9064` is inside the fire-time freshness comment. |
| `scripts/handoff-fire.sh:3519-3521`: custody at ":10715", goal at ":10723" | — | **Historical.** The comment is past tense; the current sites are `:13219` and `:13232`. I did not read `:10715`. |
| `scripts/handoff-fire.sh:8705`: `--why` on return at `bin/cc-custody:212-227` | `bin/cc-custody:211-228` | **Yes**, approximately. `$WHY` is passed at `:223-227`. |
| `hooks/mailbox-drain.sh:523`: `handoff-fire.sh:8936` | `:8935-8941` | **No.** That is `--transplant-cause` argument parsing. |
| `hooks/mailbox-drain.sh:534`, `:545`: ":7100" (ping recipe), ":7087" (slug) | `:7078-7109` | **No.** Both lines are in the recycle dead-watcher. |
| `scripts/wrap-ledger.sh:1016-1018`: `bin/cc-custody:35-38` (POLARITY), `:44-46` (TTL rule) | `bin/cc-custody:36-39`, `:45-49` | **Shifted.** Both are off by about one line. |
| `scripts/wrap-ledger.sh:1017-1018`: `hooks/session-continue.sh:608-612` ("an unattributable row still counts … HEDGES") | — | **No.** That text is at `hooks/session-continue.sh:726-730`; `:608-612` are `local`/`sf=` lines. |
| `scripts/wrap-ledger.sh:1058` cites `session-continue.sh:302` for the raw pane capture; `hooks/session-continue.sh:724-725` says `:197` | — | **Contradictory.** At least one is wrong; I read neither line. |

## 6. Not verified within the 25-call budget
- Where `NB_ARMED_TARGET`, `NB_SLUG`, `FIRE_MARKER` and `ENGAGE_VERIFY` are assigned.
- The cloud opener's code (cc-offload / `--cloud`).
- `bin/cc-reaper` and the death-watch scripts.
- The body of `hooks/lib/session-busy.sh`.
- The `$cwd` / `$_opane` assignments in `session-continue.sh`.
- Whether `fire_cleanup` stamps the peer on non-zero exit codes (claimed at `scripts/handoff-fire.sh:13311-13313`).
