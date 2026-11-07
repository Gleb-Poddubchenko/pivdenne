--!strict
-- StairwellBuilder: the inside of a Soviet panel-block entrance, built on demand
-- into a pocket slot (StairwellService). Plan in metres, +X right, +Z away from the
-- entrance door, front wall (with the entrance door) at z = 0:
--
--   z 5.0  ┌──────── back wall: flat · LIFT · flat ────────┐
--          │ half-landing │                                 │ right wall:
--          │  ▲ march A   ▼ march B    main landing         │ 2 flats
--   z 0.9  │ (x 0–1.2)  (x 1.2–2.4)    (x 2.4–7.2)          │
--   z 0    └ stair foot ─┴── entrance door / window ─────────┘
--          x 0          x 2.4                           x 7.2
--
-- Each storey (2.8 m): march A climbs to the half-landing (+1.4 m), march B climbs
-- back to the next floor's stair foot. Flat doors are ApartmentDoor models; the
-- lift (6+ floors) is a full LiftBuilder lift behind the back wall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LiftBuilder = require(script.Parent.LiftBuilder)
local FlatDoorBuilder = require(script.Parent.FlatDoorBuilder)

local M = Config.Meters

export type Spec = {
	EntranceId: string,
	Floors: number,
	AptFrom: number,
	AptTo: number,
	PerFloor: number,
	HasLift: boolean,
	HasChute: boolean,
}

export type Built = {
	Model: Model,
	EntryCFrame: CFrame,
	ExitParts: { BasePart },
	BoxCFrame: CFrame,
	BoxSize: Vector3,
}

local W, D = 7.2, 5.0
local FH_M = 2.8
local Y0_M = LiftBuilder.Y0 / Config.StudsPerMeter -- floor levels match the lift's stops
local LIFT_X = 4.9
local STEPS = 9

local WHITEWASH = Color3.fromRGB(226, 224, 214)
local OIL_PAINT = Color3.fromRGB(74, 120, 112) -- the lower-wall green
local CONCRETE = Color3.fromRGB(150, 146, 140)

local StairwellBuilder = {}

function StairwellBuilder.Build(parent: Instance, base: CFrame, spec: Spec, onExit: (Player) -> ()): Built
	local model = Instance.new("Model")
	model.Name = "Stairwell_" .. spec.EntranceId
	local floors = spec.Floors
	local function level(f: number): number
		return (f - 1) * FH_M + Y0_M
	end
	local topY = level(floors) + FH_M

	local function box(name: string, size: Vector3, center: Vector3, color: Color3, props: { [string]: any }?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = Vector3.new(M(size.X), M(size.Y), M(size.Z))
		p.CFrame = base * CFrame.new(M(center.X), M(center.Y), M(center.Z))
		p.Color = color
		p.Material = Enum.Material.Concrete
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
	local function at(x: number, y: number, z: number): Vector3
		return (base * CFrame.new(M(x), M(y), M(z))).Position
	end

	-- SHELL ---------------------------------------------------------------------
	local plaster = { Material = Enum.Material.Plaster }
	box("WallL", Vector3.new(0.2, topY, D), Vector3.new(-0.1, topY / 2, D / 2), WHITEWASH, plaster)
	box("WallR", Vector3.new(0.2, topY, D), Vector3.new(W + 0.1, topY / 2, D / 2), WHITEWASH, plaster)
	box("WallFront", Vector3.new(W + 0.4, topY, 0.2), Vector3.new(W / 2, topY / 2, -0.1), WHITEWASH, plaster)
	if spec.HasLift then
		local half = LiftBuilder.OuterWidth / Config.StudsPerMeter / 2
		local l, r = LIFT_X - half, LIFT_X + half
		box("WallBackL", Vector3.new(l + 0.2, topY, 0.2), Vector3.new((l - 0.2) / 2, topY / 2, D + 0.1), WHITEWASH, plaster)
		box("WallBackR", Vector3.new(W + 0.2 - r, topY, 0.2), Vector3.new((r + W + 0.2) / 2, topY / 2, D + 0.1), WHITEWASH, plaster)
	else
		box("WallBack", Vector3.new(W + 0.4, topY, 0.2), Vector3.new(W / 2, topY / 2, D + 0.1), WHITEWASH, plaster)
	end
	box("Roof", Vector3.new(W + 0.4, 0.3, D + 0.4), Vector3.new(W / 2, topY + 0.15, D / 2), CONCRETE)
	box("GroundStairs", Vector3.new(2.4, 0.2, D - 0.9), Vector3.new(1.2, level(1) - 0.1, 0.9 + (D - 0.9) / 2), CONCRETE)

	-- FLOORS --------------------------------------------------------------------
	local rise, run = 1.4 / STEPS, 3.2 / STEPS
	local doorSlots = {
		-- position on wall, facing direction (into the stairwell)
		{ p = Vector3.new(2.95, 0, D), look = Vector3.new(0, 0, -1) },
		{ p = Vector3.new(6.4, 0, D), look = Vector3.new(0, 0, -1) }, -- bell must clear the corner
		{ p = Vector3.new(W, 0, 1.4), look = Vector3.new(-1, 0, 0) },
		{ p = Vector3.new(W, 0, 3.3), look = Vector3.new(-1, 0, 0) },
		{ p = Vector3.new(2.95, 0, 0), look = Vector3.new(0, 0, 1) }, -- upper floors only
		{ p = Vector3.new(6.45, 0, 0), look = Vector3.new(0, 0, 1) },
	}
	local nextApt = spec.AptFrom

	for f = 1, floors do
		local lv = level(f)
		box("Landing", Vector3.new(W - 2.4, 0.2, D), Vector3.new(2.4 + (W - 2.4) / 2, lv - 0.1, D / 2), CONCRETE, {
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(130, 96, 82), -- terrazzo-ish
		})
		box("StairFoot", Vector3.new(2.4, 0.2, 0.9), Vector3.new(1.2, lv - 0.1, 0.45), CONCRETE)

		-- two-tone walls: oil paint up to 1.5 m on each landing
		local band = { Material = Enum.Material.SmoothPlastic, CanCollide = false }
		box("Paint", Vector3.new(0.02, 1.5, D), Vector3.new(W - 0.01, lv + 0.75, D / 2), OIL_PAINT, band)
		box("Paint", Vector3.new(W - 2.4, 1.5, 0.02), Vector3.new(2.4 + (W - 2.4) / 2, lv + 0.75, 0.01), OIL_PAINT, band)
		box("Paint", Vector3.new(0.02, 1.5, D), Vector3.new(0.01, lv + 0.75, D / 2), OIL_PAINT, band)

		local lamp = box("Lamp", Vector3.new(0.15, 0.2, 0.15), Vector3.new(4.8, lv + 2.55, 2.5), Color3.fromRGB(255, 236, 190), {
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Range = M(5)
		light.Brightness = 0.9
		light.Color = Color3.fromRGB(255, 225, 175)
		light.Parent = lamp

		-- painted floor number (lifts have their own stencil next to the shaft door)
		local sign = if spec.HasLift then nil else box("FloorNumber", Vector3.new(0.35, 0.35, 0.02), Vector3.new(4.8, lv + 1.7, D - 0.01), WHITEWASH, { CanCollide = false })
		if sign then
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.Parent = sign
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = Color3.fromRGB(40, 70, 140)
			label.Text = tostring(f)
			label.Parent = gui
		end

		if f > 1 then
			box("Window", Vector3.new(1.2, 1.2, 0.04), Vector3.new(4.8, lv + 1.5, 0.02), Color3.fromRGB(190, 215, 235), {
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			box("Railing", Vector3.new(0.05, 1.0, D - 0.9), Vector3.new(2.4, lv + 0.5, 0.9 + (D - 0.9) / 2), Color3.fromRGB(60, 50, 45), {
				Material = Enum.Material.Metal,
			})
		end

		-- flat doors on this landing
		local slots = if f == 1 then 4 else 6
		for s = 1, math.min(spec.PerFloor, slots) do
			if nextApt > spec.AptTo then
				break
			end
			local slot = doorSlots[s]
			local pos = at(slot.p.X, lv, slot.p.Z)
			FlatDoorBuilder.Build(model, CFrame.lookAt(pos, pos + slot.look), spec.EntranceId, nextApt)
			nextApt += 1
		end

		-- stairs up to the next floor
		if f < floors then
			local hl = lv + 1.4
			box("HalfLanding", Vector3.new(2.4, 0.2, 0.9), Vector3.new(1.2, hl - 0.1, 4.55), CONCRETE)
			for i = 1, STEPS do
				box("Step", Vector3.new(1.2, 0.3, run), Vector3.new(0.6, lv + i * rise - 0.15, 0.9 + (i - 0.5) * run), CONCRETE)
				box("Step", Vector3.new(1.2, 0.3, run), Vector3.new(1.8, hl + i * rise - 0.15, 4.1 - (i - 0.5) * run), CONCRETE)
			end
			-- handrail between the marches
			local function rail(a: Vector3, b: Vector3)
				local pa, pb = at(a.X, a.Y, a.Z), at(b.X, b.Y, b.Z)
				local bar = Instance.new("Part")
				bar.Name = "Handrail"
				bar.Anchored = true
				bar.Size = Vector3.new(0.15, 0.15, (pb - pa).Magnitude)
				bar.CFrame = CFrame.lookAt((pa + pb) / 2, pb)
				bar.Color = Color3.fromRGB(90, 60, 40)
				bar.Material = Enum.Material.Wood
				bar.Parent = model
			end
			rail(Vector3.new(1.2, lv + 0.9, 0.9), Vector3.new(1.2, hl + 0.9, 4.1))
			rail(Vector3.new(1.2, hl + 0.9, 4.1), Vector3.new(1.2, lv + FH_M + 0.9, 0.9))
			box("Balusters", Vector3.new(0.03, 0.9, 3.2), Vector3.new(1.2, lv + 0.7 + 0.7, 2.5), Color3.fromRGB(60, 50, 45), {
				Material = Enum.Material.Metal,
				Transparency = 0.4,
			})

			if spec.HasChute then
				box("ChuteHatch", Vector3.new(0.35, 0.3, 0.02), Vector3.new(0.25, hl + 0.9, 4.51), Color3.fromRGB(90, 90, 85), {
					Material = Enum.Material.Metal,
				})
			end
		end
	end
	if spec.HasChute then
		box("GarbageChute", Vector3.new(0.45, topY, 0.45), Vector3.new(0.25, topY / 2, 4.75), Color3.fromRGB(120, 118, 112))
	end

	-- GROUND FLOOR --------------------------------------------------------------
	local lv1 = level(1)
	box("Mailboxes", Vector3.new(1.4, 0.8, 0.25), Vector3.new(3.15, lv1 + 1.3, 0.14), Color3.fromRGB(70, 110, 90), {
		Material = Enum.Material.Metal,
	})
	local exitDoor = box("EntranceDoorInside", Vector3.new(1.0, 2.1, 0.12), Vector3.new(4.7, lv1 + 1.05, 0.08), Color3.fromRGB(74, 58, 46), {
		Material = Enum.Material.DiamondPlate,
	})
	local exitButton = box("ExitButton", Vector3.new(0.12, 0.12, 0.05), Vector3.new(5.45, lv1 + 1.3, 0.03), Color3.fromRGB(40, 200, 80), {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for _, p in { exitDoor, exitButton } do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Вийти"
		prompt.ObjectText = if p == exitButton then "Кнопка виходу" else "Двері під'їзду"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt.Parent = p
		prompt.Triggered:Connect(onExit)
	end

	if spec.HasLift then
		local frame = base * CFrame.new(M(LIFT_X), 0, M(D) + LiftBuilder.ShaftInner / 2 + LiftBuilder.WallThickness)
		LiftBuilder.Build(model, frame, floors, M(FH_M), spec.EntranceId .. "/lift", nil)
	end

	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = parent

	local entryPos = at(4.7, lv1, 1.3) + Vector3.new(0, 3, 0)
	return {
		Model = model,
		EntryCFrame = CFrame.lookAt(entryPos, entryPos + base.LookVector * -1),
		ExitParts = { exitDoor, exitButton },
		BoxCFrame = base * CFrame.new(M(W / 2), M(topY / 2), M(D / 2 + 1)),
		BoxSize = Vector3.new(M(W + 2), M(topY + 2), M(D + 4)),
	}
end

return StairwellBuilder
