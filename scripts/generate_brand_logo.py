#!/usr/bin/env python3
"""Rasterise the Mithka brand mark into every icon asset the app ships.

The mark is the product's logo, given as a one-glyph SVG:

    <svg viewBox="0 0 1024 1024">
      <path d="M512 0a512 512 0 1 1 0 1024A512 512 0 0 1 512 0z
               m0 307.2a204.8 204.8 0 1 0 0 409.6 204.8 204.8 0 0 0 0-409.6z"
            fill="#F84F70"/>
    </svg>

Two concentric circles: an outer one of radius 512 and an inner one of radius
204.8 — exactly 40% — so the whole mark is a centre, an outer radius and a hole
ratio. Nothing here needs an SVG parser; the geometry is re-stated below and
the rendering is a few lines of arithmetic.

Coverage is analytic rather than supersampled. A pixel's coverage of a circle
edge is `clamp(0.5 + signed distance, 0, 1)`, which is exact for a straight edge
and a very close approximation at these radii, so the mark is antialiased
without the 16x sample cost. That keeps the run to a few seconds of pure
standard-library Python — no Pillow, no Cairo, no network — which is what lets
it live in `scripts/` beside the other generators and be re-run by anyone.

Run from the repository root:

    python3 scripts/generate_brand_logo.py

Every path it writes is checked into git, so a re-run is only needed when the
mark, the icon gradient or the generated sizes change.

`assets/penguin.png` keeps its name: it is still the mascot asset the app loads
for its splash and sign-in logo, and the iOS icon variants that do still draw a
penguin carry their own copies under `ios/Runner/*.icon/Assets/`. Renaming it
would mean touching every one of those for no gain.
"""

from __future__ import annotations

import math
import os
import struct
import zlib

# --- The mark ---------------------------------------------------------------

# The SVG's viewBox, and the two circle radii inside it.
VIEWBOX = 1024.0
OUTER_RADIUS = 512.0
HOLE_RATIO = 204.8 / 512.0

# `fill="#F84F70"` from the SVG.
MARK_ROSE = (0xF8, 0x4F, 0x70)

# The launcher background is the gradient the shipped icon already used, so the
# new mark keeps the icon's identity: a vertical blend across the full canvas.
BACKGROUND_TOP = (0xFF, 0x8F, 0x6E)
BACKGROUND_BOTTOM = (0x7C, 0x76, 0xF7)

# Adaptive-icon monochrome layers are tinted by the launcher, so they carry the
# shape only: a solid white ring the system recolours.
MONOCHROME = (0xFF, 0xFF, 0xFF)

# --- Composition ------------------------------------------------------------
#
# How much of its canvas the ring fills, per target. The in-app logo sits alone
# on a gradient and can be generous; an adaptive icon has to stay inside the
# launcher mask's 72/108dp safe zone, so its ring is deliberately smaller.

IN_APP_GLYPH = 0.86
ICON_GLYPH = 0.62
ADAPTIVE_GLYPH = 0.58

# Legacy launcher icons (API < 26) draw their own rounded square, with the same
# margin the previous icon art had. The silhouette is a squircle rather than a
# plain rounded rectangle: that is what the shipped icons used, and it is what
# keeps the legacy icon looking like the adaptive one on a modern launcher.
LEGACY_CONTENT = 0.906
LEGACY_SQUIRCLE_N = 2.6

# Legacy and adaptive launcher icons are emitted per density.
DENSITIES = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
}
LEGACY_DP = 48
ADAPTIVE_DP = 108

# macOS wants a fixed ladder; Windows' ICO holds the sizes Explorer and the
# taskbar actually ask for.
MACOS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _clamp01(value: float) -> float:
    return 0.0 if value < 0.0 else (1.0 if value > 1.0 else value)


def _lerp(start: int, end: int, t: float) -> float:
    return start + (end - start) * t


def _blend_over(
    fg: tuple[float, float, float],
    fg_alpha: float,
    bg: tuple[float, float, float],
    bg_alpha: float,
) -> tuple[float, float, float, float]:
    """Source-over compositing, returning straight (non-premultiplied) RGBA."""
    out_alpha = fg_alpha + bg_alpha * (1.0 - fg_alpha)
    if out_alpha <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    inverse = bg_alpha * (1.0 - fg_alpha)
    return (
        (fg[0] * fg_alpha + bg[0] * inverse) / out_alpha,
        (fg[1] * fg_alpha + bg[1] * inverse) / out_alpha,
        (fg[2] * fg_alpha + bg[2] * inverse) / out_alpha,
        out_alpha,
    )


def _ring_coverage(distance: float, outer: float, hole: float) -> float:
    """Coverage of an annulus at [distance] from its centre.

    The two edges are independent ramps, so the product is 0 inside the hole, 1
    well inside the band and falls off over one pixel at each boundary.
    """
    outside = _clamp01(0.5 + (outer - distance))
    inside = _clamp01(0.5 + (distance - hole))
    return outside * inside


def _squircle_coverage(dx: float, dy: float, half: float, n: float) -> float:
    """Coverage of a superellipse of half-extent [half] around the canvas centre.

    A superellipse is star-shaped, so every ray from the centre crosses its
    boundary exactly once: at `half / (|cos|**n + |sin|**n) ** (1/n)`. Measuring
    the pixel against that crossing gives the edge profile directly, with no
    closed-form signed distance and no supersampling. The measurement is along
    the ray rather than along the normal, which is exact on the axes and the
    diagonals and off by at most a fraction of a pixel between them.
    """
    distance = math.sqrt(dx * dx + dy * dy)
    if distance <= 0.0:
        return 1.0
    ux = abs(dx) / distance
    uy = abs(dy) / distance
    boundary = half / (ux**n + uy**n) ** (1.0 / n)
    return _clamp01(0.5 + boundary - distance)


def render(
    size: int,
    *,
    glyph: float,
    background: str,
    glyph_colour: tuple[int, int, int] = MARK_ROSE,
    squircle: bool = False,
) -> bytes:
    """Renders one square RGBA raster and returns it PNG-encoded.

    [background] is either 'transparent' or 'gradient'. [glyph] is the ring's
    outer diameter as a fraction of the canvas.
    """
    centre = size / 2.0
    outer = size * glyph / 2.0
    hole = outer * HOLE_RATIO
    gradient = background == 'gradient'
    squircle_half = size * LEGACY_CONTENT / 2.0

    pixels = bytearray(size * size * 4)
    for y in range(size):
        # The gradient runs the full height, top to bottom.
        t = y / (size - 1) if size > 1 else 0.0
        bg_rgb = (
            _lerp(BACKGROUND_TOP[0], BACKGROUND_BOTTOM[0], t),
            _lerp(BACKGROUND_TOP[1], BACKGROUND_BOTTOM[1], t),
            _lerp(BACKGROUND_TOP[2], BACKGROUND_BOTTOM[2], t),
        )
        dy = (y + 0.5) - centre
        dy2 = dy * dy
        row = y * size * 4
        for x in range(size):
            dx = (x + 0.5) - centre
            distance = math.sqrt(dx * dx + dy2)
            # A ring only covers a narrow band; everything else is background.
            coverage = 0.0
            if distance <= outer + 1.0 and distance >= hole - 1.0:
                coverage = _ring_coverage(distance, outer, hole)

            if gradient:
                bg_alpha = (
                    _squircle_coverage(dx, dy, squircle_half, LEGACY_SQUIRCLE_N)
                    if squircle
                    else 1.0
                )
                if coverage <= 0.0:
                    rgba = (bg_rgb[0], bg_rgb[1], bg_rgb[2], bg_alpha)
                else:
                    # Scaling the glyph by the mask keeps the ring inside the
                    # legacy squircle instead of relying on it never reaching
                    # the corner.
                    rgba = _blend_over(
                        glyph_colour, coverage * bg_alpha, bg_rgb, bg_alpha
                    )
            elif coverage > 0.0:
                rgba = (
                    float(glyph_colour[0]),
                    float(glyph_colour[1]),
                    float(glyph_colour[2]),
                    coverage,
                )
            else:
                rgba = (0.0, 0.0, 0.0, 0.0)

            i = row + x * 4
            pixels[i] = int(rgba[0] + 0.5)
            pixels[i + 1] = int(rgba[1] + 0.5)
            pixels[i + 2] = int(rgba[2] + 0.5)
            pixels[i + 3] = int(rgba[3] * 255.0 + 0.5)

    return encode_png(size, size, pixels)


# --- PNG / ICO encoding -----------------------------------------------------


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    """Encodes a straight-alpha RGBA buffer as an 8-bit truecolour+alpha PNG."""

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack('>I', len(payload))
            + kind
            + payload
            + struct.pack('>I', zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None — these rasters are far cheaper to store
        raw += rgba[y * stride:(y + 1) * stride]

    return (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
        + chunk(b'IEND', b'')
    )


def encode_ico(frames: list[tuple[int, bytes]]) -> bytes:
    """Encodes 256-colour-agnostic ICO whose entries hold PNG payloads.

    Vista and later read PNG-compressed entries, which is the only way to get a
    256x256 frame without hand-writing a BMP with an AND mask.
    """
    header = struct.pack('<HHH', 0, 1, len(frames))
    entries = bytearray()
    payload = bytearray()
    offset = 6 + 16 * len(frames)
    for size, data in frames:
        entries += struct.pack(
            '<BBBBHHII',
            size % 256,
            size % 256,
            0,
            0,
            1,
            32,
            len(data),
            offset + len(payload),
        )
        payload += data
    return bytes(header + entries + payload)


# --- Writing the shipped assets ---------------------------------------------


def _write(path: str, data: bytes) -> None:
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'wb') as handle:
        handle.write(data)
    print(f'  {path}  ({len(data) / 1024:.1f} KB)')


def main() -> int:
    print('In-app logo')

    # The square splash art and the sign-in logo: the bare ring, transparent so
    # it sits on whatever gradient the user's theme picks. iOS' default icon
    # composes the same file over its own gradient fill, so it ships identical
    # bytes and the two can never drift apart.
    logo = render(1024, glyph=IN_APP_GLYPH, background='transparent')
    _write('assets/penguin.png', logo)
    _write('ios/Runner/Pengram.icon/Assets/penguin.png', logo)

    print('App icon')

    icon = render(1024, glyph=ICON_GLYPH, background='gradient')
    _write('assets/app_icon.png', icon)
    # `assets/app_icons/default.png` is what the in-app icon picker previews for
    # the default variant, so it has to be the default icon's own art.
    _write('assets/app_icons/default.png', icon)

    print('macOS')
    for size in MACOS_SIZES:
        _write(
            f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png',
            render(size, glyph=ICON_GLYPH, background='gradient'),
        )

    print('Windows')
    _write(
        'windows/runner/resources/app_icon.ico',
        encode_ico(
            [
                (size, render(size, glyph=ICON_GLYPH, background='gradient'))
                for size in ICO_SIZES
            ]
        ),
    )

    print('Android launcher')
    for density, factor in DENSITIES.items():
        legacy = render(
            int(LEGACY_DP * factor),
            glyph=ICON_GLYPH,
            background='gradient',
            squircle=True,
        )
        _write(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', legacy)

        adaptive = int(ADAPTIVE_DP * factor)
        _write(
            f'android/app/src/main/res/mipmap-{density}/ic_launcher_background.png',
            render(adaptive, glyph=ADAPTIVE_GLYPH, background='gradient'),
        )
        _write(
            f'android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png',
            render(adaptive, glyph=ADAPTIVE_GLYPH, background='transparent'),
        )
        _write(
            f'android/app/src/main/res/mipmap-{density}/ic_launcher_monochrome.png',
            render(
                adaptive,
                glyph=ADAPTIVE_GLYPH,
                background='transparent',
                glyph_colour=MONOCHROME,
            ),
        )

    print('\nDone.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
