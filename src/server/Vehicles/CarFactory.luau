--!strict
-- CarFactory: builds a drivable car from primitive parts and physics constraints.
--
-- Per wheel:
--   rear : Chassis --Prismatic(up)+Spring--> Strut --Hinge(right, Motor)--> Wheel
--   front: Chassis --Hinge(up, Servo "Steer_*")--> Knuckle --Prismatic+Spring--> Strut --Hinge--> Wheel
-- All axle hinges are Motors: driven wheels get drive torque, every wheel gets brake
-- torque. The DRIVER'S CLIENT sets those values (it owns the physics while driving),
-- see VehicleController. Body parts are massless and welded to a heavy, low
-- chassis, so the centre of mass is low and cars don't roll over easily.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))

local M = Config.Meters

export type BuiltCar = {
	Model: Model,
	Chassis: BasePart,
	DriverSeat: VehicleSeat,
	Seats: { BasePart }, -- driver seat first
	Lights: { SpotLight },
	LightParts: { BasePart },
	Engine: Sound?,
	TopSpeed: number, -- studs/s
	Width: number, -- studs
}

local CarFactory = {}

local HEADLIGHT_OFF = Color3.fromRGB(200, 200, 190)
local HEADLIGHT_ON = Color3.fromRGB(255, 250, 220)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function attach(parentPart: BasePart, worldCF: CFrame, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = parentPart
	a.WorldCFrame = worldCF
	return a
end

local function plateGui(target: BasePart, plate: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = target
	local strip = Instance.new("Frame")
	strip.Size = UDim2.fromScale(0.12, 1)
	strip.BackgroundColor3 = Color3.fromRGB(0, 87, 183)
	strip.BorderSizePixel = 0
	strip.Parent = gui
	local ua = Instance.new("TextLabel")
	ua.Size = UDim2.fromScale(1, 0.5)
	ua.Position = UDim2.fromScale(0, 0.5)
	ua.BackgroundTransparency = 1
	ua.TextScaled = true
	ua.Font = Enum.Font.GothamBold
	ua.TextColor3 = Color3.fromRGB(255, 215, 0)
	ua.Text = "UA"
	ua.Parent = strip
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.86, 1)
	label.Position = UDim2.fromScale(0.13, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(20, 20, 20)
	label.Text = plate
	label.Parent = gui
end

-- spawnCF: on the ground at the car's centre, LookVector = forward.
function CarFactory.Build(spec: Vehicles.CarModel, color: Color3, plate: string, spawnCF: CFrame): BuiltCar
	local cfg = Config.Vehicles
	local hs = cfg.HeightScale
	local W, L = M(spec.Width), M(spec.Length)
	local R = M(cfg.WheelRadius)
	local wheelW = M(0.2)
	local chassisH = M(0.3)
	local chassisY = R * 0.85 + chassisH / 2 -- chassis centre above ground
	local base = spawnCF * CFrame.new(0, chassisY + 0.5, 0) -- dropped from 0.5 studs
	local right, up = base.RightVector, base.UpVector

	local model = Instance.new("Model")
	model.Name = "Car_" .. plate
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassis = part(model, "Chassis", Vector3.new(W, chassisH, L), base, {
		Color = color,
		CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0.1),
	})
	model.PrimaryPart = chassis
	local paint = { Color = color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.05 }

	-- BODY ----------------------------------------------------------------------
	local bodyH = M(0.45) * hs
	local bodyTop = chassisH / 2 + bodyH
	local welded: { BasePart } = {}
	local function body(name: string, size: Vector3, offset: CFrame, props: { [string]: any }?): Part
		local p = part(model, name, size, base * offset, props or paint)
		table.insert(welded, p)
		return p
	end

	body("Body", Vector3.new(W, bodyH, L), CFrame.new(0, chassisH / 2 + bodyH / 2, 0))
	local cabinLen = L * (spec.CabinEnd - spec.CabinStart)
	local cabinZ = -L / 2 + L * (spec.CabinStart + spec.CabinEnd) / 2
	local cabinH = math.max(M(spec.Height) * hs - (R * 0.85 + chassisH + bodyH) - 0.3, M(0.5))
	body("Cabin", Vector3.new(W * 0.94, cabinH, cabinLen), CFrame.new(0, bodyTop + cabinH / 2, cabinZ), {
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = Color3.fromRGB(45, 55, 65),
		CanCollide = false,
	})
	body("Roof", Vector3.new(W * 0.92, 0.3, cabinLen * 0.96), CFrame.new(0, bodyTop + cabinH + 0.15, cabinZ))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			body("Pillar", Vector3.new(0.25, cabinH, 0.25), CFrame.new(sx * (W * 0.47 - 0.125), bodyTop + cabinH / 2, cabinZ + sz * (cabinLen / 2 - 0.125)), {
				Color = color,
				CanCollide = false,
			})
		end
	end

	local chrome = { Material = Enum.Material.Metal, Color = Color3.fromRGB(190, 190, 195) }
	body("BumperFront", Vector3.new(W + 0.1, M(0.18), M(0.12)), CFrame.new(0, 0, -L / 2 - M(0.06)), chrome)
	body("BumperRear", Vector3.new(W + 0.1, M(0.18), M(0.12)), CFrame.new(0, 0, L / 2 + M(0.06)), chrome)

	local lights: { SpotLight } = {}
	local lightParts: { BasePart } = {}
	for _, sx in { -1, 1 } do
		local head = body("Headlight", Vector3.new(M(0.3), M(0.18), 0.1), CFrame.new(sx * (W / 2 - M(0.25)), chassisH / 2 + bodyH * 0.6, -L / 2 - 0.05), {
			Material = Enum.Material.Neon,
			Color = HEADLIGHT_OFF,
		})
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 45
		spot.Angle = 70
		spot.Brightness = 3
		spot.Enabled = false
		spot.Parent = head
		table.insert(lights, spot)
		table.insert(lightParts, head)
		body("Taillight", Vector3.new(M(0.3), M(0.12), 0.1), CFrame.new(sx * (W / 2 - M(0.25)), chassisH / 2 + bodyH * 0.6, L / 2 + 0.05), {
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(150, 20, 20),
		})
	end

	local plateFront = body("PlateFront", Vector3.new(M(0.52), M(0.11), 0.05), CFrame.new(0, chassisH / 2 + M(0.1), -L / 2 - M(0.13)), { Color = Color3.new(1, 1, 1) })
	plateGui(plateFront, plate)
	-- rear plate faces backwards
	local plateRear = body("PlateRear", Vector3.new(M(0.52), M(0.11), 0.05), CFrame.new(0, chassisH / 2 + M(0.1), L / 2 + M(0.13)) * CFrame.Angles(0, math.pi, 0), { Color = Color3.new(1, 1, 1) })
	plateGui(plateRear, plate)

	-- SEATS (left-hand drive) ---------------------------------------------------
	local seats: { BasePart } = {}
	local firstRowZ = -L / 2 + L * spec.CabinStart + M(0.55)
	if spec.Id == "bukhanka" then
		firstRowZ = -L / 2 + M(0.9) -- forward-control van: driver sits over the front axle
	end
	local rows: { number } = { 2 }
	local remaining = spec.Seats - 2
	while remaining > 0 do
		local take = if remaining == 3 then 3 else math.min(remaining, 2)
		table.insert(rows, take)
		remaining -= take
	end
	local seatY = chassisH / 2 + 0.2
	for r, count in rows do
		local z = firstRowZ + (r - 1) * M(0.85)
		for i = 1, count do
			local x = if count == 2 then (if i == 1 then -W / 4 else W / 4) else (i - 2) * W / 3
			local isDriver = r == 1 and i == 1
			local seat: BasePart
			if isDriver then
				local vs = Instance.new("VehicleSeat")
				vs.MaxSpeed = 0 -- legacy drive off: VehicleController drives the constraints
				vs.Torque = 0
				vs.TurnSpeed = 0
				vs.HeadsUpDisplay = false
				seat = vs
			else
				seat = Instance.new("Seat")
			end
			seat.Name = if isDriver then "DriverSeat" else ("Seat" .. #seats)
			seat.Size = Vector3.new(1.6, 0.4, 1.6)
			seat.CFrame = base * CFrame.new(x, seatY, z)
			seat.Transparency = 1
			seat.CanCollide = false
			seat.Anchored = true
			seat:SetAttribute("CarSeat", true)
			seat:SetAttribute("Driver", isDriver)
			seat.Parent = model
			table.insert(welded, seat)
			table.insert(seats, seat)
		end
	end

	-- WHEELS ----------------------------------------------------------------------
	local wheelY = R - chassisY -- wheel centre relative to the chassis centre
	local frontZ, rearZ = -L / 2 + M(0.8), L / 2 - M(0.75)
	local driven = 0
	local axles: { HingeConstraint } = {}
	local springs: { SpringConstraint } = {}
	local travel = M(0.1)
	local springLen = M(0.35)

	for _, w in {
		{ id = "FL", x = -1, z = frontZ, front = true },
		{ id = "FR", x = 1, z = frontZ, front = true },
		{ id = "RL", x = -1, z = rearZ, front = false },
		{ id = "RR", x = 1, z = rearZ, front = false },
	} do
		local pos = (base * CFrame.new(w.x * (W / 2 - wheelW * 0.3), wheelY, w.z)).Position
		local hingeFrame = CFrame.fromMatrix(pos, right, up)
		local upFrame = CFrame.fromMatrix(pos, up, right)
		local invisible = { Transparency = 1, CanCollide = false, Size = Vector3.new(0.4, 0.4, 0.4) }

		local strut = part(model, "Strut_" .. w.id, Vector3.new(0.4, 0.4, 0.4), CFrame.new(pos), invisible)
		local wheel = part(model, "Wheel_" .. w.id, Vector3.new(wheelW, 2 * R, 2 * R), hingeFrame, {
			Shape = Enum.PartType.Cylinder,
			Color = Color3.fromRGB(25, 25, 25),
			CustomPhysicalProperties = PhysicalProperties.new(0.9, 2, 0, 100, 1),
		})
		local hub = part(model, "Hub", Vector3.new(wheelW + 0.04, R, R), hingeFrame, {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(160, 160, 165),
			CanCollide = false,
			Massless = true,
		})
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = wheel
		hw.Part1 = hub
		hw.Parent = hub

		-- Axle (all wheels are motors: drive and/or brake)
		local axle = Instance.new("HingeConstraint")
		axle.Name = "Axle_" .. w.id
		axle.Attachment0 = attach(strut, hingeFrame, "AxleS")
		axle.Attachment1 = attach(wheel, hingeFrame, "AxleW")
		axle.ActuatorType = Enum.ActuatorType.Motor
		axle.MotorMaxTorque = 0
		axle.MotorMaxAcceleration = math.huge
		axle.AngularVelocity = 0
		local isDriven = spec.Drive == "AWD" or (spec.Drive == "FWD" and w.front) or (spec.Drive == "RWD" and not w.front)
		axle:SetAttribute("Driven", isDriven)
		if isDriven then
			driven += 1
		end
		axle.Parent = strut
		table.insert(axles, axle)

		-- Mount: chassis directly (rear) or a steering knuckle (front)
		local mount: BasePart = chassis
		if w.front then
			local knuckle = part(model, "Knuckle_" .. w.id, Vector3.new(0.4, 0.4, 0.4), CFrame.new(pos), invisible)
			local steer = Instance.new("HingeConstraint")
			steer.Name = "Steer_" .. w.id
			steer.Attachment0 = attach(chassis, upFrame, "SteerC")
			steer.Attachment1 = attach(knuckle, upFrame, "SteerK")
			steer.ActuatorType = Enum.ActuatorType.Servo
			steer.ServoMaxTorque = 1e6
			steer.AngularSpeed = 4
			steer.LimitsEnabled = true
			steer.LowerAngle = -cfg.MaxSteerAngle
			steer.UpperAngle = cfg.MaxSteerAngle
			steer.Parent = knuckle
			mount = knuckle
		end

		local slideA = attach(mount, upFrame, "SuspM")
		local slideB = attach(strut, upFrame, "SuspS")
		local slide = Instance.new("PrismaticConstraint")
		slide.Attachment0 = slideA
		slide.Attachment1 = slideB
		slide.LimitsEnabled = true
		slide.LowerLimit = -travel
		slide.UpperLimit = travel
		slide.Parent = strut

		local spring = Instance.new("SpringConstraint")
		spring.Attachment0 = attach(mount, upFrame + up * springLen, "SpringTop")
		spring.Attachment1 = slideB
		spring.Parent = strut
		table.insert(springs, spring)
	end

	-- Weld bodywork to the chassis, then tune springs and torque from the real mass.
	for _, p in welded do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = p
		weld.Parent = p
		p.Massless = true
	end

	local chassisMass = chassis:GetMass()
	local gravity = workspace.Gravity
	local perWheel = chassisMass * gravity / 4
	local compression = 0.25
	local stiffness = perWheel / compression
	for _, s in springs do
		s.FreeLength = springLen + compression
		s.Stiffness = stiffness
		s.Damping = 2 * math.sqrt(stiffness * chassisMass / 4) * 0.6
	end

	local loadedMass = chassisMass * 1.6 -- wheels, struts and a couple of passengers
	local driveTorque = loadedMass * M(spec.Acceleration) * R / math.max(driven, 1) * 1.3
	model:SetAttribute("TopSpeed", M(spec.TopSpeed))
	model:SetAttribute("WheelRadius", R)
	model:SetAttribute("DriveTorque", driveTorque)
	model:SetAttribute("BrakeTorque", driveTorque * 2.5)
	model:SetAttribute("MaxSteer", cfg.MaxSteerAngle)
	model:SetAttribute("Plate", plate)

	local engine: Sound? = nil
	if Config.Sounds.CarEngine ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Engine"
		s.SoundId = Config.Sounds.CarEngine
		s.Looped = true
		s.Volume = 0.5
		s.RollOffMaxDistance = 80
		s.Parent = chassis
		engine = s
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end

	return {
		Model = model,
		Chassis = chassis,
		DriverSeat = seats[1] :: VehicleSeat,
		Seats = seats,
		Lights = lights,
		LightParts = lightParts,
		Engine = engine,
		TopSpeed = M(spec.TopSpeed),
		Width = W,
	}
end

function CarFactory.SetLights(car: BuiltCar, on: boolean)
	for _, l in car.Lights do
		l.Enabled = on
	end
	for _, p in car.LightParts do
		p.Color = if on then HEADLIGHT_ON else HEADLIGHT_OFF
	end
end

return CarFactory
