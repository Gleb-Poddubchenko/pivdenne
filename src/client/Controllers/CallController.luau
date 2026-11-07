--!strict
-- CallController: the flat owner's side — the apartment handset (трубка).
-- Pops up on IncomingCall: answer, talk (text), open the door, or hang up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local HudController = require(script.Parent.HudController)

local CallController = {}

type Active = {
	CallId: string,
	Gui: ScreenGui,
	Status: TextLabel,
	AnswerButton: TextButton,
	EndButton: TextButton,
	ChatFrame: Frame,
	ChatLog: ScrollingFrame,
	Ring: Sound?,
}

local active: Active? = nil
local chatOrder = 0

local actionEvent: RemoteEvent
local chatEvent: RemoteEvent

local REASONS: { [string]: string } = {
	opened = "Двері відчинено",
	noanswer = "Пропущений виклик",
	hangup = "Розмову завершено",
	declined = "Виклик відхилено",
	timeout = "Час розмови вичерпано",
	left = "Співрозмовник пішов",
}

local function closeUi()
	if active then
		if active.Ring then
			active.Ring:Destroy()
		end
		active.Gui:Destroy()
		active = nil
	end
end

local function onIncoming(callId: string, entranceId: string, apt: number, callerName: string)
	closeUi()

	local gui = UiKit.screen("Handset", 10)
	local frame = UiKit.make("Frame", {
		Size = UDim2.new(0.9, 0, 0, 300),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	}, {
		UiKit.corner(12),
		UiKit.padding(12),
		UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(380, 300) }),
	})
	UiKit.label(("☎ Домофон · кв. %d"):format(apt), {
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = frame,
	})
	local status = UiKit.label(("Дзвонить %s (%s)"):format(callerName, entranceId), {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 28),
		TextColor3 = UiKit.Colors.Muted,
		Parent = frame,
	})

	local buttons = UiKit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { UiKit.list(6, true) })
	local answer = UiKit.button("Відповісти", {
		Size = UDim2.new(0.32, -4, 1, 0),
		BackgroundColor3 = UiKit.Colors.Good,
		LayoutOrder = 1,
		Parent = buttons,
	})
	local openBtn = UiKit.button("🔓 Відчинити", {
		Size = UDim2.new(0.34, -4, 1, 0),
		BackgroundColor3 = UiKit.Colors.Blue,
		LayoutOrder = 2,
		Parent = buttons,
	})
	local endBtn = UiKit.button("Відхилити", {
		Size = UDim2.new(0.32, -4, 1, 0),
		BackgroundColor3 = UiKit.Colors.Bad,
		LayoutOrder = 3,
		Parent = buttons,
	})

	local chatFrame = UiKit.make("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 1, -110),
		Position = UDim2.fromOffset(0, 110),
		BackgroundColor3 = UiKit.Colors.Panel,
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
		PlaceholderText = "Хто там?",
		Text = "",
		ClearTextOnFocus = false,
		BackgroundColor3 = UiKit.Colors.Bg,
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

	local ring: Sound? = nil
	if Config.Sounds.HandsetRing ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = Config.Sounds.HandsetRing
		s.Looped = true
		s.Volume = 0.6
		s.Parent = workspace.CurrentCamera
		s:Play()
		ring = s
	end

	local current: Active = {
		CallId = callId,
		Gui = gui,
		Status = status,
		AnswerButton = answer,
		EndButton = endBtn,
		ChatFrame = chatFrame,
		ChatLog = chatLog,
		Ring = ring,
	}
	active = current
	local answered = false

	answer.Activated:Connect(function()
		if answered then
			return
		end
		answered = true
		actionEvent:FireServer(callId, "answer")
		if current.Ring then
			current.Ring:Destroy()
			current.Ring = nil
		end
		answer.Visible = false
		endBtn.Text = "Покласти"
		status.Text = "Розмова з " .. callerName
		chatFrame.Visible = true
	end)
	openBtn.Activated:Connect(function()
		actionEvent:FireServer(callId, "open")
	end)
	endBtn.Activated:Connect(function()
		actionEvent:FireServer(callId, if answered then "hangup" else "decline")
	end)

	local function sendChat()
		if answered and box.Text ~= "" then
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
end

function CallController.Init()
	actionEvent = Net.Event("CallAction")
	chatEvent = Net.Event("CallChat")

	Net.Event("IncomingCall").OnClientEvent:Connect(onIncoming)

	Net.Event("CallEnded").OnClientEvent:Connect(function(callId: string, reason: string)
		if active and active.CallId == callId then
			closeUi()
			HudController.Toast(REASONS[reason] or "Виклик завершено", if reason == "opened" then "good" else nil)
		end
	end)

	chatEvent.OnClientEvent:Connect(function(callId: string, from: string, text: string)
		if active and active.CallId == callId then
			chatOrder += 1
			UiKit.label(("%s: %s"):format(from, text), {
				LayoutOrder = chatOrder,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 14,
				Parent = active.ChatLog,
			})
			active.ChatLog.CanvasPosition = Vector2.new(0, 1e6)
		end
	end)
end

return CallController
