#!/usr/bin/env python3
"""
osm_to_roblox.py: convert OpenStreetMap XML (.osm) for Yuzhne/Pivdenne into Luau
data modules that CityBuilder (ServerScriptService) turns into the city.

    python3 tools/osm_to_roblox.py data/pivdenne.osm [more.osm ...] --out map/data

Pure standard library (Python 3.8+). Several input files (e.g. bbox tiles) are
merged and de-duplicated by OSM id.

What it extracts
  * buildings: footprint, height (building:levels * 2.8 m), typology, real
    address (addr:street + addr:housenumber, also from separate address nodes
    inside the outline), name, entrances (entrance=* nodes on the outline)
  * address plates: position + facing, chosen on the wall that faces the street
    named in addr:street (falls back to the wall facing the nearest road)
  * roads / paths with widths, areas (parks, water, beach, parking), POIs
Coordinates: local tangent plane around ORIGIN, 1 m = 3.5 studs, +X = east,
-Z = north (Roblox), rounded to 0.01 stud.

Map data (c) OpenStreetMap contributors, ODbL 1.0. Keep the in-game attribution.
"""

import argparse
import math
import os
import sys
import xml.etree.ElementTree as ET

STUDS_PER_METER = 3.5
FLOOR_HEIGHT_M = 2.8
# Centre of the Pivdenne city boundary (OSM relation 3606547, via Nominatim).
ORIGIN_LAT = 46.6225029
ORIGIN_LON = 31.0994897
CHUNK_SIZE = 512  # studs
MAX_MODULE_BYTES = 180_000  # stay well under Roblox's script source limits

ROAD_WIDTH_M = {
    "motorway": 14, "trunk": 12, "primary": 10, "secondary": 9, "tertiary": 8,
    "unclassified": 6, "residential": 6, "living_street": 5, "service": 4,
    "pedestrian": 4, "track": 3, "footway": 2, "path": 1.5, "cycleway": 2,
    "steps": 2, "motorway_link": 7, "trunk_link": 7, "primary_link": 7,
    "secondary_link": 6, "tertiary_link": 6,
}

AREA_TAGS = [
    ("leisure", {"park": "park", "garden": "park", "playground": "playground", "pitch": "pitch", "stadium": "pitch"}),
    ("landuse", {"grass": "grass", "forest": "forest", "meadow": "grass", "recreation_ground": "park",
                 "garages": "garages", "industrial": "industrial", "railway": "industrial"}),
    ("natural", {"water": "water", "beach": "beach", "sand": "beach", "wood": "forest", "scrub": "forest",
                 "grassland": "grass"}),
    ("amenity", {"parking": "parking", "school": "school_ground", "kindergarten": "school_ground",
                 "marketplace": "market"}),
    ("waterway", {"riverbank": "water"}),
]

POI_KEYS = ("amenity", "shop", "tourism", "leisure", "public_transport", "railway", "office", "man_made")

STREET_ABBREVIATIONS = [
    ("вулиця", "вул."), ("проспект", "просп."), ("провулок", "пров."), ("бульвар", "бульв."),
    ("площа", "пл."), ("проїзд", "проїзд"), ("набережна", "наб."), ("узвіз", "узвіз"),
    ("улица", "ул."), ("переулок", "пер."),
]


# ---------------------------------------------------------------- projection

def meters_per_degree(lat):
    phi = math.radians(lat)
    m_lat = 111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)
    return m_lat, m_lon


M_LAT, M_LON = meters_per_degree(ORIGIN_LAT)


def project(lat, lon):
    x = (lon - ORIGIN_LON) * M_LON * STUDS_PER_METER
    z = -(lat - ORIGIN_LAT) * M_LAT * STUDS_PER_METER
    return (x, z)


# ---------------------------------------------------------------- geometry

def signed_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        a += x1 * z2 - x2 * z1
    return a / 2


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def simplify(pts, tol=0.3 * STUDS_PER_METER):
    """Drop near-duplicate and collinear vertices of a closed ring."""
    out = []
    for p in pts:
        if not out or dist(out[-1], p) > 0.05:
            out.append(p)
    if len(out) > 1 and dist(out[0], out[-1]) < 0.05:
        out.pop()
    changed = True
    while changed and len(out) > 3:
        changed = False
        for i in range(len(out)):
            a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
            # distance of b from line ac
            ac = dist(a, c)
            if ac < 1e-6:
                d = dist(a, b)
            else:
                d = abs((c[0] - a[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (c[1] - a[1])) / ac
            if d < tol:
                out.pop(i)
                changed = True
                break
    return out


def point_in_polygon(p, pts):
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


def triangulate(pts):
    """Ear clipping for a simple polygon with positive signed area. Returns index triples."""
    n = len(pts)
    if n < 3:
        return []
    idx = list(range(n))
    tris = []

    def is_convex(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1e-9

    def in_tri(p, a, b, c):
        d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
        d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
        d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
        neg = d1 < 0 or d2 < 0 or d3 < 0
        pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (neg and pos)

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if not is_convex(a, b, c):
                continue
            if any(in_tri(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            found = True
            break
        if not found:  # degenerate / self-intersecting: fan the rest
            break
    for k in range(1, len(idx) - 1):
        tris.append((idx[0], idx[k], idx[k + 1]))
    return tris


def oriented_rectangle(pts):
    """If the ring is (almost) a rectangle, return (cx, cz, length, width, angle)."""
    if len(pts) != 4:
        return None
    for i in range(4):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % 4]
        v1 = (a[0] - b[0], a[1] - b[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        if l1 < 1e-6 or l2 < 1e-6:
            return None
        cos = (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)
        if abs(cos) > 0.08:  # ~ +-5 degrees off square
            return None
    e0 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    e1 = (pts[2][0] - pts[1][0], pts[2][1] - pts[1][1])
    length, width = math.hypot(*e0), math.hypot(*e1)
    angle = math.atan2(e0[1], e0[0])
    cx, cz = centroid(pts)
    return (cx, cz, length, width, angle)


def seg_point_distance(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / L2))
    q = (ax + t * dx, az + t * dz)
    return dist(p, q), q


# ---------------------------------------------------------------- parsing

def parse(files):
    nodes, ways, relations = {}, {}, {}
    for path in files:
        for _, el in ET.iterparse(path, events=("end",)):
            if el.tag == "node":
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                nodes[int(el.get("id"))] = (float(el.get("lat")), float(el.get("lon")), tags)
                el.clear()
            elif el.tag == "way":
                refs = [int(nd.get("ref")) for nd in el.findall("nd")]
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                ways[int(el.get("id"))] = (refs, tags)
                el.clear()
            elif el.tag == "relation":
                members = [(m.get("type"), int(m.get("ref")), m.get("role")) for m in el.findall("member")]
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                relations[int(el.get("id"))] = (members, tags)
                el.clear()
    return nodes, ways, relations


def number(value, default=None):
    if value is None:
        return default
    try:
        return float(str(value).replace(",", ".").split(";")[0].strip().split(" ")[0])
    except ValueError:
        return default


def typology(tags, levels, area_m2):
    b = tags.get("building", "yes")
    if b in ("garage", "garages", "carport"):
        return "garage"
    if b in ("industrial", "warehouse", "factory", "manufacture", "storage_tank", "silo", "hangar"):
        return "industrial"
    if b in ("school", "kindergarten", "university", "college", "hospital", "public", "civic",
             "government", "church", "cathedral", "chapel", "train_station", "transportation"):
        return "public"
    if b in ("retail", "commercial", "kiosk", "supermarket", "office"):
        return "commercial"
    if b in ("house", "detached", "semidetached_house", "bungalow", "cabin", "farm", "terrace") or (
            b == "yes" and levels is not None and levels <= 2 and area_m2 < 250):
        return "house"
    if b in ("apartments", "residential", "dormitory") or (levels is not None and levels >= 4):
        if levels is None:
            return "panel"
        if levels >= 12:
            return "panel_high"
        if levels >= 9:
            return "panel9"
        if levels >= 5:
            return "panel5"
        return "panel"
    return "other"


def abbreviate_street(name):
    low = name.lower()
    for full, short in STREET_ABBREVIATIONS:
        if low.startswith(full + " "):
            return short + name[len(full):]
        if low.endswith(" " + full):
            return name[: -len(full)] + short
    return name


def build_features(nodes, ways, relations):
    def ring_of(refs):
        pts = []
        for r in refs:
            n = nodes.get(r)
            if n is None:
                return None
            pts.append(project(n[0], n[1]))
        return pts

    # ---- roads
    roads = []
    for wid, (refs, tags) in ways.items():
        hw = tags.get("highway")
        if hw not in ROAD_WIDTH_M or tags.get("area") == "yes":
            continue
        pts = ring_of(refs)
        if not pts or len(pts) < 2:
            continue
        width_m = number(tags.get("width"))
        if width_m is None and number(tags.get("lanes")):
            width_m = number(tags.get("lanes")) * 3.2
        width_m = width_m or ROAD_WIDTH_M[hw]
        roads.append({
            "id": wid, "t": hw, "nm": tags.get("name") or tags.get("name:uk") or "",
            "w": width_m * STUDS_PER_METER, "p": pts,
            "br": 1 if tags.get("bridge") else 0,
        })

    named_segments = {}
    all_segments = []
    for r in roads:
        if r["t"] in ("footway", "path", "steps", "cycleway", "track"):
            continue
        for a, b in zip(r["p"], r["p"][1:]):
            all_segments.append((a, b))
            if r["nm"]:
                named_segments.setdefault(r["nm"], []).append((a, b))

    # ---- building outlines (ways + simple multipolygon relations)
    outlines = []  # (osm_id, refs, tags)
    for wid, (refs, tags) in ways.items():
        if "building" in tags and tags.get("building") != "no" and len(refs) >= 4 and refs[0] == refs[-1]:
            outlines.append((wid, refs, tags))
    for rid, (members, tags) in relations.items():
        if tags.get("type") == "multipolygon" and "building" in tags:
            for mtype, ref, role in members:
                if mtype == "way" and role == "outer" and ref in ways:
                    refs, wtags = ways[ref]
                    if len(refs) >= 4 and refs[0] == refs[-1]:
                        merged = dict(tags)
                        merged.update(wtags)
                        outlines.append((ref, refs, merged))

    # address nodes not on outlines (addr points inside buildings)
    outline_nodes = set()
    for _, refs, _ in outlines:
        outline_nodes.update(refs)
    addr_points = []
    for nid, (lat, lon, tags) in nodes.items():
        if "addr:housenumber" in tags and nid not in outline_nodes:
            addr_points.append((project(lat, lon), tags))

    buildings = []
    stats = {"buildings": 0, "with_address": 0, "with_levels": 0, "entrances": 0, "plates": 0}
    for oid, refs, tags in outlines:
        pts = ring_of(refs)
        if not pts:
            continue
        pts = simplify(pts)
        if len(pts) < 3:
            continue
        if signed_area(pts) < 0:
            pts.reverse()
        area_studs = signed_area(pts)
        area_m2 = area_studs / (STUDS_PER_METER ** 2)
        if area_m2 < 4:
            continue

        levels = number(tags.get("building:levels"))
        height_m = number(tags.get("height"))
        if height_m is None:
            height_m = (levels * FLOOR_HEIGHT_M + 0.6) if levels else None
        typ = typology(tags, levels, area_m2)
        if height_m is None:
            height_m = {"garage": 2.6, "house": 6.0, "industrial": 8.0, "public": 8.0,
                        "commercial": 4.0, "panel": 14.6, "panel5": 14.6, "panel9": 25.8,
                        "panel_high": 34.0}.get(typ, 6.0)

        street = tags.get("addr:street")
        housenumber = tags.get("addr:housenumber")
        if not housenumber:
            for p, atags in addr_points:
                if point_in_polygon(p, pts):
                    housenumber = atags.get("addr:housenumber")
                    street = street or atags.get("addr:street")
                    break

        # entrances (nodes on the outline)
        entrances = []
        for r in refs[:-1]:
            n = nodes.get(r)
            if n and "entrance" in n[2]:
                ex, ez = project(n[0], n[1])
                entrances.append({
                    "x": ex, "z": ez,
                    "ref": n[2].get("ref", ""),
                    "flats": n[2].get("addr:flats", ""),
                    "kind": n[2].get("entrance", "yes"),
                })

        # outward normal of the wall each entrance sits on (for canopy/door/plate)
        for e in entrances:
            best_d, best_n = None, (0.0, 1.0)
            for i in range(len(pts)):
                pa, pb = pts[i], pts[(i + 1) % len(pts)]
                d, _ = seg_point_distance((e["x"], e["z"]), pa, pb)
                L = dist(pa, pb)
                if L > 0 and (best_d is None or d < best_d):
                    best_d = d
                    best_n = ((pb[1] - pa[1]) / L, -(pb[0] - pa[0]) / L)
            e["nx"], e["nz"] = best_n

        b = {
            "id": oid, "t": typ, "h": height_m * STUDS_PER_METER,
            "lv": int(levels) if levels else 0,
            "p": pts,
            "nm": tags.get("name") or "",
            "st": street or "", "hn": housenumber or "",
            "en": entrances,
        }
        rect = oriented_rectangle(pts)
        if rect:
            b["rect"] = rect
        else:
            b["tri"] = triangulate(pts)
        if street and housenumber:
            b["plates"] = choose_plates(pts, named_segments.get(street) or all_segments)
            stats["plates"] += len(b["plates"])
            stats["with_address"] += 1
        stats["buildings"] += 1
        stats["with_levels"] += 1 if levels else 0
        stats["entrances"] += len(entrances)
        buildings.append(b)

    # ---- areas
    areas = []
    for wid, (refs, tags) in ways.items():
        if "building" in tags or len(refs) < 4 or refs[0] != refs[-1]:
            continue
        kind = None
        for key, mapping in AREA_TAGS:
            if tags.get(key) in mapping:
                kind = mapping[tags[key]]
                break
        if not kind:
            continue
        pts = ring_of(refs)
        if not pts:
            continue
        pts = simplify(pts, tol=0.5)
        if len(pts) < 3:
            continue
        if signed_area(pts) < 0:
            pts.reverse()
        areas.append({"id": wid, "t": kind, "p": pts, "tri": triangulate(pts), "nm": tags.get("name") or ""})

    # ---- POIs (named amenities as labels: schools, markets, bus station, shops...)
    pois = []
    for nid, (lat, lon, tags) in nodes.items():
        name = tags.get("name")
        if name and any(k in tags for k in POI_KEYS):
            x, z = project(lat, lon)
            kind = next((f"{k}={tags[k]}" for k in POI_KEYS if k in tags), "")
            pois.append({"x": x, "z": z, "nm": name, "k": kind})
    for wid, (refs, tags) in ways.items():
        name = tags.get("name")
        if name and any(k in tags for k in POI_KEYS) and refs and refs[0] == refs[-1]:
            pts = ring_of(refs)
            if pts:
                x, z = centroid(pts[:-1] or pts)
                kind = next((f"{k}={tags[k]}" for k in POI_KEYS if k in tags), "")
                pois.append({"x": x, "z": z, "nm": name, "k": kind})

    return buildings, roads, areas, pois, stats


def choose_plates(pts, segments):
    """Place address plates on the wall that faces the addressed street.

    Returns up to two plates [x, z, nx, nz] (outward unit normal), 1.5 m in from
    the ends of the chosen wall, as on real Soviet-era blocks (plates near corners).
    """
    if not segments:
        return []
    best = None
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        length = dist(a, b)
        if length < 2 * STUDS_PER_METER:
            continue
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        dx, dz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        nx, nz = dz, -dx  # outward normal (polygon has positive area: inward is (-dz, dx))
        d_best = None
        for sa, sb in segments:
            d, q = seg_point_distance(mid, sa, sb)
            facing = (q[0] - mid[0]) * nx + (q[1] - mid[1]) * nz
            if facing <= 0:
                continue
            if d_best is None or d < d_best:
                d_best = d
        if d_best is None:
            continue
        score = d_best - min(length, 30 * STUDS_PER_METER) * 0.05  # prefer long walls slightly
        if best is None or score < best[0]:
            best = (score, a, b, length, nx, nz, dx, dz)
    if best is None:
        return []
    _, a, b, length, nx, nz, dx, dz = best
    inset = min(1.5 * STUDS_PER_METER, length / 4)
    plates = [[a[0] + dx * inset, a[1] + dz * inset, nx, nz]]
    if length > 25 * STUDS_PER_METER:
        plates.append([b[0] - dx * inset, b[1] - dz * inset, nx, nz])
    return plates


# ---------------------------------------------------------------- Luau output

def lua_str(s):
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ord(ch) < 32:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def num(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def flat_points(pts):
    return "{" + ",".join(num(c) for p in pts for c in p) + "}"


def building_lua(b):
    parts = [
        f"id={b['id']}", f"t={lua_str(b['t'])}", f"h={num(b['h'])}", f"lv={b['lv']}",
        f"p={flat_points(b['p'])}",
    ]
    if b["nm"]:
        parts.append(f"nm={lua_str(b['nm'])}")
    if b["st"]:
        parts.append(f"st={lua_str(b['st'])}")
        parts.append(f"sa={lua_str(abbreviate_street(b['st']))}")
    if b["hn"]:
        parts.append(f"hn={lua_str(b['hn'])}")
    if "rect" in b:
        cx, cz, L, W, ang = b["rect"]
        parts.append(f"rect={{{num(cx)},{num(cz)},{num(L)},{num(W)},{ang:.5f}}}")
    else:
        parts.append("tri={" + ",".join(str(i + 1) for t in b["tri"] for i in t) + "}")
    if b.get("plates"):
        parts.append("pl={" + ",".join("{" + ",".join(num(v) for v in pl) + "}" for pl in b["plates"]) + "}")
    if b["en"]:
        parts.append("en={" + ",".join(
            "{" + f"x={num(e['x'])},z={num(e['z'])},nx={num(e['nx'])},nz={num(e['nz'])},ref={lua_str(e['ref'])},flats={lua_str(e['flats'])},kind={lua_str(e['kind'])}" + "}"
            for e in b["en"]) + "}")
    return "{" + ",".join(parts) + "}"


def road_lua(r):
    parts = [f"id={r['id']}", f"t={lua_str(r['t'])}", f"w={num(r['w'])}", f"p={flat_points(r['p'])}"]
    if r["nm"]:
        parts.append(f"nm={lua_str(r['nm'])}")
    if r["br"]:
        parts.append("br=1")
    return "{" + ",".join(parts) + "}"


def area_lua(a):
    parts = [f"id={a['id']}", f"t={lua_str(a['t'])}", f"p={flat_points(a['p'])}",
             "tri={" + ",".join(str(i + 1) for t in a["tri"] for i in t) + "}"]
    if a["nm"]:
        parts.append(f"nm={lua_str(a['nm'])}")
    return "{" + ",".join(parts) + "}"


def poi_lua(p):
    return "{" + f"x={num(p['x'])},z={num(p['z'])},nm={lua_str(p['nm'])},k={lua_str(p['k'])}" + "}"


def chunk_key(x, z):
    return (math.floor(x / CHUNK_SIZE), math.floor(z / CHUNK_SIZE))


def write_modules(out_dir, buildings, roads, areas, pois, stats, bounds, spawn):
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        if f.endswith(".luau"):
            os.remove(os.path.join(out_dir, f))

    chunks = {}

    def add(kind, x, z, text):
        chunks.setdefault(chunk_key(x, z), {"b": [], "r": [], "a": [], "poi": []})[kind].append(text)

    for b in buildings:
        cx, cz = centroid(b["p"])
        add("b", cx, cz, building_lua(b))
    for r in roads:
        add("r", r["p"][0][0], r["p"][0][1], road_lua(r))
    for a in areas:
        cx, cz = centroid(a["p"])
        add("a", cx, cz, area_lua(a))
    for p in pois:
        add("poi", p["x"], p["z"], poi_lua(p))

    module_names = []
    header = "--!nocheck\n-- GENERATED by tools/osm_to_roblox.py. Map data (c) OpenStreetMap contributors, ODbL.\n"
    for (i, j), content in sorted(chunks.items()):
        # split into several modules if a chunk is too big
        parts, current, size = [], {"b": [], "r": [], "a": [], "poi": []}, 0
        for kind in ("a", "r", "b", "poi"):
            for item in content[kind]:
                if size + len(item) > MAX_MODULE_BYTES and size > 0:
                    parts.append(current)
                    current, size = {"b": [], "r": [], "a": [], "poi": []}, 0
                current[kind].append(item)
                size += len(item.encode("utf-8")) + 2
        parts.append(current)
        for k, part in enumerate(parts):
            name = f"Chunk_{i}_{j}" + (f"_{k}" if k else "")
            with open(os.path.join(out_dir, name + ".luau"), "w", encoding="utf-8") as fh:
                fh.write(header)
                fh.write(f"return {{cx={i},cz={j},\n")
                for kind in ("a", "r", "b", "poi"):
                    fh.write(f"{kind}={{\n" + ",\n".join(part[kind]) + "\n},\n")
                fh.write("}\n")
            module_names.append(name)

    street_names = sorted({b["st"] for b in buildings if b["st"]} | {r["nm"] for r in roads if r["nm"]})
    with open(os.path.join(out_dir, "Index.luau"), "w", encoding="utf-8") as fh:
        fh.write(header)
        fh.write("return {\n")
        fh.write("\tAttribution = \"Map data © OpenStreetMap contributors (ODbL)\",\n")
        fh.write(f"\tOrigin = {{lat={ORIGIN_LAT},lon={ORIGIN_LON}}},\n")
        fh.write(f"\tStudsPerMeter = {STUDS_PER_METER},\n")
        fh.write(f"\tChunkSize = {CHUNK_SIZE},\n")
        fh.write(f"\tBounds = {{minX={num(bounds[0])},minZ={num(bounds[1])},maxX={num(bounds[2])},maxZ={num(bounds[3])}}},\n")
        fh.write(f"\tSpawn = {{x={num(spawn[0])},z={num(spawn[1])}}},\n")
        fh.write("\tStats = {" + ",".join(f"{k}={v}" for k, v in stats.items()) + "},\n")
        fh.write("\tChunks = {" + ",".join(lua_str(n) for n in module_names) + "},\n")
        fh.write("\tStreets = {" + ",".join(lua_str(s) for s in street_names) + "},\n")
        fh.write("}\n")
    return module_names, street_names


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help=".osm XML files (merged)")
    ap.add_argument("--out", default="map/data", help="output folder for Luau modules")
    args = ap.parse_args()

    nodes, ways, relations = parse(args.inputs)
    buildings, roads, areas, pois, stats = build_features(nodes, ways, relations)
    if not buildings and not roads:
        sys.exit("No buildings or roads found: is this the right .osm file?")

    xs = [p[0] for b in buildings for p in b["p"]] + [p[0] for r in roads for p in r["p"]]
    zs = [p[1] for b in buildings for p in b["p"]] + [p[1] for r in roads for p in r["p"]]
    bounds = (min(xs), min(zs), max(xs), max(zs))

    # spawn: the point on a main road closest to the origin
    best = None
    for r in roads:
        if r["t"] in ("primary", "secondary", "tertiary", "residential", "trunk"):
            for a, b in zip(r["p"], r["p"][1:]):
                d, q = seg_point_distance((0, 0), a, b)
                if best is None or d < best[0]:
                    best = (d, q)
    spawn = best[1] if best else (0, 0)

    modules, streets = write_modules(args.out, buildings, roads, areas, pois, stats, bounds, spawn)
    print(f"buildings: {stats['buildings']} (with address {stats['with_address']}, with levels {stats['with_levels']})")
    print(f"address plates: {stats['plates']}, entrances: {stats['entrances']}")
    print(f"roads: {len(roads)}, areas: {len(areas)}, POIs: {len(pois)}, streets: {len(streets)}")
    print(f"modules: {len(modules)} -> {args.out}")
    print(f"bounds (studs): {tuple(round(v) for v in bounds)}  spawn: {tuple(round(v) for v in spawn)}")


if __name__ == "__main__":
    main()
