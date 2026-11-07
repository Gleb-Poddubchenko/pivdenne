--!strict
-- TestStairwellBuilder (DEV ONLY): one city-style entrance on the east end wall of
-- the test block ("test-a/3", flats 73–108, 9 floors, lift), so the instanced
-- stairwell can be tested without OSM data. Uses the same builder as the city.

local EntranceBuilder = require(script.Parent.Parent.Building.EntranceBuilder)

local TestStairwellBuilder = {}

function TestStairwellBuilder.Build()
	local scene = workspace:FindFirstChild("TestScene")
	local block = scene and scene:FindFirstChild("Block_test-a")
	if not block or block:FindFirstChild("Entrance_test-a/3") then
		return
	end
	EntranceBuilder.Build(block, {
		Id = "test-a/3",
		X = 42, -- east end wall of the test block
		Z = 92,
		NX = 1,
		NZ = 0,
		Ref = "3",
		FlatsText = "73–108",
		AptFrom = 73,
		AptTo = 108,
		FlatsSource = "osm",
		Floors = 9,
		PerFloor = 4,
		HasLift = true,
		HasChute = true,
		Brand = "Metron",
	})
end

return TestStairwellBuilder
