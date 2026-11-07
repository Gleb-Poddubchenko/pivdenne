--!strict
-- Server bootstrap. Init order matters: data -> world registry -> systems.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Services = script.Parent:WaitForChild("Services")

Net.Init() -- create all remotes before any client asks for them

-- With real OSM map data present the city replaces the dev test scene
-- (it would overlap the city centre). Set Dev.ForceTestScene to keep both.
local CityService = require(Services:WaitForChild("CityService"))
if Config.Dev.BuildTestScene and (Config.Dev.ForceTestScene or not CityService.HasMap()) then
	local Dev = script.Parent:WaitForChild("Dev")
	require(Dev:WaitForChild("TestSceneBuilder")).Build()
	require(Dev:WaitForChild("TestElevatorBuilder")).Build()
	require(Dev:WaitForChild("TestApartmentBuilder")).Build()
	require(Dev:WaitForChild("TestShopBuilder")).Build()
	require(Dev:WaitForChild("TestParkingBuilder")).Build()
	require(Dev:WaitForChild("TestEquipmentBuilder")).Build()
	require(Dev:WaitForChild("TestStairwellBuilder")).Build()
	require(Dev:WaitForChild("TestStreetBuilder")).Build()
end

local order = {
	"CityService",
	"LightingService",
	"PlayerDataService",
	"EntranceRegistry",
	"DoorService",
	"KeyService",
	"ApartmentService",
	"IntercomService",
	"KioskService",
	"ElevatorService",
	"InventoryService",
	"ShopService",
	"InteriorService",
	"ApartmentDoorService",
	"StairwellService",
	"VehicleService",
	"EquipmentService",
	"FishingService",
	"AddressService",
}

-- One failing service must not take the rest down with it (it did: a city-build
-- timeout in CityService stopped VehicleService and everything after it).
local failed = {}
for _, name in order do
	local ok, err = xpcall(function()
		local module = require(Services:WaitForChild(name)) :: any
		module.Init()
	end, debug.traceback)
	if not ok then
		table.insert(failed, name)
		warn(("[Yuzhne] %s failed to start:\n%s"):format(name, tostring(err)))
	end
end

if #failed == 0 then
	print("[Yuzhne] Server ready")
else
	warn("[Yuzhne] Server started WITH ERRORS in: " .. table.concat(failed, ", "))
end
