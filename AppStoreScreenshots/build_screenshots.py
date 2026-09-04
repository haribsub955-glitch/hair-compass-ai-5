#!/usr/bin/env python3
"""Build the coordinated 6.9-inch App Store screenshot set.

Inputs are untouched simulator captures in ``Raw`` plus one generated, text-free
campaign background. Outputs are opaque 1320 x 2868 PNGs in ``Final``.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "Raw"
FINAL = ROOT / "Final"
BACKGROUND = ROOT / "campaign-background.png"
APP_ICON = ROOT.parent / "Hair Compass AI 5" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-light.png"

CANVAS = (1320, 2868)
SCREEN_WIDTH = 1000
SCREEN_Y = 650

INK = "#2B211A"
SECONDARY = "#6F6257"
COPPER = "#B1592E"
HAIRLINE = "#E6D7C8"

HEADLINE_FONT = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
BODY_FONT = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT = "/System/Library/Fonts/SFNSMono.ttf"


@dataclass(frozen=True)
class Shot:
    source: str
    output: str
    eyebrow: str
    title: str
    subhead: str
    background_transform: str = "none"


SHOTS = [
    Shot(
        "01-today.png",
        "01-daily-compass.png",
        "DAILY COMPASS",
        "Turn daily signals\ninto a clearer story.",
        "Shedding, scalp, sleep, stress and routine — together.",
    ),
    Shot(
        "02-guide.png",
        "02-evidence-guide.png",
        "EVIDENCE-LED GUIDE",
        "See what’s supported\nbefore you spend.",
        "Options ranked by evidence, with cautions up front.",
        "mirror",
    ),
    Shot(
        "03-trends.png",
        "03-longitudinal-trends.png",
        "LONGITUDINAL TRENDS",
        "See your pattern\nwithout guessing.",
        "Follow shedding, adherence and body signals over time.",
        "rotate",
    ),
    Shot(
        "04-plan.png",
        "04-treatment-plan.png",
        "YOUR PLAN",
        "Keep every treatment\non one calm plan.",
        "Routines, adherence and milestones in one place.",
        "mirror",
    ),
    Shot(
        "05-photos.png",
        "05-progress-photos.png",
        "PROGRESS PHOTOS",
        "Make change visible\nwith repeatable photos.",
        "Match region, lighting and angle for honest comparison.",
        "rotate",
    ),
    Shot(
        "06-private.png",
        "06-private-by-design.png",
        "PRIVATE BY DESIGN",
        "Thoughtful support.\nKept on your device.",
        "Your entries stay on-device — and Wren thinks there too.",
        "mirror",
    ),
]


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


def fit_font(draw: ImageDraw.ImageDraw, text: str, path: str, start: int, max_width: int) -> ImageFont.FreeTypeFont:
    size = start
    while size > 72:
        candidate = font(path, size)
        bbox = draw.multiline_textbbox((0, 0), text, font=candidate, spacing=int(size * 0.08))
        if bbox[2] - bbox[0] <= max_width:
            return candidate
        size -= 2
    return font(path, size)


def transformed_background(kind: str) -> Image.Image:
    bg = Image.open(BACKGROUND).convert("RGB")
    if kind == "mirror":
        bg = ImageOps.mirror(bg)
    elif kind == "rotate":
        bg = bg.rotate(180)
    return ImageOps.fit(bg, CANVAS, method=Image.Resampling.LANCZOS)


def rounded_icon() -> Image.Image:
    size = 112
    icon = Image.open(APP_ICON).convert("RGB")
    icon = ImageOps.fit(icon, (size, size), method=Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=25, fill=255)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(icon, (0, 0), mask)
    return result


def framed_screen(source: Path) -> tuple[Image.Image, Image.Image]:
    screenshot = Image.open(source).convert("RGB")
    target_height = round(screenshot.height * SCREEN_WIDTH / screenshot.width)
    screenshot = screenshot.resize((SCREEN_WIDTH, target_height), Image.Resampling.LANCZOS)

    radius = 74
    mask = Image.new("L", screenshot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, screenshot.width - 1, screenshot.height - 1), radius=radius, fill=255
    )

    framed = Image.new("RGBA", screenshot.size, (0, 0, 0, 0))
    framed.paste(screenshot, (0, 0), mask)
    border = Image.new("RGBA", screenshot.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (1, 1, screenshot.width - 2, screenshot.height - 2),
        radius=radius,
        outline=HAIRLINE,
        width=4,
    )
    framed.alpha_composite(border)

    shadow = Image.new("RGBA", (screenshot.width + 100, screenshot.height + 100), (0, 0, 0, 0))
    shadow_mask = Image.new("L", shadow.size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        (50, 40, 50 + screenshot.width, 40 + screenshot.height), radius=radius + 8, fill=125
    )
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(32))
    shadow.putalpha(shadow_mask)
    # Warm espresso shadow, never neutral black.
    warm = Image.new("RGBA", shadow.size, (90, 56, 27, 0))
    warm.putalpha(shadow_mask)
    return framed, warm


def draw_copy(canvas: Image.Image, shot: Shot) -> None:
    draw = ImageDraw.Draw(canvas)
    left = 120

    # Copper compass point + editorial eyebrow.
    draw.ellipse((left, 116, left + 14, 130), fill=COPPER)
    eyebrow_font = font(MONO_FONT, 29)
    draw.text((left + 28, 105), shot.eyebrow, font=eyebrow_font, fill=COPPER)

    headline_font = fit_font(draw, shot.title, HEADLINE_FONT, 102, 1010)
    spacing = int(headline_font.size * 0.06)
    draw.multiline_text((left, 170), shot.title, font=headline_font, fill=INK, spacing=spacing)

    title_bbox = draw.multiline_textbbox((left, 170), shot.title, font=headline_font, spacing=spacing)
    subhead_y = max(470, title_bbox[3] + 26)
    subhead_font = font(BODY_FONT, 33)
    draw.text((left, subhead_y), shot.subhead, font=subhead_font, fill=SECONDARY)


def build_one(shot: Shot, icon: Image.Image) -> Path:
    canvas = transformed_background(shot.background_transform).convert("RGBA")

    # A quiet ivory veil behind the marketing copy keeps every headline equally legible.
    veil = Image.new("RGBA", CANVAS, (251, 246, 239, 0))
    veil_draw = ImageDraw.Draw(veil)
    veil_draw.rectangle((0, 0, CANVAS[0], 590), fill=(251, 246, 239, 202))
    veil = veil.filter(ImageFilter.GaussianBlur(20))
    canvas.alpha_composite(veil)

    draw_copy(canvas, shot)

    # App icon at the campaign-copy edge, with the same warm shadow family as the phone.
    icon_shadow = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    shadow_mask = Image.new("L", icon_shadow.size, 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle((24, 20, 136, 132), radius=28, fill=90)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(15))
    icon_shadow = Image.new("RGBA", icon_shadow.size, (90, 56, 27, 0))
    icon_shadow.putalpha(shadow_mask)
    canvas.alpha_composite(icon_shadow, (1068, 78))
    canvas.alpha_composite(icon, (1092, 98))

    framed, shadow = framed_screen(RAW / shot.source)
    screen_x = (CANVAS[0] - SCREEN_WIDTH) // 2
    canvas.alpha_composite(shadow, (screen_x - 50, SCREEN_Y - 40))
    canvas.alpha_composite(framed, (screen_x, SCREEN_Y))

    FINAL.mkdir(parents=True, exist_ok=True)
    output = FINAL / shot.output
    canvas.convert("RGB").save(output, format="PNG", optimize=True)
    return output


def build_preview(outputs: list[Path]) -> Path:
    thumb_width = 330
    thumb_height = round(CANVAS[1] * thumb_width / CANVAS[0])
    gutter = 24
    preview = Image.new("RGB", (thumb_width * 3 + gutter * 4, thumb_height * 2 + gutter * 3), "#E8DED2")
    for index, path in enumerate(outputs):
        thumb = Image.open(path).convert("RGB").resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        x = gutter + (index % 3) * (thumb_width + gutter)
        y = gutter + (index // 3) * (thumb_height + gutter)
        preview.paste(thumb, (x, y))
    output = FINAL / "preview-grid.jpg"
    preview.save(output, format="JPEG", quality=92, optimize=True)
    return output


def main() -> None:
    missing = [RAW / shot.source for shot in SHOTS if not (RAW / shot.source).exists()]
    if missing:
        raise SystemExit("Missing raw screenshots: " + ", ".join(map(str, missing)))
    if not BACKGROUND.exists():
        raise SystemExit(f"Missing campaign background: {BACKGROUND}")
    if not APP_ICON.exists():
        raise SystemExit(f"Missing app icon: {APP_ICON}")

    icon = rounded_icon()
    outputs = [build_one(shot, icon) for shot in SHOTS]
    preview = build_preview(outputs)
    print("Built:")
    for output in outputs:
        print(output)
    print(preview)


if __name__ == "__main__":
    main()
