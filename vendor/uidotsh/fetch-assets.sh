#!/bin/bash
# Mirror assets.ui.sh placeholder assets (licensed local backup).
ROOT=~/Development/worktrees/uidotsh-mirror/vendor/uidotsh/assets
mkdir -p "$ROOT"/{marks,avatars,logos,screenshots,wallpapers}
B=https://assets.ui.sh
ok=0; fail=0
get() { # url, dest
  if curl -fsSL --max-time 30 "$1" -o "$2" 2>/dev/null && [ -s "$2" ]; then
    ok=$((ok+1))
  else
    fail=$((fail+1)); rm -f "$2"; echo "FAIL $1" >> "$ROOT/.failures"
  fi
}
rm -f "$ROOT/.failures"
get "$B/marks/1.svg" "$ROOT/marks/1.svg"
for i in $(seq 1 16); do get "$B/avatars/$i.webp" "$ROOT/avatars/$i.webp"; done
for l in align artifact axiom concise looply orbital pinelabs quirk relay; do
  get "$B/logos/$l.svg" "$ROOT/logos/$l.svg"; done
get "$B/screenshots/1.webp" "$ROOT/screenshots/1.webp"
for c in mauve mist olive stone taupe; do
  get "$B/screenshots/1.webp?color=$c" "$ROOT/screenshots/1-$c.webp"; done
wp() { get "$B/wallpapers/$1.webp?variant=$2" "$ROOT/wallpapers/$1-$2.webp"; }
for v in arctic-glimmer emerald-mist golden-hour-mist midnight-nebula nebula-glow; do wp blend "$v"; done
for v in dark default mauve-dark mauve mist-dark mist sage taupe-dark taupe; do wp haze "$v"; done
for v in arctic-rim calcite-dusk celestial-lead jade-corner obsidian-ember oxide-center sepia-rim; do wp horizon "$v"; done
for v in arctic-fjord basalt-plateau coast dunes forest fossil-cliffs highland-moors hills lake \
         limestone-karst meadow misty-marshland pampas-grassland salt-crust-expanse snow valley weathered-badlands; do wp landscapes "$v"; done
for v in crimson-surge cyan-glacier emerald-glint midnight-violet molten-amber platinum-flow sapphire-flux; do wp silk "$v"; done
echo "ASSET MIRROR DONE ok=$ok fail=$fail"
du -sh "$ROOT"
[ -f "$ROOT/.failures" ] && { echo "--- failures:"; cat "$ROOT/.failures"; } || echo "no failures"
