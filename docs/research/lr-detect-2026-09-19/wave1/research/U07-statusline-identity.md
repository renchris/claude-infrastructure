# U07 — statusline identity & the <2s session lookup

Measured 2026-09-19, 13:40–14:10 America/Chicago, on the live fleet (16 live sessions, kitty
socket `/tmp/kitty-73832`, Claude Code 2.1.260).

## 0. Headline

**A fresh, perfectly-read screenshot of today's statusline does not identify a session.** Panes
122 and 124 render the *byte-identical* line right now:

```
pane 122  -> (3) 40% · claude-infrastructure (b80f9408e) · high
pane 124  -> (3) 40% · claude-infrastructure (b80f9408e) · high
```
(`(cd $cwd && bash statusline.sh) < <real telemetry payload>`, rendered per pane, ANSI stripped.)

The two fields that would fix it — pane id and session id — are **already in the statusline's hands
at zero cost**: `KITTY_WINDOW_ID` is inherited env, and `session_id` is already parsed into
`PAY_SID` by the single `jq` pass at `statusline.sh:77-86`. Measured A/B of adding
`⌗112 d02d8feb`: **+1.2 ms/render (+1.3%, inside run-to-run noise) and +14 columns.**

Second headline: the shipped lookup tool, `cc-sessions`, takes **30.4–41.0 s** and prints **no
session id at all**. A registry-only join does the same job in **0.18 s**, and 0.63 s with liveness
+ topic.

---

## 1. Resolution of `~/.claude/statusline.sh` — it is NOT a symlink

The brief assumed a symlink. It is not:

```
ls -la ~/.claude/statusline.sh
=> -rwxr-xr-x@ 1 chrisren staff 29364 Sep  8 14:07 /Users/chrisren/.claude/statusline.sh
readlink -f ~/.claude/statusline.sh
=> /Users/chrisren/.claude/statusline.sh          # resolves to ITSELF
diff ~/.claude/statusline.sh /Users/chrisren/Development/claude-infrastructure/statusline.sh
=> IDENTICAL (content, 29364 B; live mtime 14:07 vs repo 14:03)
```

This is **deliberate and documented in the file itself** — `statusline.sh:119-121`:

> "this writer is a copy-deployed real file while every reader is a symlink, so a path change goes
> live on the readers first and blinds the spine in between."

**Consequence for any change here:** a landed edit to `statusline.sh` does **not** go live on the
trunk fast-forward the way a symlinked `hooks/` or `bin/` file does. It needs `install.sh` (which
`scripts/deploy-live.sh` runs). Registered at `~/.claude/settings.json:1274-1277`:

```json
"statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
```

---

## 2. What the statusline renders today — every field mapped to its source

Final emit is one line, `statusline.sh:486`:

```bash
echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"
```

Reproduced live (fixture payload, cwd = the repo):

```
(2) 52% · claude-infrastructure (b80f9408e) · xhigh
```

| rendered | var | source | file:line | forks |
|---|---|---|---|---|
| `(2) ` | `GLYPH_PREFIX` | `$CLAUDE_INSTANCE_N`, else config-dir Latin-ordinal map on `transcript_path` prefix (`.claude-next`→1, `-secondary`→2, `-tertiary`→3, `-quaternary`→4) | `:341-364`, ring at `:430` | 0 |
| `52% · ` | `PCT_SEG` | `.context_window.used_percentage` truncated at `.`; fallback = window-scaled reserved-token estimate | `:442-478`; consts `:38`, `:455` | 0 (uses `PAY_USED`) |
| `claude-infrastructure` | `DIR` | `basename "$(pwd)"` | `:254` | 1 (`basename`) |
| (implicit `*` if dirty) | `DIRTY` | `1 `/`2 `/`u ` records of `git status --porcelain=v2 --branch --no-ahead-behind --untracked-files=no` | `:259-266` | 1 (`git status`) |
| `(b80f9408e)` | `COMMIT` | `git rev-parse --short HEAD` | `:255`, `:289-291` | 1 (`git`) |
| ` · xhigh` | `EFFORT` | `.effort.level` | `:300-308` | 0 |
| *(absent here)* | `BRANCH` | `# branch.head` from the same porcelain-v2 call; **suppressed** on `main`/`master`/detached (`:272-274`) and **de-duplicated** when `basename($PWD) == "wt-$BRANCH"` or `== $BRANCH` (`:276-295`) | `:263`, `:272-295` | 0 |

So the operator's example `(4) 52% · wt-cc-095358-75429 (06ce6fee5) · xhigh` decodes as:
account `.claude-quaternary` · 52 % context used · cwd basename **which is also the branch**
(`wt-<branch>` de-dup fired) · short HEAD · effort tier.

**Zero identity fields.** No pane id, no session id, no model id, no account *name*, no title.

### 2a. Three of the five visible fields are structurally weak keys

- **`(N)` account** — 4 values across 16 sessions.
- **cwd basename** — 6 of 16 live sessions are literally `claude-infrastructure` (the shared
  checkout). Not 3, as the brief recorded from the incident; it is 6 now.
- **git sha** — all 6 of those share `b80f9408e`, because it is one checkout. Worse, it is a
  **moving** field: during this ~25-minute research window the shared checkout advanced
  `b80f9408e → 0194d9cb1`
  (`git merge-base --is-ancestor b80f9408e HEAD => yes`; `0194d9cb1 2026-09-19 13:47:29 -0500
  docs(rules): hook the cold-fire-under-load lesson`). A screenshot's sha therefore ages out of
  agreement with the live pane without the session having done anything.
- **context %** — volatile, and *still* non-unique. See §4.

### 2b. The narrow-pane amputation (unmeasured until now)

Live pane widths (`kitty @ ls`): **5 panes @ 30 cols, 4 @ 38, 6 @ 51, 1 @ 156.** The base line is
exactly 51 printable columns. Truncated:

```
w=30  (2) 52% · claude-infrastructur      <- sha and effort GONE
w=38  (2) 52% · claude-infrastructure (0194d   <- partial sha, no effort
w=51  (2) 52% · claude-infrastructure (0194d9cb1) · xhigh
```

**In 9 of 16 live panes (56%), two of the five identification fields the operator used today are
not even rendered.** Left-anchoring identity fixes this by construction:

```
w=30  (2) ⌗112 d02d8feb 52% · claude     <- pane AND sid8 both survive
```

---

## 3. Is the pane id / session id available to the statusline, and what does it cost?

### 3a. session_id — already parsed, zero marginal cost

`statusline.sh:77-86` already extracts it in the single `jq` pass:

```bash
IFS=$'\x1f' read -r PAY_SID PAY_TPATH PAY_EFFORT PAY_USED PAY_REMAINING PAY_WINDOW <<< "$(
    printf '%s' "$INPUT" | jq -r '[ (.session_id // ""), (.transcript_path // ""), ... ]'
)"
```

`${PAY_SID:0:8}` is a bash parameter expansion. **0 forks, 0 syscalls.**

### 3b. pane id — inherited env, zero marginal cost

Measured on a live claude process (pane 135, pid 89760):

```
ps eww -p 89760 | tr ' ' '\n' | grep -E '^(KITTY_WINDOW_ID|ITERM_SESSION_ID|...)='
=> CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary
=> ITERM_SESSION_ID=w0t0p0:135
=> KITTY_LISTEN_ON=unix:/tmp/kitty-73832
=> KITTY_PID=73832
=> KITTY_WINDOW_ID=135
=> TERM=xterm-kitty
```

And env **is** inherited by the claude process's child processes — verified from inside this
session's own Bash tool (pane 127): `KITTY_WINDOW_ID=127 ITERM_SESSION_ID=w0t0p0:127`. The
statusline is spawned the same way, so:

```bash
_pane="${KITTY_WINDOW_ID:-}"
[ -n "$_pane" ] || { _pane="${ITERM_SESSION_ID:-}"; _pane="${_pane##*:}"; }
```

**0 forks.** (`ITERM_SESSION_ID` is synthesised under kitty by `scripts/kitty-setup.sh:305` as
`w0t0p0:$KITTY_WINDOW_ID` — cited in `hooks/session-register.sh:116`; so the tail-strip is the same
idiom the registry already keys on, and both spellings resolve to the same integer.)

⚠️ **Do NOT reuse `ITERM_SESSION_ID` as a terminal discriminator** — `statusline.sh:412-418` records
that shipping `|| [ -n "$ITERM_SESSION_ID" ]` "put the small glyph back in kitty within minutes."
Reading it for its *value* is fine; reading it as a *terminal claim* is the banned move.

### 3c. Measured cost of rendering `⌗112 d02d8feb`

Patched copy at `scratchpad/lr/sl-id.sh` (patch = the 7 lines above plus `${ID_SEG}` in the emit).
30 renders × 3 reps per arm, same cwd, same payload, `CC_TELEMETRY_DIR` redirected to scratch:

| arm | rep1 | rep2 | rep3 | mean/render |
|---|---|---|---|---|
| base | 2.473 s | 2.678 s | 2.859 s | **89.0 ms** |
| +identity | 2.518 s | 2.683 s | 2.914 s | **90.2 ms** |

**Δ = +1.2 ms (+1.3%), inside the ±7% spread between reps of the same arm.** Column cost: base 51
printable cols → 65 (**+14**).

Where the 89 ms actually goes (20 iterations each, same shared checkout, 219 worktrees):

| component | per call |
|---|---|
| `git status --porcelain=v2 …` | 19.5 ms |
| `git rev-parse --short HEAD` | 11.7 ms |
| `jq` (×3: payload extract, telemetry emit, window write) | ~6.5 ms each ≈ 20 ms |
| `bash` process startup | 8.2 ms |
| remainder (basename, mkdir/test, ps-walk on first render) | ~30 ms |

**The identity fields are free; the git calls are 35% of the render.** `worktree.branch` is in the
payload (§3d) and would remove `git status` entirely if the dirty marker were dropped or sourced
elsewhere — out of scope for U07 but worth ~20 ms/render/pane.

### 3d. The payload carries far more than the script reads — including `rate_limits`

Extracted from the shipped binary
(`~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, v2.1.260, build
`e51f681183f733dbe9a81bf35921c786ee26dbc6`), via
`strings -n 8 … | grep -a 'exceeds_200k_tokens'`, the statusline payload builder verbatim:

```js
function RZt({session:w,permissionMode:H,exceeds200kTokens:ne,fastMode:pe,settings:fe,messages:Se,
  addedDirs:xe,mainLoopModel:Ee,gitWorktree:Oe,repo:He,prStatus:Ke,vimModeEnabled:Je,vimMode:Xe,
  cwd:it,effortValue:st,thinkingEnabled:jt}){ ... let uo=BX(w.id), go=iM(),
  _o={...go.five_hour&&{five_hour:{used_percentage:go.five_hour.utilization*100,
      resets_at:go.five_hour.resets_at}},
      ...go.seven_day&&{seven_day:{used_percentage:...,resets_at:...}},
      ...Pe()==="gateway"&&go.overage&&{spend_limit:{...}}};
  return {...fa(w,it), ...uo&&{session_name:uo},
    model:{id:wt,display_name:ti(wt)},
    workspace:{current_dir:it,project_dir:w.project.originalCwd,added_dirs:xe,
               ...Oe&&{git_worktree:Oe}, ...He&&{repo:He}},
    version:"2.1.260", output_style:{name:Yt},
    cost:{total_cost_usd,total_duration_ms,total_api_duration_ms,total_lines_added,total_lines_removed},
    context_window:xZt(ao,to), exceeds_200k_tokens:ne, ...EZt(), fast_mode:pe,
    ...eh(wt)&&{effort:{level:ET(wt,st)}}, thinking:{enabled:jt!==!1},
    ...(_o.five_hour||_o.seven_day||_o.spend_limit)&&{rate_limits:_o},
    ...Je&&{vim:{mode:Xe??"INSERT"}}, ...At&&{agent:{name:At}},
    ...jn()!==null&&{remote:{session_id:w.id}},
    ...Ke&&{pr:{number,url,review_state,kind}},
    ...io&&{worktree:{name:io.worktreeName,path:io.worktreePath,branch:io.worktreeBranch,
                      original_cwd:io.originalCwd,original_branch:io.originalBranch}}}}
```

Base fields `fa(w,it)` confirmed from the hook schema in the same binary:
`{session_id, transcript_path, cwd, prompt_id?, permission_mode?}`.

Fields the script reads today: `session_id`, `transcript_path`, `effort.level`,
`context_window.{used_percentage,remaining_percentage,context_window_size,total_input_tokens}`,
`cwd`, `model.id`, `exceeds_200k_tokens`.

**Unused and directly relevant to limit-recovery:**

| payload field | why it matters here |
|---|---|
| **`rate_limits.five_hour.{used_percentage,resets_at}`** | the pane can show its OWN 5-hour burn and reset time — a session about to hit the wall is visible *before* it halts, and `resets_at` is the number the recovery ranker needs |
| **`rate_limits.seven_day.{used_percentage,resets_at}`** | the weekly cap — today's ranker mis-selection (`next` at 98–99 % weekly) is a *visible* number on the pane that chose it |
| **`session_name`** | the human title (`BX(e)=cu(e)??h3(e)`); this is what kitty shows as the tab title — a keyword-searchable identity field |
| `worktree.branch`, `worktree.name` | branch without a `git` fork (−19.5 ms/render) |
| `model.display_name` | Fable vs Opus at a glance (matters: today's ranker was `--rank fable`) |
| `agent.name` | distinguishes a teammate pane from a lead pane |
| `cost.total_cost_usd`, `cost.total_duration_ms` | per-session spend |

Also found: `PZt=["tokenUsage","permissionMode","vimMode","mainLoopModel","fastMode","effortValue",
"thinkingEnabled","prStatus"]` — the prop list that triggers a re-render — and
`STe(w){let H=w?.refreshInterval; return H===void 0?null:Math.max(1,H)*1000}`, i.e. a
`statusLine.refreshInterval` (seconds, floor 1) is supported and is **not set** in
`~/.claude/settings.json` today. So the line renders on state change only; a stalled/limited pane
renders **zero** times, which is the same blindness `statusline.sh:94-98` already documents for
telemetry staleness.

---

## 4. Measured ambiguity of today's identification keys

Registry: `~/.claude/cc-registry/*.json`, 26 rows + 4 `.stale-*`; **16 live** by `kill -0` on
`.pid`. Live rows join to `/tmp/cc-telemetry/<sid>.json` **16/16, with `.pid` matching 16/16.**

### Registry row schema (verbatim, `~/.claude/cc-registry/112.json`)

```json
{
  "paneUUID": "112",
  "name": "wt-cc-095358-75429-112",
  "cwd": "/Users/chrisren/Development/.worktrees/wt-cc-095358-75429",
  "account": "claude-secondary",
  "pid": 52095,
  "startedAt": 1789838449000,
  "session_id": "d02d8feb-1f9d-42bb-8487-80b726c88950",
  "surface": "pane",
  "lstart": "Sat Sep 19 17:20:48 2026"
}
```

Written by `hooks/session-register.sh:282-288` (`jq -n … '{paneUUID,name,cwd,account,pid,startedAt,
session_id,surface,lstart}'`). Address resolution, `:127`:

```bash
pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
```

→ under kitty the filename **is** `KITTY_WINDOW_ID`. Verified: registry `135.json` ↔ live pid 89760
whose env holds `KITTY_WINDOW_ID=135`.
`name` = `${CC_SESSION_NAME:-$(basename "$cwd")-${pane%%-*}}` (`:180`) — so it is *cwd basename +
pane*, not a topic. `account` = `basename $CLAUDE_CONFIG_DIR` with the leading dot stripped
(`:178`). `lstart` is the pid-reuse guard, rendered `TZ=UTC LC_ALL=C` (`:278`).

Hook registration: `SessionStart` matcher `-` (all sources) — `settings.json` SessionStart list
includes `~/.claude/hooks/session-register.sh`. So the row is **rewritten on every SessionStart**
(startup, `/clear`, resume, compact) and `session_id` stays current. Tenancy gate at `:196+` stops
a nested `claude -p` squatting the row.

### Collision table — 16 live sessions

| key | sessions in a collision | largest class |
|---|---|---|
| cwd basename | **6 / 16** | 6 |
| account + cwd basename | 4 / 16 | 4 |
| account + cwd basename + sha | 4 / 16 | 4 |
| **account + cwd basename + sha + effort** (= everything stable the statusline renders) | **3 / 16** | **3** |
| sid8 | 0 / 16 | — |
| pane id | 0 / 16 | — (it is the filename) |

Full rendered lines for the 6 `claude-infrastructure` panes, produced by running the real
`statusline.sh` per pane against that pane's own live telemetry:

```
pane 111  -> (3) 65% · claude-infrastructure (b80f9408e) · high
pane 117  -> (2) 45% · claude-infrastructure (b80f9408e) · xhigh
pane 122  -> (3) 40% · claude-infrastructure (b80f9408e) · high   <-- identical
pane 124  -> (3) 40% · claude-infrastructure (b80f9408e) · high   <-- identical
pane 126  -> (1) 39% · claude-infrastructure (b80f9408e) · high
pane 127  -> (3) 41% · claude-infrastructure (b80f9408e) · xhigh
```

**2 of 16 (12.5%) are unidentifiable from a *perfectly fresh* full-line screenshot.** Adding the
context % does not save it — 122 and 124 are both at 40 % right now.

### Context % is also a decaying key

From the per-session history files `/tmp/cc-telemetry/<sid>.hist` (`ts used_pct input_tokens`,
written by `hooks/lib/context-econ.sh`):

- all consecutive pairs, normalised to points per 10 min: `n=621 med=0.0 p75=3.9 p90=13.3 max=200.0`
- pairs whose gap is in today's screenshot-queue band (30–50 min): `n=27 min=0 med=2 p90=12 max=24`
- today's live sessions, |now − 40 min ago|: `0,0,1,5,3,4,0,7`

So a screenshot delivered 40 min late (today's #4 was ~40 min behind; #5 ~52 min) carries a % that
is typically 0–7 points stale and can be 24 off. Combined with the byte-identical pair above:
**context % neither uniquely identifies nor survives the queue.**

### The `.json` telemetry row is not a liveness signal either

Live-pane telemetry age, seconds, at one instant: `3, 5, 14, 14, 92, 111, 122, 164, 372, 374, 414,
436, 581, 646, 2148, **3153**`. Pane 126 was 52.5 min stale **while alive** — exactly the failure
`statusline.sh:94-98` documents. `kill -0 registry.pid` is the liveness oracle; telemetry age is not.

---

## 5. Two surfaces I checked and would NOT put on the lookup's hot path

### `kitty @ ls` — 0.08 s typical, but it timed out at 10.06 s on 1 of 4 attempts today

```
kitty @ --to unix:/tmp/kitty-73832 ls
=> Error: read unix ->/tmp/kitty-73832: i/o timeout        (10.059 s, partial output)
   subsequent runs: 0.48 s / 0.08 s / 0.08 s, 243,771 B, jq-parses cleanly
```
The timed-out capture was **truncated mid-string** and every downstream `jq` returned
`parse error: Invalid string: control characters from U+0000 through U+001F must be escaped at line
206, column 76` — i.e. the failure mode is a *corrupt* payload, not an error code. A lookup that
must be instant and fault-visible cannot have this on its critical path.

Its useful content, when it works:
- `.id` == registry `paneUUID` — 16/16.
- `.title` — Claude Code's **live conversation title** (`✳ /limit-recover optimization and
  investigation`, `◑ W2 recovery it2-kitty composer guard and identity pin`, …). Distinctive and
  human-meaningful for all 16 panes. The leading glyph is CC's activity spinner.
- `.cwd` — **wrong as an identity key: 7 of 16 disagree with the registry** (it is the shell's cwd,
  not the claude process's). `.foreground_processes[].cwd` agrees **16/16** — use that if you must.
- `.env` — snapshot at window spawn: pane 127 carries only `KITTY_WINDOW_ID`; **no
  `CLAUDE_CONFIG_DIR`**, so kitty cannot tell you the account.
- `.user_vars` — **`{}` on all 16 windows.** An entirely unused channel; a shell/app can publish
  into it with OSC 1337 `SetUserVar`, which would make `kitty @ ls` an sid→pane index. Not needed
  given the registry is 400× faster, but it is free and it is the only surface that survives the
  registry being wrong.

### The session FTS index is a stub for LIVE sessions

`~/.claude/session-index.db` (SQLite + FTS5, 6,654 rows, newest `2026-09-19T18:39:37Z`; FTS query
0.019 s). Every live session **has** a row — 8/8 of today's checked — but:

```
sqlite3 … "SELECT source,count(*),sum(length(first_prompt)>0),sum(length(summary)>0)
           FROM sessions WHERE indexed_at>='2026-09-19' GROUP BY source;"
=> session-start|22|0|0
=> sessions-index|42|7|0
```

For sid `11569d45` (this session): `source=session-start, message_count=0, first_prompt='',
summary='', keywords='', context_text=''`. **Zero rows indexed today carry a summary.** The text is
filled by a later sweep. So the FTS index cannot keyword-identify a session that is halted *right
now* — which is the only case that matters.

---

## 6. The lookup design

### 6a. What must be true for identification to be unambiguous *by construction*

Exactly one of these must be in the screenshot: **the pane id** or **the session id**. Everything
else on the line is a property of a *group* of sessions (account, checkout, branch, sha) or of a
*moment* (context %). Recommended render, identity **left-anchored** so it survives the 30-column
panes:

```
(3) ⌗124 26cd14be 40% · claude-infrastructure (0194d9cb1) · high
 |    |     |      |            |                 |          |
 |    |     |      |            |                 |          effort .effort.level
 |    |     |      |            |                 git rev-parse --short HEAD
 |    |     |      |            basename $PWD (branch de-duped)
 |    |     |      .context_window.used_percentage
 |    |     ${PAY_SID:0:8}              <- NEW, 0 forks
 |    ${KITTY_WINDOW_ID:-${ITERM_SESSION_ID##*:}}  <- NEW, 0 forks
 config-dir ordinal
```

Cost: **+1.2 ms/render, +14 columns.** Patch is 7 lines; working copy at
`scratchpad/lr/sl-id.sh`, diff against `scratchpad/lr/sl-base.sh`.

`⌗` (U+2317) was chosen because it is not in the East-Asian-Ambiguous set that
`statusline.sh:365-397` documents kitty downsampling — but **pin the choice at the operator's eyes
in a real 30-col pane before landing**, per that same comment block's history of four reverted
glyph designs. An ASCII `#` is the zero-risk fallback and costs one column less.

Strongly recommended companion (also 0 forks — they ride the `jq` call that already runs at
`statusline.sh:149-156`): add `pane`, `session_name`, and `rate_limits` to the telemetry row. That
turns `/tmp/cc-telemetry/<sid>.json` into the live-state half of the identity join and makes the
topic keyword-searchable without opening a transcript.

### 6b. The resolver

One command, four accepted input shapes, all resolving to `(sid, pane, account, cwd, pid, alive,
topic)`. Prototypes written and timed at `scratchpad/lr/cc-find-proto.sh` and
`scratchpad/lr/cc-find-full.sh`.

| input | rule | measured |
|---|---|---|
| **pane id** (`124`) | direct file read `~/.claude/cc-registry/124.json` | **0.007 s** |
| **sid8** (`d02d8feb`) | `grep -l` across 26 registry files | **0.012 s** |
| **screenshot tuple** {acct#, cwdbase, sha, effort, pct} | single `jq -n '[inputs]'` join of registry + telemetry, rank by exact matches, **nearest** on pct (never exact — §4) | **0.177 s** |
| **keyword** | as above, plus first-user-prompt from `head -c 262144 <transcript>` | **0.406–0.627 s** |

Full listing with liveness + topic for all 16 live sessions: **0.627 s**. Against `cc-sessions`:
**30.4 s and 41.0 s on two consecutive runs**, and its output has no `session_id` column, no
context %, no effort and no topic — its table is `NAME UUID ACCOUNT AGE CWD`, where `NAME` is
`<cwdbase>-<pane>`. **A 48–65× speedup and strictly more information.**

The join, verbatim (this is the whole hot path — one `jq`, no subshell per row):

```bash
jq -n -r '[inputs] as $a
 | ($a|map(select(.paneUUID!=null))) as $r
 | ($a|map(select(.session_id!=null and .paneUUID==null))
      |map({key:.session_id,value:.})|from_entries) as $t
 | $r[] | . as $x | ($t[$x.session_id]//{}) as $y
 | [$x.paneUUID,$x.session_id,$x.account,$x.cwd,($x.pid|tostring),
    ($y.effort//"-"),($y.used_pct//"-"|tostring)] | @tsv' \
 "$HOME/.claude/cc-registry"/[0-9]*.json "${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"/*.json
```

Then `kill -0 $pid` per row for the liveness verdict (authoritative; telemetry age is not — §4).

### 6c. Ranking rule for a screenshot tuple, given §4

1. If the render carries a pane id or sid8 → exact, single hit, done. (This is why §6a matters.)
2. Else filter on `(account ordinal, cwd basename, effort)` — **never** on sha (it moves under the
   session, measured) and never *exactly* on pct.
3. Rank survivors by `|pct_screenshot − pct_live|`; if the top two are within the p90 drift for the
   screenshot's age (12 points at 40 min) **the lookup must REFUSE and print both rows with their
   pane ids and topics**, not guess. Today that refusal would fire on 122 vs 124.
4. A refusal is the fault-tolerance property the brief asks for: an ambiguous identification that
   silently picks one is exactly how a wrong pane gets recycled.

### 6d. Free hardening, in cost order

| change | cost | buys |
|---|---|---|
| `⌗<pane> <sid8>` left-anchored in the statusline | +1.2 ms, +14 cols, 7 lines | unambiguous by construction; survives 30-col truncation |
| `pane` + `session_name` into the telemetry row | 0 forks (same `jq`) | keyword lookup without touching a 60 MB transcript; a title the operator recognises |
| `rate_limits.{five_hour,seven_day}` into the telemetry row | 0 forks (same `jq`) | the ranker's inputs become per-pane facts, not a separate `claude-accounts` call; a pane's own approach to the wall becomes visible |
| replace `git status`+`rev-parse` with payload `worktree.branch` | −19.5 ms/render | 22% of render cost, fleet-wide |
| `statusLine.refreshInterval: 5` in settings | one setting | a halted pane keeps rendering, so its telemetry does not go 52 min stale while alive |
| OSC 1337 `SetUserVar` sid into kitty `user_vars` | one escape write at SessionStart | a registry-independent sid→pane index; `user_vars` is `{}` on all 16 windows today |

---

## 7. Residuals and guesses, labelled

- **GUESS (not measured):** that `session_name` is actually *present* in the live payload. The
  binary emits it conditionally (`...uo&&{session_name:uo}`, `uo=BX(w.id)`, `BX(e)=cu(e)??h3(e)`).
  All 16 kitty window titles carry a resolved conversation title, which is consistent, but I did not
  capture a live payload (that would require editing the global `statusLine` command — forbidden by
  this unit's read-only rule). **Falsify in one line before depending on it:** point
  `settings.local.json`'s statusLine at a tee for one render, or add
  `session_name: .session_name` to the existing telemetry `jq` and read the next row back.
- **Not measured:** whether `rate_limits` is populated on a Max subscription (the `spend_limit` arm
  is explicitly gateway-gated; `five_hour`/`seven_day` are gated only on `iM()` returning them).
  Same one-line falsification.
- **Not measured:** which specific 1-of-4 condition produced the `kitty @ ls` 10.06 s timeout. It
  reproduced zero times in three immediate retries, so it is intermittent, not a standing fault —
  but it is a real observed instance and it corrupted the payload rather than erroring cleanly.
- **`~/.claude/statusline.sh` is a copy, not a symlink** — any landed change needs `install.sh` /
  `scripts/deploy-live.sh`, and the repo's own `LIVE_ADDS`/parity machinery will not see the
  divergence until then.
- **Not checked:** whether `tests/statusline-identity.bats` layer 2 (the live per-field layer,
  `tests/statusline-identity.bats:53-76`) must gain an assertion for the new fields. It should — the
  file's own history records seven single-line mutants leaving the suite 10/10 green.

## 8. Artifacts

| path | what |
|---|---|
| `scratchpad/lr/sl-base.sh` | verbatim copy of the live `statusline.sh` (the A/B control arm) |
| `scratchpad/lr/sl-id.sh` | the +identity patch (treatment arm) |
| `scratchpad/lr/payload.json` | fixture payload used for the A/B |
| `scratchpad/lr/cc-find-proto.sh` | the 0.177 s registry+telemetry join |
| `scratchpad/lr/cc-find-full.sh` | the 0.627 s full resolver (liveness + topic + keyword) |
| `scratchpad/lr/keys.txt` | the 16 live sessions' identity keys (collision-table input) |
| `scratchpad/lr/kls.{1,2,3}.json` | three `kitty @ ls` captures |
| `scratchpad/lr/cli260.strings` | `strings` of the 2.1.260 binary (payload-builder source) |
