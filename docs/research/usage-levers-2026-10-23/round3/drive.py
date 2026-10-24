"""Drive probe calls in batches until TARGET cache-read tokens, reading meters between batches.

Guards (checked after every batch): weekly wire >= BASE_7D + 0.04, or endpoint weekly >= 17,
or the dollar field moved > $20, or any call failed twice in a row -> stop.
"""

import json
import subprocess
import sys
import time

TARGET = int(sys.argv[1]) if len(sys.argv) > 1 else 500_000_000
BATCH, PAR = 60, 6
BASE_7D_WIRE, BASE_DOLLARS = 0.12, 25.420422
LOG = "/tmp/w2probe/drive.log"


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def reads_so_far(start_line):
    reads = writes = fails = n = 0
    with open("/tmp/w2probe/calls.jsonl") as f:
        for i, line in enumerate(f):
            if i < start_line:
                continue
            d = json.loads(line)
            if d.get("rc") != 0:
                fails += 1
                continue
            n += 1
            for mu in (d.get("modelUsage") or {}).values():
                reads += mu.get("cacheReadInputTokens", 0)
                writes += mu.get("cacheCreationInputTokens", 0)
    return n, reads, writes, fails


def meter(label):
    out = subprocess.run(
        ["python3", "-I", "/tmp/w2probe/meter.py", label],
        capture_output=True,
        text=True,
        timeout=60,
    ).stdout
    try:
        r = json.loads(out)
    except ValueError:
        return None, None, None, None, None
    u = r.get("usage") or {}  # a 429 on the usage endpoint leaves only the wire reading
    return (
        (r.get("wire") or {}).get("5h_util"),
        (r.get("wire") or {}).get("7d_util"),
        (u.get("five_hour") or {}).get("utilization"),
        (u.get("seven_day") or {}).get("utilization"),
        (u.get("iguana_necktie") or {}).get("used_dollars"),
    )


start_line = (
    int(sys.argv[2])
    if len(sys.argv) > 2
    else sum(1 for _ in open("/tmp/w2probe/calls.jsonl"))
)
log(f"start: calls.jsonl line {start_line}, target {TARGET:,}")
b = 0
while True:
    n, reads, writes, fails = reads_so_far(start_line)
    if reads >= TARGET:
        break
    b += 1
    subprocess.run(
        f"seq {BATCH} | xargs -P {PAR} -I{{}} /tmp/w2probe/call.sh", shell=True
    )
    n, reads, writes, fails = reads_so_far(start_line)
    w5, w7, e5, e7, dol = meter(f"batch-{b}")
    log(
        f"batch {b}: ok={n} fail={fails} reads={reads:,} writes={writes:,} | wire 5h={w5} 7d={w7} | endpoint 5h={e5} 7d={e7} | dollars={dol}"
    )
    if (w7 is not None and w7 >= BASE_7D_WIRE + 0.04) or (e7 is not None and e7 >= 17):
        log("STOP: weekly guard (4pp) tripped")
        break
    if dol is not None and dol - BASE_DOLLARS > 20:
        log("STOP: dollar field moved > $20")
        break
    if fails > max(10, n // 20):
        log("STOP: too many failed calls")
        break
log("done")
