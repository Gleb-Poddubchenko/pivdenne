--!strict
-- CityBuilder: turns the generated OSM chunks (ServerStorage.MapData) into the
-- city: ground, areas (parks, water, beach), roads, buildings, address plates,
-- entrance canopies and POI labels.
--
-- Two ways to use it:
--   * runtime (default): CityService builds it on server start, spread over frames
--   * bake (recommended for release): in Studio's command bar run
--       require(game.ServerScriptService.Server.City.CityBuilder).Build(workspace)
--     then save the place and set Config.Map.BuildAtRuntime = false.
--
-- Rectangular footprints (most panel blocks) become ONE box part plus a roof slab
-- and window bands; other shapes become wall segments and a triangulated roof.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Geometry = require(script.Parent.Geometry)
local AddressPlates = require(script.Parent.AddressPlates)
local EntrancePlanner = require(script.Parent.Parent.Building.EntrancePlanner)
local EntranceBuilder = require(script.Parent.Parent.Building.EntranceBuilder)
local StreetDetails = require(script.Parent.StreetDetails)
local Height = require(script.Parent.Height)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local Facade = require(script.Parent.Facade)

local M = Config.Meters
local FLOOR_H = M(2.8)
local WALL_T = 0.8

local CityBuilder = {}

local PALETTE: { [string]: { Color3 } } = {
	panel = { Color3.fromRGB(205, 200, 190), Color3.fromRGB(214, 206, 186), Color3.fromRGB(190, 190, 185) },
	panel5 = { Color3.fromRGB(205, 200, 190), Color3.fromRGB(218, 208, 182), Color3.fromRGB(196, 186, 168) },
	panel9 = { Color3.fromRGB(210, 206, 198), Color3.fromRGB(200, 196, 188), Color3.fromRGB(220, 212, 194) },
	panel_high = { Color3.fromRGB(214, 212, 206), Color3.fromRGB(196, 198, 200) },
	house = { Color3.fromRGB(236, 226, 196), Color3.fromRGB(240, 214, 150), Color3.fromRGB(220, 230, 236), Color3.fromRGB(232, 232, 226), Color3.fromRGB(214, 170, 140) },
	garage = { Color3.fromRGB(150, 146, 140), Color3.fromRGB(160, 120, 100) },
	industrial = { Color3.fromRGB(160, 160, 158), Color3.fromRGB(140, 146, 150) },
	public = { Color3.fromRGB(236, 214, 170), Color3.fromRGB(226, 196, 170), Color3.fromRGB(230, 230, 220) },
	commercial = { Color3.fromRGB(240, 240, 236), Color3.fromRGB(220, 225, 230) },
	other = { Color3.fromRGB(200, 196, 190) },
}
local ROOF = Color3.fromRGB(80, 78, 76)
local WINDOW = Color3.fromRGB(70, 86, 100)

local AREA_STYLE: { [string]: { Color3 | Enum.Material } } = {
	park = { Color3.fromRGB(96, 140, 70), Enum.Material.Grass },
	grass = { Color3.fromRGB(110, 145, 75), Enum.Material.Grass },
	forest = { Color3.fromRGB(70, 110, 55), Enum.Material.LeafyGrass },
	playground = { Color3.fromRGB(190, 160, 120), Enum.Material.Sand },
	pitch = { Color3.fromRGB(80, 130, 70), Enum.Material.Grass },
	water = { Color3.fromRGB(60, 110, 150), Enum.Material.Glass },
	beach = { Color3.fromRGB(222, 205, 160), Enum.Material.Sand },
	parking = { Color3.fromRGB(85, 85, 88), Enum.Material.Asphalt },
	garages = { Color3.fromRGB(110, 110, 108), Enum.Material.Concrete },
	industrial = { Color3.fromRGB(125, 125, 120), Enum.Material.Concrete },
	school_ground = { Color3.fromRGB(150, 160, 120), Enum.Material.Ground },
	market = { Color3.fromRGB(140, 135, 128), Enum.Material.Pavement },
}

-- Vertical layering avoids z-fighting between overlapping flat things.
local ROAD_Y: { [string]: number } = {
	trunk = 0.16, primary = 0.15, secondary = 0.14, tertiary = 0.13,
	residential = 0.12, unclassified = 0.12, living_street = 0.11, service = 0.1,
	pedestrian = 0.09, footway = 0.08, path = 0.08, cycleway = 0.08, steps = 0.08, track = 0.07,
}

local POI_ICONS: { [string]: string } = {
	["amenity=school"] = "🏫", ["amenity=kindergarten"] = "🧸", ["amenity=marketplace"] = "🛒",
	["amenity=bus_station"] = "🚌", ["public_transport=station"] = "🚌", ["highway=bus_stop"] = "🚏",
	["amenity=hospital"] = "🏥", ["amenity=clinic"] = "🏥", ["amenity=pharmacy"] = "✚",
	["amenity=townhall"] = "🏛", ["amenity=place_of_worship"] = "⛪", ["amenity=library"] = "📚",
	["amenity=post_office"] = "✉", ["amenity=police"] = "🚓", ["amenity=fuel"] = "⛽",
	["amenity=cafe"] = "☕", ["amenity=restaurant"] = "🍽", ["amenity=bank"] = "🏦",
	["leisure=park"] = "🌳", ["leisure=stadium"] = "🏟", ["tourism=hotel"] = "🏨",
}

-- Generic labels used instead of chain/brand names (Config.Map.ShowBrandNames = false).
local GENERIC: { [string]: string } = {
	["shop=supermarket"] = "Супермаркет", ["shop=convenience"] = "Продукти", ["shop=bakery"] = "Хліб",
	["shop=clothes"] = "Одяг", ["shop=hardware"] = "Господарські товари", ["shop=doityourself"] = "Будматеріали",
	["shop=mobile_phone"] = "Мобільний зв'язок", ["shop=electronics"] = "Електроніка", ["shop=florist"] = "Квіти",
	["shop=butcher"] = "М'ясо", ["shop=alcohol"] = "Напої", ["shop=car_repair"] = "СТО",
	["amenity=pharmacy"] = "Аптека", ["amenity=fuel"] = "АЗС", ["amenity=bank"] = "Банк",
}

local function hash(n: number): number
	return (n * 2654435761) % 4294967296
end

local function pick(list: { Color3 }, id: number): Color3
	return list[hash(id) % #list + 1]
end

local function labelText(kind: string, name: string): string?
	local brandish = string.sub(kind, 1, 5) == "shop="
		or kind == "amenity=pharmacy" or kind == "amenity=fuel" or kind == "amenity=bank"
	local text = name
	if brandish and not Config.Map.ShowBrandNames then
		text = GENERIC[kind] or "Магазин"
	end
	local icon = POI_ICONS[kind]
	if not icon and not brandish then
		return nil -- only label things players navigate by
	end
	return (if icon then icon .. " " else "") .. text
end

local function addLabel(parent: Instance, position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Name = "Label"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = position
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 26)
	bb.MaxDistance = Config.Map.LabelDistance
	bb.AlwaysOnTop = false
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = bb
	anchor.Parent = parent
end

-- SERVICES AT REAL LOCATIONS ----------------------------------------------------
-- Real shops / pharmacies / markets from OSM get working game counters right
-- where they are in the city (just outside their building, facing the street).

local TILL_CATALOG: { [string]: string } = {
	["shop=convenience"] = "Grocery",
	["shop=supermarket"] = "Grocery",
	["shop=bakery"] = "Grocery",
	["shop=kiosk"] = "Kiosk",
	["amenity=pharmacy"] = "Pharmacy",
}
local EQUIPMENT_KINDS: { [string]: boolean } = {
	["shop=sports"] = true, ["shop=outdoor"] = true, ["shop=fishing"] = true,
	["shop=hardware"] = true, ["shop=doityourself"] = true,
}

local function counterFrame(poi: any): CFrame
	local normal = Vector3.new(poi.nx or 0, 0, poi.nz or 0)
	local pos = Vector3.new(poi.x, Height.Ground(poi.x, poi.z), poi.z)
	if normal.Magnitude < 0.5 then
		normal = Vector3.new(0, 0, -1)
	end
	-- Front face (-Z) of the counter looks out to the street.
	return CFrame.lookAt(pos, pos + normal.Unit)
end

local function serviceAt(parent: Instance, poi: any)
	local catalog = TILL_CATALOG[poi.k]
	local isMarket = poi.k == "amenity=marketplace"
	if not (catalog or isMarket or EQUIPMENT_KINDS[poi.k]) then
		return
	end
	local base = counterFrame(poi)
	local id = ("osm_%d_%d"):format(math.floor(poi.x), math.floor(poi.z))
	local display = labelText(poi.k, poi.nm) or "Магазин"

	if catalog then
		local shop = Instance.new("Model")
		shop.Name = "Shop_" .. id
		shop:SetAttribute("ShopId", id)
		shop:SetAttribute("Catalog", catalog)
		shop:SetAttribute("DisplayName", display)
		Geometry.Part(shop, "Counter", Vector3.new(M(1.6), M(1.0), M(0.6)), base * CFrame.new(0, M(0.5), 0),
			Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
		Geometry.Part(shop, "Till", Vector3.new(M(0.4), M(0.25), M(0.35)), base * CFrame.new(M(0.4), M(1.0) + M(0.125), 0),
			Color3.fromRGB(50, 50, 55))
		shop.Parent = parent
		CollectionService:AddTag(shop, "Shop")
	end
	if EQUIPMENT_KINDS[poi.k] or isMarket then
		local offset = if isMarket then CFrame.new(M(2.2), 0, 0) else CFrame.new()
		local stall = Geometry.Part(parent, "EquipmentShop", Vector3.new(M(1.6), M(1.0), M(0.6)), base * offset * CFrame.new(0, M(0.5), 0),
			Color3.fromRGB(40, 120, 60), Enum.Material.Wood)
		CollectionService:AddTag(stall, "EquipmentShop")
	end
	if isMarket then
		local fish = Geometry.Part(parent, "FishBuyer", Vector3.new(M(1.6), M(1.0), M(0.6)), base * CFrame.new(-M(2.2), M(0.5), 0),
			Color3.fromRGB(70, 110, 150), Enum.Material.Wood)
		CollectionService:AddTag(fish, "FishBuyer")
	end
end

-- BUILDINGS -------------------------------------------------------------------

local function windowBands(parent: Instance, cf: CFrame, length: number, width: number, floors: number)
	for f = 1, floors do
		local y = (f - 1) * FLOOR_H + M(1.0) + M(0.75)
		for _, side in { -1, 1 } do
			local band = Geometry.Part(parent, "Windows", Vector3.new(length * 0.94, M(1.3), 0.1),
				cf * CFrame.new(0, y, side * (width / 2 + 0.05)), WINDOW, Enum.Material.Glass)
			band.CanCollide = false
			band.CanQuery = false
			band.Reflectance = 0.15
			CollectionService:AddTag(band, "WindowBand") -- some light up at night (client)
		end
	end
end

local function entranceDetail(parent: Instance, e: any, height: number)
	local normal = Vector3.new(e.nx, 0, e.nz)
	if normal.Magnitude < 0.5 then
		return
	end
	normal = normal.Unit
	local base = Vector3.new(e.x, Height.Ground(e.x, e.z), e.z)
	local face = CFrame.lookAt(base, base + normal) -- LookVector = outward
	local door = Geometry.Part(parent, "EntranceDoor", Vector3.new(M(1.0), M(2.1), 0.3), face * CFrame.new(0, M(1.05), -0.15),
		Color3.fromRGB(74, 58, 46), Enum.Material.DiamondPlate)
	door.CanCollide = true
	if height > M(3) then
		Geometry.Part(parent, "Canopy", Vector3.new(M(2.4), M(0.15), M(1.3)), face * CFrame.new(0, M(2.6), -M(0.65)),
			Color3.fromRGB(190, 186, 178), Enum.Material.Concrete)
	end
	local text = ""
	if e.ref ~= "" then
		text = "Під'їзд " .. e.ref
	end
	if e.flats ~= "" then
		text ..= (if text ~= "" then "\n" else "") .. "кв. " .. e.flats
	end
	if text ~= "" then
		local plate = Geometry.Part(parent, "EntrancePlate", Vector3.new(M(0.5), M(0.3), 0.08), face * CFrame.new(0, M(2.35), -0.05),
			Color3.fromRGB(18, 58, 140))
		plate.CanCollide = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.MaxDistance = 80
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = text
		label.Parent = gui
	end
end

local function buildBuilding(parent: Instance, b: any): (number, number, Model)
	local model = Instance.new("Model")
	model.Name = if b.hn and b.st then ("%s, %s"):format(b.st, b.hn) else ("Building_" .. b.id)
	model:SetAttribute("OsmId", b.id)
	model:SetAttribute("Type", b.t)
	model:SetAttribute("Levels", b.lv)
	if b.st then
		model:SetAttribute("Street", b.st)
	end
	if b.hn then
		model:SetAttribute("HouseNumber", b.hn)
	end
	if b.nm then
		model:SetAttribute("Name", b.nm)
	end

	-- Real OSM colours/material when mapped, otherwise a typology palette.
	local color = Facade.ParseColour(b.bc) or pick(PALETTE[b.t] or PALETTE.other, b.id)
	local roofColor = Facade.ParseColour(b.rc) or ROOF
	local h: number = b.h
	-- On a slope the building stands on its lowest corner; the hillside covers the rest.
	local y0 = Height.Range(b.p)
	model:SetAttribute("GroundY", y0)
	local material = Facade.ParseMaterial(b.mat)
		or (if b.t == "house" or b.t == "garage" then Enum.Material.Brick else Enum.Material.Concrete)

	if b.rect then
		local cx, cz, L, W, angle = b.rect[1], b.rect[2], b.rect[3], b.rect[4], b.rect[5]
		local base = CFrame.new(cx, y0, cz) * CFrame.Angles(0, -angle, 0)
		Geometry.Part(model, "Body", Vector3.new(L, h, W), base * CFrame.new(0, h / 2, 0), color, material)
		Geometry.Part(model, "Roof", Vector3.new(L + 0.4, 0.5, W + 0.4), base * CFrame.new(0, h + 0.25, 0), roofColor, Enum.Material.Slate)
		if string.sub(b.t, 1, 5) == "panel" then
			local floors = if b.lv > 0 then b.lv else math.max(1, math.floor(h / FLOOR_H))
			local longSide = L >= W
			local bandCF = if longSide then base else base * CFrame.Angles(0, math.pi / 2, 0)
			local longLen, shortLen = if longSide then L else W, if longSide then W else L
			if Config.Map.WindowBands then
				windowBands(model, bandCF, longLen, shortLen, floors)
			end
			-- Balconies go on the long face without the entrances (usually the street
			-- or garden side); entrances face the courtyard.
			local entranceSide = 0
			for _, e in b.en or {} do
				local n = bandCF:VectorToObjectSpace(Vector3.new(e.nx or 0, 0, e.nz or 0))
				entranceSide += if n.Z > 0 then 1 else -1
			end
			Facade.PanelBlock(model, bandCF, longLen, shortLen, h, floors, color, b.id, if entranceSide > 0 then -1 else 1)
		end
	else
		local p: { number } = b.p
		local n = #p // 2
		for i = 1, n do
			local j = i % n + 1
			local a = Vector3.new(p[2 * i - 1], 0, p[2 * i])
			local c = Vector3.new(p[2 * j - 1], 0, p[2 * j])
			local edge = c - a
			local len = edge.Magnitude
			if len > 0.05 then
				local dir = edge / len
				local inward = Vector3.new(-dir.Z, 0, dir.X)
				local center = (a + c) / 2 + inward * (WALL_T / 2) + Vector3.new(0, y0 + h / 2, 0)
				Geometry.Part(model, "Wall", Vector3.new(len + WALL_T, h, WALL_T), CFrame.fromMatrix(center, dir, Vector3.yAxis), color, material)
			end
		end
		Geometry.Polygon(model, p, b.tri, y0 + h + 0.25, 0.5, roofColor, Enum.Material.Slate)
	end

	-- Real address plates on the wall facing the street (positions computed offline).
	if b.pl and b.sa and b.hn then
		for _, pl in b.pl do
			local gy = Height.Ground(pl[1], pl[2])
			AddressPlates.Create(model, Vector3.new(pl[1], gy, pl[2]), Vector3.new(pl[3], 0, pl[4]), b.sa, b.hn, h + y0 - gy)
		end
	end

	if Config.Map.EntranceDetails and b.en then
		-- Apartment blocks get working entrances (intercom, door, stairwell, lift,
		-- flats); everything else a decorative door.
		local plans = EntrancePlanner.Plan(b)
		for i, e in b.en do
			local plan = plans[i]
			if plan then
				local pl = plan :: any
				pl.Y = Height.Ground(e.x, e.z)
				EntranceBuilder.Build(model, pl)
				local normal = Vector3.new(e.nx or 0, 0, e.nz or 0)
				if normal.Magnitude > 0.5 then
					normal = normal.Unit
					local side = Vector3.new(-normal.Z, 0, normal.X)
					if Config.Map.EntranceBenches then
						-- the bench by the під'їзд (left of the door, away from the intercom), facing the courtyard
						local pos = Vector3.new(e.x, 0, e.z) - side * M(2.2) + normal * M(1.8)
						StreetDetails.Bench(model, pos.X, pos.Z, math.atan2(normal.Z, normal.X))
					end
					if pl.HasLift then
						Facade.LiftRoom(model, Vector3.new(e.x, 0, e.z), normal, y0 + h, color)
					end
				end
			else
				entranceDetail(model, e, h)
			end
		end
	end

	if b.nm and (b.t == "public" or b.t == "commercial") then
		addLabel(model, Vector3.new(b.p[1], y0 + h + 6, b.p[2]), b.nm)
	end

	model.Parent = parent
	return y0, y0 + h, model
end

-- PUBLIC ----------------------------------------------------------------------

function CityBuilder.GetIndex(): any
	local folder = ServerStorage:FindFirstChild("MapData")
	local indexModule = folder and folder:FindFirstChild("Index")
	if not (indexModule and indexModule:IsA("ModuleScript")) then
		return nil
	end
	local ok, index = pcall(require, indexModule)
	if ok and typeof(index) == "table" and index.Chunks then
		return index
	end
	return nil
end

-- Builds Workspace.City. frameBudget = seconds of work per frame before yielding
-- (nil = never yield, for baking from the Studio command bar).
function CityBuilder.Build(parentRoot: Instance, frameBudget: number?): Model?
	local index = CityBuilder.GetIndex()
	if not index then
		warn("[City] No map data. Run tools/fetch_osm.sh to generate map/data.")
		return nil
	end
	local folder = ServerStorage:FindFirstChild("MapData") :: Folder
	local old = parentRoot:FindFirstChild("City")
	if old then
		old:Destroy()
	end
	local city = Instance.new("Model")
	city.Name = "City"
	city:SetAttribute("Attribution", index.Attribution)

	-- Yield on a time budget, not a count: some steps (terrain rows, long roads) are
	-- far heavier than others, and a spawned thread runs until its first yield.
	local sliceStart = os.clock()
	local function tick()
		if frameBudget and os.clock() - sliceStart > frameBudget then
			task.wait()
			sliceStart = os.clock()
		end
	end

	-- Ground covering the map bounds plus a margin: Terrain (so the sea can be cut
	-- into it) or 2048-stud plates.
	local ground = Instance.new("Model")
	ground.Name = "Ground"
	local b = index.Bounds
	local size = 2048
	local terrain = workspace.Terrain
	-- Real relief (hills, valleys, coastal cliffs) when elevation data exists.
	local sculpted = Config.Map.TerrainGround and TerrainBuilder.Build(tick)
	if sculpted then
		local n, missing, meanErr, maxErr = TerrainBuilder.Verify(400)
		print(("[CityDebug] terrain check: %d raycast samples, %d with NO terrain, |terrain - heightmap| mean %.2f / max %.2f studs"):format(
			n, missing, meanErr, maxErr))
		city:SetAttribute("TerrainMissing", missing)
		city:SetAttribute("TerrainMaxError", maxErr)
	else
		print("[CityDebug] terrain: flat (no elevation data, or Config.Map.Relief / TerrainGround off)")
	end
	if Config.Map.TerrainGround and not sculpted then
		TerrainBuilder.SetColours(terrain)
	end
	for gx = math.floor((b.minX - 400) / size), math.floor((b.maxX + 400) / size) do
		for gz = math.floor((b.minZ - 400) / size), math.floor((b.maxZ + 400) / size) do
			if sculpted then
				-- relief already built: just make sure the far margins have a floor
				terrain:FillBlock(CFrame.new((gx + 0.5) * size, -Config.Map.SeaDepth - 6, (gz + 0.5) * size), Vector3.new(size, 4, size), Enum.Material.Ground)
			elseif Config.Map.TerrainGround then
				terrain:FillBlock(CFrame.new((gx + 0.5) * size, -2, (gz + 0.5) * size), Vector3.new(size, 4, size), Enum.Material.Ground)
			else
				Geometry.Part(ground, "Ground", Vector3.new(size, 2, size), CFrame.new((gx + 0.5) * size, -1, (gz + 0.5) * size),
					Color3.fromRGB(116, 128, 80), Enum.Material.Ground)
			end
		end
	end
	ground.Parent = city
	city.Parent = parentRoot

	local built = 0
	local stats = {
		groundMin = math.huge, groundMax = -math.huge, topMin = math.huge, topMax = -math.huge,
		sample = "", floating = 0,
	}
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Include
	probeParams.FilterDescendantsInstances = { workspace.Terrain }
	probeParams.IgnoreWater = true
	for chunkIndex, name in index.Chunks do
		workspace:SetAttribute("CityProgress", 0.5 + 0.5 * chunkIndex / #index.Chunks)
		local module = folder:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, chunk = pcall(require, module)
			if ok and typeof(chunk) == "table" then
				local chunkModel = Instance.new("Model")
				chunkModel.Name = name
				chunkModel.Parent = city

				for _, a in chunk.a do
					local style = AREA_STYLE[a.t]
					local lo, hi = Height.Range(a.p)
					local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
					for i = 1, #a.p - 1, 2 do
						minX, maxX = math.min(minX, a.p[i]), math.max(maxX, a.p[i])
						minZ, maxZ = math.min(minZ, a.p[i + 1]), math.max(maxZ, a.p[i + 1])
					end
					local small = math.max(maxX - minX, maxZ - minZ) < M(60)
					if a.t == "water" and Config.Map.TerrainGround then
						-- lakes and ponds sit at their lowest shore level
						Geometry.TerrainPolygon(a.p, a.tri, lo, Config.Map.SeaDepth, Enum.Material.Water)
					elseif sculpted and not small then
						-- big parks/beaches/forests are terrain materials (from the height grid)
					elseif style then
						-- small hard surfaces (car parks, playgrounds) laid flat at their mid height
						local y = if sculpted then (lo + hi) / 2 else 0
						Geometry.Polygon(chunkModel, a.p, a.tri, y + 0.03, 0.06 + (hi - lo), style[1] :: Color3, style[2] :: Enum.Material)
					end
					tick()
				end
				for _, r in chunk.r do
					local y = ROAD_Y[r.t] or 0.1
					local minor = r.t == "footway" or r.t == "path" or r.t == "steps" or r.t == "cycleway" or r.t == "track"
					local dashed = Config.Map.RoadMarkings and (r.t == "primary" or r.t == "secondary" or r.t == "tertiary" or r.t == "trunk")
					-- roads follow the ground, subdivided every 6 m
					Geometry.DrapedPolyline(chunkModel, r.p, r.w, y, 0.2,
						if minor then Color3.fromRGB(150, 146, 140) else Color3.fromRGB(62, 62, 64),
						if minor then Enum.Material.Pavement else Enum.Material.Asphalt, Height.Ground, M(6), dashed)
					tick()
				end
				for _, bld in chunk.b do
					local ground, top, bmodel = buildBuilding(chunkModel, bld)
					stats.groundMin = math.min(stats.groundMin, ground)
					stats.groundMax = math.max(stats.groundMax, ground)
					stats.topMin = math.min(stats.topMin, top)
					stats.topMax = math.max(stats.topMax, top)
					if stats.sample == "" and bld.st and bld.hn and string.sub(bld.t, 1, 5) == "panel" then
						local pivot = bmodel:GetPivot().Position
						stats.sample = ("%s, %s (%s, %d floors): pivot %s, ground %.1f, roof %.1f"):format(
							bld.st, bld.hn, bld.t, bld.lv, tostring(Vector3.new(math.floor(pivot.X), math.floor(pivot.Y), math.floor(pivot.Z))), ground, top)
					end
					-- a building whose base is more than 4 studs above the terrain is "floating"
					local hit = workspace:Raycast(Vector3.new(bld.p[1], 2000, bld.p[2]), Vector3.new(0, -2600, 0), probeParams)
					if not hit or ground - hit.Position.Y > 4 then
						stats.floating += 1
					end
					built += 1
					tick()
				end
				for _, poi in chunk.poi do
					local text = labelText(poi.k, poi.nm)
					if text then
						addLabel(chunkModel, Vector3.new(poi.x, Height.Ground(poi.x, poi.z) + 8, poi.z), text)
					end
					serviceAt(chunkModel, poi)
				end
				StreetDetails.BuildChunk(chunkModel, chunk, tick)
			else
				warn("[City] Could not load", name, chunk)
			end
		end
	end

	print(("[City] Built %d buildings from OSM (%s)"):format(built, index.Attribution))
	if built > 0 then
		print(("[CityDebug] buildings: base Y %.1f .. %.1f studs, roof Y %.1f .. %.1f studs, floating (base > 4 studs above terrain or no terrain): %d"):format(
			stats.groundMin, stats.groundMax, stats.topMin, stats.topMax, stats.floating))
		print("[CityDebug] sample block: " .. stats.sample)
	end
	city:SetAttribute("BuildingsFloating", stats.floating)
	city:SetAttribute("BuildingBaseMin", stats.groundMin)
	city:SetAttribute("BuildingBaseMax", stats.groundMax)
	return city
end

return CityBuilder
