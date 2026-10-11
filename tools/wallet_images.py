"""Draws the loyalty-card artwork for Apple Wallet (strip) and Google Wallet (hero + logo).
Run from the tools folder:  cd tools && python3 wallet_images.py   (needs Pillow with raqm for Arabic)."""
from PIL import Image, ImageDraw, ImageFont
from cup_sticker import sticker_cup

P = (71, 13, 67); C = (250, 243, 224); O = (227, 154, 46)
AR = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
OUT = '../assets/wallet/'

def cup(d, cx, base, h, state):
    """Drawn açaí cup with dome lid and straw. state: on / off / free."""
    w = h * 0.6; top = base - h * 0.74
    if state == 'off': line = (205, 182, 203); acai = None; lid = None; straw = line
    else: line = P; acai = (92, 22, 86); lid = (255, 255, 255); straw = O if state == 'on' else P
    lw = max(2, int(h * 0.05))
    d.line((cx + w * 0.08, top - h * 0.10, cx + w * 0.28, top - h * 0.28), fill=straw, width=int(lw * 1.5))
    d.pieslice((cx - w * 0.46, top - h * 0.20, cx + w * 0.46, top + h * 0.16), 180, 360, fill=lid, outline=line, width=lw)
    d.rounded_rectangle((cx - w * 0.54, top - h * 0.03, cx + w * 0.54, top + h * 0.06), radius=h * 0.03, fill=lid, outline=line, width=lw)
    body = [(cx - w * 0.48, top + h * 0.06), (cx + w * 0.48, top + h * 0.06), (cx + w * 0.34, base), (cx - w * 0.34, base)]
    if acai:
        d.polygon(body, fill=acai)
        d.polygon([(cx - w * 0.45, top + h * 0.30), (cx + w * 0.45, top + h * 0.30), (cx + w * 0.43, top + h * 0.38), (cx - w * 0.43, top + h * 0.38)], fill=(135, 55, 125))
        d.rounded_rectangle((cx - w * 0.22, top + h * 0.52, cx + w * 0.22, top + h * 0.58), radius=h * 0.02, fill=C)
    d.line(body + [body[0]], fill=line, width=lw, joint='curve')

_cache = {}
def stamp(h, state):
    k = (int(h), state)
    if k not in _cache: _cache[k] = sticker_cup(int(h), state)
    return _cache[k]

def panel(Wpt, Hpt, stamps, free, need=5, plain=False, pad=(30, 12)):
    """Cream panel with `need` sticker cups + one free slot (two rows when there are many). Drawn at 4x."""
    S = 4; W, H = Wpt * S, Hpt * S
    im = Image.new('RGBA', (W, H), P + (255,)); d = ImageDraw.Draw(im)
    px, py = pad[0] * S, pad[1] * S
    d.rounded_rectangle((px, py, W - px, H - py), radius=20 * S, fill=C)
    n = need + 1
    rows = 1 if n <= 7 else 2
    cols = -(-n // rows)
    inner = W - 2 * px - 20 * S; step = inner / cols
    rowh = (H - 2 * py) / rows
    ch = min(step * 1.12, rowh * (0.62 if rows == 1 else 0.80))
    f = ImageFont.truetype(AR, int((13 if rows == 1 else 9) * S))
    for i in range(n):
        r_, c_ = divmod(i, cols)
        cx = px + 10 * S + step * (cols - 1 - c_ + 0.5)          # first stamp on the right (Arabic order)
        cy = py + rowh * (r_ + 0.5) - (8 * S if rows == 1 else 2 * S)
        if i < need:
            img = stamp(ch, 'on' if (plain or free or i < stamps) else 'off')
            im.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2)))
        else:
            rr = min(step * 0.48, ch * 0.52)
            d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=O if (free or plain) else C, outline=O, width=int(2.5 * S))
            img = stamp(rr * 1.5, 'on')
            im.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2 + rr * 0.05)))
            if rows == 1:
                d.text((cx, cy + rr + 12 * S), 'مجاني', font=f, fill=P if (free or plain) else O, anchor='mm', direction='rtl', language='ar')
    return im.convert('RGB')

def save_set(prefix, Wpt, Hpt, scales, pad):
    """One image per stamp count for every rule from 3 to 10 stamps, plus a plain one."""
    for need in range(3, 11):
        for k in range(need): out(panel(Wpt, Hpt, k, False, need, pad=pad), f'{prefix}-{need}-{k}', Wpt, Hpt, scales)
        out(panel(Wpt, Hpt, need, True, need, pad=pad), f'{prefix}-{need}-free', Wpt, Hpt, scales)
    out(panel(Wpt, Hpt, 0, False, 5, plain=True, pad=pad), f'{prefix}-plain', Wpt, Hpt, scales)

def out(im, name, Wpt, Hpt, scales):
    for sc, suf in scales:
        im.resize((int(Wpt * sc), int(Hpt * sc)), Image.LANCZOS).save(f'{OUT}{name}{suf}.png', optimize=True)

def web_stamps():
    for st in ('on', 'off'): sticker_cup(160, st).save(f'{OUT}stamp-{st}.png', optimize=True)

if __name__ == '__main__':
    web_stamps()
    # Apple Wallet strip: 375x144 pt (shown aspect-fill, so keep margins)
    save_set('strip', 375, 144, [(1, ''), (2, '@2x'), (3, '@3x')], (30, 12))
    # Google Wallet hero image: 1032x336 px (= 344x112 pt at 3x)
    save_set('g-hero', 344, 112, [(3, '')], (16, 8))
    # Google program logo: square, 660 px, cream logo on purple
    lg = Image.open('../assets/logo-cream.png').convert('RGBA'); lg = lg.crop(lg.getbbox())
    sq = Image.new('RGB', (660, 660), P); w = 520; h = int(lg.height * w / lg.width)
    im = lg.resize((w, h), Image.LANCZOS); sq.paste(im, ((660 - w) // 2, (660 - h) // 2), im); sq.save(OUT + 'g-logo.png', optimize=True)
