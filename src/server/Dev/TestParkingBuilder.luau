--!strict
-- TestParkingBuilder (DEV ONLY): a car dealership booth, a parking lot with four
-- CarSpawn spots and a long straight road to try the cars on.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

local TestParkingBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.Asphalt
	p.Color = Color3.fromRGB(70, 70, 72)
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

function TestParkingBuilder.Build()
	if workspace:FindFirstChild("TestParking") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TestParking"

	local cx, cz = 115, 10
	-- Lot and road: thin slabs whose top is at y = 0.1
	part(folder, "Lot", Vector3.new(M(16), 0.2, M(18)), CFrame.new(cx, 0, cz))
	part(folder, "Road", Vector3.new(M(7), 0.2, 900), CFrame.new(cx + M(11.5), 0, cz))
	for i = -20, 20 do
		part(folder, "RoadLine", Vector3.new(0.4, 0.22, 12), CFrame.new(cx + M(11.5), 0, cz + i * 22), {
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(235, 235, 235),
		})
	end

	-- Four parking spots, cars facing -Z (towards the spawn side)
	for i, x in { -M(5.4), -M(1.8), M(1.8), M(5.4) } do
		local pos = Vector3.new(cx + x, 0.15, cz + M(3))
		local spot = part(folder, "ParkingSpot" .. i, Vector3.new(M(2.6), 0.1, M(5)), CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)), {
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(230, 200, 40),
			Transparency = 0.6,
			CanCollide = false,
		})
		CollectionService:AddTag(spot, "CarSpawn")
	end

	-- Dealership booth
	local booth = part(folder, "CarDealer", Vector3.new(M(3), M(2.6), M(2)), CFrame.new(cx - M(2), M(1.3) + 0.1, cz - M(7)), {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(30, 60, 110),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- faces -Z
	gui.Parent = booth
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.35)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "АВТОСАЛОН"
	label.Parent = gui
	CollectionService:AddTag(booth, "CarDealer")

	folder.Parent = workspace
end

return TestParkingBuilder
