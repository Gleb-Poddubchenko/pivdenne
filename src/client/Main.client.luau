--!strict
-- Client bootstrap. LoadingController first so the loading cover is up before
-- anything else; each controller starts on its own so one error can't stop the rest.

local Controllers = script.Parent:WaitForChild("Controllers")

local order = {
	"LoadingController",
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
	"NightLightsController",
	"DebugController",
}

for _, name in order do
	local ok, err = xpcall(function()
		local module = require(Controllers:WaitForChild(name)) :: any
		module.Init()
	end, debug.traceback)
	if not ok then
		warn(("[Yuzhne] client %s failed to start:\n%s"):format(name, tostring(err)))
	end
end
