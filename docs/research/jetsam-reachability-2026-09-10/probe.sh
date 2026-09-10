#!/bin/bash
# probe.sh — the instrument behind docs/research/jetsam-reachability-2026-09-10.md.
#
# Every claim in that document is one arm of this script. It is shipped so the finding is
# RE-DERIVABLE rather than quotable: the answers are properties of a kernel and a dyld that ship
# with the OS, both of which move. Run it before trusting a number in the doc.
#
#   bash docs/research/jetsam-reachability-2026-09-10/probe.sh
#
# It writes only into a temp dir, signals nothing it did not spawn, and allocates at most 300 MiB
# for under a second per arm. It does NOT probe system-wide memory pressure — reaching a limit to
# see where it is, is the one thing this repo's panic research says never to do.
set -uo pipefail
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC=$(command -v clang || command -v cc) || { echo "no compiler"; exit 2; }
say() { printf '\n== %s\n' "$*"; }
ok() { printf '   %s\n' "$*"; }

cat > "$D/hog.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int c,char**v){int mb=c>1?atoi(v[1]):300;for(int i=0;i<mb;i++){char*p=malloc(1<<20);if(!p)return 2;memset(p,i&0xff,1<<20);}printf("SURVIVED %d\n",mb);return 0;}
C
cat > "$D/relay.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <spawn.h>
#include <sys/wait.h>
extern char**environ;
int main(int c,char**v){pid_t p;char*a[]={v[1],v[2],NULL};if(posix_spawn(&p,v[1],NULL,NULL,a,environ))return 127;int s=0;waitpid(p,&s,0);
if(WIFSIGNALED(s))printf("GRANDCHILD_SIGNALED %d\n",WTERMSIG(s));else printf("GRANDCHILD_EXITED %d\n",WEXITSTATUS(s));return 0;}
C
cat > "$D/forker.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
int main(void){pid_t p=fork();if(p==0){for(int i=0;i<300;i++){char*q=malloc(1<<20);memset(q,i,1<<20);}printf("FORKCHILD_SURVIVED\n");_exit(0);}int s=0;waitpid(p,&s,0);
if(WIFSIGNALED(s))printf("FORKCHILD_SIGNALED %d\n",WTERMSIG(s));return 0;}
C
cat > "$D/msc.c" <<'C'
/* arm 1: is memorystatus_control reachable unprivileged? */
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/syscall.h>
static long msc(uint32_t c,pid_t p,uint32_t f,void*b,size_t z){return syscall(440,c,p,f,b,z);}
int main(void){
  struct { int32_t a; uint32_t aa; int32_t i; uint32_t ia; } mp = {0,0,0,0};
  struct { int32_t pri; uint64_t ud; } pp = {20,0};
  long r;
  r=msc(8,getpid(),0,&mp,sizeof mp); printf("   GET_MEMLIMIT_PROPERTIES(self) rc=%ld %s\n",r,r<0?strerror(errno):"ok");
  r=msc(1,0,0,NULL,0);               printf("   GET_PRIORITY_LIST           rc=%ld %s\n",r,r<0?strerror(errno):"ok");
  r=msc(2,getpid(),0,&pp,sizeof pp); printf("   SET_PRIORITY_PROPERTIES(self) rc=%ld %s\n",r,r<0?strerror(errno):"ok");
  mp.a=4096; mp.i=4096;
  r=msc(7,getpid(),0,&mp,sizeof mp); printf("   SET_MEMLIMIT_PROPERTIES(self) rc=%ld %s\n",r,r<0?strerror(errno):"ok");
  return 0;}
C
cat > "$D/spawnjet.c" <<'C'
/* <flags> <band> <memMB|-1 for control> <cmd> [arg] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <spawn.h>
#include <dlfcn.h>
#include <sys/wait.h>
extern char**environ;
typedef int(*sj_t)(posix_spawnattr_t*__restrict,short,int,int,int);
int main(int argc,char**argv){
  short fl=(short)strtol(argv[1],NULL,0); int band=atoi(argv[2]); int mb=atoi(argv[3]);
  sj_t sj=(sj_t)dlsym(RTLD_DEFAULT,"posix_spawnattr_setjetsam_ext");
  if(!sj){printf("   posix_spawnattr_setjetsam_ext ABSENT\n");return 3;}
  posix_spawnattr_t a; posix_spawnattr_init(&a);
  if(mb>=0){int r=sj(&a,fl,band,mb,mb); printf("   setjetsam_ext(flags=0x%x band=%d mem=%dMB) rc=%d\n",fl,band,mb,r);}
  pid_t p; int rc=posix_spawn(&p,argv[4],NULL,mb>=0?&a:NULL,&argv[4],environ);
  if(rc){printf("   spawn failed: %s\n",strerror(rc));return 1;}
  int s=0; waitpid(p,&s,0);
  if(WIFSIGNALED(s))printf("   child SIGNALED %d\n",WTERMSIG(s)); else printf("   child EXITED %d\n",WEXITSTATUS(s));
  return 0;}
C
cat > "$D/interpose.c" <<'C'
#include <spawn.h>
#include <stdlib.h>
#include <dlfcn.h>
typedef int(*sj_t)(posix_spawnattr_t*__restrict,short,int,int,int);
struct ip { const void*r; const void*e; };
static int mine(pid_t*p,const char*f,const posix_spawn_file_actions_t*fa,const posix_spawnattr_t*at,char*const av[],char*const ev[]){
  static sj_t sj; if(!sj) sj=(sj_t)dlsym(RTLD_NEXT,"posix_spawnattr_setjetsam_ext");
  const char*m=getenv("PROBE_MEM"); posix_spawnattr_t t; const posix_spawnattr_t*u=at;
  if(sj&&m){ if(at&&*at)t=*at; else posix_spawnattr_init(&t); sj(&t,0x04,30,atoi(m),atoi(m)); u=&t; }
  return posix_spawn(p,f,fa,u,av,ev);
}
__attribute__((used)) static const struct ip ips[] __attribute__((section("__DATA,__interpose"))) = {{(const void*)mine,(const void*)posix_spawn}};
C
for f in hog relay forker msc spawnjet; do "$CC" -O0 -o "$D/$f" "$D/$f.c" 2>/dev/null || { echo "build $f failed"; exit 2; }; done
"$CC" -O0 -dynamiclib -o "$D/lib.dylib" "$D/interpose.c" 2>/dev/null || { echo "build dylib failed"; exit 2; }

say "arm 1 — memorystatus_control on a LIVE pid, unprivileged (the Aug-5 §7.6 'verified lever')"
"$D/msc"
say "arm 2 — posix_spawnattr_setjetsam_ext, FATAL 100 MB, child touches 300 MB"; "$D/spawnjet" 0x04 30 100 "$D/hog" 300
say "arm 3 — CONTROL: identical child, no jetsam attrs";                        "$D/spawnjet" 0 0 -1 "$D/hog" 300
say "arm 4 — SOFT 100 MB (flags=0), same child, no system pressure";            "$D/spawnjet" 0x00 30 100 "$D/hog" 300
say "arm 5 — inheritance by an exec'd grandchild (stamp on the relay only)";    "$D/spawnjet" 0x04 30 100 "$D/relay" "$D/hog"
say "arm 6 — inheritance by a fork()ed child (stamp on the forker only)";       "$D/spawnjet" 0x04 30 100 "$D/forker" x
say "arm 7 — DYLD interposer reaches a grandchild"
PROBE_MEM=100 DYLD_INSERT_LIBRARIES="$D/lib.dylib" "$D/relay" "$D/hog" 300 | sed 's/^/   /'
say "arm 8 — does a system shell carry DYLD_INSERT_LIBRARIES to its children?"
DYLD_INSERT_LIBRARIES="$D/lib.dylib" /bin/sh -c 'printf "   inside /bin/sh: [%s]\n" "$DYLD_INSERT_LIBRARIES"'
DYLD_INSERT_LIBRARIES="$D/lib.dylib" /bin/zsh -fc 'printf "   inside /bin/zsh: [%s]\n" "$DYLD_INSERT_LIBRARIES"'
if command -v node >/dev/null 2>&1; then
  DYLD_INSERT_LIBRARIES="$D/lib.dylib" node -e 'console.log("   inside node:", JSON.stringify(process.env.DYLD_INSERT_LIBRARIES||null))'
else ok "node absent — skipped"; fi
say "arm 9 — what dyld does with an UNLOADABLE inserted library"
DYLD_INSERT_LIBRARIES=/no/such/lib.dylib "$D/hog" 1 >/dev/null 2>&1; ok "missing dylib ⇒ exit $? (134 = SIGABRT: dyld TERMINATES, it does not warn)"
printf 'not a mach-o' > "$D/bad.dylib"
DYLD_INSERT_LIBRARIES="$D/bad.dylib" "$D/relay" "$D/hog" 1 >/dev/null 2>&1; ok "corrupt dylib ⇒ exit $?"
DYLD_INSERT_LIBRARIES="$D/bad.dylib" /usr/bin/true >/dev/null 2>&1; ok "corrupt dylib + SIP-restricted /usr/bin/true ⇒ exit $? (dyld IGNORES it there — why a smoke test must probe an unsigned binary)"
printf '\n== done (%s, %s)\n' "$(uname -srm)" "$(sw_vers -productVersion 2>/dev/null)"
