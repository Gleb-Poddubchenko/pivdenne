"""
dem.py: elevation for the Pivdenne map, from the public AWS Terrain Tiles
("terrarium" PNG tiles, SRTM-based, ~30 m; https://registry.opendata.aws/terrain-tiles/).

    python3 tools/dem.py download 31.06 46.60 31.13 46.655   # -> data/dem/*.png

The converter (osm_to_roblox.py --dem data/dem) then samples a height grid on the
same local projection as the map. Standard library only (PNG decoded with zlib).
Elevation data: Mapzen / AWS Terrain Tiles (SRTM, NASA; public domain or
attribution as listed by the dataset).
"""

import math
import os
import struct
import sys
import urllib.request
import zlib

ZOOM = 14
URL = "https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png"
UA = "YuzhneRobloxMapBuilder/1.0 (personal project)"


def tile_xy(lat, lon, z=ZOOM):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n
    return x, y  # fractional tile coordinates


def download(min_lon, min_lat, max_lon, max_lat, out_dir="data/dem"):
    os.makedirs(out_dir, exist_ok=True)
    x0, y1 = tile_xy(min_lat, min_lon)
    x1, y0 = tile_xy(max_lat, max_lon)
    count = 0
    for tx in range(int(x0), int(x1) + 1):
        for ty in range(int(y0), int(y1) + 1):
            path = os.path.join(out_dir, f"{ZOOM}_{tx}_{ty}.png")
            if os.path.exists(path):
                continue
            req = urllib.request.Request(URL.format(z=ZOOM, x=tx, y=ty), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r, open(path, "wb") as fh:
                fh.write(r.read())
            count += 1
    print(f"elevation tiles: {count} downloaded into {out_dir}")


def decode_png(data):
    """Minimal PNG decoder for 8-bit RGB/RGBA, non-interlaced. Returns (w, h, channels, rows)."""
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, w = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and ctype in (2, 6) and interlace == 0, "unsupported PNG"
            ch = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
    raw = zlib.decompress(b"".join(idat))
    stride = w * ch
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, ch, rows


class Elevation:
    """Bilinear elevation (metres above sea level) from a folder of terrarium tiles."""

    def __init__(self, folder):
        self.tiles = {}
        for name in os.listdir(folder):
            if name.endswith(".png"):
                z, x, y = (int(v) for v in name[:-4].split("_"))
                with open(os.path.join(folder, name), "rb") as fh:
                    w, h, ch, rows = decode_png(fh.read())
                grid = [[r[px * ch] * 256 + r[px * ch + 1] + r[px * ch + 2] / 256 - 32768 for px in range(w)] for r in rows]
                self.tiles[(x, y)] = (w, h, grid)
        if not self.tiles:
            raise SystemExit(f"no elevation tiles in {folder}")

    def pixel(self, gx, gy):
        tx, ty = int(gx // 256), int(gy // 256)
        t = self.tiles.get((tx, ty))
        if not t:
            return None
        return t[2][int(gy - ty * 256)][int(gx - tx * 256)]

    def at(self, lat, lon):
        fx, fy = tile_xy(lat, lon)
        gx, gy = fx * 256 - 0.5, fy * 256 - 0.5
        x0, y0 = math.floor(gx), math.floor(gy)
        dx, dy = gx - x0, gy - y0
        v = [self.pixel(x0, y0), self.pixel(x0 + 1, y0), self.pixel(x0, y0 + 1), self.pixel(x0 + 1, y0 + 1)]
        if any(q is None for q in v):
            return None
        top = v[0] * (1 - dx) + v[1] * dx
        bottom = v[2] * (1 - dx) + v[3] * dx
        return top * (1 - dy) + bottom * dy


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "download":
        download(*(float(v) for v in sys.argv[2:6]))
    else:
        sys.exit(__doc__)


# ---------------------------------------------------------------- height grid for the map

# OSM area kind -> terrain material code (see City/Height.luau)
AREA_MATERIAL = {
    "park": "G", "grass": "G", "pitch": "G", "forest": "L", "beach": "S", "playground": "S",
    "parking": "A", "garages": "C", "industrial": "C", "market": "P", "school_ground": "g",
}
PRIORITY = ["S", "A", "P", "C", "L", "G", "g"]  # when areas overlap at a cell centre


def build_grid(elev, bounds, grid_studs, unproject, areas, pip):
    """Samples heights (studs, sea level = 0) on a regular grid covering bounds.

    Returns dict with x0, z0, cols, rows, h (row-major, studs) and mat (one code per
    cell, cells are between grid nodes).
    """
    from math import ceil
    x0, z0 = bounds[0], bounds[1]
    cols = int(ceil((bounds[2] - bounds[0]) / grid_studs)) + 1
    rows = int(ceil((bounds[3] - bounds[1]) / grid_studs)) + 1
    raw = []
    for r in range(rows):
        row = []
        for c in range(cols):
            lat, lon = unproject(x0 + c * grid_studs, z0 + r * grid_studs)
            v = elev.at(lat, lon)
            row.append(max(0.0, v if v is not None else 0.0))
        raw.append(row)
    # one light smoothing pass (removes SRTM speckle, keeps the cliffs)
    h = []
    for r in range(rows):
        out = []
        for c in range(cols):
            acc, wsum = raw[r][c] * 4, 4
            for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                rr, cc = r + dr, c + dc
                if 0 <= rr < rows and 0 <= cc < cols:
                    acc += raw[rr][cc]
                    wsum += 1
            out.append(acc / wsum)
        h.append(out)

    # area bounding boxes for the material lookup
    boxes = []
    for a in areas:
        code = AREA_MATERIAL.get(a["t"])
        if code:
            xs = [p[0] for p in a["p"]]
            zs = [p[1] for p in a["p"]]
            boxes.append((min(xs), min(zs), max(xs), max(zs), a["p"], code))
    mat = []
    for r in range(rows - 1):
        line = []
        for c in range(cols - 1):
            px, pz = x0 + (c + 0.5) * grid_studs, z0 + (r + 0.5) * grid_studs
            best = "g"
            for minx, minz, maxx, maxz, pts, code in boxes:
                if minx <= px <= maxx and minz <= pz <= maxz and pip((px, pz), pts):
                    if best == "g" or PRIORITY.index(code) < PRIORITY.index(best):
                        best = code
            line.append(best)
        mat.append("".join(line))

    return {"x0": x0, "z0": z0, "cols": cols, "rows": rows, "h": h, "mat": mat}
