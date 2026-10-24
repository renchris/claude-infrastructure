import json, sys
want = [int(x) for x in sys.argv[1].split(',')]
R = {json.loads(l)['pid']: json.loads(l) for l in open('/tmp/idle-recycle-risk/b/adv/returns.jsonl')}
for p in want:
    r = R[p]
    f = ' '.join(r['final'].split()); pl = ' '.join((r['post_last'] or '').split())
    print('#### pid %d gap=%dm nmach=%d npost=%d cp=%d mk=%s' % (p, r['gap_min'], r['nmach'], r['n_post'], r['cp'], r['mk']))
    print('OP:', ' '.join(r['op'].split())[:600])
    print('FINAL:', f[-int(sys.argv[2]):])
    if pl and pl != f: print('POSTLAST:', pl[-int(sys.argv[3]):])
