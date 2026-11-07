--!strict
-- InventoryController: the bag (B) and the fridge window.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Items = require(Shared:WaitForChild("Items"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)
local HudController = require(script.Parent.HudController)

local InventoryController = {}

local bagGui: ScreenGui? = nil

local function sortedIds(bag: { [string]: number }): { string }
	local ids = {}
	for id in bag do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ia, ib = Items[a], Items[b]
		return (if ia then ia.Name else a) < (if ib then ib.Name else b)
	end)
	return ids
end

local function itemName(id: string): string
	local item = Items[id]
	return if item then item.Name else id
end

local function openBag()
	if bagGui then
		bagGui:Destroy()
		bagGui = nil
		return
	end
	local gui, body = UiKit.window("Bag", "Мої речі  (B)")
	bagGui = gui
	local function rebuild()
		UiKit.clear(body)
		local snap = DataController.Get()
		local bag = if snap then snap.Inventory else {}
		local ids = sortedIds(bag)
		if #ids == 0 then
			UiKit.label("Порожньо. Купіть щось у магазині.", { TextColor3 = UiKit.Colors.Muted, Parent = body })
		end
		for i, id in ids do
			local item = Items[id]
			local text = ("%s  ×%d"):format(itemName(id), bag[id])
			if item and item.Use then
				UiKit.row(body, i, text, "Використати", function()
					Net.Event("UseItem"):FireServer(id)
				end, UiKit.Colors.Good)
			else
				UiKit.label(text, { LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 30), Parent = body })
			end
		end
	end
	rebuild()
	local conn = DataController.Changed:Connect(rebuild)
	gui.Destroying:Once(function()
		conn:Disconnect()
		if bagGui == gui then
			bagGui = nil
		end
	end)
end

local function openFridge(aptKey: string)
	local gui, body = UiKit.window("Fridge", "Холодильник")
	local remote = Net.Function("StorageMove")
	local function move(id: string, direction: string)
		local ok, msg = remote:InvokeServer(aptKey, id, 1, direction)
		if not ok then
			HudController.Toast(msg, "bad")
		end
	end
	local function rebuild()
		UiKit.clear(body)
		local snap = DataController.Get()
		if not snap or not table.find(snap.Apartments, aptKey) then
			UiKit.label("Це не ваш холодильник.", { TextColor3 = UiKit.Colors.Muted, Parent = body })
			return
		end
		local order = 0
		local function header(text: string)
			order += 1
			UiKit.label(text, { LayoutOrder = order, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
		end
		header("У холодильнику")
		local fridge = snap.Storage[aptKey] or {}
		for _, id in sortedIds(fridge) do
			order += 1
			UiKit.row(body, order, ("%s  ×%d"):format(itemName(id), fridge[id]), "← Взяти", function()
				move(id, "out")
			end)
		end
		header("У мене")
		for _, id in sortedIds(snap.Inventory) do
			order += 1
			UiKit.row(body, order, ("%s  ×%d"):format(itemName(id), snap.Inventory[id]), "Покласти →", function()
				move(id, "in")
			end, UiKit.Colors.Panel)
		end
	end
	rebuild()
	local conn = DataController.Changed:Connect(rebuild)
	gui.Destroying:Once(function()
		conn:Disconnect()
	end)
end

function InventoryController.Init()
	local gui = UiKit.screen("BagButton", 2)
	local button = UiKit.button("🎒 Речі", {
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(0, 8, 0.5, 28),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	})
	button.Activated:Connect(openBag)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.B then
			openBag()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Action") == "Fridge" then
			local aptKey = prompt:GetAttribute("AptKey")
			if typeof(aptKey) == "string" then
				openFridge(aptKey)
			end
		end
	end)
end

return InventoryController
