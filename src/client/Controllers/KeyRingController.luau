--!strict
-- KeyRingController: the key ring (в'язка ключів). The player picks the key they
-- are "holding"; the reader prompt sends that key to the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)

local KeyRingController = {}

local activeKeyId: string? = nil
local panel: Frame
local list: ScrollingFrame
local toggleButton: TextButton

local TYPE_COLORS: { [string]: Color3 } = {
	TM = Color3.fromRGB(150, 160, 175), -- steel tablet
	RFID = Color3.fromRGB(40, 110, 200), -- blue plastic fob
}

local function shortLabel(): string
	local snap = DataController.Get()
	if snap and activeKeyId then
		for _, key in snap.Keys do
			if key.Id == activeKeyId then
				return "🔑 " .. key.Label
			end
		end
	end
	return "🔑 Ключі"
end

local function rebuild()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local snap = DataController.Get()
	local keys: { Types.KeyData } = if snap then snap.Keys else {}

	-- Drop the active key if it no longer exists.
	if activeKeyId then
		local found = false
		for _, key in keys do
			found = found or key.Id == activeKeyId
		end
		if not found then
			activeKeyId = nil
		end
	end

	if #keys == 0 then
		UiKit.label("Ключів немає. Купіть квартиру в ЖЕКу або зробіть копію в кіоску.", {
			Size = UDim2.new(1, 0, 0, 60),
			TextColor3 = UiKit.Colors.Muted,
			Parent = list,
		})
	end

	for i, key in keys do
		local row = UiKit.make("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = UiKit.Colors.Panel,
			Parent = list,
		}, { UiKit.corner(8) })
		UiKit.make("Frame", {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(0, 10, 0.5, -14),
			BackgroundColor3 = TYPE_COLORS[key.Type] or UiKit.Colors.Muted,
			Parent = row,
		}, { UiKit.corner(if key.Type == "TM" then 14 else 6) })
		UiKit.label(key.Label, {
			Size = UDim2.new(1, -150, 0, 22),
			Position = UDim2.fromOffset(46, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		UiKit.label(("%s · дверей: %d"):format(Config.Keys.TypeNames[key.Type] or key.Type, #key.Entrances), {
			Size = UDim2.new(1, -150, 0, 18),
			Position = UDim2.fromOffset(46, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			TextColor3 = UiKit.Colors.Muted,
			Parent = row,
		})
		local isActive = key.Id == activeKeyId
		local pick = UiKit.button(if isActive then "В руці" else "Взяти", {
			Size = UDim2.fromOffset(90, 40),
			Position = UDim2.new(1, -100, 0.5, -20),
			BackgroundColor3 = if isActive then UiKit.Colors.Good else UiKit.Colors.Blue,
			Parent = row,
		})
		pick.Activated:Connect(function()
			KeyRingController.SetActive(key.Id)
		end)
	end
	toggleButton.Text = shortLabel()
end

function KeyRingController.GetActiveKeyId(): string?
	return activeKeyId
end

function KeyRingController.SetActive(keyId: string?)
	activeKeyId = keyId
	rebuild()
end

function KeyRingController.Open()
	panel.Visible = true
end

function KeyRingController.Toggle()
	panel.Visible = not panel.Visible
end

function KeyRingController.Init()
	local gui = UiKit.screen("KeyRing", 2)

	toggleButton = UiKit.button("🔑 Ключі", {
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(0, 8, 0.5, -22),
		BackgroundColor3 = UiKit.Colors.Bg,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = gui,
	})
	toggleButton.Activated:Connect(KeyRingController.Toggle)

	panel = UiKit.make("Frame", {
		Visible = false,
		Size = UDim2.new(0.9, 0, 0.6, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	}, {
		UiKit.corner(12),
		UiKit.padding(12),
		UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(420, 520) }),
	})
	UiKit.label("В'язка ключів  (K)", {
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -50, 0, 30),
		Parent = panel,
	})
	local close = UiKit.button("✕", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -40, 0, -6), Parent = panel })
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	list = UiKit.make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	}, { UiKit.list(6) })

	DataController.Changed:Connect(rebuild)
	rebuild()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then
			KeyRingController.Toggle()
		end
	end)
end

return KeyRingController
