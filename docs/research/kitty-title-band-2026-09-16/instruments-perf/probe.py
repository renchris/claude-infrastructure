import fcntl, termios, struct, sys, os, time
buf = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b'\0'*8)
rows, cols, xp, yp = struct.unpack('HHHH', buf)
with open('/private/tmp/ktb-perf/winsize.txt','w') as f:
    f.write("rows=%d cols=%d xpixel=%d ypixel=%d cellw=%.4f cellh=%.4f\n" % (rows, cols, xp, yp, xp/cols, yp/rows))
time.sleep(600)
