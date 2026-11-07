--!strict
-- VehicleController: driving. While the local player sits in a car's DriverSeat
-- the server hands that car's physics to this client; we read the VehicleSeat's
-- ThrottleFloat/SteerFloat (keyboard WASD, gamepad and the mobile thumbstick all
-- feed it) and set the axle motors and steering servos every frame.
-- Also: speedometer HUD, horn (H) and lights (L), engine pitch for nearby cars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)

local player = Players.LocalPlayer
local cfg = Config.Vehicles

local VehicleController = {}

type Drive = {
	Seat: VehicleSeat,
	Model: Model,
	Chassis: BasePart,
	Axles: { HingeConstraint },
	Steers: { HingeConstraint },
	TopSpeed: number,
	WheelRadius: number,
	DriveTorque: number,
	BrakeTorque: number,
	MaxSteer: number,
}

local drive: Drive? = nil
local stepConn: RBXScriptConnection? = nil
local hud: ScreenGui? = nil
local speedLabel: TextLabel? = nil

local function step()
	local d = drive
	if not d or not d.Chassis.Parent then
		return
	end
	local throttle = d.Seat.ThrottleFloat
	local steer = d.Seat.SteerFloat
	local forwardSpeed = d.Chassis.AssemblyLinearVelocity:Dot(d.Chassis.CFrame.LookVector)
	local maxW = d.TopSpeed / d.WheelRadius

	local braking = throttle ~= 0 and forwardSpeed * throttle < -1.5 -- pressing against the motion
	for _, axle in d.Axles do
		local driven = axle:GetAttribute("Driven") == true
		if braking then
			axle.AngularVelocity = 0
			axle.MotorMaxTorque = d.BrakeTorque
		elseif throttle ~= 0 and driven then
			local factor = if throttle < 0 then cfg.ReverseFactor else 1
			axle.AngularVelocity = cfg.MotorSign * throttle * maxW * factor
			axle.MotorMaxTorque = d.DriveTorque
		elseif driven then
			axle.AngularVelocity = 0 -- coasting: gentle engine braking
			axle.MotorMaxTorque = d.DriveTorque * 0.06
		else
			axle.MotorMaxTorque = 0 -- free-rolling wheel
		end
	end

	-- Less steering lock at speed keeps cars from flipping in turns.
	local speedFactor = math.clamp(1 - math.abs(forwardSpeed) / d.TopSpeed * 0.6, 0.35, 1)
	for _, s in d.Steers do
		s.TargetAngle = cfg.SteerSign * steer * d.MaxSteer * speedFactor
	end

	if speedLabel then
		local kmh = math.abs(forwardSpeed) / Config.StudsPerMeter * 3.6
		speedLabel.Text = ("%d км/год"):format(math.floor(kmh + 0.5))
	end
end

local function hideHud()
	if hud then
		hud:Destroy()
		hud = nil
		speedLabel = nil
	end
end

local function showHud(plate: string)
	hideHud()
	local gui = UiKit.screen("DriveHud", 3)
	hud = gui
	local panel = UiKit.make("Frame", {
		Size = UDim2.fromOffset(200, 96),
		Position = UDim2.new(0.5, -100, 1, -110),
		BackgroundColor3 = UiKit.Colors.Bg,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, { UiKit.corner(10), UiKit.padding(6) })
	speedLabel = UiKit.label("0 км/год", {
		Size = UDim2.new(1, 0, 0, 34),
		Font = Enum.Font.GothamBlack,
		TextSize = 28,
		TextColor3 = UiKit.Colors.Accent,
		Parent = panel,
	})
	UiKit.label(plate, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = UiKit.Colors.Muted, Parent = panel })
	local horn = UiKit.button("📯 H", { Size = UDim2.new(0.48, 0, 0, 34), Position = UDim2.new(0, 0, 1, -34), Parent = panel })
	horn.Activated:Connect(function()
		Net.Event("VehicleAction"):FireServer("honk")
	end)
	local lights = UiKit.button("💡 L", { Size = UDim2.new(0.48, 0, 0, 34), Position = UDim2.new(0.52, 0, 1, -34), Parent = panel })
	lights.Activated:Connect(function()
		Net.Event("VehicleAction"):FireServer("lights")
	end)
end

local function unbind()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	drive = nil
	hideHud()
end

local function bind(seat: VehicleSeat)
	local model = seat.Parent
	local chassis = model and model:FindFirstChild("Chassis")
	if not (model and model:IsA("Model") and chassis and chassis:IsA("BasePart")) then
		return
	end
	local axles, steers = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("HingeConstraint") then
			if string.sub(d.Name, 1, 5) == "Axle_" then
				table.insert(axles, d)
			elseif string.sub(d.Name, 1, 6) == "Steer_" then
				table.insert(steers, d)
			end
		end
	end
	local function num(name: string, default: number): number
		local v = model:GetAttribute(name)
		return if typeof(v) == "number" then v else default
	end
	drive = {
		Seat = seat,
		Model = model,
		Chassis = chassis,
		Axles = axles,
		Steers = steers,
		TopSpeed = num("TopSpeed", 80),
		WheelRadius = num("WheelRadius", 1),
		DriveTorque = num("DriveTorque", 5000),
		BrakeTorque = num("BrakeTorque", 12000),
		MaxSteer = num("MaxSteer", 30),
	}
	stepConn = RunService.Heartbeat:Connect(step)
	showHud(tostring(model:GetAttribute("Plate") or ""))
end

local function watchCharacter(character: Model)
	unbind()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
		unbind()
		if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart:GetAttribute("Driver") == true then
			bind(seatPart)
		end
	end)
end

function VehicleController.Init()
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not drive then
			return
		end
		if input.KeyCode == Enum.KeyCode.H then
			Net.Event("VehicleAction"):FireServer("honk")
		elseif input.KeyCode == Enum.KeyCode.L then
			Net.Event("VehicleAction"):FireServer("lights")
		end
	end)

	-- Engine pitch for cars near the camera (5 Hz, cosmetic only).
	task.spawn(function()
		-- created by VehicleService; a timeout argument avoids the "infinite yield" warning
		-- while the server is still starting up (the city build can take a while)
		local folder = workspace:WaitForChild("Vehicles", math.huge)
		while true do
			task.wait(0.2)
			local camPos = workspace.CurrentCamera.CFrame.Position
			for _, car in folder:GetChildren() do
				local chassis = car:FindFirstChild("Chassis")
				local engine = chassis and chassis:FindFirstChild("Engine")
				if chassis and chassis:IsA("BasePart") and engine and engine:IsA("Sound")
					and (chassis.Position - camPos).Magnitude < 120
				then
					local top = car:GetAttribute("TopSpeed")
					local ratio = chassis.AssemblyLinearVelocity.Magnitude / (if typeof(top) == "number" then top else 80)
					engine.PlaybackSpeed = 0.8 + math.clamp(ratio, 0, 1) * 1.1
				end
			end
		end
	end)
end

return VehicleController
