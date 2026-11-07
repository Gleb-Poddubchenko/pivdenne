"""
osm_details.py: street-level detail for osm_to_roblox.py.

REAL objects from OSM are used wherever they exist:
  natural=coastline        -> sea (water is on the RIGHT of the way direction, OSM convention)
  natural=tree / tree_row  -> trees
  highway=street_lamp      -> street lamps
  highway=crossing         -> zebra crossings (aligned with the road they sit on)
  highway=bus_stop         -> bus shelters with the real stop name
  amenity=bench            -> benches
  amenity=waste_disposal / recycling -> rubbish containers
  railway=rail             -> railway track

GENERATED detail fills gaps only where OSM is empty, and is reproducible (seeded
by position), so re-running gives the same city:
  trees scattered in parks, forests, grass and residential courtyards (never on
  buildings or roads), street lamps every ~35 m along streets that have no mapped
  lamps nearby.
"""

import math
import random

STUDS_PER_METER = 3.5
GRID = 64  # studs, spatial hash cell


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L2))
    q = (a[0] + t * dx, a[1] + t * dz)
    return _dist(p, q), q, t


def _pip(p, pts):
    x, z = p
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, zi = pts[i]
        xj, zj = pts[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


class SpatialIndex:
    """Buckets building outlines and road segments for fast 'is this spot free?' checks."""

    def __init__(self, buildings, roads):
        self.b = {}
        self.r = {}
        for bi, b in enumerate(buildings):
            xs = [q[0] for q in b["p"]]
            zs = [q[1] for q in b["p"]]
            for cx in range(int(min(xs) // GRID), int(max(xs) // GRID) + 1):
                for cz in range(int(min(zs) // GRID), int(max(zs) // GRID) + 1):
                    self.b.setdefault((cx, cz), []).append(bi)
        self.buildings = buildings
        for r in roads:
            pts = r["p"]
            for a, c in zip(pts, pts[1:]):
                half = r["w"] / 2
                for cx in range(int((min(a[0], c[0]) - half) // GRID), int((max(a[0], c[0]) + half) // GRID) + 1):
                    for cz in range(int((min(a[1], c[1]) - half) // GRID), int((max(a[1], c[1]) + half) // GRID) + 1):
                        self.r.setdefault((cx, cz), []).append((a, c, half, r))

    def near_building(self, p, margin):
        cx, cz = int(p[0] // GRID), int(p[1] // GRID)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for bi in self.b.get((cx + dx, cz + dz), ()):
                    pts = self.buildings[bi]["p"]
                    if _pip(p, pts):
                        return True
                    for i in range(len(pts)):
                        if _seg_dist(p, pts[i], pts[(i + 1) % len(pts)])[0] < margin:
                            return True
        return False

    def near_road(self, p, margin):
        cx, cz = int(p[0] // GRID), int(p[1] // GRID)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for a, c, half, _ in self.r.get((cx + dx, cz + dz), ()):
                    if _seg_dist(p, a, c)[0] < half + margin:
                        return True
        return False

    def nearest_road(self, p, max_dist=60):
        best = None
        cx, cz = int(p[0] // GRID), int(p[1] // GRID)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for a, c, half, r in self.r.get((cx + dx, cz + dz), ()):
                    d, q, _ = _seg_dist(p, a, c)
                    if d < max_dist and (best is None or d < best[0]):
                        best = (d, q, a, c, half, r)
        return best


def extract(nodes, ways, buildings, roads, project, max_trees=15000):
    """Returns dict kind -> list of feature dicts (each with x, z)."""
    sidx = SpatialIndex(buildings, roads)
    out = {"co": [], "tr": [], "lp": [], "cw": [], "bs": [], "bn": [], "wc": [], "rl": []}
    m = STUDS_PER_METER

    def ring(refs):
        pts = []
        for r in refs:
            n = nodes.get(r)
            if n is None:
                return None
            pts.append(project(n[0], n[1]))
        return pts

    # ---- coastline (sea on the right) and railways
    for wid, (refs, tags) in ways.items():
        if tags.get("natural") == "coastline":
            pts = ring(refs)
            if pts and len(pts) >= 2:
                out["co"].append({"x": pts[0][0], "z": pts[0][1], "p": pts})
        elif tags.get("railway") == "rail" and tags.get("service") not in ("abandoned",):
            pts = ring(refs)
            if pts and len(pts) >= 2:
                out["rl"].append({"x": pts[0][0], "z": pts[0][1], "p": pts})

    # ---- point features
    real_lamps = []
    for nid, (lat, lon, tags) in nodes.items():
        x, z = project(lat, lon)
        if tags.get("natural") == "tree":
            out["tr"].append({"x": x, "z": z, "s": 1.0, "k": 1})
        elif tags.get("highway") == "street_lamp":
            real_lamps.append((x, z))
            near = sidx.nearest_road((x, z))
            a = math.atan2(near[1][1] - z, near[1][0] - x) if near else 0.0
            out["lp"].append({"x": x, "z": z, "a": a, "real": 1})
        elif tags.get("highway") == "crossing":
            near = sidx.nearest_road((x, z), 20)
            if near:
                _, _, a, c, half, _ = near
                out["cw"].append({"x": x, "z": z, "a": math.atan2(c[1] - a[1], c[0] - a[0]), "w": half * 2})
        elif tags.get("highway") == "bus_stop" or (tags.get("public_transport") == "platform" and tags.get("bus") == "yes"):
            near = sidx.nearest_road((x, z))
            a = math.atan2(near[1][1] - z, near[1][0] - x) if near else 0.0
            out["bs"].append({"x": x, "z": z, "a": a, "nm": tags.get("name") or ""})
        elif tags.get("amenity") == "bench":
            near = sidx.nearest_road((x, z))
            a = math.atan2(near[1][1] - z, near[1][0] - x) if near else 0.0
            out["bn"].append({"x": x, "z": z, "a": a})
        elif tags.get("amenity") in ("waste_disposal", "recycling"):
            out["wc"].append({"x": x, "z": z})

    for wid, (refs, tags) in ways.items():
        if tags.get("natural") == "tree_row":
            pts = ring(refs)
            if not pts:
                continue
            for a, c in zip(pts, pts[1:]):
                L = _dist(a, c)
                n = max(1, int(L / (8 * m)))
                for k in range(n + 1):
                    t = k / n
                    out["tr"].append({"x": a[0] + (c[0] - a[0]) * t, "z": a[1] + (c[1] - a[1]) * t, "s": 1.0, "k": 1})

    # ---- generated trees in green areas and residential courtyards
    scatter = {  # key=value -> (spacing m, probability)
        "landuse=forest": (7, 0.9), "natural=wood": (7, 0.9), "natural=scrub": (9, 0.5),
        "leisure=park": (10, 0.6), "leisure=garden": (10, 0.5),
        "landuse=grass": (16, 0.25), "landuse=recreation_ground": (12, 0.4),
        "landuse=residential": (14, 0.35), "amenity=school": (14, 0.3), "amenity=kindergarten": (12, 0.4),
    }
    generated = 0
    for wid, (refs, tags) in ways.items():
        if generated >= max_trees or len(refs) < 4 or refs[0] != refs[-1] or "building" in tags:
            continue
        rule = None
        for key in ("landuse", "natural", "leisure", "amenity"):
            v = tags.get(key)
            if v and f"{key}={v}" in scatter:
                rule = scatter[f"{key}={v}"]
                break
        if not rule:
            continue
        pts = ring(refs)
        if not pts:
            continue
        spacing = rule[0] * m
        xs = [q[0] for q in pts]
        zs = [q[1] for q in pts]
        rng = random.Random(wid)
        gx = min(xs)
        while gx <= max(xs) and generated < max_trees:
            gz = min(zs)
            while gz <= max(zs) and generated < max_trees:
                p = (gx + (rng.random() - 0.5) * spacing * 0.8, gz + (rng.random() - 0.5) * spacing * 0.8)
                if rng.random() < rule[1] and _pip(p, pts) and not sidx.near_building(p, 3 * m) and not sidx.near_road(p, 1.5 * m):
                    out["tr"].append({"x": p[0], "z": p[1], "s": 0.75 + rng.random() * 0.6, "k": 0})
                    generated += 1
                gz += spacing
            gx += spacing

    # ---- generated street lamps where none are mapped
    lamp_roads = ("primary", "secondary", "tertiary", "residential", "unclassified", "living_street")
    spacing = 35 * m
    for r in roads:
        if r["t"] not in lamp_roads:
            continue
        pts = r["p"]
        carry = spacing / 2
        side = 1
        for a, c in zip(pts, pts[1:]):
            L = _dist(a, c)
            if L < 1e-6:
                continue
            ux, uz = (c[0] - a[0]) / L, (c[1] - a[1]) / L
            nx, nz = -uz, ux
            d = carry
            while d < L:
                off = r["w"] / 2 + 0.8 * m
                p = (a[0] + ux * d + nx * off * side, a[1] + uz * d + nz * off * side)
                if not any(_dist(p, q) < 20 * m for q in real_lamps) and not sidx.near_building(p, 1 * m):
                    out["lp"].append({"x": p[0], "z": p[1], "a": math.atan2(-nz * side, -nx * side), "real": 0})
                side = -side
                d += spacing
            carry = d - L
    return out


def _n(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def to_lua(kind, f, lua_str):
    if kind == "co" or kind == "rl":
        return "{" + ",".join(_n(c) for q in f["p"] for c in q) + "}"
    if kind == "tr":
        return f"{_n(f['x'])},{_n(f['z'])},{_n(f['s'])},{f['k']}"  # flat: 4 numbers per tree
    if kind == "lp":
        return "{" + f"{_n(f['x'])},{_n(f['z'])},{f['a']:.3f},{f['real']}" + "}"
    if kind == "cw":
        return "{" + f"{_n(f['x'])},{_n(f['z'])},{f['a']:.3f},{_n(f['w'])}" + "}"
    if kind == "bs":
        return "{" + f"x={_n(f['x'])},z={_n(f['z'])},a={f['a']:.3f},nm={lua_str(f['nm'])}" + "}"
    if kind == "bn":
        return "{" + f"{_n(f['x'])},{_n(f['z'])},{f['a']:.3f}" + "}"
    if kind == "wc":
        return "{" + f"{_n(f['x'])},{_n(f['z'])}" + "}"
    raise ValueError(kind)
