#!/usr/bin/env bash
# Download OpenStreetMap data and elevation tiles for Yuzhne/Pivdenne and convert
# them for Roblox.
#
#   bash tools/fetch_osm.sh          # download + convert
#
# Uses the main OSM API (/api/0.6/map) in 2x2 tiles (each well under its 50 000
# node limit). Bounding box = the Pivdenne city boundary (OSM relation 3606547)
# padded by ~400 m so the edge of the port area and the coast are included.
# Map data (c) OpenStreetMap contributors, ODbL 1.0.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p data

MIN_LON=31.0700
MIN_LAT=46.6090
MAX_LON=31.1190
MAX_LAT=46.6445
UA="YuzhneRobloxMapBuilder/1.0 (personal project)"

mid_lon=$(python3 -c "print(($MIN_LON+$MAX_LON)/2)")
mid_lat=$(python3 -c "print(($MIN_LAT+$MAX_LAT)/2)")

tiles=(
  "$MIN_LON,$MIN_LAT,$mid_lon,$mid_lat"
  "$mid_lon,$MIN_LAT,$MAX_LON,$mid_lat"
  "$MIN_LON,$mid_lat,$mid_lon,$MAX_LAT"
  "$mid_lon,$mid_lat,$MAX_LON,$MAX_LAT"
)

files=()
for i in "${!tiles[@]}"; do
  out="data/pivdenne_$i.osm"
  echo "Downloading tile $((i + 1))/4 (${tiles[$i]})"
  curl -fsS -A "$UA" -o "$out" "https://api.openstreetmap.org/api/0.6/map?bbox=${tiles[$i]}"
  files+=("$out")
  sleep 2 # be polite to the OSM API
done

# Elevation (hills, valleys, coastal cliffs): AWS Terrain Tiles, a little larger than the OSM box.
python3 tools/dem.py download 31.055 46.598 31.135 46.660

python3 tools/osm_to_roblox.py "${files[@]}" --out map/data --dem data/dem
echo "Done. Sync with Rojo (map/data -> ServerStorage.MapData) and press Play."
