"""The Açaí Dose sticker cup (sunglasses + smile) used as the loyalty stamp."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BODY = (92, 22, 86); RIM = (122, 48, 112); LINE = (58, 10, 54); CREAM = (250, 243, 224); STRAW = (240, 200, 160)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def _thick_line(d, a, b, w, fill, outline, lw):
    """Line with round caps and an outline."""
    for col, ww in ((outline, w), (fill, w - 2 * lw)):
        d.line((a, b), fill=col, width=int(ww))
        for (x, y) in (a, b):
            r = ww / 2; d.ellipse((x - r, y - r, x + r, y + r), fill=col)

def sticker_cup(h, state='on'):
    """RGBA image of the cup, height h px. state: on (stamped) / off (faded)."""
    S = 4; H = h * S; W = int(H * 0.74)
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx = W / 2; top = H * 0.27; base = H * 0.97; wt = W * 0.43; wb = W * 0.33
    lw = int(H * 0.022)
    # straw behind the cup
    _thick_line(d, (cx + W * 0.06, top + H * 0.02), (cx + W * 0.22, top - H * 0.24), H * 0.07, STRAW, LINE, lw)
    # body with softly rounded bottom
    body = [(cx - wt, top), (cx + wt, top), (cx + wb, base), (cx - wb, base)]
    d.polygon(body, fill=BODY)
    d.line(body + [body[0]], fill=LINE, width=lw, joint='curve')
    # drink surface
    d.ellipse((cx - wt, top - H * 0.04, cx + wt, top + H * 0.04), fill=RIM, outline=LINE, width=lw)
    # straw going into the drink
    _thick_line(d, (cx + W * 0.08, top - H * 0.01), (cx + W * 0.22, top - H * 0.24), H * 0.07, STRAW, LINE, lw)
    # sunglasses
    gy = top + H * 0.17; gw = W * 0.30; gh = H * 0.11; gap = W * 0.025
    for x0 in (cx - gap - gw, cx + gap):
        d.rounded_rectangle((x0, gy, x0 + gw, gy + gh), radius=gh * 0.5, fill=(24, 4, 22))
        d.rounded_rectangle((x0 + gw * 0.22, gy + gh * 0.18, x0 + gw * 0.48, gy + gh * 0.30), radius=gh * 0.06, fill=(170, 150, 170))
    d.rectangle((cx - gap - 1, gy + gh * 0.15, cx + gap + 1, gy + gh * 0.32), fill=(24, 4, 22))
    # smile
    my = gy + gh + H * 0.06
    d.arc((cx - W * 0.13, my - H * 0.07, cx + W * 0.13, my + H * 0.05), 25, 155, fill=CREAM, width=int(lw * 1.8))
    # name
    f = ImageFont.truetype(FONT, int(H * 0.068))
    d.text((cx, base - H * 0.12), 'AÇAÍ DOSE', font=f, fill=CREAM, anchor='mm')
    out = im.resize((W // S, H // S), Image.LANCZOS)
    if state == 'off':
        a = out.getchannel('A').point(lambda v: int(v * 0.20))
        ghost = Image.new('RGBA', out.size, (120, 70, 115, 0)); ghost.putalpha(a)
        return ghost
    return out
