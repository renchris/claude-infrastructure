import os, sys, json, time
from datetime import datetime, timezone
root = sys.argv[1]
t_end = float(sys.argv[2])  # epoch of /usage run
now = time.time()
windows = {'24h': 86400, '7d': 7*86400}
# calendar-day variant: start of local day 6 days before / 7 days before
import calendar
lt = time.localtime(t_end)
sod = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, 0, 0, 0, 0, 0, -1))
cal = {'7d_cal_sod-6': sod - 6*86400, '7d_cal_sod-7': sod - 7*86400}
min_start = min(t_end - 7*86400, cal['7d_cal_sod-7'])
files = []
for dp, dn, fn in os.walk(root, followlinks=False):
    for f in fn:
        if f.endswith('.jsonl'):
            p = os.path.join(dp, f)
            try:
                if os.stat(p).st_mtime >= min_start: files.append(p)
            except OSError: pass
recs = []  # (ts, msgid, reqid, is_sub, sid, model)
nbytes = 0
for p in files:
    is_sub = '/subagents/' in p
    try:
        fh = open(p, 'rb')
    except OSError: continue
    with fh:
        for line in fh:
            nbytes += len(line)
            if b'"assistant"' not in line: continue
            try: r = json.loads(line)
            except Exception: continue
            if r.get('type') != 'assistant': continue
            ts = r.get('timestamp')
            if not ts: continue
            try: e = datetime.fromisoformat(ts.replace('Z', '+00:00')).timestamp()
            except Exception: continue
            m = r.get('message') or {}
            recs.append((e, m.get('id'), r.get('requestId'), is_sub, r.get('sessionId'), m.get('model'), bool(r.get('isSidechain'))))
print('files', len(files), 'bytes_read', nbytes, 'assistant_records', len(recs))
def summarize(name, start, end):
    sel = [x for x in recs if start <= x[0] <= end]
    ids = set(x[1] for x in sel if x[1])
    ids_nosyn = set(x[1] for x in sel if x[1] and x[5] != '<synthetic>')
    reqs = set(x[2] for x in sel if x[2])
    main = set(x[1] for x in sel if x[1] and not x[3])
    sub = set(x[1] for x in sel if x[1] and x[3])
    sess_main = set(x[4] for x in sel if not x[3])
    sess_all = set(x[4] for x in sel)
    print(f"{name}: records {len(sel)} dedup_msgid {len(ids)} dedup_msgid_nosynthetic {len(ids_nosyn)} dedup_reqid {len(reqs)} main_ids {len(main)} sub_ids {len(sub)} overlap {len(main & sub)} sessions_main {len(sess_main)} sessions_all {len(sess_all)}")
summarize('24h_rolling', t_end - 86400, t_end)
summarize('7d_rolling', t_end - 7*86400, t_end)
for k, s in cal.items(): summarize(k, s, t_end)
