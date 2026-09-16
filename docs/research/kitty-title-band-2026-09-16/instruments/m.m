#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>

static CTFontRef ensure_ui_font(size_t in_height, CGFloat *out_desired) {
    CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL);
    if (!f) return NULL;
    CGFloat line_height = MAX(1, floor(CTFontGetAscent(f) + CTFontGetDescent(f) + MAX(0, CTFontGetLeading(f)) + 0.5));
    CGFloat pts_per_px = CTFontGetSize(f) / line_height;
    CGFloat desired_size = in_height * pts_per_px;
    *out_desired = desired_size;
    if (desired_size != CTFontGetSize(f)) {
        CTFontRef sized = CTFontCreateCopyWithAttributes(f, desired_size, NULL, NULL);
        CFRelease(f);
        f = sized;
    }
    return f;
}

static void dump(const char *label, CTFontRef f) {
    CFStringRef nm = CTFontCopyFullName(f);
    CFStringRef ps = CTFontCopyPostScriptName(f);
    CFStringRef fam = CTFontCopyFamilyName(f);
    CFDictionaryRef traits = CTFontCopyTraits(f);
    double w = 0; CFNumberRef wn = CFDictionaryGetValue(traits, kCTFontWeightTrait);
    if (wn) CFNumberGetValue(wn, kCFNumberDoubleType, &w);
    printf("%-22s size=%7.3f  asc=%7.3f desc=%7.3f lead=%7.3f  linebox=%7.3f  cap=%7.3f x=%7.3f  weightTrait=%+.4f\n",
        label, CTFontGetSize(f), CTFontGetAscent(f), CTFontGetDescent(f), CTFontGetLeading(f),
        CTFontGetAscent(f)+CTFontGetDescent(f)+CTFontGetLeading(f),
        CTFontGetCapHeight(f), CTFontGetXHeight(f), w);
    printf("%-22s  full=%s  ps=%s  family=%s\n", "", [(__bridge NSString*)nm UTF8String], [(__bridge NSString*)ps UTF8String], [(__bridge NSString*)fam UTF8String]);
    CFRelease(nm); CFRelease(ps); CFRelease(fam); CFRelease(traits);
}

static void line_metrics(const char *label, CTFontRef f, NSString *text) {
    NSAttributedString *s = [[NSAttributedString alloc] initWithString:text attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)f}];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)s);
    CGFloat a,d,l;
    double wdt = CTLineGetTypographicBounds(line, &a, &d, &l);
    CGRect ib = CTLineGetImageBounds(line, NULL);
    printf("%-22s CTLine: width=%8.3f asc=%7.3f desc=%7.3f lead=%7.3f | imageBounds x=%.2f y=%.2f w=%.2f h=%.2f\n",
        label, wdt, a, d, l, ib.origin.x, ib.origin.y, ib.size.width, ib.size.height);
    CFRelease(line);
}

int main(int argc, char **argv) { @autoreleasepool {
    printf("=== macOS %s ===\n", [[[NSProcessInfo processInfo] operatingSystemVersionString] UTF8String]);
    CTFontRef base = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL);
    dump("DEFAULT ui font", base);
    CGFloat lh = MAX(1, floor(CTFontGetAscent(base)+CTFontGetDescent(base)+MAX(0,CTFontGetLeading(base))+0.5));
    printf("   floor(a+d+max(0,l)+0.5) = %.3f   pts_per_px = %.6f\n", lh, CTFontGetSize(base)/lh);
    CFRelease(base);
    printf("\n");
    size_t heights[] = {47, 45, 24, 22, 20, 18, 16, 14};
    NSString *sample = @" chrisren ~/Development/claude-infrastructure";
    for (unsigned i=0;i<sizeof(heights)/sizeof(heights[0]);i++) {
        CGFloat ds=0; CTFontRef f = ensure_ui_font(heights[i], &ds);
        char lab[64]; snprintf(lab,sizeof(lab),"in_height=%zu", heights[i]);
        printf("--- %s  (desired_size=%.4f) ---\n", lab, ds);
        dump(lab, f);
        line_metrics(lab, f, sample);
        printf("   baseline set at y=descent=%.3f from BOTTOM of a %zu px buffer\n", CTFontGetDescent(f), heights[i]);
        printf("   => cap top at y = %.3f  (bar top gap = %.3f px)\n",
            CTFontGetDescent(f)+CTFontGetCapHeight(f), (double)heights[i] - (CTFontGetDescent(f)+CTFontGetCapHeight(f)));
        CFRelease(f);
        printf("\n");
    }
    return 0;
}}
