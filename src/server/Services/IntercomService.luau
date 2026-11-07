--!strict
-- IntercomService: dialling flats, owner answering/talking/opening, key reader.
--
-- Call flow:
--   caller  -- IntercomDial(entranceId, apt) -->  server
--   server  -- IncomingCall(callId, ...)     -->  online owner (if any)
--   owner   -- CallAction(callId, "answer" | "open" | "decline" | "hangup") --> server
--   both    -- CallChat(callId, text) --> server --(filtered)--> both
-- One active call per entrance panel and per owner. Unowned / offline flats
-- simply ring out. Everything is validated here; the client only renders.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local EntranceRegistry = require(script.Parent.EntranceRegistry)
local DoorService = require(script.Parent.DoorService)
local KeyService = require(script.Parent.KeyService)
local ApartmentService = require(script.Parent.ApartmentService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

type Entrance = EntranceRegistry.Entrance

type Call = {
	Id: string,
	Entrance: Entrance,
	Apt: number,
	Caller: Player,
	Owner: Player?,
	State: "Ringing" | "Connected",
	RingSound: Sound?,
}

local IntercomService = {}

local calls: { [string]: Call } = {}
local byEntrance: { [string]: Call } = {}
local byCaller: { [Player]: Call } = {}
local byOwner: { [Player]: Call } = {}
local displayGen: { [string]: number } = {}

local dialLimiter = RateLimiter.new(4, 0.5)
local keyLimiter = RateLimiter.new(5, 1)
local actionLimiter = RateLimiter.new(8, 2)
local chatLimiter = RateLimiter.new(5, 0.7)

local GREEN = Color3.fromRGB(60, 255, 90)
local RED = Color3.fromRGB(255, 50, 40)

local stateEvent: RemoteEvent
local incomingEvent: RemoteEvent
local endedEvent: RemoteEvent
local chatEvent: RemoteEvent

-- Physical panel display, visible to everyone nearby.
local function setDisplay(entrance: Entrance, text: string, resetAfter: number?)
	local gen = (displayGen[entrance.Id] or 0) + 1
	displayGen[entrance.Id] = gen
	entrance.Display.Text = text
	if resetAfter then
		task.delay(resetAfter, function()
			if displayGen[entrance.Id] == gen then
				entrance.Display.Text = entrance.Brand.Text.Idle
			end
		end)
	end
end

local function endCall(call: Call, reason: string)
	if calls[call.Id] ~= call then
		return
	end
	calls[call.Id] = nil
	byEntrance[call.Entrance.Id] = nil
	byCaller[call.Caller] = nil
	if call.Owner and byOwner[call.Owner] == call then
		byOwner[call.Owner] = nil
	end
	if call.RingSound then
		call.RingSound:Destroy()
	end

	local text = call.Entrance.Brand.Text
	setDisplay(call.Entrance, if reason == "opened" then text.Open else text.NoAnswer, 2.5)

	if call.Caller.Parent then
		stateEvent:FireClient(call.Caller, reason, { CallId = call.Id })
	end
	if call.Owner and call.Owner.Parent then
		endedEvent:FireClient(call.Owner, call.Id, reason)
	end
end

local function rejectBusy(player: Player, entrance: Entrance)
	Sfx.Play(entrance.Panel, entrance.Brand.Sounds.Busy)
	setDisplay(entrance, entrance.Brand.Text.Busy, 2)
	stateEvent:FireClient(player, "busy", {})
end

local function onDial(player: Player, entranceId: any, apt: any)
	if not dialLimiter.Check(player) then
		return
	end
	if typeof(entranceId) ~= "string" or not Validation.IsInteger(apt, 0, 9999) then
		return
	end
	local entrance = EntranceRegistry.Get(entranceId)
	if not entrance or not Validation.IsNear(player, entrance.Panel, Config.InteractDistance) then
		return
	end
	local brand = entrance.Brand

	local previous = byCaller[player]
	if previous then
		endCall(previous, "hangup")
	end
	if byEntrance[entranceId] then
		rejectBusy(player, entrance)
		return
	end
	if apt < entrance.AptFrom or apt > entrance.AptTo then
		Sfx.Play(entrance.Panel, brand.Sounds.Deny)
		setDisplay(entrance, brand.Text.Invalid, 2)
		stateEvent:FireClient(player, "invalid", { AptFrom = entrance.AptFrom, AptTo = entrance.AptTo })
		return
	end

	-- Calling your own flat is allowed on purpose: it makes solo testing possible.
	local owner = ApartmentService.GetOnlineOwner(entranceId, apt)
	if owner and byOwner[owner] then
		rejectBusy(player, entrance)
		return
	end

	local call: Call = {
		Id = HttpService:GenerateGUID(false),
		Entrance = entrance,
		Apt = apt,
		Caller = player,
		Owner = owner,
		State = "Ringing",
		RingSound = Sfx.Play(entrance.Panel, brand.Sounds.Ring, 0.7, true),
	}
	calls[call.Id] = call
	byEntrance[entranceId] = call
	byCaller[player] = call
	if owner then
		byOwner[owner] = call
		incomingEvent:FireClient(owner, call.Id, entranceId, apt, player.DisplayName)
	end

	setDisplay(entrance, brand.RingingText(tostring(apt)))
	stateEvent:FireClient(player, "ringing", { CallId = call.Id, Apt = apt })

	local timeout = if owner then Config.Intercom.RingTimeout else Config.Intercom.UnownedRingTime
	task.delay(timeout, function()
		if calls[call.Id] == call and call.State == "Ringing" then
			endCall(call, "noanswer")
		end
	end)
end

local function onCallAction(player: Player, callId: any, action: any)
	if not actionLimiter.Check(player) or typeof(callId) ~= "string" or typeof(action) ~= "string" then
		return
	end
	local call = calls[callId]
	if not call or call.Owner ~= player then
		return
	end
	local entrance = call.Entrance

	if action == "answer" and call.State == "Ringing" then
		call.State = "Connected"
		if call.RingSound then
			call.RingSound:Destroy()
			call.RingSound = nil
		end
		Sfx.Play(entrance.Panel, entrance.Brand.Sounds.Connected)
		setDisplay(entrance, entrance.Brand.Text.Connected)
		stateEvent:FireClient(call.Caller, "connected", { CallId = call.Id })
		task.delay(Config.Intercom.MaxCallDuration, function()
			if calls[call.Id] == call then
				endCall(call, "timeout")
			end
		end)
	elseif action == "open" then
		Sfx.Play(entrance.Panel, entrance.Brand.Sounds.Open)
		Sfx.Flash(entrance.Reader, GREEN, 1.5)
		DoorService.Unlock(entrance.Id, "intercom")
		endCall(call, "opened")
	elseif action == "decline" or action == "hangup" then
		endCall(call, if call.State == "Ringing" then "declined" else "hangup")
	end
end

local function onHangup(player: Player)
	local call = byCaller[player]
	if call then
		endCall(call, "hangup")
	end
end

local function onChat(player: Player, callId: any, rawText: any)
	if not chatLimiter.Check(player) or typeof(callId) ~= "string" then
		return
	end
	local text = Validation.CleanText(rawText, Config.Intercom.MaxChatLength)
	local call = calls[callId]
	if not text or not call or call.State ~= "Connected" then
		return
	end
	if player ~= call.Caller and player ~= call.Owner then
		return
	end

	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PrivateChat)
	end)
	if not ok then
		return
	end

	local recipients = { call.Caller }
	if call.Owner and call.Owner ~= call.Caller then
		table.insert(recipients, call.Owner)
	end
	for _, recipient in recipients do
		if recipient.Parent then
			local ok2, filtered = pcall(function()
				return result:GetChatForUserAsync(recipient.UserId)
			end)
			if ok2 and calls[callId] == call then
				chatEvent:FireClient(recipient, callId, player.DisplayName, filtered)
			end
		end
	end
end

local function onUseKey(player: Player, entranceId: any, keyId: any)
	if not keyLimiter.Check(player) or typeof(entranceId) ~= "string" or typeof(keyId) ~= "string" then
		return
	end
	local entrance = EntranceRegistry.Get(entranceId)
	if not entrance or not Validation.IsNear(player, entrance.Reader, Config.InteractDistance) then
		return
	end
	local brand = entrance.Brand
	local ok, reason = KeyService.CanOpen(player, keyId, entranceId, brand.AcceptedKeyTypes)
	if ok then
		Sfx.Play(entrance.Reader, brand.Sounds.Open)
		Sfx.Flash(entrance.Reader, GREEN, 1.5)
		if not byEntrance[entranceId] then
			setDisplay(entrance, brand.Text.Open, 2)
		end
		DoorService.Unlock(entranceId, "key")
		stateEvent:FireClient(player, "key_ok", {})
	else
		Sfx.Play(entrance.Reader, brand.Sounds.Deny)
		Sfx.Flash(entrance.Reader, RED, 1)
		if not byEntrance[entranceId] then
			setDisplay(entrance, brand.Text.Deny, 2)
		end
		stateEvent:FireClient(player, "key_denied", { Reason = reason })
	end
end

function IntercomService.Init()
	stateEvent = Net.Event("IntercomState")
	incomingEvent = Net.Event("IncomingCall")
	endedEvent = Net.Event("CallEnded")
	chatEvent = Net.Event("CallChat")

	Net.Event("IntercomDial").OnServerEvent:Connect(onDial)
	Net.Event("IntercomHangup").OnServerEvent:Connect(onHangup)
	Net.Event("CallAction").OnServerEvent:Connect(onCallAction)
	Net.Event("UseKey").OnServerEvent:Connect(onUseKey)
	chatEvent.OnServerEvent:Connect(onChat)

	Players.PlayerRemoving:Connect(function(player)
		local asCaller = byCaller[player]
		if asCaller then
			endCall(asCaller, "left")
		end
		local asOwner = byOwner[player]
		if asOwner then
			endCall(asOwner, "left")
		end
	end)

	-- Caller walked away from the panel -> hang up. Cheap: runs every 2 s and
	-- only over active calls.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, call in calls do
				if not Validation.IsNear(call.Caller, call.Entrance.Panel, Config.Intercom.CallerMaxDistance) then
					endCall(call, "hangup")
				end
			end
		end
	end)
end

return IntercomService
