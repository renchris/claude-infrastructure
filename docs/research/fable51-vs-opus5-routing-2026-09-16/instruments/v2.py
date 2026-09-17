import math,statistics
F={'Low':(45.1,5.44,34795,51),'Medium':(46.8,7.05,45411,63),'High':(49.2,9.08,58438,77),'xHigh':(51.6,13.01,87294,101),'Max':(51.8,17.28,117236,128)}
O={'Low':(40.7,4.87,31995,57),'Medium':(43.3,6.94,45272,72),'High':(44.7,9.00,61405,86),'xHigh':(46.1,11.43,80094,103),'Max':(46.6,11.95,85384,106)}
print("=== MATCHED-RUNG comparison (same effort label, both models) ===")
print(f"{'rung':7s} {'F score':>8s} {'O score':>8s} {'dScore':>7s} | {'F $':>6s} {'O $':>6s} {'cheaper':>9s} | {'F tok':>7s} {'O tok':>7s} {'fewer':>7s}")
cf=co=tf=to=0
for r in ['Low','Medium','High','xHigh','Max']:
    fs,fc,ft,_=F[r]; os_,oc,ot,_=O[r]
    ch='Opus' if oc<fc else 'Fable'; fw='Opus' if ot<ft else 'Fable'
    cf+= ch=='Fable'; co+= ch=='Opus'; tf+= fw=='Fable'; to+= fw=='Opus'
    print(f"{r:7s} {fs:8.1f} {os_:8.1f} {fs-os_:+7.1f} | {fc:6.2f} {oc:6.2f} {ch:>9s} | {ft:7,} {ot:7,} {fw:>7s}")
print(f"\nCheaper at matched rung: Opus {co}/5, Fable {cf}/5   Fewer tokens: Opus {to}/5, Fable {tf}/5")
print("\n=== COLLINEARITY of the 'independent' axes (10 Opus+Fable rows) ===")
rows=list(F.values())+list(O.values())
def pear(a,b):
    ma,mb=statistics.mean(a),statistics.mean(b)
    return sum((x-ma)*(y-mb) for x,y in zip(a,b))/math.sqrt(sum((x-ma)**2 for x in a)*sum((y-mb)**2 for y in b))
cost=[r[1] for r in rows]; tok=[r[2] for r in rows]; step=[r[3] for r in rows]
print(f"r(cost,tokens)={pear(cost,tok):.4f}  r(cost,steps)={pear(cost,step):.4f}  r(tokens,steps)={pear(tok,step):.4f}")
print("\n=== POWER: what n does 2.1pp need? (unpaired, p~.455, a=.05 2-sided) ===")
p=0.455
for d in (0.021,0.004,0.002,0.052):
    n=2*(1.96**2)*p*(1-p)/d**2
    print(f"  gap {d*100:4.1f}pp -> needs n >= {n:9,.0f} tasks/arm")
print("\n=== SE of a difference at plausible n ===")
for n in (50,100,200,300,500,1000):
    se=math.sqrt(2*p*(1-p)/n)*100
    print(f"  n={n:5d}: SE(diff)={se:5.2f}pp  -> 2.1pp = {2.1/se:.2f} SE ; 5.2pp = {5.2/se:.2f} SE ; 95% needs {1.96*se:5.2f}pp")
print("\n=== Is n inferable from score granularity? (are scores multiples of 1/n?) ===")
allsc=[51.8,51.6,49.2,46.8,46.6,46.1,45.1,44.7,43.3,41.7,41.6,41.4,41.3,40.7,40.4,39.6,37.7,37.5,37.3,36.1,35.9,35.7,34.1,33.6,33.4,33.0,32.6,32.0,31.1,30.8,30.7,29.4,29.3,28.0,27.7,27.6,25.2,24.6,24.3,24.1,22.2,16.0]
for n in range(20,401):
    if all(abs(s/100*n - round(s/100*n))<0.006 for s in allsc):
        print(f"  n={n} consistent with ALL 42 published scores"); break
else: print("  no n<=400 makes every score an exact multiple of 1/n -> partial credit / weighted grading, OR n large")
