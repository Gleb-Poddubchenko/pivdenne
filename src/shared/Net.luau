--!strict
-- Net: single place that defines every remote. The server creates them,
-- clients wait for them. Never add a remote anywhere else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"DataSync", -- S->C (snapshot)
	"Notify", -- S->C (text, kind)
	"IntercomDial", -- C->S (entranceId, apt)
	"IntercomHangup", -- C->S ()
	"IntercomState", -- S->C (status, info)  caller-side / key reader feedback
	"IncomingCall", -- S->C (callId, entranceId, apt, callerName)  to flat owner
	"CallAction", -- C->S (callId, "answer" | "open" | "decline" | "hangup")
	"CallEnded", -- S->C (callId, reason)  to flat owner
	"CallChat", -- C->S (callId, text) / S->C (callId, fromName, filteredText)
	"UseKey", -- C->S (entranceId, keyId)
	"ElevatorPanel", -- C->S (elevatorId, "floor" | "stop" | "alarm", floor?)
	"Fade", -- S->C (seconds)  black screen during teleports
	"DoorbellRing", -- S->C (ringId, label, visitorName)  to the flat owner
	"DoorbellAnswer", -- C->S (ringId, accept)
	"UseItem", -- C->S (itemId)
	"VehicleAction", -- C->S ("honk" | "lights" | "lock" | "flip" | "despawn")
	"FishingState", -- S->C ("cast" | "bite" | "caught" | "escaped" | "reeled", info)
}

local FUNCTIONS = {
	"GetSnapshot", -- () -> Snapshot?
	"CopyKey", -- (keyId) -> (ok, message)
	"ClaimApartment", -- (entranceId, apt) -> (ok, message)
	"BuyItem", -- (shopId, itemId, qty) -> (ok, message)
	"StorageMove", -- (aptKey, itemId, qty, "in" | "out") -> (ok, message)
	"BuyCar", -- (modelId, colorIndex) -> (ok, message)
	"SpawnCar", -- (carId) -> (ok, message)
	"BuyEquipment", -- (equipmentId) -> (ok, message)
	"SetLoadout", -- ({ equipmentId }) -> (ok, message)
	"GetStreets", -- () -> { string }
	"FindAddress", -- (street, number) -> (ok, Vector3 | message, label?)
	"DebugInfo", -- () -> { string }?  (Studio / place owner / Config.Debug.Admins only)
}

local Net = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		local f: Folder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
		f.Name = "Remotes"
		for _, name in EVENTS do
			if not f:FindFirstChild(name) then
				local r = Instance.new("RemoteEvent")
				r.Name = name
				r.Parent = f
			end
		end
		for _, name in FUNCTIONS do
			if not f:FindFirstChild(name) then
				local r = Instance.new("RemoteFunction")
				r.Name = name
				r.Parent = f
			end
		end
		f.Parent = ReplicatedStorage
		folder = f
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: Folder
end

function Net.Init()
	getFolder()
end

function Net.Event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Unknown RemoteEvent " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "Unknown RemoteFunction " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
