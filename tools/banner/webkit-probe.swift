// webkit-probe.swift — drive ONE WKWebView document and snapshot it TWICE inside its lifetime.
//
// WHY THIS EXISTS. The banner's entire world clock is expressed in CSS `@keyframes` inside an SVG
// that GitHub serves as an IMAGE. Whether a CSS-only animation advances in SVG-as-image mode is an
// ENGINE property, not a property of our art: Chromium runs it, and Firefox was probed separately
// (scripts/banner-firefox-probe.py) because Mozilla bug 1190881 says VectorImage only joins the
// refresh driver for SMIL. WebKit was the last unprobed engine, and it is not a rounding error —
// every Safari and every iOS reader is on it. If it does not tick there, the four narrative beats
// are three static frames for that whole population and a Chromium-only harness never notices.
//
// WHY WKWebView AND NOT THE PLAYWRIGHT WEBKIT BUILD. ~/Library/Caches/ms-playwright/webkit-2227
// exists, but it is a WebKit built by the Playwright project, not the one any reader has. WKWebView
// binds the SYSTEM WebKit — the exact framework Safari loads on this OS — so a verdict from here is
// about the engine readers run. The tool prints the UA string for that reason: a finding about an
// engine is only true of the build it was measured on, and the build number is how a future session
// dates this result rather than trusting it (memory: published-figure-decays-with-its-source).
//
// WHY TWO SNAPSHOTS IN ONE DOCUMENT, which is the whole design. A single screenshot cannot answer
// the question: compositing the animation's t=0 value proves only that the animation was APPLIED,
// never that the clock ADVANCES. Two separate page loads cannot answer it either — the timeline
// anchors at load, so both land at t≈0 and a static engine and a ticking one produce identical
// pairs. Only two samples straddling a hard flip WITHIN one document lifetime separate them.
//
// THIS TOOL DELIBERATELY RENDERS NO VERDICT ABOUT CSS. It is an instrument: load, sample twice,
// write two PNGs, say whether it managed to. The comparison, the SMIL positive control and the
// conclusion live in scripts/banner-webkit-probe.py, because a control is only a control if the
// thing being controlled cannot also be the thing declaring itself correct.
//
// 🚨 COMPILE IT, never `swift webkit-probe.swift`. Interpreted, the same AppKit/WebKit setup aborts
// inside swift-frontend — the identical constraint recorded at the head of window-film.swift.
//
//   swiftc -O tools/banner/webkit-probe.swift -o /tmp/banner-webkit-probe
//
// USAGE
//   banner-webkit-probe <page.html> <delayA-ms> <delayB-ms> <outA.png> <outB.png>
//
// VERDICT. A machine-parsable `verdict=` token on the LAST line, because a consumer must be able to
// tell "sampled twice, here are the frames" from "the instrument never ran". A bare exit 0 from a
// broken instrument reading as a result is the failure this repo has already paid for twice
// (memory: claimed-outcome-vs-checked-outcome, positive-control-the-denominator):
//   verdict=OK            both snapshots written              exit 0
//   verdict=LOAD-FAIL     the document never finished loading exit 3
//   verdict=SNAPSHOT-FAIL takeSnapshot returned no image      exit 4
//   verdict=TIMEOUT       the watchdog fired                  exit 5
//   verdict=USAGE         wrong arguments                     exit 2

import Cocoa
import WebKit

// The sampled rect. Matches the fixture's own 200x100 viewport so the centre pixel the driver reads
// is the middle of the flipping rect and nothing else.
let kWidth = 200.0
let kHeight = 100.0

func die(_ token: String, _ code: Int32, _ message: String = "") -> Never {
    if !message.isEmpty { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    print("verdict=\(token)")
    exit(code)
}

let argv = CommandLine.arguments
guard argv.count == 6,
      let delayA = Double(argv[2]),
      let delayB = Double(argv[3]) else {
    die("USAGE", 2, "usage: banner-webkit-probe <page.html> <delayA-ms> <delayB-ms> <outA.png> <outB.png>")
}
let pageURL = URL(fileURLWithPath: argv[1])
let outA = URL(fileURLWithPath: argv[4])
let outB = URL(fileURLWithPath: argv[5])

// delayB is measured from load, not from delayA, so the driver states the two sample times in one
// frame of reference and the flip it straddles is arithmetic rather than an accumulated sleep.
guard delayB > delayA else { die("USAGE", 2, "delayB must be greater than delayA") }

func writePNG(_ image: NSImage, to url: URL) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
}

final class Probe: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private var fired = false
    // Held as properties rather than captured: a top-level `let` bound in a guard is not in scope
    // for a class body, and threading them through init keeps the sample times with the sampler.
    private let delayA: Double
    private let delayB: Double
    private let outA: URL
    private let outB: URL

    init(delayA: Double, delayB: Double, outA: URL, outB: URL) {
        self.delayA = delayA
        self.delayB = delayB
        self.outA = outA
        self.outB = outB
        let frame = NSRect(x: 0, y: 0, width: kWidth, height: kHeight)
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: frame, configuration: cfg)
        // A borderless window in the bottom-left corner, ordered front WITHOUT activating. The view
        // has to be in a window hierarchy that is actually being drawn: a WKWebView that never
        // reaches the screen snapshots blank, and a blank pair compares EQUAL — i.e. it would report
        // "static" for a perfectly healthy engine. The SMIL control in the driver is what catches
        // that if it happens anyway; this is the cheap way to stop it happening.
        window = NSWindow(contentRect: frame,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false
        super.init()
        webView.navigationDelegate = self
        window.orderFrontRegardless()
    }

    func load(_ url: URL) {
        // Read access is granted to the containing directory so a file:// page can pull a file://
        // subresource. The fixtures inline their SVG as a data: URI anyway — which is SVG-as-image
        // by construction and removes file-origin rules from the question entirely — but a probe
        // that only works for one fixture shape is a probe that will be quietly retired the first
        // time someone points it at a real asset.
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !fired else { return }   // sub-frame loads must not restart the clock
        fired = true
        webView.evaluateJavaScript("navigator.userAgent") { value, _ in
            print("ua=\(value as? String ?? "unknown")")
            self.schedule()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        die("LOAD-FAIL", 3, "navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        die("LOAD-FAIL", 3, "provisional navigation failed: \(error.localizedDescription)")
    }

    private func snapshotFrame(to url: URL, then next: @escaping () -> Void) {
        let cfg = WKSnapshotConfiguration()
        cfg.rect = NSRect(x: 0, y: 0, width: kWidth, height: kHeight)
        webView.takeSnapshot(with: cfg) { image, error in
            guard let image, writePNG(image, to: url) else {
                die("SNAPSHOT-FAIL", 4,
                    "takeSnapshot: \(error?.localizedDescription ?? "no image returned")")
            }
            next()
        }
    }

    private func schedule() {
        DispatchQueue.main.asyncAfter(deadline: .now() + delayA / 1000.0) {
            self.snapshotFrame(to: self.outA) {
                DispatchQueue.main.asyncAfter(deadline: .now() + (self.delayB - self.delayA) / 1000.0) {
                    self.snapshotFrame(to: self.outB) {
                        print("verdict=OK")
                        exit(0)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
// .accessory keeps the probe out of the Dock and off the app switcher. It still gets a window
// server connection, which is what the snapshot needs.
app.setActivationPolicy(.accessory)

let probe = Probe(delayA: delayA, delayB: delayB, outA: outA, outB: outB)
probe.load(pageURL)

// The watchdog is generous against delayB rather than absolute: a bound sized from a fast run
// becomes a permanent non-verdict the moment the machine is loaded (memory:
// bound-must-fit-the-band-not-the-bench).
let budget = (delayB / 1000.0) + 30.0
DispatchQueue.main.asyncAfter(deadline: .now() + budget) {
    die("TIMEOUT", 5, "no verdict within \(budget)s")
}

app.run()
