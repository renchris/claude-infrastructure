#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib resolved at run time; the heredocs are literal scripts
# fixture.sh <dir> <origin> — a build that prints ~1,500 lines with three deprecation warnings inside.
set -euo pipefail; . "$(dirname "$0")/../../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/build.sh" <<'EOF'
#!/bin/bash
# build.sh — compile every module and print the compiler log.
for i in $(seq 1 1500); do
  case "$i" in
    403) echo "src/net/socket.c:88: warning: deprecated call to old_connect(); use net_connect()" ;;
    777) echo "src/io/buffer.c:214: warning: deprecated call to old_flush(); use io_flush()" ;;
    1190) echo "src/ui/window.c:31: warning: deprecated call to old_draw(); use ui_draw()" ;;
    *) echo "CC src/mod$((i % 97))/unit$i.c -> build/unit$i.o [$((i * 37 % 1000)) ms]" ;;
  esac
done
echo "build finished: 1500 units, 3 warnings, 0 errors"
EOF
chmod +x "$FX/build.sh"
fx_commit "chore: build script"
fx_origin
