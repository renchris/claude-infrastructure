# Robustness: pin the output weight at a list-price-implied value and refit the rest (pooled, attribution-free).
# Re-uses rfit.py's design by exec'ing its top half is fragile; instead rebuild X,y via rfit.py's code path.
import runpy, sys, os, io, contextlib, json
import numpy as np
sys.argv = ["rfit.py", "2026-09-28T00:00:00+00:00", "2026-10-24T06:00:00+00:00", "-", "3", "base", "w"]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    g = runpy.run_path("/tmp/usage-audit/r2/cache-read-weight-review/rfit.py")
X, y, names, nnls, day = g["X"], g["y"], g["names"], g["nnls"], g["day"]
io_ = names.index("out_opus"); ic = names.index("cr_opus")
rng = np.random.default_rng(5); u = np.unique(day); idx = {c: np.where(day == c)[0] for c in u}
for fo in (0.0, 0.4, 0.8, 1.2, 2.0):
    cols = [i for i in range(len(names)) if i != io_]
    def fit(Xs, ys):
        bb = np.zeros(len(names)); bb[io_] = fo
        bb[cols] = nnls(Xs[:, cols], ys - fo * Xs[:, io_]); return bb
    b = fit(X, y); e = y - X @ b
    BS = np.array([fit(X[ii], y[ii]) for ii in (np.concatenate([idx[c] for c in rng.choice(u, len(u))]) for _ in range(300))])
    lo, hi = np.percentile(BS[:, ic], [2.5, 97.5])
    print("out fixed=%.1f RMSE=%.3f cr=%.5f CI=[%.5f %.5f] zero=%.0f%% | %s" % (fo, np.sqrt(e @ e / len(y)), b[ic], lo, hi, 100 * (BS[:, ic] == 0).mean(), " ".join("%s=%.4f" % (n, v) for n, v in zip(names, b))))
