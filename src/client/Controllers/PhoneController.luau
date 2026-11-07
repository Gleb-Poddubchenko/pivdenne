--!strict
-- PhoneController: the phone screen, shown while the phone tool is in hand —
-- clock, money, and search for a real address (OSM data) with a map marker.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)
local HudController = require(script.Parent.HudController)

local player = Players.LocalPlayer

local PhoneController = {}

local phoneGui: ScreenGui? = nil
local streets: { string }? = nil
local marker: Part? = nil

local function clearMarker()
	if marker then
		marker:Destroy()
		marker = nil
	end
end

local function setMarker(position: Vector3, label: string)
	clearMarker()
	local p = Instance.new("Part")
	p.Name = "AddressMarker"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = position
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 44)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.Parent = p
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 0.25
	text.BackgroundColor3 = UiKit.Colors.Blue
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = bb
	p.Parent = workspace
	marker = p
	-- distance readout (2 Hz, only while a marker exists)
	task.spawn(function()
		while marker == p do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local metres = (root.Position - position).Magnitude / Config.StudsPerMeter
				text.Text = ("📍 %s · %d м"):format(label, math.floor(metres))
				if metres < 8 then
					HudController.Toast("Ви на місці: " .. label, "good")
					clearMarker()
				end
			end
			task.wait(0.5)
		end
	end)
end

local function hidePhone()
	if phoneGui then
		phoneGui:Destroy()
		phoneGui = nil
	end
end

local function showPhone()
	hidePhone()
	local gui = UiKit.screen("Phone", 7)
	phoneGui = gui
	local frame = UiKit.make("Frame", {
		Size = UDim2.fromOffset(260, 420),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 15, 20),
		Parent = gui,
	}, { UiKit.corner(22), UiKit.padding(14), UiKit.make("UIScale", { Name = "Scale" }) })
	local scale = frame:FindFirstChild("Scale") :: UIScale
	scale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 520, 0.6, 1)

	local clock = UiKit.label("", { Size = UDim2.new(1, 0, 0, 40), Font = Enum.Font.GothamBlack, TextSize = 32, Parent = frame })
	local money = UiKit.label("", { Position = UDim2.fromOffset(0, 40), TextColor3 = UiKit.Colors.Accent, Parent = frame })
	task.spawn(function()
		while phoneGui == gui do
			local t = Lighting.ClockTime
			clock.Text = ("%02d:%02d"):format(math.floor(t), math.floor((t % 1) * 60))
			local snap = DataController.Get()
			money.Text = if snap then ("%s %d"):format(Config.Currency, snap.Money) else ""
			task.wait(1)
		end
	end)

	UiKit.label("Знайти адресу", { Position = UDim2.fromOffset(0, 72), Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local function box(placeholder: string, y: number, width: number?): TextBox
		return UiKit.make("TextBox", {
			Size = UDim2.new(width or 1, 0, 0, 36),
			Position = UDim2.fromOffset(0, y),
			PlaceholderText = placeholder,
			Text = "",
			ClearTextOnFocus = false,
			BackgroundColor3 = UiKit.Colors.Panel,
			TextColor3 = UiKit.Colors.Text,
			Font = Enum.Font.Gotham,
			TextSize = 15,
			Parent = frame,
		}, { UiKit.corner(8) })
	end
	local streetBox = box("Вулиця", 98)
	local numberBox = box("Будинок", 140, 0.45)
	local find = UiKit.button("Знайти", {
		Size = UDim2.new(0.5, 0, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 140),
		BackgroundColor3 = UiKit.Colors.Blue,
		Parent = frame,
	})
	local suggestions = UiKit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 180),
		Position = UDim2.fromOffset(0, 184),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { UiKit.list(4) })
	local clear = UiKit.button("Прибрати мітку", {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 1, -32),
		TextSize = 13,
		Parent = frame,
	})
	clear.Activated:Connect(clearMarker)

	if not streets then
		local ok, list = pcall(function()
			return Net.Function("GetStreets"):InvokeServer()
		end)
		streets = if ok and typeof(list) == "table" then list else {}
	end

	local function suggest()
		UiKit.clear(suggestions)
		local query = TextUtil.NormalizeStreet(streetBox.Text)
		local all = streets or {}
		if #all == 0 then
			UiKit.label("Немає даних карти (запустіть tools/fetch_osm.sh)", { TextSize = 12, TextColor3 = UiKit.Colors.Muted, Parent = suggestions })
			return
		end
		if query == "" then
			return
		end
		local shown = 0
		for _, name in all do
			if string.find(TextUtil.NormalizeStreet(name), query, 1, true) then
				shown += 1
				local b = UiKit.button(name, { Size = UDim2.new(1, 0, 0, 30), TextSize = 13, LayoutOrder = shown, Parent = suggestions })
				b.Activated:Connect(function()
					streetBox.Text = name
				end)
				if shown >= 5 then
					break
				end
			end
		end
	end
	streetBox:GetPropertyChangedSignal("Text"):Connect(suggest)
	suggest()

	find.Activated:Connect(function()
		local ok, result, label = Net.Function("FindAddress"):InvokeServer(streetBox.Text, numberBox.Text)
		if ok and typeof(result) == "Vector3" then
			setMarker(result, tostring(label))
			HudController.Toast("Мітку поставлено: " .. tostring(label), "good")
		else
			HudController.Toast(tostring(result), "bad")
		end
	end)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("EquipmentId") == "phone" then
			showPhone()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("EquipmentId") == "phone" then
			hidePhone()
		end
	end)
end

function PhoneController.Init()
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		hidePhone()
		watchCharacter(character)
	end)
end

return PhoneController
