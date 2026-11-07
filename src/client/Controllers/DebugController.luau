--!strict
-- DebugController (Studio, the place owner, or Config.Debug.Admins only):
--   \  (FlyKey)  free-fly camera: WASD move, Q/E down/up, Shift = fast,
--               hold the right mouse button to look around, T = teleport here.
--   ]  (InfoKey) print position, heightmap vs. real terrain height under you,
--               and the server's city build stats (also shown on screen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)

local player = Players.LocalPlayer

local DebugController = {}

local flying = false
local yaw, pitch = 0, -0.6
local flyConn: RBXScriptConnection? = nil
local label: TextLabel? = nil

local function allowed(): boolean
	return RunService:IsStudio() or player.UserId == game.CreatorId or table.find(Config.Debug.Admins, player.UserId) ~= nil
end

local function groundUnder(pos: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(pos, Vector3.new(0, -3000, 0), params)
	return if hit then hit.Position.Y else nil
end

local function stopFly()
	flying = false
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = false
	end
	if label then
		label.Visible = false
	end
end

local function startFly()
	flying = true
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true -- park the character while the camera roams
	end
	local start = camera.CFrame
	local look = start.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -0.99, 0.99))
	camera.CameraType = Enum.CameraType.Scriptable
	local position = start.Position
	if label then
		label.Visible = true
	end
	flyConn = RunService.RenderStepped:Connect(function(dt)
		local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.E) then vertical += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.Q) then vertical -= 1 end
		local speed = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 400 else 80
		position += (rotation:VectorToWorldSpace(move) + Vector3.new(0, vertical, 0)) * speed * dt
		camera.CFrame = CFrame.new(position) * rotation
		UserInputService.MouseBehavior = if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			then Enum.MouseBehavior.LockCurrentPosition
			else Enum.MouseBehavior.Default
		if label then
			local g = groundUnder(position)
			label.Text = ("FLY  (\\ exit · T teleport)  pos %d, %d, %d  ·  ground below %s"):format(
				math.floor(position.X), math.floor(position.Y), math.floor(position.Z), if g then ("%.1f"):format(g) else "NONE")
		end
	end)
end

local function printInfo()
	local lines = { "[Debug] ===== city debug =====" }
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local g = groundUnder(root.Position + Vector3.new(0, 5, 0))
		table.insert(lines, ("[Debug] client: position %s, ground below (client raycast) %s"):format(
			tostring(root.Position), if g then ("%.1f"):format(g) else "NONE"))
	end
	local ok, info = pcall(function()
		return Net.Function("DebugInfo"):InvokeServer()
	end)
	if ok and typeof(info) == "table" then
		for _, line in info do
			table.insert(lines, "[Debug] server: " .. line)
		end
	end
	for _, line in lines do
		print(line)
	end
	if label then
		label.Visible = true
		label.Text = table.concat(lines, "\n")
		task.delay(8, function()
			if label and not flying then
				label.Visible = false
			end
		end)
	end
end

function DebugController.Init()
	if not allowed() then
		return
	end
	local gui = UiKit.screen("Debug", 150)
	label = UiKit.label("", {
		Visible = false,
		Size = UDim2.new(1, -20, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(10, 50),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Code,
		TextSize = 14,
		Parent = gui,
	})

	UserInputService.InputChanged:Connect(function(input)
		if flying and input.UserInputType == Enum.UserInputType.MouseMovement
			and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		then
			yaw -= input.Delta.X * 0.004
			pitch = math.clamp(pitch - input.Delta.Y * 0.004, -1.5, 1.5)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Config.Debug.FlyKey then
			if flying then
				stopFly()
			else
				startFly()
			end
		elseif input.KeyCode == Config.Debug.InfoKey then
			task.spawn(printInfo)
		elseif flying and input.KeyCode == Enum.KeyCode.T then
			local camera = workspace.CurrentCamera
			local g = groundUnder(camera.CFrame.Position)
			local character = player.Character
			if g and character then
				local target = Vector3.new(camera.CFrame.Position.X, g + 4, camera.CFrame.Position.Z)
				stopFly()
				character:PivotTo(CFrame.new(target))
			end
		end
	end)
	print("[Debug] Debug keys: \\ = fly camera, ] = city debug info")
end

return DebugController
