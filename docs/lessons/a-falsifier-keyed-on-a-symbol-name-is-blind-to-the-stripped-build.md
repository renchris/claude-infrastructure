# A falsifier keyed on a SYMBOL NAME is blind to the stripped build

**The rule.** When a probe asks whether a crash/trace *"whose frames are A -> B"* recurs, it is
not asking about the fault. It is asking about **symbolication**, which is a property of the
binary that produced the report — and the production binary is usually the one that cannot
answer. Key such a probe on something the production build still emits: the thread name, the
faulting image + offset, the signal and fault address. Never on a symbol the stripped build
does not carry.

## The incident (cc-backlog `fd1c840434a5`, 2026-09-17)

A row recorded *"one unattributed sandbox segfault in the patched build"* with the falsifier:

> a second kitty crash report whose faulting thread is `io_loop -> glfwPostEmptyEvent` appears
> under `~/Library/Logs/DiagnosticReports/`

Two independent reasons that text can never be produced by the shipped app, and **both are
facts about the build, not about the bug**:

1. the shipped `kitty.fast_data_types.so` is **stripped** — `nm` yields only undefined imports —
   so `io_loop` has no name in it and never will;
2. `glfwPostEmptyEvent` **tail-calls** `objc_msgSend` (`b`, not `bl`), so its frame is torn down
   before the fault and **does not appear in the stack at all**.

Only the unstripped local sandbox build renders both names. So the probe could be satisfied
*only* by a sandbox run — while the population that mattered was the operator's ~55 live
sessions on `/Applications/kitty.app`. The row's own framing ("in the patched build") then
followed from the blindness rather than from evidence.

It was already false when filed. The stock app had crashed with the same signature on
2026-09-15 00:15:22, ~42 h **before** the patched build was linked. The receipt's own command
would have shown it — it quotes four lines of `ls -t` and stops one line above the file.

## What the probe should have been

The parts the stripped build still emits, and which both reports share byte-for-byte:

    faulting thread named "KittyChildMon", f0 = libobjc.A.dylib+38944, SIGSEGV

That is checkable against any build. The names came back afterwards, from evidence stripping
cannot remove — a function's own string literals — but that is a *recovery* method, not
something a falsifier may presuppose.

## The generalisation

Any probe whose text is producible only by the instrumented variant of a subject — debug
symbols, an unstripped build, a verbose log level, a dev-only error string — certifies silence
over the production variant. And its silence reads as **agreement**: nothing recurred, so the
premise stands. Ask of every falsifier: *which build, log level or mode must the subject be in
for this string to exist at all?* If the answer is not "the one it runs in", the probe is
measuring the instrument.

Companions: [[superseded-stranded-and-the-falsifier-cannot-tell-them-apart]] (measure the
FEATURE, not the bytes), [[a-falsifier-resting-on-a-frozen-pointer-is-inert-and-inertness-r]]
(a falsifier is only as live as the store it reads),
[[fixture-identifier-shape-collapses-two-spaces]] (one shape for two spaces hides the defect).

Record: `docs/research/kitty-childmon-crash-attribution-2026-09-17.md`.
