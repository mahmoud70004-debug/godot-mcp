"""Procedural 20x32 character sprite sheets in the style of the character reference sheet:
big expressive heads, warm shading, selective dark outlines - dressed for Iceland, 1887.

Sheet layout (4 columns x 5 rows):
  row 0 down, row 1 left, row 2 right, row 3 up   -> idle, step A, idle, step B
  row 4 action (facing down): arms up, strike, crouch, hold object
Each character also gets a framed bust portrait for the dialogue box.
"""
from PIL import Image
import numpy as np
from pixel import Spr, c, shade, mix, sheet

FW, FH = 20, 32

SKIN = {"light": c("f2c6a0"), "fair": c("f7d8bd"), "ruddy": c("e9ad86"), "weathered": c("d89c78"), "tan": c("dca27a")}
EYE = c("2b1d1a")

# ---------------------------------------------------------------- cast (period clothing)
CHARACTERS = {
    # reference "eldest son": messy dark hair, maroon plaid shirt -> wool shirt, braces, wool trousers, boots
    "gideon": dict(skin="light", hair=c("4e2c1c"), hair_style="messy", top=c("7d2f45"), pattern="plaid",
                   braces=c("5a3a26"), pants=c("2f3f6b"), shoes=c("4a2c1c")),
    "gideon_outfit": dict(skin="light", hair=c("4e2c1c"), hair_style="messy", top=c("e8dcc2"), coat=c("2f4a78"),
                          scarf=c("a83a3a"), pants=c("2c3346"), shoes=c("3a2418")),
    # reference "mother": green headscarf, green dress, cream apron
    "margaret": dict(skin="fair", hair=c("7a5a44"), hair_style="kerchief", kerchief=c("5f7f4a"), top=c("4f6e44"),
                     dress=True, apron=c("efe3c8"), pants=c("4f6e44"), shoes=c("3a2a20")),
    # reference "little sister": pink hooded coat with white trim
    "clara": dict(skin="fair", hair=c("8a5a3a"), hair_style="hood", hood=c("e07a9a"), top=c("e07a9a"), coat=c("e07a9a"),
                  trim=c("fbf3f0"), pants=c("c9607e"), shoes=c("6a3a2a"), child=True),
    # wealthy cousin: black frock coat, cravat, top hat, gloves
    "elias": dict(skin="fair", hair=c("231a18"), hair_style="slick", top=c("f2eee6"), coat=c("1f2230"), cravat=c("8a2c3a"),
                  buttons=c("d6b14a"), pants=c("1a1c26"), shoes=c("0f0f14"), hat="tophat", gloves=c("cfc8bc")),
    # reference "grandfather": olive coat, knit cap, white beard, cane -> years of hiding
    "edmund": dict(skin="weathered", hair=c("b8b4ae"), hair_style="long", beard=c("d8d4cc"), top=c("6f6a4a"), coat=c("6a5a3a"),
                   patches=True, pants=c("4a4236"), shoes=c("2e2620"), hat="knit", hat_col=c("5a5a3a"), cane=True),
    # reference "aunt": yellow oilskin -> the old fisherman's oilskins and sou'wester
    "bjorn": dict(skin="ruddy", hair=c("e4e0da"), hair_style="short", beard=c("f2efe8"), top=c("3f5a7a"), coat=c("e8b62e"),
                  pants=c("2f3f55"), shoes=c("2a2422"), hat="souwester", hat_col=c("e8b62e")),
    "sigrid": dict(skin="fair", hair=c("b8482a"), hair_style="bun", top=c("2f6a8a"), dress=True, apron=c("f4ede0"),
                   pants=c("2a5a78"), shoes=c("3a2a20"), shawl=c("8a3a3a")),
    # reference "father": grey hair & beard, brown jacket -> the blacksmith's leather apron
    "leif": dict(skin="ruddy", hair=c("8f8a86"), hair_style="short", beard=c("a29c96"), top=c("3f4a5a"), apron=c("6e4428"),
                 pants=c("2f3a5a"), shoes=c("1f1a18"), tool="hammer", big=True),
    "astrid": dict(skin="light", hair=c("d6b46a"), hair_style="braid", top=c("6a8a4a"), dress=True, shawl=c("3f5f3a"),
                   pants=c("5a7a3a"), shoes=c("3a2a20"), basket=True),
    "einar": dict(skin="fair", hair=c("d0ccc6"), hair_style="short", top=c("1f1f28"), cassock=True, collar=True,
                  pants=c("1f1f28"), shoes=c("101010")),
    "runa": dict(skin="light", hair=c("6a3a22"), hair_style="long", top=c("4a68b8"), dress=True, apron=c("f4e8d0"),
                 pants=c("3a56a8"), shoes=c("3a2a20"), scarf=c("e0b84a")),
    "henrik": dict(skin="ruddy", hair=c("4a3424"), hair_style="short", beard=c("4a3424"), mustache=True, top=c("c8b48a"),
                   coat=c("3f6a4a"), pants=c("4a3a2a"), shoes=c("2a2018"), hat="cap", hat_col=c("6a4a2a"), satchel=c("7a5232")),
    # reference "teenage brother": striped knit sweater
    "jonas": dict(skin="light", hair=c("c79a52"), hair_style="messy", top=c("d8d0c0"), pattern="stripes", stripe=c("4a6a9a"),
                  pants=c("4a4a5a"), shoes=c("3a2a20"), hat="knit", hat_col=c("3a5a8a")),
    "halldor": dict(skin="fair", hair=c("f0f0f0"), hair_style="slick", top=c("f2f2f2"), coat=c("23232c"), cravat=c("23232c"),
                    pants=c("23232c"), shoes=c("101010"), mustache=True, beard=c("f0f0f0")),
    "gunnar": dict(skin="weathered", hair=c("8a5a2a"), hair_style="short", top=c("c8b080"), braces=c("4a6a9a"),
                   pants=c("4a5a7a"), shoes=c("3a2a20"), hat="straw"),
    "olafur": dict(skin="light", hair=c("3a2a1a"), hair_style="short", top=c("2a4a8a"), coat=c("2a4a8a"), buttons=c("d6b14a"),
                   pants=c("2a2a3a"), shoes=c("1a1a1a"), hat="cap", hat_col=c("1a2a5a"), mustache=True, satchel=c("7a5232")),
    "worker": dict(skin="ruddy", hair=c("4a3020"), hair_style="short", top=c("8a7a6a"), braces=c("4a3a2a"),
                   pants=c("4a4440"), shoes=c("2a2a2a"), hat="cap", hat_col=c("5a5048")),
}


def lit(col, x, x0, w):
    """Light from the top-left: left third lighter, right third darker."""
    t = (x - x0) / max(1, w - 1)
    if t < 0.25:
        return shade(col, 1.08)
    if t > 0.72:
        return shade(col, 0.82)
    return col


def srect(s, x, y, w, h, col, light=True):
    for xx in range(x, x + w):
        s.r(xx, y, 1, h, lit(col, xx, x, w) if light else col)


def draw(p, d, f, action=None):
    """d: 0 down, 2 right, 3 up (left = mirrored right).  f: walk frame 0..3."""
    s = Spr(FW, FH)
    skin = SKIN[p["skin"]]
    skin_d = shade(skin, 0.86)
    hair = p["hair"]
    hair_d = shade(hair, 0.75)
    hair_l = shade(hair, 1.25)
    top = p["top"]
    pants = p["pants"]
    shoes = p["shoes"]
    child = p.get("child", False)
    side = d == 2
    step = f in (1, 3) and action is None
    bob = -1 if step else 0
    crouch = 2 if action == "crouch" else 0
    oy = (4 if child else 0) + crouch
    HT = 2 + bob + oy                 # top of head
    TY = HT + 13                      # top of torso
    TH = 6 if child else 8            # torso height
    LY = TY + TH                      # legs
    FEET = 30
    robe = p.get("dress") or p.get("cassock")
    coat = p.get("coat")

    # ---- legs & shoes ----------------------------------------------------
    if side:
        if step:
            for lx, lift in ((6, 0 if f == 1 else 1), (11, 1 if f == 1 else 0)):
                srect(s, lx, LY, 3, FEET - 1 - LY - lift, pants)
                s.r(lx, FEET - 1 - lift, 4, 2, shoes)
                s.p(lx + 3, FEET - 1 - lift, shade(shoes, 1.4))
        else:
            srect(s, 8, LY, 4, FEET - 1 - LY, pants)
            s.r(8, FEET - 1, 5, 2, shoes)
            s.p(12, FEET - 1, shade(shoes, 1.4))
    else:
        for i, lx in enumerate((6, 11)):
            lift = 1 if (f == 1 and i == 0) or (f == 3 and i == 1) else 0
            h = max(1, FEET - 1 - LY - lift)
            srect(s, lx, LY, 3, h, pants)
            s.r(lx, FEET - 1 - lift, 3, 2, shoes)
            s.p(lx, FEET - 1 - lift, shade(shoes, 1.45))

    # ---- torso ----------------------------------------------------------
    tx, tw = (6, 8) if side else (5, 10)
    srect(s, tx, TY, tw, TH, top)
    if p.get("pattern") == "plaid":
        for yy in range(TY, TY + TH):
            for xx in range(tx, tx + tw):
                if (xx - tx) % 3 == 1:
                    s.p(xx, yy, shade(s.get(xx, yy), 1.22))
                if (yy - TY) % 3 == 2:
                    s.p(xx, yy, shade(s.get(xx, yy), 0.78))
    if p.get("pattern") == "stripes":
        for yy in range(TY + 1, TY + TH, 2):
            for xx in range(tx, tx + tw):
                s.p(xx, yy, lit(p["stripe"], xx, tx, tw))
    if p.get("braces") and d != 3:
        if side:
            s.vl(tx + 3, TY, TH, p["braces"])
        else:
            s.vl(tx + 2, TY, TH, p["braces"])
            s.vl(tx + tw - 3, TY, TH, p["braces"])
    if coat:
        if side:
            srect(s, tx, TY, tw, TH + 3, coat)
        else:
            srect(s, tx, TY, tw, TH + 3, coat)
            if d == 0:
                s.r(tx + 4, TY, 2, TH + 3, top)          # shirt/lapel opening
                s.vl(tx + 3, TY, TH + 3, shade(coat, 0.72))
                s.vl(tx + 6, TY, TH + 3, shade(coat, 0.72))
                if p.get("buttons"):
                    for by in range(TY + 2, TY + TH + 2, 3):
                        s.p(tx + 6, by, p["buttons"])
        if p.get("trim"):
            s.hl(tx, TY + TH + 2, tw, p["trim"])
        if p.get("patches") and d != 3:
            s.r(tx + 1, TY + 4, 2, 2, shade(coat, 1.3))
            s.p(tx + tw - 2, TY + 2, shade(coat, 0.6))
    if robe:
        rc = p["pants"] if p.get("dress") else top
        for i, yy in enumerate(range(LY - 1, FEET - 1)):
            grow = min(2, i // 2)
            srect(s, tx - grow, yy, tw + grow * 2, 1, rc)
        s.hl(tx - 2, FEET - 2, tw + 4, shade(rc, 0.75))
    if p.get("apron") and d != 3:
        ap = p["apron"]
        if side:
            srect(s, tx + tw - 3, TY + 2, 3, FEET - 3 - TY - 2, ap)
        else:
            srect(s, tx + 2, TY + 2, tw - 4, (FEET - 3) - (TY + 2), ap)
            s.hl(tx + 2, TY + 2, tw - 4, shade(ap, 0.85))
    if p.get("shawl"):
        sh = p["shawl"]
        srect(s, tx - (0 if side else 1), TY, tw + (0 if side else 2), 3, sh)
        if d == 0:
            s.r(tx + tw // 2 - 1, TY + 3, 2, 2, sh)
    if p.get("scarf"):
        sc = p["scarf"]
        s.r(tx, TY, tw, 2, sc)
        if d == 0:
            s.r(tx + 2, TY + 2, 2, 3, sc)
            s.hl(tx, TY + 1, tw, shade(sc, 0.8))
    if p.get("cravat") and d == 0:
        s.r(9, TY, 2, 3, p["cravat"])
    if p.get("collar") and d == 0:
        s.r(9, TY, 2, 1, c("f4f4f4"))
    if p.get("satchel") and d != 3:
        sa = p["satchel"]
        if side:
            s.r(tx + 1, TY + 5, 4, 4, sa)
        else:
            s.line(tx, TY, tx + tw - 1, TY + 6, shade(sa, 0.85))
            s.r(tx + tw - 3, TY + 5, 4, 4, sa)
    # belt line
    if not robe and not coat and not p.get("apron"):
        s.hl(tx, TY + TH - 1, tw, shade(pants, 0.8))

    # ---- arms -----------------------------------------------------------
    sleeve = coat or top
    hand = p.get("gloves") or skin
    if action in ("up", "strike", "hold"):
        if action == "up":
            for ax in (3, 15):
                s.r(ax, TY - 4, 2, 6, shade(sleeve, 0.92))
                s.r(ax, TY - 6, 2, 2, hand)
        elif action == "strike":
            for ax in (4, 14):
                s.r(ax, TY + 1, 2, 5, shade(sleeve, 0.92))
            s.r(8, TY + 6, 4, 2, hand)
        else:  # hold something at the chest
            s.r(4, TY + 1, 2, 4, shade(sleeve, 0.92))
            s.r(14, TY + 1, 2, 4, shade(sleeve, 0.92))
            s.r(6, TY + 3, 8, 4, c("f0e6cc"))
            s.r(6, TY + 3, 8, 1, c("8a5a3a"))
            s.vl(10, TY + 3, 4, c("c8b890"))
            s.p(6, TY + 5, hand)
            s.p(13, TY + 5, hand)
    elif side:
        swing = (1 if f == 1 else -1) if step else 0
        ax = 9 + swing
        srect(s, ax, TY + 1, 3, TH - 2, shade(sleeve, 0.9), light=False)
        s.r(ax, TY + TH - 1, 3, 2, hand)
    else:
        for i, ax in enumerate((3, 15)):
            sw = 0
            if step:
                sw = -1 if (f == 1) == (i == 0) else 0
            s.r(ax, TY + 1 + sw, 2, TH - 2, shade(sleeve, 0.92) if i == 0 else shade(sleeve, 0.8))
            s.r(ax, TY + TH - 1 + sw, 2, 2, hand)
    if p.get("basket") and d != 3 and action is None:
        bx = 15 if not side else 11
        s.r(bx, TY + TH - 1, 4, 3, c("b0844a"))
        s.hl(bx, TY + TH - 1, 4, c("6a9a4a"))
    if p.get("cane") and d != 3 and action is None:
        cx = 16 if not side else 14
        s.vl(cx, TY + 4, FEET - TY - 4, c("6a4a2a"))

    # ---- head -----------------------------------------------------------
    hx, hw = (5, 12) if side else (3, 14)
    srect(s, hx + 1, HT + 2, hw - 2, 11, skin)
    s.r(hx, HT + 4, hw, 7, skin)
    s.hl(hx + 2, HT + 12, hw - 4, skin_d)
    style = p["hair_style"]

    def hair_cap(depth):
        s.r(hx + 1, HT, hw - 2, depth, hair)
        s.r(hx, HT + 1, hw, depth - 1, hair)
        for xx in range(hx + 2, hx + hw - 3):
            if xx % 3 == 0:
                s.p(xx, HT + 1, hair_l)
        s.hl(hx + 3, HT, 4, hair_l)

    if d == 3:
        if style not in ("bald", "hood", "kerchief"):
            hair_cap(4)
            s.r(hx, HT + 4, hw, 8 if style != "long" else 12, hair)
            for xx in range(hx + 1, hx + hw - 1, 2):
                s.vl(xx, HT + 5, 6, hair_d)
            if style == "bun":
                s.r(hx + 4, HT - 2, 6, 3, hair_d)
            if style == "braid":
                s.r(hx + hw // 2 - 1, HT + 11, 2, 6, hair)
                s.p(hx + hw // 2 - 1, HT + 17, c("8a3a3a"))
        elif style == "bald":
            s.r(hx, HT + 6, hw, 5, hair)
    elif style not in ("bald", "hood", "kerchief"):
        if style == "messy":
            hair_cap(4)
            for i, xx in enumerate(range(hx, hx + hw)):
                depth = (3, 5, 4, 6, 4, 5, 3, 5, 6, 4, 5, 3, 4, 3)[i % 14]
                if side and xx > hx + hw - 5:
                    depth = 3
                s.r(xx, HT + 3, 1, depth - 2, hair)
            s.p(hx + 4, HT - 1, hair)
            s.p(hx + 8, HT - 1, hair)
        elif style == "slick":
            hair_cap(4)
            s.r(hx, HT + 3, hw // 2, 1, hair)
            s.hl(hx + 2, HT + 1, hw - 5, hair_l)
        else:
            hair_cap(4)
            s.r(hx, HT + 3, hw, 1, hair)
            s.r(hx + 1, HT + 4, 3, 1, hair)
        if side:
            back = hx
            s.r(back, HT + 2, 6, 7, hair)
            s.vl(back + 1, HT + 4, 4, hair_d)
        else:
            s.r(hx, HT + 3, 2, 6, hair)
            s.r(hx + hw - 2, HT + 3, 2, 6, hair)
        if style == "long":
            if side:
                s.r(hx, HT + 6, 5, 11, hair)
                s.vl(hx + 2, HT + 7, 9, hair_d)
            else:
                s.r(hx - 1, HT + 4, 3, 13, hair)
                s.r(hx + hw - 2, HT + 4, 3, 13, hair)
                s.vl(hx, HT + 6, 10, hair_d)
                s.vl(hx + hw - 1, HT + 6, 10, hair_d)
        if style == "braid":
            if side:
                s.r(hx, HT + 8, 3, 9, hair)
                for yy in range(HT + 9, HT + 17, 2):
                    s.p(hx + 1, yy, hair_d)
            else:
                s.r(hx + hw - 2, HT + 8, 3, 10, hair)
                for yy in range(HT + 9, HT + 18, 2):
                    s.p(hx + hw - 1, yy, hair_d)
                s.p(hx + hw - 1, HT + 18, c("8a3a3a"))
        if style == "bun":
            if side:
                s.r(hx - 2, HT + 1, 4, 4, hair_d)
                s.r(hx - 1, HT + 2, 2, 2, hair)
            else:
                s.r(hx + 4, HT - 3, 6, 4, hair)
                s.hl(hx + 5, HT - 3, 3, hair_l)
    elif style == "bald":
        if side:
            s.r(hx, HT + 5, 3, 5, hair)
        else:
            s.r(hx, HT + 5, 2, 5, hair)
            s.r(hx + hw - 2, HT + 5, 2, 5, hair)
        s.p(hx + 4, HT + 2, shade(skin, 1.12))

    if style == "kerchief":
        k = p["kerchief"]
        s.r(hx, HT, hw, 5, k)
        s.r(hx - (0 if side else 1), HT + 2, hw + (0 if side else 2), 3, k)
        for xx in range(hx + 1, hx + hw - 1, 3):
            s.p(xx, HT + 1, shade(k, 1.25))
        if d == 3:
            s.r(hx, HT, hw, 12, k)
            s.r(hx + hw // 2 - 2, HT + 12, 4, 2, shade(k, 0.8))
        elif side:
            s.r(hx, HT, 7, 11, k)
            s.r(hx + 1, HT + 11, 3, 2, shade(k, 0.8))
        else:
            s.r(hx, HT + 3, 2, 9, k)
            s.r(hx + hw - 2, HT + 3, 2, 9, k)
            s.r(hx + 1, HT + 4, hw - 2, 1, hair)
    if style == "hood":
        k = p["hood"]
        trim = p.get("trim", c("ffffff"))
        if d == 3:
            s.r(hx - 1, HT - 1, hw + 2, 14, k)
            s.vl(hx + hw // 2, HT, 12, shade(k, 0.8))
        elif side:
            s.r(hx - 1, HT - 1, 9, 14, k)
            s.r(hx + 7, HT - 1, 5, 4, k)
            s.vl(hx + 8, HT + 2, 10, trim)
        else:
            s.r(hx - 1, HT - 1, hw + 2, 4, k)
            s.r(hx - 1, HT + 3, 3, 10, k)
            s.r(hx + hw - 2, HT + 3, 3, 10, k)
            s.hl(hx + 1, HT + 3, hw - 2, trim)
            s.vl(hx + 2, HT + 3, 9, trim)
            s.vl(hx + hw - 3, HT + 3, 9, trim)
            s.r(hx + 3, HT + 4, hw - 6, 2, hair)
            s.r(hx + hw // 2 - 1, HT - 2, 2, 2, trim)  # pompom

    # ---- face ----
    if d == 0:
        ey = HT + 7
        for ex in (hx + 3, hx + hw - 5):
            s.r(ex, ey, 2, 3, EYE)
            s.p(ex + 1, ey, c("f6f2ea"))
        if style not in ("hood", "kerchief", "messy"):
            s.hl(hx + 3, ey - 2, 2, hair_d)
            s.hl(hx + hw - 5, ey - 2, 2, hair_d)
        s.p(hx + 2, ey + 3, c("e89a90"))
        s.p(hx + hw - 3, ey + 3, c("e89a90"))
        s.p(hx + hw // 2, ey + 3, skin_d)
        s.hl(hx + hw // 2 - 1, ey + 4, 2, c("a8544a"))
    elif side:
        ey = HT + 7
        ex = hx + hw - 4
        s.r(ex, ey, 2, 3, EYE)
        s.p(ex, ey, c("f6f2ea"))
        s.p(hx + hw, ey + 2, skin)
        s.p(hx + hw - 2, ey + 4, c("a8544a"))
        s.r(hx + 5, ey + 1, 2, 2, skin_d)  # ear
        s.p(hx + hw - 3, ey + 3, c("e89a90"))
    if p.get("beard") and d != 3:
        b = p["beard"]
        bd = shade(b, 0.82)
        if side:
            s.r(hx + 5, HT + 9, 7, 4, b)
            s.r(hx + 7, HT + 13, 4, 2, b)
            s.p(hx + 8, HT + 11, bd)
        else:
            s.r(hx + 1, HT + 9, hw - 2, 4, b)
            s.r(hx + 3, HT + 13, hw - 6, 2, b)
            for xx in range(hx + 2, hx + hw - 2, 2):
                s.p(xx, HT + 11, bd)
            s.hl(hx + hw // 2 - 1, HT + 10, 2, c("8a4a40"))
    elif p.get("mustache") and d == 0:
        s.r(hx + 4, HT + 10, hw - 8, 1, p.get("beard", hair_d))

    # ---- hats ----
    hat = p.get("hat")
    hc = p.get("hat_col", c("4a4a4a"))
    if hat == "tophat":
        hc = c("16161c")
        srect(s, hx + 2, HT - 6, hw - 4, 7, hc)
        s.hl(hx + 2, HT - 2, hw - 4, c("6a2a3a"))
        s.r(hx - 1, HT + 1, hw + 2, 1, hc)
        s.hl(hx + 3, HT - 6, 3, c("3a3a48"))
    elif hat == "souwester":
        srect(s, hx + 1, HT - 2, hw - 2, 5, hc)
        s.r(hx - 2, HT + 3, hw + 4, 1, shade(hc, 0.82))
        s.hl(hx + 2, HT - 2, 4, shade(hc, 1.2))
        if d == 0:
            s.p(hx + hw - 2, HT + 12, shade(hc, 0.7))  # chin strap
    elif hat == "cap":
        srect(s, hx, HT - 1, hw, 4, hc)
        if d == 0:
            s.r(hx + 1, HT + 3, hw - 2, 1, shade(hc, 0.7))
        elif side:
            s.r(hx + hw - 2, HT + 2, 4, 1, shade(hc, 0.7))
    elif hat == "knit":
        srect(s, hx, HT - 1, hw, 5, hc)
        s.hl(hx, HT + 3, hw, shade(hc, 0.75))
        for xx in range(hx + 1, hx + hw, 2):
            s.p(xx, HT + 1, shade(hc, 1.2))
        s.r(hx + hw // 2 - 1, HT - 3, 3, 2, shade(hc, 1.3))
    elif hat == "straw":
        st = c("e2c66a")
        srect(s, hx + 2, HT - 2, hw - 4, 4, st)
        s.r(hx - 2, HT + 2, hw + 4, 1, shade(st, 0.85))
        s.hl(hx + 2, HT + 1, hw - 4, c("a0402a"))

    # tool in hand for action frames
    if action in ("up", "strike") and p.get("tool") or action in ("up", "strike") and p.get("is_player"):
        if action == "up":
            s.r(15, TY - 12, 2, 6, c("8a5a32"))
            s.r(13, TY - 13, 6, 3, c("8a8a96"))
        else:
            s.r(10, TY + 7, 2, 5, c("8a5a32"))
            s.r(8, TY + 11, 6, 3, c("8a8a96"))

    selective_outline(s)
    return s


def selective_outline(s):
    """Outline each opaque region with a darkened copy of its own colour (sel-out)."""
    a = np.array(s.im).astype(np.int16)
    m = a[:, :, 3] > 0
    out = a.copy()
    h, w = m.shape
    for y in range(h):
        for x in range(w):
            if m[y, x]:
                continue
            best = None
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and m[yy, xx]:
                    best = a[yy, xx]
                    break
            if best is not None:
                col = (best[:3] * 0.32 + np.array([18, 10, 12])).clip(0, 255)
                out[y, x] = [col[0], col[1], col[2], 255]
    s.im = Image.fromarray(out.astype(np.uint8))
    from PIL import ImageDraw
    s.d = ImageDraw.Draw(s.im)


def make_sheet(p):
    frames = []
    for d in range(4):
        for f in range(4):
            if d == 1:
                frames.append(draw(p, 2, f).flip())
            else:
                frames.append(draw(p, d, f))
    for act in ("up", "strike", "crouch", "hold"):
        frames.append(draw(p, 0, 0, action=act))
    return sheet(frames, 4), frames[0]


def portrait(p, idle):
    """Bust portrait in a wooden frame, like the reference sheet."""
    head = idle.im.crop((0, 0, FW, 23))
    inner = Image.new("RGBA", (FW + 4, 25), (226, 206, 168, 255))
    # soft background vignette
    px = inner.load()
    for y in range(inner.height):
        for x in range(inner.width):
            t = ((x - inner.width / 2) ** 2 + (y - 8) ** 2) ** 0.5 / 18
            base = (236, 220, 186) if t < 0.8 else (214, 190, 150)
            px[x, y] = base + (255,)
    off = 4 if p.get("child") else 0
    inner.alpha_composite(head, (2, 2 - off if off else 2))
    big = inner.resize((inner.width * 4, inner.height * 4), Image.NEAREST)
    framed = Image.new("RGBA", (big.width + 12, big.height + 12), (120, 74, 40, 255))
    from PIL import ImageDraw
    d = ImageDraw.Draw(framed)
    d.rectangle([0, 0, framed.width - 1, framed.height - 1], outline=(70, 40, 22, 255), width=3)
    d.rectangle([4, 4, framed.width - 5, framed.height - 5], outline=(168, 112, 62, 255), width=1)
    framed.alpha_composite(big, (6, 6))
    return framed


def build(out_dir):
    meta = {}
    for name, p in CHARACTERS.items():
        if name.startswith("gideon"):
            p = dict(p, is_player=True)
        sh, idle = make_sheet(p)
        sh.save(f"{out_dir}/chars/{name}.png")
        portrait(p, idle).save(f"{out_dir}/portraits/{name}.png")
        meta[name] = {"frame_w": FW, "frame_h": FH, "rows": 5}
    return meta
