# C12 — Office and LibreOffice no-op re-save: are OOXML parts byte-stable? (attempted 2026-09-22)

> **Corrected 2026-09-23 — see §5.** The blocker is not the GUI, it is the LICENCE: Office on this Mac runs unactivated ("View Only — Activate Microsoft 365 to Create and Edit"), so no save can happen by any route, scripted or by hand. The -50 / -1708 / -1712 errors below are that gate seen from AppleScript. The original verdict is kept as written.

**Verdict.** The Microsoft Office arm is GUI-gated: scripted Excel, Word and PowerPoint (AppleScript via `osascript`, files staged inside each app's own sandbox container so no "Grant File Access" dialog should apply) never completed a save in an unattended session. The LibreOffice arm ran: a headless no-op round-trip changed three **content** parts (`xl/styles.xml`, `xl/worksheets/sheet1.xml`, `xl/worksheets/sheet2.xml`), so a per-part rollup excluding `docProps/*` is NOT stable across writers, and only the converter-output hash (H2) makes a no-op save free.

## 1. Inputs

`a.xlsx` (openpyxl 3.1.5: two sheets, one formula column), `a.docx` (python-docx), `a.pptx` (python-pptx), copied into `~/Library/Containers/com.microsoft.{Excel,Word,Powerpoint}/Data/agentsync/`. None of the three apps was running before the probe; every instance the probe launched was quit or killed afterwards.

## 2. Office attempts and their errors

| app | form | result |
|---|---|---|
| Excel | `open workbook workbook file name <POSIX>` then `save workbook as wb filename <POSIX> file format Excel XML file format` | `Parameter error. (-50)` |
| Excel | same without `file format`, POSIX path | `Parameter error. (-50)` |
| Excel | same with HFS path | `Parameter error. (-50)` |
| Excel (inside container) | `open workbook …`, `set value of range "A1" of active sheet to "Region"`, `save active workbook` | `Parameter error. (-50)`, twice |
| Word | `open <POSIX>`, `save as active document file name <POSIX>` | `AppleEvent timed out. (-1712)` |
| Word (inside container) | `open`, `save active document` | `active document doesn't understand the "save" message. (-1708)` |
| PowerPoint (both locations) | `open`, `save active presentation in <path>` | `AppleEvent timed out. (-1712)` |

No consent error (`-1743`) appeared, so scripting permission is not the blocker. The `-1712` timeouts are consistent with a modal the apps put up on launch; an unattended session cannot answer it and must not send synthetic input to a shared screen. The operator's arm of §9 probe 6 is therefore one manual Save per app on a real tenant file, then the comparator in §4.

## 3. LibreOffice headless round-trip (ran)

```
soffice --headless --convert-to xlsx --outdir r1 a.xlsx
soffice --headless --convert-to xlsx --outdir r2 r1/a.xlsx
```

r1/a.xlsx vs r2/a.xlsx (LibreOffice → LibreOffice, no edits): whole-file sha256 `24d2a21e12e6…` vs `43b212b2cc97…` (differ); 12 parts; content-differing parts `['xl/styles.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml']`; zip-timestamp-differing entries 12; rollup excluding `docProps/*` **not** equal.

## 4. Comparator

```python
import zipfile,hashlib,os
def parts(p):
    z=zipfile.ZipFile(p); return {i.filename:(hashlib.sha256(z.read(i)).hexdigest(), i.date_time) for i in z.infolist()}
def cmp(b,c):
    pb,pc=parts(b),parts(c); names=sorted(set(pb)|set(pc))
    diff=[n for n in names if pb.get(n,("",))[0]!=pc.get(n,("",))[0]]
    ex=lambda n: n.startswith("docProps/")
    rb=hashlib.sha256("".join(f"{n}:{pb[n][0]}" for n in sorted(pb) if not ex(n)).encode()).hexdigest()
    rc=hashlib.sha256("".join(f"{n}:{pc[n][0]}" for n in sorted(pc) if not ex(n)).encode()).hexdigest()
    return diff, rb==rc
```

## 5. Microsoft Office arm — operator-driven attempt, and the real blocker (2026-09-23)

**Result: not measurable on this machine. Office is unactivated, so it cannot save.** Two operator-driven runs of `agentsync-office-resave.sh` (durable copy `~/.claude/autonomy/briefs/agentsync-office-resave.sh`) captured no save in any app: every round timed out with the target file's mtime and inode unchanged and no new file anywhere a Save As could land.

What pinned the cause, all read live on the second run with `a.xlsx` open in Excel after the operator's edit:

| instrument | reading |
|---|---|
| Excel AppleScript `saved of active workbook` / `read only` | `false` / `false` — modified, and not opened read-only |
| System Events, Excel `File` menu | `Save` **disabled**, `Save As…` **disabled**, `Save as Template…` disabled; `New`/`Open` enabled |
| same, after `activate` brought the window on-screen (it had been maximized on another Space, so `count of windows` read 0) | `Save` still disabled |
| screenshot of the Excel window | banner under the ribbon: **"View Only — Activate Microsoft 365 to Create and Edit"**, with an `Activate` button |
| `save active workbook` on that modified workbook | `Parameter error. (-50)` — the same error as every row of §2 |
| `save workbook as … file format Excel XML file format` (HFS path) | `Parameter error. (-50)` |

So §2's reading ("scripting cannot drive a save, one manual Save per app will") was wrong in its mechanism: a manual Save is refused too, because the reduced-functionality mode removes Save from every route. §2's `-1712` timeouts are consistent with the activation prompt being the modal on launch (not re-verified per app). On-disk licence state: one file under `~/Library/Group Containers/UBF8T346G9.Office/Licenses/5/`, dated 2025-11-03.

**Two operator-run defects fixed in the script along the way**, recorded because each one alone produces the same "TIMEOUT, no save" reading and would have hidden the licence gate: (a) the terminal tab resolved a `python3` without openpyxl, so the script now pins an interpreter that imports all three libraries; (b) the Excel steps said "press Delete" on a selected cell, which on macOS Excel enters cell-edit mode, where ⌘S is silently disabled — a second, independent route to a disabled Save that the menu read cannot tell apart from the licence gate, which is why the banner is the deciding evidence.

**What this changes in the design doc:** nothing about H1/H2. The LibreOffice arm (§3) already shows H1-on-parts is not stable across writers, so H2 stays load-bearing; the open question is only how narrow H1 is for Office-written files, and answering it needs an activated Office (or someone else's Office-written file pair).

## 6. Microsoft Office arm — MEASURED (2026-09-23, Office activated, fully scripted)

**Result: Office never re-saves a file byte-stably, and H1-on-parts (excluding `docProps/*`) holds only for PowerPoint. Excel and Word each churn one or two content parts with pure save metadata. H2 (the converter-output hash) was identical across the two saves for all three formats — for Word it was also identical to the original python-docx fixture.**

Once the operator activated Office with the tenant's Microsoft 365 Business Standard licence (chris@reso.gl; a new licence file appeared under `Licenses/5/` at 23:00), every save the §2 table recorded as `-50` / `-1708` succeeded by AppleScript. That confirms §5: the gate was the licence, not scripting. Script: `/tmp/agentsync-office-resave-auto.sh` (Office 16.x on macOS; files opened with `open -a`, so no "Grant File Access" prompt). For each format, fixture `a.*` → working copy → Office save (**b**) → Office save again with no net content change (**c**) → compare b vs c. Office wrote both sides.

| format | how round c was made with no net edit | parts | content-differing parts | rollup excl. `docProps/*` | what actually changed | H2 |
|---|---|---|---|---|---|---|
| `.pptx` | set title text to its current value ("Deck"), save | 37 | `docProps/core.xml` | **equal** | modified timestamp only | text of every shape: equal |
| `.xlsx` | set `F10` to its current value (1), save | 12 | `docProps/core.xml`, `xl/workbook.xml` | differs | `xl/workbook.xml`: only `<xr:revisionPtr documentId="13_ncr:1_{GUID}">`, a fresh GUID per save (2 tokens) | openpyxl values + formulas dump: equal |
| `.docx` | `set saved of active document to false`, save (Word skips a clean save, so this is the ⌘S-equivalent) | 15 | `docProps/core.xml`, `word/document.xml`, `word/settings.xml` | differs | `word/document.xml`: `w:rsidRDefault` on paragraphs (12 tokens); `word/settings.xml`: the `<w:rsids>` list gains the new session's revision-save id | `pandoc -f docx -t gfm`: equal, and equal to the fixture |

ZIP entry timestamps did not differ in any format (Office writes a fixed entry time), so the whole-file inequality is all in-part content.

**Two method traps, kept because each produced a false reading first.** (a) A Word "no-op" done as `set content of text object of paragraph 2 to <same text>` replaced the paragraph mark and merged the paragraph into the following table cell — pandoc output differed, correctly, because the content had changed. Only the `saved`-flag re-save is a true no-op. (b) A plain `save active document` / `save active presentation` on a freshly opened clean document writes nothing (mtime unchanged), so a harness keyed on mtime reads that as "the app refused to save".

**Consequences for the design (§4.1 invariant 2, §9 probe 6):**
- The denylist as written (`docProps/*`, `xl/calcChain.xml`, `printerSettings/*`, `docMetadata/LabelInfo.xml`) makes H1 stable for PowerPoint only. For Excel, add attribute-level canonicalization of `xr:revisionPtr/@documentId` in `xl/workbook.xml` (the part cannot be denylisted whole: it carries sheet names and defined names). For Word, strip `w:rsid*` attributes in `word/document.xml` and the `<w:rsids>` element in `word/settings.xml`; this is revision metadata, and removing it is the standard canonicalization. Without those, every Word or Excel ⌘S reaches the converter, where H2 absorbs it.
- H2 is load-bearing, now measured against all three real Office writers as well as LibreOffice. The design's claim that H2, not H1, makes a no-op save free holds.

