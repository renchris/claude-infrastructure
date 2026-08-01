// window-film.swift — record ONE window to an mp4 at a requested frame rate, by window id.
//
// WHY NOT `screencapture -v`. `screencapture -v -l<window-id>` does not scope a VIDEO capture; it
// silently films the whole display (measured — a 1280x720 window produced a 3456x2234 take with the
// operator's desktop in it). The documented workaround is `-R x,y,w,h`, which scopes the RECT but
// not the WINDOW: it records whatever is on screen there. Measured while building this file, with
// the film window correctly positioned and the rect correct to the pixel, the capture came back
// showing a BROWSER — the operator's tabs, their mail client and their home address — because the
// browser was on top. The rect was never wrong. The instrument was.
//
// ScreenCaptureKit's `SCContentFilter(desktopIndependentWindow:)` captures the window's OWN
// composited content. Occlusion, Z-order, notification banners, the Dock and every other window on
// the machine become irrelevant BY CONSTRUCTION rather than by a check that can be forgotten — and
// the operator can keep using the machine while a take runs, which with a 30 s take per candidate
// is the difference between a repeatable instrument and a ritual.
//
// WHAT IT GUARANTEES, and what it does not:
//   · The frames contain exactly one window's content. It cannot film anything else.
//   · `fps=` in the verdict is the rate ACTUALLY delivered (frames written / wall seconds), never
//     the rate requested. A terminal that cannot repaint fast enough is a FINDING; a capture that
//     silently drops to 30 and gets captioned "60 fps" is a lie, and this is a file whose entire
//     purpose is to be believed.
//   · minimumFrameInterval is a CEILING, not a floor. ScreenCaptureKit emits a frame when the
//     window's content changes, so a window that repaints at 10 Hz yields ~10 fps of DISTINCT
//     frames. The mp4 is written at the requested timebase so playback speed is real time; the
//     delivered-vs-requested gap is reported rather than hidden.
//
// USAGE
//   swift window-film.swift --window-id 637 --seconds 30 --out /tmp/take.mov [--fps 60]
// PRINTS: frames=<n> seconds=<f> fps=<f> size=<w>x<h> out=<path>  then verdict=OK|NO-WINDOW|ERROR
// EXIT:   0 OK · 2 usage · 4 NO-WINDOW · 5 capture/write error

import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// 🚨 TWO NON-OBVIOUS REQUIREMENTS, both of which abort the process rather than return an error.
//
// 1. `NSApplicationLoad()` — a plain CLI binary has no WindowServer connection, and the FIRST
//    ScreenCaptureKit call that needs one dies on `Assertion failed: (did_initialize),
//    CGS_REQUIRE_INIT`. Not a thrown error, not a nil: an abort with no verdict line, which is the
//    worst possible failure for a script whose output is parsed.
// 2. A LIVE MAIN RUN LOOP. Waiting on a semaphore on the main thread deadlocks the capture —
//    ScreenCaptureKit services its callbacks through the main run loop, so the thread that must
//    stay free is exactly the one a `sem.wait()` blocks. The structure below runs the work in a
//    Task and stops the run loop from inside it.
//
// Also: this file must be COMPILED (`swiftc`), never run as `swift window-film.swift`. In
// interpreter mode the same SCContentFilter call crashes inside swift-frontend
// (SLSGetActiveDisplayList → abort). Its sibling window-rect.swift runs fine interpreted, which is
// exactly the trap — the two files look interchangeable and are not.

var windowID: UInt32?
var seconds: Double = 30
var requestedFPS: Int = 60
var outPath: String?
var activate = false

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--window-id": windowID = args.isEmpty ? nil : UInt32(args.removeFirst())
    case "--seconds":   seconds = args.isEmpty ? seconds : (Double(args.removeFirst()) ?? seconds)
    case "--fps":       requestedFPS = args.isEmpty ? requestedFPS : (Int(args.removeFirst()) ?? requestedFPS)
    case "--out":       outPath = args.isEmpty ? nil : args.removeFirst()
    case "--activate":  activate = true
    case "-h", "--help":
        print("usage: window-film.swift --window-id <n> --seconds <s> --out <file.mov> [--fps 60]")
        exit(0)
    default:
        FileHandle.standardError.write("window-film: unknown arg \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}
guard let wid = windowID, let out = outPath else {
    FileHandle.standardError.write("window-film: --window-id and --out are required\n".data(using: .utf8)!)
    exit(2)
}

// The writer runs on the stream's own queue; `final class` + a lock keeps the frame counter honest
// under that concurrency instead of racing it.
final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let lock = NSLock()
    var frames = 0
    var dropped = 0
    var maxGap: Double = 0
    var stalls = 0
    var stalledSeconds: Double = 0
    // 1.5 s is the threshold a viewer reads as "it hung", and the same one the harness used when it
    // was still asking ffmpeg. Kept identical so the two eras of this number stay comparable.
    let stallThreshold: Double = 1.5
    var startFailure: String?
    var appendFailure: String?
    var started = false
    var firstPTS: CMTime = .zero
    var lastPTS: CMTime = .zero

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // A renderer test is judged on fine coloured detail, so the master is deliberately
                // over-provisioned; every deliverable is derived from it and a re-shoot is expensive.
                AVVideoAverageBitRateKey: 40_000_000,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw NSError(domain: "window-film", code: 1) }
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buf: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(buf), buf.numSamples > 0 else { return }
        // SCStream delivers status-only buffers (idle / blank / suspended) with no image. Writing
        // one produces a frame that is not the window, so the status is read and non-complete
        // buffers are dropped rather than counted.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buf, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        guard CMSampleBufferGetImageBuffer(buf) != nil else { return }

        lock.lock(); defer { lock.unlock() }
        let pts = CMSampleBufferGetPresentationTimeStamp(buf)
        if !started {
            // startWriting() RETURNS FALSE on failure and sets .error — it does not throw. Ignoring
            // that return produced the worst failure this file has had: every subsequent append
            // silently no-opped, the frame counter stayed 0, and the only symptom was an unrelated
            // crash in markAsFinished at the end. Record the reason at the moment it is knowable.
            if !writer.startWriting() {
                startFailure = writer.error.map { "\($0)" } ?? "startWriting returned false (status=\(writer.status.rawValue))"
                return
            }
            writer.startSession(atSourceTime: pts)
            started = true
            firstPTS = pts
        }
        // Not an error: the encoder applies backpressure and SCStream keeps delivering. Count the
        // drops so a take thinned by a busy box is visible rather than inferred from a low fps.
        guard input.isReadyForMoreMediaData else { dropped += 1; return }
        if input.append(buf) {
            // STALL MEASUREMENT, TAKEN AT THE SOURCE. ScreenCaptureKit emits a frame only when the
            // window's content CHANGES, so the interval between two delivered frames is exactly how
            // long the window sat unchanged. That makes stalls measurable without looking at pixels
            // at all — which matters, because the pixel route was tried and is not trustworthy here:
            // ffmpeg's freezedetect averages the difference over the WHOLE frame, so on sparse
            // coloured text (and after the letterboxing an off-16:9 window needs) it called an
            // entire 20 s film "frozen from t=0" while 808 distinct frames were plainly present.
            // Worse, its answer varied with how much black padding each candidate's window shape
            // happened to need — i.e. it was not comparable ACROSS the very candidates being
            // compared. Frame-arrival gaps have no such dependence.
            if frames > 0 {
                let gap = CMTimeGetSeconds(CMTimeSubtract(pts, lastPTS))
                if gap > maxGap { maxGap = gap }
                if gap > stallThreshold { stalls += 1; stalledSeconds += gap }
            }
            frames += 1; lastPTS = pts
        }
        else { appendFailure = writer.error.map { "\($0)" } ?? "append returned false" }
    }

    func finish() -> (Int, Double) {
        lock.lock()
        let n = frames
        let span = CMTimeGetSeconds(CMTimeSubtract(lastPTS, firstPTS))
        let didStart = started
        lock.unlock()
        // markAsFinished() THROWS an ObjC exception when the writer never started ("Cannot call
        // method when status is 0"), which is uncatchable in Swift and terminates the process. A
        // take that produced no frames is a normal outcome to report, not a crash — so the
        // never-started case returns without touching the writer.
        guard didStart else { return (0, 0) }
        let done = DispatchSemaphore(value: 0)
        input.markAsFinished()
        writer.finishWriting { done.signal() }
        done.wait()
        return (n, span)
    }
}

// Touching NSApplication.shared is what opens the WindowServer connection — `NSApplicationLoad()`
// is not exposed to Swift. `.accessory` keeps this off the Dock and out of the app switcher, so
// filming never steals focus from whatever the operator is doing.
NSApplication.shared.setActivationPolicy(.accessory)
var exitCode: Int32 = 0

Task {
    do {
        // onScreenWindowsOnly:false — a window that is fully covered is still a legitimate subject
        // here, which is the entire point of window-scoped capture.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == wid }) else {
            print("verdict=NO-WINDOW window_id=\(wid) candidates=\(content.windows.count)")
            exitCode = 4; CFRunLoopStop(CFRunLoopGetMain()); return
        }

        // 🚨 THE SUBJECT MUST BE VISIBLE, and window-scoped capture does NOT exempt it.
        // Measured: a 20 s take of an 18-pane window that was covered by a browser returned THREE
        // frames — 0.14 fps. Not a capture bug. macOS sets NSWindowOcclusionState to non-visible on
        // a covered window and well-behaved apps (kitty among them) stop drawing entirely, so there
        // is no new content for ScreenCaptureKit to deliver. The filter guarantees we never film
        // ANOTHER window's pixels; it cannot make an app render while the system is telling it not
        // to bother. So the owning app is raised first.
        //
        // `NSRunningApplication.activate` is public API and needs no Accessibility grant — which is
        // what makes this viable, since `osascript` System Events positioning is refused on this box
        // (-1728) and `open -a` cannot address one instance-group's process.
        // `.activateIgnoringOtherApps` is not optional here, deprecation notwithstanding. Without it
        // macOS honours the request only when the CALLER is already frontmost — and this process is
        // an .accessory with no windows, so it never is. Measured: activating kitty appeared to work
        // (a kitty window was already frontmost), while WezTerm never came forward at all — 16 of 16
        // re-activations found it still inactive, and the take returned ZERO frames because an
        // occluded window is not drawn. Same call, opposite outcomes, decided by which app happened
        // to be in front.
        if activate, let pid = window.owningApplication?.processID {
            NSRunningApplication(processIdentifier: pid)?
                .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }

        // Capture at the window's BACKING resolution (2x on Retina), so the master is native and
        // every downscale afterwards is a genuine downscale — never an upscale wearing 1080p's name.
        let scale = 2
        let w = Int(window.frame.width) * scale
        let h = Int(window.frame.height) * scale

        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(requestedFPS))
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.queueDepth = 8
        cfg.scalesToFit = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let url = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: url)

        let rec = try Recorder(url: url, width: w, height: h, fps: requestedFPS)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try stream.addStreamOutput(rec, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "window-film.frames"))
        try await stream.startCapture()

        // HOLD THE FOREGROUND FOR THE LENGTH OF THE TAKE.
        // This box runs the operator's live agent fleet, and a peer session raising a browser is an
        // ordinary event: measured, a take ran clean for 9.58 s and then flatlined the moment a
        // browser covered the window — 472 frames, then nothing, because an occluded window stops
        // being drawn. Activating once at the start is therefore not enough; the subject is
        // re-activated on a timer so a passing focus-steal costs a few frames instead of the take.
        // Re-activation is idempotent when the window is already frontmost.
        var reactivations = 0
        if activate, let pid = window.owningApplication?.processID {
            Task {
                while !Task.isCancelled {
                    // 1.2 s, not 2.5 s: at 2.5 s a single focus-steal left a >1.5 s hole in the
                    // footage — long enough that freeze detection (correctly) called the take
                    // static. The interval has to be shorter than the shortest gap anyone would
                    // read as the terminal having stalled.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if let app = NSRunningApplication(processIdentifier: pid), !app.isActive {
                        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                        reactivations += 1
                    }
                }
            }
        }

        let t0 = Date()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        let wall = Date().timeIntervalSince(t0)
        if reactivations > 0 {
            // Not a failure — but it means something else wanted the foreground during the take, so
            // the frame count deserves a second look rather than silent acceptance.
            print("refocused=\(reactivations)")
        }

        let (frames, span) = rec.finish()
        if frames == 0 {
            let why = rec.startFailure ?? rec.appendFailure ?? "stream delivered no usable frames"
            print("verdict=ERROR reason=no-frames-written detail=\(why) dropped=\(rec.dropped)")
            exitCode = 5; CFRunLoopStop(CFRunLoopGetMain()); return
        }
        print(String(format: "frames=%d dropped=%d seconds=%.2f fps=%.2f size=%dx%d out=%s",
                     frames, rec.dropped, wall, Double(frames) / wall, w, h, (out as NSString).utf8String!))
        print(String(format: "pts_span=%.2fs", span))
        print(String(format: "stalls=%d stalled_s=%.2f max_gap_s=%.2f",
                     rec.stalls, rec.stalledSeconds, rec.maxGap))
        print("verdict=OK")
    } catch {
        print("verdict=ERROR reason=\(error.localizedDescription)")
        exitCode = 5
    }
    CFRunLoopStop(CFRunLoopGetMain())
}

CFRunLoopRun()
exit(exitCode)
