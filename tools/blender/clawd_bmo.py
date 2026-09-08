"""Clawd as BMO — a 3D scene, built rather than drawn.

Run headless:

    /Applications/Blender.app/Contents/MacOS/Blender -b -noaudio \
        --python tools/blender/clawd_bmo.py -- --out assets/blender

THE GEOMETRY IS QUOTED, NOT INVENTED. Clawd ships as literal data inside the Claude Code
binary — an 11 x 8 grid of square pixels, read out in
docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md. This scene extrudes THAT grid. Every
column and row below is the sprite's own, so the 3D creature and the SVG banners are the
same character rather than two drawings of one description:

    x:     0 1 2 3 4 5 6 7 8 9 10
    y=0      # # # # # # # # #
    y=1      # # # # # # # # #
    y=2    # # . # # # # # . # #     <- . = eye, and the arm stubs at x=0 / x=10
    y=3    # # # # # # # # # # #
    y=4      # # # # # # # # #
    y=5      # # # # # # # # #
    y=6      #   #       #   #
    y=7      #   #       #   #

The costume's numbers are quoted too — from tools/banner/recycle.py, which already ratified
the BMO shell against the operator: SHELL, SCREEN, STRAP_COLS and the whole teal palette are
imported constants here in spirit, restated so this file runs without importing an SVG
generator. The one place the costume disagrees with the bare sprite is the eye row: on the
bare creature the eyes sit at row 2, and under the costume they sit at row 3.0 so that they
fall INSIDE the screen aperture (recycle.py's `ey = gy(3.0)`, guarded there by
`assert_costume_reveals`). That shift is deliberate and is reproduced here.

AXES. One sprite pixel is one Blender unit. x is the sprite's own column. z is height, with
z = 0 at the sole, so sprite row r occupies z in [7-r, 8-r] and the creature stands 8 tall
by construction rather than by eye. y is depth, negative toward the camera, so the costume
hangs on the FRONT of the body at negative y.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

# --------------------------------------------------------------------------------------
# palette — every value quoted from tools/banner/{gen,recycle}.py so the 3D scene and the
# shipped SVG banners cannot drift apart.
# --------------------------------------------------------------------------------------

CLAWD = "#D77757"  # exact body orange, from the binary. NOT #D97757.
CLAWD_LO = "#a8543a"  # shaded orange, for the sides the key light never reaches

TEAL = "#4bb3a1"  # BMO's body
TEAL_HI = "#79cdbd"  # top bevel
TEAL_LO = "#2f7d6f"  # bezel
TEAL_DK = "#1a534b"  # seams and the shell's own outline

SCREEN_LIT = "#a9e8d6"
FACE_INK = "#123330"  # the mouth, and the eye holes while the costume is on
BRASS = "#caa15e"
STRAP = "#2b1b14"

CELL_LIVE = CLAWD  # a live cell is Claude orange. A spent one is not.
CELL_SPENT = "#6a6068"

BIN_BODY = "#33253a"
BIN_FRONT = "#1b1322"
BIN_EDGE = "#5b4466"
LED = "#7dd6a0"

GROUND_COL = "#241a26"  # the dusk ridge the banners stand the creature on
RIDGE_FAR = (
    "#3b2d49"  # the far ridges read as silhouettes, so they must beat the sky, not
)
SKY_HI = "#4b3866"  # match it — at #2f2338 against #16101d they were invisible
SKY_LO = "#241a30"

BTN_RED = "#d9534f"
BTN_BLUE = "#4a7fd0"

# --------------------------------------------------------------------------------------
# the sprite grid — the authoritative geometry
# --------------------------------------------------------------------------------------

BODY_COLS = (1, 10)  # cols 1..9 inclusive -> x in [1, 10]
BODY_ROWS = (0, 6)  # rows 0..5 -> z in [2, 8]
ARM_ROWS = (2, 4)  # rows 2..3 -> z in [4, 6]
LEG_COLS = (1, 3, 7, 9)  # the +1 column offset the bundle emits row 4 at
LEG_ROWS = (6, 8)  # rows 6..7 -> z in [0, 2]

BODY_D = 5.0  # depth, in sprite pixels. The sprite is silent on depth; this is the one
LIMB_D = (
    2.6  # invented axis, chosen so the creature reads as a solid rather than a card.
)

# costume, from recycle.py.
#
# ONE NUMBER IS DELIBERATELY NOT THE SVG'S: the shell's bottom row. recycle.py ends the shell
# at row 7.0, which in a flat drawing still leaves the legs reading, because a 2D overlay has
# no depth and casts no shadow. Give the same shell 0.8 of depth and it stops clearing the
# legs at all — it stands in front of leg row 6 and drops the whole leg band into its own
# shadow, and the first render showed exactly that: a console sitting on the ground with no
# creature under it. Row 6.4 is the balance point: it clears 80% of the leg band so all four
# legs stand bare and lit, while still leaving a deck deep enough to mount the D-pad and the
# two buttons on (see the `deck_z0..deck_z1` guard, which refuses if it ever stops being).
SHELL = (1.25, 2.2, 9.75, 6.4)  # col0, row0, col1, row1
SCREEN = (1.6, 2.6, 9.4, 5.0)
STRAP_COLS = (2.15, 8.1)
STRAP_W = 0.45
EYE_COLS = (2.0, 8.0)
EYE_ROW = 3.0  # NOT row 2 — see the module docstring
MOUTH_ROW = 4.5
SEAM_COL = 9.45

SHELL_FRONT = -BODY_D / 2 - 0.85  # the shell's outer face
SHELL_BACK = -BODY_D / 2 - 0.05  # ... and where it meets the body
BEZEL = 0.12  # the frame's width around the screen aperture, in sprite pixels

# The one slab that both the creature's eyes and the costume's lit field live in. Shared so
# the two cannot drift apart: the instant they stop being coplanar, the backlight's rear face
# starts floodlighting the eyes and they render pale. See `build_clawd`.
EYE_PLANE = (-BODY_D / 2 - 0.10, -BODY_D / 2 - 0.04)

ROWS = 8  # sprite height, for the row -> z flip


def z_of(row: float) -> float:
    """Sprite row (0 at the top) -> Blender z, with z = 0 at the sole."""
    return (ROWS - 1) - row + 1.0


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------


def srgb_to_linear(c: float) -> float:
    """Blender's shader nodes want linear; hex is sRGB. Converting by the actual transfer
    function rather than a 2.2 power keeps the orange EXACTLY #D77757 when rendered."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_str: str, alpha: float = 1.0) -> tuple[float, float, float, float]:
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


_materials: dict[str, bpy.types.Material] = {}
_intended: dict[
    str, str
] = {}  # material name -> the hex it was asked for, for assert_palette


def linear_to_srgb(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def assert_palette() -> None:
    """Every material's Base Color must round-trip back to the hex it was built from.

    This repo's claim about the mascot is specifically that #D77757 is the exact orange read
    out of the shipping binary, so 'the render looks orange' is not the standard — the value
    has to survive. sRGB->linear on the way in and linear->sRGB on the way out is where a
    silent shift would happen (a 2.2 power instead of the real transfer function moves
    #D77757 to #D2703F, which still looks fine and is still wrong). Checking the material
    rather than the rendered pixel is deliberate: a pixel also carries the lighting, so it
    could only ever be compared loosely, and a loose comparison would pass on that shift.
    """
    bad = []
    for name, mat in _materials.items():
        want = _intended[name]
        r, g, b, _ = (
            mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
        )
        got = "#{:02X}{:02X}{:02X}".format(
            *(min(255, max(0, round(linear_to_srgb(c) * 255))) for c in (r, g, b))
        )
        if got.upper() != want.upper():
            bad.append(f"  {name}: asked {want.upper()}, material holds {got}")
    if bad:
        raise SystemExit("palette drifted:\n" + "\n".join(bad))
    print(f"PALETTE OK — {len(_materials)} materials round-trip to their source hex")


def material(
    name: str,
    color: str,
    *,
    roughness: float = 0.62,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    """One material per name, cached — so 40-odd voxels share 6 materials, not 40."""
    if name in _materials:
        return _materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba(color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = rgba(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    _materials[name] = mat
    _intended[name] = color
    return mat


def box(
    name: str,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z0: float,
    z1: float,
    mat: bpy.types.Material,
    *,
    bevel: float = 0.0,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    """A cube specified by the box it must fill, never by centre-and-scale.

    Every solid in this scene is placed by its bounds because every bound here is a sprite
    coordinate. Converting to centre/scale at each call site is where an off-by-half-a-cell
    creeps in, so it happens exactly once, here.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.object
    obj.name = name
    obj.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    obj.scale = (x1 - x0, y1 - y0, z1 - z0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
    if parent is not None:
        obj.parent = parent
    return obj


def empty(name: str, loc=(0.0, 0.0, 0.0)) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    e.location = loc
    bpy.context.collection.objects.link(e)
    return e


def cylinder(
    name: str,
    x: float,
    y0: float,
    y1: float,
    z: float,
    r: float,
    mat: bpy.types.Material,
    parent: bpy.types.Object | None = None,
) -> bpy.types.Object:
    """A disc facing the camera — the two face buttons, and the charger's LED."""
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=abs(y1 - y0), vertices=32)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (math.radians(90), 0, 0)
    obj.location = (x, (y0 + y1) / 2, z)
    obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
    return obj


# --------------------------------------------------------------------------------------
# the creature
# --------------------------------------------------------------------------------------


def build_clawd() -> bpy.types.Object:
    """The sprite, extruded. Body block, two arm stubs, four legs, two eye voids.

    The body is one block rather than 54 voxels on purpose: rows 0-5 x cols 1-9 are SOLID in
    the source grid, so drawing them as separate cubes would add 53 invisible interior faces
    and a seam-shimmer on every edge, and change nothing you can see. The voxel structure
    that IS visible — the arm stubs standing proud, the four separate legs, the eye holes —
    is modelled as separate geometry.
    """
    root = empty("clawd")

    orange = material("clawd_body", CLAWD, roughness=0.66)
    ink = material("face_ink", FACE_INK, roughness=0.4)

    bx0, bx1 = BODY_COLS
    bz0, bz1 = z_of(BODY_ROWS[1] - 1), z_of(BODY_ROWS[0] - 1)
    box(
        "clawd_body",
        bx0,
        bx1,
        -BODY_D / 2,
        BODY_D / 2,
        bz0,
        bz1,
        orange,
        bevel=0.10,
        parent=root,
    )

    # arm stubs: col 0 and col 10, rows 2..3. They are the only part of the creature the
    # costume leaves bare on the sides, and in the SVG loop they are what reaches behind the
    # shell — so they stand proud of the body, not flush with it.
    az0, az1 = z_of(ARM_ROWS[1] - 1), z_of(ARM_ROWS[0] - 1)
    for side, x0, x1 in (("l", 0.0, 1.0), ("r", 10.0, 11.0)):
        box(
            f"clawd_arm_{side}",
            x0,
            x1,
            -LIMB_D / 2,
            LIMB_D / 2,
            az0,
            az1,
            orange,
            bevel=0.10,
            parent=root,
        )

    # four legs, at the +1-offset columns the bundle emits
    lz0, lz1 = z_of(LEG_ROWS[1] - 1), z_of(LEG_ROWS[0] - 1)
    for i, col in enumerate(LEG_COLS):
        box(
            f"clawd_leg_{i}",
            col,
            col + 1.0,
            -LIMB_D / 2,
            LIMB_D / 2,
            lz0,
            lz1,
            orange,
            bevel=0.08,
            parent=root,
        )

    # THE EYES ARE HOLES, NOT DOTS. In the source the eye is the BACKGROUND showing through a
    # half-block: the creature has no drawn eye, it has an absence.
    #
    # THEY ARE COPLANAR WITH THE SCREEN'S LIT FIELD, and getting there cost three renders. An
    # eye plate mounted anywhere BEHIND the lit field renders pale, and no amount of darkening
    # the material fixes it — the backlight is a solid, and a solid emits from all six faces,
    # so its REAR face floodlights anything in the gap behind it at point-blank range. Boring
    # a 0.9-deep socket to hide in did not help either, for the same reason: the socket is
    # behind the emitter.
    #
    # Coplanar, the problem disappears rather than being fought: the eye plate and the lit
    # bands lie in one slab (EYE_PLANE, shared with `build_costume` so they cannot drift), all
    # their front faces point the same way, and light leaving the bands travels PARALLEL to
    # the eye plate instead of into it. The eye is then lit only by the scene's frontal fill,
    # which is what makes it read as ink on a glowing screen — exactly what the SVG draws.
    ez0, ez1 = z_of(EYE_ROW + 1.0), z_of(EYE_ROW)
    for side, col in zip(("l", "r"), EYE_COLS):
        box(
            f"clawd_eye_{side}",
            col,
            col + 1.0,
            EYE_PLANE[0],
            EYE_PLANE[1],
            ez0,
            ez1,
            ink,
            parent=root,
        )
    return root


# --------------------------------------------------------------------------------------
# the costume
# --------------------------------------------------------------------------------------


def build_costume(parent: bpy.types.Object) -> bpy.types.Object:
    """The teal games-console shell, strapped on — a costume, never a body swap.

    The whole read depends on the shell being SMALLER than the creature wearing it. The
    body runs columns 1-10 and the shell is inset to 1.25-9.75, which leaves a strip of bare
    orange down both sides; the head above row 2.2 and the legs below are bare too. Cover
    those and the scene stops being 'clawd in a BMO costume' and becomes 'a BMO', which is a
    different picture.
    """
    root = empty("costume")
    root.parent = parent

    teal = material("shell", TEAL, roughness=0.44)
    teal_hi = material("shell_hi", TEAL_HI, roughness=0.36)
    teal_lo = material("shell_bezel", TEAL_LO, roughness=0.5)
    teal_dk = material("shell_seam", TEAL_DK, roughness=0.55)
    ink = material("face_ink", FACE_INK, roughness=0.4)
    brass = material("brass", BRASS, roughness=0.32, metallic=0.85)
    strap_mat = material("strap", STRAP, roughness=0.85)

    sc0, sr0, sc1, sr1 = SHELL
    sz0, sz1 = z_of(sr1), z_of(sr0)

    ec0, er0, ec1, er1 = SCREEN
    gz0, gz1 = z_of(er1), z_of(er0)
    ap0, ap1 = ec0 - BEZEL, ec1 + BEZEL  # the aperture in x
    apz0, apz1 = gz0 - BEZEL, gz1 + BEZEL  # ... and in z

    # THE SHELL IS A FRAME, NOT A SLAB — and that is a correction, not a preference. Built as
    # one solid box it models perfectly and still kills the picture: an opaque teal wall then
    # stands between the glass and the creature's face, so the costume occludes the very eyes
    # it exists to show. The first render proved it — a blank lit screen, a smile, and nobody
    # behind it. So the aperture is real: four rails around a hole you can see through.
    for name, x0, x1, z0, z1 in (
        ("shell_rail_top", sc0, sc1, apz1, sz1),
        ("shell_rail_bottom", sc0, sc1, sz0, apz0),
        ("shell_rail_left", sc0, ap0, apz0, apz1),
        ("shell_rail_right", ap1, sc1, apz0, apz1),
    ):
        # A rail that has gone non-positive means SCREEN has grown until it ate SHELL, and the
        # costume would render as a floating pane of glass. Refuse rather than emit it.
        if x1 - x0 <= 0 or z1 - z0 <= 0:
            raise SystemExit(
                f"{name}: aperture {ap0:.2f}..{ap1:.2f} x {apz0:.2f}..{apz1:.2f} leaves no "
                f"frame inside SHELL {SHELL} — SCREEN is too large or BEZEL too wide"
            )
        box(
            name, x0, x1, SHELL_FRONT, SHELL_BACK, z0, z1, teal, bevel=0.09, parent=root
        )

    # the lip standing proud around the aperture, so the glass reads as inset into the shell
    ly0, ly1 = SHELL_FRONT - 0.07, SHELL_FRONT + 0.05
    lw = BEZEL
    for name, x0, x1, z0, z1 in (
        ("lip_top", ap0, ap1, apz1 - lw, apz1),
        ("lip_bottom", ap0, ap1, apz0, apz0 + lw),
        ("lip_left", ap0, ap0 + lw, apz0, apz1),
        ("lip_right", ap1 - lw, ap1, apz0, apz1),
    ):
        box(name, x0, x1, ly0, ly1, z0, z1, teal_lo, parent=root)

    # the top bevel, the one lit edge that tells you the shell is a solid object
    box(
        "shell_top_bevel",
        sc0 + 0.05,
        sc1 - 0.05,
        SHELL_FRONT + 0.05,
        SHELL_BACK,
        sz1 - 0.10,
        sz1 + 0.02,
        teal_hi,
        parent=root,
    )

    # THE BACKLIGHT — the screen's lit field, mounted against the creature's own face at the
    # BACK of the aperture. Putting the light BEHIND the eyes rather than in front of them is
    # the whole trick: the eyes then read as two dark squares standing proud of a glowing
    # plane, which is exactly what the SVG draws (FACE_INK holes on SCREEN_LIT). Light the
    # glass instead — the obvious way, and the way the first version did it — and the eyes
    # are swallowed by the glow they are supposed to be seen against.
    #
    # AND THE LIT FIELD HAS EYE-SHAPED ABSENCES IN IT — five bands tiling the aperture around
    # the two eye squares, rather than one plane with the eyes laid on top. Laid on top, the
    # eyes are lit geometry: the frontal fill catches their faces and they render as two PALE
    # squares on a bright screen, which is the exact inverse of the drawing. Cut out, they are
    # holes, the dark recess behind shows through, and the creature is looking at you. The
    # bands are computed from the eye columns, so they cannot drift out of register with the
    # eyes the way a hand-placed mask would.
    lit = material(
        "screen_lit",
        SCREEN_LIT,
        roughness=0.5,
        emission=SCREEN_LIT,
        emission_strength=1.15,
    )
    exl, exr = EYE_COLS
    ez0, ez1 = z_of(EYE_ROW + 1.0), z_of(EYE_ROW)
    ly0, ly1 = EYE_PLANE  # coplanar with the eyes, by construction — see `build_clawd`
    # The lit field fills the whole APERTURE, not just the nominal screen rect. Sized to the
    # rect it left a 0.12 margin of unlit gap inside the aperture on all four sides, and from
    # any angle off dead-centre you saw straight past the screen into the shell's hollow — an
    # orange strip under the glass and a dark notch above it.
    for name, x0, x1, z0, z1 in (
        ("lit_above_eyes", ap0, ap1, ez1, apz1),
        ("lit_below_eyes", ap0, ap1, apz0, ez0),
        ("lit_outboard_l", ap0, exl, ez0, ez1),
        ("lit_between_eyes", exl + 1.0, exr, ez0, ez1),
        ("lit_outboard_r", exr + 1.0, ap1, ez0, ez1),
    ):
        box(name, x0, x1, ly0, ly1, z0, z1, lit, parent=root)

    # THE GLASS IS A SHEEN, NOT A PANE — and this is the correction that cost the most renders.
    #
    # A full-screen semi-transparent pane across the aperture is the obvious way to say
    # "screen", and it is what made the eyes unreadable through four passes. An alpha-blended
    # pane composites its own pale mint over EVERYTHING behind it, so the two ink squares came
    # back sage green; at low roughness it also mirrors the lit interior, which washed them
    # further. Three plausible causes were chased first — the eye plate being proud of the
    # backlight, then recessed in a bored socket, then coplanar with it — and none of them was
    # the cause. What settled it was a positive control: recolouring FACE_INK to magenta showed
    # the mouth turning vivid and the eyes turning DULL pink, and the only thing that differs
    # between those two is which side of the pane they sit on.
    #
    # So the pane is gone and the SVG's own answer is used instead: one diagonal sheen streak
    # across the glass (recycle.py draws exactly this, white at .055). It reads as glass, and
    # it cannot veil the face because it does not cover the face.
    # Its opacity is recycle.py's ratified .055 and it carries NO emission of its own. The
    # first version used .11 plus a little glow and behaved like a small area light: where its
    # edge crossed the smile it turned the left cap from ink to putty, so the mouth rendered
    # with one dark corner and one pale one. A sheen is a reflection, not a lamp.
    #
    # It also sits BEHIND the mouth rather than over it (between the lit field and the ink), so
    # the face is always drawn on top of the highlight and can never be tinted by it.
    sheen = material("screen_sheen", "#ffffff", roughness=0.18)
    sheen.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.055
    sheen.blend_method = "BLEND"
    band = box(
        "screen_sheen",
        (ec0 + ec1) / 2 - 2.0,
        (ec0 + ec1) / 2 - 1.1,
        ly0 - 0.015,
        ly0 - 0.005,
        sz0,
        sz1,
        sheen,
        parent=root,
    )
    # THE STREAK IS CLIPPED BY THE SHELL, not by its own length — the 3D equivalent of the
    # SVG's `clip-path="url(#glass)"`. It is bounded to the SHELL's extent and sits at the
    # shell's own depth, so the shell's rails hide every part of it that is not over the
    # aperture, and it runs off the top and bottom of the glass the way a real highlight does.
    # Bounded to the aperture instead it stops short and reads as a floating quad; bounded to
    # nothing — the first attempt — it ran 0.5 past the shell's top edge and painted a pale
    # translucent wedge across the creature's bare orange head.
    band.rotation_euler = (0, math.radians(26), 0)

    # the painted smile, on the screen below the eyes. A pixel smile: a flat bar with its two
    # ends lifted — never a curve, which at this quantisation samples to grey mud.
    #
    # It sits a hair IN FRONT of the lit field, not behind it. In front is provably safe: the
    # mouth was the one element that stayed vivid all the way through the veiled-eye debugging,
    # and being in front of the emitter is exactly why. Behind it — the rear-face problem — it
    # would wash out the way the eyes did.
    u = 0.25
    mx, mz = 5.5, z_of(MOUTH_ROW)
    halfw = 1.0
    fy0, fy1 = ly0 - 0.04, ly0 - 0.02
    box("mouth_bar", mx - halfw, mx + halfw, fy0, fy1, mz, mz + u, ink, parent=root)
    for sx in (mx - halfw - u, mx + halfw):
        box("mouth_cap", sx, sx + u, fy0, fy1, mz + u, mz + 2 * u, ink, parent=root)

    # THE CONTROL DECK IS MEASURED OFF THE RAIL IT SITS ON, never off absolute sprite rows.
    # recycle.py can place these at rows 5.75-6.95 because in the SVG the shell always ends at
    # row 7.0. Here the shell's bottom edge is a tuning knob (it has to clear the legs), and
    # the first version hardcoded the SVG's rows — so raising the shell dropped the blue button
    # and the speaker grille straight through the bottom of the costume onto the ground, still
    # rendering, just no longer attached to anything. Deriving from `deck_z0..deck_z1` makes
    # that failure unrepresentable: the deck moves with the shell by construction.
    deck_z0, deck_z1 = sz0, apz0
    dh = deck_z1 - deck_z0
    if dh <= 0.35:
        raise SystemExit(
            f"control deck is {dh:.2f} tall — SHELL's bottom row {sr1} has risen into the "
            f"screen aperture, leaving nowhere to mount the D-pad and buttons"
        )
    dcz = (deck_z0 + deck_z1) / 2
    dy0, dy1 = SHELL_FRONT - 0.18, SHELL_FRONT + 0.02

    dpx = 2.6
    arm, thick = 0.46 * dh, 0.30 * dh
    box(
        "dpad_h",
        dpx - arm,
        dpx + arm,
        dy0,
        dy1,
        dcz - thick / 2,
        dcz + thick / 2,
        teal_dk,
        parent=root,
    )
    box(
        "dpad_v",
        dpx - thick / 2,
        dpx + thick / 2,
        dy0,
        dy1,
        dcz - arm,
        dcz + arm,
        teal_dk,
        parent=root,
    )

    cylinder(
        "btn_red",
        8.2,
        dy0,
        dy1,
        dcz + 0.16 * dh,
        0.21 * dh,
        material("btn_red", BTN_RED, roughness=0.35),
        root,
    )
    cylinder(
        "btn_blue",
        9.05,
        dy0,
        dy1,
        dcz - 0.20 * dh,
        0.21 * dh,
        material("btn_blue", BTN_BLUE, roughness=0.35),
        root,
    )
    box(
        "speaker",
        5.3,
        7.1,
        dy0,
        dy1,
        dcz - 0.30 * dh,
        dcz - 0.18 * dh,
        brass,
        parent=root,
    )

    # the panel seam and its two screws, on the edge the hands disappear behind
    box(
        "panel_seam",
        SEAM_COL - 0.03,
        SEAM_COL + 0.03,
        SHELL_FRONT - 0.02,
        SHELL_FRONT + 0.06,
        sz0 + 0.2,
        sz1 - 0.2,
        teal_dk,
        parent=root,
    )
    for frac in (0.12, 0.88):
        sz = sz0 + 0.2 + frac * (sz1 - sz0 - 0.4)
        box(
            "screw",
            SEAM_COL - 0.28,
            SEAM_COL - 0.08,
            SHELL_FRONT - 0.04,
            SHELL_FRONT + 0.04,
            sz - 0.1,
            sz + 0.1,
            teal_dk,
            parent=root,
        )

    # THE TWO STRAPS. They are the single load-bearing prop in the picture: they are the
    # reason the shell is a costume and not a torso. They cross the BARE head — above the
    # shell, over the top of the body — and wrap all the way round it, so they read as
    # holding something on rather than as two stripes painted on the front.
    #
    # THEIR LOWER END STOPS INSIDE THE SHELL'S TOP RAIL, and that is load-bearing too. Run
    # them any further down and they pass in front of the backlight but behind the open
    # aperture, so their tips appear INSIDE the screen — two dark tabs hanging over the eyes,
    # which is what the third render showed. Ending at `sz1 - 0.15` tucks the join under the
    # top rail, so the strap disappears where a real strap would: behind the thing it holds.
    head_z1 = z_of(BODY_ROWS[0] - 1)
    strap_bottom = sz1 - 0.15
    for i, col in enumerate(STRAP_COLS):
        box(
            f"strap_{i}",
            col,
            col + STRAP_W,
            -BODY_D / 2 - 0.14,
            BODY_D / 2 + 0.14,
            strap_bottom,
            head_z1 + 0.14,
            strap_mat,
            parent=root,
        )
        # the strap continues over the crown, so it is a loop rather than two vertical bars
        box(
            f"strap_top_{i}",
            col,
            col + STRAP_W,
            -BODY_D / 2 - 0.14,
            BODY_D / 2 + 0.14,
            head_z1 - 0.02,
            head_z1 + 0.14,
            strap_mat,
            parent=root,
        )
    return root


# --------------------------------------------------------------------------------------
# the props — the beat the SVG loop animates, held at its most legible instant
# --------------------------------------------------------------------------------------


def build_props() -> None:
    """The charger and the crate, with one fresh cell and a heap of spent ones.

    The still has to carry what the animated loop carries: a creature that swaps its own
    battery. So the two ends of that swap are both on camera — a charged cell waiting in the
    charger, and the spent ones already in the crate.
    """
    live = material("cell_live", CELL_LIVE, roughness=0.5)
    spent = material("cell_spent", CELL_SPENT, roughness=0.72)
    brass = material("brass", BRASS, roughness=0.32, metallic=0.85)
    bin_body = material("bin_body", BIN_BODY, roughness=0.8)
    bin_front = material("bin_front", BIN_FRONT, roughness=0.85)
    bin_edge = material("bin_edge", BIN_EDGE, roughness=0.7)

    def cell(name: str, x: float, y: float, z: float, is_live: bool, rot: float = 0.0):
        """One battery. Live cells carry a proud brass terminal, spent ones a dull short
        one — the silhouettes differ before any colour is read, which is the same two-channel
        rule the SVG battery uses."""
        w, h, d = 2.2, 0.75, 0.75
        obj = box(
            name, x, x + w, y, y + d, z, z + h, live if is_live else spent, bevel=0.05
        )
        nub_w = 0.30 if is_live else 0.18
        nub = box(
            name + "_nub",
            x + w,
            x + w + nub_w,
            y + 0.18,
            y + d - 0.18,
            z + 0.20,
            z + h - 0.20,
            brass if is_live else spent,
        )
        for o in (obj, nub):
            o.rotation_euler = (0, 0, math.radians(rot))
        return obj

    # the charger, camera-left
    cx, cy = -6.4, 1.4
    box(
        "charger_body", cx, cx + 5.6, cy - 1.6, cy + 1.6, 0.0, 1.5, bin_body, bevel=0.10
    )
    box("charger_lip", cx, cx + 5.6, cy - 1.7, cy - 1.5, 1.5, 1.9, bin_edge)
    cylinder(
        "charger_led",
        cx + 5.0,
        cy - 1.75,
        cy - 1.6,
        1.15,
        0.16,
        material("led", LED, emission=LED, emission_strength=6.0),
    )
    cell("cell_fresh", cx + 1.5, cy - 0.4, 1.5, True)

    # the crate of spent cells, camera-right
    bx, by = 13.0, 1.4
    box("bin_body", bx, bx + 5.6, by - 1.6, by + 1.6, 0.0, 2.3, bin_body, bevel=0.10)
    box("bin_front", bx + 0.25, bx + 5.35, by - 1.75, by - 1.5, 0.2, 2.1, bin_front)
    box(
        "bin_rim",
        bx - 0.1,
        bx + 5.7,
        by - 1.7,
        by + 1.7,
        2.3,
        2.5,
        bin_edge,
        bevel=0.06,
    )
    # a heap, not a stack — spent cells thrown in, at angles
    for i, (ox, oy, oz, rot) in enumerate(
        [
            (0.5, -0.5, 1.5, 6),
            (2.2, 0.3, 1.5, -11),
            (1.1, 0.4, 2.25, 19),
            (2.6, -0.7, 2.25, -4),
        ]
    ):
        cell(f"cell_spent_{i}", bx + ox, by + oy, oz, False, rot)


def build_world() -> None:
    """The dusk ridge. One saturated orange subject, everything else dim monochrome —
    the aesthetic the session-start scene establishes and the banners keep."""
    ground = material("ground", GROUND_COL, roughness=0.94)
    bpy.ops.mesh.primitive_plane_add(size=400)
    plane = bpy.context.object
    plane.name = "ground"
    plane.data.materials.append(ground)

    # two far ridges, flat cards, deliberately unlit — texture, not scenery
    far = material("ridge_far", RIDGE_FAR, roughness=1.0)
    for i, (x, y, w, h) in enumerate([(-26, 52, 96, 20), (30, 84, 130, 33)]):
        box(f"ridge_{i}", x - w / 2, x + w / 2, y, y + 2, 0, h, far)

    world = bpy.data.worlds.new("dusk")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    # THE GRADIENT IS DRIVEN BY THE VIEW DIRECTION'S z, not by a Generated texture coordinate.
    # Generated is the obvious wiring and it rendered a black sky: for a world shader it is not
    # a tidy 0..1 vertical ramp, so the whole visible band landed below the ramp's first stop
    # and every pixel came back as the darkest colour. Geometry > Incoming is unambiguous —
    # its z runs -1 straight down to +1 straight up — and Map Range puts the horizon exactly
    # at 0.5 by construction rather than by tuning a number until it looks right.
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = -1.0
    rng.inputs["From Max"].default_value = 1.0
    ramp.color_ramp.elements[0].color = rgba(SKY_LO)
    ramp.color_ramp.elements[1].color = rgba(SKY_HI)
    ramp.color_ramp.elements[0].position = 0.46
    ramp.color_ramp.elements[1].position = 0.72
    bg.inputs["Strength"].default_value = 1.15
    nt.links.new(geo.outputs["Incoming"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def setup_lighting() -> None:
    """A dusk key from behind-left, a cool fill, and the screen doing its own work."""
    bpy.ops.object.light_add(type="AREA", location=(-17, -15, 17))
    key = bpy.context.object
    key.name = "key"
    key.data.energy = 26000
    key.data.size = 16
    key.data.color = rgba("#ffd2b0")[:3]
    key.rotation_euler = (math.radians(58), 0, math.radians(-46))

    bpy.ops.object.light_add(type="AREA", location=(21, 15, 15))
    rim = bpy.context.object
    rim.name = "rim"
    rim.data.energy = 17000
    rim.data.size = 12
    rim.data.color = rgba("#8fa8ff")[:3]
    rim.rotation_euler = (math.radians(116), 0, math.radians(148))

    # a soft frontal fill in the screen's own colour, so the shadow side of the costume is
    # readable without a second white light flattening the dusk
    bpy.ops.object.light_add(type="AREA", location=(5.5, -19, 7))
    fill = bpy.context.object
    fill.name = "fill"
    fill.data.energy = 1500
    fill.data.size = 22
    fill.data.color = rgba("#a9e8d6")[:3]
    fill.rotation_euler = (math.radians(86), 0, 0)

    # A LOW KICKER FOR THE LEGS. Clearing the shell past the legs (SHELL's bottom row) was only
    # half the job: the shell still casts its own shadow straight down over them, so all four
    # went dark the moment they were geometrically visible. Four bare orange legs are the thing
    # that says a CREATURE is wearing this console rather than a console standing on the
    # ground, so they get their own light rather than being left to the fill.
    bpy.ops.object.light_add(type="AREA", location=(5.5, -13, 1.6))
    kick = bpy.context.object
    kick.name = "leg_kicker"
    kick.data.energy = 900
    kick.data.size = 9
    kick.data.color = rgba("#ffc9a4")[:3]
    kick.rotation_euler = (math.radians(96), 0, 0)


def setup_camera(shot: str) -> bpy.types.Object:
    """Two framings. `hero` is the README still; `portrait` is the costume close enough to
    audit — the straps, the bare orange strip beside the shell, the eyes behind the glass."""
    # The subject is not the creature alone — it spans the charger at x=-6.4 to the crate at
    # x=18.6, so the hero framing centres on 6.1 rather than on clawd's own 5.5. Centring on
    # the creature pushed the crate off the right edge in the first pass.
    if shot == "portrait":
        loc = Vector((6.9, -23.0, 6.4))
        lens = 62.0
        target = Vector((5.5, 0.0, 4.6))
    elif shot == "three-quarter":
        # The one framing that proves the scene is built rather than drawn: from here the
        # shell stands off the body as a separate object, the straps wrap round the side of
        # the head, and the screen is a recess with depth instead of a flat panel.
        loc = Vector((-11.0, -26.0, 9.0))
        lens = 58.0
        target = Vector((5.0, 0.0, 3.6))
    else:
        loc = Vector((6.1, -37.0, 10.0))
        lens = 55.0
        target = Vector((6.1, 0.0, 3.8))

    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.name = f"cam_{shot}"
    cam.data.lens = lens
    direction = target - loc
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


ORBIT_PIVOT = Vector((6.1, 0.0, 3.8))
ORBIT_RADIUS = 37.0
ORBIT_HEIGHT = 10.0
ORBIT_LENS = 55.0
ORBIT_SWING_DEG = 30.0  # peak swing either side of the hero's dead-on framing


def orbit_angle(i: int, frames: int) -> float:
    """Frame index -> camera angle, in radians, as a PING-PONG rather than a full circle.

    A 360 turntable is the obvious motion and it is the wrong one here: this scene is built to
    be seen from the front. The far ridges only exist at +y, the charger and the crate are
    placed for a frontal read, and the lights are a front key/rim pair — so the back half of a
    full revolution is an unlit void with the props edge-on. Swinging +/-30 degrees shows the
    parallax that proves the scene is solid (the shell separating from the body, the straps
    wrapping the head) without ever turning to a side that was never dressed.

    A sine ping-pong is also seamless FOR FREE, which a linear sweep is not: sin returns to 0
    at i = frames, so frame 0 and frame `frames` are the same camera and the cycle closes with
    no reversal jerk at the ends — the ease-in/out is the derivative of the sine, not a curve
    that had to be hand-tuned.
    """
    return math.radians(ORBIT_SWING_DEG) * math.sin(2 * math.pi * i / frames)


def assert_orbit_loop_closes(frames: int) -> None:
    """The cycle must return exactly to its start, and must not be a still.

    This repo already refuses to emit a loop whose first and last frame differ (see the banner
    generators); the same standard applies to a rendered one. Both halves matter: a loop that
    does not close pops on repeat, and a 'loop' whose frames never move is a still with a
    filesize, which would pass a closure check on its own.
    """
    start, end = orbit_angle(0, frames), orbit_angle(frames, frames)
    if abs(start - end) > 1e-9:
        raise SystemExit(
            f"orbit does not close: angle(0)={start:.9f} but angle({frames})={end:.9f}"
        )
    swing = max(abs(orbit_angle(i, frames)) for i in range(frames))
    if swing < math.radians(1.0):
        raise SystemExit(
            f"orbit peaks at {math.degrees(swing):.3f} degrees — that is a still, not a move"
        )
    print(
        f"ORBIT OK — {frames} frames, closes exactly, peak swing "
        f"{math.degrees(swing):.1f} degrees"
    )


def place_orbit_camera(cam: bpy.types.Object, angle: float) -> None:
    cam.location = ORBIT_PIVOT + Vector(
        (
            ORBIT_RADIUS * math.sin(angle),
            -ORBIT_RADIUS * math.cos(angle),
            ORBIT_HEIGHT - ORBIT_PIVOT.z,
        )
    )
    cam.rotation_euler = (
        (ORBIT_PIVOT - cam.location).to_track_quat("-Z", "Y").to_euler()
    )


def render_orbit(
    out_dir: str, frames: int, width: int, height: int, samples: int
) -> str:
    """Render the ping-pong orbit as a numbered PNG sequence."""
    assert_orbit_loop_closes(frames)
    seq = os.path.join(out_dir, "orbit")
    os.makedirs(seq, exist_ok=True)

    bpy.ops.object.camera_add(location=(0, 0, 0))
    cam = bpy.context.object
    cam.name = "cam_orbit"
    cam.data.lens = ORBIT_LENS
    bpy.context.scene.camera = cam

    _configure_render(width, height, samples)
    for i in range(
        frames
    ):  # 0..frames-1: frame `frames` IS frame 0, so it is never emitted
        place_orbit_camera(cam, orbit_angle(i, frames))
        bpy.context.scene.render.filepath = os.path.join(seq, f"f{i:04d}")
        bpy.ops.render.render(write_still=True)
        if i % 12 == 0:
            print(f"  orbit frame {i}/{frames}")
    print(f"WROTE {seq}/f0000..f{frames - 1:04d}.png")
    return seq


def _configure_render(width: int, height: int, samples: int) -> None:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = samples
    sc.eevee.use_raytracing = True
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    # STANDARD, NOT AgX — and this is a palette decision, not a taste one. This repo's whole
    # claim about the mascot is that #D77757 is the exact orange read out of the binary; AgX
    # is a filmic transform that desaturates and shifts saturated hues by design, so it would
    # render an orange that is provably not the one the character ships as. Standard is a
    # straight sRGB encode, so the body colour survives to the PNG.
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"


def render(out_dir: str, name: str, width: int, height: int, samples: int) -> str:
    _configure_render(width, height, samples)
    path = os.path.join(out_dir, name)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path + ".png"


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(prog="clawd_bmo.py")
    ap.add_argument("--out", default="assets/blender")
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--height", type=int, default=900)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument(
        "--shot", default="hero", choices=["hero", "portrait", "three-quarter", "all"]
    )
    ap.add_argument("--save-blend", action="store_true")
    ap.add_argument(
        "--orbit",
        type=int,
        default=0,
        metavar="FRAMES",
        help="render a seamless ping-pong orbit as a PNG sequence instead of stills",
    )
    args = ap.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    _intended.clear()

    clawd = build_clawd()
    build_costume(clawd)
    build_props()
    build_world()
    setup_lighting()
    assert_palette()

    if args.orbit:
        render_orbit(args.out, args.orbit, args.width, args.height, args.samples)
    else:
        shots = (
            ["hero", "portrait", "three-quarter"] if args.shot == "all" else [args.shot]
        )
        for shot in shots:
            setup_camera(shot)
            p = render(
                args.out, f"clawd-bmo-{shot}", args.width, args.height, args.samples
            )
            print(f"WROTE {p}")

    if args.save_blend:
        blend = os.path.abspath(os.path.join(args.out, "clawd-bmo.blend"))
        bpy.ops.wm.save_as_mainfile(filepath=blend)
        print(f"WROTE {blend}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
