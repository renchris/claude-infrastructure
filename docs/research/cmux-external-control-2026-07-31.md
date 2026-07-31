# cmux external socket control — GAP 2 closed (2026-07-31)

Closes GAP 2 of `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md` §4:
> "cmux socket auth from outside — `socketControlMode: "passwordOrCmux"` is NOT a valid enum;
> the correct value is unknown, and without it external automation cannot drive cmux."

Subject: cmux **0.64.20 (build 100)** `[14e3400b9]`, `/Applications/cmux.app`, bundle
`com.cmuxterm.app`. CLI entrypoint: `/opt/homebrew/bin/cmux` → symlink →
`/Applications/cmux.app/Contents/Resources/bin/cmux` (a separate 39 MB Mach-O, not the app binary).

---

## VERDICT

**External automation CAN drive cmux, because `automation.socketControlMode` accepts
`"automation"` (or `"password"`), either of which replaces the default process-ancestry check —
proven end-to-end from an iTerm2-parented shell: `new-split` created a pane and `send` executed a
command that wrote a file on disk.**

Caveat, separately verified and NOT an auth problem: cmux 0.64.20 **deterministically wedges at
100% CPU with unbounded RSS growth when launched with no workspace to open** (6/6 launches, in
every socket mode incl. the untouched default). Launch via `cmux <path>` instead — that path is
healthy (1/1). Details in [§6](#6-blocker-the-launch-wedge-not-an-auth-problem).

---

## 1. The enum answer

The field is spelled correctly in the plan — `automation.socketControlMode` — but the **value** was
invented. Published schema
(`https://raw.githubusercontent.com/manaflow-ai/cmux/main/web/data/cmux.schema.json`,
HTTP 200, 85 840 bytes, fetched 2026-07-31), at `/properties/automation/properties/socketControlMode`:

```json
{
  "type": "string",
  "enum": ["off","cmuxOnly","automation","password","allowAll",
           "openAccess","fullOpenAccess","notifications","full"],
  "default": "cmuxOnly",
  "description": "Socket control mode. Legacy aliases are accepted and normalized."
}
```

Nine values, but only **five are canonical**. The app binary's Swift `RawValue`/`AllCases` table
(`strings /Applications/cmux.app/Contents/MacOS/cmux`, offsets 100597-100600, 111860-111863)
contains exactly `cmuxOnly, automation, password, allowAll`; `off` is handled separately. The
remaining four schema values are the legacy-alias normalization table, stored **lowercased** at
offsets 760731-760738: `cmuxonly, automation, password, allowall, openaccess, fullopenaccess,
notifications, full`.

Semantics, verbatim from the shipped UI strings
(`/Applications/cmux.app/Contents/Resources/en.lproj/Localizable.strings`, `plutil -convert json`):

| Value | UI name | Description (verbatim) | External automation? |
|---|---|---|---|
| `off` | Off | "Disable the local control socket." | No socket at all |
| `cmuxOnly` **(default)** | cmux processes only | "Only processes started inside cmux terminals can send commands." | **BLOCKED** |
| `automation` | Automation mode | "Allow external local automation clients from this macOS user (no ancestry check)." | **YES — no secret** |
| `password` | Password mode | "Require socket authentication with a password stored in a local file." | **YES — shared secret** |
| `allowAll` | Full open access | "Allow any local process and user to connect with no auth. Unsafe." | Yes — **do not use** |

`allowAll` is gated behind a confirmation dialog whose message reads: *"This disables ancestry and
password checks and opens the socket to all local users. Only enable when you understand the risk."*
and a settings warning: *"Full open access makes the control socket world-readable/writable on this
Mac and disables auth checks. Use only for local debugging."*

**`"passwordOrCmux"` does not exist.** `grep -a -c -o passwordOrCmux` against the 208 MB app binary
returns **0**. (For calibration, the same grep returns 24 for `socketControlMode` and 10 for
`openAccess`.) It is not a legacy alias, not a normalized form, not a rejected-but-known value.

### 1a. Where the plan's bogus value came from

Not a hallucination in the plan — a real prior experiment. `~/.config/cmux/cmux.20260731T204525.bak`
(13 554 bytes, mtime 13:45 today) differs from the live config by exactly:

```diff
3a4,7
>   "automation": {
>     "socketControlMode": "passwordOrCmux",
>     "socketPassword": "bakeoff-temp-2026073113"
>   },
```

A sibling session at 13:45 guessed `passwordOrCmux`, it did not work, and the plan recorded the
failure as "the correct value is unknown". That backup is pre-existing operator state and was left
in place. (It still contains the stale string `bakeoff-temp-2026073113` — harmless, since no cmux
build ever accepted that mode, but worth deleting for hygiene.)

### 1b. Env-var override (works, and needs no config edit)

Shipped settings note, verbatim: *"Overrides: `CMUX_SOCKET_ENABLE`, `CMUX_SOCKET_MODE`, and
`CMUX_SOCKET_PATH` (set `CMUX_ALLOW_SOCKET_OVERRIDE=1` for stable/nightly builds)."*

Verified working — the app process carried both vars and `capabilities` reported the overridden mode:

```
$ open -g -a /Applications/cmux.app --env CMUX_ALLOW_SOCKET_OVERRIDE=1 --env CMUX_SOCKET_MODE=automation
$ ps eww -p <pid> -o command= | tr ' ' '\n' | grep '^CMUX_'
CMUX_ALLOW_SOCKET_OVERRIDE=1
CMUX_SOCKET_MODE=automation
$ cmux capabilities
{ "access_mode" : "automation", ... }
```

macOS `open(1)` supports `--env` on this box, so this is a viable per-launch alternative to editing
`cmux.json`. Note it requires relaunching the app, which the config-file route does not
(`cmux reload-config` applies a mode change in place — see §5).

---

## 2. Caller externality (what "external" means here)

Every command below was run from the Claude Code Bash tool, whose ancestry is iTerm2 — **not** a
cmux child, with zero inherited cmux env:

```
--- CMUX_* env vars visible to this shell ---
0
--- TERM_PROGRAM ---
TERM_PROGRAM=iTerm.app  TERM=xterm-256color
--- process ancestry ---
  depth1 pid=16609 comm=/bin/zsh
  depth2 pid=82256 comm=.../@anthropic-ai/claude-code/bin/claude.exe
  depth3 pid=81368 comm=-zsh
  depth4 pid=81364 comm=login
  depth5 pid=1067  comm=.../iTerm2/iTermServer-3.6.11
  depth6 pid=591   comm=/Applications/iTerm.app/Contents/MacOS/iTerm2
  depth7 pid=1     (launchd/root)
--- any cmux ancestor? ---
cmux_ancestor=no
```

Commands were additionally run under `env -u CMUX_WORKSPACE_ID -u CMUX_SURFACE_ID -u CMUX_TAB_ID
-u CMUX_SOCKET_PASSWORD -u CMUX_SOCKET_PATH`.

---

## 3. Negative control — default `cmuxOnly` (config untouched)

cmux was **not running** at session start (`pgrep -x cmux` → rc=1; no socket). Launched with the
operator's pristine config, sha256 `b39651a4…f7c2`:

```
$ cmux ping
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
$ cmux list-panes
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
$ cmux list-windows
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
$ cmux identify --json
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
$ cmux capabilities
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
```

The gap is real, and the refusal is total — even `ping` and `capabilities` are gated. The string is
localization key `socket.client.accessDenied`.

Socket is `srw-------` (0600), owner `chrisren`, at `~/.local/state/cmux/cmux-501.sock` (uid-suffixed;
`~/.local/state/cmux/cmux.sock` is a legacy/stale path — the live path is reported by
`cmux capabilities` as `socket_path`).

---

## 4. THE PROOF — external drive under `socketControlMode: "automation"`

`~/.config/cmux/cmux.json` set to (file-managed, no env override in play):

```json
"automation": {
  "socketControlMode": "automation"
},
```

`cmux config validate` → `OK primary: ~/.config/cmux/cmux.json … keys: $schema, automation,
schemaVersion … JSONC syntax is valid`. App launched via `cmux /tmp` (see §6 for why not `open -a`).

**Read commands:**

```
$ cmux ping
PONG
[exit=0]

$ cmux capabilities --json
{
  "access_mode" : "automation",
  "methods" : [ … 240 methods … ],
  "protocol" : "cmux-socket",
  "socket_path" : "/Users/chrisren/.local/state/cmux/cmux-501.sock",
  "version" : 2
}
[exit=0]

$ cmux list-windows
  0: 82880518-DB7D-4A82-AE3C-69B4E34B541B selected_workspace=CE6C6758-9F7A-4ABA-8D32-C4AC307EA69B workspaces=1
[exit=0]

$ cmux list-workspaces
* workspace:1  chrisren@Chriss-MacBook-Pro-3:/tmp  [selected]
[exit=0]

$ cmux list-panes
* pane:1  [1 surface]  [focused]
[exit=0]
```

**Mutating commands:**

```
$ cmux new-split right --workspace workspace:1
OK surface:2 workspace:1
[exit=0]

$ cmux list-panes --workspace workspace:1
* pane:1  [1 surface]  [focused]
  pane:2  [1 surface]
[exit=0]

$ cmux send --workspace workspace:1 --surface surface:2 "echo EXTERNAL_DRIVE_PROOF_$(date +%H%M%S) > /tmp/cmux-proof.txt"
OK surface:2 workspace:1
[exit=0]

$ cmux send-key --workspace workspace:1 --surface surface:2 Enter
OK surface:2 workspace:1
[exit=0]
```

**The send did not merely arrive — it executed.** Independent on-disk oracle plus the pane's own
screen:

```
$ cat /tmp/cmux-proof.txt
EXTERNAL_DRIVE_PROOF_150927
[exit=0]

$ cmux read-screen --workspace workspace:1 --surface surface:2 --lines 6
Last login: Fri Jul 31 15:08:18 on ttys051
➜ /tmp echo EXTERNAL_DRIVE_PROOF_$(date +%H%M%S) > /tmp/cmux-proof.txt
➜ /tmp
[exit=0]
```

(`$(date +%H%M%S)` was expanded by the *calling* shell to `150927` before transmission; the file
containing that literal is therefore proof the text crossed the socket and reached a live shell.)

The full 240-method RPC surface is reachable externally, including `terminal.create`,
`terminal.input`, `surface.send_text`, `surface.read_text`, `pane.create`, `window.create`,
`workspace.create` and the whole `browser.*` namespace — i.e. everything an L3/L4 terminal driver
needs.

**Positive control that the mode change was load-bearing** — after restoring the config and
`cmux reload-config`, the *same running app* refused the *same caller* again:

```
$ cmux ping
Error: ERROR: Access denied - only processes started inside cmux can connect
[exit=1]
```

---

## 5. Auth mechanism and where the secret lives

- **`automation` mode requires no secret at all.** The only gate is "same macOS user", enforced by
  the socket's 0600 permission and owner. Nothing to store, rotate, or hand to a caller.
- **`password` mode uses a plaintext file**: `~/.local/state/cmux/socket-control-password`,
  mode `0600`, owner `chrisren`, content = the password with no trailing newline (29 bytes for a
  29-char password). Setting `automation.socketPassword` in `cmux.json` materialises this file.
  Note this contradicts the current web docs, which say
  `~/Library/Application Support/cmux/socket-control-password` — on 0.64.20 the file is written to
  `~/.local/state/cmux/`. Keychain service `com.cmuxterm.app.socket-control` and UserDefaults key
  `socket-control-password` exist in the binary as a legacy/fallback path
  (`SocketControlPasswordStore`, `socketControlPasswordMigrationVersion = 1`); the live store on
  this build is the file.
- **CLI precedence**, verbatim from `cmux --help`: *"`--password` takes precedence, then
  `CMUX_SOCKET_PASSWORD`, then the password saved in Settings."*
- **cmux-spawned terminals get the secret injected for free.** Per the CLI contract, `CMUX_SOCKET_PATH`
  and `CMUX_SOCKET_PASSWORD` are protected managed variables cmux injects at spawn time. This is
  exactly why a cmux child "just works" and an external caller does not.

Measured password-mode matrix (mode set via `cmux.json`, caller external):

| # | Invocation | Result |
|---|---|---|
| 1 | `cmux ping` (no password given) | `PONG` exit 0 |
| 2 | `cmux --password <correct> ping` | `PONG` exit 0 |
| 3 | `cmux --password wrong-pw ping` | `Error: ERROR: Invalid password` exit 1 |
| 4 | `CMUX_SOCKET_PASSWORD=<correct> cmux ping` | `PONG` exit 0 |
| 5 | `cmux --password <correct> capabilities` | `"access_mode" : "password"` |

Row 1 looks like a fail-open. **It is not** — and the distinction matters, so it was tested rather
than assumed. Making the password file unreadable (`chmod 000`, my own probe artifact) flipped row 1:

```
-- no --password, password file UNREADABLE --
Error: ERROR: Authentication required — send auth <password> first
[exit=1]
-- correct --password supplied explicitly, file still unreadable --
Error: ERROR: Password mode is enabled but no socket password is configured in Settings.
[exit=1]
```

So the server genuinely demands `auth <password>` first; row 1 succeeded because **the CLI silently
read the saved password file and sent it on the caller's behalf**. The second line also shows the
*server* re-reads that same file per attempt rather than caching it in memory — when it cannot read
it, it degrades to "no password configured" and (observed subsequently) falls back to refusing
external callers with the `cmuxOnly` message. Fail-closed, which is the right direction.

**Security consequence for the plan:** because the secret is a 0600 file readable by the same user,
`password` mode buys *nothing* over `automation` mode against a same-user process — any process
running as `chrisren` can read it. Its real value is scoping access across *different* macOS users
or handing a credential to a remote/foreign caller. For our automation (same user, same box),
`automation` is the honest choice: same effective trust boundary, no secret to manage, no plaintext
credential on disk.

---

## 6. BLOCKER: the launch wedge (not an auth problem)

cmux 0.64.20 wedges on this machine when launched **without a workspace to open**:

| # | Launch | Socket mode | Result |
|---|---|---|---|
| 1 | `open -g -a cmux` | default `cmuxOnly` (config untouched) | 100% CPU, RSS 1.27→2.02 GB, 0 windows |
| 2 | `nohup .../MacOS/cmux &` | `automation` via env | 98.7% CPU, RSS →10 GB |
| 3 | `open -g -a cmux --env …` | `automation` via env | 99% CPU, RSS →16 GB |
| 4 | `open -a cmux --env …` (foreground) | `automation` via env | 99.4% CPU, wedged |
| 5 | `open -g -a cmux --env HOME=<scratch> …` | `automation` via env | 100% CPU, wedged |
| 6 | `open -g -a cmux` | `password` via cmux.json | 99.8% CPU, RSS →16.7 GB |
| **7** | **`cmux /tmp`** | any | **1.0% CPU, 252 MB, 1 window — HEALTHY** |

Row 1 is the decisive control: **the wedge reproduces with the operator's config completely
untouched and the socket in its default mode**, so it is unrelated to socket auth. Rows 1 and 7
differ only in launch path.

Root cause, from `sample(1)` (2 407/2 407 samples on the main thread, identical stack):

```
-[NSWindow makeKeyAndOrderFront:]
 -[NSWindow _reallyDoOrderWindowAboveOrBelow:]
  -[NSWindow _doWindowWillBeVisibleAsSheet:]
   -[NSWindow _setUpFirstResponder] → recalculateKeyViewLoop
    -[NSView _setDefaultKeyViewLoop]
     NSHostingView._recursiveSetDefaultKeyViewLoop()      ⟵ unbounded mutual recursion
      FocusBridge.updateDefaultKeyViewLoop()              ⟵ (SwiftUI)
       -[NSView _recursiveSetDefaultKeyViewLoop] … ad infinitum
```

An unbounded SwiftUI key-view-loop recursion while ordering the restored **empty** window front.
The saved session (`~/Library/Application Support/cmux/session-com.cmuxterm.app.json`) holds one
window whose workspace entry is `{}` — nothing focusable — which is consistent with the recursion
never terminating. `cmux <path>` creates a real workspace and the same window orders front fine.

Ruled out as causes, each by direct check rather than assumption:

- **Not the socket mode** — row 1 above.
- **Not the onboarding sheet** — `cmuxWelcomeShown = 1`.
- **Not a Sparkle "update available" sheet** — the appcast
  (`.../releases/latest/download/appcast.xml`, HTTP 200) advertises `0.64.20`, identical to the
  installed build, so no update sheet can be presented. (`SULastCheckTime = 2026-07-31 20:45:27Z`
  coincided suspiciously with the onset, which is what made this worth checking.)
- **Not a crash** — no entries for cmux in `~/Library/Logs/DiagnosticReports`.
- **Not permanent** — `ghosttyCrashBreadcrumb.lastCleanExitAt = 2026-07-31 21:02:58Z` (14:02 local)
  shows cmux ran and exited cleanly earlier today.

Unresolved: what changed between 14:02 (clean) and 14:41 (first wedge). The saved window geometry
targets `displayID 1` / `stableID uuid:37D8832A-…` at 1728×1117 pt (the built-in Retina XDR), while
the box currently drives that plus two DELL S2725QC 5K panels — a display-set change is the leading
unverified hypothesis and is *not* claimed as the cause here.

**Operational impact:** low, and fully worked around. Launch cmux with a path
(`cmux ~/Development/foo`) rather than bare `open -a cmux`. Any L3/L4 driver should do this anyway,
since it wants a workspace. Worth filing upstream regardless — a 16 GB runaway on a bare app launch
is a real defect.

---

## 7. What did NOT work (negative results — load-bearing)

- **`socketControlMode: "passwordOrCmux"`** — not a value. Zero occurrences in the 208 MB app binary.
- **`osascript -e 'quit app "cmux"'`** — never returns; hung until killed at the 2 min tool timeout,
  twice. No modal dialog was on screen (frontmost app was unaffected). `kill -TERM <pid>` terminates
  cmux cleanly and instantly and is what every teardown here used.
- **Direct exec of the app binary** (`nohup /Applications/cmux.app/Contents/MacOS/cmux &`) — launches
  and serves the socket, but reached ~10 GB RSS. Prefer `open`/LaunchServices.
- **`HOME=<scratch>` isolation** — the env var reaches the app process (verified via `ps eww`) but the
  app wrote nothing into the scratch home, i.e. it resolves its state paths independently of `$HOME`.
  This means the "fresh session" hypothesis was *not* actually tested by that run, and I did not
  claim it was.
- **UI/topology RPCs while wedged** — `window.list`, `workspace.list`, `pane.list`, `surface.list`,
  `system.identify`, `system.tree`, `system.top`, `auth.status` all hang; only `system.ping` and
  `system.capabilities` answer (they are served off the wedged main thread). Useful diagnostic:
  **`ping` succeeding while `list-panes` hangs means the app is wedged, not that auth failed.**
- **Reading the operator's existing keychain** — deliberately not done. `security dump-keychain` was
  blocked by the safety classifier and I did not work around it; the secret's location was
  established from binary strings and from a password *I* set, never by reading the operator's.

### Methodology note (a trap this probe hit twice)

`rc=$?` after `cmd | head` captures the **pipeline's** rc, not the command's. Two intermediate probe
tables printed `[exit=0]` beside output that was actually an error or a timeout. Every exit code
quoted in §3-§5 above is from an unpiped invocation. Same class as
`MEMORY.md → pipefail-inverts-early-exit-probe`.

---

## 8. Recommendation for TERMINAL_AGNOSTIC_L3_L4

1. **Set `automation.socketControlMode: "automation"`** in `~/.config/cmux/cmux.json`. It is the
   minimum mode that unblocks external control, needs no secret, and keeps the "same macOS user"
   boundary that the 0600 socket already enforces. Do **not** use `allowAll` (all local users, no auth).
2. **`cmux reload-config` applies a mode change in place** — no app restart, no relaunch. (The env
   override in §1b works too but requires a relaunch, so it is the weaker option.)
3. **Launch cmux with a path**, never bare — see §6.
4. Treat `cmux capabilities`'s `access_mode` field as the runtime assertion that the mode took effect;
   it is cheap, unambiguous, and served even when the UI is wedged.
5. Upstream context: this is open issue
   [manaflow-ai/cmux#3089](https://github.com/manaflow-ai/cmux/issues/3089) ("CLI rejects connections
   from processes outside the terminal session"), still open with no documented workaround, and
   feature request [#1864](https://github.com/manaflow-ai/cmux/issues/1864). The answer above resolves
   #3089 empirically for 0.64.20 — the capability the issue asks for already shipped, just
   undocumented in the help text.

---

## 9. Config-safety attestation

`~/.config/cmux/cmux.json` was edited **twice** (once for `password` mode, once for `automation`
mode) and restored both times from a byte-level pristine copy taken before the first edit.

| Checkpoint | sha256 |
|---|---|
| Pre-edit (recorded before any change) | `b39651a469da4975d11185716f59cb25bcc0c491f26dc8f23153221696c5f7c2` |
| After restore #1 | `b39651a469da4975d11185716f59cb25bcc0c491f26dc8f23153221696c5f7c2` ✅ |
| **Final (end of session)** | `b39651a469da4975d11185716f59cb25bcc0c491f26dc8f23153221696c5f7c2` ✅ **MATCH** |

Size 13 440 bytes, mtime preserved at 13:43 via `cp -p`.

A byte-identical config is **not sufficient** on its own, because cmux imports file-managed values
into UserDefaults. Also verified reverted:

- `defaults read com.cmuxterm.app socketControlMode` → *"does not exist"* (was `password`, then
  `automation`). Reverted by cmux's own mechanism — it records the prior state in
  `cmux.settingsFile.backups.v1` as `{"socketControlMode":{"kind":"absent"}}` and restores it on
  reload; both `cmux.settingsFile.backups.v1` and `cmux.settingsFile.importedManagedDefaults.v1` are
  now absent. Residue grep count: **0**.
- **Behavioural positive control:** the running app refused the external caller again with
  `Access denied - only processes started inside cmux can connect` — i.e. the revert was verified by
  observed enforcement, not just by key absence.
- `~/.local/state/cmux/socket-control-password` (created by the probe, contained the probe password)
  — **removed**. Probe sockets `cmux-501.sock`, `cmux-501.sock.lock`, and the stale `cmux.sock`
  — removed. `last-socket-path` restored to its original 44-byte content. State dir now holds exactly
  the two files present at session start (`cmux.sock.lock`, `last-socket-path`).
- `~/.config/cmux/cmux.json.bak-20260731T145730` (the protocol backup) — removed as redundant once the
  restore was hash-verified. `~/.config/cmux/cmux.20260731T215907.bak` — a backup **cmux itself** wrote
  in response to the probe edit, which contained the probe password in plaintext — removed. The config
  dir now holds exactly the three files present at session start.
- Session file shape unchanged: 1 window / 1 empty workspace entry, matching the pre-existing
  `session-com.cmuxterm.app-previous.json` from 13:45.
- cmux left **not running**, as found. Every pane/split/workspace created by the probe was closed
  before shutdown. Peak concurrent footprint: 1 app, 1 window, 2 panes — far inside the 512 thread /
  64 pane / 16 window / 64 process ceilings. No iTerm2 window and no `claude` process was signalled,
  closed, or sent input. System memory after teardown: 92% free, 0 swap.
