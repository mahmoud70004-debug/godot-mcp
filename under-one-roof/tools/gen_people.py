"""Villagers drawn in the style of the art reference (assets/reference/world_reference.jpg):
small, naturally proportioned figures (about 3 heads tall), soft painted light from the
upper left and a thin warm-brown contour - no pixel art, no chibi heads.

Every frame is drawn with smooth vector shapes at S x supersampling and downscaled to
stylize.RES x the 20x32 world frame, so the sheets keep the existing layout:
  row 0 down, row 1 left, row 2 right, row 3 up   -> idle, step A, idle, step B
  row 4 action (facing down): tool raised, strike, crouch, hands at work
The cast and their clothes come from gen_characters.CHARACTERS.
"""
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageOps
from gen_characters import CHARACTERS, SKIN, FW, FH
from stylize import RES

S = 8                      # supersampling (frame px -> canvas px)
OUT = (FW * RES, FH * RES)
LINE = (52, 36, 28)


def rgb(col):
    return tuple(int(v) for v in col[:3])


def tint(col, f):
    return tuple(max(0, min(255, int(v * f))) for v in col[:3])


class Frame:
    """One supersampled frame; parts are painted back to front with shading."""

    def __init__(self):
        self.w, self.h = FW * S, FH * S
        self.col = np.zeros((self.h, self.w, 3), np.float32)
        self.alpha = np.zeros((self.h, self.w), np.float32)

    def mask(self, fn):
        m = Image.new("L", (self.w, self.h), 0)
        fn(ImageDraw.Draw(m), lambda *v: [x * S for x in v])
        return np.array(m, np.float32) / 255.0

    def part(self, fn, col, overlay=None, shade=True, light=1.0):
        """fn(draw, P) draws the part's silhouette in white; P scales frame px to canvas px."""
        m = self.mask(fn)
        if not m.any():
            return m
        base = np.empty((self.h, self.w, 3), np.float32)
        base[:] = tint(col, light)
        if overlay is not None:
            layer = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
            overlay(ImageDraw.Draw(layer), lambda *v: [x * S for x in v])
            la = np.array(layer, np.float32)
            a = la[..., 3:] / 255.0
            base = base * (1 - a) + la[..., :3] * a
        if shade:
            inside = m > 0.5
            dx, dy = int(1.1 * S), int(0.9 * S)
            lit = inside & np.roll(np.roll(inside, -dy, 0), -dx, 1)
            hx, hy = int(0.55 * S), int(0.5 * S)
            rim = inside & ~np.roll(np.roll(inside, hy, 0), hx, 1)
            f = np.where(lit, 1.0, 0.68)
            f = np.where(rim, 1.16, f)
            f = cv2.GaussianBlur(f.astype(np.float32), (0, 0), S * 0.35)
            base *= f[..., None]
        a = m[..., None]
        self.col = self.col * (1 - a) + base * a
        self.alpha = np.maximum(self.alpha, m)
        return m

    def detail(self, fn, col, alpha=1.0):
        """Unshaded detail (eyes, stripes, seams)."""
        m = self.mask(fn) * alpha
        self.col = self.col * (1 - m[..., None]) + np.array(rgb(col), np.float32) * m[..., None]
        self.alpha = np.maximum(self.alpha, m)

    def image(self, seed=0):
        a = (self.alpha > 0.5).astype(np.uint8)
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(0.7 * S), int(0.7 * S)))
        ring = (cv2.dilate(a, k) & (1 - a)).astype(np.float32)
        col = self.col.copy()
        # painterly finish: soft fabric grain, light falling off towards the feet
        rng = np.random.default_rng(seed)
        grain = cv2.GaussianBlur(rng.normal(0, 1, (self.h, self.w)).astype(np.float32), (0, 0), S * 0.3)
        grain /= max(1e-6, grain.std())
        ys = np.linspace(0, 1, self.h, dtype=np.float32)[:, None]
        light = 1.06 - 0.16 * ys + 0.035 * grain
        col *= light[..., None]
        # warm, slightly desaturated like the reference
        grey = col.mean(axis=2, keepdims=True)
        col = grey + (col - grey) * 0.86
        col *= np.array([1.03, 1.0, 0.95], np.float32)
        col = np.where(ring[..., None] > 0, np.array(LINE, np.float32), col)
        alpha = np.maximum(self.alpha, ring * 0.7)
        img = np.dstack([np.clip(col, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
        return Image.fromarray(img, "RGBA")


# ---------------------------------------------------------------- figure
def geometry(p):
    child = p.get("child", False)
    big = 1.12 if p.get("big") else 1.0
    return dict(
        cx=10.0, head_y=8.6, head_rx=3.6, head_ry=4.0,
        sh_y=12.9, waist_y=20.6, hip_y=20.6, foot_y=30.6,
        sh_w=4.3 * big, waist_w=3.5 * big, arm_w=1.15 * big,
        child=child,
    )


def draw_figure(p, view, step, action=None):
    """Draws one frame. view: down | right | up. step: 0 idle, 1 / 3 stride."""
    F = Frame()
    g = geometry(p)
    cx = g["cx"]
    skin = rgb(SKIN[p["skin"]])
    top = rgb(p["top"])
    coat = rgb(p["coat"]) if "coat" in p else None
    pants = rgb(p["pants"])
    shoes = rgb(p["shoes"])
    hair = rgb(p["hair"])
    sleeve = coat or top
    long_body = p.get("dress") or p.get("cassock")
    stride = {0: 0.0, 1: 1.0, 2: 0.0, 3: -1.0}[step]
    bob = -0.35 if step in (1, 3) else 0.0
    crouch = 3.0 if action == 18 else 0.0
    hy = g["head_y"] + bob + crouch
    sh = g["sh_y"] + bob + crouch
    wy = g["waist_y"] + bob + crouch * 0.85
    fy = g["foot_y"]
    side = view == "right"

    # ---- hair hanging behind (long hair, braids seen from the back)
    if p["hair_style"] in ("long",) and view != "up":
        F.part(lambda d, P: d.rounded_rectangle(P(cx - 3.9, hy - 1, cx + 3.9, sh + 2.6), radius=1.6 * S, fill=255), hair)

    # ---- legs
    def leg(x0, lift, fwd):
        top_y = wy - 0.4
        bot = fy - 0.9 - lift
        if crouch:
            bot = fy - 0.9
        w = 1.35
        def fn(d, P):
            d.polygon(P(x0 - w, top_y, x0 + w, top_y, x0 + fwd + w * 0.9, bot, x0 + fwd - w * 0.9, bot), fill=255)
        F.part(fn, pants)
        def shoe(d, P):
            if side:
                d.rounded_rectangle(P(x0 + fwd - 1.3, bot - 0.4, x0 + fwd + 2.1, bot + 1.3), radius=0.6 * S, fill=255)
            else:
                d.ellipse(P(x0 + fwd - 1.5, bot - 0.5, x0 + fwd + 1.5, bot + 1.3), fill=255)
        F.part(shoe, shoes)

    if not long_body:
        if side:
            leg(cx - 0.3, 0.6 if stride < 0 else 0, -2.0 * stride)
            leg(cx + 0.3, 0.6 if stride > 0 else 0, 2.0 * stride)
        else:
            leg(cx - 1.55, max(0, stride) * 0.9, 0)
            leg(cx + 1.55, max(0, -stride) * 0.9, 0)
    else:
        # feet peeking under a long skirt / cassock
        for i, x in enumerate((cx - 1.5, cx + 1.5)):
            off = (stride if i else -stride) * (1.2 if side else 0)
            F.part(lambda d, P, x=x, off=off: d.ellipse(P(x + off - 1.4, fy - 1.5, x + off + 1.4, fy + 0.2), fill=255), shoes)

    # ---- far arm (side view)
    def arm(x_sh, hand, col, width=g["arm_w"], hand_col=None):
        def fn(d, P):
            d.line(P(x_sh, sh + 0.9, hand[0], hand[1]), fill=255, width=int(width * 2 * S))
            r = width
            d.ellipse(P(x_sh - r, sh + 0.9 - r, x_sh + r, sh + 0.9 + r), fill=255)
        F.part(fn, col)
        hc = hand_col or (rgb(p["gloves"]) if "gloves" in p else skin)
        F.part(lambda d, P: d.ellipse(P(hand[0] - 0.95, hand[1] - 0.95, hand[0] + 0.95, hand[1] + 0.95), fill=255), hc)

    if side:
        arm(cx - 0.4, (cx - 0.4 - 1.6 * stride, wy - 0.6), tint(sleeve, 0.8))

    # ---- body: skirt / coat tails / torso
    sw, ww = g["sh_w"], g["waist_w"]
    if side:
        sw, ww = sw * 0.72, ww * 0.78
    if long_body:
        dress_col = top if p.get("cassock") else rgb(p["top"])
        hem = fy - 1.1
        F.part(lambda d, P: d.polygon(P(cx - ww - 0.2, wy - 1.0, cx + ww + 0.2, wy - 1.0, cx + ww + 2.2, hem, cx - ww - 2.2, hem), fill=255),
               tint(dress_col, 0.92))
    if coat and not long_body:
        tail = wy + 3.6
        F.part(lambda d, P: d.polygon(P(cx - ww - 0.3, sh + 3, cx + ww + 0.3, sh + 3, cx + ww + 1.2, tail, cx - ww - 1.2, tail), fill=255), coat)

    def torso(d, P):
        d.rounded_rectangle(P(cx - sw, sh, cx + sw, wy), radius=1.6 * S, fill=255)
        d.polygon(P(cx - sw, sh + 1.5, cx + sw, sh + 1.5, cx + ww, wy, cx - ww, wy), fill=255)

    def pattern(d, P):
        if p.get("pattern") == "plaid":
            dk = tint(top, 0.62) + (200,)
            for i in range(-6, 7):
                d.line(P(cx + i * 1.5, sh, cx + i * 1.5, wy), fill=dk, width=int(0.35 * S))
            for j in range(0, 7):
                d.line(P(cx - sw, sh + 0.8 + j * 1.5, cx + sw, sh + 0.8 + j * 1.5), fill=dk, width=int(0.35 * S))
        elif p.get("pattern") == "stripes":
            st = rgb(p["stripe"]) + (255,)
            for j in range(0, 6):
                y = sh + 1.0 + j * 1.45
                d.line(P(cx - sw, y, cx + sw, y), fill=st, width=int(0.6 * S))
    F.part(torso, top, overlay=pattern)

    # coat front panels over the shirt
    if coat and not long_body:
        gap = 0.0 if side else 0.9
        def panels(d, P):
            if side:
                d.rounded_rectangle(P(cx - sw - 0.1, sh, cx + sw + 0.1, wy + 2.2), radius=1.4 * S, fill=255)
            else:
                d.polygon(P(cx - sw - 0.2, sh + 0.2, cx - gap, sh + 1.2, cx - gap * 0.6, wy + 3.4, cx - ww - 1.1, wy + 3.4), fill=255)
                d.polygon(P(cx + sw + 0.2, sh + 0.2, cx + gap, sh + 1.2, cx + gap * 0.6, wy + 3.4, cx + ww + 1.1, wy + 3.4), fill=255)
                d.rectangle(P(cx - sw - 0.2, sh, cx + sw + 0.2, sh + 1.6), fill=255)
        def patch(d, P):
            if p.get("patches"):
                d.rectangle(P(cx - 3.2, wy - 1.5, cx - 1.8, wy), fill=tint(coat, 1.25) + (255,))
                d.rectangle(P(cx + 1.4, sh + 2.6, cx + 2.6, sh + 3.8), fill=tint(coat, 0.7) + (255,))
        F.part(panels, coat, overlay=patch)
        if "buttons" in p and not side:
            for j in range(3):
                F.detail(lambda d, P, j=j: d.ellipse(P(cx - 1.6, sh + 2 + j * 2, cx - 1.0, sh + 2.6 + j * 2), fill=255), p["buttons"])
    elif "buttons" in p and not side:
        for j in range(3):
            F.detail(lambda d, P, j=j: d.ellipse(P(cx - 0.3, sh + 2 + j * 2, cx + 0.3, sh + 2.6 + j * 2), fill=255), p["buttons"])

    if "braces" in p and view != "up" and not coat:
        br = rgb(p["braces"])
        if side:
            F.detail(lambda d, P: d.line(P(cx + 0.2, sh, cx + 0.2, wy), fill=255, width=int(0.75 * S)), br)
        else:
            F.detail(lambda d, P: (d.line(P(cx - 1.9, sh, cx - 1.6, wy), fill=255, width=int(0.75 * S)),
                                   d.line(P(cx + 1.9, sh, cx + 1.6, wy), fill=255, width=int(0.75 * S))), br)
    # belt
    if not long_body and not coat:
        F.detail(lambda d, P: d.rectangle(P(cx - ww - 0.1, wy - 0.7, cx + ww + 0.1, wy + 0.1), fill=255), tint(pants, 0.6), 0.9)

    if "apron" in p and view != "up":
        ap = tint(p["apron"], 0.92)
        y0 = sh + 1.2 if p.get("big") or not long_body else wy - 1.0
        y1 = wy + 5.6 if long_body else wy + 4.2
        x0, x1 = (cx - 2.1, cx + 2.1) if not side else (cx + ww - 0.4, cx + ww + 1.1)
        F.part(lambda d, P: d.rounded_rectangle(P(x0, y0, x1, y1), radius=0.6 * S, fill=255), ap)
    if "shawl" in p:
        sc = rgb(p["shawl"])
        F.part(lambda d, P: d.polygon(P(cx - sw - 0.6, sh - 0.2, cx + sw + 0.6, sh - 0.2, cx + sw * 0.6, sh + 3.4, cx, sh + 5.4, cx - sw * 0.6, sh + 3.4), fill=255), sc)
    if "satchel" in p and view != "up":
        sa = rgb(p["satchel"])
        F.detail(lambda d, P: d.line(P(cx + sw - 0.6, sh + 0.3, cx - ww - 0.2, wy - 0.2), fill=255, width=int(0.6 * S)), tint(sa, 0.8))
        F.part(lambda d, P: d.rounded_rectangle(P(cx - ww - 2.0, wy - 1.8, cx - ww + 0.9, wy + 1.4), radius=0.5 * S, fill=255), sa)

    # ---- near arms
    if action is None:
        if side:
            arm(cx + 0.3, (cx + 0.3 + 1.6 * stride, wy - 0.4), sleeve)
        else:
            swing = 0.55 * stride
            arm(cx - sw + 0.2, (cx - sw - 0.4, wy - 0.4 - swing), sleeve)
            arm(cx + sw - 0.2, (cx + sw + 0.4, wy - 0.4 + swing), sleeve)
    else:
        tool_col = (120, 110, 104)
        if action == 16:   # tool raised over the head
            hand = (cx + 0.2, sh - 4.8)
            arm(cx - sw + 0.2, hand, sleeve)
            arm(cx + sw - 0.2, hand, sleeve)
            F.part(lambda d, P: d.line(P(hand[0], hand[1] + 0.8, hand[0] + 0.4, hand[1] - 4.2), fill=255, width=int(0.6 * S)), (120, 84, 52))
            F.part(lambda d, P: d.rounded_rectangle(P(hand[0] - 1.6, hand[1] - 5.2, hand[0] + 2.2, hand[1] - 3.6), radius=0.3 * S, fill=255), tool_col)
        elif action == 17:  # strike
            hand = (cx + 0.4, wy + 0.8)
            arm(cx - sw + 0.2, hand, sleeve)
            arm(cx + sw - 0.2, hand, sleeve)
            F.part(lambda d, P: d.line(P(hand[0], hand[1], hand[0] + 0.6, hand[1] + 4.0), fill=255, width=int(0.6 * S)), (120, 84, 52))
            F.part(lambda d, P: d.rounded_rectangle(P(hand[0] - 1.4, hand[1] + 3.4, hand[0] + 2.6, hand[1] + 5.0), radius=0.3 * S, fill=255), tool_col)
        elif action == 18:  # crouch, hands to the ground
            arm(cx - sw + 0.2, (cx - 2.2, fy - 2.4), sleeve)
            arm(cx + sw - 0.2, (cx + 2.2, fy - 2.4), sleeve)
        else:               # 19: hands together at work (nets, sewing, carrying)
            arm(cx - sw + 0.2, (cx - 0.9, sh + 4.2), sleeve)
            arm(cx + sw - 0.2, (cx + 0.9, sh + 4.4), sleeve)
            F.part(lambda d, P: d.ellipse(P(cx - 2.2, sh + 4.2, cx + 2.2, sh + 6.0), fill=255), (214, 200, 160))
    if p.get("basket") and action is None and view != "up":
        bx = cx + sw + 0.4 if not side else cx + 1.4
        F.part(lambda d, P: d.ellipse(P(bx - 1.6, wy - 1.0, bx + 1.8, wy + 1.6), fill=255), (150, 110, 62))
        F.detail(lambda d, P: d.arc(P(bx - 1.3, wy - 3.0, bx + 1.5, wy + 0.6), 180, 360, fill=255, width=int(0.4 * S)), (110, 78, 44))
    if p.get("cane") and action is None and view != "up":
        x = cx + sw + 0.6 if not side else cx + 2.2
        F.part(lambda d, P: d.line(P(x, wy - 0.6, x + 0.3, fy), fill=255, width=int(0.55 * S)), (96, 66, 40))

    # ---- neck & head
    F.part(lambda d, P: d.rectangle(P(cx - 0.9, sh - 1.4, cx + 0.9, sh + 0.4), fill=255), tint(skin, 0.85), shade=False)
    hx = cx + (0.5 if side else 0.0)
    rx, ry = g["head_rx"] * (0.92 if side else 1.0), g["head_ry"]
    F.part(lambda d, P: d.ellipse(P(hx - rx, hy - ry, hx + rx, hy + ry), fill=255), skin)
    if side:   # nose and ear
        F.part(lambda d, P: d.ellipse(P(hx + rx - 0.7, hy + 0.2, hx + rx + 0.6, hy + 1.4), fill=255), skin, shade=False)
    # collar pieces
    if "cravat" in p and view == "down":
        F.part(lambda d, P: d.polygon(P(cx - 0.9, sh - 0.2, cx + 0.9, sh - 0.2, cx, sh + 1.8), fill=255), rgb(p["cravat"]), shade=False)
    if p.get("collar") and view == "down":
        F.detail(lambda d, P: d.rectangle(P(cx - 0.7, sh - 0.6, cx + 0.7, sh + 0.3), fill=255), (240, 240, 236))
    if "scarf" in p:
        sc = rgb(p["scarf"])
        F.part(lambda d, P: d.rounded_rectangle(P(cx - 2.2, sh - 1.0, cx + 2.2, sh + 0.9), radius=0.8 * S, fill=255), sc)
        if view != "up":
            F.part(lambda d, P: d.rectangle(P(cx + 0.6, sh + 0.2, cx + 1.8, sh + 3.4), fill=255), tint(sc, 0.9))

    # face
    style = p["hair_style"]
    if view == "down":
        ey = hy + 0.4
        for ex in (hx - 1.35, hx + 1.35):
            F.detail(lambda d, P, ex=ex: d.ellipse(P(ex - 0.42, ey - 0.55, ex + 0.42, ey + 0.55), fill=255), (40, 28, 24))
        F.detail(lambda d, P: d.line(P(hx - 0.6, hy + 2.3, hx + 0.6, hy + 2.3), fill=255, width=int(0.3 * S)), tint(skin, 0.62), 0.8)
        F.detail(lambda d, P: (d.ellipse(P(hx - 2.6, hy + 1.0, hx - 1.4, hy + 1.8), fill=255),
                               d.ellipse(P(hx + 1.4, hy + 1.0, hx + 2.6, hy + 1.8), fill=255)), (226, 130, 120), 0.25)
    elif side:
        F.detail(lambda d, P: d.ellipse(P(hx + 1.3, hy - 0.1, hx + 2.1, hy + 1.0), fill=255), (40, 28, 24))
    if "beard" in p and view != "up":
        bd = rgb(p["beard"])
        if side:
            F.part(lambda d, P: d.chord(P(hx - 1.0, hy - 0.4, hx + rx + 0.3, hy + ry + 0.8), 0, 180, fill=255), bd)
        else:
            F.part(lambda d, P: d.chord(P(hx - rx + 0.2, hy - 1.6, hx + rx - 0.2, hy + ry + 1.0), 10, 170, fill=255), bd)
    if p.get("mustache") and view != "up":
        mx = hx + (1.6 if side else 0)
        F.part(lambda d, P: d.ellipse(P(mx - 1.4, hy + 1.3, mx + 1.4, hy + 2.2), fill=255), rgb(p.get("beard", p["hair"])), shade=False)

    # hair
    def hair_cap(d, P, low):
        d.chord(P(hx - rx - 0.35, hy - ry - 0.4, hx + rx + 0.35, hy + ry + 0.2), 180, 360, fill=255)
        if view == "up":
            d.ellipse(P(hx - rx - 0.3, hy - ry - 0.4, hx + rx + 0.3, hy + ry - 0.2), fill=255)
        elif side:
            d.pieslice(P(hx - rx - 0.4, hy - ry - 0.4, hx + rx + 0.3, hy + ry + 0.4), 150, 330, fill=255)
            d.rounded_rectangle(P(hx - rx - 0.4, hy - 1.0, hx - 0.6, hy + 1.6 + low), radius=0.8 * S, fill=255)
        else:
            d.rectangle(P(hx - rx - 0.35, hy - 0.6, hx - rx + 0.8, hy + low), fill=255)
            d.rectangle(P(hx + rx - 0.8, hy - 0.6, hx + rx + 0.35, hy + low), fill=255)

    if style in ("kerchief", "hood"):
        cloth = rgb(p.get("kerchief", p.get("hood", p["hair"])))
        def scarf(d, P):
            d.ellipse(P(hx - rx - 0.7, hy - ry - 0.7, hx + rx + 0.7, hy + ry * 0.5), fill=255)
            if view == "up" or style == "hood":
                d.rounded_rectangle(P(hx - rx - 0.8, hy - 1, hx + rx + 0.8, hy + ry + 0.8), radius=1.2 * S, fill=255)
        F.part(scarf, cloth)
        if view == "down":   # face opening
            F.part(lambda d, P: d.ellipse(P(hx - rx + 0.8, hy - ry + 2.0, hx + rx - 0.8, hy + ry - 0.2), fill=255), skin)
            ey = hy + 0.4
            for ex in (hx - 1.25, hx + 1.25):
                F.detail(lambda d, P, ex=ex: d.ellipse(P(ex - 0.4, ey - 0.5, ex + 0.4, ey + 0.5), fill=255), (40, 28, 24))
            F.detail(lambda d, P: d.chord(P(hx - rx + 0.4, hy - ry + 0.6, hx + rx - 0.4, hy + 0.2), 180, 360, fill=255), hair, 0.9)
            if "trim" in p:
                F.detail(lambda d, P: d.arc(P(hx - rx + 0.4, hy - ry + 1.6, hx + rx - 0.4, hy + ry + 0.2), 0, 360, fill=255, width=int(0.6 * S)), p["trim"])
        elif side:
            F.part(lambda d, P: d.ellipse(P(hx + 0.2, hy - ry + 2.0, hx + rx + 0.2, hy + ry - 0.4), fill=255), skin)
            F.detail(lambda d, P: d.ellipse(P(hx + 1.3, hy - 0.1, hx + 2.1, hy + 1.0), fill=255), (40, 28, 24))
    else:
        low = {"long": 3.6, "bun": 1.0, "braid": 1.4, "pigtails": 1.2, "messy": 0.9}.get(style, 0.2)
        F.part(lambda d, P: hair_cap(d, P, low), hair)
        if style == "messy" and view != "up":
            fr = 1 if not side else 0
            F.part(lambda d, P: d.polygon(P(hx - 2.8, hy - ry + 0.6, hx - 0.6, hy - ry + 0.4, hx - 1.4, hy - 1.0 + fr * 0.4), fill=255), hair, shade=False)
            F.part(lambda d, P: d.polygon(P(hx - 0.2, hy - ry + 0.4, hx + 2.8, hy - ry + 0.8, hx + 1.4, hy - 1.2 + fr * 0.4), fill=255), hair, shade=False)
        if style == "slick" and view != "up":
            F.detail(lambda d, P: d.arc(P(hx - rx + 0.6, hy - ry + 0.2, hx + rx - 0.6, hy + 1.4), 200, 320, fill=255, width=int(0.35 * S)), tint(hair, 1.6), 0.7)
        if style == "bun":
            F.part(lambda d, P: d.ellipse(P(hx - 1.6 - (0.8 if side else 0), hy - ry - 2.0, hx + 1.6 - (0.8 if side else 0), hy - ry + 1.0), fill=255), hair)
        if style == "braid" and view != "down":
            for j in range(4):
                F.part(lambda d, P, j=j: d.ellipse(P(hx - 2.2 - 0.9, hy + 1 + j * 1.5, hx - 2.2 + 0.9, hy + 2.6 + j * 1.5), fill=255), hair)
        elif style == "braid":
            for j in range(3):
                F.part(lambda d, P, j=j: d.ellipse(P(hx + rx - 1.4, hy + 2 + j * 1.5, hx + rx + 0.4, hy + 3.6 + j * 1.5), fill=255), hair)
        if style == "pigtails":
            for sx in (-1, 1):
                F.part(lambda d, P, sx=sx: d.ellipse(P(hx + sx * (rx + 0.2) - 1.0, hy - 0.4, hx + sx * (rx + 0.2) + 1.0, hy + 3.2), fill=255), hair)

    # hats
    hat = p.get("hat")
    hc = rgb(p.get("hat_col", (30, 30, 34)))
    top_y = hy - ry
    if hat == "tophat":
        F.part(lambda d, P: d.ellipse(P(hx - rx - 1.3, top_y + 0.4, hx + rx + 1.3, top_y + 2.0), fill=255), (24, 24, 30))
        F.part(lambda d, P: d.rounded_rectangle(P(hx - rx + 0.6, top_y - 4.2, hx + rx - 0.6, top_y + 1.3), radius=0.5 * S, fill=255), (30, 30, 38))
        F.detail(lambda d, P: d.rectangle(P(hx - rx + 0.6, top_y + 0.1, hx + rx - 0.6, top_y + 0.8), fill=255), (90, 30, 40))
    elif hat == "knit":
        F.part(lambda d, P: d.chord(P(hx - rx - 0.4, top_y - 1.2, hx + rx + 0.4, hy + ry * 0.6), 180, 360, fill=255), hc)
        F.part(lambda d, P: d.rounded_rectangle(P(hx - rx - 0.5, hy - 1.9, hx + rx + 0.5, hy - 0.5), radius=0.6 * S, fill=255), tint(hc, 0.85))
    elif hat == "cap":
        F.part(lambda d, P: d.chord(P(hx - rx - 0.4, top_y - 0.6, hx + rx + 0.4, hy + 1.4), 180, 360, fill=255), hc)
        if view == "down":
            F.part(lambda d, P: d.chord(P(hx - rx + 0.2, hy - 2.0, hx + rx - 0.2, hy - 0.2), 0, 180, fill=255), tint(hc, 0.75))
        elif side:
            F.part(lambda d, P: d.polygon(P(hx + 1, hy - 1.4, hx + rx + 2.2, hy - 0.8, hx + rx + 1.6, hy - 0.2, hx + 1, hy - 0.4), fill=255), tint(hc, 0.75))
    elif hat in ("souwester", "straw"):
        brim = 6.0 if hat == "straw" else 5.4
        col = (214, 186, 110) if hat == "straw" else hc
        F.part(lambda d, P: d.ellipse(P(hx - brim, top_y + 0.8, hx + brim, top_y + 3.6 + (0.6 if hat == "souwester" else 0)), fill=255), tint(col, 0.92))
        F.part(lambda d, P: d.chord(P(hx - rx + 0.2, top_y - 1.4, hx + rx - 0.2, top_y + 4.4), 180, 360, fill=255), col)
        if hat == "straw":
            F.detail(lambda d, P: d.rectangle(P(hx - rx + 0.4, top_y + 1.2, hx + rx - 0.4, top_y + 1.9), fill=255), (120, 60, 40))

    im = F.image()
    if p.get("child"):
        # children: same style, smaller and with a slightly larger head ratio
        small = im.resize((int(im.width * 0.8), int(im.height * 0.8)), Image.LANCZOS)
        canvas = Image.new("RGBA", im.size, (0, 0, 0, 0))
        canvas.alpha_composite(small, ((im.width - small.width) // 2, im.height - small.height))
        im = canvas
    return im


def frame(p, view, step, action=None):
    if view == "left":
        return ImageOps.mirror(frame(p, "right", step, action))
    big = draw_figure(p, view, step, action)
    return big.resize(OUT, Image.LANCZOS)


def sheet(p):
    fw, fh = OUT
    out = Image.new("RGBA", (fw * 4, fh * 5), (0, 0, 0, 0))
    for r, view in enumerate(("down", "left", "right", "up")):
        for i in range(4):
            out.alpha_composite(frame(p, view, i), (i * fw, r * fh))
    for i, act in enumerate((16, 17, 18, 19)):
        out.alpha_composite(frame(p, "down", 0, act), (i * fw, 4 * fh))
    return out


def bust(p, size=(72, 80)):
    """High-resolution head-and-shoulders crop for dialogue portraits."""
    big = draw_figure(p, "down", 0)
    top = 0.0 if not p.get("child") else 0.2
    box = (int(FW * S * 0.08), int(FH * S * top), int(FW * S * 0.92), int(FH * S * (0.62 + top)))
    return big.crop(box).resize(size, Image.LANCZOS)


if __name__ == "__main__":
    import sys, os
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/people"
    os.makedirs(out, exist_ok=True)
    names = sys.argv[2:] or list(CHARACTERS)
    row = Image.new("RGBA", (OUT[0] * 4 * 3, OUT[1] * 5 * ((len(names) + 2) // 3)), (120, 140, 90, 255))
    for i, n in enumerate(names):
        row.alpha_composite(sheet(CHARACTERS[n]), ((i % 3) * OUT[0] * 4, (i // 3) * OUT[1] * 5))
    row.save(os.path.join(out, "people.png"))
