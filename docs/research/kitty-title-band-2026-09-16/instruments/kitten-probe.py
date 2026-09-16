# no_ui probe kitten: proves handle_result runs INSIDE the kitty process.
import os, sys, json


def main(args):
    raise SystemExit('this kitten is no_ui; main() must never run')


def handle_result(args, answer, target_window_id, boss):
    import kitty.window as W
    import kitty.fast_data_types as fdt
    out = {
        'kitten_os_getpid': os.getpid(),
        'sys_executable': sys.executable,
        'boss_class': type(boss).__module__ + '.' + type(boss).__name__,
        'boss_id': id(boss),
        'n_os_windows': len(list(boss.os_window_map.keys())),
        'n_windows': len(list(boss.all_windows)),
        'target_window_id': target_window_id,
        'args': list(args),
        'Window_set_geometry_qualname': W.Window.set_geometry.__qualname__,
        'Window_set_geometry_module': W.Window.set_geometry.__module__,
        'has_fast_data_types': hasattr(fdt, 'set_window_render_data'),
        'ALREADY_PATCHED': hasattr(W.Window.set_geometry, '_ktb_patched'),
    }
    return json.dumps(out)


handle_result.no_ui = True
