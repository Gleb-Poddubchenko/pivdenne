--!strict
-- TestElevatorBuilder (DEV ONLY): a 9-stop open-frame lift tower next to the test
-- block, built with LiftBuilder, plus landing decks with railings and a climbable
-- truss so you can reach any floor without the lift.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LiftBuilder = require(script.Parent.Parent.Building.LiftBuilder)

local M = Config.Meters

local FLOORS = 9
local FH = M(2.8)
local Y0 = LiftBuilder.Y0
local SHAFT = LiftBuilder.ShaftInner
local WT = LiftBuilder.WallThickness

local TestElevatorBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(170, 165, 155)
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

function TestElevatorBuilder.Build()
	if workspace:FindFirstChild("TestLiftTower") then
		return
	end
	local root = Instance.new("Folder")
	root.Name = "TestLiftTower"

	local centre = Vector3.new(-80, 0, 70)
	local frame = CFrame.lookAt(centre, centre + Vector3.new(0, 0, -1))
	LiftBuilder.Build(root, frame, FLOORS, FH, "test-lift/1", {
		StallChance = 0.25, -- high so testers actually see it
		RandomOutOfService = false,
	})

	-- Landing decks, railings and a truss "ladder" (not part of the lift model).
	local deckW, deckD = M(3.4), M(2.3)
	local deckZ = -(SHAFT / 2 + WT) - deckD / 2
	for f = 1, FLOORS do
		local level = (f - 1) * FH + Y0
		part(root, "Deck_" .. f, Vector3.new(deckW, 0.6, deckD), frame * CFrame.new(0, level - 0.3, deckZ), {
			Color = Color3.fromRGB(150, 145, 135),
		})
		if f > 1 then
			part(root, "RailFront", Vector3.new(deckW, M(1.0), 0.3), frame * CFrame.new(0, level + M(0.5), deckZ - deckD / 2 + 0.15), {
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(50, 80, 60),
			})
			part(root, "RailSide", Vector3.new(0.3, M(1.0), deckD), frame * CFrame.new(-deckW / 2 + 0.15, level + M(0.5), deckZ), {
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(50, 80, 60),
			})
		end
	end
	local trussH = math.ceil(((FLOORS - 1) * FH + Y0 + 4) / 2) * 2
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Size = Vector3.new(2, trussH, 2)
	truss.CFrame = frame * CFrame.new(deckW / 2 + 1, trussH / 2, deckZ)
	truss.Color = Color3.fromRGB(70, 70, 70)
	truss.Parent = root

	root.Parent = workspace
end

return TestElevatorBuilder
