--!strict
-- TerrainBuilder: sculpts the real relief of Pivdenne into Roblox Terrain.
--
--   1. Heightmap: every grid cell = a solid FillBlock column up to its lowest
--      corner (12-stud crust, never mis-oriented) plus a thin FillWedge cap made of
--      the same two triangles Height.At() interpolates on.
--      Material per cell from OSM areas (parks = grass, beaches = sand, parking =
--      asphalt ...); steep faces become loess (yellow-brown Sandstone).
--   2. Coastal cliffs: along coastline segments flagged by the converter, a sand
--      beach is cut at the waterline and a near-vertical loess cliff rises behind
--      it to the plateau.
-- The sea itself is added afterwards by StreetDetails.Coast (water replaces the
-- terrain on the water side of the coastline).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Geometry = require(script.Parent.Geometry)
local Height = require(script.Parent.Height)

local M = Config.Meters

local TerrainBuilder = {}

local MATERIALS: { [string]: Enum.Material } = {
	g = Enum.Material.Ground,
	G = Enum.Material.Grass,
	L = Enum.Material.LeafyGrass,
	S = Enum.Material.Sand,
	A = Enum.Material.Asphalt,
	C = Enum.Material.Concrete,
	P = Enum.Material.Pavement,
}
local CLIFF_MATERIAL = Enum.Material.Sandstone

local function slab(terrain: Terrain, a: Vector3, b: Vector3, c: Vector3, floor: number, material: Enum.Material)
	local top = math.max(a.Y, b.Y, c.Y)
	local thickness = top - floor + 4
	local cf1, s1, cf2, s2 = Geometry.WedgePair(a, b, c, thickness)
	if not (cf1 and s1 and cf2 and s2) then
		return
	end
	-- WedgePair centres the slab on the triangle; push it down so its top face is the surface.
	local n = cf1.RightVector
	local down = if n.Y > 0 then -n else n
	local shift = down * (thickness / 2)
	terrain:FillWedge(cf1 + shift, s1, material)
	terrain:FillWedge(cf2 + shift, s2, material)
end

function TerrainBuilder.SetColours(terrain: Terrain)
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(122, 118, 80))
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(104, 132, 70))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(84, 116, 58))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(214, 196, 150))
	terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(190, 160, 112)) -- loess cliffs
	terrain:SetMaterialColor(Enum.Material.Asphalt, Color3.fromRGB(78, 78, 80))
	terrain.WaterColor = Color3.fromRGB(28, 92, 110) -- Black Sea green-blue
	terrain.WaterWaveSize = 0.12
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.6
end

-- Returns false when there is no elevation data (caller then uses flat ground).
function TerrainBuilder.Build(tick: () -> ()): boolean
	if not Height.Load() then
		return false
	end
	local terrain = workspace.Terrain
	TerrainBuilder.SetColours(terrain)
	local G, X0, Z0, COLS, ROWS = Height.Grid()
	local floor = -Config.Map.SeaDepth - 8
	local steep = math.tan(math.rad(30))
	local CRUST = 12 -- studs of solid ground under the surface (enough to stand, cheap to replicate)

	for r = 1, ROWS - 1 do
		workspace:SetAttribute("CityProgress", 0.5 * r / ROWS) -- terrain = first half of the build
		for c = 1, COLS - 1 do
			local x, z = X0 + (c - 1) * G, Z0 + (r - 1) * G
			local p00 = Vector3.new(x, Height.Node(c, r), z)
			local p10 = Vector3.new(x + G, Height.Node(c + 1, r), z)
			local p01 = Vector3.new(x, Height.Node(c, r + 1), z + G)
			local p11 = Vector3.new(x + G, Height.Node(c + 1, r + 1), z + G)
			local material = MATERIALS[Height.CellMaterial(c, r)] or Enum.Material.Ground
			local rise = math.max(math.abs(p10.Y - p00.Y), math.abs(p01.Y - p00.Y), math.abs(p11.Y - p10.Y), math.abs(p11.Y - p01.Y))
			if rise / G > steep then
				material = CLIFF_MATERIAL
			end
			-- 1) solid axis-aligned column up to the cell's LOWEST corner: unambiguous, so
			--    there is always walkable ground within a few studs of the real surface
			local lo = math.min(p00.Y, p10.Y, p01.Y, p11.Y)
			local hi = math.max(p00.Y, p10.Y, p01.Y, p11.Y)
			local bottom = if lo < 8 then math.min(lo - CRUST, -Config.Map.SeaDepth - 4) else lo - CRUST
			terrain:FillBlock(CFrame.new(x + G / 2, (bottom + lo) / 2, z + G / 2), Vector3.new(G, lo - bottom, G), material)
			-- 2) thin sloped cap: the two triangles Height.At() interpolates on
			if hi - lo > 0.5 then
				slab(terrain, p00, p10, p11, lo - 2, material)
				slab(terrain, p00, p11, p01, lo - 2, material)
			end
			tick() -- per cell: the caller yields when its frame budget is used up
		end
	end

	-- Coastal cliffs over a sand beach.
	local beach, run = M(Config.Map.CliffBeach), M(Config.Map.CliffRun)
	local toeY = M(1)
	for _, seg in Height.Cliffs() do
		local a = Vector3.new(seg[1], 0, seg[2])
		local b = Vector3.new(seg[3], 0, seg[4])
		local top = seg[5]
		local d = b - a
		local len = d.Magnitude
		if len > 1 then
			local dir = d / len
			local land = Vector3.new(dir.Z, 0, -dir.X) -- OSM: land is left of the coastline
			local mid = (a + b) / 2
			local width = len + 8
			local right = Vector3.yAxis:Cross(land)
			local function frame(offset: number, y: number): CFrame
				return CFrame.fromMatrix(mid + land * offset + Vector3.new(0, y, 0), right, Vector3.yAxis, land)
			end
			-- clear everything above the beach, then lay sand
			terrain:FillBlock(frame(beach / 2, toeY + 60), Vector3.new(width, 120, beach), Enum.Material.Air)
			terrain:FillBlock(frame(beach / 2, (toeY + floor) / 2), Vector3.new(width, toeY - floor, beach), Enum.Material.Sand)
			-- the cliff face (wedge rising towards the land) and the ground behind its edge
			local h = top - toeY
			terrain:FillWedge(frame(beach + run / 2, toeY + h / 2), Vector3.new(width, h, run), CLIFF_MATERIAL)
			local backDepth = M(30)
			terrain:FillBlock(frame(beach + run + backDepth / 2, (top + floor) / 2), Vector3.new(width, top - floor, backDepth), Enum.Material.Ground)
			terrain:FillBlock(frame(beach + run / 2, (toeY + floor) / 2), Vector3.new(width, toeY - floor, run), CLIFF_MATERIAL)
		end
		tick()
	end
	Height.SetTerrainReady(true)
	return true
end

-- Raycasts the built terrain at grid nodes and compares with the heightmap.
-- Returns samples, missing (no terrain at all), mean and max |error| in studs.
function TerrainBuilder.Verify(samples: number): (number, number, number, number)
	local G, X0, Z0, COLS, ROWS = Height.Grid()
	local missing, sum, worst, n = 0, 0, 0, 0
	local rng = Random.new(42)
	for _ = 1, samples do
		local c, r = rng:NextInteger(2, math.max(2, COLS - 2)), rng:NextInteger(2, math.max(2, ROWS - 2))
		local x, z = X0 + (c - 1) * G + G * 0.37, Z0 + (r - 1) * G + G * 0.61
		local expected = Height.At(x, z)
		local got = Height.Probe(x, z)
		n += 1
		if not got then
			missing += 1
		elseif expected > 1 then -- skip sea / beach where water and cliffs reshape the ground
			local err = math.abs(got - expected)
			sum += err
			worst = math.max(worst, err)
		end
	end
	return n, missing, if n - missing > 0 then sum / (n - missing) else 0, worst
end

return TerrainBuilder
