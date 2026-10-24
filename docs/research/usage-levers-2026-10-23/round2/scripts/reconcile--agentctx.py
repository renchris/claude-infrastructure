import re, sys, mmap
p = sys.argv[1]
names = [b'Explore', b'Plan', b'general-purpose', b'statusline-setup', b'workflow-subagent', b'comment-thread-analyst']
with open(p, 'rb') as f:
    mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    for n in names:
        for m in re.finditer(rb'agentType:"' + n + rb'"', mm):
            w = mm[m.start():m.start()+1500]
            bi = b'built-in' in w
            tools = re.search(rb'(disallowedTools|tools):\[[^\]]{0,200}\]', w)
            print(n.decode(), m.start(), 'built-in' if bi else 'no-builtin-tag', (tools.group(0)[:160].decode('latin1') if tools else ''))
