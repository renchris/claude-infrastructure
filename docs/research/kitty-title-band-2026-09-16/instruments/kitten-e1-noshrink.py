# E1: band at row 1 WITHOUT shrinking the screen. Proves/refutes whether live-now
# can reach (a) zero shift and (c) hit-testable band simultaneously.
import json
def main(args): raise SystemExit('no_ui')
def handle_result(args, answer, target_window_id, boss):
    import kitty.window as W
    from kitty.fast_data_types import get_options, cell_size_for_window, set_window_render_data, set_window_title_bar_render_data
    from kitty.types import WindowGeometry
    base = getattr(W.Window.set_geometry, '_ktb_orig', W.Window.set_geometry)
    if getattr(W.Window.set_geometry, '_ktb_e1', False):
        return json.dumps({'status': 'already-e1'})

    def e1(self, new_geometry):
        if self.destroyed:
            return
        if not (self.show_title_bar and new_geometry.ynum > 1):
            return base(self, new_geometry)
        cw, ch = cell_size_for_window(self.os_window_id)
        # THE DIFFERENCE: keep the FULL row count. No screen.resize, no SIGWINCH.
        render_ynum = new_geometry.ynum
        render_top = new_geometry.top + ch
        render_bottom = new_geometry.bottom
        if self.needs_layout or new_geometry.xnum != self.screen.columns or render_ynum != self.screen.lines:
            self.screen.resize(max(0, render_ynum), max(0, new_geometry.xnum))
            self.needs_layout = False
        cur = (self.screen.lines, self.screen.columns,
               max(0, new_geometry.right - new_geometry.left), max(0, render_bottom - render_top))
        if cur != self.last_reported_pty_size:
            self.resize_child(cur)
        self.geometry = g = new_geometry
        set_window_render_data(self.os_window_id, self.tab_id, self.id, self.screen,
                               g.left, render_top, g.right, render_bottom,
                               g.spaces.left, g.spaces.top, g.spaces.right, g.spaces.bottom)
        self.update_effective_padding()
        if self._title_bar_screen is None:
            from kitty.window_title_bar import WindowTitleBarScreen
            self._title_bar_screen = WindowTitleBarScreen(self.os_window_id, cw, ch)
        tb = WindowGeometry(left=g.left, top=new_geometry.top, right=g.right,
                            bottom=new_geometry.top + ch, xnum=0, ynum=1)
        self._title_bar_screen.layout(tb)
        set_window_title_bar_render_data(self.os_window_id, self.tab_id, self.id,
                                         self._title_bar_screen.screen, tb.left, tb.top, tb.right, tb.bottom)

    e1._ktb_e1 = True
    e1._ktb_patched = True
    e1._ktb_orig = base
    W.Window.set_geometry = e1
    return json.dumps({'status': 'e1-installed'})
handle_result.no_ui = True
