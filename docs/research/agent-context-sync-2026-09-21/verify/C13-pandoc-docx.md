# C13 — pandoc 3.11 on .docx: determinism and table fidelity (measured 2026-09-22)

**Verdict.** pandoc 3.11 (`brew install pandoc`, macOS 15.7.9) is byte-deterministic across two runs on the same .docx and keeps the table header row as `<thead>`. One fidelity fact the design row did not carry: a **merged cell makes pandoc emit the whole table as an HTML `<table>` with `colspan`**, because a GFM pipe table cannot express spans — still greppable text, but not a pipe table; a table without merges is emitted as a pipe table. The recommended `.docx` converter had not been run in the wave (E-converters cited its docs; pandoc was not installed here until today); this closes that gap.

## Fixture
`a.docx` (python-docx): H1, paragraph, 3×3 "Table Grid" table with the first two cells of row 2 merged, H2, paragraph. `plain.docx`: same without the merge.

## Runs
`pandoc -f docx -t gfm --extract-media=<dir> a.docx -o rN.md`, twice, 2 s apart.

| file | run 1 sha256[:16] | run 2 | identical |
|---|---|---|---|
| a.docx (merged cell) | 71e1761eb774433a | 71e1761eb774433a | yes |
| plain.docx | — | — | yes (`cmp`) |

## Output shape
- a.docx → `# Scope` … `<table><colgroup>…<thead><tr><th>Region</th><th>Spend</th><th>Total</th></tr></thead><tbody><tr><td colspan="2">West (merged)</td><td>300</td></tr>…` … `## Notes`
- plain.docx → a GFM pipe table with the header row intact (`| Region | Spend | Total |`).

## Implication for §4.4
Keep pandoc for `.docx`. Expect HTML tables wherever a source has merged cells (common in corporate templates); the mirror stays greppable, and a curated page cites it the same way. If pipe tables are required, post-process `<table>` blocks or route merged-cell documents to Docling (which carries row/col spans as metadata).
