"""
palette.py -- KPMG's two-colour page grammar, as a refusal rather than a lookup table.

=============================================================================================
SUPERSEDED AS A LAYOUT SYSTEM, 2026-08-09. READ THIS BEFORE REACHING FOR `legal_pairs`.
=============================================================================================

Everything below encodes the **2015** brand book's Group 3 page grammar: seven colours, any two
different, as a 10/90 or 40/60 field. The **FY22** brand guidelines (March 2022, obtained in
full -- see docs/research/KPMG-SYSTEM-2026-08-08/S7-fy22-brandbook.md) REPLACE that system
outright. FY22 has no layout groups and no pair matrix. It has one graphic device, **the
window**, on one of **two** permitted gradients.

WHAT IS STILL LIVE IN THIS FILE, and it is not nothing:

  BODY_FIELDS / DISPLAY_FIELDS / ELEMENT_ONLY / ON_WHITE
      The AA rider -- which colours can carry white type at body and display weight. That is
      OUR rule, derived from contrast measurement, not from either brand book, so no edition
      supersedes it. `Deck.blocks` depends on this and is correct to.
  LEGACY_2015_MAPPING
      The argued 2015 -> 2022 hex mapping. Still the record of how the old names map.

WHAT IS DEAD: `legal_pairs`, `pair`, `rotate`, `gradient_stops`, `PAIR_SET` as a page system,
and the 30-pair count. `Deck.group3_a` / `group3_b` are the archetypes that consume them and
carry the same notice. Nothing new should be built on them. They are kept, not deleted, because
a 2015-era document is still a real genre and because deleting the reasoning would delete the
record of how the error was found.

THE ERROR THIS FILE IS THE MONUMENT TO, stated so the next author does not repeat it: this
whole system was reconstructed from 95 rendered pages plus an eleven-year-old book, and it was
a faithful reading of real evidence that was nonetheless not the current rule. Sampling outputs
tells you what someone did; only the rulebook tells you what is allowed.

WHAT THIS ENCODES, AND WHY IT IS NOT A LIST OF PAIRS

KPMG's brand book prints the same table twice -- p.115 in the Layout section, headed "Color
combinations", and p.60 in the Colour section, headed "An overview of our colors". Both show
the same grid: SEVEN colours, each appearing as a narrow vertical element against each of the
other six as the wide field. 7 x 6 = 42 cells. The page's own caption states the rule in one
sentence:

    "Please note that under no circumstances can the same color be used twice in one layout."

BECAUSE THE MATRIX IS THE COMPLETE PERMUTATION TABLE, THERE IS NOTHING TO TRANSCRIBE. A reader
seeing "42 combinations" naturally assumes 42 hand-picked pairs and starts typing them in. They
are not curated -- they are every ordered pair of two different colours from the set, and the
ordering carries only which one is the 10% element and which the 90% field. So the rule reduces
to "two of the set, different", and the correct way to encode it is a check that REFUSES, not a
table that can silently fall out of date.

That idiom is already in this package: `oxml.set_gradient` refuses a non-adjacent stop pair
rather than describing the constraint in a reference file, because the previous version WAS
described in a reference file and the description was false for two years without anything
catching it. Same reasoning, same shape.

WHERE THIS OVERRULES BUILD-SPEC

`docs/research/KPMG-SYSTEM-2026-08-08/BUILD-SPEC.md` derived this package's colour behaviour from
the KPMG CEO-Outlook report family. That family is MONOCHROME -- 40 interior pages re-examined,
every coloured page one hue against white, not a single two-colour field anywhere. It is a real
genre and the measurement of it was correct, but it cannot testify about a cover-and-divider
rule it never exercises. On colour PAIRING the brand book outranks it, and the deck built to the
monochrome measurement was rejected on sight as "a generic blue theme". Where the two disagree,
the book wins and this comment is the record of the disagreement.

THE BRAND BOOK CONFLICTS WITH WCAG HERE, AND WCAG WINS -- see THE AA RIDER below.
"""

from __future__ import annotations

import itertools

from .tokens import Brand, contrast_ratio


class PairError(ValueError):
    """A two-colour layout that the brand system does not permit."""


# ---------------------------------------------------------------------------
# The set
# ---------------------------------------------------------------------------

# Ordered the way the book orders its own overview: the three primaries first, then the
# secondaries. Role names, never hexes -- brands/kpmg.json is the single source of truth for
# values and this module must not become a second one.
PAIR_SET: tuple[str, ...] = (
    "pair_kpmg_blue",  # primary
    "pair_cobalt",  # primary
    "pair_pacific",  # primary
    "pair_dark_blue",  # secondary
    "pair_deep_purple",  # secondary
    "pair_purple",  # secondary
    "pair_light_purple",  # secondary
)

# This module encodes a KPMG rule, so it reads the KPMG brand. A different brand does not have a
# two-colour page grammar to enforce; it has its own, or none.
_BRAND = Brand.load("kpmg")
_HEX: dict[str, str] = {role: _BRAND.color(role).upper() for role in PAIR_SET}
_BY_HEX: dict[str, str] = {h: role for role, h in _HEX.items()}


# ---------------------------------------------------------------------------
# The 2015 -> 2022 mapping. The genuinely uncertain step, argued row by row.
# ---------------------------------------------------------------------------

# The matrix above is printed in the 2015 brand recipe book, whose seven colours are DEAD --
# KPMG changed its palette in 2022 and not one of the four non-blue hexes survived. The
# structure survived; the values did not. This table is the bridge, and it is the only place in
# this package where a superseded hex is written down, deliberately: someone porting a 2015-era
# deck needs to look up what a page's colour became, and putting those hexes in brands/kpmg.json
# would put dead values in the file whose whole job is to hold live ones.
#
# `to_role` is None where the slot has no legal successor. `confidence` is honest, not decorative
# -- read the "least sure" rows before trusting a divider's colour.
#
#   name_2015          hex_2015    to_role              confidence  why
LEGACY_2015_MAPPING: tuple[tuple[str, str, str | None, str, str], ...] = (
    (
        "KPMG Blue",
        "#00338D",
        "pair_kpmg_blue",
        "certain",
        "Why: not a mapping at all -- the hex is unchanged across the 2022 rebrand. The logo "
        "blue is the one fixed point in the system.",
    ),
    (
        "Medium Blue",
        "#005EB8",
        "pair_cobalt",
        "certain",
        "Why: the mid-blue slot, and Cobalt #1E49E2 is what occupies it in every current-era "
        "KPMG document. #005EB8 returns zero hits in KPMG's live stylesheet; it is one of the "
        "four values every colour-aggregator site still serves, which is exactly the trap "
        "brands/kpmg.json's _README exists to name.",
    ),
    (
        "Light Blue",
        "#0091DA",
        "pair_pacific",
        "certain",
        "Why: the light-cyan slot. Pacific #00B8F5 is also, by frequency, KPMG's default "
        "single-series chart fill, so it is the best-attested colour in the 2022 set.",
    ),
    (
        "Violet",
        "#483698",
        "pair_deep_purple",
        "confident",
        "Why: nearest in BOTH hue and luminance -- 9.31:1 against white becomes 9.84:1. Of the "
        "three purple rows this is the one that needs no argument.",
    ),
    (
        "Light Purple",
        "#A6228D",
        "pair_purple",
        "least sure -- hue moves",
        "Why: matched on luminance (6.49:1 -> 7.01:1) and on position-in-set (the lightest of "
        "the three purples that may carry type), NOT on hue: #A6228D is a magenta and #7213EA "
        "is a violet. REJECTED ALTERNATIVE: Pink #FD349C, which is the true hue successor and "
        "is 3.42:1. It was rejected on measured practice, not on taste -- #FD349C is 0.01% of "
        "57.1 million pixels across 320 pages of ten KPMG decks, i.e. present in the colour set "
        "and absent from the work. A field colour that never appears as a field in the corpus "
        "is not the successor to one that appeared 42 ways. Same evidence, same conclusion as "
        "the _dataviz_rationale block that already removed #FD349C from the series order.",
    ),
    (
        "Purple",
        "#470A68",
        "pair_dark_blue",
        "least sure -- family changes",
        "Why: #470A68 is the DARKEST field in the 2015 set (13.90:1) and the 2022 set contains "
        "no aubergine at all. The choice is between preserving the hue family and preserving "
        "the structural slot, and the slot wins: a system with no very-dark field loses the "
        "page that the book uses most. Dark blue #0C233C is that field in the current era by a "
        "wide margin -- 204 occurrences in KPMG's live stylesheet, the single most-used token "
        "in it. REJECTED ALTERNATIVE: retire this slot too, leaving six colours and 20 legal "
        "pairs. Rejected because it would delete the darkest ground from a system whose covers "
        "are mostly dark, for the sake of hue tidiness. THIS IS THE ROW TO REVISIT FIRST if the "
        "SSO-gated Brand Central portal ever becomes reachable.",
    ),
    (
        "Green",
        "#00A3A1",
        None,
        "certain -- RETIRED",
        "Why: there is no legal successor. The only greens in the 2022 palette (#098E7E, "
        "#00C0AE) come from KPMG's 'additional colours for infographics and charts' set, and "
        "brands/kpmg.json states in its own words that those 'are explicitly NOT brand colours "
        "and must never appear as page furniture'. A green divider would be off-brand in a way "
        "that looks deliberate, which is worse than one that looks like a mistake.",
    ),
)

# One colour in PAIR_SET has no 2015 antecedent, and saying so matters because the set came out
# at seven again and that looks like the mapping preserved seven. It did not: the green left and
# this arrived.
NEW_IN_2022: tuple[tuple[str, str], ...] = (
    (
        "pair_light_purple",
        "Why: #B497FF is a pastel and the 2015 set contained nothing pale at all -- its lightest "
        "member, Light Blue, was 3.46:1. It enters as an ELEMENT ONLY (2.38:1 against white; see "
        "THE AA RIDER), which is precisely where the 2022 palette's pale colours are strongest: "
        "a 10% strip of #B497FF against a #510DBC field is a current-era KPMG page and has no "
        "2015 equivalent.",
    ),
)


# ---------------------------------------------------------------------------
# THE AA RIDER -- ours, not KPMG's, and the reason a name-for-name mapping breaks
# ---------------------------------------------------------------------------
#
# The book requires WHITE logo and white type on these layouts, without qualification. Against
# the 2015 hexes that was nearly safe: the set bottomed out at 3.11:1, large-text-legal
# throughout. Against the 2022 hexes it is not safe, and this is the single most consequential
# thing the rebuild found:
#
#     white on...   2015                          2022
#                   Purple       #470A68  13.90   Dark blue    #0C233C  15.89
#                   KPMG Blue    #00338D  11.30   KPMG Blue    #00338D  11.30
#                   Violet       #483698   9.31   Deep purple  #510DBC   9.84
#                   Light Purple #A6228D   6.49   Purple       #7213EA   7.01
#                   Medium Blue  #005EB8   6.38   Cobalt       #1E49E2   6.76
#                   Light Blue   #0091DA   3.46   Light purple #B497FF   2.38  <- illegal, any size
#                   Green        #00A3A1   3.11   Pacific      #00B8F5   2.29  <- illegal, any size
#
# So a naive name-for-name mapping produces unreadable pages, and it would pass any check that
# only asked "are these two colours different" -- which is exactly what the book's own rule asks.
#
# THE RESOLUTION NEEDS NO DEVIATION FROM THE BOOK, because the archetypes already say which field
# carries type. In the narrow-element layout the 10% element carries nothing and the 90% field
# carries everything; in the wide-element layout the 40% element carries the logo and headline
# and the 60% field is empty. Exactly one field per layout is type-bearing. Hence:
#
#     The type-bearing field must reach >= 4.5:1 against white where it carries BODY copy, and
#     >= 3.0:1 where it carries DISPLAY type only. The other field is unconstrained.
#
# That admits Pacific and Light purple as ELEMENTS -- where they are strongest -- and keeps them
# out from under type. It also matches what the book does with its own weakest colour: p.71 sets
# one huge display word on Light Blue at 3.46:1 and never sets body copy there.
#
# BRAND BOOK vs WCAG, AND WHY WCAG WINS HERE. White-on-pale legibility is a room constraint, not
# a taste one: 140 people, a lit room, a projector that loses a great deal of contrast against
# the laptop the deck was built on. This is the THIRD time this package has taken the same
# deviation for the same reason, and the other two are recorded in brands/kpmg.json's
# _roles_rationale: Gray 3 #989898 -> #666666 for muted text (2.88:1, fails at every size), and
# the inactive nav tab #B2B2B2 -> #666666 (2.12:1). Every one of them is a value chosen for small
# type in a PDF read at a desk, reused at projector distance. Taking the deviation is not
# improving on KPMG's judgment; it is applying it to a medium it was not written for.
#
# THE CLASSIFICATION BELOW IS COMPUTED, NEVER TYPED. Only the two WCAG constants are literals.
# Change a hex in brands/kpmg.json and the tiers move with it -- which is the point, because a
# hardcoded "Pacific is element-only" would silently rot the day Pacific changes.

BODY_MIN_RATIO = 4.5
DISPLAY_MIN_RATIO = 3.0

ON_WHITE: dict[str, float] = {
    role: contrast_ratio("#FFFFFF", _HEX[role]) for role in PAIR_SET
}

# CHART-ONLY COLOURS ARE EXCLUDED FROM EVERY FIELD SET, and this is a rule no contrast maths
# could have produced. FY22 p.48 fences eight colours inside a dotted outline captioned "for use
# in infographics and charts only", and p.53 states it flatly: the secondary palette is reserved
# for data. A colour can therefore be on-palette, legible, and still forbidden as page furniture.
#
# It caught a live defect: Dark Purple #510DBC cleared 9.84:1 against white, so it was in
# BODY_FIELDS, so `Deck.blocks` was painting it as a full-width content block on shipped slides.
# Every gate passed, because every gate asked whether a colour was ON PALETTE and none asked what
# the palette said it was FOR.
CHART_ONLY: frozenset[str] = frozenset(
    h.upper() for h in _BRAND.chart_only
)


def _is_furniture(role: str) -> bool:
    """Whether this colour may be used as page furniture rather than only in charts."""
    return _HEX[role] not in CHART_ONLY


BODY_FIELDS: tuple[str, ...] = tuple(
    r for r in PAIR_SET if ON_WHITE[r] >= BODY_MIN_RATIO and _is_furniture(r)
)
DISPLAY_FIELDS: tuple[str, ...] = tuple(
    r for r in PAIR_SET if ON_WHITE[r] >= DISPLAY_MIN_RATIO and _is_furniture(r)
)
ELEMENT_ONLY: tuple[str, ...] = tuple(r for r in PAIR_SET if r not in DISPLAY_FIELDS)


# ---------------------------------------------------------------------------
# THE COUNT. 42 was the 2015 number. Do not assert it -- it is no longer true.
# ---------------------------------------------------------------------------
#
# The arithmetic, and every term of it is computed below rather than quoted:
#
#     2015          7 colours x 6 others            = 42 ordered pairs
#     2022 set      7 colours (one retired, one new) = 42 permutations, unchanged
#     AA rider      only 5 of the 7 may be the type-bearing FIELD
#                   -> 5 fields x 6 elements each   = 30 legal pairs
#                   -> 12 refused (Pacific and Light purple as a field, 2 x 6)
#
# So the number is 30, not 42, and the 12 that went are exactly the unreadable ones.
#
# A SECOND RESULT, AND IT IS THE SURPRISING ONE: the display tier is EMPTY. legal_pairs(body=
# False) returns the same 30 pairs as legal_pairs(body=True), because no colour in the set lands
# between 3.0 and 4.5 -- the 2022 palette is bimodal, five colours above 6.7:1 and two below
# 2.4:1, with nothing in the gap. The relaxation is real and correctly implemented and currently
# buys zero additional pairs. It is kept, not deleted, because the gap is one hex change wide:
# the moment a mid-tone enters the set (the dark green #098E7E is 4.05:1 and would land there if
# it ever stopped being chart-only) the two tiers separate and the distinction starts paying.
# A caller who sees the two counts match should read this paragraph rather than assume a bug.


def _pairs(fields: tuple[str, ...]) -> tuple[tuple[str, str], ...]:
    return tuple(
        (element, field) for field in fields for element in PAIR_SET if element != field
    )


_LEGAL_BODY = _pairs(BODY_FIELDS)
_LEGAL_DISPLAY = _pairs(DISPLAY_FIELDS)


def legal_pairs(*, body: bool = True) -> tuple[tuple[str, str], ...]:
    """
    Every legal (element_role, field_role) pair, as role names.

    `body=True` means the field carries body copy and must clear 4.5:1 against white.
    `body=False` means it carries display type only and needs 3.0:1. See THE COUNT above for
    why both currently return the same 30 pairs -- that is a fact about the palette, not a bug.

    Resolve the roles through `Brand.color()`. This function never returns a hex, so there is
    exactly one place a value can be wrong.
    """
    return _LEGAL_BODY if body else _LEGAL_DISPLAY


def _resolve(value: str, what: str) -> str:
    """Accept a role name or a hex; return the canonical role name or raise."""
    if value in _HEX:
        return value
    candidate = value.upper()
    if not candidate.startswith("#"):
        candidate = "#" + candidate
    if candidate in _BY_HEX:
        return _BY_HEX[candidate]
    raise PairError(
        f"{value!r} is not a Group 3 colour, so it cannot be the {what} of a two-colour "
        f"layout. The set is {list(PAIR_SET)}. If you reached for a green, note that the 2022 "
        f"greens are chart-only and the 2015 Green slot was retired with no successor -- see "
        f"LEGACY_2015_MAPPING."
    )


def pair(element: str, field: str, *, body: bool = True) -> tuple[str, str]:
    """
    Validate a two-colour layout and return its (element_role, field_role).

    Raises PairError on the same colour twice, on an off-palette colour, or on a field that
    cannot legally carry white type at the requested weight.

    Accepts role names or hexes and always returns role names, so a caller may hand back what
    `Brand.color()` gave it and still get a checked answer.
    """
    element_role = _resolve(element, "element")
    field_role = _resolve(field, "field")

    if element_role == field_role:
        raise PairError(
            f"{element_role} on both sides. The brand book's words: 'under no circumstances can "
            f"the same color be used twice in one layout' (p.115). A one-colour page is a "
            f"legitimate KPMG page -- it is just not a Group 3 layout, so build it as a plain "
            f"field instead of asking for a pair."
        )

    allowed = BODY_FIELDS if body else DISPLAY_FIELDS
    if field_role not in allowed:
        need = BODY_MIN_RATIO if body else DISPLAY_MIN_RATIO
        kind = "body copy" if body else "display type"
        raise PairError(
            f"{field_role} ({_HEX[field_role]}) measures {ON_WHITE[field_role]:.2f}:1 against "
            f"white and cannot carry {kind}, which needs {need}:1. The brand book asks for white "
            f"type on any of these layouts and against the 2022 palette that is unsafe -- see "
            f"THE AA RIDER. Use it as the ELEMENT instead, where it carries no type and is at "
            f"its strongest; legal fields are {list(allowed)}."
        )

    return (element_role, field_role)


# ---------------------------------------------------------------------------
# The walk
# ---------------------------------------------------------------------------
#
# The book does not merely permit variety, it instructs it -- p.112: "try to use as many
# combinations as you can over a period of time" -- and it obeys itself: eight of its own section
# dividers are two-colour pages and no pair repeats across them.
#
# So consecutive dividers must differ, and the strong form of that is that consecutive pairs
# share NO colour at all -- otherwise divider 3 and divider 4 both being "something on KPMG Blue"
# reads as one long section, which is the opposite of what a divider is for.
#
# THE FIELD CYCLES ROUND-ROBIN, AND THE FIRST VERSION OF THIS FUNCTION DID NOT, WHICH IS WHY THE
# RULE IS WRITTEN DOWN. A plain "first pair that shares nothing with the previous one" walk
# satisfies the disjointness rule perfectly and still produces KPMG Blue as the field on dividers
# 0, 2, 4 and 6 -- every other section the same colour, which is the exact monotony this walk
# exists to prevent. Disjointness is a constraint on ADJACENT pairs and says nothing about the
# run; only cycling the field says anything about the run. Both rules are needed, and the
# disjointness one is the weaker of the two.
#
# ONE PAIR IS EXCLUDED FROM THE WALK AND IT IS NOT EXCLUDED FROM legal_pairs(). Dark blue #0C233C
# against KPMG Blue #00338D is two different colours by the book's rule and measures 1.41:1
# against each other -- same hue family, adjacent in luminance, and at projector distance a
# viewer will see one navy page with a slightly darker stripe rather than a two-colour layout.
# It is NOT refused, because the book's own matrix certifies pairs far closer than that: Medium
# Blue against Light Purple is 1.02:1, essentially identical in luminance, and the book pairs
# them anyway because the HUES are unmistakably different. Luminance separation is therefore not
# the rule and inventing a floor from it would be our arithmetic overruling KPMG's eye. What is
# defensible is narrower: never let the automatic rotation CHOOSE the one pair whose hues are not
# different either. An author who asks for it explicitly gets it, and verify.check_pairs warns.
NEAR_IDENTICAL_PAIRS: frozenset[frozenset[str]] = frozenset(
    {frozenset({"pair_dark_blue", "pair_kpmg_blue"})}
)


# ---------------------------------------------------------------------------
# Hue families -- the THIRD walk constraint, and the one the rejection was about
# ---------------------------------------------------------------------------
#
# The first version of this walk satisfied both of its rules -- the field cycles, adjacent pairs
# share no colour -- and still produced this as its first eight:
#
#     cobalt/kpmg_blue  pacific/dark_blue  kpmg_blue/cobalt  pacific/deep_purple
#     kpmg_blue/purple  cobalt/dark_blue   pacific/kpmg_blue dark_blue/cobalt
#
# Six of eight are two blues. A course deck uses about seven, so the deck would have opened on
# the same wall of blue that got the previous build rejected -- this time with a rule behind it,
# which is worse. NEITHER EXISTING RULE IS ABOUT HUE, so neither could have caught it.
#
# THE BOOK SUPPLIES THE MISSING RULE AND IT IS MEASURED, NOT A PREFERENCE. Its own eight section
# dividers, element/field: Purple/Green (p44), Green/MediumBlue (p52), MediumBlue/KPMGBlue (p59),
# Green/Violet (p64), Violet/LightBlue (p71), Green/KPMGBlue (p95), Purple/MediumBlue (p100),
# MediumBlue/KPMGBlue (p117). SIX OF THE EIGHT CROSS HUE FAMILIES; the only two that do not are
# the same pair twice. The dominant move is a non-blue element against a blue field.
#
# Current practice agrees. The 2026 KPMG Luxembourg Impact Report runs its four dividers dark
# blue -> cyan -> blue-purple -> purple, and the 2023 KPMG India deck sets its section openers in
# PURPLE. See S6-current-era-sources.md.
#
# WHY THE RULE HAS TO BE ADDED HERE RATHER THAN INHERITED: the 2015 set was 3 blues, 3 purples
# and a green, so a hue-blind walk landed on cross-family pairs most of the time by construction.
# The mapped 2022 set is 4 blues to 3 purples, and three of the five colours legally allowed to
# be the FIELD are blue. The same blind walk on a blue-heavier set behaves differently, so this
# is a consequence of the mapping and has to be corrected where the mapping landed.
#
# Same-family pairs stay LEGAL -- the book certifies MediumBlue/KPMGBlue twice, so they are not
# wrong. They are just not what the rotation reaches for first. 17 of the 30 pairs cross.
HUE_FAMILY: dict[str, str] = {
    "pair_kpmg_blue": "blue",
    "pair_cobalt": "blue",
    "pair_pacific": "blue",
    "pair_dark_blue": "blue",
    "pair_deep_purple": "purple",
    "pair_purple": "purple",
    "pair_light_purple": "purple",
}


def crosses_families(element: str, field: str) -> bool:
    """True when the two colours come from different hue families."""
    return HUE_FAMILY[element] != HUE_FAMILY[field]


def gradient_stops(
    element: str, field: str, *, body: bool = True
) -> list[tuple[float, str]] | None:
    """
    The two-stop ramp for a Group 3 field, or None when this pair has no measured ramp.

    Returns `[(0.0, field_hex), (1.0, element_hex)]` -- the FIELD's own colour at position 0,
    ramping toward the element's colour at 1.0.

    WHY THIS EXISTS. Current KPMG colour fields are gradients, not flat fills: every one of the
    eight full-bleed coloured pages in the 2026 KPMG Luxembourg Impact Report is a two-stop ramp,
    and every one runs between two DIFFERENT brand colours. That is this module's matrix rendered
    with current tooling rather than 2015's, which is why a correct flat hex still reads as a
    generic blue panel. See S6-current-era-sources.md.

    WHY IT RETURNS None RATHER THAN ALWAYS RAMPING, and this is the honest part. `oxml`'s
    GRADIENT_ADJACENCY is a record of ramps that have been OBSERVED in KPMG material, and it is
    small -- nine pairs. Most of the 30 legal Group 3 pairs have never been seen as a ramp. A
    ramp between two colours nobody has observed KPMG ramping between is our invention, and
    inventing one is the same class of error as inventing a colour pair, which this module exists
    to prevent. So: measured ramp -> gradient; everything else -> flat, and flat is not a
    fallback. KPMG's own 2023 PowerPoint deck is 6 gradient pages and 3 flat ones.

    WHY THE FIELD COLOUR SITS AT POSITION 0, which is the AA rider extended rather than dropped.
    The rider binds a single field colour and a ramp has no single colour, so "can this carry
    white type" has to become a question about WHERE the type sits. In G3-A the type sits at the
    left of the field, so the left stop is the one under it -- and `pair()` has already certified
    that the field colour clears the threshold. Ordering the ramp the other way would put type
    over an uncertified colour. KPMG does the same thing: the 2026 divider that ramps Dark blue
    to Light purple sets its type over the dark end and leaves the pale end empty. Light purple
    is 2.38:1 and would be illegal under type anywhere on that page.
    """
    from .oxml import GRADIENT_ADJACENCY  # noqa: PLC0415 -- avoids an import cycle

    element_role, field_role = pair(element, field, body=body)
    if frozenset((_HEX[element_role][1:], _HEX[field_role][1:])) not in GRADIENT_ADJACENCY:
        return None
    return [(0.0, _HEX[field_role]), (1.0, _HEX[element_role])]


def _has_ramp(element: str, field: str) -> bool:
    """Whether this pair is one of the ramps observed in KPMG material. Never raises."""
    try:
        return gradient_stops(element, field) is not None
    except PairError:
        return False


def _build_walk(pairs: tuple[tuple[str, str], ...]) -> tuple[tuple[str, str], ...]:
    """
    Order every legal pair so the field cycles, adjacent pairs share no colour, and each pair
    crosses hue families where one is available.

    Deterministic and total: it emits each pair exactly once. The three rules can in principle
    all be unsatisfiable at the same step, which is why the fallbacks are explicit rather than
    an exception -- a walk that refused to finish would be a worse failure than one repetition
    near the end of a 30-pair cycle. The cross-family rule is the FIRST to be given up, because
    it is a preference between legal pairs while the other two are structural.
    """
    fields = [f for f in PAIR_SET if any(p[1] == f for p in pairs)]
    pool: dict[str, list[str]] = {
        f: [
            e
            for e, ff in pairs
            if ff == f and frozenset((e, ff)) not in NEAR_IDENTICAL_PAIRS
        ]
        for f in fields
    }
    total = sum(len(v) for v in pool.values())
    # A field goes to the BACK of the rota the moment it is used, so it cannot come round again
    # until every other field has had its turn. Rotating by a step COUNTER instead looks
    # equivalent and is not: a blocked field silently forfeits its slot and the counter marches
    # on without it, which put KPMG Blue back on every other divider.
    rota = list(fields)
    ordered: list[tuple[str, str]] = []
    used: set[str] = set()

    while len(ordered) < total:
        choice = None
        # Four passes, weakest preference given up first. The two STRUCTURAL rules (field
        # cycles, adjacent pairs disjoint) hold in every pass; only the two PREFERENCES relax.
        #
        #   1. crosses hue families AND has a measured ramp   -- the best page this system makes
        #   2. crosses hue families                           -- flat, but not a wall of blue
        #   3. has a measured ramp                            -- same family, but it ramps
        #   4. anything still unused                          -- structural rules only
        #
        # Cross-family outranks ramp-availability deliberately. Hue monotony is what got the
        # previous build rejected; a flat page in two clearly different colours is a KPMG page,
        # while a ramp between two blues is the rejected deck with a gradient on it. Ramps are
        # scarce anyway -- only about a third of the legal pairs have ever been observed as one
        # (see gradient_stops) -- so demanding both at every step would exhaust them and force
        # repeats, which is why this is a preference ladder and not a filter.
        # THE LADDER RANKS ELEMENTS WITHIN A FIELD; IT NEVER CHOOSES BETWEEN FIELDS. An earlier
        # version let a later pass reach past the front of the rota to a field with a better
        # element, which broke the field-cycling invariant and was caught by the assertion at
        # the bottom of this file rather than by anything visible -- exactly what that assertion
        # is for. The rota is structural and picks the field; the ladder only decides which
        # element goes against it.
        for f in rota:
            if not pool[f] or f in used:
                continue
            for want_cross, want_ramp in (
                (True, True),
                (True, False),
                (False, True),
                (False, False),
            ):
                element = next(
                    (
                        e
                        for e in pool[f]
                        if e not in used
                        and (not want_cross or crosses_families(e, f))
                        and (not want_ramp or _has_ramp(e, f))
                    ),
                    None,
                )
                if element is not None:
                    choice = (element, f)
                    break
            if choice is not None:
                break
        if (
            choice is None
        ):  # all rules unsatisfiable -- take the front-most pair still unused
            f = next(f for f in rota if pool[f])
            choice = (pool[f][0], f)
        pool[choice[1]].remove(choice[0])
        rota.remove(choice[1])
        rota.append(choice[1])
        ordered.append(choice)
        used = set(choice)

    return tuple(ordered)


_WALK_BODY = _build_walk(_LEGAL_BODY)
_WALK_DISPLAY = _build_walk(_LEGAL_DISPLAY)


def rotate(index: int, *, body: bool = True) -> tuple[str, str]:
    """
    The nth pair of a deterministic non-repeating walk, so consecutive dividers differ.

    Pass the divider's ordinal. The walk visits every legal pair before repeating any, and
    consecutive entries share no colour, so divider N and divider N+1 never sit on the same
    field. Deterministic: the same index always gives the same pair, so a rebuild does not
    reshuffle a deck someone has already reviewed.
    """
    walk = _WALK_BODY if body else _WALK_DISPLAY
    return walk[index % len(walk)]


# ---------------------------------------------------------------------------
# Self-checks. Cheap (30 items) and they run at import, because every claim in the
# comments above is either checked here or is a citation.
# ---------------------------------------------------------------------------

assert len(PAIR_SET) == len(set(PAIR_SET)) == 7
assert all(role in _BRAND.roles for role in PAIR_SET), (
    "PAIR_SET names a role brands/kpmg.json does not define"
)
assert len(set(_HEX.values())) == 7, "two PAIR_SET roles resolve to the same hex"
assert {m[2] for m in LEGACY_2015_MAPPING if m[2]} | {n[0] for n in NEW_IN_2022} == set(
    PAIR_SET
), "the 2015 mapping and PAIR_SET disagree about the set"
assert len(_LEGAL_BODY) == len(BODY_FIELDS) * (len(PAIR_SET) - 1)
assert all(e != f for e, f in _LEGAL_BODY + _LEGAL_DISPLAY)
assert set(_WALK_BODY) <= set(_LEGAL_BODY) and len(set(_WALK_BODY)) == len(_WALK_BODY)
assert set(_WALK_DISPLAY) <= set(_LEGAL_DISPLAY)

# The two walk rules hold for the whole run EXCEPT the tail, where the pool is nearly empty and
# the fallbacks fire. Asserted rather than claimed, and asserted over the first two thirds --
# a deck has six to nine dividers and never reaches the tail, but a silent regression to
# "KPMG Blue on every other page" must not be possible again.
_HEAD = (len(_WALK_BODY) * 2) // 3
assert not any(set(_WALK_BODY[i]) & set(_WALK_BODY[i - 1]) for i in range(1, _HEAD)), (
    "the rotation walk repeats a colour on consecutive dividers"
)
assert len({f for _, f in _WALK_BODY[: len(BODY_FIELDS)]}) == len(BODY_FIELDS), (
    "the rotation walk does not cycle the field"
)


def explain() -> str:
    """The arithmetic, computed. `python3 -m kpmg_deck.palette` prints it."""
    lines = [
        f"KPMG Group 3 two-colour pairs -- {len(PAIR_SET)} colours in the set",
        "",
        "  colour                 hex       white on it   may be a field",
    ]
    for role in PAIR_SET:
        tier = (
            "body + display"
            if role in BODY_FIELDS
            else ("display only" if role in DISPLAY_FIELDS else "NO -- element only")
        )
        lines.append(f"  {role:22s} {_HEX[role]}   {ON_WHITE[role]:6.2f}:1     {tier}")
    lines += [
        "",
        f"  permutations of the set        {len(PAIR_SET)} x {len(PAIR_SET) - 1} = "
        f"{len(PAIR_SET) * (len(PAIR_SET) - 1)}",
        f"  refused by the AA rider        {len(ELEMENT_ONLY)} x {len(PAIR_SET) - 1} = "
        f"{len(ELEMENT_ONLY) * (len(PAIR_SET) - 1)}",
        f"  legal with body copy           {len(_LEGAL_BODY)}",
        f"  legal with display type only   {len(_LEGAL_DISPLAY)}"
        + (
            "   (same -- the 3.0-4.5 tier is empty; see THE COUNT)"
            if len(_LEGAL_DISPLAY) == len(_LEGAL_BODY)
            else ""
        ),
        f"  in the rotation walk           {len(_WALK_BODY)}"
        f"   ({len(_LEGAL_BODY) - len(_WALK_BODY)} held back as near-identical)",
        "",
        "  42 was the 2015 number. It is not this system's number.",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    print(explain())
    print()
    print("  first eight of the rotation walk:")
    for i in range(8):
        e, f = rotate(i)
        print(f"    {i}  {e:22s} on {f}")
