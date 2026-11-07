--!strict
-- InteriorService: apartment interiors.
--
-- A city of 9-storey blocks has thousands of flats; building them all would kill
-- streaming and phones. Instead each interior is generated on demand into a free
-- "slot" in a pocket area far from the map (Config.Interiors.Origin) the first time
-- someone enters, and destroyed after it has been empty for a while. Persistent
-- state (fridge contents) lives in the owner's PlayerData; light/TV/stove state
-- is per visit.
--
-- Layout "1k" (однокімнатна, ~35 m²) in metres, entry door at z = 0, +Z inward:
--   Hall     x 0–4.4  z 0–2.8      Room    x 4.4–7.2 z 0–5.4
--   Bath     x 0–2.0  z 2.8–5.4    Balcony x 4.6–7.0 z 5.4–6.4 (glazed)
--   Kitchen  x 2.0–4.4 z 2.8–5.4

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local InventoryService = require(script.Parent.InventoryService)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

export type Interior = {
	AptKey: string,
	Model: Model,
	Slot: number,
	EntryCFrame: CFrame,
	BoxCFrame: CFrame,
	BoxSize: Vector3,
	EmptySince: number?,
}

local M = Config.Meters
local H = 2.5 -- ceiling height (m)
local WALL_T = 0.12
local FLAT_W, FLAT_D = 7.2, 5.4

local WALLPAPERS = {
	Color3.fromRGB(214, 196, 160),
	Color3.fromRGB(190, 205, 180),
	Color3.fromRGB(205, 185, 192),
	Color3.fromRGB(182, 196, 212),
	Color3.fromRGB(222, 206, 172),
}
local WARM = Color3.fromRGB(255, 222, 170)
local WHITE = Color3.fromRGB(236, 236, 230)
local WOOD = Color3.fromRGB(92, 58, 34)

local TV_PROGRAMS = { "УТ-1\nНовини", "Мультфільм", "Футбол\n1 : 0", "Прогноз погоди\nОдеса +24°", "Концерт" }

local InteriorService = {}

local interiors: { [string]: Interior } = {}
local usedSlots: { [number]: boolean } = {}
local locations: { [Player]: string } = {}
local exitHandler: ((Player, string) -> ())? = nil
local folder: Folder

local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function slotPosition(slot: number): Vector3
	local cfg = Config.Interiors
	local col = slot % cfg.SlotsPerRow
	local row = slot // cfg.SlotsPerRow
	return cfg.Origin + Vector3.new(col * cfg.Spacing, 0, row * cfg.Spacing)
end

local function inBox(boxCFrame: CFrame, size: Vector3, position: Vector3): boolean
	local p = boxCFrame:PointToObjectSpace(position)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

local function build(aptKey: string, slot: number): Interior
	local base = CFrame.new(slotPosition(slot))
	local model = Instance.new("Model")
	model.Name = "Interior_" .. aptKey
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local wallpaper = WALLPAPERS[hash(aptKey) % #WALLPAPERS + 1]

	-- size and centre in metres, y measured from the finished floor
	local function box(name: string, size: Vector3, center: Vector3, props: { [string]: any }?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = Vector3.new(M(size.X), M(size.Y), M(size.Z))
		p.CFrame = base * CFrame.new(M(center.X), M(center.Y), M(center.Z))
		p.Material = Enum.Material.SmoothPlastic
		p.Color = WHITE
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if props then
			for k, v in props do
				(p :: any)[k] = v
			end
		end
		p.Parent = model
		return p
	end

	-- Axis-aligned wall with door/window gaps {from, to, bottom, top} (m along the wall).
	local wallProps = { Material = Enum.Material.Plaster, Color = wallpaper }
	local function wall(axis: string, fixed: number, from: number, to: number, gaps: { { number } }?)
		local function piece(a: number, b: number, y0: number, y1: number)
			if b - a < 0.01 or y1 - y0 < 0.01 then
				return
			end
			local mid, len, h = (a + b) / 2, b - a, y1 - y0
			if axis == "X" then
				box("Wall", Vector3.new(len, h, WALL_T), Vector3.new(mid, y0 + h / 2, fixed), wallProps)
			else
				box("Wall", Vector3.new(WALL_T, h, len), Vector3.new(fixed, y0 + h / 2, mid), wallProps)
			end
		end
		local cursor = from
		for _, g in gaps or {} do
			piece(cursor, g[1], 0, H)
			piece(g[1], g[2], 0, g[3])
			piece(g[1], g[2], g[4], H)
			cursor = g[2]
		end
		piece(cursor, to, 0, H)
	end

	-- anyone = true skips the "is this player registered in this flat" check (used
	-- for the exit door, so nobody can ever be trapped inside).
	local function prompt(part: BasePart, actionText: string, objectText: string, handler: ((Player) -> ())?, anyone: boolean?): ProximityPrompt
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = actionText
		pr.ObjectText = objectText
		pr.HoldDuration = 0
		pr.MaxActivationDistance = 6
		pr.RequiresLineOfSight = false
		pr.Parent = part
		if handler then
			pr.Triggered:Connect(function(player: Player)
				if (anyone or locations[player] == aptKey) and Validation.IsNear(player, part, 12) then
					handler(player)
				end
			end)
		end
		return pr
	end

	-- STRUCTURE ---------------------------------------------------------------
	box("Slab", Vector3.new(FLAT_W + 0.6, 0.3, 6.8), Vector3.new(FLAT_W / 2, -0.25, 3.2), {
		Material = Enum.Material.Concrete,
		Color = Color3.fromRGB(120, 120, 120),
	})
	box("FloorHall", Vector3.new(4.4, 0.1, 2.8), Vector3.new(2.2, -0.05, 1.4), { Color = Color3.fromRGB(140, 96, 62) })
	box("FloorBath", Vector3.new(2.0, 0.1, 2.6), Vector3.new(1.0, -0.05, 4.1), {
		Material = Enum.Material.CeramicTiles,
		Color = Color3.fromRGB(200, 215, 225),
	})
	box("FloorKitchen", Vector3.new(2.4, 0.1, 2.6), Vector3.new(3.2, -0.05, 4.1), { Color = Color3.fromRGB(172, 150, 118) })
	box("FloorRoom", Vector3.new(2.8, 0.1, 5.4), Vector3.new(5.8, -0.05, 2.7), {
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 96, 52),
	})
	box("FloorBalcony", Vector3.new(2.4, 0.1, 1.0), Vector3.new(5.8, -0.05, 5.9), { Material = Enum.Material.Concrete, Color = Color3.fromRGB(150, 150, 145) })
	box("Ceiling", Vector3.new(FLAT_W, 0.1, FLAT_D), Vector3.new(FLAT_W / 2, H + 0.05, FLAT_D / 2))
	box("CeilingBalcony", Vector3.new(2.4, 0.1, 1.0), Vector3.new(5.8, H + 0.05, 5.9), { Material = Enum.Material.Concrete })

	wall("X", 0, 0, FLAT_W, { { 0.4, 1.3, 0, 2.1 } }) -- entry
	wall("Z", 0, 0, FLAT_D)
	wall("Z", FLAT_W, 0, FLAT_D)
	wall("X", FLAT_D, 0, FLAT_W, { { 2.6, 3.8, 0.9, 2.2 }, { 4.8, 5.8, 0.9, 2.2 }, { 6.0, 6.7, 0, 2.1 } })
	wall("X", 2.8, 0, 4.4, { { 0.6, 1.3, 0, 2.0 }, { 2.6, 3.4, 0, 2.0 } })
	wall("Z", 2.0, 2.8, FLAT_D)
	wall("Z", 4.4, 0, FLAT_D, { { 0.8, 1.7, 0, 2.0 } })

	local glass = { Material = Enum.Material.Glass, Transparency = 0.55, Color = Color3.fromRGB(170, 210, 230) }
	box("WindowKitchen", Vector3.new(1.2, 1.3, 0.04), Vector3.new(3.2, 1.55, FLAT_D), glass)
	box("WindowRoom", Vector3.new(1.0, 1.3, 0.04), Vector3.new(5.3, 1.55, FLAT_D), glass)

	-- Glazed balcony (keeps players from falling into the void, and very Soviet).
	local brick = { Material = Enum.Material.Brick, Color = Color3.fromRGB(165, 92, 70) }
	box("Parapet", Vector3.new(2.4, 1.0, 0.12), Vector3.new(5.8, 0.5, 6.4), brick)
	box("ParapetL", Vector3.new(0.12, 1.0, 1.0), Vector3.new(4.6, 0.5, 5.9), brick)
	box("ParapetR", Vector3.new(0.12, 1.0, 1.0), Vector3.new(7.0, 0.5, 5.9), brick)
	box("Glazing", Vector3.new(2.4, 1.5, 0.04), Vector3.new(5.8, 1.75, 6.4), glass)
	box("GlazingL", Vector3.new(0.04, 1.5, 1.0), Vector3.new(4.6, 1.75, 5.9), glass)
	box("GlazingR", Vector3.new(0.04, 1.5, 1.0), Vector3.new(7.0, 1.75, 5.9), glass)
	box("Jars", Vector3.new(0.5, 0.3, 0.3), Vector3.new(6.6, 0.15, 6.2), { Material = Enum.Material.Glass, Color = Color3.fromRGB(200, 90, 60), Transparency = 0.2 })

	-- LIGHTS ------------------------------------------------------------------
	local lightGroups: { [string]: { { Part: Part, Light: PointLight } } } = {}
	local function lamp(group: string, center: Vector3, big: boolean?)
		local p = box("Lamp", if big then Vector3.new(0.5, 0.25, 0.5) else Vector3.new(0.3, 0.12, 0.3), center, {
			Material = Enum.Material.Neon,
			Color = WARM,
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Range = M(if big then 4.5 else 3)
		light.Brightness = 1
		light.Color = WARM
		light.Parent = p
		lightGroups[group] = lightGroups[group] or {}
		table.insert(lightGroups[group], { Part = p, Light = light })
	end
	lamp("hall", Vector3.new(1.0, 2.4, 1.4))
	lamp("hall", Vector3.new(3.3, 2.4, 1.4))
	lamp("bath", Vector3.new(1.0, 2.42, 4.1))
	lamp("kitchen", Vector3.new(3.2, 2.42, 4.1))
	lamp("room", Vector3.new(5.8, 2.3, 2.7), true) -- люстра

	local function switch(group: string, size: Vector3, center: Vector3)
		local s = box("Switch", size, center, { Color = Color3.fromRGB(240, 238, 225), CanCollide = false })
		prompt(s, "Світло", "Вимикач", function()
			Sfx.Play(s, Config.Sounds.LightSwitch, 0.5)
			for _, l in lightGroups[group] do
				l.Light.Enabled = not l.Light.Enabled
				l.Part.Color = if l.Light.Enabled then WARM else Color3.fromRGB(90, 85, 75)
			end
		end)
	end
	switch("hall", Vector3.new(0.08, 0.12, 0.03), Vector3.new(1.6, 1.4, 0.075))
	switch("bath", Vector3.new(0.08, 0.12, 0.03), Vector3.new(0.45, 1.4, 2.725))
	switch("kitchen", Vector3.new(0.08, 0.12, 0.03), Vector3.new(3.6, 1.4, 2.725))
	switch("room", Vector3.new(0.03, 0.12, 0.08), Vector3.new(4.325, 1.4, 2.0))

	-- HALL ----------------------------------------------------------------------
	box("CoatRack", Vector3.new(0.05, 0.08, 1.0), Vector3.new(0.09, 1.7, 1.6), { Material = Enum.Material.Wood, Color = WOOD })
	box("ShoeShelf", Vector3.new(0.3, 0.4, 0.8), Vector3.new(0.21, 0.2, 1.6), { Material = Enum.Material.Wood, Color = WOOD })
	local exitDoor = box("FlatDoorInside", Vector3.new(0.9, 2.05, 0.08), Vector3.new(0.85, 1.025, 0.08), {
		Material = Enum.Material.Leather, -- dermantin upholstery
		Color = Color3.fromRGB(92, 40, 34),
	})
	prompt(exitDoor, "Вийти", "Двері", function(player: Player)
		if exitHandler then
			exitHandler(player, aptKey)
		end
	end, true)

	-- BATHROOM ------------------------------------------------------------------
	box("Bathtub", Vector3.new(0.75, 0.55, 1.6), Vector3.new(0.44, 0.275, 4.55))
	box("BathWater", Vector3.new(0.6, 0.02, 1.45), Vector3.new(0.44, 0.45, 4.55), {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(120, 180, 220),
		Transparency = 0.3,
		CanCollide = false,
	})
	box("Toilet", Vector3.new(0.4, 0.4, 0.6), Vector3.new(1.6, 0.2, 5.0))
	box("ToiletTank", Vector3.new(0.4, 0.4, 0.15), Vector3.new(1.6, 0.6, 5.25))
	box("Washbasin", Vector3.new(0.15, 0.15, 0.45), Vector3.new(1.86, 0.85, 3.6))
	box("Mirror", Vector3.new(0.02, 0.5, 0.4), Vector3.new(1.93, 1.4, 3.6), { Material = Enum.Material.Glass, Reflectance = 0.4, Color = Color3.fromRGB(200, 220, 230) })

	-- KITCHEN -------------------------------------------------------------------
	local fridge = box("Fridge", Vector3.new(0.6, 1.5, 0.6), Vector3.new(2.35, 0.75, 3.15))
	local fp = prompt(fridge, "Відкрити", "Холодильник", nil) -- handled on the client (storage UI)
	fp:SetAttribute("Action", "Fridge")
	fp:SetAttribute("AptKey", aptKey)

	local stove = box("Stove", Vector3.new(0.55, 0.85, 0.5), Vector3.new(4.12, 0.425, 3.4))
	local flames: { Part } = {}
	for _, xz in { { 4.0, 3.28 }, { 4.24, 3.28 }, { 4.0, 3.52 }, { 4.24, 3.52 } } do
		table.insert(flames, box("Flame", Vector3.new(0.12, 0.02, 0.12), Vector3.new(xz[1], 0.86, xz[2]), {
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(80, 140, 255),
			Transparency = 1,
			CanCollide = false,
		}))
	end
	prompt(stove, "Конфорки", "Газова плита", function()
		local on = flames[1].Transparency > 0.5
		for _, f in flames do
			f.Transparency = if on then 0.1 else 1
		end
	end)
	box("SinkUnit", Vector3.new(0.55, 0.85, 0.6), Vector3.new(4.12, 0.425, 4.0))
	box("Sink", Vector3.new(0.4, 0.02, 0.4), Vector3.new(4.12, 0.86, 4.0), { Material = Enum.Material.Metal, Color = Color3.fromRGB(170, 170, 175) })
	box("KitchenTable", Vector3.new(0.7, 0.04, 0.7), Vector3.new(2.8, 0.74, 4.8))
	box("TableLeg", Vector3.new(0.1, 0.72, 0.1), Vector3.new(2.8, 0.36, 4.8), { Color = Color3.fromRGB(150, 150, 150) })
	box("Stool", Vector3.new(0.35, 0.45, 0.35), Vector3.new(2.8, 0.225, 4.3), { Material = Enum.Material.Wood, Color = WOOD })
	box("Stool", Vector3.new(0.35, 0.45, 0.35), Vector3.new(3.35, 0.225, 4.9), { Material = Enum.Material.Wood, Color = WOOD })

	-- ROOM ----------------------------------------------------------------------
	box("Sofa", Vector3.new(0.9, 0.45, 2.0), Vector3.new(6.7, 0.225, 2.6), { Material = Enum.Material.Fabric, Color = Color3.fromRGB(120, 62, 50) })
	box("SofaBack", Vector3.new(0.2, 0.5, 2.0), Vector3.new(7.04, 0.7, 2.6), { Material = Enum.Material.Fabric, Color = Color3.fromRGB(110, 55, 45) })
	box("WallCarpet", Vector3.new(0.03, 1.4, 2.2), Vector3.new(7.125, 1.55, 2.6), { Material = Enum.Material.Carpet, Color = Color3.fromRGB(150, 30, 36) })
	box("WallCarpetPattern", Vector3.new(0.03, 1.0, 1.8), Vector3.new(7.11, 1.55, 2.6), { Material = Enum.Material.Carpet, Color = Color3.fromRGB(196, 140, 60) })
	box("Carpet", Vector3.new(2.0, 0.02, 2.6), Vector3.new(5.6, 0.01, 2.6), { Material = Enum.Material.Carpet, Color = Color3.fromRGB(130, 42, 42), CanCollide = false })
	box("WallUnit", Vector3.new(0.45, 2.2, 1.9), Vector3.new(4.69, 1.1, 4.15), { Material = Enum.Material.Wood, Color = WOOD }) -- "стінка"
	box("WallUnitGlass", Vector3.new(0.02, 0.8, 0.9), Vector3.new(4.925, 1.5, 4.15), glass)
	box("CoffeeTable", Vector3.new(0.5, 0.45, 0.8), Vector3.new(5.7, 0.225, 2.6), { Material = Enum.Material.Wood, Color = WOOD })
	box("TVStand", Vector3.new(0.5, 0.7, 0.8), Vector3.new(4.72, 0.35, 2.6), { Material = Enum.Material.Wood, Color = WOOD })
	box("TV", Vector3.new(0.45, 0.45, 0.55), Vector3.new(4.72, 0.95, 2.6), { Color = Color3.fromRGB(60, 50, 40) })
	local screen = box("Screen", Vector3.new(0.02, 0.36, 0.46), Vector3.new(4.955, 0.95, 2.6), { Color = Color3.fromRGB(20, 22, 20) })
	local tvGui = Instance.new("SurfaceGui")
	tvGui.Face = Enum.NormalId.Right
	tvGui.LightInfluence = 0
	tvGui.Parent = screen
	local tvLabel = Instance.new("TextLabel")
	tvLabel.Size = UDim2.fromScale(1, 1)
	tvLabel.BackgroundTransparency = 1
	tvLabel.TextScaled = true
	tvLabel.Font = Enum.Font.GothamBold
	tvLabel.TextColor3 = Color3.fromRGB(230, 240, 255)
	tvLabel.Text = ""
	tvLabel.Parent = tvGui
	local channel = 0
	prompt(screen, "Перемкнути", "Телевізор", function()
		channel = (channel + 1) % (#TV_PROGRAMS + 1) -- 0 = off
		if channel == 0 then
			tvLabel.Text = ""
			screen.Material = Enum.Material.SmoothPlastic
			screen.Color = Color3.fromRGB(20, 22, 20)
		else
			tvLabel.Text = TV_PROGRAMS[channel]
			screen.Material = Enum.Material.Neon
			screen.Color = Color3.fromRGB(40, 60, 90)
		end
	end)

	model.Parent = folder

	local entryPos = (base * CFrame.new(M(0.85), 3, M(0.9))).Position
	return {
		AptKey = aptKey,
		Model = model,
		Slot = slot,
		EntryCFrame = CFrame.lookAt(entryPos, entryPos + Vector3.zAxis),
		BoxCFrame = base * CFrame.new(M(3.6), M(1.2), M(3.2)),
		BoxSize = Vector3.new(M(8.5), M(4), M(8)),
		EmptySince = nil,
	}
end

-- PUBLIC API ------------------------------------------------------------------

function InteriorService.GetOrCreate(aptKey: string): Interior
	local existing = interiors[aptKey]
	if existing then
		existing.EmptySince = nil
		return existing
	end
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	local interior = build(aptKey, slot)
	interiors[aptKey] = interior
	return interior
end

function InteriorService.GetLocation(player: Player): string?
	return locations[player]
end

function InteriorService.SetLocation(player: Player, aptKey: string?)
	locations[player] = aptKey
end

function InteriorService.SetExitHandler(fn: (Player, string) -> ())
	exitHandler = fn
end

function InteriorService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Interiors"
	folder.Parent = workspace

	InventoryService.SetLocationResolver(InteriorService.GetLocation)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			locations[player] = nil -- respawned at the spawn point
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		locations[player] = nil
	end)

	-- Housekeeping every 10 s: forget stale locations, free empty interiors.
	task.spawn(function()
		while true do
			task.wait(10)
			local now = os.clock()
			for aptKey, interior in interiors do
				local occupied = false
				for player, key in locations do
					if key == aptKey then
						local root = Validation.GetRoot(player)
						if root and inBox(interior.BoxCFrame, interior.BoxSize, root.Position) then
							occupied = true
						else
							locations[player] = nil
						end
					end
				end
				if occupied then
					interior.EmptySince = nil
				else
					interior.EmptySince = interior.EmptySince or now
					if now - (interior.EmptySince :: number) > Config.Interiors.EmptyLifetime then
						interior.Model:Destroy()
						usedSlots[interior.Slot] = nil
						interiors[aptKey] = nil
					end
				end
			end
		end
	end)
end

return InteriorService
