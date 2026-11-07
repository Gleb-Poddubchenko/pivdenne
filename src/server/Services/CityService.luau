--!strict
-- CityService: decides whether to build the OSM city at runtime and puts the
-- spawn on a real street near the centre.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

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
		p.CFrame = CFrame.new(spot.X, Height.Ground(spot.X, spot.Z) + M(1.2) + 0.2, spot.Z)
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
		pos = Vector3.new(pos.X, Height.Ground(pos.X, pos.Z) + 0.3, pos.Z)
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

local function isAdmin(player: Player): boolean
	return RunService:IsStudio() or player.UserId == game.CreatorId or table.find(Config.Debug.Admins, player.UserId) ~= nil
end

local function fmt(v: number?): string
	return if v then ("%.1f"):format(v) else "NONE"
end

-- Puts every SpawnLocation (creating one if needed) on the real ground at the spawn
-- point: solid, anchored, visible. Returns the position characters appear at.
local function placeSpawn(index: any): Vector3
	local x, z = index.Spawn.x, index.Spawn.z
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			table.insert(exclude, d)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	-- highest solid thing at the spawn: road surface, terrain, or the heightmap fallback
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -2600, 0), params)
	local y = if hit then hit.Position.Y else Height.Ground(x, z)

	local pads = exclude
	local found = false
	for _, d in pads do
		if d:IsA("SpawnLocation") then
			found = true
		end
	end
	if not found then
		local pad = Instance.new("SpawnLocation")
		pad.Name = "CitySpawn"
		pad.Parent = workspace
		table.insert(pads, pad)
	end
	for _, d in pads do
		if d:IsA("SpawnLocation") then
			d.Anchored = true
			d.CanCollide = true
			d.Neutral = true
			d.Transparency = 0
			d.Size = Vector3.new(8, 1, 8)
			d.Material = Enum.Material.Concrete
			d.Color = Color3.fromRGB(150, 146, 140)
			d.Position = Vector3.new(x, y + 0.5, z)
		end
	end
	return Vector3.new(x, y + 1, z)
end

function CityService.Init()
	local index = CityBuilder.GetIndex()
	Net.Function("DebugInfo").OnServerInvoke = function(player: Player)
		if not isAdmin(player) then
			return nil
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = if root then root.Position else Vector3.zero
		local city = workspace:FindFirstChild("City")
		return {
			("position %s"):format(tostring(Vector3.new(math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z)))),
			("heightmap Y here %s, terrain raycast Y here %s"):format(fmt(Height.At(pos.X, pos.Z)), fmt(Height.Probe(pos.X, pos.Z))),
			("city ready %s, progress %d%%"):format(tostring(workspace:GetAttribute("CityReady")), math.floor((workspace:GetAttribute("CityProgress") or 0) * 100)),
			("terrain samples missing %s, max error %s studs"):format(tostring(city and city:GetAttribute("TerrainMissing")), tostring(city and city:GetAttribute("TerrainMaxError"))),
			("buildings floating %s, base Y %s .. %s"):format(tostring(city and city:GetAttribute("BuildingsFloating")),
				tostring(city and city:GetAttribute("BuildingBaseMin")), tostring(city and city:GetAttribute("BuildingBaseMax"))),
		}
	end

	if not index then
		workspace:SetAttribute("CityReady", true) -- dev test scene: nothing to wait for
		return
	end

	if Config.Map.ReplaceBaseplate then
		local baseplate = workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			baseplate:Destroy()
		end
	end

	-- Nobody spawns until the ground exists: characters are loaded by hand once the
	-- city is built (and again after each death).
	workspace:SetAttribute("CityReady", false)
	workspace:SetAttribute("CityProgress", 0)
	Players.CharacterAutoLoads = false
	local ready = false
	local spawnPos = Vector3.new(index.Spawn.x, 0, index.Spawn.z)

	local function spawnPlayer(player: Player)
		if not ready or not player.Parent then
			return
		end
		pcall(function()
			player:RequestStreamAroundAsync(spawnPos, 15) -- stream the ground in first
		end)
		if player.Parent then
			player:LoadCharacter()
		end
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					task.delay(Players.RespawnTime, spawnPlayer, player)
				end)
			end
		end)
		if player.Character then
			player.Character:Destroy() -- joined before the city existed
		end
		spawnPlayer(player)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		task.spawn(watch, player)
	end

	task.spawn(function()
		local t0 = os.clock()
		if Config.Map.BuildAtRuntime and not workspace:FindFirstChild("City") then
			local ok, err = xpcall(CityBuilder.Build, debug.traceback, workspace, Config.Map.FrameBudget)
			if not ok then
				warn("[City] Build failed:\n" .. tostring(err))
			end
		elseif Height.Load() then
			Height.SetTerrainReady(true) -- baked city: terrain is saved in the place
		end
		CityService.BuildServicePoint(Vector3.new(index.Spawn.x, 0, index.Spawn.z))
		spawnPos = placeSpawn(index)
		print(("[CityDebug] spawn x=%.0f z=%.0f | heightmap Y %s | terrain raycast Y %s | spawn pad top Y %.1f | build took %.0f s"):format(
			index.Spawn.x, index.Spawn.z, fmt(Height.At(index.Spawn.x, index.Spawn.z)), fmt(Height.Probe(index.Spawn.x, index.Spawn.z)),
			spawnPos.Y - 0.5, os.clock() - t0))
		ready = true
		workspace:SetAttribute("CityReady", true)
		workspace:SetAttribute("CityProgress", 1)
		for _, player in Players:GetPlayers() do
			if not player.Character then
				task.spawn(spawnPlayer, player)
			end
		end
	end)
end

return CityService
