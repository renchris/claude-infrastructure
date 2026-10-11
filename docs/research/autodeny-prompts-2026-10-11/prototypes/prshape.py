# Broad dialog-time predicate: only consulted when CC has ALREADY raised a Bash permission dialog.
import re,sys
sys.path.insert(0,'/tmp/autodeny-census/final')
from detect2 import scripts,nan,unguarded_var,cd_rel_glob,INL
VARSHELL=re.compile(r'''(?:^|[\s;&|(])"?\$\{?\w+\}?"?\s+-[A-Za-z]*c[A-Za-z]*\s''')
RMANY=re.compile(r'''(?:^|[^\w.-])rm(?:dir)?(?![\w.-])''')
def shape(cmd):
    for sc in scripts(cmd):
        if nan(sc) or "$'" in sc:
            return 'inline_shell'
    if VARSHELL.search(cmd): return 'inline_shell'
    if unguarded_var(cmd): return 'unguarded_var'
    if cd_rel_glob(cmd): return 'cd_rel_glob'
    if RMANY.search(cmd) and '$' in cmd: return 'rm_dynamic'
    return None
