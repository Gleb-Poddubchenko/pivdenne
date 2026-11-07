--!strict
-- DataController: holds the latest snapshot of the local player's data.
-- Read-only mirror; the server is the only source of truth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local DataController = {}

local changedEvent = Instance.new("BindableEvent")
DataController.Changed = changedEvent.Event -- (snapshot)

local current: Types.Snapshot? = nil

local function set(snapshot: Types.Snapshot)
	current = snapshot
	changedEvent:Fire(snapshot)
end

function DataController.Get(): Types.Snapshot?
	return current
end

function DataController.Init()
	Net.Event("DataSync").OnClientEvent:Connect(set)

	-- DataSync may have fired before this script ran: ask once the profile exists.
	task.spawn(function()
		for _ = 1, 60 do
			if current then
				return
			end
			local ok, snapshot = pcall(function()
				return Net.Function("GetSnapshot"):InvokeServer()
			end)
			if ok and snapshot then
				if not current then
					set(snapshot)
				end
				return
			end
			task.wait(1)
		end
	end)
end

return DataController
