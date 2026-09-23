import json, subprocess, datetime as dt
R='/Users/chrisren/Development/reso-management-app'
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z']
def g(*a):
    p=subprocess.run(['git','-C',R]+list(a),capture_output=True,text=True); return p.stdout.strip(),p.returncode
hookfail=[(r,p) for r in w for p in r['per_round'] if 'unit tests failed' in (p.get('push_tail') or '')]
for r,p in hookfail:
    h=r['head']; ex=g('cat-file','-e',h)[1]==0
    print('==',r['ts_start'],r['branch'],'head',h[:9],'exists',ex,'L',r['load1_entry'],'suite',p.get('suite_mode'),p.get('suite_s'),'push_s',p.get('push_s'),'prc',p.get('push_rc'))
    if ex:
        mb,_=g('merge-base',h,'origin/main')
        subj,_=g('log','--format=%h %s',mb+'..'+h)
        print('   commits not on main:', subj.replace('\n',' || ')[:600])
        # is the patch landed? find commit on main with same subject
        for line in subj.splitlines()[:6]:
            s=line.split(' ',1)[1]
            m,_=g('log','origin/main','--since=2026-09-15','--fixed-strings','--grep='+s[:60],'--format=%h %cI')
            print('     landed as:',m.replace('\n',' ; ')[:120] or 'NOT FOUND','<-',s[:70])
# later attempts of same branch
