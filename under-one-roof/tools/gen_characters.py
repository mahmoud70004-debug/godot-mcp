"""Procedural 16x28 character sprite sheets (4 walk frames x 4 directions).

Sheet layout: rows = down, left, right, up; columns = idle, step A, idle, step B.
Also writes a scaled-up face portrait per character for the dialogue box.
"""
from PIL import Image
from pixel import Spr, c, shade, sheet

FW, FH = 16, 28

SKIN = {"light": c("f2c9a0"), "fair": c("f6d7b8"), "ruddy": c("e8b08a"), "weathered": c("d9a07a")}

# Every character in the story concept (plus a few extras the scenes need).
CHARACTERS = {
    "gideon":  dict(skin="light", hair=c("5a3a26"), hair_style="short", top=c("e9dcc0"), vest=c("7a4e2d"), pants=c("3e4a5e"), shoes=c("3a2a22")),
    "gideon_outfit": dict(skin="light", hair=c("5a3a26"), hair_style="short", top=c("e9dcc0"), coat=c("2f4f7f"), pants=c("2e3440"), shoes=c("2a1e18")),
    "margaret": dict(skin="fair", hair=c("8a7262"), hair_style="bun", top=c("7a5a8a"), dress=True, shawl=c("b98a5a"), pants=c("5a4466"), shoes=c("3a2a22")),
    "clara":   dict(skin="fair", hair=c("e8c060"), hair_style="pigtails", top=c("e88aa0"), dress=True, pants=c("c06a80"), shoes=c("5a3a2a"), child=True),
    "elias":   dict(skin="fair", hair=c("2a2220"), hair_style="short", top=c("2a2a34"), coat=c("1e1e28"), pants=c("1a1a22"), shoes=c("0e0e12"), hat="tophat", gloves=c("4a3428")),
    "edmund":  dict(skin="weathered", hair=c("a8a8a8"), hair_style="long", beard=c("9a9a9a"), top=c("6a5a46"), coat=c("5a4a38"), pants=c("4a4036"), shoes=c("2e2620")),
    "bjorn":   dict(skin="ruddy", hair=c("e0e0e0"), hair_style="short", beard=c("eeeeee"), top=c("e8c23a"), coat=c("e0b42a"), pants=c("3a4a5a"), shoes=c("2a2a2a"), hat="souwester"),
    "sigrid":  dict(skin="fair", hair=c("c0502a"), hair_style="bun", top=c("3a6a8a"), dress=True, apron=c("f0ece0"), pants=c("2e5a78"), shoes=c("3a2a22")),
    "leif":    dict(skin="ruddy", hair=c("6a4028"), hair_style="bald", beard=c("6a4028"), top=c("8a6a5a"), apron=c("5a3a28"), pants=c("3a3430"), shoes=c("222222")),
    "astrid":  dict(skin="light", hair=c("d8b878"), hair_style="long", top=c("6a8a4a"), dress=True, shawl=c("4a6a3a"), pants=c("5a7a3a"), shoes=c("3a2a22")),
    "einar":   dict(skin="fair", hair=c("cfcfcf"), hair_style="short", top=c("22222a"), cassock=True, collar=True, pants=c("22222a"), shoes=c("111111")),
    "runa":    dict(skin="light", hair=c("7a4a2a"), hair_style="long", top=c("4a6ac0"), dress=True, apron=c("f4e8d0"), pants=c("3a56a8"), shoes=c("3a2a22")),
    "henrik":  dict(skin="ruddy", hair=c("4a3a2a"), hair_style="short", beard=c("4a3a2a"), mustache=True, top=c("4a7a5a"), coat=c("3a6a4a"), pants=c("4a3a2a"), shoes=c("2a2018"), hat="cap", hat_col=c("6a4a2a")),
    "jonas":   dict(skin="light", hair=c("f0d070"), hair_style="short", top=c("c04a3a"), pants=c("4a5a7a"), shoes=c("3a2a22"), hat="knit", hat_col=c("3a6aa0")),
    "halldor": dict(skin="fair", hair=c("f0f0f0"), hair_style="short", top=c("f0f0f0"), coat=c("22222a"), pants=c("22222a"), shoes=c("111111"), mustache=True, beard=c("f0f0f0")),
    "gunnar":  dict(skin="weathered", hair=c("8a5a2a"), hair_style="short", top=c("c8b080"), vest=c("4a6a9a"), pants=c("4a6a9a"), shoes=c("3a2a22"), hat="straw"),
    "olafur":  dict(skin="light", hair=c("3a2a1a"), hair_style="short", top=c("2a4a8a"), coat=c("2a4a8a"), pants=c("2a2a3a"), shoes=c("1a1a1a"), hat="cap", hat_col=c("1a2a5a"), mustache=True),
    "worker":  dict(skin="ruddy", hair=c("4a3020"), hair_style="short", top=c("8a7a6a"), vest=c("5a4a3a"), pants=c("4a4440"), shoes=c("2a2a2a"), hat="cap", hat_col=c("5a5048")),
}


def draw(p, d, f):
    """d: 0 down, 1 left, 2 right, 3 up.  f: frame 0..3."""
    s = Spr(FW, FH)
    skin = SKIN[p["skin"]]
    skin_d = shade(skin, 0.85)
    hair = p["hair"]
    hair_d = shade(hair, 0.8)
    top = p["top"]
    pants = p["pants"]
    shoes = p["shoes"]
    step = f in (1, 3)
    child = p.get("child", False)
    bob = -1 if step else 0
    oy = 3 if child else 0  # children are shorter
    HY = 5 + bob + oy       # head top
    TY = HY + 10            # torso top
    TH = 5 if child else 7  # torso height
    LY = TY + TH            # legs top
    leg_len = (25 - LY) if not child else (25 - LY)
    side = d in (1, 2)

    # ---- legs & shoes ---------------------------------------------------
    long_robe = p.get("cassock") or p.get("dress")
    if side:
        if step:
            # legs apart
            for lx, lift in ((5, 0 if f == 1 else 1), (9, 1 if f == 1 else 0)):
                s.r(lx, LY, 2, 25 - LY - lift, pants)
                s.r(lx, 25 - lift, 3, 2, shoes)
        else:
            s.r(6, LY, 3, 25 - LY, pants)
            s.r(6, 25, 4, 2, shoes)
    else:
        for i, lx in enumerate((5, 9)):
            lift = 1 if (f == 1 and i == 0) or (f == 3 and i == 1) else 0
            s.r(lx, LY, 2, 25 - LY - lift, pants)
            s.r(lx, 25 - lift, 2, 2, shoes)

    # ---- torso ----------------------------------------------------------
    tx, tw = (5, 6) if side else (4, 8)
    s.r(tx, TY, tw, TH, top)
    if p.get("vest") and d != 3:
        v = p["vest"]
        if side:
            s.r(tx, TY, tw, TH, v)
            s.vl(tx + (tw - 2 if d == 2 else 1), TY, TH, top)
        else:
            s.r(tx, TY, 3, TH, v)
            s.r(tx + 5, TY, 3, TH, v)
    elif p.get("vest"):
        s.r(tx, TY, tw, TH, p["vest"])
    if p.get("coat"):
        co = p["coat"]
        s.r(tx, TY, tw, TH, co)
        # coat tails over the legs
        s.r(tx, LY, tw, 2, co)
        if d == 0:
            s.vl(tx + tw // 2, TY + 1, TH + 1, shade(co, 0.75))
            s.r(tx + 3, TY, 2, 2, top)  # shirt collar
    if long_robe:
        robe = p["pants"] if p.get("dress") else top
        # skirt widening towards the hem
        for i, yy in enumerate(range(LY - 1, 25)):
            grow = min(2, i // 2)
            s.r(tx - grow, yy, tw + grow * 2, 1, robe)
        s.hl(tx - 2, 24, tw + 4, shade(robe, 0.8))
    if p.get("apron") and d != 3:
        ap = p["apron"]
        if side:
            ax = tx + (tw - 3 if d == 2 else 0)
            s.r(ax, TY + 2, 3, 25 - TY - 3, ap)
        else:
            s.r(tx + 1, TY + 2, tw - 2, 25 - TY - 3, ap)
    if p.get("shawl"):
        s.r(tx - (0 if side else 1), TY, tw + (0 if side else 2), 2, p["shawl"])
    if p.get("collar") and d == 0:
        s.r(7, TY, 2, 1, c("f4f4f4"))
    s.hl(tx, TY + TH - 1, tw, shade(s.get(tx + 1, TY + TH - 1), 0.85)) if not long_robe else None

    # ---- arms -----------------------------------------------------------
    sleeve = p.get("coat") or top
    hand = p.get("gloves") or skin
    if side:
        swing = (1 if f == 1 else -1) if step else 0
        ax = 7 + swing
        s.r(ax, TY + 1, 2, TH - 2, shade(sleeve, 0.9))
        s.r(ax, TY + TH - 1, 2, 1, hand)
    else:
        for i, ax in enumerate((3, 12)):
            sw = 0
            if step:
                sw = -1 if (f == 1) == (i == 0) else 0
            s.r(ax, TY + 1 + sw, 1, TH - 2, shade(sleeve, 0.9))
            s.p(ax, TY + TH - 1 + sw, hand)

    # ---- head -----------------------------------------------------------
    if side:
        hx, hw = 4, 9
    else:
        hx, hw = 3, 10
    s.r(hx, HY + 1, hw, 9, skin)
    s.r(hx + 1, HY, hw - 2, 1, skin)
    s.hl(hx, HY + 9, hw, skin_d)
    style = p["hair_style"]
    if d == 3:
        if style != "bald":
            s.r(hx, HY, hw, 9, hair)
            s.r(hx + 1, HY - 1 if style == "bun" else HY, hw - 2, 1, hair)
            s.hl(hx + 1, HY + 8, hw - 2, hair_d)
        else:
            s.r(hx, HY + 4, hw, 4, hair)
    elif style != "bald":
        s.r(hx, HY, hw, 3, hair)
        s.hl(hx + 1, HY - 1, hw - 2, hair)
        if side:
            back = hx if d == 2 else hx + hw - 4
            s.r(back, HY, 4, 7, hair)
        else:
            s.r(hx, HY, 1, 6, hair)
            s.r(hx + hw - 1, HY, 1, 6, hair)
            s.r(hx + 1, HY + 3, 2, 1, hair)  # fringe
    else:
        if side:
            back = hx if d == 2 else hx + hw - 2
            s.r(back, HY + 4, 2, 3, hair)
        else:
            s.r(hx, HY + 4, 1, 3, hair)
            s.r(hx + hw - 1, HY + 4, 1, 3, hair)
    if style == "long":
        if side:
            back = hx if d == 2 else hx + hw - 3
            s.r(back, HY + 3, 3, 9, hair)
        elif d == 0:
            s.r(hx - 1, HY + 2, 2, 9, hair)
            s.r(hx + hw - 1, HY + 2, 2, 9, hair)
        else:
            s.r(hx, HY + 2, hw, 10, hair)
    if style == "bun":
        if d == 3:
            s.r(hx + 3, HY - 2, 4, 3, hair_d)
        elif side:
            back = hx - 1 if d == 2 else hx + hw - 2
            s.r(back, HY + 1, 3, 3, hair_d)
        else:
            s.r(hx + 3, HY - 2, 4, 2, hair_d)
    if style == "pigtails":
        if d == 0 or d == 3:
            s.r(hx - 2, HY + 3, 2, 4, hair)
            s.r(hx + hw, HY + 3, 2, 4, hair)
        else:
            back = hx - 2 if d == 2 else hx + hw
            s.r(back, HY + 3, 2, 4, hair)

    # face
    eye = c("2a2030")
    if d == 0:
        s.r(hx + 2, HY + 5, 1, 2, eye)
        s.r(hx + hw - 3, HY + 5, 1, 2, eye)
        s.p(hx + 1, HY + 7, shade(skin, 0.93))
        s.p(hx + hw - 2, HY + 7, shade(skin, 0.93))
    elif side:
        ex = hx + hw - 3 if d == 2 else hx + 2
        s.r(ex, HY + 5, 1, 2, eye)
        nose = hx + hw if d == 2 else hx - 1
        s.p(nose, HY + 6, skin)
    if p.get("beard") and d != 3:
        b = p["beard"]
        if side:
            bx = hx + 3 if d == 2 else hx
            s.r(bx, HY + 7, 6, 3, b)
            s.r(bx + (3 if d == 2 else 0), HY + 10, 3, 1, b)
        else:
            s.r(hx + 1, HY + 7, hw - 2, 3, b)
            s.r(hx + 3, HY + 10, hw - 6, 1, b)
            if not p.get("mustache"):
                s.r(hx + 4, HY + 8, hw - 8, 1, shade(skin, 0.8))
    elif p.get("mustache") and d == 0:
        s.r(hx + 3, HY + 7, hw - 6, 1, p.get("beard", hair_d))

    # hats
    hat = p.get("hat")
    if hat == "tophat":
        hc = c("16161c")
        s.r(hx + 1, HY - 5, hw - 2, 6, hc)
        s.r(hx - 1, HY + 1, hw + 2, 1, hc)
        s.r(hx + 1, HY - 1, hw - 2, 1, c("6a2a3a"))
    elif hat == "souwester":
        hc = c("e8c23a")
        s.r(hx + 1, HY - 2, hw - 2, 4, hc)
        s.r(hx - 2, HY + 2, hw + 4, 1, shade(hc, 0.85))
    elif hat == "cap":
        hc = p.get("hat_col", c("4a4a4a"))
        s.r(hx, HY - 1, hw, 3, hc)
        if d == 0:
            s.r(hx + 1, HY + 2, hw - 2, 1, shade(hc, 0.7))
        elif side:
            s.r(hx + (hw - 1 if d == 2 else -2), HY + 1, 3, 1, shade(hc, 0.7))
    elif hat == "knit":
        hc = p.get("hat_col", c("3a6aa0"))
        s.r(hx, HY - 1, hw, 4, hc)
        s.hl(hx, HY + 2, hw, shade(hc, 0.8))
        s.r(hx + hw // 2 - 1, HY - 3, 2, 2, c("f0f0f0"))
    elif hat == "straw":
        hc = c("e2c66a")
        s.r(hx + 1, HY - 2, hw - 2, 3, hc)
        s.r(hx - 2, HY + 1, hw + 4, 1, shade(hc, 0.85))
        s.hl(hx + 1, HY, hw - 2, c("a0402a"))

    if d == 1:
        # left facing sprites are drawn as right then mirrored; nothing extra
        pass
    s.outline()
    return s


def make_sheet(p):
    frames = []
    for d in range(4):
        for f in range(4):
            if d == 1:
                frames.append(draw(p, 2, f).flip())
            else:
                frames.append(draw(p, d, f))
    return sheet(frames, 4), frames[0]


def portrait(idle):
    head = idle.im.crop((0, 0, 16, 18))
    big = head.resize((16 * 5, 18 * 5), Image.NEAREST)
    return big


def build(out_dir):
    meta = {}
    for name, p in CHARACTERS.items():
        sh, idle = make_sheet(p)
        sh.save(f"{out_dir}/chars/{name}.png")
        portrait(idle).save(f"{out_dir}/portraits/{name}.png")
        meta[name] = {"frame_w": FW, "frame_h": FH}
    return meta
