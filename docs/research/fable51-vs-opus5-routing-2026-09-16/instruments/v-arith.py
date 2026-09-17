rows=[("Fable 5.1 Max",51.8,17.28,117236,128),("Fable 5.1 xHigh",51.6,13.01,87294,101),
("Fable 5.1 High",49.2,9.08,58438,77),("Fable 5.1 Medium",46.8,7.05,45411,63),
("Opus 5 Max",46.6,11.95,85384,106),("Opus 5 xHigh",46.1,11.43,80094,103),
("Fable 5.1 Low",45.1,5.44,34795,51),("Opus 5 High",44.7,9.00,61405,86),
("Opus 5 Medium",43.3,6.94,45272,72),("Opus 5 Low",40.7,4.87,31995,57),
("Sonnet 5 Max",34.1,7.17,149257,140),("Composer 2.5",27.7,0.68,17347,41),
("GPT-5.6 Luna Low",16.0,0.03,3288,18),("Gemini 3.8 Flash High",39.6,4.70,162565,324),
("Muse Spark 1.3 Max",41.6,2.64,52005,98)]
print(f"{'row':26s} {'$/MTok blended':>14s} {'$/step':>8s} {'tok/step':>9s}")
for n,s,c,t,st in rows:
    print(f"{n:26s} {c/t*1e6:14.1f} {c/st:8.3f} {t/st:9.0f}")
print()
# Opus 5 list: in 5, out 25, cache read 0.50, cache write 6.25 -> MAX unit price 25
# Fable 5.1 list: in 10, out 50, cache read 0.25, cache write 12.50 -> MAX unit price 50
for n,mx in (("Opus 5",25.0),("Fable 5.1",50.0)):
    for r in rows:
        if r[0].startswith(n):
            b=r[2]/r[3]*1e6
            print(f"{r[0]:22s} blended ${b:7.1f}/MTok  vs max list unit ${mx:5.1f}  -> {b/mx:5.2f}x IMPOSSIBLE" if b>mx else f"{r[0]:22s} ok")
print()
# If Tokens column == OUTPUT only, solve residual dollars as cache reads
print("Decomposition test: assume Tokens/task = generated(output) tokens only")
print(f"{'row':22s} {'out$':>7s} {'resid$':>8s} {'cacheR $/M':>10s} {'implied cacheR tok':>19s} {'TOTAL tok':>12s}")
for n,po,pc in (("Opus 5",25.0,0.50),("Fable 5.1",50.0,0.25)):
    for r in rows:
        if r[0].startswith(n):
            outc=r[3]*po/1e6; res=r[2]-outc; cr=res/pc*1e6
            print(f"{r[0]:22s} {outc:7.2f} {res:8.2f} {pc:10.2f} {cr:19,.0f} {cr+r[3]:12,.0f}")
