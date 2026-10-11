"""Draws the loyalty-card artwork for Apple Wallet (strip) and Google Wallet (hero + logo).
Run from the repo root:  python3 tools/wallet_images.py   (needs Pillow with raqm for Arabic)."""
from PIL import Image, ImageDraw, ImageFont

P = (71, 13, 67); C = (250, 243, 224); O = (227, 154, 46)
AR = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
OUT = 'assets/wallet/'

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

def panel(Wpt, Hpt, stamps, free, need=5, plain=False, pad=(30, 12)):
    """Cream panel with need cups + one free slot. Sizes in points, drawn 8x then scaled."""
    S = 8; W, H = Wpt * S, Hpt * S
    im = Image.new('RGB', (W, H), P); d = ImageDraw.Draw(im)
    px, py = pad[0] * S, pad[1] * S
    d.rounded_rectangle((px, py, W - px, H - py), radius=20 * S, fill=C)
    n = need + 1; inner = W - 2 * px - 20 * S; step = inner / n
    ch = min(48, (Hpt - 2 * pad[1]) * 0.42) * S          # cup height
    cy = H / 2 - 6 * S
    f = ImageFont.truetype(AR, int(13 * S))
    for i in range(n):
        cx = px + 10 * S + step * (n - 1 - i + 0.5)       # first stamp on the right (Arabic order)
        if i < need:
            cup(d, cx, cy + ch / 2, ch, 'on' if (plain or free or i < stamps) else 'off')
        else:
            r = ch * 0.52
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=O if (free or plain) else C, outline=O, width=int(2.5 * S))
            cup(d, cx, cy + r * 0.66, ch * 0.75, 'free')
            d.text((cx, cy + r + 14 * S), 'مجاني', font=f, fill=P if (free or plain) else O, anchor='mm', direction='rtl', language='ar')
    return im

def save_set(prefix, Wpt, Hpt, scales, pad):
    for k in range(5): out(panel(Wpt, Hpt, k, False, pad=pad), f'{prefix}-{k}', Wpt, Hpt, scales)
    out(panel(Wpt, Hpt, 5, True, pad=pad), f'{prefix}-free', Wpt, Hpt, scales)
    out(panel(Wpt, Hpt, 0, False, plain=True, pad=pad), f'{prefix}-plain', Wpt, Hpt, scales)

def out(im, name, Wpt, Hpt, scales):
    for sc, suf in scales:
        im.resize((int(Wpt * sc), int(Hpt * sc)), Image.LANCZOS).save(f'{OUT}{name}{suf}.png', optimize=True)

if __name__ == '__main__':
    # Apple Wallet strip: 375x144 pt (shown aspect-fill, so keep margins)
    save_set('strip', 375, 144, [(1, ''), (2, '@2x'), (3, '@3x')], (30, 12))
    # Google Wallet hero image: 1032x336 px (= 344x112 pt at 3x)
    save_set('g-hero', 344, 112, [(3, '')], (16, 8))
    # Google program logo: square, 660 px, cream logo on purple
    lg = Image.open('assets/logo-cream.png').convert('RGBA'); lg = lg.crop(lg.getbbox())
    sq = Image.new('RGB', (660, 660), P); w = 520; h = int(lg.height * w / lg.width)
    im = lg.resize((w, h), Image.LANCZOS); sq.paste(im, ((660 - w) // 2, (660 - h) // 2), im); sq.save(OUT + 'g-logo.png', optimize=True)
