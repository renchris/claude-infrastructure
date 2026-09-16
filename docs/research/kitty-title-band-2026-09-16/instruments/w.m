#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>

static void info(const char *label, CTFontRef f) {
    CFStringRef ps = CTFontCopyPostScriptName(f);
    CFDictionaryRef tr = CTFontCopyTraits(f);
    double w = 0; CFNumberRef wn = tr ? CFDictionaryGetValue(tr, kCTFontWeightTrait) : NULL;
    if (wn) CFNumberGetValue(wn, kCFNumberDoubleType, &w);
    printf("  %-34s ps=%-22s size=%7.3f weight=%+.4f cap=%7.3f asc=%7.3f desc=%7.3f\n",
        label, [(__bridge NSString*)ps UTF8String], CTFontGetSize(f), w,
        CTFontGetCapHeight(f), CTFontGetAscent(f), CTFontGetDescent(f));
    CFRelease(ps); if (tr) CFRelease(tr);
}

// exact ink bbox of a string rendered with CTLine, as render path would
static void ink(const char *label, CTFontRef f, NSString *s) {
    NSAttributedString *a = [[NSAttributedString alloc] initWithString:s attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)f}];
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)a);
    CGRect ib = CTLineGetImageBounds(line, NULL);
    CGFloat asc,desc,lead; double wdt = CTLineGetTypographicBounds(line,&asc,&desc,&lead);
    printf("  %-34s ink: x=%6.2f y=%7.3f w=%8.2f h=%7.3f | adv=%8.2f\n", label, ib.origin.x, ib.origin.y, ib.size.width, ib.size.height, wdt);
    CFRelease(line); [a release];
}

int main(void){@autoreleasepool{
    const CGFloat SZ = 40.7333333333; // desired_size at in_height=47
    printf("### A. Ways to reach a Semibold system face at size %.4f\n", SZ);

    CTFontRef sys = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, SZ, NULL);
    info("kCTFontUIFontSystem", sys);

    CTFontRef emph = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, SZ, NULL);
    info("kCTFontUIFontEmphasizedSystem", emph);

    NSFont *nsSemi = [NSFont systemFontOfSize:SZ weight:NSFontWeightSemibold];
    info("NSFont systemFontOfSize:weight:Semibold", (__bridge CTFontRef)nsSemi);
    NSFont *nsMed  = [NSFont systemFontOfSize:SZ weight:NSFontWeightMedium];
    info("NSFont ... Medium", (__bridge CTFontRef)nsMed);
    NSFont *nsBold = [NSFont systemFontOfSize:SZ weight:NSFontWeightBold];
    info("NSFont ... Bold", (__bridge CTFontRef)nsBold);

    // pure CoreText: copy with a weight trait descriptor
    double wv = 0.3;
    CFNumberRef wnum = CFNumberCreate(NULL, kCFNumberDoubleType, &wv);
    CFDictionaryRef traits = CFDictionaryCreate(NULL,(const void*[]){kCTFontWeightTrait},(const void*[]){wnum},1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFDictionaryRef attrs = CFDictionaryCreate(NULL,(const void*[]){kCTFontTraitsAttribute},(const void*[]){traits},1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes(attrs);
    CTFontRef copy = CTFontCreateCopyWithAttributes(sys, SZ, NULL, d);
    info("CTFontCreateCopyWithAttributes(w=0.3)", copy);

    // symbolic bold
    CTFontRef sb = CTFontCreateCopyWithSymbolicTraits(sys, SZ, NULL, kCTFontTraitBold, kCTFontTraitBold);
    if (sb) info("CopyWithSymbolicTraits(Bold)", sb); else printf("  CopyWithSymbolicTraits(Bold)       = NULL\n");

    printf("\n### B. NSFontWeight constants\n");
    printf("  Regular=%+.4f Medium=%+.4f Semibold=%+.4f Bold=%+.4f\n",
        (double)NSFontWeightRegular,(double)NSFontWeightMedium,(double)NSFontWeightSemibold,(double)NSFontWeightBold);

    printf("\n### C. Worst-case ink in the automatic 47px band (em %.3f), baseline at y=descent=%.3f\n", SZ, CTFontGetDescent(sys));
    NSString *worst = @"ÅÉÎÕÜ gjpqy";
    NSString *typical = @" ✳ claude-infrastructure — main";
    NSString *sp = @" ";
    CTFontRef semi = (__bridge CTFontRef)nsSemi;
    ink("Regular  worst ÅÉÎÕÜ gjpqy", sys, worst);
    ink("Semibold worst ÅÉÎÕÜ gjpqy", semi, worst);
    ink("Regular  typical title", sys, typical);
    ink("Semibold typical title", semi, typical);
    ink("Regular  single space", sys, sp);
    ink("Semibold single space", semi, sp);
    CGFloat desc = CTFontGetDescent(sys);
    NSAttributedString *aw=[[NSAttributedString alloc] initWithString:worst attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)sys}];
    CTLineRef lw=CTLineCreateWithAttributedString((CFAttributedStringRef)aw);
    CGRect ibw=CTLineGetImageBounds(lw,NULL);
    printf("  => Regular worst ink occupies y=[%.2f .. %.2f] of a 47px band  (top gap %.2f, bottom gap %.2f, ink/band %.3f)\n",
        desc+ibw.origin.y, desc+ibw.origin.y+ibw.size.height, 47.0-(desc+ibw.origin.y+ibw.size.height), desc+ibw.origin.y, ibw.size.height/47.0);
    CFRelease(lw);

    printf("\n### D. Body face for the cap-ratio comparison: Monaco at em 36 (font_size 18 @2x)\n");
    CTFontRef mono = CTFontCreateWithName(CFSTR("Monaco"), 36.0, NULL);
    info("Monaco em36", mono);
    printf("  cap(SF Regular em %.3f)/cap(Monaco em36) = %.3f\n", SZ, CTFontGetCapHeight(sys)/CTFontGetCapHeight(mono));
    printf("  cap(SF Semibold em %.3f)/cap(Monaco em36) = %.3f\n", SZ, CTFontGetCapHeight(semi)/CTFontGetCapHeight(mono));
    printf("  (the shipped Pillow overlay runs SF Semibold em 42 -> cap/body %.3f)\n",
        CTFontGetCapHeight((__bridge CTFontRef)[NSFont systemFontOfSize:42.0 weight:NSFontWeightSemibold])/CTFontGetCapHeight(mono));

    printf("\n### E. Sizes that would put the band where the operator accepted it\n");
    for (double h = 20; h <= 50; h += 1) {
        CGFloat base_lh = 15.0, base_sz = 13.0;
        CGFloat ds = h * (base_sz/base_lh);
        CTFontRef f = (__bridge CTFontRef)[NSFont systemFontOfSize:ds weight:NSFontWeightSemibold];
        NSAttributedString *aa=[[NSAttributedString alloc] initWithString:worst attributes:@{(NSString*)kCTFontAttributeName:(__bridge id)f}];
        CTLineRef ll=CTLineCreateWithAttributedString((CFAttributedStringRef)aa);
        CGRect ii=CTLineGetImageBounds(ll,NULL);
        printf("  band=%2.0fpx em=%6.2f worstink=%6.2f ink/band=%.3f cap/body=%.3f\n",
            h, ds, ii.size.height, ii.size.height/h, CTFontGetCapHeight(f)/CTFontGetCapHeight(mono));
        CFRelease(ll);
    }
    return 0;
}}
