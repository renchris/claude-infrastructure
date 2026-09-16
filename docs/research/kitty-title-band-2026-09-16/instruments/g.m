#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
int main(void){@autoreleasepool{
    // Exactly what cocoa_render_line_of_text builds: attributed string with ONLY kCTFontAttributeName
    // set to the system UI font (plus optionally the Nerd cascade), then CTLineCreateWithAttributedString.
    NSString *nfp = @"/Applications/kitty.app/Contents/Resources/kitty/fonts/SymbolsNerdFontMono-Regular.ttf";
    CTFontDescriptorRef nerd = NULL;
    NSArray *descs = (NSArray*)CTFontManagerCreateFontDescriptorsFromURL((CFURLRef)[NSURL fileURLWithPath:nfp]);
    if (descs && [descs count]) { nerd = (CTFontDescriptorRef)CFRetain((CFTypeRef)descs[0]); }
    printf("nerd descriptor: %s\n", nerd ? "loaded" : "NULL");

    CTFontRef sys = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 40.7333, NULL);
    CTFontRef render_font = sys;
    if (nerd) {
        CFArrayRef cl = CFArrayCreate(NULL,(const void*[]){nerd},1,&kCFTypeArrayCallBacks);
        CFDictionaryRef at = CFDictionaryCreate(NULL,(const void*[]){kCTFontCascadeListAttribute},(const void*[]){cl},1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
        CFRelease(cl);
        CTFontDescriptorRef nd = CTFontDescriptorCreateWithAttributes(at); CFRelease(at);
        CTFontRef fwn = CTFontCreateCopyWithAttributes(sys, 0, NULL, nd); CFRelease(nd);
        if (fwn) render_font = fwn;
    }
    NSString *s = @" ✳ ◐ ◑ ✻ ✶ — • claude";
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:s attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)render_font}];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)a);
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    printf("string: %s\n", [s UTF8String]);
    printf("runs: %ld\n", CFArrayGetCount(runs));
    for (CFIndex i=0;i<CFArrayGetCount(runs);i++) {
        CTRunRef r = CFArrayGetValueAtIndex(runs,i);
        CFDictionaryRef at = CTRunGetAttributes(r);
        CTFontRef f = CFDictionaryGetValue(at, kCTFontAttributeName);
        CFStringRef ps = CTFontCopyPostScriptName(f);
        CFRange rr = CTRunGetStringRange(r);
        NSString *sub = [s substringWithRange:NSMakeRange(rr.location, rr.length)];
        // check for .notdef (glyph 0)
        CFIndex n = CTRunGetGlyphCount(r);
        CGGlyph *gl = malloc(sizeof(CGGlyph)*n);
        CTRunGetGlyphs(r, CFRangeMake(0,n), gl);
        int notdef=0; for (CFIndex k=0;k<n;k++) if (gl[k]==0) notdef++;
        printf("  run %ld  font=%-26s  text=%-14s glyphs=%ld notdef=%d\n", i, [(__bridge NSString*)ps UTF8String], [sub UTF8String], n, notdef);
        free(gl); CFRelease(ps);
    }
    CFRelease(line);
    return 0;
}}
