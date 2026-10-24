# watcher job durations (notification time - tool_use time) for watcher jobs, by bucket
import collections
for a in ['next','next2','next3','next4']:
    pass
d=[]
for a in ['next','next2','next3','next4']:
    for l in open('/tmp/lean-idle/idle-keepalive-wake/'+a+'.jobs'):
        fi,sid,tu,nm,w,js,je=l.rstrip('\n').split('\t')
        if w=='1' and js and je: d.append(float(je)-float(js))
d.sort()
near=[x for x in d if 3250<=x<3700]
print('watcher jobs with notice',len(d),'in 3250-3700s',len(near))
q=lambda xs,p: xs[min(len(xs)-1,int(p*len(xs)))]
print('job dur-3300 p5 %.1f p10 %.1f p25 %.1f p50 %.1f p75 %.1f p90 %.1f'%tuple(q(near,p)-3300 for p in (.05,.1,.25,.5,.75,.9)))
