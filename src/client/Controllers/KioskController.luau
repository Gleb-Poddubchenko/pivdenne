--!strict
-- KioskController: key-copy kiosk and housing office (ЖЕК) windows.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local HudController = require(script.Parent.HudController)
local DataController = require(script.Parent.DataController)

local KioskController = {}

local function window(title: string): (ScreenGui, Frame)
	local gui = UiKit.screen("Kiosk", 6)
	local frame = UiKit.make("Frame", {
		Size = UDim2.new(0.9, 0, 0.7, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	}, {
		UiKit.corner(12),
		UiKit.padding(12),
		UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(420, 520) }),
	})
	UiKit.label(title, {
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -50, 0, 30),
		Parent = frame,
	})
	local close = UiKit.button("✕", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -40, 0, -6), Parent = frame })
	close.Activated:Connect(function()
		gui:Destroy()
	end)
	local body = UiKit.make("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, { UiKit.list(6) })
	return gui, body
end

local function openKeyKiosk()
	local gui, body = window("Виготовлення ключів")
	local function rebuild()
		for _, c in body:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		UiKit.label(("Копія будь-якого ключа: %s%d"):format(Config.Currency, Config.Keys.CopyPrice), {
			TextColor3 = UiKit.Colors.Muted,
			Parent = body,
		})
		local snap = DataController.Get()
		if not snap or #snap.Keys == 0 then
			UiKit.label("У вас немає ключів для копіювання.", { Parent = body })
			return
		end
		for i, key in snap.Keys do
			local b = UiKit.button(("Копіювати: %s"):format(key.Label), {
				LayoutOrder = i,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = body,
			})
			b.Activated:Connect(function()
				local ok, msg = Net.Function("CopyKey"):InvokeServer(key.Id)
				HudController.Toast(msg, if ok then "good" else "bad")
			end)
		end
	end
	rebuild()
	local conn = DataController.Changed:Connect(rebuild)
	gui.Destroying:Once(function()
		conn:Disconnect()
	end)
end

local function openHousingOffice()
	local _, body = window("ЖЕК · Купівля квартири")
	UiKit.label(("Ціна: %s%d. Ключ від під'їзду видається одразу."):format(Config.Currency, Config.Apartments.Price), {
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = UiKit.Colors.Muted,
		LayoutOrder = 1,
		Parent = body,
	})

	local function textBox(placeholder: string, order: number): TextBox
		return UiKit.make("TextBox", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 40),
			PlaceholderText = placeholder,
			Text = "",
			ClearTextOnFocus = false,
			BackgroundColor3 = UiKit.Colors.Panel,
			TextColor3 = UiKit.Colors.Text,
			Font = Enum.Font.Gotham,
			TextSize = 16,
			Parent = body,
		}, { UiKit.corner(8) })
	end
	local entranceBox = textBox("Під'їзд (напр. test-a/1)", 2)
	local aptBox = textBox("Номер квартири", 3)

	local buy = UiKit.button("Купити", { LayoutOrder = 4, BackgroundColor3 = UiKit.Colors.Good, Parent = body })
	buy.Activated:Connect(function()
		local apt = tonumber(aptBox.Text)
		if not apt then
			HudController.Toast("Введіть номер квартири", "bad")
			return
		end
		local ok, msg = Net.Function("ClaimApartment"):InvokeServer(entranceBox.Text, apt)
		HudController.Toast(msg, if ok then "good" else "bad")
	end)

	-- Quick-pick buttons for entrances currently streamed in.
	UiKit.label("Під'їзди поруч:", { LayoutOrder = 5, TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	-- The city has hundreds of entrances: list the 12 nearest streamed-in ones.
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else Vector3.zero
	local nearby = {}
	for _, inst in CollectionService:GetTagged("Entrance") do
		if inst:IsA("Model") then
			table.insert(nearby, { inst = inst, d = (inst:GetPivot().Position - origin).Magnitude })
		end
	end
	table.sort(nearby, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#nearby, 12) do
		local inst = nearby[i].inst
		local id = inst:GetAttribute("EntranceId")
		if typeof(id) == "string" then
			local b = UiKit.button(("%s · кв. %s–%s"):format(id, tostring(inst:GetAttribute("AptFrom")), tostring(inst:GetAttribute("AptTo"))), {
				LayoutOrder = 5 + i,
				Parent = body,
			})
			b.Activated:Connect(function()
				entranceBox.Text = id
			end)
		end
	end
end

function KioskController.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local action = prompt:GetAttribute("Action")
		if action == "KeyKiosk" then
			openKeyKiosk()
		elseif action == "HousingOffice" then
			openHousingOffice()
		end
	end)
end

return KioskController
