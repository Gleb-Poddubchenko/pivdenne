--!strict
-- ElevatorController: everything cosmetic about lifts runs here, locally, driven
-- by the replicated attributes State / Floor / CabinRequests / AlarmAt:
--   motor hum, start/stop clunks, door clatter, emergency bell, camera jolts for
--   riders, the flickering cabin lamp, and the cabin button panel UI.
-- The server only receives button presses (ElevatorPanel remote).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)

local player = Players.LocalPlayer
local Sounds = Config.Sounds

local ElevatorController = {}

local tracked: { [Model]: boolean } = {}
local panelGui: ScreenGui? = nil

local MOVING: { [string]: boolean } = { MovingUp = true, MovingDown = true }

local STATE_TEXT: { [string]: string } = {
	Idle = "",
	MovingUp = "▲",
	MovingDown = "▼",
	DoorsOpening = "◀▶",
	DoorsOpen = "◀▶",
	DoorsClosing = "▶◀",
	Stalled = "СТОЇТЬ",
	OutOfService = "НЕ ПРАЦЮЄ",
}

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isInside(bounds: BasePart): boolean
	local root = rootPart()
	if not root then
		return false
	end
	local p = bounds.CFrame:PointToObjectSpace(root.Position)
	local half = bounds.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y + 1 and math.abs(p.Z) <= half.Z
end

-- Short camera jolt through Humanoid.CameraOffset (local only).
local function jolt(intensity: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local fade = 1 - (os.clock() - t0) / duration
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * intensity * fade, (math.random() - 0.5) * intensity * fade, 0)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local function playAt(parent: Instance, soundId: string, volume: number?): Sound?
	if soundId == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 0.6
	s.RollOffMaxDistance = 40
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	return s
end

local function setupCabin(model: Model, cabin: Instance)
	local platform = cabin:FindFirstChild("Platform")
	local bounds = cabin:FindFirstChild("Bounds")
	if not (platform and platform:IsA("BasePart") and bounds and bounds:IsA("BasePart")) then
		return
	end
	local lamp = cabin:FindFirstChild("Lamp")
	local light = lamp and lamp:FindFirstChildOfClass("PointLight")
	local connections: { RBXScriptConnection } = {}

	local hum: Sound? = nil
	if Sounds.ElevatorHum ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = Sounds.ElevatorHum
		s.Looped = true
		s.Volume = 0.35
		s.RollOffMaxDistance = 50
		s.Parent = platform
		hum = s
	end

	local lastState = model:GetAttribute("State") :: string?
	if hum and lastState and MOVING[lastState] then
		hum:Play()
	end

	table.insert(connections, model:GetAttributeChangedSignal("State"):Connect(function()
		local state = model:GetAttribute("State") :: string
		local was = lastState or "Idle"
		lastState = state
		local inside = isInside(bounds)

		if MOVING[state] and not MOVING[was] then
			playAt(platform, Sounds.ElevatorStart)
			if hum then
				hum:Play()
			end
			if inside then
				jolt(0.25, 0.35)
			end
		elseif not MOVING[state] and MOVING[was] then
			if hum then
				hum:Stop()
			end
			playAt(platform, Sounds.ElevatorStop)
			if inside then
				jolt(if state == "Stalled" then 0.6 else 0.3, if state == "Stalled" then 0.6 else 0.3)
			end
		end
		if state == "DoorsOpening" or state == "DoorsClosing" then
			playAt(platform, Sounds.ElevatorDoors)
			playAt(platform, Sounds.ElevatorShaftDoor, 0.5)
		end
	end))

	table.insert(connections, model:GetAttributeChangedSignal("AlarmAt"):Connect(function()
		playAt(platform, Sounds.ElevatorBell, 0.8)
	end))

	-- Flickering fluorescent-ish lamp; much worse while stalled.
	if lamp and lamp:IsA("BasePart") and light then
		local baseColor = lamp.Color
		task.spawn(function()
			while cabin.Parent do
				local stalled = model:GetAttribute("State") == "Stalled"
				task.wait(if stalled then 0.4 + math.random() * 1.2 else 3 + math.random() * 9)
				if not cabin.Parent then
					break
				end
				for _ = 1, math.random(2, if stalled then 7 else 4) do
					light.Enabled = false
					lamp.Color = Color3.fromRGB(90, 85, 75)
					task.wait(0.04 + math.random() * 0.1)
					light.Enabled = true
					lamp.Color = baseColor
					task.wait(0.03 + math.random() * 0.15)
				end
				light.Brightness = if stalled then 0.5 else 1.1
			end
		end)
	end

	cabin.Destroying:Once(function()
		for _, c in connections do
			c:Disconnect()
		end
		if hum then
			hum:Destroy()
		end
	end)
end

local function track(inst: Instance)
	if not inst:IsA("Model") or tracked[inst] then
		return
	end
	tracked[inst] = true
	local cabin = inst:FindFirstChild("Cabin")
	if cabin then
		setupCabin(inst, cabin)
	end
	-- Streaming: the (atomic) cabin may arrive later or be re-streamed.
	inst.ChildAdded:Connect(function(child)
		if child.Name == "Cabin" then
			setupCabin(inst, child)
		end
	end)
end

local function findElevator(id: string): Model?
	for _, inst in CollectionService:GetTagged("Elevator") do
		if inst:IsA("Model") and inst:GetAttribute("ElevatorId") == id then
			return inst
		end
	end
	return nil
end

local function closePanel()
	if panelGui then
		panelGui:Destroy()
		panelGui = nil
	end
end

local function openPanel(id: string, floors: number, panelPart: BasePart)
	closePanel()
	local model = findElevator(id)
	if not model then
		return
	end
	local remote = Net.Event("ElevatorPanel")
	local gui = UiKit.screen("LiftPanel", 5)
	panelGui = gui

	local rows = math.ceil(floors / 2)
	local frame = UiKit.make("Frame", {
		Size = UDim2.fromOffset(170, 120 + rows * 58),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.fromRGB(45, 40, 34),
		Parent = gui,
	}, { UiKit.corner(6), UiKit.padding(10), UiKit.make("UIScale", { Name = "Scale" }) })
	local scale = frame:FindFirstChild("Scale") :: UIScale
	scale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / (180 + rows * 58), 0.55, 1)

	local status = UiKit.label("", {
		Size = UDim2.new(1, -40, 0, 26),
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(255, 160, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local closeBtn = UiKit.button("✕", { Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -32, 0, -4), Parent = frame })
	closeBtn.Activated:Connect(closePanel)

	local grid = UiKit.make("Frame", {
		Size = UDim2.new(1, 0, 0, rows * 58),
		Position = UDim2.fromOffset(0, 34),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		UiKit.make("UIGridLayout", {
			CellSize = UDim2.fromOffset(64, 50),
			CellPadding = UDim2.fromOffset(12, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	-- Soviet panels: floor 1 at the bottom, so fill from the highest floor down.
	local buttons: { [number]: TextButton } = {}
	local order = 0
	for r = rows, 1, -1 do
		for c = 1, 2 do
			local f = (r - 1) * 2 + c
			order += 1
			if f <= floors then
				local b = UiKit.button(tostring(f), {
					LayoutOrder = order,
					TextSize = 24,
					BackgroundColor3 = Color3.fromRGB(20, 18, 16),
					TextColor3 = Color3.fromRGB(210, 205, 190),
					Parent = grid,
				})
				UiKit.corner(25).Parent = b
				b.Activated:Connect(function()
					UiKit.playLocal(Sounds.ElevatorButton)
					remote:FireServer(id, "floor", f)
				end)
				buttons[f] = b
			else
				UiKit.make("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Parent = grid })
			end
		end
	end

	local stop = UiKit.button("СТОП", {
		Size = UDim2.new(0.47, 0, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		BackgroundColor3 = Color3.fromRGB(160, 30, 25),
		Parent = frame,
	})
	stop.Activated:Connect(function()
		UiKit.playLocal(Sounds.ElevatorButton)
		remote:FireServer(id, "stop")
	end)
	local alarm = UiKit.button("🔔 ВИКЛИК", {
		Size = UDim2.new(0.47, 0, 0, 44),
		Position = UDim2.new(0.53, 0, 1, -44),
		BackgroundColor3 = Color3.fromRGB(200, 150, 20),
		TextColor3 = Color3.fromRGB(20, 18, 16),
		TextSize = 14,
		Parent = frame,
	})
	alarm.Activated:Connect(function()
		remote:FireServer(id, "alarm")
	end)

	local function refresh()
		local lit: { [number]: boolean } = {}
		local raw = model:GetAttribute("CabinRequests")
		if typeof(raw) == "string" then
			for s in string.gmatch(raw, "%d+") do
				lit[tonumber(s) :: number] = true
			end
		end
		for f, b in buttons do
			b.BackgroundColor3 = if lit[f] then Color3.fromRGB(255, 140, 40) else Color3.fromRGB(20, 18, 16)
		end
		local state = model:GetAttribute("State") :: string?
		status.Text = ("%s %s"):format(tostring(model:GetAttribute("Floor") or ""), STATE_TEXT[state or ""] or "")
	end
	refresh()
	local conns = {
		model:GetAttributeChangedSignal("CabinRequests"):Connect(refresh),
		model:GetAttributeChangedSignal("State"):Connect(refresh),
		model:GetAttributeChangedSignal("Floor"):Connect(refresh),
	}
	gui.Destroying:Once(function()
		for _, c in conns do
			c:Disconnect()
		end
	end)

	-- Close once the player steps out of the cabin.
	task.spawn(function()
		while panelGui == gui do
			task.wait(0.5)
			local root = rootPart()
			if panelGui == gui and (not root or (root.Position - panelPart.Position).Magnitude > Config.Elevator.PanelDistance) then
				closePanel()
			end
		end
	end)
end

function ElevatorController.Init()
	for _, inst in CollectionService:GetTagged("Elevator") do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal("Elevator"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Elevator"):Connect(function(inst)
		if inst:IsA("Model") then
			tracked[inst] = nil
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Action") ~= "ElevatorPanel" then
			return
		end
		local id = prompt:GetAttribute("ElevatorId")
		local floors = prompt:GetAttribute("Floors")
		local part = prompt.Parent
		if typeof(id) == "string" and typeof(floors) == "number" and part and part:IsA("BasePart") then
			openPanel(id, floors, part)
		end
	end)
end

return ElevatorController
