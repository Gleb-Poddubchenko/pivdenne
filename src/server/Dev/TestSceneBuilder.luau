--!strict
-- TestSceneBuilder (DEV ONLY): builds a 9-storey panel block with two working
-- entrances (one VIZOR, one METRON), a key kiosk and a housing office (ЖЕК),
-- so every Phase 1 system can be tested in an empty Baseplate.
-- All dimensions are real-world metres converted with Config.Meters (1 m = 3.5 studs).
-- The entrance model it builds is also the reference layout for real entrances.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Brands = require(Shared:WaitForChild("IntercomBrands"))

local M = Config.Meters

local PANEL_CONCRETE = Color3.fromRGB(196, 190, 178)
local DOOR_PAINT = Color3.fromRGB(74, 58, 46) -- brown hammer paint
local MAILBOX_GREEN = Color3.fromRGB(70, 110, 90)

local FLOOR_H = M(2.8) -- typical panel-block floor-to-floor
local FLOORS = 9
local ENTRANCE_W = M(12) -- one section width
local GROUND_H = FLOOR_H
local WALL_T = M(0.35)
local LOBBY_D = M(4)
local BUILDING_D = M(12)
local DOOR_W = M(1.0)
local DOOR_H = M(2.1)

local TestSceneBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.Concrete
	p.Color = PANEL_CONCRETE
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Name = "DoorWeld" -- DoorService skips parts that already have one
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- cf: on the ground, at the OUTER wall surface, centre of the doorway.
-- LookVector points outward (towards the courtyard). Local +Z = into the building.
local function buildEntrance(parent: Instance, cf: CFrame, id: string, brandId: string, aptFrom: number, aptTo: number): Model
	local model = Instance.new("Model")
	model.Name = "Entrance_" .. id
	model:SetAttribute("EntranceId", id)
	model:SetAttribute("Brand", brandId)
	model:SetAttribute("AptFrom", aptFrom)
	model:SetAttribute("AptTo", aptTo)

	local W, H, T = ENTRANCE_W, GROUND_H, WALL_T
	local side = (W - DOOR_W) / 2

	-- Front wall with doorway
	part(model, "WallLeft", Vector3.new(side, H, T), cf * CFrame.new(-(DOOR_W / 2 + side / 2), H / 2, T / 2))
	part(model, "WallRight", Vector3.new(side, H, T), cf * CFrame.new(DOOR_W / 2 + side / 2, H / 2, T / 2))
	part(model, "Lintel", Vector3.new(DOOR_W, H - DOOR_H, T), cf * CFrame.new(0, DOOR_H + (H - DOOR_H) / 2, T / 2))

	-- Lobby: floor, side walls, back wall (upper floors are the building mass)
	part(model, "LobbyFloor", Vector3.new(W, 1, LOBBY_D), cf * CFrame.new(0, -0.4, T + LOBBY_D / 2), {
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(120, 92, 80), -- terrazzo/tile
	})
	part(model, "LobbyWallL", Vector3.new(T, H, LOBBY_D), cf * CFrame.new(-W / 2 + T / 2, H / 2, T + LOBBY_D / 2))
	part(model, "LobbyWallR", Vector3.new(T, H, LOBBY_D), cf * CFrame.new(W / 2 - T / 2, H / 2, T + LOBBY_D / 2))
	part(model, "LobbyBack", Vector3.new(W, H, T), cf * CFrame.new(0, H / 2, T + LOBBY_D + T / 2))
	part(model, "Mailboxes", Vector3.new(0.6, M(0.8), M(1.6)), cf * CFrame.new(-W / 2 + T + 0.3, M(1.3), T + M(1.5)), {
		Material = Enum.Material.Metal,
		Color = MAILBOX_GREEN,
	})
	local lamp = part(model, "Lamp", Vector3.new(1, 0.3, 1), cf * CFrame.new(0, H - 0.4, T + LOBBY_D / 2), {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 230, 180),
	})
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 0.8
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Parent = lamp

	-- Outside: concrete canopy (козирок) and step
	part(model, "Canopy", Vector3.new(DOOR_W + M(1.6), M(0.15), M(1.4)), cf * CFrame.new(0, DOOR_H + M(0.5), -M(0.7)))
	part(model, "Step", Vector3.new(DOOR_W + M(1.6), 0.2, M(1.4)), cf * CFrame.new(0, 0.1, -M(0.7)))

	-- Door: anchored Hinge + welded leaf + handle
	local door = Instance.new("Model")
	door.Name = "Door"
	local hinge = part(door, "Hinge", Vector3.new(0.2, DOOR_H, 0.2), cf * CFrame.new(-DOOR_W / 2, DOOR_H / 2, -0.15), {
		Transparency = 1,
		CanCollide = false,
	})
	-- Leaf bottom sits 0.3 above ground so it clears the step when swinging.
	local leaf = part(door, "Leaf", Vector3.new(DOOR_W - 0.1, DOOR_H - 0.3, 0.25), cf * CFrame.new(0, DOOR_H / 2 + 0.15, -0.15), {
		Material = Enum.Material.DiamondPlate,
		Color = DOOR_PAINT,
		Anchored = false,
	})
	local handle = part(door, "Handle", Vector3.new(0.15, 1.2, 0.25), cf * CFrame.new(DOOR_W / 2 - 0.5, M(1.0), -0.4), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 40, 40),
		Anchored = false,
		CanCollide = false,
	})
	weld(hinge, leaf)
	weld(hinge, handle)
	door.Parent = model

	-- Intercom panel + key reader, right of the door at ~1.5 m
	local brand = Brands[brandId]
	local intercom = Instance.new("Model")
	intercom.Name = "Intercom"
	local px = DOOR_W / 2 + M(0.35)
	part(intercom, "Panel", Vector3.new(1.1, 2.2, 0.2), cf * CFrame.new(px, M(1.5), -0.1), {
		Material = Enum.Material.Metal,
		Color = brand.PanelColor,
	})
	part(intercom, "Reader", Vector3.new(0.12, 0.45, 0.45), cf * CFrame.new(px, M(1.5) - 0.8, -0.26) * CFrame.Angles(0, math.pi / 2, 0), {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(30, 30, 30),
	})
	intercom.Parent = model

	-- Inside exit button ("ВИХІД")
	part(model, "ExitButton", Vector3.new(0.4, 0.4, 0.15), cf * CFrame.new(DOOR_W / 2 + M(0.3), M(1.3), T + 0.08), {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(40, 200, 80),
	})

	model.PrimaryPart = hinge
	model.Parent = parent
	CollectionService:AddTag(model, "Entrance")
	return model
end

local function buildKiosk(parent: Instance, name: string, tag: string, position: Vector3, sign: string, color: Color3)
	local booth = part(parent, name, Vector3.new(M(2), M(2.4), M(1.5)), CFrame.new(position + Vector3.new(0, M(1.2), 0)), {
		Material = Enum.Material.SmoothPlastic,
		Color = color,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = booth
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.3)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = sign
	label.Parent = gui
	CollectionService:AddTag(booth, tag)
end

function TestSceneBuilder.Build()
	if workspace:FindFirstChild("TestScene") then
		return
	end
	local scene = Instance.new("Folder")
	scene.Name = "TestScene"

	if not workspace:FindFirstChild("Baseplate") then
		part(scene, "Ground", Vector3.new(600, 2, 600), CFrame.new(0, -1, 0), {
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(90, 120, 70),
		})
	end
	if not workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		local spawn = Instance.new("SpawnLocation")
		spawn.Anchored = true
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = Vector3.new(0, 0.5, 0)
		spawn.Parent = scene
	end

	-- Block front faces -Z (towards the spawn), starting 60 studs away.
	local frontZ = 60
	local sections = 2
	local totalW = ENTRANCE_W * sections
	local building = Instance.new("Model")
	building.Name = "Block_test-a"

	local specs = {
		{ id = "test-a/1", brand = "Vizor", from = 1, to = 36 },
		{ id = "test-a/2", brand = "Metron", from = 37, to = 72 },
	}
	for i, spec in specs do
		local x = -totalW / 2 + ENTRANCE_W * (i - 0.5)
		local pos = Vector3.new(x, 0, frontZ)
		local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
		buildEntrance(building, cf, spec.id, spec.brand, spec.from, spec.to)
	end

	-- Building mass above the ground floor and behind the lobbies
	local backDepth = BUILDING_D - LOBBY_D - 2 * WALL_T
	part(building, "UpperMass", Vector3.new(totalW, FLOOR_H * (FLOORS - 1), BUILDING_D),
		CFrame.new(0, GROUND_H + FLOOR_H * (FLOORS - 1) / 2, frontZ + BUILDING_D / 2))
	part(building, "GroundBack", Vector3.new(totalW, GROUND_H, backDepth),
		CFrame.new(0, GROUND_H / 2, frontZ + LOBBY_D + 2 * WALL_T + backDepth / 2))

	-- Balcony slabs: 2 per section per floor
	for floor = 2, FLOORS do
		for s = 1, sections do
			for b = -1, 1, 2 do
				local x = -totalW / 2 + ENTRANCE_W * (s - 0.5) + b * M(3.2)
				local y = FLOOR_H * (floor - 1)
				part(building, "Balcony", Vector3.new(M(2.8), M(1.0), M(1.1)), CFrame.new(x, y + M(0.5), frontZ - M(0.55)), {
					Color = Color3.fromRGB(176, 170, 160),
				})
			end
		end
	end
	building.Parent = scene

	buildKiosk(scene, "KeyKiosk", "KeyKiosk", Vector3.new(-25, 0, 25), "КЛЮЧІ", Color3.fromRGB(40, 90, 160))
	buildKiosk(scene, "HousingOffice", "HousingOffice", Vector3.new(25, 0, 25), "ЖЕК", Color3.fromRGB(150, 60, 50))

	scene.Parent = workspace
end

return TestSceneBuilder
