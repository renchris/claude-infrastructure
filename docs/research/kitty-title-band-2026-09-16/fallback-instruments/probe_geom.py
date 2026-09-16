def on_load(boss, data):
    import traceback
    L='/private/tmp/ktb-fallback/geom.log'
    def log(*a):
        open(L,'a').write(' '.join(str(x) for x in a)+'\n')
    try:
        import kitty.window as kw
        ch = None
        for osw in boss.os_window_map.values():
            for tab in osw:
                for w in tab:
                    g = w.geometry
                    cw, chh = kw.cell_size_for_window(w.os_window_id)
                    ch = chh
                    et = int(w.effective_padding('top'))
                    log(f'win {w.id} show_tb={w.show_title_bar} g.top={g.top} g.bottom={g.bottom} '
                        f'g.ynum={g.ynum} screen.lines={w.screen.lines} cell_h={chh} eff_pad_top={et} '
                        f'band=[{g.top},{g.top+chh}) pushed_pad_top={et-chh} '
                        f'contains_mouse_top_stock={g.top-et} contains_mouse_top_hacked={(g.top-(et-chh))}')
        log('---')
    except Exception:
        log('FAIL', traceback.format_exc())
