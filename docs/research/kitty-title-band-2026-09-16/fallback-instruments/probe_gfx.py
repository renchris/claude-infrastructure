def on_load(boss, data):
    import traceback, base64
    L='/private/tmp/ktb-fallback/gfx.log'
    def log(*a): open(L,'a').write(' '.join(str(x) for x in a)+'\n')
    try:
        def parse_bytes(screen, payload):
            mv = memoryview(payload)
            while mv:
                dest = screen.test_create_write_buffer()
                s = screen.test_commit_write_buffer(mv, dest)
                mv = mv[s:]
                screen.test_parse_written_data(None)

        W, H = 300, 45
        px = bytes([255, 0, 255]) * (W * H)          # solid magenta RGB
        b64 = base64.standard_b64encode(px).decode('ascii')
        chunks = [b64[i:i+4000] for i in range(0, len(b64), 4000)]
        target = None
        for osw in boss.os_window_map.values():
            for tab in osw:
                for w in tab:
                    tbs = getattr(w, '_title_bar_screen', None)
                    if tbs is None:
                        log('win', w.id, 'NO title bar screen'); continue
                    scr = tbs.screen
                    log('win', w.id, 'tb screen lines', scr.lines, 'cols', scr.columns)
                    first = True
                    for i, c in enumerate(chunks):
                        m = 1 if i < len(chunks) - 1 else 0
                        if first:
                            cmd = f'\x1b_Ga=T,f=24,s={W},v={H},q=2,C=1,m={m};{c}\x1b\\'
                            first = False
                        else:
                            cmd = f'\x1b_Gm={m};{c}\x1b\\'
                        parse_bytes(scr, cmd.encode('ascii'))
                    log('win', w.id, 'fed', len(chunks), 'chunks')
                    target = w
        log('done')
    except Exception:
        log('FAIL', traceback.format_exc())
