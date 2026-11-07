--!strict
-- EquipmentService: buying equipment, choosing the loadout, and giving the
-- carried tools to the character on every spawn. Tool behaviour that is simple
-- (flashlight, umbrella) lives here; fishing has its own service.
--
-- Equipment is sold at BaseParts tagged "EquipmentShop" (test scene, and real
-- sports/hardware shops and markets from OSM in the city).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Equipment = require(Shared:WaitForChild("Equipment"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local ToolFactory = require(script.Parent.Parent.Equipment.ToolFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local EquipmentService = {}

local limiter = RateLimiter.new(3, 0.5)
local toolActivated = Instance.new("BindableEvent")
-- (player, tool, equipmentId) for other services (FishingService)
EquipmentService.ToolActivated = toolActivated.Event

function EquipmentService.IsCarrying(player: Player, id: string): boolean
	local data = PlayerDataService.Get(player)
	return data ~= nil and data.Equipment[id] == true and table.find(data.Loadout, id) ~= nil
end

local function onToolActivated(player: Player, tool: Tool, id: string)
	local handle = tool:FindFirstChild("Handle")
	if id == "flashlight" then
		local beam = handle and handle:FindFirstChild("Beam")
		if beam and beam:IsA("SpotLight") then
			beam.Enabled = not beam.Enabled
			local lens = tool:FindFirstChild("Lens")
			if lens and lens:IsA("BasePart") then
				lens.Color = if beam.Enabled then Color3.fromRGB(255, 250, 220) else Color3.fromRGB(220, 220, 200)
			end
			if handle and handle:IsA("BasePart") then
				Sfx.Play(handle, Config.Sounds.FlashlightClick, 0.4)
			end
		end
	elseif id == "umbrella" then
		local canopy = tool:FindFirstChild("Canopy")
		if canopy and canopy:IsA("BasePart") then
			local open = not (tool:GetAttribute("Open") == true)
			tool:SetAttribute("Open", open)
			canopy.Transparency = if open then 0 else 1
			if handle and handle:IsA("BasePart") then
				Sfx.Play(handle, Config.Sounds.UmbrellaOpen, 0.5)
			end
		end
	end
	toolActivated:Fire(player, tool, id)
end

-- Rebuild the carried tools (and the backpack) for the current character.
local function refresh(player: Player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local data = PlayerDataService.Get(player)
	if not (character and backpack and data) then
		return
	end
	for _, container in { backpack, character } do
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("EquipmentId") then
				item:Destroy()
			end
		end
	end
	local oldBag = character:FindFirstChild("EquipmentBackpack")
	if oldBag then
		oldBag:Destroy()
	end

	for _, id in data.Loadout do
		local def = Equipment.Defs[id]
		if def and data.Equipment[id] then
			if def.Kind == "Passive" then
				if id == "backpack" then
					ToolFactory.AttachBackpack(character)
				end
			else
				local tool = ToolFactory.Build(id, def.Name)
				if tool then
					tool.Activated:Connect(function()
						-- Tool.Activated replicates; make sure the holder is this player.
						if tool.Parent == player.Character then
							onToolActivated(player, tool, id)
						end
					end)
					tool.Parent = backpack
				end
			end
		end
	end
end

local function onBuy(player: Player, id: any): (boolean, string)
	if not limiter.Check(player) or typeof(id) ~= "string" then
		return false, "Не так швидко"
	end
	local def = Equipment.Defs[id]
	if not def then
		return false, "Такого немає"
	end
	local nearShop = false
	for _, inst in CollectionService:GetTagged("EquipmentShop") do
		if inst:IsA("BasePart") and Validation.IsNear(player, inst, Config.InteractDistance) then
			nearShop = true
			break
		end
	end
	if not nearShop then
		return false, "Підійдіть до магазину спорядження"
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "Дані ще не завантажено"
	end
	if data.Equipment[id] then
		return false, "У вас це вже є"
	end
	if not PlayerDataService.TrySpend(player, def.Price) then
		return false, ("Недостатньо грошей (потрібно %s%d)"):format(Config.Currency, def.Price)
	end
	PlayerDataService.Update(player, function(d)
		d.Equipment[id] = true
		if #d.Loadout < Config.Equipment.LoadoutSlots then
			table.insert(d.Loadout, id)
		end
	end)
	refresh(player)
	return true, ("Куплено: %s"):format(def.Name)
end

local function onSetLoadout(player: Player, list: any): (boolean, string)
	if not limiter.Check(player) or typeof(list) ~= "table" then
		return false, "Невірний запит"
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "Дані ще не завантажено"
	end
	local clean: { string } = {}
	for _, id in list do
		if typeof(id) == "string" and data.Equipment[id] and not table.find(clean, id) then
			table.insert(clean, id)
		end
		if #clean >= Config.Equipment.LoadoutSlots then
			break
		end
	end
	PlayerDataService.Update(player, function(d)
		d.Loadout = clean
	end)
	refresh(player)
	return true, "Спорядження оновлено"
end

function EquipmentService.Init()
	InventoryService.SetCapacityBonus(function(player: Player): (number, number)
		if EquipmentService.IsCarrying(player, "backpack") then
			return Config.Equipment.BackpackBonusDistinct, Config.Equipment.BackpackBonusStack
		end
		return 0, 0
	end)

	local function setupShop(inst: Instance)
		if inst:IsA("BasePart") and not inst:FindFirstChild("EquipmentPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "EquipmentPrompt"
			prompt.ActionText = "Спорядження"
			prompt.ObjectText = "Спорттовари"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("Action", "EquipmentShop")
			prompt.Parent = inst
		end
	end
	for _, inst in CollectionService:GetTagged("EquipmentShop") do
		setupShop(inst)
	end
	CollectionService:GetInstanceAddedSignal("EquipmentShop"):Connect(setupShop)

	Net.Function("BuyEquipment").OnServerInvoke = onBuy
	Net.Function("SetLoadout").OnServerInvoke = onSetLoadout

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			player:WaitForChild("Backpack", 10)
			refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- The profile may load after the first character spawned.
	PlayerDataService.ProfileLoaded:Connect(refresh)
end

return EquipmentService
