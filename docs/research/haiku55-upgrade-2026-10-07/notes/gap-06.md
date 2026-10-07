# Gap G6: does 2.1.293's native read-before-write guard cover `claude-haiku-5-5`?

## Answer

**No.** In the 2.1.293 binary the native read-before-write refusal for Write and Edit is still gated
on an exact-id set of 10 legacy models, and `claude-haiku-5-5` is not in it. The set is
byte-for-byte the same list as in 2.1.284. A Haiku 5.5 session (or subagent) on 2.1.293 can
therefore Write or Edit a file it never read, whenever a Read of that path would have been
auto-allowed by permissions.

Consequences for the fleet:

- `RBW_ENFORCED_MODELS` in `hooks/lib/read-before-write-parity.sh:168` needs **no change** for
  2.1.293. It already matches the binary's set, and because `claude-haiku-5-5` is outside it,
  `rbw_guard_disabled` returns 0 and the parity shim enforces for Haiku 5.5. That is the correct
  direction.
- The parity shim (plus `backup-before-write.sh`) is the only read-before-write protection a
  Haiku 5.5 code-writing teammate would have. The binary gives it none.
- Moving the `haiku` alias from 4.5 to 5.5 is a guard regression at the binary level: Haiku 4.5 is
  in the enforced set, Haiku 5.5 is not. Explore/retrieval spawns do not write, so this matters
  only for a code-writing role.

## Evidence

All offsets measured with Python `mmap.find` on
`~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (236,330,608 bytes) and
`~/.claude-284/.../claude.exe` (226,563,088 bytes). Neither binary was executed.

### 1. The enforced set and the predicate (2.1.293, byte 187977738)

```
var yi=new Set(["claude-opus-4-6","claude-haiku-4-5","claude-opus-4-5","claude-opus-4-1",
"claude-opus-4-0","claude-sonnet-4-5","claude-sonnet-4-0","claude-3-7-sonnet",
"claude-3-5-sonnet","claude-3-5-haiku"]);
function Ho(e){return yi.has(It(e))}
function n5t(e,n){if(n===void 0)return Ho(e);return n.model!==void 0&&Ho(n.model)}
```

`n5t` is 2.1.293's name for 2.1.284's `kNt`; `yi` is the old `zr`. The 2.1.284 copy (byte
180978029) holds the same 10 ids in the same order:

```
var zr=new Set(["claude-opus-4-6","claude-haiku-4-5","claude-opus-4-5","claude-opus-4-1",
"claude-opus-4-0","claude-sonnet-4-5","claude-sonnet-4-0","claude-3-7-sonnet",
"claude-3-5-sonnet","claude-3-5-haiku"]);function Bt(e){return zr.has(Jt(e))}
function kNt(e,n){if(n===void 0)return Bt(e);return n.model!==void 0&&Bt(n.model)}
```

The normalizer applied before the set test only strips the 1M suffix (2.1.293, byte 184284381):

```
function It(e){return e.replace(/\[1m\]$/i,"")}
```

The string `claude-haiku-5-5` occurs 21 times in 2.1.293 (0 times in 2.1.284); none of the 21
offsets is inside the set literal at 187977738-187977990. The nearest are the model-table entries
at 184392112-184392430 and unrelated hits at 186775990 and later.

### 2. Where the predicate is used (2.1.293): four call sites, two tools

Write, `validateInput` (byte 192868088):

```
let Se=s.readFileState.get(M);if(!Se||Se.isPartialView){let Ce=Be(s.model()),xe=L8t(Ce),
Ie=!Se&&!bEt(M)&&!n5t(Ce,s.remoteCall)&&Yae(tn,M,s,s.permissions()), ...
i("tengu_write_tool_not_read_hypothetical",{...,guardSkipped:Ie,modelBucket:xe,...}),
!Ie)return{result:!1,message:SXt,errorCode:2};
```

`SXt` is `"File has not been read yet. Read it first before writing to it."` (byte 185332785).
So the refusal is returned only when `guardSkipped` (`Ie`) is false. `Ie` is true when all four
hold: no read record at all for the file (`!Se`), the path is not in the `bEt` class, the model is
**not** in the enforced set (`!n5t`), and `Yae(...)` is true. `Yae` is
`function Yae(e,n,r,s){return!Tf(e,r)&&Af(n,s)}` (byte 188645434); the write-time call passes it
as `readNotAutoAllowed:()=>!Yae(...)`, so `Yae` true means "a Read of this path would be
auto-allowed".

Write, call time (byte 192870455), same gate re-checked in `Ieo` (byte 192864100):

```
preReadGuard:n5t(Be(r.model()),r.remoteCall), ...
if(!s||s.isPartialView){if(!s&&!bEt(e)&&!g&&!w()){ ... return}throw new Jne(SXt)}
```

Edit, `validateInput` (byte 196213872) and call time (byte 196217629, helper `VFr` at 196221240),
same shape: `it=!n5t(st,s.remoteCall)&&Yae(wt,q,s,s.permissions())`, then
`!it)return{result:!1,behavior:"ask",message:SXt,...,errorCode:6}`.

For `claude-haiku-5-5`, `n5t` is false, so the guard is skipped for any never-read file whose Read
would be auto-allowed. The guard still fires for Haiku 5.5 in these narrower cases, read directly
from the code above: the file was seen only as a partial view (`isPartialView`), the path is in
the `bEt` class, or a Read of the path would not be auto-allowed.

The 2.1.284 call sites (bytes 185491986, 185494348, 188405929, 188409681) have the identical
shape with `kNt`, so the behavior the shim was built against is unchanged in 2.1.293.

NotebookEdit is not model-gated in either binary (2.1.293 byte 196226954):
`let Y=e.readFileState.get(G);if(!Y)return{result:!1,message:"File has not been read yet. Read it first before writing to it.",errorCode:9}`.

### 3. No flag re-arms it

`velvet_mallet` occurs 0 times in 2.1.293 (measured, `mmap.find`). The predicate reads only the
hard-coded set; there is no feature-flag lookup in `Ho`/`n5t`.

### 4. Changelog

`pack/cc-changelog.md` lines 3-815 (2.1.285-2.1.293): no entry mentions read-before-write, "not
been read", or the Write guard (measured: `grep -n -i 'read-before\|read it first\|not been read'`
returns only lines 3522, 4417, 4722, all outside the band). NOT STATED there; the binary is the
only source.

### 5. The shim (fleet repo)

- `hooks/lib/read-before-write-parity.sh:168`: `RBW_ENFORCED_MODELS` lists the same 10 ids as the
  2.1.293 set. No edit needed; only the comment at :165 ("2.1.284's `zr`, the exact-id set kNt()
  tests") is stale on the names (`yi`, `n5t` in 2.1.293).
- `:178-186` `rbw_guard_disabled`: strips `[1m]`/`[1M]`, exact compare, unknown id returns 0
  (enforce). `claude-haiku-5-5` returns 0. Read from the code, not run.
- `tests/read-before-write-parity.bats:147` proves only the Haiku 4.5 allow arm.
  `:177-185` asserts rc 0 for `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-opus-5`; there is no
  `claude-haiku-5-5` row. Adding `[ "$(gd_rc claude-haiku-5-5)" -eq 0 ]` there (and a deny case
  beside :151-159) would pin the answer above. Not done here (read-only brief).

## What remains unknown

1. **Live behavior was not run.** Everything above is static reading of the binary. Settling
   measurement: on 2.1.293, in a scratch directory with hooks disabled, have a `claude-haiku-5-5`
   session Write to an existing file it has not read; expect success with no "File has not been
   read yet" error. Repeat with the fleet hooks on; expect the parity shim to deny.
2. **The canonicalizer `Be(s.model())` was not identified.** It is a chunk-local alias and several
   unrelated `function Be(` definitions exist. The 2.1.293 model table gives Haiku 5.5's
   first-party id as the bare `claude-haiku-5-5` (byte 184392112, `provider_ids.first_party`), so
   no plausible canonicalization maps it into the 10-id set; but this is inferred, not read.
3. **What model id the shim sees for a Haiku 5.5 subagent.** The shim reads `.message.model` from
   the transcript (census D1). If the transcript carries a dated or provider-prefixed id, the exact
   compare still lands outside the set and the shim enforces, so the direction is safe. The
   pre-existing census concern is the opposite case: a dated `claude-haiku-4-5-20251001` makes the
   shim enforce where the binary also enforces (a double guard, not a hole). Settling measurement:
   read `.message.model` from one Haiku 5.5 subagent transcript on 2.1.293.
4. **Whether the shim hook fires inside subagents and teammates on 2.1.293**, which is where a
   Haiku 5.5 code-writing role would run. `cc293-axis3.md:139` already asks to verify
   `backup-before-write.sh` fires on 293; the same probe should cover the parity shim.
5. **What the `bEt` path class is.** Its body is `_0(e.replace(/[. ]+$/,""))` (byte 192864084);
   `_0` was not followed. It only widens the native guard, so it does not change the answer.
