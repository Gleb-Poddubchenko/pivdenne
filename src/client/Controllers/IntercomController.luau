--!strict
-- IntercomController: caller-side keypad UI and the key reader.
-- Opens when the player triggers an intercom panel prompt; styled per brand.
-- Only sends requests; the server decides what actually happens.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Brands = require(Shared:WaitForChild("IntercomBrands"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local HudController = require(script.Parent.HudController)
local KeyRingController = require(script.Parent.KeyRingController)

local player = Players.LocalPlayer

local IntercomController = {}

type Session = {
	EntranceId: string,
	Brand: Brands.Brand,
	Panel: BasePart,
	Gui: ScreenGui,
	Display: TextLabel,
	ChatFrame: Frame,
	ChatLog: ScrollingFrame,
}

local session: Session? = nil
local digits = ""
local callId: string? = nil
local inputToken = 0 -- invalidates pending auto-dial / display resets
local chatOrder = 0

local dialEvent: RemoteEvent
local hangupEvent: RemoteEvent
local chatEvent: RemoteEvent

local function setDisplay(text: string)
	if session then
		session.Display.Text = text
	end
end

local function resetLater(delaySeconds: number)
	inputToken += 1
	local token = inputToken
	task.delay(delaySeconds, function()
		if token == inputToken and session and not callId then
			digits = ""
			setDisplay(session.Brand.Text.Idle)
		end
	end)
end

local function setChatVisible(visible: boolean)
	if session then
		session.ChatFrame.Visible = visible
		if not visible then
			for _, c in session.ChatLog:GetChildren() do
				if c:IsA("TextLabel") then
					c:Destroy()
				end
			end
		end
	end
end

local function dial()
	if not session or callId or digits == "" then
		return
	end
	local apt = tonumber(digits)
	if apt then
		dialEvent:FireServer(session.EntranceId, apt)
	end
end

local function pressDigit(d: string)
	if not session or callId or #digits >= Config.Intercom.MaxDigits then
		return
	end
	local brand = session.Brand
	UiKit.playLocal(brand.Sounds.Click)
	digits ..= d
	setDisplay(brand.FormatNumber(digits))
	inputToken += 1
	local delaySeconds = brand.AutoDialDelay
	if delaySeconds then
		local token = inputToken
		task.delay(delaySeconds, function()
			if token == inputToken then
				dial()
			end
		end)
	end
end

local function clear()
	if not session then
		return
	end
	UiKit.playLocal(session.Brand.Sounds.Click)
	if callId then
		hangupEvent:FireServer()
		callId = nil
		setChatVisible(false)
	end
	inputToken += 1
	digits = ""
	setDisplay(session.Brand.Text.Idle)
end

function IntercomController.Close()
	if not session then
		return
	end
	if callId then
		hangupEvent:FireServer()
	end
	session.Gui:Destroy()
	session = nil
	callId = nil
	digits = ""
	inputToken += 1
end

local function appendChat(from: string, text: string)
	if not session then
		return
	end
	chatOrder += 1
	UiKit.label(("%s: %s"):format(from, text), {
		LayoutOrder = chatOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Parent = session.ChatLog,
	})
	session.ChatLog.CanvasPosition = Vector2.new(0, 1e6)
end

local function open(entranceId: string, brand: Brands.Brand, panel: BasePart)
	IntercomController.Close()

	local gui = UiKit.screen("Intercom", 5)
	local frame = UiKit.make("Frame", {
		Size = UDim2.fromOffset(260, 470),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = brand.PanelColor,
		Parent = gui,
	}, { UiKit.corner(14), UiKit.padding(14), UiKit.make("UIScale", { Name = "Scale" }) })

	-- Shrink on small (phone) screens.
	local camera = workspace.CurrentCamera
	local scale = frame:FindFirstChild("Scale") :: UIScale
	local function fit()
		scale.Scale = math.clamp(camera.ViewportSize.Y / 560, 0.6, 1)
	end
	fit()
	local fitConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	gui.Destroying:Once(function()
		fitConn:Disconnect()
	end)

	UiKit.label(brand.DisplayName, {
		Size = UDim2.new(1, -40, 0, 20),
		Font = Enum.Font.GothamBlack,
		TextColor3 = brand.ButtonTextColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local closeBtn = UiKit.button("✕", {
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -32, 0, -6),
		BackgroundColor3 = brand.ButtonColor,
		TextColor3 = brand.ButtonTextColor,
		Parent = frame,
	})
	closeBtn.Activated:Connect(IntercomController.Close)

	local screen = UiKit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 54),
		Position = UDim2.fromOffset(0, 28),
		BackgroundColor3 = brand.DisplayBg,
		Parent = frame,
	}, { UiKit.corner(4) })
	local display = UiKit.label(brand.Text.Idle, {
		Size = UDim2.new(1, -12, 1, -8),
		Position = UDim2.fromOffset(6, 4),
		Font = brand.DisplayFont,
		TextScaled = true,
		TextColor3 = brand.DisplayTextColor,
		Parent = screen,
	})

	local pad = UiKit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 236),
		Position = UDim2.fromOffset(0, 92),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		UiKit.make("UIGridLayout", {
			CellSize = UDim2.new(0.31, 0, 0, 52),
			CellPadding = UDim2.new(0.035, 0, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "CALL" }
	for i, k in keys do
		local text = if k == "C" then brand.ClearLabel elseif k == "CALL" then brand.CallLabel else k
		local b = UiKit.button(text, {
			LayoutOrder = i,
			TextSize = 24,
			BackgroundColor3 = brand.ButtonColor,
			TextColor3 = brand.ButtonTextColor,
			Parent = pad,
		})
		b.Activated:Connect(function()
			if k == "C" then
				clear()
			elseif k == "CALL" then
				UiKit.playLocal(brand.Sounds.Click)
				inputToken += 1 -- cancel pending auto-dial
				dial()
			else
				pressDigit(k)
			end
		end)
	end

	-- Talk panel (visible while connected)
	local chatFrame = UiKit.make("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.fromOffset(0, 336),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = frame,
	}, { UiKit.corner(6), UiKit.padding(6) })
	local chatLog = UiKit.make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = chatFrame,
	}, { UiKit.list(2) })
	local box = UiKit.make("TextBox", {
		Size = UDim2.new(1, -50, 0, 34),
		Position = UDim2.new(0, 0, 1, -34),
		PlaceholderText = "Говорити…",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundColor3 = UiKit.Colors.Panel,
		TextColor3 = UiKit.Colors.Text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		Parent = chatFrame,
	}, { UiKit.corner(6) })
	local send = UiKit.button("➤", {
		Size = UDim2.fromOffset(44, 34),
		Position = UDim2.new(1, -44, 1, -34),
		BackgroundColor3 = UiKit.Colors.Blue,
		Parent = chatFrame,
	})
	local function sendChat()
		if callId and box.Text ~= "" then
			chatEvent:FireServer(callId, box.Text)
			box.Text = ""
		end
	end
	send.Activated:Connect(sendChat)
	box.FocusLost:Connect(function(enter)
		if enter then
			sendChat()
		end
	end)

	session = {
		EntranceId = entranceId,
		Brand = brand,
		Panel = panel,
		Gui = gui,
		Display = display,
		ChatFrame = chatFrame,
		ChatLog = chatLog,
	}
	digits = ""
	callId = nil

	-- Close when the player walks away from the panel.
	local mine = session
	task.spawn(function()
		while session == mine do
			task.wait(0.5)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if session == mine and (not root or (root.Position - panel.Position).Magnitude > 16) then
				IntercomController.Close()
			end
		end
	end)
end

local function onState(status: string, info: { [string]: any })
	-- Key reader feedback works whether or not the keypad is open.
	if status == "key_ok" then
		HudController.Toast("Пі-пі — двері відчинено", "good")
		return
	elseif status == "key_denied" then
		HudController.Toast(info.Reason or "Немає доступу", "bad")
		return
	end

	if not session then
		return
	end
	local text = session.Brand.Text
	if status == "ringing" then
		callId = info.CallId
		inputToken += 1
		setDisplay(session.Brand.RingingText(digits))
	elseif status == "connected" then
		setDisplay(text.Connected)
		setChatVisible(true)
	elseif status == "opened" then
		callId = nil
		setChatVisible(false)
		setDisplay(text.Open)
		HudController.Toast("Вам відчинили двері", "good")
		resetLater(2)
	elseif status == "busy" then
		setDisplay(text.Busy)
		resetLater(2)
	elseif status == "invalid" then
		setDisplay(text.Invalid)
		HudController.Toast(("Тут квартири %d–%d"):format(info.AptFrom or 0, info.AptTo or 0), "bad")
		resetLater(2)
	else -- noanswer, declined, hangup, timeout, left
		callId = nil
		setChatVisible(false)
		setDisplay(text.NoAnswer)
		if status == "declined" then
			HudController.Toast("Виклик відхилено", "bad")
		end
		resetLater(2)
	end
end

function IntercomController.Init()
	dialEvent = Net.Event("IntercomDial")
	hangupEvent = Net.Event("IntercomHangup")
	chatEvent = Net.Event("CallChat")

	Net.Event("IntercomState").OnClientEvent:Connect(onState)
	chatEvent.OnClientEvent:Connect(function(id: string, from: string, text: string)
		if session and callId == id then
			appendChat(from, text)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local action = prompt:GetAttribute("Action")
		local entranceId = prompt:GetAttribute("EntranceId")
		local brand = Brands[prompt:GetAttribute("Brand") :: string]
		if typeof(entranceId) ~= "string" or not brand then
			return
		end
		local part = prompt.Parent
		if not (part and part:IsA("BasePart")) then
			return
		end

		if action == "Intercom" then
			open(entranceId, brand, part)
		elseif action == "Reader" then
			local keyId = KeyRingController.GetActiveKeyId()
			if keyId then
				Net.Event("UseKey"):FireServer(entranceId, keyId)
			else
				HudController.Toast("Візьміть ключ у руку: в'язка ключів (K)")
				KeyRingController.Open()
			end
		end
	end)
end

return IntercomController
