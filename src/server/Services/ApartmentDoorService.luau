--!strict
-- ApartmentDoorService: flat doors in stairwells — entering/leaving interiors,
-- the doorbell and guest passes.
--
-- A flat door is a Model tagged "ApartmentDoor" with attributes EntranceId and
-- Apt, and children "Door" (BasePart, front face towards the stairwell) and
-- "Bell" (BasePart). Owners walk straight in; visitors ring, and the owner (who
-- must be inside the flat to hear it) lets them in, which grants a guest pass.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local ApartmentService = require(script.Parent.ApartmentService)
local InteriorService = require(script.Parent.InteriorService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

type FlatDoor = {
	Model: Model,
	EntranceId: string,
	Apt: number,
	AptKey: string,
	Door: BasePart,
	Bell: BasePart,
	OutsideCFrame: CFrame,
}

type Ring = { Id: string, Visitor: Player, Owner: Player, Door: FlatDoor }

local ApartmentDoorService = {}

local doors: { [string]: FlatDoor } = {} -- by aptKey
local guests: { [string]: { [number]: number } } = {} -- aptKey -> userId -> expiry (os.time)
local rings: { [string]: Ring } = {}
local ringByVisitor: { [Player]: Ring } = {}
local busy: { [Player]: boolean } = {}

local doorLimiter = RateLimiter.new(3, 0.5)
local bellLimiter = RateLimiter.new(3, 0.3)
local answerLimiter = RateLimiter.new(5, 1)

local notifyEvent: RemoteEvent
local fadeEvent: RemoteEvent

local function notify(player: Player, text: string, kind: string?)
	notifyEvent:FireClient(player, text, kind)
end

local function teleport(player: Player, cf: CFrame)
	fadeEvent:FireClient(player, 0.8)
	task.wait(0.25)
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 3)
	end)
	local character = player.Character
	if character and player.Parent then
		character:PivotTo(cf)
	end
end

local function canEnter(player: Player, d: FlatDoor): boolean
	if ApartmentService.Owns(player, d.EntranceId, d.Apt) then
		return true
	end
	local pass = guests[d.AptKey] and guests[d.AptKey][player.UserId]
	return pass ~= nil and pass > os.time()
end

local function enter(player: Player, d: FlatDoor)
	if busy[player] then
		return
	end
	busy[player] = true
	Sfx.Play(d.Door, Config.Sounds.FlatDoor, 0.6)
	local interior = InteriorService.GetOrCreate(d.AptKey)
	teleport(player, interior.EntryCFrame)
	InteriorService.SetLocation(player, d.AptKey) -- after arriving, so housekeeping never sees a half-teleported player
	busy[player] = nil
end

local function exitFlat(player: Player, aptKey: string)
	if busy[player] then
		return
	end
	busy[player] = true
	local d = doors[aptKey]
	InteriorService.SetLocation(player, nil)
	if d then
		Sfx.Play(d.Door, Config.Sounds.FlatDoor, 0.6)
		teleport(player, d.OutsideCFrame)
	else
		player:LoadCharacter() -- door gone (map changed): back to spawn
	end
	busy[player] = nil
end

local function onDoor(player: Player, d: FlatDoor)
	if not doorLimiter.Check(player) or not Validation.IsNear(player, d.Door, Config.InteractDistance) then
		return
	end
	if canEnter(player, d) then
		enter(player, d)
	else
		notify(player, "Зачинено. Подзвоніть у дзвінок.", "bad")
	end
end

local function clearRing(ring: Ring)
	rings[ring.Id] = nil
	if ringByVisitor[ring.Visitor] == ring then
		ringByVisitor[ring.Visitor] = nil
	end
end

local function onBell(player: Player, d: FlatDoor)
	if not bellLimiter.Check(player) or not Validation.IsNear(player, d.Bell, Config.InteractDistance) then
		return
	end
	Sfx.Play(d.Bell, Config.Sounds.Doorbell, 0.7)
	local owner = ApartmentService.GetOnlineOwner(d.EntranceId, d.Apt)
	if owner == player then
		notify(player, "Це ваша квартира — просто заходьте.")
		return
	end
	if not owner or InteriorService.GetLocation(owner) ~= d.AptKey then
		task.delay(3, function()
			if player.Parent then
				notify(player, "Ніхто не відчиняє.", "bad")
			end
		end)
		return
	end
	if ringByVisitor[player] then
		return -- already waiting for an answer
	end

	local ring: Ring = { Id = HttpService:GenerateGUID(false), Visitor = player, Owner = owner, Door = d }
	rings[ring.Id] = ring
	ringByVisitor[player] = ring
	Net.Event("DoorbellRing"):FireClient(owner, ring.Id, ("Кв. %d"):format(d.Apt), player.DisplayName)
	notify(player, "Дзвонимо… Хтось удома.")
	task.delay(Config.Interiors.DoorbellTimeout, function()
		if rings[ring.Id] == ring then
			clearRing(ring)
			if player.Parent then
				notify(player, "Вам не відчинили.", "bad")
			end
		end
	end)
end

local function onAnswer(player: Player, ringId: any, accept: any)
	if not answerLimiter.Check(player) or typeof(ringId) ~= "string" then
		return
	end
	local ring = rings[ringId]
	if not ring or ring.Owner ~= player then
		return
	end
	clearRing(ring)
	local visitor = ring.Visitor
	if not visitor.Parent then
		return
	end
	if accept == true then
		local key = ring.Door.AptKey
		guests[key] = guests[key] or {}
		guests[key][visitor.UserId] = os.time() + Config.Interiors.GuestPassDuration
		if Validation.IsNear(visitor, ring.Door.Door, 20) then
			notify(visitor, "Вам відчинили. Заходьте!", "good")
			task.spawn(enter, visitor, ring.Door)
		else
			notify(visitor, "Вам відчинили, але ви пішли. Поверніться до дверей.")
		end
	else
		notify(visitor, "Вам не відчинили.", "bad")
	end
end

local function makePrompt(part: BasePart, actionText: string, objectText: string, key: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

local function register(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local entranceId = inst:GetAttribute("EntranceId")
	local apt = inst:GetAttribute("Apt")
	local door = inst:FindFirstChild("Door")
	local bell = inst:FindFirstChild("Bell")
	if typeof(entranceId) ~= "string" or not Validation.IsInteger(apt, 0, 9999)
		or not (door and door:IsA("BasePart") and bell and bell:IsA("BasePart"))
	then
		warn("[FlatDoor] Needs EntranceId, Apt, Door and Bell:", inst:GetFullName())
		return
	end
	local aptKey = ApartmentService.AptKey(entranceId, apt)
	if doors[aptKey] then
		warn("[FlatDoor] Duplicate door for", aptKey)
		return
	end
	-- Stand ~1 m in front of the door, facing away from it.
	local front = door.CFrame * CFrame.new(0, 0, -Config.Meters(1.0))
	local d: FlatDoor = {
		Model = inst,
		EntranceId = entranceId,
		Apt = apt,
		AptKey = aptKey,
		Door = door,
		Bell = bell,
		OutsideCFrame = CFrame.lookAt(front.Position, front.Position + door.CFrame.LookVector),
	}
	doors[aptKey] = d

	local label = ("Квартира %d"):format(apt)
	makePrompt(door, "Увійти", label, Enum.KeyCode.E).Triggered:Connect(function(player)
		onDoor(player, d)
	end)
	makePrompt(bell, "Подзвонити", label, Enum.KeyCode.F).Triggered:Connect(function(player)
		onBell(player, d)
	end)
end

function ApartmentDoorService.Init()
	notifyEvent = Net.Event("Notify")
	fadeEvent = Net.Event("Fade")

	InteriorService.SetExitHandler(function(player, aptKey)
		task.spawn(exitFlat, player, aptKey)
	end)
	Net.Event("DoorbellAnswer").OnServerEvent:Connect(onAnswer)

	for _, inst in CollectionService:GetTagged("ApartmentDoor") do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal("ApartmentDoor"):Connect(register)

	Players.PlayerRemoving:Connect(function(player)
		local ring = ringByVisitor[player]
		if ring then
			clearRing(ring)
		end
		for id, r in rings do
			if r.Owner == player then
				rings[id] = nil
				ringByVisitor[r.Visitor] = nil
			end
		end
		busy[player] = nil
	end)
end

return ApartmentDoorService
