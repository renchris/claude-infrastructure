#!/usr/bin/env python3
"""Attribute a macOS crash report frame to a FUNCTION NAME inside a STRIPPED CPython
extension module — with no symbol-bearing build and no reproduction.

WHY THIS EXISTS. cc-backlog bf6af099a712 recorded that kitty's 2026-09-16 20:13:49 SIGSEGV
was "NOT attributable on this box", because `nm` on the shipped
kitty.fast_data_types.so yields only undefined imports, so `+840952` resolved to nothing but
`_PyInit_fast_data_types+670476`. That reasoning treated the SYMBOL TABLE as the only name
source. It is not. Two other tables survive stripping, and together they name the function:

  1. LC_FUNCTION_STARTS — a ULEB128 delta list of every function's start offset. Stripping
     does not remove it. It gives BOUNDS, so a pc anywhere inside a function maps to that
     function's entry address.
  2. The module's PyMethodDef tables — `{const char *ml_name; PyCFunction ml_meth; int
     ml_flags; const char *ml_doc;}`, 32 bytes per entry, sitting in __DATA/__DATA_CONST with
     both pointers relocated. They MUST survive: CPython reads them at import time to build
     the module. So every Python-callable entry point has its NAME, in cleartext, next to its
     ADDRESS.

Intersect the two and a frame whose caller is `cfunction_call` resolves exactly.

WHAT IT REFUSES TO DO. The map is a property of ONE BUILD. Applying a shipped binary's map to
a sandbox build silently yields a confident wrong name — the offsets do not transfer. So every
attribution is gated on the crash report's own image UUID matching the binary being read, and a
mismatch is a REFUSAL (exit 3), never a guess. That guard is not decoration: the first draft of
this tool attributed two sandbox crashes against the shipped map before it existed.

A pc of 0 (a jump through a NULL/clobbered code pointer) is reported as UNATTRIBUTABLE rather
than mapped to the first function, which is what a naive bisect-left would do.

USAGE
    kitty-crash-attribute.py <report.ips> [--json]
    kitty-crash-attribute.py --control <stripped.so> --against <symbolized.so>
        Positive control: rebuild the map from the stripped binary and check the names it
        recovers against `nm` on a symbol-bearing build of the same version.
"""
from __future__ import annotations

import bisect
import json
import os
import re
import struct
import subprocess
import sys

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_UUID = 0x1B
LC_FUNCTION_STARTS = 0x26

CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86_64 = 0x01000007
ARCH_NAME = {CPU_TYPE_ARM64: "arm64", CPU_TYPE_X86_64: "x86_64"}


class MachO:
    """One slice of a (possibly fat) Mach-O, parsed only as far as this tool needs."""

    def __init__(self, data: bytes, slice_off: int):
        self.data = data
        self.off = slice_off
        magic, cputype, _cpusub, _ft, ncmds, _sz, _fl, _res = struct.unpack_from(
            "<IiiIIIII", data, slice_off
        )
        if magic != MH_MAGIC_64:
            raise ValueError(f"not a 64-bit Mach-O slice at {slice_off}")
        self.cputype = cputype & 0xFFFFFFFF
        self.arch = ARCH_NAME.get(self.cputype, hex(self.cputype))
        self.segments: list[dict] = []
        self.sections: dict[str, dict] = {}
        self.uuid: str | None = None
        self.func_starts: tuple[int, int] | None = None
        p = slice_off + 32
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", data, p)
            if cmd == LC_SEGMENT_64:
                name = data[p + 8 : p + 24].rstrip(b"\0").decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, p + 24)
                nsects = struct.unpack_from("<I", data, p + 64)[0]
                self.segments.append(
                    dict(name=name, vmaddr=vmaddr, vmsize=vmsize, fileoff=fileoff, filesize=filesize)
                )
                sp = p + 72
                for _s in range(nsects):
                    sname = data[sp : sp + 16].rstrip(b"\0").decode()
                    saddr, ssize = struct.unpack_from("<QQ", data, sp + 32)
                    self.sections[sname] = dict(addr=saddr, size=ssize, seg=name)
                    sp += 80
            elif cmd == LC_UUID:
                b = data[p + 8 : p + 24]
                self.uuid = "%s-%s-%s-%s-%s" % (
                    b[0:4].hex(), b[4:6].hex(), b[6:8].hex(), b[8:10].hex(), b[10:16].hex()
                )
            elif cmd == LC_FUNCTION_STARTS:
                dataoff, datasize = struct.unpack_from("<II", data, p + 8)
                self.func_starts = (dataoff, datasize)
            p += cmdsize

    # -- address translation -------------------------------------------------
    def read(self, vmaddr: int, n: int) -> bytes:
        for s in self.segments:
            if s["vmaddr"] <= vmaddr < s["vmaddr"] + s["vmsize"] and s["filesize"]:
                fo = self.off + s["fileoff"] + (vmaddr - s["vmaddr"])
                return self.data[fo : fo + n]
        return b""

    def cstring(self, vmaddr: int, limit: int = 512) -> str:
        b = self.read(vmaddr, limit)
        z = b.find(b"\0")
        return b[:z].decode("utf-8", "replace") if z >= 0 else ""

    def section_range(self, name: str) -> tuple[int, int]:
        s = self.sections.get(name)
        if not s:
            return (0, 0)
        return (s["addr"], s["addr"] + s["size"])

    # -- LC_FUNCTION_STARTS --------------------------------------------------
    def function_starts(self) -> list[int]:
        if not self.func_starts:
            return []
        off, size = self.func_starts
        blob = self.data[self.off + off : self.off + off + size]
        text_base = self.sections.get("__text", {}).get("addr")
        if text_base is None:
            return []
        # The table is deltas from the image base (the __TEXT segment vmaddr, normally 0).
        base = self.segments[0]["vmaddr"] if self.segments else 0
        out: list[int] = []
        addr = base
        i = 0
        while i < len(blob):
            shift = 0
            delta = 0
            while True:
                if i >= len(blob):
                    return sorted(set(out))
                byte = blob[i]
                i += 1
                delta |= (byte & 0x7F) << shift
                shift += 7
                if not (byte & 0x80):
                    break
            if delta == 0:  # terminator
                break
            addr += delta
            out.append(addr)
        return sorted(set(out))


def fat_slices(path: str) -> list[tuple[int, int]]:
    """-> [(cputype, file offset)] for each slice; a thin file yields one at 0."""
    data = open(path, "rb").read(4096)
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (FAT_MAGIC,):
        n = struct.unpack_from(">I", data, 4)[0]
        out = []
        for i in range(n):
            cputype, _sub, off, _size, _al = struct.unpack_from(">IIIII", data, 8 + i * 20)
            out.append((cputype, off))
        return out
    return [(struct.unpack_from("<i", data, 4)[0] & 0xFFFFFFFF, 0)]


def load_slice(path: str, want_arch: str | None = None) -> MachO:
    data = open(path, "rb").read()
    slices = fat_slices(path)
    cand = []
    for cputype, off in slices:
        try:
            m = MachO(data, off)
        except ValueError:
            continue
        cand.append(m)
    if want_arch:
        for m in cand:
            if m.arch == want_arch:
                return m
    if not cand:
        raise ValueError(f"no 64-bit slice in {path}")
    return cand[0]


def rebase_map(path: str, arch: str) -> dict[int, int]:
    """address -> rebase target, via dyld_info. Chained fixups mean the on-disk word is not
    the final address, so this is read from the system tool rather than re-derived."""
    cmd = ["dyld_info", "-arch", arch, "-fixups", path]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {}
    reb: dict[int, int] = {}
    for ln in out.stdout.splitlines():
        p = ln.split()
        if len(p) >= 5 and p[3] == "rebase":
            try:
                reb[int(p[2], 16)] = int(p[4], 16)
            except ValueError:
                continue
    return reb


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


def method_table(m: MachO, path: str) -> dict[int, tuple[str, int]]:
    """meth address -> (python method name, ml_flags), recovered from PyMethodDef arrays."""
    text = m.section_range("__text")
    cstr = m.section_range("__cstring")
    if not text[1] or not cstr[1]:
        return {}
    reb = rebase_map(path, m.arch)
    found: dict[int, tuple[str, int]] = {}
    for a in sorted(reb):
        t0 = reb[a]
        if not (cstr[0] <= t0 < cstr[1]):
            continue
        t1 = reb.get(a + 8)
        if t1 is None or not (text[0] <= t1 < text[1]):
            continue
        raw = m.read(a + 16, 4)
        if len(raw) != 4:
            continue
        flags = struct.unpack("<i", raw)[0]
        if not (0 <= flags <= 0x1000):
            continue
        name = m.cstring(t0, 256)
        if not name or not IDENT.match(name):
            continue
        found.setdefault(t1, (name, flags))
    return found


# -- ARM64 load decoding: turns "consistent with" into "proven" ---------------
def decode_load(word: int) -> tuple[str, int] | None:
    """-> (mnemonic, byte offset dereferenced) for the load forms that produce a near-NULL
    fault, so the decoded offset can be checked against the report's fault ADDRESS."""
    op = (word >> 24) & 0x3F
    size = (word >> 30) & 3
    scale = {0: 1, 1: 2, 2: 4, 3: 8}[size]
    if op == 0x39 and ((word >> 22) & 3) == 1:  # LDR immediate, unsigned offset
        return ("ldr", ((word >> 10) & 0xFFF) * scale)
    if op == 0x38 and ((word >> 21) & 1) == 0 and ((word >> 10) & 3) == 0:  # LDUR
        imm9 = (word >> 12) & 0x1FF
        if imm9 & 0x100:
            imm9 -= 0x200
        return ("ldur", imm9)
    if (word >> 22) & 0x3FF in (0x149, 0x169, 0x2A5, 0x2C5):
        pass
    # LDP signed offset: opc(2) 101 0 010 1 imm7 Rt2 Rn Rt
    if ((word >> 22) & 0x1FF) in (0x0A5, 0x1A5, 0x2A5):
        opc = (word >> 30) & 3
        psize = {0: 4, 1: 4, 2: 8}.get(opc, 8)
        imm7 = (word >> 15) & 0x7F
        if imm7 & 0x40:
            imm7 -= 0x80
        return ("ldp", imm7 * psize)
    return None


# -- ADRP/ADD literal recovery: names an INTERNAL function from its own strings ----
def adrp_literals(m: "MachO", start: int, end: int, limit: int = 4096) -> set[str]:
    """cstrings referenced by adrp+add pairs inside [start, end).

    The PyMethodDef trick only reaches Python-callable entry points. A thread entry
    function is not one, so it resolves to "internal" and stops there. But a third table
    survives stripping for the same reason the other two do — the program READS it at
    runtime: its own string literals, in __cstring, reached by an adrp/add pair whose
    displacement is baked into the instruction stream. That is enough to recognise a
    function whose literal is distinctive, and a thread entry's pthread_setname_np
    argument is exactly that.
    """
    text0, text1 = m.section_range("__text")
    c0, c1 = m.section_range("__cstring")
    if not c1 or not (text0 <= start < text1):
        return set()
    end = min(end if end else start + limit, start + limit, text1)
    blob = m.read(start, end - start)
    pages: dict[int, int] = {}
    out: set[str] = set()
    for i in range(0, len(blob) - 3, 4):
        word = struct.unpack_from("<I", blob, i)[0]
        pc = start + i
        if (word >> 24) & 0x9F == 0x90:  # ADRP Rd, page
            immlo = (word >> 29) & 3
            immhi = (word >> 5) & 0x7FFFF
            imm = (immhi << 2) | immlo
            if imm & (1 << 20):
                imm -= 1 << 21
            pages[word & 0x1F] = (pc & ~0xFFF) + (imm << 12)
        elif (word >> 23) & 0x1FF == 0x122:  # ADD (immediate, 64-bit)
            rn = (word >> 5) & 0x1F
            base = pages.get(rn)
            if base is None:
                continue
            imm12 = (word >> 10) & 0xFFF
            if (word >> 22) & 1:
                imm12 <<= 12
            addr = base + imm12
            if c0 <= addr < c1:
                sv = m.cstring(addr, 128)
                if sv and sv.isprintable():
                    out.add(sv)
    return out


def fault_instruction(m: MachO, pc: int) -> dict:
    raw = m.read(pc, 4)
    if len(raw) != 4:
        return {}
    word = struct.unpack("<I", raw)[0]
    d = decode_load(word)
    out = {"word": f"0x{word:08x}"}
    if d:
        out["mnemonic"], out["deref_offset"] = d[0], d[1]
    return out


# -- crash report ------------------------------------------------------------
def load_report(path: str) -> dict:
    raw = open(path, "r", errors="replace").read()
    i = raw.index("\n")
    body = json.loads(raw[i:])
    body["_header"] = json.loads(raw[:i])
    return body


class Attributor:
    def __init__(self):
        self._cache: dict[str, object] = {}

    def for_image(self, img: dict, arch: str):
        """-> (MachO, starts, methods) or a string explaining the refusal."""
        path = img.get("path") or ""
        key = path + "|" + arch
        if key in self._cache:
            return self._cache[key]
        if not path or not os.path.exists(path):
            res = f"binary not on disk: {path or '<none>'}"
        else:
            try:
                m = load_slice(path, arch)
            except Exception as e:  # noqa: BLE001
                res = f"unreadable: {e}"
            else:
                want = (img.get("uuid") or "").lower()
                have = (m.uuid or "").lower()
                if want and have and want != have:
                    res = (
                        f"REFUSED: uuid mismatch — report {want}, on-disk {have}. "
                        "Offsets do not transfer between builds."
                    )
                else:
                    res = (m, m.function_starts(), method_table(m, path))
        self._cache[key] = res
        return res

    def frame(self, img: dict, off: int, arch: str, thread_name: str | None = None) -> dict:
        out = {"image": img.get("name"), "offset": off}
        if off == 0:
            out["resolution"] = "UNATTRIBUTABLE: pc is 0 (jump through a NULL code pointer)"
            return out
        got = self.for_image(img, arch)
        if isinstance(got, str):
            out["resolution"] = got
            return out
        m, starts, methods = got
        if not starts:
            out["resolution"] = "no LC_FUNCTION_STARTS in this binary"
            return out
        i = bisect.bisect_right(starts, off) - 1
        if i < 0:
            out["resolution"] = "offset precedes the first function"
            return out
        st = starts[i]
        end = starts[i + 1] if i + 1 < len(starts) else None
        out["func_start"] = f"0x{st:x}"
        out["into_func"] = off - st
        if end is not None:
            out["func_size"] = end - st
        nm = methods.get(st)
        if nm:
            out["function"] = nm[0]
            out["ml_flags"] = nm[1]
            out["resolution"] = f"{nm[0]} (PyCFunction, ml_flags={nm[1]})"
        else:
            out["resolution"] = "internal (not a module-level PyCFunction)"
            # A thread entry is internal by construction. If the report says the faulting
            # thread is named N and this function is the one that contains the literal N,
            # the two independent facts agree and the function IS that thread's entry.
            # Cross-checked, never guessed: an unmatched literal is not reported at all.
            if thread_name and end is not None:
                lits = adrp_literals(m, st, end)
                if thread_name in lits:
                    out["thread_entry"] = thread_name
                    out["resolution"] = (
                        f'thread entry for "{thread_name}" '
                        "(matched against the report's own thread name)"
                    )
        return out

    def frame_at_fault(self, img: dict, off: int, arch: str, thread_name: str | None = None) -> dict:
        """frame() plus the decoded instruction. Only frame 0's pc is the faulting
        address; decoding a RETURN address further up names an instruction that completed
        successfully, which reads as evidence and is not."""
        out = self.frame(img, off, arch, thread_name)
        got = self.for_image(img, arch)
        if not isinstance(got, str) and off:
            fi = fault_instruction(got[0], off)
            if fi:
                out["insn"] = fi
        return out


def attribute_report(path: str) -> dict:
    b = load_report(path)
    arch = "arm64" if "ARM" in str(b.get("cpuType", "")) else "x86_64"
    imgs = b["usedImages"]
    ft = b.get("faultingThread", 0)
    ex = b.get("exception", {}) or {}
    att = Attributor()
    tname = (b["threads"][ft].get("name") or "").strip() or None
    frames = []
    for n, fr in enumerate(b["threads"][ft]["frames"]):
        img = imgs[fr["imageIndex"]]
        fn = att.frame_at_fault if n == 0 else att.frame
        frames.append(dict(n=n, **fn(img, fr.get("imageOffset", 0), arch, tname)))
    res = {
        "report": os.path.basename(path),
        "arch": arch,
        "thread_name": tname,
        "signal": ex.get("signal"),
        "subtype": ex.get("subtype"),
        "frames": frames,
    }
    fa = None
    mm = re.search(r"at (0x[0-9a-fA-F]+)", ex.get("subtype") or "")
    if mm:
        fa = int(mm.group(1), 16)
    res["fault_address"] = fa
    if fa is not None and frames:
        ins = frames[0].get("insn") or {}
        if "deref_offset" in ins:
            res["fault_offset_matches_instruction"] = ins["deref_offset"] == fa
    return res


def render(res: dict) -> str:
    hdr = f"{res['report']}  [{res['arch']}]  {res.get('signal')}  {res.get('subtype')}"
    if res.get("thread_name"):
        hdr += f"\n  faulting thread: {res['thread_name']}"
    L = [hdr]
    for f in res["frames"][:12]:
        line = f"  f{f['n']:<2} {f.get('image')}+{f.get('offset')}"
        if "func_start" in f:
            line += f"  func {f['func_start']}+{f['into_func']}"
        line += f"  -> {f.get('resolution')}"
        L.append(line)
        ins = f.get("insn") or {}
        if "deref_offset" in ins:
            d = ins["deref_offset"]
            sign = "-" if d < 0 else "+"
            L.append(
                f"       insn {ins['word']} {ins['mnemonic']} "
                f"dereferences {sign}0x{abs(d):x}"
            )
    m = res.get("fault_offset_matches_instruction")
    if m is True:
        L.append("  VERIFIED: the faulting instruction's dereference offset EQUALS the fault address")
    elif m is False:
        L.append("  NOTE: decoded dereference offset does not equal the fault address")
    return "\n".join(L)


def control(stripped: str, symbolized: str) -> int:
    """Positive control: does the method-table map reproduce nm on a build where nm works?"""
    m = load_slice(symbolized, None)
    methods = method_table(m, symbolized)
    if not methods:
        print("control: no method table recovered from the symbolized build", file=sys.stderr)
        return 1
    sym: dict[int, str] = {}
    out = subprocess.run(["nm", "-n", symbolized], capture_output=True, text=True)
    for ln in out.stdout.splitlines():
        p = ln.split()
        if len(p) == 3 and p[1] in ("t", "T"):
            sym[int(p[0], 16)] = p[2]
    agree = differ = unmapped = 0
    examples = []
    for addr, (name, _fl) in methods.items():
        s = sym.get(addr)
        if s is None:
            unmapped += 1
            continue
        bare = s.lstrip("_")
        if bare in (name, "py" + name, "pyw_" + name, name + "_"):
            agree += 1
        else:
            differ += 1
            if len(examples) < 6:
                examples.append(f"{name} -> {s}")
    total = len(methods)
    print(f"control: {total} method-table entries recovered from {os.path.basename(symbolized)}")
    print(f"  name agrees with nm symbol : {agree}")
    print(f"  python name != C symbol    : {differ}   (expected: MW() wrappers rename)")
    print(f"  address not in nm          : {unmapped}")
    for e in examples:
        print(f"    e.g. {e}")
    # The control passes on ADDRESS agreement, which is what attribution rests on.
    mapped = agree + differ
    if mapped == 0:
        print("control: FAIL — no recovered address matched any nm symbol", file=sys.stderr)
        return 1
    ratio = mapped / total
    print(f"  addresses that ARE real function symbols: {mapped}/{total} ({ratio:.1%})")
    if ratio < 0.90:
        print("control: FAIL — too many recovered addresses are not functions", file=sys.stderr)
        return 1
    print("control: PASS")
    return 0


def main(argv: list[str]) -> int:
    if "--control" in argv:
        i = argv.index("--control")
        j = argv.index("--against")
        return control(argv[i + 1], argv[j + 1])
    args = [a for a in argv[1:] if not a.startswith("-")]
    if not args:
        print(__doc__)
        return 2
    rc = 0
    for p in args:
        try:
            res = attribute_report(p)
        except Exception as e:  # noqa: BLE001
            print(f"{p}: could not read: {e}", file=sys.stderr)
            rc = 1
            continue
        if "--json" in argv:
            print(json.dumps(res, indent=1))
        else:
            print(render(res))
            print()
        if any("REFUSED" in (f.get("resolution") or "") for f in res["frames"]):
            rc = 3
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
