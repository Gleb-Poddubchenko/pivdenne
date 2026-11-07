--!strict
-- TestEquipmentBuilder (DEV ONLY): sports-goods kiosk, a fishing pond and a fish
-- stall, west of the test shops.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

local TestEquipmentBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(target: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.35)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
end

function TestEquipmentBuilder.Build()
	if workspace:FindFirstChild("TestEquipment") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TestEquipment"

	-- Facing +Z (towards the spawn): Front face is -Z, so rotate 180°.
	local facing = CFrame.Angles(0, math.pi, 0)
	local kiosk = part(folder, "EquipmentShop", Vector3.new(M(2.6), M(2.6), M(2)), CFrame.new(-75, M(1.3), -20) * facing,
		Color3.fromRGB(40, 120, 60))
	sign(kiosk, "СПОРТТОВАРИ")
	CollectionService:AddTag(kiosk, "EquipmentShop")

	local pond = part(folder, "Pond", Vector3.new(60, 1, 40), CFrame.new(-115, -0.3, -40), Color3.fromRGB(50, 100, 140), Enum.Material.Glass)
	pond.Transparency = 0.2
	pond.CanCollide = false -- wade in; the baseplate is just below the surface
	CollectionService:AddTag(pond, "FishingSpot")
	part(folder, "Pier", Vector3.new(6, 0.6, 16), CFrame.new(-100, 0.5, -28), Color3.fromRGB(110, 80, 50), Enum.Material.WoodPlanks)

	local stall = part(folder, "FishBuyer", Vector3.new(M(2.4), M(1.1), M(1.0)), CFrame.new(-80, M(0.55), -50) * facing,
		Color3.fromRGB(70, 110, 150), Enum.Material.Wood)
	sign(stall, "РИБА")
	CollectionService:AddTag(stall, "FishBuyer")

	folder.Parent = workspace
end

return TestEquipmentBuilder
