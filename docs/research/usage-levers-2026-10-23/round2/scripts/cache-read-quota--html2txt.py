import sys, re, html
for f in sys.argv[1:]:
    s = open(f, encoding='utf-8', errors='replace').read()
    m = re.search(r'<article.*?</article>', s, re.S)
    body = m.group(0) if m else s
    body = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', body, flags=re.S)
    body = re.sub(r'<(br|/p|/li|/h\d|/div)[^>]*>', '\n', body)
    t = html.unescape(re.sub(r'<[^>]+>', '', body))
    t = re.sub(r'\n\s*\n+', '\n', t)
    out = f.rsplit('.',1)[0] + '.txt'
    open(out,'w').write(t)
    print(f, '->', out, len(t))
