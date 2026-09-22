#include <sys/attr.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
static void probe(const char*path,uint32_t common,uint32_t fork,uint64_t opt,const char*tag){
  struct attrlist al; memset(&al,0,sizeof(al));
  al.bitmapcount=ATTR_BIT_MAP_COUNT; al.commonattr=common; al.forkattr=fork;
  char buf[1024];
  if(getattrlist(path,&al,buf,sizeof(buf),opt)){printf("%-28s ERRNO=%d\n",tag,errno);return;}
  printf("%-28s OK len=%u\n",tag,*(uint32_t*)buf);
}
int main(int argc,char**argv){
  const char*p=argv[1];
  probe(p,ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_FILEID,0,0,"plain fileid");
  probe(p,ATTR_CMN_RETURNED_ATTRS,ATTR_CMN_GEN_COUNT,FSOPT_ATTR_CMN_EXTENDED,"gen only, EXTENDED");
  probe(p,ATTR_CMN_RETURNED_ATTRS,ATTR_CMN_GEN_COUNT|ATTR_CMN_DOCUMENT_ID,FSOPT_ATTR_CMN_EXTENDED,"gen+docid, EXTENDED");
  probe(p,ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_FILEID|ATTR_CMN_MODTIME|ATTR_CMN_FLAGS,ATTR_CMN_GEN_COUNT|ATTR_CMN_DOCUMENT_ID,FSOPT_ATTR_CMN_EXTENDED,"all, EXTENDED");
  probe(p,ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_FILEID,ATTR_CMN_GEN_COUNT,FSOPT_ATTR_CMN_EXTENDED|FSOPT_NOFOLLOW,"gen+NOFOLLOW");
  return 0;
}
