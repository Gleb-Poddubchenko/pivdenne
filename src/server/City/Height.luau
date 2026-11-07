--!strict
-- Height: ground height (studs, sea level = 0) anywhere on the map, from the
-- elevation grid in ServerStorage.MapData (tools/dem.py, AWS Terrain Tiles / SRTM).
--
-- Every grid cell is split into two triangles along the (c,r)-(c+1,r+1) diagonal,
-- exactly like TerrainBuilder sculpts it, and At() interpolates on those same
-- triangles. So buildings, roads, trees and lamps sit precisely on the terrain.
-- Without elevation data (or with Config.Map.TerrainGround off) everything is 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Height = {}

local loaded = false
local tried = false
local G, X0, Z0, COLS, ROWS = 1, 0, 0, 0, 0
local H: { number } = {} -- row-major, (r-1)*COLS + c
local MAT: { string } = {} -- one string per cell row
local CLIFFS: { { number } } = {}

function Height.Load(): boolean
	if tried then
		return loaded
	end
	tried = true
	if not Config.Map.TerrainGround or not Config.Map.Relief then
		return false
	end
	local folder = ServerStorage:FindFirstChild("MapData")
	local indexModule = folder and folder:FindFirstChild("Index")
	if not (folder and indexModule and indexModule:IsA("ModuleScript")) then
		return false
	end
	local ok, index = pcall(require, indexModule)
	if not ok or typeof(index) ~= "table" or not index.Height then
		return false
	end
	local meta = index.Height
	G, X0, Z0, COLS, ROWS = meta.Grid, meta.X0, meta.Z0, meta.Cols, meta.Rows
	for _, name in meta.Modules do
		local m = folder:FindFirstChild(name)
		if m and m:IsA("ModuleScript") then
			local part = require(m) :: any
			for i, v in part.h do
				H[(part.first - 1) * COLS + i] = v
			end
			for i, line in part.mat do
				MAT[part.first - 1 + i] = line
			end
		end
	end
	local cliffModule = folder:FindFirstChild("Cliffs")
	if cliffModule and cliffModule:IsA("ModuleScript") then
		CLIFFS = require(cliffModule) :: any
	end
	loaded = #H >= COLS * ROWS
	if not loaded then
		warn("[Height] Incomplete elevation grid; using a flat map")
	end
	return loaded
end

local function node(c: number, r: number): number
	return H[(r - 1) * COLS + c] or 0
end

-- Grid geometry for TerrainBuilder (1-based columns/rows).
function Height.Grid(): (number, number, number, number, number)
	return G, X0, Z0, COLS, ROWS
end

function Height.Node(c: number, r: number): number
	return node(c, r)
end

-- Material code of cell (c, r): g Ground, G Grass, L LeafyGrass, S Sand, A Asphalt, C Concrete, P Pavement.
function Height.CellMaterial(c: number, r: number): string
	local line = MAT[r]
	return if line then string.sub(line, c, c) else "g"
end

function Height.Cliffs(): { { number } }
	return CLIFFS
end

function Height.At(x: number, z: number): number
	if not loaded then
		return 0
	end
	local cf = (x - X0) / G
	local rf = (z - Z0) / G
	local c = math.floor(cf)
	local r = math.floor(rf)
	if c < 0 or r < 0 or c >= COLS - 1 or r >= ROWS - 1 then
		return 0
	end
	local fx, fz = cf - c, rf - r
	c += 1
	r += 1
	local h00, h10, h01, h11 = node(c, r), node(c + 1, r), node(c, r + 1), node(c + 1, r + 1)
	if fx >= fz then
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	end
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)
end

-- GROUND PROBING ------------------------------------------------------------
-- Once the terrain exists, Ground() raycasts straight down onto it, so objects sit
-- on the terrain that is really there, whatever the heightmap maths says. Before
-- that (or where the ray misses) it falls back to At().

local terrainReady = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

function Height.SetTerrainReady(ready: boolean)
	terrainReady = ready
	rayParams.FilterDescendantsInstances = { workspace.Terrain }
end

-- Terrain surface height under (x, z) by raycast, or nil if there is no terrain.
function Height.Probe(x: number, z: number): number?
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -2600, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

function Height.Ground(x: number, z: number): number
	if terrainReady then
		local y = Height.Probe(x, z)
		if y then
			return y
		end
	end
	return Height.At(x, z)
end

-- Lowest and highest ground under a set of points (flat x,z list).
function Height.Range(flat: { number }): (number, number)
	local lo, hi = math.huge, -math.huge
	for i = 1, #flat - 1, 2 do
		local h = Height.Ground(flat[i], flat[i + 1])
		lo = math.min(lo, h)
		hi = math.max(hi, h)
	end
	if lo == math.huge then
		return 0, 0
	end
	return lo, hi
end

return Height
