
### P1 — recall /36 per sample, strict majority

| arm | s1 | s2 | s3 | mean | items found in >=2 of 3 | in >=1 of 3 | in 3 of 3 |
|---|---|---|---|---|---|---|---|
| o55@high | 8 | 9 | 11 | 9.3 | **9** | 12 | 7 |
| o55@xhigh | 10 | 15 | 13 | 12.7 | **12** | 17 | 9 |
| o5@high | 8 | 8 | 8 | 8.0 | **8** | 12 | 4 |
| o5@max | 13 | 11 | 11 | 11.7 | **12** | 16 | 7 |
| f51@high | 10 | 8 | 9 | 9.0 | **10** | 12 | 5 |

### P2 — recall /36 per sample, strict majority

| arm | s1 | s2 | s3 | mean | items found in >=2 of 3 | in >=1 of 3 | in 3 of 3 |
|---|---|---|---|---|---|---|---|
| o55@high | 8 | 8 | 10 | 8.7 | **8** | 11 | 7 |
| o55@xhigh | 9 | 14 | 13 | 12.0 | **11** | 17 | 8 |
| o5@high | 7 | 7 | 8 | 7.3 | **8** | 10 | 4 |
| o5@max | 12 | 10 | 9 | 10.3 | **11** | 14 | 6 |
| f51@high | 10 | 8 | 9 | 9.0 | **10** | 12 | 5 |

### Q1 — paired sign tests (item = found in >=2 of 3 samples)

| panel | A vs B | A items | B items | A only | B only | p (items) | cells A only / B only (x3 samples) | p (cells, NOT independent) |
|---|---|---|---|---|---|---|---|---|
| P1 | o5@max vs o55@xhigh | 12 | 12 | 1 | 1 | **1.00** | 6 / 9 | 0.607 |
| P1 | o5@max vs f51@high | 12 | 10 | 4 | 2 | **0.69** | 12 / 4 | 0.077 |
| P1 | o55@xhigh vs f51@high | 12 | 10 | 4 | 2 | **0.69** | 16 / 5 | 0.027 |
| P1 | o5@max vs o5@high | 12 | 8 | 4 | 0 | **0.12** | 13 / 2 | 0.007 |
| P1 | o55@xhigh vs o55@high | 12 | 9 | 3 | 0 | **0.25** | 12 / 2 | 0.013 |
| P2 | o5@max vs o55@xhigh | 11 | 11 | 1 | 1 | **1.00** | 6 / 11 | 0.332 |
| P2 | o5@max vs f51@high | 11 | 10 | 3 | 2 | **1.00** | 8 / 4 | 0.388 |
| P2 | o55@xhigh vs f51@high | 11 | 10 | 3 | 2 | **1.00** | 14 / 5 | 0.064 |
| P2 | o5@max vs o5@high | 11 | 8 | 3 | 0 | **0.25** | 12 / 3 | 0.035 |
| P2 | o55@xhigh vs o55@high | 11 | 8 | 3 | 0 | **0.25** | 12 / 2 | 0.013 |

### Q2 — complement to o55@high

| panel | X | pooled: mean X-only over 9 sample pairings | pooled: mean union | item-level (>=2/3) X-only | item-level union | O alone (item-level) |
|---|---|---|---|---|---|---|
| P1 | f51@high | 2.44 (range 1–3) | 11.78 | 4 | 13 | 9 |
| P1 | o5@high | 1.67 (range 0–3) | 11.00 | 2 | 11 | 9 |
| P1 | o55@xhigh | 4.11 (range 1–7) | 13.44 | 3 | 12 | 9 |
| P1 | o5@max | 3.67 (range 1–7) | 13.00 | 3 | 12 | 9 |
| P2 | f51@high | 2.44 (range 1–3) | 11.11 | 4 | 12 | 8 |
| P2 | o5@high | 1.33 (range 0–2) | 10.00 | 2 | 10 | 8 |
| P2 | o55@xhigh | 4.00 (range 1–6) | 12.67 | 3 | 11 | 8 |
| P2 | o5@max | 3.22 (range 1–6) | 11.89 | 3 | 11 | 8 |

**Head-to-head, f51@high vs o5@high as complements.** Per item, the number of the 9 sample pairings in which
X found it and o55@high missed it; items where f51 scores higher vs lower, exact sign test.

| panel | items f51 > o5 | items f51 < o5 | p | complement items, f51 only (item-level) | o5 only (item-level) | p (item-level) |
|---|---|---|---|---|---|---|
| P1 | 2 | 2 | 1.00 | 2 | 0 | 0.50 |
|  | f51 complement items: ['cp-02#4', 'cp-04#6', 'cp-08#3', 'cp-09#2'] · o5@high: ['cp-04#6', 'cp-08#3'] | | | | | |
| P2 | 2 | 0 | 0.50 | 2 | 0 | 0.50 |
|  | f51 complement items: ['cp-02#4', 'cp-04#6', 'cp-08#3', 'cp-09#2'] · o5@high: ['cp-04#6', 'cp-08#3'] | | | | | |

### Per item — samples (of 3) in which each arm found it, P1 / P2

| item | o55@high | o55@xhigh | o5@high | o5@max | f51@high |
|---|---|---|---|---|---|
| cp-01#1 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-01#2 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-01#3 | 3 / 3 | 3 / 3 | 1 / 1 | 3 / 3 | 1 / 1 |
| cp-01#4 | 0 / 0 | 1 / 1 | 0 / 0 | 2 / 2 | 0 / 0 |
| cp-01#5 | 3 / 3 | 3 / 3 | 2 / 2 | 2 / 2 | 3 / 3 |
| cp-01#6 | 3 / 3 | 2 / 2 | 1 / 1 | 3 / 2 | 1 / 1 |
| cp-02#4 | 0 / 0 | 0 / 0 | 0 / 0 | 1 / 1 | 2 / 2 |
| cp-04#4 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-04#5 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 | 3 / 3 |
| cp-04#6 | 0 / 0 | 2 / 2 | 2 / 2 | 2 / 2 | 2 / 2 |
| cp-05#3 | 2 / 2 | 3 / 3 | 2 / 2 | 2 / 2 | 2 / 2 |
| cp-05#4 | 2 / 0 | 2 / 1 | 1 / 0 | 2 / 0 | 0 / 0 |
| cp-08#1 | 0 / 0 | 1 / 1 | 0 / 0 | 0 / 0 | 0 / 0 |
| cp-08#2 | 1 / 1 | 3 / 2 | 1 / 0 | 1 / 0 | 0 / 0 |
| cp-08#3 | 1 / 1 | 3 / 3 | 2 / 2 | 3 / 3 | 2 / 2 |
| cp-08#4 | 0 / 0 | 1 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| cp-09#2 | 1 / 1 | 1 / 1 | 0 / 0 | 0 / 0 | 2 / 2 |
| cp-09#3 | 0 / 0 | 1 / 1 | 0 / 0 | 1 / 1 | 0 / 0 |
| cp-09#5 | 0 / 0 | 0 / 1 | 0 / 0 | 1 / 1 | 0 / 0 |

Found by no arm in any sample under either panel (17): cp-02#1, cp-02#2, cp-02#3, cp-04#1, cp-04#2, cp-04#3, cp-05#1, cp-05#2, cp-06#1, cp-06#2, cp-06#3, cp-06#4, cp-06#5, cp-06#6, cp-08#5, cp-09#1, cp-09#4

### P2 — each judge's recall per arm, summed over 3 samples (/108)

| judge | o55@high | o55@xhigh | o5@high | o5@max | f51@high | total |
|---|---|---|---|---|---|---|
| o5 | 27 | 38 | 24 | 34 | 27 | 150 |
| o55 | 26 | 36 | 22 | 31 | 27 | 142 |
| f51 | 26 | 35 | 22 | 31 | 27 | 141 |

**Own-model lean test.** A judge's SOLO credit = it credits a cell neither other judge credits; SOLO miss =
both others credit and it does not. Own-family arms vs the rest, Fisher exact on solo credit vs solo miss.

| judge | own arms: solo credit / solo miss | other arms: solo credit / solo miss | p |
|---|---|---|---|
| o5 | 5 / 0 | 3 / 0 | 1.00 |
| o55 | 0 / 0 | 0 / 0 | 1.00 |
| f51 | 0 / 0 | 0 / 1 | 1.00 |

P1 vs P2 majority verdicts agree on 351/360 (arm, sample, item) cells, samples 2-3.

### Tokens and quota per arm

Per 7-brief sample, mean over the samples that carry token counts. W-pp = weekly plan points at the
Opus-5 margin (1 W-pp ~ 360K output or 3.4M cache_creation), x the model's per-token draw (Opus 5.5 1.1
[0.78-1.72], Fable 5.1 3.2-3.7; 09-22 and 09-16 records). [$list] shown for reference only.

| arm | samples with tokens | median out / cell | out / sample | cache_create / sample | est W-pp / sample [range] | vs o55@high | cells failed (no review) | [$list] / sample |
|---|---|---|---|---|---|---|---|---|
| o55@high | 3 | 17,404 | 137,465 | 127,502 | 0.46 [0.33–0.72] | 1.0x | 0 | 3.77 |
| o55@xhigh | 3 | 44,303 | 354,160 | 127,502 | 1.12 [0.80–1.76] | 2.4x | 0 | 8.10 |
| o5@high | 3 | 45,922 | 335,942 | 134,500 | 0.97 [0.97–0.97] | 2.1x | 0 | 9.75 |
| o5@max | 2 | 71,090 | 477,646 | 134,503 | 1.37 [1.37–1.37] | 3.0x | 0 | 13.29 |
| f51@high | 3 | 29,065 | 233,573 | 150,943 | 2.39 [2.22–2.56] | 5.2x | 0 | 14.73 |
