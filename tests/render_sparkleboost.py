"""Offline UI preview from the addon controls and renderer; not a game capture."""
from pathlib import Path
import math
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "sparkleboost_mock.lua").read_text(encoding="utf-8"))
lua.execute("MOCK.Load(); SlashCmdList.SPARKLEBOOST('test'); MOCK.Advance(1.1)")
mock = lua.globals().MOCK
panel = lua.globals().SparkleBoostOptions
frames = list(mock.frames.values())
anchors = {"TOPLEFT": (0, 0), "TOP": (.5, 0), "TOPRIGHT": (1, 0), "LEFT": (0, .5),
           "CENTER": (.5, .5), "RIGHT": (1, .5), "BOTTOMLEFT": (0, 1), "BOTTOM": (.5, 1), "BOTTOMRIGHT": (1, 1)}
cache = {}


def bounds(frame):
    index = frame.index
    if index in cache:
        return cache[index]
    width, height = frame.width, frame.height
    point = frame.points[1]
    if point is None:
        result = (0, 0, width, height)
    else:
        relative = point[2] or frame.parent
        left, top, rw, rh = bounds(relative)
        own = anchors[point[1]]
        target = anchors[point[3]]
        result = (left + rw * target[0] + (point[4] or 0) - width * own[0],
                  top + rh * target[1] - (point[5] or 0) - height * own[1], width, height)
    cache[index] = result
    return result


origin_x, origin_y, width, height = bounds(panel)
image = Image.new("RGBA", (round(width), round(height)), (14, 17, 23, 255))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((1, 1, width - 2, height - 2), radius=8, outline=(179, 140, 66), width=2)
font_path = Path("C:/Windows/Fonts/msyh.ttc")
if not font_path.exists():
    font_path = Path("C:/Windows/Fonts/simhei.ttf")


def font(size):
    return ImageFont.truetype(str(font_path), size)


def visible(frame):
    return frame.IsVisible(frame)


def text(value, x, y, maximum, size=14, color=(220, 224, 233)):
    value = str(value)
    if "|cffffd166" in value:
        color = (255, 209, 102)
    value = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", value)
    face = font(size)
    lines = []
    for paragraph in value.split("\n"):
        line = ""
        for character in paragraph:
            if line and draw.textlength(line + character, font=face) > maximum:
                lines.append(line)
                line = character
            else:
                line += character
        lines.append(line)
    for line in lines:
        draw.text((x, y), line, font=face, fill=color)
        y += size + 5


for frame in frames:
    if not visible(frame):
        continue
    left, top, w, h = bounds(frame)
    x, y = left - origin_x, top - origin_y
    if frame.kind == "Frame" and w == 226 and h == 254:
        draw.rounded_rectangle((x, y, x + w, y + h), radius=5, fill=(4, 7, 12), outline=(43, 51, 66))
    elif frame.kind == "Button" and frame.text:
        draw.rounded_rectangle((x, y, x + w, y + h), radius=4, fill=(35, 41, 54), outline=(88, 78, 56))
        face = font(13)
        plain = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", frame.text)
        text(frame.text, x + (w - draw.textlength(plain, font=face)) / 2, y + 3, w, 13)
    elif frame.kind == "CheckButton":
        draw.rounded_rectangle((x + 3, y + 3, x + 22, y + 22), radius=3, fill=(27, 33, 44), outline=(118, 113, 96))
        if frame.checked:
            draw.line((x + 7, y + 12, x + 11, y + 17, x + 20, y + 7), fill=(255, 209, 102), width=3)
    elif frame.kind == "Slider":
        draw.rounded_rectangle((x, y + 6, x + w, y + 11), radius=2, fill=(39, 46, 60))
        ratio = (frame.value - frame.low) / (frame.high - frame.low)
        knob = x + ratio * w
        draw.ellipse((knob - 6, y + 2, knob + 6, y + 15), fill=(221, 184, 111))
    elif frame.kind == "FontString" and frame.text:
        size = 21 if frame.font == "GameFontNormalLarge" else (12 if frame.font == "GameFontHighlightSmall" else 14)
        color = (224, 186, 112) if frame.font in ("GameFontNormal", "GameFontNormalLarge") else (212, 219, 230)
        text(frame.text, x, y, w, size, color)

for frame in frames:
    if frame.kind != "Texture" or not visible(frame) or not frame.texture:
        continue
    if "\\Textures\\" not in frame.texture or not frame.color:
        continue
    name = frame.texture.rsplit("\\", 1)[-1]
    texture = Image.open(ROOT / "SparkleBoost" / "Textures" / (name + ".tga")).convert("RGBA")
    left, top, w, h = bounds(frame)
    texture = texture.resize((max(1, round(w)), max(1, round(h))), Image.Resampling.LANCZOS)
    color = list(frame.color.values())
    alpha = texture.getchannel("A").point(lambda a: round(a * color[3]))
    texture = Image.new("RGBA", texture.size, tuple(round(c * 255) for c in color[:3]) + (0,))
    texture.putalpha(alpha)
    if frame.rotation:
        texture = texture.rotate(math.degrees(frame.rotation), resample=Image.Resampling.BICUBIC, expand=True)
    x = round(left - origin_x + (w - texture.width) / 2)
    y = round(top - origin_y + (h - texture.height) / 2)
    image.alpha_composite(texture, (x, y))

draw = ImageDraw.Draw(image)
draw.text((width - 226, 24), "离线布局预览 · 非游戏实拍", font=font(11), fill=(139, 148, 164))
destination = ROOT / "design" / "offline-sparkleboost-options.png"
image.convert("RGB").save(destination)
print(destination)
