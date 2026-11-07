--!strict
-- KioskService: key-copy kiosks ("KeyKiosk") and the housing office ("HousingOffice",
-- ЖЕК) where flats are bought. Tag a BasePart (the counter) with one of those tags;
-- this service adds the ProximityPrompt and validates every request server-side.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local KeyService = require(script.Parent.KeyService)
local ApartmentService = require(script.Parent.ApartmentService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)

local KIOSKS = {
	KeyKiosk = { ActionText = "Виготовити ключ", ObjectText = "Ключі · Домофони" },
	HousingOffice = { ActionText = "Купити квартиру", ObjectText = "ЖЕК" },
}

local KioskService = {}

local limiter = RateLimiter.new(3, 0.5)

local function nearTagged(player: Player, tag: string): boolean
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and Validation.IsNear(player, inst, Config.InteractDistance) then
			return true
		end
	end
	return false
end

local function setup(inst: Instance, tag: string)
	if not inst:IsA("BasePart") or inst:FindFirstChild(tag .. "Prompt") then
		return
	end
	local info = KIOSKS[tag]
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = tag .. "Prompt"
	prompt.ActionText = info.ActionText
	prompt.ObjectText = info.ObjectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", tag)
	prompt.Parent = inst
end

function KioskService.Init()
	for tag in KIOSKS do
		for _, inst in CollectionService:GetTagged(tag) do
			setup(inst, tag)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			setup(inst, tag)
		end)
	end

	Net.Function("CopyKey").OnServerInvoke = function(player: Player, keyId: any): (boolean, string)
		if not limiter.Check(player) then
			return false, "Не так швидко"
		end
		if typeof(keyId) ~= "string" then
			return false, "Невірний запит"
		end
		if not nearTagged(player, "KeyKiosk") then
			return false, "Підійдіть до кіоску"
		end
		return KeyService.CopyKey(player, keyId)
	end

	Net.Function("ClaimApartment").OnServerInvoke = function(player: Player, entranceId: any, apt: any): (boolean, string)
		if not limiter.Check(player) then
			return false, "Не так швидко"
		end
		if typeof(entranceId) ~= "string" or not Validation.IsInteger(apt, 0, 9999) then
			return false, "Невірний номер"
		end
		if not nearTagged(player, "HousingOffice") then
			return false, "Підійдіть до ЖЕКу"
		end
		return ApartmentService.Claim(player, entranceId, apt)
	end
end

return KioskService
