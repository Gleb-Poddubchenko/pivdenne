--!strict
-- InventoryService: item stacks in the player's inventory and in apartment
-- storage (the fridge). All counts live in PlayerData; this module is the only
-- writer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Items = require(Shared:WaitForChild("Items"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)

local InventoryService = {}

local useLimiter = RateLimiter.new(3, 1)
local storageLimiter = RateLimiter.new(6, 2)

-- Set by InteriorService (avoids a require cycle): player -> aptKey they are inside.
local locationResolver: ((Player) -> string?)? = nil

local function countKeys(t: { [string]: number }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Can `qty` of `itemId` be added to `bag` within the given limits?
local function fits(bag: { [string]: number }, itemId: string, qty: number, maxDistinct: number, maxStack: number): boolean
	local have = bag[itemId] or 0
	if have == 0 and countKeys(bag) >= maxDistinct then
		return false
	end
	return have + qty <= maxStack
end

local function addTo(bag: { [string]: number }, itemId: string, qty: number)
	bag[itemId] = (bag[itemId] or 0) + qty
end

local function removeFrom(bag: { [string]: number }, itemId: string, qty: number)
	local left = (bag[itemId] or 0) - qty
	bag[itemId] = if left > 0 then left else nil
end

function InventoryService.Count(player: Player, itemId: string): number
	local data = PlayerDataService.Get(player)
	return if data then data.Inventory[itemId] or 0 else 0
end

-- Set by EquipmentService (the backpack): player -> (extra distinct items, extra per stack).
local capacityBonus: ((Player) -> (number, number))? = nil

function InventoryService.SetCapacityBonus(fn: (Player) -> (number, number))
	capacityBonus = fn
end

local function limits(player: Player): (number, number)
	local cfg = Config.Inventory
	local extraDistinct, extraStack = 0, 0
	if capacityBonus then
		extraDistinct, extraStack = capacityBonus(player)
	end
	return cfg.MaxDistinctItems + extraDistinct, cfg.MaxStack + extraStack
end

function InventoryService.CanAdd(player: Player, itemId: string, qty: number): boolean
	local data = PlayerDataService.Get(player)
	local maxDistinct, maxStack = limits(player)
	return data ~= nil and Items[itemId] ~= nil and fits(data.Inventory, itemId, qty, maxDistinct, maxStack)
end

function InventoryService.Add(player: Player, itemId: string, qty: number): boolean
	if qty <= 0 or not InventoryService.CanAdd(player, itemId, qty) then
		return false
	end
	return PlayerDataService.Update(player, function(d)
		addTo(d.Inventory, itemId, qty)
	end)
end

function InventoryService.Remove(player: Player, itemId: string, qty: number): boolean
	if qty <= 0 or InventoryService.Count(player, itemId) < qty then
		return false
	end
	return PlayerDataService.Update(player, function(d)
		removeFrom(d.Inventory, itemId, qty)
	end)
end

function InventoryService.SetLocationResolver(fn: (Player) -> string?)
	locationResolver = fn
end

local function onUse(player: Player, itemId: any)
	if not useLimiter.Check(player) or typeof(itemId) ~= "string" then
		return
	end
	local item = Items[itemId]
	if not item or not item.Use then
		return
	end
	if not InventoryService.Remove(player, itemId, 1) then
		return
	end
	local heal = item.Use.Heal
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if heal and humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + heal)
	end
	Net.Event("Notify"):FireClient(player, item.Use.Message, "good")
end

-- Move items between inventory ("out" of storage) and apartment storage ("in").
local function onStorageMove(player: Player, aptKey: any, itemId: any, qty: any, direction: any): (boolean, string)
	if not storageLimiter.Check(player) then
		return false, "Не так швидко"
	end
	if typeof(aptKey) ~= "string" or typeof(itemId) ~= "string" or Items[itemId] == nil
		or not Validation.IsInteger(qty, 1, Config.Storage.MaxStack)
		or (direction ~= "in" and direction ~= "out")
	then
		return false, "Невірний запит"
	end
	local data = PlayerDataService.Get(player)
	if not data or not table.find(data.Apartments, aptKey) then
		return false, "Це не ваш холодильник"
	end
	if not locationResolver or locationResolver(player) ~= aptKey then
		return false, "Ви не у своїй квартирі"
	end
	local storage = data.Storage[aptKey] or {}

	if direction == "in" then
		if (data.Inventory[itemId] or 0) < qty then
			return false, "Немає стільки"
		end
		if not fits(storage, itemId, qty, Config.Storage.MaxDistinctItems, Config.Storage.MaxStack) then
			return false, "Холодильник повний"
		end
		PlayerDataService.Update(player, function(d)
			removeFrom(d.Inventory, itemId, qty)
			d.Storage[aptKey] = d.Storage[aptKey] or {}
			addTo(d.Storage[aptKey], itemId, qty)
		end)
		return true, "Покладено в холодильник"
	else
		if (storage[itemId] or 0) < qty then
			return false, "Немає стільки"
		end
		local maxDistinct, maxStack = limits(player)
		if not fits(data.Inventory, itemId, qty, maxDistinct, maxStack) then
			return false, "Руки зайняті — інвентар повний"
		end
		PlayerDataService.Update(player, function(d)
			removeFrom(d.Storage[aptKey], itemId, qty)
			addTo(d.Inventory, itemId, qty)
		end)
		return true, "Взято з холодильника"
	end
end

function InventoryService.Init()
	Net.Event("UseItem").OnServerEvent:Connect(onUse)
	Net.Function("StorageMove").OnServerInvoke = onStorageMove
end

return InventoryService
