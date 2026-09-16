// Measures the exact GL sequence kitty's render_a_bar runs, on THIS box.
// Arms, one variable each:
//   A  = today's render_a_bar: glGenTextures + 4x glTexParameteri + glTexImage2D + glDeleteTextures
//   B  = cached texture, re-upload every frame: glTexSubImage2D on a persistent texture
//   C  = cached texture, NOTHING uploaded (the steady state after the fix): just bind
//   Z  = control: the loop + glFinish and no GL work at all
// glFinish() per iteration so we time the driver's work, not command queueing.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>

static double now_ms(void) {
    static mach_timebase_info_data_t tb; if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

int main(int argc, char **argv) {
    int W = argc > 1 ? atoi(argv[1]) : 1690;
    int H = argc > 2 ? atoi(argv[2]) : 47;
    int N = argc > 3 ? atoi(argv[3]) : 2000;

    CGLPixelFormatAttribute attrs[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated, kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj pix; GLint npix;
    if (CGLChoosePixelFormat(attrs, &pix, &npix) != kCGLNoError) { fprintf(stderr,"no pixfmt\n"); return 1; }
    CGLContextObj ctx;
    if (CGLCreateContext(pix, NULL, &ctx) != kCGLNoError) { fprintf(stderr,"no ctx\n"); return 1; }
    CGLSetCurrentContext(ctx);
    printf("# GL_RENDERER=%s\n# GL_VERSION=%s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    printf("# bar %dx%d RGBA = %zu bytes, N=%d iterations per arm\n", W, H, (size_t)W*H*4, N);

    unsigned char *buf = malloc((size_t)W*H*4);
    for (size_t i = 0; i < (size_t)W*H*4; i++) buf[i] = (unsigned char)(i & 0xff);

    double t;
    // Z: control
    glFinish();
    t = now_ms();
    for (int i = 0; i < N; i++) { glFinish(); }
    double z = now_ms() - t;

    // A: today's path
    glFinish();
    t = now_ms();
    for (int i = 0; i < N; i++) {
        GLuint tid; glGenTextures(1, &tid); glBindTexture(GL_TEXTURE_2D, tid);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf);
        glFinish();
        glDeleteTextures(1, &tid);
    }
    double a = now_ms() - t;

    // B: persistent texture, sub-upload every frame
    GLuint tb_; glGenTextures(1, &tb_); glBindTexture(GL_TEXTURE_2D, tb_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    glFinish();
    t = now_ms();
    for (int i = 0; i < N; i++) {
        glBindTexture(GL_TEXTURE_2D, tb_);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, buf);
        glFinish();
    }
    double b = now_ms() - t;

    // C: cached, nothing uploaded (post-fix steady state)
    glFinish();
    t = now_ms();
    for (int i = 0; i < N; i++) { glBindTexture(GL_TEXTURE_2D, tb_); glFinish(); }
    double c = now_ms() - t;

    GLenum e = glGetError();
    printf("Z control (glFinish only)      : %8.3f ms total  %8.4f us/iter\n", z, z*1000/N);
    printf("A gen+texImage+delete (TODAY)  : %8.3f ms total  %8.4f us/iter  (net %.4f us)\n", a, a*1000/N, (a-z)*1000/N);
    printf("B cached tex, subimage each fr : %8.3f ms total  %8.4f us/iter  (net %.4f us)\n", b, b*1000/N, (b-z)*1000/N);
    printf("C cached tex, no upload (FIX)  : %8.3f ms total  %8.4f us/iter  (net %.4f us)\n", c, c*1000/N, (c-z)*1000/N);
    printf("# glGetError=%d\n", e);
    return 0;
}
