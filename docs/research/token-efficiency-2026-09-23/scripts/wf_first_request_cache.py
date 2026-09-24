#!/usr/bin/env python3
"""wf_first_request_cache.py — for every Workflow agent transcript (<cfg>/projects/*/<sid>/subagents/workflows/wf_*/agent-*.jsonl,
deduped by realpath), read the FIRST API response's usage and report: how often the first request READS any cache,
the 5m/1h split, and within each workflow run whether sibling agents share a prefix (read>0). Also the same for
Agent-tool subagents (<sid>/subagents/agent-*.jsonl). Aggregates only."""
import json,glob,os,statistics as st,collections
def first_usage(f):
    try:
        for line in open(f):
            if '"assistant"' not in line: continue
            r=json.loads(line)
            if r.get('type')!='assistant': continue
            u=r['message'].get('usage') or {}
            return r['message'].get('model'),u
    except Exception: return None
    return None
def scan(pattern):
    seen=set(); rows=[]
    for f in glob.glob(os.path.expanduser(pattern)):
        rp=os.path.realpath(f)
        if rp in seen: continue
        seen.add(rp)
        x=first_usage(rp)
        if not x: continue
        m,u=x
        if m=='<synthetic>': continue
        cc=u.get('cache_creation') or {}
        rows.append(dict(f=rp,run=os.path.dirname(rp),model=m,read=u.get('cache_read_input_tokens') or 0,create=u.get('cache_creation_input_tokens') or 0,
                         inp=u.get('input_tokens') or 0,c5=cc.get('ephemeral_5m_input_tokens') or 0,c1=cc.get('ephemeral_1h_input_tokens') or 0))
    return rows
def report(name,rows):
    if not rows: print(name,'none'); return
    n=len(rows); r0=sum(1 for r in rows if r['read']==0)
    pre=[r['read']+r['create']+r['inp'] for r in rows]
    print(f"{name}: agents={n} first_req_read==0: {r0} ({100*r0/n:.1f}%)  median_prefix={st.median(pre):.0f} p90={sorted(pre)[int(.9*n)-1]:.0f}")
    print(f"   first-request create tokens: 5m={sum(r['c5'] for r in rows):,} 1h={sum(r['c1'] for r in rows):,} read={sum(r['read'] for r in rows):,}")
    runs=collections.defaultdict(list)
    for r in rows: runs[r['run']].append(r)
    multi=[v for v in runs.values() if len(v)>=2]
    shared=sum(1 for v in multi for r in v if r['read']>5000)
    tot=sum(len(v) for v in multi)
    print(f"   runs with >=2 agents: {len(multi)}; agents in them with first-req read>5k: {shared}/{tot}")
    rd=[r['read'] for r in rows if r['read']>0]
    print(f"   mean first-req read among reading agents={sum(rd)/max(1,len(rd)):.0f}; median={st.median(rd) if rd else 0:.0f}; share of first-req prefix READ={sum(r['read'] for r in rows)/sum(pre):.3f}")
    c=sum(r['c5'] for r in rows)*1.25*4/1e6 + sum(r['c1'] for r in rows)*2*4/1e6 + sum(r['read'] for r in rows)*0.20/1e6
    print(f"   first-request prefix cost re-priced at Opus 5.5 list ($4 in, 1.25x 5m write, $0.20 read): ${c:,.0f}")
    print('   models:',collections.Counter(r['model'] for r in rows).most_common(5))
wf=[]; sa=[]
for cfg in ['~/.claude','~/.claude-next','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']:
    wf+=scan(cfg+'/projects/*/*/subagents/workflows/wf_*/agent-*.jsonl')
    sa+=scan(cfg+'/projects/*/*/subagents/agent-*.jsonl')
# dedupe across cfg by realpath
def dd(rows):
    s={}; 
    for r in rows: s[r['f']]=r
    return list(s.values())
report('WORKFLOW agents',dd(wf)); report('AGENT-TOOL subagents',dd(sa))
