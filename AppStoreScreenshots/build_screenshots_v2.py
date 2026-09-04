#!/usr/bin/env python3
"""Build the bolder, slogan-led App Store campaign.

The app UI comes only from real simulator captures. This script adds the
marketing layer: campaign background, exact slogans, brand lockup, hierarchy,
and an offset copper device frame.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "Raw"
OUTPUT = ROOT / "Designed"
BACKGROUND = ROOT / "campaign-background-v2.png"
APP_ICON = ROOT.parent / "Hair Compass AI 5" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-light.png"

CANVAS = (1320, 2868)
SCREEN_WIDTH = 970
SCREEN_Y = 700

INK = "#2B211A"
SECONDARY = "#6F6257"
COPPER = "#B1592E"
IVORY = "#FBF6EF"
SURFACE = "#FEFCF9"
HAIRLINE = "#E6D7C8"

HEADLINE_FONT = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
BODY_FONT = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT = "/System/Library/Fonts/SFNSMono.ttf"


@dataclass(frozen=True)
class Creative:
    source: str
    output: str
    line_one: str
    line_two: str
    subhead: str
    transform: str = "none"


CREATIVES = [
    Creative(
        "01-today.png",
        "01-a-clearer-picture.png",
        "A FEW TAPS.",
        "A CLEARER PICTURE.",
        "Log shedding, scalp, sleep and stress in seconds.",
    ),
    Creative(
        "02-guide.png",
        "02-skip-the-hype.png",
        "SEE THE EVIDENCE.",
        "SKIP THE HYPE.",
        "Compare options by evidence strength, risks and cautions.",
        "rotate",
    ),
    Creative(
        "03-trends.png",
        "03-see-the-pattern.png",
        "STOP GUESSING.",
        "SEE THE PATTERN.",
        "Watch your real trends emerge across weeks and months.",
    ),
    Creative(
        "04-plan.png",
        "04-every-treatment.png",
        "ONE CALM PLAN.",
        "EVERY TREATMENT.",
        "Keep routines, adherence and milestones together.",
        "rotate",
    ),
    Creative(
        "05-photos.png",
        "05-honest-progress.png",
        "SAME ANGLE.",
        "HONEST PROGRESS.",
        "Repeatable photos make change easier to compare.",
    ),
    Creative(
        "06-private.png",
        "06-your-device.png",
        "YOUR DATA.",
        "YOUR DEVICE.",
        "Your entries stay on-device. So does Wren’s thinking.",
        "rotate",
    ),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def fit_font(draw: ImageDraw.ImageDraw, text: str, start: int, max_width: int) -> ImageFont.FreeTypeFont:
    for size in range(start, 58, -2):
        candidate = font(HEADLINE_FONT, size)
        bbox = draw.textbbox((0, 0), text, font=candidate)
        if bbox[2] - bbox[0] <= max_width:
            return candidate
    return font(HEADLINE_FONT, 58)


def background_for(transform: str) -> Image.Image:
    bg = Image.open(BACKGROUND).convert("RGB")
    if transform == "rotate":
        bg = bg.rotate(180)
    return ImageOps.fit(bg, CANVAS, method=Image.Resampling.LANCZOS)


def rounded_asset(path: Path, size: int, radius: int) -> Image.Image:
    source = ImageOps.fit(Image.open(path).convert("RGB"), (size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(source, (0, 0), mask)
    return result


def brand_lockup(canvas: Image.Image, index: int, icon: Image.Image) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    # Compact white brand pill: visible enough to brand the series, quiet enough not
    # to compete with the slogan.
    draw.rounded_rectangle((88, 62, 474, 150), radius=44, fill=(254, 252, 249, 238), outline=HAIRLINE, width=2)
    layer.alpha_composite(icon, (100, 72))
    draw.text((176, 88), "HAIR COMPASS AI", font=font(MONO_FONT, 23), fill=INK)

    # Carousel number lands inside whichever painted corner the background supplies.
    draw.text((1100, 70), f"{index:02d}", font=font(MONO_FONT, 60), fill=(251, 246, 239, 230))
    canvas.alpha_composite(layer)


def marketing_copy(canvas: Image.Image, creative: Creative) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    left = 106

    first_font = fit_font(draw, creative.line_one, 82, 1060)
    draw.text((left, 185), creative.line_one, font=first_font, fill=INK)

    second_font = fit_font(draw, creative.line_two, 82, 1050)
    box = draw.textbbox((0, 0), creative.line_two, font=second_font)
    text_width = box[2] - box[0]
    band_y = 292
    band_height = second_font.size + 38
    draw.rounded_rectangle(
        (left - 14, band_y - 4, left + text_width + 42, band_y + band_height),
        radius=30,
        fill=COPPER,
    )
    draw.text((left + 10, band_y + 8), creative.line_two, font=second_font, fill=IVORY)

    draw.text((left, 438), creative.subhead, font=font(BODY_FONT, 34), fill=SECONDARY)
    canvas.alpha_composite(layer)


def screen_layers(path: Path) -> tuple[Image.Image, Image.Image]:
    source = Image.open(path).convert("RGB")
    height = round(source.height * SCREEN_WIDTH / source.width)
    source = source.resize((SCREEN_WIDTH, height), Image.Resampling.LANCZOS)
    radius = 72

    mask = Image.new("L", source.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, source.width - 1, source.height - 1), radius=radius, fill=255)

    screen = Image.new("RGBA", source.size, (0, 0, 0, 0))
    screen.paste(source, (0, 0), mask)
    ImageDraw.Draw(screen).rounded_rectangle(
        (2, 2, source.width - 3, source.height - 3), radius=radius, outline=SURFACE, width=6
    )

    shadow = Image.new("RGBA", (source.width + 120, source.height + 120), (0, 0, 0, 0))
    shadow_mask = Image.new("L", shadow.size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (60, 44, 60 + source.width, 44 + source.height), radius=radius + 8, fill=115
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(34))
    shadow = Image.new("RGBA", shadow.size, (77, 48, 26, 0))
    shadow.putalpha(shadow_mask)
    return screen, shadow


def offset_frame(height: int) -> Image.Image:
    frame = Image.new("RGBA", (SCREEN_WIDTH, height), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        (0, 0, SCREEN_WIDTH - 1, height - 1), radius=76, fill=COPPER
    )
    return frame


def build(creative: Creative, index: int, icon: Image.Image) -> Path:
    canvas = background_for(creative.transform).convert("RGBA")

    # A translucent upper wash guarantees that the exact slogan stays readable even
    # when the textured field is rotated for alternating panels.
    wash = Image.new("RGBA", CANVAS, (251, 246, 239, 0))
    ImageDraw.Draw(wash).rectangle((0, 0, CANVAS[0], 585), fill=(251, 246, 239, 190))
    wash = wash.filter(ImageFilter.GaussianBlur(18))
    canvas.alpha_composite(wash)

    brand_lockup(canvas, index, icon)
    marketing_copy(canvas, creative)

    screen, shadow = screen_layers(RAW / creative.source)
    screen_x = (CANVAS[0] - SCREEN_WIDTH) // 2
    canvas.alpha_composite(shadow, (screen_x - 60, SCREEN_Y - 44))

    # Offset copper slab creates an unmistakable designed frame, while the real UI
    # remains pixel-for-pixel intact on top of it.
    copper_slab = offset_frame(screen.height)
    canvas.alpha_composite(copper_slab, (screen_x - 24, SCREEN_Y - 22))
    canvas.alpha_composite(screen, (screen_x, SCREEN_Y))

    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / creative.output
    canvas.convert("RGB").save(destination, "PNG", optimize=True)
    return destination


def preview_grid(paths: list[Path]) -> Path:
    thumb_width = 330
    thumb_height = round(CANVAS[1] * thumb_width / CANVAS[0])
    gap = 24
    grid = Image.new("RGB", (thumb_width * 3 + gap * 4, thumb_height * 2 + gap * 3), "#DCCDBE")
    for i, path in enumerate(paths):
        thumb = Image.open(path).convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        grid.paste(thumb, (gap + (i % 3) * (thumb_width + gap), gap + (i // 3) * (thumb_height + gap)))
    destination = OUTPUT / "preview-grid-v2.jpg"
    grid.save(destination, "JPEG", quality=93, optimize=True)
    return destination


def main() -> None:
    icon = rounded_asset(APP_ICON, 68, 16)
    paths = [build(creative, index, icon) for index, creative in enumerate(CREATIVES, start=1)]
    preview = preview_grid(paths)
    for path in [*paths, preview]:
        print(path)


if __name__ == "__main__":
    main()
