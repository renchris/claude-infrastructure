#!/usr/bin/env python3
# Print printable bytes of the binary at [off-before, off+after].
import mmap, sys, re
path=sys.argv[1]; off=int(sys.argv[2]); b=int(sys.argv[3]); a=int(sys.argv[4])
with open(path,'rb') as f:
    mm=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
    print(re.sub(rb"[^\x20-\x7e\n]", b".", mm[max(0,off-b):off+a]).decode('ascii'))
