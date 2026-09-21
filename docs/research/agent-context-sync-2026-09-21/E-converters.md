# Axis E — document→markdown converters for the L3 derived layer

Scope: which converter writes `docs/` from `docs-source/`, per format, judged on **determinism first**
(byte-stable output for unchanged input — the property that makes `git diff` on the derived layer mean
"the source changed"), then fidelity, speed, licensing.

Everything marked **[tested]** was run on this machine today (macOS arm64, Python 3.11, fresh venv in
`…/scratchpad/conv`). Reproduction commands in §9. Everything marked **[cited]** carries a URL.
Everything marked **[reasoning]** is mine and unverified.

---

## 1. The verdict in one table

| Format | Converter | Why |
|---|---|---|
| `.docx` | **pandoc 3.11** (`-f docx -t gfm --extract-media`) with Docling as the fallback for image-heavy decks | deterministic pure-XML path, real table headers; MarkItDown emits a **blank table header row** [tested] |
| `.xlsx` | **custom openpyxl emitter** (~40 lines, §5.2) — *not* MarkItDown, *not* pandas | only route that keeps merged-cell headers, formulas beside values, and empty≠`NaN` [tested] |
| `.pptx` | **MarkItDown** (notes + slide-number anchors) or Docling (spans, reading order) | both emit speaker notes; MarkItDown is 0-model and byte-stable [tested] |
| `.pdf` born-digital | **PyMuPDF4LLM** (`table_strategy="lines_strict"`, `page_chunks=True`) | 5.5 pages/s and byte-stable over 3 runs [tested] vs 1.3 p/s Docling [cited] / 0.22 p/s Marker on a Mac [cited]. **AGPL-3.0** — see §7 |
| `.pdf` scanned / table-critical | **Docling** or **Marker**, run **once per content hash into a cache** | both are batched-torch pipelines; Docling is *measurably* non-deterministic under concurrency [cited]. The cache, not the converter, is what makes the derived layer stable (§2) |
| `.msg` / `.eml` | **Docling email backend** (`mailparser` + `python-oxmsg`) | MarkItDown has **no `.eml` converter at all** and dumps raw MIME + base64 attachments into the markdown [tested] |
| images | PyMuPDF/Pillow extract + **optional** VLM caption written to a **sidecar**, never inline | a caption is model output; inlining it makes every model upgrade a whole-corpus diff [reasoning] |

---

## 2. Determinism is the load-bearing axis, and the answer is not "pick a deterministic converter"

**The measured split is pure-XML/pure-text parsers (stable) vs batched-neural pipelines (not).**

### 2.1 Stable, tested here

| Converter (version) | Input | 3 runs | Result |
|---|---|---|---|
| MarkItDown 0.1.7 | fix.docx / fix.xlsx / fix.pptx / fix.pdf | sha256 ×3 | **identical** [tested] |
| PyMuPDF4LLM 1.28.2 | 12-page real statement PDF | sha256 ×3 | **identical** [tested] |
| PyMuPDF4LLM 1.28.2 | image-only PDF → **Tesseract OCR path fired** | sha256 ×3 | **identical** [tested] |
| PyMuPDF 1.28.2 `get_pixmap().tobytes("png")` | page raster | sha256 ×3 | **identical**, and no `tIME` chunk in the PNG [tested] |

The OCR row matters: Tesseract at a fixed version/dpi/langdata was byte-stable, so an OCR step is not
automatically a nondeterminism source — *batched GPU inference* is.

### 2.2 Not stable — measured by the project's own users

Docling under concurrency: *"the same PDF with the same options comes back with a different
`DoclingDocument` structure — text items merged or split, labels changed"*; root cause *"docling's
threaded `StandardPdfPipeline` … assembles model batches on a wall-clock timer, so under load it
flushes partial batches and inference is not bit-identical across batch sizes."* Measured 15 concurrent
requests: 1 worker → 12/12 identical; 2 workers (the default) → 6 of 15 differ; 5 workers → 3–5 of 15
differ; **5 workers + batch size 1 → 12/12 identical**.
[cited] https://github.com/docling-project/docling-serve/issues/701 (upstream: docling#4274)
⇒ **Workaround is real and cheap**: `DOCLING_SERVE_LAYOUT_BATCH_SIZE=1`, `TABLE_BATCH_SIZE=1`, or a
single worker. Pinning batch size restores reproducibility at a throughput cost.

Docling image extraction: *"Image extraction is **not guaranteed to be deterministic**. Docling uses
pypdfium2's `render()` method to rasterize page regions and then crop/resize them. The code renders at
1.5x scale and then resizes, which involves floating-point operations."*
[cited] https://github.com/docling-project/docling/discussions/3137 — **caveat: this is Dosubot, an LLM
bot, not a maintainer.** Treat as a mechanism hypothesis, not a project statement. The mechanism
(float scale→resize) is plausible and would be CPU/BLAS-dependent [reasoning].

Marker: the only "deterministic" claim I could find is **marketing, and about a different property** —
*"It delivers deterministic, high-fidelity parsing without the hallucination or instability of larger
LLMs"* ([cited] https://modal.com/blog/datalab-and-modal, written by Modal). That is "does not
hallucinate", not "byte-identical across runs". Marker is the same architecture class as Docling
(batched torch + Surya) so I would assume the same batch-size sensitivity until tested. **No test run
— GPU-class dependency, not installed here.** `--use_llm` is nondeterministic by construction.

### 2.3 The architectural consequence (this is the finding, not the matrix)

> **Do not require the converter to be deterministic. Require the derived file to be content-addressed
> and write-once.** [reasoning]

Key the cache on `(source_sha256, converter_id, converter_version, options_hash)`. If that key is
present, the markdown is copied from cache and **the nondeterministic converter never runs again** —
so a re-render of an unchanged source can never produce a git diff, whatever the model does. This
converts "we can only use deterministic converters" (which rules out every good PDF converter) into
"we may use any converter, and a rerun costs nothing". It also makes a converter **version bump** an
explicit, dated, reviewable event: bumping `converter_version` changes the key, re-renders the whole
affected class, and lands as one large commit you *intended*, instead of drip-feeding mystery diffs.

Second-order rule: **never put a non-content-derived field in the markdown body or frontmatter**
(`converted_at`, a run id, a wall-clock). Any such field makes every re-render a diff and destroys the
signal you built the layer for. Put `converted_at` in a **sidecar manifest**, not in the file. [reasoning]
(Brief's proposed frontmatter includes `converted_at` — §6 argues it out.)

---

## 3. Converter × format matrix

Fidelity grades are from the tested outputs in §4–5, not from vendor claims.

| | docx | xlsx | pptx | pdf digital | pdf scanned | msg | eml | determinism | license |
|---|---|---|---|---|---|---|---|---|---|
| **MarkItDown 0.1.7** | B− (blank header row) | **D (silent `NaN`)** | A− (notes+slide nums) | C (pdfminer+pdfplumber; 2× tokens) | ✗ | C (From/To/Subject/Body, **no Date, no attachments**) | **✗ raw MIME** | **stable [tested]** | MIT |
| **Docling** | A | A− (spans; still `data_only`) | A (notes, spans, reading order) | A− | A (OCR, TableFormer) | A (via `python-oxmsg`→RFC822) | A (mailparser, attachments as metadata only) | **batch-sensitive [cited]**; fixable with batch=1 | MIT (models separate) |
| **pandoc 3.11** | A (native reader) | B (reader added 3.8.3) | B (reader added 3.8.3) | ✗ **cannot read PDF** | ✗ | ✗ | ✗ | stable [reasoning] | GPL-2.0+ (CLI ⇒ no linking issue) |
| **PyMuPDF4LLM 1.28.2** | ✗ | ✗ | ✗ | **A− + fastest** | B (auto-Tesseract) | ✗ | ✗ | **stable [tested]** | **AGPL-3.0 / commercial** |
| **Marker** | B | B | B | A (self-reported) | A | ✗ | ✗ | untested; assume batch-sensitive | Apache-2.0 code, **weights AI-Pubs Open-RAIL-M, free only under $5M rev** [cited] |
| **unstructured** | B | B | B | B/A (hi_res) | A | B | B | untested | Apache-2.0 |
| **openpyxl / python-pptx / python-docx** | B+ (DIY) | **A (only route that keeps formulas)** | A (DIY) | ✗ | ✗ | ✗ | ✗ | stable [tested] | MIT |

Cited version/benchmark anchors:
- pandoc **3.8.3 (2025-12-01)**: *"Add `pptx` (PowerPoint) as new input format"* and *"Add `xlsx`
  (Microsoft Excel) as an input format"* — [cited] https://raw.githubusercontent.com/jgm/pandoc/main/changelog.md.
  Both appear in the `-f` list on main [tested: `grep` of MANUAL.txt]. Latest release **3.11, 2026-08-29**
  [cited, GitHub releases API]. **This corrects the common belief that pandoc reads neither.**
- Docling throughput, own technical report, 225-page set, OCR off: **M3 Max 1.27 p/s @4 threads,
  1.34 @16; 6.20 GB RAM**; Xeon E5-2690 0.60/0.92 p/s; pypdfium backend 2.45 p/s at lower quality —
  [cited] https://arxiv.org/html/2408.09869v5.
- Marker on olmocr-bench (**self-reported by Datalab**): balanced GPU 76.0% @2.9 p/s, fast GPU 66.6%
  @7.4 p/s, CPU no-OCR 43.6% @23.7 p/s, vs MinerU 72.7% and **docling 50.3%** —
  [cited] https://github.com/datalab-to/marker README. On an **M4 Mac (MPS) Marker is 0.22 p/s**
  [cited] Modal blog. Adversarial note: a vendor benchmark scoring a competitor at 50.3% is the
  weakest evidence class in this report; and there is **no public leaderboard ranking Docling/Marker/
  MinerU on one suite** — any tidy three-way table is stitched from different suites/versions/corpora
  [cited, search synthesis over OmniDocBench material].

---

## 4. Tested failure modes you would otherwise ship

### 4.1 MarkItDown silently destroys Excel data — the single sharpest finding

Fixture: `Region | Spend(merged B1:C1) | …` plus a `Total` column holding `=B2+C2`.

```
## Q3 Budget
| Region | Spend | Unnamed: 2 |      ← merged header lost; 2nd half renamed "Unnamed: 2"
| --- | --- | --- |
| West | 100.0 | 200 |               ← int 100 became "100.0" (pandas dtype)
| East | NaN | 50 |                  ← empty cell rendered as the literal string NaN
```
and with a proper header over the formula column:
```
| Region | A | B | Total |
| West | 100 | 200 | NaN |           ← EVERY computed value is NaN
```
Without a header over that column it **vanishes entirely** — no error, exit 0. [tested]

Mechanism, confirmed by reading source: MarkItDown's `_xlsx_converter.py` is `pandas.read_excel`
→ `to_html` → markdownify; pandas' `_openpyxl.py` reader hardcodes
`{"read_only": True, "data_only": True, "keep_links": False}`
([cited] https://raw.githubusercontent.com/pandas-dev/pandas/main/pandas/io/excel/_openpyxl.py), and
openpyxl docs: `data_only` *"controls whether cells with formulae have either the formula (default) or
the value stored the last time Excel read the sheet"* ([cited] openpyxl tutorial). Verified directly:
`data_only=True → D2 is None`, `data_only=False → D2 == '=B2+C2'` [tested].

**Corporate blast radius:** workbooks last saved by Excel *do* carry cached values, so this looks fine
in a smoke test. Workbooks emitted by **anything that is not Excel** — BI/Power-BI exports, python/
`openpyxl` scripts, many SharePoint/web exports, `xlsxwriter` — carry no cached values, and every
derived number in them becomes `NaN` in `docs/` with no warning. An agent then reads and reasons over
a table of `NaN`. **Docling has the same `data_only=True` call** ([cited] its `msexcel_backend.py`), so
it inherits the same hazard; it only wins on merged cells (`row_span`/`col_span`) and sheet grouping.

### 4.2 MarkItDown cannot parse `.eml` — it has no converter for it

There is no `_eml_converter.py` in `packages/markitdown/src/markitdown/converters/` [cited, GitHub
contents API]. A `.eml` falls through to the plain-text converter. Fed a realistic multipart message,
`docs/` gets:

```
Subject: =?utf-8?B?UTMgZMOpY2s=?=          ← RFC2047, never decoded
Content-Transfer-Encoding: base64
SGkgdGVhbSwgdGhlIFEzIGRlY2sgaXMg…          ← body still base64
…application/pdf; name="deck.pdf" … JVBERi0xLjQK   ← attachment bytes inlined
```
[tested] — unreadable, ungreppable, and the attachment base64 is pure token cost. `.msg` is handled but
thinly: `olefile`, fields **From / To / Subject / Body only — no Date, no attachments**
([cited] `_outlook_msg_converter.py`).

Docling is the opposite: `mailparser` for `.eml`, `python-oxmsg` to convert `.msg` → RFC-822 bytes and
then the *same* path (so one code path, one output shape for both), Subject as title, From/To/Date as
text, HTML bodies routed through the HTML backend, and attachments emitted as **filename + content-type
metadata while "the encoded payload is never included"** ([cited]
https://raw.githubusercontent.com/docling-project/docling/main/docling/backend/email_backend.py).
That last property is exactly what you want: the attachment becomes a *link* to its own converted
markdown, not a base64 blob.

### 4.3 MarkItDown docx tables lose their header row

```
# Scope
body text
|  |  |          ← synthesized empty header
| --- | --- |
| a | b |        ← the real header, demoted to a body row
| 1 | 2 |
```
[tested]. Cause: mammoth emits `<td>` not `<th>`, markdownify then manufactures an empty header.
Pandoc's native docx reader does not have this problem [reasoning — untested here, pandoc not installed].

### 4.4 Both PDF routes mangle a real corporate PDF, differently

12-page browser-printed bank statement, same file, both converters:

| | chars | table lines | failure |
|---|---|---|---|
| PyMuPDF4LLM | 22,341 | 285 | wraps blocks in `<!-- Start of picture text -->`, emits a junk `\|<br>\|` table, double-marks headings `## **…**` |
| MarkItDown (pdfminer+pdfplumber) | **42,796** | 528 | **one table per transaction row**, each with its own `\| --- \|` separator; the real column header is emitted as loose prose, outside the table |

[tested]. MarkItDown's output is **1.9× the tokens** for *worse* structure. Neither is usable for
table-accurate retrieval on this class of document — which is the argument for routing table-critical
PDFs to Docling/Marker behind the §2.3 cache rather than pretending a cheap extractor suffices.

---

## 5. Per-format recommendations with the specifics

### 5.1 PPTX — both good; pick on anchors
MarkItDown emits `<!-- Slide number: N -->` before each slide and `### Notes:` for speaker notes
([cited] `_pptx_converter.py`; [tested] output below), converts tables and even charts to markdown
tables, and emits `[unsupported chart]` where it cannot.
```
<!-- Slide number: 1 -->
# Deck Title
| k | v |
| rate | 4.2% |
### Notes:
SPEAKER NOTE: decision deferred to Oct
```
Docling also extracts notes (`notes_slide.notes_text_frame.text`), gives `page_no = slide_ind + 1`,
table row/col spans, EMF/WMF rasterization via LibreOffice, and sorts shapes **top-to-bottom then
left-to-right with a 45,720 EMU (~0.05") row tolerance** ([cited] `mspowerpoint_backend.py`) — i.e. it
fixes the reading-order problem MarkItDown ignores (MarkItDown walks `shapes` in XML order).
**Take MarkItDown when decks are linear; take Docling when slides are dense multi-column.**

### 5.2 XLSX — write the ~40-line emitter; every off-the-shelf converter is wrong here
Open the workbook **twice** (`data_only=True` for values, `data_only=False` for formulas), propagate
merged-range anchors into every covered cell, and emit `value \`=FORMULA\``:
```
### Sheet: Q3 Budget  (used range A1:D3)
| Region | Spend | Spend |         |
| West   | 100   | 200   | `=B2+C2` |
| East   |       | 50    | `=B3+C3` |
```
[tested — produced by the script in §9]. Against MarkItDown on the identical file this preserves the
merged header, keeps `100` as `100`, renders empty as empty rather than `NaN`, and **keeps the formula
even when the cached value is absent**. Answering the brief's Q(b) directly: **yes, preserve formulas
beside values** — the formula is the only surviving evidence of intent when the cache is empty, it is
short, and an agent asked "how was Total derived" cannot answer from the number.
Also emit the used-range in the heading: it is the cheapest way for an agent to know whether it is
looking at the whole sheet. Pivot tables and charts have no markdown form — emit a stub line naming
them so the agent knows to open the binary [reasoning].

### 5.3 PDF — two tiers, and the tier choice is a property of the *document*, not the corpus
Tier 1 (default, ~95% of business PDFs): PyMuPDF4LLM, `table_strategy="lines_strict"` (its default),
`page_chunks=True` to get per-page dicts for page-anchored provenance, `write_images=True,
image_path=…` for figures. **5.5–5.7 pages/s on this laptop** [tested], byte-stable, and it
auto-detects pages needing OCR and calls Tesseract on just those (it did so on page 0 of the real
statement, and stayed byte-stable across 3 runs) [tested].
Tier 2 (scanned, dense tables, forms): Docling with `LAYOUT_BATCH_SIZE=1`/`TABLE_BATCH_SIZE=1`, or
Marker; ~1.3 p/s and ~6.2 GB [cited] / 0.22 p/s on an M4 Mac [cited]. At tens of GB this is a
**one-time backfill measured in days on one laptop** — budget for it explicitly or run tier 2 on a
server [reasoning].
Routing signal: per page, `len(page.get_text()) < threshold` ⇒ scanned; count ruled lines / detect a
form ⇒ table-critical. Cheap, deterministic, computable in PyMuPDF before you choose [reasoning].

### 5.4 Email and Teams
`.msg`/`.eml` → Docling's email backend (§4.2). Thread-level markdown is **not** something any
converter gives you: they all emit one message per file. Build threads at L4 from
`Message-ID`/`In-Reply-To`/`References` (or Graph `conversationId`) into one
`threads/<slug>.md` with per-message `##` sections, and leave the per-message files as the 1:1 mirror
[reasoning]. Teams exports: neither MarkItDown nor Docling has a chat backend (Docling ships `boxnote`
and `webvtt`, not Teams) [cited, backend listing]. Teams content arrives either as Graph
`chatMessage` JSON or as a compliance/user-export HTML bundle; both need a project-local emitter.
**Meeting recordings/transcripts do have a route: Docling reads WebVTT and does ASR on
WAV/MP3/MP4** ([cited] README) — VTT is the one to prefer, since ASR output is model output and
belongs behind the §2.3 cache.

### 5.5 Images and captions
Extract bytes (deterministic: PyMuPDF PNG had no `tIME` chunk and hashed identically ×3 [tested]) and
store under a content-addressed name. Caption with a VLM **only into a sidecar** (`figures/<sha>.md` or
a `captions.jsonl`), keyed by image sha — so the caption survives a re-render, and a model change
rewrites only sidecars. MarkItDown supports captions inline via `llm_client`/`llm_model` (tested with
GPT-4o) [cited README]; Docling has VLM picture description. Inline is the trap [reasoning].

---

## 6. Output layout and provenance frontmatter

```
docs/
  _manifest/                      # NOT markdown; the L2 state
    index.jsonl                   # one row per source: path, sha256, etag, mtime, converter, key, outputs[]
    cache/<key>/…                 # write-once converter output, key = sha256(source_sha|conv|ver|opts)
  onedrive/<mirrored path>/<Name>.md
  onedrive/<mirrored path>/<Name>.xlsx.d/          # multi-part sources become a DIRECTORY
        00-index.md               # sheet list, used ranges, links
        01-Q3-Budget.md
        02-Notes.md
  mail/<year>/<yyyy-mm-dd>-<from-slug>-<subject-slug>.md
  mail/threads/<thread-slug>.md   # L4-built, links to the per-message files
  figures/<sha256[:16]>.png  +  figures/<sha256[:16]>.md   # caption sidecar
```

Frontmatter — **only content-derived fields**:
```yaml
---
source_path: "OneDrive/Client X/Q3 Budget.xlsx"     # logical, stable across sync roots
source_id: "01ABCDEF…"                              # Graph driveItem id — survives RENAMES, unlike path
source_hash: "sha256:…"                             # of the source bytes
source_etag: "\"{GUID},12\""                        # Graph eTag/cTag; cheap change check without download
source_modified: "2026-09-18T14:03:11Z"             # lastModifiedDateTime from the source system
source_version: 12                                  # cTag counter / version-history ordinal if available
part: {kind: sheet, name: "Q3 Budget", index: 1, of: 2}
converter: pymupdf4llm                              # or markitdown | docling | pandoc | xlsx-native
converter_version: "1.28.2"
options_hash: "sha256:…"                            # so a flag change is as visible as a content change
content_hash: "sha256:…"                            # of THIS markdown body — lets L4 skip unchanged parts
---
```
**Omit `converted_at` from the file.** It is the one proposed field that is not content-derived: with it,
any forced re-render rewrites every file and the `git diff` stops meaning "the source changed". Keep it
in `_manifest/index.jsonl`, where it is queryable and diff-free. [reasoning — this is a direct amendment
to the brief's field list.]

`source_id` is the other amendment: keying on path alone makes a SharePoint rename look like
delete+create, which is exactly the churn the design is trying to avoid; Graph's immutable item id
collapses it to a metadata-only edit [reasoning, consistent with the delta-API design on axis L1].

Splitting rule: **one markdown file per addressable unit an agent would cite** — per sheet, per email;
per slide only when decks exceed ~40 slides (below that, a single file with `<!-- Slide N -->` anchors
greps better than 40 files). PDFs stay one file with `page_chunks` used to emit `<!-- page: N -->`
anchors, so a citation can be `file.md#page-7` [reasoning].

---

## 7. Licensing — the one thing that can veto the recommended stack

| Package | License | Consequence in a corporate tenant |
|---|---|---|
| MarkItDown 0.1.7 | **MIT** [cited] | free |
| Docling | **MIT** (model weights licensed separately) [cited README] | free; check each model's license before shipping weights |
| pandoc 3.11 | GPL-2.0+ | invoked as a **subprocess**, so no linking obligation [reasoning] |
| openpyxl / python-docx / python-pptx | MIT | free |
| **PyMuPDF / PyMuPDF4LLM 1.28.2** | **"Dual Licensed - GNU AFFERO GPL 3.0 or Artifex Commercial License"** [tested: `pip show`; COPYING is AGPL-3.0 verbatim] | **AGPL.** Internal-only batch use is defensible, but if the derived docs are ever served over a network by a service that links PyMuPDF, AGPL §13 bites. Many enterprise OSS policies deny AGPL outright. **Get this cleared before it becomes the default PDF path, or fall back to Docling (MIT) + pypdfium2.** |
| Marker | code Apache-2.0; **weights "Modified AI Pubs Open Rail-M … free for research, personal use, and startups under $5M funding/revenue"** [cited README] | a corporate deployment above that threshold **needs a paid license** — usually disqualifying for this use case |
| unstructured | Apache-2.0 [cited LICENSE.md] | free; the paid platform adds chunking/embedding/enrichment, the OSS lib still partitions locally [cited README] |
| `extract-msg` | **GPL-3.0** [cited LICENSE.txt] | avoid; Docling's `python-oxmsg` route reaches `.msg` without it |

---

## 8. Alternatives considered and ruled out

- **One converter for everything (MarkItDown).** Ruled out by §4.1/§4.2: silent `NaN` on Excel and no
  `.eml` parsing are data-loss bugs, not fidelity gripes.
- **One converter for everything (Docling).** Closest to viable and the best *single* choice if you want
  one binary; ruled out as the default only on speed (1.3 p/s, 6.2 GB) and the batch nondeterminism,
  both of which matter at "tens to hundreds of GB". Excellent as tier 2 + email + pptx.
- **Marker as default.** Ruled out on the weights license (<$5M revenue clause) and 0.22 p/s on Mac
  hardware; strong if you have GPUs and a commercial license.
- **unstructured.** Apache-2.0 and broad, but its markdown is element-list-shaped rather than
  document-shaped, and its `hi_res` PDF path has the same batched-model profile as Docling without
  Docling's table model. No advantage found on any axis here.
- **LLM/VLM-only conversion (feed the PDF to a model, ask for markdown).** Rejected: output is not
  reproducible, cost scales with corpus not with diff, and hallucinated table cells are undetectable
  downstream. Where a VLM helps (scanned tables), put it behind the §2.3 write-once cache so it runs
  once per content hash. [reasoning]
- **Storing only the binaries and calling a tool at query time** (the "black box" the operator is
  moving away from): rejected by the premise, but note it does have one real advantage — no derived
  layer to keep in sync. The counter is that grep-ability and `git diff` are the whole point.

---

## 9. Reproduce it

Everything tested lives in
`/private/tmp/claude-501/…/scratchpad/conv/` (venv at `./v`, fixtures `fix.{docx,xlsx,pptx,pdf}`,
`hdr.xlsx`, `multi.eml`, `real.pdf`, outputs `real.p4l.md` / `real.mid.md`).

```bash
python3 -m venv v && ./v/bin/pip install "markitdown[docx,pptx,xlsx,pdf,outlook]" pymupdf4llm python-docx
# determinism
for f in fix.docx fix.xlsx fix.pptx fix.pdf; do
  for i in 1 2 3; do ./v/bin/markitdown $f | shasum -a256 | cut -c1-16; done; done
# the Excel data-loss repro
./v/bin/markitdown hdr.xlsx        # every formula cell prints NaN
./v/bin/python -c "import openpyxl;print(openpyxl.load_workbook('hdr.xlsx',data_only=True)['S']['D2'].value)"   # None
# the .eml repro
./v/bin/markitdown multi.eml       # raw MIME, base64 body, base64 attachment
```

## 10. Open questions / blockers

1. **Marker determinism is untested** (no GPU here). Before it is considered, run the docling#701
   protocol against it: N copies of one PDF, concurrent, compare hashes at batch size default vs 1.
2. **Docling determinism with batch size pinned to 1 is reported 12/12 identical but only at n=12**,
   from a user, on one corpus. Re-run on *your* corpus before relying on it; and note a pinned batch
   size changes throughput by an unmeasured factor.
3. **AGPL clearance for PyMuPDF** is a legal decision, not a technical one, and it gates the fastest
   PDF path. If denied, the tier-1 default becomes Docling-with-pypdfium (2.45 p/s per its own report)
   — still workable, ~2× slower than measured PyMuPDF4LLM here.
4. **Cross-version byte stability is assumed, never tested**: I measured stability *within* one version
   of each tool. A `pip install -U` in six months will rewrite files. §2.3's `converter_version` in the
   cache key is the mitigation, but the re-render cost at corpus scale is unmeasured.
5. **No Excel-written workbook was available to test**, so the claim "files last saved by Excel carry
   cached values and therefore look fine" is [reasoning] from the openpyxl docs, not [tested]. It is the
   reason the §4.1 bug is *silent*, so it is worth confirming with one real `.xlsx` from the tenant.
6. **Teams has no converter anywhere in this field** — every option requires project-local code against
   Graph `chatMessage` or the export bundle. That is a build item, not a selection.
