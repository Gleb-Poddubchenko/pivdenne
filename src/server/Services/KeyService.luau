--!strict
-- KeyService: intercom keys (TM tablets and RFID fobs) stored in player data.
-- Each key has an Id, a Type and the list of EntranceIds it is programmed for.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local KeyService = {}

local function countKeys(data: Types.PlayerData): number
	local n = 0
	for _ in data.Keys do
		n += 1
	end
	return n
end

function KeyService.CreateKey(player: Player, keyType: string, entrances: { string }, label: string): (string?, string?)
	if Config.Keys.Types[keyType] == nil then
		return nil, "Невідомий тип ключа"
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return nil, "Дані ще не завантажено"
	end
	if countKeys(data) >= Config.Keys.MaxKeysPerPlayer then
		return nil, "В'язка ключів повна"
	end

	local id = HttpService:GenerateGUID(false)
	local key: Types.KeyData = {
		Id = id,
		Type = keyType,
		Label = label,
		Entrances = table.clone(entrances),
		CreatedAt = os.time(),
	}
	PlayerDataService.Update(player, function(d)
		d.Keys[id] = key
	end)
	return id, nil
end

function KeyService.GetKey(player: Player, keyId: string): Types.KeyData?
	local data = PlayerDataService.Get(player)
	return if data then data.Keys[keyId] else nil
end

-- Does this player's key open this entrance's reader?
function KeyService.CanOpen(player: Player, keyId: string, entranceId: string, acceptedTypes: { string }): (boolean, string)
	local key = KeyService.GetKey(player, keyId)
	if not key then
		return false, "Ключ не знайдено"
	end
	if not table.find(acceptedTypes, key.Type) then
		return false, ("Цей зчитувач не приймає: %s"):format(Config.Keys.TypeNames[key.Type] or key.Type)
	end
	if not table.find(key.Entrances, entranceId) then
		return false, "Ключ не запрограмований для цих дверей"
	end
	return true, ""
end

-- Key-copy kiosk: duplicates a key (same type and entrances) for a fee.
function KeyService.CopyKey(player: Player, keyId: string): (boolean, string)
	local key = KeyService.GetKey(player, keyId)
	if not key then
		return false, "Ключ не знайдено"
	end
	local data = PlayerDataService.Get(player) :: Types.PlayerData
	if countKeys(data) >= Config.Keys.MaxKeysPerPlayer then
		return false, "В'язка ключів повна"
	end
	local price = Config.Keys.CopyPrice
	if not PlayerDataService.TrySpend(player, price) then
		return false, ("Недостатньо грошей (потрібно %s%d)"):format(Config.Currency, price)
	end
	local newId, err = KeyService.CreateKey(player, key.Type, key.Entrances, key.Label .. " (копія)")
	if not newId then
		PlayerDataService.AddMoney(player, price)
		return false, err or "Помилка"
	end
	return true, ("Копію виготовлено за %s%d"):format(Config.Currency, price)
end

function KeyService.Init() end

return KeyService
