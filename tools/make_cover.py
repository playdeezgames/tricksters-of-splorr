#!/usr/bin/env python3
"""Draws the itch.io cover (630 by 500) from the game's own art: assets/cover.png. Needs Pillow.

The sprites are the white-ink Bit Bonanza sheets in assets/bit-bonanza (CC0, VEXED), tinted the way the page
tints them; the lettering is Public Pixel (assets/fonts, CC0, GGBotNet). Nothing is random, so a rerun is identical."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 630, 500
GOLD = (255, 208, 96)
RED = (255, 96, 96)
BLUE = (96, 144, 255)

def sprite(sheet, col, row, scale, rgb):
    """One 10 by 10 cell of a white-ink sheet, tinted and enlarged without smoothing."""
    cell = Image.open(f"assets/bit-bonanza/{sheet}.png").convert("RGBA").crop((col * 10, row * 10, col * 10 + 10, row * 10 + 10))
    tint = Image.new("RGBA", cell.size, rgb + (255,))
    tint.putalpha(cell.getchannel("A"))
    return tint.resize((10 * scale, 10 * scale), Image.NEAREST)

def lettering(s, size, rgb):
    font = ImageFont.truetype("assets/fonts/PublicPixel.ttf", size)
    font.fontmode = "1"  # a pixel font: no anti-aliasing
    img = Image.new("RGBA", (int(font.getlength(s)) + 4, size + 4), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((0, 0), s, font=font, fill=rgb + (255,))
    return img

def shadowed(cover, s, size, rgb, y, shadow=3):
    text = lettering(s, size, rgb)
    dark = lettering(s, size, (0, 0, 0))
    x = (W - text.width) // 2
    cover.alpha_composite(dark, (x + shadow, y + shadow))
    cover.alpha_composite(text, (x, y))

def curtain(cover, x0, width):
    d = ImageDraw.Draw(cover)
    d.rectangle((x0, 0, x0 + width, H), fill=(107, 10, 20, 255))
    for fx in range(0, width, 22):
        d.rectangle((x0 + fx + 4, 0, x0 + fx + 12, H), fill=(148, 20, 31, 255))
        d.rectangle((x0 + fx + 14, 0, x0 + fx + 15, H), fill=(71, 5, 13, 255))

def main():
    os.chdir(os.path.join(os.path.dirname(__file__), ".."))
    cover = Image.new("RGBA", (W, H), (13, 8, 20, 255))
    d = ImageDraw.Draw(cover)

    # the stage: a faint floor glow behind the trickster
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((115, 250, 515, 520), fill=(255, 200, 100, 70))
    cover.alpha_composite(glow.filter(ImageFilter.GaussianBlur(40)))

    # two guards either side of the stage, looking the wrong way
    cover.alpha_composite(sprite("People", 3, 2, 7, RED), (130, 352))
    cover.alpha_composite(sprite("People", 3, 2, 7, BLUE), (440, 352))
    cover.alpha_composite(lettering("?", 24, GOLD), (150, 322))
    cover.alpha_composite(lettering("!", 24, (96, 192, 255)), (460, 322))

    # the trickster in a gold top hat, with the prize hanging over one shoulder
    cover.alpha_composite(sprite("People", 0, 2, 11, (255, 255, 255)), (260, 300))
    cover.alpha_composite(sprite("Clothing", 2, 0, 11, GOLD), (260, 246))
    cover.alpha_composite(sprite("Jewelry", 0, 0, 5, GOLD), (392, 300))

    curtain(cover, 0, 112)
    curtain(cover, W - 112, 112)
    d = ImageDraw.Draw(cover)
    d.rectangle((110, 0, 113, H), fill=GOLD + (255,))
    d.rectangle((W - 114, 0, W - 111, H), fill=GOLD + (255,))
    # valance with scallops
    d.rectangle((0, 0, W, 34), fill=(128, 13, 26, 255))
    for sx in range(0, W, 30):
        d.rectangle((sx + 2, 34, sx + 28, 40), fill=(128, 13, 26, 255))
        d.rectangle((sx + 6, 40, sx + 24, 46), fill=(128, 13, 26, 255))
        d.rectangle((sx + 10, 46, sx + 20, 50), fill=(128, 13, 26, 255))
    d.rectangle((0, 32, W, 34), fill=GOLD + (255,))

    shadowed(cover, "TRICKSTERS", 54, GOLD, 70)
    shadowed(cover, "OF SPLORR!!", 28, (255, 192, 64), 138)

    # footlights and the tagline
    for i in range(20):
        d.rectangle((120 + i * 20, 436, 120 + i * 20 + 11, 440), fill=(255, 217, 102, 255))
    shadowed(cover, "A SMALL SHOW OF SLEIGHT AND NERVE", 16, (240, 230, 200), 452, 2)
    cover.convert("RGB").save("assets/cover.png")
    print("assets/cover.png", cover.size)

main()
