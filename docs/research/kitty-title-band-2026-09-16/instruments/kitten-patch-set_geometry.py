# no_ui kitten: monkeypatch the LIVE kitty Python layer.
import json


def main(args):
    raise SystemExit('no_ui')


def handle_result(args, answer, target_window_id, boss):
    import kitty.window as W
    orig = W.Window.set_geometry
    if getattr(orig, '_ktb_patched', False):
        return json.dumps({'status': 'already-patched'})

    counter = {'n': 0, 'last': None}

    def patched(self, new_geometry):
        counter['n'] += 1
        counter['last'] = (
            getattr(self, 'id', None),
            new_geometry.left, new_geometry.top, new_geometry.right, new_geometry.bottom,
        )
        return orig(self, new_geometry)

    patched._ktb_patched = True
    patched._ktb_counter = counter
    patched._ktb_orig = orig
    W.Window.set_geometry = patched
    return json.dumps({'status': 'patched', 'orig': repr(orig)})


handle_result.no_ui = True
