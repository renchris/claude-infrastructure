// Adversarial re-measurement of perf.md claims 2 and 3, plus the arm the report LACKS.
//
// Report arms:  A = gen+params+texImage2D+delete (today)   B = cached+subimage   C = bind only ("the fix")
// Added arms:
//   A2 = A but with kitty's ACTUAL internal format GL_SRGB_ALPHA (report used GL_SRGB8_ALPHA8)
//   D  = gen+bind+params+delete, NO upload  -> isolates OBJECT CHURN from BANDWIDTH (claim 3)
//   E  = the REAL post-fix steady state of render_a_bar: bind cached tex + bind_program +
//        scissor + blank_canvas(glClear) + viewport + draw_graphics quad + viewport +
//        draw_rounded_rect quad.  This is what "the fix" actually costs. Arm C models NONE of it.
//   F  = the REAL pre-fix steady state: E plus the gen/upload/delete of arm A.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>
static double now_ms(void){static mach_timebase_info_data_t tb;if(!tb.denom)mach_timebase_info(&tb);
    return (double)mach_absolute_time()*tb.numer/tb.denom/1e6;}
static const char*VS="#version 330 core\nuniform vec4 dest_rect;\nout vec2 uv;\n"
 "const vec2 c[4]=vec2[4](vec2(1,1),vec2(1,-1),vec2(-1,-1),vec2(-1,1));\n"
 "void main(){vec2 p=c[gl_VertexID];uv=(p+1.0)*0.5;"
 "gl_Position=vec4(mix(dest_rect.x,dest_rect.z,uv.x),mix(dest_rect.y,dest_rect.w,uv.y),0,1);}\n";
static const char*FS="#version 330 core\nuniform sampler2D tex;uniform vec4 src_rect;uniform float extra_alpha;\n"
 "in vec2 uv;out vec4 c;void main(){c=texture(tex,uv)*extra_alpha*src_rect.x;}\n";
static const char*FS2="#version 330 core\nuniform vec4 tint;in vec2 uv;out vec4 c;void main(){c=tint;}\n";
static GLuint mk(const char*vs,const char*fs){GLuint v=glCreateShader(GL_VERTEX_SHADER),f=glCreateShader(GL_FRAGMENT_SHADER),p=glCreateProgram();
 glShaderSource(v,1,&vs,0);glCompileShader(v);glShaderSource(f,1,&fs,0);glCompileShader(f);
 GLint ok;glGetShaderiv(f,GL_COMPILE_STATUS,&ok);if(!ok){char l[2048];glGetShaderInfoLog(f,2048,0,l);fprintf(stderr,"FS:%s\n",l);exit(2);}
 glGetShaderiv(v,GL_COMPILE_STATUS,&ok);if(!ok){char l[2048];glGetShaderInfoLog(v,2048,0,l);fprintf(stderr,"VS:%s\n",l);exit(2);}
 glAttachShader(p,v);glAttachShader(p,f);glLinkProgram(p);
 glGetProgramiv(p,GL_LINK_STATUS,&ok);if(!ok){char l[2048];glGetProgramInfoLog(p,2048,0,l);fprintf(stderr,"LINK:%s\n",l);exit(2);}
 return p;}
static void params(void){glPixelStorei(GL_UNPACK_ALIGNMENT,1);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
 glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);}
int main(int argc,char**argv){
    int W=argc>1?atoi(argv[1]):1690,H=argc>2?atoi(argv[2]):47,N=argc>3?atoi(argv[3]):2000;
    int FBW=argc>4?atoi(argv[4]):1694, FBH=argc>5?atoi(argv[5]):1575;
    CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,kCGLPFAColorSize,(CGLPixelFormatAttribute)24,(CGLPixelFormatAttribute)0};
    CGLPixelFormatObj pix;GLint np;CGLChoosePixelFormat(attrs,&pix,&np);
    CGLContextObj ctx;CGLCreateContext(pix,NULL,&ctx);CGLSetCurrentContext(ctx);
    printf("# GL_RENDERER=%s  GL_VERSION=%s\n",glGetString(GL_RENDERER),glGetString(GL_VERSION));
    unsigned char*buf=malloc((size_t)W*H*4);for(size_t i=0;i<(size_t)W*H*4;i++)buf[i]=(unsigned char)(i&0xff);
    // offscreen target so the draws are real
    GLuint fbtex,fbo;glGenTextures(1,&fbtex);glBindTexture(GL_TEXTURE_2D,fbtex);
    glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB8_ALPHA8,FBW,FBH,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
    glGenFramebuffers(1,&fbo);glBindFramebuffer(GL_FRAMEBUFFER,fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,fbtex,0);
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE){fprintf(stderr,"FBO incomplete\n");return 3;}
    GLuint vao;glGenVertexArrays(1,&vao);glBindVertexArray(vao);
    GLuint pg=mk(VS,FS), pr=mk(VS,FS2);
    GLint u_dest=glGetUniformLocation(pg,"dest_rect"),u_src=glGetUniformLocation(pg,"src_rect"),
          u_ea=glGetUniformLocation(pg,"extra_alpha"),u_tex=glGetUniformLocation(pg,"tex");
    GLint r_dest=glGetUniformLocation(pr,"dest_rect"),r_tint=glGetUniformLocation(pr,"tint");
    printf("# %dx%d = %zu B  N=%d  fbo=%dx%d  pipelined (one glFinish per arm)\n",W,H,(size_t)W*H*4,N,FBW,FBH);
    double t,a,a2,b,c,d,e,f; GLuint tid;
    // A : today, report's format
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){glGenTextures(1,&tid);glBindTexture(GL_TEXTURE_2D,tid);params();
      glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB8_ALPHA8,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);glDeleteTextures(1,&tid);}
    glFinish();a=now_ms()-t;
    // A2: today, kitty's ACTUAL unsized format
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){glGenTextures(1,&tid);glBindTexture(GL_TEXTURE_2D,tid);params();
      glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB_ALPHA,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);glDeleteTextures(1,&tid);}
    glFinish();a2=now_ms()-t;
    // D : object churn only, NO upload
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){glGenTextures(1,&tid);glBindTexture(GL_TEXTURE_2D,tid);params();glDeleteTextures(1,&tid);}
    glFinish();d=now_ms()-t;
    GLuint tb;glGenTextures(1,&tb);glBindTexture(GL_TEXTURE_2D,tb);params();
    glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB_ALPHA,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);
    // B : cached + subimage
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){glBindTexture(GL_TEXTURE_2D,tb);glTexSubImage2D(GL_TEXTURE_2D,0,0,0,W,H,GL_RGBA,GL_UNSIGNED_BYTE,buf);}
    glFinish();b=now_ms()-t;
    // C : report's "fix" = bind only
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){glBindTexture(GL_TEXTURE_2D,tb);}
    glFinish();c=now_ms()-t;
    // E : the REAL post-fix steady state of render_a_bar
    glUseProgram(pg);glUniform1i(u_tex,0);
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){
      glBindTexture(GL_TEXTURE_2D,tb);
      glUseProgram(pg);                                        // bind_program(GRAPHICS_PROGRAM)
      glEnable(GL_SCISSOR_TEST);glScissor(0,FBH-(H+4),FBW,H+4);// enable_scissor_using_top_left_origin
      glClearColor(0.1f,0.1f,0.1f,1.f);glClear(GL_COLOR_BUFFER_BIT); // blank_canvas
      glDisable(GL_SCISSOR_TEST);
      glViewport(2,FBH-(H+2),W,H);                             // save_viewport_using_top_left_origin
      glUseProgram(pg);glUniform1f(u_ea,1.f);glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D,tb);
      glUniform4f(u_src,0,0,1,1);glUniform4f(u_dest,-1,1,1,-1);
      glDrawArrays(GL_TRIANGLE_FAN,0,4);                       // draw_quad
      glViewport(0,0,FBW,FBH);                                 // restore_viewport
      glViewport(0,FBH-(H+4),FBW,H+4);glUseProgram(pr);glUniform4f(r_dest,-1,1,1,-1);glUniform4f(r_tint,1,1,1,1);
      glDrawArrays(GL_TRIANGLE_FAN,0,4);                       // draw_rounded_rect
    }
    glFinish();e=now_ms()-t;
    // F : the REAL pre-fix steady state = E + today's texture churn
    glFinish();t=now_ms();
    for(int i=0;i<N;i++){
      glGenTextures(1,&tid);glBindTexture(GL_TEXTURE_2D,tid);params();
      glTexImage2D(GL_TEXTURE_2D,0,GL_SRGB_ALPHA,W,H,0,GL_RGBA,GL_UNSIGNED_BYTE,buf);
      glUseProgram(pg);
      glEnable(GL_SCISSOR_TEST);glScissor(0,FBH-(H+4),FBW,H+4);
      glClearColor(0.1f,0.1f,0.1f,1.f);glClear(GL_COLOR_BUFFER_BIT);
      glDisable(GL_SCISSOR_TEST);
      glViewport(2,FBH-(H+2),W,H);
      glUseProgram(pg);glUniform1f(u_ea,1.f);glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D,tid);
      glUniform4f(u_src,0,0,1,1);glUniform4f(u_dest,-1,1,1,-1);
      glDrawArrays(GL_TRIANGLE_FAN,0,4);
      glViewport(0,0,FBW,FBH);
      glDeleteTextures(1,&tid);                                // free_texture AFTER the draw
      glViewport(0,FBH-(H+4),FBW,H+4);glUseProgram(pr);glUniform4f(r_dest,-1,1,1,-1);glUniform4f(r_tint,1,1,1,1);
      glDrawArrays(GL_TRIANGLE_FAN,0,4);
    }
    glFinish();f=now_ms()-t;
#define P(n,v) printf("%-46s %9.3f ms %10.4f us/call\n",n,v,v*1000/N)
    P("A  gen+params+texImage(SRGB8_ALPHA8)+del",a);
    P("A2 gen+params+texImage(SRGB_ALPHA)+del  ",a2);
    P("D  gen+bind+params+del, NO UPLOAD       ",d);
    P("B  cached tex + glTexSubImage2D         ",b);
    P("C  cached tex, BIND ONLY (report's fix) ",c);
    P("E  REAL post-fix render_a_bar steady st.",e);
    P("F  REAL pre-fix render_a_bar steady st. ",f);
    printf("# glGetError=%d\n",glGetError());
    return 0;}
