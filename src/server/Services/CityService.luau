--!strict
-- CityService: decides whether to build the OSM city at runtime and puts the
-- spawn on a real street near the centre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local CityBuilder = require(script.Parent.Parent.City.CityBuilder)

local CityService = {}

function CityService.HasMap(): boolean
	return CityBuilder.GetIndex() ~= nil
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
		local spawnPos = Vector3.new(index.Spawn.x, 0.6, index.Spawn.z)
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

	if Config.Map.BuildAtRuntime and not workspace:FindFirstChild("City") then
		task.spawn(CityBuilder.Build, workspace, Config.Map.YieldEvery)
	end
end

return CityService
