#!/usr/bin/env python3
"""List every record before the first assistant response of a transcript (no content, sizes only).
Usage: sp_dump_first_request.py FILE [FILE...] [--save DIR]  (--save writes rendered text of
setup attachments of the FIRST file to DIR/<type>.txt for token calibration)."""
import json, sys, os
args = sys.argv[1:]; save = None
if '--save' in args:
    i = args.index('--save'); save = args[i+1]; del args[i:i+2]
def rtext(a, rec):
    r = rec.get('attachment', {}).get('rendered') or rec.get('rendered')
    if isinstance(r, list): return ''.join(x.get('content', '') for x in r if isinstance(x, dict))
    return None
for n, path in enumerate(args):
    print('=' * 8, path.split('/projects/')[1][:140])
    seen = {}
    with open(path) as fh:
        for ln in fh:
            try: rec = json.loads(ln)
            except Exception: continue
            t = rec.get('type')
            if t == 'assistant':
                u = rec['message'].get('usage', {})
                cc = u.get('cache_creation') or {}
                print(f"  FIRST RESPONSE model={rec['message'].get('model')} in={u.get('input_tokens')} cr={u.get('cache_read_input_tokens')} "
                      f"cw5m={cc.get('ephemeral_5m_input_tokens')} cw1h={cc.get('ephemeral_1h_input_tokens')}")
                break
            if t == 'attachment':
                a = rec.get('attachment', {}); at = a.get('type')
                rt = None
                r = rec.get('attachment', {}).get('rendered', rec.get('rendered'))
                if isinstance(r, list): rt = ''.join(x.get('content', '') for x in r if isinstance(x, dict))
                extra = ''
                if at == 'instructions':
                    extra = ' files=' + '; '.join(f"{f.get('path')}:{len(f.get('content') or '')}" for f in a.get('files', []))
                elif at and at.startswith('hook'):
                    extra = f" hook={a.get('hookName')} event={a.get('hookEvent')} contentlen={len(str(a.get('content') or ''))}"
                elif at == 'deferred_tools_delta':
                    extra = f" added={len(a.get('addedNames') or a.get('names') or [])}"
                print(f"  attachment {at:28s} rendered={'-' if rt is None else len(rt)}{extra}")
                if save and n == 0 and rt:
                    key = at if at != 'hook_additional_context' else f"hook_{a.get('hookEvent')}"
                    seen[key] = seen.get(key, '') + rt
            elif t == 'user':
                m = rec.get('message', {}).get('content')
                L = len(m) if isinstance(m, str) else sum(len(json.dumps(b)) for b in m)
                print(f"  user isMeta={rec.get('isMeta', False)} chars={L}")
            else:
                print(f"  {t}")
    if save and n == 0:
        os.makedirs(save, exist_ok=True)
        for k, v in seen.items():
            open(os.path.join(save, f"{k}.md"), 'w').write(v)
        print('  saved', sorted((k, len(v)) for k, v in seen.items()))
