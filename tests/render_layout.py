"""Render actual Lua widget coordinates for offline layout review, not game acceptance. Solazhu."""
from pathlib import Path
import math
import sys
from functools import lru_cache

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools" / "python"))
from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute('''
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
for _, file in ipairs({"Libs/LibStub.lua", "Libs/LibAHTab.lua", "Logic.lua", "Core.lua", "History.lua", "Market.lua",
    "Native.lua", "Widgets.lua", "Editor.lua", "UI.lua"}) do
    assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. file))("AuctionPilot", A)
end
A.Initialize(); A.open = true; A.Native.Attach(); A.Native.ShowMonitor(); MOCK.flush()
AuctionHouseFrame:SetSize(800,538)
assert(A.SaveProduct({itemID=1, recipeName="专业硫酸 #900", output=1, fee=5, extra=0, alert=true,
    sourceRecipeID=900,sourceOutputMin=1,sourceOutputMax=1,
    materials={{itemID=2,quantity=2,source="market"},{itemID=3,quantity=1,source="fixed",price=200}}}))
assert(A.SaveProduct({id=1,itemID=1,recipeName="另一生产方案（示例）",output=2,fee=5,extra=0,alert=true,
    materials={{itemID=2,quantity=3,source="market"},{itemID=3,quantity=2,source="fixed",price=200}}}))
assert(A.SaveProduct({itemID=4, recipeName="默认配方", output=1, fee=5, extra=0, alert=true,
    materials={{itemID=2,quantity=1,source="fixed",price=3400}}}))
A.Select(1,1)
for id, price in pairs({[1]=12000,[2]=4200,[4]=4000,[5]=1200}) do
    A.AcceptQuote(id,A.Logic.Snapshot({{price=price,quantity=200,own=id==1 and 40 or 0}},MOCK.time,true))
end
A.AcceptQuote(1,A.Logic.Snapshot({{price=12000,quantity=280,own=40}},MOCK.time,true))
A.UI.quantity:SetText("20")
MOCK.addon = A
''')

FONT = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
@lru_cache(None)
def font(size, bold=False):
    return ImageFont.truetype(FONT_BOLD if bold else FONT, max(9, int(size)))

def render(path, native=False):
    frames = list(lua.globals().MOCK.frames.values())
    by_id = {int(f.index): f for f in frames}
    bounds = {}
    scale = 1.5
    root = lua.globals().AuctionHouseFrame if native else lua.globals().MOCK.addon.UI.frame
    root_id = int(root.index)
    anchors = {"TOPLEFT": (0, 0), "TOP": (.5, 0), "TOPRIGHT": (1, 0), "LEFT": (0, .5),
               "CENTER": (.5, .5), "RIGHT": (1, .5), "BOTTOMLEFT": (0, 1), "BOTTOM": (.5, 1), "BOTTOMRIGHT": (1, 1)}
    def effective_scale(f):
        return float(f.GetEffectiveScale(f))
    def rect(f):
        i = int(f.index)
        if i in bounds: return bounds[i]
        if f.allPoints:
            result = rect(f.allPoints); bounds[i] = result; return result
        w, h = float(f.width or 0), float(f.height or 0)
        text = str(f.text or "")
        if f.kind == "FontString":
            ff = font(float(f.fontSize or 14))
            if not w: w = max((ff.getlength(t) for t in text.split("\n")), default=1)
            if not h: h = float(f.fontSize or 14) * 1.45 * max(1, text.count("\n") + 1)
        zoom = effective_scale(f)
        w, h = w * zoom, h * zoom
        points = list(f.points.values())
        if points:
            first = points[0]
            a, rel, b, dx, dy = first[1], first[2], first[3], float(first[4]), float(first[5])
            rx, ry, rw, rh = rect(rel) if rel else (0, 0, 1600, 1000)
            ax, ay = anchors[a]; bx, by = anchors[b]
            x, y = rx + bx * rw + dx * zoom - ax * w, ry + by * rh - dy * zoom - ay * h
            if not w and len(points) > 1:
                second = points[1]
                if second[1] == "TOPRIGHT":
                    rx2, ry2, rw2, rh2 = rect(second[2])
                    w = rx2 + rw2 + float(second[4]) * zoom - x
        elif f.parent:
            x, y, _, _ = rect(f.parent)
        else: x, y = 0, 0
        bounds[i] = (x, y, w, h)
        return bounds[i]
    ox, oy, width, height = rect(root)
    image = Image.new("RGB", (int(width * scale), int(height * scale) + 36), "#111210")
    draw = ImageDraw.Draw(image)
    draw.text((16, 7), "离线布局预览 · 示例报价 · 原生边界示意，非游戏截图", font=font(15), fill="#b4aa91")
    if native:
        draw.rectangle((0,36,width*scale-1,height*scale+35),fill="#21211e",outline="#a58b48",width=2)
        draw.text((width*scale/2-75,42),"原生拍卖行标题栏",font=font(14),fill="#c6aa67")
        draw.text((12,height*scale+12),"原生金币栏 / 底部标签保留",font=font(12),fill="#b4aa91")
    def descendant(f):
        p = f
        while p:
            if int(p.index) == root_id: return True
            p = p.parent
        return False
    def visible(f):
        return bool(f.IsVisible(f)) and descendant(f)
    def coords(f):
        x, y, w, h = rect(f)
        return ((x-ox)*scale, (y-oy)*scale+36, w*scale, h*scale)
    def color(v, default):
        return tuple(int(float(v[i])*255) for i in (1, 2, 3)) if v else default
    # All panels first, then controls, then text, following native frame layering.
    for f in frames:
        if not visible(f) or f.kind == "FontString": continue
        x, y, w, h = coords(f)
        if w <= 0 or h <= 0: continue
        box = (x, y, x+w, y+h)
        if f.backdrop:
            draw.rectangle(box, fill=color(f.fill,(23,24,22)), outline=color(f.border,(110,90,45)), width=2)
        elif f.kind in ("Button", "EditBox", "CheckButton"):
            if f.template:
                draw.rectangle(box, fill="#31231c" if f.kind == "Button" else "#111210", outline="#74644b", width=1)
                if f.text and not f.label:
                    ff=font(14*scale*effective_scale(f)); tw=draw.textlength(str(f.text),font=ff)
                    draw.text((x+max(4,(w-tw)/2),y+max(0,(h-20)/2)),str(f.text),font=ff,fill="#e4d8bc")
            if f.kind == "CheckButton" and f.checked:
                draw.line([(x+5,y+12),(x+12,y+20),(x+26,y+5)],fill="#e2b858",width=3)
        elif f.kind == "Texture" and f.fill:
            draw.rectangle(box, outline="#7b642d", width=1)
    overflow = []
    for f in frames:
        if not visible(f) or f.kind != "FontString" or not f.text: continue
        x,y,w,h = coords(f); ff=font(float(f.fontSize or 14)*scale*effective_scale(f))
        fill=color(f.color,(229,219,192)); text=str(f.text)
        lines=[]
        for raw in text.split("\n"):
            if f.width and draw.textlength(raw,font=ff)>w:
                line=""
                for char in raw:
                    if line and draw.textlength(line+char,font=ff)>w: lines.append(line); line=""
                    line+=char
                lines.append(line)
            else: lines.append(raw)
        for line in lines:
            tw=draw.textlength(line,font=ff)
            tx=x+max(0,w-tw) if f.justify=="RIGHT" else x
            draw.text((tx,y),line,font=ff,fill=fill); y+=ff.size*1.4
        if x < -1 or x+w > image.width+2 or y > image.height+8: overflow.append(text)
    path.parent.mkdir(parents=True,exist_ok=True)
    image.save(path)
    print(path.name, "viewport overflows:", overflow)

render(ROOT / "design" / "offline-docked-list.png", native=True)
lua.execute('MOCK.addon.Editor.Open(MOCK.addon.Selected())')
render(ROOT / "design" / "offline-docked-editor.png", native=True)
lua.execute('MOCK.addon.Editor.Close(); MOCK.addon.open=false; MOCK.addon.UI.frame:SetParent(UIParent); MOCK.addon.UI.Layout()')
render(ROOT / "design" / "offline-standalone.png")
