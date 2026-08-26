#!/usr/bin/env python3
"""Measure a local MLX vision-language model on THIS machine, across input resolutions.

Two published claims meet here and both are about resolution, not about model size:

  A. Downscaling a screenshot makes UI grounding MORE accurate, not less
     (mlx-vlm#1175: mean IoU 0.542 at 12.8 MP -> 0.736 at 1 MP), while also
     cutting prefill roughly in proportion to pixel count.
  B. No M1 Max VLM benchmark exists anywhere in public. Every fast number quoted
     for Apple Silicon VLMs is M4 Pro/Max or M5.

So this sweeps one screenshot across widths and records time-to-first-token,
decode rate, image-token count and the actual answer. The answer column is the
one that matters: a fast wrong answer is not a cheaper right answer.

The checkpoint under test is a UNIFORM 4-bit conversion, which the quantization
literature specifically indicts for spatial work (vision encoder 4-bit costs
8-15% on layout tasks; the projector is the worst bottleneck). That is deliberate:
this is the configuration a person gets by default from `mlx-community/*-4bit`,
so it is the one worth measuring before recommending against it.

Usage: python3 bench_local_vlm.py --model <hf-id> --image <png> [--widths 2560,1792,1344,1024]
"""

from __future__ import annotations

import argparse
import gc
import json
import pathlib
import time

import mlx.core as mx
from PIL import Image

PROMPT = (
    "You are reviewing a screenshot of a web dashboard for visual design defects. "
    "Look at spacing rhythm, alignment, text contrast, type hierarchy, and whether "
    "the eye is drawn to the correct primary action. "
    "Name the single most serious visual defect you can see, and say where it is. "
    "If the page looks correct, say exactly: NO DEFECT FOUND."
)


def prep(src: pathlib.Path, width: int, tmp: pathlib.Path) -> tuple[pathlib.Path, int]:
    im = Image.open(src).convert("RGB")
    if im.width != width:
        h = round(im.height * width / im.width)
        im = im.resize((width, h), Image.LANCZOS)
    out = tmp / f"w{width}.png"
    im.save(out)
    # Qwen-family VLMs tokenize at one token per 28x28 patch, then merge 2x2.
    tokens = (im.width // 28) * (im.height // 28) // 4
    return out, tokens


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--image", required=True, type=pathlib.Path)
    ap.add_argument("--widths", default="2560,1792,1344,1024")
    ap.add_argument("--max-tokens", type=int, default=160)
    ap.add_argument(
        "--out", type=pathlib.Path, default=pathlib.Path("local_vlm_results.json")
    )
    a = ap.parse_args()

    from mlx_vlm import load, generate
    from mlx_vlm.prompt_utils import apply_chat_template

    tmp = pathlib.Path("_bench_tmp")
    tmp.mkdir(exist_ok=True)

    print(f"loading {a.model} ...")
    t0 = time.perf_counter()
    model, processor = load(a.model)
    load_s = time.perf_counter() - t0
    cfg = model.config if hasattr(model, "config") else None
    peak_after_load = mx.get_peak_memory() / 1e9
    print(f"  loaded in {load_s:.1f}s | peak GPU mem {peak_after_load:.1f} GB")

    rows = []
    for w in [int(x) for x in a.widths.split(",")]:
        img, est_tokens = prep(a.image, w, tmp)
        px = Image.open(img).size
        mx.reset_peak_memory()
        # One untimed warm pass would hide the cold cost this workload actually pays:
        # a design-review loop shows a NEW screenshot every iteration, so the vision
        # encode is never cached. Measure cold, on purpose.
        t0 = time.perf_counter()
        try:
            fmt = apply_chat_template(processor, cfg, PROMPT, num_images=1)
            res = generate(
                model,
                processor,
                fmt,
                [str(img)],
                max_tokens=a.max_tokens,
                verbose=False,
            )
            text = res.text if hasattr(res, "text") else str(res)
            gen_tps = getattr(res, "generation_tps", None)
            prompt_tps = getattr(res, "prompt_tps", None)
            ptoks = getattr(res, "prompt_tokens", None)
        except Exception as e:  # noqa: BLE001 - report, don't mask
            text, gen_tps, prompt_tps, ptoks = (
                f"ERROR: {type(e).__name__}: {e}",
                None,
                None,
                None,
            )
        wall = time.perf_counter() - t0
        peak = mx.get_peak_memory() / 1e9

        row = {
            "width": w,
            "pixels": f"{px[0]}x{px[1]}",
            "megapixels": round(px[0] * px[1] / 1e6, 2),
            "est_image_tokens": est_tokens,
            "prompt_tokens": ptoks,
            "wall_s": round(wall, 2),
            "prompt_tps": round(prompt_tps, 1) if prompt_tps else None,
            "gen_tps": round(gen_tps, 1) if gen_tps else None,
            "peak_gpu_gb": round(peak, 1),
            "answer": text.strip()[:400],
        }
        rows.append(row)
        print(
            f"\n  [{w}px  {row['megapixels']} MP  ~{est_tokens} img-tok]  "
            f"wall {wall:.1f}s  prefill {row['prompt_tps'] or '?'} t/s  "
            f"decode {row['gen_tps'] or '?'} t/s  peak {peak:.1f} GB"
        )
        print(f"    -> {row['answer'][:220]}")
        gc.collect()

    out = {
        "machine": "Apple M1 Max, 64 GB unified, 32-core GPU",
        "model": a.model,
        "quantization": "uniform 4-bit (LLM + vision tower + projector)",
        "image": str(a.image),
        "load_s": round(load_s, 1),
        "peak_after_load_gb": round(peak_after_load, 1),
        "note": "cold vision encode every row -- matches a review loop, which never "
        "shows the same screenshot twice",
        "rows": rows,
    }
    a.out.write_text(json.dumps(out, indent=2))
    print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
