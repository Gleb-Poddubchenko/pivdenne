--!strict
-- ElevatorService: Soviet-era passenger lifts.
--
-- MODEL CONTRACT — a Model tagged "Elevator" with attributes
--   ElevatorId  : string   unique, e.g. "b0142/2/lift"
--   Floors      : number   number of stops, numbered 1..Floors from the bottom
--   FloorHeight : number   studs between stops (2.8 m * 3.5 = 9.8)
--   optional: StallChance (number), RandomOutOfService (bool, default true),
--             OutOfService (bool; can be toggled live in Studio on the server)
-- children
--   Rail      (BasePart, anchored)  guide rail; the prismatic attachment goes here
--   Cabin     (Model) built AT FLOOR 1 with: Platform (floor part), Bounds (interior
--             volume), ButtonPanel, DoorL, DoorR (sliding panels, front = -Z), Lamp,
--             plus any decoration
--   Landings  (Folder) Landing_1..Landing_N, each with ShaftDoor (Model: Hinge +
--             door parts, swings outward), CallButton (BasePart), Indicator (BasePart, optional)
-- Every other part in the model counts as shaft structure.
--
-- PHYSICS: the cabin is an unanchored assembly driven by a server-owned
-- PrismaticConstraint servo. Because it really moves with physics velocity, the
-- Roblox character controller carries riders smoothly (an anchored part moved by
-- tweening teleports under their feet and makes them jitter or fall through).
-- Cabin and shaft are in separate collision groups, so tight clearances never jam.
--
-- STATE MACHINE (replicated as attribute "State"):
--   Idle -> MovingUp/MovingDown -> DoorsOpening -> DoorsOpen -> DoorsClosing -> ...
--   Stalled (stuck between floors), OutOfService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)

export type ElevatorState =
	"Idle"
	| "MovingUp"
	| "MovingDown"
	| "DoorsOpening"
	| "DoorsOpen"
	| "DoorsClosing"
	| "Stalled"
	| "OutOfService"

type Landing = {
	Floor: number,
	Hinge: BasePart,
	HingeClosed: CFrame,
	DoorParts: { BasePart },
	CallButton: BasePart,
	CallButtonColor: Color3,
	Indicator: TextLabel?,
}

type SlidingDoor = {
	Part: BasePart,
	Weld: Weld,
	Closed: CFrame,
	Open: CFrame,
}

type Elevator = {
	Id: string,
	Model: Model,
	Floors: number,
	FloorHeight: number,
	StallChance: number,
	Platform: BasePart,
	Bounds: BasePart,
	Prismatic: PrismaticConstraint,
	CabinDoors: { SlidingDoor },
	Landings: { [number]: Landing },
	State: ElevatorState,
	Floor: number,
	Direction: number, -- 1 up, -1 down, 0 none
	HallCalls: { [number]: boolean },
	CabinCalls: { [number]: boolean },
	DoorsAreOpen: boolean,
	HoldUntil: number,
	StopRequested: boolean,
	StallUntil: number,
	OutOfService: boolean,
	LastAlarm: number,
	Signal: BindableEvent,
}

local TAG = "Elevator"
local CABIN_GROUP = "ElevatorCabin"
local SHAFT_GROUP = "ElevatorShaft"
local CALL_LIT = Color3.fromRGB(255, 120, 30)

local ElevatorService = {}

local elevators: { [string]: Elevator } = {}
local panelLimiter = RateLimiter.new(6, 2)
local callLimiter = RateLimiter.new(4, 1)
local notifyEvent: RemoteEvent

-- HELPERS ---------------------------------------------------------------------

local function findPart(parent: Instance?, name: string): BasePart?
	local child = parent and parent:FindFirstChild(name)
	if child and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function offset(e: Elevator, floor: number): number
	return (floor - 1) * e.FloorHeight
end

local function isInside(e: Elevator, position: Vector3): boolean
	local p = e.Bounds.CFrame:PointToObjectSpace(position)
	local half = e.Bounds.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y + 1 and math.abs(p.Z) <= half.Z
end

local function riders(e: Elevator): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = Validation.GetRoot(player)
		if root and isInside(e, root.Position) then
			table.insert(list, player)
		end
	end
	return list
end

local function notify(player: Player, text: string, kind: string?)
	notifyEvent:FireClient(player, text, kind)
end

local function notifyRiders(e: Elevator, text: string, kind: string?)
	for _, player in riders(e) do
		notify(player, text, kind)
	end
end

local function updateIndicators(e: Elevator)
	local s = e.State
	local busy = s == "MovingUp" or s == "MovingDown" or s == "Stalled" or s == "DoorsOpening" or s == "DoorsClosing"
	for _, landing in e.Landings do
		local label = landing.Indicator
		if label then
			if e.OutOfService then
				label.Text = "НЕ ПРАЦЮЄ"
				label.TextColor3 = Color3.fromRGB(255, 60, 50)
			elseif busy then
				label.Text = "ЗАНЯТО"
				label.TextColor3 = Color3.fromRGB(255, 180, 60)
			else
				label.Text = ""
			end
		end
	end
end

local function setState(e: Elevator, state: ElevatorState)
	if e.State == state then
		return
	end
	e.State = state
	e.Model:SetAttribute("State", state)
	updateIndicators(e)
end

local function setFloor(e: Elevator, floor: number)
	if e.Floor ~= floor then
		e.Floor = floor
		e.Model:SetAttribute("Floor", floor)
	end
end

local function syncCalls(e: Elevator)
	local cabin = {}
	for f = 1, e.Floors do
		if e.CabinCalls[f] then
			table.insert(cabin, tostring(f))
		end
		local landing = e.Landings[f]
		if landing then
			local lit = e.HallCalls[f] == true
			landing.CallButton.Color = if lit then CALL_LIT else landing.CallButtonColor
			landing.CallButton.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	e.Model:SetAttribute("CabinRequests", table.concat(cabin, ","))
end

-- DOORS -----------------------------------------------------------------------

local function setCollide(parts: { BasePart }, collide: boolean)
	for _, part in parts do
		part.CanCollide = collide
	end
end

local function cabinDoorParts(e: Elevator): { BasePart }
	local parts = {}
	for _, d in e.CabinDoors do
		table.insert(parts, d.Part)
	end
	return parts
end

-- Moves both door sets; yields until done.
local function moveDoors(e: Elevator, open: boolean)
	local cfg = Config.Elevator
	local landing = e.Landings[e.Floor]
	local cabinParts = cabinDoorParts(e)

	setCollide(cabinParts, false)
	for _, d in e.CabinDoors do
		TweenService:Create(d.Weld, TweenInfo.new(cfg.CabinDoorTime, Enum.EasingStyle.Quad), {
			C0 = if open then d.Open else d.Closed,
		}):Play()
	end
	if landing then
		setCollide(landing.DoorParts, false)
		local goal = if open
			then landing.HingeClosed * CFrame.Angles(0, math.rad(cfg.ShaftDoorAngle), 0)
			else landing.HingeClosed
		TweenService:Create(landing.Hinge, TweenInfo.new(cfg.ShaftDoorTime, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
	end

	task.wait(math.max(cfg.CabinDoorTime, cfg.ShaftDoorTime))

	setCollide(cabinParts, true)
	if landing then
		setCollide(landing.DoorParts, true)
	end
	e.DoorsAreOpen = open
end

local function doorwayBlocked(e: Elevator): boolean
	local half = e.Bounds.Size / 2
	for _, player in Players:GetPlayers() do
		local root = Validation.GetRoot(player)
		if root then
			local p = e.Bounds.CFrame:PointToObjectSpace(root.Position)
			-- strip from just inside the cabin front to just outside the shaft door
			if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y + 1 and p.Z < -half.Z + 1.2 and p.Z > -half.Z - 2.5 then
				return true
			end
		end
	end
	return false
end

-- Opens at the current floor, waits, closes. Requests for this floor are served.
local function serveFloor(e: Elevator)
	local cfg = Config.Elevator
	e.HallCalls[e.Floor] = nil
	e.CabinCalls[e.Floor] = nil
	syncCalls(e)

	setState(e, "DoorsOpening")
	moveDoors(e, true)

	setState(e, "DoorsOpen")
	e.HoldUntil = os.clock() + cfg.DoorHoldTime
	local reversals = 0
	while true do
		-- 4 Hz only while the doors are open, so HoldUntil can be shortened or extended.
		while os.clock() < e.HoldUntil do
			task.wait(math.min(0.25, e.HoldUntil - os.clock()))
		end
		if doorwayBlocked(e) and reversals < cfg.MaxDoorReversals then
			reversals += 1
			e.HoldUntil = os.clock() + 1.5
		else
			break
		end
	end
	-- Calls for this floor that came in while open are already satisfied.
	e.HallCalls[e.Floor] = nil
	e.CabinCalls[e.Floor] = nil
	syncCalls(e)

	setState(e, "DoorsClosing")
	moveDoors(e, false)
end

-- TRAVEL ----------------------------------------------------------------------

local function stall(e: Elevator)
	local cfg = Config.Elevator
	local pr = e.Prismatic
	pr.TargetPosition = pr.CurrentPosition
	setState(e, "Stalled")
	e.StallUntil = os.clock() + cfg.StallMin + math.random() * (cfg.StallMax - cfg.StallMin)
	notifyRiders(e, "Ліфт застряг між поверхами! Натисніть «ВИКЛИК» на панелі.", "bad")
	while os.clock() < e.StallUntil and not e.OutOfService do
		task.wait(0.5)
	end
	notifyRiders(e, "Ліфт рушив далі.", nil)
end

local function nextFloorAhead(k: number, dir: number): number
	if dir > 0 then
		return math.floor(k + 0.01) + 2
	end
	return math.ceil(k - 0.01)
end

local function travel(e: Elevator, dest: number)
	local cfg = Config.Elevator
	local pr = e.Prismatic
	local dir = if dest > e.Floor then 1 else -1
	local target = dest
	e.Direction = dir
	e.StopRequested = false

	local function start()
		setState(e, if dir > 0 then "MovingUp" else "MovingDown")
		pr.Speed = cfg.Speed * cfg.StartJerkFactor -- the characteristic jolt
		pr.TargetPosition = offset(e, target)
		task.wait(cfg.StartJerkTime)
		pr.Speed = cfg.Speed
	end
	start()

	local travelTime = math.abs(dest - e.Floor) * e.FloorHeight / cfg.Speed
	local stallAt: number? = nil
	if math.random() < e.StallChance then
		stallAt = os.clock() + 0.6 + math.random() * math.max(travelTime - 1.5, 0.1)
	end
	local deadline = os.clock() + math.abs(dest - e.Floor) * cfg.MaxTravelTimePerFloor + 5

	-- 10 Hz only while this cabin is moving.
	while true do
		task.wait(0.1)
		local pos = pr.CurrentPosition
		local k = pos / e.FloorHeight
		setFloor(e, math.clamp(math.round(k) + 1, 1, e.Floors))

		local ahead = math.clamp(nextFloorAhead(k, dir), 1, e.Floors)
		local aheadDistance = math.abs(offset(e, ahead) - pos)
		if e.StopRequested then
			-- СТОП: stop at the next floor we can still brake for.
			e.StopRequested = false
			local stopAt = ahead
			if aheadDistance < cfg.MinStopDistance then
				stopAt = math.clamp(ahead + dir, 1, e.Floors)
			end
			if (stopAt - target) * dir < 0 then
				target = stopAt
				pr.TargetPosition = offset(e, target)
			end
		elseif
			(ahead - target) * dir < 0
			and (e.CabinCalls[ahead] or e.HallCalls[ahead])
			and aheadDistance >= cfg.MinStopDistance
		then
			-- Pick up a call on the way.
			target = ahead
			pr.TargetPosition = offset(e, target)
		end

		if stallAt and os.clock() >= stallAt and math.abs(offset(e, target) - pos) > cfg.MinStopDistance then
			stallAt = nil
			local t0 = os.clock()
			stall(e)
			deadline += os.clock() - t0
			start()
		end

		local remaining = math.abs(offset(e, target) - pr.CurrentPosition)
		if remaining < cfg.LevelingDistance then
			pr.Speed = cfg.Speed * cfg.LevelingSpeedFactor -- creep in to level with the floor
		end
		if remaining < 0.06 then
			break
		end
		if os.clock() > deadline then
			warn(("[Elevator] %s did not reach floor %d (blocked?)"):format(e.Id, target))
			break
		end
	end
	setFloor(e, target)
end

-- QUEUE ----------------------------------------------------------------------

-- Keep going in the current direction while there are calls ahead, otherwise
-- take the nearest call (classic elevator / SCAN algorithm).
local function chooseNext(e: Elevator): number?
	if e.HallCalls[e.Floor] or e.CabinCalls[e.Floor] then
		return e.Floor -- someone pressed the button where we already are: reopen
	end
	local bestAhead: number?, bestAheadDist = nil, math.huge
	local bestAny: number?, bestAnyDist = nil, math.huge
	for f = 1, e.Floors do
		if e.HallCalls[f] or e.CabinCalls[f] then
			local d = f - e.Floor
			if e.Direction ~= 0 and d * e.Direction > 0 and math.abs(d) < bestAheadDist then
				bestAhead, bestAheadDist = f, math.abs(d)
			end
			if math.abs(d) < bestAnyDist then
				bestAny, bestAnyDist = f, math.abs(d)
			end
		end
	end
	return bestAhead or bestAny
end

local function run(e: Elevator)
	while e.Model.Parent do
		if e.OutOfService then
			-- Broken lift waits with its doors open, so nobody is ever trapped inside.
			if not e.DoorsAreOpen then
				moveDoors(e, true)
			end
			setState(e, "OutOfService")
			e.Signal.Event:Wait()
			if not e.OutOfService and e.DoorsAreOpen then
				setState(e, "DoorsClosing")
				moveDoors(e, false)
			end
		else
			local target = chooseNext(e)
			if target == nil then
				e.Direction = 0
				setState(e, "Idle")
				e.Signal.Event:Wait()
			elseif target == e.Floor then
				serveFloor(e)
			else
				travel(e, target)
				serveFloor(e)
			end
		end
	end
end

-- REQUESTS --------------------------------------------------------------------

local function soviet(): boolean
	return Config.Elevator.Mode == "Soviet"
end

local function hallCall(e: Elevator, floor: number, player: Player)
	if e.OutOfService then
		notify(player, "Ліфт не працює. Доведеться пішки.", "bad")
		return
	end
	local here = e.Floor == floor
	if here and (e.State == "DoorsOpen" or e.State == "DoorsOpening") then
		e.HoldUntil = math.max(e.HoldUntil, os.clock() + Config.Elevator.DoorHoldTime)
		return
	end
	if soviet() and (e.State ~= "Idle" or #riders(e) > 0) then
		notify(player, "ЗАНЯТО — зачекайте, поки ліфт звільниться.", "bad")
		return
	end
	e.HallCalls[floor] = true
	syncCalls(e)
	e.Signal:Fire()
end

local function onPanel(player: Player, id: any, action: any, floor: any)
	if not panelLimiter.Check(player) or typeof(id) ~= "string" or typeof(action) ~= "string" then
		return
	end
	local e = elevators[id]
	if not e then
		return
	end
	local root = Validation.GetRoot(player)
	if not root or not isInside(e, root.Position) then
		return -- buttons can only be pressed from inside the cabin
	end
	local cfg = Config.Elevator

	if action == "floor" then
		if not Validation.IsInteger(floor, 1, e.Floors) or e.OutOfService then
			return
		end
		if floor == e.Floor and (e.State == "DoorsOpen" or e.State == "Idle" or e.State == "DoorsClosing") then
			e.CabinCalls[floor] = true -- re-open here
		elseif soviet() then
			if e.State ~= "Idle" and e.State ~= "DoorsOpen" then
				return -- old lifts ignore buttons while moving
			end
			table.clear(e.CabinCalls)
			e.CabinCalls[floor] = true
		else
			e.CabinCalls[floor] = true
		end
		if e.State == "DoorsOpen" and floor ~= e.Floor then
			e.HoldUntil = math.min(e.HoldUntil, os.clock() + cfg.DoorHoldAfterCommand)
		end
		syncCalls(e)
		e.Signal:Fire()
	elseif action == "stop" then
		if e.State == "MovingUp" or e.State == "MovingDown" then
			table.clear(e.CabinCalls)
			syncCalls(e)
			e.StopRequested = true
		end
	elseif action == "alarm" then
		local now = os.clock()
		if now - e.LastAlarm < cfg.AlarmCooldown then
			return
		end
		e.LastAlarm = now
		e.Model:SetAttribute("AlarmAt", now) -- clients ring the bell
		if e.State == "Stalled" then
			e.StallUntil = math.min(e.StallUntil, now + cfg.AlarmRescueTime)
			notifyRiders(e, "Диспетчер: «Чую вас. Зараз запустимо, тримайтеся!»", nil)
		else
			notifyRiders(e, "Диспетчер: «Що трапилося? Ліфт справний.»", nil)
		end
	end
end

-- SETUP -----------------------------------------------------------------------

local function setupCollisionGroups()
	for _, group in { CABIN_GROUP, SHAFT_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(CABIN_GROUP, SHAFT_GROUP, false)
end

local function makePrompt(parent: BasePart, action: string, actionText: string, objectText: string, distance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = action .. "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	return prompt
end

local function makeIndicator(part: BasePart): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(25, 20, 15)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = ""
	label.Parent = gui
	return label
end

local function prepareLanding(e: Elevator, floor: number, landingModel: Instance): boolean
	local shaftDoor = landingModel:FindFirstChild("ShaftDoor")
	local hinge = findPart(shaftDoor, "Hinge")
	local button = findPart(landingModel, "CallButton")
	if not (shaftDoor and hinge and button) then
		warn("[Elevator]", landingModel:GetFullName(), "needs ShaftDoor/Hinge and CallButton")
		return false
	end
	if landingModel:IsA("Model") then
		landingModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end

	hinge.Anchored = true
	hinge.CanCollide = false
	hinge.Transparency = 1
	local parts: { BasePart } = {}
	for _, d in shaftDoor:GetDescendants() do
		if d:IsA("BasePart") and d ~= hinge then
			if not d:FindFirstChild("DoorWeld") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "DoorWeld"
				weld.Part0 = hinge
				weld.Part1 = d
				weld.Parent = d
			end
			d.Anchored = false
			d.Massless = true
			table.insert(parts, d)
		end
	end

	local indicatorPart = findPart(landingModel, "Indicator")
	e.Landings[floor] = {
		Floor = floor,
		Hinge = hinge,
		HingeClosed = hinge.CFrame,
		DoorParts = parts,
		CallButton = button,
		CallButtonColor = button.Color,
		Indicator = if indicatorPart then makeIndicator(indicatorPart) else nil,
	}

	local prompt = makePrompt(button, "ElevatorCall", "Викликати ліфт", ("Ліфт · поверх %d"):format(floor), 7)
	prompt.Triggered:Connect(function(player: Player)
		if callLimiter.Check(player) and Validation.IsNear(player, button, Config.InteractDistance) then
			hallCall(e, floor, player)
		end
	end)
	return true
end

local function setOutOfService(e: Elevator, value: boolean)
	if e.OutOfService == value then
		return
	end
	e.OutOfService = value
	e.Model:SetAttribute("OutOfService", value)
	if value then
		table.clear(e.HallCalls)
		table.clear(e.CabinCalls)
		syncCalls(e)
	end
	updateIndicators(e)
	e.Signal:Fire()
end

local function prepare(inst: Instance)
	local path = inst:GetFullName()
	if not inst:IsA("Model") then
		return
	end
	local id = inst:GetAttribute("ElevatorId")
	local floors = inst:GetAttribute("Floors")
	local floorHeight = inst:GetAttribute("FloorHeight")
	if typeof(id) ~= "string" or not Validation.IsInteger(floors, 2, 40) or typeof(floorHeight) ~= "number" then
		warn("[Elevator] Needs ElevatorId, Floors (2-40) and FloorHeight attributes:", path)
		return
	end
	if elevators[id] then
		warn("[Elevator] Duplicate ElevatorId", id)
		return
	end

	local rail = findPart(inst, "Rail")
	local cabin = inst:FindFirstChild("Cabin")
	local platform = findPart(cabin, "Platform")
	local bounds = findPart(cabin, "Bounds")
	local panel = findPart(cabin, "ButtonPanel")
	local landingsFolder = inst:FindFirstChild("Landings")
	if not (rail and cabin and cabin:IsA("Model") and platform and bounds and panel and landingsFolder) then
		warn("[Elevator] Needs Rail, Cabin/{Platform,Bounds,ButtonPanel} and Landings:", path)
		return
	end

	-- Collision groups: everything outside the cabin is shaft.
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = if d:IsDescendantOf(cabin) then CABIN_GROUP else SHAFT_GROUP
		end
	end
	cabin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	bounds.Transparency = 1
	bounds.CanCollide = false
	bounds.CanQuery = false
	bounds.CanTouch = false

	-- Sliding cabin doors: Weld whose C0 is tweened.
	local cabinDoors: { SlidingDoor } = {}
	for _, name in { "DoorL", "DoorR" } do
		local part = findPart(cabin, name)
		if part then
			local weld = Instance.new("Weld")
			weld.Name = "SlideWeld"
			weld.Part0 = platform
			weld.Part1 = part
			weld.C0 = platform.CFrame:Inverse() * part.CFrame
			weld.Parent = part
			local side = if name == "DoorL" then -1 else 1
			table.insert(cabinDoors, {
				Part = part,
				Weld = weld,
				Closed = weld.C0,
				Open = CFrame.new(side * part.Size.X * 0.95, 0, 0) * weld.C0,
			})
		end
	end
	for _, d in cabin:GetDescendants() do
		if d:IsA("BasePart") and d ~= platform and d.Name ~= "DoorL" and d.Name ~= "DoorR" then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = platform
			weld.Part1 = d
			weld.Parent = d
		end
	end

	-- Prismatic servo along world up, zero at floor 1 (where the cabin was built).
	local axisFrame = CFrame.fromMatrix(platform.Position, Vector3.yAxis, Vector3.xAxis)
	local a0 = Instance.new("Attachment")
	a0.Name = "LiftRail"
	a0.Parent = rail
	a0.WorldCFrame = axisFrame
	local a1 = Instance.new("Attachment")
	a1.Name = "LiftCabin"
	a1.Parent = platform
	a1.WorldCFrame = axisFrame
	local prismatic = Instance.new("PrismaticConstraint")
	prismatic.Attachment0 = a0
	prismatic.Attachment1 = a1
	prismatic.ActuatorType = Enum.ActuatorType.Servo
	prismatic.ServoMaxForce = 1e7
	prismatic.Speed = Config.Elevator.Speed
	prismatic.TargetPosition = 0
	prismatic.LimitsEnabled = true
	prismatic.LowerLimit = -0.1
	prismatic.UpperLimit = (floors - 1) * floorHeight + 0.1
	prismatic.Parent = platform

	for _, d in cabin:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = d ~= platform
		end
	end
	pcall(function()
		platform:SetNetworkOwner(nil) -- server simulates the cabin, never a rider's client
	end)

	local stallChance = inst:GetAttribute("StallChance")
	local e: Elevator = {
		Id = id,
		Model = inst,
		Floors = floors,
		FloorHeight = floorHeight,
		StallChance = if typeof(stallChance) == "number" then stallChance else Config.Elevator.StallChance,
		Platform = platform,
		Bounds = bounds,
		Prismatic = prismatic,
		CabinDoors = cabinDoors,
		Landings = {},
		State = "Idle",
		Floor = 1,
		Direction = 0,
		HallCalls = {},
		CabinCalls = {},
		DoorsAreOpen = false,
		HoldUntil = 0,
		StopRequested = false,
		StallUntil = 0,
		OutOfService = false,
		LastAlarm = -math.huge,
		Signal = Instance.new("BindableEvent"),
	}

	for f = 1, floors do
		local landing = landingsFolder:FindFirstChild("Landing_" .. f)
		if not landing or not prepareLanding(e, f, landing) then
			warn("[Elevator]", id, "missing/invalid Landing_" .. f)
			return
		end
	end

	local panelPrompt = makePrompt(panel, "ElevatorPanel", "Кнопки", "Ліфт", 6)
	panelPrompt:SetAttribute("ElevatorId", id)
	panelPrompt:SetAttribute("Floors", floors)

	inst:SetAttribute("State", e.State)
	inst:SetAttribute("Floor", e.Floor)
	inst:SetAttribute("CabinRequests", "")
	elevators[id] = e
	-- Lifts inside instanced stairwells are destroyed and rebuilt: free the id and
	-- wake the controller loop so it exits.
	inst.Destroying:Once(function()
		if elevators[id] == e then
			elevators[id] = nil
		end
		task.defer(function()
			e.Signal:Fire() -- after destruction, so the loop sees Model.Parent == nil
		end)
	end)

	local startBroken = inst:GetAttribute("OutOfService") == true
		or (inst:GetAttribute("RandomOutOfService") ~= false and math.random() < Config.Elevator.OutOfServiceChance)
	if startBroken then
		setOutOfService(e, true)
	end
	-- Toggle live from Studio (server view) or from admin tools later.
	inst:GetAttributeChangedSignal("OutOfService"):Connect(function()
		setOutOfService(e, inst:GetAttribute("OutOfService") == true)
	end)

	task.spawn(run, e)
end

-- PUBLIC API ------------------------------------------------------------------

function ElevatorService.SetOutOfService(elevatorId: string, value: boolean)
	local e = elevators[elevatorId]
	if e then
		setOutOfService(e, value)
	end
end

function ElevatorService.GetState(elevatorId: string): ElevatorState?
	local e = elevators[elevatorId]
	return if e then e.State else nil
end

function ElevatorService.Init()
	notifyEvent = Net.Event("Notify")
	setupCollisionGroups()
	Net.Event("ElevatorPanel").OnServerEvent:Connect(onPanel)
	for _, inst in CollectionService:GetTagged(TAG) do
		task.spawn(prepare, inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(prepare)
end

return ElevatorService
