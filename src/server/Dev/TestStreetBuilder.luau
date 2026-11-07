--!strict
-- TestStreetBuilder (DEV ONLY): a few street details around the test scene so the
-- realism pieces can be seen without OSM data: lamps and a zebra crossing on the
-- test road, a bus shelter, trees in front of the test block, entrance benches.

local StreetDetails = require(script.Parent.Parent.City.StreetDetails)

local TestStreetBuilder = {}

function TestStreetBuilder.Build()
	if workspace:FindFirstChild("TestStreet") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TestStreet"

	local roadX = 155 -- the long test road next to the parking lot
	local side = 1
	for z = -400, 400, 122 do
		local x = roadX + side * 14
		StreetDetails.Lamp(folder, x, z, if side > 0 then math.pi else 0) -- arm reaches over the road
		side = -side
	end
	StreetDetails.Crossing(folder, roadX, 60, math.pi / 2, 24)
	StreetDetails.BusStop(folder, roadX + 20, -40, math.pi, "Тестова зупинка")

	for x = -60, 60, 15 do
		StreetDetails.Tree(folder, x, 45, 0.9 + (x % 3) * 0.1)
	end
	for _, x in { -28, 14 } do
		StreetDetails.Bench(folder, x, 54, -math.pi / 2)
	end
	StreetDetails.Bins(folder, -95, 40)

	folder.Parent = workspace
end

return TestStreetBuilder
