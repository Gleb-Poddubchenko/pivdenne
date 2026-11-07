--!strict
-- FishingService: the fishing rod and the fish buyer — the first way to earn money.
--
-- Cast (click with the rod) near water -> a bobber lands in front of you ->
-- after a random wait "Клює!" -> click again within the bite window to catch.
-- Water = parts tagged "FishingSpot" plus the water/beach areas from the OSM map
-- data. Fish go to the inventory and are sold at parts tagged "FishBuyer".

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Items = require(Shared:WaitForChild("Items"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local EquipmentService = require(script.Parent.EquipmentService)
local MapData = require(script.Parent.Parent.City.MapData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

type Zone = { MinX: number, MinZ: number, MaxX: number, MaxZ: number, P: { number } }
type Session = {
	Tool: Tool,
	Bobber: Part,
	State: string, -- "waiting" | "bite"
	Token: number,
}

local FishingService = {}

local zones: { Zone } = {}
local sessions: { [Player]: Session } = {}
local tokens: { [Player]: number } = {}
local sellLimiter = RateLimiter.new(2, 0.5)
local stateEvent: RemoteEvent

local function loadZones()
	for _, chunk in MapData.Chunks() do
		for _, a in chunk.a do
			if a.t == "water" or a.t == "beach" then
				local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
				for i = 1, #a.p, 2 do
					minX = math.min(minX, a.p[i])
					maxX = math.max(maxX, a.p[i])
					minZ = math.min(minZ, a.p[i + 1])
					maxZ = math.max(maxZ, a.p[i + 1])
				end
				table.insert(zones, { MinX = minX, MinZ = minZ, MaxX = maxX, MaxZ = maxZ, P = a.p })
			end
		end
	end
end

local function nearPolygon(x: number, z: number, p: { number }, margin: number): boolean
	local n = #p // 2
	local inside = false
	local j = n
	for i = 1, n do
		local xi, zi, xj, zj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) ~= 0 and (zj - zi) or 1e-9) + xi then
			inside = not inside
		end
		-- distance to edge
		local dx, dz = xi - xj, zi - zj
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((x - xj) * dx + (z - zj) * dz) / len2, 0, 1) else 0
		local qx, qz = xj + t * dx, zj + t * dz
		if (x - qx) ^ 2 + (z - qz) ^ 2 <= margin * margin then
			return true
		end
		j = i
	end
	return inside
end

function FishingService.IsNearWater(position: Vector3): boolean
	local margin = Config.Fishing.WaterDistance
	for _, inst in CollectionService:GetTagged("FishingSpot") do
		if inst:IsA("BasePart") then
			local p = inst.CFrame:PointToObjectSpace(position)
			local half = inst.Size / 2
			local dx = math.max(math.abs(p.X) - half.X, 0)
			local dz = math.max(math.abs(p.Z) - half.Z, 0)
			if dx * dx + dz * dz <= margin * margin then
				return true
			end
		end
	end
	for _, zone in zones do
		if position.X >= zone.MinX - margin and position.X <= zone.MaxX + margin
			and position.Z >= zone.MinZ - margin and position.Z <= zone.MaxZ + margin
			and nearPolygon(position.X, position.Z, zone.P, margin)
		then
			return true
		end
	end
	return false
end

local function rollCatch(): string
	local total = 0
	for _, w in Config.Fishing.Catch do
		total += w
	end
	local r = math.random() * total
	for id, w in Config.Fishing.Catch do
		r -= w
		if r <= 0 then
			return id
		end
	end
	return "fish_goby"
end

local function stop(player: Player, reason: string?)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	tokens[player] = (tokens[player] or 0) + 1
	s.Bobber:Destroy()
	if reason and player.Parent then
		stateEvent:FireClient(player, reason, {})
	end
end

local function cast(player: Player, tool: Tool)
	local current = sessions[player]
	if current then
		if current.State == "bite" then
			-- Hooked it!
			local itemId = rollCatch()
			stop(player, nil)
			local item = Items[itemId]
			if InventoryService.Add(player, itemId, 1) then
				stateEvent:FireClient(player, "caught", { Name = item and item.Name or itemId })
			else
				stateEvent:FireClient(player, "full", {})
			end
		else
			stop(player, "reeled")
		end
		return
	end

	local root = Validation.GetRoot(player)
	if not root then
		return
	end
	if not FishingService.IsNearWater(root.Position) then
		stateEvent:FireClient(player, "nowater", {})
		return
	end

	local landing = root.Position + root.CFrame.LookVector * Config.Fishing.CastDistance
	local ray = workspace:Raycast(landing + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0))
	local surfaceY = if ray then ray.Position.Y else root.Position.Y - 2.8

	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Shape = Enum.PartType.Ball
	bobber.Size = Vector3.new(0.5, 0.5, 0.5)
	bobber.Color = Color3.fromRGB(230, 40, 30)
	bobber.Anchored = true
	bobber.CanCollide = false
	bobber.CanQuery = false
	bobber.Position = Vector3.new(landing.X, surfaceY + 0.15, landing.Z)
	local a1 = Instance.new("Attachment")
	a1.Parent = bobber
	local rod = tool:FindFirstChild("Rod")
	local tip = rod and rod:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then
		local line = Instance.new("Beam")
		line.Attachment0 = tip
		line.Attachment1 = a1
		line.Width0 = 0.04
		line.Width1 = 0.04
		line.Color = ColorSequence.new(Color3.fromRGB(230, 230, 230))
		line.FaceCamera = true
		line.CurveSize0 = -2
		line.Parent = bobber
	end
	bobber.Parent = workspace
	Sfx.Play(bobber, Config.Sounds.FishingCast, 0.5)

	tokens[player] = (tokens[player] or 0) + 1
	local token = tokens[player]
	local session: Session = { Tool = tool, Bobber = bobber, State = "waiting", Token = token }
	sessions[player] = session
	stateEvent:FireClient(player, "cast", {})

	local cfg = Config.Fishing
	task.delay(cfg.BiteMin + math.random() * (cfg.BiteMax - cfg.BiteMin), function()
		if tokens[player] ~= token or sessions[player] ~= session then
			return
		end
		session.State = "bite"
		bobber.Position -= Vector3.new(0, 0.3, 0) -- the bobber dips
		Sfx.Play(bobber, Config.Sounds.FishingSplash, 0.6)
		stateEvent:FireClient(player, "bite", {})
		task.delay(cfg.BiteWindow, function()
			if tokens[player] == token and sessions[player] == session then
				stop(player, "escaped")
			end
		end)
	end)
end

local function sellAll(player: Player, buyer: BasePart)
	if not sellLimiter.Check(player) or not Validation.IsNear(player, buyer, Config.InteractDistance) then
		return
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	local total, count = 0, 0
	for itemId, qty in data.Inventory do
		local item = Items[itemId]
		if item and item.Category == "Риба" then
			total += item.Price * qty
			count += qty
		end
	end
	if count == 0 then
		Net.Event("Notify"):FireClient(player, "У вас немає риби. Візьміть вудку й ідіть до води.", "bad")
		return
	end
	PlayerDataService.Update(player, function(d)
		for itemId in d.Inventory do
			local item = Items[itemId]
			if item and item.Category == "Риба" then
				d.Inventory[itemId] = nil
			end
		end
		d.Money += total
	end)
	Net.Event("Notify"):FireClient(player, ("Продано %d риб за %s%d"):format(count, Config.Currency, total), "good")
end

function FishingService.Init()
	stateEvent = Net.Event("FishingState")
	loadZones()

	EquipmentService.ToolActivated:Connect(function(player: Player, tool: Tool, id: string)
		if id == "fishingrod" then
			cast(player, tool)
		end
	end)

	local function setupBuyer(inst: Instance)
		if inst:IsA("BasePart") and not inst:FindFirstChild("FishPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "FishPrompt"
			prompt.ActionText = "Продати рибу"
			prompt.ObjectText = "Рибний ряд"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.Parent = inst
			prompt.Triggered:Connect(function(player: Player)
				sellAll(player, inst)
			end)
		end
	end
	for _, inst in CollectionService:GetTagged("FishBuyer") do
		setupBuyer(inst)
	end
	CollectionService:GetInstanceAddedSignal("FishBuyer"):Connect(setupBuyer)

	-- Reel in when the rod is put away or the player walks off (2 Hz, active casts only).
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in sessions do
				local root = Validation.GetRoot(player)
				if s.Tool.Parent ~= player.Character or not root
					or (root.Position - s.Bobber.Position).Magnitude > Config.Fishing.MaxDrift + Config.Fishing.CastDistance
				then
					stop(player, "reeled")
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		stop(player, nil)
		tokens[player] = nil
	end)
end

return FishingService
