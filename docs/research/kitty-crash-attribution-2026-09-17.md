# The kitty title-band SIGSEGV IS attributable on this box — `viewport_for_window`, NULL `fonts_data`

**Disproof of cc-backlog `bf6af099a712`**, whose premise reads *"crash NOT attributable on this
box"* and whose `whyNotNow` reads *"the shipped kitty.fast_data_types.so is stripped to 8 exported
symbols, so the faulting offset 840952 resolves to no function here; attribution needs a
symbol-bearing build or a sandbox reproduction."*

Both named routes were unnecessary. A third one attributes the crash in one command, from the
binary already on disk, with no reproduction and no rebuild.

## The answer

| crash | fault | function | faulting instruction |
|---|---|---|---|
| 2026-09-16 20:13:49 | `0x20` | **`viewport_for_window`** +200 | `ldp w21,w23,[x8,#0x20]` |
| 2026-09-16 13:58:06 | `0x8` | `os_window_regions` +72, entered from **`update_pointer_shape`** | `ldp d1,d2,[x12,#0x8]` |
| 2026-09-16 13:58:14 | `0x8` | identical to 13:58:06 | identical |
| 2026-09-16 13:56:59 | `0x0` | **unattributed** — pc is 0 | (no instruction; see Honest boundary) |
| 2026-09-16 13:57:17 | `0x0` | **unattributed** — pc is 0 | (no instruction) |

**One root cause, not a family.** Both attributed signatures are the same NULL field:

    cd4f4: ldr x8,  [x19, #0x190]    ; x8 = os_window->fonts_data
    cd4f8: ldp w21, w23, [x8, #0x20] ; <- FAULT: fcm.cell_width / fcm.cell_height

`FONTS_DATA_HEAD` (kitty/data-types.h:282) is `sprite_map`(+0), `logical_dpi_x`(+8),
`logical_dpi_y`(+0x10), `font_sz_in_pts`(+0x18), `fcm`(+0x20). So a NULL `fonts_data`
dereferenced for `fcm.cell_width` faults at **exactly `0x20`**, and dereferenced for
`logical_dpi_x/y` faults at **exactly `0x8`** — which is the other cluster, via
`pt_to_px_for_os_window()` inlined into `os_window_regions` (kitty/state.c:727; the deref
is at :735 and :773). The two fault
addresses that looked like two different bugs are two different FIELDS of one NULL pointer.

Source, stock 0.48.2 (`kitty/state.c:1038`, deref at :1047), unguarded:

    PYWRAP1(viewport_for_window) {
        ...
        WITH_OS_WINDOW(os_window_id)
            os_window_regions(os_window, &central, &tab_bar);
            vw = os_window->viewport_width; vh = os_window->viewport_height;
            cell_width = os_window->fonts_data->fcm.cell_width; cell_height = ...;

`WITH_OS_WINDOW` guards the *window* lookup, which is why the prior note correctly refuted "a NULL
window falls through the lookup". It does not guard `fonts_data`, and nothing else does either.

**Where the NULL comes from.** `fonts_data` is written NULL in exactly one place —
`restore_window_font_groups()` (kitty/fonts.c:197), which NULLs it for *every* OS window and then
re-resolves each by saved id, **leaving it NULL on a lookup miss**. It is reached from
`add_font_group()` → `trim_unused_font_groups()`, i.e. on font-group churn: a DPI change, a font
size change, or a config reload that changes font settings. `trim_unused_font_groups` also
`memmove`s the `font_groups` array and `add_font_group` `realloc`s it, which is why the bracket
exists at all — `fonts_data` points *into* that array.

⚠️ **Every line number here is against PRISTINE 0.48.2 (`git show HEAD:kitty/state.c` in a
0.48.2 checkout), NOT against a local build tree.** `~/k482` carries the band patch, which inserts
37 lines at state.c:1748 — so every citation *after* that point shifts, and the first draft of this
note duly cited the `MW()` registrations 37 lines too high. If you re-derive these, read the stock
file.

⚠️ **And the unguarded deref is not confined to the two functions named above.**
`os_window->fonts_data->...` is dereferenced with no NULL check at state.c:494, 514, 715, 750, 764,
1047, 1059 and 1344 in stock 0.48.2. The two attributed here are simply the two that were reached.

## The method — why the symbol table was the wrong place to look

`nm` on the shipped `.so` yields only undefined imports, so the item concluded the name was
unrecoverable. Two other tables survive stripping:

1. **`LC_FUNCTION_STARTS`** — a ULEB128 delta list of every function's start offset. Present
   (2,912 bytes / 1,645 functions in the arm64 slice). It gives *bounds*, so a pc anywhere inside
   a function maps to that function's entry.
2. **The module's `PyMethodDef` arrays** — `{const char *ml_name; PyCFunction ml_meth; int
   ml_flags; const char *ml_doc;}`. These **cannot** be stripped: CPython reads them at import
   time to build the module. So every Python-callable entry point has its **name, in cleartext,
   next to its address**, in `__DATA`/`__DATA_CONST` with both pointers relocated.

Intersect them and any frame whose caller is `cfunction_call` resolves exactly. **496** named
entries were recovered from the shipped binary this way.

Two independent confirmations that this is a reading and not a story:

* **`ml_flags` agrees with source.** The tool recovered `ml_flags=1` for both
  `viewport_for_window` and `update_pointer_shape`; stock source registers both as
  `MW(..., METH_VARARGS)` (state.c:1844 and :1806) and `METH_VARARGS == 1`.
* **The faulting instruction's dereference offset equals the fault address.** Decoding
  `0x29445d15` gives `ldp` at `+0x20`; the report says `KERN_INVALID_ADDRESS at 0x20`. That is
  what takes the attribution from *consistent with* to *proven*, and the tool asserts it itself.

## Positive control

The whole method rests on "a `PyMethodDef` `ml_meth` is a function entry address". The arm that
could refute it: rebuild the map from a build where `nm` *does* work, and check every recovered
address against the symbol table. Against `~/k482/kitty/fast_data_types.so` (a symbol-bearing
0.48.2 build, 1,670 text symbols):

    494 method-table entries recovered
      name agrees with nm symbol : 418
      python name != C symbol    : 76    <- expected: MW() renames, e.g. set_iutf8_winid -> _pyset_iutf8
      address not in nm          : 0
      addresses that ARE real function symbols: 494/494 (100.0%)

Zero unmapped. The 76 "disagreements" are the Python-visible name differing from the C symbol
name, which is the *more* useful of the two for attributing a `cfunction_call` frame. And both
targets resolve: `viewport_for_window` → `_pyviewport_for_window`,
`update_pointer_shape` → `_pyupdate_pointer_shape`.

## Honest boundary — what this does NOT establish

* **The 13:56:59 and 13:57:17 crashes are still unattributed.** Their pc is **0** — a jump through
  a NULL or clobbered code pointer, with `cfunction_call` as the caller. There is no
  `fast_data_types` frame to name, so this method cannot reach them; they are a different fault
  shape (invalid *code* pointer) from the three data dereferences above. They may or may not share
  a cause.
* **This does not establish that the title-band shim CAUSED the crash.** It establishes what
  crashed and why it crashed. The shim is a live candidate for the *trigger* — it calls
  `cell_size_for_window`, which carries the byte-identical unguarded
  `os_window->fonts_data->fcm.cell_width` deref one function below `viewport_for_window`
  (state.c:1054, deref at :1059) — but nothing here measures that it drove the font-group churn. The conjunction
  hypothesis in `kitty-title-band-crash-population-2026-09-16.md` is untouched by this note.
* **The map is per-build.** Offsets do not transfer. The tool refuses on a report/binary UUID
  mismatch rather than emitting a name, because its own first draft attributed two sandbox
  crashes against the shipped map.

## The upstream defect this exposes

`kitty.fast_data_types` exports `viewport_for_window`, `cell_size_for_window` and
`update_pointer_shape` to Python with **no NULL guard on `fonts_data`**, while `fonts_data` has a
window in which it is legitimately NULL and can stay NULL. Any Python caller — a kitten, a
`--watcher` module, a `kitty @` remote-control call, or kitty's own `boss.py`/`tabs.py` layout
paths — can therefore take the whole terminal down, and on this box that is ~55 sessions. Filed
rather than patched: the remedy is a change to the operator's terminal binary, which is an
escalation surface, and the shim that makes it reachable is currently disarmed.

## Re-derive it

    scripts/kitty-crash-attribute.py <report.ips>
    scripts/kitty-crash-attribute.py --control <stripped.so> --against <symbolized.so>

Pinned by `tests/kitty-crash-attribute.bats` (8 cases) over redacted fixtures in
`tests/fixtures/`, so the suite does not depend on `~/Library/Logs/DiagnosticReports`, which
rotates. Every case needing the shipped binary SKIPS on a UUID change, so a kitty upgrade retires
the case instead of reddening it. Three mutants, each killing exactly one case and no other:
removing the UUID check kills the refusal guard; removing the pc==0 check kills the
unattributable guard; removing the instruction decode kills the self-verification.
