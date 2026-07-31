# Agent View coverage across a 4-account fleet — settled

**Date:** 2026-07-31 · **Subject:** `claude agents` / `claude agents --json` (FleetView) on CC **2.1.219**
**Closes:** `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md` §4 item 4 (*"Agent View coverage — scoped to
`CLAUDE_CONFIG_DIR`; it saw 3 of 25 sessions. A 4-account fleet fragments into 4 views."*)

Binary read: `~/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(Mach-O arm64, 256,908,272 B, `VERSION:"2.1.219"`, `GIT_SHA:"7006c4c3acac98e554d3997baeda6a7fa4d1ff7c"`,
`BUILD_TIME:"2026-07-24T03:24:19Z"`). Byte offsets below are into that file; extracted with a literal
`mmap.find` context dump, not a lossy `strings` pass.

---

## VERDICT

> **One view CAN aggregate the 4-account fleet for OBSERVATION, and CANNOT for DISPATCH.**
> Observation: because the only scoping input is the single path `join(CLAUDE_CONFIG_DIR, "sessions")`
> — a *directory*, with no account identity anywhere in the read path and **no auth required** — so
> pointing all four accounts at one real registry directory yields one complete view (mechanism proven
> live, and by a 12-session single-view read). Dispatch: because a session launched from the view
> inherits **the view process's own** `CLAUDE_CONFIG_DIR` (`bin @238538957`), so a unified view can
> only ever start work on one account. N views is structural for *starting* work, not for *seeing* it.

**Cheapest thing that WOULD aggregate observation — buildable by us, today, three commands:**
replace each account's `sessions/` with a symlink to one shared real directory. **This already exists
for one account** (`~/.claude-next/sessions -> ~/.claude/sessions`, mtime 2026-06-03) and is *working
in production right now* — see §5. It needs no code, no patch, no upstream change.
**Do NOT instead symlink the individual `<pid>.json` files** — that silently reads as zero (§4).

**Available with zero config change:** `for d in $DIRS; do CLAUDE_CONFIG_DIR=$d claude agents --json;
done | dedupe-by-pid` is a **complete** aggregation of the registry and costs **1.45 s** wall for all
four accounts (§3). It has no TUI equivalent — `--json` only.

---

## 1. The scoping mechanism (implementation, not inference)

`agents --json` → `agentsCommandHandler` (`$yT`, bin @246883427) → `printAgentsJson` (`LyT`,
bin @246880484). `LyT` fans out to exactly three sources:

```js
let [o,i,s] = await Promise.all([ Bze(), IV(), fXo() ]);   // bin @246880484
```

| Source | What it is | Root | Evidence |
|---|---|---|---|
| `Bze()` | live interactive + bg **sessions** | `join(fn(),"sessions")` | bin @232678529 |
| `IV()` | background **job** state dirs | `U2() = join(fn(),"jobs")` | bin @232944089 / @232935314 |
| `fXo()` | bg-daemon worker "shorts" | daemon socket, else worker map | bin @241463977 |

`Bze()` delegates the actual walk to `jAs()` — **this is the whole scoping mechanism**:

```js
async function jAs(){                                        // bin @232677061
  let e = BAs.join(fn(), "sessions"), t;
  try { t = await brn.readdir(e) } catch { return [] }        // <-- missing root ⇒ SILENT []
  return (await Promise.all(
    t.filter(n => /^\d+\.json$/.test(n))                      // one file per session, named <PID>.json
     .map(async n => { let o = parseInt(...); let s = await qI(join(e,n), 262144); ... })
  )).filter(n => n !== null)
}
```

and the writer is the mirror image (`NDc()`, the `[concurrentSessions] register` fn, bin @227948526):

```js
function $5r(){ return Kje.join(fn(),"sessions") }            // bin @227948139
async function NDc(){
  if (yB() != null || Qkt()) return !1;                       // <-- registration gate, see §6
  let n = $5r(), o = Kje.join(n, `${process.pid}.json`);
  process.on("exit", () => { try{ unlinkSync(o) }catch{} });
  await fK.mkdir(n,{recursive:!0,mode:448}); await fK.chmod(n,448);   // 0o700
  await fK.writeFile(o, Ie({ pid, sessionId, cwd, startedAt, procStart, version, kind, entrypoint, ... }))
}
```

Liveness is re-verified on every read: `kC(pid)` (process alive) **and** `gB(pid, procStart)`
(start-time match, anti-PID-reuse); rows failing `kC` are **unlinked** — so a read mutates the dir.

`fn()` is the resolved config dir. `CLAUDE_CONFIG_DIR` is read raw and unsplit —
`function Tkl(){ return process.env.CLAUDE_CONFIG_DIR }` (bin @225787498). **There is no CLI flag** for
it: `claude --help` on 2.1.219 exposes no `--config-dir`. The only agent-view settings keys are
`leftArrowOpensAgents` / `defaultToAgentsView` (bin @111000704) — both pure UX, neither a root.

The interactive TUI is scoped **identically**: `mountFleetViewWithComposerBack` (`MYS`, bin @245566988)
is seeded from the same `IV()` (bin @245566988 `hpm()`) and the same `Bze()` session registry. There is
no second, wider root anywhere in the read path; the one plausible-looking candidate, `default_home`
(bin @153203968), is an `entryChannel` **telemetry label**, not a directory.

**Contrast that proves the design is deliberate**, not an oversight: the *IDE-lockfile* discovery
function DOES walk two roots — `gco(){ let e=[join(fn(),"ide")]; if (Z.CLAUDE_CONFIG_DIR)
e.push(join(homedir(),".claude","ide")) ... }` (bin @230014180). The session registry has no such
fallback. Single-root is the shipped intent.

---

## 2. Does `CLAUDE_CONFIG_DIR` accept multiple paths? — **NO** (measured, not reasoned)

Tested all four plausible separator conventions against two real, populated config dirs
(`~/.claude-secondary` = 3 sessions, `~/.claude-tertiary` = 3 sessions; a correct merge would print 6):

| `CLAUDE_CONFIG_DIR` value | `agents --json` output |
|---|---|
| `…/.claude-secondary,…/.claude-tertiary` | `[]` |
| `…/.claude-secondary:…/.claude-tertiary` | `[]` |
| `…/.claude-secondary;…/.claude-tertiary` | `[]` |
| `…/.claude-secondary …/.claude-tertiary` (space) | `[]` |

The negative is **shown, not asserted** — the whole string is used as ONE literal path, and the proof is
the filesystem side effect: each run `mkdir -p`'d the entire literal string as a single path and wrote a
fresh bootstrap config into it:

```
~/.claude-secondary,/Users/chrisren/.claude-tertiary/.claude.json          (2 files, 14:43:20)
~/.claude-secondary:/Users/chrisren/.claude-tertiary/.claude.json          (2 files, 14:43:21)
~/.claude-secondary;/Users/chrisren/.claude-tertiary/.claude.json          (2 files, 14:43:21)
~/.claude-secondary /Users/chrisren/.claude-tertiary/.claude.json          (2 files, 14:43:21)
```

(All four removed; `$HOME` diffed byte-identical to the pre-test snapshot afterwards.)

🚨 **The failure mode is the dangerous one.** `jAs()` catches the `readdir` `ENOENT` and returns `[]`.
So a mistyped or multi-path `CLAUDE_CONFIG_DIR` renders as **"no sessions are running"** — never as an
error — while simultaneously forking a fresh empty `.claude.json` into a garbage directory tree. Any
wrapper we build must **assert the root exists** before trusting an empty result.

---

## 3. Is loop-and-merge a COMPLETE aggregation? — **YES**

```
for d in ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  CLAUDE_CONFIG_DIR=$d claude agents --json
done
⇒ views=4  rows_total=12  distinct_pids=12  duplicated_pids={}
⇒ SERIAL_LOOP_WALL_SECONDS = 1.448
```

The union equals the ground-truth registry exactly (§5). Nothing blocks it:

- **Auth:** not required. Proved by construction — a scratch `CLAUDE_CONFIG_DIR` in `/tmp` containing
  *only* a `sessions/` directory and **no `.credentials.json` at all** printed all 12 rows (§4).
- **Daemon:** `fXo()` prefers a daemon socket but falls back to a worker map; four consecutive
  invocations across four dirs succeeded, twice.
- **Lock:** the only lock in play is a per-config-dir `.claude.json.lock`; no cross-dir lock exists.
- **Ownership:** rows carry no account identity. `messagingSocketPath` is **not even populated** on
  2.1.219 (`let r; … messagingSocketPath:r` — bin @239415794), so every row's `sock` is `""`.

**Two caveats for whoever writes the wrapper:**
1. **Dedupe by `pid` is mandatory.** `~/.claude-next/sessions` is a symlink to `~/.claude/sessions`, so
   enumerating both roots yields 13 rows for 12 sessions. PIDs are unique among live processes, so
   `pid` is a sound merge key.
2. **`--all` is per-dir too.** `--all` adds *completed* background sessions from `jobs/`; measured
   `~/.claude-secondary` `json=3` vs `json --all=6`. The `jobs/` half fragments identically.

---

## 4. The trap: per-FILE symlinks read as ZERO, silently

The obvious fan-in — symlink every account's `<pid>.json` into one directory — **does not work, and
does not say so.** Measured back-to-back on the same 12 files:

| Scratch `CLAUDE_CONFIG_DIR` | `sessions/` contents | `agents --json` |
|---|---|---|
| `/tmp/ccagg-proof-39463` | 12 **symlinks** to the real registry files | **`COUNT=0`** |
| `/tmp/ccagg-copy-49211` | the same 12 files, **copied** | **`COUNT=12`** ✅ |

Cause, exactly:

```js
async function qI(e,t){                                       // bin @229016398
  try { let r = await ooo.lstat(e);                           // lstat — does NOT follow symlinks
        if (!r.isFile() || r.size > t) return null;            // a symlink ⇒ isFile()===false ⇒ null
        return await ooo.readFile(e,"utf8") } catch { return null } }
```

`readdir` lists the symlinks, `jAs()` maps each to `null`, everything is filtered out. No warning, no
telemetry, no unlink — just `[]`.

**Corollary (the useful half):** a symlinked *directory* is fine — `readdir` follows it and the entries
inside are real files. That is why `~/.claude-next` works and per-file symlinking does not, and it is
exactly why the §5 recommendation is a **dir**-level symlink.

The `COUNT=12` copy result is also the single strongest fact in this document: **one view, one root, 12
sessions belonging to four different accounts.** Nothing in the render path objected.

---

## 5. Measured coverage, with a real denominator

Ground truth established **independently of `claude agents`**, by process census matched on the command
**position** (`basename(argv[0])`), then each process's *own* `CLAUDE_CONFIG_DIR` read out of its
environment via `ps -Ewwo command=`. Two readings ~4 min apart were identical.

```
TOTAL_PROCS = 1002 / 1049      ARGV0_CLAUDEISH = 16 / 16      NAIVE_SUBSTRING_MATCH = 101 / 101
```

The naive figure is the known trap: **101 vs 16**. An audit of all 79 substring-matched-but-not-argv0
rows found **zero** genuine sessions — they are 49 `bash` (hooks, `lead-crash-watchdog.sh`,
`postland-verify.sh`), 17 `zsh`, 9 `tee`, 2 `kitty`, 1 `tail`, 1 `timeout`. No `node`/`bun` wrapper is
running the claude binary, so the argv0 filter has **no false negatives** either.

| Config dir (account) | live claude procs | registered in `sessions/` | `agents --json` |
|---|---|---|---|
| `~/.claude-next` (→ `~/.claude/sessions`) | 1 | 1 | 1 |
| `~/.claude-secondary` | 3 | 3 | 3 |
| `~/.claude-tertiary` | 4 | 3 | 3 |
| `~/.claude-quaternary` | 8 | 5 | 5 |
| **total** | **16** | **12** | **12** |

Denominators (state which one you mean — they differ):

- **D_sess = 13** — live *interactive REPL sessions*, i.e. what an operator means by "a session".
- **D_proc = 16** — every live claude-binary process (D_sess + 3 agent-team teammate processes).
- **D_naive = 101** — `pgrep -f claude`. Wrong by 6.3×. Do not use.

| View | Coverage of D_sess (13) | of D_proc (16) |
|---|---|---|
| default (`CLAUDE_CONFIG_DIR` unset → `~/.claude`) | 1/13 = **7.7 %** | 6.3 % |
| best single account (`~/.claude-quaternary`) | 5/13 = **38.5 %** | 31.3 % |
| **loop-and-merge over 4 accounts** | **12/13 = 92.3 %** | 75.0 % |
| shared-registry single view (§4 copy proof) | **12/13 = 92.3 %** | 75.0 % |

**The plan's recalled "3 of 25" is not reproducible.** No denominator on this box today is 25: the
disk-truth figures are 13 and 16, and the naive census reads 101. "25" sits between and its basis
cannot be reconstructed — treat it as retired, not as a second data point.

**The 12/13 residue is NOT an account-scoping failure** — see §6. Merging is complete *with respect to
the registry*; one live session is missing from the registry itself, in its own account's view too.

---

## 6. Second, orthogonal defect found: sessions that never register at all

`NDc()`'s first line is a gate — `if (yB() != null || Qkt()) return !1` — and it returns **before**
writing anything. Two independent suppressions:

```js
function yB(){ let e=_B(); if(e) return e.agentId; return yde?.agentId }        // bin @227945571
function Qkt(){                                                                 // bin @227945952
  if (Z.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE) return !1;                       // <-- escape hatch
  if (!(Z.CLAUDE_CODE_CHILD_SESSION && ON() && !o_())) return !1;               // ON() = isInteractive
  return !gsg() }                                                               // gsg(): tmux-only
function _sg(){ ... if (!Z.TMUX) return !1;                                     // no tmux ⇒ suppress
  e = spawnSync("tmux",["show-environment","-g","CLAUDE_CODE_CHILD_SESSION"],…); return xDc(e.stdout) }
```

And Claude Code sets that variable on **every** process it spawns:

```js
function zDt(e){ let t={ CLAUDECODE:"1", CLAUDE_CODE_SESSION_ID:e.sessionId,
                         CLAUDE_CODE_CHILD_SESSION:"1", CLAUDE_PID:String(process.pid) }; … }  // bin @229261460
```

⇒ **Any interactive `claude` REPL launched from inside another session's Bash tool, outside tmux, is
invisible to Agent View — including in its own account's view.** That is precisely this fleet's
handoff / dedicated-split-pane pattern.

**Confirmed by natural experiment, no new session started.** pid **53778**:
`CLAUDE_CONFIG_DIR=~/.claude-tertiary`, `CLAUDE_CODE_CHILD_SESSION=1`, `CLAUDE_PID=17439`,
`TERM=xterm-kitty`, **no `TMUX`**, state `Ss+` (interactive foreground), up 2 h 19 m, parent chain
`53778 → kitty(53708) → zsh(53701) → claude(17439)`. `~/.claude-tertiary/sessions/53778.json` **does not
exist**. Every branch of `Qkt()` is satisfied and the observable matches.

The other three unregistered processes (82256 `gap2-cmux`, 88072 `q3-scout`, 98782 `gap4-agentview`) are
agent-team teammates carrying `--agent-id`; they are suppressed by the `yB()` branch — **by design**,
and correctly so (they are not sessions).

**Fix, read from the implementation:** export `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` in the
handoff/split-pane launcher. ⚠️ This is read from the binary and corroborated by the 53778 observable;
it is **not** runtime-verified, because verifying it requires starting a session (out of scope under this
brief's safety ceiling). Verify before shipping. Expected effect: 12/13 → 13/13.

---

## 7. What a shared `sessions/` root costs (evidence-based, not speculation)

Recommended change is **`sessions/` only** — leave `jobs/`, credentials, settings and projects
per-account. Consequences traced in the binary:

| Effect | Impact |
|---|---|
| `U5r()` concurrent-session count goes fleet-wide (bin @227950786) | Benign — it feeds only `tengu_concurrent_sessions` telemetry and the "Running multiple Claude sessions?" nudge (bin @245696966) |
| `.fleetview-heartbeat` (`LDc`, 5 s window, bin @227948712) becomes shared | Benign, arguably correct: "a FleetView is open somewhere in the fleet" |
| Stale-row GC becomes cross-account (`Bze` + `U5r` unlink) | Cosmetic: account A's startup may log `Prior session exited uncleanly` + `tengu_unclean_exit` for account B's crashed row |
| `mkdir(…,{mode:0o700})` + `chmod(0o700)` on every registration | No-op — all four `sessions/` dirs are already `drwx------`, same uid |
| Background jobs (`jobs/`) still fragment | Accepted: bg/`--all` coverage stays per-account; use the §3 loop for that half |
| **Dispatch still binds to one account** | **Structural — not fixable this way.** See VERDICT |

The dispatch binding, verbatim, in the background-session env builder:

```js
if (process.env.CLAUDE_CONFIG_DIR) s.CLAUDE_CONFIG_DIR = process.env.CLAUDE_CONFIG_DIR;  // bin @238538957
```

A session dispatched from a unified view inherits the *view process's* account. Sharding survives
observation; it does not survive dispatch-from-the-view.

---

## 8. Provenance note + open items

- `~/.claude-next/sessions -> ~/.claude/sessions` (mtime **2026-06-03 22:26**) is **undocumented**:
  `install.sh` never mentions `sessions`, and nothing under `bin/ scripts/ hooks/` references it. Its
  origin is unknown — but it is the live proof that the mechanism works, and it should be brought under
  `install.sh` rather than left as an ad-hoc artifact.
- **Not runtime-verified:** `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` (§6) — code-read + observable only.
- **Not tested:** the interactive FleetView TUI against a shared root. Scoping is proven identical by
  source (§1), but the render/attach path was not exercised (needs a TTY; would disturb live sessions).
- **Out of scope:** remote/cloud sessions (`--remote`, `"Couldn't attach to cloud session"`,
  bin @152427821) are a separate source and are not part of this local-registry analysis.

### Method / safety

Read-only throughout. No `claude` process was killed, signalled, resumed, or sent input; no iTerm2 or
kitty window was touched; no session was created to pad the sample. Peak concurrency was one short-lived
`claude agents --json` at a time (≈0.36 s each). The only writes were to `/tmp` scratch dirs and the four
`$HOME` directories created by the §2 negative test, all removed and diff-verified.
