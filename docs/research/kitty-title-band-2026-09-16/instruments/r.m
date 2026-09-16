// Faithful replica of kitty/core_text.m cocoa_render_line_of_text + ensure_ui_font (v0.48.2),
// minus the nerd-font cascade (absent here; it only adds fallback glyphs, not the primary face).
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>
typedef uint32_t color_type;
static CTFontRef system_ui_font = nil;
static double g_weight = 0.0; static bool g_use_weight = false;

static bool ensure_ui_font(size_t in_height) {
    static size_t for_height = 0; static double for_w = -2;
    if (system_ui_font) { if (for_height == in_height && for_w == g_weight) return true; CFRelease(system_ui_font); }
    if (g_use_weight) system_ui_font = (CTFontRef)CFRetain((CFTypeRef)[NSFont systemFontOfSize:[NSFont systemFontSize] weight:(CGFloat)g_weight]);
    else system_ui_font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL);
    if (!system_ui_font) return false;
    CGFloat line_height = MAX(1, floor(CTFontGetAscent(system_ui_font) + CTFontGetDescent(system_ui_font) + MAX(0, CTFontGetLeading(system_ui_font)) + 0.5));
    CGFloat pts_per_px = CTFontGetSize(system_ui_font) / line_height;
    CGFloat desired_size = in_height * pts_per_px;
    if (desired_size != CTFontGetSize(system_ui_font)) {
        CTFontRef sized = CTFontCreateCopyWithAttributes(system_ui_font, desired_size, NULL, NULL);
        CFRelease(system_ui_font); system_ui_font = sized; if (!system_ui_font) return false;
    }
    for_height = in_height; for_w = g_weight; return true;
}

static bool render(const char *text, color_type fg, color_type bg, uint8_t *out, size_t width, size_t height, double baseline_override, bool use_override) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB(); if (!cs) return false;
    CGContextRef ctx = CGBitmapContextCreate(out, width, height, 8, 4*width, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(cs); if (!ctx) return false;
    if (!ensure_ui_font(height)) return false;
    CGContextSetShouldAntialias(ctx, true); CGContextSetShouldSmoothFonts(ctx, true);
    CGContextClearRect(ctx, CGRectMake(0,0,width,height));
    CGContextSetRGBFillColor(ctx, ((bg>>16)&0xff)/255.f, ((bg>>8)&0xff)/255.f, (bg&0xff)/255.f, ((bg>>24)&0xff)/255.f);
    CGContextFillRect(ctx, CGRectMake(0,0,width,height));
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetRGBFillColor(ctx, ((fg>>16)&0xff)/255.f, ((fg>>8)&0xff)/255.f, (fg&0xff)/255.f, 1.f);
    NSColor *color = [NSColor colorWithCalibratedRed:((fg>>16)&0xff)/255.f green:((fg>>8)&0xff)/255.f blue:(fg&0xff)/255.f alpha:1.0];
    NSAttributedString *str = [[NSAttributedString alloc] initWithString:@(text) attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)system_ui_font, NSForegroundColorAttributeName: color}];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)str);
    CGFloat a,d,l; CTLineGetTypographicBounds(line,&a,&d,&l);
    double y = use_override ? baseline_override : d;
    CGContextSetTextPosition(ctx, 0, y);
    CTLineDraw(line, ctx);
    CFRelease(line); CGContextRelease(ctx); [str release];
    return true;
}

// report which rows (top-origin) carry FG ink, given a known bg
static void ink_rows(uint8_t *buf, size_t w, size_t h, color_type bg) {
    uint8_t br=(bg>>16)&0xff, bgc=(bg>>8)&0xff, bb=bg&0xff;
    int first=-1,last=-1; size_t firstx=w;
    for (size_t row=0; row<h; row++) {
        bool any=false;
        for (size_t x=0;x<w;x++){ uint8_t *p=buf+((h-1-row)*w+x)*4; // CG origin bottom-left -> row 0 = top
            if (abs((int)p[0]-br)>8 || abs((int)p[1]-bgc)>8 || abs((int)p[2]-bb)>8) { any=true; if (x<firstx) firstx=x; break; } }
        if (any) { if (first<0) first=(int)row; last=(int)row; }
    }
    printf("     ink rows (top-origin): %d..%d of %zu   -> top gap %d px, bottom gap %d px, ink/band %.3f\n",
        first, last, h, first, (int)h-1-last, (double)(last-first+1)/h);
    // leftmost ink column, scanning all rows
    size_t lx = w;
    for (size_t row=0; row<h; row++) for (size_t x=0;x<lx;x++){ uint8_t *p=buf+((h-1-row)*w+x)*4;
        if (abs((int)p[0]-br)>8 || abs((int)p[1]-bgc)>8 || abs((int)p[2]-bb)>8) { if (x<lx) lx=x; break; } }
    printf("     leftmost ink column: %zu px\n", lx);
}

int main(int argc,char**argv){@autoreleasepool{
    const size_t W=900;
    color_type fg=0xffffffff, bg=0xff2f62d8; // active_fg #ffffff on active_bg #2f62d8
    const char *titles[] = {"  claude-infrastructure", " ÅÉÎÕÜ gjpqy", " ~/Development — main"};
    size_t heights[] = {47};
    for (unsigned wi=0; wi<2; wi++) {
        g_use_weight = (wi==1); g_weight = 0.30; // Semibold on the 2nd pass
        if (system_ui_font) { CFRelease(system_ui_font); system_ui_font=nil; }
        printf("== %s ==\n", wi? "Semibold (NSFontWeightSemibold 0.30)" : "Regular (kCTFontUIFontSystem, SHIPPED)");
        for (unsigned hi=0; hi<sizeof(heights)/sizeof(heights[0]); hi++){
            size_t H=heights[hi];
            for (unsigned ti=0;ti<3;ti++){
                uint8_t *buf=calloc(W*H,4);
                if (!render(titles[ti], fg, bg, buf, W, H, 0, false)) { printf("render failed\n"); return 1; }
                printf("   H=%zu  %-26s\n", H, titles[ti]);
                ink_rows(buf,W,H,bg);
                free(buf);
            }
        }
    }
    // Now the DECOUPLED variant: font sized for a smaller line box, baseline centred in the band.
    printf("\n== DECOUPLED: font sized to 0.74*band, baseline centred (proposed cure) ==\n");
    g_use_weight=true; g_weight=0.30;
    for (double frac=0.70; frac<=0.86; frac+=0.04) {
        size_t H=47; size_t fh=(size_t)lround(H*frac);
        if (system_ui_font){CFRelease(system_ui_font);system_ui_font=nil;}
        ensure_ui_font(fh);
        CGFloat a=CTFontGetAscent(system_ui_font), d=CTFontGetDescent(system_ui_font);
        double baseline=(H-(a+d))/2.0+d;
        for (unsigned ti=1;ti<2;ti++){ // worst case only
            uint8_t *buf=calloc(W*H,4);
            CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx=CGBitmapContextCreate(buf,W,H,8,4*W,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
            CGColorSpaceRelease(cs);
            CGContextSetShouldAntialias(ctx,true); CGContextSetShouldSmoothFonts(ctx,true);
            CGContextSetRGBFillColor(ctx,((bg>>16)&0xff)/255.f,((bg>>8)&0xff)/255.f,(bg&0xff)/255.f,1.f);
            CGContextFillRect(ctx,CGRectMake(0,0,W,H));
            CGContextSetTextMatrix(ctx,CGAffineTransformIdentity);
            NSColor *c=[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1];
            NSAttributedString *s=[[NSAttributedString alloc] initWithString:@(titles[ti]) attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)system_ui_font, NSForegroundColorAttributeName:c}];
            CTLineRef ln=CTLineCreateWithAttributedString((CFAttributedStringRef)s);
            CGContextSetTextPosition(ctx,0,baseline); CTLineDraw(ln,ctx);
            CFRelease(ln); CGContextRelease(ctx); [s release];
            printf("   frac=%.2f fontbox=%zupx em=%.2f baseline=%.2f\n", frac, fh, CTFontGetSize(system_ui_font), baseline);
            ink_rows(buf,W,H,bg);
            free(buf);
        }
    }
    return 0;
}}
