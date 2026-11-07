--!strict
-- GarageController: "My cars" window (V) and the dealership window.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local DataController = require(script.Parent.DataController)
local HudController = require(script.Parent.HudController)

local player = Players.LocalPlayer

local GarageController = {}

local garageGui: ScreenGui? = nil

local function openGarage()
	if garageGui then
		garageGui:Destroy()
		garageGui = nil
		return
	end
	local gui, body = UiKit.window("Garage", "Мої машини  (V)")
	garageGui = gui
	local function rebuild()
		UiKit.clear(body)
		local snap = DataController.Get()
		local cars = if snap then snap.Cars else {}
		if #cars == 0 then
			UiKit.label("Машин немає. Автосалон — біля парковки.", { TextColor3 = UiKit.Colors.Muted, Parent = body })
			return
		end
		local activeId = player:GetAttribute("ActiveCarId")
		local order = 0
		for _, car in cars do
			local spec = Vehicles.Models[car.ModelId]
			local paint = Vehicles.Colors[car.ColorIndex]
			order += 1
			local title = ("%s · %s · %s"):format(spec and spec.Name or car.ModelId, paint and paint.Name or "?", car.Plate)
			UiKit.row(body, order, title, if car.Id == activeId then "Викликати знову" else "Викликати", function()
				local ok, msg = Net.Function("SpawnCar"):InvokeServer(car.Id)
				HudController.Toast(msg, if ok then "good" else "bad")
			end)
		end
		if activeId then
			for _, a in {
				{ "🔒 Замок", "lock" },
				{ "💡 Фари", "lights" },
				{ "↻ Перевернути", "flip" },
				{ "🅿 Відігнати в гараж", "despawn" },
			} do
				order += 1
				local b = UiKit.button(a[1], { LayoutOrder = order, Parent = body })
				b.Activated:Connect(function()
					Net.Event("VehicleAction"):FireServer(a[2])
				end)
			end
		end
	end
	rebuild()
	local conns = {
		DataController.Changed:Connect(rebuild),
		player:GetAttributeChangedSignal("ActiveCarId"):Connect(rebuild),
	}
	gui.Destroying:Once(function()
		for _, c in conns do
			c:Disconnect()
		end
		if garageGui == gui then
			garageGui = nil
		end
	end)
end

local function openDealer()
	local _, body = UiKit.window("Dealer", "Автосалон")
	local selected = 1
	local function rebuild()
		UiKit.clear(body)
		local order = 0
		order += 1
		UiKit.label("Колір: " .. Vehicles.Colors[selected].Name, { LayoutOrder = order, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
		order += 1
		local swatches = UiKit.make("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Parent = body,
		}, { UiKit.list(6, true) })
		for i, paint in Vehicles.Colors do
			local s = UiKit.button(if i == selected then "✓" else "", {
				Size = UDim2.fromOffset(36, 36),
				BackgroundColor3 = paint.Color,
				TextColor3 = Color3.new(0, 0, 0),
				LayoutOrder = i,
				Parent = swatches,
			})
			s.Activated:Connect(function()
				selected = i
				rebuild()
			end)
		end
		for _, id in Vehicles.Order do
			local spec = Vehicles.Models[id]
			order += 1
			UiKit.label(("%s — %s%d"):format(spec.Name, Config.Currency, spec.Price), {
				LayoutOrder = order,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = body,
			})
			order += 1
			UiKit.label(("%s  %d км/год · %s · %d місць"):format(spec.Description, math.floor(spec.TopSpeed * 3.6), spec.Drive, spec.Seats), {
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 36),
				TextSize = 13,
				TextColor3 = UiKit.Colors.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = body,
			})
			order += 1
			local buy = UiKit.button("Купити", { LayoutOrder = order, BackgroundColor3 = UiKit.Colors.Good, Parent = body })
			buy.Activated:Connect(function()
				local ok, msg = Net.Function("BuyCar"):InvokeServer(id, selected)
				HudController.Toast(msg, if ok then "good" else "bad")
			end)
		end
	end
	rebuild()
end

function GarageController.Init()
	local gui = UiKit.screen("GarageButton", 2)
	local button = UiKit.button("🚗 Авто", {
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(0, 8, 0.5, 78),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	})
	button.Activated:Connect(openGarage)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.V then
			openGarage()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Action") == "CarDealer" then
			openDealer()
		end
	end)
end

return GarageController
