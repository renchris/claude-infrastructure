"""Challenge lottery: an agent files a challenge on a fraction r of completeness asks (measured: 27% of
yes-replies also name an item, 15.7% of asks spawn a subagent in-turn; ask_turns.out). Each triage is a
fresh LLM verify+rate draw; eps = P(a non-escape is triaged 'escape'). Take-back when false escapes > bound.
Also: W0 calibration power with n programs, all holding (one-sided 95% Clopper-Pearson lower bound)."""
import math
def p_ge(k, lam): return 1 - sum(math.exp(-lam) * lam**i / math.factorial(i) for i in range(k))
print("asks  r     eps   E[challenge notices]  P(false escapes >= 2)  (bound n_pred95 = 1)")
for n in (10, 20, 30):
    for r in (0.157, 0.27):
        for eps in (0.05, 0.10, 0.20):
            print("%4d  %.3f %.2f  %5.1f                 %5.1f%%" % (n, r, eps, n * r, 100 * p_ge(2, n * r * eps)))
print("\nW0 backtest: programs n, all hold -> 95% lower bound on the true hold rate")
for n in (1, 2, 5, 10, 30, 59): print(" n=%-3d  hold rate >= %.1f%%" % (n, 100 * 0.05 ** (1 / n)))
