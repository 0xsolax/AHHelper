"""Render the shipped panel using its actual Lua layout and an offline frame mock."""

from pathlib import Path
import argparse
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from run_wanted_poster_tests import ROOT, runtime

ART = ROOT / "WantedPoster" / "Parchment.tga"
FONT_DIR = Path("C:/Windows/Fonts")
DISPLAY_SCALE = 1.5
LAYERS = {"BACKGROUND": 0, "ARTWORK": 1, "OVERLAY": 2}


def edge_mask(width, height, rng):
    def fray(length):
        offset = 18
        phase = rng.uniform(0, math.tau)
        while offset < length - 18:
            wave = 3.0 * math.sin(offset / 93 + phase) + 2.1 * math.sin(offset / 26)
            dent = rng.randint(4, 11) if rng.random() < 0.09 else 0
            yield offset, max(2, round(9 + wave + dent + rng.uniform(-2.4, 2.4)))
            offset += rng.randint(5, 18)

    top = [(x, edge) for x, edge in fray(width)]
    right = [(width - edge, y) for y, edge in fray(height)]
    bottom = [(x, height - edge) for x, edge in fray(width)]
    left = [(edge, y) for y, edge in fray(height)]
    outline = top + right + bottom[::-1] + left[::-1]
    mask = Image.new("L", (width, height))
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    return mask


def paper_stock(width, height, rng, mask):
    cloud = Image.new("L", (15, 19))
    cloud.putdata([rng.randrange(256) for _ in range(15 * 19)])
    cloud = cloud.resize((width, height), Image.Resampling.BICUBIC)
    noise = cloud.load()
    paper = Image.new("RGB", (width, height))
    pixels = []
    for y in range(height):
        vertical = abs(2 * y / height - 1)
        for x in range(width):
            edge = max(abs(2 * x / width - 1), vertical)
            stain = 0.132 * (noise[x, y] - 128) - 28 * edge**5 + rng.gauss(0, 2.0)
            pixels.append(tuple(min(255, max(0, round(value + stain))) for value in (239, 204, 151)))
    paper.putdata(pixels)
    for radius, tone, opacity in [(25, "#ab7644", 90), (11, "#985d34", 98), (5, "#5f381f", 145)]:
        band = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(radius)))
        paper.paste(tone, mask=band.point(lambda alpha: alpha * opacity // 255))
    surface = paper.convert("RGBA")
    surface.putalpha(mask)
    return surface


def make_art():
    width, height = 696, 798
    rng = random.Random(6534)
    mask = edge_mask(width, height, rng)
    art = paper_stock(width, height, rng, mask)
    art.resize((512, 512), Image.Resampling.LANCZOS).save(ART)


def color(values):
    return tuple(round(values[index] * 255) for index in range(1, len(values) + 1))


def region_visible(region):
    if not region.shown:
        return False
    if region.state == "normal":
        return region.parent.enabled
    if region.state == "disabled":
        return not region.parent.enabled
    return region.state not in ("pushed", "highlight")


def draw_native_button(image, at, size, enabled):
    """Represent the game template's bevel and state in the offline preview."""
    x, y = at
    right, bottom = x + size[0] - 1, y + size[1] - 1
    draw = ImageDraw.Draw(image)
    draw.polygon([(x + 4, y), (right - 4, y), (right, y + 4), (right, bottom - 4),
                  (right - 4, bottom), (x + 4, bottom), (x, bottom - 4), (x, y + 4)], fill="#2b2014")
    draw.line([(x + 2, bottom - 4), (x + 2, y + 4), (x + 5, y + 1),
               (right - 5, y + 1), (right - 2, y + 4)],
              fill="#c3a06a" if enabled else "#8b7c63", width=2)
    draw.line([(right - 2, y + 5), (right - 2, bottom - 4), (right - 5, bottom - 2),
               (x + 5, bottom - 2), (x + 2, bottom - 5)],
              fill="#8b6734" if enabled else "#5d5140", width=2)
    draw.rectangle((x + 4, y + 4, right - 4, bottom - 4), fill="#2b0c07" if enabled else "#29241b")
    for line in range(y + 5, bottom - 4):
        ratio = (line - y - 5) / (size[1] - 10)
        shade = round(152 - 68 * ratio)
        color = (shade, round(24 - 18 * ratio), 12) if enabled else (63, 51, 39)
        draw.line((x + 5, line, right - 5, line), fill=color)


def render(panel, output):
    scale = DISPLAY_SCALE * panel.GetScale(panel)
    margin = 32
    panel_size = tuple(round(value * scale) for value in (panel.width, panel.height))
    stage_size = (panel_size[0] + margin * 2, panel_size[1] + margin * 2)
    image = Image.new("RGBA", stage_size, "#201815")
    stage = ImageDraw.Draw(image)
    for step in range(110, 0, -1):
        width = round(stage_size[0] * step / 125)
        height = round(stage_size[1] * step / 125)
        shade = round(6 * (1 - step / 110))
        stage.ellipse(((stage_size[0] - width) // 2, (stage_size[1] - height) // 2,
                       (stage_size[0] + width) // 2, (stage_size[1] + height) // 2),
                      fill=(32 + shade, 24 + shade, 21 + shade, 255))
    parchment = Image.open(ART).convert("RGBA").resize(panel_size, Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", stage_size)
    mask = parchment.getchannel("A").point(lambda alpha: round(alpha * 0.75))
    shadow.paste((0, 0, 0, 255), (margin + 2, margin + 6,
                                   margin + 2 + panel_size[0], margin + 6 + panel_size[1]), mask)
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(13)))
    font_faces = {}
    widths = []

    def draw_label(value, at, size, font_size, tint, center):
        font_key = round(font_size * scale)
        if font_key not in font_faces:
            font_faces[font_key] = ImageFont.truetype(str(FONT_DIR / "msyh.ttc"), font_key)
        face = font_faces[font_key]
        draw = ImageDraw.Draw(image)
        widths.append((value, round(draw.textlength(value, font=face)), size[0]))
        align_x = at[0] + (size[0] / 2 if center else 0)
        draw.text((align_x, at[1] + size[1] / 2), value, font=face,
                  fill=tint, anchor="mm" if center else "lm")

    def draw_tree(node, left, top, width, height):
        children = (node.children[index] for index in range(1, len(node.children) + 1))
        for child in sorted(children, key=lambda region: LAYERS.get(region.layer, 3)):
            if not region_visible(child):
                continue
            x = left + (child.x or 0)
            y = top + (child.y or 0)
            w = width if child.allPoints else child.width
            h = height if child.allPoints else child.height
            if w is None or h is None:
                continue
            at = (margin + round(x * scale), margin + round(y * scale))
            size = (margin + round((x + w) * scale) - at[0], margin + round((y + h) * scale) - at[1])
            if child.kind == "Texture" and child.asset:
                image.alpha_composite(parchment, at)
            elif child.kind == "Texture" and child.color:
                image.alpha_composite(Image.new("RGBA", size, color(child.color)), at)
            elif child.kind == "FontString" and child.text:
                draw_label(child.text, at, size, child.size, color(child.color), child.justify == "CENTER")
            elif child.panelButton:
                draw_native_button(image, at, size, child.enabled)
                tint = "#ffdb75" if child.enabled else "#aa9d87"
                draw_label(child.text, (at[0] + 5, at[1]), (size[0] - 10, size[1]), 13, tint, True)
            elif child.normalAsset and child.normalAsset.endswith("SizeGrabber-Up"):
                draw = ImageDraw.Draw(image)
                x, y = at[0] + size[0] - 4, at[1] + size[1] - 4
                for fraction in (0.25, 0.5, 0.75):
                    inset = round((min(size) - 4) * fraction)
                    draw.line((x - inset, y, x, y - inset), fill="#765335" if child.enabled else "#a98b68", width=2)
                    draw.line((x - inset + 2, y, x, y - inset + 2), fill="#f2d5a0")
            else:
                draw_tree(child, x, y, w, h)

    draw_tree(panel, 0, 0, panel.width, panel.height)
    overflow = [(value, pixels, available) for value, pixels, available in widths if pixels > available]
    if overflow:
        raise ValueError(f"Text overflow: {overflow}")
    image.convert("RGB").save(output, optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--make-art", action="store_true")
    parser.add_argument("--empty", action="store_true")
    args = parser.parse_args()
    if args.make_art:
        make_art()
    lua = runtime()
    lua.execute("""MOCK.Load({groups={{started=time()-3600,names={"寒山 月白"}}}}, true, false)
        MOCK.Open()""")
    if not args.empty:
        lua.execute("""for _, name in ipairs({"暮刃 枫影", "踏雪 银松", "深潮 暮羽", "荒歌 岩脊",
            "夜棘 灰烬", "寒鸦 晨星", "长风入夜 霜白听松"}) do MOCK.Paste(name) end
            MOCK.Click(WantedPosterFrame.previousPage)""")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render(lua.globals().WantedPosterFrame, args.output)


if __name__ == "__main__":
    main()
