--!strict
-- EquipmentController: the sports shop window, choosing what to carry
-- (loadout, key J), and fishing feedback.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Equipment = require(Shared:WaitForChild("Equipment"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)
local HudController = require(script.Parent.HudController)

local EquipmentController = {}

local loadoutGui: ScreenGui? = nil

local FISHING_TEXT: { [string]: { string } } = {
	cast = { "Закинули. Чекаємо…", "" },
	bite = { "🎣 КЛЮЄ! Тисніть ще раз!", "good" },
	escaped = { "Зірвалася…", "bad" },
	reeled = { "Змотали вудку.", "" },
	nowater = { "Тут немає води. Підійдіть до берега.", "bad" },
	full = { "Інвентар повний — риба втекла.", "bad" },
}

local function openShop()
	local gui, body = UiKit.window("EquipmentShop", "Спорттовари")
	local function rebuild()
		UiKit.clear(body)
		local snap = DataController.Get()
		local owned = if snap then snap.Equipment else {}
		for i, id in Equipment.Order do
			local def = Equipment.Defs[id]
			local text = ("%s — %s%d\n%s"):format(def.Name, Config.Currency, def.Price, def.Description)
			local button = UiKit.row(body, i, text, if owned[id] then "Є" else "Купити", function()
				if owned[id] then
					return
				end
				local ok, msg = Net.Function("BuyEquipment"):InvokeServer(id)
				HudController.Toast(msg, if ok then "good" else "bad")
			end, if owned[id] then UiKit.Colors.Panel else UiKit.Colors.Good)
			local row = button.Parent :: Frame
			row.Size = UDim2.new(1, 0, 0, 64)
		end
	end
	rebuild()
	local conn = DataController.Changed:Connect(rebuild)
	gui.Destroying:Once(function()
		conn:Disconnect()
	end)
end

local function openLoadout()
	if loadoutGui then
		loadoutGui:Destroy()
		loadoutGui = nil
		return
	end
	local gui, body = UiKit.window("Loadout", ("Спорядження (до %d)  (J)"):format(Config.Equipment.LoadoutSlots))
	loadoutGui = gui
	local function rebuild()
		UiKit.clear(body)
		local snap = DataController.Get()
		if not snap then
			return
		end
		local any = false
		for i, id in Equipment.Order do
			if snap.Equipment[id] then
				any = true
				local def = Equipment.Defs[id]
				local carried = table.find(snap.Loadout, id) ~= nil
				UiKit.row(body, i, def.Name, if carried then "✓ Беру" else "Не беру", function()
					local list = table.clone(snap.Loadout)
					local at = table.find(list, id)
					if at then
						table.remove(list, at)
					elseif #list < Config.Equipment.LoadoutSlots then
						table.insert(list, id)
					else
						HudController.Toast("Усі слоти зайняті", "bad")
						return
					end
					local ok, msg = Net.Function("SetLoadout"):InvokeServer(list)
					if not ok then
						HudController.Toast(msg, "bad")
					end
				end, if carried then UiKit.Colors.Good else UiKit.Colors.Panel)
			end
		end
		if not any then
			UiKit.label("Немає спорядження. Зайдіть у «Спорттовари».", { TextColor3 = UiKit.Colors.Muted, Parent = body })
		end
	end
	rebuild()
	local conn = DataController.Changed:Connect(rebuild)
	gui.Destroying:Once(function()
		conn:Disconnect()
		if loadoutGui == gui then
			loadoutGui = nil
		end
	end)
end

function EquipmentController.Init()
	local gui = UiKit.screen("LoadoutButton", 2)
	local button = UiKit.button("🧰 Спорядження", {
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(0, 8, 0.5, 128),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	})
	button.Activated:Connect(openLoadout)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.J then
			openLoadout()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Action") == "EquipmentShop" then
			openShop()
		end
	end)

	Net.Event("FishingState").OnClientEvent:Connect(function(state: string, info: { [string]: any })
		if state == "caught" then
			HudController.Toast(("Спіймали: %s! 🐟"):format(tostring(info.Name)), "good")
			return
		end
		local entry = FISHING_TEXT[state]
		if entry then
			HudController.Toast(entry[1], if entry[2] ~= "" then entry[2] else nil)
		end
	end)
end

return EquipmentController
