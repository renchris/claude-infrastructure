# Mistral OCR API as an agent-run step for vendor-PDF ingestion: evaluation

2026-09-22 · measured on the Claude Opus 5.5 system card (`/tmp/opus55-src/syscard.pdf`, 230 pages, 17,795,106 bytes, Google Docs → Skia PDF)

**The question:** should an agent call Mistral's OCR API during model upgrades, replacing the operator's manual Mistral web-UI run?

## Answer

1. **Born-digital PDFs (like this card): no.** Neither the Mistral API nor the web UI should be used. The local pipeline replaces the manual step: `pdftotext -layout` + `pdfimages -png -p` + Claude vision on the native figures. The text is exact, figures come at native resolution, it costs $0, and a full run takes about 30 s. **Conviction 90%.**
2. **Scanned or image-only pages: detect them per page and send only those pages to the Mistral OCR API** (`mistral-ocr-latest` = OCR 4.1, $4 per 1,000 pages). Use page-level confidence as the review gate, with Claude vision as the fallback. **Conviction 65%**: this branch rests on documentation and indirect evidence, because the API arm could not be run.
3. **The API arm was not run.** The single OCR call got HTTP 429 with `x-ratelimit-limit-req-minute: 0`: this key's workspace allows zero OCR requests per minute. **0 pages were processed, so the test cost $0.00.** Comparisons (a), (b) and (c) below are measured for the native source and the web-UI export; the API column is UNMEASURED. Unblocking it is the operator's plan or billing decision (§2). After that, `bash /tmp/opus55-src/local/mistral-api-rerun.sh` re-runs the test: 1 call, 2 pages, about $0.008.

## 1. What Mistral's own docs say (all fetched 2026-09-22; raw bytes kept in `/tmp/opus55-src/local/mistral-docs/`)

| Fact | Value | Source |
|---|---|---|
| Endpoint | `POST https://api.mistral.ai/v1/ocr` | https://docs.mistral.ai/api/endpoint/ocr |
| Current model | **OCR 4.1**, dated July 16, 2026. Names: `mistral-ocr-4-1`, `mistral-ocr-4`, `mistral-ocr-latest` | https://docs.mistral.ai/models/ocr-4-1 |
| Previous models | OCR 4.0 `mistral-ocr-4-0` (June 23, 2026). OCR 3 `mistral-ocr-2512` = `mistral-ocr-3-0` = `mistral-ocr-3` | https://docs.mistral.ai/models/ocr-4-0, and a live `GET /v1/models` with this key (HTTP 200), which confirms `mistral-ocr-latest` has aliases `mistral-ocr-4` and `mistral-ocr-4-1` |
| Sending a PDF | "pass a publicly available URL, pass a Base64-encoded PDF, or upload a PDF file". Schema: `document` = `DocumentURLChunk` \| `FileChunk` (`file_id`) \| `ImageURLChunk` | https://docs.mistral.ai/studio/document-processing/basic_ocr ; API reference above |
| Page selection | `pages`: "a list of integers or a string of comma-separated numbers and ranges (e.g. '0,1,2' or '0-5' or '0,2-4'). **Page numbers start from 0.**" | API reference |
| Image options | `include_image_base64` ("Include image URLs in response"), `image_limit` ("Max images to extract"), `image_min_size` ("Minimum height and width of image to extract"). **The request schema has no resolution, DPI or native-image parameter.** | API reference |
| Image resolution | Page `dimensions` = "**The dimensions of the PDF Page's screenshot image**"; `dpi` = "Dots per inch of the page-image". Image boxes are corner coordinates on that screenshot. The reference example renders a US Letter page at dpi 200 (1700×2200). Returned images are `data:image/jpeg;base64,…`. So images are **crops of a page render, not the embedded originals** (inferred from the docs, and proven for the web UI in §3a) | API reference ; https://docs.mistral.ai/studio/document-processing/annotations |
| Other parameters | `table_format` null (inline) \| `markdown` \| `html` (OCR 2512 or newer); `extract_header`/`extract_footer`; `include_blocks` (OCR 4 or newer; the API reference says default true, the guide says set it to True, so the docs disagree); `confidence_scores_granularity` `page`\|`block`\|`word` | basic_ocr guide + API reference |
| Chart → structured data | `bbox_annotation_format`: "After regular OCR is finished; we call a Vision capable LLM for all bboxes individually". Listed use: "**Conversion of charts to tables**". It annotates the *extracted* image crops. `document_annotation_format` sends the OCR markdown plus "the first eight extracted image bounding boxes" to a vision LLM, with a limit of "a maximum of 8 image bounding boxes". Per the OCR 4 blog, the schema step runs on `mistral-small-2603`, and image annotation triggers "an additional vision-language model call per image" | annotations page ; https://mistral.ai/news/ocr-4/ |
| Price | "OCR 4.1 … OCR **$4 / 1000 pages** · Document AI **$5 / 1000 pages**". The model card says "$5 /1000 Annotated Pages". Batch API is 50% off, "reducing the cost to $2 per 1,000 pages" | https://mistral.ai/pricing/api/ ; model card ; https://mistral.ai/news/ocr-4/ |
| Size and page limits | "Uploaded document files must be **50 MB or less** and contain **1,000 pages or fewer**." This card (17.8 MB, 230 pages) fits | basic_ocr guide, FAQ (the annotations FAQ repeats it) |
| Rate limits | "set at the workspace level … defined by usage tier". Included monthly usage is shared across Studio, API and Vibe; when it runs out and pay-as-you-go is off, "usage can stop until the next billing period or until an admin changes the settings". The Free plan includes "$10 /mo in API credits" | https://docs.mistral.ai/llms-full.txt (section "Rate limit and usage tiers"; its own source URL now returns 404, so it may be stale) ; https://docs.mistral.ai/admin/billing-usage/subscriptions ; https://mistral.ai/pricing/ |

## 2. The API test: refused, and why the second attempt was not spent

- **Request** (`mistral-api-test.request.json`): `mistral-ocr-latest`; `document_url` = the Anthropic CDN URL, whose ETag `527d6fee000d18e49d2e8bbc3d48f62c` equals the local file's MD5, so the bytes are identical; `pages: [173, 175]` (pages 174 and 176 in 1-based numbering); `include_image_base64`, `include_blocks`, `confidence_scores_granularity: "page"`.
- **Response** (`mistral-api-test.json`, raw): `{"object":"error","message":"Rate limit exceeded","type":"rate_limited","param":null,"code":"1300","raw_status_code":429}`. Headers: **`x-ratelimit-limit-req-minute: 0`**, `x-ratelimit-remaining-req-minute: 0`, upstream time 20 ms, total 0.25 s, correlation id `01a0cad9-a280-7841-b9e0-e5e65b071d17`.
- **Diagnosis.** The *limit* is 0, not used up, so backing off cannot clear it. The key itself authenticates (`GET /v1/models` returns 200). The read-only `GET /v1/admin/rate-limit` and `GET /v1/admin/spend-limit` both returned 401 "Invalid API Key" because they require an `AdminApiKey`, so the per-model limit table cannot be read with this key. This refusal is a fact about **this key's workspace**, not about the product: the operator's web-UI export shows the service processing this exact document. Likely causes, per the docs above: included credits exhausted with pay-as-you-go off, or the plan's tier. Unverified.
- **Why only one call.** The brief allows one *fix*. No fix exists within an agent's authority. Retrying a limit of 0 re-measures the same zero, and switching to a sibling model id (`mistral-ocr-4-0`) to dodge it would be working around a refusal, which the brief's stop clause rules out. **Calls used: 1 of 2. Pages processed: 0 of 5. Cost: $0.00.**
- **To unblock (operator, money path):** open the workspace limits page (https://admin.mistral.ai/plateforme/limits, per the stale doc above) or Admin Panel › Subscription (https://admin.mistral.ai/subscription), find why OCR is at 0 req/min, and decide on pay-as-you-go. Then run `bash /tmp/opus55-src/local/mistral-api-rerun.sh`. Its post-processing was verified on a mock response built from the web-UI export (613×359, 50/50, $0.008).

## 3. Comparisons

| | Native / `pdftotext` | Web-UI export (operator) | Mistral API (this test) |
|---|---|---|---|
| **(a) p176 chart, pixels** | **2000×1300** (`pdfimages`; placed at 308 ppi) | **613×359**: 8.5% of native pixels, 30.7% of native linear resolution | UNMEASURED (429). Projected ~1318×772 *if* it renders at the documented 200-dpi example |
| **(b) p174 table vs `pdftotext -layout`** | ground truth: 50 numeric cells | **50/50 cells exact and in order**, but see the defects below | UNMEASURED (429) |
| **(c) latency** | text for all 230 pages 0.56 s; 111 figures 28.6 s | manual (operator time) | refusal round-trip 0.25 s; OCR latency UNMEASURED |
| **(c) cost** | $0 | inside the plan's credits (not visible) | **test $0.00 (0 pages)**; the planned 2 pages would have been $0.008; the full card is $0.92 ($0.46 via batch, $1.15 with annotations) |

**(a) Why the web-UI image is small (measured).** The export records each page as a screenshot at **93 dpi, 791×1023**, which is exactly US Letter at 93 dpi. The chart's box is (90,438)–(703,797), so the crop is 703−90 = **613** by 797−438 = **359**, exactly the JPEG's size. The chart's own title ("FrontierCode Main", drawn inside the embedded PNG) was split off into a text `caption` block and cropped out of the image. The API documents the same screenshot mechanism and offers no parameter to get the embedded original.

**(b) Web-UI table defects** that `pdftotext -layout` does not have:
- The source's 3 en-dash placeholders plus 2 hyphens all became 5 ASCII hyphens.
- Both curly apostrophes were straightened.
- The group header "Other models" moved one column left, over *Claude Fable 5.1* instead of *GPT-6 Astra*, so it labels a Claude model as an "other" model. `pdftotext -layout` places it correctly.
- The lead's earlier measurement also found 15 LaTeX-wrapped fragments (for example `\(33\%\)`).

**Figure legibility for Claude vision** (my read of both images; not blind, since I had read the page text first). Both are legible for the qualitative picture: 6 series, effort labels, axes. The chart has **no data labels**, so values must be read from position. Measured gridline spacing: native **42.6 px per percentage point** (213 px per 5-point gridline), crop **12.9 px** (64.5 px per gridline, a 0.30 ratio). The page text's values (54.6, 54.4, 53.4, 53.5, 53.3, 52.8) sit where the text says in both images.

## 4. Local pipeline (measured)

- `pdftotext -layout`: 230 pages in 0.56 s (456,835 bytes), exact by construction.
- `pdfimages -png -p`: 111 native figures in 28.6 s (16 MB). Page 176 comes out at 2000×1300.
- All 85 pages carrying a `[Figure …]` label have at least one raster image. The only page with more labels than images (197) holds an in-text reference, not a vector figure. So `pdfimages` covers every figure in *this* card. **Residual:** a vendor PDF with vector charts would get no image from `pdfimages`. Render those regions with `pdftoppm -r 300` instead, which is still sharper than a 93- or 200-dpi screenshot crop.

## 5. Detecting a scanned or image-only PDF automatically (measured)

Census of this card, per page with `pdffonts`, `pdftotext` and `pdfimages`:
- **230/230 pages carry at least 2 embedded fonts**, so 0 pages are flagged.
- Text volume alone would misfire: page 106 has **3** non-whitespace characters (a figure page with 4 images) and page 1 has 54. The 5th percentile is 332 and the median 1,450.

Positive controls, built from page 174 rasterised at 300 dpi:

| Control | `pdffonts` | `pdftotext` characters | `pdfimages` |
|---|---|---|---|
| Original page 174 | 4 embedded fonts (Lora, Poppins) | text present | 0 images |
| Image-only PDF (`localpipe/scan174-imageonly.pdf`) | **0 fonts** | **0** | one 2550×3300 image at 300 ppi |
| Tesseract "searchable" PDF (`localpipe/scan174-tess.pdf`) | **1 font, `GlyphLessFont`** | 1,062 | one full-page 300 ppi image |

A font-count rule alone passes the searchable scan as born-digital. **Per-page rule:** a page is SCANNED if any of these holds:
1. `pdffonts` lists **0 fonts**;
2. **every** font is `GlyphLessFont`, meaning an invisible OCR layer someone else made;
3. `pdftotext` gives fewer than 50 non-whitespace characters **and** `pdfimages -list` shows a single image of at least 150 ppi spanning the page.

Otherwise the page is born-digital. Route SCANNED pages to OCR and the rest to the local pipeline.

On this card the full rule flags **0/230 pages**. Only page 106 falls under 50 characters, and none of its 4 images spans the page: each is 6.49 in wide and at most 2.67 in tall on an 8.5×11 in page. The image-only control trips clause 1; the searchable control trips clause 2.

**Tesseract 5.5.3 on the idealised 300-dpi scan:** 49/50 cells, with **one silent digit substitution: 55.8 → 59.8** (Fable 5.1, Terminal-Bench 4.0). It took 1.15 s per page and produces no table structure. That rules it out for number-dense vendor cards.

## 6. Recommendations

**R1: born-digital vendor PDFs use the local pipeline, and Mistral is removed from this step (API and web UI). 90%.**
- The text layer is exact, so OCR can only equal it or degrade it. The degradations are measured: LaTeX wraps, dash and quote normalisation, a header shifted one column.
- Native figures carry 3.3× the linear resolution of the web-UI crops, and the API documents no way to get the originals.
- $0, about 30 s for the whole card, and no key dependency (the key is refused today).
- *What would move this:*
  - The unrun API arm could return native-resolution images and cleaner table structure than `pdftotext -layout`. It still could not beat the text layer, so that would only argue for the API on table-heavy documents.
  - Multi-column vendor layouts where `-layout` reading order fails. Not the case in this document.

**R2: scanned or image-only pages go to the §5 per-page detector, then to the Mistral OCR API (`mistral-ocr-latest`) for flagged pages only, with page confidence as the review gate and Claude vision as the fallback. 65%.**
- *Why Mistral:*
  - It is a purpose-built OCR model that returns markdown tables, blocks and confidence scores.
  - It is cheap: $0.004 per page, $0.92 for 230 pages.
  - Indirect evidence: the operator's run of Mistral's web UI got 50/50 cells on page 174 from what its metadata records as a 93-dpi page render. Whether it also read the text layer is unknown.
  - Tesseract made a silent numeric error even on a clean synthetic scan.
- *Why only 65%:*
  - The API arm is unmeasured.
  - Mistral's benchmark claims (OlmOCRBench 85.20, a 72% human-preference win rate) are vendor-reported.
  - Claude vision on page renders (no second vendor or key; billed in quota, not dollars) was not blind-tested here, because this context had already seen the ground truth.
  - Vendor model PDFs are rarely scanned, so this branch may almost never fire.
- *Cheapest refutation:* run the same page-174 fixture (`localpipe/scan174-imageonly.pdf`, exact ground truth in `localpipe/truth174.txt`) through the API, once unblocked, and through a blind Claude-vision subagent. The one with 50/50 cells and correct table structure wins.
- *Conviction in the detector itself: 85%.* It was measured on 230 born-digital pages plus 2 positive controls. It is untested on real skewed or noisy scans, and on text converted to vector outlines, which has 0 fonts and would be flagged: the right action, since that text is not extractable anyway.

## 7. Artifacts (`/tmp/opus55-src/local/`)

- **API test:**
  - `mistral-api-test.json`: raw response (the 429 body)
  - `mistral-api-test.request.json`
  - `mistral-api-test.headers.txt`
  - `mistral-api-test.timing.txt`
  - `mistral-api-rerun.sh`: one call, 2 pages; not run
- **Docs:** `mistral-docs/`: raw HTML plus text extractions of every cited page, and `v1-models.json`.
- **Local pipeline (`localpipe/`):**
  - `page-census.json`
  - `truth174.txt`
  - `scan174-174.png`, `scan174-imageonly.pdf`, `scan174-tess.pdf`, `scan174-tess.txt`
  - `mock-response.json`
- **Leftover:** `localpipe/figs-timing/` (16 MB) duplicates `/tmp/opus55-src/figs/`. My `rm -rf` of it was denied by the permission guard; delete it at will.
