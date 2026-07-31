---
status: closed
created: 2026-07-31
owner: desk
closes: docs/plans/TERMINAL_AGNOSTIC_L3_L4.md §4.3
---

# The `it2` contract surface Claude Code calls — CLOSED

Closes gap §4.3 of `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md` ("the exact `it2` contract surface Claude
Code calls — reversed only partially"). Plan decision **D5** makes an `it2` facade the mechanism by
which Agent-Team panes work on any terminal, because Claude Code shells out to an *external* `it2`
CLI and ships 0 KittyBackend / 0 GhosttyBackend. This document is the contract that facade must
satisfy.

**Method.** The whole ITermBackend class was recovered as **readable JavaScript** from
`~/.claude-219/…/bin/claude.exe` (2.1.219). The Bun bundle stores its JS as plain text at ≈229–233 MB
into the image, so this is the actual implementation, not an inference from `strings`. `strings`
alone is insufficient and misleading here: its default 4-char minimum **silently drops every 2-char
flag** (`-v`, `-s`, `-f`), so an argv reconstructed from it would have been missing exactly the
arguments that matter. Behavioural claims below were then confirmed against the real
`it2` 0.2.3 CLI and its Python source at
`~/Library/Python/3.11/lib/python/site-packages/it2/commands/session.py`.

---

## 1. The headline: **Claude Code does not call the fleet wrapper** (live defect)

`bin/it2-wrapper`'s own header states its interceptions fix *"Claude Code's native ITermBackend
killPane — both spawn PATH-resolved `it2`"*. **That premise is false on this box.** Claude Code
resolves `it2` ONCE through a **login shell**, caches the resulting **absolute path**, and execs that
path for every subsequent call:

```js
async function Uor(){                                   // isIt2CliAvailable
  let e = Z.SHELL || "/bin/zsh";
  let t = await nn(e, ["-lc", `command -v it2`], {useCwd:!1, timeout:2000});
  let r = t.code===0 ? t.stdout.split("\n").map(s=>s.trim()).filter(Boolean).at(-1) ?? "" : "";
  let n = async(s)=>nn(s,["session","list"]);
  let o = r || "it2";                                   // fallback: bare name, PATH-resolved by exec
  let i = await n(o);
  if (r && i.code!==0 && (i.code===127 || /ENOENT/i.test(i.error??""))) o="it2", i=await n(o);
  if (i.code!==0) return false;
  ncs = o;                                              // ← cached absolute path
  return true;
}
function ocs(){ return ncs }                            // getIt2Command
function Drn(e){ return nn(ocs(), e) }                  // every it2 call goes through here
```

Measured on this box, 2026-07-31:

| Fact | Value |
|---|---|
| `$SHELL` | `/bin/zsh` |
| `/bin/zsh -lc "command -v it2"` | **`/Users/chrisren/.local/bin/it2`** → `~/.local/share/uv/tools/it2/bin/it2` (the **raw** uv-installed CLI) |
| `~/.local/bin` in login PATH | position **1** |
| `~/.claude/bin` (the wrapper) in login PATH | position **15** |
| login-shell lookup latency | **0.02–0.03 s** vs CC's 2000 ms bound |

The lookup is fast and deterministic, so the fallback to the bare name — the ONLY branch that would
reach the wrapper via `exec`'s PATH search — is never taken. **All three wrapper interceptions are
therefore bypassed for Claude Code's own teammate panes**: the `-p Claude-Teammate` never-prompt
profile injection (so CC's teammate panes do NOT close cleanly from ⌘W), the `force=True` close that
suppresses iTerm2's running-job modal (so CC's `killPane` DOES pop the modal), and the 30 s bound
that exists because `session list` is the fleet's hot liveness probe.

This is not a facade problem to solve later — it decides *where the facade must live*. A facade is
only reachable if it **wins `$SHELL -lc "command -v it2"`**, i.e. it must sit earlier on the **login**
PATH than `~/.local/bin`. Placing it on the interactive PATH (or exporting PATH in the calling
process) accomplishes nothing, because CC never does a PATH search for the real calls.

> Corollary worth stating plainly: a shim placed on the *current process* PATH cannot instrument
> Claude Code's it2 traffic at all. That was verified the expensive way here — an instrumented shim
> plus a real teammate spawn recorded **zero** invocations.

---

## 2. Backend selection — and why a headless probe records nothing

```js
function Hrn(e){                                        // isInProcessEnabled
  if(_n()) return w("[BackendRegistry] isInProcessEnabled: true (non-interactive session)"), !0;
  let t=uP_(); if(t==="in-process") r=!0; else if(t==="tmux"||t==="iterm2") r=!1; else …
}
```

**A non-interactive session (`claude -p`) is unconditionally in-process — no pane, no backend, no
`it2` call whatsoever.** This was confirmed live: a `-p` run that successfully spawned a teammate
produced an empty probe log.

That is not merely a measurement caveat, it is **direct support for plan decisions D3/P2**: the
headless driver the plan wants to build is *already how Claude Code behaves when not interactive*.
The pane path is the exception, exactly as P2 asserts it should be.

Interactive selection order (`Orn`): explicit `teammateMode:"iterm2"` (throws if not in iTerm2 or no
it2) → inside tmux ⇒ TmuxBackend → in iTerm2 and not `preferTmuxOverIterm2` and it2 available ⇒
ITermBackend → tmux available ⇒ TmuxBackend (`needsIt2Setup`) → else throw. `wpe()` (isInITerm2) is
true if `TERM_PROGRAM==="iTerm.app"` **or** `ITERM_SESSION_ID` is set **or** `terminal==="iTerm.app"` —
note the middle disjunct means an inherited env var alone is enough.

---

## 3. The contract — every `it2` invocation Claude Code makes

Four verbs, five argv shapes. This is the complete surface; there are no others in the class.

### 3.1 `createTeammatePaneInSwarmView(name, color)`

| # | Condition | **exact argv** |
|---|---|---|
| 1 | first teammate, leader id resolvable | `session split -v -s <leaderId>` |
| 2 | first teammate, no leader id | `session split -v` |
| 3 | subsequent, last teammate id known | `session split -s <lastTeammateId>` |
| 4 | subsequent, no teammate id | `session split` |

`-v` is `--vertical`, **not** verbose — and it appears **only on the first split**. Subsequent splits
are horizontal. A facade that treats `-v` as a verbosity flag produces the wrong geometry on every
pane after the first.

**Leader id derivation** — note it is *not* the raw env var:

```js
function lP_(){ let e=Z.ITERM_SESSION_ID; if(!e) return null;
                let t=e.indexOf(":"); if(t===-1) return null; return e.slice(t+1) }
```

`ITERM_SESSION_ID` is `w3t0p6:93DFB2D7-…`; everything up to and **including the first colon** is
stripped. **No colon ⇒ null**, which silently downgrades shape 1 → shape 2. A facade minting ids for
another terminal must therefore emit `<something>:<id>`, or the leader is never targeted and the
first split lands on whatever pane happens to be active.

### 3.2 `sendCommandToPane(paneId, command)` — **two calls, both verbs**

```js
let n = e ? ["-s", e] : [];
await Drn(["session","send",...n,"\x15"]);   // Ctrl-U — clear whatever is on the input line
let o = await Drn(["session","run",...n,t]); // the command, with a trailing \r
if(o.code!==0) throw new Sj(`Failed to send command to iTerm2 pane ${e}: ${o.stderr}`);
```

The `send`-vs-`run` question is settled: **both**, always in that order. `it2 session send` writes
text with *no* newline (`async_send_text(text)`), `it2 session run` appends `\r`
(`async_send_text(command + "\r")`). Only the second call's exit code is checked. A facade
implementing just one of them either leaves stale input on the line or never submits the command.

Claude Code refuses control characters in `command` *before* sending (`qur(t)` →
`swarm_pane_command_control_chars`, "Refusing to send command containing control character U+… to
terminal pane") — while itself sending `\x15`. A facade must accept `\x15` on `send`.

### 3.3 `killPane(paneId)`

`session close -f -s <paneId>` — returns `code===0` as a boolean. The pane id is removed from the
internal list regardless of the result, and when the list empties the "first teammate" flag resets.

### 3.4 `session list` — liveness, and **it is structurally broken**

Used only on the split-failure recovery path:

```js
if(s.code!==0){
  if(i){ let l=await Drn(["session","list"]);
         if(l.code===0 && !l.stdout.includes(i)){ /* prune i, retry */ } }
  throw new Sj(`Failed to create iTerm2 split pane: ${s.stderr}`) }
```

**No `--json`** (verified absent from the entire ITermBackend segment). So CC parses the human
`rich` table — and that table **truncates the Session ID column**. Measured:

```
full id from --json : A5B61882-E2AD-438D-8432-3BC7B7F431F6
in the plain table  : │ A5B61882-E2AD-438D-… │        ← ellipsis at 80 cols
```

- `stdout.includes(fullId)` → **NO** (positive control: the 18-char prefix IS present, so the table
  really is rendering that session — the check is failing on truncation, not on absence).
- `COLUMNS=250` → full id present. So the truncation is **width-dependent**, and `rich` defaults to
  80 columns whenever stdout is a pipe — which is exactly how Claude Code captures it.

**Consequence:** `!l.stdout.includes(i)` is always true, so whenever a split fails while targeting a
teammate, CC concludes that teammate is dead and prunes it — unconditionally, without evidence. The
liveness check carries zero bits.

**Facade requirement:** emit **full, untruncated session IDs** on `session list`. A facade that does
so makes Claude Code's pruning *work*, i.e. strictly better than it behaves on real iTerm2 today.

### 3.5 `isAvailable()` probe

`<resolved-it2> session list` is run once at detection purely for its **exit code**; a non-zero code
is reported as "Python API not enabled". A facade must exit 0 here or it is never selected.

---

## 4. Minimum viable facade

Nine behaviours, all above. Ordered by what breaks first if omitted:

1. Be the winner of `$SHELL -lc "command -v it2"` — earlier on the **login** PATH than `~/.local/bin`.
2. `session list` → exit 0, and print **full** session IDs.
3. `session split [-v] [-s ID]` → print `Created new pane: <id>`; `-v` = vertical, first split only.
4. Mint ids containing a colon if the leader is to be addressable via `ITERM_SESSION_ID`.
5. `session send -s ID <text>` → write text, no newline; must tolerate `\x15`.
6. `session run -s ID <cmd>` → write cmd + `\r`; its exit code is the one that is checked.
7. `session close -f -s ID` → exit 0 on success.
8. Non-zero exit + stderr on genuine failure (CC surfaces `stderr` in its thrown errors).
9. Nothing else — `capture`, `focus`, `set-var`, `restart`, `monitor` etc. are never called by
   ITermBackend.

**Parser exactness.** Split output is matched with `/Created new pane:\s*(.+)/` and `.trim()`ed; an
empty group throws `Failed to parse session ID from split output`. `(.+)` is greedy to end-of-line,
so **any trailing text on that line becomes part of the id**. The facade must print that line and
nothing else on it.

---

## 5. Falsifiable claims made here

| Claim | How it was established | How to refute it |
|---|---|---|
| CC execs an absolute it2 path, not the wrapper | JS source of `Uor`/`ocs`/`Drn` + measured login-PATH order | show `~/.claude/bin` winning `zsh -lc 'command -v it2'` |
| `-v` is vertical and first-split-only | JS argv arrays + `it2 session split --help` | — |
| both `send` and `run` are used | JS `sendCommandToPane` body | — |
| `session list` ids are truncated | measured, with a prefix positive control | run it where stdout is a tty ≥ ~110 cols |
| `-p` never calls it2 | JS `isInProcessEnabled` + a live teammate spawn logging zero calls | — |

The instrument used for the live check is committed at `tools/it2-probe/it2-logging-shim.sh`. Its
transparency was positive-controlled: byte-identical passthrough on a *deterministic* subject
(`--help`), after an initial control wrongly read FAIL because `session list` renders an **animating
braille spinner** and live session names — i.e. the subject was volatile, not the shim. A negative
control confirmed the check could still detect a real difference.
