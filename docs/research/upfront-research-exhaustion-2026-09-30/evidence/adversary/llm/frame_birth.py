"""First appearance date of each completeness 'frame' phrase in genuine human prompts (all transcripts)."""
import json, re, glob, os
P = {"100th percentile": r"100th", "100.00/100.00": r"100\.00\s*/\s*100\.00", "absolute perfection": r"absolute perfection",
     "exhaustive/exhausted": r"exhaust", "covering": r"\bcovering\b", "deployed and live": r"deployed and live",
     "nothing can beat it": r"nothing (else )?can beat|can'?t be beaten", "no take-backs": r"take[- ]?backs?",
     "one-and-done": r"one[- ]and[- ]done", "end-game": r"end[- ]?game", "no redo": r"no[- ]redo", "once and for all": r"once and for all",
     "ceiling to push": r"ceiling to push|still have a ceiling", "left on the table": r"left on the table", "optimum/optimal": r"\boptim(um|al)\b"}
first = {}; count = {k: 0 for k in P}
for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')):
    with open(f, 'rb') as fh:
        for line in fh:
            if b'"type":"user"' not in line: continue
            try: r = json.loads(line)
            except Exception: continue
            if r.get('type') != 'user' or r.get('isMeta'): continue
            c = (r.get('message') or {}).get('content')
            if not isinstance(c, str) or c.lstrip().startswith('<') or 'Workflow harness' in c or len(c) > 3000: continue
            ts = r.get('timestamp', '')[:10]
            for k, p in P.items():
                if re.search(p, c, re.I):
                    count[k] += 1
                    if k not in first or ts < first[k]: first[k] = ts
for k in sorted(first, key=first.get): print("%-22s first %s  prompts %d" % (k, first[k], count[k]))
