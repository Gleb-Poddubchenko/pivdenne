--!strict
-- StreetDetails: street-level realism built from the "detail" lists the converter
-- writes into each chunk (see tools/osm_details.py). Real OSM objects where they
-- are mapped, reproducible generated fill where OSM is empty.
--   co  coastline pieces        -> Terrain sea on the water side (right of the way)
--   rl  railway polylines       -> ballast + two rails at 1520 mm gauge
--   tr  trees (x, z, size, real)-> trunk + ellipsoid crown (poplar / round crowns)
--   lp  street lamps            -> concrete pole, arm towards the road, lamp head
--   cw  crossings               -> zebra stripes across the road
--   bs  bus stops               -> shelter with the real stop name
--   bn  benches, wc rubbish containers

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Geometry = require(script.Parent.Geometry)
local Height = require(script.Parent.Height)

local M = Config.Meters

local StreetDetails = {}

local CONCRETE = Color3.fromRGB(165, 162, 155)
local LAMP_GLASS = Color3.fromRGB(235, 225, 190)
local CROWNS = {
	Color3.fromRGB(74, 112, 52),
	Color3.fromRGB(88, 124, 58),
	Color3.fromRGB(64, 100, 50),
	Color3.fromRGB(98, 130, 66),
}

local function hash2(x: number, z: number): number
	return math.floor(math.abs(x * 73.13 + z * 19.7) * 1000) % 1000003
end

local function nocollide(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- SEA ---------------------------------------------------------------------------

function StreetDetails.Coast(flat: { number })
	local terrain = workspace.Terrain
	local extrude = Config.Map.SeaExtrude
	local depth = Config.Map.SeaDepth
	for i = 1, #flat // 2 - 1 do
		local a = Vector3.new(flat[2 * i - 1], 0, flat[2 * i])
		local b = Vector3.new(flat[2 * i + 1], 0, flat[2 * i + 2])
		local d = b - a
		local len = d.Magnitude
		if len > 0.5 then
			local dir = d / len
			local sea = Vector3.new(-dir.Z, 0, dir.X) -- OSM: water is to the right of the coastline
			local center = (a + b) / 2 + sea * (extrude / 2) + Vector3.new(0, -depth / 2, 0)
			terrain:FillBlock(CFrame.fromMatrix(center, dir, Vector3.yAxis), Vector3.new(len + 8, depth, extrude), Enum.Material.Water)
		end
	end
end

-- RAILWAY -------------------------------------------------------------------------

function StreetDetails.Railway(parent: Instance, flat: { number })
	local gauge = M(1.52)
	for i = 1, #flat // 2 - 1 do
		local ax, az, bx, bz = flat[2 * i - 1], flat[2 * i], flat[2 * i + 1], flat[2 * i + 2]
		local a = Vector3.new(ax, Height.At(ax, az), az)
		local b = Vector3.new(bx, Height.At(bx, bz), bz)
		local len = (b - a).Magnitude
		if len > 0.2 then
			local mid = (a + b) / 2
			local cf = CFrame.lookAt(mid, b)
			Geometry.Part(parent, "Ballast", Vector3.new(M(3), 0.4, len), cf * CFrame.new(0, 0.2, 0), Color3.fromRGB(110, 104, 98), Enum.Material.Pebble)
			for _, side in { -1, 1 } do
				local rail = Geometry.Part(parent, "Rail", Vector3.new(0.25, 0.3, len), cf * CFrame.new(side * gauge / 2, 0.55, 0),
					Color3.fromRGB(95, 85, 80), Enum.Material.Metal)
				rail.CastShadow = false
			end
		end
	end
end

-- TREES -----------------------------------------------------------------------------

function StreetDetails.Tree(parent: Instance, x: number, z: number, size: number)
	local h = hash2(x, z)
	local poplar = h % 5 == 0 -- pyramidal poplars line many Soviet-era streets
	local height = M(if poplar then 13 else 8) * size
	local trunkH = height * (if poplar then 0.3 else 0.4)
	local gy = Height.At(x, z)
	local trunk = Geometry.Part(parent, "Trunk", Vector3.new(trunkH, M(0.35) * size, M(0.35) * size),
		CFrame.new(x, gy + trunkH / 2, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(92, 72, 56), Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CastShadow = false

	local crownH = height - trunkH * 0.8
	local width = if poplar then crownH * 0.35 else crownH * (0.8 + (h % 7) / 20)
	local crown = Geometry.Part(parent, "Crown", Vector3.new(1, 1, 1), CFrame.new(x, gy + trunkH * 0.8 + crownH / 2, z),
		CROWNS[h % #CROWNS + 1], Enum.Material.LeafyGrass)
	nocollide(crown)
	crown.CastShadow = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(width, crownH, width * (0.9 + (h % 3) / 10))
	mesh.Parent = crown
end

-- STREET LAMPS ---------------------------------------------------------------------
-- Concrete pole, arm reaching over the road. The light itself is switched on at
-- night, near the player, by the client (NightLightsController).

function StreetDetails.Lamp(parent: Instance, x: number, z: number, angle: number)
	local poleH = M(8.5)
	local toward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local base = Vector3.new(x, Height.At(x, z), z)
	Geometry.Part(parent, "LampPole", Vector3.new(M(0.22), poleH, M(0.22)), CFrame.new(base + Vector3.new(0, poleH / 2, 0)), CONCRETE, Enum.Material.Concrete)
	local armLen = M(1.6)
	local armMid = base + Vector3.new(0, poleH - 0.3, 0) + toward * (armLen / 2)
	local arm = Geometry.Part(parent, "LampArm", Vector3.new(0.25, 0.25, armLen), CFrame.lookAt(armMid, armMid + toward), Color3.fromRGB(110, 110, 112), Enum.Material.Metal)
	nocollide(arm)
	local headPos = base + Vector3.new(0, poleH - 0.6, 0) + toward * armLen
	local head = Geometry.Part(parent, "LampHead", Vector3.new(M(0.35), M(0.15), M(0.6)), CFrame.lookAt(headPos, headPos + toward), LAMP_GLASS, Enum.Material.SmoothPlastic)
	nocollide(head)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 110
	light.Range = M(14)
	light.Brightness = 2.2
	light.Color = Color3.fromRGB(255, 196, 120) -- sodium-orange
	light.Enabled = false
	light.Parent = head
	CollectionService:AddTag(head, "StreetLamp")
end

-- ZEBRA CROSSINGS --------------------------------------------------------------------

function StreetDetails.Crossing(parent: Instance, x: number, z: number, angle: number, width: number)
	local along = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local across = Vector3.new(-along.Z, 0, along.X)
	local stripe = M(0.5)
	local count = math.max(2, math.floor(width / (2 * stripe)))
	local center = Vector3.new(x, Height.At(x, z) + 0.3, z)
	for i = 0, count - 1 do
		local offset = (i - (count - 1) / 2) * 2 * stripe
		local pos = center + across * offset
		local s = Geometry.Part(parent, "Zebra", Vector3.new(stripe, 0.05, M(3)), CFrame.lookAt(pos, pos + along), Color3.fromRGB(236, 236, 230))
		nocollide(s)
	end
end

-- BUS STOP ------------------------------------------------------------------------------

function StreetDetails.BusStop(parent: Instance, x: number, z: number, angle: number, name: string)
	local toward = Vector3.new(math.cos(angle), 0, math.sin(angle)) -- towards the road
	local base = Vector3.new(x, Height.At(x, z), z)
	local cf = CFrame.lookAt(base, base + toward) -- open side faces the road
	local w, h = M(3.2), M(2.4)
	local frame = Color3.fromRGB(70, 110, 160)
	Geometry.Part(parent, "ShelterBack", Vector3.new(w, h, 0.25), cf * CFrame.new(0, h / 2, M(0.7)), frame, Enum.Material.Metal)
	Geometry.Part(parent, "ShelterRoof", Vector3.new(w + 0.6, 0.3, M(1.6)), cf * CFrame.new(0, h + 0.15, 0), frame, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		Geometry.Part(parent, "ShelterSide", Vector3.new(0.2, h, M(1.4)), cf * CFrame.new(side * w / 2, h / 2, 0), Color3.fromRGB(180, 210, 230), Enum.Material.Glass).Transparency = 0.5
	end
	Geometry.Part(parent, "ShelterBench", Vector3.new(w * 0.8, 0.3, M(0.4)), cf * CFrame.new(0, M(0.45), M(0.45)), Color3.fromRGB(120, 85, 55), Enum.Material.Wood)
	if name ~= "" then
		local signPart = Geometry.Part(parent, "StopSign", Vector3.new(M(0.6), M(0.6), 0.1), cf * CFrame.new(w / 2 + 1.5, M(2.6), 0), Color3.fromRGB(255, 255, 255))
		nocollide(signPart)
		Geometry.Part(parent, "StopPole", Vector3.new(0.2, M(2.6), 0.2), cf * CFrame.new(w / 2 + 1.5, M(1.3), 0), Color3.fromRGB(120, 120, 120), Enum.Material.Metal)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(180, 40)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.MaxDistance = 120
		bb.Parent = signPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(0, 87, 183)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = "🚌 " .. name
		label.Parent = bb
	end
end

-- BENCHES / BINS ----------------------------------------------------------------------

function StreetDetails.Bench(parent: Instance, x: number, z: number, angle: number)
	local facing = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local base = Vector3.new(x, Height.At(x, z), z)
	local cf = CFrame.lookAt(base, base + facing)
	local wood = Color3.fromRGB(150, 100, 55)
	Geometry.Part(parent, "BenchSeat", Vector3.new(M(1.8), 0.25, M(0.45)), cf * CFrame.new(0, M(0.45), 0), wood, Enum.Material.WoodPlanks)
	Geometry.Part(parent, "BenchBack", Vector3.new(M(1.8), M(0.4), 0.2), cf * CFrame.new(0, M(0.75), M(0.22)), wood, Enum.Material.WoodPlanks)
	for _, side in { -1, 1 } do
		Geometry.Part(parent, "BenchLeg", Vector3.new(0.3, M(0.45), M(0.45)), cf * CFrame.new(side * M(0.75), M(0.22), 0), CONCRETE, Enum.Material.Concrete)
	end
end

function StreetDetails.Bins(parent: Instance, x: number, z: number)
	local gy = Height.At(x, z)
	for i = -1, 1 do
		local bin = Geometry.Part(parent, "Container", Vector3.new(M(1.0), M(1.1), M(0.9)), CFrame.new(x + i * M(1.15), gy + M(0.55), z),
			Color3.fromRGB(50, 110, 70), Enum.Material.Metal)
		bin.CastShadow = false
	end
end

-- Builds every detail list of one chunk. tick() lets the caller yield.
function StreetDetails.BuildChunk(parent: Instance, chunk: any, tick: () -> ())
	local cfg = Config.Map
	if cfg.TerrainGround and chunk.co then
		for _, piece in chunk.co do
			StreetDetails.Coast(piece)
			tick()
		end
	end
	if cfg.StreetFurniture then
		for _, piece in chunk.rl or {} do
			StreetDetails.Railway(parent, piece)
			tick()
		end
		for _, bs in chunk.bs or {} do
			StreetDetails.BusStop(parent, bs.x, bs.z, bs.a, bs.nm)
		end
		for _, bn in chunk.bn or {} do
			StreetDetails.Bench(parent, bn[1], bn[2], bn[3])
		end
		for _, wc in chunk.wc or {} do
			StreetDetails.Bins(parent, wc[1], wc[2])
		end
	end
	if cfg.RoadMarkings then
		for _, cw in chunk.cw or {} do
			StreetDetails.Crossing(parent, cw[1], cw[2], cw[3], cw[4])
		end
	end
	if cfg.StreetLamps then
		for _, lp in chunk.lp or {} do
			StreetDetails.Lamp(parent, lp[1], lp[2], lp[3])
			tick()
		end
	end
	if cfg.Trees and chunk.tr then
		local t = chunk.tr
		for i = 1, #t - 3, 4 do
			StreetDetails.Tree(parent, t[i], t[i + 1], t[i + 2])
			tick()
		end
	end
end

return StreetDetails
