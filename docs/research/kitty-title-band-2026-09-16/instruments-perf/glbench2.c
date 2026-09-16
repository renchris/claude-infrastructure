// Throughput arms: no per-iteration glFinish. kitty pipelines its GL work and finishes once
// per frame at swap, so a per-iteration glFinish measures LATENCY, not the real per-frame cost.
// These arms finish ONCE at the end, which is the honest throughput number.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_time.h>
static double now_ms(void){static mach_timebase_info_data_t tb;if(!tb.denom)mach_timebase_info(&tb);
    return (double)mach_absolute_time()*tb.numer/tb.denom/1e6;}
int main(int argc,char**argv){
    int W=argc>1?atoi(argv[1]):1690, H=argc>2?atoi(argv[2]):47, N=argc>3?atoi(argv[3]):2000;
    CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,kCGLPFAColorSize,(CGLPixelFormatAttribute)24,(CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pix;GLint np;CGLChoosePixelFormat(attrs,&pix,&np);
    CGLContextObj ctx;CGLCreateContext(pix,NULL,&ctx);CGLSetCurrentContext(ctx);
    unsigned char*buf=malloc((size_t)W*H*4);for(size_t i=0;i<(size_t)W*H*4;i++)buf[i]=(unsigned char)(i&0xff);
    printf("# %dx%d = %zu B, N=%d, pipelined (one glFinish at end)\n",W,H,(size_t)W*H*4,N);
    double t;
    glFinish(); t=now_ms();
    for(int i=0;i<N;i++){GLuint tid;glGenTextures(1,&tid);glBindTexture(GL_TEXTURE_2D,tid);
        glPixelStorei(GL_UNPACK_ALIGNMENT,1);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB8_ALPHA8,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);
        glDeleteTextures(1,&tid);}
    glFinish(); double a=now_ms()-t;
    GLuint tb_;glGenTextures(1,&tb_);glBindTexture(GL_TEXTURE_2D,tb_);
    glPixelStorei(GL_UNPACK_ALIGNMENT,1);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB8_ALPHA8,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);
    glFinish(); t=now_ms();
    for(int i=0;i<N;i++){glBindTexture(GL_TEXTURE_2D,tb_);
        glTexSubImage2D(GL_TEXTURE_2D,0,0,0,W,H,GL_RGBA,GL_UNSIGNED_BYTE,buf);}
    glFinish(); double b=now_ms()-t;
    glFinish(); t=now_ms();
    for(int i=0;i<N;i++){glBindTexture(GL_TEXTURE_2D,tb_);}
    glFinish(); double c=now_ms()-t;
    printf("A gen+texImage+delete (TODAY) : %8.3f ms  %8.3f us/call\n",a,a*1000/N);
    printf("B cached tex + subimage       : %8.3f ms  %8.3f us/call\n",b,b*1000/N);
    printf("C cached tex, bind only (FIX) : %8.3f ms  %8.3f us/call\n",c,c*1000/N);
    printf("# glGetError=%d\n",glGetError());
    return 0;}
