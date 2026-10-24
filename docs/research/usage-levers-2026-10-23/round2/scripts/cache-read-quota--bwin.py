import mmap, sys
path=sys.argv[1]; off=int(sys.argv[2]); before=int(sys.argv[3]); after=int(sys.argv[4])
with open(path,'rb') as f:
    m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ)
    print(m[max(0,off-before):off+after].decode('utf-8','replace'))
