--!strict
-- Teleport: fade the screen, stream the destination in, then move the character.
-- Yields ~0.3 s; call from a spawned thread.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Teleport = {}

function Teleport.To(player: Player, cf: CFrame)
	Net.Event("Fade"):FireClient(player, 0.8)
	task.wait(0.25)
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 3)
	end)
	local character = player.Character
	if character and player.Parent then
		character:PivotTo(cf)
	end
end

return Teleport
