# Instruments behind perf.md — every number here is re-derivable in one command

    clang -O2 -DGL_SILENCE_DEPRECATION -o glbench  glbench.c  -framework OpenGL
    clang -O2 -DGL_SILENCE_DEPRECATION -o glbench2 glbench2.c -framework OpenGL
    clang -O2 -o ctbench ctbench.m -framework Cocoa -framework CoreText

    ./glbench2 1690 47 2000     # 77-col pane : A=109.873us B=57.319us C=0.011us
    ./glbench2 1118 47 2000     # 51-col pane : A= 87.668us B=38.595us C=0.011us
    ./glbench2 3450 47 2000     # full width  : A=218.412us B=116.302us C=0.011us
    ./glbench  1690 47 2000     # serialized control (glFinish per iter), agrees within 6%
    ./ctbench  1690 47 500      # CoreText re-render: 60.472us/call, cascade block 10.585us

    python3 titlesample.py 60 0.5   # title-change rate over the LIVE RC socket, read-only

kitty.conf + probe.py: the sandbox instance used to measure cell_width/cell_height by TIOCGWINSZ.
    kitty --config kitty.conf --listen-on unix:/private/tmp/ktb-perf/sock \
          --instance-group ktbperf python3 probe.py
    => rows=35 cols=108 xpixel=2376 ypixel=1575 cellw=22.0000 cellh=45.0000

Measured 2026-09-16 on Apple M1 Max, GL_VERSION "4.1 Metal - 89.4", kitty 0.48.2.
glbench2 is the arm to trust: it finishes once per arm, which is how kitty batches its GL work.
