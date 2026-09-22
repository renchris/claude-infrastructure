judge rows 168 · parse failures 0 · ground truth 36
index rows 54 · quota-fault rows set aside 0 · cells kept 54 · paired briefs (every arm measured) ['cp-01', 'cp-02', 'cp-04', 'cp-05', 'cp-06', 'cp-08', 'cp-09']

Recall, strict majority (>=2 of 3 judges). `—` = unmeasured (quota fault, never scored 0).

| brief | GT | o55@low | o55@medium | o55@high | o55@xhigh | o55@max | o5@high | o5@max | f51@high |
|---|---|---|---|---|---|---|---|---|---|
| cp-01 | 6 | 4 | 4 | 5 | 5 | 5 | 3 | 5 | 4 |
| cp-02 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| cp-04 | 6 | 2 | 2 | 2 | 2 | 3 | 2 | 3 | 3 |
| cp-05 | 4 | 0 | 1 | 0 | 1 | 0 | 1 | 1 | 1 |
| cp-06 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| cp-08 | 5 | 0 | 1 | 0 | 2 | 1 | 2 | 2 | 1 |
| cp-09 | 5 | 0 | 0 | 1 | 0 | 0 | 0 | 2 | 1 |
| **TOTAL (measured)** | 36 | **6**/36 | **8**/36 | **8**/36 | **10**/36 | **9**/36 | **8**/36 | **13**/36 | **10**/36 |
| **PAIRED** | 36 | **6**/36 | **8**/36 | **8**/36 | **10**/36 | **9**/36 | **8**/36 | **13**/36 | **10**/36 |

| threshold (paired briefs) | o55@low | o55@medium | o55@high | o55@xhigh | o55@max | o5@high | o5@max | f51@high |
|---|---|---|---|---|---|---|---|---|
| >=1 judge | 6 | 8 | 9 | 11 | 9 | 9 | 13 | 11 |
| >=2 of 3 | 6 | 8 | 8 | 10 | 9 | 8 | 13 | 10 |
| unanimous | 6 | 8 | 8 | 9 | 9 | 7 | 13 | 10 |

| arm | cells measured | arm failures | median output tokens | max output tokens | cells continued past the cap | continuations | cost USD (all measured cells) |
|---|---|---|---|---|---|---|---|
| o55@low | 9 | 0 | 2578 | 3117 | 0 | 0 | 1.60 |
| o55@medium | 9 | 0 | 6310 | 18823 | 0 | 0 | 2.96 |
| o55@high | 9 | 0 | 14487 | 29687 | 0 | 0 | 4.18 |
| o55@xhigh | 9 | 0 | 36528 | 89248 | 0 | 0 | 9.10 |
| o55@max | 9 | 2 (cp-06, cp-09) | 105619 | 502897 | 1 | 3 | 46.18 |
| o5@high | 9 | 0 | 43040 | 69268 | 0 | 0 | 10.62 |

Quota faults: 0 rows, 0.00 USD spent for no output.
