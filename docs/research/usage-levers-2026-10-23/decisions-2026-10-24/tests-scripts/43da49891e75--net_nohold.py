# Re-run net.py's arithmetic with the 1-hour operator hold removed (replay passed), plus Wilson bounds on 0 failures.
import math
G = {'150k': (16.36, 347, 219), '200k': (15.39, 225, 143), '250k': (13.64, 157, 86)}
RW, HOLD, HOUR = 0.10/155, 1.40/155, 2.31/155
for k, (g, m, t) in G.items():
    mw, tw = m/2, (m+t)/2
    pess = mw*5.86/155 + mw*RW + tw*3.87/264 + mw*1.40/155 + mw*HOLD
    print('pessimistic without 1h hold', k, 'net %.2f (with hold %.2f)' % (g - pess, g - pess - mw*HOUR))
def wilson_hi(k, n, z=1.96):
    p = k/n; d = 1 + z*z/n; c = p + z*z/(2*n); h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n)); return (c + h)/d
for n in (10, 3): print('0/%d failures: 95%% Wilson upper bound %.1f%%' % (n, 100*wilson_hi(0, n)))
print('2/10 would be the decision bar; P(>=3 fail | true rate 10%%) = %.3f' % (1 - sum(math.comb(10,i)*0.1**i*0.9**(10-i) for i in range(3))))
