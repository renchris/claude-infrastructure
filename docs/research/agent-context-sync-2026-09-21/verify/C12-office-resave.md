# C12 — Office and LibreOffice no-op re-save: are OOXML parts byte-stable? (attempted 2026-09-22)

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
