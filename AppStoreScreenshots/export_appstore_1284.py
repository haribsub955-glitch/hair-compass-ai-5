from pathlib import Path
from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "Campaign10Mixed"
OUTPUT = ROOT / "AppStoreReady-1284x2778"
OUTPUT.mkdir(exist_ok=True)

FILES = [
    "01-wren-ai.png",
    "02-not-the-whole-story.png",
    "03-daily-clarity.png",
    "04-small-things-add-up.png",
    "05-watch-the-pattern.png",
    "06-skip-the-hype.png",
    "07-nothing-forgotten.png",
    "08-built-for-months.png",
    "09-honest-progress.png",
    "10-private-by-design.png",
]

TARGET = (1284, 2778)


def main():
    exported = []
    for name in FILES:
        source = Image.open(SOURCE / name).convert("RGB")
        final = ImageOps.fit(
            source,
            TARGET,
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )
        destination = OUTPUT / name
        final.save(destination, optimize=True)
        exported.append(destination)

    thumb_w = 240
    thumb_h = round(TARGET[1] * thumb_w / TARGET[0])
    gap = 24
    margin = 32
    columns = 5
    preview = Image.new(
        "RGB",
        (
            margin * 2 + thumb_w * columns + gap * (columns - 1),
            margin * 2 + thumb_h * 2 + gap,
        ),
        (219, 207, 193),
    )
    for index, path in enumerate(exported):
        image = Image.open(path).resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = margin + (index % columns) * (thumb_w + gap)
        y = margin + (index // columns) * (thumb_h + gap)
        preview.paste(image, (x, y))
    preview.save(OUTPUT / "preview-grid-1284.jpg", quality=92)


if __name__ == "__main__":
    main()
