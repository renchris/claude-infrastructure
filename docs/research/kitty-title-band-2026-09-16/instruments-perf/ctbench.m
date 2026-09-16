// Replica of kitty's cocoa_render_line_of_text (482:kitty/core_text.m:945-999) so the CPU-side
// cost of one band re-render can be priced without building kitty.
// Arm 1 = the whole function as kitty writes it (incl. the per-call nerd-font cascade copy).
// Arm 2 = the same without the cascade copy, to attribute that block.
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <mach/mach_time.h>
static double now_ms(void){static mach_timebase_info_data_t tb;if(!tb.denom)mach_timebase_info(&tb);
    return (double)mach_absolute_time()*tb.numer/tb.denom/1e6;}
static CTFontRef ui_font=NULL; static size_t for_height=0;
static bool ensure_ui_font(size_t h){
    if(ui_font){ if(for_height==h) return true; CFRelease(ui_font);} 
    ui_font=CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,0.f,NULL);
    if(!ui_font) return false;
    CGFloat lh=MAX(1,floor(CTFontGetAscent(ui_font)+CTFontGetDescent(ui_font)+MAX(0,CTFontGetLeading(ui_font))+0.5));
    CGFloat ppp=CTFontGetSize(ui_font)/lh; CGFloat ds=h*ppp;
    if(ds!=CTFontGetSize(ui_font)){CTFontRef s=CTFontCreateCopyWithAttributes(ui_font,ds,NULL,NULL);CFRelease(ui_font);ui_font=s;if(!ui_font)return false;}
    for_height=h; return true;}
static CTFontDescriptorRef nerd=NULL;
static bool render(const char*text,uint8_t*out,size_t W,size_t H,bool with_cascade){
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB(); if(!cs) return false;
    CGContextRef ctx=CGBitmapContextCreate(out,W,H,8,4*W,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(cs); if(!ctx) return false;
    if(!ensure_ui_font(H)) return false;
    CGContextSetShouldAntialias(ctx,true); CGContextSetShouldSmoothFonts(ctx,true);
    CGContextClearRect(ctx,CGRectMake(0,0,W,H));
    CGContextSetRGBFillColor(ctx,0.18f,0.38f,0.85f,1.f); CGContextFillRect(ctx,CGRectMake(0,0,W,H));
    CGContextSetTextDrawingMode(ctx,kCGTextFill);
    CGContextSetTextMatrix(ctx,CGAffineTransformIdentity);
    CGContextSetRGBFillColor(ctx,1,1,1,1); CGContextSetRGBStrokeColor(ctx,1,1,1,1);
    NSColor*color=[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1.0];
    CTFontRef rf=ui_font; CTFontRef fwn=NULL;
    if(with_cascade && nerd){
        CFArrayRef cl=CFArrayCreate(kCFAllocatorDefault,(const void*[]){nerd},1,&kCFTypeArrayCallBacks);
        if(cl){CFDictionaryRef at=CFDictionaryCreate(kCFAllocatorDefault,(const void*[]){kCTFontCascadeListAttribute},
                (const void*[]){cl},1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
            CFRelease(cl);
            if(at){CTFontDescriptorRef nd=CTFontDescriptorCreateWithAttributes(at);CFRelease(at);
                if(nd){fwn=CTFontCreateCopyWithAttributes(ui_font,0,NULL,nd);CFRelease(nd);if(fwn)rf=fwn;}}}}
    NSAttributedString*s=[[NSAttributedString alloc] initWithString:@(text)
        attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)rf, NSForegroundColorAttributeName:color}];
    if(fwn)CFRelease(fwn);
    if(!s){CGContextRelease(ctx);return false;}
    CTLineRef line=CTLineCreateWithAttributedString((CFAttributedStringRef)s);
    [s release];
    if(!line){CGContextRelease(ctx);return false;}
    CGFloat a,d,l; CTLineGetTypographicBounds(line,&a,&d,&l);
    CGContextSetTextPosition(ctx,0,d); CTLineDraw(line,ctx);
    CFRelease(line); CGContextRelease(ctx); return true;}
int main(int argc,char**argv){@autoreleasepool{
    size_t W=argc>1?atol(argv[1]):1690, H=argc>2?atol(argv[2]):47; int N=argc>3?atoi(argv[3]):500;
    // a nerd-font-ish cascade descriptor, to price the block; falls back to none if absent
    nerd=CTFontDescriptorCreateWithNameAndSize(CFSTR("Menlo"),0);
    uint8_t*buf=malloc(W*H*4);
    const char*t=" \342\234\263 Kitty window drag implementation phase 3";  // a real operator title
    render(t,buf,W,H,true); // warm
    double s=now_ms(); for(int i=0;i<N;i++) render(t,buf,W,H,true); double a=now_ms()-s;
    s=now_ms(); for(int i=0;i<N;i++) render(t,buf,W,H,false); double b=now_ms()-s;
    printf("# %zux%zu, N=%d, title=%s\n",W,H,N,t);
    printf("full cocoa_render_line_of_text (with cascade copy): %8.3f us/call\n",a*1000/N);
    printf("same, cascade block skipped                       : %8.3f us/call\n",b*1000/N);
    printf("=> per-call cost of the cascade copy              : %8.3f us\n",(a-b)*1000/N);
    return 0;}}
