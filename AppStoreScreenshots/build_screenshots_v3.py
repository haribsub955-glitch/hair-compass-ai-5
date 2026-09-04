from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "Raw"
OUT = ROOT / "Campaign10Mixed"
OUT.mkdir(exist_ok=True)

W, H = 1320, 2868

IVORY = (247, 240, 229)
CREAM = (238, 222, 205)
COPPER = (176, 79, 39)
TERRACOTTA = (135, 56, 32)
SAGE = (89, 101, 75)
NAVY = (23, 37, 55)
INK = (46, 34, 28)
WHITE = (255, 252, 246)

SERIF = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)


def cover(image, size, anchor=(0.5, 0.5)):
    image = image.convert("RGB")
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = round((resized.width - target_w) * anchor[0])
    top = round((resized.height - target_h) * anchor[1])
    return resized.crop((left, top, left + target_w, top + target_h))


def source_to_box(canvas, image, source, box, anchor=(0.5, 0.5), mask=None):
    cropped = image.crop(source)
    x0, y0, x1, y1 = box
    fitted = cover(cropped, (x1 - x0, y1 - y0), anchor)
    canvas.paste(fitted, (x0, y0), mask)


def add_gradient(canvas, box, color, alpha_top, alpha_bottom):
    x0, y0, x1, y1 = box
    overlay = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    height = max(1, y1 - y0 - 1)
    for y in range(y1 - y0):
        a = round(alpha_top + (alpha_bottom - alpha_top) * y / height)
        d.line((0, y, x1 - x0, y), fill=(*color, a))
    canvas.alpha_composite(overlay, (x0, y0))


def spaced_text(draw, xy, text, fnt, fill, spacing=3):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + spacing


def brand(draw, x, y, dark=False, number=None):
    fill = INK if dark else WHITE
    spaced_text(draw, (x, y), "HAIR COMPASS AI", font(MONO, 25), fill, 4)
    draw.line((x, y + 50, x + 195, y + 50), fill=fill, width=3)
    if number:
        draw.text((W - 88, y - 2), number, font=font(MONO, 26), fill=fill, anchor="ra")


def tag(draw, x, y, text, fill, text_fill, width=None):
    f = font(SANS, 27)
    if width is None:
        width = round(draw.textlength(text, font=f) + 54)
    draw.rounded_rectangle((x, y, x + width, y + 62), radius=31, fill=fill)
    spaced_text(draw, (x + 27, y + 14), text.upper(), f, text_fill, 2)


def multiline(draw, xy, lines, size, fill, gap=0, anchor="la", font_path=SERIF):
    f = font(font_path, size)
    x, y = xy
    line_h = size + gap
    for i, line in enumerate(lines):
        draw.text((x, y + i * line_h), line, font=f, fill=fill, anchor=anchor)
    return y + len(lines) * line_h


def polish(image, contrast=1.02, color=1.02):
    image = ImageEnhance.Contrast(image).enhance(contrast)
    return ImageEnhance.Color(image).enhance(color)


def slide_ai():
    person = Image.open(ROOT / "editorial-man-copper.png")
    wren = Image.open(ROOT.parent / "Hair Compass AI 5" / "Assets.xcassets" / "wren-listening.imageset" / "wren-listening.png").convert("RGBA")
    base = cover(person, (W, H), anchor=(0.32, 0.5)).convert("RGBA")
    add_gradient(base, (0, 0, W, 1030), INK, 105, 0)
    draw = ImageDraw.Draw(base)
    brand(draw, 72, 72, number="01")
    tag(draw, 72, 177, "WREN • PRIVATE ON-DEVICE AI", WHITE, TERRACOTTA, width=536)
    multiline(draw, (72, 305), ["YOUR HAIR DATA.", "NOW IT TALKS."], 101, WHITE, gap=3)
    draw.text((75, 575), "Ask Wren what your own pattern could mean.", font=font(SANS, 35), fill=WHITE)

    shadow = Image.new("RGBA", (650, 1320), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((28, 28, 625, 1295), radius=62, fill=(20, 14, 10, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    base.alpha_composite(shadow, (34, 1320))
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((58, 1340, 660, 2655), radius=60, fill=IVORY, outline=CREAM, width=4)
    draw.text((112, 1410), "Wren AI", font=font(SERIF, 54), fill=INK)
    draw.text((112, 1480), "Ask about your hair data", font=font(SANS, 29), fill=(111, 96, 85))
    wren.thumbnail((280, 245), Image.Resampling.LANCZOS)
    base.alpha_composite(wren, (112, 1575))
    draw = ImageDraw.Draw(base)
    draw.text((112, 1832), "A private guide to your\nown pattern—not a diagnosis.", font=font(SANS, 29), fill=INK, spacing=10)
    questions = [
        "What could explain this relationship?",
        "Is this change meaningful?",
        "How do time lags work for hair?",
    ]
    for i, question in enumerate(questions):
        y = 2055 + i * 150
        draw.rounded_rectangle((92, y, 625, y + 112), radius=44, fill=(238, 220, 205))
        draw.text((120, y + 27), question, font=font(SANS, 24), fill=TERRACOTTA)
    return base.convert("RGB")


def slide_today():
    base = Image.new("RGBA", (W, H), IVORY + (255,))
    draw = ImageDraw.Draw(base)
    draw.polygon([(0, 0), (500, 0), (500, H), (0, H)], fill=TERRACOTTA)
    draw.ellipse((1040, -170, 1470, 260), fill=(222, 199, 173))
    draw.arc((820, 2200, 1450, 2830), 120, 300, fill=SAGE, width=55)
    draw = ImageDraw.Draw(base)
    brand(draw, 64, 72)
    draw.text((W - 72, 72), "03", font=font(MONO, 26), fill=INK, anchor="ra")
    tag(draw, 63, 182, "DAILY CHECK-IN", CREAM, TERRACOTTA, width=316)
    multiline(draw, (63, 350), ["20", "SECONDS", "TODAY."], 90, WHITE, gap=4)
    draw.line((63, 825, 332, 825), fill=CREAM, width=5)
    multiline(draw, (63, 820), ["CLARITY", "TOMORROW."], 55, CREAM, gap=4)
    draw.text((64, 1035), "Shedding. Scalp.\nSleep. Stress. Routine.", font=font(SANS, 29), fill=WHITE, spacing=13)
    spaced_text(draw, (62, H - 130), "A FEW TAPS. A STRONGER RECORD.", font(MONO, 21), WHITE, 2)

    draw.text((575, 210), "TODAY'S SHEDDING", font=font(MONO, 24), fill=TERRACOTTA)
    draw.text((575, 270), "Minimal", font=font(SERIF, 91), fill=INK)
    draw.text((575, 390), "A light moment in the pattern.", font=font(SANS, 30), fill=(112, 96, 84))
    draw.rounded_rectangle((575, 510, 1190, 840), radius=40, fill=WHITE, outline=CREAM, width=4)
    draw.ellipse((625, 580, 800, 755), outline=COPPER, width=17)
    draw.text((712, 660), "80", font=font(SERIF, 54), fill=INK, anchor="mm")
    draw.text((850, 590), "COMPASS SCORE", font=font(MONO, 22), fill=TERRACOTTA)
    draw.text((850, 650), "Photo still open today.", font=font(SANS, 27), fill=INK)
    rows = [("SCALP", "Mild"), ("SLEEP", "7.2h"), ("STRESS", "Moderate"), ("ROUTINE", "Done")]
    for i, (label, value) in enumerate(rows):
        y = 930 + i * 230
        draw.rounded_rectangle((575, y, 1190, y + 180), radius=35, fill=WHITE, outline=CREAM, width=3)
        spaced_text(draw, (620, y + 35), label, font(MONO, 21), TERRACOTTA, 2)
        draw.text((620, y + 83), value, font=font(SERIF, 41), fill=INK)
        draw.ellipse((1105, y + 67, 1135, y + 97), fill=SAGE if i in (1, 3) else COPPER)
    draw.text((575, 1985), "TODAY'S ROUTINE", font=font(MONO, 22), fill=TERRACOTTA)
    draw.rounded_rectangle((575, 2050, 1190, 2290), radius=36, fill=(237, 226, 211))
    draw.text((620, 2105), "Minoxidil 5%", font=font(SANS, 31), fill=INK)
    draw.text((620, 2163), "08:00", font=font(MONO, 23), fill=(115, 99, 86))
    draw.ellipse((1085, 2115, 1145, 2175), fill=COPPER)
    draw.line((1101, 2146, 1117, 2160), fill=WHITE, width=6)
    draw.line((1117, 2160, 1133, 2132), fill=WHITE, width=6)
    return base.convert("RGB")


def slide_trends():
    person = Image.open(ROOT / "editorial-man-sage.png")
    base = cover(person, (W, H), anchor=(0.5, 0.45)).convert("RGBA")
    add_gradient(base, (0, 0, W, 900), SAGE, 230, 55)
    add_gradient(base, (0, 2500, W, H), INK, 0, 95)
    draw = ImageDraw.Draw(base)
    brand(draw, 72, 72, number="05")
    tag(draw, 72, 182, "LONGITUDINAL TRENDS", IVORY, SAGE, width=406)
    multiline(draw, (72, 330), ["STOP GUESSING.", "WATCH THE PATTERN."], 92, WHITE, gap=4)
    draw.text((75, 583), "See what changes across weeks—not just one mirror check.", font=font(SANS, 32), fill=WHITE)
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((58, 1790, 1262, 2660), radius=54, fill=IVORY, outline=CREAM, width=4)
    draw.text((105, 1850), "YOUR CURRENT READ", font=font(MONO, 23), fill=TERRACOTTA)
    draw.text((105, 1910), "Too early to judge", font=font(SERIF, 53), fill=INK)
    draw.text((105, 1980), "Week 20 of 24", font=font(SANS, 29), fill=(110, 95, 82))
    draw.rounded_rectangle((928, 1855, 1185, 1925), radius=35, fill=(235, 222, 205))
    draw.text((1055, 1890), "3 MONTHS", font=font(MONO, 20), fill=TERRACOTTA, anchor="mm")
    chart_left, chart_top, chart_right, chart_bottom = 130, 2135, 1180, 2490
    for i, label in enumerate(["HEAVY", "ELEVATED", "NORMAL", "MINIMAL"]):
        y = chart_top + i * ((chart_bottom - chart_top) // 3)
        draw.line((chart_left + 145, y, chart_right, y), fill=(215, 203, 187), width=2)
        draw.text((chart_left, y - 12), label, font=font(MONO, 17), fill=(125, 109, 94))
    points = [(275, 2190), (390, 2235), (530, 2235), (650, 2310), (820, 2310), (915, 2390), (1070, 2425), (1180, 2470)]
    draw.line(points, fill=COPPER, width=12, joint="curve")
    for x, y in points:
        draw.ellipse((x - 7, y - 7, x + 7, y + 7), fill=COPPER)
    draw.text((105, 2550), "WEEK BY WEEK • YOUR REAL DATA", font=font(MONO, 20), fill=SAGE)
    return base.convert("RGB")


def slide_guide():
    base = Image.new("RGBA", (W, H), IVORY + (255,))
    draw = ImageDraw.Draw(base)
    draw.polygon([(0, 0), (W, 0), (W, 900), (0, 1120)], fill=COPPER)
    brand(draw, 72, 72, number="06")
    tag(draw, 72, 182, "EVIDENCE GUIDE", IVORY, TERRACOTTA, width=334)
    multiline(draw, (72, 350), ["SEE THE EVIDENCE.", "SKIP THE HYPE."], 87, WHITE, gap=6)
    draw.text((75, 608), "Compare options by evidence, risks and real-world cautions.", font=font(SANS, 31), fill=WHITE)
    draw.text((72, 1120), "READ THE SIGNAL, NOT THE SALES PITCH.", font=font(MONO, 23), fill=TERRACOTTA)
    cards = [
        ("01", "STRONG EVIDENCE", "Best-supported options, with what the studies actually show.", SAGE),
        ("02", "MIXED EVIDENCE", "Promising in some settings. Context and baseline still matter.", COPPER),
        ("03", "CAUTIONS", "Risks, trade-offs and clinician questions—in plain language.", INK),
    ]
    for i, (num, title, body, accent) in enumerate(cards):
        y = 1230 + i * 430
        draw.rounded_rectangle((72, y, 1248, y + 350), radius=45, fill=WHITE, outline=CREAM, width=4)
        draw.rounded_rectangle((105, y + 42, 230, y + 167), radius=30, fill=accent)
        draw.text((167, y + 104), num, font=font(MONO, 27), fill=WHITE, anchor="mm")
        draw.text((275, y + 48), title, font=font(SERIF, 43), fill=INK)
        draw.text((275, y + 126), body, font=font(SANS, 28), fill=(102, 87, 75), spacing=9)
        draw.line((275, y + 260, 1130, y + 260), fill=accent, width=5)
    spaced_text(draw, (72, H - 120), "LEARN • COMPARE • DECIDE", font(MONO, 21), INK, 2)
    return base.convert("RGB")


def slide_plan():
    base = Image.new("RGBA", (W, H), INK + (255,))
    draw = ImageDraw.Draw(base)
    draw.polygon([(0, 0), (520, 0), (420, H), (0, H)], fill=INK)
    draw.polygon([(500, 0), (560, 0), (460, H), (400, H)], fill=TERRACOTTA)
    brand(draw, 64, 72)
    draw.text((W - 72, 72), "07", font=font(MONO, 26), fill=INK, anchor="ra")
    tag(draw, 64, 184, "YOUR ROUTINE", CREAM, TERRACOTTA, width=300)
    multiline(draw, (63, 350), ["ONE", "ROUTINE."], 86, WHITE, gap=1)
    multiline(draw, (63, 620), ["NOTHING", "FORGOTTEN."], 58, CREAM, gap=3)
    draw.line((63, 865, 345, 865), fill=COPPER, width=6)
    draw.text((64, 925), "Keep treatments,\nadherence and\nmilestones together.", font=font(SANS, 32), fill=WHITE, spacing=13)
    tag(draw, 62, H - 205, "CALM • CONSISTENT • YOURS", COPPER, WHITE, width=420)

    draw.rounded_rectangle((545, 190, 1245, 2650), radius=58, fill=IVORY, outline=CREAM, width=5)
    draw.text((610, 270), "TODAY'S PLAN", font=font(MONO, 24), fill=TERRACOTTA)
    draw.text((610, 340), "Your routine", font=font(SERIF, 60), fill=INK)
    sections = [
        ("MORNING", [("08:00", "Minoxidil 5%", True)]),
        ("EVENING", [("21:00", "Minoxidil 5%", True), ("21:10", "Finasteride 1mg", True)]),
        ("PERIODIC", [("TODAY", "PRP session", False)]),
    ]
    y = 500
    for section, tasks in sections:
        spaced_text(draw, (610, y), section, font(MONO, 21), TERRACOTTA, 2)
        y += 58
        for time_value, task, complete in tasks:
            draw.rounded_rectangle((600, y, 1188, y + 170), radius=32, fill=WHITE, outline=CREAM, width=3)
            draw.text((630, y + 40), time_value, font=font(MONO, 22), fill=(117, 101, 88))
            draw.text((780, y + 35), task, font=font(SANS, 30), fill=INK)
            draw.ellipse((1085, y + 54, 1145, y + 114), fill=COPPER if complete else IVORY, outline=COPPER, width=4)
            if complete:
                draw.line((1101, y + 84, 1117, y + 98), fill=WHITE, width=6)
                draw.line((1117, y + 98, 1133, y + 70), fill=WHITE, width=6)
            y += 205
        y += 65
    draw.rounded_rectangle((600, 2015, 1188, 2330), radius=38, fill=(236, 222, 207))
    draw.text((635, 2060), "PROGRESS REPORT", font=font(MONO, 21), fill=TERRACOTTA)
    draw.text((635, 2125), "Week 20", font=font(SERIF, 42), fill=INK)
    draw.text((635, 2190), "Next report at week 24", font=font(SANS, 27), fill=(111, 95, 82))
    draw.line((635, 2275, 1115, 2275), fill=COPPER, width=7)
    return base.convert("RGB")


def slide_progress():
    person = Image.open(ROOT / "editorial-man-copper.png")
    photos = Image.open(RAW / "05-photos.png")
    base = cover(person, (W, H), anchor=(0.3, 0.5)).convert("RGBA")
    add_gradient(base, (0, 0, W, 1160), INK, 92, 10)
    draw = ImageDraw.Draw(base)
    brand(draw, 72, 72, number="09")
    tag(draw, 72, 182, "PROGRESS PHOTOS", IVORY, TERRACOTTA, width=380)
    multiline(draw, (72, 330), ["SAME ANGLE.", "HONEST PROGRESS."], 94, WHITE, gap=4)
    draw.text((75, 590), "Repeatable photos make subtle change easier to see.", font=font(SANS, 32), fill=WHITE)

    scalp = photos.crop((70, 620, 1250, 2080)).convert("RGB")
    scalp.thumbnail((500, 760), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", (610, 1290), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((35, 35, 575, 1250), radius=55, fill=(20, 14, 10, 100))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    base.alpha_composite(shadow, (24, 1180))
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((58, 1200, 610, 2465), radius=55, fill=IVORY, outline=CREAM, width=4)
    draw.text((100, 1260), "REPEATABLE ANGLE", font=font(MONO, 20), fill=TERRACOTTA)
    photo_x = 58 + (552 - scalp.width) // 2
    base.paste(scalp, (photo_x, 1345))
    draw = ImageDraw.Draw(base)
    photo_bottom = 1345 + scalp.height
    draw.text((100, photo_bottom + 45), "Baseline", font=font(SERIF, 42), fill=INK)
    draw.text((100, photo_bottom + 105), "FRAME 1 OF 4", font=font(MONO, 21), fill=(114, 98, 85))
    for i in range(4):
        x = 110 + i * 105
        draw.ellipse((x, photo_bottom + 185, x + 28, photo_bottom + 213), fill=COPPER if i == 0 else CREAM, outline=COPPER, width=3)
    draw.text((100, photo_bottom + 260), "Same position • Same light", font=font(SANS, 25), fill=(104, 89, 76))
    tag(draw, 810, H - 240, "TRACK WHAT'S REAL", IVORY, TERRACOTTA, width=386)
    return base.convert("RGB")


def slide_bad_day():
    paper = Image.open(ROOT / "campaign-background-v2.png")
    base = cover(paper, (W, H), anchor=(0.5, 0.5)).convert("RGBA")
    draw = ImageDraw.Draw(base)
    draw.polygon([(0, 1030), (W, 820), (W, 1610), (0, 1820)], fill=TERRACOTTA)
    draw.ellipse((825, 1840, 1550, 2565), fill=SAGE + (220,))
    brand(draw, 72, 72, dark=True, number="02")
    tag(draw, 72, 182, "THE LONG VIEW", COPPER, WHITE, width=320)
    multiline(draw, (72, 370), ["ONE BAD", "HAIR DAY"], 125, INK, gap=3)
    multiline(draw, (72, 1080), ["ISN'T THE", "WHOLE STORY."], 112, WHITE, gap=5)
    draw.text((76, 1900), "Patterns need time. Hair Compass keeps the record.", font=font(SANS, 34), fill=INK)
    draw.line((76, 1990, 620, 1990), fill=COPPER, width=7)
    for i, label in enumerate(["DAYS", "WEEKS", "MONTHS"]):
        x = 76 + i * 260
        draw.rounded_rectangle((x, 2080, x + 220, 2160), radius=40, outline=INK, width=3)
        spaced_text(draw, (x + 47, 2105), label, font(MONO, 21), INK, 2)
        if i < 2:
            draw.line((x + 224, 2120, x + 250, 2120), fill=INK, width=3)
            draw.polygon([(x + 250, 2120), (x + 238, 2112), (x + 238, 2128)], fill=INK)
    spaced_text(draw, (72, H - 150), "DON'T JUDGE A MONTH BY A MORNING", font(MONO, 22), INK, 2)
    return base.convert("RGB")


def slide_small_things():
    person = Image.open(ROOT / "editorial-person-copper.png")
    base = cover(person, (W, H), anchor=(0.5, 0.5)).convert("RGBA")
    add_gradient(base, (0, 0, W, 1200), NAVY, 100, 0)
    draw = ImageDraw.Draw(base)
    brand(draw, 72, 72, number="04")
    tag(draw, 72, 182, "CONSISTENCY", IVORY, NAVY, width=290)
    multiline(draw, (72, 340), ["TRACK THE", "SMALL THINGS."], 99, WHITE, gap=4)
    draw.text((75, 606), "THEY ADD UP.", font=font(SERIF, 83), fill=(221, 123, 72))
    draw.text((76, 745), "Build a record you can actually use.", font=font(SANS, 34), fill=WHITE)
    for i, label in enumerate(["SHEDDING", "SCALP", "SLEEP", "STRESS"]):
        x = 72 + (i % 2) * 290
        y = 910 + (i // 2) * 106
        draw.rounded_rectangle((x, y, x + 256, y + 72), radius=36, outline=WHITE, width=3)
        spaced_text(draw, (x + 25, y + 22), label, font(MONO, 19), WHITE, 2)
    return base.convert("RGB")


def slide_long_view():
    person = Image.open(ROOT / "editorial-person-sage.png")
    base = cover(person, (W, H), anchor=(0.5, 0.5)).convert("RGBA")
    add_gradient(base, (0, 0, W, 1450), INK, 125, 0)
    draw = ImageDraw.Draw(base)
    brand(draw, 72, 72, number="08")
    tag(draw, 830, 180, "BUILT FOR MONTHS", IVORY, TERRACOTTA, width=390)
    multiline(draw, (1245, 355), ["HAIR CHANGES", "SLOWLY."], 90, WHITE, gap=4, anchor="ra")
    draw.line((760, 625, 1243, 625), fill=COPPER, width=8)
    multiline(draw, (1245, 680), ["YOUR RECORD", "SHOULDN'T."], 76, CREAM, gap=4, anchor="ra")
    draw.text((1245, 925), "Stay consistent across months—not moments.", font=font(SANS, 31), fill=WHITE, anchor="ra")
    tag(draw, 810, H - 215, "THE LONG VIEW WINS", IVORY, TERRACOTTA, width=410)
    return base.convert("RGB")


def slide_private():
    base = Image.new("RGBA", (W, H), NAVY + (255,))
    draw = ImageDraw.Draw(base)
    draw.ellipse((-470, 1020, 890, 2380), outline=COPPER, width=120)
    draw.ellipse((-270, 1210, 690, 2170), outline=CREAM, width=4)
    draw.arc((670, -380, 1570, 520), 18, 245, fill=SAGE, width=185)
    draw.polygon([(1010, 1660), (1320, 1500), (1320, 2868), (620, 2868)], fill=TERRACOTTA)
    brand(draw, 72, 72, number="10")
    tag(draw, 72, 182, "PRIVATE BY DESIGN", IVORY, NAVY, width=390)
    multiline(draw, (72, 355), ["YOUR DATA.", "YOUR DEVICE.", "YOUR NEXT MOVE."], 92, WHITE, gap=7)
    draw.text((76, 770), "Your entries stay on-device. So does Wren's thinking.", font=font(SANS, 33), fill=CREAM)
    draw.line((75, 858, 612, 858), fill=COPPER, width=7)

    lock_x, lock_y = 760, 1190
    draw.arc((lock_x + 90, lock_y, lock_x + 370, lock_y + 350), 180, 360, fill=WHITE, width=28)
    draw.rounded_rectangle((lock_x, lock_y + 160, lock_x + 460, lock_y + 640), radius=55, outline=WHITE, width=28)
    draw.ellipse((lock_x + 205, lock_y + 330, lock_x + 255, lock_y + 380), fill=WHITE)
    draw.rectangle((lock_x + 225, lock_y + 370, lock_x + 235, lock_y + 460), fill=WHITE)
    spaced_text(draw, (72, H - 170), "HAIR COMPASS AI • BUILT FOR THE LONG VIEW", font(MONO, 22), WHITE, 2)
    return base.convert("RGB")


def preview(files):
    thumb_w = 240
    thumb_h = round(H * thumb_w / W)
    gap = 24
    margin = 32
    columns = 5
    board = Image.new("RGB", (margin * 2 + thumb_w * columns + gap * (columns - 1), margin * 2 + thumb_h * 2 + gap), (219, 207, 193))
    for i, path in enumerate(files):
        im = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = margin + (i % columns) * (thumb_w + gap)
        y = margin + (i // columns) * (thumb_h + gap)
        board.paste(im, (x, y))
    board.save(OUT / "preview-grid-mixed.jpg", quality=92)


def main():
    slides = [
        ("01-wren-ai.png", slide_ai()),
        ("02-not-the-whole-story.png", slide_bad_day()),
        ("03-daily-clarity.png", slide_today()),
        ("04-small-things-add-up.png", slide_small_things()),
        ("05-watch-the-pattern.png", slide_trends()),
        ("06-skip-the-hype.png", slide_guide()),
        ("07-nothing-forgotten.png", slide_plan()),
        ("08-built-for-months.png", slide_long_view()),
        ("09-honest-progress.png", slide_progress()),
        ("10-private-by-design.png", slide_private()),
    ]
    paths = []
    for name, image in slides:
        path = OUT / name
        image.save(path, optimize=True)
        paths.append(path)
    preview(paths)


if __name__ == "__main__":
    main()
