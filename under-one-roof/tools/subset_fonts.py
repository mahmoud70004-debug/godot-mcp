"""Subsets the Japanese fonts to the characters the game actually uses (keeps the APK small).

Sources (OFL, Google Fonts) are downloaded into tools/fonts_src/ when missing.
Usage: python3 tools/subset_fonts.py   (needs fonttools)
"""
import json, os, urllib.request
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "fonts_src")
URLS = {
    "NotoSansJP.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf",
    "NotoSerifJP.ttf": "https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifjp/NotoSerifJP%5Bwght%5D.ttf",
}


def chars():
    text = ""
    p = os.path.join(ROOT, "data", "i18n", "ja.json")
    if os.path.exists(p):
        text += "".join(json.load(open(p, encoding="utf-8")).values())
    # kana, common punctuation, digits and Latin so any UI string renders
    text += "".join(chr(c) for c in range(0x3000, 0x30FF + 1))
    text += "".join(chr(c) for c in range(0xFF01, 0xFF5E + 1))
    text += "".join(chr(c) for c in range(0x20, 0x7F))
    text += "日本語設定音楽言語再生停止音量効果振動文字速度全画面初期化閉戻続新遊村謎郷愁"
    return "".join(sorted(set(text)))


def make(src_name, out_name, weight):
    os.makedirs(SRC, exist_ok=True)
    src = os.path.join(SRC, src_name)
    if not os.path.exists(src):
        urllib.request.urlretrieve(URLS[src_name], src)
    font = TTFont(src)
    font = instancer.instantiateVariableFont(font, {"wght": weight})
    opts = subset.Options()
    opts.layout_features = ["*"]
    s = subset.Subsetter(opts)
    s.populate(text=chars())
    s.subset(font)
    out = os.path.join(ROOT, "assets", "fonts", out_name)
    font.save(out)
    print(out_name, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    make("NotoSansJP.ttf", "NotoSansJP-subset.ttf", 500)
    make("NotoSerifJP.ttf", "NotoSerifJP-subset.ttf", 700)
