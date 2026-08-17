# Launcher-wrapper layer — measurement notes (2026-08-16)

Axis: `~/bin/claude-latest` (15,182 bytes, 389 lines, bash, `set -euo pipefail`).
Box: macOS 24.6.0, ~24 live claude sessions. All numbers re-measured today.

## 0. Static read — the wrapper's blocking sequence

`main` (lines 331-389), everything here runs BEFORE `exec`:

```
rotate_log            # 325-329
update_if_needed      # 155-288   <-- network
validate_or_recover   # 292-321
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=50   (if unset)
stderr-capture block  # 366-388   <-- per-file kill -0 loop + ls|tail
exec .../node_modules/.bin/claude "$@" 2> >(tee -a "$_sl" >&2)
```

## 1. STATE SNAPSHOT (the finding is in the state, not the code)

```
$ cat ~/.claude/.npm-version-cache
1786916600
2.1.233
$ readlink ~/.claude-versions/current
/Users/chrisren/.claude-versions/2.1.114
$ grep -o '"version": "[^"]*"' "$(readlink ~/.claude-versions/current)/node_modules/@anthropic-ai/claude-code/package.json" | cut -d'"' -f4
2.1.114
```

**cached_version (2.1.233) != installed (2.1.114).** The cache guard is

```bash
if [[ "$cache_age" -lt "$CACHE_TTL" && "$cached_version" == "$installed" ]]; then
    return 0
fi
```

Both clauses must hold. The second NEVER holds, because the wrapper caches
*the newest version on npm*, not *the version it decided to run*. reso pins
2.1.114 via MANIFEST default-deny, so the two can never converge while the pin
stands. => **CACHE_TTL=600 is dead code on this machine. `npm view` runs on
EVERY launch.** Permanently-cold cache, exactly as hypothesised.

Corroborating disk evidence — every launch logs a REFUSED line:

```
$ tail -3 ~/.claude/.update-versions.log
[2026-08-16 14:43:18] REFUSED auto-install of 2.1.233 ... staying on 2.1.114.
[2026-08-16 14:43:19] REFUSED ...
[2026-08-16 14:43:21] REFUSED ...
```

Three launches inside 4 seconds each paid the network call.

Other state:
- `~/.claude/.update-versions.log` = 62,529 bytes, **335 lines** (< 500 ⇒ rotate_log
  does the `wc -l` and returns; no tail/mv).
- `~/.claude/logs/stderr/` = **41** `.log` files.
- `~/.claude-versions/` = 2.1.113, 2.1.114, 2.1.183, current, MANIFEST.jsonl
  (3 version dirs, GC_THRESHOLD = 2+2 = 4 ⇒ cleanup_stale_versions no-ops, and
  it is only reached on the install path anyway).

Note on those three 14:43 lines: they are **the lead's own three probe runs**
(`~/bin/claude-latest --version` = 1.50/1.29/1.28s in the brief). My first probe was 14:49.
So even the "launches" in today's log are measurement traffic — see §6.

---

## 2. THE HEADLINE DEFECT — the cache is structurally unhittable (when the wrapper runs)

Guard, `update_if_needed` lines 169-172:

```bash
if [[ "$cache_age" -lt "$CACHE_TTL" && "$cached_version" == "$installed" ]]; then
    return 0
fi
```

The wrapper caches **what npm returned** (`available`), not **what it decided to run**
(`installed`) — line 176 `echo -e "$now\n$available" > "$CACHE_FILE"`. MANIFEST default-deny
pins 2.1.114 (every later version `status:"skip"`), npm latest is 2.1.233, so the two operands
can never converge while the pin stands. **CACHE_TTL=600 is dead code. Every launch pays
`npm view`.** Confirmed by A/B on an instrumented copy (§4, batches D/D2/D3 vs E).

### Bistability (why I found the live cache reading 2.1.114 mid-probe)

Line 175 is `available=$(timeout 3 npm view … 2>/dev/null || echo "$installed")`. If the network
call **fails or hits the 3 s timeout**, `available` becomes `installed`, the cache is written
`2.1.114`, and the guard then HITS for the next 600 s. So a *failed* network call is the only
thing that ever makes this cache work, and only transiently. Steady state is cold.

Evidence the steady state is cold: **333 REFUSED lines** in the (rotated, 335-line) log spanning
2026-05-28 → 2026-08-16. Every REFUSED line is a launch that missed the cache *and* got a
successful `npm view`.

---

## 3. COMMANDS AND RAW SAMPLES

### 3a. `npm view` in isolation — n=20 across 3 batches

```bash
for i in 1 2 3 4 5; do /usr/bin/time -p npm view @anthropic-ai/claude-code version; done
```
batch 1 (back-to-back): 1.31 1.22 1.10 1.21 1.17
batch 2 (`timeout 3 …`, exit codes all 0): 1.351 1.004 0.975 1.101 1.111 2.111 1.741 1.128
batch 3 (4 s gaps, npm HTTP cache warm): 0.44 0.36 0.41 2.59 0.44 0.72 0.44

**min 0.36 s · median 1.11 s · max 2.59 s**, plus 3.0 s `timeout`-kills observed under
contention (§4 D/D2). npm cache = `~/.npm-cache`, **3.1 G**. user+sys ≈ 0.25 s ⇒ it is
network wait, not CPU.

### 3b. Instrumented scratch copy (own LOG_FILE/CACHE_FILE under /tmp, logic byte-identical)

```bash
sed -e 's#^LOG_FILE=.*#LOG_FILE="/tmp/wraplab/update.log"#' \
    -e 's#^CACHE_FILE=.*#CACHE_FILE="/tmp/wraplab/npm-cache"#' \
    ~/bin/claude-latest > /tmp/wraplab/wrap.sh
```

| batch | cache state | samples (s) | min | median |
|---|---|---|---|---|
| D  | MISMATCH, back-to-back (self-contended) | 3.45 3.20 1.59 1.73 1.45 | 1.45 | 1.73 |
| D2 | MISMATCH, back-to-back | 2.85 3.26 2.16 3.22 3.23 | 2.16 | 3.22 |
| D3 | MISMATCH, 3 s gaps | 0.98 0.71 0.63 0.79 0.66 0.65 0.68 | 0.63 | 0.68 |
| paired | MISMATCH, 4 s gaps | 0.63 1.02 0.59 0.73 0.60 0.70 0.91 | 0.59 | 0.70 |
| E  | **MATCHED (cache HIT)** | 0.23 0.23 0.24 0.26 0.21 0.23 | 0.21 | 0.23 |
| F  | `CLAUDE_SKIP_UPDATE=1` | 0.23 0.23 0.19 0.25 0.20 0.25 | 0.19 | 0.23 |

**Cache-HIT ≡ SKIP_UPDATE (0.23 s both).** The npm-view delta is the entire update layer.
Uncontended miss-path median (n=14) = **0.69 s**; the lead's independent n=3 = 1.29 s; contended
= up to 3.45 s. The spread is npm-HTTP-cache warmth, and it is real: this is a network call.

### 3c. `CLAUDE_SKIP_UPDATE=1` vs plain — the removable cost

Because the *live* cache flapped to a HIT mid-probe (§2), the plain-vs-skip A/B on
`~/bin/claude-latest` itself returned a null result (0.19-0.22 vs 0.19-0.25 — both cache hits,
one REFUSED line at 14:52:41 from a concurrent operator launch). **The honest A/B is the
scratch copy above, where I control the cache state**: skip/hit 0.23 s vs miss 0.69-3.45 s.
Removable cost of `update_if_needed` = **0.46 s (best) to 3.2 s (worst), ~0.9 s typical.**

### 3d. Stage isolation — 20 iterations under one `/usr/bin/time -p`, divided

(First attempt used a `python3` timestamp per sample; python startup swamped the signal and
reported `bash -c true` at 40 ms. Discarded. Dead end recorded.)

| stage | per-launch |
|---|---|
| empty loop baseline | ~0 ms |
| `rotate_log` (`wc -l` over 62 KB / 335 lines) | **3.0 ms** — never rotates (335 < 500) |
| `validate_or_recover` (single `test -x`) | **<0.5 ms** |
| `get_installed_version` (readlink+grep+cut) | **5.0 ms** |
| stderr GC loop, 41 files | **120 ms** |
| `ls -1t \| tail -n +201` | **3.0 ms** (cap never reached at 41 files) |
| one `basename` fork | **2.0 ms** |
| `cleanup_stale_versions` | **NOT REACHED** — install path only; 3 version dirs ≤ GC_THRESHOLD 4 |

### 3e. stderr-capture block — clean A/B via its own kill switch

```bash
CLAUDE_SKIP_UPDATE=1 CLAUDE_STDERR_CAPTURE=0 /usr/bin/time -p /tmp/wraplab/wrap.sh --version
CLAUDE_SKIP_UPDATE=1                          /usr/bin/time -p /tmp/wraplab/wrap.sh --version
"$(readlink ~/.claude-versions/current)/node_modules/.bin/claude" --version
```
- raw 2.1.114 binary, n=8: 0.06 ×8
- wrapper, everything off, n=8: 0.07 0.07 0.07 0.07 0.07 0.07 0.07 0.08
- wrapper, stderr block ON, n=8: 0.19 0.19 0.18 0.18 0.19 0.19 0.19 0.19

⇒ **stderr-capture block = 0.12 s**, and the wrapper's *entire* remaining shell scaffolding
(bash start + rotate_log + validate + exec) = **0.01 s. Negligible.**

Cause is one `basename` **fork per file** (line 373, `_p=$(basename "$_f" .log)`); `kill -0` is
a builtin and free. Scaling probe (`/tmp/wraplab/scale.sh`, synthetic dirs, 5 iters each):

```
41 files (today's live count):        0.62s / 5  => 124 ms per launch
200 files (the cap this GC enforces): 2.94s / 5  => 588 ms per launch
```

Linear at ~2.9 ms/file. The block's own 200-file cap therefore admits a **588 ms** launch tax.
Both are pure shell: `${_f##*/}` + `${_p%.log}` removes the fork entirely.

### 3f. `2> >(tee -a "$_sl" >&2)` — process substitution

Cost: inside the 0.12 s above (one `tee` fork), not separately resolvable — but the GC loop
accounts for ~120 ms of it, so the procsub itself is single-digit ms. **UNKNOWN to finer
resolution.**

**TTY effect: REAL and confirmed.** Under a python `pty.spawn` harness
(`/tmp/wraplab/ptyrun.py`; `script -q /dev/null` was unusable — the Bash tool has no
controlling tty, `tcgetattr/ioctl: Operation not supported on socket`):

```
plain  exec python3 ttycheck.py            → isatty fd0=True fd1=True fd2=True   fd2 -> /dev/ttys027
exec … 2> >(tee -a "$_sl" >&2)             → isatty fd0=True fd1=True fd2=False  fd2 -> NOT A TTY
```

fd 2 becomes a **pipe**. Consequences: `isatty(2)` false (stderr colour/terminal detection
flips); stderr becomes block-buffered through a pipe instead of unbuffered to a tty — which
can **lose the very crash diagnostic the block exists to capture**; and `tee` stays resident
for the session's lifetime as an extra process.

---

## 4. 🚨 SCOPING CORRECTION — `claude-latest` IS NOT ON THE LIVE LAUNCH PATH

The brief's ground truth ("the `claude()` zsh function … calls `_claude_pinned`, which
ultimately runs `~/bin/claude-latest`") is **stale**, superseded by the 2026-07-31 launcher
consolidation. Refuted three independent ways:

1. **`_claude_pinned` does not exist.** `grep -n "_claude_pinned" ~/.zshrc` → no hits.
2. **`claude()` execs the binary directly.** `~/.zshrc:451` … `:496`
   `local _bin="$HOME/.claude-220/node_modules/.bin/claude"`, launched via
   `"$HOME/.claude/bin/cc-close-attrib" "$_bin" …`. `claude-latest` appears nowhere in it.
   The wrapper is reached only by `claude-prev` / `claude-prev2/3/4` / `cc-prev`
   (`~/.zshrc:173,175`) — the legacy stable-2.1.114 track.
3. **The running processes agree.**
   ```bash
   ps -eo command= | grep -o "/Users/chrisren/\.claude[^/ ]*/node_modules/\.bin/claude" | sort | uniq -c
   #   36 /Users/chrisren/.claude-220/node_modules/.bin/claude
   ```
   **36/36 live claude processes are `.claude-220`. Zero are `.claude-versions/*`.**
   `ps | grep -c 'tee -a …/logs/stderr'` = **0** — no session is running the wrapper's tee.

`handoff-fire.sh` also resolves its launcher from `accounts.json` via
`cc_acct_launcher_for_name` (`:6664`) → the `claude`/`claude2/3/4` zsh functions → the same
`.claude-220` path. Non-shell reachers of `claude-latest` are 4 infra probe scripts
(`headless-precondition-probe.sh`, `cloud-ceiling-probe.sh`, `deploy-parity-assert.sh`,
`growth-coverage.conf`) and zero hooks.

**⇒ `~/bin/claude-latest` contributes 0 ms to the operator's actual cold start today.**

---

## 5. THE LAUNCHER-WRAPPER THAT *IS* ON THE PATH — `cc-close-attrib`

`~/.claude/bin/cc-close-attrib` → `~/Development/claude-infrastructure/bin/cc-close-attrib`
(262 lines). It is the real exec-wrapper for every live session.

```bash
B="$HOME/.claude-220/node_modules/.bin/claude"
for i in $(seq 8); do /usr/bin/time -p "$B" --version; done                                  # J
for i in $(seq 8); do CC_CLOSE_ATTRIB_DISABLED=1 /usr/bin/time -p ~/.claude/bin/cc-close-attrib "$B" --version; done  # K
for i in $(seq 8); do /usr/bin/time -p ~/.claude/bin/cc-close-attrib "$B" --version; done      # L
```
- J raw binary: 0.07 0.08 0.06 0.07 0.06 0.07 0.07 0.07 → median **0.07**
- K kill-switch (plain exec, but pre-gate setup still ran): 0.11 0.11 0.11 0.10 0.10 0.10 0.09 0.10 → median **0.10**
- L full: 0.18 0.14 0.14 0.13 0.14 0.13 0.14 0.14 → median **0.14**

**Total overhead ≈ 70 ms** (L−J), of which **~30 ms** (K−J) is pre-gate setup: `mkdir -p`,
**two `find … -mtime` sweeps over 1,278 close-record files (5.0 M)**, a third `find` on the
version cache, and 3 × `date` forks. The remaining ~40 ms is the procsub probe + `mktemp` +
`mkfifo` + `tee &` + fork/`wait` (+ for `--version` only, the exit-time `write_record` and GC,
which in a real session run at EXIT and do **not** block startup — so the true startup-blocking
figure is between 30 and 70 ms).

Two things it does **right** relative to `claude-latest`:
- its `--version` probe is **BACKGROUNDED** (`&` + `disown`) and additionally skipped while the
  cache is <1 day old — `.ver__Users_chrisren__claude_220_…` mtime Aug 15 23:48, ~15 h ⇒ **skipped
  today**. Cost 0.
- its stderr GC (`ls -1t | tail -n +201`) runs at **EXIT**, not at start, and has **no
  per-file fork**. This is what keeps `~/.claude/logs/stderr` at 41 files.

One thing it repeats: **it also makes the child's fd 2 a non-tty** (a FIFO, by design — see its
header on the load-781 lingering-tee incident):
```
cc-close-attrib FULL         → isatty fd0=True fd1=True fd2=False  fd2 -> NOT A TTY
CC_CLOSE_ATTRIB_DISABLED=1   → isatty fd0=True fd1=True fd2=True   fd2 -> /dev/ttys027
```
So the fd2-is-not-a-tty property is **live on every session today**, via `cc-close-attrib`, not
via `claude-latest`.

---

## 6. PRIOR ART — what holds, what is stale

`R3-shell-latency.md` (measured 2026-08-11) is the relevant one; R4/R5/cc-startup-modals/
RESTART-BRIEF say nothing about this layer (grep for `claude-latest|npm view|update_if_needed`
returns nothing in them).

| R3 claim | verdict today |
|---|---|
| `cc-close-attrib` wrapper overhead ~110 ms, crit path (row 7) | **HOLDS in kind, STALE in magnitude.** R3's own spread was 273-552 wrapped vs 162-633 bare at n=3 — too noisy to separate. Re-measured n=8 both sides: **70 ms** (median 0.14 vs 0.07). |
| R3's per-stage table contains **no** `claude-latest` row | **HOLDS, and independently corroborates §4** — R3 profiled the real chain and the wrapper was not in it. |
| "pre-exec chain ~0.25 s from an ordinary cwd" | **HOLDS** — consistent with my `cc-close-attrib` 70 ms + R3's shell stages. |
| Lead's "`~/bin/claude-latest --version` = 1.50/1.29/1.28 ⇒ ~1.3 s spent before any session begins" | **TIMING REPLICATES, INFERENCE REFUTED.** The 1.3 s is real for that command, but no session runs it (§4). |
| Lead's "`_claude_pinned` ultimately runs `~/bin/claude-latest`" | **STALE/WRONG** (§4, three ways). |

---

## 7. DEAD ENDS / METHOD NOTES

- **python3-per-sample timing harness**: discarded, python startup (~30-50 ms) swamped every
  sub-100 ms stage and reported `bash -c true` at 40 ms and the stderr loop at 234-392 ms
  (vs 124 ms correctly measured). Replaced by N=20 under one `/usr/bin/time -p`.
- **`script -q /dev/null`** for the pty probe: fails in the Bash tool
  (`tcgetattr/ioctl: Operation not supported on socket`). Used `pty.spawn` instead.
- **Plain-vs-skip A/B on the LIVE `~/bin/claude-latest`**: null result, because the live cache
  file is raced by concurrent operator launches and happened to be in its transient HIT state.
  This is *itself* a finding (§2 bistability) but it means the live A/B is worthless; the
  scratch copy with a controlled cache is the valid instrument.
- **Side effects I caused** (all benign/self-healing, no live config edited): ~14 REFUSED lines
  appended to `~/.claude/.update-versions.log` (rotates at 500, currently 336); the live
  `.npm-version-cache` rewritten (the wrapper rewrites it every launch anyway); a handful of
  close-records under `~/.claude/logs/close-records` (30-day self-GC). Scratch artifacts in
  `/tmp/wraplab/`.

---

## 8. FIX SKETCHES (not applied — read-only session)

1. **Cache the DECISION, not the discovery** — `claude-latest:176`. Write `installed` (or a
   `refused:<version>` sentinel) so the guard can hit while the MANIFEST pin stands. Or simply
   drop the `&& "$cached_version" == "$installed"` clause and rely on `cache_age < CACHE_TTL`
   alone. Removes 0.46-3.2 s from every launch of the stable track. Risk: an update becomes
   visible up to 600 s later — which is already the intended TTL semantics.
2. **Kill the fork-per-file** — `claude-latest:373`. `_p=${_f##*/}; _p=${_p%.log}; _p=${_p##*-}`.
   124 ms → ~2 ms at 41 files; 588 ms → ~5 ms at the 200 cap. Zero behaviour change.
3. **`cc-close-attrib` pre-gate finds** — the two `find … -mtime` sweeps over 1,278 files cost
   ~30 ms on *every* launch to collect files that only accumulate daily. Gate them on a
   once-a-day stamp (the file already uses exactly that idiom for `$VER_CACHE`). Risk: none;
   it is already best-effort and fail-open.
4. **fd2-is-not-a-tty**: NOT a latency item, but it is a correctness risk the crash-forensics
   design should own — piped stderr is block-buffered, so a hard crash can lose the tail the
   capture exists to preserve. Leave alone without a deliberate decision; `cc-close-attrib`'s
   header shows the FIFO spelling was chosen over the procsub for well-measured reasons.

