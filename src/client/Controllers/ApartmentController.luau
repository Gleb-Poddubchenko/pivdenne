--!strict
-- ApartmentController: screen fade during door teleports and the doorbell popup
-- for a flat owner who is at home.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)

local ApartmentController = {}

local fadeFrame: Frame

local function fade(seconds: number)
	fadeFrame.BackgroundTransparency = 1
	fadeFrame.Visible = true
	local inTween = TweenService:Create(fadeFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0 })
	inTween:Play()
	task.delay(math.max(seconds - 0.4, 0.2), function()
		local outTween = TweenService:Create(fadeFrame, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		outTween:Play()
		outTween.Completed:Wait()
		fadeFrame.Visible = false
	end)
end

local function onDoorbell(ringId: string, label: string, visitorName: string)
	UiKit.playLocal(Config.Sounds.Doorbell, 0.8)
	local gui = UiKit.screen("Doorbell", 10)
	local frame = UiKit.make("Frame", {
		Size = UDim2.new(0.9, 0, 0, 150),
		Position = UDim2.new(0.5, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	}, {
		UiKit.corner(12),
		UiKit.padding(12),
		UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(380, 150) }),
	})
	UiKit.label("🔔 Дзвонять у двері · " .. label, { Font = Enum.Font.GothamBold, TextSize = 18, Size = UDim2.new(1, 0, 0, 26), Parent = frame })
	UiKit.label("У вічко видно: " .. visitorName, { Position = UDim2.fromOffset(0, 30), TextColor3 = UiKit.Colors.Muted, Parent = frame })
	local function answer(accept: boolean)
		Net.Event("DoorbellAnswer"):FireServer(ringId, accept)
		gui:Destroy()
	end
	UiKit.button("Відчинити", {
		Size = UDim2.new(0.48, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		BackgroundColor3 = UiKit.Colors.Good,
		Parent = frame,
	}).Activated:Connect(function()
		answer(true)
	end)
	UiKit.button("Не відчиняти", {
		Size = UDim2.new(0.48, 0, 0, 44),
		Position = UDim2.new(0.52, 0, 1, -44),
		BackgroundColor3 = UiKit.Colors.Bad,
		Parent = frame,
	}).Activated:Connect(function()
		answer(false)
	end)
	task.delay(Config.Interiors.DoorbellTimeout, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

function ApartmentController.Init()
	local gui = UiKit.screen("Fade", 100)
	gui.IgnoreGuiInset = true
	fadeFrame = UiKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Net.Event("Fade").OnClientEvent:Connect(fade)
	Net.Event("DoorbellRing").OnClientEvent:Connect(onDoorbell)
end

return ApartmentController
