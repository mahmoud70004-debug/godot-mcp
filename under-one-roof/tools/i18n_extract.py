"""Collect every Arabic source string the game can display (story, UI scripts, world data).

Writes data/i18n/strings.json; translations live in data/i18n/en.json and ja.json
(maps Arabic source -> translation). tests/playthrough checks full coverage.
"""
import json, os, re, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AR = re.compile(r"[؀-ۿ]")
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


def collect():
    out = []
    files = [os.path.join(ROOT, "data", "story.gd")] + glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)
    for f in files:
        for m in STR.finditer(open(f, encoding="utf-8").read()):
            s = m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in m.group(1) else m.group(1)
            if AR.search(s) and s not in out:
                out.append(s)
    world = json.load(open(os.path.join(ROOT, "data", "world.json"), encoding="utf-8"))
    for z in world["zones"]:
        if z["name"] and z["name"] not in out:
            out.append(z["name"])
    return out


if __name__ == "__main__":
    s = collect()
    os.makedirs(os.path.join(ROOT, "data", "i18n"), exist_ok=True)
    json.dump(s, open(os.path.join(ROOT, "data", "i18n", "strings.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print(len(s), "strings")
