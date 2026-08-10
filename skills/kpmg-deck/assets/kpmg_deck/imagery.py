"""
imagery.py -- the colour treatment, baked into pixels because PowerPoint cannot do it.

THE PROBLEM THIS SOLVES: the engine had no imagery at all. Six of the nine real KPMG slides
the FY22 brand book prints on p.113 carry a photograph, and the book spends thirteen pages
(pp.97-109) plus four more inside the window section (pp.90-93) on how an image is treated.
`add_picture` was used here for exactly one thing, the logo. A deck with no imagery is the
single largest reason a correct palette still reads as "a blue theme".

WHY THE TREATMENT IS BAKED RATHER THAN DRAWN. The book's treatment is a stack of BLEND MODES:
Overlay at 65%, or Soft Light at 100% with the same gradient again in Multiply at 40%. OOXML
shape fills have no blend modes -- `a:blip` carries `alphaModFix`, `duotone`, `lum` and a
handful of colour transforms, and none of them is Overlay. The only two options are to
approximate the look with a translucent flat rectangle, which is a duotone by another name and
destroys exactly what the book protects, or to composite the real thing in Pillow and insert a
flat PNG. This module does the second. Everything downstream then sees one picture.

THE THREE RECIPES, ALL STATED, ALL SANCTIONED (bb FY22 p.92: "note that each of these
approaches is approved for use"):

    neutral                 the image is left as a neutral photograph and the COLOUR sits
                            behind it -- window style 3, p.92 step 4. The contrast between a
                            neutral foreground and a saturated ground is the composition; an
                            overlaid image on a gradient ground is two of the same thing.
    overlay      65%        p.91's worked example and p.92 step 2, "moderate transparency".
                            Retains photographic detail; the correct choice where the image is
                            one block of a working page rather than the whole page.
    softlight_multiply      p.93's fully worked three-panel example: Soft Light at 100%, then
                            THE SAME gradient again in Multiply at 40%. The Soft Light layer is
                            retained beneath the Multiply layer, not replaced by it.

The 40% is not a house choice. The three panels on p.93 were extracted and the model
`final = soft x (0.6 + 0.4 x G/255)` tested against the book's own final panel: mean absolute
error 16.5/255 against a null model's 34/255, minimised at alpha = 0.4 across a 0.2-0.6 sweep.

TWO PROHIBITIONS ARE LOAD-BEARING AND BOTH ARE INVISIBLE TO EVERY MECHANICAL CHECK:

  1. Exactly two gradients exist and inventing others is forbidden (p.46). This module reads
     both from `oxml`, so there is one definition of each in the package and no path by which a
     third can appear.
  2. "Don't leave skin tones with color effects in hero imagery" (p.106, prohibition 4) -- the
     book's most visible prohibition, and the one a naive full-frame overlay breaks on every
     photograph containing a person. `skin_blend` is the fix and it is arithmetic, not
     judgment: p.103's own step 5 is `0.6 x figure + 0.4 x colour-adjusted`, verified to 2/255
     per channel.

RIGHTS. We hold no licensed KPMG photography and this module must never let a deck imply
otherwise. Both source routes are built: `synthetic_field` generates rights-clean abstract
imagery of our own, and `load_source` takes any external file, so licensed photography drops
into the identical slot with no code change. Every image carries its own provenance in
`Image.info`, which the archetypes read and write into the build log -- so a deck built on
generated imagery says so in its own build output rather than in someone's memory.
"""

from __future__ import annotations

import io
import math
from dataclasses import dataclass
from typing import Literal, Sequence

import numpy as np
from PIL import Image, ImageFilter, ImageOps

from .oxml import GRADIENT_PRIMARY, GRADIENT_SUPPORT
from .tokens import contrast_ratio

__all__ = [
    "GRADIENTS",
    "Neutrality",
    "crop_to_fill",
    "deepen_for_type",
    "load_source",
    "neutralise",
    "neutrality",
    "provenance",
    "region_color",
    "synthetic_field",
    "to_png_bytes",
    "treat",
]

# The two gradients, read from the single definition in `oxml` rather than restated. p.46 is a
# closed set: PRIMARY Purple #7213EA -> Cobalt #1E49E2, SUPPORT Pacific #00B8F5 -> Light Blue
# #ACEAFF, stops at 0% and 100%, midpoint 50%, 0 degree angle, linear and never radial.
GRADIENTS: dict[str, Sequence[tuple[float, str]]] = {
    "primary": GRADIENT_PRIMARY,
    "support": GRADIENT_SUPPORT,
}

# p.99 and p.92 both make this asymmetric and it is easy to miss: SUPPORT is a flat opaque
# colour and PRIMARY is the one that goes over a photograph. "Window styles 1 and 4 use the
# Purple/Cobalt gradient as a transparency overlay on imagery" -- the support ramp is named
# nowhere in that role.
TREATMENT_GRADIENT = "primary"

# Stated opacities. Named rather than inlined so a reader can see there are only two numbers
# here and that neither was chosen by us.
OVERLAY_ALPHA = 0.65  # p.91 fourth panel, p.92 step 2
MULTIPLY_ALPHA = 0.40  # p.93 final panel, independently confirmed by measurement

# p.103's step 5, as a range. The book's own worked example sits at 0.6.
SKIN_BLEND_MIN, SKIN_BLEND_MAX = 0.40, 0.60

# p.92's depth ramp. The page gives no numbers -- it prints four treatments along a bar
# captioned "gradient increasing depth/darkness" and describes each in words. These two are
# ours, chosen to sit either side of the stated recipe rather than to reproduce a measurement,
# and they are labelled as inferred wherever they are cited.
DEPTH_LIGHT = 0.55  # how much of the treated result survives at "light transparency"
DEPTH_DEEP_MULTIPLY = 0.30  # the extra Multiply pass at "moderate" -> "moderate-deep"

# p.91's Hue/Saturation adjustment layer, read directly off the reproduced Photoshop panel:
# Master channel, Hue 0, Saturation -50, Lightness +40.
NEUTRAL_SATURATION = -50.0
NEUTRAL_LIGHTNESS = +40.0

PROVENANCE_KEY = "kpmg_deck_provenance"

Treatment = Literal["neutral", "overlay", "softlight_multiply"]
Depth = Literal["light", "moderate", "moderate_deep"]
Region = tuple[float, float, float, float]  # (left, top, right, bottom) as fractions


# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------


def provenance(img: Image.Image) -> str:
    """
    Where this image came from, as a sentence fit for a build log.

    Carried in `Image.info` and propagated through every operation in this module, because the
    alternative -- the caller remembering -- is exactly the memory that fails on the deck that
    matters. An untagged image reports as unknown rather than as licensed.
    """
    return str(img.info.get(PROVENANCE_KEY, "source not recorded"))


def _carry(src: Image.Image, dst: Image.Image) -> Image.Image:
    dst.info[PROVENANCE_KEY] = src.info.get(PROVENANCE_KEY, "source not recorded")
    return dst


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------


def load_source(path: str) -> Image.Image:
    """
    Any external image file, ready for `treat()`.

    THIS IS THE SLOT LICENSED PHOTOGRAPHY DROPS INTO, WITH NO CODE CHANGE ANYWHERE. Hand it a
    KPMG-licensed JPEG or TIFF and every archetype behaves identically -- the treatment, the
    geometry and the contrast measurement are all downstream of this call and none of them
    knows or cares whether the pixels were generated or photographed. The only difference is
    the provenance line in the build log, which is the difference that matters.

    EXIF orientation is applied on the way in. A phone photograph whose orientation lives only
    in a metadata tag renders sideways in PowerPoint, and no check in this package would see
    it.
    """
    img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    img.info[PROVENANCE_KEY] = f"licensed/external source file: {path}"
    return img


def synthetic_field(
    width: int,
    height: int,
    *,
    seed: int,
    kind: Literal["ribbon", "depth", "structure", "strata"] = "depth",
) -> Image.Image:
    """
    Rights-clean abstract source imagery, generated here. `width`/`height` are PIXELS.

    WHY THIS EXISTS RATHER THAN A STOCK PHOTOGRAPH: we hold no licensed KPMG photography, and a
    deck that quietly borrowed some would be a rights problem wearing a design solution. What
    is generated here is ours, so it can ship.

    WHAT IT IS AIMING AT, AND THE TARGET IS THE BOOK'S OWN. p.107 gives an "allowable spectrum
    of neutrality" and four accepted example images; measured across their pixels those average
    75.4% of pixels below 0.20 saturation, which independently corroborates the stated
    "approximate 70% overall neutral tone", and every one carries a small "hit of color"
    (0.5%-17% of pixels above 0.40 saturation, never zero). The rejected example fails on all
    five measures. So these fields are built neutral-with-a-pop by construction rather than by
    taste, and `neutrality()` measures any image against that envelope.

    Three kinds, chosen because they are the three subjects the book's own support imagery
    keeps returning to and because each survives the treatment differently:

        depth       soft depth-of-field field -- large out-of-focus forms, a bright subject
                    region, a falloff. The most forgiving under a heavy overlay.
        structure   architectural: receding vertical slabs, a soffit, a lit floor. Holds its
                    edges under Soft Light, which is what makes a window-held image read as a
                    photograph rather than as a texture.
        strata      layered landform under haze. The widest tonal range of the three, so it is
                    the one to reach for when type has to sit over the image.

    `seed` is required, not defaulted. An unseeded field is a different image on every build,
    which means the deck a reviewer approved is not the deck that ships.
    """
    if width < 16 or height < 16:
        raise ValueError(f"synthetic_field needs a sensible size, got {width}x{height}")
    rng = np.random.default_rng(seed)
    builder = {
        "ribbon": _field_ribbon,
        "depth": _field_depth,
        "structure": _field_structure,
        "strata": _field_strata,
    }
    if kind not in builder:
        raise ValueError(f"kind must be one of {sorted(builder)}, got {kind!r}")

    lum, pop = builder[kind](width, height, rng)
    rgb = _tint(lum, pop)
    img = Image.fromarray(
        (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB"
    )
    img.info[PROVENANCE_KEY] = (
        f"SYNTHETIC: generated abstract imagery, kind={kind!r} seed={seed} "
        f"-- NOT KPMG photography"
    )
    return img


# ---------------------------------------------------------------------------
# The treatment
# ---------------------------------------------------------------------------


def treat(
    img: Image.Image,
    *,
    gradient: str = TREATMENT_GRADIENT,
    mode: Treatment = "softlight_multiply",
    neutral: bool = False,
    subject_mask: Image.Image | None = None,
    skin_blend: float = 0.0,
    depth: Depth = "moderate",
    flip: bool = False,
) -> Image.Image:
    """
    Apply the brand colour treatment to an image and return a new one. bb FY22 pp.91-93, 103.

    The order is the book's, and it is not interchangeable:

        1. NEUTRALISE (p.91)   Hue/Saturation, Saturation -50, Lightness +40, with the subject
                               masked OUT of the edit. Only when `neutral=True`; an image that
                               is already neutral does not want this and the book warns
                               explicitly to "be mindful of any degradation of the image during
                               the process of adjustment".
        2. COLOUR (p.92/93)    the gradient, in the stated blend mode at the stated opacity.
        3. SKIN (p.103)        the untreated figure blended back over the mask at 40-60%
                               Normal. Last, because it must undo step 2 locally and nothing
                               after it may re-tint the figure.

    `mode="neutral"` runs step 1 and skips step 2 entirely. That is not a degenerate case: it
    is window style 3, where the gradient is opaque BEHIND the image (p.92 step 4) and putting
    it over the image as well would collapse the foreground/background contrast the whole
    device depends on (p.90).

    `subject_mask` is an "L"-mode image the size of `img`, white where the subject is. It does
    two jobs and they are opposite: it excludes the subject from the neutralising edit, and it
    is the region the untreated figure is blended back into.

    `skin_blend` above zero without a mask raises. A skin-tone rescue with no idea where the
    skin is would be a number with no effect, and silently having no effect is how the book's
    most visible prohibition gets shipped.

    `flip` reverses the gradient direction. p.46 permits it -- "flipping is permitted if the
    location and midpoint are kept" -- and it is the only variation this module allows.
    """
    if gradient not in GRADIENTS:
        raise ValueError(
            f"gradient must be one of {sorted(GRADIENTS)}, got {gradient!r}"
        )
    if skin_blend and subject_mask is None:
        raise ValueError(
            "skin_blend needs subject_mask: an 'L' image, white where the figure is. "
            "Without it the blend has nowhere to apply and would silently do nothing, which "
            'is how bb FY22 p.106 prohibition 4 ("do not leave skin tones with color effects '
            'in hero imagery") gets shipped.'
        )
    if skin_blend and not (SKIN_BLEND_MIN <= skin_blend <= SKIN_BLEND_MAX):
        raise ValueError(
            f"skin_blend must be within the stated {SKIN_BLEND_MIN:.0%}-{SKIN_BLEND_MAX:.0%} "
            f"band (bb FY22 p.103), got {skin_blend:.0%}"
        )

    base = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    original = base.copy()
    mask = None
    if subject_mask is not None:
        if subject_mask.size != img.size:
            subject_mask = subject_mask.resize(img.size, Image.BICUBIC)
        mask = (np.asarray(subject_mask.convert("L"), dtype=np.float32) / 255.0)[
            ..., None
        ]

    if neutral:
        base = _neutralise_array(base, mask)

    if mode == "neutral":
        out = base
    else:
        h, w = base.shape[:2]
        grad = _gradient_layer(w, h, gradient, flip=flip)
        if mode == "overlay":
            # p.91's fourth panel and p.92 step 2. One layer, 65%.
            out = base * (1.0 - OVERLAY_ALPHA) + _overlay(base, grad) * OVERLAY_ALPHA
        elif mode == "softlight_multiply":
            # p.93, both layers. The Soft Light is at 100% so there is no composite to do for
            # it; the Multiply is composited over the RESULT of the Soft Light, which is what
            # "the same gradient is placed with 40% opacity" means and what the measurement
            # confirmed. Writing it as soft * (0.6 + 0.4 * grad) is the same arithmetic with
            # one fewer temporary array.
            soft = _soft_light(base, grad)
            out = soft * ((1.0 - MULTIPLY_ALPHA) + MULTIPLY_ALPHA * grad)
        else:
            raise ValueError(
                f"mode must be neutral/overlay/softlight_multiply, got {mode!r}. "
                "bb FY22 p.92 is a closed set of approved approaches."
            )

        # THE DEPTH RAMP, p.92. The page prints four treatments across a bar captioned
        # "gradient increasing depth/darkness" and states that each is approved. It is a
        # SEPARATE AXIS from the blend recipe above -- the recipe decides how the colour meets
        # the image, the depth decides how much of the image survives it -- which is why this
        # is its own argument rather than four more mode strings. `moderate` is the stated
        # recipe untouched, so the default changes nothing.
        if depth == "light":
            # "The soft tones of the window transparency complement the light gray background;
            # the lightness of the window gradient softens the high-contrast portrait." The
            # image keeps its detail and the colour reads as a wash.
            out = base * (1.0 - DEPTH_LIGHT) + out * DEPTH_LIGHT
        elif depth == "moderate_deep":
            # "The neutral image is overlaid with the Purple/Cobalt gradient... increased
            # gradient darkness. If used at full opacity, photo details disappear." One more
            # Multiply pass of the same gradient, which is the book's own way of getting there.
            out = out * ((1.0 - DEPTH_DEEP_MULTIPLY) + DEPTH_DEEP_MULTIPLY * grad)
        elif depth != "moderate":
            raise ValueError(
                f"depth must be light/moderate/moderate_deep, got {depth!r}. "
                f"bb FY22 p.92 names a fourth, 'opaque', and it is NOT an image treatment: it "
                f"is the style-3 composition, where the gradient sits at full opacity BEHIND a "
                f"neutral image rather than over it. Build that with mode='neutral' and an "
                f"opaque gradient ground -- which is what Deck.window_image() does."
            )

    if skin_blend and mask is not None:
        # p.103 step 5, verbatim as arithmetic: 0.6 x figure + 0.4 x colour-adjusted, applied
        # only where the mask says there is a figure. The luminance of the original is
        # preserved by construction, which is the measurable property the book is protecting --
        # treated skin is allowed to move hue (it lands in the magenta band, 311-332 degrees),
        # it is not allowed to change value.
        out = out * (1.0 - mask * skin_blend) + original * (mask * skin_blend)

    return _carry(img, _to_image(out))


def neutralise(img: Image.Image, mask: Image.Image | None = None) -> Image.Image:
    """
    p.91's Hue/Saturation adjustment on its own: Saturation -50, Lightness +40, subject masked out.

    Exposed separately because the book treats it as a separate decision from the colour layer
    -- it is what you do to an image that "provides the right content, but not the right
    colour", and an image that is already neutral should not be run through it at all.
    """
    base = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    m = None
    if mask is not None:
        if mask.size != img.size:
            mask = mask.resize(img.size, Image.BICUBIC)
        m = (np.asarray(mask.convert("L"), dtype=np.float32) / 255.0)[..., None]
    return _carry(img, _to_image(_neutralise_array(base, m)))


# ---------------------------------------------------------------------------
# Measurement -- what the treated pixels actually are
# ---------------------------------------------------------------------------


def region_color(
    img: Image.Image,
    region: Region = (0.0, 0.0, 1.0, 1.0),
    *,
    bias: Literal["mean", "light", "dark"] = "mean",
) -> str:
    """
    The colour of a fractional region of the image, as '#RRGGBB'.

    THIS IS WHAT MAKES CONTRAST OVER AN IMAGE A MEASUREMENT RATHER THAN A HOPE. Every contrast
    check in this package resolves a run against the shape behind it, and a picture is not a
    filled shape -- `verify._filled_rects` reads `a:solidFill` and `a:gradFill` and a `p:pic`
    has neither. So type over a photograph is checked against the SLIDE background, which is
    whatever colour is hidden underneath the picture: a number with no relationship to what a
    reader sees. Sampling the baked pixels is the only honest ground, and it is available here
    precisely because the treatment is baked.

    `bias` IS THE DIFFERENCE BETWEEN A MEASUREMENT AND AN AVERAGE THAT HIDES THE FAILURE. A
    photograph is not a flat colour, and the mean of a region containing one bright band and a
    lot of shadow reports a comfortable mid tone while the type crossing that band is
    unreadable. So light type measures against `bias="light"` -- the mean of the brightest
    quarter of the region, which is the ground it will actually be worst against -- and dark
    type measures against `bias="dark"`. `bias="mean"` remains right for a region that has
    already been flattened by a scrim.
    """
    w, h = img.size
    x0, y0, x1, y1 = region
    box = (
        max(0, int(x0 * w)),
        max(0, int(y0 * h)),
        min(w, max(1, int(x1 * w))),
        min(h, max(1, int(y1 * h))),
    )
    px = np.asarray(img.convert("RGB").crop(box), dtype=np.float32).reshape(-1, 3)
    if bias != "mean":
        # Rank by the same weighted luminance WCAG uses, then keep the quartile that is worst
        # for the type in question.
        lum = px @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        order = np.argsort(lum)
        keep = max(1, len(order) // 4)
        order = order[-keep:] if bias == "light" else order[:keep]
        px = px[order]
    mean = px.mean(axis=0)
    return "#%02X%02X%02X" % tuple(int(round(float(v))) for v in mean)


@dataclass(frozen=True)
class Neutrality:
    """The p.107 spectrum, measured. `passes` is the book's own four accepted images' envelope."""

    neutral_share: float  # pixels below 0.20 saturation
    pop_share: float  # pixels above 0.40 saturation -- the "hit of color"
    mean_saturation: float
    dark_share: float  # pixels below 0.25 value
    passes: bool

    def describe(self) -> str:
        return (
            f"{self.neutral_share:.0%} neutral, {self.pop_share:.1%} pop, "
            f"mean saturation {self.mean_saturation:.2f}, {self.dark_share:.0%} dark "
            f"-- {'within' if self.passes else 'OUTSIDE'} the p.107 envelope"
        )


def neutrality(img: Image.Image) -> Neutrality:
    """
    Measure an image against p.107's spectrum of neutrality.

    The envelope is measured off the book's own four ACCEPTED support images and its one
    rejected one, which fails all five measures: at least 60% of pixels below 0.20 saturation,
    mean saturation at or under 0.20, and a hit of colour between 0.5% and 17% of pixels. The
    range is bounded at BOTH ends -- an image with no pop at all is as wrong as a rainbow, and
    that is the half of the rule a saturation ceiling alone would miss.

    Advisory, not enforcing. It applies to SUPPORT imagery; a hero image is deliberately
    outside it, and the book's own hero examples measure 0.33 and 0.56 mean saturation.
    """
    px = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    mx = px.max(axis=2)
    mn = px.min(axis=2)
    sat = np.where(mx > 0.0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    neutral_share = float((sat < 0.20).mean())
    pop_share = float((sat > 0.40).mean())
    mean_sat = float(sat.mean())
    dark_share = float((mx < 0.25).mean())
    return Neutrality(
        neutral_share,
        pop_share,
        mean_sat,
        dark_share,
        passes=(
            neutral_share >= 0.60 and mean_sat <= 0.20 and 0.005 <= pop_share <= 0.17
        ),
    )


# ---------------------------------------------------------------------------
# Making type legal over an image
# ---------------------------------------------------------------------------


def deepen_for_type(
    img: Image.Image,
    *,
    region: Region,
    fg: str,
    edge: Literal["bottom", "top", "left", "right"] = "bottom",
    min_ratio: float = 4.5,
    gradient: str = TREATMENT_GRADIENT,
    feather: float = 0.35,
) -> tuple[Image.Image, str]:
    """
    Deepen the SAME gradient over the region type will occupy, until that type is legal.
    Returns `(image, measured_ground_hex)`.

    THE RULE THIS DISCHARGES IS THE ENGINE'S OWN: a component picks its legal foreground from
    the ground it is standing on. Over a photograph nothing knows what that ground is, so the
    usual mechanism -- `Ctx.assert_legible` against a named canvas colour -- checks a colour
    the reader cannot see. This measures the pixels and returns the answer, so the caller can
    assert against reality and the verifier can be told the truth.

    THE SCRIM IS THE BRAND'S OWN GRADIENT AT A HIGHER MULTIPLY OPACITY, NOT A BLACK BOX. That
    is not decoration dressed up: p.92 step 3 sanctions exactly this lever in words -- "the
    blending mode is set to Overlay, which provides increased gradient darkness, but not full
    opacity" -- and the four-step ramp on that page is labelled "gradient increasing
    depth/darkness". A black or white scrim would introduce a value that is not in the palette
    and would read, correctly, as a fix applied afterwards. Ramping the brand gradient reads as
    the composition.

    The ramp runs from `edge`, smoothstepped over `feather` of the slide dimension, so the
    scrim has no visible boundary. A rectangular scrim with a soft edge is still a rectangle;
    an edge-anchored ramp is art direction.

    The region is measured at the bias that is WORST for `fg`, not at its mean -- see
    `region_color`. The colour returned is that worst-case, so a caller handing it to the
    verifier is handing over the number the type is actually up against.

    Raises rather than returning something illegible. A page whose type cannot be made legal
    over its own image is a page that has chosen the wrong image, and that is an editorial
    finding, not a rendering one.
    """
    if gradient not in GRADIENTS:
        raise ValueError(
            f"gradient must be one of {sorted(GRADIENTS)}, got {gradient!r}"
        )

    base = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    h, w = base.shape[:2]
    grad = _gradient_layer(w, h, gradient)
    ramp = _edge_ramp(w, h, region, edge, feather)[..., None]
    # Light type is worst against the region's brightest quarter and dark type against its
    # darkest, so the bias follows the foreground rather than being a caller's choice.
    bias: Literal["light", "dark"] = (
        "light"
        if contrast_ratio(fg, "#FFFFFF") < contrast_ratio(fg, "#000000")
        else "dark"
    )

    best_hex = region_color(img, region, bias=bias)
    if contrast_ratio(fg, best_hex) >= min_ratio:
        return img, best_hex

    # Walk the multiply opacity up in the book's own direction of travel. 0.85 is the stop:
    # past it the photograph has gone and the page would be better built as `full_field`.
    for alpha in (0.25, 0.40, 0.55, 0.70, 0.85):
        scrimmed = base * (1.0 - ramp * alpha * (1.0 - grad))
        candidate = _carry(img, _to_image(scrimmed))
        measured = region_color(candidate, region, bias=bias)
        if contrast_ratio(fg, measured) >= min_ratio:
            return candidate, measured
        best_hex = measured

    raise ValueError(
        f"type at {fg} cannot reach {min_ratio:.1f}:1 over this image even with the gradient "
        f"scrim at 85% multiply -- the region measures {best_hex} "
        f"({contrast_ratio(fg, best_hex):.2f}:1). Past this point the photograph has been "
        f"destroyed to save the type, and the honest fixes are a darker image, a smaller type "
        f"region, or `full_field()` with no photograph at all."
    )


# ---------------------------------------------------------------------------
# Geometry and output
# ---------------------------------------------------------------------------


def crop_to_fill(img: Image.Image, width: int, height: int) -> Image.Image:
    """
    Centre-crop and scale to exactly `width` x `height` PIXELS, never distorting.

    Anamorphic scaling is the one image defect a viewer spots without knowing why, and it is
    the default failure when a caller hands `add_picture` both a width and a height. Cropping
    is the correct trade: a composition loses its edges, which the photographer expected, and
    keeps its proportions, which nobody forgives losing.
    """
    if width < 1 or height < 1:
        raise ValueError(f"crop_to_fill needs a positive size, got {width}x{height}")
    src_w, src_h = img.size
    scale = max(width / src_w, height / src_h)
    inter_w, inter_h = (
        max(width, int(round(src_w * scale))),
        max(height, int(round(src_h * scale))),
    )
    resized = img.convert("RGB").resize((inter_w, inter_h), Image.LANCZOS)
    left = (inter_w - width) // 2
    top = (inter_h - height) // 2
    return _carry(img, resized.crop((left, top, left + width, top + height)))


def to_png_bytes(img: Image.Image) -> io.BytesIO:
    """
    A PNG stream ready for `shapes.add_picture`. Rewound, so the caller never has to remember.

    PNG rather than JPEG deliberately. The treated fields here are large areas of smooth
    gradient, which is the exact content JPEG bands visibly and PNG compresses well; and a
    lossy round-trip after a treatment computed to 2/255 would throw away the precision that
    made the treatment worth measuring.
    """
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="PNG", optimize=True)
    buf.seek(0)
    return buf


# ---------------------------------------------------------------------------
# Internals -- blend maths
# ---------------------------------------------------------------------------


def _to_image(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(
        (np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB"
    )


def _hex_to_rgb(value: str) -> tuple[float, float, float]:
    v = value.lstrip("#")
    return tuple(int(v[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def _gradient_layer(
    width: int, height: int, gradient: str, *, flip: bool = False
) -> np.ndarray:
    """
    The gradient as a pixel layer: two stops, linear, horizontal, 0 degrees. p.46.

    Interpolated straight in sRGB rather than in a linear-light space, because that is what
    Illustrator does in an sRGB document and it is what the book's own artwork measures as: the
    Normal-100% panel on p.93 reads (101, 31, 209) at the left and (5, 73, 253) at the right,
    which are Purple and Cobalt at the two ends with the green channel matching Cobalt's 73
    exactly. A perceptually "better" interpolation would produce a ramp KPMG's files do not
    contain.
    """
    stops = GRADIENTS[gradient]
    a = np.array(_hex_to_rgb(stops[0][1]), dtype=np.float32)
    b = np.array(_hex_to_rgb(stops[-1][1]), dtype=np.float32)
    if flip:
        a, b = b, a
    t = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :, None]
    return (a[None, None, :] * (1.0 - t) + b[None, None, :] * t).repeat(height, axis=0)


def _overlay(base: np.ndarray, blend: np.ndarray) -> np.ndarray:
    """Overlay: the condition is on the BASE, which is what makes it not Hard Light."""
    return np.where(
        base < 0.5,
        2.0 * base * blend,
        1.0 - 2.0 * (1.0 - base) * (1.0 - blend),
    )


def _soft_light(base: np.ndarray, blend: np.ndarray) -> np.ndarray:
    """
    Soft Light, the W3C compositing formula -- which is the one Photoshop and Illustrator use.

    The naive `2ab + a^2(1-2b)` variant is a different curve and produces a visibly flatter,
    greyer result on exactly the light neutral images this treatment is specified for. The
    piecewise D(a) below is the part people drop.
    """
    d = np.where(
        base <= 0.25,
        ((16.0 * base - 12.0) * base + 4.0) * base,
        np.sqrt(np.maximum(base, 0.0)),
    )
    return np.where(
        blend <= 0.5,
        base - (1.0 - 2.0 * blend) * base * (1.0 - base),
        base + (2.0 * blend - 1.0) * (d - base),
    )


def _neutralise_array(base: np.ndarray, mask: np.ndarray | None) -> np.ndarray:
    """
    Photoshop's Hue/Saturation model, in HSL, with the subject masked out of the edit.

    Photoshop's two sliders are not linear scalings and getting either wrong is invisible on a
    grey and obvious on a face. Saturation at a negative value scales toward zero,
    `S x (1 + v/100)`; Lightness at a positive value moves toward white by the fraction of the
    headroom remaining, `L + (1 - L) x v/100`. The second is why +40 on an already-light image
    washes rather than clips.
    """
    hsl = _rgb_to_hsl(base)
    hsl[..., 1] *= 1.0 + NEUTRAL_SATURATION / 100.0
    hsl[..., 2] += (1.0 - hsl[..., 2]) * (NEUTRAL_LIGHTNESS / 100.0)
    adjusted = _hsl_to_rgb(np.clip(hsl, 0.0, 1.0))
    if mask is None:
        return adjusted
    # p.91: "the figure and building ... are masked out of color edits".
    return adjusted * (1.0 - mask) + base * mask


def _rgb_to_hsl(rgb: np.ndarray) -> np.ndarray:
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    lum = (mx + mn) / 2.0
    delta = mx - mn
    sat = np.where(
        delta < 1e-6,
        0.0,
        delta / np.maximum(1.0 - np.abs(2.0 * lum - 1.0), 1e-6),
    )
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    safe = np.maximum(delta, 1e-6)
    hue = np.where(
        delta < 1e-6,
        0.0,
        np.where(
            mx == r,
            ((g - b) / safe) % 6.0,
            np.where(mx == g, (b - r) / safe + 2.0, (r - g) / safe + 4.0),
        ),
    )
    return np.stack([hue / 6.0, np.clip(sat, 0.0, 1.0), lum], axis=2)


def _hsl_to_rgb(hsl: np.ndarray) -> np.ndarray:
    hue, sat, lum = hsl[..., 0] * 6.0, hsl[..., 1], hsl[..., 2]
    c = (1.0 - np.abs(2.0 * lum - 1.0)) * sat
    x = c * (1.0 - np.abs(hue % 2.0 - 1.0))
    m = lum - c / 2.0
    zero = np.zeros_like(c)
    sector = np.floor(hue).astype(np.int32) % 6
    table = [
        (c, x, zero),
        (x, c, zero),
        (zero, c, x),
        (zero, x, c),
        (x, zero, c),
        (c, zero, x),
    ]
    out = np.zeros(hsl.shape, dtype=np.float32)
    for index, (rr, gg, bb) in enumerate(table):
        sel = sector == index
        out[..., 0] = np.where(sel, rr, out[..., 0])
        out[..., 1] = np.where(sel, gg, out[..., 1])
        out[..., 2] = np.where(sel, bb, out[..., 2])
    return out + m[..., None]


def _edge_ramp(
    width: int, height: int, region: Region, edge: str, feather: float
) -> np.ndarray:
    """A smoothstepped ramp reaching full strength across `region`, anchored to `edge`."""
    xs = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :]
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]
    x0, y0, x1, y1 = region
    if edge == "bottom":
        axis, start, full = ys, y0 - feather, y0
    elif edge == "top":
        axis, start, full = ys, y1 + feather, y1
    elif edge == "left":
        axis, start, full = xs, x1 + feather, x1
    elif edge == "right":
        axis, start, full = xs, x0 - feather, x0
    else:
        raise ValueError(f"edge must be bottom/top/left/right, got {edge!r}")
    span = full - start
    u = np.clip((axis - start) / (span if abs(span) > 1e-6 else 1e-6), 0.0, 1.0)
    ramp = u * u * (3.0 - 2.0 * u)  # smoothstep: no visible boundary at either end
    return np.broadcast_to(ramp, (height, width)).astype(np.float32)


# ---------------------------------------------------------------------------
# Internals -- procedural source imagery
# ---------------------------------------------------------------------------


def _value_noise(
    width: int, height: int, rng: np.random.Generator, cells: int
) -> np.ndarray:
    """Smooth value noise: a small random lattice, bicubically resampled. Cheap and band-limited."""
    lattice = rng.random((cells + 1, cells + 1)).astype(np.float32)
    small = Image.fromarray((lattice * 255.0).astype(np.uint8), "L")
    return (
        np.asarray(small.resize((width, height), Image.BICUBIC), dtype=np.float32)
        / 255.0
    )


def _fbm(
    width: int, height: int, rng: np.random.Generator, octaves: int = 5, base: int = 3
) -> np.ndarray:
    total = np.zeros((height, width), dtype=np.float32)
    amplitude, norm = 1.0, 0.0
    for octave in range(octaves):
        total += amplitude * _value_noise(width, height, rng, base * 2**octave)
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def _disc(
    width: int, height: int, cx: float, cy: float, radius: float, softness: float = 1.0
):
    """A gaussian falloff disc in normalised coordinates, aspect-corrected."""
    aspect = width / height
    xs = (np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :] - cx) * aspect
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None] - cy
    d2 = xs**2 + ys**2
    return np.exp(-d2 / max(radius * radius * softness, 1e-6)).astype(np.float32)


def _blob(width: int, height: int, cx: float, cy: float, rx: float, ry: float):
    """
    An anisotropic gaussian. What the colour accent is made of, and the shape matters.

    A ROUND ACCENT READS AS A STAIN, NOT AS LIGHT, AND THAT IS NOT A MATTER OF TASTE -- it was
    the loudest thing on three rendered pages and the first thing the eye went to on all of
    them. p.107's "hit of color" in the book's own accepted images is an object: a yellow ear
    defender, a bright jacket, containers on a ship. What none of them is, is a circular glow
    hanging in mid-air, which is exactly what a symmetric disc of warm colour looks like once
    the cool treatment is over it.

    An elongated highlight lying along a form in the image reads as light falling on that form.
    Same measurement, same share of saturated pixels, completely different picture.
    """
    aspect = width / height
    xs = (np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :] - cx) * aspect
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None] - cy
    d2 = (xs / max(rx, 1e-6)) ** 2 + (ys / max(ry, 1e-6)) ** 2
    return np.exp(-d2).astype(np.float32)


def _plane(
    width: int, height: int, angle_deg: float, offset: float, thickness: float
) -> np.ndarray:
    """A straight-edged band at `angle_deg` off vertical. The atom every field is built from."""
    aspect = width / height
    xs = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :] * aspect
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]
    theta = math.radians(angle_deg)
    u = xs * math.cos(theta) + ys * math.sin(theta)
    return ((u >= offset) & (u < offset + thickness)).astype(np.float32)


def _field_ribbon(width: int, height: int, rng: np.random.Generator):
    """
    A swept band with real surface normals, crossing over itself once. bb FY22 p.104.

    THE OTHER THREE BUILDERS MAKE FIELDS; THIS ONE MAKES AN OBJECT, and p.104 asks for an
    object in as many words: "seek images with a 3D quality... the shape should have mass and
    volume -- something you could pick up and hold." A gradient field cannot pass that test at
    any level of polish, because the test is not about beauty. It is about whether the image
    depicts a thing. The book's own first exemplar on that page is a flowing ribbon with a
    specular sheen, which is what this reproduces.

    WHAT ACTUALLY PRODUCES THE 3D READ, in order of how much each contributes:

    1. A SURFACE NORMAL AT EVERY PIXEL. The ribbon is shaded as a half-cylinder: across its
       width the normal rotates through a half-turn, so the lighting varies the way it does on
       a rolled surface rather than the way it does on a painted stripe. Everything else here
       depends on having normals; without them no amount of colour makes a solid.
    2. A SPECULAR HIGHLIGHT from one fixed light. Diffuse shading alone reads as paper. The
       highlight is what says "this has a surface", and holding the light direction constant is
       what makes several generated images look like one photographic set rather than a
       collection.
    3. OCCLUSION WHERE IT CROSSES ITSELF, resolved with a depth buffer, plus a contact shadow
       cast onto the band behind. Overlap is the strongest depth cue available in a still
       image, and it is the one that cannot be faked with a gradient.

    Returns `(lum, pop)` on the same contract as its siblings: luminance in 0-1 and a small
    mask for the warm accent, which is placed at the specular peak so the pop reads as light on
    the form rather than as a mark laid over it.
    """
    yy, xx = np.mgrid[0:height, 0:width].astype(np.float64)
    x = xx / max(width - 1, 1)
    y = yy / max(height - 1, 1)

    # One light, held constant across every ribbon this function ever draws.
    light = np.array([-0.42, -0.58, 0.70])
    light /= np.linalg.norm(light)

    # Two passes of the same curve at different phase and depth. The nearer one is drawn with a
    # smaller z, so the depth test below resolves the crossing.
    phase = float(rng.uniform(0.0, 2.0 * np.pi))
    lum = 0.90 - 0.16 * y - 0.05 * x  # the ground: a soft, slightly raked near-white
    zbuf = np.full_like(lum, 1e9)
    pop = np.zeros_like(lum)

    for depth, (amp, freq, half_w, y0, tilt) in enumerate(
        ((0.150, 1.15, 0.115, 0.56, 0.16), (0.115, 1.45, 0.085, 0.40, -0.11))
    ):
        centre = (
            y0 + amp * np.sin(2.0 * np.pi * freq * x + phase + depth * 1.7) + tilt * x
        )
        slope = (
            amp
            * 2.0
            * np.pi
            * freq
            * np.cos(2.0 * np.pi * freq * x + phase + depth * 1.7)
            + tilt
        )
        t = np.clip((y - centre) / half_w, -1.0, 1.0)
        inside = np.abs(y - centre) <= half_w

        # Half-cylinder normal across the width, tilted along the sweep so the highlight runs
        # with the curve instead of sitting in a straight line down the middle.
        nz = np.sqrt(np.clip(1.0 - t * t, 0.0, 1.0))
        n = np.stack([-slope * nz * 0.30, t, nz], axis=2)
        n /= np.linalg.norm(n, axis=2, keepdims=True) + 1e-9

        lambert = np.clip(n @ light, 0.0, 1.0)
        half = light + np.array([0.0, 0.0, 1.0])
        half /= np.linalg.norm(half)
        spec = np.clip(n @ half, 0.0, 1.0) ** 42.0

        shade = 0.30 + 0.52 * lambert + 0.62 * spec
        z = (
            float(depth) - 0.35 * nz
        )  # nearer at the crown, which is what rounds the edges

        nearer = inside & (z < zbuf)
        lum = np.where(nearer, shade, lum)
        zbuf = np.where(nearer, z, zbuf)
        pop = np.where(nearer, np.clip((spec - 0.55) * 2.1, 0.0, 1.0), pop)

        # Contact shadow: the band just below this one darkens whatever it lands on. Applied
        # after the depth test so it only ever falls on something already behind.
        below = (y - centre > half_w) & (y - centre < half_w * 2.4)
        falloff = np.clip(1.0 - (y - centre - half_w) / (half_w * 1.4), 0.0, 1.0)
        lum = np.where(below & (zbuf > z), lum * (1.0 - 0.30 * falloff), lum)

    return np.clip(lum, 0.0, 1.0), pop


def _field_depth(width: int, height: int, rng: np.random.Generator):
    """
    Overlapping near-vertical planes at receding focus. Frosted glass, essentially.

    THE FIRST VERSION OF THIS WAS A GREY BLUR WITH A YELLOW DOT IN IT AND IT FAILED THE ONLY
    TEST THAT MATTERS: rendered at slide size it read as a defect in the projector, not as a
    photograph. Randomly placed soft discs produce an image with no edges, and an image with no
    edges gives the Soft Light layer nothing to act on -- the treatment lands on it as flat
    colour, which is precisely the "just a blue theme" result imagery was added to fix.

    What replaced it has a real depth cue: straight-edged planes, each blurred in proportion to
    how far back it sits, so the near ones carry crisp edges and the far ones dissolve. Depth
    of field is the cheapest signal there is that something was photographed rather than
    generated, and it costs one blur radius per plane.
    """
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]
    lum = 0.76 - 0.34 * ys**1.4  # a light wash, settling toward the foreground
    aspect = width / height

    # Far to near. Tone alternates about the wash so no two adjacent planes merge, and the
    # blur radius collapses as they approach, which is what puts the front plane in focus.
    count = 7
    for index in range(count):
        near = index / (count - 1)
        angle = float(rng.uniform(-9.0, 9.0))
        offset = float(rng.uniform(-0.1, aspect))
        thickness = float(rng.uniform(0.10, 0.30)) * aspect
        tone = (0.24 if index % 2 else -0.26) * (0.45 + 0.55 * near)
        blur_px = int(round((0.055 * (1.0 - near) ** 2 + 0.002) * width))
        lum = lum + tone * _blur(
            _plane(width, height, angle, offset, thickness), blur_px
        )

    # The subject: the sharpest plane edge in the frame, at the right third, lit from behind.
    subject = _blur(
        _plane(width, height, 4.0, 0.58 * aspect, 0.17 * aspect), max(1, width // 500)
    )
    lum = lum + 0.24 * subject + 0.10 * _disc(width, height, 0.66, 0.44, 0.22)
    lum = lum + 0.05 * (_fbm(width, height, rng, octaves=4, base=3) - 0.5)
    lum = lum - 0.22 * _vignette(width, height, strength=1.0)

    # A tall, narrow warm highlight lying along the lit edge of the subject plane.
    pop = _blob(width, height, 0.655, 0.50, 0.048, 0.36)
    return np.clip(lum, 0.03, 0.99), pop


def _field_structure(width: int, height: int, rng: np.random.Generator):
    """
    A colonnade in one-point perspective: shadowed interior, lit slabs, light at the far end.

    Built from geometry rather than noise because the point of this kind is EDGES. Under Soft
    Light a hard vertical edge survives as a hard vertical edge, which is what stops a treated
    image from dissolving into its own colour layer -- and it is what makes a window-held image
    read as a photograph of something rather than as a fill.

    ONE-POINT PERSPECTIVE IS TWO CONVERGING LINES AND NOTHING ELSE. The ceiling and floor lines
    both run to the vanishing point, and each slab's height is clipped between them at its own
    x, so the colonnade recedes without a single trigonometric term. The earlier version drew
    equal-height rectangles with thin black gaps and read as a barcode; the difference is the
    convergence, not the detail.
    """
    xs = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :]
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]

    # THE CORRIDOR ENDS IN AN APERTURE, NOT AT A POINT. Converging the ceiling and floor lines
    # all the way to the vanishing point drew a hard wedge with a flat white block beyond it,
    # which read as op-art rather than as a building. Stopping them 0.055 apart leaves a small
    # bright opening at the end, which is what a photographed colonnade actually gives you and
    # what makes the far end read as distance rather than as an edge.
    vx, vy, aperture = 0.78, 0.47, 0.055
    t = np.clip(xs / vx, 0.0, 1.0)
    ceiling = 0.10 + (vy - aperture - 0.10) * t
    floor = 0.93 - (0.93 - vy - aperture) * t

    lum = np.where(ys < ceiling, 0.50 + 0.14 * ys / np.maximum(ceiling, 1e-6), 0.0)
    # The floor brightens toward the viewer, which is what a lit floor does and what stops the
    # region below the converging line from reading as a flat triangle of white.
    lum = np.where(
        ys > floor, 0.70 + 0.22 * (ys - floor) / np.maximum(1.0 - floor, 1e-6), lum
    )
    interior = ((ys >= ceiling) & (ys <= floor)).astype(np.float32)
    lum = lum + interior * 0.40  # the shadowed depth the slabs stand against
    lum = np.where((xs >= vx) & (interior > 0), 0.96, lum)  # the light at the far end

    # Slabs marching away: screen position and width both scale as 1/depth, so the spacing
    # compresses toward the vanishing point exactly as it does in a photograph. The nearest
    # slab is deliberately cropped by the left edge -- a colonnade whose front column fits
    # comfortably in frame is a diagram of a colonnade.
    depth = 0.85
    for _ in range(11):
        x0 = vx - 0.95 / depth
        w_slab = 0.20 / depth
        if x0 + w_slab < -0.05:
            depth *= 1.42
            continue
        band = ((xs >= x0) & (xs < x0 + w_slab)).astype(np.float32)
        shadow = ((xs >= x0 + w_slab) & (xs < x0 + w_slab * 1.35)).astype(np.float32)
        near = np.clip(1.0 / depth, 0.0, 1.0)
        lum = lum + interior * band * (0.20 + 0.16 * near)
        lum = lum - interior * shadow * 0.07
        depth *= 1.42

    lum = lum + 0.04 * (_fbm(width, height, rng, octaves=4, base=3) - 0.5)
    lum = _blur(lum, max(1, width // 260))
    lum = lum - 0.12 * _vignette(width, height, strength=1.2)

    # The warm light in the opening: as wide as the aperture, no taller.
    pop = _blob(width, height, vx + 0.05, vy, 0.17, 0.075)
    return np.clip(lum, 0.08, 0.99), pop


def _field_strata(width: int, height: int, rng: np.random.Generator):
    """
    Layered landform under haze: the widest tonal range of the three, so type can sit on it.

    Atmospheric perspective is the whole trick -- each ridge is mixed back toward the sky by its
    distance, which is why the far ones read as far rather than as merely paler. The nearest
    band stops at 0.30 rather than running to black: p.107's accepted images all "balance the
    lightness with dark shadow tones", and its one rejected image is rejected partly because
    "darker tones dominate".
    """
    ys = np.linspace(0.0, 1.0, height, dtype=np.float32)[:, None]
    horizon = 0.46
    sky = 0.97 - 0.24 * np.clip((horizon - ys) / horizon, 0.0, 1.0) ** 1.5
    lum = np.broadcast_to(sky, (height, width)).astype(np.float32).copy()

    bands = 6
    for index in range(bands):
        near = (index + 1) / bands
        ridge = horizon + (1.0 - horizon) * (0.02 + 0.92 * near**1.7)
        profile = (
            ridge
            - 0.05 * (1.0 - near)
            - (0.05 + 0.06 * near)
            * _fbm(width, 1, rng, octaves=4, base=2).reshape(width)
        )
        below = (ys >= profile[None, :]).astype(np.float32)
        tone = 0.80 - 0.50 * near  # near ridges dark, far ridges pale
        haze = 1.0 - 0.70 * (1.0 - near)  # ...then mixed back toward the sky
        lum = lum * (1.0 - below * haze) + (tone * below * haze)

    lum = lum + 0.035 * (_fbm(width, height, rng, octaves=5, base=4) - 0.5)
    lum = lum - 0.08 * _vignette(width, height, strength=1.4)

    # The hit of colour, p.107: a low band of warm light on the horizon. Placed RIGHT of centre
    # because `image_field` sets its type in the lower LEFT -- an accent under a white headline
    # is a smudge behind the words, which is what the first version of this looked like.
    pop = _blob(width, height, 0.72, horizon - 0.008, 0.26, 0.045)
    return np.clip(lum, 0.03, 0.99), pop


def _vignette(width: int, height: int, *, strength: float) -> np.ndarray:
    return np.clip(
        1.0 - _disc(width, height, 0.5, 0.5, 0.85 / strength, softness=2.2), 0.0, 1.0
    )


def _blur(arr: np.ndarray, radius: int) -> np.ndarray:
    if radius < 1:
        return arr
    img = Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0).astype(np.uint8), "L")
    return (
        np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32)
        / 255.0
    )


def _tint(lum: np.ndarray, pop: np.ndarray) -> np.ndarray:
    """
    Luminance to RGB: a cool neutral, plus one small warm accent.

    The tint is deliberately tiny -- (0.985, 0.995, 1.02) is under two percent of channel
    separation. p.107's accepted images are "white- and light-blue dominant" and "tones of gray
    + white are dominant"; a stronger cast would be a colour, and the colour is supposed to
    arrive with the gradient, not before it.
    """
    base = np.stack([lum * 0.985, lum * 0.995, np.clip(lum * 1.02, 0.0, 1.0)], axis=2)
    # The accent is warm and genuinely saturated, because "a hit of color" that measures below
    # 0.40 saturation is not one -- p.107 bounds the pop at BOTH ends and an image with none
    # fails its envelope exactly as a rainbow does. The gamma on the weight keeps it small: the
    # core reads as colour and the falloff is back to neutral within a few percent of the frame.
    #
    # IT IS AMBER RATHER THAN ORANGE, AND THE TREATMENT IS THE REASON. A Purple/Cobalt layer
    # pushes warm hues toward magenta -- the book measures this itself on skin, which lands at
    # 311-332 degrees after treatment (p.103) -- so an orange accent came back PINK on the pale
    # Overlay pages and read as a stain on the print rather than as light in the picture. Amber
    # has further to travel before it gets there. The hue that looks right untreated is not the
    # hue that looks right treated, and only the treated render shows which is which.
    accent = np.stack(
        [np.full_like(lum, 0.95), np.full_like(lum, 0.75), np.full_like(lum, 0.20)],
        axis=2,
    )
    weight = (np.clip(pop, 0.0, 1.0) ** 1.05)[..., None] * 0.72
    return (
        base * (1.0 - weight)
        + accent * np.clip(lum + 0.12, 0.0, 1.0)[..., None] * weight
    )
