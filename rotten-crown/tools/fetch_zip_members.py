"""Extract selected members from a remote zip using HTTP Range requests.

Used to pull only the web export templates (~10 MB each) out of the 1.2 GB
Godot export_templates.tpz.  Usage:
  python3 fetch_zip_members.py URL OUT_DIR [member ...]   (no members = list)
"""
import io, struct, sys, urllib.request, zlib, os

url, outdir, *wanted = sys.argv[1:]
def fetch(start, end):
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req) as r:
        return r.read()
head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
size = int(head.headers["Content-Length"])
tail = fetch(size - 65536, size - 1)
eocd = tail.rfind(b"PK\x05\x06")
cd_size, cd_off = struct.unpack("<II", tail[eocd + 12:eocd + 20])
cd = fetch(cd_off, cd_off + cd_size - 1)
i = 0
entries = {}
while i < len(cd):
    (sig, _, _, _, method, _, _, crc, csize, usize, nlen, elen, clen, _, _, _, off) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[i:i + 46])
    name = cd[i + 46:i + 46 + nlen].decode()
    entries[name] = (method, csize, usize, off)
    i += 46 + nlen + elen + clen
if not wanted:
    for n, (_, c, u, _) in entries.items():
        print(f"{u:>12} {n}")
    sys.exit()
os.makedirs(outdir, exist_ok=True)
for name in wanted:
    method, csize, usize, off = entries[name]
    lh = fetch(off, off + 29)
    nlen, elen = struct.unpack("<HH", lh[26:30])
    data = fetch(off + 30 + nlen + elen, off + 30 + nlen + elen + csize - 1)
    if method == 8:
        data = zlib.decompress(data, -15)
    path = os.path.join(outdir, os.path.basename(name))
    open(path, "wb").write(data)
    print("extracted", name, len(data))
