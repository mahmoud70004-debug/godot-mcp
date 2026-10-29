"""Builds data/i18n/en.json and ja.json from tools/i18n/translations.json
({arabic source: [english, japanese]}) for every string in data/i18n/strings.json.
Run tools/i18n_extract.py first. Missing translations are listed (and fail the tests)."""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
strings = json.load(open(os.path.join(ROOT, "data", "i18n", "strings.json"), encoding="utf-8"))
store = json.load(open(os.path.join(ROOT, "tools", "i18n", "translations.json"), encoding="utf-8"))
en, ja, missing = {}, {}, []
for src in strings:
    if src in store:
        en[src], ja[src] = store[src]
    else:
        missing.append(src)
for lang, d in (("en", en), ("ja", ja)):
    json.dump(d, open(os.path.join(ROOT, "data", "i18n", f"{lang}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print(len(en), "translated;", len(missing), "missing")
for m in missing:
    print("  MISSING:", m)
sys.exit(1 if missing else 0)
