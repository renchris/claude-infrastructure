#include <sys/attr.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
int main(int argc,char**argv){
 for(int i=1;i<argc;i++){
  struct attrlist al; memset(&al,0,sizeof(al));
  al.bitmapcount=ATTR_BIT_MAP_COUNT;
  al.commonattr=ATTR_CMN_GEN_COUNT|ATTR_CMN_FILEID;
  char buf[256];
  if(getattrlist(argv[i],&al,buf,sizeof(buf),FSOPT_ATTR_CMN_EXTENDED|FSOPT_NOFOLLOW)){printf("%s ERRNO=%d\n",argv[i],errno);continue;}
  uint32_t gc; uint64_t fid;
  memcpy(&gc,buf+4,4);
  memcpy(&fid,buf+8,8);
  printf("%-10s GEN=%u FILEID=%llu (len=%u)\n",argv[i],gc,fid,*(uint32_t*)buf);
 }
 return 0;}
