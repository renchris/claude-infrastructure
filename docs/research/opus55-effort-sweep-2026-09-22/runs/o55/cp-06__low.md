Four defects found.

### 1. A failed or skipped checkpoint is recorded as a successful one

- **What:** `checkpoint_preserve` writes a success `checkpoint` IDL record for every outcome except rc 124. The DEAD page then always says "worktree checkpoint-preserved".
- **Where:**
  - L313: `CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?`
  - L321: `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - L408: `checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- **Why it is wrong:**
  - If `teammate-checkpoint.sh` is not on PATH (likely under launchd's minimal PATH), the `command -v` guard skips the call and `rc` stays 0.
  - If the script exits with any non-124 error (for example rc 1), the code still falls through to the success path.
  - In both cases the IDL records a checkpoint and the operator is told the worktree was preserved, but nothing was preserved. This is a failure reported as a success.

### 2. The permission-beacon "owner dead" reap uses bare `kill -0`, so a recycled pid keeps a dead session's beacon paging

- **What:** REAP 1 decides whether the owning session is alive with `kill -0`. The file itself documents that `kill -0` misreads a recycled pid as the original session (the reason `pid_alive_owner` exists).
- **Where:** L469: `if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
- **Why it is wrong:**
  - Suppose the session died without SessionEnd and its pid was reused by any other process.
  - The beacon is not reaped. It keeps producing PERMISSION-PENDING IDL records and findings every sweep for a prompt nobody can answer.
  - This continues until `PERMPEND_HORIZON_S` (24h).
  - The guard does not cover the recycled-pid class it claims to handle ("owning session provably DEAD").

### 3. The transcript path mangling only replaces `/` and `.`, so the warm-transcript exemption misses many cwds

- **What:** `transcript_age` builds the projects slug by replacing only `/` and `.` with `-`.
- **Where:** L373: `slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`
- **Why it is wrong:**
  - Claude Code's projects-dir mangling also replaces other non-alphanumeric characters, such as `_` and spaces.
  - Take a cwd like `.../doc_classifier`, a repo this file itself names. The computed path does not exist, so the function returns the 999999999 "cold" sentinel.
  - As a result, a live session with a warm transcript still gets STALL? pages and escalations. The exemption is silently skipped for exactly those repos.

### 4. If the `date` conversion fails, the `find` reference falls back to 1970, which makes every re-read "fresh"

- **What:** When `date -r "$since"` fails, the reference file is touched to the epoch (1970).
- **Where:** L270: `touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`
- **Why it is wrong:**
  - `date -r` fails on GNU `date`, where `-r` means reference *file*, or on a malformed `since`.
  - Every file in the tree is then newer than the reference, so `find` always hits and the verdict is `fresh`.
  - A genuinely dark or hung lead is then always voided and never escalated. The comment at L262 describes this same trap, reached here through the fallback instead of through BSD find.
