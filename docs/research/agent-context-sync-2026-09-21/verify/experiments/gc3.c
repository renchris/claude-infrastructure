#include <sys/attr.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
int main(int argc,char**argv){
 for(int i=1;i<argc;i++){
  struct attrlist al; memset(&al,0,sizeof(al));
  al.bitmapcount=ATTR_BIT_MAP_COUNT;
  al.commonattr=ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_FILEID|ATTR_CMN_MODTIME|ATTR_CMN_FLAGS|ATTR_CMN_GEN_COUNT|ATTR_CMN_DOCUMENT_ID;
  char buf[1024];
  if(getattrlist(argv[i],&al,buf,sizeof(buf),FSOPT_ATTR_CMN_EXTENDED|FSOPT_NOFOLLOW|FSOPT_PACK_INVAL_ATTRS)){printf("%s ERRNO=%d\n",argv[i],errno);continue;}
  char*p=buf+sizeof(uint32_t);
  attribute_set_t ret; memcpy(&ret,p,sizeof(ret)); p+=sizeof(ret);
  uint64_t fid=0; struct timespec mt={0,0}; uint32_t fl=0,gc=0,did=0;
  memcpy(&mt,p,sizeof(mt));p+=sizeof(mt);
  memcpy(&fl,p,4);p+=4;
  memcpy(&gc,p,4);p+=4;
  memcpy(&did,p,4);p+=4;
  p+=4; /* pad to 8-byte align for fileid */
  memcpy(&fid,p,8);p+=8;
  printf("%-10s ret_common=0x%x fileid=%llu mtime=%ld.%09ld flags=0x%x GEN=%u DOCID=%u dataless=%d\n",
    argv[i],ret.commonattr,fid,(long)mt.tv_sec,(long)mt.tv_nsec,fl,gc,did,(fl&SF_DATALESS)?1:0);
 }
 return 0;}
