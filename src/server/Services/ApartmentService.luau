--!strict
-- ApartmentService: apartment ownership.
--
-- Ownership is stored twice:
--   * a global registry DataStore ("<EntranceId>#<apt>" -> UserId), written with
--     UpdateAsync so two players on different servers can never buy the same flat;
--   * the owner's own PlayerData.Apartments (for quick lookup + client UI).
-- An in-memory index maps flats to *online* owners for the intercom.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local EntranceRegistry = require(script.Parent.EntranceRegistry)
local KeyService = require(script.Parent.KeyService)

local ApartmentService = {}

local registry: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.ApartmentRegistryStore)
	end)
	if ok then
		registry = result
	end
end
local memoryRegistry: { [string]: number } = {} -- Studio fallback
local useMemory = registry == nil

local onlineOwners: { [string]: Player } = {}
local busy: { [Player]: boolean } = {}

function ApartmentService.AptKey(entranceId: string, apt: number): string
	return entranceId .. "#" .. tostring(apt)
end

function ApartmentService.GetOnlineOwner(entranceId: string, apt: number): Player?
	local owner = onlineOwners[ApartmentService.AptKey(entranceId, apt)]
	if owner and owner.Parent then
		return owner
	end
	return nil
end

function ApartmentService.Owns(player: Player, entranceId: string, apt: number): boolean
	local data = PlayerDataService.Get(player)
	return data ~= nil and table.find(data.Apartments, ApartmentService.AptKey(entranceId, apt)) ~= nil
end

-- Atomically reserve a flat in the global registry.
local function reserve(key: string, userId: number): (boolean, string?)
	if not useMemory then
		local ds = registry :: DataStore
		local taken = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: number?): number?
				taken = false
				if old ~= nil and old ~= userId then
					taken = true
					return nil
				end
				return userId
			end)
		end)
		if ok then
			return not taken, if taken then "Цю квартиру вже хтось купив" else nil
		end
		warn("[Apartments] Registry write failed:", err)
		if not RunService:IsStudio() then
			return false, "Сервіс тимчасово недоступний, спробуйте пізніше"
		end
		useMemory = true
	end
	local old = memoryRegistry[key]
	if old ~= nil and old ~= userId then
		return false, "Цю квартиру вже хтось купив"
	end
	memoryRegistry[key] = userId
	return true, nil
end

function ApartmentService.Claim(player: Player, entranceId: string, apt: number): (boolean, string)
	local entrance = EntranceRegistry.Get(entranceId)
	if not entrance then
		return false, "Невідомий під'їзд"
	end
	if apt < entrance.AptFrom or apt > entrance.AptTo then
		return false, ("У цьому під'їзді квартири %d–%d"):format(entrance.AptFrom, entrance.AptTo)
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "Дані ще не завантажено"
	end
	if #data.Apartments >= Config.Apartments.MaxPerPlayer then
		return false, "У вас вже є квартира"
	end
	if busy[player] then
		return false, "Зачекайте…"
	end

	local price = Config.Apartments.Price
	if not PlayerDataService.TrySpend(player, price) then
		return false, ("Недостатньо грошей (потрібно %s%d)"):format(Config.Currency, price)
	end

	busy[player] = true
	local key = ApartmentService.AptKey(entranceId, apt)
	local ok, err = reserve(key, player.UserId)
	busy[player] = nil

	if not ok then
		PlayerDataService.AddMoney(player, price)
		return false, err or "Помилка"
	end
	if not PlayerDataService.Update(player, function(d)
		table.insert(d.Apartments, key)
	end) then
		return false, "Гравець вийшов"
	end
	onlineOwners[key] = player

	KeyService.CreateKey(player, entrance.Brand.DefaultKeyType, { entranceId }, ("Кв. %d · %s"):format(apt, entranceId))
	return true, ("Квартира №%d ваша! Ключ від під'їзду додано у в'язку."):format(apt)
end

function ApartmentService.Init()
	local function index(player: Player)
		local data = PlayerDataService.Get(player)
		if data then
			for _, key in data.Apartments do
				onlineOwners[key] = player
			end
		end
	end
	PlayerDataService.ProfileLoaded:Connect(index)
	for _, player in PlayerDataService.GetLoadedPlayers() do
		index(player)
	end

	PlayerDataService.ProfileReleasing:Connect(function(player: Player)
		for key, owner in onlineOwners do
			if owner == player then
				onlineOwners[key] = nil
			end
		end
		busy[player] = nil
	end)
end

return ApartmentService
