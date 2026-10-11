# slot-compat: which metadata encoding leaves every inbox reader working unchanged?

Worktree `peer-mail-headline` @ 110ea9a64. Read-only census. No bats suite was run: the brief forbids
running cc-notify, and the suites drive it. Every test verdict below comes from a static grep and is
labelled "static". Corpus numbers come from two read-only python3 passes over
`~/.claude/mailbox/*.md` plus `archive/*.md`, run 2026-10-10. The store is live, so a second pass
counted one more line than the first.

## 0. Answer in one paragraph

Only **D (sidecar)** is zero-touch by construction, because no current reader opens a new file. D
pays for that with a new store, a GC rule and a hashing join. It also needs forwards keyed by
**origin-line hash, never by line number or byte offset**. Line numbers move under GC, recycling and
reuse of a kitty window key (§4).

I recommend **A** for the in-line choice, with a sigil and a closed value grammar (§5). Every reader
that extracts a field keeps working unchanged: the first-bracket "from" readers, the forward-chain
strippers, the line-count cursors, the receipts and the stale-forward fold. Every existing test grep
keeps passing (static), on three writer rules:
1. meta sits right after `[from]` and before `[for:]`;
2. it is emitted only when cc-notify resolved FROM itself, with no `--from`;
3. free-text values are percent-escaped and keyword-defanged.

Without rule 3, four whole-line substring classifiers could be hijacked by a session title.

**B and E break cc-inbox-guard's deadline classifier** (the title lands in the first bracket) and two
tests. **C lets trailing meta win the custody HANDOFF-PING parse** (last occurrence wins), and every
truncating view hides it.

## 1. Facts the brief got wrong or left open (measured)

- **Receipts are keyed on the line NUMBER, not the line text.** `cc-notify --receipt <t> <N>` rejects
  any non-integer (bin/cc-notify:1058-1063). `mailbox_receipt` compares N with `.acked` and `.seen`
  (hooks/lib/mailbox-pending.sh:266-272). The N comes from `mailbox_lines` right after the append
  (bin/cc-notify:1194-1199) and is recorded in `.sent-lines/<own>` as `<ts> <box> <line> <given>`
  (:1213-1218). So any encoding that keeps one message on one physical line is receipt-safe.
- **`.seen` and `.acked` are LINE COUNTS, not byte offsets.** `mailbox_lines` is `grep -c ''`
  (mailbox-pending.sh:224-229). `mailbox_seen` and `mailbox_acked` are clamped integers read from the
  first line of `<key>.seen` / `<key>.acked` (:213, :231-246). The same counting appears in
  handoff-disposition.sh:115, cc-thread:22 and cc-blockers:1393. cc-gc.sh:211 uses `wc -l`.
  cc-notify collapses CR/LF in the body for exactly this reason (bin/cc-notify:1093-1095). Any meta
  value must be newline-free too.
- **There are five direct line writers, not one:**
  - cc-notify:1146 `"%s [%s] %s"`;
  - cc-notify:1514, the desk reroute `"%s [%s] [for:%s] %s"`, which is already an A-shaped second
    bracket;
  - mailbox_migrate:722-725, the forward prefix `"<now> [forwarded:<first 8 chars of old key>] "`
    followed by the origin line verbatim;
  - cc-await-ping:1014 and :1057, the `[cc-await-ping] WAKE-PATH-CLASS:` and `WAKE-PATH-DOWN:` lines
    appended straight to the box.

  An encoding must therefore be OPTIONAL: readers will see meta-less lines forever.
- **Forwards already keep the original sender.** The origin line is carried byte-for-byte after the
  chain. What loses it are the four **first-bracket readers**, which return `forwarded:XXXXXXXX` for a
  forwarded line: drain:853, session-continue:1470, cc-mail:64 and inbox-guard:379. Corpus: **5,053
  of 31,139 lines (16.2%) are forwarded**; depth 1: 5,012, depth 2: 35, depth ≥3: 6. This holds under
  every encoding and is a reader fix the headline work needs regardless.
- **The from field does not identify senders today.** **22,223 of 31,133 canonical origin lines
  (71.4%) carry `[claude]`**, the account fallback at cc-notify:594. Next come `cc-await-ping` (2,654)
  and `handoff-fire` (976). There are 1,149 distinct from values. 9 contain a space, 10 fall outside
  `[A-Za-z0-9._:/-]`, 0 contain `]` and 0 contain `=`.
- **A second bracket token already exists in 2,451 lines (7.9%).** The top values are `desk-sweep`
  (2,002, a body prefix from autonomy-sweep.sh:2229), `for:7` (226), `for:<id>` (123), `restore`
  (16) and `lead` (12). There are also free-form ones a sender typed: `husk-forensics, pane 72` (8),
  `from exhaustive-drive lead 643` (3). An A token therefore needs a sigil that never occurs; "the
  second bracket" alone is ambiguous. **`[@` occurs 0 times**, as do `[meta`, `⟨` and `[✉`.
- **Lines ending in `]`: 0 of 31,140** (`grep -c '\]$'` and `grep -c '\] *$'` over the same files).
  A trailing token (C) is unambiguous in the corpus. The only trailing bracket is the drain's own
  presentation-only `[stale forward: …]` (drain:801).
- Lines: p50 284 chars, p90 978, max 88,497. All 1,318 files end in a newline.
- Duplicate origin lines (for D's hash key): 30,114 distinct origin lines among 31,140, with 996
  origin keys seen more than once (1,026 extra copies). These are mostly the same message forwarded
  into another box, which is the case a hash key should treat as one message.

## 2. Reader census and behaviour under each candidate

Legend: ✅ unchanged · 🟡 works, cosmetic change only · ⚠ breaks only if a free-text value contains
a reserved word (§5 rule R4 prevents it) · ❌ breaks.
A = `[from] [@meta] body` · B = `[from · pane 225 · title]` · C = `… body [@meta]` ·
D = sidecar, line byte-identical · E = `[from pane=225 title=…]`

| # | Reader (file:line) | What it extracts | A | B | C | D | E |
|---|---|---|---|---|---|---|---|
| 1 | mailbox-drain.sh:853 operator digest `sed 's/^[0-9TZ:+-]* \[\([^]]*\)\].*/\1/p'` | first bracket = sender name (shows `forwarded:XXXX` for forwards) | ✅ | 🟡 names grow and dedupe per title, not per sender; ❌ if a title has `]` | ✅ | ✅ | same as B |
| 2 | mailbox-drain.sh:852,855 noise filter `grep 'HANDOFF-HUSK-PANE\|REAPER SURFACE\|\[desk-sweep\]'` | whole-line substring | ⚠ | ⚠ | ⚠ | ✅ | ⚠ |
| 3 | mailbox-drain.sh:676 + awk :709-733, custody discharge | `grep -q HANDOFF-PING`, then the **LAST** `HANDOFF-PING <slug>:` on the line (`index` loop :714); the status's first token is checked against the terminal words | ✅ body comes after meta, so the body's ping still wins; ⚠ only when the body has no slugged ping | ✅/⚠ (inside the from bracket, so before the body) | ❌ meta after the body becomes the LAST occurrence and hijacks the slug and status | ✅ | ✅/⚠ |
| 4 | mailbox-drain.sh:786 stale-forward fold `^((?:\S+ \[forwarded:[^\]]*\] )+)(\S+) (\[[^\]]*\] )?(.*)$` | chain, origin ts, `[from]`, msg; preview is `msg[:100]`; grep key is `ots+" "+frm`; age from ots | 🟡 meta takes the first chars of the 100-char preview | 🟡 longer sender tally; `]` in a title silently drops group 3 | 🟡 meta is never in the preview | ✅ | same as B |
| 5 | mailbox-drain.sh:602 `n=grep -c ''` | message count | ✅ | ✅ | ✅ | ✅ | ✅ |
| 6 | session-continue.sh:1470 in-loop operator line `sed 's/^[^[]*\[\([^]]*\)\].*$/\1/p'` | first bracket | ✅ | 🟡 / ❌ on `]` | ✅ | ✅ | same as B |
| 7 | bin/cc-mail:64 `LINE=^(ISO)\s+\[([^\]]*)\]\s*(.*)$`; :63/76 NOISE `k in body`; :79-80 `--from`/`--grep`; :101 `snd[:26]` | ts, sender, body | 🟡 the body preview starts with meta; ⚠ NOISE | 🟡 truncated to 26 chars, so pane and title are cut off | 🟡 meta cut off by the width truncation (:104) | ✅ | same as B |
| 8 | bin/cc-inbox-guard:378-381 awk `tag = FIRST [...]`; :382 `tag ~ /reaper\|supervisor\|desk-invariant\|deathwatch\|PAGE\|permission/` ⇒ URGENT deadline | ts and class deadline | ✅ | ❌ a title containing "permission", "reaper", "PAGE" etc. gets the urgent deadline and a false escalation | ✅ | ✅ | ❌ same |
| 9 | bin/cc-await-ping:1395-1403 `_line_class` (`*"SUPERVISOR PAGE"*`, `*"REAPER SURFACE"*`, `*"PERMISSION-PENDING"*`, `*"HANDOFF-PING"*`, `*"WAKE-PATH"*`, `*"desk-sweep"*`; first match wins) | wake class for `--only-class` / `--except-class` | ⚠ e.g. title "REAPER SURFACE fix" on a HANDOFF-PING ⇒ REAPER-SURFACE, so the desk's `--only-class HANDOFF-PING,PERMISSION-PENDING` (:34) never wakes | ⚠ | ⚠ | ✅ | ⚠ |
| 10 | bin/cc-await-ping:1361-1372 `_own_wake_down_line` glob `*"[cc-await-ping] WAKE-PATH-DOWN: the watcher armed for ["*` | adjacency of `[from]` and body | ✅ these lines come only from the direct writers :1014/:1057, which never emit meta | ✅ same | ✅ | ✅ | ✅ |
| 11 | bin/cc-await-ping:1572-1576 body print (`mailbox_peek_from` / `tail`) → hooks/mailbox-wake-arm.sh:205-214 (stderr, exit 2) | raw lines to the model; operator sees the static `rewakeSummary` (migrations/0007:159, 0012:151) | 🟡 the model sees meta for free | 🟡 | 🟡 | ✅ (no meta unless joined) | 🟡 |
| 12 | lib `_MBX_AWK_ORIGIN` / `_mbx_origin` mailbox-pending.sh:912-914 (strip `^[^ ]+ \[forwarded:[^]]*\] `, then parse the leading ISO); used by `mailbox_window_tagged` :965-971 (pre-birth tag, read by cc-await-ping :1460 and cc-wake :168) and `mailbox_seal_before` :983+ | origin timestamp | ✅ | ✅ | ✅ | ✅ | ✅ |
| 13 | lib `mailbox_migrate` :696-741 | copies the (acked, EOF] lines verbatim behind the prefix | ✅ meta survives forwards | ✅ | ✅ | ❌ a per-box sidecar does not follow unless migrate copies it, or the key is the origin-line hash in a global store | ✅ |
| 14 | cursors and receipts: `mailbox_lines/seen/acked/receipt`, cc-notify:1194 and `.sent-lines`, handoff-fire.sh:8054-8067 V1 check, handoff-disposition.sh:115, cc-blockers:1393, cc-thread:22, cc-gc.sh:211 | line counts and line numbers | ✅ (one line kept) | ✅ | ✅ | ✅ only if the key is not a line number or offset, see §4 | ✅ |
| 15 | bin/cc-thread:52-58 | raw line cut to 168 chars | 🟡 | 🟡 | 🟡 meta never shown | ✅ | 🟡 |
| 16 | bin/cc-wake:164-168 | counts `L ` lines; FROM comes from argv (:185-189) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 17 | `.sent/<own>` readers (cc-reaper; handoff-fire.sh:6955, `NF<=2`, per cc-notify:1186-1188) | separate store | ✅ | ✅ | ✅ | ✅ | ✅ |
| 18 | cc-mailbox-alias-gc, `.alias` trail (mailbox-pending.sh:856-876, 1058, 1163) | `.alias/<pane>` files, `<ts> <session>` | ✅ never reads inbox lines | ✅ | ✅ | ✅ | ✅ |
| 19 | desk `[for:uuid]` (cc-notify:1514) | no code parser of `[for:` in bin/hooks/scripts (grep found none) | ✅ if meta goes before `[for:]` | ✅ | ✅ | ✅ | ✅ |
| 20 | cc-gc.sh:195-225 archive and reap of `<key>.{md,seen,acked}`; the orphan sweep is per-extension | file triple | ✅ | ✅ | ✅ | ❌ a `<key>.meta.*` sidecar is neither archived nor reaped; a recreated box would inherit stale meta | ✅ |
| 21 | handoff-fire.sh:8327 dead-letter copy (`cat box >> dl`); scripts/handoff-selfclose-e2e.sh:190 `grep -q HANDOFF-SUCCESSION` | whole file / substring | ✅ | ✅ | ✅ | 🟡 the sidecar is not dead-lettered | ✅ |

Searched, no inbox-line parser found: `bin/cc-bus:999` (parses cc-bus's own inbox), cc-reaper,
comms-strand-report.sh, lead- and custody-deathwatch, cc-restore-rebind, operator-readout.sh,
transcript_norm.py and norm-share.py (transcript prefixes, not inbox lines), payload-lint.sh (brief
text). cc-custody (bin/cc-custody:23-29) does **not** parse mail. The drain awk in row 3 is the only
custody discharger.

## 3. Tests that pin line shape (static grep of tests/*.bats)

- Body right after a bracket, `grep -q '\] <body>'`: cc-notify.bats:134, 142, 152, 163, 282, 525,
  599, 1190, 1265; payload-lint-tool-parity.bats:71. **A ✅** (the meta token also ends in `] `).
  **B/E ✅. C ✅** (unanchored).
- `[for:X] <body>`: cc-notify.bats:425, 724, 920, 954, 981. **A ✅ only if meta goes BEFORE
  `[for:]`.** B/C/E ✅.
- `[<from>] <body>` adjacency with `--from`:
  - cc-notify.bats:232 `'\[reaper\] surface page'` (sent `--from reaper`, :230);
  - restore-note.bats:68 `' \[boot-resume\] \[restore\] Kitty was restarted…'` (sent with
    `--from boot-resume`, boot-resume.bats:1109).

  **A and B/E ❌ unless meta is skipped on `--from` sends (rule R3).** C ✅.
- Direct-writer shapes: cc-await-ping.bats:710 `^ISO \[cc-await-ping\] WAKE-PATH-DOWN`, :1753/:1756
  `^[^ ]+ \[cc-await-ping\] WAKE-PATH-CLASS:`. These writers don't go through cc-notify, so all
  candidates ✅.
- Forward prefix: mailbox-drain.bats:178-179, mailbox-forward.bats:81, mailbox-session-key.bats:444-445.
  All candidates ✅. Stale fold: mailbox-drain.bats:1085-1166 uses seeded fixture lines, all ✅.
- No test compares a whole cc-notify-written line for equality. The grep for `$(cat|tail -1|head -1 …)`
  equality found only cursor and `.forward` files.

## 4. Why not D, and how D would have to be built if chosen

D leaves every reader byte-identical, which is its whole appeal. Its costs:
- **Line-number or byte-offset keys are unsafe.** The cursor code already assumes boxes shrink or
  restart: "a cursor PAST EOF (rotate/GC/recycle) ⇒ 0" (mailbox-pending.sh:231). cc-gc deletes or
  archives only the `.md/.seen/.acked` triple (cc-gc.sh:197-199, :225). Kitty window keys are reused:
  key 236 held 7 sessions (mailbox-pending.sh:895-901). A sidecar keyed by position would attach old
  meta to a new box's lines.
- **The only stable key is a hash of the ORIGIN line**, after stripping `(\S+ \[forwarded:[^\]]*\] )+`.
  Forwards copy that line verbatim (row 13), so the hash survives any number of forwards, but only if
  the store is global (for example `mailbox/.meta/…`; the leading dot keeps it outside
  `_mbx_valid_uuid` and every `*.md` glob). A per-recipient `<uuid>.meta.jsonl` is lost on the first
  forward. The forward prefix carries only `cut -c1-8` of the old key (mailbox-pending.sh:723), so a
  UUID-keyed old box cannot be resolved back from a forwarded line.
- It needs:
  - a new writer step in cc-notify, written meta-first so a crash leaves an orphan meta row rather
    than a line without meta;
  - a hash fork per send, on a machine at load ~800;
  - a join in every headline consumer;
  - a GC rule;
  - dead-letter coverage (handoff-fire.sh:8327).
- And it is invisible to raw views: `cc-thread`, `cat`/`tail` and the model's wake body.

## 5. Recommended encoding: A, exact grammar

```
inbox-line  = stamp SP "[" from "]" SP [ meta SP ] [ "[for:" key "]" SP ] body
stamp       = YYYY-MM-DD "T" HH:MM:SS ("+"/"-") HHMM        ; unchanged, date '+%Y-%m-%dT%H:%M:%S%z'
from        = unchanged (registry .name, else account basename, or --from)
meta        = "[@" "v1" *( ";" mkey "=" mval ) "]"
mkey        = 1*( "a"-"z" / "0"-"9" / "-" )                  ; v1 keys: pane, sid, title, subj
mval        = 1*mchar                                         ; UTF-8
forwarded   = stamp SP "[forwarded:" 8char "]" SP inbox-line ; unchanged; meta rides inside, verbatim
```

Example (sent by a registered session, no `--from`):

```
2026-10-10T23:41:07+0100 [claude] [@v1;pane=225;sid=e0cc58bf;title=peer mail headline;subj=compat verdict: A] HANDOFF-PING compat: DONE — …
```

Writer rules. Only cc-notify:1146 and :1514 change, and the meta goes between `[%s] ` and the body
or `[for:%s] `:
- **R1 (placement):** meta comes immediately after `[from] ` and before `[for:…] `. This keeps all
  first-bracket readers (rows 1, 6, 7, 8), the stale-fold group 3 (row 4) and the five `[for:` tests.
- **R2 (sigil and charset):** the token opens with `[@`, which measured 0 times in 31,140 lines and
  separates it from the 2,451 existing second brackets. In `mval`, `%`, `[`, `]`, `;`, `=`, every C0
  control and DEL are written as `%XX`; CR, LF and TAB become a space first. So a value can never
  close the bracket or split the line, and cursors and receipts (row 14) stay intact. Caps: title ≤ 48
  chars, subj ≤ 80, whole token ≤ 160 bytes. That keeps the cc-mail, cc-thread and stale-fold
  previews mostly body.
- **R3 (emission):** emit meta only when cc-notify resolved FROM itself (`--from` absent) and own
  pane resolves to a registry row. That keeps cc-notify.bats:232 and restore-note.bats:68 green and
  leaves machine senders (`--from reaper|boot-resume|handoff-fire|…`) byte-identical. The direct
  writers (cc-await-ping:1014/:1057, migrate:723) never emit. HANDOFF-PING peers send with plain
  `cc-notify <originator> "HANDOFF-PING …"` (handoff-fire.sh:15564-15567), so they DO get meta.
  Extending meta to `--from` senders later costs exactly those two test edits.
- **R4 (keyword defang):** in `mval`, compared case-insensitively, the first byte of each reserved
  word is percent-encoded (for example `%48ANDOFF-PING`). Reserved words: `HANDOFF-PING`,
  `HANDOFF-HUSK-PANE`, `SUPERVISOR PAGE`, `REAPER SURFACE`, `PERMISSION-PENDING`, `WAKE-PATH`,
  `desk-sweep`. These are the literal needles of rows 2, 3, 7 (NOISE) and 9. Without R4 those four
  classifiers misfire whenever a title or subject quotes one. With R4 none can.
- No new field is needed for sent time or lag. The origin stamp already survives forwards (row 12).
  A reader computes lag as `drain-time − origin stamp`, and forward hops as the chain stamps.

Reference parse for NEW consumers (python):

```
^((?:\S+ \[forwarded:[^\]]*\] )*)(\S+) \[([^\]]*)\] (?:\[@v1((?:;[a-z0-9-]+=[^\];]*)*)\] )?(?:\[for:([^\]]*)\] )?(.*)$
```

The groups are chain, origin stamp, from, meta fields, for-key and body. Decode `%XX` after splitting
on `;` and `=`.

## 6. Readers that must change to USE the metadata (not to stay working)

These are feature work, needed under any encoding:
- mailbox-drain.sh:849-854: the operator digest. Strip the forward chain before taking the sender
  (it shows `forwarded:XXXX` for 16.2% of lines today), then render pane, title and subj.
- session-continue.sh:1470: the same in-loop line.
- bin/cc-mail:64 and :101-106: show meta in the sender column and keep it out of the body preview.
  `--from` could also match pane and title.
- cc-await-ping stdout and mailbox-wake-arm.sh:211: the model already sees the raw line. The operator
  headline is the static `rewakeSummary` (migrations/0007:159, 0012:151), which no line encoding
  reaches. That needs its own mechanism (see slot-rewake.md).
- Optional: cc-thread:52-58, and the drain stale-fold preview (:800), to skip `[@…] ` before `msg[:100]`.

## 7. Residual risks

- Under A, every truncating view (cc-thread 168, cc-mail width, stale-fold 100) loses up to 160 bytes
  of body preview to meta until the consumers in §6 are updated. This is cosmetic.
- R4's word list is a second copy of needles that live in four readers. A new class word added to
  `_line_class` without being added to R4 reopens the injection hole. Put the list in
  hooks/lib/handoff-ping-terminal.sh or a sibling lib so there is one source.
- R3 means the 3,630+ machine-sender lines (`cc-await-ping` 2,654 and `handoff-fire` 976 measured)
  carry no pane or title until the two tests are updated.
- The test verdicts are static. No bats run was possible under the brief's no-cc-notify rule.
