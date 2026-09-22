<!-- arm B = claude-opus-5-5 @high · brief T1-custody · raw worker output, verbatim -->

# Custody debt lifecycle at snapshot 47c3317eb

**Scope.** The Grep and Glob tools were not available here, and Bash was forbidden, so the whole survey was done with Read and a 25-call budget against a 13,381-line `scripts/handoff-fire.sh`. Every claim below cites a line I actually read. Anything I could not locate is listed in section 4 and is not asserted.

---

## 1. Recording

### Where the store lives and what one file is
- **Directory:** `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}` (bin/cc-custody:65).
- **One file per originator cwd:** `<cwd-key>.jsonl`, append-only (bin/cc-custody:12-13, and the `>>` append at :179).
- **How the key is made:** `_fired_cwd_key` resolves the path with `cd "$d" && pwd -P`, hashes it with `shasum -a 256`, and keeps the first 32 hex characters (hooks/lib/origin-identity.sh:68-77).
  - Symlinked and `/tmp`-vs-`/private/tmp` spellings therefore share one file (origin-identity.sh:71-73; test tests/cc-custody.bats:75-79).
  - A path that does not resolve produces no key. `open` then dies with "cwd does not resolve" (bin/cc-custody:177), and reads find no file (:133).

### What a row carries
- Always present: `ts`, `kind`, `cwd` (bin/cc-custody:96).
- Present only when non-empty: `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` (bin/cc-custody:97-103).
- `ts` is UTC with one-second resolution (:85).
- `open` needs both `--cwd` and `--target` (:176).
- `provenance` is written only by `open` (:179). The `return` and `abandon` writers pass 8 arguments, so the 9th (`provenance`) is empty and omitted. They also pass an empty `notifyBack` (:195-199, :223-227).

### How the open set is computed at read time (`_OPEN_JQ`, bin/cc-custody:108-112)
- **Join key:** `"m:"+marker` when `marker` is non-empty. When the marker is missing or empty, the key falls back to `"s:"+slug+"|"+targetPane`, with a missing field becoming `""` (:110).
  - Because `targetPane` is mandatory on `open`, an unmarked row with no slug keys as `s:|<target>`.
- **Which row wins:** rows are grouped by key, sorted by `ts`, and the `last` one wins; only groups whose winner has `kind=="open"` survive (:111).
  - Ties are not handled explicitly. With one-second resolution, the winner between same-second rows comes down to jq's sort order. The test avoids this with `sleep 1 # ts is second-granular; the re-open must sort strictly later` (tests/cc-custody.bats:54), so the tie behaviour is untested.
- **Scope of a read:** with `--cwd`, only that one file is read. Without it, every `*.jsonl` is read (:130-139). `list` and `count` `cat` the files together, so marker keys group across the whole store (:240, :263).
- **Age:** `ageHours` and `stale` are added afterwards (:118-122). The TTL defaults to 24 hours (:66-67). A timestamp that will not parse gives `ageHours:null` and `stale:false`, so an unknown age keeps the debt rather than clearing it (:59-60, :119-121).

### When a fire opens a row
The single site is `engage_apply_consequences` (scripts/handoff-fire.sh:13195-13238). The condition is:

```
[ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody
```
(handoff-fire.sh:13219)

- **Which directory it is keyed on:** `--cwd "$PWD"`, the *firing* session's cwd. The comment says so explicitly: "keyed on the FIRING cwd, not the target worktree" (:13198-13200, :13220).
- **What goes into the row:** target = `SPAWNED_PANE`, marker = `FIRE_MARKER`, slug = `NB_SLUG`, notify-back = `NB_ARMED_TARGET`, originator pane = `FIRING_SID`, and provenance = `proven` on rc 0 or `unproven-rc$rc` otherwise (:13196-13197, :13220-13223).
- **Self-retire no longer matters:** the earlier `WANT_SELF_RETIRE` condition was removed. "Was a return owed" is now judged by `NB_ARMED_TARGET` alone (:13203-13211).
- **Only verified fires reach it:** `engage_apply_consequences` runs only inside `if [ "$ENGAGE_VERIFY" = 1 ]` (:13239). The comment says `ENGAGE_VERIFY=0` exactly when the run is a recycle or a dry run (:13213-13218). I did not read the assignment that sets it.

### Engagement outcomes and their consequences
The table is `engage_rc_consequence` (handoff-fire.sh:3547-3597). `verify_engagement` returns only 0, 1, 2, 4 or 5 (:3380-3385, :3416-3516).

| rc | Meaning | Custody debt opened? | Goal armed? | Branch that applies it |
|---|---|---|---|---|
| 0 | engaged | yes (:3550) | yes | :13273 |
| 1 | never ingested inside the window | **yes**, as `unproven-rc1` (:3574) | **no** (:3580) | :13365 |
| 2 | pane parked at a shell, launcher never ran | no (:3583) | no | :13289 |
| 4 | session alive but wedged on a dialog | yes (:3589) | yes | :13301 |
| 5 | cannot tell (non-verdict) | yes (:3592) | yes | :13323 |
| any other | undocumented | yes, fail-open with a stderr warning (:3593-3595) | yes | see below |

- **The /goal arm does not follow the same rule.** It differs only on rc 1: custody fails open there, but the goal stays fail-closed, because pasting a goal before the brief is ingested would be "a wrong first instruction" (:3575-3580). The goal call site is :13232-13235.
- **On any non-zero rc, the fire prints a notice** that the debt was opened anyway (:13227).
- **The `*)` fail-open arm is unreachable from the fire path.** The final `else` branch hard-codes `engage_apply_consequences 1 never-engaged` (:13365). An undocumented rc would therefore be treated as rc 1 (custody yes, goal no), not given the `*)` treatment.

### Every producer that opens rows
1. **`scripts/handoff-fire.sh`**, at :13220 as above. The producer list in bin/cc-custody:22-24 names only this one.
2. **Cloud fires (cc-offload / cloud-return).** scripts/wrap-ledger.sh:1021-1024 says 117 open rows were "all cc-offload cloud fires", and mailbox-drain.sh:534 says cloud pings use `HANDOFF-PING cloud/<id>`. So a cloud producer exists, but its code is not verified.
3. **Manual `cc-custody open`.** The desk hand-opened one row (handoff-fire.sh:3527-3528). The test suite also opens rows directly (tests/cc-custody.bats:20ff).

### Line citations that do not hold
- handoff-fire.sh:3520 says the custody debt is at `:10715` and the goal arm at `:10723`. They are actually at :13219-13223 and :13232-13233.

---

## 2. Discharging

Discharge means appending a row with `kind` `return` or `abandon`. The appended row copies the matched open row's `cwd`, `targetPane`, `marker` and `slug`, so it lands on the same key (bin/cc-custody:223-227). How a token is matched: the open set is filtered with `select(.marker == $t or .slug == $t) | first`, one file at a time, and the first file with a match wins (:214-221). If nothing matches, the command still exits 0 and prints "no OPEN row matches" on stderr (:229-233; test :59-65).

Every site I found, one per item:

1. **Ping receipt in `hooks/mailbox-drain.sh`**
   - **Verb:** `return "$_slug" --cwd "$_cust_cwd"` (mailbox-drain.sh:579).
   - **Key:** the slug. A received ping only carries `HANDOFF-PING <slug>:`, and the marker is never sent to the peer (:532-536).
   - **Scope:** only the session's own cwd. That cwd comes from the hook payload's `.cwd`, falling back to `$PWD` (:564-568). Slugs are prompt-file basenames that two originators can share, so a store-wide discharge could drop another cwd's debt (:543-550).
   - **Conditions:**
     - `CC_DRAIN_CUSTODY_RETURN` is not 0, and the delivered body contains `HANDOFF-PING` (:558).
     - A `cc-custody` binary is found (:559-563, :569).
     - The slug matches `[A-Za-z0-9][A-Za-z0-9._/-]*` before a `:`. At most 8 slugs are handled per drain, de-duplicated (:584-586).
     - Self-close's slug-less `HANDOFF-PING (auto, …)` is excluded by construction (:570-573).
     - Success is read from an empty stderr (:576-582).
   - **Caveat:** `first` returns a single row, so if two open rows in the cwd share a slug, one ping discharges only one of them. This follows from :216.

2. **Self-close (`sc_announce_before_retire` in handoff-fire.sh)**
   - Calls `return` by **marker**, store-wide from any cwd, because a marker is globally unique (bin/cc-custody:22-23, :26-27; mailbox-drain.sh:573 "discharges by marker").
   - **Not verified:** I could not locate that code in the 13k-line file.

3. **`cloud-return.sh`**
   - A store-wide `return` by marker (mailbox-drain.sh:543-544; bin/cc-custody:26-27).
   - **Not verified:** I did not read it.

4. **Manual `cc-custody return|abandon <token>`** (bin/cc-custody:182-234)
   - The token may be a marker or a slug. `--cwd` is optional; without it the command runs store-wide.
   - `abandon` requires `--why` (:212). A flag given where the token should be is rejected as malformed (:144-148, :211).

5. **Bulk, age-driven `abandon --stale --why …`** (bin/cc-custody:186-210)
   - For every open row with `stale==true` in scope (one cwd, or store-wide without `--cwd`), it appends an `abandon` row and prints how many it discharged.
   - `--why` is required (:187; test :139-151).
   - It runs only when someone invokes it explicitly (:55-58).

### Does anything expire or delete rows automatically?
**No, as far as the code I read shows.** "Nothing here deletes, nothing here rewrites" (bin/cc-custody:45-49). The usage text ends "nothing ever expires" (:271). The bare `count --open` still counts stale rows (:256-257; test :116-117). I could not search the repo for a scheduled `abandon --stale`, so I cannot rule that out.

### Does the deathwatch/reaper discharge anything?
**No evidence that it does, and the repo's own statements say it does not.** I did not read `bin/cc-reaper` or the deathwatch code, so this rests on these lines:
- The producer and discharger list names only handoff-fire, mailbox-drain and cloud-return (bin/cc-custody:22-27).
- mailbox-drain.sh:526-528: a peer "closed by the operator, by a reaper, or by a crash left its originator's row OPEN FOREVER".
- The stale class exists because a debt from a peer "that was reaped" stays open "until a human runs `abandon`" (bin/cc-custody:41-44).

---

## 3. Consuming

### a. Close-ledger rung: `count_open_custody` (scripts/wrap-ledger.sh:1047-1085)
- **When the count is taken:** only in the ✅-eligible `else` branch (:1990-1997). That branch is reached after ⛔ (:1971-1978), a dirty tree (:1979), a DoD remainder (:1981) and unlanded commits (:1983) have all been ruled out.
- **What that means for other turns:** on any turn whose rung is ⛔, 🔧 or 📦, `CUSTODY_OPEN` stays at its initial 0 and `CUSTODY_SRC=skip` (:1047). It is emitted as 0 (:2202-2208), and `--full` shows "not counted (a worse rung governs)" (:2328).
- **Effect on the rung:** `CUSTODY_OPEN>0` gives 🔧. That outranks resident teammates, filed rows, no-trunk, 🚀 and 👤 (:1998-2010, closed at :2118).
- **Lines that read the count:**
  - `j="$(_bounded … "$bin" list --open --cwd "$PWD" --json …)"` (:1063)
  - fallback: `n="$(_bounded … "$bin" count --open --cwd "$PWD" …)"` (:1081)
- **Attribution:**
  - The pane id is `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the last colon stripped (:1061).
  - A row is **known** if `originatorPane` or `notifyBack` is non-empty.
  - A row is **mine** if `originatorPane == pane`, or `notifyBack == pane`, or `notifyBack` ends with `"-"+pane` (:1065-1071).
  - `CUSTODY_MINE` counts rows that are known and mine. `CUSTODY_UNK` counts rows that are not known. Known rows that belong to another pane are dropped. `CUSTODY_OPEN = MINE + UNK`, with `SRC=pane` (:1072-1076).
  - With no pane id, no jq, or no JSON output, it falls back to a plain cwd count: `MINE=0`, `UNK=n`, `SRC=cwd` (:1079-1084).
  - No binary gives `SRC=none` (:1057); a failed read gives `SRC=error` (:1082-1083).
- **What counts as "yours":** the raw pane id, the bare-pane form of `notifyBack` (e.g. `386`), and the `<worktree>-<pane>` form (e.g. `wt-pool-2-415`). The `-` anchor is required so that pane 15 cannot claim pane 415's row (:1037-1039).
- **Readout wording:** when `SRC=pane` and `MINE=0`, the 🔧 readout hedges ("cannot say whose", :2006-2007). Otherwise it uses :2009. The `--full` row is :2313-2330.
- **Memo key:** includes `CC_CUSTODY_BIN`, `CC_CUSTODY_DIR` and the pane id (:388, :396), so a resumed session with a renumbered pane is not served its predecessor's count.
- **Line citations that do not hold:**
  - :1016-1018 cites `hooks/session-continue.sh:608-612` for "an unattributable row still counts, and the message HEDGES". Those lines are `local` declarations and the state-file path inside `wake_floor` (session-continue.sh:609-611). The rule is actually at session-continue.sh:726-730.
  - The same lines cite `bin/cc-custody:35-38` and `:44-46`. The real spans are POLARITY :36-39 and the NOT-expiry bullet :45-49, so these are off by a line or three.
  - For the capture of the raw pane key, wrap-ledger.sh:1058 cites session-continue.sh:302, while session-continue.sh:724 cites its own `:197`. They disagree, and I read neither line.

### b. Done-claim gate: `hooks/completion-assert.sh:718-719`
- **Line that reads the count:** `CUSTODY="$(lfield CUSTODY_OPEN)"`. If it is greater than 0, the gate sets `contra=1` and adds the "dispatched session(s) have NOT returned…" fact.
- It uses the attributed sum, so unattributable rows still convict.
- It inherits the ledger's ✅-eligible-only gating, so it can only fire where the ledger actually computed a count.
- Capped per class, `COMPLETION_MAX` default 3 (:127, :1238-1262).
- wrap-ledger.sh:1011-1013 says this consumer "read[s] the unattributed field". After the port, the field it reads *is* the attributed sum.

### c. Stop/wake floor: `hooks/session-continue.sh` `wake_floor`
- It computes its own count rather than reading the ledger, and the call is not wrapped in a timeout.
- **Lines that read the count:**
  - `_cj="$("$_cb" list --open --cwd "$cwd" --json 2>/dev/null)"` (:744)
  - the same known/mine jq as wrap-ledger (:748-754)
  - fallback `count --open --cwd "$cwd"` (:762)
- **How the count is used:** `[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0` (:805). Open custody keeps the floor firing, the same way pending mail does.
- **Earlier exits that skip it:**
  - Before the count is taken: floor disabled, no jq, no mailbox lib, or no inbox id (:604-607); a watcher is already armed (:614); a headless session (:656-664); a live goal with mail pending (:697-703).
  - After the count, before :805: a team assignee or a teardown-marked session (:776-798).

### d. Busy line
- wrap-ledger passes `CC_BUSY_CUSTODY_OPEN="${CUSTODY_OPEN:-0}"` into `session_busy_live` (wrap-ledger.sh:2143). This runs after the rung ladder so it sees the final value (:2127-2128).
- What `session_busy_live` does with it is not verified; I did not read hooks/lib/session-busy.sh.

### e. Operator readout: `hooks/operator-readout.sh`
- It is named as the component that "renders the line" (bin/cc-custody:35) and as a reader of `CUSTODY_OPEN` (wrap-ledger.sh:1012).
- **I did not find the line that reads it.**
- What I did see: `cheap_stamp`, the cheap check that lets the hook skip re-rendering inside its damping window, covers only `ACT_DIR`, `DEC_DIR`, `BLG_FILE`, the cwd's HEAD and dirty count, and trunk. The custody store is not in it (operator-readout.sh:1468-1482). A custody open or return on its own therefore cannot invalidate that stamp. I have not verified whether that actually leaves a stale custody line on screen within the TTL.

### f. `cc-custody list` / `count` itself
- These are the contract every consumer calls (bin/cc-custody:235-265).

---

## 4. Not verified

These were out of reach with Read only and 25 calls:
- `sc_announce_before_retire` and the `_hf_custody` wrapper in handoff-fire.sh.
- Where `ENGAGE_VERIFY`, `NB_ARMED_TARGET`, `FIRING_SID` and `FIRE_MARKER` are assigned.
- `cloud-return.sh` and the cc-offload open path.
- `bin/cc-reaper` and the deathwatch code.
- The custody render in operator-readout.sh.
- hooks/lib/session-busy.sh.
- Cross-file citations I could not check: mailbox-drain.sh:523 → `handoff-fire.sh:8936`, :534 → `:7100`, :545 → `:7087`, and handoff-fire.sh:3557 → `:9064`.
