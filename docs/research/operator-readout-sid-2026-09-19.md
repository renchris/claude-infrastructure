# The ⏳ sensor reads UNKNOWN because its caller withholds the session id it is holding

**2026-09-19 · `hooks/operator-readout.sh` · `scripts/wrap-ledger.sh` · `hooks/lib/session-busy.sh`**

## The finding

`tests/operator-readout.bats` is the only genuinely red suite of the five the postland stamps name
(the other four measure green on trunk — see §3). Its two failures are both in the `busy` arm and
both assert that a `⏳` working-vs-idling line renders:

```
not ok 111 busy: 🔧 with no steps — silent today — now says IDLE with no wake path armed
not ok 112 busy: EDGE, not level — the same line inside TTL is damped, not repeated
```

**Chain, read end to end:**

1. `hooks/operator-readout.sh` parses `session_id` from its own stdin JSON in hook mode (`SID=` at
   the top of the hook-mode block) — so it HOLDS the id.
2. Inside `render_block` it calls `bash "$wrap" --machine` — **without `--session`**.
3. `scripts/wrap-ledger.sh:628-638` resolves the id as
   `--session > WRAP_SESSION_ID > CLAUDE_SESSION_ID > CLAUDE_CODE_SESSION_ID > unresolvable`.
4. With none of those, `hooks/lib/session-busy.sh:385` returns `UNKNOWN 0 0 none no-session-id`.
5. The `⏳` line never renders.

In an ordinary session the **env arm** supplies the id, which is why this has looked correct for
months. It bites in every invocation where that variable is not ambient: a hermetic `env -i` test,
a launchd job, a daemon, anything re-exec'd through a clean environment. An instrument reporting
*"I could not read"* because its caller withheld a value it was holding is a plumbing defect, not
an honest abstention.

`wrap-ledger.sh:267` already records the shape, though as a note about the CACHE KEY rather than as
a design ruling: *"completion-assert passes `--session $SID`, the other six do not, and the resolved
SID changes YOURS/BLOCKED."*

## 2. Why the obvious patch is not obviously right

Passing `--session "$SID"` on the existing `--machine` read cures both busy tests — measured,
`112 ok / 2 not ok` → `113 ok / 1 not ok`. It also **regresses** test 57, *"YOURS fires the block
alone: session-filed step + every other class empty + ✅ git"*, which pins the headline
`OPERATOR ▸ 1 step(s) are yours · ✅ live on trunk`.

That is the warned-about consequence: a resolved sid changes `YOURS`/`BLOCKED`, and those feed the
rung. The close protocol's own definition of `👤` is *"agent side complete AND landed, but
operator-only step(s) THIS SESSION filed are unrun"* — which describes test 57's fixture exactly,
so the post-patch rung may be the CORRECT one and the pinned `✅` an artifact of the id never
arriving. **That reading is not verified**: the confirming single-test run was refused three times
by the bats admission ceiling (two other sessions holding both slots at 0.0% idle), so the actual
post-patch headline has not been read. It is inference, and it is why this is filed rather than
landed.

A narrower alternative — a second, session-scoped `--busy` read purely for the sensor — is
**blocked by a documented invariant**: the busy globals are deliberately published from "the ledger
read that ALREADY happens here … the reason this costs zero extra forks", under C19, *"no new fork
may enter render_block"*.

**RESOLVED the same session — the packet needed no ruling.** The blocker above was stated as "the
bats ceiling refused the confirming run", which was never irreducible: the hermetic off-box runner
was working throughout, and test 57's fixture reproduces by hand in one script. Measured inside it:

| ledger call | RUNG | YOURS |
|---|---|---|
| `--machine` (as shipped) | `✅` | 0 |
| `--machine --session S6` | **`👤`** | **1** |

The close protocol defines `👤` as *"agent side complete AND landed, but operator-only step(s) THIS
SESSION filed are unrun"* — which is that fixture exactly. So the unscoped read was emitting the
precise false-done the `👤` rung exists to prevent, and the suite's `· ✅ live on trunk` assertion
was **pinning the defect** (memory: `stale-assertion-becomes-an-inverted-guard`). The headline loses
its rung clause because the renderer does not append "· 👤 …" when "1 step(s) are yours" already
says it. Fix landed, assertion corrected, suite 114/114 green. Decision packet `a19269213ce1`
closed on evidence rather than ruled on.

One more self-inflicted method error on the way, the third of this session: the first controlled
comparison showed the `--session` arm emitting NOTHING, which read as the ledger failing on an
unresolvable id. That was the probe, not the subject — **zsh does not word-split an unquoted
`$arg`**, so `--session S6` arrived as a single argument. Re-run through `bash -c` with `set --`,
both arms produced clean output and the real answer. The repo already carries this one
(`verification-harness-vacuous-pass-traps`: *zsh … never word-splits*).

## 3. The population correction this investigation produced

The "five standing reds" framing is mostly an instrument artifact. Measured on current trunk with
the hermetic runner:

| suite | verdict |
|---|---|
| `tests/kitty-conf-bindings.bats` | green 33/0 |
| `tests/mailbox-drain.bats` | green 57/0 |
| `tests/pipefail-sigpipe-lint.bats` | green 28/0 |
| `tests/cc-permission-harvest.bats` | green 61/0 |
| `tests/operator-readout.bats` | **red 112/2** |

The other four appear in the stamps' `failing` field because their runs were **cut**, and the
machine's own adjudication already says so: `~/.claude/autonomy/postland/flakes.jsonl` records
`cut-not-red` 31× for operator-readout, 4× for pipefail-sigpipe-lint, 3× for mailbox-drain, and
`1-of-3` (acquitted) 7× for cc-permission-harvest. A consumer reading `failing` without joining the
flake store over-counts the red population — which is what depresses the verification net's green
rate and keeps it from certifying.

## 4. Two method warnings, both self-inflicted here

- **`LC_ALL=C` was wrongly convicted.** A first A/B showed `⏳` under UTF-8 and not under `C` — but
  both arms shared one state dir and one session key, so the second was damped by the edge-latch
  working correctly. With isolated state per arm it fires in all four cells (both locales, both
  orders). The subject reads its own last output; give each arm a private store.
- **`CC_OFFBOX=1` was wrongly suspected** for the same reason — it reproduces with and without, once
  `env -i` is applied to both arms. The differentiator was never a single variable; it was the
  absence of the whole ambient environment, and specifically of `CLAUDE_CODE_SESSION_ID`.
