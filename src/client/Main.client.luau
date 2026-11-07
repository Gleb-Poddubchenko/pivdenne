--!strict
-- Client bootstrap.

local Controllers = script.Parent:WaitForChild("Controllers")

local order = {
	"DataController",
	"HudController",
	"KeyRingController",
	"IntercomController",
	"CallController",
	"KioskController",
	"ElevatorController",
	"InventoryController",
	"ShopController",
	"ApartmentController",
	"VehicleController",
	"GarageController",
	"EquipmentController",
	"PhoneController",
}

for _, name in order do
	local module = require(Controllers:WaitForChild(name)) :: any
	module.Init()
end
