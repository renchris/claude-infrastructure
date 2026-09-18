# The KittyChildMon SIGSEGV is in the STOCK build too — the patched sandbox is exonerated (2026-09-17)

Closes cc-backlog `fd1c840434a5`, *"kitty title band: one unattributed sandbox segfault in the
patched build"*, filed with `whyNotNow: not-yet-true — it happened once in six sandbox runs and
did not recur, so there is nothing to bisect until it reproduces`.

**The premise is REFUTED in its load-bearing word.** The crash is not peculiar to the patched
build and was never unattributed-in-principle. `/Applications/kitty.app` — the operator's stock
binary, mtime **2026-07-30 06:50**, carrying no patch of ours — crashed with the *same
signature* on **2026-09-15 00:15:22**, about **42 hours before the sandbox build that crashed
was even linked**. It is an upstream kitty/GLFW defect on the child-monitor thread.

Run it yourself:

    python3 scripts/kitty-crash-attribute.py ~/Library/Logs/DiagnosticReports/kitty-2026-09-15-001522.ips

## Why the two reports are the same crash

They do not *look* alike, which is the whole trap. Side by side:

| | stock, 2026-09-15 00:15:22 | sandbox, 2026-09-16 18:14:46 |
|---|---|---|
| binary | `/Applications/kitty.app` (mtime Jul 30) | `~/ktb/kitty` (linked 18:07:37, 7 min earlier) |
| faulting thread | 5, **KittyChildMon** | 5, **KittyChildMon** |
| f0 | `libobjc.A.dylib+38944` (`objc_msgSend`) | `libobjc.A.dylib+38944` (`objc_msgSend`) |
| f1 | `kitty.fast_data_types.so+67460` — *stripped* | `glfw-cocoa.so+62912` → `glfwPostEmptyEvent` |
| f2 | `_pthread_start` | `fast_data_types.so+35448` → `io_loop` |
| fault | `KERN_INVALID_ADDRESS at 0x000007b84c952d70` | `…at 0x00008a6b2c83db70` (PAC failure) |

The stock stack is **one frame shorter**, and that is not a difference in the bug — it is a tail
call. Disassembling the sandbox's symbol-bearing `glfw-cocoa.so`:

    _glfwPostEmptyEvent +108   b  "_objc_msgSend$performSelectorOnMainThread:withObject:waitUntilDone:"

`b`, not `bl`: the frame is torn down first, so in a frame-pointer walk `glfwPostEmptyEvent`
**does not appear at all** and `objc_msgSend`'s caller reads as `io_loop` directly. The sandbox
report caught the *other* call site in the same function, a real `bl` at +148, which is why it
kept its frame:

    _glfwPostEmptyEvent +136   adrp x19, …          ; a global ObjC object
                        +140   ldr  x0, [x19,#0x9d0]
                        +144   cbz  x0, …           ; NULL-checked …
                        +148   bl   _objc_msgSend$lock   ; … but not validity-checked
                        +152   <- the sandbox report's return address

So the pointer is non-NULL and stale — the guard passes and the message send faults. Both
reports are `glfwPostEmptyEvent` sending to a dead ObjC object from the child-monitor thread.

And the stock's stripped `+67460` **is** `io_loop`, proven rather than assumed: both builds'
function at that offset sets its thread name from a literal, and the literal is the same one the
report names.

    STOCK   +56 adrp x0 / +60 add x0, #0xe8c ; "KittyChildMon" / +64 bl _pthread_setname_np
    SANDBOX +56 adrp x0 / +60 add x0, #0xaa8 ; "KittyChildMon" / +64 bl _pthread_setname_np
    …
    STOCK   +140 blr x8   → crash return +144
    SANDBOX +144 blr x8   → crash return +148

Same prologue, same thread-name literal, same indirect call through a runtime-populated
function-pointer slot (kitty `dlopen`s its GLFW backend, which is why the target is a pointer
and not a bind — `dyld_info -fixups` has no `glfwPostEmptyEvent` entry in either build), and the
crash return address is the instruction after it in both. The 4-byte offset difference is one
extra instruction in the sandbox prologue.

## The falsifier could never have fired

Stored on the row:

> a second kitty crash report whose faulting thread is `io_loop -> glfwPostEmptyEvent` appears
> under `~/Library/Logs/DiagnosticReports/`

That text is **structurally unsatisfiable by the population that carries the bug**, for two
independent reasons, both of which are properties of *symbolication* rather than of the crash:

1. stock `kitty.fast_data_types.so` is stripped — `nm` yields only undefined imports — so
   `io_loop` has no name there and never will;
2. `glfwPostEmptyEvent` tail-calls `objc_msgSend`, so on the stock build its frame is **absent
   from the stack entirely**.

Only an unstripped local build renders the two names the falsifier asks for. The row could
therefore only ever be falsified by a *sandbox* recurrence — i.e. it was blind to exactly the
population it mattered for: the operator's ~55 live sessions on the stock app. Meanwhile it had
**already been satisfied in substance**, by a report sitting on disk at filing time. The
receipt's own command would have shown it:

    ls -t ~/Library/Logs/DiagnosticReports/kitty*.ips

The receipt quotes four entries from that listing and stops one line above
`kitty-2026-09-15-001522.ips`.

Separately, the falsifier is **prose**, and `cc-premise` shell-executes stored probes every 6 h,
so `-> glfwPostEmptyEvent` is a REDIRECT: it had been creating a zero-byte file named
`glfwPostEmptyEvent` in the shared checkout root (latest 2026-09-17 21:18; removed). That
general defect is already filed as `e0a8245ff5f6` and is not re-filed here. This row's probe is
now a command, keyed on what a stripped build still emits:

    faulting thread named "KittyChildMon", f0 imageOffset 38944, procPath under /Applications

## What the instrument can now do

`scripts/kitty-crash-attribute.py` previously stopped at *"internal (not a module-level
PyCFunction)"* for any frame that is not a Python entry point — which a thread entry never is.
It now recovers a function's own string literals (an `adrp`/`add` pair into `__cstring`; a third
table stripping cannot touch, for the same reason as the other two — the program reads it at
runtime) and reports a thread entry **only when the literal matches the name the report gives
the faulting thread**. Two independent facts agreeing, never an echo:

    f1  kitty.fast_data_types.so+67460  func 0x106f4+144
        -> thread entry for "KittyChildMon" (matched against the report's own thread name)

`tests/kitty-crash-attribute.bats` gains two cases over a redacted fixture, and they are
orthogonal — measured, not asserted. Against the pre-fix tool case 9 fails and case 10 passes;
against a mutant that trusts the report's thread name without checking the binary, case 9 passes
and case 10 fails. Each kills exactly one arm.

## What this does NOT establish

* **Not that the title band is blameless in general.** It is exonerated *for this crash class*
  only. The 13:5x / 20:13 main-thread family (`viewport_for_window`, NULL `fonts_data`) is a
  different bug, attributed separately in `kitty-crash-attribution-2026-09-17.md`.
* **Not a fix.** The upstream defect — `glfwPostEmptyEvent` messaging an unvalidated global ObjC
  pointer from a non-main thread — is in the operator's terminal binary and is not patched here,
  matching the precedent set for the `fonts_data` defect: exposed and recorded, not patched.
* **Not a frequency claim.** Two occurrences in the retained window (which rotates). Nothing here
  says how often it fires, only that the stock build does it.
