--!strict
-- CityService: decides whether to build the OSM city at runtime and puts the
-- spawn on a real street near the centre.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CityBuilder = require(script.Parent.Parent.City.CityBuilder)
local Height = require(script.Parent.Parent.City.Height)

local CityService = {}

function CityService.HasMap(): boolean
	return CityBuilder.GetIndex() ~= nil
end

-- Temporary service point at the spawn: housing office (buy a flat in any city
-- entrance), key-cutting kiosk, car dealer and two parking spots. Their real
-- locations in Yuzhne are NEEDS VERIFICATION; move them once known.
function CityService.BuildServicePoint(center: Vector3)
	if workspace:FindFirstChild("ServicePoint") then
		return
	end
	local M = Config.Meters
	local folder = Instance.new("Folder")
	folder.Name = "ServicePoint"
	local function booth(name: string, tag: string, offset: Vector3, color: Color3, text: string)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = Vector3.new(M(2), M(2.4), M(1.5))
		local spot = center + offset
		p.CFrame = CFrame.new(spot.X, Height.At(spot.X, spot.Z) + M(1.2) + 0.2, spot.Z)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = folder
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = p
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 0.3)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = text
		label.Parent = gui
		CollectionService:AddTag(p, tag)
	end
	booth("HousingOffice", "HousingOffice", Vector3.new(-14, 0, 10), Color3.fromRGB(150, 60, 50), "ЖЕК")
	booth("KeyKiosk", "KeyKiosk", Vector3.new(-5, 0, 10), Color3.fromRGB(40, 90, 160), "КЛЮЧІ")
	booth("CarDealer", "CarDealer", Vector3.new(5, 0, 10), Color3.fromRGB(30, 60, 110), "АВТОСАЛОН")
	for i, x in { 16, 26 } do
		local pos = center + Vector3.new(x, 0, 4)
		pos = Vector3.new(pos.X, Height.At(pos.X, pos.Z) + 0.3, pos.Z)
		local spot = Instance.new("Part")
		spot.Name = "ParkingSpot" .. i
		spot.Anchored = true
		spot.CanCollide = false
		spot.Transparency = 0.6
		spot.Size = Vector3.new(M(2.6), 0.1, M(5))
		spot.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
		spot.Color = Color3.fromRGB(230, 200, 40)
		spot.Parent = folder
		CollectionService:AddTag(spot, "CarSpawn")
	end
	folder.Parent = workspace
end

function CityService.Init()
	local index = CityBuilder.GetIndex()
	if not index then
		return -- no generated data yet: the dev test scene is used instead
	end

	if Config.Map.ReplaceBaseplate then
		local baseplate = workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			baseplate:Destroy()
		end
	end

	if Config.Map.MoveSpawns then
		local spawnPos = Vector3.new(index.Spawn.x, Height.At(index.Spawn.x, index.Spawn.z) + 0.6, index.Spawn.z)
		local found = false
		for _, d in workspace:GetDescendants() do
			if d:IsA("SpawnLocation") then
				d.Position = spawnPos
				found = true
			end
		end
		if not found then
			local spawn = Instance.new("SpawnLocation")
			spawn.Anchored = true
			spawn.Size = Vector3.new(6, 1, 6)
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.Position = spawnPos
			spawn.Parent = workspace
		end
	end

	CityService.BuildServicePoint(Vector3.new(index.Spawn.x, 0, index.Spawn.z))

	if Config.Map.BuildAtRuntime and not workspace:FindFirstChild("City") then
		task.spawn(CityBuilder.Build, workspace, Config.Map.YieldEvery)
	end
end

return CityService
