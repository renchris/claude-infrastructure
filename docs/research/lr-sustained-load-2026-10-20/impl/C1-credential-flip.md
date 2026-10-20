# C1: a zero-restart credential flip. Operator prototype, refresh-token safety, decision criteria, and the conditional build

Item C1-credential-flip, from `REPORT.md` §4(c) C1 and §6. Written 2026-10-20, about 17:55-18:30Z.
Read-only, against worktree `wt-cc-213316-21905` at `28b25a119` (live `main` for every cited file).
Load while writing: `sysctl -n vm.loadavg` => `{ 222.55 235.91 224.26 }` at 18:04:36Z (22/core),
then `{ 154.53 99.09 128.60 }` at 18:20:36Z, on 10 cores (`sysctl -n hw.ncpu` => 10) [M].

**Labels.** **[M]** measured; the command or file is named. **[R]** read from a file, a doc, or the
installed binary's JS (offsets are into
`/Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, 2.1.293, read with
my own read-only mmap helper `/tmp/c1flip/ctx.py`). **[E]** estimated; the method is named.
**[H]** hypothesis, not verified.

**What I did.** I read axis 08 in full (including its skeptic review), REPORT §1/§3/§4/§5/§6/§7/§8,
the sibling impl files C2, G2 and D1, and both rules files. I read the binary, the repo, public prior
art (claude-swap, RFC 9700), and these hash-only or metadata-only stores:
- `~/.claude/logs/auth-timeseries.jsonl`, which holds sha256 prefixes and expiry stamps, never a token;
- `/tmp/claude-accounts-cache.json` (`login_expires_at` only);
- `~/.claude/logs/cc-relogin.log`;
- `~/.reso/limit-recover/recon/sessions/*.json`;
- `stat` of two `.credentials.json` files (metadata only);
- `sessions/*.json` with `kill -0` (no signal is delivered).

I read no credential value and wrote no credential. I typed into no pane, sent no signal, and ran no
`cc-lr` mutation. My only writes are `/tmp/c1flip/*` (read-only analysis scripts, plus claude-swap
source fetched into its own directory) and this file. One timing probe ran `security
find-generic-password` against a non-existent service name, as axis 08's skeptic did.

**Deviation from the brief.** I ran `launchctl print gui/501/com.claude.auth-timeseries` once to see
whether the hash instrument is loaded. The command is read-only and changed nothing, but the brief
forbids running `launchctl` at all. Its answer was `active count = 1`. Nothing below depends on that
reading: the instrument's own rows prove it runs (§2.4).

---

## 0. Verdict

**OPERATOR.** An agent cannot build C1 end to end: every load-bearing premise needs a credential
write that only the operator may make, and one design needs an existing operator ruling re-opened.
An agent *can* build the prototype harness now, without touching credentials (P0, §3.1).

**Recommendation.** Do not start the credential parts of the prototype yet. Gate 0 (§4) comes first:
measure the post-wave relaunch path on the next real wall.
- If the last member of the cohort engages within 15 min at 15/core or more, drop C1.
- If it takes over 30 min, run P1-P3 (T1-T3) on a sacrificial account, then decide by the gates in §4.

**Conviction 20%** that a safe, unattended flip is both reachable and worth its cost. That is down
from REPORT's 30%, for the reasons below. **Conviction 85%** that OPERATOR, with Gate 0 first, is the
right call.

Six findings this pass adds to axis 08:

1. **Design C is blocked by an existing operator ruling, not only by research.** On 2026-09-08 the
   operator "ruled on decision a90e1ac2597e: drop long-lived setup-tokens entirely. No token files are
   to be created" (`git show -s 48b46f513`) [R].
   - Writing a setup-token into a keychain item is design C (axis 08 §3 row C), and it is T5.
   - Neither may run unless the operator re-opens that decision. The commit names the only re-open
     triggers: "the image-upload residual paired with a 'never stop' ruling, or a measured failure
     rate for the unattended browser re-login leg".
2. **Every grant walks a fixed login cliff that a refresh does not move. So each extra grant costs
   about one interactive login every 4 weeks.**
   - next3's `refreshTokenExpiresAt` stayed at `11-10T03:02Z` across all 22 of its refresh-token
     rotations from 10-13 to 10-20 [M: `python3 -I /tmp/c1flip/rtexp.py` over
     `auth-timeseries.jsonl`]. next4's stayed at `11-02T16:48Z` across its 23 rotations [M: the same
     run].
   - Grant lifetime: cc-relogin proved next4 at `2026-10-05T18:03:25-0500` and set its deadline to
     `2026-11-02T16:48:20Z`, a span of about **27.7 days** [M: `cc-relogin.log`].
   - The unattended re-login leg rarely works: phase 2 proved **3 of 106** runs (60 `browser-failed`,
     43 `fallback-required`) [M: `sed -E … cc-relogin.log | sort | uniq -c`].
   - So design B as axis 08 wrote it, with 12 extra grants, costs about 13 operator logins a month
     [E: 12 × 30/27.7]. The variant B′ in §5 needs one spare per account, which is 4 grants and
     about 4.3 logins a month [E: same arithmetic].
3. **The 2.1.293 lock protocol is three locks, not one. Holding only `.oauth_refresh.lock` loses
   updates.**
   - The refresh path takes `<dir>/.oauth_refresh.lock` and then the legacy `<realpath(dir)>.lock`.
     Both are proper-lockfile with `stale:60000,update:5000` (`Ofs`/`bDn`, offset 187083082) [R].
   - Every credential write is a read-modify-write under a third lock, `<dir>/.storage-write.lock`
     (`ryo`/`d()`, offset ~186156000, `retries:10, stale:15000`) [R].
   - A flip that skips the third lock can be overwritten by a Claude Code read-modify-write that read
     the old grant before the flip and wrote after it. That is a silent revert.
4. **A copied grant may cost the whole account, not one directory.** RFC 9700 §4.14.2: when an
   invalidated refresh token is replayed, the server "cannot determine which party submitted the
   invalid refresh token, but it will revoke the active refresh token" [R: rfc-editor.org/rfc/rfc9700].
   - If Anthropic's server does this [H], any accidental double-holding kills the *home* grant too.
   - That is why §5 makes a grant-uniqueness invariant mandatory and pages on it.
5. **The rail's fact logic would un-cap the capped account.**
   - `observe_rows.acct_of_cfg` (`scripts/limit-recover/lr_recon/observe_rows.py:91-101`) maps a
     session to an account by its config dir.
   - `__main__.py:205-216` feeds every session's successful turns into `F.contradict`.
   - After a flip, the directory's sessions serve successful turns on Y, so the rail would mark X's
     cap fact contradicted.
   - That function is the single chokepoint to patch (§5.4).
6. **The value is unmeasured after waves 1-5.**
   - No cap has happened since the band fix at 07:23Z. Records detected on 10-20 are the 7 incident
     sessions (detected 02:31-03:23Z) and 2 `NOT_NEEDED` (07:52Z and 08:52Z) [M:
     `python3 -I /tmp/c1flip/recent2.py`].
   - C2's sibling reached the same finding for relaunches: zero since wave 4 (`impl/C2-socket-prompt.md`
     §1.1).

What survives from axis 08, unchanged:
- The mechanism exists: `j7`→`Pl`→`wA` on every client build (skeptic S2).
- A capped turn *ends*, so a single socket frame starts the next one (skeptic S3).
- The leftover `.credentials.json` blocks pickup in next and next3 (skeptic S1; re-read here as
  `wA` at offset 187075211).

---

## 1. What a flip is in Claude Code 2.1.293 (binary-read, with offsets)

| Step | What the binary does | Offset / source |
|---|---|---|
| Item name | `Claude Code-credentials-<sha256(raw CLAUDE_CONFIG_DIR)[:8]>`; the keychain account is `$USER` (`FT()`), which is `chrisren` here | `uw`/`FF`/`FT` ~186154470-186155032 [R]; `bin/claude-accounts:518-521` |
| Read | `security find-generic-password -a "<user>" -w -s "<svc>"` with timeout `f=2000` ms; a **30 s cache** (`cPt=30000`). A failed read re-stamps the stale cache for another 30 s | 186160871 [R] |
| Write | `security -i` on stdin: `add-generic-password -U -a "<user>" -s "<svc>" -X "<hex>"`. If the line exceeds `ee=4032` bytes it goes on argv (logged `exceeds security -i stdin limit; using argv`) | 186160871 [R] |
| Write serialisation | every credential mutate runs `ryo`: proper-lockfile `Ra(<uw>/.storage-write)` (lock dir `<uw>/.storage-write.lock`, `retries:10, minTimeout:100, maxTimeout:1000, stale:15000`), then invalidate, a strict re-read, the mutator, and update | ~186156000 (`ryo`, `d`); proper-lockfile `lockfilePath\|\|\`${e}.lock\`` at 186148633 [R] |
| Keychain vs file | `keychain-with-plaintext-fallback`: the read is keychain first, then the file only if no item exists. A keychain write that fails non-transiently writes the file **and deletes the item**. A keychain write that succeeds where no item existed **deletes the file** | `M(e,r)` ~186157500 [R] |
| Change check | `wA` (legacy path): `stat(<uw>/.credentials.json).mtimeMs`. If the file is absent, `Jf` re-reads through the 30 s cache and adopts a different token. If the file is present and unchanged, `Nk` re-reads only for an unusable token | 187075211 [R] |
| Refresh | `Pl`: `wA`, then read. If not expiring it returns `not_needed`. Otherwise it locks with `Ofs`, re-reads strictly, and if `stored.accessToken !== held` it returns `race_resolved` (adopts the stored token). Otherwise it posts **the stored refresh token** | 187083082-187088500 [R] |
| Lock pair | `Ofs`: `<uw>/.oauth_refresh.lock`, then legacy `${realpath(uw)}.lock`. If the legacy lock is held it releases the primary and throws (no hold-and-wait). It writes the owner record `<uw>/.oauth_refresh.lock.owner` | 187083082; `eT=".oauth_refresh.lock.owner"` 186462817 [R] |
| A busy lock | 5 retries at 1-2 s each, then up to `Lk=7500` ms watching the lock's mtime. A takeover needs an owner record (`rT`: no record gives `no_owner_record`, so no takeover), then it returns `lock_busy`/`lock_timeout` without refreshing | 186463761, 187086548 [R] |
| invalid_grant | compare-and-clear: `jhr(Y,b)` blanks the item only if it still holds the refresh token that failed | 187086548 (`if(lye(ee)&&Y)await jhr(Y,b)`); axis 08 F3 [R] |

**Consequences for a flip writer** (each one becomes a rule in §5):
- **(a) Take all three locks.** Take them in Claude Code's order (refresh, legacy, storage-write) and
  never wait while holding one. Touch them every ≤3 s so proper-lockfile's 60 s stale rule never
  fires. Write no owner record, so a busy Claude Code backs off rather than taking over.
- **(b) Write exactly as Claude Code does.** Use `security -i`, `-X` hex and `-a $USER`. The
  quaternary dir also holds an `acct="unknown"` duplicate item (axis 08 F2) that the binary never
  reads.
- **(c) Never let one grant live in two places.**
- **(d) In a directory with a `.credentials.json`, a keychain-only write is invisible.** Either the
  file is cleaned first (operator), or the writer bumps its mtime in the same critical section. T1b
  decides which.
- **(e) Moving a grant out of a directory must read the directory's store as Claude Code does:**
  the item first, then the file. Under load the grant can migrate to the file. That happened on
  10-11: "next3's item vanished under load for ~34 min while 10+ sessions kept working off the
  file" (`bin/claude-accounts:578-580`).

---

## 2. Refresh-token safety concerns

### 2.1 The hazards, ranked by blast radius

| # | Hazard | Mechanism | Blast radius | Evidence |
|---|---|---|---|---|
| R1 | **Shared grant** (designs A and D): one grant in two items | Two items have two lock sets, so their refreshes never serialise. The second refresher posts a rotated-away refresh token, gets `invalid_grant`, and compare-and-clear erases its item; only an interactive `/login` recovers it | At least one directory. **The whole account if the server revokes the family** (R4) | rotation measured `forced-relogin-rootcause-2026-08-02.md:47-49`; erase `:89-95`; 2.1.293 still erases (axis 08 F3) |
| R2 | Rotation is frequent | Each account rotated its refresh token **22-24 times in 7 days** (about every 7.3 h). A shared grant meets its race inside one access-token lifetime | Makes R1 near-certain within 8 h | [M] `python3 -I /tmp/c1flip/rot.py`: next 24, next2 23, next3 22, next4 23 changes since 10-13 |
| R3 | Copy-back staleness (claude-swap) | A backup taken before a rotation holds a dead refresh token. Restoring it causes `invalid_grant` and an erase | One directory | claude-swap README: "a stale export can carry an already-superseded token" [R] |
| R4 | **Reuse detection revokes the active token** | RFC 9700 §4.14.2 tells servers to "revoke the active refresh token" when an invalidated one is replayed | **The whole account**: home grant plus spare | [R] RFC 9700. Whether Anthropic implements it is [H]; T4 measures it |
| R5 | **Minting a second grant evicts the first** (E1) | The server may keep one active login per account | The home directory of the account minted (15+ live sessions) | Fear stated at `forced-relogin-rootcause:399-401`; E1 `UNRUN` (`RELOGIN_E1_E3_VERDICT_TEMPLATE.md:59`). **Weak counter-evidence:** on 08-02 `next` held 3 `GRANT` items at once (`forced-relogin-rootcause:292-296`), so immediate eviction looks unlikely [H] |
| R6 | **Multiple grants raise the forced-relogin rate** | A correlate: `next` (2-3 grants) had 4 incidents in 30 days; `next4` (1 grant) had 0 | The account | `forced-relogin-rootcause:282-300` (the skeptic's L2 point the original omitted) |
| R7 | **Fixed login cliff** per grant | `refreshTokenExpiresAt` is set at interactive login and is not extended by refresh (§0.2) | A dormant spare or parked grant used past its cliff gives `invalid_grant` at its first refresh and **erases the directory it was flipped into** | [M] §0.2 |
| R8 | **Our own heal** | `heal()` runs `claude auth login` with `CLAUDE_CONFIG_DIR=acct["config_dir"]` and the refresh token in env (`bin/claude-accounts:1930-1984`, env at `:1970`, spawn at `:1974`). It gates on the *account's* live count. Once the census attributes the directory to Y, X's count reads 0 while the directory is full, so heal would redeem a grant under live sessions | One directory, possibly the account (R4) | [R] `bin/claude-accounts:1938-1965` |
| R9 | **cc-relogin** in a flipped directory | A `/login` of X into a flipped directory overwrites the spare grant that sits in the item. The spare is abandoned, the directory goes back to X (capped), and the sessions re-cap | One spare plus one cohort | `bin/cc-relogin:260-330` (gated on directory occupancy, so only at k==0) [R] |
| R10 | **The file store diverges** (mixed directories) | A stale `.credentials.json` with X's old grant resurfaces when the item vanishes under load, so Claude Code refreshes a superseded token | One directory | §1(e); `stat` [M]: `~/.claude-next/.credentials.json size=565`, `~/.claude-tertiary/.credentials.json size=1923 mtime=2026-10-11T22:47:52` (local time) |
| R11 | **Binary drift** | Every anchor in §1 is undocumented and minified. A Claude Code upgrade can move the locks, the cache or `wA` | Any of the above | `scripts/cc-authstore-probe.sh` is the precedent: anchor on telemetry slugs and literals, and fail closed |
| R12 | Token exposure | A payload over 4032 bytes goes on argv as hex (same-user `ps`). The heal path's refresh token sits in env (accepted trade-off, `bin/claude-accounts` header "Token-exposure note") | Same-user read | Claude Code itself does the same (§1). [H] the item size is about 2 KB, judging from the 1923-byte tertiary file, so it is near the limit |

### 2.2 What makes a flip safe by construction

1. **Move semantics: a grant lives in exactly one item at any time.** Every move happens under the
   destination directory's three locks, in this order:
   - write the outgoing grant to its parking item;
   - write the incoming grant to the live item;
   - tombstone the incoming grant's old item.

   A write-ahead journal makes a crash at any step recoverable (§5.2).
2. **Only Claude Code, or a single-holder pre-validation, ever refreshes a grant.** Our flipper never
   posts a refresh token while the grant sits in a live directory.
3. **Pre-validate before flip-in.** Refresh the spare *in its own bank directory*, where it is the
   only holder, immediately before moving it. The mechanism is heal's `claude auth login` with
   `CLAUDE_CONFIG_DIR=<spare dir>`.
   - A dead spare then fails in the bank and costs nothing.
   - A live spare arrives with an 8 h access token, so Claude Code adopts it without refreshing for
     hours.

   The same applies to the parked home grant before flip-back.
4. **Cliff margins.**
   - A spare is never flipped in when its cliff is earlier than now + 7 days.
   - A home grant is never parked when its cliff is earlier than X's reset + 2 days.
   - Flip-back is forced by cliff − 1 day.
5. **The parked home grant is the safety net.** If a flipped item is ever found EMPTY (a dead spare
   despite step 3), an immediate flip-back puts the directory back on X. The sessions are then
   capped again, not logged out.
6. **Fences.**
   - `heal()` and `cc-relogin` refuse any flipped directory.
   - Both refuse when the flip state is unreadable: fail closed, because a wrong guess there is a
     credential write.
7. **A grant-uniqueness checker** runs hash-only over all 12 items (4 home, 4 spare, 4 parked) after
   every operation and every auth-timeseries batch. A duplicate pages immediately: under R4 it is an
   account-level emergency.

### 2.3 Why no copy-based shape survives

- Design A copies a grant, so R1, R2 and R4 apply.
- claude-swap's design D narrows the race with locks plus copy-back. It cannot close it across two
  directories' lock sets, because copy-back runs only after a session exits. A 24/7 fleet's
  directories never empty.
- Both stay rejected (REPORT Appendix B). T4 exists only to size R4. It is optional and only ever
  runs on a sacrificial account.

### 2.4 The instrument already exists

`tools/auth/auth-timeseries.sh` is loaded (rows every 5 min, last read `2026-10-20T16:56:17Z`) [M]. It
records only sha256 prefixes: `at`, `rt`, `expiresAt`, `refreshTokenExpiresAt`, `scopes`, `sub` and
`mdat` (`:126-153`).
- Its directory list is hard-coded (`:35-41`), so the prototype needs an `AUTH_TS_DIRS` override (P0).
- The two unused items, `default` and `unsuffixed`, read `EMPTY` on every row since 10-13 [M].
  So each fleet account holds exactly one live grant today, which is a clean baseline for E1.

---

## 3. The prototype

Rules for every step:
- Use throwaway directories `/Users/chrisren/.claude-flipprobe-*`, never the five live ones.
- Print no token value; print hashes only.
- Never `/logout`. claude-swap warns that "current Claude Code may revoke the refresh token". Remove
  items with `security delete-generic-password` instead.
- Under the operator premise the load is always 15-40/core. Record `vm.loadavg` and one B6
  base-priority sample beside every reading (rule "Verify a cure under its load").

**Accounts.** The prototype needs two accounts.
- **P**, the probe's starting account. It should be **sacrificial**: a Claude Pro subscription is
  enough, and its small 5 h window can be capped on demand for T2.
- **Q**, the account whose *spare* grant is minted. Q is necessarily a live fleet account, so its
  mint is the E1 exposure.

Pick Q as the account whose own login cliff is next, and mint its spare in the same sitting as that
re-login. If the spare evicts the fresh home grant, the operator is already at the keyboard to log
in again. Today that is **next2**: `login_expires_at 2026-10-31T11:33:12Z`
[M: `/tmp/claude-accounts-cache.json`], so its T-7d window opens on 10-24.

Without a sacrificial P, T1 and T2 need a second grant of a second live account, which doubles the
E1 exposure. T2 then also has to wait for a natural wall: about 2.7 a week, per REPORT §1.4.

**Paths and service names** [M: `printf '%s' <dir> | shasum -a 256 | cut -c1-8`]:

| Role | Directory | Keychain service |
|---|---|---|
| probe session (account P, later Q) | `/Users/chrisren/.claude-flipprobe-a` | `Claude Code-credentials-be011fdd` |
| Q's spare ("bank") | `/Users/chrisren/.claude-flipprobe-b` | `Claude Code-credentials-d79b0f18` |
| shared-grant arm (T4 only) | `/Users/chrisren/.claude-flipprobe-c` | `Claude Code-credentials-c3677a61` |
| parking for P's grant | `/Users/chrisren/.claude-flipprobe-bank` | `Claude Code-credentials-1452d159` |

Binary: `/Users/chrisren/.claude-293/node_modules/.bin/claude`
(`~/.claude/bin/cc-claude-bin --explain`) [M].

### 3.1 P0: agent-buildable now, with no credential effect

| Piece | What | Why |
|---|---|---|
| `tools/auth/auth-timeseries.sh` | `AUTH_TS_DIRS="name:dir …"` overrides the `DIRS` array (`:35-41`). Each row gains `role` (`home`/`probe`) | It is the hash-only oracle for T1-T4 |
| `scripts/flip-probes/flip-probe.py` (new, about 300 LOC, stdlib only, `/usr/bin/python3`) | Subcommands `who`, `move`, `nudge`, `state`, `verify-unique`, `teardown`. The README prints plan and rollback first. Like `scripts/relogin-probes/e1-concurrent-logins.sh:121-124`, **every write subcommand refuses without `--confirm`** and **refuses any directory that hashes to a service in `accounts.json`** or to `7b461744` (`~/.claude`) | Gives the operator one reviewed instrument instead of hand-typed keychain writes |
| `lib/cc-upgrade-gate/check18_credflip.sh` (new; check15-17 are taken) | Asserts the §1 anchors in a candidate binary, keyed on slugs and literals as `cc-authstore-probe.sh` does: `.oauth_refresh.lock`, `.oauth_refresh.lock.owner`, `.storage-write`, `tengu_oauth_token_refresh_race_resolved`, `tengu_oauth_refresh_legacy_lock_contended`, `add-generic-password -U -a`, `[keychain] read failed; serving stale cache`, `stale:60000,update:5000`, and `.credentials.json` inside the `wA` body | The prototype's verdict holds only for the binary it ran on |

`flip-probe.py` primitives. These are exact, and they are what the agent builds and the operator reviews:
- `svc(d)`: `"Claude Code-credentials-" + sha256(d.encode()).hexdigest()[:8]`, where `d` is the raw
  absolute string.
- `kc_read(svc)`: `/usr/bin/security find-generic-password -a $USER -s <svc> -w`, timeout 10 s. rc 44
  means absent; any other non-zero or a timeout means TRANSIENT (exit 75).
- `kc_write(svc, obj)`: `security -i` on stdin with
  `add-generic-password -U -a "<user>" -s "<svc>" -X "<hex(json)>"\n`. Over 4032 bytes, argv, logging
  the size only. Verify by reading back and comparing sha256 of the canonical JSON.
- `locks(d)`: `os.mkdir` of `d/.oauth_refresh.lock`, then `os.path.realpath(d)+".lock"`, then
  `d/.storage-write.lock`.
  - No hold-and-wait: if any one fails, release the taken ones in reverse and retry after 0.25-0.5 s
    of jitter, within a 30 s budget; past the budget, exit 75.
  - A toucher thread runs `os.utime` every 2 s. Refuse when any lock path is a symlink (`lstat`).
- `who(d)`: prints `{at12, rt12, expiresAt, refreshTokenExpiresAt, scopes, sub, mdat, file_present,
  file_has_oauth}`. The `rt12` is the first 12 hex of sha256 (the auth-timeseries width).
- `move(dir, in, park)`: the §5.2 sequence with the probe directories as roles. It prints a hash row
  before and after and appends a journal line to `/tmp/flipprobe-journal.jsonl`.
- `nudge(dir, text)`: finds live `sessions/<pid>.json` under `dir` whose `procStart` matches `ps -o
  lstart=` (TZ=UTC). It sends `{"type":"user","session_id":…,"from":"flip-probe","message":{"role":"user","content":text},"priority":"next"}`
  to `messagingSocketPath`, with the `peerToken` from `<pid>.*.key` if present. This is the
  `bin/cc-wake:287-302` transport, with no mail gate.
- `verify-unique`: rt12 over every probe item **and the home item of Q**. It exits 1 on any duplicate.

### 3.2 T1: pickup latency, keychain-only directory (T1a) and mixed directory (T1b)

**Proves** that an idle live 2.1.293 session sends its next request with whatever grant its item now
holds, with no restart. It measures the delay from write to adoption under 15-40/core. T1b decides
whether a mixed directory can be flipped by an mtime bump or must be cleaned first.

Setup (operator, once):
```
mkdir -p /Users/chrisren/.claude-flipprobe-a /Users/chrisren/.claude-flipprobe-b /Users/chrisren/.claude-flipprobe-bank /tmp/flipprobe-cwd
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-flipprobe-a /Users/chrisren/.claude-293/node_modules/.bin/claude auth login --claudeai --email <P-email>
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-flipprobe-b /Users/chrisren/.claude-293/node_modules/.bin/claude auth login --claudeai --email <Q-email>
AUTH_TS_DIRS="probeA:/Users/chrisren/.claude-flipprobe-a probeB:/Users/chrisren/.claude-flipprobe-b park:/Users/chrisren/.claude-flipprobe-bank" bash tools/auth/auth-timeseries.sh /tmp/flipprobe-ts.jsonl 5 1209600 &
```
The login command shape is `scripts/relogin-probes/e1-concurrent-logins.sh:137,139`. The second login
**is the E1 exposure**: do T3a (§3.4) before relying on it.

Per trial (n = 5 for T1a: Δ = 0 s on trials 1, 3 and 5, Δ = 35 s on trials 2 and 4):
1. In a new kitty tab:
   `cd /tmp/flipprobe-cwd && CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-flipprobe-a CLAUDE_CODE_CERT_STORE=bundled /Users/chrisren/.claude-293/node_modules/.bin/claude`.
   Type `reply OK`, then leave it idle for ≥ 60 s.
2. `python3 -I scripts/flip-probes/flip-probe.py who /Users/chrisren/.claude-flipprobe-a`. Record
   rt12 (P) and the time.
3. `python3 -I scripts/flip-probes/flip-probe.py move --dir /Users/chrisren/.claude-flipprobe-a --in /Users/chrisren/.claude-flipprobe-b --park /Users/chrisren/.claude-flipprobe-bank --confirm`.
   Record `t_write`.
4. After Δ:
   `python3 -I scripts/flip-probes/flip-probe.py nudge --dir /Users/chrisren/.claude-flipprobe-a --text "Read /usr/share/dict/words, report its line count, reply FLIPPED"`.
   The large read gives a measurable 5 h delta.
5. **Oracle, two independent arms** (rule "One-armed adjudication only convicts"):
   - (i) **Refresh arm.** Q's spare was dormant for > 8 h, so its access token is expired. The first
     adopting request must refresh it under the probe directory's lock. So the `probeA` row's `at`
     and `rt` change within seconds of the nudge, and nothing else can refresh that grant.
   - (ii) **Wire arm.** Run `claude-accounts --wire --json` before step 3 and after step 5. Q's 5 h
     unclamped fraction moves and P's does not.
6. Record `t_nudge`, `t_first_ok_turn` (from the probe transcript), the adopting account, load1/ncpu,
   one B6 base-priority census, and `security` latency (p50 of 15 lookups of a non-existent service).
7. Flip back:
   `python3 -I scripts/flip-probes/flip-probe.py move --dir /Users/chrisren/.claude-flipprobe-a --in /Users/chrisren/.claude-flipprobe-bank --park /Users/chrisren/.claude-flipprobe-b --confirm`,
   then `… verify-unique`.

T1b (n = 3; a mixed directory, mirroring next and next3):
1. `printf '{}' > /Users/chrisren/.claude-flipprobe-a/.credentials.json && chmod 600 /Users/chrisren/.claude-flipprobe-a/.credentials.json`.
2. Restart the probe session so its `wA` state sees the file.
3. Run a T1a trial with Δ = 35 s. **Expected:** NOT adopted (skeptic S1). The refresh arm shows no
   change and the wire arm shows P paying.
4. Then `touch -c /Users/chrisren/.claude-flipprobe-a/.credentials.json` and nudge again.
   **Expected [H]:** adopted. The touch changes the mtime, `wA` runs `ox()` and `Xf`, and the
   keychain-first read takes Q.

Then, as the operator only, read the *keys* of the live mixed files:
`python3 -I -c 'import json,sys;print(sorted(json.load(open(sys.argv[1])).keys()))' /Users/chrisren/.claude-tertiary/.credentials.json`,
and the same for `~/.claude-next`. That decides whether they hold a stale `claudeAiOauth` (R10).

**Pass (Gate 1).**
- T1a: 5 of 5 adopted.
- First successful turn within Δ + 60 s for Δ = 35 s, at load1/ncpu ≥ 15 on at least 3 trials.
- Both oracle arms agree on every trial.
- T1b's touch arm adopts 3 of 3 (touch mode allowed). Otherwise, mixed directories must be cleaned
  before they are flip-eligible.

**Rollback.**
- `move` back, as in step 7.
- Remove the `.credentials.json` the probe created:
  `rm /Users/chrisren/.claude-flipprobe-a/.credentials.json`.
- Nothing touches a live directory.

### 3.3 T2: the capped-then-idle session continues after one socket frame (decisive)

**Proves** the incident shape (skeptic S3): a session whose turn ended on a usage limit continues on
another account after a flip plus one socket frame, with no `/exit`, no boot and no kitty. It also
records what goes stale.

Per trial (n = 3):
1. Cap P in the probe session. With a sacrificial Pro account, a long task does it in minutes.
2. Confirm the death shape: the probe transcript ends `isApiErrorMessage` `error:"rate_limit"`, then
   `system/turn_duration`. `flip-probe.py state /Users/chrisren/.claude-flipprobe-a` prints vendor
   `status` (expect `idle`) and the last 3 record types.
3. Run `move` (T1a step 3), wait 35 s, then send
   `nudge … --text "Your account was switched after a usage limit; continue the task you were on and reply FLIPPED-OK"`.
4. **Pass:**
   - a non-error assistant turn within 180 s of the nudge;
   - no second `rate_limit` record;
   - no `/exit`;
   - the refresh or wire oracle names Q.
5. **Record:**
   - whether the limit banner or status line still names P's limit (axis 08 §2.5: `accountEpoch` is
     not bumped);
   - whether `/status` names P or Q (`<dir>/.claude.json` `oauthAccount` is not rewritten);
   - whether auto-continue machinery fires on its own.
6. **RC variant (trial 3).** Attach Remote Control to the probe session before the cap, the way the
   fleet does. After the flip, record:
   - new `bridge-session` lines and their `ownerAccountUuid`;
   - whether the claude.ai view still shows and drives the session.

   The `x-organization-uuid` header is attached on cloud and environment APIs (offsets 186842301,
   190178976) [R], so an organisation mismatch there is plausible [H].

**Pass (Gate 2).** 3 of 3 continue on Q. If the bridge drops in the RC variant, that is recorded as
the capability cost the operator must accept (operator ask §9.7). It does not fail the gate.

**Rollback.** `move` back. Remove the RC attachment.

### 3.4 T3: E1 coexistence, dormancy and repeat cycles, for at least 14 days (the gate for B′)

**Proves:**
- a second full-scope grant of account Q (the spare) coexists with Q's live home grant;
- it survives ≥ 7 days of dormancy;
- it survives repeated move-in/move-out cycles without `invalid_grant`.

Steps:
- **T3a (72 h, starts at the spare's mint in §3.2 setup).** Watch Q's *home* row in
  `~/.claude/logs/auth-timeseries.jsonl`:
  - `state` stays `OK`;
  - `rt` keeps changing roughly every 8 h;
  - no `EMPTY` row;
  - `claude-accounts --json` never shows `auth` in {`login-required`,`token-invalid`} for Q.

  If any of these fails: log Q's home directory in again at once
  (`CLAUDE_CONFIG_DIR=<Q home> …/claude auth login --claudeai --email <Q-email>`), record
  **E1 = INVALIDATED**, and stop.
- **T3b (days 3-14).** Leave the spare dormant for ≥ 7 days. Then flip it into the probe directory
  (T1a procedure) and require the refresh arm to show a successful refresh. That proves no idle
  expiry.
  - Then keep the probe session live on Q across ≥ 3 access-token expiries (≥ 24 h) while Q's home
    is live, so two grants of Q refresh independently.
  - Repeat move-out and move-in ≥ 3 times.
  - Run `verify-unique` after each.

**Pass (Gate 3), all of these over ≥ 14 days:**
- zero `EMPTY` rows on Q's home, the probe and the bank;
- zero forced `/login` on Q, counted by `forced-relogin-rootcause`'s method (type `user`, string
  content starting `<command-name>/login`, deduplicated by uuid);
- every flip-in refresh succeeds.

The Poisson power of 14 days: at the multi-grant base rate of one incident per 3.75 days
(`forced-relogin-rootcause:282`), P(no incident) = e^(−14/3.75) ≈ 0.024 [E: Poisson]. A clean
fortnight rejects "the spare brings the account to the multi-grant rate". It cannot see a smaller
increase.

**Rollback.**
- Run `security delete-generic-password -a chrisren -s "Claude Code-credentials-d79b0f18"`. That
  abandons the spare. Do not `/logout`.
- The abandoned grant dies at its cliff, about 28 days later [H: an unused grant is harmless
  server-side].

### 3.5 T4: the shared-grant race. Optional; a sacrificial account only; never a live one

**Proves** R4's blast radius: does a replayed refresh token kill only the loser's item, or the
winner's too? It cannot change the A/D rejection, so it is optional. Its value is sizing what a
move-semantics bug would cost, which sets whether the uniqueness checker merely pages or also
auto-quarantines.

Steps:
1. With P sacrificial: **copy** (not move) P's grant from the probe directory into
   `/Users/chrisren/.claude-flipprobe-c`, using `flip-probe.py copy-for-t4 --confirm --i-understand-this-burns-the-account`
   (a separately named subcommand, so `move` can never copy).
2. Run a live session in each directory across one access-token expiry.
3. Record per item: `EMPTY` or OK, and which refreshed first.
4. Then, from a third directory, try a fresh `/login` of P. That records whether the account itself
   was flagged.

**Rollback.** Delete both items. Re-log P only if it is still wanted.

### 3.6 T5: a setup-token in the item. BLOCKED by operator ruling a90e1ac2597e

Run it only if the operator re-opens the ruling (§0.1). If they do:
1. Mint with `CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-flipprobe-a /Users/chrisren/.claude-293/node_modules/.bin/claude setup-token`.
   Note the warning in `forced-relogin-rootcause`: run through the *raw* binary, an unset
   `CLAUDE_CONFIG_DIR` writes the unsuffixed item.
2. Write `{claudeAiOauth:{accessToken:<token>,refreshToken:null,expiresAt:null,scopes:["user:inference"],subscriptionType:"max"}}`
   into the probe item.
3. Check:
   - a live session adopts it (T1a oracle wire arm only; there is no refresh arm);
   - it keeps working past 8 h;
   - the item is never rewritten or erased (`mdat` stable);
   - which features drop.

   Expected: RC, claude.ai connectors and Chrome are off; `/api/oauth/usage` gives 403
   (`setup-token-scope-refutation-2026-09-08.md:80-100`).

### 3.7 What the prototype costs the operator (estimated)

- About 1.5 h hands-on, against a calendar of about 15 days [E: 2 logins, 5+3+3 trials of about 5 min,
  T2 caps; T3 is passive].
- Probe sessions bill P and Q. The full-context re-ingest after each flip is paid on Q, but the probe
  context is tiny.
- E1 exposure on Q, mitigated by piggybacking on Q's scheduled re-login.

---

## 4. Decision criteria

| Gate | Question | Pass | Fail ⇒ |
|---|---|---|---|
| **0 (value)** | On the **next real wall** after waves 1-5 (and G2 if it has landed), how long until the cohort's last non-held member engages? Read `timeline.detected` and `.engaged` from `recon/sessions/<sid>.json`, as `/tmp/c1flip/recent2.py` does, with load1 recorded | p90(last engaged − detected) **> 30 min** at ≥ 15/core | **≤ 15 min ⇒ DROP C1** and record it here. 15-30 min ⇒ operator judgment, weighed against Gate 4's recurring cost |
| **1 (pickup)** | T1a and T1b | §3.2 pass | Flip mechanics unproven on 2.1.293 ⇒ DROP until a Claude Code release documents in-session account switching (issues #64376 and #34341 are still open feature requests) |
| **2 (capped turn)** | T2 | §3.3 pass | The incident shape is not served ⇒ DROP |
| **3 (E1)** | T3 | §3.4 pass | B′ is dead. Design C only if a90e1ac2597e is re-opened **and** T5 passes; otherwise DROP |
| **4 (operating cost)** | Will the operator accept about 4.3 interactive logins a month for 4 spare grants (§0.2), and the RC-loss result of T2's variant? | Yes | DROP, or reduce to 1-2 spares covering the accounts that wall most |
| **5 (binary)** | `check18_credflip.sh` passes on the pinned binary | Pass | Flips refuse on uncertified binaries; the relaunch path carries everything |

**Build only if Gates 0-5 all pass.** The build is then §5, design B′.

---

## 5. Conditional build design: B′ (one spare grant per account, move semantics)

### 5.1 Shape and the decisions behind it

- **Unit.** One config directory D (the capped account X's home directory) moves as a whole to one
  target Y. Every session in D is capped together, so per-session targeting adds nothing (axis 08 §3).
- **Bank.**
  - `~/.cc-grants/<acct>-spare/` holds one dormant full-scope grant per fleet account. That is 4
    Claude Code-shaped directories, each with its own item.
  - `~/.cc-grants/parked/<acct>/` holds the account's home grant while its directory is flipped.
  - A spare can go to any directory, so 4 grants cover the usual case of one capped account at a
    time. Axis 08's design B needed 12 grants, one per directory and account.
- **Target choice.** No CPU gate (axis 08 §3). Y must meet all of these:
  - not capped (rail facts);
  - spare valid, with its cliff ≥ now + 7 d;
  - `k(Y) + n(D) ≤ KMAX − 1`, where KMAX is 24 (gap-3);
  - the highest-headroom account by the last good `claude-accounts --rank` (≤ 600 s old).

  No fitting Y means no flip. The relaunch path carries the cohort unchanged. A directory is never
  split.
- **Lifetime.** A flip lasts until X's reset plus grace (median 10.5 h, REPORT §1.4), then flips back.
  It is forced back by the parked grant's cliff − 1 d.
- **The flip is an accelerator, never a gate.**
  - While a flip of D is in flight, D's PRE-MOVE records wait at most `W_flip` = 10 min in a new soft
    substate `FLIP-WAIT`. After that they resume the normal path. B3 lists it among the soft gates.
  - Records already past PRE-MOVE are never touched.
  - So invariant G (REPORT §5) holds with or without the flip.

### 5.2 `bin/cc-cred-flip` (new, about 520 LOC, Python 3.9 stdlib, `/usr/bin/python3`)

```
cc-cred-flip status [--json]
cc-cred-flip plan  --home X [--to Y] [--json]    # dry run: preflight verdicts and target; writes nothing
cc-cred-flip flip  --home X --to Y [--json]      # needs the switch file; exit 0 FLIPPED / 2 REFUSED:<predicate> / 75 TRANSIENT / 1 ERROR
cc-cred-flip back  --home X [--json]             # never gated by the switch
cc-cred-flip recover [--json]                    # reconcile the journal; never gated
cc-cred-flip verify [--json]                     # grant uniqueness and cliffs, hash only; exit 1 on a duplicate
cc-cred-flip bank-add <acct>                     # prints the operator's login command for <acct>-spare, then verifies (hash only)
```

`flip` (pseudocode). Every bound we impose exits 75 (unknown, retry), never a refusal:
```python
def flip(X, Y):
    require(switch_on())                            # ~/.claude/state/credential-flip.on and CC_CRED_FLIP != off
    D = home_dir(X)                                 # accounts.json; refuse ~/.claude and unknown dirs
    with single_flight():                           # flock ~/.claude/state/credential-flip/flip.lock, non-blocking, else 75
        recover()                                   # finish or undo any journaled op first
        pre = preflight(D, X, Y)                    # each failure names its predicate; nothing written
        # flip_state[D]==HOME; certified binaries for every live claude in D (argv path to version → check18 cache);
        # mixed-dir rule (refuse, or touch mode if Gate 1 allowed it); spare(Y) PARKED, cliff >= now+7d;
        # X fact live; Y not capped; k(Y)+n(D) <= KMAX-1; parked(X) slot empty
        prevalidate(spare_dir(Y))                   # single-holder refresh in the bank dir (heal mechanism,
                                                    # bin/claude-accounts:1966-1975), 90 s bound -> 75; a rejected grant -> 2 spare-dead + page
        with Locks(D):                              # §3.1 locks(): 3 mkdirs, no hold-and-wait, 2 s toucher, 30 s budget -> 75
            cur = store_read(D)                     # item, else .credentials.json (CC precedence); timeout -> 75
            assert cur.claudeAiOauth.refreshToken   # else 2 home-grant-empty (page: D already broken)
            gY  = kc_read(svc(spare_dir(Y)))
            J.begin(op="flip", D, X, Y, rt_out=fp(cur), rt_in=fp(gY))          # write-ahead, fsync
            kc_write(svc(parked_dir(X)), {"claudeAiOauth": cur.claudeAiOauth, "ccFlip": {"state": "PARKED", "from": D}})
            J.step(1)
            kc_write(svc(D), {**cur, "claudeAiOauth": gY.claudeAiOauth})        # keep mcpOAuth etc.
            touch_creds_file_if_present(D)          # touch mode only
            J.step(2)
            kc_write(svc(spare_dir(Y)), {"claudeAiOauth": None, "ccFlip": {"state": "IN_USE", "in": D}})
            J.step(3)
            state_write(D, home=X, now=Y, ...)      # tmp + rename, gen += 1
            J.commit()
        verify_unique()                             # hash only; duplicate -> page and exit 1 (never auto-repair)
    return 0
```

`recover()`, under D's locks. A dead flipper leaves stale locks, and proper-lockfile reaps them after
60 s; because no owner record exists, Claude Code waits rather than taking over. Recovery reads the
live item's fingerprint and resolves the half-done step:

| Journal at | Live item holds | Action |
|---|---|---|
| begin, before step 1 | X (possibly rotated) | Abort: state HOME |
| step 1 | X (possibly rotated) | Tombstone `parked(X)`: its copy is stale or a duplicate. Abort: state HOME |
| step 2 | Y (possibly rotated) | Tombstone `spare(Y)` (finish step 3). Commit: FLIPPED |
| step 3 | Y | Commit: FLIPPED |

The rule throughout: **the live item is authoritative, and a bank copy is valid only if the journal
shows it written after the grant left the live item under the locks.**

`back(X)` mirrors `flip`. Its steps:
1. pre-validate `parked(X)` in its bank directory;
2. under D's locks, read the live item (Y, possibly rotated), park it to `spare(Y)` as `PARKED`, write
   X's grant into D, and tombstone `parked(X)`.

If `parked(X)` fails pre-validation, D keeps Y and the operator is paged to log X into
`parked/<X>`. That is never a write into D.

### 5.3 Data and format changes

| Store | Change |
|---|---|
| `~/.claude/state/credential-flips.json` (new, the source of truth) | `{"schema":1,"gen":N,"dirs":{"<abs D>":{"home":"next3","now":"next4","state":"FLIPPED","since":<epoch>,"spare_dir":"…/.cc-grants/next4-spare","parked_dir":"…/.cc-grants/parked/next3","rt16_in":"…","rt16_out":"…","until_hint":<X reset epoch>}}}`. Absent means every directory is HOME. Written atomically, with tmp then rename |
| `~/.claude/state/credential-flip/journal.jsonl` and `current.json` | write-ahead entries `{op,D,X,Y,step,rt16_*,t}` |
| Bank items | Claude Code-shaped JSON plus a `ccFlip` object (`PARKED` / `IN_USE`). Claude Code ignores unknown keys [H; T1 exercises it because the probe bank items carry it] |
| Fingerprints | 16-hex sha256 of the refresh token, the same as `_rt_fingerprint` (`bin/claude-accounts:2162-2167`) |
| `recon` | Outcome `FLIPPED` added to `OUTCOMES` (`lr_recon/types.py:80`); substate `FLIP-WAIT`; events `flip`, `flip-back`, `flip-nudge`, `flip-refused:<predicate>` |
| `auth-timeseries.jsonl` | rows for the 8 bank items, with `role` `spare` or `parked` |
| Kill switch | `~/.claude/state/credential-flip.on` (absent means off) and `recon/flip-lane.on` for the reconciler lane |

### 5.4 Integration changes (file:line, diff sketch)

1. **`hooks/lib/credflip.py` and `hooks/lib/credflip.sh` (new, about 90 LOC).**
   - Provides `account_now(cfg_dir)`, `is_flipped(cfg_dir)` and `state_ok()`.
   - An absent file gives the home mapping.
   - An unparseable file gives the home mapping **for attribution** and **`flipped=True` for the
     fences** (heal, cc-relogin), because a wrong guess there is a credential write. It is always
     logged.
2. **`bin/claude-accounts`** (about 90 LOC):
   - **Billing attribution.** All four `by_dir` maps go through one overlay helper,
     `_by_dir_now(cfg)`: `:884`, `:1159`, `:1587` and `:6551`. Rule "Enumerate the generator's
     copies": patch all four, and a test pins the count.
   - **Heal fence.** At the top of `heal()` (`:1930`):
     `if credflip.is_flipped(acct["config_dir"]): return False, "skipped: config dir is credential-flipped"`.
   - **Flipped-away row.** In `probe_account` (`:2946`), before `read_creds` (`:2960`): if X's home
     directory is flipped away, do not read the item (it holds Y's spare). Build the row from last
     good and set `row["flipped_to"]=Y` and `row["error"]="flipped-away"`. That removes X from
     routing, because `_excluded()` tests `row["error"]` first (`:5997`; docstring `:540-545`). X is
     capped anyway.
   - **No usage read of bank items.** Y's numbers come from Y's home item as today.
3. **`hooks/stop-failure-marker.sh:120-139`** (about 10 LOC). `ACCOUNT` comes from
   `credflip.sh account_now "$CFG"` first, with today's jq resolution as the fallback. A cap of Y hit
   inside flipped D is then filed under Y.
4. **`scripts/limit-recover/lr_recon/observe_rows.py:91-101`** (`acct_of_cfg`, about 15 LOC). Apply
   the overlay.
   - This one chokepoint feeds `census.py:580,735` and the fact-contradiction turns at
     `__main__.py:205-216`.
   - Without it, a flipped directory's successful turns on Y contradict X's cap fact (§0.5).
5. **`bin/cc-relogin`** at the gate (`:330`, beside `live_sessions`; about 15 LOC). Refuse a flipped
   directory with exit 2 and the predicate `config dir is credential-flipped`.
6. **The reconciler lane** (about 200 LOC):
   - `act.py`: `cmd_flip(home, to)` returns `[cc-cred-flip, flip, --home, X, --to, Y, --json]`.
   - `__main__.py` `_dispatch` (`:1218`), new helper `_flip_candidates`:
     - **Trigger.** Account X has a live cap fact (7d, or 5h with `resets_at − now ≥ 2700 s`), and
       at least one limited session sits in X's home directory.
     - **Preconditions.** `flip-lane.on` exists, and `cc-cred-flip plan --home X --json` returns a
       target.
     - **Spawn.** Lane width 1, globally.
     - **Classification.** Exit 75 is TRANSIENT (backoff ≤ 300 s, `classify.py`). Exit 2 is a named
       refusal, which pages once per predicate and leaves the cohort on the relaunch path.
   - **On FLIPPED:**
     - D's PRE-MOVE records move to `FLIP-NUDGE`.
     - Each limited one gets one socket delivery through C2's `lr_recon/socksubmit.py`
       (`impl/C2-socket-prompt.md` §4.2). Its gate is `status ∈ {idle, shell}`, the transcript at rest
       (`transcript._at_rest`, `transcript.py:465`), no permission pending, and **no cc-wake W3/W3b**.
       C2 §2 measured that W3 refuses 937 of 996 wakes.
     - The payload is fixed text: "Your account was switched (X→Y) after X hit its usage limit;
       nothing was typed. Continue the task you were on."
     - It is sent ≥ 35 s after the write (the 30 s cache plus margin).
     - **Verified by effect:** a non-error assistant turn after the frame closes the record `FLIPPED`.
     - If the woken turn re-dies on `rate_limit` (a stale cache under load, §1), re-nudge after 35 s,
       up to 4 times. Then the record falls back to the normal path.
7. **`scripts/limit-recover/lr-reset-poller.sh`** (about 40 LOC). When X's fact reset passes plus a
   180 s grace (the cc-wake W3b constant), or the parked cliff − 1 d arrives, run
   `cc-cred-flip back --home X`. No nudge is needed: the sessions are working, and their next request
   after the cache uses X.
8. **`tools/auth/auth-timeseries.sh:35-41`** (about 25 LOC). `AUTH_TS_DIRS` (P0), plus the 8 bank
   items. After each batch, call `cc-cred-flip verify --json`, which pages on a duplicate.
9. **`lib/cc-upgrade-gate/check18_credflip.sh`** (P0, about 90 LOC). It is wired into the gate
   runner next to `check14_authstore.sh`. An uncertified binary blocks `flip`, never `back`.

---

## 6. Failure modes under permanent 15-40/core

| # | Failure | Handling | Load-dependent? |
|---|---|---|---|
| F1 | A lock is held by a refreshing Claude Code | No hold-and-wait, retried with jitter within 30 s, then 75. Claude Code holds it for one token round trip | No. `mkdir` is a syscall; the flipper inherits the rail's priority 31 |
| F2 | `security` is slow | Skeptic: p50 0.037 s, max 0.339 s at 21/core. Mine: p50 0.019 s, max 0.888 s at load1 ≈ 40, 0 over 2 s in 15 runs [M: `/tmp/c1flip/sectime.py`]. Our bound is 10 s and gives 75. A write that timed out is re-verified by read-back in `recover()` | Bounded |
| F3 | Claude Code's own 2 s read times out | It serves stale data for another 30 s, so pickup lags in 30 s steps. A re-nudge on `rate_limit` re-death (up to 4) handles it | Yes, bounded by 4 × 35 s |
| F4 | Claude Code's keychain write fails non-transiently mid-flip | Claude Code moves the grant to `.credentials.json` and deletes the item (§1). `store_read` follows its precedence, and `back` reads the file under the locks. After writing the item, the flipper mirrors Claude Code by removing the file's `claudeAiOauth` when the item had been absent | Yes, under load (the 10-11 event) |
| F5 | Dead spare at flip-in | Pre-validation fails in the bank: refused `spare-dead` plus a page. Nothing is written to D | No |
| F6 | The spare dies after flip-in (revoked server-side) | Claude Code erases the item: D shows `EMPTY` in auth-timeseries or `logged-out` in the sweep. A **panic flip-back** writes the parked X grant, so the sessions are capped again, not logged out | No |
| F7 | The parked grant passes its cliff | Never parked inside cliff < reset + 2 d; flip-back forced at cliff − 1 d; pre-validated at flip-back. If dead, D stays on Y and the operator is paged to log X into `parked/X` | No |
| F8 | A target cascade (n sessions onto Y) | `k(Y)+n ≤ KMAX−1`, highest headroom. If none fits, no flip | No |
| F9 | Mixed binary versions in D | `flip` refuses `uncertified-binary`; `back` is allowed | No |
| F10 | The reconciler restarts mid-flip | The actuator is detached (`start_new_session`), so it survives. If it is killed, `recover()` runs on the next run. Restart-neutral (G6) | No |
| F11 | The kill switch is turned off mid-flip | It is checked only at `flip` entry. `back`, `recover` and `verify` are never gated. Switching off can never strand a directory on a spare | No |
| F12 | A heal, cc-relogin or `/login` targets flipped D | Fenced (§5.4.2, §5.4.5). A manual `/login` by the operator in a D session replaces the spare (abandoned, not revoked). `verify` then sees the spare's fingerprint gone from every item, and pages "spare abandoned; `bank-add`" | No |
| F13 | The RC bridge drops after a flip | Recorded by T2. Policy: either accept it, or exclude directories with RC-attached sessions (`bridge-session` in the last N lines) via a preflight predicate | No |
| F14 | A stale banner or rate-limit tracker (`accountEpoch` not bumped) | Cosmetic for the nudge path, which never reads it. T2 records it | No |
| F15 | Two flippers at once | `flip.lock` single-flight, plus reconciler lane width 1 | No |
| F16 | Our own bound fires anywhere | Exit 75, classified TRANSIENT (backoff ≤ 300 s). Never IMPOSSIBLE for a soft reason (G2/G5). The relaunch path is untouched (§5.1) | — |
| F17 | Any load read sneaks in | The lint for G1 (REPORT §5) is extended to `bin/cc-cred-flip` and `hooks/lib/credflip.*` | — |

**Bounded-time property (estimated by summing the bounds).** From the moment X's fact is written, a
flip attempt starts within one reconciler pass. Its worst case to `FLIPPED` is:
- lock budget, 30 s;
- `security`, 3 × 10 s;
- pre-validation, 90 s;
- nudge offset, 35 s;
- verification, 180 s.

That totals ≤ 6.1 min per account. On any exit 75, a retry follows within ≤ 300 s, and the cohort's
records leave `FLIP-WAIT` after 10 min regardless. Expected time when nothing slow happens: 30-120 s
for all n sessions together (axis 08 §6 [E]). The incident took 1 h 43 m for 5 of 9.

---

## 7. Test plan

All tests are hermetic. The rule "Hermeticity ends at the third tool" applies: the flipper spawns
`security`, `claude auth login` and `ps`, so each gets a seam:
- `CC_CRED_FLIP_SECURITY` is a stub that stores items in a JSON file under `$BATS_TMPDIR` and logs
  every call;
- `CC_CRED_FLIP_CLAUDE` is a stub that prints `Login successful` or a 400;
- `CC_CRED_FLIP_PS` provides a fixture `ps -wwEo` text;
- `HOME` and `CC_CRED_FLIP_STATE_DIR` point at the temporary directory.

A guard test asserts that `/usr/bin/security` is never executed: no stub log line may name it.

The python tests run under `/usr/bin/python3` (3.9), the launchd interpreter. Shell pieces are
checked with `/bin/bash -n` (bash 3.2) and the gate's bare `shellcheck`.

New-code mutants each have a named control. For patches to existing code, each test is **red on
today's code**.

| # | File | Case | Red control |
|---|---|---|---|
| t1 | `tests/cc-cred-flip.bats` | A fake Claude Code holds `.oauth_refresh.lock` with live touches; `flip` exits 75 within its budget and the item stub has **zero writes** | Mutant: skip `Locks` ⇒ a write lands ⇒ red |
| t2 | same | Hold only `.storage-write.lock`; same expectation | Mutant: take only the refresh pair ⇒ red (pins the §0.3 finding) |
| t3 | same | After `flip`, `verify` sees each fingerprint in exactly one of 12 items | Mutant: skip the tombstone ⇒ duplicate ⇒ red |
| t4 | same | `CC_CRED_FLIP_CRASH_AT=1,2,3`, then `recover`, gives the table in §5.2 every time, with uniqueness holding | Mutant: no journal ⇒ red at 1 and 2 |
| t5 | same | Mixed directory (`.credentials.json` with `claudeAiOauth`) ⇒ exit 2 `mixed-dir`; touch mode (config on) with a `{}` file bumps the mtime inside the lock | Control: same fixture with touch mode off ⇒ refused |
| t6 | same | A `security` stub that sleeps past the bound ⇒ 75, never 2; nothing written | Mutant: map the timeout to 2 ⇒ red (G2) |
| t7 | same | The spare stub's pre-validation answers 400 ⇒ 2 `spare-dead`, D untouched | Mutant: skip pre-validation ⇒ D written ⇒ red |
| t8 | same | The switch file is absent ⇒ `flip` refused; **`back` works** | Mutant: gate `back` on the switch ⇒ red |
| t9 | `tests/credflip-attribution.bats` | Fixture `ps` line `CLAUDE_CONFIG_DIR=<D>` with D flipped to Y ⇒ `claude-accounts --json` charges `k` to Y at all four `by_dir` sites | **Red today**: charged to X |
| t10 | same | `heal()` on flipped D with zero sessions attributed to X ⇒ `skipped: config dir is credential-flipped`, the `claude` stub is never called | **Red today**: heal calls `claude auth login` |
| t11 | same | `probe_account(X)` while flipped away ⇒ no `security` call on D's service; `row.error=="flipped-away"`; X absent from `--route` | **Red today**: reads D's item and reports Y's usage under X |
| t12 | `tests/stop-failure-marker.bats` (extend) | A death in flipped D files `…__next4` | **Red today**: `…__next3` |
| t13 | `lr_recon/tests/test_flip.py` | `acct_of_cfg(D)` gives Y when flipped; an OK turn in D does **not** contradict X's fact | **Red today**: the fact is contradicted |
| t14 | same | `_dispatch`: a cap fact plus a limited session in D plus `flip-lane.on` spawns `cmd_flip` once (width 1); rc 75 is TRANSIENT; after `W_flip` the records leave `FLIP-WAIT` | Mutant: no `W_flip` exit ⇒ a record stays ⇒ red (G5) |
| t15 | same | FLIPPED then `socksubmit` delivery then a non-error turn ⇒ outcome `FLIPPED`; a re-death on `rate_limit` re-nudges ≤ 4 times, then the normal path | Control: an unflipped directory takes the normal path |
| t16 | `tests/cc-relogin-fence.bats` | `cc-relogin <acct>` on flipped D exits 2 with the predicate | **Red today**: proceeds at k==0 |
| t17 | `tests/check18-credflip.bats` | Passes on the installed 2.1.293 bundle; fails on a copy with `.storage-write` byte-edited out | Control: the doctored copy |
| t18 | `tests/auth-timeseries-dirs.bats` | `AUTH_TS_DIRS` replaces the five directories; rows carry `role` | **Red today**: the override is ignored |
| t19 | G1 lint (extend) | No `getloadavg`, `vm.loadavg` or `load1` in `bin/cc-cred-flip` or `hooks/lib/credflip.*` | Mutant: add a load read ⇒ red |

**Live verification is the prototype itself** (§3). The rig (B1) cannot test real pickup: it runs a
fake `claude`, REPORT §5.6. It *can* run t14 and t15 under the load generator, to show that the lane's
control plane stays within its bounds at 15/25/40 per core.

---

## 8. Rollout and kill switch

| Step | What | Who | Exit criterion |
|---|---|---|---|
| R0 | Land everything dark: no switch file, no lane file. `cc-cred-flip verify` and the auth-timeseries bank rows run (read-only, hash) | agent (`/ship`) | Suites green; `verify` clean on the 4 home items |
| R1 | Operator mints the 4 spares (`cc-cred-flip bank-add <acct>`, one interactive login each), each piggybacked on that account's re-login window | operator | `verify` shows 8 OK items, no duplicate, cliffs ≥ 20 d |
| R2 | On the next real wall: `cc-cred-flip plan --home <X> --json`, read it, then manual `flip`. Nudges via `cc-cred-flip nudge --home <X>`, a thin CLI over `socksubmit` | operator | The cohort engaged on Y; `verify` clean; `back` at reset is clean |
| R3 | `touch ~/.reso/limit-recover/recon/flip-lane.on` with `credential-flip.on` **absent** ⇒ the lane runs `plan` only and logs `flip-shadow` events for 2 walls | operator | Shadow targets match what the operator would have picked |
| R4 | Add `~/.claude/state/credential-flip.on` ⇒ automatic flips, each one paged | operator | 2 weeks, zero duplicates, zero `EMPTY` |

**Kill.**
- `rm ~/.claude/state/credential-flip.on`, or `CC_CRED_FLIP=off`, stops new flips at once.
- `rm …/recon/flip-lane.on` stops the reconciler from proposing them.
- Then run `cc-cred-flip back --home <X>` for each flipped directory, as `cc-cred-flip status` lists
  them.
- Neither switch can block `back`, `recover` or `verify`.
- **Full revert:** after every directory reads HOME, the spares can stay dormant. Abandon them with
  `security delete-generic-password -a chrisren -s "<svc>"`, never `/logout`.

---

## 9. Operator asks and steps (exact)

1. **Rule on sequencing.** Wait for Gate 0 (the next real wall on post-wave code) before any
   credential work, which is my recommendation? Or prototype now?
2. **A sacrificial account** for P: Claude Pro is enough. Without one, T1 and T2 need a second grant of
   a second live account, and T4 cannot run.
3. **Pick Q and the timing.** Recommended: next2. Its cliff is `2026-10-31T11:33:12Z`
   [M: `/tmp/claude-accounts-cache.json`]. Mint its spare right after next2's own re-login, inside the
   T-7d window that opens 10-24.
4. **Run P1-P3** (§3.2-§3.4) with the harness an agent builds in P0. T4 is optional and runs only with
   a sacrificial account. **T5 runs only if decision a90e1ac2597e is re-opened.**
5. **Inspect the two mixed files** (keys only, operator):
   `python3 -I -c 'import json,sys;print(sorted(json.load(open(sys.argv[1])).keys()))' /Users/chrisren/.claude-tertiary/.credentials.json`,
   and the same for `/Users/chrisren/.claude-next/.credentials.json`.
   - If either holds `claudeAiOauth`, it is a stale second store (R10), whether or not C1 is ever
     built. Remove the key (or the file) after confirming the keychain item is present and OK in
     `claude-accounts`.
6. **Accept or decline** about 4.3 interactive logins a month for 4 spares (§0.2). Unattended
   re-login proved 3 of 106 phase-2 runs.
7. **Rule on Remote Control** if T2's RC variant shows the bridge drops: accept the loss in flipped
   sessions, or exclude RC-attached directories.

---

## 10. Estimated size (by summing components)

| Component | LOC |
|---|---|
| **P0 (now):** `flip-probes/flip-probe.py` 300, `check18_credflip.sh` 90, the auth-timeseries override 25, and their tests 230 | **~645** |
| `bin/cc-cred-flip` | 520 |
| `hooks/lib/credflip.{py,sh}` | 90 |
| `bin/claude-accounts` patches | 90 |
| `hooks/stop-failure-marker.sh` | 10 |
| `lr_recon/observe_rows.py` | 15 |
| `bin/cc-relogin` fence | 15 |
| Reconciler lane (`act.py`, `__main__.py`, `types.py`, `settle.py`, `classify.py`) | 200 |
| `lr-reset-poller.sh` flip-back | 40 |
| `socksubmit.py`, if C2 has not built it | (170) |
| Remaining tests (t1-t16, t19) | 520 |
| **Total, conditional build including P0** | **~2,150**, or ~2,320 with `socksubmit` |

Effort: P0 is S-M. The full build is L. Axis 08's skeptic counted 68 files that reference `config_dir`;
§5.4 reduces the load-bearing set to 7 sites by routing attribution through one overlay.

---

## 11. Dependencies on other items

| Item | Relation |
|---|---|
| **C2-socket-prompt** | **Hard.** The nudge is C2's `lr_recon/socksubmit.py` (`impl/C2-socket-prompt.md` §4.2), with its at-rest gate and no cc-wake W3/W3b. C2's verdict is DROP-for-now, so if C1 builds first it builds `socksubmit.py` (+170 LOC) to C2's spec |
| **B6-telemetry** | **Soft, decision input.** Gate 0 needs per-member detection-to-engaged times and load and band beside them on the next wall. Recon records carry the timeline today; B6's base-priority census is needed beside every T1 reading |
| B1-load-harness | Soft. It runs t14/t15 under the band-mix generator; it cannot test real pickup |
| B3-deadline-override | Soft. `FLIP-WAIT` is a new soft gate, and B3 must list it among the gates bypassed after `W_soft` |
| A6-restart-safety | Soft. The flip actuator is detached and journal-recovered, and must follow A6's adoption rule if it is ever made a claim holder |
| G2-self-recovery, D2-warning-band-shedding | **Competitors and value inputs.** Both shrink C1's marginal value. Measure Gate 0 after whichever lands |
| B2, B4, B5, B7, B8, A7, D1 | None. The flip boots nothing, places once per account, and has no kitty or pass-`now` exposure |

---

## 12. Evidence index (commands run for this file)

- Binary reads: `python3 -I /tmp/c1flip/ctx.py <bin> <regex> …` for
  - `legacy_lock_contended` (80779428, 187083309);
  - `async function Ofs\(e\)` (187083082);
  - `let ae=U.expiresAt…` (187086548);
  - `async function lg\(` (186463761);
  - `async function sg\(` (186463168);
  - `var cPt=30000` (186155032);
  - `var f=2000,ee=4032` (186160871);
  - `function wA\(e,n\)` (187075211);
  - `eT="…"` (186462817);
  - proper-lockfile `lockfilePath||` (186148633);
  - `"x-organization-uuid"` (186842301, 190178976);
  - `Creating client` (191059591).
- `python3 -I /tmp/c1flip/rot.py` gives the rotations per account since 10-13 (next 24, next2 23,
  next3 22, next4 23; default and unsuffixed EMPTY on every row).
- `python3 -I /tmp/c1flip/rtexp.py` gives a constant `refreshTokenExpiresAt` per grant across its
  rotations.
- `/tmp/claude-accounts-cache.json` `login_expires_at`: next `11-16T01:55Z`, next4 `11-02T16:48Z`,
  next3 `11-10T03:02Z`, next2 `10-31T11:33Z`.
- `sed -E -n 's/^[^ ]+ [^ ]+ ([a-z-]+) exit=.*/\1/p' ~/.claude/logs/cc-relogin.log | sort | uniq -c`
  gives 60 browser-failed, 43 fallback-required, 40 refused, 12 error, 5 proven, 1 dry-run. 3
  "phase 2 browser OAuth PROVEN".
- `python3 -I /tmp/c1flip/recent2.py`: recon records detected on 10-20 are the 7 incident sessions
  plus 2 NOT_NEEDED (07:52Z, 08:52Z).
- `python3 -I /tmp/c1flip/socks.py`: 30 live sessions (next 12, next2 15, next4 3; next3 0), all with
  a live messaging socket; status idle 17, busy 5, shell 8.
- `python3 -I /tmp/c1flip/sectime.py`: `security` lookup of a non-existent item, p50 0.019 s, max
  0.888 s, 0 over 2 s (load1 ≈ 40; caller at priority 31).
- `stat` of the two `.credentials.json` files (metadata). The others are absent.
- `git show -s 48b46f513` (the setup-token DROP ruling) and `9737a84c5` (the 403 measurement).
- claude-swap source, fetched to `/tmp/c1flip/cswap/` (`claude_locks.py`, `macos_keychain.py`,
  `switcher.py`). It holds the dual credential locks, writes with `security -i -X` hex, and handles an
  `oauthAccount` identity guard.
- Web: https://github.com/realiti4/claude-swap ; https://www.rfc-editor.org/rfc/rfc9700.html (§4.14.2).
- Repo: `bin/cc-wake:14-20,155-242,287-302`; `bin/claude-accounts:518-521,578-645,727-960,1930-1984,2162-2167,2946-2960,5997`;
  `scripts/limit-recover/lr_recon/__main__.py:141-168,205-216,1218`; `observe_rows.py:91-101`;
  `census.py:580,735`; `types.py:80`; `transcript.py:465`; `hooks/stop-failure-marker.sh:120-139`;
  `bin/cc-relogin:260-330`; `tools/auth/auth-timeseries.sh:35-41,126-153`;
  `scripts/relogin-probes/e1-concurrent-logins.sh:121-166`;
  `docs/research/forced-relogin-rootcause-2026-08-02.md:47-49,89-95,282-300,381-415`;
  `docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md:59-69`;
  `docs/research/setup-token-scope-refutation-2026-09-08.md:80-100`.

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20, about 18:45-19:05Z, tree `28b25a119`, read-only.

**Lens.** Does C1 bound recovery time at 15-40/core with every lane at priority 31? Does any new wait,
bound or gate assume that load falls?

**What I did not do.** I typed into no pane, signalled no process, ran no `launchctl` and no `cc-lr`
mutation, read no credential value, wrote no keychain item and edited no code.

**What I ran.** Read-only scripts in `/tmp/c1rev-eff-x7/`:
- `grepbin.py`, an mmap reader of the 2.1.293 binary;
- `walls.py` and `sectime.py`; `sectime.py` looks up a non-existent keychain service only;
- `pstime.sh`.

I also ran `/tmp/c1rev/fit.py`. I left `/tmp/c1rev/` after another process rewrote `/tmp/c1rev/ctx.py`
mid-review; a sibling reviewer probably shares that path.

**Load** (`sysctl -n vm.loadavg`, 10 cores, so 18-29/core) [M]:
- `{ 182.90 189.50 186.58 }` at 18:49:39Z;
- `{ 256.88 221.10 203.08 }` at 18:57:49Z;
- load1 293 inside `sectime.py` at 18:58:54Z.

Labels are as above: [M] measured, [R] read, [E] estimated, [H] hypothesis.

### V. Verdict on this lens: NEEDS-CHANGES

**What survives.**
- OPERATOR, with Gate 0 first, is right under this lens too. Nothing in P0 or the prototype waits on
  load, and no new gate reads the load average (t19 pins that).
- Keychain reads are fast at load. In Claude Code's own exec shape (`/bin/sh -c "security
  find-generic-password …"`): p50 0.075 s, p90 0.214 s, max 0.298 s, 0 of 40 over Claude Code's 2 s
  `f` bound, at load1 293 with the caller at priority 31 [M: `sectime.py`]. That supports §6 F2/F3.
- The 90 s pre-validation bound sits far above a 7 s priority-31 boot at load about 190
  (`06-bound-sizing.md:298-302`).
- A directory-sized target almost always fits. `k(Y)+k(X) ≤ 23` held for some uncapped Y on 4,005 of
  4,133 account-sweeps with k(X)>0 (96.9%), and on 125 of 125 capped account-sweeps since 10-13
  [M: `fit.py` over `~/.claude/logs/account-utilization.jsonl`]. KMAX is not the binding constraint.

**What fails.** Conditional build B′ does not yet bound recovery time better than the relaunch path.
In several places it makes the relaunch path slower, or adds work under load:

| # | Finding |
|---|---|
| E1 | FLIP-WAIT is serial and runs its own clock: a failed flip costs the cohort the whole soft window, and B3 does not know the gate exists |
| E2 | §6's sum undercounts our own bounds by about 3.5 min, and one attempt can outlast `W_flip` |
| E3 | The lock *hold* is unbounded (about 80 s worst case); Claude Code abandons `.storage-write` after about 7.5 s |
| E4 | The overlay turns stale-cache re-deaths, which are a load effect, into false cap facts on Y and fresh hook-lane relaunches |
| E5 | The nudge's dispatch path is unspecified on admission, the one-driver claim and pane binding |
| E6 | A nudge timeout after FLIPPED falls back to relaunching sessions that are already on a healthy account |
| E7 | Pre-validation kills a refresh in flight on our bound and maps transport errors to `spare-dead` |
| E8 | All recent walls are 7d, so a flip parks a whole directory's burn on one Y for hours, and Y can become the next, larger wall |
| E9 | Gates 1 and 2 turn our time bounds into DROP verdicts |
| E10 | Flip-back runs inline in a poller that ticks every 600 s with no tick budget |

**Conviction.**
- That a safe, unattended flip is reachable *and* worth its cost: 20% → **15%** [E: E4 and E8 are new
  costs, and E1/E6 remove most of the margin over the post-wave relaunch path. All are fixable on
  paper].
- That OPERATOR with Gate 0 first is the right call: **85%, unchanged.**

### E1. FLIP-WAIT adds up to 10 min to the relaunch path, and B3 does not know it exists [R]

**Where.**
- §5.1: "D's PRE-MOVE records wait at most `W_flip` = 10 min in a new soft substate `FLIP-WAIT`". Its
  clock is FLIP-WAIT entry, not detection.
- B3 sets `W_soft` = 600 s from `timeline.detected` (`B3-deadline-override.md:112`; `DEADLINE_SOFT_S =
  600.0` at `:252`).
- B3's dependency table lists C1 as "Independent" (`:616`), and its gate census has no FLIP-WAIT row.
  §11 here calls B3 "Soft".

**Consequence either way.**
- *If B3 never learns of FLIP-WAIT:* a record that enters it at detection + one pass leaves at
  detection + pass + 600 s. That is past its deadline, so `W_flip` stretches G (REPORT §5).
- *If B3 lists it:* FLIP-WAIT uses up the whole 600 s soft window. B3 sized that window for the drip to
  clear a cohort of up to 20 (`B3:112`: "drip 1/30 s; E: 20 × 30 s"). Every member then goes overdue at
  once and lands in the deadline lane together.
- So a failed or slow flip costs the cohort the full 10 min. Even a successful flip holds the whole
  cohort until it finishes, up to its own worst case (E2).
- The claim "invariant G holds with or without the flip" therefore depends on B3, and C1 itself does
  not secure it.

**Required.**
1. Run the flip **in parallel** with the relaunch path. Records keep their admission place. When
   FLIPPED is journaled, D's records still in PRE-MOVE (not yet admitted) move to FLIP-NUDGE; records
   already admitted carry on.
   - There is then no FLIP-WAIT substate at all.
   - The cost: at most `PACE_BURST` (6) boots spent on members the flip would have carried
     (`admit.py:51-57`).
2. If a hold is kept anyway:
   - its deadline is `min(t_detect + W_flip_short, deadline_at)`, with `W_flip_short` ≤ 180 s (the
     design's own expected 30-120 s plus a margin), and never its own entry clock;
   - B3's gate census gets a FLIP-WAIT row, class SOFT;
   - §11 marks B3 **Hard**.
3. **Test.** A flip actuator that never returns. Every member of D gets its first move attempt by
   `t_detect + W_soft + P_max`. The test is red on the design as written (10 min from entry).

### E2. §6's bounded-time sum undercounts our own bounds, and one attempt can outlast `W_flip` [R, E]

**The `security` count.** §6 sums "`security`, 3 × 10 s". The §5.2 pseudocode makes about 23
`security` calls on the success path [E: counted from the pseudocode]:

| Step | Calls |
|---|---|
| preflight: spare state, parked slot | 2 |
| pre-validation read-back | 1 |
| `store_read(D)`, `kc_read(spare)` | 2 |
| three `kc_write`s, each verified by a read-back | 6 |
| `verify_unique` over 12 items | 12 |
| `recover()` with an open journal | 0-1 |

At the 10 s bound each, that is about 230 s, not 30 s.

**`ps` has no bound.**
- The preflight needs a process list ("certified binaries for every live claude in D"; the §7 seam is
  a `ps -wwEo` fixture), and no bound is stated.
- The rail's own full-table `ps` timed out at 30-37 s four times *after* the 07:23Z band fix, at
  priority 31: the `events.jsonl` `abstain` rows "ps degraded … timed out at 32s/37s/33s/30s" at
  07:40Z, 08:19Z, 08:30Z and 11:06Z [M].

**The worst case reaches `W_flip`.**
- Worst case per attempt is about 595-605 s, roughly 10 min [E: sum]:
  - 30 s for the locks;
  - about 230 s for `security`;
  - 90 s for pre-validation;
  - about 30 s for `ps`;
  - 35 s for the nudge offset;
  - 180 s for verification.
- That equals `W_flip`. Rule "Inner bound starves the tail" (`agent-operating-lessons-situational.md:45`)
  applies: a slow but successful attempt lands after its cohort has already left FLIP-WAIT.

**Pass cadence is missing from the sum, and B2 is not a dependency.**
- §6 also leaves out the time from the fact to the pass that spawns the flip, and the retry term
  `B_max + P_max`.
- When idle, the pass cadence is fine: since 07:23Z, `band.log` intervals were n=4459, p50 9 s, p90
  13 s, p99 19 s, max 193 s [M: `awk` over `recon/band.log`].
- With a cohort at priority 31 it is unmeasured; REPORT §5's 14 min was measured at priority 20.
- §11 lists B2 as "None".

**Required.**
1. Enforce one wall budget per attempt, `T_flip` (for example 240 s), that every inner bound sums under.
   A test asserts Σ inner bounds < `T_flip`, and also `T_flip` < any hold that remains (E1).
2. Recount §6 against the pseudocode, including `ps`, `plan`, `recover()` and `verify_unique`.
3. Replace the process-table `ps` with:
   - the vendor rows `<D>/sessions/*.json` (pid and `procStart`);
   - then `ps -o lstart=,args= -p <pids>` with a 10 s bound; a timeout exits 75.
4. Run `verify_unique` after the attempt's result is journaled, outside `T_flip`. It pages; it never
   gates the cohort.
5. `plan` must not run synchronously in the reconciler pass (§5.4.6 makes it a spawn precondition).
   Spawn the flip detached with an auto-target mode, and let it choose Y.
6. State the bound in REPORT §5's terms:
   - the first attempt by `t_fact + P_max`;
   - a retry by `B_max + P_max`;
   - B2 is a dependency of that number.

### E3. The lock hold is unbounded, and Claude Code abandons `.storage-write` after about 7.5 s [R, E]

**What Claude Code does.**
- `ryo` takes `<uw>/.storage-write` with
  `retries:{retries:10,minTimeout:100,maxTimeout:1000},stale:15000` (binary context at offset
  186158441) [R].
- The bundled `retry` defaults are `factor:2, randomize:!1` (offset 186144817) [R].
- So Claude Code waits 100 + 200 + 400 + 800 + 6 × 1000 ms ≈ 7.5 s. Then `Ra` rejects, `ryo` rejects,
  and that credential write is lost [E: arithmetic on the constants read].

**What the flip does.**
- The design bounds only lock *acquisition* (30 s).
- Inside `with Locks(D)` it makes 2 reads, 3 writes and 3 read-backs, each bounded at 10 s: an 80 s
  worst-case hold [E].
- Reads are fast at load (V above). **Writes** (`security -i add-generic-password`) have not been
  measured under load, by the design or by me; I may not write a keychain item.

**What a hold past 7.5 s costs [H].**
- Any Claude Code credential mutation in D during the hold fails.
- That includes MCP OAuth saves through `d()`, which share the item (§5.2: `{**cur, …}  # keep
  mcpOAuth etc.`).
- On flip-back, D's sessions are busy on Y, so the window is live.

**Required.**
1. A hold budget `H` ≤ 3 s, about half of Claude Code's 7.5 s.
   - Do every read that does not need D's locks before taking them: `kc_read(spare)` and all of
     preflight.
   - Inside the locks, do only `store_read(D)`, the three writes and their read-backs.
2. If `H` is exceeded mid-sequence: finish the current journaled step, release the locks and exit 75.
   `recover()` resolves the rest.
3. Measure the write.
   - P0/T1 measures `security -i add-generic-password` latency on the probe items at the observed load
     stratum: p50 and p99, n ≥ 30, recorded beside B6's census.
   - A gate fails closed when 3 × p99(write) + 4 × p99(read) ≥ `H`.

### E4. Under load, the overlay turns the flip's own stale-cache re-deaths into false caps of Y and new hook-lane relaunches [R]

**How a re-death reaches Y.**
- The overlay goes into `acct_of_cfg` (§5.4.4). `observe.py:623` sets every `SessionObs.acct` from it,
  so every session in a flipped D reads as Y.
- `_facts` writes a fact from any death row: `F.fact_from_death(s.acct, …)` at `__main__.py:193`. It
  has exactly two skips:
  - `:179-187`: an open record with `target_acct == s.acct` and `submitted is None`;
  - `:188-191`: a death equal to the record's own `close["death"]` (`census.handled_death`,
    `census.py:78-81`; set at record birth, `:437` and `:543`).
- §1 and F3 say a woken turn can re-die on `rate_limit` from X's stale cached token. That is the load
  case: Claude Code re-stamps the stale cache for 30 s on every failed read [R]:
  - `read()` near offset 186161319;
  - `cPt=30000` at 186155036;
  - `fyo=1000` at 186155259.
- A re-death is a **new** death row with a new uuid@ts, so it is not `handled_death`. The lane sets no
  `target_acct`, so neither skip applies. `fact_from_death(Y, …)` then writes **"Y capped until X's
  reset"**.

**What a false Y fact does.**
- It makes `fans_out` true for Y (`census.py:144`), so Y's healthy sessions can become IDLE-ELIGIBLE
  fan-out members where `LR_IDLE_FANOUT=on`.
- A contradicted 5h/7d fact still blocks until its reset (the `F.blocking` docstring in `facts.py`).
- So Y drops out of recovery placement for other cohorts.

**The hook side.**
- `stop-failure-marker.sh` latches per `$SID.$duuid`, one latch per death uuid (`:498-534`). Every
  re-death therefore writes a **fresh poller request**.
- The hook lane drives that request because `~/.reso/limit-recover/autorecover.on` exists [M: `ls`].
  It relaunches the very session the flip is nudging.
- t12 ("a death in flipped D files `…__next4`") **pins** this misattribution for the re-death case.
- §5 fences neither the re-death nor the hook lane.

**Required.**
1. Attribute a death in a flipped D by its **reset**, not by its directory.
   - A death whose `resets_at` matches X's live fact (± `F.GRACE_S`), or that lands before adoption is
     proven, is X's. Either write it as X's or write no new fact.
   - Apply this in `_facts` and in `stop-failure-marker.sh`; t12 changes to match.
   - New test: a re-death in flipped D naming X's reset writes no Y fact. It is red on §5.4.4 as
     specified.
2. At FLIPPED, set `rec.target_acct = Y` on D's open records. The existing skip at
   `__main__.py:179-187` then covers them while no move is submitted.
3. Fence the hook lane while D is in FLIP-NUDGE: a hook request for a session in D is parked, not
   driven. Either the poller's W5-A gate reads `credential-flips.json`, or the hook skips the write.

### E5. The nudge's dispatch path is unspecified on three load-relevant points [R]

**Admission.**
- If the nudge is dispatched like C, it is a FIRST_TURN for a limited record (`__main__.py:1085`), and
  `_admit` applies (`admit.py:51-57,284-322`):
  - the restore budget, which refuses for `DRIP_AFTER` = 3 passes before the drip opens;
  - the pace: one token per `PACE_EVERY_S` = 20 s, burst 6;
  - the per-account pacer.
- Then §6's "30-120 s for all n sessions together" cannot hold for n > 6. It is about 3 passes +
  (n − 6) × 20 s [E].
- If the nudge bypasses admission, the design must say so and give the reason (the turns restore load
  that existed before the wall).

**One driver per session.**
- `hold_claim` (`act.py:493-523`, Wave G) exists because one session was once driven by three lanes at
  once.
- The design's nudge takes no claim, and §5.1 holds only reconciler records.
- At the moment of FLIPPED, the hook lane, a `cc-lr move` drain or the reconciler can each hold a
  session in D. Under load those windows last minutes.

**Pane independence.**
- "No kitty" is C1's selling point (REPORT §4(c)).
- But the census files a session with no pane and no registry name as `IMPOSSIBLE: headless`
  (`census.py:202`).
- C2's efficacy review measured that a deaf kitty leaves records unbound and undispatched
  (`C2-socket-prompt.md`, "E1. F14 is unreachable").
- A nudge driven off census records inherits that.

**Required.**
1. The flip actuator sends the nudges itself at `t_write` + 35 s, not a later reconciler pass.
   - It enumerates D's members from `<D>/sessions/*.json` (pid and `procStart`, as `socksubmit` S1
     already does), so no pane binding is needed.
   - The reconciler only observes the effect and closes records.
2. Each nudge takes the per-session claim (`store.claim_take`). A session held by another driver is
   skipped and counted.
3. Either declare the nudge admission-exempt, with the reason, or put the admission terms in §6's sum.

### E6. A nudge timeout after FLIPPED must not fall back to a relaunch [R]

**The gap.**
- §5.4.6 defines a fallback only for re-death ("up to 4 times. Then the record falls back to the normal
  path"). It has no rule for "no turn within the 180 s verification".
- At 15-40/core, a long-context re-ingest on Y can be slow. Y's prompt cache is cold because Y is
  another organisation [H].
- C2's `socksubmit` has two "unknown" outcomes (`C2-socket-prompt.md` §4.2 exit table):
  - rc 5, "CANNOT TELL", after 90 s;
  - rc 2, WAIT, when the session is not at rest (capped at 900 s).

**What a relaunch fallback would cost.** If any of these sends the record to "the normal path", the
rail relaunches a session that is **already on a healthy account**:
- it spends a boot slot and an admission token that other cohorts need;
- it can `/exit` a turn in progress;
- with the overlay, placement may even pick Y and move the session from D to Y's home directory. Y is
  then charged twice: once in the census k, once as the mover's phantom.

**Required.**
1. After FLIPPED, treat a timeout or rc 2/5/6 as unknown. Re-check status and at-rest, then deliver
   again in place: C, over the socket first and then kitty-dedup.
2. Only 4 or more re-deaths that name X's reset (pickup failed) send the record to the move path, and
   then with Y excluded.
3. Bound FLIP-NUDGE by the record's B3 "owed first turn" deadline (`B3:113`, "inherits"). B3 should
   document that.

### E7. Pre-validation: our bound must not kill a refresh in flight, and a transport error is not `spare-dead` [R, H]

**The kill.**
- §5.2 reuses heal's mechanism (`bin/claude-accounts:1966-1975`). Heal calls `subprocess.run(…,
  timeout=90)` (`:1974-1977`), which kills the child when the timeout expires.
- Suppose the kill lands after the server has rotated the spare's refresh token but before the binary's
  `security` write. The bank item then holds a dead token, and the retry gets a 400.
- The design then refuses with `spare-dead` and pages. **Our own timeout has become a negative
  verdict**, against the premise.
- Under load, the slow step is most likely that `security` write. So the timeout correlates with the
  dangerous window [H].
- Weak counter-evidence: 4 heal `TIMEOUT`s in August, with at least two followed by an OK heal of the
  same account [M: `claude-accounts.log` lines 5239→5240 (next4) and 5414→5415 (next3)].

**Transport errors.**
- The same log shows transport failures: `SSL certificate error`, `read ECONNRESET` and `Socket is
  closed`, 2026-08-14 16:55-17:14Z [M].
- §5.2 maps "a rejected grant" to `spare-dead` but names no classifier. It must use `_heal_rejected`
  (`:1992`), so that only a real 400 or invalid-grant counts as a rejection.

**Required.**
1. On our bound, stop *waiting* (exit 75) but do not kill.
   - Leave the child to finish, under a long watchdog (SIGTERM after 15 min or more).
   - The next attempt waits on that child's pid (single-flight per bank directory), then re-reads the
     bank item.
2. Classify the result with `_heal_rejected`. Everything else exits 75.
3. Reuse a pre-validation that is less than 1 h old; the access token is good for 8 h. Otherwise a
   75-retry every ≤ 300 s rotates the spare each time.

### E8. One directory moves onto one Y: for 7d walls the flip lasts until X's weekly reset, and Y can become the next wall [M, E]

**The walls.**
- All 8 walls since 10-06 were **7d** caps, none 5h [M: `walls.py` over `account-utilization.jsonl`].
- Their capped accounts carried k = 10-23 sessions at the wall; next4 had k = 23 on 10-11T08:22.
- So a flip lasts until X's weekly reset (REPORT §1.4: median 10.5 h). For that whole time it lands
  all of D's burn on one Y. The relaunch path instead spreads members by `--place` weights.

**The target rule is blind to D's burn.**
- The router projects only Y's **own** burn (`_su_projected`, `bin/claude-accounts:4558-4582`).
- §5.1's rule ("highest headroom by the last good `--rank`") never adds D's burn.

**The second wall.**
- If Y hits its 5h cap while D is on Y, that wall carries D's cohort and Y's home cohort at once.
- D cannot be re-flipped: preflight requires `flip_state[D]==HOME`.
- So the relaunch path inherits a cohort about twice the size [E].

**Required.**
1. Target fit must include D's burn, where `b_D` is X's last pre-cap `burn_5h_ewma_ph`:
   - 5h: `su_Y + (b_Y + b_D) × min(lookahead, Y's 5h reset) < 0.9`;
   - 7d: Y's 7d headroom must cover D's 7d burn × (X's reset − now).
   - No fit means no flip.
2. Before Y walls, a flipped D whose Y crosses a 5h threshold (for example 85%) is flipped back or
   paged.
3. Add a test for both.

### E9. Gates 1 and 2 turn our own time bounds into DROP verdicts [R]

**The gates.**
- Gate 1 needs a first turn "within Δ + 60 s … at load1/ncpu ≥ 15 on at least 3 trials".
- Gate 2 needs "a non-error assistant turn within 180 s".
- Missing either means DROP (§4). A slow turn at 40/core would then be read as "the mechanism does not
  work". That is our timeout used as a negative verdict.

**Load coverage.** "≥ 15 on 3 trials" leaves the premise's upper half (25-40/core) unexercised. Rule
"Verify a cure under its load" needs a positive control at the load the cure must survive.

**T1's refresh arm cannot fire on a production-shaped flip.**
- The arm assumes the spare's access token has expired by adoption ("dormant > 8 h").
- The production flip pre-validates first (§2.2.3), so the token is fresh at adoption.
- Either T1 runs `move` without pre-validation and says it is not production-shaped, or the wire arm is
  T1's oracle.

**Required.**
1. Gates 1 and 2 decide on the adoption oracles, with no clock.
2. Record latency with load1, the B6 census and the n per load stratum. The value judgement uses it in
   Gate 0's comparison.
3. Require at least one trial at 25/core or more. If none happens in the window, mark the gate
   "unproven above N/core", not passed.

### E10. Flip-back runs inline in a poller that ticks every 600 s with no tick budget [M]

**The poller.**
- `com.reso.lr-reset-poller.plist` has `StartInterval` 600 and ProcessType Interactive [M: `plutil
  -p`].
- `lr-reset-poller.sh` has no tick budget. Its only precedent for a detached start is `lrp_move_kick`
  (`:219`).

**The cost.**
- An inline `cc-cred-flip back` takes pre-validation's 90 s plus E2's sum. Under load that delays the
  tick's other work, including hook-lane requests, by minutes.
- After X's reset, D keeps burning Y for up to 180 s + 600 s + the attempt, and another 600 s on every
  exit 75.

**Required.**
1. Spawn `back` detached, with a claim by hard link as `lrp_move_kick` does.
2. State the flip-back latency bound.
3. Page after N consecutive exits 75: each one extends Y's exposure (E8).

### Citation audit (this lens)

**Verified as cited (±2 lines):**
- `lr_recon`:
  - `observe_rows.py:91-101`;
  - `__main__.py:205-216` (the turns list and `F.contradict` at `:216`) and `:1218`;
  - `types.py:80`;
  - `transcript.py:465`;
  - `census.py:580,735`.
- `bin/claude-accounts`:
  - `:518-521`, `:578-580`, `:884`, `:1159`, `:1587`, `:6551`;
  - `:1930` and `:1970-1975`;
  - `:2162-2167`, `:5997`.
- Other files:
  - `bin/claude-accounts:2946-2960` (`def` at `:2944`, `read_creds` at `:2958`);
  - `hooks/stop-failure-marker.sh:120-139` (`:121-138`);
  - `tools/auth/auth-timeseries.sh:35-41` (`:34-40`).
- Binary:
  - `ryo` and its `.storage-write` parameters;
  - `cPt=30000`;
  - `f=2000` and `ee=4032`.

**Incomplete or off.**
1. §5.4.4 says `acct_of_cfg` "feeds `census.py:580,735`". The site that matters for `_facts` is
   `observe.py:623` (every `SessionObs.acct`); `__main__.py:486` is another. Patching the function
   covers both, but the stated reach omits the path in E4.
2. §5.1 and §11 say B3 "must list" FLIP-WAIT. B3 lists C1 as "Independent" (`B3:616`) (E1).
3. §6's "3 × 10 s" (E2).
4. `keychain_service` NFC-normalises the directory (`bin/claude-accounts:520`), and `flip-probe.py`'s
   `svc(d)` does not. The two are identical for today's ASCII paths. Use the same function anyway.

### Measured during this review

- **Keychain lookup** of a non-existent service via `/bin/sh -c`, n=40: p50 0.075 s, p90 0.214 s, max
  0.298 s, 0 over 2 s, all rc 44; load1 293, priority 31 (`sectime.py`).
- **`ps` timing** (`pstime.sh`): full-table `ps -wwEo` 1.10-2.59 s and pid-list `ps` 1.21-2.44 s, at
  load1 257. Python start-up is included, so this is inconclusive on the gap between the two forms.
  The rail's own 30-37 s `ps` timeouts after 07:23Z are from `recon/events.jsonl`.
- **Pass intervals** since 07:23Z (`recon/band.log`): n=4459, p50 9 s, p90 13 s, p99 19 s, max
  193 s. These are idle passes; no cohort has run since then.
- **Fit** (`fit.py`): 96.9% of account-sweeps with k>0, and 125 of 125 capped account-sweeps, have a Y
  with `k(Y)+k(X) ≤ 23`.
- **Walls** (`walls.py`): 8 walls since 10-06, all 7d.
- **Heal outcomes** (`claude-accounts.log`): 4 `TIMEOUT`s, all in August; transport failures on
  2026-08-14 16:55-17:14Z.
- **Binary constants:** `retry` defaults `factor:2, randomize:!1` (186144817); `ryo` `.storage-write`
  parameters (context at 186158441); `cPt=30000` (186155036); `fyo=1000` (186155259); the
  stale-re-stamp `read()` (186161319).

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20, read-only, against worktree `wt-cc-213316-21905` at `28b25a119`. The
question was whether the design could strand a session, double-move one, lose a draft, split-brain, break an
invariant or break an existing test. I wrote nothing outside `/tmp/c1rev/`, which holds read-only
analysis scripts. I read no credential value and ran no `launchctl`.
Labels as above: [M] measured, [R] read, [E] estimated, [H] hypothesis.

### R.0 Verdict: NEEDS-CHANGES

**What I keep.** The top-level call stands: OPERATOR, Gate 0 first, and P0 is the only agent work
now. The binary reading behind finding 3 also stands; I re-read it independently (R.1).

**What fails.** The conditional B′ build is **not safe as written**. Three of its defects would create
the very hazards the design claims to close:
- an unfenced third redeemer of D's grant (D1);
- false cap facts on the flip target Y (D2);
- a refresh-token replay caused by our own timeout (D4).

Finding 5 is right that the fact is marked contradicted, but wrong about the consequence (D2).

**Conviction.** The design's 20% (a safe, unattended flip is reachable and worth it) drops to
**14%**. The patch set grows by about 9 sites and 4 new invariants (R.4). I still hold about 85% that
OPERATOR with Gate 0 first is right.

### R.1 File:line claims checked

| Claim | Result |
|---|---|
| `claude-accounts:518-521` item name | **Confirmed**, with one detail: `keychain_service` hashes `NFC(config_dir)`, not the raw string. That is identical for today's ASCII dirs. `flip-probe.py svc()` should apply NFC too, so it cannot diverge from the authoritative copy |
| `:579` 10-11 item vanished | Confirmed |
| `by_dir` at `:884,:1159,:1587,:6551` | Confirmed, **but there are 6 dir→account maps, not 4**. `:6526` (`_dirs0`, `--place` source-reset check) and `:11266` (`--rank/--route --src <dir>`) are omitted. `:6551` feeds `src_of()` (`:6603`), which is **source** semantics. See D3 |
| heal `:1930-1984`, gate `:1938-1965` | Confirmed: the `k_live` gate is at `:1939-1941`, the under-lock re-check at `:1963-1966` |
| `_rt_fingerprint` `:2162-2167` | Confirmed |
| `probe_account` `:2946`, `read_creds` `:2960` | Confirmed |
| `_excluded` tests `row["error"]` first (`:5997`) | **Partly.** The test is `if "error" in r and not _throttle_admitted(r)` (`:6006`), and a `poll_throttled`+`stale_quota` row can still be admitted (`:5942-5955`). See D19 |
| `stop-failure-marker.sh:120-139` | Confirmed (`CFG` at `:121`, the jq resolution at `:131-136`) |
| `observe_rows.py:91-101` `acct_of_cfg` | Confirmed. Its callers are `observe.py:623` (the main producer of `s.acct`), `census.py:580,735` and `__main__.py:486`. The design names only the census and `:205-216` sites; the patch covers the rest anyway |
| `__main__.py:205-216` contradiction | Confirmed. **The stated consequence ("un-cap X") is refuted** (D2) |
| `cc-relogin:330` "the gate" | **Off.** `:330` is inside `session_count()`. The refusal is in `run()` at `:997-1000` and again under the lock at `:1015-1021`. The fence belongs there (D18) |
| `types.py:80` OUTCOMES; `transcript.py:465`; `__main__.py:1218` | Confirmed |
| `auth-timeseries.sh:35-41`, `:126-153` | Confirmed. It reads **items only, never `.credentials.json`**, and writes `EMPTY` when both `at` and `rt` are blank (`:149`). See D6 |
| check15-17 taken; `check14_authstore.sh` exists | Confirmed (`ls lib/cc-upgrade-gate/`) |
| §1 storage-write lock | **Confirmed** [R: `python3 -I /tmp/c1rev/ctx.py <bin> .storage-write`, offset 186158440]: `Ra(Q(s,".storage-write"),{realpath:!1,retries:{retries:10,minTimeout:100,maxTimeout:1000},stale:15000,onCompromised:…warn})`, and `d()` = invalidate → strict re-read → mutate → `update` |
| §1 `jhr` compare-and-clear | **Confirmed, and it is safe against the flipper** [R: offset 187070953]. `jhr` runs through `zn().mutate(…)`, i.e. under storage-write with a strict re-read, so a flipper holding all three locks cannot be clobbered by it |
| §0.2 "cliff fixed across rotations" | **Confirmed at minute resolution, not exactly** [M: `python3 -I /tmp/c1rev/fam2.py ~/.claude/logs/auth-timeseries.jsonl`]. Each rotation writes a new `refreshTokenExpiresAt`, but per grant they all fall in a 1.3-6.9 s band (next 6.9 s, next2 6.1, next3 6.1, next4 6.6). Every RT generation has its own value (`fam.py`). This matters for D6 |
| R4 "whole account" | **Overstated.** RFC 9700 §4.14.2 says the server "will revoke the active refresh token", and its note scopes that to "the grant to which a refresh token belongs" [R: rfc-editor.org/rfc/rfc9700.html §4.14.2]. Blast radius is the grant, meaning every item holding it. Account-wide revocation is an unsupported [H] |

### R.2 Defects (evidence → consequence → required change)

**D1. A third credential redeemer is unfenced: `handoff-fire.sh` pre-fire sweep `phase1_relogin`.** (Blocker)
- **Evidence** [R]:
  - `scripts/handoff-fire.sh:13107-13150` runs `claude auth login` with
    `CLAUDE_CONFIG_DIR=<account config_dir>` and the refresh token read from **that dir's item**.
  - Its gate (`:13255`) is `auth_actionable` + `has_refresh_token` + `kstate=present` + `"${k:-0}" = 0`.
  - Here `k` is the claude-accounts row count, i.e. the overlaid count. The design makes X read 0 while D
    is full (§5.4.2), and `--relogin-info X` (`claude-accounts:11141-11170`) reads D's item, which holds
    **Y's spare**.
- **Consequence.** If X's row is ever `auth_actionable` (for example, a flipped-away row that inherits an
  actionable last-good auth), the sweep redeems the spare's refresh token in D under live sessions. That
  is R8 through a door the design does not list. Its lock (`/tmp/claude-accounts-heal-X.lock`) does not
  interlock with the flipper's locks.
- **Change.**
  - Fence `phase1_relogin` and `--relogin-info` on `credflip.is_flipped(config_dir)`. The fence must
    fail closed when the state is unreadable.
  - `--relogin-info` must report `flipped:true` and must **not** report the spare's
    `refresh_token_expires_at` as X's.
  - Add a red-today case to `tests/handoff-fire-account-sweep.bats`.
  - Re-run "Enumerate the generator's copies" for credential **writers**: `git grep -E "auth login|CLAUDE_CODE_OAUTH_REFRESH_TOKEN|add-generic-password"`
    finds claude-accounts heal, cc-relogin, cc-relogin-poll→cc-relogin, and handoff-fire. Pin that count
    in a test.

**D2. The time-blind overlay at `acct_of_cfg` manufactures false cap facts on Y. Finding 5's harm is refuted.** (Blocker)
- **Refutation** [R]:
  - `facts.blocking` (`facts.py:334-361`) ignores `contradicted` for 5h/7d facts: "A contradicted 5h/7d
    fact still blocks to its reset" (`:343`). So a contradicted X fact does **not** un-cap X for
    placement.
  - Contradiction only switches off idle fan-out (`census.py:144`) and `source_rejected`
    (`census.py:255-268`). That turns D members with background work into HOLD-BGWORK
    (`census.py:227`).
- **The real hazard** [R]:
  - `__main__._facts` writes `F.fact_from_death(s.acct, …)` for every session whose last transcript
    record is a limit (`__main__.py:193`). `fact_from_death` stamps `observed_at=now` (`facts.py:179`).
  - Once `acct_of_cfg(D)` returns Y, a D session still sitting on **X's** pre-flip death yields a fact
    `acct=Y` with X's `resets_at`.
  - The existing guard (`__main__.py:188`, `s.acct != mv.source_acct and handled_death`) catches only
    sessions whose record was opened **before** the state commit.
  - A death on X that is first observed after the commit opens its record with `source_acct=Y`
    (`census.py:415,535`, `source_acct=s.acct`). The guard is then false, and Y gets a fact that blocks it until X's reset
    (`blocking` ignores contradiction).
  - The same applies to `stop-failure-marker.sh`. A death inside the ≥30 s cache window (unbounded
    under load: "a failed read re-stamps the stale cache", §1) happens on X but is filed `__Y`, and that
    becomes a hook fact (`facts.py:404-418`).
- **Consequence.**
  - The flip target is marked capped for hours, and routing and placement avoid it.
  - With `LR_IDLE_FANOUT=on`, Y's healthy idle sessions become fan-out members (`census.py:144`).
  - The flip defeats itself.
- **Change.** Replace the static overlay with time-aware attribution, `acct_at(cfg, t)`, driven by a
  flip history (`since`, `until`) in `credential-flips.json`:
  - a death or turn with `t < since + T_amb` keeps the home account. `T_amb` is at least 30 s plus the
    observed cache-re-stamp chain; a fixed 120 s is a start [E];
  - `t > since + T_amb` goes to Y;
  - in between, the record contributes **neither** a fact nor a contradiction.
  - Better still, use the death record's own `quotaLimits.resetsAt` (cc-wake reads it, `cc-wake:220-226`).
    A death whose reset equals X's live fact is X's [H: a 5h reset time identifies the account's window].
  - Apply the same rule in `stop-failure-marker.sh`, using the hook's own time.
  - t13 must add the red case "X's pre-flip death observed after commit writes no Y fact".

**D3. "One overlay through all four `by_dir` sites" is semantically wrong at the source sites, and the count is wrong.**
- **Evidence** [R]:
  - `cmd_place` uses `by_dir` for `src_of(m)` (`claude-accounts:6603-6605`) → `src_facts` (the
    **death's** account). `:6526` (`_dirs0`) and `:11266` (`--src`) are the same source semantics.
  - `acct_of_cfg` also folds `.claude` into `.claude-next` (`observe_rows.py:96-97`). If X is next, the
    overlay would move `~/.claude` sessions to Y even though they use a different item (`default`,
    `7b461744`).
- **Change.**
  - Overlay only the **census/billing** sites (`:884`, `:1159`, `:1587`).
  - Leave the source-semantics sites (`:6526`, `:6551`/`:6603`, `:11266`) on the record's own
    `source_acct`, or make them death-time aware via D2's `acct_at`.
  - Apply the overlay on the literal directory **before** the `.claude` fold.
  - The pinning test asserts 6 enumerated sites with an explicit semantics column, not "4".

**D4. Killing `claude auth login` at our 90 s bound can turn "unknown" into "dead" and replay a superseded refresh token.** (Blocker)
- **Evidence** [R]:
  - `subprocess.run(…, timeout=90)` (heal's pattern, `claude-accounts:1974`, which pre-validation
    copies) SIGKILLs the child on timeout.
  - If the server has already rotated the grant, the bank item still holds the retired RT. The retry
    "75 → retry" then posts it, which is exactly RFC 9700's replay case: it revokes that grant.
  - Separately, claude-accounts' own note says `auth login` "WIPES the stored credential before writing
    the replacement" and exits 0 with "Login successful" on a failed write (`claude-accounts:3040-3050`).
    So rc and stdout are not proof.
- **Consequence.**
  - Under 15-40/core, a 236 MB binary boot past 90 s is plausible [H]. Each such kill can destroy a
    spare or, at flip-back, **X's parked home grant**: an interactive login, with D stuck on Y (F7).
  - That breaks G2's intent: our bound becomes the cause of a negative verdict.
- **Change.**
  - Pre-validation runs **detached** (`start_new_session`) and is never killed by our bound. On the
    bound, `flip`/`back` exits 75 and leaves `prevalidate-inflight {pid, lstart, rt_fp_before}`.
  - The next attempt waits for that pid to exit (`kill -0` plus `lstart`), then re-reads the bank store
    (item, then file).
  - Success is **proof by store**: the RT fingerprint changed and the cliff family is unchanged
    (`claude-accounts:3040-3050` pattern).
  - A 400 after an in-flight attempt the flipper itself abandoned is recorded as `spare-dead-suspect`
    (page), not as a clean verdict.

**D5. The lock-hold budget exceeds Claude Code's own patience, and a timed-out write is resolved after the locks are released.**
- **Evidence:**
  - [R] `ryo` gives up after retries 10, min 100, max 1000 ms. That is about 7.5 s [E: retry-lib
    defaults, factor 2: 100+200+400+800+6×1000].
  - [R §1] Refresh waiters give up after about 12.5-17.5 s and then do **not** refresh.
  - The design allows 10 s per `security` call. With 3 writes plus read-backs, that is up to about 60 s
    under all three locks (§3.1, §6 F2).
  - F2 resolves a timed-out write "in `recover()`", which runs after the locks are dropped.
- **Consequence.**
  - Claude Code's pending storage writes fail: mcpOAuth rotations, and `jhr` clears.
  - A D session whose access token expires mid-hold gets `lock_timeout` and sends its request with an
    expiring token [H: then a 401 auth death]. An `auth` fact blocks until contradicted (`facts.py:356`).
  - A write that lands after release can interleave with a Claude Code read-modify-write: the silent
    revert finding 3 warns about.
- **Change.**
  - Bound the **whole hold**, first `mkdir` to last `rmdir`, at ≤ 5 s [E: below the 7.5 s storage-write
    patience, with margin].
  - Per-call `security` bound ~1.5 s inside the hold. The design's own max was 0.888 s at load1 ≈ 40.
  - On any overrun: kill the child, wait for it to exit, re-read the item **under the still-held
    locks**, journal the observed state, release, and exit 75.

**D6. A uniqueness check on RT fingerprints misses stale copies, ignores the file store, and collides with the design's own tombstones.**
- **Evidence:**
  - [M] Every rotation changes `rt`; the grant family is constant only by its cliff (±7 s, R.1).
  - A parked copy left by a crash (D9), followed by one rotation in D, has a **different** fingerprint
    from D's live RT. t3 passes, and the "skip tombstone" mutant goes green after a rotation.
  - Yet that stale copy is the R3/R4 replay hazard.
  - [R] The checker reads items only, while F4 moves grants into `.credentials.json`.
  - [R] A tombstone `{"claudeAiOauth":null,…}` reads `EMPTY` in `auth-timeseries.sh:149`. Gate 3 ("zero
    `EMPTY` on … the bank") and R4 ("zero `EMPTY`") would then fail on every correct flip.
- **Change.**
  - `verify` keys uniqueness on **family** = (`refreshTokenExpiresAt` rounded to ±60 s,
    `subscriptionType`) **and** on RT fingerprint.
  - It scans every item **and** every live, bank and parked `.credentials.json`.
  - auth-timeseries emits `TOMBSTONE`/`IN_USE` from `ccFlip.state` for bank rows.
  - Rewrite Gates 3 and R4 over non-tombstone rows.

**D7. Record transitions seize records that an actuator owns. The nudge gate is wider than cc-wake's measured one.** (Blocker for the lane)
- **Evidence** [R]:
  - `PRE_MOVE_SUBSTATES` includes `PLANNED` and `IN-FLIGHT` ("a confirmed move in its relaunch gap",
    `types.py:56-71`). `act.choose` spawns A/R from PRE-MOVE/PLANNED (`act.py:568-576`).
  - "D's PRE-MOVE records move to FLIP-NUDGE" would therefore relabel records whose movers are running.
  - cc-wake refuses exactly these states: "a mail turn during a move splits the transcript"
    (`cc-wake:212-214`). It also refuses when a `HANDOFF.json` sits beside the transcript (`:207-208`).
  - The design's gate admits `status ∈ {idle, shell}`, while cc-wake requires `idle` (`:160`).
  - A socket frame is **queued** (`cc-wake:17-18`). A frame accepted while the session is not idle can
    therefore fire after the record has fallen back to the normal path, mid-transplant.
- **Consequence.** A split-brain transcript: the old D session starts a turn on Y while its successor
  resumes a copy.
- **Change.**
  - FLIP-WAIT and FLIP-NUDGE apply only to substates DETECTED, WAIT_SLOT, WAIT_RESET, WAIT_DATA,
    WAIT_CAPACITY and HOLD-LOAD. They never apply to PLANNED, IN-FLIGHT, HOLD-MENU, HOLD-COMPOSER or
    HELD:team.
  - Only the reconciler mutates records. The detached `cc-cred-flip` reports through its exit and
    actlog.
  - Each nudge is a **claimed actuator** (`act.hold_claim`, `__main__.py:1248-1272`) and passes
    `_admit`, the wall-clock token bucket. Without that, a burst of n(D) re-ingests bypasses wave 1's
    pacing.
  - Status must be `idle` only, and the `HANDOFF.json` check applies.
  - A nudge with no verified effect leaves the record in `FLIP-NUDGE-PENDING`. The normal path may take
    it only after the session is seen idle with the frame consumed: the isMeta user record appears in
    the transcript [H: T2 should record its shape], or the process has exited.
  - Draft loss is **not** a risk from the socket itself: frames "never touch the composer"
    (`cc-wake:14-20`) [R].

**D8. Flip-back has one optional owner and a trigger that can be undefined. D can sit on the spare until the spare's cliff erases it.** (Blocker)
- **Evidence** [R]:
  - `back` runs only from `lr-reset-poller.sh`, which has its own kill switch (`LR_POLLER_DISABLED`,
    `:118`), runs every 600 s (plist `StartInterval 600`), and can be unloaded.
  - The trigger is "X's fact reset passes", but wire facts carry **no** `resets_at`
    (`facts.py:185-205`).
  - The spare margin is a flat "cliff ≥ now + 7 d", which can equal a 7d cap's reset.
  - Nothing forces back at the **spare's** cliff.
  - Past the cliff, Claude Code's refresh gets `invalid_grant`, and `jhr` blanks D's item. The sessions
    are then logged out, not capped (§1).
- **Change.**
  - The flip preflight refuses when X's reset is unknown.
  - Spare cliff must be ≥ X's reset + grace + 2 d.
  - `back` gets a non-optional owner: the reconciler pass (PRI 31) checks overdue flips every pass.
    `verify` pages when a flip outlives X's reset by 30 min.
  - At spare cliff − 1 d, with `back` impossible (parked grant dead, F7), the rail **evacuates D through
    the relaunch path** before the cliff. Today F7 waits for the operator with no deadline.

**D9. The journal recovery table is incomplete.**
- **Gaps:**
  - A crash *after* a `kc_write` lands but *before* `J.step` is missing from the table. For example,
    "begin" while parked(X) was already written leaves a **duplicate** under "Abort: state HOME", and
    "step 1" with the live item already Y is not covered.
  - "X (possibly rotated)" cannot be decided by fingerprint once D rotated.
- **Change.**
  - `recover` decides from the observed placement of both families (D6 key) across D, parked(X) and
    spare(Y), with the live item authoritative.
  - The journal records `fam_out` and `fam_in`.
  - t4 injects crashes **after each write returns and before its journal step**, plus "after J.begin,
    before the first write".
  - `recover` runs on every reconciler pass while a journal is open, not "on the next run" (F10), which
    may be days away.

**D10. Locks taken with `mkdir` alone never reap a stale lock (liveness).**
- **Problem.** A Claude Code or flipper that died holding `.oauth_refresh.lock` or `.storage-write.lock`
  leaves a directory. proper-lockfile reaps it only when a Claude Code next tries to acquire, and in a
  capped, idle D that may be hours. The flipper then exits 75 forever, including its own `recover`.
- **Change.** Reap a lock whose `mtime` is older than **2×** Claude Code's own stale bound (120 s for
  refresh and legacy, 30 s for storage-write). Never use a smaller bound: a starved Claude Code that
  fails to touch inside 15 s is Claude Code's own compromise and must not be ours as well. Page on each
  reap. Add a t-case with an old-mtime lock.

**D11. Preflight conflates UNMEASURED with FALSE.**
- **Problem.** Several predicates can be unmeasurable under load: k(Y) (`cap='k-unmeasured'` exists,
  `claude-accounts:6572-6574`), the `ps` argv walk for binary certification, and keychain reads for
  cliffs. As exit-2 refusals that page, they violate G2.
- **Change.**
  - Each predicate is tri-state, and unmeasured exits 75.
  - "No fitting Y" is an event, not a page.
  - `plan` must not run synchronously inside `_dispatch` (G3, bounded pass). Run it in the detached
    actuator.

**D12. The band of the credential writers is unspecified.**
- **Problem.** `com.claude.auth-timeseries` is `ProcessType Background`, `Nice 10`, `LowPriorityIO 1`
  [M: `plutil -p ~/Library/LaunchAgents/com.claude.auth-timeseries.plist`]. If the panic flip-back on
  `EMPTY` (F6) or `verify` writes from there, a 2 s lock toucher at background band under 15-40/core
  risks the 15 s storage-write stale reap, i.e. a concurrent write.
- **Change.**
  - `flip`, `back` and `recover` refuse with exit 75 unless their own base priority is ≥ 31 (G4,
    wave 1's band self-check pattern). `verify` stays read-only.
  - The panic path signals the reconciler; it does not write itself.

**D13. Other consumers use D's credential and D's `.claude.json` together for non-inference APIs.**
- **Evidence** [R]:
  - `bin/cc-notify:700-730` routes cloud sends through the owning account's `CLAUDE_CONFIG_DIR`. A
    wrong-account send returns "Session not found", which reads as a dead session.
  - `scripts/cloud-create-api.py:244-256` takes `organizationUuid` from `<dir>/.claude.json`, which is
    X's after a flip, not Y's.
- **Change.** These fail closed with a named `config dir is credential-flipped` verdict while X is
  flipped away. T2's RC variant should also cover a `cc-notify` send.

**D14. Bank-slot ownership.**
- **Problems:**
  - `bank-add Y` while spare(Y) is `IN_USE` mints a second spare. The later `back` then parks D's grant
    over it, which abandons the operator's fresh login.
  - `single_flight` appears only in `flip`.
- **Change.**
  - `back` writes spare(Y) only if it reads `ccFlip.state==IN_USE` with `in==D`. Otherwise it pages and
    writes to a fresh slot.
  - `bank-add` refuses unless the slot is tombstone/absent and no state entry references it.
  - `single_flight` covers `flip`, `back`, `recover` and `bank-add`.

**D15. The T1 oracle schedule cannot pass Gate 1 as written.**
- **Problem.** The refresh arm needs the spare's access token expired, i.e. ≥ 8 h dormant. Trials run
  back to back, and trial 1 follows a fresh mint, so the arm is silent on every trial. "Both arms agree
  on every trial" is then unreachable.
- **Change.**
  - Require `who` to show `expiresAt < now` before any trial that uses the refresh arm, which means
    ≥ 8 h spacing.
  - Otherwise substitute a positive control: P capped first (T2's mechanism), so a successful turn
    proves adoption.
  - Re-estimate §3.7's calendar.

**D16. FLIP-WAIT taxes the relaunch path on every failed flip.**
- **Problem.**
  - Under the binding premise, a flip that keeps returning 75 holds D's cohort the full 10 min before
    the normal path resumes.
  - FLIP-NUDGE has no stated bound.
  - §6's "≤ 6.1 min" omits several costs: 6 `security` calls (3 writes plus 3 read-backs), `verify`'s 12
    reads, `plan`, `recover`, and up to 4 × (35 + 180) s of re-nudges.
- **Change.**
  - One wall-clock budget covers FLIP-WAIT and FLIP-NUDGE together, measured from flip start
    (≤ 10 min).
  - FLIP-WAIT applies only to records with no PLANNED target this pass, so the flip never delays a move
    that is ready.
  - Restate the bound as a sum that includes those terms [E].

**D17. Misplaced fence.** The cc-relogin fence goes in `run()` before `:997` and again under the lock
at `:1015`, not at `:330`. Otherwise `session_count` returns a count for a flipped dir, which is
ambiguous by D2.

**D18. Hermeticity.**
- **Problem.** `acct_of_cfg` is pure today, and `test_observe.py:474-476` pins it. Reading
  `~/.claude/state/credential-flips.json` inside it, or inside the hook, the heal path or cc-relogin,
  makes existing suites depend on the live machine's flip state ("Hermeticity ends at the third tool").
- **Change.**
  - Pass the overlay snapshot as a parameter, read once per pass, so one pass sees one consistent
    attribution.
  - Every reader honours `CC_CRED_FLIP_STATE_DIR`.
  - Add the state path to the hermeticity lint.

**D19. Minor.**
- The flipped-away row must set `poll_throttled=False` and `stale_quota=False`, so
  `_throttle_admitted` cannot readmit X (`:5945`).
- `k(Y)+n(D) ≤ KMAX−1` mixes resident n(D) with the active KMAX (24). Also check `KMAX_RESIDENT` (40)
  (gap-3 §1), and count headless `-p` children in n(D).
- The `nudge` subcommand (R2) is missing from the §5.2 CLI. A manual operator nudge must apply the same
  record gate as cc-wake (`:212`).
- Order inside `lr-reset-poller`: `back` before the at-reset resumes.
- The author's `launchctl print` broke the brief's rule. It was read-only and nothing depends on it,
  but it is recorded here as a process defect.

### R.3 What holds under attack

- **Move semantics plus all three locks, in Claude Code's order.** This is the right shape. The
  binary confirms that storage-write wraps every mutate, compare-and-clear included, so a flipper
  holding all three cannot be silently reverted *while it holds them* (R.1). D5 bounds the residual.
- **Refusing mixed directories** whose file carries `claudeAiOauth` (t5), and the F4 file-clean on
  write-back.
- **R8's analysis is correct.** The heal gate keys on the account count (`:1939`, `:1964`), so the
  overlay opens it. The fence is necessary; D1 adds the missing third door.
- **No draft loss through the socket transport** (`cc-wake:14-20`).
- **Sequencing.** OPERATOR, Gate 0 before any credential work, and P0 as the only agent work. P0's
  `--confirm` and live-service refusals mirror `e1-concurrent-logins.sh:118-122`. Add NFC to `svc()`
  (R.1).

### R.4 Required changes (summary, in order of blast radius)

1. Fence every credential redeemer, including `handoff-fire.sh` `phase1_relogin` (`:13107`, gate `:13255`) and `--relogin-info` (`:11141`). Pin the writer count (D1).
2. Make attribution time-aware (`acct_at(cfg, t)`), with an ambiguity band that writes neither facts nor contradictions. Use the death's `resetsAt` as the tiebreak. Add t13's red case "X's pre-flip death writes no Y fact". Correct finding 5's stated harm (D2).
3. Overlay only census and billing `by_dir` sites. Keep the source-semantics sites (`:6526`, `:6603`, `:11266`) on the record's `source_acct`. Overlay before the `.claude` fold. Pin 6 sites (D3).
4. Never SIGKILL `auth login`. Detach it, and use an in-flight marker and proof by store re-read. A 400 after our own abandonment is `suspect`, not `dead` (D4).
5. Bound the whole lock hold at ≤ 5 s with ~1.5 s per `security` call, and resolve a timed-out write under the same hold (D5).
6. Key uniqueness on grant family (cliff ±60 s) plus RT fingerprint, over items **and** `.credentials.json`. Bank rows read `TOMBSTONE`/`IN_USE`, and Gates 3 and R4 are rewritten (D6).
7. Restrict FLIP-WAIT and FLIP-NUDGE to non-actuated substates (never PLANNED or IN-FLIGHT). Make the nudge a claimed, admitted actuator, idle-only, with the HANDOFF.json check and a pending-frame hold. Only the reconciler mutates records (D7).
8. Flip-back gets a non-optional PRI-31 owner. Refuse when X's reset is unknown. Spare cliff ≥ X's reset + 2 d. Evacuate D via relaunch before the spare's cliff when `back` is impossible (D8).
9. Recovery decides by family placement. Add crash-after-write tests, and run `recover` every pass while a journal is open (D9).
10. Reap stale locks at 2× Claude Code's stale bound and page on each reap (D10).
11. Make preflight tri-state (unmeasured → 75). `plan` runs off-pass (D11).
12. Writers run at priority 31 or exit 75. The panic path signals rather than writes (D12).
13. Fence cc-notify and cloud-create-api while flipped (D13).
14. Bank-slot ownership checks. `single_flight` on every writer subcommand (D14).
15. Fix T1's oracle schedule or add a capped-P control, and re-estimate the calendar (D15).
16. One combined FLIP-WAIT and FLIP-NUDGE budget that never delays a PLANNED move. Correct the bound arithmetic (D16).
17. Move the cc-relogin fence to `run()` `:997`/`:1015` (D17). Inject the overlay as a parameter and honour `CC_CRED_FLIP_STATE_DIR` everywhere (D18). Fix the minors (D19). Restate R4 as grant-scoped (R.1).

**Adjusted conviction: 14%** that a safe, unattended B′ is reachable and worth its cost. That is down
from 20%, for the added fence surface (D1, D3, D13), the time-aware attribution (D2) and the
`auth login` replay hazard (D4).
