#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
static void one(NSString *s, CTFontRef base){
    NSAttributedString *a=[[NSAttributedString alloc] initWithString:s attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)base}];
    CTLineRef l=CTLineCreateWithAttributedString((CFAttributedStringRef)a);
    CGRect ib=CTLineGetImageBounds(l,NULL);
    CFArrayRef runs=CTLineGetGlyphRuns(l);
    CTRunRef r=CFArrayGetValueAtIndex(runs,0);
    CTFontRef f=CFDictionaryGetValue(CTRunGetAttributes(r),kCTFontAttributeName);
    CFStringRef ps=CTFontCopyPostScriptName(f);
    printf("  %-4s via %-24s ink h=%6.2f  y=[%6.2f..%6.2f]  (SF cap=28.70, SF baseline y=0)\n",
        [s UTF8String],[(__bridge NSString*)ps UTF8String], ib.size.height, ib.origin.y, ib.origin.y+ib.size.height);
    CFRelease(ps); CFRelease(l);
}
int main(void){@autoreleasepool{
    CTFontRef sys=CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,40.7333,NULL);
    printf("Per-symbol ink, relative to the SF Pro baseline, at em 40.733:\n");
    for (NSString *s in @[@"✳",@"◐",@"◑",@"✻",@"✶",@"H",@"x",@"—"]) one(s,sys);
    return 0;
}}
