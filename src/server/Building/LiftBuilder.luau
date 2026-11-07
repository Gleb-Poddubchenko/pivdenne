--!strict
-- LiftBuilder: builds a complete Soviet passenger lift that matches the Elevator
-- model contract (see ElevatorService): shaft with a front wall and door opening
-- per floor, guide rail, cabin (wood-grain laminate, sliding doors, dim lamp,
-- worn button panel), hinged shaft doors, call buttons, ЗАНЯТО lamps, stencilled
-- floor numbers. Used by the city stairwells and by the dev lift tower.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

local FH = M(2.8) -- floor-to-floor
local Y0 = 0.6 -- floor 1 deck top
local SHAFT = M(1.6) -- inner shaft size
local WT = 0.4 -- shaft wall thickness
local CW, CD, CH = M(1.25), M(1.3), M(2.1) -- cabin outer width/depth, inner height
local CABIN_DOOR_W = M(0.75)
local SHAFT_DOOR_W, SHAFT_DOOR_H = M(0.8), M(2.0)

local CONCRETE = Color3.fromRGB(170, 165, 155)
local LAMINATE = Color3.fromRGB(146, 100, 58) -- "під дерево"
local DOOR_GREY = Color3.fromRGB(118, 116, 110)
local SHAFT_DOOR = Color3.fromRGB(96, 84, 70)

local LiftBuilder = {}

-- Geometry shared with callers that must line things up with the shaft (studs).
LiftBuilder.Y0 = Y0
LiftBuilder.ShaftInner = SHAFT
LiftBuilder.WallThickness = WT
LiftBuilder.OuterWidth = SHAFT + 2 * WT
LiftBuilder.DoorWidth = SHAFT_DOOR_W

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.Concrete
	p.Color = CONCRETE
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

local function text(partInst: BasePart, face: Enum.NormalId, value: string, color: Color3, bg: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = partInst
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if bg then 0 else 1
	label.BackgroundColor3 = bg or Color3.new()
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.Text = value
	label.Parent = gui
end

local function buildCabin(parent: Instance, base: CFrame, floors: number)
	-- base: platform centre at floor 1, LookVector = cabin front (towards landings)
	local cabin = Instance.new("Model")
	cabin.Name = "Cabin"
	local top = 0.3

	local platform = part(cabin, "Platform", Vector3.new(CW, 0.6, CD), base, {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 62, 55), -- worn linoleum
	})
	local wall = { Material = Enum.Material.Wood, Color = LAMINATE }
	part(cabin, "WallL", Vector3.new(0.15, CH, CD), base * CFrame.new(-CW / 2 + 0.075, top + CH / 2, 0), wall)
	part(cabin, "WallR", Vector3.new(0.15, CH, CD), base * CFrame.new(CW / 2 - 0.075, top + CH / 2, 0), wall)
	part(cabin, "WallBack", Vector3.new(CW, CH, 0.15), base * CFrame.new(0, top + CH / 2, CD / 2 - 0.075), wall)
	local fw = (CW - CABIN_DOOR_W) / 2
	part(cabin, "FrontL", Vector3.new(fw, CH, 0.15), base * CFrame.new(-(CABIN_DOOR_W / 2 + fw / 2), top + CH / 2, -CD / 2 + 0.075), wall)
	part(cabin, "FrontR", Vector3.new(fw, CH, 0.15), base * CFrame.new(CABIN_DOOR_W / 2 + fw / 2, top + CH / 2, -CD / 2 + 0.075), wall)
	part(cabin, "Ceiling", Vector3.new(CW, 0.15, CD), base * CFrame.new(0, top + CH + 0.075, 0), {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(200, 195, 180),
	})

	local lamp = part(cabin, "Lamp", Vector3.new(1.0, 0.1, 0.5), base * CFrame.new(0, top + CH - 0.05, 0), {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 238, 200),
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1.1
	light.Color = Color3.fromRGB(255, 225, 180)
	light.Parent = lamp

	part(cabin, "Bounds", Vector3.new(CW - 0.3, CH, CD - 0.3), base * CFrame.new(0, top + CH / 2, 0), {
		Transparency = 1,
		CanCollide = false,
	})

	local panel = part(cabin, "ButtonPanel", Vector3.new(0.08, 1.8, 0.7), base * CFrame.new(CW / 2 - 0.19, top + M(1.15), -CD / 2 + 0.75), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(45, 40, 34),
		CanCollide = false,
	})
	-- Decorative worn buttons, two columns, faces into the cabin (-X = Left face).
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.Parent = panel
	local rows = math.ceil(floors / 2) + 1
	for i = 1, floors + 2 do
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local label = if i == floors + 1 then "С" elseif i == floors + 2 then "🔔" else tostring(i)
		local b = Instance.new("TextLabel")
		b.Size = UDim2.fromScale(0.34, 0.8 / rows)
		b.Position = UDim2.fromScale(0.12 + col * 0.42, 0.06 + row * (0.9 / rows))
		b.BackgroundColor3 = if i == floors + 1 then Color3.fromRGB(160, 30, 25) else Color3.fromRGB(20, 18, 16)
		b.TextColor3 = Color3.fromRGB(210, 205, 190)
		b.TextScaled = true
		b.Font = Enum.Font.GothamBold
		b.Text = label
		b.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = b
	end

	local door = { Material = Enum.Material.Metal, Color = DOOR_GREY }
	part(cabin, "DoorL", Vector3.new(CABIN_DOOR_W / 2, CH, 0.12), base * CFrame.new(-CABIN_DOOR_W / 4, top + CH / 2, -CD / 2 - 0.1), door)
	part(cabin, "DoorR", Vector3.new(CABIN_DOOR_W / 2, CH, 0.12), base * CFrame.new(CABIN_DOOR_W / 4, top + CH / 2, -CD / 2 - 0.1), door)

	cabin.PrimaryPart = platform
	cabin.Parent = parent
end

local function buildLanding(parent: Instance, floor: number, frame: CFrame, level: number)
	-- frame: shaft centre at ground, LookVector = towards landings
	local landing = Instance.new("Model")
	landing.Name = "Landing_" .. floor
	local face = -(SHAFT / 2 + WT) -- outer face of the front wall (local Z)

	local shaftDoor = Instance.new("Model")
	shaftDoor.Name = "ShaftDoor"
	local hinge = part(shaftDoor, "Hinge", Vector3.new(0.2, SHAFT_DOOR_H, 0.2),
		frame * CFrame.new(-SHAFT_DOOR_W / 2, level + SHAFT_DOOR_H / 2, face - 0.1), { Transparency = 1, CanCollide = false })
	local leaf = part(shaftDoor, "Leaf", Vector3.new(SHAFT_DOOR_W - 0.1, SHAFT_DOOR_H - 0.1, 0.18),
		frame * CFrame.new(0, level + SHAFT_DOOR_H / 2, face - 0.1), { Material = Enum.Material.Metal, Color = SHAFT_DOOR })
	local handle = part(shaftDoor, "Handle", Vector3.new(0.15, 0.9, 0.2),
		frame * CFrame.new(SHAFT_DOOR_W / 2 - 0.4, level + M(1.0), face - 0.28), {
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(30, 30, 30),
			CanCollide = false,
		})
	for _, p in { leaf, handle } do
		local w = Instance.new("WeldConstraint")
		w.Name = "DoorWeld"
		w.Part0 = hinge
		w.Part1 = p
		w.Parent = p
	end
	shaftDoor.Parent = landing

	part(landing, "CallButton", Vector3.new(0.15, 0.55, 0.55),
		frame * CFrame.new(SHAFT_DOOR_W / 2 + 0.9, level + M(1.15), face - 0.075) * CFrame.Angles(0, math.pi / 2, 0), {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(25, 25, 25),
		})
	part(landing, "Indicator", Vector3.new(1.6, 0.5, 0.08),
		frame * CFrame.new(0, level + SHAFT_DOOR_H + 0.6, face - 0.04), { Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(25, 20, 15) })
	local sign = part(landing, "FloorSign", Vector3.new(1.1, 1.1, 0.05),
		frame * CFrame.new(-SHAFT_DOOR_W / 2 - 0.9, level + M(1.4), face - 0.025), { Transparency = 1, CanCollide = false })
	text(sign, Enum.NormalId.Front, tostring(floor), Color3.fromRGB(30, 60, 140)) -- stencilled floor number
	-- Threshold bridging the wall and the cabin (cabin/shaft never collide).
	part(landing, "Sill", Vector3.new(SHAFT_DOOR_W, 0.3, 0.6), frame * CFrame.new(0, level - 0.15, face + 0.3), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(90, 90, 90),
	})
	landing.Parent = parent
end
-- frame: shaft centre at ground level of floor 1, LookVector = towards the landings
-- (the front wall's outer face is at local z = -(ShaftInner/2 + WallThickness)).
-- Stop f's floor level is frame.Y + (f - 1) * floorHeight + Y0.
function LiftBuilder.Build(parent: Instance, frame: CFrame, floors: number, floorHeight: number, id: string, attributes: { [string]: any }?): Model
	local FH = floorHeight
	local totalH = floors * FH + 2
	local outer = SHAFT + 2 * WT

	local lift = Instance.new("Model")
	lift.Name = "Lift_" .. id
	lift:SetAttribute("ElevatorId", id)
	lift:SetAttribute("Floors", floors)
	lift:SetAttribute("FloorHeight", FH)
	for k, v in attributes or {} do
		lift:SetAttribute(k, v)
	end

	part(lift, "ShaftBack", Vector3.new(outer, totalH, WT), frame * CFrame.new(0, totalH / 2, SHAFT / 2 + WT / 2))
	part(lift, "ShaftL", Vector3.new(WT, totalH, SHAFT), frame * CFrame.new(-SHAFT / 2 - WT / 2, totalH / 2, 0))
	part(lift, "ShaftR", Vector3.new(WT, totalH, SHAFT), frame * CFrame.new(SHAFT / 2 + WT / 2, totalH / 2, 0))
	part(lift, "ShaftRoof", Vector3.new(outer, 0.5, outer), frame * CFrame.new(0, totalH + 0.25, 0))
	part(lift, "Rail", Vector3.new(0.3, totalH, 0.3), frame * CFrame.new(0, totalH / 2, SHAFT / 2 - 0.15), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 65),
	})
	local side = (outer - SHAFT_DOOR_W) / 2
	local fz = -SHAFT / 2 - WT / 2
	for f = 1, floors do
		local yb = (f - 1) * FH
		part(lift, "FrontL", Vector3.new(side, FH, WT), frame * CFrame.new(-(SHAFT_DOOR_W / 2 + side / 2), yb + FH / 2, fz))
		part(lift, "FrontR", Vector3.new(side, FH, WT), frame * CFrame.new(SHAFT_DOOR_W / 2 + side / 2, yb + FH / 2, fz))
		part(lift, "FrontSill", Vector3.new(SHAFT_DOOR_W, Y0, WT), frame * CFrame.new(0, yb + Y0 / 2, fz))
		local lintelH = FH - Y0 - SHAFT_DOOR_H
		part(lift, "FrontLintel", Vector3.new(SHAFT_DOOR_W, lintelH, WT), frame * CFrame.new(0, yb + Y0 + SHAFT_DOOR_H + lintelH / 2, fz))
	end
	part(lift, "FrontTop", Vector3.new(outer, totalH - floors * FH, WT), frame * CFrame.new(0, floors * FH + (totalH - floors * FH) / 2, fz))

	buildCabin(lift, frame * CFrame.new(0, Y0 - 0.3, 0), floors)

	local landings = Instance.new("Folder")
	landings.Name = "Landings"
	for f = 1, floors do
		buildLanding(landings, f, frame, (f - 1) * FH + Y0)
	end
	landings.Parent = lift
	lift.Parent = parent
	CollectionService:AddTag(lift, "Elevator")
	return lift
end

return LiftBuilder
