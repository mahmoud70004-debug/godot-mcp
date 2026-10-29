"""Small pixel-art drawing helpers shared by the asset generators.

Everything in the game is drawn procedurally from these primitives so the art
stays consistent and can be regenerated (python3 tools/build_assets.py).
"""
from PIL import Image, ImageDraw
import numpy as np
import random

OUTLINE = (42, 30, 32, 255)


def c(hexstr, a=255):
    hexstr = hexstr.lstrip("#")
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), a)


def shade(col, f):
    """Multiply rgb by f (f<1 darker, f>1 lighter)."""
    return tuple(max(0, min(255, int(v * f))) for v in col[:3]) + (col[3] if len(col) > 3 else 255,)


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3)) + (255,)


class Spr:
    def __init__(self, w, h, seed=0):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.rng = random.Random(seed)

    # --- primitives -------------------------------------------------------
    def r(self, x, y, w, h, col):
        if w <= 0 or h <= 0:
            return
        self.d.rectangle([x, y, x + w - 1, y + h - 1], fill=col)

    def p(self, x, y, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((int(x), int(y)), col)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.im.getpixel((int(x), int(y)))
        return (0, 0, 0, 0)

    def hl(self, x, y, w, col):
        self.r(x, y, w, 1, col)

    def vl(self, x, y, h, col):
        self.r(x, y, 1, h, col)

    def poly(self, pts, col):
        self.d.polygon(pts, fill=col)

    def ell(self, x, y, w, h, col):
        self.d.ellipse([x, y, x + w - 1, y + h - 1], fill=col)

    def line(self, x0, y0, x1, y1, col, width=1):
        self.d.line([x0, y0, x1, y1], fill=col, width=width)

    def speckle(self, x, y, w, h, cols, density, only_opaque=True):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if self.rng.random() < density:
                    if only_opaque and self.get(xx, yy)[3] == 0:
                        continue
                    self.p(xx, yy, self.rng.choice(cols))

    def outline(self, col=OUTLINE):
        a = np.array(self.im)
        m = a[:, :, 3] > 0
        d = np.zeros_like(m)
        d[1:, :] |= m[:-1, :]
        d[:-1, :] |= m[1:, :]
        d[:, 1:] |= m[:, :-1]
        d[:, :-1] |= m[:, 1:]
        edge = d & ~m
        a[edge] = col
        self.im = Image.fromarray(a)
        self.d = ImageDraw.Draw(self.im)

    def shadow(self, x, y, w, h, alpha=70):
        """Soft drop shadow ellipse drawn *behind* existing pixels."""
        sh = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([x, y, x + w - 1, y + h - 1], fill=(20, 30, 40, alpha))
        sh.alpha_composite(self.im)
        self.im = sh
        self.d = ImageDraw.Draw(self.im)

    def paste(self, other, x, y):
        self.im.alpha_composite(other.im if isinstance(other, Spr) else other, (int(x), int(y)))

    def flip(self):
        s = Spr(self.w, self.h)
        s.im = self.im.transpose(Image.FLIP_LEFT_RIGHT)
        s.d = ImageDraw.Draw(s.im)
        return s

    def save(self, path):
        self.im.save(path)


def sheet(frames, cols):
    """Pack equally sized Spr frames into a sheet image."""
    fw, fh = frames[0].w, frames[0].h
    rows = (len(frames) + cols - 1) // cols
    out = Image.new("RGBA", (fw * cols, fh * rows), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f.im, ((i % cols) * fw, (i // cols) * fh))
    return out
