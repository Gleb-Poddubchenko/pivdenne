--!strict
-- TestApartmentBuilder (DEV ONLY): puts four ground-floor flat doors on the back
-- wall of each test lobby (test-a/1: flats 1–4, test-a/2: flats 37–40).
-- Also the reference layout for the ApartmentDoor model contract.

local FlatDoorBuilder = require(script.Parent.Parent.Building.FlatDoorBuilder)

local TestApartmentBuilder = {}

function TestApartmentBuilder.Build()
	local scene = workspace:FindFirstChild("TestScene")
	local block = scene and scene:FindFirstChild("Block_test-a")
	if not block or block:FindFirstChild("FlatDoors") then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "FlatDoors"

	for _, spec in { { id = "test-a/1", first = 1 }, { id = "test-a/2", first = 37 } } do
		local entrance = block:FindFirstChild("Entrance_" .. spec.id)
		local back = entrance and entrance:FindFirstChild("LobbyBack")
		if back and back:IsA("BasePart") then
			-- Front face of LobbyBack faces the lobby; floor top is 0.1 above ground.
			local surface = back.CFrame * CFrame.new(0, -back.Size.Y / 2 + 0.1, -back.Size.Z / 2)
			for i, x in { -13, -4.5, 4.5, 13 } do
				FlatDoorBuilder.Build(holder, surface * CFrame.new(x, 0, 0), spec.id, spec.first + i - 1)
			end
		end
	end
	holder.Parent = block
end

return TestApartmentBuilder
