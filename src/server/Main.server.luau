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
end

local order = {
	"CityService",
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
	"VehicleService",
	"EquipmentService",
	"FishingService",
	"AddressService",
}

for _, name in order do
	local module = require(Services:WaitForChild(name)) :: any
	module.Init()
end

print("[Yuzhne] Server ready")
