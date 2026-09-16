# kitty watcher: monkeypatch Window.set_geometry for a ZERO-ROW title band.
import traceback
LOG = '/private/tmp/ktb-fallback/patch2.log'
def log(*a):
    with open(LOG, 'a') as f:
        f.write(' '.join(str(x) for x in a) + '\n')

def on_load(boss, data):
    try:
        import weakref
        import kitty.window as kw
        from kitty.types import WindowGeometry

        orig = kw.Window.set_geometry
        if getattr(kw.Window, '_ktb_patched_v2', False):
            log('already patched v2'); return

        def patched(self, new_geometry):
            if self.destroyed:
                return
            opts = kw.get_options()
            position = opts.window_title_bar
            show_tb = self.show_title_bar and new_geometry.ynum > 1

            render_ynum = new_geometry.ynum
            render_top = new_geometry.top
            render_bottom = new_geometry.bottom
            if show_tb:
                cell_width, cell_height = kw.cell_size_for_window(self.os_window_id)
                if position == 'top':
                    tb_top = new_geometry.top
                    tb_bottom = new_geometry.top + cell_height
                else:
                    tb_top = new_geometry.bottom - cell_height
                    tb_bottom = new_geometry.bottom

            if self.needs_layout or new_geometry.xnum != self.screen.columns or render_ynum != self.screen.lines:
                self.screen.resize(max(0, render_ynum), max(0, new_geometry.xnum))
                self.needs_layout = False
                kw.call_watchers(weakref.ref(self), 'on_resize', {'old_geometry': self.geometry, 'new_geometry': new_geometry})
            current_pty_size = (self.screen.lines, self.screen.columns,
                                max(0, new_geometry.right - new_geometry.left),
                                max(0, render_bottom - render_top))
            update_ime_position = False
            if current_pty_size != self.last_reported_pty_size:
                if self._pause_resize_notifications_to_child is None:
                    update_ime_position = self.resize_child(current_pty_size)
                else:
                    self._pause_resize_notifications_to_child = current_pty_size
            else:
                kw.mark_os_window_dirty(self.os_window_id)

            self.geometry = g = new_geometry
            kw.set_window_render_data(
                self.os_window_id, self.tab_id, self.id, self.screen,
                g.left, render_top, g.right, render_bottom,
                g.spaces.left, g.spaces.top, g.spaces.right, g.spaces.bottom)
            self.update_effective_padding()
            if show_tb and kw.get_options().window_title_bar == 'top':
                from kitty.fast_data_types import set_window_padding as _swp
                _swp(self.os_window_id, self.tab_id, self.id,
                     int(self.effective_padding('left')),
                     int(self.effective_padding('top')) - cell_height,
                     int(self.effective_padding('right')),
                     int(self.effective_padding('bottom')))
                log('padding pushed top=', int(self.effective_padding('top')) - cell_height)

            if show_tb:
                if self._title_bar_screen is None:
                    from kitty.window_title_bar import WindowTitleBarScreen
                    self._title_bar_screen = WindowTitleBarScreen(self.os_window_id, cell_width, cell_height)
                tb_geom = WindowGeometry(left=g.left, top=tb_top, right=g.right, bottom=tb_bottom, xnum=0, ynum=1)
                self._title_bar_screen.layout(tb_geom)
                kw.set_window_title_bar_render_data(
                    self.os_window_id, self.tab_id, self.id, self._title_bar_screen.screen,
                    tb_geom.left, tb_geom.top, tb_geom.right, tb_geom.bottom)
            elif self._title_bar_screen is not None:
                kw.set_window_title_bar_render_data(
                    self.os_window_id, self.tab_id, self.id, self._title_bar_screen.screen, 0, 0, 0, 0)
                self._title_bar_screen = None

            if update_ime_position:
                kw.update_ime_position_for_window(self.id, True)

        kw.Window.set_geometry = patched
        kw.Window._ktb_patched_v2 = True
        kw.Window._ktb_orig_set_geometry = orig
        log('PATCHED OK')
        # force a relayout of every tab
        for osw in boss.os_window_map.values():
            for tab in osw:
                tab.relayout()
        log('relayout done')
    except Exception:
        log('FAIL', traceback.format_exc())
