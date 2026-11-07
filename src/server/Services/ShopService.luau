--!strict
-- ShopService: buying from shops and kiosks.
-- A shop is a Model tagged "Shop" with attributes ShopId (unique string),
-- Catalog (key in ShopCatalogs) and optional DisplayName, and a "Till" BasePart
-- (the counter / cash register). Prices always come from ShopCatalogs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Items = require(Shared:WaitForChild("Items"))
local ShopCatalogs = require(Shared:WaitForChild("ShopCatalogs"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

type Shop = { Id: string, Model: Model, Catalog: string, Till: BasePart }

local ShopService = {}

local shops: { [string]: Shop } = {}
local limiter = RateLimiter.new(5, 2)

local function priceOf(catalog: string, itemId: string): number?
	for _, entry in ShopCatalogs[catalog] or {} do
		if entry.ItemId == itemId then
			local item = Items[itemId]
			return entry.Price or (if item then item.Price else nil)
		end
	end
	return nil
end

local function register(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local id = inst:GetAttribute("ShopId")
	local catalog = inst:GetAttribute("Catalog")
	local till = inst:FindFirstChild("Till")
	if typeof(id) ~= "string" or typeof(catalog) ~= "string" or ShopCatalogs[catalog] == nil
		or not (till and till:IsA("BasePart"))
	then
		warn("[Shop] Needs ShopId, a valid Catalog and a Till part:", inst:GetFullName())
		return
	end
	if shops[id] then
		warn("[Shop] Duplicate ShopId", id)
		return
	end
	shops[id] = { Id = id, Model = inst, Catalog = catalog, Till = till }

	local name = inst:GetAttribute("DisplayName")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Купити"
	prompt.ObjectText = if typeof(name) == "string" then name else "Магазин"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "Shop")
	prompt:SetAttribute("ShopId", id)
	prompt:SetAttribute("Catalog", catalog)
	prompt.Parent = till
end

local function onBuy(player: Player, shopId: any, itemId: any, qty: any): (boolean, string)
	if not limiter.Check(player) then
		return false, "Не так швидко"
	end
	if typeof(shopId) ~= "string" or typeof(itemId) ~= "string"
		or not Validation.IsInteger(qty, 1, Config.Shops.MaxQuantityPerPurchase)
	then
		return false, "Невірний запит"
	end
	local shop = shops[shopId]
	if not shop then
		return false, "Магазин не знайдено"
	end
	if not Validation.IsNear(player, shop.Till, Config.InteractDistance) then
		return false, "Підійдіть до каси"
	end
	local price = priceOf(shop.Catalog, itemId)
	local item = Items[itemId]
	if not price or not item then
		return false, "Такого тут не продають"
	end
	if not InventoryService.CanAdd(player, itemId, qty) then
		return false, "Інвентар повний"
	end
	local total = price * qty
	if not PlayerDataService.TrySpend(player, total) then
		return false, ("Недостатньо грошей (потрібно %s%d)"):format(Config.Currency, total)
	end
	if not InventoryService.Add(player, itemId, qty) then
		PlayerDataService.AddMoney(player, total)
		return false, "Помилка, гроші повернуто"
	end
	Sfx.Play(shop.Till, Config.Sounds.Purchase, 0.5)
	return true, ("Куплено: %s ×%d за %s%d"):format(item.Name, qty, Config.Currency, total)
end

function ShopService.Init()
	for _, inst in CollectionService:GetTagged("Shop") do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal("Shop"):Connect(register)
	Net.Function("BuyItem").OnServerInvoke = onBuy
end

return ShopService
