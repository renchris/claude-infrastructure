import json,re,collections
H=json.load(open('/tmp/autodeny-census/final/hits.json'))
def has_rm_word(cmd):
    return bool(re.search(r'(^|[\s;&|(`{])(/bin/)?(rm|rmdir|unlink)(\s|$)',cmd or ''))
def cause(h):
    fl=h['flagged']; c=h['cmd'] or ''
    if 'shell -c script' in fl or 'shell -c' in fl:
        return 'inline_shell_c_no_rm' if not has_rm_word(c) else 'inline_shell_c_with_rm'
    if 'changes directories before the removal' in fl or 'changes directory' in fl: return 'cd_then_relative_glob'
    if 'variable' in fl.lower(): 
        # heredoc false positive?
        return 'unguarded_var_target'
    if 'command substitution' in fl.lower(): return 'cmd_substitution_target'
    return 'other:'+fl[:120]
rows=[]
for h in H:
    h['cause']=cause(h)
    el=h['elapsed']
    h['outcome']='capped' if h['capped'] else ('timed_out' if el is not None and el>=110 else 'immediate_no_dialog' if el is not None and el<10 else 'unknown_el')
    rows.append(h)
C=collections.Counter
print('total',len(rows)); print('outcome',C(r['outcome'] for r in rows)); print('ctx',C(r['ctx'] for r in rows))
print('ver',C(r['ver'] for r in rows)); print('cause',C(r['cause'] for r in rows))
print('cause x outcome'); 
for k,v in sorted(C((r['cause'],r['outcome']) for r in rows).items()): print(' ',k,v)
print('cause x ctx')
for k,v in sorted(C((r['cause'],r['ctx']) for r in rows).items()): print(' ',k,v)
print('range',min(r['ts'] for r in rows),max(r['ts'] for r in rows))
print('by day',sorted(C(r['ts'][:10] for r in rows).items()))
print('sessions',len({r['sid'] for r in rows}), C(r['sid'][:8] for r in rows).most_common(6))
print('multi-store copies',sum(1 for r in rows if len(r['stores'])>1), C(tuple(r['stores']) for r in rows))
json.dump(rows,open('/tmp/autodeny-census/final/rows.json','w'),indent=0)
for r in rows:
    if r['cause'].startswith('other') or r['cause'] in('unguarded_var_target','cmd_substitution_target','inline_shell_c_with_rm'):
        print('---',r['cause'],r['outcome'],r['ts'][:16]); print('  FLAG:',r['flagged'][:300].replace('\n',' ')); print('  CMD:',(r['cmd'] or '')[:300].replace('\n',' | '))
