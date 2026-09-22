# C11 — local `getattrlistbulk` walk cost at 10⁵ files (measured 2026-09-22)

**Verdict.** On local APFS the metadata-only full reconcile is sub-second at 100,000 files: T3 alone is fast enough to run at every session start with no watcher. Scope: local APFS only (macOS 15.7.9, Apple Silicon, warm page cache — no cache drop is possible without sudo). The File Provider (`~/Library/CloudStorage`) arm remains unmeasured: no sync domain is signed in on this Mac.

## 1. Fixture

100,000 zero-content `.md` files in 1,000 directories (`tree/d0000..d0999/f000..f099.md`), created with Python immediately before the runs.

## 2. Walker (compiled with `/usr/bin/clang -O2`; `cc` is a shell function on this box)

```c
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
static long files=0, dirs=0;
static void walk(const char *path){
  int fd=open(path,O_RDONLY|O_DIRECTORY); if(fd<0) return; dirs++;
  struct attrlist al; memset(&al,0,sizeof al); al.bitmapcount=ATTR_BIT_MAP_COUNT;
  al.commonattr=ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_NAME|ATTR_CMN_OBJTYPE|ATTR_CMN_MODTIME|ATTR_CMN_FILEID|ATTR_CMN_GEN_COUNT|ATTR_CMN_FLAGS;
  al.fileattr=ATTR_FILE_DATALENGTH;
  char buf[65536];
  for(;;){ int n=getattrlistbulk(fd,&al,buf,sizeof buf,0); if(n<=0) break;
    char *p=buf; for(int i=0;i<n;i++){ char *e=p; uint32_t len=*(uint32_t*)e; char *q=e+4;
      attribute_set_t ret=*(attribute_set_t*)q; q+=sizeof(attribute_set_t);
      char *name=NULL; if(ret.commonattr&ATTR_CMN_NAME){ attrreference_t *ar=(attrreference_t*)q; name=(char*)ar+ar->attr_dataoffset; q+=sizeof(attrreference_t);}
      fsobj_type_t ot=VNON; if(ret.commonattr&ATTR_CMN_OBJTYPE){ ot=*(fsobj_type_t*)q; q+=sizeof(fsobj_type_t);}
      if(ot==VDIR && name){ char sub[4096]; snprintf(sub,sizeof sub,"%s/%s",path,name); walk(sub);} else files++;
      p=e+len; } }
  close(fd);
}
int main(int c,char**v){ walk(v[1]); printf("files=%ld dirs=%ld\n",files,dirs); return 0; }
```

## 3. Results (three consecutive runs, wall-clock around the process)

| run | output | wall |
|---|---|---|
| 1 (first pass after creation) | `files=100000 dirs=1001` | 0.308 s |
| 2 | `files=100000 dirs=1001` | 0.143 s |
| 3 | `files=100000 dirs=1001` | 0.133 s |

Comparison, same tree, Python `os.scandir` + `lstat` per entry: `files=100000 0.30s`.

Refresh-queue re-timing on the same day (§4.5 of the design doc): the printed script, with the `SOURCE-UNREADABLE` branch, over a 1,600-row all-fresh `DEPENDS.tsv` against 200 mirror pages: 0.094 s / 0.116 s / 0.083 s, rc 0; on a two-row fixture (`status: unreadable`, `status: refused`) it printed two `SOURCE-UNREADABLE` rows, rc 1.

## 4. Not measured

Cold cache (no sudo); File Provider volumes (no signed-in domain); whether `ATTR_CMN_GEN_COUNT` is returned on a File Provider tree.
