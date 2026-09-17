from PIL import Image
import numpy as np, sys, json
def gridrows(a,W):
    sub=a[:, int(W*0.15):int(W*0.95)]
    rows=[]
    for y in range(a.shape[0]):
        row=sub[y]
        m=((row[:,0]>212)&(row[:,0]<248)&(abs(row[:,0]-row[:,1])<7)&(abs(row[:,1]-row[:,2])<7)).mean()
        if m>0.88: rows.append(y)
    # collapse
    out=[];cur=[rows[0]]
    for y in rows[1:]:
        if y-cur[-1]<=3: cur.append(y)
        else: out.append(sum(cur)/len(cur)); cur=[y]
    out.append(sum(cur)/len(cur))
    return out
def xlabels(a,H,W,y0,y1):
    band=a[y0:y1,:,:]
    dark=(band.sum(axis=2)<330).any(axis=0)
    xs=np.where(dark)[0]
    groups=[];cur=[xs[0]]
    for x in xs[1:]:
        if x-cur[-1]<=22: cur.append(x)
        else: groups.append(cur); cur=[x]
    groups.append(cur)
    return [ (g[0]+g[-1])/2 for g in groups ]
def boxsum(m,k):
    cc=np.cumsum(np.cumsum(m.astype(np.int32),0),1); cc=np.pad(cc,((1,0),(1,0)))
    return cc[k:,k:]-cc[:-k,k:]-cc[k:,:-k]+cc[:-k,:-k]
def markers(a,c,ytop,k=13,tol=70,frac=0.97):
    m=(np.abs(a-np.array(c)).sum(axis=2)<tol); m[:ytop,:]=False
    s=boxsum(m,k); hit=np.argwhere(s>=k*k*frac)+k//2
    if len(hit)==0: return []
    used=np.zeros(len(hit),bool); out=[]
    for i,p in enumerate(hit):
        if used[i]: continue
        d=np.abs(hit-p).max(axis=1)<20; used|=d
        out.append(hit[d].mean(axis=0))
    out.sort(key=lambda p:p[1])
    return out
