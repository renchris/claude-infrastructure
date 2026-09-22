#include <sys/resource.h>
#include <stdio.h>
#include <errno.h>
int main(void){
  errno=0;
  int p = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS);
  printf("process policy = %d (errno %d)  [DEFAULT=%d OFF=%d ON=%d]\n", p, errno,
    IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT, IOPOL_MATERIALIZE_DATALESS_FILES_OFF, IOPOL_MATERIALIZE_DATALESS_FILES_ON);
  errno=0;
  int t = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD);
  printf("thread  policy = %d (errno %d)\n", t, errno);
  return 0;
}
