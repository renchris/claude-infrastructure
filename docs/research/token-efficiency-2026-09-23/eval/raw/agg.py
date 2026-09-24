# task, run, arm, cost, input, cc, cr, out, turns, terr, hblk, success, quality, comp_true, comp_n
R = """T1 1 full 0.8913 24 79923 953738 3054 15 3 2 1 4 5 5
T1 2 slim 0.59 24 50289 638971 2988 14 3 0 1 5 5 5
T1 3 slim 0.5706 22 49922 579393 2761 13 3 0 1 4 5 5
T1 4 full 0.8364 20 78173 781490 2734 11 2 0 1 4 5 5
T2 1 full 0.7594 14 77550 515316 1794 9 2 0 1 4 5 5
T2 2 slim 0.7658 38 54636 1076601 5661 23 4 3 1 4 5 5
T2 3 slim 0.8192 46 54874 1336143 5638 25 4 2 1 4 4 5
T2 4 full 0.6843 10 73857 342264 1246 6 1 0 1 3 4 5
T3 1 full 0.6958 10 74169 344064 1680 5 2 0 1 4 5 5
T3 2 slim 0.5161 12 48188 286890 3658 8 3 0 1 5 5 5
T3 3 slim 0.4647 10 46255 229567 2436 5 2 0 1 5 5 5
T3 4 full 0.7035 10 74694 344673 1851 5 2 0 1 4 5 5
T4 1 full 1.0023724 24 86244 1005022 5566 16 4 1 1 4 5 5
T4 2 slim 0.7671572 24 61623 727886 6425 18 3 0 1 5 5 5
T4 3 slim 0.6751954 18 58899 515257 5044 14 2 1 1 4 5 5
T4 4 full 0.9911586 24 85483 1005693 5303 16 3 1 1 4 5 5
T5 1 full 0.6248072 6 72562 175236 462 3 0 0 1 5 4 4
T5 2 slim 0.3837024 6 43887 117912 450 3 0 0 1 5 4 4
T5 3 slim 0.3839226 6 43892 117913 459 3 0 0 1 5 4 4
T5 4 full 0.6277148 6 72747 175374 532 3 0 0 1 5 4 4
T6 1 full 0.5841206 2 72003 10343 301 1 0 0 1 4 4 4
T6 2 slim 0.4663012 6 52541 123846 1059 4 0 0 1 3 3 4
T6 3 slim 0.4704566 6 52541 123823 1267 4 0 0 1 5 4 4
T6 4 full 0.6579224 4 78191 92692 692 3 0 0 1 3 3 4"""
rows=[l.split() for l in R.splitlines()]
import statistics as st
def f(x): return float(x)
for arm in ("full","slim"):
    a=[r for r in rows if r[2]==arm]
    m=lambda i: st.mean(f(r[i]) for r in a)
    print(arm, "n",len(a),"succ",sum(int(r[11]) for r in a),
      "comp %d/%d"%(sum(int(r[13]) for r in a),sum(int(r[14]) for r in a)),
      "q %.2f"%m(12),"cost %.4f"%m(3),"sum %.4f"%sum(f(r[3]) for r in a),
      "in %.1f cc %.0f cr %.0f out %.0f turns %.2f terr %.2f hb %.2f"%(m(4),m(5),m(6),m(7),m(8),m(9),m(10)),
      "tot terr",sum(int(r[9]) for r in a),"tot hb",sum(int(r[10]) for r in a))
    # meter proxy: cc+out+input
    print("  meter-proxy mean %.0f"%st.mean(f(r[4])+f(r[5])+f(r[7]) for r in a))
for t in sorted(set(r[0] for r in rows)):
    out=[t]
    for arm in ("full","slim"):
        a=[r for r in rows if r[0]==t and r[2]==arm]
        out.append("%s cost %.3f cc %.0f cr %.0f out %.0f turns %.1f q %.1f"%(arm,st.mean(f(r[3]) for r in a),st.mean(f(r[5]) for r in a),st.mean(f(r[6]) for r in a),st.mean(f(r[7]) for r in a),st.mean(f(r[8]) for r in a),st.mean(f(r[12]) for r in a)))
    fc=st.mean(f(r[3]) for r in rows if r[0]==t and r[2]=="full"); sc=st.mean(f(r[3]) for r in rows if r[0]==t and r[2]=="slim")
    out.append("delta %.1f%%"%((sc-fc)/fc*100))
    print(" | ".join(out))
# excluding T2 (confound)
for arm in ("full","slim"):
    a=[r for r in rows if r[2]==arm and r[0]!="T2"]
    print(arm,"exT2 cost %.4f"%st.mean(f(r[3]) for r in a))
L="""L1 1 gp 69687 12 104765 450082 4860 6 0 1.6940216 1 4
L1 2 lean 5273 18 43251 243501 5607 9 0 1.0129946 1 5
L1 3 lean 5273 10 75430 192591 6387 5 0 1.1943958 1 5
L1 4 gp 70652 16 98190 653001 6106 8 0 1.3799084 1 4
L2 1 gp 70685 16 86196 567713 4548 8 0 1.2716388 1 3
L2 2 lean 5306 14 23303 133398 4594 7 0 0.8710116 1 4
L2 3 lean 5306 12 23521 108450 4482 6 0 0.861009 1 5
L2 4 gp 70685 10 69336 298064 2704 5 0 1.0843652 0 2
L3 1 gp 70620 10 68336 296374 1868 5 0 1.058182 1 4
L3 2 lean 5241 8 8264 20463 1330 4 1 0.689156 1 5
L3 3 lean 5241 8 3794 25143 1476 4 1 0.6715378 1 5
L3 4 gp 70620 8 67819 222851 1395 4 0 1.0293766 1 5"""
lr=[l.split() for l in L.splitlines()]
for arm in ("gp","lean"):
    a=[r for r in lr if r[2]==arm]
    m=lambda i: st.mean(f(r[i]) for r in a)
    print(arm,"succ",sum(int(r[11]) for r in a),"q %.2f"%m(12),"prefix %.0f"%m(3),"in %.0f cc %.0f cr %.0f out %.0f"%(m(4),m(5),m(6),m(7)),
      "total %.0f"%st.mean(f(r[4])+f(r[5])+f(r[6])+f(r[7]) for r in a),"resp %.2f"%m(8),"terr",sum(int(r[9]) for r in a),"cost %.4f"%m(10))
for t in ("L1","L2","L3"):
    for arm in ("gp","lean"):
        a=[r for r in lr if r[0]==t and r[2]==arm]
        print(t,arm,"total",[int(f(r[4])+f(r[5])+f(r[6])+f(r[7])) for r in a],"cost %.3f"%st.mean(f(r[10]) for r in a))
