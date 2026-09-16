import json


def main(args):
    raise SystemExit('no_ui')


def handle_result(args, answer, target_window_id, boss):
    import kitty.window as W
    f = W.Window.set_geometry
    return json.dumps({
        'patched': getattr(f, '_ktb_patched', False),
        'calls': getattr(f, '_ktb_counter', {}).get('n') if getattr(f, '_ktb_patched', False) else None,
        'last': getattr(f, '_ktb_counter', {}).get('last') if getattr(f, '_ktb_patched', False) else None,
    })


handle_result.no_ui = True
