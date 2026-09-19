# U08 — pane transport on kitty: what is sanctioned, what failed today, and the one library to build

Unit: U08-pane-transport · 2026-09-19 · read-only · box: kitty 0.48.2 (`kitty --version => kitty 0.48.2 created by Kovid Goyal`), socket `unix:/tmp/kitty-73832`, this pane `KITTY_WINDOW_ID=127`, `TERM=xterm-kitty`.

## 0. The one-line verdict

**`cc-pane send` cannot reach a kitty pane at all — its text path is hardcoded to iTerm2 AppleScript and iTerm2 is not running on this box — and the two primitives limit-recovery actually needs (submit-verified typing into a Claude Code composer, and clear-the-composer) exist in the tree only as *private* functions inside `scripts/handoff-fire.sh`, keyed on SCREEN SCRAPING, with no callable entry point.** The fix is not a new transport; it is to lift three already-measured helpers out of `handoff-fire.sh` into a sourceable lib, re-key the verification on the target session's own transcript (`~/.claude/cc-registry/<pane>.json → session_id → <projects>/<slug>/<sid>.jsonl`, a 19 ms tail read), and switch the wire to `kitty @ send-text --from-file … --bracketed-paste=enable`, which kitty documents as byte-exact and which **appears nowhere in this repo**.

---

## 1. Call-site census — every `kitty @` / `send-text` / `send-key` / `get-text` in `scripts/`, `bin/`, `hooks/`

`grep -rn 'kitty @\|send-text\|send-key\|get-text' scripts bin hooks` => 120 lines. Stripping prose/comment-only hits, the **executable** call sites are:

### 1a. `send-text` — the ONLY text-delivery primitive in the tree (7 executable sites)

| file:line | call | purpose |
|---|---|---|
| `bin/it2-kitty:1144` | `kt send-text --match "id:$SESSION" -- "$text"` | `session send` — raw text, **no newline** |
| `bin/it2-kitty:1180` | `kt send-text --match "id:$SESSION" -- "$text"$'\r'` | `session type` — text **+ CR**, unconditional (added 2026-09-17) |
| `bin/it2-kitty:1209` | `kt send-text --match "id:$SESSION" -- "$text"$'\r'` | `session run` legacy arm, reached only on `type_verified` rc 2 (abstain) |
| `bin/it2-kitty:552` | `kt send-text --match "id:$id" -- $'\x15'` | pre-type scrub (Ctrl-U) inside `type_verified` |
| `bin/it2-kitty:554` | `kt send-text --match "id:$id" -- "$wire"` | the nonce wire `: <nonce>; <line>` |
| `bin/it2-kitty:570` | `kt send-text --match "id:$id" -- $'\r'` | the **verified** CR |
| `bin/it2-kitty:572` | `kt send-text --match "id:$id" -- $'\x15'` | post-failure scrub |
| `scripts/kitty-drag-w4.sh:492` | `kit send-text --match "id:${bottom}" …` | drag harness (not agent traffic) |
| `scripts/cloud-websetup-drive.sh:220,222,237` | `kitten @ send-text --match "id:$wid" "/web-setup"` then `"\r"` | the one non-`it2` agent-text caller; **note `"\r"` is passed as the two-character string and relies on kitty's escape interpretation** — comment at :222 reads `# T2: \r, never \n` |

**Zero call sites use `--stdin`, `--from-file`, or `--bracketed-paste`.** Verified: `grep -rn -- '--from-file\|send-text --stdin\|bracketed-paste' scripts bin hooks` returns only prose hits (handoff-fire.sh:8, 2228-2232, 2362, 3226, 5380-5381, 11093…; cc-type-verified.sh:29; pty-run.py:30) — every one of them describing the **hand-rolled** ESC[200~ wrap, never the flag.

### 1b. `send-key` — ZERO call sites

`grep -rn 'send-key' scripts bin hooks` matches **only** `scripts/typed-send-lint.sh` (lines 23, 228, 518, 639, 717), and every one of those is about **`tmux send-keys`**, a different verb in a different terminal, used as a lint pattern. **`kitty @ send-key` is used nowhere in this repository and is not a sanctioned primitive.** §3c explains why that is correct.

### 1c. `get-text` — the read primitive (8 executable sites)

| file:line | call |
|---|---|
| `bin/it2-kitty:1286` | `kt get-text --match "id:$SESSION"` — the `it2 session read` verb, the public seam |
| `bin/it2-kitty:862` | `kt get-text --match "id:$id" --ansi` — inside `composer_state` |
| `bin/it2-kitty:426` | `kt get-text --match "id:$pane"` — `deliver_argv` failure diagnostic (last 5 lines) |
| `bin/it2-kitty:557` | `kt get-text --match "id:$id"` — the echo-verify read inside `type_verified` |
| `bin/it2-kitty:1244` | `kt get-text --match "id:$SESSION"` — composer snapshot before a refused close |
| `bin/cc-wedge-watch:152,154` | `"$KITTY" @ --to "$KITTY_LISTEN_ON" get-text --match "id:$1"` (with a no-`--to` fallback) |
| `bin/cc-spawn-verify:231,232` | same shape |
| `scripts/cloud-websetup-drive.sh:186` | `kitten @ get-text --match "id:$1" \| tr -d '\000'` |
| `bin/reso-keepalive:171` | get-text, with the correct "empty means *could not read*, not *nothing there*" rule |

### 1d. `kitty @ ls` — the enumeration/identity primitive

`bin/it2-kitty` (`kt ls`, `kt ls --match id:N` in `shell_prompt_pane`/`identity_ok`/`pane_exists`), `bin/cc-kitty-wash:39,95,118`, `bin/cc-where:78`, `bin/kitty-pane-menu`, `bin/cc-resume-layout.sh:177`, `scripts/render-census.sh:264-273`, `scripts/handoff-fire.sh:1211-1215`, `scripts/kitty-pane-title-overlay.py:1155`.

---

## 2. The sanctioned transport for each primitive, on kitty, today

| primitive | sanctioned call | file:line | verified? |
|---|---|---|---|
| **read a pane's screen** | `it2 session read -s <id>` → `kitty @ get-text --match id:<id>` | `bin/it2-kitty:1286` | n/a — but **empty output means UNREADABLE, never empty** (`bin/reso-keepalive:171`; `composer_content` returns rc 1 on empty, `handoff-fire.sh:2396`) |
| **type text, no submit** | `it2 session send -s <id> <text>` → `kitty @ send-text --match id:<id> -- <text>` | `bin/it2-kitty:1143-1144` | **no** — `prove_target` only proves the window exists (`bin/it2-kitty:466-479`) |
| **submit (bare CR)** | `it2 session send -s <id> $'\r'` (control-only payload) | `handoff-fire.sh:2812`; `bin/cc-pane:187-191` classifies control-only and takes the raw path | no |
| **type + submit, one call** | `it2 session type -s <id> <text>` → `send-text … -- "$text"$'\r'` | `bin/it2-kitty:1180` (verb added 2026-09-17) | **no** |
| **clear the composer** | `$'\x15'` (Ctrl-U) repeatedly, then `$'\x7f'` (DEL) when Ctrl-U stops making progress, **read-back verified each round** | `handoff-fire.sh:composer_scrub_verified` **:2491-2517** | **yes** (rc 0 = proven empty, 1 = could not clear, 2 = box unreadable / nothing sent) |
| **verify a submit — screen tier** | `composer_content` (`:2392`) + `paste_readback_ok` (`:2646`), inside `it2_paste_submit_verified` (`:2713`) | `handoff-fire.sh` | yes, but screen-based and **private to handoff-fire.sh** |
| **verify a submit — DISK tier** | `engagement_seen` (`:2993`) = marker present in a `type:"user"` record (`marker_in_user_record` `:2956`) **AND** a content-bearing `type:"assistant"` record (`assistant_turn_in` `:2931`) | `handoff-fire.sh` | **yes — this is the oracle the new lib must use**; also private |

**Three things that do NOT exist and that limit-recovery needed today:**
1. No public "type into a TUI composer and prove it submitted" entry point. `it2 session type` (`:1180`) types and presses Enter with **no proof of anything**; `type_verified` (`:531`) *abstains* (rc 2) on any TUI — `shell_prompt_pane "$id" || return 2` at `:528`, and every live Claude pane reads `in_alternate_screen: True` (measured below).
2. No public composer-clear. `composer_scrub_verified` is a private function 2491 lines into a 11,500-line script.
3. No kitty driver for `cc-pane`: `ls bin/cc-pane-* => bin/cc-pane-headless, bin/cc-pane-runner`. There is no `bin/cc-pane-kitty`.

---

## 3. Why the three things failed today

### 3a. `cc-pane send 111 "<text>"` warned "could not disarm zsh spell-correction" and delivered nothing

Exact call chain, all cited:

1. `bin/cc-pane:65` — `DRIVER="${CC_PANE_DRIVER:-iterm2}"`. Unset ⇒ the built-in **iterm2** driver, in kitty.
2. `bin/cc-pane:326-327` — `send)` → `drv_iterm2_send "$id" "$@"`.
3. `bin/cc-pane:213-224` — `drv_iterm2_send` splits on payload class via `pane_ctrl_only` (`:187-191`). A real message is **not** control-only ⇒ falls to `pane_type_verified "$id" "$*"` (`:224`).
4. `bin/cc-pane:197-211` — `pane_type_verified` sources `scripts/lib/cc-type-verified.sh` and calls `osa_type_verified`.
5. `scripts/lib/cc-type-verified.sh:246-256` — `osa_type_verified` first types the disarm line, and on failure prints **verbatim** the warning seen today:
   `cc-type-verified: could not disarm zsh spell-correction in pane $sid — proceeding (the command line is still echo-verified)` (`:252`).
6. That disarm goes through `_cc_tv_type_line` → `_cc_tv_scrub_type_read` (`:118-141`), whose **third line of AppleScript** is
   `if not (application id "com.googlecode.iterm2" is running) then return "__CC_TV_NO_SUCH_SESSION__"` (`:126`).
7. `_cc_tv_type_line:219` — `case "$screen" in *"$CC_TV_NOSESS"*) return 1 ;;` → immediate rc 1, **no retry**.
8. Back in `osa_type_verified:255` the **command line itself** takes the identical path and also returns 1 ⇒ `pane_type_verified` returns `RC_NO`.

Two independent reasons it could never have worked:
- **iTerm2 is not running.** `pgrep -lf 'iTerm' => (no output)`. The sentinel fires on line 126 before anything else.
- **`111` is a kitty window id, not an iTerm2 session UUID.** Even with iTerm2 up, `if id of s is sid` (`:130`) could not match; the `-e` chain would fall through to `return "$CC_TV_NOSESS"` at `:143`.

**This is the file's own documented gap, not a surprise.** `scripts/lib/cc-type-verified.sh:38-51` explains it chose the osascript transport *over* the it2 CLI deliberately, because two of its three callers run from launchd. That reasoning was written for an iTerm2 fleet; on a kitty box it inverts — the transport it chose is the one that cannot reach a pane. `bin/cc-pane:101-118` (`it2_real_bin`) already carries a kitty arm for the *spawn* verb; **`send`'s text path never got one.**

Net: the warning is not a warning. It is the first of two identical fatal errors, and the second one (the payload) failed silently into `RC_NO`.

### 3b. `it2 session send -s 111 CR` did nothing

`bin/it2-kitty:1137-1146`, the whole `send)` arm:

```
text="${ARGS[*]:-}"
armed "$SESSION" && exit 0
prove_target "$SESSION" send || exit 1
kt send-text --match "id:$SESSION" -- "$text" || exit 1
```

`$text` is the literal string **`CR`**. There is no keyname vocabulary anywhere in the shim — `grep -n "'CR'\|\"CR\"\|keyname" bin/it2-kitty` finds none. So the call delivered the two printable characters `C` and `R` into pane 111's composer, with **no newline** (the arm's own comment at `:1138` says *"Raw text, NO newline"*). Nothing submitted, and "nothing happened" is the honest description of two characters landing in a box you were not watching closely.

Two amplifiers worth naming:
- **rc 0 is meaningless here.** kitty's own help, verbatim: *"Note that errors are not reported, for technical reasons, so send-text always succeeds, even if no text was sent to any window."* (`kitty @ send-text --help`). `bin/it2-kitty:443-446` records the same thing measured: `kitty @ send-text --match id:999999 -- "" → rc=0, no output`. The `|| exit 1` on `:1144` is dead code; `prove_target` is the only reason a wrong id is caught.
- **The `armed` short-circuit can make `send` a silent no-op that exits 0** (`:1143`, function at `:377-388`). Today that was probably *not* the cause: TTL is `CC_PANE_CMD_WAIT_S(300)+60 = 360 s` (`bin/it2-kitty:350-355`), and `ls -la ~/.claude/run/kitty-pane-cmd/` shows only `105.armed`, `131.armed`, `141.armed` — no `111.armed`. But it IS the shape that killed the recycle path on 2026-09-17 (`scripts/handoff-fire.sh:1424-1432`: pane 17's stale marker, `as_write` returned non-zero 3× and both callers killed their own armed watcher). Any new lib must not route a *message* through a verb that consults `armed`.

`cc-pane send 111 CR` would also have failed, differently: `pane_ctrl_only` (`bin/cc-pane:187-191`) classifies `CR` as **not** control-only (it is two printable bytes), so it would have gone down the dead iTerm2 path in §3a.

### 3c. `kitty @ send-key ctrl+u` rendered as the literal `^[[117;5u`, while `send-text` of printable text + `\r` worked and a literal ESC cleared the composer

Three facts, each cited:

**(i) kitty encodes `send-key` against the program's *current keyboard mode*, and will not tell you what it did.** `kitty @ send-key --help`, verbatim:
> *"All specified keys are sent first as press events then as release events in reverse order. Keys are sent to the programs running in the windows. **They are sent only if the current keyboard mode for the program supports the particular key.** … Note that errors are not reported, for technical reasons, so send-key always succeeds, even if no key was sent to any window."*

And that mode is **not observable from outside**: `kitty @ ls` exposes 26 fields per window — `at_prompt, cmdline, columns, created_at, cwd, env, foreground_processes, has_activity_since_last_focus, id, in_alternate_screen, is_active, is_focused, is_self, last_cmd_exit_status, last_focused_at, last_reported_cmdline, lines, needs_attention, neighbors, pid, session_name, title, title_overridden, user_vars` — **none of them is the keyboard mode**. So `send-key`'s output bytes are unpredictable from the caller's side, and its rc is a constant 0. That is disqualifying on its own.

**(ii) Claude Code puts the pane into the kitty keyboard protocol, which is why the encoding was CSI-u.** Measured directly in the shipped binary (`~/.claude-versions/{2.1.114,2.1.183}/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`):

```
iB4=bT("G");Vk=bT("H");…haq=bT("200~"),yaq=bT("201~"),vI6=bT("I"),hI6=bT("O"),
ooH=bT(">1u"),Ea=bT("<u"),aoH=bT(">4;2m"),ZwH=bT(">4m")
```
`bT()` is the CSI builder, so `ooH = CSI > 1 u` (**push kitty keyboard protocol, flags=1 "disambiguate escape codes"**) and `Ea = CSI < u` (pop). And it is written on every mount and re-asserted on every resume:
```
…if(uaH())this.props.stdout.write(ooH),this.props.stdout.write(aoH);
…this.options.stdout.write("\x1B[?1004h"+(uaH()?Ea+ooH+aoH:""))
reassertTerminalModes=(H=!1)=>{…if(uaH())this.options.stdout.write(Ea+ooH+aoH);…}
```
`uaH()` is the kitty/ghostty predicate — the same binary carries `if(_?.includes("kitty")||process.env.KITTY_WINDOW_ID)return!0`. Confirmation from the other direction: the binary also carries the **response** parser `TF4=/^\x1b\[\?(\d+)u$/` producing `{type:"kittyKeyboard",flags:…}`.

So the window's current keyboard mode *was* the kitty protocol. `ctrl+u` in that protocol encodes as `CSI <codepoint> ; <modifier> u` = `ESC [ 117 ; 5 u` — 117 is `u`, 5 is `1 + ctrl(4)`. **That is byte-for-byte the `^[[117;5u` the operator saw.** The observation is therefore *consistent and explained*: kitty did exactly what its contract says.

Why it then rendered as text rather than clearing the line: Claude Code's input decoder did not consume that particular CSI-u sequence, so it fell through to the composer as printable characters. *(This last step is inferred from the operator's observation plus (ii); I could not execute a keystroke to confirm it, and the exact decode table was not extracted. Label: inferred, high confidence on the encoding, medium on the decoder.)*

**(iii) `send-text` works because it bypasses the keyboard mode entirely.** `send-text` writes bytes to the pty; no key model, no mode lookup. `--help`: *"The text follows Python escaping rules. So you can use escapes like `\e` to send control codes."* Hence:
- printable text + `\r` → the composer receives the characters and a CR, which Claude Code treats as submit. Works.
- a literal `0x1b` → the composer receives one ESC byte. Claude Code binds Escape to clear-input, and with nothing following it the parser resolves it as the Escape key. Works.
- `\x15` → one Ctrl-U byte, which is exactly what `composer_scrub_verified` (`handoff-fire.sh:2503`) and `type_verified` (`it2-kitty:552,572`) already send. **This, not ESC, is the in-tree sanctioned clear** — and it is safer: ESC in a Claude Code TUI also interrupts a running turn, and a double-ESC opens history, so an ESC-based clear has side effects a Ctrl-U does not.

**🚨 A latent defect this exposes, currently unmitigated in the tree.** *"The text follows Python escaping rules"* applies to **every** `send-text` payload the repo sends, including whole briefs. A brief containing `\n`, `\e`, `\u`, `\x` or a lone backslash is **silently reinterpreted on the wire**. `bin/it2-kitty` passes payloads as `-- "$text"` (`:1144,:1180,:1209`) — `--` stops *option* parsing, it does not disable escape interpretation. kitty documents the cure and the repo uses it nowhere: `--stdin` (*"the text is sent as is, not interpreted for escapes"*) and `--from-file` (*"the file contents are sent as is, not interpreted for escapes"*).
**Cheap falsifier for the lead:** `handoff-fire.sh:2680-2690` records 5 MANGLED read-backs in 94 arms (3/62 recycles, 2/26 fresh fires, ~6%, mode-independent, "stochastic"). Grep those 5 payloads for a backslash. If they carry one, the "stochastic" residue is not stochastic at all — it is this escape rule, and `--from-file` deletes it.

---

## 4. The proposed library: `scripts/lib/cc-tui.sh`

Three functions, sourceable, bash 3.2-safe. Design rules, each earned above:

* **Wire = `send-text --from-file` + `--bracketed-paste=enable`.** Byte-exact (no Python escapes), one RPC, and kitty's own bracketed-paste rather than `handoff-fire.sh:2242-2243`'s hand-rolled `BP_START`/`BP_END` — which are themselves passed *inside* the escape-interpreted text argument.
* **Never `send-key`.** §3c(i): unobservable encoding, constant rc 0.
* **Never route a message through `session run`** (consults `armed`, waits for a runner that does not exist behind a TUI — `handoff-fire.sh:1424-1432`). Bypass `it2 session send/type` too, so the `armed` short-circuit at `it2-kitty:1143` can never swallow a message.
* **Verification is DISK-first, screen-second.** A TUI screen is a sample, not a state (`handoff-fire.sh:2681`: *"A TUI screen is a SAMPLE, not a STATE"*); the transcript is append-only ground truth.

### 4.1 Identity: pane → session → transcript, in two file reads

```bash
# ~/.claude/cc-registry/<pane>.json  (REG_DIR, handoff-fire.sh:372)
#   => {"session_id": "...", "cwd": "...", "name": "...", "account": "claude-tertiary", ...}
cc_tui_sid()  { jq -r '.session_id // empty' "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$1.json"; }
cc_tui_acct() { jq -r '.account    // empty' "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$1.json"; }
# transcript = <account cfg dir>/projects/<slug(cwd)>/<sid>.jsonl
```
Measured live: `~/.claude/cc-registry/111.json => session_id 09e64dcb-16c7-4c65-8b11-fd854d50f299, cwd /Users/chrisren/Development/claude-infrastructure, account claude-tertiary`; `114 => 05683f40-…, wt-cc-100046-36511, claude-secondary`; `117 => cb227486-…, claude-infrastructure, claude-secondary`. **The registry already answers "which session is in pane N, on which account" without reading a single pixel** — this is the same lookup U-whatever-owns-identification should use instead of OCR'ing a statusline. (It is also strictly better than the screen: pane 111 is currently 30 columns wide and its statusline renders `(3) 65% · claude-infrastr…` — the cwd is **truncated**, so screen-derived identity is width-dependent and lossy.)

### 4.2 `cc_tui_type <pane> <file>` — deliver, no submit

```bash
cc_tui_type() {  # $1=kitty window id  $2=path to a file holding the EXACT bytes
  local id="$1" f="$2"
  cc_tui_exists "$id" || return 1                     # kitty @ ls --match id:N, 37ms — NOT bare ls
  kitty @ --to "$CC_KITTY_TO" send-text --match "id:$id" \
      --bracketed-paste=enable --from-file "$f" || return 1
}
```
Notes: `send-text` rc is a constant 0 (kitty help), so `cc_tui_exists` **before** the send is the only existence proof — same rule and same reason as `prove_target` (`it2-kitty:466-479`). Use `ls --match id:N` (14,089 B / 37 ms) not bare `ls` (243,772 B / 499 ms) — measured below.

### 4.3 `cc_tui_submit_verified <pane> <file>` — the one that must be right

```
rc 0  submitted AND a user record carrying the payload exists in the session transcript
rc 1  send failed / pane provably absent
rc 2  ABSTAINED — composer unreadable, or a blocking modal (no box on screen); nothing typed
rc 3  HELD — composer was non-empty through the pre-wait (an operator draft); nothing typed
rc 4  MANGLED — read-back mismatch; CR NOT sent; composer scrubbed; receipt written
rc 5  CR sent but no transcript record within the window — CANNOT TELL (never "failed")
```

Sequence:
1. **Ownership + emptiness gate.** `composer_owned "$id"` (`handoff-fire.sh:2340`) then poll `composer_content` (`:2392`) until empty, bounded (`FIRE_PASTE_PREWAIT`, default 30 s). Unreadable ⇒ rc 2, occupied ⇒ rc 3. Rationale is already written at `handoff-fire.sh:2732-2736`: *"a bracketed paste into a single-key prompt is consumed as ANSWERS."* Never skip this.
2. **Snapshot the transcript high-water mark** *before* typing: `wc -c < "$transcript"` (or last record ts). This is the whole reason the disk oracle is not fooled by residue — the equivalent of the nonce in `type_verified`, without putting a nonce into a chat message (which `it2-kitty:1160-1167` correctly calls *"not merely useless on a TUI but DESTRUCTIVE"*).
3. **`cc_tui_type`.**
4. **Screen read-back, polled not sampled.** `paste_readback_ok "$text" "$(composer_content …)"` (`:2646`), `FIRE_PASTE_READBACK_TRIES` (default 8) × `FIRE_TYPE_SETTLE`. Mismatch after the budget ⇒ `cc_tui_clear` + `composer_residue_record` (`:2570`) ⇒ rc 4. This tier only decides *whether to press Enter*; it is not the success oracle.
5. **CR:** `send-text --match id:N -- $'\r'`.
6. **Disk oracle** — the actual verdict. Poll the **single** transcript named by the registry, from the byte offset captured in step 2:
   ```bash
   tail -c +"$off" "$transcript" | jq -rn --arg m "$payload_tail" \
     'first(inputs|select(.type=="user" and ((.message.content?//.content?//""|tostring)|contains($m)))|"1")'
   ```
   This is `marker_in_user_record` (`handoff-fire.sh:2956-2964`) narrowed to one file. **Cost measured: `tail -c 400000` of a 12.2 MB transcript = 19 ms; a full `grep -c` of the same file = 94 ms.** Compare `engagement_seen`'s current cost, which enumerates the whole projects dir (`find … -mmin -240`, 1705 files → 23 candidates per its own note at `handoff-fire.sh:~3080`). Knowing the sid collapses that to one open.
   Optionally escalate to "and it *ran*": `assistant_turn_in` (`:2931`) — a content-bearing `type:"assistant"` record after the offset.
7. Window expiry with no record ⇒ **rc 5, cannot tell**, never rc 1. `engagement_seen`'s own four-state contract (`handoff-fire.sh:2986-2990`) and the incident behind it (three panes re-fired while already working) is the precedent.

### 4.4 `cc_tui_clear <pane>` — proven empty or say so

Lift `composer_scrub_verified` verbatim (`handoff-fire.sh:2491-2517`): read `composer_content`; if unreadable return 2 **before any keystroke**; loop up to `CC_COMPOSER_SCRUB_ROUNDS` (12) sending `$'\x15'`, re-reading each round; when Ctrl-U stops making progress send one `$'\x7f'` (the cursor is at the start of an empty line). Return 0 only on a read-back that is empty.

**Do not use ESC**, even though it worked today: ESC in a Claude Code TUI also interrupts the running turn, and the double-ESC chord opens history — side effects `\x15` does not have. **Do not use `kitty @ send-key ctrl+u`** (§3c).

### 4.5 Where it goes, and what it deletes

- New file `scripts/lib/cc-tui.sh`; `bin/it2-kitty` gains one verb `session tui-submit -s <id> --from-file <f>` so there is still ONE seam (`handoff-fire.sh:1408`'s *"ONE SEAM, NOT TWO"*).
- `bin/cc-pane` grows a real `bin/cc-pane-kitty` driver, or `drv_iterm2_send`'s text arm learns the kitty branch `it2_real_bin` already has (`bin/cc-pane:101-118`). **Until one of those lands, `cc-pane send <text>` is a no-op on this box and should be treated as unavailable.**
- `handoff-fire.sh`'s five private helpers become thin wrappers over the lib, so the limit-recovery rail and the fire rail cannot drift.

---

## 5. The race the design must respect (`cc-pane-runner`'s rationale)

`bin/cc-pane-runner:5-25`, verbatim in substance: Claude Code's iTerm2 backend delivers a launch command by typing `$'\x15'` then the text — *"TWO separate process spawns against ONE mutable resource — the pane's prompt line, which the human also owns."* On 2026-08-03 a 7-way fan-out lost two agents when *"the operator's own in-flight keystroke landed BETWEEN the Ctrl-U and the payload"*, giving `ccd …` and `tcd …` (the second parked forever on `zsh: correct 'tcd' to 'cd' [nyae]?`). And the load-bearing sentence for U08: **"It cannot be fixed by better escaping or better timing. Correctness would require that the operator not be typing, which is neither knowable nor enforceable."** `bin/it2-kitty:966` says it again: *"our send-text write to the SAME pty, and a pty has no notion of who typed."*

Consequences for `cc_tui_*`:
1. **The race is not removable, only detectable.** `cc-pane-runner` removes it for *launch* by making the command the pane's **argv** (`kitty @ launch --env CC_PANE_CMD=…`, `bin/it2-kitty:1057`) — there is no prompt line to collide with. **There is no argv for a message into a live composer**, so limit-recovery's ingest keeps the race and must keep the read-back.
2. **Therefore the emptiness pre-gate is mandatory, not optional.** It is what stops a paste *appending* to an operator draft and a CR submitting the hybrid (`handoff-fire.sh:2707-2711`).
3. **Therefore the failure must leave the composer clean.** Unsubmitted text is recoverable; a submitted hybrid is not. The 2026-08-23 outage (`handoff-fire.sh:2775-2782`) was exactly this: an unscrubbed mangle blocked every later recycle for 4+ hours, with absence as its only symptom.
4. **Therefore a mangle needs a receipt.** `composer_residue_record` / `composer_residue_is_ours` (`:2570-2600`) — content-keyed, so it cannot rot into a licence.

---

## 6. Measurements taken this session (all read-only, kitty 0.48.2, socket `unix:/tmp/kitty-73832`)

| measurement | result |
|---|---|
| `kitty @ ls` (all 16 windows) | **243,772 B, 499 ms** (other samples 70-190 ms) |
| `kitty @ ls --match id:111` | **14,089 B, 37 ms** — 17× smaller, ~13× faster |
| `kitty @ get-text --match id:111` | rc 0, 1,348 B, 428 ms / 45 ms (`--extent screen`) / 35 ms (`--extent all`) |
| `kitty @ get-text --match id:117` | rc 0, 1,545 B, 31-134 ms |
| `kitty @ get-text --match id:127` | rc 0, 6,559 B, 39-201 ms |
| `kitty @ get-text --match "id:"` (empty id) | **7.6 s** then `Error: No matching windows for expression: id:` — a malformed match is 200× the cost of a good one; validate the id before the RPC |
| socket reliability | one hard failure in ~12 calls: `Error: read unix ->/tmp/kitty-73832: i/o timeout`, rc 1, 0 bytes. **Every `kitty @` call must be bounded, retried, and its failure treated as INDETERMINATE, never "the pane is gone."** |
| `tail -c 400000` of a 12,171,774 B transcript | **19 ms** |
| `grep -c '"type":"user"'` same file | **94 ms** |
| `in_alternate_screen` across live panes | `110 True, 122 True, 126 True, 124 True, 112 True, 117 True, 114 True, 135 True` — every Claude pane is TUI, so `type_verified` (`it2-kitty:531`) abstains on all of them by construction |
| `pgrep -lf iTerm` | **no output** — iTerm2 not running |
| `ls ~/.claude/run/kitty-pane-cmd/` | `105.armed` (Sep 18 17:09), `131.armed`, `141.armed` — three stale markers; TTL is 360 s (`it2-kitty:350-355`), so all three are expired, but they are live evidence that markers leak |
| `cmp ~/.claude/bin/it2 bin/it2-wrapper` | **identical** — the deployed shim IS `bin/it2-wrapper`, which execs `bin/it2-kitty` under kitty (`bin/it2-wrapper:60-110`) |
| `grep -rn -- '--from-file\|--stdin\|bracketed-paste' scripts bin hooks` | **0 executable uses** |
| `grep -rn 'send-key' scripts bin hooks` | **0 kitty uses** (5 hits, all `tmux send-keys` inside `scripts/typed-send-lint.sh`) |

---

## 7. What I could not determine (labelled)

1. **Why Claude Code's decoder rendered `CSI 117;5u` as text** rather than consuming it, given it pushed `CSI >1u` itself. The encoding is proven from the binary; the decode-table gap is inferred from the operator's observation. I did not extract the key-parser table, and I could not send a keystroke to test. It does not change the recommendation (`send-key` is disqualified by rc-always-0 and unobservable mode regardless).
2. **Which binary version the affected panes were running.** `~/.claude-versions/` holds 2.1.113, 2.1.114, 2.1.183; `>1u`/`<u` are present in all three, so the mechanism holds either way.
3. **Whether the 5 MANGLED read-backs in `handoff-fire.sh:2680-2690` carry backslashes.** That is the falsifier for §3c's escape-interpretation hypothesis and costs one grep of `~/.claude/logs/handoffs.jsonl`; I did not run it (out of scope for this unit's file set).
4. **Exact latency of `cc_tui_submit_verified` end-to-end.** Composed from the parts above it should be ~0.1 s wire + 0.5-4 s read-back settle + ~20 ms disk poll per tick; not measured as an assembly because assembling it requires sending into a pane.
