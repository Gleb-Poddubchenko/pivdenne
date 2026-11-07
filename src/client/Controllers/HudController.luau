--!strict
-- HudController: money display, toasts and the mandatory OSM attribution.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)

local HudController = {}

local toastHolder: Frame

function HudController.Toast(text: string, kind: string?)
	if not toastHolder then
		return
	end
	local color = if kind == "bad" then UiKit.Colors.Bad elseif kind == "good" then UiKit.Colors.Good else UiKit.Colors.Panel
	local toast = UiKit.make("TextLabel", {
		Text = text,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		TextColor3 = UiKit.Colors.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		Parent = toastHolder,
	}, { UiKit.corner(8), UiKit.padding(8) })
	task.delay(3.5, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		toast:Destroy()
	end)
end

function HudController.Init()
	local gui = UiKit.screen("Hud", 1)

	local money = UiKit.label(Config.Currency .. " …", {
		Size = UDim2.fromOffset(150, 36),
		Position = UDim2.new(1, -160, 0, 8),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = UiKit.Colors.Bg,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextColor3 = UiKit.Colors.Accent,
		Parent = gui,
	})
	UiKit.corner(8).Parent = money

	DataController.Changed:Connect(function(snapshot)
		money.Text = ("%s %d"):format(Config.Currency, snapshot.Money)
	end)
	local snap = DataController.Get()
	if snap then
		money.Text = ("%s %d"):format(Config.Currency, snap.Money)
	end

	toastHolder = UiKit.make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 320, 0.5, 0),
		Position = UDim2.new(0.5, -160, 0, 56),
		Parent = gui,
	}, { UiKit.list(6) })

	-- ODbL requirement: visible attribution for OpenStreetMap-derived map data.
	UiKit.label("Map data © OpenStreetMap contributors", {
		Size = UDim2.fromOffset(260, 16),
		Position = UDim2.new(0, 8, 1, -20),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.Colors.Text,
		TextTransparency = 0.3,
		TextStrokeTransparency = 0.6,
		Parent = gui,
	})

	Net.Event("Notify").OnClientEvent:Connect(function(text: string, kind: string?)
		HudController.Toast(text, kind)
	end)
end

return HudController
