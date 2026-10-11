import re,sys
sys.path.insert(0,'/tmp/autodeny-census/final')
from detect2 import classify
VARSHELL=re.compile(r'''(?:^|[\s;&|(])"?\$\{?\w+\}?"?\s+-[A-Za-z]*c[A-Za-z]*\s''')
def shape(cmd):
    k=classify(cmd)
    if k: return k[0].split(':')[0]
    if VARSHELL.search(cmd): return 'inline_shell'
    return None
