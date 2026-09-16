# Upstream-grade quality: option naming, docs, tests, and the diff's shape

Axis: what "100th-percentile clean code" means for the proposed `render_a_bar`-based
overlay title band, measured against **kitty's own conventions**, not against taste.

**Trees.** Every `file:line` below is tagged with the tree it was read in:
- `~/kitty-482` = detached at `v0.48.2` (`2cb1d95c3`) — **the build the operator runs**.
- `~/kitty-dev` = master `1d67ecd47` (nightly-21).
Where the two differ materially it is stated.

**Status legend.** CONFIRMED = read in the tree at the cited line, or the exact command
and its output is shown. UNMEASURED = could not be executed on this box (build cost,
safety rules); stated as a gap, never reasoned into a confirmation.

---

## 0. Headline

The proposed design is **not a new subsystem**; it is a *third consumer* of machinery
that already has two in-tree consumers, one of which **already draws this exact thing**:
`draw_window_number` (`~/kitty-482 kitty/shaders.c:938-943`) already calls
`render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false)` to paint the
**window title** as a bar at the **top** of the window, over content, outside the cell
grid, in the system font — today, in the shipped binary, whenever the window-number
overlay is up. The patch is therefore "make that path reachable from an option and add a
hit-test region", which is a materially smaller and more defensible diff than "add an
overlay title bar".

That reframing is the single most important thing for upstream acceptance: the PR is
**not** proposing a new rendering path, it is proposing a policy option over an existing
one. Say so in the first paragraph of the PR body.

---

## 1. How one option is declared end to end, and the complete file checklist

### 1.1 The source of truth is exactly one file

`~/kitty-482/kitty/options/definition.py:1` carries its own instruction:

```
#!/usr/bin/env python
# License: GPLv3 Copyright: 2021, Kovid Goyal <kovid at kovidgoyal.net>

# After editing this file run ./gen-config.py to apply the changes
```

⚠️ **That comment is stale in v0.48.2 and in master.** There is no `./gen-config.py`:

```
$ cd ~/kitty-482 && ls gen*
__init__.py  __main__.py  apc_parsers.py  bitfields.py  color_names.py  config.py
cursors.py  go_code.py  key_constants.py  README.rst  rowcolumn-diacritics.txt
srgb_lut.py  wcwidth.py
$ cat gen-config.py
cat: gen-config.py: No such file or directory
```

The generator moved into the `gen` package. The real command is section 1.4.

### 1.2 The existing `window_title_bar` family, verbatim

`~/kitty-482/kitty/options/definition.py:1940-2031` (the `opt('window_title_bar', …)` call opens at :1941, `window_title_bar_align` is :2031):

```python
opt(
    'window_title_bar',
    'top',
    choices=('top', 'bottom'),
    long_text="""
Control the position of the window title bar relative to the window content.
Use :opt:`window_title_bar_min_windows` to control when title bars are shown.
Use :opt:`window_title_template` to format the displayed window title.
""",
)

opt(
    'window_title_bar_min_windows',
    '0',
    option_type='positive_int',
    long_text=...
)
...
opt('window_title_bar_align', 'center', choices=('left', 'center', 'right'),
    long_text='Horizontal alignment of the text in window title bars.')
```

Note what this family does **not** do: `window_title_bar`, `window_title_bar_min_windows`
and `window_title_bar_align` carry **no `ctype`**. They are consumed entirely in Python —
`~/kitty-482/kitty/tabs.py:1890` (`min_windows`), `:1998` and `:2068`
(`opts.window_title_bar == 'top'`), `~/kitty-482/kitty/window.py:1055`
(`position = opts.window_title_bar`). Only the four *colour* members of the family carry a
`ctype` (`color_or_none_as_int`), and they reach C via the generated header
(`~/kitty-482/kitty/options/to-c-generated.h:1023-1070`).

**This matters for our option**: if the band is drawn in C (`render_a_bar`), the new
option *does* need a `ctype`, unlike its three closest siblings. That asymmetry must be
justified in the PR or a reviewer will ask.

### 1.3 The model to copy: `scrollbar`

`scrollbar` is the right template — a `choices` option with a `ctype`, consumed by the C
renderer. Its five hops, all CONFIRMED in `~/kitty-482`:

| # | File | Line | Content |
|---|---|---|---|
| 1 | `kitty/options/definition.py` | 530 | `opt('scrollbar','scrolled', ctype='scrollbar', choices=(...), long_text=...)` — **hand-edited** |
| 2 | `kitty/options/types.py` | 33 | `choices_for_scrollbar = typing.Literal['scrolled','always','never','hovered','scrolled-and-hovered']` — **generated** |
| 2b | `kitty/options/types.py` | 436 | name added to the `option_names` tuple — **generated** |
| 2c | `kitty/options/types.py` | 646 | `scrollbar: choices_for_scrollbar = 'scrolled'` in the `Options` class — **generated** |
| 3 | `kitty/options/parse.py` | 1264-1270 | `def scrollbar(self, val, ans)` + `choices_for_scrollbar = frozenset((...))` — **generated** |
| 4 | `kitty/options/to-c-generated.h` | 256-266 | `convert_from_python_scrollbar` / `convert_from_opts_scrollbar`, plus a call at line 1569 in the master convert function — **generated** |
| 5 | `kitty/options/to-c.h` | 62-70 | `static inline ScrollbarVisibilityPolicy scrollbar(PyObject *src)` — **hand-written**, the name must equal the `ctype` string |
| 6 | `kitty/data-types.h` | 118 | `typedef enum { SCROLLBAR_NEVER, ... } ScrollbarVisibilityPolicy;` — **hand-written** |
| 7 | `kitty/state.h` | 89 | `ScrollbarVisibilityPolicy scrollbar;` inside the `Options` struct — **hand-written** |
| 8 | consumer | `kitty/shaders.c:828` | `case SCROLLBAR_ALWAYS: return true;` via `OPT(scrollbar)`; `#define OPT(name) global_state.opts.name` is `kitty/state.h:19` |

So: **four hand-edited files** (`definition.py`, `to-c.h`, `data-types.h`, `state.h`) and
**three generated files** that must be regenerated and committed (`types.py`, `parse.py`,
`to-c-generated.h`).

Note hop 5's contract, which is easy to get wrong: the C function's **name is the `ctype`
string**, and the generator emits `opts->NAME = CTYPE(val);`
(`~/kitty-482/kitty/options/to-c-generated.h:256-258`). A `ctype` prefixed with `!`
(e.g. `ctype='!tab_bar_style'`, `ctype='!focus_follows_mouse'` in
`~/kitty-482/kitty/options/definition.py`) means "the converter is a *statement*, not an
assignment" — used when one option writes several struct fields. Our option is a plain
enum, so it uses the unprefixed form.

### 1.4 The exact generator command

`~/kitty-482/gen/config.py:66-71` is the writer, and `~/kitty-482/kitty/conf/generate.py:464-483`
(`write_output`) names the three outputs:

```python
with open(os.path.join(*loc.split('.'), 'options', 'types.py'), 'w') as f: ...
with open(os.path.join(*loc.split('.'), 'options', 'parse.py'), 'w') as f: ...
if ctypes:
    c = generate_c_conversion(loc, ctypes)
    with open(os.path.join(*loc.split('.'), 'options', 'to-c-generated.h'), 'w') as f: ...
```

`gen/config.py` additionally patches two Go colour lists
(`tools/cmd/at/set_colors.go`, `tools/themes/collection.go`,
`~/kitty-482/gen/config.py:60-61`) — **irrelevant to a non-colour option**, but if your
diff shows changes there you have a stale checkout, not a correct patch.

The command, per `~/kitty-482/gen/__main__.py:19-21`:

```
python3 -m gen config          # from the kitty source root
```

`gen/config.py:74-76` also supports direct invocation (`./gen/config.py`), which re-enters
through `runpy` with `args = [sys.executable, 'config']`. Either form is correct; `python3 -m gen config`
is the one that does not depend on the `#!./kitty/launcher/kitty +launch` shebang
(`~/kitty-482/gen/config.py:1`), which requires a **built** kitty launcher and therefore
would need a build we are forbidden to run.

🚩 **UNMEASURED**: I did not execute `python3 -m gen config`. It imports
`kitty.options.definition`, which imports `kitty.conf.types` and `kitty.constants` — pure
Python, so it *should* run without a built kitty — but `kitty/constants.py` may import
`kitty.fast_data_types` (a C extension). **Verify this before relying on it**; the fallback
is to run it under a built kitty via `./kitty/launcher/kitty +launch gen/config.py`.
Not run here because the box panicked twice today under build memory pressure.

### 1.5 Docs are generated — `docs/conf.rst` is NOT the option reference

A common wrong assumption. `~/kitty-482/docs/conf.rst` is 101 lines of prose about *where
the config file lives and how include/comment syntax works*; it contains **no option
entries at all** (`grep -n window_title_bar docs/conf.rst` → no match). The option
reference is generated at Sphinx build time:

`~/kitty-482/docs/conf.py:607-618`:
```python
def generate_default_config(definition: Definition, name: str) -> None:
    with open(f'generated/conf-{name}.rst', 'w', encoding='utf-8') as f:
        ...
        f.write('\n'.join(definition.as_rst(name, shortcut_slugs)))
    with open(f'generated/conf/{conf_name}', 'w', encoding='utf-8') as f:
        text = '\n'.join(definition.as_conf(commented=True))
from kitty.options.definition import definition
generate_default_config(definition, 'kitty')
```
and `docs/conf.py:104` puts `generated/conf-*.rst` in the exclude list (it is included by
reference, not walked). `docs/generated/` does not exist in a clean checkout
(`ls docs/generated` → `No such file or directory`).

**Consequence: the `long_text=` you write in `definition.py` IS the documentation.**
There is no second place to write it, and no docs file to edit for the option itself.
That raises the bar on `long_text` — it is user-facing reference prose, not a code comment.

### 1.6 THE CHECKLIST — every file that must change

**Hand-edited (4 + consumers):**
1. `kitty/options/definition.py` — the `opt(...)` call, in the `window` group, physically
   adjacent to the existing `window_title_bar*` options so the generated docs group them.
2. `kitty/options/to-c.h` — `static inline <EnumType> <ctype_name>(PyObject *src)`.
3. `kitty/data-types.h` — the `typedef enum { ... } <EnumType>;` (this is where
   `ScrollbarVisibilityPolicy`, `UnderlineHyperlinks`, `ShowHyperlinkTargets` live;
   `kitty/data-types.h:118`, `kitty/state.h:34-35`).
4. `kitty/state.h` — one field in the `Options` struct (`kitty/state.h:83-93` is the
   neighbourhood).
5. Consumers: `kitty/shaders.c` (draw), `kitty/mouse.c` (hit test), and whichever of
   `kitty/tabs.py` / `kitty/window.py` must stop reserving a row.

**Generated — regenerate and COMMIT (do not hand-edit):**
6. `kitty/options/types.py`
7. `kitty/options/parse.py`
8. `kitty/options/to-c-generated.h`

**Docs:**
9. `docs/changelog.rst` — a one-line entry (§4).
10. **No `docs/conf.rst` change.** The option's docs are its `long_text`.

**Tests:** §3.

**Go:** nothing, for a non-colour option. (`gen/go-code` regenerates `tools/` Go sources
during the build; a new option with no colour and no remote-control surface touches
neither of the two lists `gen/config.py` patches.) UNMEASURED — I did not run `gen go-code`.

---

## 1.7 MEASURED: the generator runs on this box with **no build at all**

This is a real result and it changes how the patch can be developed here.

**First, the negative.** A plain `python3` cannot import `definition.py`:

```
$ PYTHONPATH=/Users/chrisren/kitty-482 python3 -c "from kitty.options.definition import definition"
  File "/Users/chrisren/kitty-482/kitty/types.py", line 161
    class RunOnce[T]:
SyntaxError: invalid syntax          # python3 here is 3.11.4; kitty needs >= 3.12 (pyproject.toml:2)

$ PYTHONPATH=/Users/chrisren/kitty-482 python3.13 -c "from kitty.options.definition import definition"
  File "/Users/chrisren/kitty-482/kitty/conf/utils.py", line 18, in <module>
    from ..fast_data_types import Color
ModuleNotFoundError: No module named 'kitty.fast_data_types'
```

So the generator needs the C extension — i.e. normally a build.

**Second, the positive.** The *installed* `kitty.app` ships that extension, and kitty's
frozen-python build honours a develop-mode env var, `KITTY_DEVELOP_FROM`
(`~/kitty-482/bypy/macos/__main__.py:384`, `bypy/linux/__main__.py:137`), which makes the
frozen importer defer to a source tree:

```
$ env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
      KITTY_DEVELOP_FROM=/Users/chrisren/kitty-482 \
      /Applications/kitty.app/Contents/MacOS/kitty +runpy '
        import kitty; print("kitty pkg from:", kitty.__file__)
        import kitty.fast_data_types as f; print("fdt:", f.__file__)
        from kitty.options.definition import definition
        print("IMPORT OK; n=", len(list(definition.iter_all_options())))'
kitty pkg from: /Users/chrisren/kitty-482/kitty/__init__.py
fdt: /Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/kitty.fast_data_types.so
IMPORT OK; n= 472
```

⚠️ Without `KITTY_DEVELOP_FROM` the frozen package **wins over `sys.path.insert(0, …)`** —
I measured it resolving to
`…/python-lib.bypy.frozen/kitty/__init__.pyc`. If you skip the env var you will silently
regenerate from the *shipped* definition and see an empty diff. That is the trap.

**Third, the positive control.** Working on a scratch copy (never the read-only trees):

```
$ SB=/private/tmp/ktb-cleancode/gentest       # cp -R of kitty/ gen/ + the two .go files
$ cd $SB && env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID KITTY_DEVELOP_FROM=$SB \
    /Applications/kitty.app/Contents/MacOS/kitty +runpy '
      import sys, os; sys.path.insert(0, os.getcwd())
      from gen.config import main; main([sys.executable, "config"])'
GEN DONE
```
sha256 (first 16) of the three generated files, before and after, on an **unmodified**
tree:

| file | before | after |
|---|---|---|
| `kitty/options/types.py` | `f95a514690157098` | `f95a514690157098` |
| `kitty/options/parse.py` | `435b2ccfb6782688` | `435b2ccfb6782688` |
| `kitty/options/to-c-generated.h` | `6e07e82ffa06ead3` | `6e07e82ffa06ead3` |

**Byte-idempotent.** So the instrument is proven before it is used, and any diff it
produces below is attributable to the edit, not to generator drift or a stale checkout.

### The measured generated diff for one new choices+ctype option

I then applied candidate A (§2) to the scratch `definition.py` — added
`ctype='window_title_bar_position'` and two choices — and re-ran the generator. This is
the **entire** generated-file cost, measured, not estimated:

```diff
--- kitty/options/types.py
@@ -40,7 +40,7 @@
-choices_for_window_title_bar = typing.Literal['top', 'bottom']
+choices_for_window_title_bar = typing.Literal['top', 'bottom', 'overlay-top', 'overlay-bottom']

--- kitty/options/parse.py
@@ -1550,7 +1550,7 @@
-    choices_for_window_title_bar = frozenset(('top', 'bottom'))
+    choices_for_window_title_bar = frozenset(('top', 'bottom', 'overlay-top', 'overlay-bottom'))

--- kitty/options/to-c-generated.h
@@ -1020,6 +1020,19 @@
+static void
+convert_from_python_window_title_bar(PyObject *val, Options *opts) {
+    opts->window_title_bar = window_title_bar_position(val);
+}
+
+static void
+convert_from_opts_window_title_bar(PyObject *py_opts, Options *opts) {
+    PyObject *ret = PyObject_GetAttrString(py_opts, "window_title_bar");
+    if (ret == NULL) return;
+    convert_from_python_window_title_bar(ret, opts);
+    Py_DECREF(ret);
+}
@@ -1684,6 +1697,8 @@
+    convert_from_opts_window_title_bar(py_opts, opts);
+    if (PyErr_Occurred()) return false;
```
and, confirming §1.4: `tools/cmd/at/set_colors.go` **UNCHANGED**,
`tools/themes/collection.go` **UNCHANGED**.

Note the generated C calls `window_title_bar_position(val)` — **the `ctype` string is the
C function name** — and assigns to `opts->window_title_bar`, **the option name**. Both
must be hand-written (to-c.h and state.h respectively) or the build breaks at the
generated header, which is the correct place for it to break.

### 1.8 MEASURED: `choices` are **not** auto-documented — the long_text must enumerate them

`~/kitty-482/kitty/conf/types.py:245-283` — `Option.as_conf()` and `Option.as_rst()` emit
only the **name**, the **default**, and the **long_text**. `self.choices` is stored
(`types.py:236`) and used only by the *parser* generator. Rendering the current option:

```
# window_title_bar top

#: Control the position of the window title bar relative to the window
#: content. Use window_title_bar_min_windows to control when title
#: bars are shown. Use window_title_template to format the displayed
#: window title.
```

The values `top` and `bottom` **appear nowhere in the docs**. That is why
`scrollbar`, `progress_bar` and `tab_bar_style` all hand-write a `:code:` definition list
in their `long_text` and `window_title_bar` does not.

⇒ **In-scope, defensible drive-by**: our patch's `long_text` should enumerate all four
values as a definition list, in the `scrollbar`/`progress_bar` house style. That is not
scope creep; it is the option's documentation, and the generator will not write it for us.

---

## 2. Option naming — scored against in-tree precedent

### 2.1 The decisive precedent: kitty collapses, it does not compose

Three in-tree options are direct analogues of what we are adding, and **all three fold
position/visibility/mode into ONE enumerated option** rather than into a base option plus
a modifier (all `~/kitty-482/kitty/options/definition.py`):

| option | values | what it proves |
|---|---|---|
| `progress_bar` | `left · right · top · bottom · hidden` | a bar drawn at a window edge: **position and visibility in one choices option** |
| `scrollbar` | `scrolled · always · never · hovered · scrolled-and-hovered` | a *visibility policy* that could trivially have been `scrollbar yes/no` + `scrollbar_when`, and was deliberately not |
| `undercurl_style` | `thin-sparse · thin-dense · thick-sparse · thick-dense` | an explicit **2×2 encoded as four hyphenated values**, whose long_text says "takes the form `(thin\|thick)-(sparse\|dense)`" |

`undercurl_style` is the exact structural match for what we need: two orthogonal binary
axes (reserve-a-row vs overlay) × (top vs bottom), expressed as four hyphenated values.
There is an in-tree precedent for precisely this shape, written by the maintainer.

`window_logo_position` (`top-left`, `bottom-right`, …) confirms that **hyphenated compound
values are house style**, not an invention.

### 2.2 Scoring the three candidates

| | Candidate | Verdict |
|---|---|---|
| **A** | `window_title_bar top \| bottom \| overlay-top \| overlay-bottom` | ★ **RECOMMENDED** |
| **B** | `window_title_bar_overlay yes \| no` | rejected |
| **C** | `window_title_bar_style cells \| overlay` | second choice |

**A — extend the existing option.**
*For:* Zero new option names. The option's own long_text already says it controls "the
position of the window title bar **relative to the window content**" — and "overlaying the
first row of content" is exactly a position relative to content, so the existing sentence
does not even need rewriting, only extending. Matches `undercurl_style`'s 2×2 shape and
`window_logo_position`'s hyphenation. Every sibling (`_min_windows`, `_align`,
`_active_foreground`, `_active_background`, `_inactive_*`) keeps its meaning **unchanged**
— this is the least-surprising interaction of the three, because there is no new
interaction at all: `min_windows` still decides *when*, `_align` still decides *where in
the bar*, the colours still decide *what colour*. A user who already knows the family
learns one new value, in the place they already look. Backwards compatible by
construction: `top` and `bottom` keep their current behaviour and remain the default.
*Against:* the option gains a `ctype` its three closest siblings do not have (§2.3);
adding values to an existing `choices` is a compatibility surface — old kitty rejects a
config using the new value with `The value overlay-top is not a valid choice for
window_title_bar` (`~/kitty-482/kitty/options/parse.py:1549-1550`), which is a *loud,
correct* failure but a failure nonetheless.

**B — `window_title_bar_overlay yes|no`. Rejected, for two reasons.**
(i) It contradicts the collapse precedent above. (ii) kitty has been actively bitten by
boolean options that later needed a third state: `~/kitty-482/kitty/options/definition.py:23-27`
carries four `definition.add_deprecation(...)` lines, and
`focus_follows_mouse` is the live example of a boolean that had to grow a third value
(`choices=('no','n','false','y','yes','true','drop')`) — a permanently ugly value list that
exists only because it started life as a bool. A bar-drawing *mode* is a classic
three-values-eventually axis (reserve / overlay / floating-inset / …). Do not start it as a
bool.

**C — `window_title_bar_style cells|overlay`. Viable, second choice.**
*For:* exact precedent in `tab_bar_style` (`fade|slant|separator|powerline|custom|hidden`),
which is the `<thing>_style` naming the family would use. Fully orthogonal: position stays
in `window_title_bar`, style in `window_title_bar_style`, so `overlay` × `bottom` needs no
new value. Extensible without touching an existing choices list, so no config-compat
surface at all on the existing option.
*Against:* two options must be read together to know what the bar does, which is the exact
composition kitty avoided three times. And the value name `cells` is jargon leaking from
the implementation — a user does not think of the default bar as "the cells one". You would
have to call it something like `reserved` vs `overlay`, at which point the option is
describing a *layout* decision under a `_style` name, which is worse than A.

### 2.3 The one real objection to A, and its answer

`window_title_bar`, `window_title_bar_min_windows` and `window_title_bar_align` carry **no
`ctype`** — they are read in Python only (`~/kitty-482/kitty/tabs.py:1890`, `:1998`,
`:2068`; `kitty/window.py:1055`). Adding a `ctype` to `window_title_bar` makes it the first
of the three to cross into C, and a reviewer will ask why.

The answer is that **the C side must already be told about the bar**, and today it is told
*implicitly*, through geometry: `set_window_title_bar_render_data`
(`~/kitty-482/kitty/state.c:1006-1016`) takes `(os_window_id, tab_id, window_id, screen,
left, top, right, bottom)` and stores it in `window->window_title_render_data`; the hit
test then keys on that struct being populated (`kitty/mouse.c:1072-1078`). So there are two
honest designs and the PR must pick one deliberately:

- **A1 — option in C (`ctype`).** C reads `OPT(window_title_bar)` in the draw path to decide
  `render_a_bar` vs the existing screen, exactly as `shaders.c:828` reads `OPT(scrollbar)`.
  Cost: the generated hunk in §1.7 plus two hand-written lines.
- **A2 — no `ctype`; extend the existing Python→C call.** Add one `int overlay` argument to
  `set_window_title_bar_render_data` and one `bool` to `WindowRenderData`. Python keeps
  ownership of the whole policy (it already owns `min_windows` and the per-window
  show/hide), and C only ever executes. **This is the smaller and more kitty-shaped diff**,
  because it keeps the existing division of labour: Python decides, C draws.

🚩 **Recommendation: A2** — candidate A's *name*, without a `ctype`. It leaves all three
`window_title_bar*` siblings ctype-free and consistent, deletes the generated
`to-c-generated.h` hunk entirely (the diff shrinks to two one-line changes in generated
files), and does not put a policy string in the C options struct that C only ever compares
for one bit. The measured `to-c-generated.h` diff in §1.7 is therefore a *cost you can
choose not to pay* — I measured it so the choice is informed rather than assumed.

### 2.4 Value naming: `overlay-top` beats `top-overlay`

Both are defensible. `overlay-top` is preferred because the leading token is the
*discriminator*: a reader scanning the four values sees two that start with `overlay` and
groups them instantly, which is how `undercurl_style` reads (`thin-*` / `thick-*`) and how
`window_logo_position` reads (`top-*` / `bottom-*`). With `top-overlay` the four values
sort as `top`, `top-overlay`, `bottom`, `bottom-overlay`, where the pairs alternate and
the discriminator is a suffix. UNMEASURED: this is a legibility judgement, not a
measurement; the precedent argument is the only evidence and it is weak-to-moderate.

### 2.5 The interaction nobody has named yet: the bar's border ignores `window_border_width`

`render_a_bar` hardcodes its border thickness:
`~/kitty-482/kitty/shaders.c:838` — `unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));` — i.e. **1pt**, not `OPT(window_border_width)`; and
`shaders.c:886` draws the rounded border with `draw_rounded_rect(..., 1, ui->cell_width, fg, bg, 0.f)`.
It also derives fg/bg from the **screen's default colours** (`shaders.c:849-851`), *not*
from `window_title_bar_active_background` / `_inactive_background`.

⇒ Two consequences the PR must state explicitly, or a reviewer will find them:
1. An overlay bar will **not** honour the four `window_title_bar_*_{fore,back}ground`
   options unless `render_a_bar` is extended to take fg/bg. That is a visible behaviour
   difference between `top` and `overlay-top` and it must be either fixed in the patch or
   documented in the long_text. (The operator's own config sets
   `window_title_bar_active_background #2f62d8` — so on this machine it is not academic.)
2. The bar's border ignores `window_border_width` and `draw_minimal_borders`. Existing
   behaviour of an existing function, inherited, not caused by us — say so rather than
   silently adopting it.

---

## 3. Tests

### 3.1 MEASURED: the window title bar has **zero** test coverage today

```
$ cd ~/kitty-482 && grep -rl "title_bar" kitty_tests/ | wc -l
       0
$ grep -rln "window_title" kitty_tests/
(no output)
```

The feature shipped (changelog `~/kitty-482/docs/changelog.rst:508`, "Allow showing
:opt:`configurable window titles <window_title_bar>` for individual kitty …") with no
tests in `kitty_tests/`. So there is no "closest existing title-bar test" to extend, and
**a PR that adds the first test for this subsystem is doing the maintainer a favour** —
say so in the PR body; it converts "more code to review" into "coverage you did not have".

### 3.2 The exact model to copy: `kitty_tests/tab_bar.py`

`~/kitty-482/kitty_tests/tab_bar.py` (89 lines, dated 2026 — written in the same era as
the title-bar feature) is the right template, and it is a very close structural match: it
tests **a bar's geometry and its hit testing**, with the C layer mocked out.

```python
with (
    patch('kitty.tab_bar.cell_size_for_window', return_value=(10, 20)),
    patch('kitty.tab_bar.viewport_for_window', return_value=(central, tab_bar, 400, 160, 10, 20)),
    patch('kitty.tab_bar.set_tab_bar_render_data', side_effect=lambda *args: geometries.append(args[2:6])),
    patch('kitty.tab_bar.get_boss', return_value=boss),
):
    tb = TabBar(1); tb.layout(); tb.update((...))
self.ae(geometries[-1], (0, 0, 120, 160))
self.ae(tb.tab_id_at(5, 10), 1)
```
(`~/kitty-482/kitty_tests/tab_bar.py:34-58`)

The same technique applies directly to our change, because `kitty/window.py` imports its C
entry points by name from `.fast_data_types` and is therefore patchable at
`kitty.window.<name>`. CONFIRMED by reading the import block
(`~/kitty-482/kitty/window.py`, the `from .fast_data_types import (...)` block spanning
lines 39-98): it contains `cell_size_for_window` (:26 within the block),
`get_options` (:35), `set_window_render_data` (:52), `set_window_title_bar_render_data` (:53).

### 3.3 Where the property under test actually lives

`Window.set_geometry`, `~/kitty-482/kitty/window.py:1050-1145`, is the **whole** of the
row-stealing behaviour and therefore the whole of requirement (a):

```python
def set_geometry(self, new_geometry: WindowGeometry) -> None:
    ...
    position = opts.window_title_bar                     # :1055
    show_tb = self.show_title_bar and new_geometry.ynum > 1   # :1056
    if show_tb:
        render_ynum = new_geometry.ynum - 1               # :1059  <-- the stolen row
        cell_width, cell_height = cell_size_for_window(self.os_window_id)
        if position == 'top':
            render_top = new_geometry.top + cell_height   # :1062  <-- the content shift
            ...
    ...
    self.screen.resize(max(0, render_ynum), ...)          # :1075  <-- the PTY resize
    ...
    set_window_render_data(..., render_top, ..., render_bottom, ...)   # :1092-1105
    if show_tb:
        self._title_bar_screen = WindowTitleBarScreen(...)             # :1112
        set_window_title_bar_render_data(..., tb_geom....)             # :1124
```

⚠️ Two things follow that the PR must state:
1. **The existing native bar is a `Screen`**, so it is rendered in the **cell font**
   (`WindowTitleBarScreen`, `~/kitty-482/kitty/window.py:1112`). The `⌘⌥B` bars therefore
   fail the operator's requirement (d) as well as (a) — they are in Monaco, not SF Pro.
   Only the `render_a_bar` path uses `cocoa_render_line_of_text`. This is a *second*
   independent reason the overlay design is the right one, and it does not appear to have
   been written down anywhere yet.
2. For `overlay-*`, the minimal change is one branch in this one function:
   leave `render_ynum`, `render_top`, `render_bottom` **untouched** (= `new_geometry`),
   compute `tb_top/tb_bottom` as the band over the first (or last) row, and do **not**
   construct a `WindowTitleBarScreen`. The `screen.resize` at :1075 then sees no change,
   so there is no SIGWINCH and no content shift — by construction, not by luck.

### 3.4 The tests to add, in kitty's own style

**T1 — `kitty_tests/options.py`, inside `conf_parsing()`** (the house idiom is a one-line
parse + one-line assert; `~/kitty-482/kitty_tests/options.py:258-269` is the pattern, and
`:277` is the invalid-value pattern):

```python
opts = p('window_title_bar overlay-top')
self.ae(opts.window_title_bar, 'overlay-top')
opts = p('window_title_bar overlay-bottom')
self.ae(opts.window_title_bar, 'overlay-bottom')
opts = p('window_title_bar top')            # regression: existing values unchanged
self.ae(opts.window_title_bar, 'top')
opts = p('window_title_bar sideways', bad_line_num=1)   # invalid choice still rejected
```

**T2 — a new `kitty_tests/window_title_bar.py`** — the load-bearing one. This is the
zero-shift red-proof, and it fails before the patch and passes after:

```python
class TestWindowTitleBar(BaseTest):

    def test_overlay_title_bar_does_not_consume_a_row(self):
        # for position in ('top', 'bottom'): reserved mode steals a row
        #   -> assert screen.lines == ynum - 1 and the render rect is inset by cell_height
        # for position in ('overlay-top', 'overlay-bottom'): it does not
        #   -> assert screen.lines == ynum
        #   -> assert the (top, bottom) passed to set_window_render_data equals
        #      the (top, bottom) of the un-barred geometry, exactly
        #   -> assert the band passed to set_window_title_bar_render_data is
        #      cell_height tall and lies INSIDE the content rect
```

with the C layer patched exactly as `tab_bar.py` does it:
`patch('kitty.window.cell_size_for_window', return_value=(10, 20))`,
`patch('kitty.window.set_window_render_data', side_effect=...)`,
`patch('kitty.window.set_window_title_bar_render_data', side_effect=...)`.

**Why T2 is the right shape rather than a screenshot or an end-to-end check:** the operator's
requirement (a) — "no content layout shift" — is *exactly* the proposition
`screen.lines` and `(render_top, render_bottom)` are unchanged. A test that asserts that
proposition cannot pass for the wrong reason, and it is pure Python arithmetic, so it runs
without GL, without a window, and without the `⌘⇧B` daemon.

🚩 **Make T2 possible by extracting the arithmetic.** Today it is interleaved with
`screen.resize`, `resize_child` and two C calls inside a 95-line method. The kitty-shaped
refactor is a small module-level pure function in `kitty/window.py`, e.g.

```python
def title_bar_layout(g: WindowGeometry, position: str, cell_height: int) -> TitleBarLayout | None
```
returning `(render_ynum, render_top, render_bottom, tb_top, tb_bottom, needs_screen)`.
`set_geometry` then calls it. That is a **separate, behaviour-preserving commit** (see §5)
and it is what makes the feature testable. Extracting-to-test is a pattern already in the
tree — `layout_dimension` / `layout_single_window` in `kitty/layout/base.py` are pure
functions imported directly by `kitty_tests/layout.py:6`.

**T3 — hit testing. NOT POSSIBLE today without a new C export.** MEASURED:
`mouse_region()` (`~/kitty-482/kitty/mouse.c:988`) is `static` and the module's whole
Python surface is four functions (`~/kitty-482/kitty/mouse.c:1662-1666`):
```c
static PyMethodDef module_methods[] = {
    {"send_mouse_event", ...},
    METHODB(test_encode_mouse, METH_VARARGS),
    METHODB(send_mock_mouse_event_to_window, METH_VARARGS),
    METHODB(mock_mouse_selection, METH_VARARGS),
```
None reaches `mouse_region`. **But `test_encode_mouse` is itself a test-only export**, so
there is in-tree precedent for adding one: a `test_mouse_region(x, y) -> (window_id,
in_title_bar, in_tab_bar, window_border)` `METHODB` beside it would make the band hit test
a real unit test. That is the honest, in-style way to cover the C half. If the reviewer
rejects it, the fallback is to cover only the Python geometry (T2) and state in the PR that
the hit test is verified manually — do not pretend otherwise.

### 3.5 The check commands, and MEASURED whether each runs on this box

Sources: `~/kitty-482/.github/workflows/ci.yml` (the authoritative gate list) and
`~/kitty-482/kitty_tests/main.py`.

| # | Gate | Command (ci.yml line) | Runs here? |
|---|---|---|---|
| 1 | build | `python .github/workflows/ci.py build` (:64) | **NO** — forbidden (brief rule 6) |
| 2 | test suite | `python .github/workflows/ci.py test` → `./test.py` (`ci.py:149`) | **NO** — `test.py` needs a built launcher / `fast_data_types` |
| 3 | trailing whitespace | `grep -Inr '\s$' kitty kitty_tests kittens docs *.py *.asciidoc *.rst *.go .gitattributes .gitignore` (:82) | **YES** |
| 4 | space after `:code:` | `grep -Inr ':code:`\s' …` (:85) | **YES** |
| 5 | lint | `ruff check .` (:112) | **YES** |
| 6 | gofmt | `python .github/workflows/ci.py gofmt` → `gofmt -s -l tools kittens` (`ci.py:296-297`) | **YES** |
| 7 | type check | `./test.py type-check` (:124) → `os.execlp('ty', 'ty', 'check')` (`kitty_tests/main.py:98`) | **YES, with a caveat** (below) |
| 8 | go vet | `go vet -tags testing ./...` (:127) | probably; UNMEASURED |
| 9 | docs | `make FAIL_WARN=1 docs` (:130) | UNMEASURED — needs `docs/requirements.txt` (sphinx) |

🚨 **There is NO clang-format gate in CI.** `grep -n "clang" .github/workflows/ci.yml` →
no match. `./autoformat` is a developer convenience, not a gate. This matters because
**`clang-format` is not installed on this box** (`command -v clang-format` → nothing), and
the `.clang-format` file exists only in `~/kitty-dev`, not in `~/kitty-482`
(`ls: /Users/chrisren/kitty-482/.clang-format: No such file or directory`) — the tree-wide
C reformat landed *after* v0.48.2. So: match the surrounding style by hand, target master,
and do not block on formatting. Confirmed by diffing `render_a_bar` between the two trees —
it is byte-for-byte the same logic with different line breaking, plus one real API change
(`draw_rounded_rect` gained parameters in master).

**Measured results of the gates that do run, on the unmodified `~/kitty-482` tree** — these
are your BASELINE; judge the patch as a differential against them, not against zero:

```
$ ruff check .                      -> All checks passed!
$ grep -Inr '\s$' kitty … .gitignore -> rc=1, 0 lines      (gate passes)
$ grep -Inr ':code:`\s' kitty …      -> 0 lines            (gate passes)
$ gofmt -s -l tools kittens          -> 0 lines            (gate passes)
```

**Gate 7 in detail — `ty`, not mypy.** `type_check()` (`~/kitty-482/kitty_tests/main.py:91-98`)
generates two stubs and then `os.execlp('ty', 'ty', 'check')`. `ty` **is** installed here
(`ty 0.0.81 (4edd7724a 2026-09-14)`), and `mypy` is too (1.20.0) but is **not** what the
gate runs, despite `./test.py mypy` being accepted as an alias (`main.py:267`).

The stub generation matters enormously and is easy to miss — measured on a scratch copy of
the tree:

| state | `ty check` result |
|---|---|
| stubs **not** generated | **367 diagnostics** |
| stubs generated (`kitty.cli_stub.generate_stub()` + `kittens.tui.operations_stub.generate_stub()`) | **23 diagnostics** |

and of those 23: `errors: 7, warnings: 16`, where **all 7 errors are
`unresolved-import` for `sphinx` / `docutils`** — which CI installs
(`ci.yml:109`, `pip install -r docs/requirements.txt`). Restricted to the code:

```
$ ty check kitty kittens glfw   ->  errors: 0   warnings: 16   (rc=1)
```

⚠️ **So `ty check` exits 1 on the unmodified v0.48.2 tree with today's `ty`.** Do not read
a non-zero exit as "my patch broke the type check". The usable protocol is a differential:
record `errors:`/`warnings:` counts before and after your edit and require them not to
increase. (Upstream's CI installs `ty` unpinned — `ci.yml:109` — so its baseline drifts
with every `ty` release; this is the ordinary published-figure decay and the reason to
re-measure the baseline in the same session rather than quote one.)

**How to run gate 7 here**, without a build, in a scratch copy:
```
SB=/private/tmp/<scratch>          # cp -R kitty kittens glfw docs kitty_tests *.py pyproject.toml
cd $SB && env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID KITTY_DEVELOP_FROM=$SB \
  /Applications/kitty.app/Contents/MacOS/kitty +runpy '
    import sys, os; sys.path.insert(0, os.getcwd())
    from kitty.cli_stub import generate_stub; generate_stub()
    from kittens.tui.operations_stub import generate_stub as g2; g2()'
cd $SB && ty check kitty kittens glfw
```

**New test files need no registration.** `find_all_tests()`
(`~/kitty-482/kitty_tests/main.py:50-57`) walks the package and imports every module except
`main` and `gr`. A new `kitty_tests/window_title_bar.py` is picked up automatically.

---

## 4. Docs

### 4.1 MEASURED: there is almost nothing to write, and one thing that must be

```
$ cd ~/kitty-dev && grep -rn "title bar\|title_bar" docs/*.rst | grep -v changelog
(no output)
```

No hand-written docs page mentions window title bars at all. So:

1. **`docs/conf.rst` — no change.** It is prose about config-file *location and syntax*
   (101 lines, `~/kitty-482/docs/conf.rst`), and contains no option entries. The option
   reference is generated from `definition.py` at Sphinx build time
   (`~/kitty-482/docs/conf.py:607-618`).
2. **The `long_text` IS the documentation.** And because `choices` are not rendered
   (§1.8), it must enumerate the four values in the `scrollbar` / `progress_bar` house
   style — a `:code:` definition list. Proposed text:

```rst
Control the position of the window title bar relative to the window content.

:code:`top`, :code:`bottom`
    Reserve one row of the window for the title bar, shifting the terminal
    content down (or up) by one line.
:code:`overlay-top`, :code:`overlay-bottom`
    Draw the title bar over the first (or last) row of the window, using the
    system UI font. No row is reserved, so turning title bars on and off does
    not resize the terminal or send it :code:`SIGWINCH`. The bar is drawn on
    top of the content in that row.

Use :opt:`window_title_bar_min_windows` to control when title bars are shown.
Use :opt:`window_title_template` to format the displayed window title.
```
⚠️ Watch gate 4: `grep -Inr ':code:`\s'` fails the build on a space immediately after an
opening `:code:` backtick. Do not write ``:code:` top` ``.

3. **`docs/changelog.rst` — one entry, in the `0.49.0 [future]` list.** The in-tree
   template for exactly this change (a new value on an existing choices option) is already
   there, `~/kitty-dev/docs/changelog.rst`:

   > \- The :opt:`scrollbar` option now takes a new value ``scrolled-or-hovered`` to also
   > show the scrollbar when the mouse moves over the scrollbar region (:pull:`10345`)

   so ours is:

   > \- The :opt:`window_title_bar` option now takes the values ``overlay-top`` and
   > ``overlay-bottom``, which draw the window title over the first (or last) row of the
   > window in the system UI font, instead of reserving a row for it. Toggling title bars
   > in this mode does not resize the terminal.

   🚩 **Do not invent a `:pull:` number.** MEASURED from
   `~/kitty-dev git show dac035751 -- docs/changelog.rst`: a contributor's entry was later
   *moved* by the maintainer and the `(:pull:`10471`)` reference added by him. Add the
   entry without a reference and let him place it.

4. **If the patch adds or changes an action** (e.g. anything near
   `toggle_window_title_bars`), the docstring on the `Boss` method is the documentation —
   `~/kitty-482/kitty/boss.py:3483-3497` — and `docs/generated/actions.rst` is generated
   from it (`~/kitty-482/docs/conf.py:627`). No separate docs file.

---

## 5. The commit series

### 5.1 🚩 CORRECTION: kitty does **not** use conventional commits, and does not start lowercase

The brief asks for "the repo's own commit-message style (lowercase start,
conventional-commit prefix, no redundant verbs)". That is **this operator's**
`claude-infrastructure` style (global `CLAUDE.md` § Git Commit Messages), not kitty's. My
axis is kitty's own conventions, so here is the measurement.

```
$ cd ~/kitty-dev && git log --no-merges -200 --format=%s > subs.txt
total=200   start-lowercase=34   conventional-prefix=1   'Subsystem: ' prefix=24
```

- **1 of 200** (0.5%) has a conventional-commit prefix, and it is a drive-by from an
  outside contributor: `docs: add Mobile SSH to terminals implementing the graphics protocol`.
- **34 of 200** (17%) start lowercase; the dominant form is **Sentence case + imperative verb**.
- **24 of 200** (12%) carry a `Subsystem: ` prefix. Real examples from `~/kitty-dev git log`:
  `Splits: Fix issues with proportional sizing` · `Graphics protocol: Fix file descriptor leak
  that can be triggered by malicious clients` · `Custom shaders: Redraw static effects only on
  demand` · `Test suite: Fix small numbers of Python tests being run in incorrect environment`.

⇒ **For an upstream PR, write `Window title bars: <Imperative sentence>`.** Using
`feat(window):` would make the series visibly foreign in `git log` — the one place a
maintainer sees every contribution side by side. (For a commit in *our* repo carrying the
patch file, the operator's lowercase/conventional style still governs; the two repos have
different rules and the patch simply crosses between them.)

Also measured: the maintainer **merges** contributor branches rather than squashing
(`Merge branch 'feature/inactive-shader-tint' of https://github.com/xiaobai050/kitty`, and
21 more in the last 30), and follows up with his own `cleanup previous PR …` commits. So
the series shape you push is the series that lands. It is worth getting right.

### 5.2 The series — 5 commits

Each is independently reviewable, each builds, each leaves the tree green.

| # | Subject | Contents |
|---|---|---|
| 1 | `Window title bars: Extract the title bar layout arithmetic into a pure function` | Behaviour-preserving refactor of `kitty/window.py:1050-1145`: pull the `render_ynum` / `render_top` / `render_bottom` / `tb_top` / `tb_bottom` computation out of `set_geometry` into a module-level pure function. **No behaviour change**, so it can be reviewed by inspection. This is what makes commit 4's test possible. |
| 2 | `Window title bars: Add overlay-top and overlay-bottom positions` | `kitty/options/definition.py` (the two new choices + the rewritten `long_text` enumerating all four values), plus the two regenerated one-line hunks in `kitty/options/types.py` and `kitty/options/parse.py`. **Generated files in the same commit as the definition that generated them** — never separately; a reviewer must be able to regenerate and get an empty diff. |
| 3 | `Window title bars: Draw overlay bars with render_a_bar and hit-test their band` | The actual feature: the `overlay-*` branch in `window.py` (no `WindowTitleBarScreen`, no row taken), the Python→C flag, the `shaders.c` draw call, and the `mouse.c` ordering change. The one commit that needs real review. |
| 4 | `Window title bars: Add tests for title bar layout` | `kitty_tests/window_title_bar.py` (T2) + the `conf_parsing` additions (T1). Separate so its red-before/green-after can be demonstrated against commit 3. |
| 5 | `Update changelog` | `docs/changelog.rst` only. This is the maintainer's own literal subject line for this commit — measured, `~/kitty-dev git log --format=%s -- docs/changelog.rst` shows `Update changelog` three times in the recent history. |

**Why 1 is separate and first.** It is the difference between "here is a 400-line diff,
trust me" and "here is a no-op refactor you can verify by reading, then a 60-line feature
on top of it". It also survives rejection: if the feature is declined, commit 1 is still a
net improvement the maintainer can keep.

**Why 2 and 3 are separate.** Commit 2 alone adds a parseable option value that behaves
exactly like `top`/`bottom` (the C side has not learned it yet, so it falls through the
existing branch). That is a safe intermediate state and it isolates the generated-file
churn from the logic.

**Do not squash 2's generated files into 3.** The rule a reviewer applies is "run
`python3 -m gen config` and confirm the diff is empty"; that is checkable only if the
`opt(...)` edit and its three generated outputs are in one commit.

### 5.3 The PR body — lead with the reframe

The single highest-leverage sentence is the one from §0: **this adds a third consumer to
machinery that already has two, one of which already draws exactly this.**
`draw_window_number` (`~/kitty-482/kitty/shaders.c:938-943`) already calls
`render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false)` — the window's
title, at the top of the window, over content, outside the cell grid, in the system font.
The PR proposes making that reachable from an option instead of only from the
window-number overlay. Say that first; it converts the review from "new rendering path" to
"policy over an existing one".

Second paragraph: the two known behaviour differences from `top`/`bottom` (§2.5) — the
overlay bar does not yet honour the four `window_title_bar_*_{fore,back}ground` options,
and its border is a hardcoded 1pt — stated as known, with whichever you fixed marked as
fixed. Naming them yourself is worth more than any amount of polish; finding them himself
is what makes a maintainer distrust the rest of the diff.

---

## 6. Our own repo's gates — every bats suite that touches kitty config or the title toggle

```
$ cd /Users/chrisren/Development/claude-infrastructure
$ grep -rln "config/kitty.conf\|kitty\.conf" tests/*.bats | sort
tests/cc-kitty-reload.bats            tests/kitty-setup-canonical-tree.bats
tests/completion-assert.bats          tests/kitty-socket-address.bats
tests/deploy-parity.bats              tests/kitty-title-zero-shift.bats
tests/handoff-fire-kitty-daemon.bats  tests/peer-owned.bats
tests/kitty-conf-bindings.bats        tests/session-writes.bats
tests/kitty-drag-arm.bats             tests/subagent-stop-r1.bats
```

### 6.1 Triage — which of the twelve actually constrain a config change

| Suite | Constrains our change? | What it demands |
|---|---|---|
| `kitty-title-zero-shift.bats` | 🚨 **YES — pins the current design hard** | §6.2 |
| `kitty-conf-bindings.bats` | 🚨 **YES — pins the current design hard** | §6.3 |
| `kitty-drag-arm.bats` | **YES, mildly** | `config/kitty.conf` must keep `globinclude drag-arm.d/*.conf` as the last line of its section 8, `config/drag-arm.d/` must hold only `drag.conf.example`, and the real edited conf must parse at rc=0 with **0 bytes of stderr** through `kitty +runpy … load_config` (`tests/kitty-drag-arm.bats:23,34-36`). Any new option we add must therefore be one the **installed 0.48.2** parser accepts — see §6.5. |
| `kitty-socket-address.bats` | **NO (assertions)**, yes (citations) | Asserts `listen_on` behaviour from a *fixture* conf it writes itself (`:52`). Its `config/kitty.conf:67`, `:158-160`, `:164-176` references are **comments**, so they rot but do not redden. |
| `deploy-parity.bats` | **YES, if the overlay script is deleted** | §6.4 |
| `cc-kitty-reload.bats` | NO | writes its own `printf 'font_size 18\n' > .../kitty.conf` fixture (`:17`). |
| `handoff-fire-kitty-daemon.bats` | NO | fixture conf at `:65`; cares only about `listen_on` as the socket-address SSOT. |
| `kitty-setup-canonical-tree.bats` | NO | one comment mention (`:171`). |
| `peer-owned.bats`, `session-writes.bats`, `subagent-stop-r1.bats`, `completion-assert.bats` | NO | they use the *string* `config/kitty.conf` as a convenient tracked-file path inside synthetic repos. Content-agnostic. |

### 6.2 `tests/kitty-title-zero-shift.bats` — 11 cases, **6 break**

The suite's own header states the design it pins: a `⌘⇧B` chord that runs
`scripts/kitty-pane-title-toggle.sh off` then `scripts/kitty-pane-title-overlay.py toggle`,
with bars OFF by default (`window_title_bar_min_windows 0`) and held up only by
`config/kitty-title-on.conf`.

| # | line | case | under a native overlay-band design |
|---|---|---|---|
| 1 | 54 | `kitty.conf reserves NO top padding` | ✅ **passes** — padding stays `0 5 0 5`; the overlay needs no reservoir either. |
| 2 | 67 | `the ON half hands the whole reservoir back` | ⚠️ **passes only while `kitty-title-on.conf` exists**; if that file is deleted, `last_directive` on a missing file returns empty and the case fails. |
| 3 | 84 | `the pairing identity holds` | same as #2. |
| 4 | 97 | `the reservoir is pinned to the font that derives it` | ✅ **passes** — `font_size 18.0` + `modify_font cell_height 94%` unchanged. Its *rationale* is already dead (`a49280bd9` removed the reservoir), which the case's own comment concedes. |
| 5 | 105 | `placement_strategy top` | ✅ **passes**. |
| 6 | 113 | `bars are OFF by default and held up ONLY by the ON half` | 🚨 **BREAKS.** Demands `OFF → min_windows 0`. With a zero-cost overlay bar the right main-config value is `1` (always show). |
| 7 | 122 | `the ON half includes the main config` | 🚨 **BREAKS** if `kitty-title-on.conf` is retired. |
| 8 | 127 | `cmd+shift+b runs the toggle script and NOT the bare built-in action` | 🚨 **BREAKS, and this is the important one.** It explicitly forbids `toggle_window_title_bars` in the chord — the exact action the new design makes correct and free. |
| 9 | 141 | `cmd+shift+b clears the REAL bars before drawing the overlay` | 🚨 **BREAKS** — requires both retired scripts by name in the chord. |
| 10 | 155 | `the toggle script exists, is executable, and rejects an unknown argument` | 🚨 **BREAKS** — the script is deleted. |
| 11 | 161 | `both halves parse through kitty's OWN loader with the intended values` | 🚨 **BREAKS** — asserts `^OFF 0(\.0)? 0(\.0)? 0 top$`, i.e. `min_windows 0`, and `^ON  0 0 1$`. |

**How to re-key each onto the PROPERTY.** The suite's own header already names the right
standard — "The identity is: … Break either and nothing errors" — so re-key to the
*measurable consequence*, never to the spelling:

- **#6, #11 → the zero-shift identity itself, measured through kitty's parser.** The
  property is not "min_windows is 0"; it is **"turning the bar on does not change the row
  count"**. Under the overlay design that becomes checkable *directly* rather than through
  a padding-arithmetic proxy: assert `window_title_bar` ∈ the overlay values, and assert
  that with bars on, the loader's `window_padding_width.top` is unchanged from the bars-off
  state. The old padding-delta identity was only ever a **proxy** for the row count,
  needed because the reserved-row design could not be interrogated any other way.
- **#8 → "the chord must reach a REAL, HIT-TESTED bar."** That property is already written
  out verbatim in `tests/kitty-conf-bindings.bats:208` ("THE CHORD MUST REACH REAL,
  HIT-TESTED BARS"), and the sibling suite has *already* been re-keyed onto it. Copy that
  key: accept `toggle_window_title_bars` **or** a config-swap route **or** an overlay-value
  route. Under the new design `toggle_window_title_bars` becomes a *passing* answer rather
  than a forbidden one — which is precisely the inversion that case is written to guard
  against having again.
- **#9, #10 → delete, do not relax.** They assert the existence and call order of two
  scripts that the change retires. A test for a deleted component is not re-keyable; it is
  removed, and its *record* preserved as a comment in the house style this file already
  uses ("REFUTED IN PLACE 2026-09-16 by a49280bd9, kept as the record of what was
  believed") — stating that the overlay daemon was retired because `render_a_bar` gives the
  same face natively.
- **#2, #3, #7 → follow the fate of `kitty-title-on.conf`.** If the ON half survives as a
  `min_windows` swap, they are unchanged. If it is retired, remove them with the same
  in-place record.
- **#1, #4, #5 → leave alone.** They pass, and #4/#5 still pin real, live properties
  (`placement_strategy top` remains load-bearing for any band arithmetic).

🚨 **The house rule this suite itself records, and the reason to be careful here:**
`~/…/tests/kitty-conf-bindings.bats:33-35` — *"never repair a red here by relaxing an
assertion to match the conf — that is the move that produced both rebaselines"*. Re-keying
onto a **named property with its own mutant control** is a different act from relaxing, and
the PR/commit must say which one it is doing, per case.

### 6.3 `tests/kitty-conf-bindings.bats` — 32 cases, **~13 break**

This suite is already half-way to the right shape: on 2026-09-16 it grew role resolvers
(`real_bar_key()` / `glance_key()`, `:100-113`) *because* the chords had traded roles twice
and each trade reddened three spelling-keyed cases. The new design breaks the resolvers
themselves, because `glance_key()` is defined as *"the chord that ends in
`kitty-pane-title-overlay.py toggle`"* — a script that ceases to exist.

| # | line | case | verdict |
|---|---|---|---|
| 1 | 115 | `the chord ASSIGNMENT is the operator's…` | 🚨 BREAKS — demands `glance_key == cmd_shift_b_last`, and no chord ends in the overlay any more. |
| 7 | 215 | `cmd+shift+b is the ONE bar — overlay cleared, then the real draggable bars` | 🚨 BREAKS — its final assertion requires the chord to contain `kitty-pane-title-overlay.py off`, and requires `kitty-pane-title-overlay.py` to appear in the conf at all. |
| 8 | 267 | `the overlay script … exists and is valid python` | 🚨 BREAKS — script deleted. |
| 9 | 279 | `the overlay can reach a python with Pillow` | 🚨 BREAKS — script deleted. |
| 10 | 292 | `every graphics escape in the overlay suppresses responses (q=2)` | 🚨 BREAKS — script deleted. |
| 19 | 440 | `the title type breathes inside its band…` | 🚨 BREAKS — runs `overlay.py measure`. |
| 20 | 467 | `the placement is whole cells and the band fits inside it` | 🚨 BREAKS — greps `BAND_FILL_CELLS` in the overlay. |
| 21 | 491 | `the keypress path imports nothing but os and sys` | 🚨 BREAKS — script deleted. |
| 22 | 514 | `the tty cache is keyed by pane AND pid…` | 🚨 BREAKS — overlay internals. |
| 23 | 537 | `no title clips the band — ink stays inside it` | 🚨 BREAKS — renders through the overlay. |
| 24 | 576 | `the styled glance survives on ⌘⌥B — the overlay, still zero-shift` | 🚨 BREAKS — `glance_key` empty. |
| 25 | 606 | `MUTANT CONTROL: dropping the re-order map…` | ⚠️ survives *mechanically* (it keys on `real_bar_key`, which `toggle_window_title_bars` still satisfies) but its `wc -l` delta check assumes exactly one map line for the chord. Re-verify. |
| 27 | 680 | `no usable face is a REFUSAL…` | 🚨 BREAKS — overlay `_faces`. |
| 28 | 738 | `a single-pane tab still gets a title — no minimum-pane guard` | ⚠️ depends which route; likely re-key onto `window_title_bar_min_windows == 1`. |
| 29 | 757 | `the title toggle passes --ignore-overrides` | 🚨 BREAKS — toggle script deleted. |
| 30 | 774 | `--all rides the daemon SPAWN` | 🚨 BREAKS — daemon deleted. |
| 26 | 648 | `the real title bars carry the overlay's palette` | ✅ **passes and becomes MORE important** — it asserts `window_title_bar_align left`, `_active_background Color(47, 98, 216)`, `_inactive_background Color(63, 85, 144)` through kitty's own parser. But see §2.5: `render_a_bar` **ignores** those colours today, so this case would be asserting a config the renderer does not read. That is the gate telling you something true. |
| 2-6, 11-18, 31-32 | — | splits, close chords, tilde guard, drag tolerance, detach chords, drag kitten | ✅ unaffected |

**The re-key that dissolves most of this.** Cases 8-10, 19-23, 27, 29, 30 are all tests
**of the overlay script**, not of the config. They should move, wholesale, into a file
named for their subject (they are already about a Python program, not about bindings) and
then be **deleted with the program**. Keeping them by stubbing the script is the
scope-metastasis failure.

The three that need genuine re-keying are 1, 7 and 24, and all three want the same key:

> **the chord must reach a bar that is (a) hit-tested and draggable and (b) drawn in the
> system UI font, and it must not steal a row.**

That is the operator's requirement list (b)(c)(d)(a) restated as a test key, and — this is
the point — under the new design **one chord satisfies all four**, so the two-chord role
split the resolvers exist to disambiguate simply goes away. `glance_key()` and
`real_bar_key()` collapse into one `title_bar_chord()`. Delete the split rather than
teaching it a third route.

🚩 **And the premise recorded at `:116-121` must be refuted in place, not deleted.** It
reads: *"The styled overlay is the only thing that can carry our face — kitty's real bar is
a monospace cell grid and the header is SF Pro Semibold, proportional, which kitty's matcher
refuses (four spec forms all fell back to Menlo Italic)."* That sentence is **true of the
`WindowTitleBarScreen` bar** (`~/kitty-482/kitty/window.py:1112` — it is a `Screen`, hence
the cell font) and **false of `render_a_bar`**, which routes through `draw_window_title` →
`cocoa_render_line_of_text`, i.e. CoreText, i.e. the system UI font, bypassing kitty's font
matcher entirely. The whole reason the overlay exists is that premise, and the new design
falsifies it. Mark it refuted beside the original words with the file:line that refutes it.

### 6.4 `tests/deploy-parity.bats` — the ORPHAN consequence of deleting the overlay

Deleting `scripts/kitty-pane-title-overlay.py` from the repo does **not** break
`deploy-parity.bats`'s fixtures (it writes its own synthetic copy at `:735`), but it does
create a real finding on the live layer. `scripts/deploy-parity-assert.sh:1010-1062`:

```
# ── ORPHAN: the live link whose repo source was DELETED (backlog 456d5c61f4c8) ───
    printf 'ORPHAN: rm -f %s\n' "$_l"
    report "ORPHAN" "$_orel" "live link → deleted repo source; resolves to nothing"
```

`~/.claude/scripts/kitty-pane-title-overlay.py` is a per-file symlink into the checkout, so
after the deletion it resolves to nothing and is reported as an ORPHAN until swept.

⇒ **The retirement commit must be followed by a converge** (`bash scripts/deploy-live.sh`,
per this repo's § Standing-converge authorization), and the close must check
`deploy-parity-assert` rather than assume. Note also the warning `deploy-parity.bats:728-735`
carries: the `scripts/*.py` class was once declared `want=0` on a census showing "no live
consumer", and then `config/kitty.conf:346` bound a chord to the deployed copy by absolute
path — four commits of landed work invisible. **Do not re-narrow that glob** as part of
retiring the script.

### 6.5 🚨 The gate nobody has named: our conf must parse under the **installed** 0.48.2

`tests/kitty-drag-arm.bats:34-36` requires the real edited `config/kitty.conf` to parse
through `kitty +runpy … load_config` at **rc=0 with zero bytes of stderr**, and
`tests/kitty-conf-bindings.bats:47-52` resolves `$KITTY` to
`/Applications/kitty.app/Contents/MacOS/kitty` — the **shipped 0.48.2 binary**.

`window_title_bar overlay-top` is **not a valid choice in 0.48.2**
(`~/kitty-482/kitty/options/parse.py:1549-1550` raises
`The value overlay-top is not a valid choice for window_title_bar`). So the moment
`config/kitty.conf` carries the new value, **both of those suites go red on this machine**
until a patched kitty is installed — and they will go red with a message about the config,
which reads like a config defect rather than a version mismatch.

This is the single most likely way the change lands red for a reason unrelated to its
merit. Two ways to handle it, and the choice should be deliberate:

1. **Version-gate the assertion.** Make the drag-arm / bindings suites skip (not fail) when
   the resolved `kitty` does not advertise the new value — probe it the same way the suites
   already probe everything else, through `load_config` on a one-line fixture. A
   `skip` here is honest: the property genuinely cannot be evaluated on that binary.
2. **Keep the new value out of `config/kitty.conf`** until the patched build is installed,
   arming it instead through the existing, purpose-built seam:
   `globinclude drag-arm.d/*.conf` (`tests/kitty-drag-arm.bats:4`), whose whole stated
   purpose is "the landed diff arms nothing". That is what that seam is for, and it is
   already tested.

🚩 Option 2 first, option 1 alongside it. Arming through the drop-in keeps trunk green on
an unpatched box, and the version-gated skip is what makes the suite *able* to go green
again once the patched kitty is installed rather than silently staying skipped forever —
so the skip must print which binary it saw, or it becomes an alarm that can never fire.

### 6.6 The citation rot, stated once

`config/kitty.conf:NNN` is cited by line number in
`tests/kitty-socket-address.bats:8,13,18,331` and `tests/deploy-parity.bats:730`. **All five
are in comments**, so none of them reddens — they simply become wrong. Any insert into
`config/kitty.conf` shifts them. Re-pin them from the real diff hunks
(`git diff -U0 <base> -- config/kitty.conf`, accumulating `new_len - old_len` per hunk), or
better, re-key them onto a stable anchor — the option name, the section heading — since a
line number is a perishable pointer into a living file.

---

## 7. What I could not measure

Stated as gaps rather than reasoned into conclusions.

| Claim | Status |
|---|---|
| `python3 -m gen config` regenerates correctly **from a modified definition.py** | **CONFIRMED** — measured, §1.7, with a byte-idempotent positive control. |
| `./test.py` (the kitty test suite) passes with the patch | **UNMEASURED** — requires a build, forbidden by the brief. |
| `go vet -tags testing ./...` | **UNMEASURED** — not run. |
| `make FAIL_WARN=1 docs` | **UNMEASURED** — sphinx/docutils not installed here (`ty` reports them unresolvable). |
| Whether `render_a_bar`'s hardcoded fg/bg can be parameterised without disturbing its two existing callers | **UNMEASURED** — read the code, did not compile. Both callers pass the same `ui`, so a two-extra-argument change looks mechanical, but that is inference, not a build. |
| Whether a `test_mouse_region` export is acceptable to the maintainer | **UNMEASURED** — precedent exists (`test_encode_mouse`, `~/kitty-482/kitty/mouse.c:1664`); acceptance is a judgement. |
| `overlay-top` vs `top-overlay` legibility | **UNMEASURED** — a judgement supported only by a weak precedent argument (§2.4). |
| The brief's `./autoformat` hazard mechanism | **DOES NOT REPRODUCE in `~/kitty-dev`.** There is no `dependencies/` directory there (`ls: … No such file or directory`) and `autoformat`'s clang file set is **232 files, 0 of them under `dependencies/`** (measured with its own walk rules). Whatever caused the two panics, it was not that tree's clang set. Reported for accuracy only — **I did not run `autoformat`, and the safety rule should stand regardless**; independently, `clang-format` is not installed here, so it would fail anyway. |

## 8. The one-line summary per brief question

1. **Checklist**: 4 hand-edited files (`definition.py`, `to-c.h`, `data-types.h`, `state.h`) + 3 regenerated-and-committed (`types.py`, `parse.py`, `to-c-generated.h`) + `docs/changelog.rst`; **no `docs/conf.rst` change**; generator = `python3 -m gen config`, runnable here with no build via `KITTY_DEVELOP_FROM` + `kitty.app`'s binary (§1.4, §1.7). The recommended A2 variant drops the `to-c*` files entirely.
2. **Name**: `window_title_bar top | bottom | overlay-top | overlay-bottom` — extend the existing option; precedent is `progress_bar`, `scrollbar` and especially `undercurl_style`'s 2×2 (§2.1). Reject `_overlay yes|no`. `_style cells|overlay` is second.
3. **Tests**: the subsystem has **zero** coverage today; copy `kitty_tests/tab_bar.py`'s mock-the-C-layer technique into a new `kitty_tests/window_title_bar.py` asserting the zero-shift identity, plus four lines in `conf_parsing()`. Hit testing needs a new `test_mouse_region` C export (precedent: `test_encode_mouse`). Gates: `ruff check .`, the two greps, `gofmt`, and `ty check` all run here; `./test.py` and the build do not. There is **no clang-format gate in CI** (§3.5).
4. **Docs**: `long_text` **is** the docs and must enumerate the choices itself (measured, §1.8); one `docs/changelog.rst` entry modelled on the `scrollbar` `scrolled-or-hovered` line; no `:pull:` number.
5. **Commits**: five — extract, option, feature, tests, changelog — in kitty's **Sentence case / `Subsystem: ` style**, *not* conventional commits (measured 1/200, §5.1).
6. **Our gates**: 12 suites mention `kitty.conf`; **2 pin the current design** — `kitty-title-zero-shift.bats` (6 of 11 cases break) and `kitty-conf-bindings.bats` (~13 of 32) — 1 mildly (`kitty-drag-arm.bats`), 1 gains an ORPHAN finding (`deploy-parity.bats`), 8 are content-agnostic. Re-key onto *"the chord reaches a hit-tested, system-font bar that steals no row"*; delete the overlay-script cases with the script; and handle §6.5, the unpatched-0.48.2 parse gate, deliberately.

---

## ADVERSARIAL VERIFICATION

Adversarial pass, 2026-09-16. Every `file:line` below was re-opened in the tree it names;
every measurement was re-run from a fresh scratch copy with its own positive and negative
control. Tree tags: `~/kitty-482` = `v0.48.2` (`2cb1d95c3`), `~/kitty-dev` = master
`1d67ecd47`.

**Bottom line.** The report's *measurements* hold up unusually well — I reproduced the
generator result byte-for-byte, including the three baseline hashes — and I additionally
ran the one arm it never ran. But the **recommendation it derives from them (A2, no
`ctype`) is contradicted by its own strongest cited precedent**, its **A2 mechanism does
not work as described**, its **(d) claim is delivered at the wrong font weight**, and its
**§6.5 arming plan is refused by the very suite it cites as authorising it** — with a
measured live-terminal hazard behind that refusal.

### A. UPHELD, re-measured independently

| Claim | Verdict |
|---|---|
| 1 — generator runs with no build via `KITTY_DEVELOP_FROM` | **UPHELD, and strengthened.** My scratch copy's pre-run hashes are *identical* to the report's (`f95a514690157098` / `435b2ccfb6782688` / `6e07e82ffa06ead3`), the unmodified re-run was byte-idempotent, and I ran the **negative control the report only asserted**: with the env var removed, `kitty.__file__` resolves to `…/python-lib.bypy.frozen/kitty/__init__.pyc`, the generator runs, prints `GEN DONE`, and leaves both hashes **unchanged** against a *patched* `definition.py`. The trap is real and silent. |
| 2 — 4 hand-edited + 3 generated; `docs/conf.rst` needs no change | **UPHELD.** `docs/conf.rst` = 101 lines, `grep -c window_title_bar` → 0. |
| 3 — the A1 generated diff is 1 + 1 + (13 + 2) lines | **UPHELD, byte-for-byte.** My `diff -u` against pristine reproduces the report's hunks exactly, including `convert_from_python_window_title_bar` calling `window_title_bar_position(val)`. `tools/cmd/at/set_colors.go` and `tools/themes/collection.go` both `diff -q` clean. |
| 4 — `choices` are not auto-documented | **UPHELD.** And `progress_bar` (`~/kitty-482 kitty/options/definition.py:689-700`) ships the exact `:code:` definition-list template to copy. |
| 5 — kitty collapses, it does not compose | **UPHELD, all six value lists read verbatim** from `~/kitty-482/kitty/options/definition.py`: `progress_bar` `left·right·top·bottom·hidden`; `scrollbar` `scrolled·always·never·hovered·scrolled-and-hovered`; `undercurl_style` `thin-sparse…thick-dense`; `window_logo_position` `top-left…bottom-right`; `focus_follows_mouse` `no·n·false·y·yes·true·drop`; `tab_bar_style` `fade·hidden·powerline·separator·slant·custom`. |
| 9 — `mouse_region` tests `contains_mouse` first **and** requires `trd->screen` | **UPHELD verbatim**, `~/kitty-482 kitty/mouse.c:1067-1081`. |
| 10 — zero title-bar test coverage | **UPHELD, with a positive control the report did not run.** `grep -rl tab_bar kitty_tests/` → **5 files** (instrument works); `title_bar` → 0; `window_title` → 0. The one case-insensitive `titlebar` hit is `kitty_tests/options.py:355 macos_hide_titlebar`, an unrelated OS-window decoration option. |
| 12 — requirement (a) lives entirely in `Window.set_geometry` | **UPHELD**, `~/kitty-482 kitty/window.py:1050-1076` read in full; `render_ynum = ynum - 1` at :1059, `render_top += cell_height` at :1062. |
| 13 — `mouse_region` is `static`; `test_encode_mouse` is the precedent | **UPHELD verbatim**, `~/kitty-482 kitty/mouse.c:1661-1667`. |
| 14 — 5 gates run here, all green | **UPHELD on results** (`ruff check .` → "All checks passed!"; the two greps → 0 lines; `gofmt -s -l tools kittens` → 0 lines) — **but see §C.8: the report's quoted `clang` grep is wrong.** |
| 16 — kitty does not use conventional commits | **UPHELD, re-measured in `~/kitty-dev`**: total=200, start-lowercase=34, conventional-prefix=1, `Subsystem: `=23 (report said 24; my regex differs by one, direction identical). Bonus for commit 5: `^Update changelog$` appears **9** times in those 200. |
| 17 / 18 — the bats case identities and the broken resolvers | **UPHELD on mechanics.** Zero-shift `@test` lines are exactly 54/67/84/97/105/113/122/127/141/155/161; `:127` does forbid `toggle_window_title_bars`; `:161` does assert `^OFF 0 0 0 top$` / `^ON  0 0 1$`. `glance_key()` (`tests/kitty-conf-bindings.bats:106-113`) is literally keyed on the regex `kitty-pane-title-overlay\.py toggle$`. **But the *count* is partly conditional — §C.9.** |
| 20 — `render_a_bar` hardcodes a 1pt border and takes fg/bg from the screen's defaults | **UPHELD**, `~/kitty-482 kitty/shaders.c:838, :849-851, :886`. |

### B. The single best thing in the report, and it is under-claimed

Claim 7 is **UPHELD** (`~/kitty-482 kitty/shaders.c:939-943`) and it is the right PR framing.
It is also **weaker than the truth**. Two things the report did not find:

1. **The drag state machine already exists, entirely in Python, and needs no new code.**
   `~/kitty-482 kitty/tabs.py:1853-1881 handle_window_title_bar_mouse()` already implements
   press → `set_window_being_dragged`, motion → `drag_threshold` → `start_window_drag`,
   release → double-click → `set_window_title`. And `update_mouse_pointer_shape()`
   (`~/kitty-482 kitty/mouse.c:1128-1134`) already maps `r.in_title_bar` →
   `POINTER_POINTER`. So the *whole* of requirement (c) — hand cursor **and** native drag
   **and** the no-op-drag case — falls out the moment `mouse_region` returns
   `in_title_bar` for the band. The PR body should say the feature adds **no new
   interaction code at all**, which is a stronger claim than "add a hit-test region".
2. **`top`/`bottom` shift content *at drag start*, and overlay does not.**
   `~/kitty-482 kitty/tabs.py:1882-1891 start_window_drag()` sets
   `t.force_show_title_bars = True; t.relayout()` for every tab below `min_windows`. Under
   a reserved-row bar that relayout *is* the one-row shift — on every drag. Under overlay
   it is free. That is a second, independent argument for the option, and it is missing.

### C. OVERTURNED — corrected claims

**C.1 — The recommendation (A2, ctype-free) is refuted by the report's own strongest precedent.**
*Report:* "Recommendation: A2 … It leaves all three `window_title_bar*` siblings ctype-free
and consistent … preserves kitty's own division of labour (Python decides policy, C draws)
… a reviewer will ask why [we added a ctype]."
*Corrected:* **Ship A1 (with the `ctype`).** `progress_bar` — which the report itself cites
in §2.1 as the naming precedent — is the exact structural twin of what is being added and
it is a **`ctype` option read directly by C**: `ctype='progress_bar'`
(`~/kitty-482 kitty/options/definition.py:691`), `ProgressBarPosition`
(`kitty/data-types.h:119`, immediately adjacent to `ScrollbarVisibilityPolicy` at :118),
the `Options` field (`kitty/state.h:94`, adjacent to `scrollbar` at :89), the hand-written
converter (`kitty/options/to-c.h:74-86`), and the consumer `const ProgressBarPosition pos =
OPT(progress_bar); … switch (pos)` (`kitty/shaders.c:1168, 1187`). It is a
position-enumerated **window** bar, drawn **over content, outside the cell grid**, in the
same per-window draw path, and it reserves **no row** (`grep -rn progress_bar
kitty/window.py kitty/tabs.py` → **0 hits**). The three ctype-free `window_title_bar*`
siblings are ctype-free *because their bar is a `Screen`* — a cell-grid object Python
legitimately owns. The moment the bar stops being a `Screen` and becomes a C-drawn
out-of-grid quad, it leaves that class and joins `progress_bar`/`scrollbar`, where the
`ctype` is the **consistent** choice, not the anomalous one. The reviewer question the
report fears has a one-line answer: *"same as `progress_bar`."* The report found the
precedent and then recommended against the pattern that precedent follows.

**C.2 — A2's stated mechanism does not work, so it is not the smaller diff either.**
*Report:* "A2 — no `ctype`; extend the existing Python→C call. Add one `int overlay`
argument to `set_window_title_bar_render_data` and one `bool` to `WindowRenderData`. …
**This is the smaller and more kitty-shaped diff**."
*Corrected:* `set_window_title_bar_render_data` (`~/kitty-482 kitty/state.c:1006-1016`) is
`PA("KKKOIIII", …, &screen, …)` — `Screen *screen` is a **required positional** — and its
body unconditionally executes `screen->reload_all_gpu_data = true;`. An overlay bar has
**no `Screen`** (that is the entire point: not constructing `WindowTitleBarScreen` is what
makes the row free). Passing `None` there casts the `None` singleton to `Screen*` and
writes through it. So A2 is not "one extra argument": it additionally requires making the
screen argument optional, guarding that dereference, and — on top of the `mouse.c`
ordering change the report *does* name — relaxing the `trd->screen` guard at
`kitty/mouse.c:1073` **and** the two identical `trd->screen` guards in the draw path
(`kitty/child-monitor.c:853` and `:917`). A1 pays a 15-line generated hunk I measured; A2
pays an ABI change to a shared Python↔C entry point plus four guard relaxations. A1 is
smaller *and* it is the house pattern.

**C.3 — MEASURED: the A2 generated cost (the arm the report recommended but never ran).**
The report measured A1's generated diff and then recommended A2 by inference. I ran A2:
patched `choices` only, no `ctype`, regenerated with the same instrument. Result — exactly
two one-line changes (`kitty/options/types.py:43` `choices_for_window_title_bar` Literal;
`kitty/options/parse.py:1553` the `frozenset`), `to-c-generated.h` **byte-identical**, both
Go files `diff -q` clean. **So the report's cost claim for its own recommendation is now
measured and correct** — it is simply the wrong trade, per C.1 and C.2.

**C.4 — Requirement (d) is delivered at the WRONG WEIGHT, and "refute the premise in place" would install a new false premise.**
*Report (claim 8):* "Only `render_a_bar` reaches CoreText. This refutes the premise recorded
in `tests/kitty-conf-bindings.bats:116-121` that the overlay is 'the only thing that can
carry our face'."
*Corrected:* **Half-refuted.** The premise has two halves. The first — *"kitty's real bar is
a monospace cell grid"* — is genuinely refuted for `render_a_bar`. The second is
**`SF Pro Semibold`**, and `render_a_bar` cannot deliver it. Traced end to end in
`~/kitty-482`: `shaders.c:856 draw_window_title(...)` → `glfw.c:1083` (macOS branch, note
`font_sz_pts UNUSED`) → `cocoa_render_line_of_text` (`kitty/core_text.m:945`) → `ensure_ui_font`
(`kitty/core_text.m:920-941`), whose whole font selection is
`CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL)` — the system UI font at
**default weight, i.e. SF Pro Regular**, sized only by the bar's pixel height. There is **no
weight parameter anywhere** in `render_a_bar → draw_window_title → cocoa_render_line_of_text`,
and `system_ui_font` is a single file-static cached on height alone (`core_text.m:40`). The
overlay it replaces uses `UI_VARIATION = "Semibold"`
(`claude-infrastructure/scripts/kitty-pane-title-overlay.py:275`), chosen after a recorded
four-way comparison (`:264-272`). ⇒ Mark the premise **PARTIALLY refuted** beside the original
words: a proportional system face is reachable without the overlay, but at Regular; Semibold
needs a weight threaded through `ensure_ui_font`, which is a *second* upstream ask. Writing a
flat "refuted" into that file installs a new false sentence in the one file whose own header
warns against exactly this.

**C.5 — §6.5's arming plan is refused by the suite the report cites as authorising it.**
*Report:* "Keep the new value out of `config/kitty.conf` … arming it instead through the
existing, purpose-built seam: `globinclude drag-arm.d/*.conf` (`tests/kitty-drag-arm.bats:4`),
whose whole stated purpose is 'the landed diff arms nothing'. That is what that seam is for,
and it is already tested. 🚩 Option 2 first."
*Corrected:* `tests/kitty-drag-arm.bats` case 5 — *"🚨 the tracked tree contains NO
config/drag-arm.d/\*.conf"* — refuses a repo-side drop-in through **two arms, deliberately**:
ARM 1 globs the **working tree** (`for f in "$ARMDIR"/*.conf; do [ -e "$f" ] && …`), so an
**untracked** file fails it too; ARM 2 is `git ls-files`. The report's own §6.1 triage row
states this constraint (*"config/drag-arm.d/ must hold only drag.conf.example"*) and §6.5 then
recommends violating it one screen later. The seam is real, but it exists **only** as the
LIVE-side, untracked `~/.config/kitty/drag-arm.d/drag.conf`, created as a real empty file by
`scripts/kitty-setup.sh` §1b and never present in the repo. State it that way or the next
session reddens a land.

**C.6 — And arming through that live drop-in has a MEASURED hazard the report creates and never names.**
The report's §6.2 row #6 recommends raising the main config to `window_title_bar_min_windows 1`
("With a zero-cost overlay bar the right main-config value is `1`"). Combine that with §6.5's
arming plan on a box whose kitty is still 0.48.2 and you get, **measured** through the live
reload path (`~/kitty-482 kitty/boss.py:3209` passes `accumulate_bad_lines`, so a bad value is
collected rather than fatal):

```
$ printf 'window_title_bar overlay-top\nwindow_title_bar_min_windows 1\n' > combo.conf
$ kitty +runpy 'load_config("combo.conf", accumulate_bad_lines=bad)'
window_title_bar = top | min_windows = 1
bad lines: 1
```

`overlay-top` is rejected and **falls back to the default `top`** while `min_windows 1` is
accepted — i.e. **reserved-row title bars ON for every pane: the one-row content shift the
operator has rejected in writing, live, on a 9-session terminal, ~100 ms after the write**
(the config dir is watched by a `kitten __watch_conf__` child). A fail-open default turning a
version mismatch into the exact rejected behaviour. ⇒ Either arm the value and `min_windows`
**together, never separately**, or gate the drop-in on a probe of the installed binary first.

**C.7 — Claim 19 is right in direction, understated in magnitude.**
*Report:* the suites "go red with a message about the config, which reads like a config defect".
*Corrected:* both suites call `load_config(path)` with **no** `accumulate_bad_lines`
(`tests/kitty-conf-bindings.bats:64-65` and `:652-653`), which is the **raising** form
(`~/kitty-482 kitty/conf/utils.py:405-410`: `except Exception as e: if accumulate_bad_lines is
None: raise`). Measured: **rc=1 and 1104 bytes of Python traceback on stderr**, ending
`ValueError: The value overlay-top is not a valid choice for window_title_bar`. Against
`kitty-drag-arm.bats:34-36`'s *"rc=0 with 0 bytes of stderr"* that is a hard, loud failure, not
a message. (Positive control: the same probe on `window_title_bar bottom` → rc=0, 0 bytes.)

**C.8 — Claim 14's quoted evidence is false even though its conclusion is true.**
*Report:* "`grep -n "clang" .github/workflows/ci.yml` → no match."
*Corrected:* re-run in `~/kitty-482` → **3 hits**: `.github/workflows/ci.yml:23 cc: [gcc, clang]`,
`:40`, `:42` — the compiler matrix. The **conclusion stands** (no clang-format gate; `command -v
clang-format` → nothing; `.clang-format` absent from `~/kitty-482`), but a reader re-running the
quoted command gets a different answer than the document promises, which is the shape that
erodes trust in the twenty citations around it. Quote `grep -n clang-format` instead.

**C.9 — The "19 of 43" headline is partly the cost of a DESIGN CHOICE, not of the design.**
Zero-shift cases #6 (`:113`) and #11 (`:161`) break **only** because the report elects to raise
`window_title_bar_min_windows` from 0 to 1 in the main config. That is the report's own
recommendation, not a property of an overlay bar — an overlay design that leaves `min_windows 0`
and arms bars by another route leaves both cases green. Report the figure as conditional
("19 of 43 **under the min_windows→1 variant**; 17 of 43 otherwise") or the next session inherits
a cost attributed to the wrong cause.

### D. NEW — load-bearing defects nobody has named

**D.1 — "free" is false: `render_a_bar` churns a GPU texture on EVERY call.**
`~/kitty-482 kitty/shaders.c:861-874`: `glGenTextures` → `glTexImage2D` (a full
`bar_width × bar_height × 4` upload from CPU RAM) → `draw_graphics` → `free_texture`
(`kitty/gl.c:104`, i.e. `glDeleteTextures`). **There is no texture cache** — only the CoreText
*rasterisation* is cached, via `bar->last_drawn_title_object_id`. Both existing consumers are
**transient** (`draw_hyperlink_target` fires only while a hyperlink is hovered;
`draw_window_number` only while `screen->display_window_char != 0`), so the churn is bounded in
time and nobody has ever paid for it continuously. A **persistent** title band makes it
per-window-per-frame, inside `draw_cells_with_layers` (`shaders.c:1381-1382`), plus a resident
`malloc`'d `bar->buf` per window (≈165 KB at the operator's geometry: 896 × 47 × 4). Against the
goal's *"lowest to zero latency and memory pressure"* the PR needs a texture cached on
(title, size) and invalidated with `needs_render` — not the word "free".

**D.2 — Both existing consumers SHARE `window->title_bar_data`; a third will thrash it.**
`shaders.c:929` — `draw_hyperlink_target` calls
`render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom)`,
passing **`title_bar_data`** as the bar cache while taking the string from
`url_target_bar_data`. `shaders.c:943` — `draw_window_number` passes the same
`&ui->window->title_bar_data`. A third, *persistent* consumer on that same
`WindowBarData` makes `bar->last_drawn_title_object_id` alternate between the URL and the
title **every frame** whenever a hyperlink is hovered, forcing a full `cocoa_render_line_of_text`
per frame (the expensive path). ⇒ The new consumer needs **its own `WindowBarData` field** on
`Window` (`kitty/state.h:276` is where the two live). This is a one-line addition and a
silent 10× regression if missed.

**D.3 — The band is 113 % of a row, and the report's own test T2 asserts it is 100 %.**
`shaders.c:839` `bar_height = ui->cell_height + 2`; `:874` `border_rect.height = bar_height + 2 *
border_width`; `:838` `border_width = ceil(thickness_as_float(os_window, 1))` =
`ceil(box_drawing_scale[1] × dpi / 72)`, and `box_drawing_scale` defaults to `0.001, 1, 1.5, 2`
(`kitty/options/definition.py:230-233`) so level 1 = **1.0 pt**. At the operator's dpi 144 /
cell 45 px: border_width **2**, bar_height **47**, **drawn band = 51 px against a 45 px row — a
6 px overhang into row 2.** The report's T2 proposes asserting *"the band passed to
`set_window_title_bar_render_data` is `cell_height` tall"*. Then the **drawn** band and the
**hit-tested** band differ by 6 px, and both readings are bad: a 6 px strip that looks like the
bar but starts a text selection (fails (c) at the edge), or a hit band that swallows the top
6 px of row 2 from content. ⇒ Decide this explicitly in the PR, assert the **same** rectangle in
both places, and state which one wins.

**D.4 — the `to-c.h` converter has a first-character collision, and fixing it *upgrades* §2.4.**
The house idiom switches on `q[0]` and disambiguates a shared first char with one `strcmp` —
`scrollbar` does exactly that for `scrolled` vs `scrolled-and-hovered`
(`~/kitty-482 kitty/options/to-c.h:62-71`); `progress_bar` (`:74-86`) needs no strcmp because its
five values have five distinct initials. `overlay-top`/`overlay-bottom` collide on `'o'` and need
**one** `strcmp`. `top-overlay`/`bottom-overlay` would collide **twice**, on `'t'` and `'b'`. So
§2.4's naming preference — which the report flagged UNMEASURED and "weak-to-moderate" — has a
hard mechanical argument it did not find: `overlay-*` costs one `strcmp` in the house converter,
`*-overlay` costs two. Keep `overlay-top` / `overlay-bottom`.

**D.5 — the proposed test filename collides with a documented user-facing filename.**
kitty documents a user hook at **`window_title_bar.py` in the kitty config directory**
(`~/kitty-482 kitty/options/definition.py:1973`, the `{custom}` variable of
`window_title_template`). A new `kitty_tests/window_title_bar.py` reads as a test *of that hook*.
Name it `kitty_tests/window_title_bar_layout.py`.

### E. What I could not re-measure

- `ty check` before/after the patch (claim 15) — not re-run; the report's protocol (treat it as a
  differential, never pass/fail) is sound on its face and `ty 0.0.81` is confirmed installed.
- `./test.py`, `go vet`, `make docs` — same gaps the report declares; I did not close them.
- Whether `render_a_bar`'s fg/bg can be parameterised without disturbing its two callers — still
  inference, not a build. Note D.2 makes that change *larger* than the report assumed, because the
  new consumer wants its own `WindowBarData` as well.
- The maintainer's acceptance of a `test_mouse_region` export — a judgement, unmeasurable here.

