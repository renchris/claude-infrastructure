# Slot: sender identity at send time, and how it survives forwards

Date 2026-10-10. Worktree `peer-mail-headline` at `110ea9a64`. Read-only with respect to the repo, `$HOME/.claude`,
settings, and every mailbox, `.seen` and `.acked` file. Every probe was either a read of a live file or ran
against a scratch `CC_MAILBOX_DIR=/tmp/slot-identity-probe/mbx`. Probe scripts are in `/tmp/slot-identity-probe/`.
Load during the timings was 826 to 856 (`sysctl -n vm.loadavg`), so every timing is a loaded-box figure.

Question: at SEND time, how does cc-notify work out the sender's pane number and session TITLE, and how do we
keep the ORIGINAL sender through forwards?

---

## 1. What cc-notify writes today

**The line.** `bin/cc-notify:1146`:

```
printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$FROM" "$MSG_1LINE" >> "$MAILBOX_DIR/$uuid.md"
```

The line holds a timestamp, `[FROM]` and the body, which `bin/cc-notify:1095` flattens to one line. It holds
no pane, no session id and no title. The sender's pane IS known at this point (`own_uuid`), but it is written
only to `.sent/<own_uuid>` (`_record_send`, `bin/cc-notify:1128-1143`) and to `.sent-lines/<own_uuid>`
(`bin/cc-notify:1209+`). Those are side stores keyed by the sender, not part of the line.

**Who the sender is.** This is `resolve_from`, `bin/cc-notify:588-596`:

```
resolve_from() {
  [ -n "$FROM" ] && return 0                                   # --from wins outright
  local rdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  if [ -n "$own_uuid" ] && [ -f "$rdir/$own_uuid.json" ]; then
    FROM="$(jq -r '.name // empty' "$rdir/$own_uuid.json" 2>/dev/null)"
  fi
  [ -n "$FROM" ] || FROM="$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | sed 's/^\.//')"
}
```

- `own_uuid` is set at `bin/cc-notify:581` as `${CC_PANE_ID:-${ITERM_SESSION_ID:-}}` with everything up to the
  last `:` stripped. Under kitty, `scripts/kitty-setup.sh` exports `ITERM_SESSION_ID=w0t0p0:$KITTY_WINDOW_ID`
  (it is described in `hooks/lib/mailbox-pending.sh:880-881`), so `own_uuid` is the kitty window id. In this
  session it is `233` (measured: `ITERM_SESSION_ID=w0t0p0:233 KITTY_WINDOW_ID=233`).
- There is one direct file read with one `jq` and no it2 IPC. The registry-wide `registry_load`
  (`bin/cc-notify:259-344`) is not used for the sender. It is used only for resolving the TARGET
  (`registry_name_to_uuid` :384, `registry_prefix_to_uuid` :403).
- **Drift:** cc-notify's `own_uuid` has no `KITTY_WINDOW_ID` fallback. The registry writer does have one
  (`hooks/session-register.sh:173`: `CC_PANE_ID → ITERM_SESSION_ID → KITTY_WINDOW_ID`), and so does
  `bin/cc-wake:187`. Take a kitty process whose `ITERM_SESSION_ID` override did not apply. It registers under
  its window id but sends as the account fallback.
- **Stale comment:** `bin/cc-notify:1101` cites `resolve_from` at ":406-411". The function is at :588-596.
- `--from <x>` replaces the identity completely (`bin/cc-notify:566-567`, :589). Live callers that pass it:
  `cc-bus` (`bus:$actor`, `bin/cc-bus:874`), `cc-announce` (:157), `cc-resume-debt` (:436, :640),
  `handoff-fire` (`recycle-watcher` :4396/:4433, `handoff-fire` :10179) and `desk-invariant` (:221). Those sends
  lose the pane identity even when they run inside a registered pane, because the registry is never consulted
  once `--from` is set.

## 2. The session registry (where pane and name live)

**Writer:** `hooks/session-register.sh` (SessionStart). **Readers:** `bin/cc-sessions` (lazy sweep plus the
`--json`/`--names` addressing views, `bin/cc-sessions:275-366`) and cc-notify `registry_load`. `hooks/lib/identity.py`
is NOT session identity. It reads the operator's personal overlay (`identity.local.json`: e-mails, mailbox
aliases, git author) and plays no part here.

- Store: `$HOME/.claude/cc-registry/<paneKey>.json`, one row per pane key, written atomically (tmp+mv,
  `hooks/session-register.sh:364-377`).
- Pane key: `pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"; pane="${pane##*:}"`
  (`hooks/session-register.sh:173`). A background fork recovers its key from the parent's row (:183-188).
- **Name:** `name="${CC_SESSION_NAME:-$(basename "$cwd")-$short}"` with `short="${pane%%-*}"`
  (`hooks/session-register.sh:220-221`). Under kitty, `short` is the whole window id, so the trailing `-225` of
  `wt-cc-224434-52011-225` IS the pane number. Under iTerm2 it would be the first 8 hex digits of the pane UUID.
  `CC_SESSION_NAME` overrides the whole name, so **the trailing number is a convention, not a field**. Read the
  pane from `.paneUUID`, never by parsing it out of `.name`.
- Columns: written at `hooks/session-register.sh:366-372`. Read live (python census over
  `~/.claude/cc-registry/*.json`): 43 rows, and all 11 keys are present on all 43:

| key | meaning |
|---|---|
| `paneUUID` | the pane key: kitty window id (`"225"`), iTerm2 pane UUID, or `CC_PANE_ID` (headless) |
| `name` | friendly name, `<cwd-basename>-<short>` or `CC_SESSION_NAME` |
| `cwd`, `account` | the account is the `CLAUDE_CONFIG_DIR` basename without its leading dot |
| `pid`, `lstart` | the claude pid plus its `ps -o lstart` (the pid-reuse guard) |
| `startedAt` | epoch ms |
| `session_id` | the harness session id (the join key to the transcript) |
| `surface` | `pane` or `headless` |
| `kitty_listen_on`, `kitty_pid` | the kitty instance (window ids are only unique within one kitty) |

Example live row (`~/.claude/cc-registry/233.json`, read-only):

```
{"paneUUID":"233","name":"peer-mail-headline-233","cwd":"/Users/chrisren/Development/.worktrees/peer-mail-headline",
 "account":"claude-quaternary","pid":22360,"startedAt":1791692663000,"session_id":"6ecdcaa0-5370-4c62-bdda-e2fe9769c869",
 "surface":"pane","lstart":"Sun Oct 11 04:24:16 2026","kitty_listen_on":"unix:/tmp/kitty-64211","kitty_pid":64211}
```

Measured: all 43 live `paneUUID` values are numeric kitty window ids, and all 43 rows have `surface=pane`. On
reuse, the registry comment and `hooks/lib/mailbox-pending.sh:611-625` / :879-887 agree: a window id is reused
from 1 after every kitty restart. So "pane 225" names a seat in ONE kitty epoch, and a headline should pair it
with the sent time.

## 3. What "title" can mean: the sources on disk and what each costs at send time

| source | where | populated (measured) | cost per send (measured) | verdict |
|---|---|---|---|---|
| registry `name` | `cc-registry/<pane>.json` `.name` | 43/43 live rows | one `jq`, 5-18 ms (`timing.sh` A/B) | this is what `[from]` holds today. It carries the pane, but it is a cwd-basename and not a topic |
| **transcript `ai-title`** | `~/.<account>/projects/<slug(cwd)>/<session_id>.jsonl`, records `{"type":"ai-title","aiTitle":"…"}`, re-appended over a session's life (this session: 8 copies) | 40/43 live rows have one in the last 64 KB. The other 3: 2 are dead retained rows with no transcript and 1 is a live session with no transcript yet (pane 229) | `tail -c 65536 \| grep -o aiTitle \| tail -1`: 15-57 ms (`timing.sh` C). A whole-file grep on a 4 MB transcript: 75-116 ms (D). In-process python tail read: 0.2-14 ms (`census.py`) | **this is the title in the target example**: pane 225 → `/limit-recover pane recovery gap` |
| transcript `custom-title` (`/rename`-style) | same file, `{"type":"custom-title","customTitle":"…"}` | 14 of 2,036 transcripts modified in the last 14 days, tail 256 KB (`tails.py`). 0 of 40 live rows | same tail read | it is rare, but when it is present the operator chose it, so it should win |
| transcript `agent-name` | same file, `{"type":"agent-name","agentName":"…"}` | 75 of 2,036 (`tails.py`) | same tail read | a third candidate. The examples look like ai-title-style topics |
| Claude Code `sessions/<pid>.json` `.name` | `~/.<account>/sessions/<pid>.json` (`name`, `nameSource`, `nameSince`, `status`) | 48 files: `nameSource=derived` ×46 (`<cwd>-<2 hex>`, e.g. `peer-mail-headline-ce`), `auto` ×2 (an AI title) | one small JSON read | not useful as it stands: "derived" is a cwd label. `auto` and `/rename` would be useful, but the `/rename` value (`nameSource=?`) is UNMEASURED |
| kitty / iTerm tab title | the terminal | not read | needs `kitty @ ls` or it2 IPC (banned by the brief, and it2 is the measured >120 s hang, `bin/cc-notify:433`) | rejected for the send path. Whether Claude Code sets the tab title to the aiTitle is UNMEASURED |

A combined candidate capture runs one `jq` on the sender's own row, then `tail -c 64K` on the sender's
transcript, then a `grep -oE '"(customTitle|agentName|aiTitle)":"[^"]*"'`. Six runs took 30 / 45 / 57 / 94 /
104 / 131 ms (`/tmp/slot-identity-probe/combined.sh`), and the result was
`pane=225 name=wt-cc-224434-52011-225 title=/limit-recover pane recovery gap`, which is exactly the target
headline. For scale, `cc-notify --help` alone (the process startup floor) takes 46-65 ms (`timing.sh` F). The
capture therefore roughly doubles the fixed part of a send under load. It should be bounded and best-effort:
title absent means pane only, and a send never fails over a title.

Caveats on the title read:
- `[^"]*` truncates a title that contains an escaped quote. Use `jq -r` on the matched line, or a python one-shot.
- A last-match-wins scan mixes the three record kinds. Precedence should be custom-title > agent-name > ai-title,
  taking the newest of each.
- Cross-account path: the transcript lives under the row's `account` config dir (`~/.<account>/projects/…`).
  The mailbox and registry dirs are shared across accounts (`scripts/limit-recover/lr-handoff.sh:762-765`), but
  `projects/` is not.
- Snapshot semantics: the title is the sender's topic AT SEND TIME. It must be captured into the line. A reader
  that resolves it later gets the wrong topic, or nothing once the sender is gone. This is the same argument
  `_record_send` makes for recording facts about the past (`bin/cc-notify:1122-1127`).

## 4. Automated senders (no registered session)

`resolve_from` falls through to `basename(CLAUDE_CONFIG_DIR or ~/.claude)` without its leading dot. A launchd
job or a daemon has neither `ITERM_SESSION_ID` nor `CLAUDE_CONFIG_DIR`, so it signs as **`claude`**. A script
running under an account env with no pane row signs as `claude-<account>`.

Measured over the live corpus (`froms.py` / `claude_from.py`; lines whose ORIGIN stamp falls in the last 30 days,
7,231 lines in total):
- `[claude]`: **2,951 lines (40.8%)**. Top bodies: `⚠️ SUPERVISOR PAGE` 913, `⛔ PERMISSION-PENDING` 380 plus
  `… ESCALATED` 206, `⚠️ REAPER SURFACE` 109, `⚠️ REAPER SELF-CHECK` 69, and a long tail of `[desk-sweep] NEW: …`.
  Example senders: `scripts/lead-supervisor.sh:434/437` calls cc-notify with no `--from`.
- `[cc-await-ping]`: 1,694. This is a SECOND line writer that bypasses cc-notify altogether
  (`bin/cc-await-ping:1014`, :1057, `printf '%s [cc-await-ping] …' >> "$box"`).
- `[claude-quaternary|tertiary|secondary|next]`: 67 + 39 + 39 + 16. These are mostly `SESSION DEATH —` and
  `RECYCLE RETRY`, plus a few REAL agent messages (`[lead] …`, `HANDOFF-PING …`) from sessions whose pane had no
  registry row. In those cases the account fallback hides a real peer.
- Lines with a registered `…-<pane>` name: 2,353. Literal `--from` labels: 1,766, most of them cc-await-ping.

**What the headline should show for these senders.** Show a role label, not an account name, and no pane:
`⚙ lead-supervisor · SUPERVISOR PAGE …`. Two changes get there:
1. Every daemon or hook sender passes `--from <daemon-name>`. A lint could enforce this, the same way
   `scripts/typed-send-lint.sh` guards other send rules.
2. The fallback in `resolve_from` becomes self-describing instead of naming the account. It would use the
   `--from` value if set, else the registry name, else `auto:<parent comm>` (`ps -o comm= -p $PPID`, 21-42 ms
   measured), else the account.

The headline renderer then shows `pane N · <title>` only when the line carries a pane, and `⚙ <label>` otherwise.

## 5. Forwards: every place a line moves, and whether `[from]` survives

| site | mechanism | line shape that lands | does the original `[from]` survive? |
|---|---|---|---|
| send-time `.forward` chain (`bin/cc-notify` ~1037-1047 calls `mailbox_forward_of`, `hooks/lib/mailbox-pending.sh:593-609`) | the ADDRESS is redirected before the enqueue. The line is written once, fresh, into the successor's box | `<ISO> [<from>] <body>` | yes. No forward marker at all, so the reader cannot tell it was redirected |
| `.forward` writers: `desk-register:173-182`, `desk-invariant.sh:363-364/481`, `handoff-fire.sh:7683-7684`, `cc-restore-rebind:215` | pointer files only (`mailbox_write_forward`, lib :664-681) | n/a | n/a (they move no lines) |
| **adoption / migration** `mailbox_migrate` (lib :696-740). Callers: `hooks/mailbox-drain.sh:245` (coverage fold, every boundary), :315 (`.forward` adoption), :344/:350 (pull-adoption M4), `scripts/handoff-fire.sh:8310` (M3 close), `bin/cc-restore-rebind:222` | re-appends each unconsumed line with a prefix `pfx="$ts [forwarded:$(printf '%s' "$old" \| cut -c1-8)] "` (lib :722-725) | `<ISO-migrate> [forwarded:<old8>] <ISO-orig> [<from>] <body>`, and chains nest | **yes, byte for byte**. Tested in a scratch dir: 2 hops A→B→C on a line containing a tab, `\n`, `\\`, `$(echo pwn)`, backticks, quotes, trailing spaces and UTF-8. After stripping the chain prefix the bytes are IDENTICAL to the source (`fwdtest.sh` plus a python `cmp`) |
| desk reroute tee (dead target) `bin/cc-notify:1514` | a COPY into the desk box | `<ISO-now> [<from>] [for:<orig-target>] <body>` | yes. `[from]` stays the first bracket and `[for:]` names the dead RECIPIENT. The timestamp is re-taken by a new `date` call (equal to the send time to within the same run) |
| `cc-mailbox-alias-gc` | deletes `.alias/<pane>` files only (`bin/cc-mailbox-alias-gc:1-35`) | n/a | moves no lines |
| limit-recover | moves no lines. The mail is pane-keyed and every account's `mailbox/` is one shared dir (`lr-handoff.sh:762-765`). Its own verdict goes out through cc-notify (`lr-handoff.sh:780-786`) | ordinary line | n/a |

Corpus figures: forwarded lines all-time number 4,964, at chain depths 1/2/3 = 4,924 / 35 / 5 (`froms.py`). Of
the lines whose OUTER stamp falls in the last 30 days, **4,965 of 7,773 (63.9%) are forwarded**. `[for:]` tees:
14.

**Important:** `[forwarded:<old8>]` names the PREVIOUS RECIPIENT's box key (8 characters of a session uuid, or
the kitty window id). It says nothing about the sender. The original sender and origin time survive only as the
inner `<ISO-orig> [<from>]`.

**Reader bugs this causes today (measured):**
- Operator digest `hooks/mailbox-drain.sh` (the `_names` sed in the systemMessage block, ~line 841):
  `sed -n 's/^[0-9TZ:+-]* \[\([^]]*\)\].*/\1/p'` takes the FIRST bracket. On a forwarded line it returns
  `forwarded:bbbbbbbb` (reproduced on the scratch box). So for about 64% of recent lines, the operator's
  "📬 peer mail ◀ N peer message(s) from …" names a recipient box instead of the sender.
- `bin/cc-mail:64` `LINE` regex: the same first-bracket capture, so `snd = forwarded:<8>` and `ts` = the
  MIGRATION time. Forwarded mail does not match `cc-mail --from <sender>`, and its time column shows the adoption
  time, not the sent time.
- Correct readers, which can serve as models: the stale-forward summariser `hooks/mailbox-drain.sh:786`
  (`^((?:\S+ \[forwarded:[^\]]*\] )+)(\S+) (\[[^\]]*\] )?(.*)$`) and the origin parser
  `_MBX_AWK_ORIGIN` / `_mbx_origin` (`hooks/lib/mailbox-pending.sh:894-915`). Both strip the chain first.

## 6. Proposal: carry pane + title in the line, inside the part forwards preserve

Migration preserves the inner `<ISO-orig> [<from>] <body>` byte for byte. So **whatever is written into the
original line at send time survives every forward for free**, and no sidecar store keyed by box or line number
does (line numbers change on migration). Concretely:

1. **Keep `[<from>]` exactly as it is.** It is the first bracket, which `cc-mail`, the digest, `cc-await-ping:1364`
   and the `.sent` reasoning all key on. Changing its contents breaks substring and equality matches.
2. **Add one metadata token directly after `[from]`**, captured at send time from the sender's own registry row
   and transcript tail. For example:
   `<ISO> [wt-cc-224434-52011-225] ⟦p=225 s=6ecdcaa0 t=/limit-recover pane recovery gap⟧ <body>`
   - `p` comes from `.paneUUID`, not from parsing `name`. `s` is the first 8 characters of `.session_id`, which
     disambiguates a reused kitty window id. `t` is the title, chosen as custom-title > agent-name > ai-title,
     with `]`, `⟧` and newlines stripped and the value capped at about 60 characters.
   - Use a delimiter that is NOT `[`…`]`. Then every first-bracket parser keeps returning the sender, and the
     drain's optional-second-bracket group (`:786`, `(\[[^\]]*\] )?`) does not swallow it as a `[for:]`-style tag.
   - Capture it EVEN WHEN `--from` is given, whenever `own_uuid` has a row. `--from` sets the voice, while
     `p`/`t` record where the mail was sent from. When there is no row, omit the token (daemon case, §4).
   - Body-prefix readers are unanchored (`grep -q 'HANDOFF-PING'` at `hooks/mailbox-drain.sh:676`,
     `handoff-selfclose-e2e.sh:190`), so an inserted token does not break them. A full census of anchored body
     readers is still owed before landing.
3. **The renderer derives everything else.** It strips the forward chain (reusing the `_mbx_origin` / `:786`
   regex), takes the inner ISO as the sent time, takes outer-ISO or now minus the inner ISO as the lag, and
   shows the outermost `[forwarded:…]` only as "↪ adopted". Result:
   `pane 225 · /limit-recover pane recovery gap · sent 14:02 (+3h late)`.
4. **Bring the sender-side resolution into line with the writer:** give `own_uuid` the `KITTY_WINDOW_ID`
   fallback from `session-register.sh:173` and `cc-wake:187`. Route the desk tee (`bin/cc-notify:1514`) and
   `cc-await-ping`'s direct writes through the same line builder, so all three writers emit one shape.
5. **Fix the two first-bracket readers** (the drain `_names` sed and `cc-mail:64`) to strip the chain. This is
   worth doing whether or not anything else lands.

Cost: about 30-130 ms per send under load ~850 (measured, `combined.sh`). That can be cut to about 10 ms by doing
the row and tail read in ONE python process instead of jq, tail, grep and sed (the in-process tail read measured
0.2-14 ms in `census.py`, which does not count interpreter start-up). Bound the whole capture, for example with a
200 ms budget. A miss or a timeout drops only the token.
