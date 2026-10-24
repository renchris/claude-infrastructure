# Estimated net pp/week: rp_p90 gross (rp90.out) minus reviewer-priced costs scaled per recycle from the 150k figures.
G = {'150k': (16.36, 347, 219), '200k': (15.39, 225, 143), '250k': (13.64, 157, 86), 'cur': (7.58, 110, 87)}
OR, RW, BUSY, HOLD, HOUR = 2.78/155, 0.10/155, 0.60/155, 1.40/155, 2.31/155   # per mid recycle/week (base 310 mid/14d)
HO = 1.10/264                                                                   # per recycle/week (base 528/14d)
for k, (g, m, t) in G.items():
    mw, tw = m/2, (m+t)/2
    c = dict(orient=mw*OR, rework=mw*RW, handoff=tw*HO, busy=mw*BUSY, tailhold=mw*HOLD)
    tot = sum(c.values())
    print(k, 'gross %.2f' % g, ' '.join('%s %.2f' % kv for kv in c.items()), 'cost %.2f net %.2f | +1h op hold %.2f -> %.2f' % (tot, g-tot, mw*HOUR, g-tot-mw*HOUR))
# Pessimistic stack: all-successor orientation 5.86, handoff at 5 requests 3.87, busy 1.4 (no-notice rule), tail hold, 1h operator hold.
for k, (g, m, t) in G.items():
    mw, tw = m/2, (m+t)/2
    tot = mw*5.86/155 + mw*RW + tw*3.87/264 + mw*1.40/155 + mw*HOLD + mw*HOUR
    print('pessimistic', k, 'cost %.2f net %.2f' % (tot, g-tot))
