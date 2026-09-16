import json
def main(args): raise SystemExit('no_ui')
def handle_result(args, answer, target_window_id, boss):
    from kitty.fast_data_types import get_options, cell_size_for_window
    o = get_options()
    out = {'opt_window_title_bar': o.window_title_bar,
           'opt_min_windows': o.window_title_bar_min_windows,
           'windows': []}
    for w in boss.all_windows:
        g = w.geometry
        out['windows'].append({
            'id': w.id, 'show_title_bar': bool(w.show_title_bar),
            'screen_lines': w.screen.lines, 'screen_cols': w.screen.columns,
            'geom': [g.left, g.top, g.right, g.bottom, g.xnum, g.ynum],
            'tb_screen': w._title_bar_screen is not None,
            'tb_geom': (list(w._title_bar_screen.geometry)[:4] if w._title_bar_screen is not None and w._title_bar_screen.geometry else None),
            'last_pty': list(w.last_reported_pty_size) if w.last_reported_pty_size else None,
            'cell': list(cell_size_for_window(w.os_window_id)),
            'pad': {k: getattr(w, k, None) for k in ('padding',)},
        })
    return json.dumps(out, default=str)
handle_result.no_ui = True
