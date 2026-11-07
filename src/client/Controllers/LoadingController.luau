--!strict
-- LoadingController: covers the screen while the server builds the city
-- (workspace attribute CityReady / CityProgress), then holds the character in
-- place (HumanoidRootPart anchored) until there is solid ground under it, so the
-- player can never fall before the terrain around the spawn has streamed in.

local Players = game:GetService("Players")

local UiKit = require(script.Parent.Parent.Ui.UiKit)

local player = Players.LocalPlayer

local LoadingController = {}

local HOLD_TIMEOUT = 20 -- seconds; never hold forever

local function groundBelow(root: BasePart, character: Model): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = false
	return workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params)
end

local function hold(character: Model, status: TextLabel?)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) then
		return
	end
	root.Anchored = true -- the client owns its character, so this is allowed
	local t0 = os.clock()
	while character.Parent and os.clock() - t0 < HOLD_TIMEOUT do
		if groundBelow(root, character) then
			break
		end
		if status then
			status.Text = "Завантажуємо землю під вами…"
		end
		task.wait(0.25)
	end
	if root.Parent then
		root.Anchored = false
	end
	if os.clock() - t0 >= HOLD_TIMEOUT then
		warn("[Loading] No ground found under the character after " .. HOLD_TIMEOUT .. " s at " .. tostring(root.Position))
	end
end

function LoadingController.Init()
	local gui = UiKit.screen("Loading", 200)
	gui.IgnoreGuiInset = true
	local cover = UiKit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(18, 22, 30),
		Parent = gui,
	})
	UiKit.label("ПІВДЕННЕ", {
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 0.4, -60),
		Font = Enum.Font.GothamBlack,
		TextSize = 48,
		TextColor3 = UiKit.Colors.Accent,
		Parent = cover,
	})
	local status = UiKit.label("Будуємо місто…", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0.4, 10),
		TextSize = 20,
		Parent = cover,
	})
	local barBack = UiKit.make("Frame", {
		Size = UDim2.new(0.5, 0, 0, 10),
		Position = UDim2.new(0.25, 0, 0.4, 50),
		BackgroundColor3 = UiKit.Colors.Panel,
		Parent = cover,
	}, { UiKit.corner(5) })
	local bar = UiKit.make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = UiKit.Colors.Accent,
		Parent = barBack,
	}, { UiKit.corner(5) })
	UiKit.label("Map data © OpenStreetMap contributors · Elevation: SRTM / AWS Terrain Tiles", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -30),
		TextSize = 12,
		TextColor3 = UiKit.Colors.Muted,
		Parent = cover,
	})

	local function update()
		local progress = workspace:GetAttribute("CityProgress")
		local p = if typeof(progress) == "number" then progress else 0
		bar.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
		status.Text = ("Будуємо місто… %d%%"):format(math.floor(p * 100))
	end
	update()
	workspace:GetAttributeChangedSignal("CityProgress"):Connect(update)

	-- Hide the cover once the city is ready AND our character stands on ground.
	task.spawn(function()
		while workspace:GetAttribute("CityReady") ~= true do
			task.wait(0.25)
		end
		status.Text = "Майже готово…"
		local character = player.Character or player.CharacterAdded:Wait()
		hold(character, status)
		gui:Destroy()
	end)

	-- Every later spawn (respawn after death) gets the same ground hold, no cover.
	player.CharacterAdded:Connect(function(character)
		if not gui.Parent then
			hold(character, nil)
		end
	end)
end

return LoadingController
