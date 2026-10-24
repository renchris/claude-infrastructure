#!/usr/bin/env python3
"""Python re-implementation of hooks/subagent-long-bash-shadow.sh narrow predicate (d9ffc3964);
compares against the researcher's replay.jsonl and writes broad_v.jsonl with my verdict.
Usage: python3 -I pred.py broad.jsonl ../replay.jsonl broad_v.jsonl"""

import json, re, sys

S = r"[ \t\n\r\f\v]"
RX_LOOP = re.compile(
    r"(^|[;&|" + S[1:-1] + r"])(while|until|for)" + S + r".*sleep" + S, re.S
)
RX_SLEEP = re.compile(r"(^|[;&|" + S[1:-1] + r"])sleep" + S + r"+([0-9]+)", re.S)
RX_WAIT = re.compile(
    r"cc-await-ping|cc-wait("
    + S
    + r"|$)|gh"
    + S
    + r"+run"
    + S
    + r"+watch|--watch("
    + S
    + r"|$)|tail"
    + S
    + r"+-[A-Za-z]*[fF]|(^|[;&|]"
    + S
    + r"*)wait("
    + S
    + r"*($|[;&|]))",
    re.S,
)
RX_TO = re.compile(
    r"(^|[;&|"
    + S[1:-1]
    + r"])g?timeout"
    + S
    + r"+(-[^ \t\n\r\f\v]+"
    + S
    + r"+)*([0-9]+)([sm]?)"
    + S,
    re.S,
)
RX_LONG = re.compile(
    r"(^|[/"
    + S[1:-1]
    + r";&|])(cc-bats|bats|ship-land(\.sh)?|deploy-live(\.sh)?|pytest|xcodebuild|ffmpeg)("
    + S
    + r"|$)|(pnpm|npm|yarn|bun)"
    + S
    + r"+(run"
    + S
    + r"+)?(test|build|e2e)|cargo"
    + S
    + r"+(build|test)|(^|[;&|"
    + S[1:-1]
    + r"])make("
    + S
    + r"|$)|"
    + S
    + r"render("
    + S
    + r"|$)",
    re.S,
)


def why(cmd):
    c = cmd.rstrip("\n")
    if RX_LOOP.search(c):
        return "poll-loop"
    m = RX_SLEEP.search(c)
    if m and int(m.group(2)) >= 270:
        return "long-sleep"
    if RX_WAIT.search(c):
        return "waiter"
    m = RX_TO.search(c)
    if m:
        n = int(m.group(3)) * (60 if m.group(4) == "m" else 1)
        if n >= 270:
            return "waiter"
    if RX_LONG.search(c):
        return "long-runner"
    return None


if __name__ == "__main__":
    B = [json.loads(l) for l in open(sys.argv[1])]
    R = {}
    for l in open(sys.argv[2]):
        x = json.loads(l)
        R[x["tool_use_id"]] = x
    agree = dis = miss = 0
    ex = []
    with open(sys.argv[3], "w") as f:
        for r in B:
            w = why(r["cmd"])
            r["why"] = w
            x = R.get(r["id"])
            if x is None:
                miss += 1
            elif (x["why"] or None) == w:
                agree += 1
            else:
                dis += 1
                if len(ex) < 15:
                    ex.append((r["id"], x["why"], w, r["cmd"][:140]))
            f.write(json.dumps(r) + "\n")
    print("agree", agree, "disagree", dis, "not in their replay", miss)
    for e in ex:
        print(e)
