#!/usr/bin/env python3
"""Download CC0 OpenGameArt packs into build/asset_cache/oga/<slug>/ and extract them.

  python3 tools/assets/fetch_opengameart.py <page-slug> <file-url>... [--slug NAME]

<page-slug> is the last part of https://opengameart.org/content/<page-slug>. The page is scraped for the
author ("Author:" field), the submitter and the licence name; the fetch refuses anything that is not CC0.
Each file URL is saved under <slug>/ and extracted (zip, 7z via py7zr or the 7z binary). info.json records
page URL, author, licence and the file list. Existing files are skipped. Needs only the stdlib (+ py7zr for .7z).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CACHE = os.path.join(ROOT, "build", "asset_cache", "oga")
UA = {"User-Agent": "Mozilla/5.0 rotten-crown-asset-fetch/1.0"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def strip(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s)).strip()


def scrape(page_url):
    html = get(page_url).decode("utf-8", "replace")
    lic = re.findall(r"license-name'>([^<]+)<", html)
    am = re.search(r"field-name-author-submitter.*?field-items\"><div class=\"field-item even\">(.*?)</div></div></div>", html, re.S)
    author, submitter = "", ""
    if am:
        block = am.group(1)
        sm = re.search(r"Submitted by\s*<strong>(.*?)</strong>", block, re.S)
        submitter = strip(sm.group(1)) if sm else ""
        author = strip(block.split("<br")[0])
    t = re.search(r"<title>(.*?)</title>", html, re.S)
    return {"title": strip(t.group(1)).replace("| OpenGameArt.org", "").strip() if t else "",
            "author": author, "submitter": submitter, "licenses": lic}


def extract(path, dest):
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            z.extractall(dest)
    elif path.endswith(".7z"):
        try:
            import py7zr
            with py7zr.SevenZipFile(path) as z:
                z.extractall(dest)
        except ImportError:
            exe = shutil.which("7z") or shutil.which("7za") or shutil.which("7zr")
            if not exe:
                raise SystemExit("need py7zr (pip install py7zr) or a 7z binary to extract " + path)
            subprocess.run([exe, "x", "-y", "-o" + dest, path], check=True, stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page")
    ap.add_argument("urls", nargs="+")
    ap.add_argument("--slug")
    a = ap.parse_args()
    slug = a.slug or a.page
    page_url = "https://opengameart.org/content/" + a.page
    meta = scrape(page_url)
    if meta["licenses"] != ["CC0"]:
        raise SystemExit(f"{page_url}: licence is {meta['licenses']}, not CC0 only; refusing")
    out = os.path.join(CACHE, slug)
    os.makedirs(out, exist_ok=True)
    open(os.path.join(ROOT, "build", ".gdignore"), "a").close()
    files = []
    for url in a.urls:
        dest = os.path.join(out, os.path.basename(url))
        if not (os.path.exists(dest) and os.path.getsize(dest) > 0):
            with open(dest + ".part", "wb") as f:
                f.write(get(url))
            os.replace(dest + ".part", dest)
        sub = os.path.join(out, "x_" + os.path.splitext(os.path.basename(url))[0])
        if not os.path.isdir(sub):
            extract(dest, sub)
        files.append(os.path.basename(url))
    meta.update({"slug": slug, "source": page_url, "license": "CC0", "files": files})
    with open(os.path.join(out, "info.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(slug, "ok", json.dumps(meta))


if __name__ == "__main__":
    main()
