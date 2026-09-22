<!-- arm A = claude-sonnet-5 @max · brief T1-custody · raw worker output, verbatim -->

# The custody-debt lifecycle in claude-infrastructure

All line numbers below are against the pinned snapshot `/tmp/o55probe-repo-47c3317eb` (sha `47c3317eb`). The core implementation is `bin/cc-custody` (274 lines, read in full).

## 1. RECORDING

**Store location, one file per what.** The store is `${CC_CUSTODY_DIR:-$HOME/.claude/autonomy/custody}/<cwd-key>.jsonl` (`bin/cc-custody:65,130-139`) — **one append-only JSONL file per originator cwd**, not per fire and not per marker. The filename is `<cwd-key>.jsonl` where `cwd-key = _fired_cwd_key "$CWD"`, sourced from `hooks/lib/origin-identity.sh` (resolved by walking `$0`'s own symlink first, then `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/origin-identity.sh`, then `$HOME/.claude/hooks/lib/origin-identity.sh`, `bin/cc-custody:73-84`) — "the SAME normalisation the fired-peer store uses, so the two stores cannot disagree about what a cwd is" (`bin/cc-custody:14-15`). I did not open `origin-identity.sh`, so I can't verify the exact key algorithm from code; `docs/plans/CLOSE_INTEGRITY_2026-08-10.md:96` describes it as a hash (`<cwd-hash>.jsonl`) — that's a doc claim I'm flagging, not one I confirmed.

**Row fields.** Built by `_row()` (`bin/cc-custody:93-104`): `{ts, kind:open|return|abandon, cwd}` always present, plus `originatorPane`, `targetPane`, `marker`, `slug`, `notifyBack`, `why`, `provenance` — each included **only if non-empty** (each is `(if $x == "" then {} else {x:$x} end)`). `provenance` is open-only, values `proven` or `unproven-rc<N>` (`bin/cc-custody:87-92`).

**Open-set derivation at read time** — `_OPEN_JQ`, `bin/cc-custody:106-112`:
```
[ inputs ]
| map(. + {k: (if (.marker // "") != "" then ("m:"+.marker) else ("s:"+(.slug//"")+"|"+(.targetPane//"")) end)})
| group_by(.k) | map(sort_by(.ts) | last) | map(select(.kind == "open"))
```
Join key = **marker**, when present; if the marker field is missing/empty, it falls back to the composite key `"s:" + slug + "|" + targetPane` (so a marker-less, slug-less row with an empty targetPane collapses to the degenerate key `"s:|"`, a real collision surface for that case, though not one the header calls out). When several rows share a key, `group_by` + `sort_by(.ts) | last` means **the row with the latest timestamp wins**, and the key survives into the open set only if that winning row's `kind == "open"` — i.e. any later `return`/`abandon` under the same key fully closes it regardless of how many `open` rows preceded it.

**The boolean condition that opens a row.** `scripts/handoff-fire.sh:13219`:
```
if [ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ] && engage_rc_consequence "$rc" custody; then
  _hf_custody open --cwd "$PWD" --target "$SPAWNED_PANE" --marker "${FIRE_MARKER:-}" --slug "${NB_SLUG:-}" \
    --notify-back "$NB_ARMED_TARGET" --originator-pane "${FIRING_SID:-}" --provenance "$prov"
```
Three conjuncts: (a) `NB_ARMED_TARGET` non-empty — set at `handoff-fire.sh:10728` to the resolved `BACK_SID` **only at the point the back-channel trailer is actually appended to the brief** (i.e. `--notify-back` resolved to a real address; a headless fire with no firing pane, or an explicit `--notify-back` with no resolvable id, stands down and leaves `NOTIFY_BACK`/`NB_ARMED_TARGET` empty, `handoff-fire.sh:10711-10718`); (b) `SPAWNED_PANE` non-empty (a pane was actually spawned); (c) `engage_rc_consequence "$rc" custody` returns 0. This whole block only runs when `ENGAGE_VERIFY=1`, which is set only for a genuine fire — `[ "$RECYCLE" = 0 ] && [ "$DRY" = 0 ] && ENGAGE_VERIFY=1` (`handoff-fire.sh:10662`) — so `--recycle` and `--dry-run` fires never reach `engage_apply_consequences` at all and open nothing (`handoff-fire.sh:13213-13218`, reasoned explicitly: a recycle is "same pane by definition," so a row would key the firing session's own cwd against its own pane).

**Directory keying.** The row is opened with `--cwd "$PWD"` — the **originator's (firing session's) own cwd at fire time**, explicitly *not* the fired peer's worktree (`handoff-fire.sh:13198-13200`: "keyed where the ORIGINATOR's ledger can count it (keyed on the FIRING cwd, not the target worktree)").

**Per-engagement-outcome table** — `engage_rc_consequence()`, `handoff-fire.sh:3547-3597` (comment: `$1=rc $2=custody|goal → 0 = DO IT, 1 = do not`):

| rc | meaning | custody | goal |
|---|---|---|---|
| 0 | engaged, proven by transcript | **open** (`:3550`) | **arm** (`:3550`) |
| 1 | never ingested within the window | **open** (`:3574`) | **do not arm** (`:3580`) |
| 2 | pane parked, no session at all | **do not open** (`:3583`) | do not arm (`:3583`) |
| 4 | wedged (booted, alive, stuck on a startup dialog) | **open** (`:3589`) | **arm** (`:3589`) |
| 5 | cannot tell (non-verdict) | **open** (`:3592`) | **arm** (`:3592`) |
| undocumented/new | — | **open, fails OPEN, warns on stderr** (`:3593-3595`) | same |

So custody opens on **every** outcome except rc 2 (no session ever existed to owe a debt). Goal arms only on rc 0/4/5/undocumented — **not** on rc 1, which is the one place custody and goal diverge: a debt is cheap and reversible (`cc-custody abandon`, one appended line), while pasting a goal into a composer that hasn't ingested the brief yet would arm a condition against work the session was never told to do (`handoff-fire.sh:3551-3580`).

**Every producer I found.** Grepping the whole tree for `cc-custody open`/`_hf_custody open`/direct appends of `kind:"open"` turns up exactly **one** call site: `scripts/handoff-fire.sh:13219-13223` (`engage_apply_consequences`), gated as above. I did not find a second opener in code within my tool budget. Project docs (`docs/plans/CLOUD_BACKLOG_PIPELINE.md:200,244`) describe a cloud dispatcher ("`cc-offload up` → `cc-custody open` at the fire") opening rows independently for cloud-fired sessions — I was not able to locate/verify that call site in code, so I'm reporting it as an **unverified doc claim**, not a confirmed second producer.

## 2. DISCHARGING

Five distinct sites, all best-effort (`_hf_custody`'s own comment, `handoff-fire.sh:4143-4157`: "custody bookkeeping must never gate a fire or a close... failures swallowed"):

1. **Self-close** — `handoff-fire.sh:8707`: `[ -n "$_sc_cmk" ] && _hf_custody return "$_sc_cmk" --why "$SC_LEDGER_STAMP"`. Verb `return`. Join key: **marker**, read off the fired peer's own stamp (`_sc_cmk="$(jq -r '.marker // ""' "$FIRED_DIR/$SC_SID.json")"`, `:8657`) — marker-only because the peer only knows its own identity, not which store/cwd the originator's row lives in. Scope: no `--cwd` passed ⇒ **store-wide** (`_files_for` with empty cwd walks every `.jsonl`, `bin/cc-custody:130-139,220`). Condition: the discharge call sits *after* the W3-B1 terminal-close refusal gate (`:8676-8702`) — "a close that does not happen must not discharge the originator's debt" (`:8669-8672`); a **refused** `--terminal` self-close (exit 8, `:8700`) never reaches the discharge call. A marker-less (schema-1) stamp discharges nothing (`:8656,8704-8706`).

2. **`hooks/mailbox-drain.sh:579`**: `"$_cust_bin" return "$_slug" --cwd "$_cust_cwd"`. Verb `return`. Join key: **slug** — the only custody field actually echoed to the peer (`HANDOFF-PING <slug>: …`; the marker is never sent, `:532-535`). Scope: `--cwd`-scoped to `$_cust_cwd` (from the hook payload's own `.cwd`, falling back to `$PWD`, `:564-568`) — deliberately *not* store-wide, because two different originators' prompt-file basenames can collide, and a store-wide slug discharge could silently close a different cwd's debt (`bin/cc-custody:28-32`; `mailbox-drain.sh:546-547`). Condition: `[ "${CC_DRAIN_CUSTODY_RETURN:-1}" != 0 ] && printf '%s\n' "$body" | grep -q 'HANDOFF-PING'` (`:558`); bounded to at most 8 deduplicated slugs per drain (`awk '!s[$0]++' | head -8`, `:586`); "did it actually discharge" is read off cc-custody's own stderr being empty (`:576-579`), since `cc-custody return/abandon` prints its "no OPEN row matches" message to stderr and always exits 0 (`bin/cc-custody:229-233`).

3. **`scripts/cloud-return.sh:537`**: `"$CUSTODY_BIN" abandon "$custody" --why "cloud session superseded — item $item already done"`, guarded by `[ -n "$custody" ] && [ -n "$CUSTODY_BIN" ]` (`:536`) — fires when a cloud session's backlog item turns out already done via another path.

4. **`scripts/cloud-return.sh:979`**: `"$CUSTODY_BIN" return "$custody"`, guarded the same way at `:977` — fires on that script's own success/landed path for a cloud session. Both sites key off a `$custody` variable; I read the two call sites but not the line assigning `$custody`, so I can't independently confirm it's populated from a declaration's `.custody` field beyond the naming convention. Neither call passes `--cwd` ⇒ **store-wide**.

5. **`scripts/cloud-retire-terminal.sh:204,206-207`**: `[ -n "$marker" ] && [ -n "$CUSTODY_BIN" ] || return 0` then `landed) "$CUSTODY_BIN" return "$marker" ;; *) "$CUSTODY_BIN" abandon "$marker" --why "$why" ;;`. Verb depends on a computed disposition: `return` iff disposition is `landed`, `abandon --why "$why"` otherwise. Join key: **marker**. No `--cwd` ⇒ **store-wide**.

**Bulk/age-driven path.** `bin/cc-custody abandon --stale --why <text> [--cwd <dir>]` (`bin/cc-custody:183-210,266-268,271`) *is* implemented — it discharges every row whose derived `stale` flag is true (`ageHours >= CC_CUSTODY_TTL_HOURS`, default 24h). But grepping the whole `.sh` tree for `abandon --stale` finds **zero callers** anywhere outside `bin/cc-custody`'s own usage string — nothing in the repo invokes it automatically. This matches the header's own framing: "The disposition is a human/agent decision that age makes cheap — never an automatic one" (`:56-58`).

**Does anything expire/delete a row automatically? No.** The header states it explicitly: "NOT expiry... Nothing here deletes, nothing here rewrites; the log stays append-only and `count --open`... counts stale rows exactly as before" (`bin/cc-custody:45-49`). `stale` is purely a derived, visible annotation computed at read time from `ts` (`_AGE_JQ`, `:114-122`) — it never filters the open set unless `--stale`/`--fresh` is explicitly passed, and an unparseable/absent `ts` yields `ageHours: null` and `stale: false` (fails toward *keeping* the debt, `:59-60`).

**Deathwatch/reaper — adjudicated: it discharges nothing.** `scripts/custody-deathwatch.sh` invokes `"$CUSTODY_BIN"` exactly twice: an existence check (`:277`) and `list --open --json` with no `--cwd` — store-wide (`:282`). There is no `return` or `abandon` call anywhere in the file (verified by grepping every `"$CUSTODY_BIN"` occurrence). It only composes escalation text naming the remedy — `"...\`cc-custody return ${key}\`; if it is superseded, \`cc-custody abandon ${key} --why …\`."` (`:353`) and a backlog `needs` row for orphaned/unreachable-originator debts (`:388`) — it is a pure read-side alarm/escalator, never an actuator on the store.

## 3. CONSUMING

**A. Close-ledger rung — `scripts/wrap-ledger.sh`.** The rung ladder is a strict `if/elif/…/else` chain: default `RUNG="✅"` (`:1962`) → `if [ "$BLOCKED" -gt 0 ]` ⇒ ⛔ (`:1972-1978`) → `elif [ "$DIRTY" -eq 1 ]` ⇒ 🔧 (`:1979-1980`) → `elif [ "$REMAINDER" -gt 0 ]` ⇒ 🔧 (`:1981-1982`) → `elif [ "$UNLANDED" -eq 1 ]` ⇒ 📦 (`:1983-1989`) → **`else`** (the "✅-eligible" branch, `:1990`). `count_open_custody` is called **only inside that final `else`**, at `:1997` — the comment is explicit: "ONLY here do the custody count... matter — on the 🔧/📦 paths none can change the answer, so none is ever paid for" (`:1991-1996`). Implication for turns whose rung is decided earlier: on any turn where BLOCKED/DIRTY/REMAINDER/UNLANDED already fired, `count_open_custody` is **never invoked** — `CUSTODY_OPEN` stays at its pre-declared default `0` and `CUSTODY_SRC` stays `"skip"` (`:1047`, never overwritten), which the code deliberately distinguishes from "counted zero" (`:1993`). Inside the `else`, `if [ "$CUSTODY_OPEN" -gt 0 ]` (`:1998`) forces `RUNG="🔧"` (`:2006-2010`), which blocks the nested `else` at `:2012` where 🚀/👤/✅ get computed — so custody's 🔧 outranks 🚀/👤/✅ in outcome, matching the documented priority `⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅`, even though in source order it's evaluated after the other 🔧/📦 checks (same symbol, first-match-wins).

Attribution: `count_open_custody()` (`:1048-1085`) reads `cc-custody list --open --cwd "$PWD" --json` (`:1063`) and applies (`:1065-1071`):
```
def known: ((.originatorPane // "") != "") or ((.notifyBack // "") != "");
def mine:  ((.originatorPane // "") == $p) or ((.notifyBack // "") == $p) or ((.notifyBack // "") | endswith("-" + $p));
```
`CUSTODY_MINE` = rows `known and mine`; `CUSTODY_UNK` = rows *not* `known` (neither field present); `CUSTODY_OPEN = CUSTODY_MINE + CUSTODY_UNK` (`:1076`) — rows that *are* attributable but to someone else (`known` and not `mine`, i.e. provably a sibling's dispatch) are silently dropped from the sum ("`theirs` is DROPPED and `unk` is KEPT", `:1019`). "Yours" therefore means: `originatorPane` exact match, `notifyBack` exact match, or `notifyBack` ending in `"-"+pane` (the `<worktree>-<pane>` address form, guarding a bare-pane suffix collision like "15" matching "415", `:1037-1039`). `CUSTODY_SRC` states (`:1041-1046`): `pane` (attributed), `cwd` (fallback — no pane id/jq, everything counted into `CUSTODY_UNK`, `:1084`), `none` (no binary), `error` (unreadable store), `skip` (not computed — a worse rung already governs).

**B. Done-claim/completion gate — `hooks/completion-assert.sh:718-719`**:
```
718: CUSTODY="$(lfield CUSTODY_OPEN)"; case "$CUSTODY" in ''|*[!0-9]*) CUSTODY=0 ;; esac
719: [ "$CUSTODY" -gt 0 ] && { contra=1; facts="${facts}${CUSTODY} dispatched session(s) have NOT returned (custody open — collect+synthesize+land their work then \`cc-custody return <marker|slug>\`, or \`cc-custody abandon <token> --why …\`; awaiting them ARMED via cc-await-ping is a valid non-close state, but 'done' is not); "; }
```
Reads the same `CUSTODY_OPEN` machine field wrap-ledger emits at `:2202` (`printf 'CUSTODY_OPEN=%s\n' "$CUSTODY_OPEN"`) via its own `lfield` helper — so it inherits the identical "skip" blind spot on turns where a worse rung already fired. When genuinely `>0`, it sets `contra=1`: an open custody debt is treated as a logical contradiction of a "done" self-assertion.

**C. Stop/wake floor — `hooks/session-continue.sh`.** Independently re-derives its own count (does not read wrap-ledger's fields) via a second `cc-custody list --open --cwd "$cwd" --json` call (`:743-744`) using the byte-identical attribution predicate (`:748-754`). Firing condition, `:805`:
```
[ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || [ "$cust" -gt 0 ] || return 0
```
— proceeds (doesn't bail) on first-ever idle, or pending mail, or `cust = cust_mine + cust_unk > 0`. If it proceeds (and isn't exempted by the goal-live/teardown/assignee abstains, budget exhaustion, TTL, or the kill switch — all checked earlier in the function), it emits a block instructing `cc-await-ping` be armed before stopping (`:821`, or the `--idle-scoped` form under a live `/goal`, `:827-833`), prefixed, when `cust_mine>0` or `cust_unk>0`, with a custody-specific paragraph (`:878-885`) — e.g. `:879`: `"🧵 ${cust_mine} dispatched session(s) YOU fired have NOT returned (\`cc-custody list --open --cwd . --json\`...) ... then \`cc-custody return <marker-or-slug>\` (or \`cc-custody abandon <token> --why …\` if superseded)."`

**D. Operator-facing readouts — `hooks/operator-readout.sh:915`**: `custody="$(lf CUSTODY_OPEN)"; case "$custody" in ''|*[!0-9]*) custody=0 ;; esac` — a third differently-named helper (`lf`) reading the same wrap-ledger `CUSTODY_OPEN=` output. Folded into the rendered "in progress" parts at `:929`: `[ "$custody" != "0" ] && parts="${parts:+$parts · }${custody} dispatched session(s) NOT returned"`; the drivable-action line, when custody is the live cause and no resident teammates are also outstanding, becomes `:940`: `state="${state} → cc-custody list --open --cwd ."` — it hands over the *listing* command only, not `return`/`abandon`, consistent with the comment at `:936-938` ("this is a check, not an actuator").

**E. Others found.** `hooks/lib/why-tier.sh:210-212` carries the expanded help text for a custody-flavored `session-continue.sh --why custody` query (the three commands: `list --open --cwd . --json`, `return <marker-or-slug>`, `abandon <token> --why "…"`) — a documentation/help surface, not a live count-reader. `hooks/validate-bash.sh:633,713` references `cc-custody` only to exempt it from the duplicate-worker write-claim gate ("Reporting is NOT refused: cc-backlog, cc-notify and cc-custody match no arm of this gate") — related, but not a consumer of the open-set count.

## Citation checks against the doc claims

- `docs/plans/STOPHOOK_MESSAGE_TIERING.md:361` says a prior citation of `cc-custody:254` for the "awaiting ARMED is a valid non-close state" carve-out **does not hold**. I independently confirm this: `bin/cc-custody:254` is `files="$(_files_for "$CWD")"` inside the `count)` verb — nothing about that carve-out.
- `docs/plans/STOP_CHAIN_WAVE2.md:220` cites `bin/cc-custody:35-38` for the POLARITY "over-count rather than silently drop" rule. In the file I read, that block actually spans **lines 36-39** (line 35 is the tail of the preceding CONSUMERS sentence) — a one-line-off citation; substance is otherwise correctly described.
- `bin/cc-custody:212-227`, cited by `handoff-fire.sh:8705` for the `--why` field on `return`/`abandon`, checks out: that span is exactly the `TOKEN`-match/`_row` construction implementing it.
- `~/.claude-next/CLAUDE.md`'s own one-line summary ("a fire that arms `--notify-back` records a DEBT... the peer's self-close discharges it") is accurate but incomplete against "exhaustive": self-close is one of five discharge sites, not the only one.
