# ccwrap.py <out.ans> <msg>... : Claude Code's re-wrap of a systemMessage as the probe captured it
# (fin-live-rows30-stale): each line word-wrapped to the pane's cells (cols - 5), a word wider than a
# row hard-split at the edge, a continuation row unindented; tiles side by side per width.
import sys
out, msgs = sys.argv[1], sys.argv[2:]
def wrap(line, w):
    lead = line[:len(line) - len(line.lstrip(' '))]
    rows, cur = [], lead
    for word in line.split():
        while len(word) > w:                       # hard split
            if cur.strip(): rows.append(cur); cur = ''
            rows.append(word[:w]); word = word[w:]
        if not cur.strip(): cur = cur + word if len(cur + word) <= w else word
        elif len(cur) + 1 + len(word) <= w: cur += ' ' + word
        else: rows.append(cur); cur = word
    rows.append(cur)
    return rows
tiles = []
for spec in msgs:
    path, cols, label = spec.split(':')
    w = int(cols) - 5
    text = open(path).read().strip('\n').split('\n')
    rows = [f'\x1b[1;38;2;121;192;255m{label[:w]}\x1b[0m'] + [r for l in text for r in (wrap(l, w) if l else [''])]
    tiles.append((w, rows))
H = max(len(r) for _, r in tiles)
vis = lambda s: len(s.replace('\x1b[1;38;2;121;192;255m', '').replace('\x1b[0m', ''))
with open(out, 'w') as f:
    for y in range(H):
        f.write(' '.join((r[y] if y < len(r) else '') + ' ' * (w - vis(r[y] if y < len(r) else '')) + '\x1b[38;2;248;81;73m│\x1b[0m' for w, r in tiles) + '\n')
print(sum(w + 2 for w, _ in tiles))
