#!/usr/bin/env python3
"""fsevents-top.py — which paths dominate the FSEvents stream, read unprivileged.

    fsevents-top.py [--seconds N] [--depth D] [--top K] [--root PATH] [--json] [--ready-file F]

WHY (2026-10-04): fseventsd reached a 64 GB footprint and filled swap (scripts/fseventsd-watch.sh).
Its own history (/System/Volumes/Data/.fseventsd) and fs_usage are root-only, but any user may open
an FSEvents stream over "/" through CoreServices, and fseventsd delivers every path to it. This
subscribes for N seconds with per-file events, buckets each path by its first D components, and
prints the event count per bucket, largest first, so the sources feeding the daemon have names.

First reading, 2026-10-04 (60 s, a loaded box): 16,448 then 24,965 events/min; bats temp dirs under
$TMPDIR (/private/var/folders/.../T/bats-run-*) were ~13,000 of the 24,965.

Python stdlib only (ctypes); no pyobjc, no fswatch. It reads; it changes nothing.
"""

import argparse
import collections
import ctypes
import json
import sys
import time

CS = ctypes.CDLL("/System/Library/Frameworks/CoreServices.framework/CoreServices")
CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
CF.CFStringCreateWithCString.restype = ctypes.c_void_p
CF.CFStringCreateWithCString.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_uint32,
]
CF.CFArrayCreate.restype = ctypes.c_void_p
CF.CFArrayCreate.argtypes = [
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_void_p),
    ctypes.c_long,
    ctypes.c_void_p,
]
CF.CFRunLoopGetCurrent.restype = ctypes.c_void_p
CF.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]
kCFRunLoopDefaultMode = ctypes.c_void_p.in_dll(CF, "kCFRunLoopDefaultMode")
CALLBACK = ctypes.CFUNCTYPE(
    None,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_char_p),
    ctypes.POINTER(ctypes.c_uint32),
    ctypes.POINTER(ctypes.c_uint64),
)
CS.FSEventStreamCreate.restype = ctypes.c_void_p
CS.FSEventStreamCreate.argtypes = [
    ctypes.c_void_p,
    CALLBACK,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_uint64,
    ctypes.c_double,
    ctypes.c_uint32,
]
for fn in (
    "FSEventStreamStart",
    "FSEventStreamFlushSync",
    "FSEventStreamStop",
    "FSEventStreamInvalidate",
    "FSEventStreamRelease",
):
    getattr(CS, fn).argtypes = [ctypes.c_void_p]
CS.FSEventStreamScheduleWithRunLoop.argtypes = [
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_void_p,
]
CS.FSEventStreamStart.restype = (
    ctypes.c_bool
)  # Boolean is one byte; c_int would read stray bytes

SINCE_NOW = 0xFFFFFFFFFFFFFFFF
FLAG_NO_DEFER, FLAG_FILE_EVENTS = 0x2, 0x10
UTF8 = 0x08000100


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seconds", type=float, default=60.0)
    ap.add_argument("--depth", type=int, default=4, help="path components per bucket")
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument(
        "--root", default="/", help="watch this path instead of the whole tree"
    )
    ap.add_argument(
        "--json", action="store_true", help="one JSON object instead of a table"
    )
    ap.add_argument(
        "--ready-file",
        help="touch this file once the stream is open (lets a caller start writing without a race)",
    )
    a = ap.parse_args()

    counts = collections.Counter()
    total = [0]

    def on_events(_stream, _info, n, paths, _flags, _ids):
        for i in range(n):
            p = paths[i].decode("utf-8", "replace")
            total[0] += 1
            parts = [x for x in p.split("/") if x]
            counts["/" + "/".join(parts[: a.depth])] += 1

    cb = CALLBACK(on_events)
    root = CF.CFStringCreateWithCString(None, a.root.encode(), UTF8)
    arr = (ctypes.c_void_p * 1)(root)
    paths = CF.CFArrayCreate(None, arr, 1, None)
    stream = CS.FSEventStreamCreate(
        None, cb, None, paths, SINCE_NOW, 0.5, FLAG_NO_DEFER | FLAG_FILE_EVENTS
    )
    if not stream:
        print("fsevents-top: FSEventStreamCreate failed", file=sys.stderr)
        return 1
    CS.FSEventStreamScheduleWithRunLoop(
        stream, CF.CFRunLoopGetCurrent(), kCFRunLoopDefaultMode
    )
    if not CS.FSEventStreamStart(stream):
        print("fsevents-top: FSEventStreamStart failed", file=sys.stderr)
        return 1
    if a.ready_file:
        open(a.ready_file, "w").close()
    t0 = time.time()
    end = t0 + a.seconds
    while time.time() < end:
        CF.CFRunLoopRunInMode(
            kCFRunLoopDefaultMode, min(0.5, max(0.01, end - time.time())), False
        )
    CS.FSEventStreamFlushSync(stream)
    CS.FSEventStreamStop(stream)
    CS.FSEventStreamInvalidate(stream)
    CS.FSEventStreamRelease(stream)
    secs = time.time() - t0

    top = counts.most_common(a.top)
    if a.json:
        print(
            json.dumps(
                {
                    "seconds": round(secs, 1),
                    "events": total[0],
                    "per_min": int(total[0] * 60 / secs) if secs > 0 else None,
                    "depth": a.depth,
                    "top": [{"path": k, "events": v} for k, v in top],
                }
            )
        )
    else:
        print(
            "fsevents-top: %d events in %.1f s (%d/min), bucketed at depth %d"
            % (total[0], secs, int(total[0] * 60 / secs) if secs > 0 else 0, a.depth)
        )
        for k, v in top:
            print("%8d  %5.1f%%  %s" % (v, 100.0 * v / total[0] if total[0] else 0, k))
    return 0


if __name__ == "__main__":
    sys.exit(main())
